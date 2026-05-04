//! Session name resolution for the winui3 control plane.
//!
//! Extracted from control_plane.zig so the env-handling rules can be
//! unit-tested without dragging in apprt-internal imports
//! (D3D11RenderPass, termio, ...). The window title and the pipe name
//! both flow from this function's output, so getting the trim/fallback
//! rules wrong has user-visible consequences.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Resolve the session name for this ghostty instance.
///
/// Resolution order:
///   1. `GHOSTTY_SESSION_NAME` env var, trimmed of ASCII whitespace.
///      Empty after trim falls through to (2).
///   2. `ghostty-<pid>`.
///
/// Caller owns the returned slice.
pub fn loadSessionName(allocator: Allocator, pid: u32) ![]u8 {
    const env_name = std.process.getEnvVarOwned(allocator, "GHOSTTY_SESSION_NAME") catch null;
    if (env_name) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len == 0) {
            allocator.free(value);
        } else if (trimmed.ptr == value.ptr and trimmed.len == value.len) {
            return value;
        } else {
            const duped = try allocator.dupe(u8, trimmed);
            allocator.free(value);
            return duped;
        }
    }
    return std.fmt.allocPrint(allocator, "ghostty-{d}", .{pid});
}

// ── Tests ─────────────────────────────────────────────────────────
//
// The 4 branches of loadSessionName (env unset / whitespace-only /
// clean / needs-trim) each affect the window title and pipe name.
// Tests below mutate process env directly via Win32
// SetEnvironmentVariableA; each test snapshots and restores the prior
// value to stay hermetic.

const builtin = @import("builtin");

const k32_env = struct {
    extern "kernel32" fn SetEnvironmentVariableA(lpName: [*:0]const u8, lpValue: ?[*:0]const u8) callconv(.winapi) i32;
};

const EnvGuard = struct {
    name: [*:0]const u8,
    prior: ?[]u8,
    allocator: Allocator,

    fn capture(allocator: Allocator, comptime name: [:0]const u8) EnvGuard {
        const prior = std.process.getEnvVarOwned(allocator, name) catch null;
        return .{ .name = name.ptr, .prior = prior, .allocator = allocator };
    }

    fn set(self: *const EnvGuard, value: ?[:0]const u8) void {
        const ptr: ?[*:0]const u8 = if (value) |v| v.ptr else null;
        _ = k32_env.SetEnvironmentVariableA(self.name, ptr);
    }

    fn restore(self: *EnvGuard) void {
        if (self.prior) |p| {
            const z = self.allocator.dupeZ(u8, p) catch {
                self.allocator.free(p);
                return;
            };
            defer self.allocator.free(z);
            _ = k32_env.SetEnvironmentVariableA(self.name, z.ptr);
            self.allocator.free(p);
        } else {
            _ = k32_env.SetEnvironmentVariableA(self.name, null);
        }
    }
};

test "loadSessionName: env unset → falls back to ghostty-<pid>" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var guard = EnvGuard.capture(allocator, "GHOSTTY_SESSION_NAME");
    defer guard.restore();
    guard.set(null);

    const name = try loadSessionName(allocator, 4242);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("ghostty-4242", name);
}

test "loadSessionName: env set with clean value → returns as-is" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var guard = EnvGuard.capture(allocator, "GHOSTTY_SESSION_NAME");
    defer guard.restore();
    guard.set("custom-name");

    const name = try loadSessionName(allocator, 1);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("custom-name", name);
}

test "loadSessionName: env set with surrounding whitespace → trims" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var guard = EnvGuard.capture(allocator, "GHOSTTY_SESSION_NAME");
    defer guard.restore();
    guard.set("  spaced  ");

    const name = try loadSessionName(allocator, 1);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("spaced", name);
}

test "loadSessionName: env set to whitespace only → falls back to ghostty-<pid>" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var guard = EnvGuard.capture(allocator, "GHOSTTY_SESSION_NAME");
    defer guard.restore();
    guard.set("   \t\r\n   ");

    const name = try loadSessionName(allocator, 9999);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("ghostty-9999", name);
}

test "loadSessionName: env set to single space (trims to empty) → falls back" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var guard = EnvGuard.capture(allocator, "GHOSTTY_SESSION_NAME");
    defer guard.restore();
    // SetEnvironmentVariableA with empty string is equivalent to unset on Win32,
    // so use a single-space sentinel that gets trimmed to empty by loadSessionName.
    guard.set(" ");

    const name = try loadSessionName(allocator, 7);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("ghostty-7", name);
}
