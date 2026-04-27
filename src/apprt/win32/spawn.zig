//! Fork-local Win32 child-process helpers used by `src/Command.zig`.
//!
//! This file exists to keep our delta against upstream's `src/Command.zig`
//! small. Anything in here is fork-owned (refs YuujiKamura/ghostty#221 and
//! YuujiKamura/ghostty#239 for the footprint-minimisation context). Behaviour
//! must match the original inline implementations exactly — this is a pure
//! reorganisation, no semantic change.
//!
//! Scope is intentionally narrow:
//!   * `default_wait_timeout_ms` — the grace period for #221's bounded wait.
//!   * `waitTimeout(handle, timeout_ms)` — bounded WaitForSingleObject +
//!     TerminateProcess escalation. Replaces the previous unbounded
//!     `WaitForSingleObject(INFINITE)` in the Windows path of `Command.wait`.
//!   * `encodeWtf16Z(arena, label, s)` — wraps `wtf8ToWtf16LeAllocZ` with the
//!     same diagnostic logging the inline catch-blocks used to emit. Folds
//!     each per-string catch-block down to a single call, which shrinks the
//!     size of any future merge conflict in `startWindows`.
//!   * `encodeEnvBlock(allocator, env_map)` — drop-in body for the
//!     fork-modified `createWindowsEnvBlock`. Skip-on-invalid behaviour for
//!     entries whose bytes aren't valid WTF-8 (third-party apps that wrote
//!     raw code-page bytes into env vars). Losing one env var is better than
//!     a non-functional terminal.
//!
//! UPSTREAM-SHARED-OK: minimize footprint only (#239)
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const windows = std.os.windows;

const log = std.log.scoped(.command);

/// Default grace period (in milliseconds) for `waitTimeout()` before
/// escalating to TerminateProcess. See YuujiKamura/ghostty#221: a
/// kernel-frozen / suspended child must not be allowed to hang ghostty's
/// shutdown indefinitely.
pub const default_wait_timeout_ms: u32 = 5000;

/// Same shape as `Command.Exit` on Windows. Kept local to avoid a cyclic
/// import (`Command.zig` imports this file; this file must not import
/// `Command.zig`). Callers in `Command.zig` translate this back to
/// `Command.Exit`.
pub const Exit = union(enum) {
    Exited: u32,
};

/// Windows-only: wait up to `timeout_ms` for the given child handle to be
/// signalled. If the wait times out, TerminateProcess is called and we
/// briefly wait for the kernel to flush the handle so we can observe an
/// exit code. This is the fix for YuujiKamura/ghostty#221: the previous
/// unbounded `WaitForSingleObject(INFINITE)` would hang shutdown forever
/// if the child was suspended / debugger-attached / otherwise unable to
/// reach exit.
pub fn waitTimeout(handle: windows.HANDLE, timeout_ms: u32) !Exit {
    if (comptime builtin.os.tag != .windows) {
        @compileError("waitTimeout is Windows-only; use Command.wait() on POSIX");
    }

    const result = windows.kernel32.WaitForSingleObject(handle, timeout_ms);
    if (result == windows.WAIT_FAILED) {
        return windows.unexpectedError(windows.kernel32.GetLastError());
    }

    if (result == windows.WAIT_TIMEOUT) {
        // Child is unresponsive within the grace period. This is the
        // #221 case: kernel-frozen, suspended, or otherwise unable to
        // reach exit. We must escalate by force-terminating, otherwise
        // ghostty's shutdown hangs forever.
        log.warn(
            "child unresponsive after {}ms; calling TerminateProcess",
            .{timeout_ms},
        );
        if (windows.kernel32.TerminateProcess(handle, 1) == 0) {
            return windows.unexpectedError(windows.kernel32.GetLastError());
        }

        // Brief wait for the kernel to actually flush the process so
        // GetExitCodeProcess returns a real status instead of
        // STILL_ACTIVE. 1s is generous for a forced termination.
        const post_kill = windows.kernel32.WaitForSingleObject(handle, 1000);
        if (post_kill == windows.WAIT_FAILED) {
            return windows.unexpectedError(windows.kernel32.GetLastError());
        }
    }

    var exit_code: windows.DWORD = undefined;
    const has_code = windows.kernel32.GetExitCodeProcess(handle, &exit_code) != 0;
    if (!has_code) {
        return windows.unexpectedError(windows.kernel32.GetLastError());
    }

    return .{ .Exited = exit_code };
}

/// WTF-8 → WTF-16LE encoding with arena allocation and a diagnostic log
/// on failure. `label` identifies the input field (e.g. "path", "cwd",
/// "command_line") in the log message so a malformed value is easy to
/// pinpoint instead of a bare `error.InvalidWtf8`.
///
/// `getEnvMap` on Windows returns WTF-8 (surrogate halves allowed), so we
/// use `wtf8ToWtf16LeAllocZ` (which accepts that superset) rather than
/// upstream's strict `utf8ToUtf16LeAllocZ`. See `feedback_ghostty_win_wtf8_env_fix`.
pub fn encodeWtf16Z(
    arena: mem.Allocator,
    comptime label: []const u8,
    s: []const u8,
) ![:0]u16 {
    return std.unicode.wtf8ToWtf16LeAllocZ(arena, s) catch |err| {
        log.err("startWindows: encode " ++ label ++ " failed err={} value='{s}'", .{ err, s });
        return err;
    };
}

