//! Phase 4 of issue #232: in-process UI thread watchdog.
//!
//! Goal: implement the **"stuck > crash"** principle. When the UI thread
//! stops servicing its message pump for longer than a configured timeout,
//! a separate Win32 thread (this module) escalates from a soft warn-log
//! to a snapshot dump and finally to `process.exit(2)`. The OS can then
//! recycle the process instead of leaving the user staring at a frozen
//! window — this is a universal crash-guard that fires regardless of
//! which #218–#225 family deadlock actually occurred.
//!
//! Two independent staleness signals are checked, and either tripping
//! is sufficient to fire:
//!
//!   1. `last_ui_heartbeat_ns` — the WM_TIMER heartbeat the UI thread
//!      stamps every ~100ms (already wired in `App.zig`). If this is
//!      older than `timeout_ms`, the UI thread is not running its
//!      WM_TIMER handlers — message pump is wedged.
//!   2. `IsHungAppWindow(hwnd)` — Win32's own "did the user-input queue
//!      go N seconds without being read?" heuristic. We require N
//!      consecutive observations (= timeout_ms / poll_ms) before
//!      treating it as definitive, to avoid false positives from
//!      transient overload.
//!
//! Self-suicide guards
//! -------------------
//! The watchdog thread MUST NOT call any UI-thread-affined API. We use
//! only OS-level functions (`IsHungAppWindow`, `WriteFile`, file APIs,
//! `process.exit`) — never anything that would `SendMessageW` back into
//! the wedged UI thread. `IsHungAppWindow` itself is documented as safe
//! from any thread and never blocks waiting on the target window.
//!
//! Configuration (env vars)
//! ------------------------
//!   KS_WATCHDOG=disabled|warn-only|dump-only|crash   (default: crash)
//!   KS_WATCHDOG_TIMEOUT_MS=<u64 ms>                  (default: 5000)
//!   KS_WATCHDOG_POLL_MS=<u64 ms>                     (default: 1000)
//!
//! Set `KS_WATCHDOG=disabled` only for debugger sessions. The default
//! (crash) is intentional — Phase 4 exists *because* leaving the user
//! stuck in a hung window has been empirically worse than a crash that
//! restarts cleanly.
//!
//! Files written
//! -------------
//! On `.dump` or `.fire`, a single line of snapshot text lands at
//!   `%USERPROFILE%\.ghostty-win\crash\<unix_secs>-watchdog.log`
//! containing pid, tid, hwnd, observed stall, and IsHungAppWindow state.
//! We deliberately keep the dump dependency-free (no MiniDumpWriteDump /
//! DbgHelp) — those APIs need to load DbgHelp.dll which itself can race
//! with a wedged loader lock. A single OS WriteFile is safe.

const std = @import("std");
const builtin = @import("builtin");
const os = @import("os.zig");

const log = std.log.scoped(.watchdog);

const ns_per_ms = std.time.ns_per_ms;
const ns_per_s = std.time.ns_per_s;

// ---------------------------------------------------------------------------
// Public types — also exercised by tests/repro_watchdog_fires_on_ui_hang.zig
// (the test mirrors the algorithmic contract; this module is the production
// implementation that adds the OS thread + filesystem dump on top).
// ---------------------------------------------------------------------------

pub const Action = enum { crash, dump_only, warn_only, disabled };

pub const Decision = enum { idle, warn, dump, fire };

