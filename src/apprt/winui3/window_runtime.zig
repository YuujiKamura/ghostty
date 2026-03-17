const std = @import("std");
const com = @import("com.zig");
const os = @import("os.zig");
const winrt = @import("winrt.zig");

const log = std.log.scoped(.winui3);

pub fn activateAndLoadResources(self: anytype, window: *com.IWindow) !void {
    // Step 7: Activate the window (makes it visible).
    log.info("initXaml step 7: Activate...", .{});
    try window.activate();
    log.info("initXaml step 7 OK: Window activated!", .{});

    // Titlebar: DWM frame extension only (ExtendsContentIntoTitleBar is not used —
    // it causes UI thread freeze on mouse hover, see Issue #42).
    // DWM frame is extended below via DwmExtendFrameIntoClientArea.

    // FORCE visibility via Win32 ShowWindow
    if (self.hwnd) |h| {
        _ = os.ShowWindow(h, os.SW_SHOWNORMAL);
        _ = os.UpdateWindow(h);
        _ = os.SetForegroundWindow(h);
        log.info("initXaml: Win32 ShowWindow(NORMAL) called", .{});

        // DWM frame extension (Windows Terminal style — NOT ExtendsContentIntoTitleBar).
        // Extend the DWM frame into the client area by the titlebar height so we can
        // draw our own content (TabView) in that region while keeping the DWM shadow.
        // cyTopHeight must be DPI-scaled (40px at 96 DPI).
        const dpi = os.GetDpiForWindow(h);
        const scale: f32 = if (dpi > 0) @as(f32, @floatFromInt(dpi)) / 96.0 else 1.0;
        const top_height: c_int = @intFromFloat(40.0 * scale);
        const margins = os.MARGINS{
            .cxLeftWidth = 0,
            .cxRightWidth = 0,
            .cyTopHeight = top_height,
            .cyBottomHeight = 0,
        };
        const hr = os.DwmExtendFrameIntoClientArea(h, &margins);
        if (hr >= 0) {
            log.info("initXaml: DwmExtendFrameIntoClientArea OK (cyTopHeight={} dpi={})", .{ top_height, dpi });
        } else {
            log.warn("initXaml: DwmExtendFrameIntoClientArea failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
        }
        // Force WM_NCCALCSIZE to run immediately so the system titlebar is
        // removed from the start. Without this, the titlebar is visible on
        // initial show but disappears on the first resize — an inconsistency
        // that looks like a bug ("titlebar disappears on resize").
        _ = os.SetWindowPos(
            h,
            null,
            0,
            0,
            0,
            0,
            os.SWP_FRAMECHANGED | os.SWP_NOMOVE | os.SWP_NOSIZE | os.SWP_NOZORDER,
        );

        // Enable dark mode for DWM caption buttons (white icons on dark background).
        const dark_mode: u32 = 1;
        _ = os.DwmSetWindowAttribute(h, os.DWMWA_USE_IMMERSIVE_DARK_MODE, @ptrCast(&dark_mode), @sizeOf(u32));
        // Set caption color to black to match our background.
        const caption_color: u32 = 0x00000000; // COLORREF: 0x00BBGGRR
        _ = os.DwmSetWindowAttribute(h, os.DWMWA_CAPTION_COLOR, @ptrCast(&caption_color), @sizeOf(u32));
        log.info("initXaml: DWM dark mode + caption color set", .{});
    }

    // Set initial size
    if (window.queryInterface(com.IFrameworkElement)) |fe| {
        var fe_guard = winrt.ComRef(com.IFrameworkElement).init(fe);
        defer fe_guard.deinit();
    } else |_| {}

    // Step 7.2: load XamlControlsResources after window activation.
    // Putting resources too early in startup can yield 0x8000ffff in unpackaged runs.
    // Theme is set in TabViewRoot.xaml (RequestedTheme="Light").
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
}
