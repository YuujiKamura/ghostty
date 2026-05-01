//! UPSTREAM-SHARED-OK: fork-only file in upstream-shared dir; abstracts
//! platform-specific VSync (Win32 DwmFlush thread, macOS CVDisplayLink) so
//! the generic renderer doesn't carry platform branches.
//!
//! Unified VSync provider for the generic renderer.
//!
//! Wraps platform-specific VSync mechanisms (macOS CVDisplayLink,
//! Windows DwmFlush thread) behind a common interface so that
//! the generic renderer doesn't need platform-specific branches.

const std = @import("std");
const builtin = @import("builtin");
const xev = @import("xev");
const win32_vsync_mod = @import("win32_vsync.zig");

const log = std.log.scoped(.vsync);

const macos = switch (builtin.os.tag) {
    .macos => @import("macos"),
    else => void,
};

const DisplayLink = switch (builtin.os.tag) {
    .macos => *macos.video.DisplayLink,
    else => void,
};

pub fn Provider(comptime GraphicsAPI: type) type {
    const Win32VSync = win32_vsync_mod.For(GraphicsAPI);

    return struct {
        const Self = @This();

        display_link: if (DisplayLink != void) ?DisplayLink else void = if (DisplayLink != void) null else {},
        win32: if (Win32VSync != void) Win32VSync else void = if (Win32VSync != void) .{} else {},

        /// Initialize the VSync provider, creating a display link if on macOS
        /// and vsync is enabled.
        pub fn init(vsync_enabled: bool) !Self {
            var self: Self = .{};
            if (comptime DisplayLink != void) {
                self.display_link = if (vsync_enabled)
                    try macos.video.DisplayLink.createWithActiveCGDisplays()
                else
                    null;
            }
            return self;
        }

        /// Start the VSync provider. Called from loopEnter.
        pub fn start(self: *Self, draw_now: *xev.Async) !void {
            if (comptime DisplayLink != void) {
                const dl = self.display_link orelse return;
                try dl.setOutputCallback(xev.Async, &displayLinkCallback, draw_now);
                dl.start() catch {};
                return;
            }
            if (comptime Win32VSync != void) {
                self.win32.start(draw_now);
            }
        }

        /// Stop the VSync provider. Called from loopExit.
        pub fn stop(self: *Self) void {
            if (comptime DisplayLink != void) {
                const dl = self.display_link orelse return;
                dl.stop() catch {};
                return;
            }
            if (comptime Win32VSync != void) {
                self.win32.stop();
            }
        }

        /// Release resources. Called from deinit.
        pub fn deinit(self: *Self) void {
            if (comptime DisplayLink != void) {
                if (self.display_link) |dl| {
                    dl.stop() catch {};
                    dl.release();
                }
            }
            if (comptime Win32VSync != void) {
                self.win32.stop();
            }
        }

        /// Pause or resume based on focus state.
        pub fn setFocusPaused(self: *Self, focus: bool) void {
            if (comptime DisplayLink != void) link: {
                const dl = self.display_link orelse break :link;
                if (focus) {
                    dl.start() catch {};
                } else {
                    dl.stop() catch {};
                }
            }
            if (comptime Win32VSync != void) {
                self.win32.setPaused(!focus);
            }
        }

        /// Pause or resume based on visibility and focus.
        pub fn setVisibilityPaused(self: *Self, visible: bool, focused: bool) void {
            if (comptime DisplayLink != void) link: {
                const dl = self.display_link orelse break :link;
                if (visible and focused) {
                    dl.start() catch {};
                } else {
                    dl.stop() catch {};
                }
            }
            if (comptime Win32VSync != void) {
                self.win32.setPaused(!(visible and focused));
            }
        }

        /// Returns true if VSync is active and not paused.
        pub fn isRunning(self: *const Self) bool {
            if (comptime Win32VSync != void) {
                return self.win32.isRunning();
            }
            if (comptime DisplayLink != void) {
                const dl = self.display_link orelse return false;
                return dl.isRunning();
            }
            return false;
        }

        /// Update macOS display ID for the display link.
        pub fn setMacOSDisplayID(self: *Self, id: u32) void {
            if (comptime DisplayLink != void) {
                const dl = self.display_link orelse return;
                log.info("updating display link display id={}", .{id});
                dl.setCurrentCGDisplay(id) catch |err| {
                    log.warn("error setting display link display id err={}", .{err});
                };
            } else {
                // Parameters are unused when DisplayLink is void (non-macOS).
                _ = .{ self, id };
            }
        }

        /// CVDisplayLink callback (macOS). Notifies the draw_now async handle.
        fn displayLinkCallback(
            _: if (DisplayLink != void) DisplayLink else *anyopaque,
            ud: ?*xev.Async,
        ) void {
            const draw_now = ud orelse return;
            draw_now.notify() catch |err| {
                log.err("error notifying draw_now err={}", .{err});
            };
        }
    };
}