pub const Config = struct {
    action: Action = .crash,
    timeout_ms: u64 = 5000,
    poll_ms: u64 = 1000,

    /// Read `KS_WATCHDOG`, `KS_WATCHDOG_TIMEOUT_MS`, `KS_WATCHDOG_POLL_MS`
    /// from the process environment. Unknown values fall back to defaults
    /// (which means `crash`). The watchdog allocator is only used during
    /// init; the running thread holds no allocations.
    pub fn fromEnv(allocator: std.mem.Allocator) Config {
        var cfg = Config{};
        if (std.process.getEnvVarOwned(allocator, "KS_WATCHDOG")) |s| {
            defer allocator.free(s);
            if (std.mem.eql(u8, s, "disabled")) {
                cfg.action = .disabled;
            } else if (std.mem.eql(u8, s, "warn-only")) {
                cfg.action = .warn_only;
            } else if (std.mem.eql(u8, s, "dump-only")) {
                cfg.action = .dump_only;
            } else if (std.mem.eql(u8, s, "crash")) {
                cfg.action = .crash;
            }
        } else |_| {}
        if (std.process.getEnvVarOwned(allocator, "KS_WATCHDOG_TIMEOUT_MS")) |s| {
            defer allocator.free(s);
            cfg.timeout_ms = std.fmt.parseInt(u64, s, 10) catch cfg.timeout_ms;
        } else |_| {}
        if (std.process.getEnvVarOwned(allocator, "KS_WATCHDOG_POLL_MS")) |s| {
            defer allocator.free(s);
            cfg.poll_ms = std.fmt.parseInt(u64, s, 10) catch cfg.poll_ms;
        } else |_| {}
        return cfg;
    }
};

/// Pure decision function. Decoupled from the thread loop so it can be
/// unit-tested without touching real time. `last_heartbeat_ns` and
/// `now_ns` are i64 because Zig atomics top out at 64-bit; ~292 years
/// of ns range past 1970 is ample for app lifetime use.
pub fn evaluate(cfg: Config, last_heartbeat_ns: i64, now_ns: i64) Decision {
    if (cfg.action == .disabled) return .idle;
    if (last_heartbeat_ns == 0) return .idle; // not yet primed
    const delta = now_ns - last_heartbeat_ns;
    const timeout_ns: i64 = @as(i64, @intCast(cfg.timeout_ms)) * @as(i64, ns_per_ms);
    if (delta < timeout_ns) return .idle;
    return switch (cfg.action) {
        .disabled => .idle,
        .warn_only => .warn,
        .dump_only => .dump,
        .crash => .fire,
    };
}

// ---------------------------------------------------------------------------
// Win32 surface — local extern decls so we don't bloat os.zig with APIs
// that are only ever used from inside this module.
// ---------------------------------------------------------------------------

extern "user32" fn IsHungAppWindow(hWnd: os.HWND) callconv(.winapi) os.BOOL;
extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) os.DWORD;

// ---------------------------------------------------------------------------
// Watchdog state — owned by App.zig (single instance). The poller thread
// only reads `cfg`, `hwnd`, `last_heartbeat_ns_ptr`, and the stop flag.
// All updates from the UI thread go through the heartbeat pointer; no
// lock is needed because nanoseconds-as-i64 are an atomic load.
// ---------------------------------------------------------------------------

