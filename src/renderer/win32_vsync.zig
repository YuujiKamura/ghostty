const std = @import("std");
const builtin = @import("builtin");
const xev = @import("xev");

const log = std.log.scoped(.win32_vsync);

/// Win32 VSync using DwmFlush() to synchronize with the desktop compositor's
/// vertical blank, equivalent to macOS CVDisplayLink.
///
/// Returns `void` when the graphics API handles its own VSync (e.g. D3D11 via
/// DXGI Present) or on non-Windows platforms.
pub fn For(comptime GraphicsAPI: type) type {
    if (@hasDecl(GraphicsAPI, "needs_vsync_thread") and !GraphicsAPI.needs_vsync_thread) return void;
    return switch (builtin.os.tag) {
        .windows => Win32VSync,
        else => void,
    };
}

pub const Win32VSync = struct {
    thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = .{ .raw = false },
    paused: std.atomic.Value(bool) = .{ .raw = false },
    draw_now: ?*xev.Async = null,

    const Self = @This();

    /// Sleep duration (ms) while paused — balances CPU usage vs resume latency.
    /// 16ms ≈ one frame at 60fps. 100ms caused visible stutter when the window
    /// goes to background after being focused (Issue #116 regression).
    const PAUSE_SLEEP_MS: u32 = 16;

    /// Spawn the VSync thread that calls DwmFlush() in a loop.
    pub fn start(self: *Self, draw_now: *xev.Async) void {
        self.draw_now = draw_now;
        self.running.store(true, .release);
        self.thread = std.Thread.spawn(.{}, threadFn, .{self}) catch |err| {
            log.err("failed to spawn Win32 VSync thread: {}", .{err});
            return;
        };
        log.info("Win32 DwmFlush VSync thread started", .{});
    }

    /// Signal the thread to stop and join it.
    pub fn stop(self: *Self) void {
        self.running.store(false, .release);
        if (self.thread) |thread| {
            thread.join();
        }
        self.thread = null;
        self.draw_now = null;
    }

    /// Set the paused state of the VSync thread. When paused, the thread
    /// sleeps instead of calling DwmFlush().
    pub fn setPaused(self: *Self, p: bool) void {
        self.paused.store(p, .release);
    }

    /// Returns true if the VSync thread is running and not paused.
    pub fn isRunning(self: *const Self) bool {
        return self.running.load(.acquire) and !self.paused.load(.acquire);
    }

    /// Thread function. Calls DwmFlush() to block until the compositor's
    /// next vertical blank, then notifies draw_now.
    fn threadFn(self: *Self) void {
        const win32_api = struct {
            extern "dwmapi" fn DwmFlush() callconv(.winapi) c_long;
            extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;
        };

        while (self.running.load(.acquire)) {
            if (self.paused.load(.acquire)) {
                win32_api.Sleep(PAUSE_SLEEP_MS);
                continue;
            }

            _ = win32_api.DwmFlush();

            if (self.draw_now) |draw_now| {
                draw_now.notify() catch |err| {
                    log.err("error notifying draw_now from Win32 VSync err={}", .{err});
                };
            }
        }
    }
};