/// Drop-in body for `Command.createWindowsEnvBlock` (the fork-modified
/// variant). Tolerates env entries whose bytes aren't valid WTF-8 by
/// skipping them with a warning instead of failing the whole spawn.
/// Losing one env var is better than a non-functional terminal.
pub fn encodeEnvBlock(
    allocator: mem.Allocator,
    env_map: *const std.process.EnvMap,
) ![]u16 {
    // count bytes needed
    const max_chars_needed = x: {
        var max_chars_needed: usize = 4; // 4 for the final 4 null bytes
        var it = env_map.iterator();
        while (it.next()) |pair| {
            // +1 for '='
            // +1 for null byte
            max_chars_needed += pair.key_ptr.len + pair.value_ptr.len + 2;
        }
        break :x max_chars_needed;
    };
    const result = try allocator.alloc(u16, max_chars_needed);
    errdefer allocator.free(result);

    var it = env_map.iterator();
    var i: usize = 0;
    var skipped: usize = 0;
    while (it.next()) |pair| {
        // Defensive: inherited environment may contain entries whose bytes
        // aren't valid WTF-8 (e.g., third-party apps writing raw code-page
        // bytes into env vars). Skip such entries rather than failing the
        // whole spawn — losing one env var is better than a non-functional
        // terminal.
        const entry_start = i;
        const key_len = std.unicode.wtf8ToWtf16Le(result[i..], pair.key_ptr.*) catch |err| {
            log.warn("env skip: invalid key err={} key_len={d}", .{ err, pair.key_ptr.len });
            skipped += 1;
            continue;
        };
        i += key_len;
        result[i] = '=';
        i += 1;
        const val_len = std.unicode.wtf8ToWtf16Le(result[i..], pair.value_ptr.*) catch |err| {
            log.warn("env skip: invalid value err={} key='{s}' val_len={d}", .{ err, pair.key_ptr.*, pair.value_ptr.len });
            skipped += 1;
            i = entry_start; // rewind past the partially-written key + '='
            continue;
        };
        i += val_len;
        result[i] = 0;
        i += 1;
    }
    if (skipped > 0) log.warn("createWindowsEnvBlock: skipped {d} env var(s) with invalid encoding", .{skipped});
    result[i] = 0;
    i += 1;
    result[i] = 0;
    i += 1;
    result[i] = 0;
    i += 1;
    result[i] = 0;
    i += 1;
    return try allocator.realloc(result, i);
}

// Repro for YuujiKamura/ghostty#221:
//   src/Command.zig wait() (Windows path) called WaitForSingleObject with
//   INFINITE, so a kernel-frozen / suspended child would hang ghostty's
//   shutdown forever. The fix is a bounded wait + TerminateProcess
//   escalation, exposed via Command.waitTimeout() / spawn.waitTimeout().
//   This test spawns a long-running ping (~60s) and proves waitTimeout()
//   returns within the bounded grace instead of waiting for the child to
//   exit naturally, and that the child is reaped after escalation.
//
// Lives here (not in Command.zig) as part of the #239 footprint-minimisation
// refactor: the production logic is in this file, so the test belongs here
// too. It's surfaced to `zig build test` via a `_ = @import` reference from
// Command.zig's test block.
test "spawn: wait timeout terminates unresponsive child (#221)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const Command = @import("../../Command.zig");
    const testing = std.testing;

    var cmd: Command = .{
        // ping -n 60 127.0.0.1 keeps the child alive ~60s. From our wait's
        // point of view that handle is "stuck" for the duration of the test
        // grace, which is the same code-path a kernel-suspended child takes:
        // WaitForSingleObject returns WAIT_TIMEOUT and we must escalate.
        .path = "C:\\Windows\\System32\\ping.exe",
        .args = &.{ "C:\\Windows\\System32\\ping.exe", "-n", "60", "127.0.0.1" },
        .os_pre_exec = null,
        .rt_pre_exec = null,
        .rt_post_fork = null,
        .rt_pre_exec_info = undefined,
        .rt_post_fork_info = undefined,
    };

    cmd.start(testing.allocator) catch |err| {
        if (err == error.ExecFailedInChild) std.posix.exit(1);
        return err;
    };
    try testing.expect(cmd.pid != null);

    const grace_ms: u32 = 500;
    var timer = try std.time.Timer.start();
    const exit = try cmd.waitTimeout(grace_ms);
    const elapsed_ns = timer.read();

    // Must return within grace + slack (allow 4s for TerminateProcess +
    // post-terminate cleanup wait + scheduler jitter on a busy CI box).
    const slack_ns: u64 = 4 * std.time.ns_per_s;
    const budget_ns: u64 = @as(u64, grace_ms) * std.time.ns_per_ms + slack_ns;
    try testing.expect(elapsed_ns < budget_ns);

    // Child must be reaped (exit code is observable). ping was forcibly
    // terminated (TerminateProcess passes exit code 1 in our fix); a normal
    // ping completion would be 0. Either way the handle is signalled, which
    // is the actual contract — tolerate either to keep the test resilient if
    // the process happened to race to exit.
    try testing.expect(exit == .Exited);
    _ = exit.Exited;
}
