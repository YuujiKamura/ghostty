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

        // DWM frame extension (Windows Terminal style — NOT ExtendsContentIntoTitleBar).
        // Extend the DWM frame into the client area by the titlebar height so we can
        // draw our own content (TabView) in that region while keeping the DWM shadow.
        const margins = os.MARGINS{
            .cxLeftWidth = 0,
            .cxRightWidth = 0,
            .cyTopHeight = 40, // titlebar height in px
            .cyBottomHeight = 0,
        };
        const hr = os.DwmExtendFrameIntoClientArea(h, &margins);
        if (hr >= 0) {
            log.info("initXaml: DwmExtendFrameIntoClientArea OK (cyTopHeight=40)", .{});
        } else {
            log.warn("initXaml: DwmExtendFrameIntoClientArea failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
        }
    }

    // Set initial size
    if (window.queryInterface(com.IFrameworkElement)) |fe| {
        var fe_guard = winrt.ComRef(com.IFrameworkElement).init(fe);
        defer fe_guard.deinit();
    } else |_| {}

    // Step 7.1: Enable content extension into title bar (Windows Terminal style).
    // ExtendsContentIntoTitleBar is on IWindow (v1), not IWindow2.
    // Since `window` is already *com.IWindow, call directly.
    // NOTE: Temporarily disabled — enabling this without a fully styled TabView
    // causes layout issues (white screen in Row 1). Re-enable once TabView
    // template rendering is confirmed working.
    // window.putExtendsContentIntoTitleBar(true) catch |err| {
    //     log.warn("initXaml step 7.1: putExtendsContentIntoTitleBar failed: {}", .{err});
    // };
    log.info("initXaml step 7.1: ExtendsContentIntoTitleBar = SKIPPED (pending TabView template fix)", .{});

    // Step 7.2: load XamlControlsResources after window activation.
    // Putting resources too early in startup can yield 0x8000ffff in unpackaged runs.
    if (self.xaml_app) |xa| {
        // ApplicationTheme: Light=0, Dark=1
        xa.putRequestedTheme(1) catch |err| {
            log.warn("putRequestedTheme(Dark) failed: {}", .{err});
        };
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
                // ElementTheme: Default=0, Light=1, Dark=2
                fe.putRequestedTheme(2) catch {};
            } else |_| {}
            self.setControlBackground(@ptrCast(content), .{ .a = 255, .r = 0, .g = 0, .b = 0 });
        }
    }
}
