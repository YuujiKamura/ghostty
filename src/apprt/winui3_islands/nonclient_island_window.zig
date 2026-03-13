/// Custom titlebar window — Windows Terminal NonClientIslandWindow equivalent.
///
/// Extends IslandWindow with:
///   - DwmExtendFrameIntoClientArea (glass titlebar)
///   - WM_NCCALCSIZE (system titlebar removal)
///   - WM_NCHITTEST (resize borders + caption)
///   - Drag bar child window (input sink for titlebar mouse events)
///   - Dark mode + caption color via DWM attributes
///
/// Ref: github.com/microsoft/terminal/blob/main/src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp

const std = @import("std");
const com = @import("../winui3/com.zig");
const os = @import("../winui3/os.zig");
const winrt = @import("../winui3/winrt.zig");
const IslandWindow = @import("island_window.zig");

const log = std.log.scoped(.winui3_islands);

pub const NonClientIslandWindow = @This();

/// The underlying IslandWindow (Win32 HWND + DesktopWindowXamlSource).
island: IslandWindow,

/// Transparent child window that catches mouse events in the titlebar region.
drag_bar_hwnd: ?os.HWND = null,

/// DWM titlebar height in logical pixels (at 96 DPI).
const TITLEBAR_HEIGHT_96DPI: c_int = 40;

/// Caption button zone width at 96 DPI (Min + Max + Close ≈ 138px).
const CAPTION_BUTTON_ZONE_96DPI: c_int = 138;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Create a NonClientIslandWindow.
///
/// Calls IslandWindow.makeWindow with `nonclientWndProc` as the window procedure,
/// then applies initial DWM frame settings.
pub fn create(app_ptr: *anyopaque) !NonClientIslandWindow {
    var island = try IslandWindow.makeWindow(app_ptr, &nonclientWndProc);
    _ = &island; // avoid unused-var in case of early return

    var nci = NonClientIslandWindow{
        .island = island,
    };

    // Apply initial DWM settings before the window is shown.
    nci.updateFrameMargins();

    return nci;
}

// ---------------------------------------------------------------------------
// DWM frame management
// ---------------------------------------------------------------------------