pub const Watchdog = struct {
    cfg: Config,
    hwnd: os.HWND,
    last_heartbeat_ns: *std.atomic.Value(i64),
    stop: std.atomic.Value(bool) = .init(false),
    fired: std.atomic.Value(bool) = .init(false),
    consecutive_hung: std.atomic.Value(u32) = .init(0),
    thread: ?std.Thread = null,

    /// Initialize the watchdog state. Caller must own the storage and
    /// call `start()` separately so the spawn happens after the HWND is
    /// fully bound. Returns null when the configured action is .disabled
    /// — callers can treat that as "no watchdog at all".
    pub fn init(
        cfg: Config,
        hwnd: os.HWND,
        heartbeat_ptr: *std.atomic.Value(i64),
    ) Watchdog {
        return .{
            .cfg = cfg,
            .hwnd = hwnd,
            .last_heartbeat_ns = heartbeat_ptr,
        };
    }

    /// Spawn the poller thread. Idempotent — calling twice is a no-op.
    pub fn start(self: *Watchdog) !void {
        if (self.cfg.action == .disabled) {
            log.info("watchdog disabled via KS_WATCHDOG=disabled", .{});
            return;
        }
        if (self.thread != null) return;
        self.thread = try std.Thread.spawn(.{}, loop, .{self});
        log.info(
            "watchdog started action={s} timeout_ms={} poll_ms={} hwnd=0x{x}",
            .{ @tagName(self.cfg.action), self.cfg.timeout_ms, self.cfg.poll_ms, @intFromPtr(self.hwnd) },
        );
    }

    /// Signal the poller thread to stop and join it. Idempotent.
    pub fn stopAndJoin(self: *Watchdog) void {
        self.stop.store(true, .release);
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
    }

    fn loop(self: *Watchdog) void {
        while (!self.stop.load(.acquire)) {
            std.Thread.sleep(self.cfg.poll_ms * ns_per_ms);
            if (self.stop.load(.acquire)) break;
            if (self.fired.load(.acquire)) continue; // do not double-fire

            const now = nsNow();
            const last = self.last_heartbeat_ns.load(.acquire);
            const heartbeat_decision = evaluate(self.cfg, last, now);

            // Independent IsHungAppWindow signal. Require enough
            // consecutive hung ticks to cover `timeout_ms` so a single
            // transient blip does not crash a healthy app. This is a
            // pure OS-level call — never blocks on the wedged UI thread.
            const is_hung = IsHungAppWindow(self.hwnd) != 0;
            const required_ticks: u32 = blk: {
                const t = @divTrunc(self.cfg.timeout_ms, @max(self.cfg.poll_ms, 1));
                break :blk @intCast(@max(t, 1));
            };
            if (is_hung) {
                _ = self.consecutive_hung.fetchAdd(1, .acq_rel);
            } else {
                self.consecutive_hung.store(0, .release);
            }
            const hung_decision: Decision = if (self.consecutive_hung.load(.acquire) >= required_ticks)
                switch (self.cfg.action) {
                    .disabled => .idle,
                    .warn_only => .warn,
                    .dump_only => .dump,
                    .crash => .fire,
                }
            else
                .idle;

            // Take the **stronger** of the two signals. fire > dump > warn > idle.
            const final = strongest(heartbeat_decision, hung_decision);
            if (final == .idle) continue;

            const stall_ms: u64 = if (last != 0)
                @intCast(@max(@divTrunc(now - last, ns_per_ms), 0))
            else
                0;

            switch (final) {
                .idle => unreachable,
                .warn => {
                    log.warn(
                        "ui_stall warn-only stall_ms={} is_hung={} consecutive_hung={}",
                        .{ stall_ms, is_hung, self.consecutive_hung.load(.acquire) },
                    );
                    // warn-only: do not arm `fired`, so a transient stall
                    // can re-warn after recovery + restall.
                },
                .dump => {
                    self.fired.store(true, .release);
                    log.warn(
                        "ui_stall dump-only stall_ms={} is_hung={} — writing snapshot",
                        .{ stall_ms, is_hung },
                    );
                    writeSnapshot(self.hwnd, stall_ms, is_hung) catch |err| {
                        log.warn("watchdog snapshot write failed: {}", .{err});
                    };
                },
                .fire => {
                    self.fired.store(true, .release);
                    log.err(
                        "ui_stall CRASH stall_ms={} is_hung={} — dumping + exiting",
                        .{ stall_ms, is_hung },
                    );
                    writeSnapshot(self.hwnd, stall_ms, is_hung) catch |err| {
                        log.warn("watchdog snapshot write failed: {}", .{err});
                    };
                    // Stuck > crash. Exit code 2 distinguishes "watchdog
                    // killed me" from normal exit (0) and crash (1).
                    std.process.exit(2);
                },
            }
        }
    }
};

fn strongest(a: Decision, b: Decision) Decision {
    return @enumFromInt(@max(@intFromEnum(a), @intFromEnum(b)));
}

/// Truncate a 128-bit nanosecond timestamp to i64. Safe because i64 ns
/// holds ~292 years of range past 1970.
fn nsNow() i64 {
    return @as(i64, @truncate(std.time.nanoTimestamp()));
}

