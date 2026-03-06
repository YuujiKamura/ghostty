const std = @import("std");
const com = @import("com.zig");
const native_interop = @import("native_interop.zig");
const os = @import("os.zig");
const winrt = @import("winrt.zig");

const log = std.log.scoped(.winui3);

pub fn activateAndLoadResources(self: anytype, window: *com.IWindow) !void {
    // Step 7: Activate the window (makes it visible).
    log.info("initXaml step 7: Activate...", .{});
    try window.activate();
    log.info("initXaml step 7 OK: Window activated!", .{});

    // FORCE visibility via Win32 ShowWindow
    if (self.hwnd) |h| {
        _ = os.ShowWindow(h, os.SW_SHOWMAXIMIZED);
        _ = os.UpdateWindow(h);
        _ = os.SetForegroundWindow(h);
        log.info("initXaml: Win32 ShowWindow(MAXIMIZED) called", .{});
    }

    // Set initial size
    if (window.queryInterface(com.IFrameworkElement)) |fe| {
        var fe_guard = winrt.ComRef(com.IFrameworkElement).init(fe);
        defer fe_guard.deinit();
    } else |_| {}

    // Step 7.1: Enable content extension into title bar (Windows Terminal style).
    if (window.queryInterface(native_interop.IWindow2)) |win2| {
        var win2_guard = winrt.ComRef(native_interop.IWindow2).init(win2);
        defer win2_guard.deinit();
        win2_guard.get().putExtendsContentIntoTitleBar(true) catch |err| {
            log.warn("initXaml step 7.1: putExtendsContentIntoTitleBar failed: {}", .{err});
        };
    } else |_| {}

    // Step 7.2: load XamlControlsResources after window activation.
    // Putting resources too early in startup can yield 0x8000ffff in unpackaged runs.
    if (self.xaml_app) |xa| {
        log.info("initXaml step 7.2: loading XamlControlsResources...", .{});
        self.loadXamlResources(xa);
        log.info("initXaml step 7.2 OK", .{});
    } else {
        log.warn("initXaml step 7.2: skipped (IApplication unavailable)", .{});
    }
}

pub fn syncVisualDiagnostics(self: anytype) void {
    log.info("WinUI 3 Window created and activated (HWND=0x{x})", .{@intFromPtr(self.hwnd.?)});

    // Final attempt to force black background on root content.
    if (self.window) |win| {
        if (win.getContent() catch null) |content| {
            var content_guard = winrt.ComRef(winrt.IInspectable).init(@as(*winrt.IInspectable, @ptrCast(content)));
            defer content_guard.deinit();
            // Set Dark theme on the content as well.
            if (content.queryInterface(com.IFrameworkElement)) |fe| {
                var fe_guard = winrt.ComRef(com.IFrameworkElement).init(fe);
                defer fe_guard.deinit();
            } else |_| {}
            self.setControlBackground(@ptrCast(content), .{ .a = 255, .r = 0, .g = 0, .b = 0 });
        }
    }
}