/// WT: _UpdateFrameMargins
///
/// Extends the DWM frame into the client area by the titlebar height,
/// enabling the glass titlebar effect. Also sets dark mode and caption color.
pub fn updateFrameMargins(self: *NonClientIslandWindow) void {
    const hwnd = self.island.hwnd;
    const dpi = os.GetDpiForWindow(hwnd);
    const scale: f32 = if (dpi > 0) @as(f32, @floatFromInt(dpi)) / 96.0 else 1.0;
    const top_height: c_int = @intFromFloat(@as(f32, @floatFromInt(TITLEBAR_HEIGHT_96DPI)) * scale);

    const margins = os.MARGINS{
        .cxLeftWidth = 0,
        .cxRightWidth = 0,
        .cyTopHeight = top_height,
        .cyBottomHeight = 0,
    };
    const hr = os.DwmExtendFrameIntoClientArea(hwnd, &margins);
    if (hr >= 0) {
        log.info("DwmExtendFrameIntoClientArea OK (cyTopHeight={} dpi={})", .{ top_height, dpi });
    } else {
        log.warn("DwmExtendFrameIntoClientArea failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
    }

    // Force WM_NCCALCSIZE so the system titlebar is removed immediately.
    _ = os.SetWindowPos(
        hwnd,
        null,
        0,
        0,
        0,
        0,
        os.SWP_FRAMECHANGED | os.SWP_NOMOVE | os.SWP_NOSIZE | os.SWP_NOZORDER,
    );

    // Dark mode for DWM caption buttons (white icons on dark background).
    const dark_mode: u32 = 1;
    _ = os.DwmSetWindowAttribute(hwnd, os.DWMWA_USE_IMMERSIVE_DARK_MODE, @ptrCast(&dark_mode), @sizeOf(u32));

    // Black caption color to match terminal background.
    const caption_color: u32 = 0x00000000; // COLORREF: 0x00BBGGRR
    _ = os.DwmSetWindowAttribute(hwnd, os.DWMWA_CAPTION_COLOR, @ptrCast(&caption_color), @sizeOf(u32));

    log.info("DWM dark mode + caption color applied", .{});
}

// ---------------------------------------------------------------------------
// WM_NCCALCSIZE — remove system titlebar
// ---------------------------------------------------------------------------

/// WT: _OnNcCalcSize
///
/// Windows Terminal pattern: let DefWindowProcW calculate the standard
/// non-client area, then restore the original top coordinate so the
/// client area extends into the titlebar. Left/right/bottom borders
/// are preserved so DWM-drawn caption buttons (Min/Max/Close) remain.
///
/// When maximized, add system frame offset so content doesn't bleed
/// under the taskbar.
pub fn onNcCalcSize(hwnd: os.HWND, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (wparam == 0) return os.DefWindowProcW(hwnd, os.WM_NCCALCSIZE, wparam, lparam);

    const params: *os.NCCALCSIZE_PARAMS = @ptrFromInt(@as(usize, @bitCast(lparam)));
    const original_top = params.rgrc[0].top;

    // Let Windows calculate standard borders.
    _ = os.DefWindowProcW(hwnd, os.WM_NCCALCSIZE, wparam, lparam);

    // Restore original top to remove system titlebar.
    params.rgrc[0].top = original_top;

    // When maximized, offset top by the resize frame + padded border so
    // the content doesn't extend under the taskbar.
    if (os.IsZoomed(hwnd) != 0) {
        const dpi = os.GetDpiForWindow(hwnd);
        const frame_h = os.GetSystemMetricsForDpi(os.SM_CYSIZEFRAME, dpi) +
            os.GetSystemMetricsForDpi(os.SM_CXPADDEDBORDER, dpi);
        params.rgrc[0].top += frame_h;
    }

    return 0;
}

// ---------------------------------------------------------------------------
// WM_NCHITTEST — resize borders + caption
// ---------------------------------------------------------------------------

/// WT: _OnNcHitTest
///
/// Returns the appropriate NCHITTEST value for resize borders, caption
/// area, and client area. This is the same logic used in the existing
/// winui3/wndproc.zig subclass, adapted for a direct wndproc.
pub fn onNcHitTest(hwnd: os.HWND, lparam: os.LPARAM) os.LRESULT {
    // Extract screen coordinates from lparam.
    var wrect: os.RECT = .{};
    _ = os.GetWindowRect(hwnd, &wrect);
    const lp: usize = @bitCast(lparam);
    const mouse_x = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp)))));
    const mouse_y = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp >> 16)))));

    const dpi = os.GetDpiForWindow(hwnd);
    const resize_h = os.GetSystemMetricsForDpi(os.SM_CXPADDEDBORDER, dpi) +
        os.GetSystemMetricsForDpi(os.SM_CYSIZEFRAME, dpi);

    // Top resize border.
    if (mouse_y < wrect.top + resize_h) {
        if (mouse_x < wrect.left + resize_h) return os.HTTOPLEFT;
        if (mouse_x >= wrect.right - resize_h) return os.HTTOPRIGHT;
        return os.HTTOP;
    }

    // Bottom resize border.
    if (mouse_y >= wrect.bottom - resize_h) {
        if (mouse_x < wrect.left + resize_h) return os.HTBOTTOMLEFT;
        if (mouse_x >= wrect.right - resize_h) return os.HTBOTTOMRIGHT;
        return os.HTBOTTOM;
    }

    // Left/right resize borders.
    if (mouse_x < wrect.left + resize_h) return os.HTLEFT;
    if (mouse_x >= wrect.right - resize_h) return os.HTRIGHT;

    // Titlebar region → HTCAPTION (for drag and system menu).
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    const titlebar_h: c_int = @intFromFloat(@as(f32, @floatFromInt(TITLEBAR_HEIGHT_96DPI)) * scale);
    if (mouse_y < wrect.top + titlebar_h) {
        // Exclude caption buttons area (DWM-drawn Min/Max/Close).
        const button_zone: c_int = @intFromFloat(@as(f32, @floatFromInt(CAPTION_BUTTON_ZONE_96DPI)) * scale);
        if (mouse_x >= wrect.right - button_zone) {
            // Let DwmDefWindowProc handle caption button clicks.
            return os.HTCLIENT;
        }
        return os.HTCAPTION;
    }

    return os.HTCLIENT;
}

// ---------------------------------------------------------------------------
// Island positioning
// ---------------------------------------------------------------------------

