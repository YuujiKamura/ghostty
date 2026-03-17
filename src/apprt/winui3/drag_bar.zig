/// Transparent drag-bar child window for custom titlebar dragging.
///
/// Modeled after Windows Terminal's NonClientIslandWindow `_dragBarWindow`:
/// a layered, no-redirection-bitmap child window that sits on top of the XAML
/// content in the titlebar region and returns HTCAPTION for WM_NCHITTEST so
/// the user can drag the window by clicking on the titlebar area.
const std = @import("std");
const os = @import("os.zig");
const App = @import("App.zig");

const log = std.log.scoped(.winui3_drag_bar);
const fileLog = App.fileLog;

/// Window class name (UTF-16LE, null-terminated).
const DRAG_BAR_CLASS_NAME = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyDragBar");

/// Whether the window class has been registered.
var class_registered: bool = false;

/// DWM titlebar height in pixels at 96 DPI.
const TITLEBAR_HEIGHT_96DPI: c_int = 40;
/// Resize border width at 96 DPI.
const RESIZE_BORDER_96DPI: c_int = 6;
/// Caption button width at 96 DPI (Min/Max/Close each ~46px).
const CAPTION_BUTTON_WIDTH_96DPI: c_int = 46;

/// Create the drag-bar child window and return its HWND.
pub fn createDragBar(parent: os.HWND) ?os.HWND {
    const hinstance = os.GetModuleHandleW(null) orelse {
        fileLog("createDragBar: GetModuleHandleW returned null", .{});
        return null;
    };

    // Register the window class once.
    if (!class_registered) {
        const wc = os.WNDCLASSEXW{
            .style = os.CS_HREDRAW | os.CS_VREDRAW,
            .lpfnWndProc = &dragBarWndProc,
            .hInstance = hinstance,
            .hbrBackground = null,
            .lpszClassName = DRAG_BAR_CLASS_NAME,
        };
        const atom = os.RegisterClassExW(&wc);
        if (atom == 0) {
            fileLog("createDragBar: RegisterClassExW failed err={}", .{os.GetLastError()});
            return null;
        }
        class_registered = true;
        fileLog("createDragBar: class registered atom={}", .{atom});
    }

    // Compute initial size from parent client rect.
    var rect: os.RECT = .{};
    const gcr = os.GetClientRect(parent, &rect);
    const parent_width: c_int = rect.right - rect.left;
    fileLog("createDragBar: GetClientRect={} rect=({},{},{},{}) width={}", .{ gcr, rect.left, rect.top, rect.right, rect.bottom, parent_width });

    const dpi = os.GetDpiForWindow(parent);
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    const tb_h: c_int = @intFromFloat(@as(f32, @floatFromInt(TITLEBAR_HEIGHT_96DPI)) * scale);

    fileLog("createDragBar: calling CreateWindowExW size={}x{}", .{ parent_width, tb_h });
    os.SetLastError(0);
    const hwnd = os.CreateWindowExW(
        os.WS_EX_LAYERED, // transparent — must call SetLayeredWindowAttributes after creation
        DRAG_BAR_CLASS_NAME,
        DRAG_BAR_CLASS_NAME,
        os.WS_CHILD | os.WS_VISIBLE,
        0,
        0,
        parent_width,
        tb_h,
        parent,
        null,
        hinstance,
        null,
    );

    if (hwnd) |h| {
        // Make fully transparent (alpha=0) so it doesn't render but still catches mouse.
        _ = os.SetLayeredWindowAttributes(h, 0, 0, os.LWA_ALPHA);
        // Place on top of XAML content (Z-order).
        _ = os.SetWindowPos(h, os.HWND_TOP, 0, 0, 0, 0, os.SWP_NOMOVE | os.SWP_NOSIZE | os.SWP_NOACTIVATE);
        fileLog("createDragBar: created HWND=0x{x} size={}x{}", .{ @intFromPtr(h), parent_width, tb_h });
    } else {
        fileLog("createDragBar: CreateWindowExW failed err={}", .{os.GetLastError()});
    }

    return hwnd;
}

/// Resize the drag bar to match the current parent size and DPI.
pub fn resizeDragBar(drag_bar_hwnd: os.HWND, parent_hwnd: os.HWND, width_px: c_int) void {
    const dpi = os.GetDpiForWindow(parent_hwnd);
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    const tb_h: c_int = @intFromFloat(@as(f32, @floatFromInt(TITLEBAR_HEIGHT_96DPI)) * scale);

    _ = os.MoveWindow(drag_bar_hwnd, 0, 0, width_px, tb_h, 1);
    // Re-assert Z-order on top of XAML.
    _ = os.SetWindowPos(drag_bar_hwnd, os.HWND_TOP, 0, 0, 0, 0, os.SWP_NOMOVE | os.SWP_NOSIZE | os.SWP_NOACTIVATE);
}

/// Window procedure for the drag bar.
fn dragBarWndProc(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) callconv(.winapi) os.LRESULT {
    switch (msg) {
        os.WM_NCHITTEST => {
            return dragBarHitTest(hwnd, lparam);
        },
        os.WM_NCLBUTTONDOWN, os.WM_NCLBUTTONDBLCLK => {
            // Forward to parent so the top-level window initiates the drag/maximize.
            // Windows Terminal: SendMessage(GetAncestor(hWnd, GA_PARENT), message, wParam, lParam)
            const parent = os.GetAncestor(hwnd, os.GA_PARENT) orelse return 0;
            return os.SendMessageW(parent, msg, wparam, lparam);
        },
        os.WM_SETCURSOR => {
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        else => return os.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// Hit-test for the drag bar: determine what part of the non-client area the
/// cursor is over.
fn dragBarHitTest(hwnd: os.HWND, lparam: os.LPARAM) os.LRESULT {
    // Extract screen coordinates from lparam.
    const lp: usize = @bitCast(lparam);
    const pt = os.POINT{
        .x = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp))))),
        .y = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp >> 16))))),
    };

    // Use GetWindowRect (already in screen coords) to avoid DPI mismatch.
    var wrect: os.RECT = .{};
    _ = os.GetWindowRect(hwnd, &wrect);

    const parent = os.GetParent(hwnd) orelse return os.HTCAPTION;
    const dpi = os.GetDpiForWindow(parent);
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    const resize_border: c_int = @intFromFloat(@as(f32, @floatFromInt(RESIZE_BORDER_96DPI)) * scale);
    const button_w: c_int = @intFromFloat(@as(f32, @floatFromInt(CAPTION_BUTTON_WIDTH_96DPI)) * scale);

    // Top resize border (HTTOP).
    if (pt.y >= wrect.top and pt.y < wrect.top + resize_border) {
        return os.HTTOP;
    }

    // Caption buttons area — pass through to DWM-drawn buttons.
    const buttons_left = wrect.right - button_w * 3;
    if (pt.x >= buttons_left) {
        return os.HTTRANSPARENT;
    }

    // Everything else is draggable caption.
    return os.HTCAPTION;
}