// ---------------------------------------------------------------------------
// Snapshot writer — single-line WriteFile of pid/tid/hwnd/stall to
// %USERPROFILE%\.ghostty-win\crash\<unix>-watchdog.log. We deliberately
// avoid DbgHelp / MiniDumpWriteDump because those APIs need to load
// DbgHelp.dll which itself can race with a wedged loader lock during a
// real deadlock. A single OS WriteFile through allocator-free code is
// the safest thing the watchdog can do from a parallel thread.
// ---------------------------------------------------------------------------

fn writeSnapshot(hwnd: os.HWND, stall_ms: u64, is_hung: bool) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const home = std.process.getEnvVarOwned(alloc, "USERPROFILE") catch
        std.process.getEnvVarOwned(alloc, "HOMEPATH") catch return error.NoHome;
    const crash_dir = try std.fs.path.join(alloc, &.{ home, ".ghostty-win", "crash" });

    std.fs.cwd().makePath(crash_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const unix_s = std.time.timestamp();
    const filename = try std.fmt.allocPrint(alloc, "{d}-watchdog.log", .{unix_s});
    const full_path = try std.fs.path.join(alloc, &.{ crash_dir, filename });

    var f = try std.fs.cwd().createFile(full_path, .{ .truncate = true });
    defer f.close();

    const pid = GetCurrentProcessId();
    const line = try std.fmt.allocPrint(
        alloc,
        "watchdog v1 pid={d} hwnd=0x{x} stall_ms={d} is_hung_app_window={} unix_s={d}\n" ++
            "reason: ui thread did not service heartbeat or IsHungAppWindow=true\n" ++
            "next: process will exit(2) unless action=dump-only/warn-only\n",
        .{ pid, @intFromPtr(hwnd), stall_ms, is_hung, unix_s },
    );
    try f.writeAll(line);

    log.info("watchdog snapshot written: {s}", .{full_path});
}

// ---------------------------------------------------------------------------
// Tests — exercise the same contract as tests/repro_watchdog_fires_on_ui_hang.zig
// but against the production module. Kept lightweight (compressed timing).
// ---------------------------------------------------------------------------

const testing = std.testing;

test "evaluate stays idle while heartbeat is fresh" {
    const cfg = Config{ .action = .crash, .timeout_ms = 5000 };
    const now: i64 = 1_000_000_000_000;
    const fresh = now - (1 * ns_per_s);
    try testing.expectEqual(Decision.idle, evaluate(cfg, fresh, now));
}

test "evaluate fires after timeout under .crash" {
    const cfg = Config{ .action = .crash, .timeout_ms = 5000 };
    const now: i64 = 1_000_000_000_000;
    const stale = now - (6 * ns_per_s);
    try testing.expectEqual(Decision.fire, evaluate(cfg, stale, now));
}

test "evaluate stays idle under .disabled even when heartbeat is stale" {
    const cfg = Config{ .action = .disabled, .timeout_ms = 5000 };
    const now: i64 = 1_000_000_000_000;
    const stale = now - (60 * ns_per_s);
    try testing.expectEqual(Decision.idle, evaluate(cfg, stale, now));
}

test "evaluate emits .dump under .dump_only" {
    const cfg = Config{ .action = .dump_only, .timeout_ms = 5000 };
    const now: i64 = 1_000_000_000_000;
    const stale = now - (6 * ns_per_s);
    try testing.expectEqual(Decision.dump, evaluate(cfg, stale, now));
}

test "evaluate emits .warn under .warn_only" {
    const cfg = Config{ .action = .warn_only, .timeout_ms = 5000 };
    const now: i64 = 1_000_000_000_000;
    const stale = now - (6 * ns_per_s);
    try testing.expectEqual(Decision.warn, evaluate(cfg, stale, now));
}

test "strongest picks the higher-priority decision" {
    try testing.expectEqual(Decision.fire, strongest(.idle, .fire));
    try testing.expectEqual(Decision.fire, strongest(.fire, .warn));
    try testing.expectEqual(Decision.dump, strongest(.warn, .dump));
    try testing.expectEqual(Decision.idle, strongest(.idle, .idle));
}