/// WT: _UpdateIslandPosition
///
/// In Windows Terminal, the island content is offset from the top of the
/// window by the "top border height" — normally 1px (the visible top border),
/// or the full resize handle height when maximized (to avoid clipping).
///
/// We then pass the remaining height to IslandWindow.onSize() for the
/// actual XAML content sizing.
pub fn updateIslandPosition(self: *NonClientIslandWindow, width: c_int, height: c_int) void {
    const hwnd = self.island.hwnd;
    const top_offset = getTopBorderHeight(hwnd);
    const content_height = if (height > top_offset) height - top_offset else 0;

    // If using manual sizing, we need to position the island HWND.
    if (!self.island.auto_resize) {
        if (self.island.interop_hwnd) |ih| {
            _ = os.SetWindowPos(
                ih,
                null,
                0,
                top_offset,
                width,
                content_height,
                os.SWP_SHOWWINDOW,
            );
            return;
        }
    }

    // For auto-resize mode, just call onSize (which is a no-op, but keeps
    // the interface consistent for future use).
    self.island.onSize(width, content_height);
}

/// WT: _GetTopBorderHeight
///
/// Returns the height of the top border that should be visible above the
/// island content. Normally 1px. When maximized, returns the full resize
/// frame height so content doesn't peek above the monitor edge.
fn getTopBorderHeight(hwnd: os.HWND) c_int {
    if (os.IsZoomed(hwnd) != 0) {
        const dpi = os.GetDpiForWindow(hwnd);
        return os.GetSystemMetricsForDpi(os.SM_CYSIZEFRAME, dpi) +
            os.GetSystemMetricsForDpi(os.SM_CXPADDEDBORDER, dpi);
    }
    // Normal (restored) state: 1px top border is visible.
    return 1;
}

// ---------------------------------------------------------------------------
// Window procedure
// ---------------------------------------------------------------------------

/// Main window procedure for the NonClientIslandWindow.
///
/// Handles NC messages (DWM titlebar, resize borders) directly, then
/// delegates App-specific messages (WM_USER, WM_TIMER, WM_SIZE, etc.)
/// to App.handleWndProcMessage().
fn nonclientWndProc(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) callconv(.winapi) os.LRESULT {
    const App = @import("App.zig");

    // WM_CREATE: store the app pointer from CREATESTRUCTW.lpCreateParams
    // into GWLP_USERDATA for later retrieval.
    if (msg == os.WM_CREATE) {
        const cs: *os.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        if (cs.lpCreateParams) |app_ptr| {
            _ = os.SetWindowLongPtrW(hwnd, os.GWLP_USERDATA, @intFromPtr(app_ptr));
            log.info("WM_CREATE: stored app_ptr=0x{x} in GWLP_USERDATA", .{@intFromPtr(app_ptr)});
        }
        return os.DefWindowProcW(hwnd, msg, wparam, lparam);
    }

    // Let DWM handle caption button rendering first.
    var dwm_result: os.LRESULT = 0;
    if (os.DwmDefWindowProc(hwnd, msg, wparam, lparam, &dwm_result) != 0) {
        return dwm_result;
    }

    // NC messages handled directly by NonClientIslandWindow.
    switch (msg) {
        os.WM_NCCALCSIZE => return onNcCalcSize(hwnd, wparam, lparam),
        os.WM_NCHITTEST => return onNcHitTest(hwnd, lparam),

        os.WM_PAINT => {
            // Minimal paint handler — just validate the region.
            var ps: os.PAINTSTRUCT = .{};
            _ = os.BeginPaint(hwnd, &ps);
            _ = os.EndPaint(hwnd, &ps);
            return 0;
        },

        os.WM_ERASEBKGND => return 1, // Suppress background erase.

        os.WM_DESTROY => {
            log.info("WM_DESTROY", .{});
            os.PostQuitMessage(0);
            return 0;
        },

        else => {},
    }

    // Delegate App-specific messages (WM_USER, WM_TIMER, WM_SIZE, WM_CLOSE,
    // WM_ENTERSIZEMOVE, WM_EXITSIZEMOVE, WM_SETFOCUS, WM_DPICHANGED, etc.).
    const app_ptr_raw = os.GetWindowLongPtrW(hwnd, os.GWLP_USERDATA);
    if (app_ptr_raw != 0) {
        const app: *App = @ptrFromInt(app_ptr_raw);
        if (app.handleWndProcMessage(hwnd, msg, wparam, lparam)) |result| {
            return result;
        }
    }

    return os.DefWindowProcW(hwnd, msg, wparam, lparam);
}
