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
const os = @import("../winui3/os.zig");
const IslandWindow = @import("island_window.zig");
const AppHost = @import("App.zig");

const log = std.log.scoped(.winui3_islands);
const fileLog = AppHost.fileLog;

pub const NonClientIslandWindow = @This();

/// The underlying IslandWindow (Win32 HWND + DesktopWindowXamlSource).
island: IslandWindow,

/// Input-sink child window that catches mouse events in the titlebar region.
/// WT: _dragBarWindow (wil::unique_hwnd)
drag_bar_hwnd: ?os.HWND = null,

/// Whether the window is currently maximized.
/// WT: _isMaximized
is_maximized: bool = false,

/// WT: topBorderVisibleHeight = 1
const TOP_BORDER_VISIBLE_HEIGHT: c_int = 1;

/// Caption button zone width at 96 DPI (Min + Max + Close ≈ 138px).
const CAPTION_BUTTON_ZONE_96DPI: c_int = 138;

const DRAG_BAR_CLASS_NAME = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyDragBar");
const EMPTY_WINDOW_NAME = std.unicode.utf8ToUtf16LeStringLiteral("");

var drag_bar_class_registered: bool = false;

// ---------------------------------------------------------------------------
// Construction — WT: NonClientIslandWindow::MakeWindow()
// ---------------------------------------------------------------------------

pub fn init(self: *NonClientIslandWindow, app_ptr: *anyopaque) !void {
    self.* = .{
        .island = try IslandWindow.makeWindow(app_ptr, &nonclientWndProc),
        .drag_bar_hwnd = null,
    };

    // WT: MakeWindow() creates drag bar immediately after top-level HWND,
    // with size 0,0,0,0 and WS_EX_LAYERED | WS_EX_NOREDIRECTIONBITMAP.
    self.drag_bar_hwnd = self.createDragBarWindow();

    // Apply initial DWM settings before the window is shown.
    self.updateFrameMargins();
}

/// WT: NonClientIslandWindow::Close()
/// Clear GWLP_USERDATA on drag bar to prevent callbacks into XAML after close.
pub fn close(self: *NonClientIslandWindow) void {
    if (self.drag_bar_hwnd) |db| {
        _ = os.SetWindowLongPtrW(db, os.GWLP_USERDATA, 0);
    }
    self.destroyDragBarWindow();
    self.island.close();
}

pub fn destroyDragBarWindow(self: *NonClientIslandWindow) void {
    if (self.drag_bar_hwnd) |hwnd| {
        _ = os.DestroyWindow(hwnd);
        self.drag_bar_hwnd = null;
    }
}

// ---------------------------------------------------------------------------
// DWM frame management — WT: _UpdateFrameMargins()
// ---------------------------------------------------------------------------

/// WT uses AdjustWindowRectExForDpi to compute -frame.top as the margin.
/// We approximate with the same system metrics.
pub fn updateFrameMargins(self: *NonClientIslandWindow) void {
    const hwnd = self.island.hwnd;
    const dpi = os.GetDpiForWindow(hwnd);

    // WT: AdjustWindowRectExForDpi(&frame, style, FALSE, 0, dpi)
    // then margins.cyTopHeight = -frame.top
    // frame.top is negative, so -frame.top is positive.
    var frame: os.RECT = .{};
    const style = os.GetWindowLongPtrW(hwnd, os.GWL_STYLE);
    _ = os.AdjustWindowRectExForDpi(&frame, @truncate(@as(usize, @bitCast(style))), 0, 0, dpi);
    const top_height: c_int = -frame.top;

    const margins = os.MARGINS{
        .cxLeftWidth = 0,
        .cxRightWidth = 0,
        .cyTopHeight = top_height,
        .cyBottomHeight = 0,
    };
    const hr = os.DwmExtendFrameIntoClientArea(hwnd, &margins);
    if (hr >= 0) {
        fileLog("DwmExtendFrameIntoClientArea OK (cyTopHeight={} dpi={})", .{ top_height, dpi });
    } else {
        fileLog("DwmExtendFrameIntoClientArea failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
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
}

// ---------------------------------------------------------------------------
// WM_NCCALCSIZE — WT: _OnNcCalcSize
// ---------------------------------------------------------------------------

pub fn onNcCalcSize(hwnd: os.HWND, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (wparam == 0) return os.DefWindowProcW(hwnd, os.WM_NCCALCSIZE, wparam, lparam);

    const params: *os.NCCALCSIZE_PARAMS = @ptrFromInt(@as(usize, @bitCast(lparam)));
    const original_top = params.rgrc[0].top;

    // Let Windows calculate standard borders.
    const ret = os.DefWindowProcW(hwnd, os.WM_NCCALCSIZE, wparam, lparam);
    if (ret != 0) return ret;

    // Restore original top to remove system titlebar.
    params.rgrc[0].top = original_top;

    // When maximized, offset top by resize handle height so content
    // doesn't extend under the taskbar. WT: _GetResizeHandleHeight()
    if (os.IsZoomed(hwnd) != 0) {
        params.rgrc[0].top += getResizeHandleHeight(hwnd);
    }

    return 0;
}

// ---------------------------------------------------------------------------
// WM_NCHITTEST — WT: _OnNcHitTest
// ---------------------------------------------------------------------------

pub fn onNcHitTest(hwnd: os.HWND, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const mouse_y = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp >> 16)))));

    const original_ret = os.DefWindowProcW(hwnd, os.WM_NCHITTEST, 0, lparam);
    if (original_ret != os.HTCLIENT) {
        return original_ret;
    }

    var wrect: os.RECT = .{};
    _ = os.GetWindowRect(hwnd, &wrect);

    const resize_h = getResizeHandleHeight(hwnd);
    const is_on_resize_border = mouse_y < wrect.top + resize_h;

    // WT: the top of the drag bar is used to resize the window
    if (os.IsZoomed(hwnd) == 0 and is_on_resize_border) {
        return os.HTTOP;
    }

    return os.HTCAPTION;
}

// ---------------------------------------------------------------------------
// Island positioning — WT: _UpdateIslandPosition
// ---------------------------------------------------------------------------

/// WT places the island at HWND_BOTTOM with SWP_SHOWWINDOW | SWP_NOACTIVATE.
/// The drag bar sits on top (HWND_TOP) to intercept mouse events.
pub fn updateIslandPosition(self: *NonClientIslandWindow, width: c_int, height: c_int) void {
    const ih = self.island.interop_hwnd orelse {
        fileLog("updateIslandPosition: no interop_hwnd, skip", .{});
        return;
    };

    // WT: topBorderHeight. Bodgy: shift island up 1px when maximized
    // so the top row of pixels is clickable (Fitt's Law).
    const original_top = getTopBorderHeight(self.island.hwnd);
    const top_offset = if (original_top == 0) @as(c_int, -1) else original_top;
    const content_height = if (height > top_offset) height - top_offset else 0;

    // WT: SetWindowPos(_interopWindowHandle, HWND_BOTTOM, ...)
    _ = os.SetWindowPos(
        ih,
        os.HWND_BOTTOM,
        0,
        top_offset,
        width,
        content_height,
        os.SWP_SHOWWINDOW | os.SWP_NOACTIVATE,
    );

    // Resize drag bar to match new width.
    fileLog("updateIslandPosition: width={} height={} top_offset={}", .{ width, height, top_offset });
    self.resizeDragBarWindow(width);
}

/// WT: _ResizeDragBarWindow
/// Positions drag bar at HWND_TOP, covering the titlebar area.
/// Uses alpha=255 (opaque) — WS_EX_NOREDIRECTIONBITMAP makes it
/// composited-transparent (DWM sees no content → shows through).
pub fn resizeDragBarWindow(self: *NonClientIslandWindow, width_px: c_int) void {
    const drag_bar_hwnd = self.drag_bar_hwnd orelse return;
    const top_offset = getTopBorderHeight(self.island.hwnd);

    // WT: _GetDragAreaRect() returns the full width, titlebar height.
    // We use the full client width and the titlebar height from the window.
    const dpi = os.GetDpiForWindow(self.island.hwnd);
    const resize_h = getResizeHandleHeight(self.island.hwnd);
    // Use the frame top height as the titlebar area (same as updateFrameMargins).
    var frame: os.RECT = .{};
    const style = os.GetWindowLongPtrW(self.island.hwnd, os.GWL_STYLE);
    _ = os.AdjustWindowRectExForDpi(&frame, @truncate(@as(usize, @bitCast(style))), 0, 0, dpi);
    const titlebar_h: c_int = -frame.top;
    _ = resize_h; // used by getResizeHandleHeight for top border

    fileLog("resizeDragBarWindow: width={} titlebar_h={} frame.top={} top_offset={} style=0x{x}", .{
        width_px, titlebar_h, frame.top, top_offset, @as(usize, @bitCast(style)),
    });

    if (width_px > 0 and titlebar_h > 0) {
        // WT: SetWindowPos(HWND_TOP, rect.left, rect.top + _GetTopBorderHeight(), ...)
        _ = os.SetWindowPos(
            drag_bar_hwnd,
            os.HWND_TOP,
            0,
            top_offset,
            width_px,
            titlebar_h,
            os.SWP_NOACTIVATE | os.SWP_SHOWWINDOW,
        );
        // WT calls SetLayeredWindowAttributes(drag_bar, 0, 255, LWA_ALPHA) here,
        // but WS_EX_LAYERED is not available on child windows in this environment.
        // The drag bar is transparent by virtue of having no paint handler.
    } else {
        // WT: hide when titlebar not visible
        _ = os.SetWindowPos(drag_bar_hwnd, os.HWND_BOTTOM, 0, 0, 0, 0, os.SWP_HIDEWINDOW | os.SWP_NOMOVE | os.SWP_NOSIZE);
    }
}

// ---------------------------------------------------------------------------
// Helpers — WT: _GetTopBorderHeight, _GetResizeHandleHeight
// ---------------------------------------------------------------------------

/// WT: _GetTopBorderHeight — returns topBorderVisibleHeight (1) normally,
/// 0 when maximized or fullscreen.
fn getTopBorderHeight(hwnd: os.HWND) c_int {
    if (os.IsZoomed(hwnd) != 0) return 0;
    return TOP_BORDER_VISIBLE_HEIGHT;
}

/// WT: _GetResizeHandleHeight
fn getResizeHandleHeight(hwnd: os.HWND) c_int {
    const dpi = os.GetDpiForWindow(hwnd);
    return os.GetSystemMetricsForDpi(os.SM_CXPADDEDBORDER, dpi) +
        os.GetSystemMetricsForDpi(os.SM_CYSIZEFRAME, dpi);
}

// ---------------------------------------------------------------------------
// Drag bar window creation — WT: MakeWindow() drag bar section
// ---------------------------------------------------------------------------

fn createDragBarWindow(self: *NonClientIslandWindow) ?os.HWND {
    const hinstance = os.GetModuleHandleW(null) orelse {
        fileLog("createDragBarWindow: GetModuleHandleW returned null", .{});
        return null;
    };

    // WT: static lambda registers class once with CS_DBLCLKS, BLACK_BRUSH,
    // cbWndExtra = sizeof(NonClientIslandWindow*).
    if (!drag_bar_class_registered) {
        const wc = os.WNDCLASSEXW{
            .style = os.CS_HREDRAW | os.CS_VREDRAW | os.CS_DBLCLKS,
            .lpfnWndProc = &dragBarStaticWndProc,
            .cbWndExtra = @sizeOf(usize), // WT: sizeof(NonClientIslandWindow*)
            .hInstance = hinstance,
            .hCursor = os.LoadCursorW(null, os.IDC_ARROW),
            .hbrBackground = os.GetStockObject(os.BLACK_BRUSH),
            .lpszClassName = DRAG_BAR_CLASS_NAME,
        };
        const atom = os.RegisterClassExW(&wc);
        if (atom == 0) {
            const reg_err = os.GetLastError();
            if (reg_err == 1410) {
                fileLog("createDragBarWindow: class already registered (1410), continuing", .{});
            } else {
                fileLog("createDragBarWindow: RegisterClassExW failed err={}", .{reg_err});
                return null;
            }
        } else {
            fileLog("createDragBarWindow: class registered atom={}", .{atom});
        }
        drag_bar_class_registered = true;
    }

    // WT uses WS_EX_LAYERED | WS_EX_NOREDIRECTIONBITMAP here.
    // However, WS_EX_LAYERED cannot be set on child windows (WS_CHILD)
    // on Windows 11 Build 26200+ — CreateWindowExW returns NULL with err=0,
    // and SetWindowLongPtrW post-creation also silently fails.
    // (Verified with minimal repro: test-layered-child.c)
    //
    // The drag bar works without WS_EX_LAYERED because:
    // - It has no paint handler (DefWindowProc draws nothing meaningful)
    // - The parent has WS_EX_NOREDIRECTIONBITMAP, so DWM composition
    //   handles transparency without per-window layered attributes
    // - Its sole purpose is as an HWND_TOP input sink for WM_NCHITTEST
    const hwnd = os.CreateWindowExW(
        0,
        DRAG_BAR_CLASS_NAME,
        EMPTY_WINDOW_NAME,
        os.WS_CHILD,
        0, 0, 0, 0,
        self.island.hwnd,
        null,
        hinstance,
        @ptrCast(self),
    );
    if (hwnd) |h| {
        fileLog("createDragBarWindow: OK hwnd=0x{x}", .{@intFromPtr(h)});
    } else {
        fileLog("createDragBarWindow: CreateWindowExW FAILED err={}", .{os.GetLastError()});
    }
    return hwnd;
}

// ---------------------------------------------------------------------------
// Drag bar window procedure — WT: _StaticInputSinkWndProc + _InputSinkMessageHandler
// ---------------------------------------------------------------------------

/// WT: _StaticInputSinkWndProc
/// WM_NCCREATE stores `self` in GWLP_USERDATA, then falls through to DefWindowProc.
/// All other messages dispatch to _InputSinkMessageHandler via GWLP_USERDATA.
fn dragBarStaticWndProc(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) callconv(.winapi) os.LRESULT {
    if (msg == os.WM_NCCREATE) {
        const cs: *os.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        if (cs.lpCreateParams) |nci_ptr| {
            _ = os.SetWindowLongPtrW(hwnd, os.GWLP_USERDATA, @intFromPtr(nci_ptr));
            fileLog("dragBarWndProc: WM_NCCREATE hwnd=0x{x} nci=0x{x}", .{ @intFromPtr(hwnd), @intFromPtr(nci_ptr) });
        }
        // WT: fall through to DefWindowProc (do NOT return early)
    } else {
        const nci_ptr = os.GetWindowLongPtrW(hwnd, os.GWLP_USERDATA);
        if (nci_ptr != 0) {
            const self: *NonClientIslandWindow = @ptrFromInt(nci_ptr);
            return self.inputSinkMessageHandler(hwnd, msg, wparam, lparam);
        }
    }

    return os.DefWindowProcW(hwnd, msg, wparam, lparam);
}

/// WT: _InputSinkMessageHandler
fn inputSinkMessageHandler(self: *NonClientIslandWindow, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    _ = self; // TODO: will use for titlebar button state when XAML buttons are integrated

    switch (msg) {
        os.WM_NCHITTEST => return dragBarNcHitTest(hwnd, lparam),

        os.WM_NCMOUSEMOVE => {
            const parent = os.GetAncestor(hwnd, os.GA_PARENT) orelse return 0;
            const ht = @as(c_int, @intCast(@as(usize, @bitCast(wparam))));
            return switch (ht) {
                os.HTTOP, os.HTCAPTION => os.SendMessageW(parent, msg, wparam, lparam),
                else => 0,
            };
        },

        os.WM_NCLBUTTONDOWN, os.WM_NCLBUTTONDBLCLK => {
            const parent = os.GetAncestor(hwnd, os.GA_PARENT) orelse return 0;
            const ht = @as(c_int, @intCast(@as(usize, @bitCast(wparam))));
            return switch (ht) {
                os.HTTOP, os.HTCAPTION => os.SendMessageW(parent, msg, wparam, lparam),
                // WT: caption buttons are pressed via _titlebar.PressButton()
                os.HTMINBUTTON, os.HTMAXBUTTON, os.HTCLOSE => 0,
                else => 0,
            };
        },

        os.WM_NCLBUTTONUP => {
            const parent = os.GetAncestor(hwnd, os.GA_PARENT) orelse return 0;
            const ht = @as(c_int, @intCast(@as(usize, @bitCast(wparam))));
            return switch (ht) {
                os.HTTOP, os.HTCAPTION => os.SendMessageW(parent, msg, wparam, lparam),
                // WT: _titlebar.ReleaseButtons() + _titlebar.ClickButton()
                // We use WM_SYSCOMMAND since we don't have XAML titlebar buttons yet.
                os.HTMINBUTTON => blk: {
                    _ = os.PostMessageW(parent, os.WM_SYSCOMMAND, os.SC_MINIMIZE, 0);
                    break :blk 0;
                },
                os.HTMAXBUTTON => blk: {
                    const sc: usize = if (os.IsZoomed(parent) != 0) os.SC_RESTORE else os.SC_MAXIMIZE;
                    _ = os.PostMessageW(parent, os.WM_SYSCOMMAND, sc, 0);
                    break :blk 0;
                },
                os.HTCLOSE => blk: {
                    _ = os.PostMessageW(parent, os.WM_SYSCOMMAND, os.SC_CLOSE, 0);
                    break :blk 0;
                },
                else => 0,
            };
        },

        os.WM_NCRBUTTONDOWN, os.WM_NCRBUTTONUP, os.WM_NCRBUTTONDBLCLK => {
            const parent = os.GetAncestor(hwnd, os.GA_PARENT) orelse return 0;
            return os.SendMessageW(parent, msg, wparam, lparam);
        },

        else => return os.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// WT: _dragBarNcHitTest
fn dragBarNcHitTest(hwnd: os.HWND, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const pt = os.POINT{
        .x = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp))))),
        .y = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp >> 16))))),
    };

    const parent = os.GetParent(hwnd) orelse return os.HTCAPTION;
    var parent_rect: os.RECT = .{};
    _ = os.GetWindowRect(parent, &parent_rect);

    const dpi = os.GetDpiForWindow(parent);
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    const button_zone: c_int = @intFromFloat(@as(f32, @floatFromInt(CAPTION_BUTTON_ZONE_96DPI)) * scale);
    const button_w = @divFloor(button_zone, 3);

    // WT: rightBorder = rcParent.right - nonClientFrame.right
    // nonClientFrame.right is the right border width from GetNonClientFrame().
    // For simplicity, use the resize handle height as the border (same metric).
    const border = os.GetSystemMetricsForDpi(os.SM_CXSIZEFRAME, dpi) +
        os.GetSystemMetricsForDpi(os.SM_CXPADDEDBORDER, dpi);
    const right_border = parent_rect.right - border;

    if ((right_border - pt.x) < button_w) {
        return os.HTCLOSE;
    }
    if ((right_border - pt.x) < button_w * 2) {
        return os.HTMAXBUTTON;
    }
    if ((right_border - pt.x) < button_w * 3) {
        return os.HTMINBUTTON;
    }

    const resize_h = getResizeHandleHeight(parent);
    return if (pt.y < parent_rect.top + resize_h and os.IsZoomed(parent) == 0) os.HTTOP else os.HTCAPTION;
}

// ---------------------------------------------------------------------------
// Window procedure — WT: NonClientIslandWindow::MessageHandler
// ---------------------------------------------------------------------------

fn nonclientWndProc(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) callconv(.winapi) os.LRESULT {
    const App = @import("App.zig");

    // WM_CREATE: store the app pointer from CREATESTRUCTW.lpCreateParams.
    if (msg == os.WM_CREATE) {
        const cs: *os.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        if (cs.lpCreateParams) |app_ptr| {
            _ = os.SetWindowLongPtrW(hwnd, os.GWLP_USERDATA, @intFromPtr(app_ptr));
        }
        return os.DefWindowProcW(hwnd, msg, wparam, lparam);
    }

    // WT: Let DWM handle caption button rendering first.
    var dwm_result: os.LRESULT = 0;
    if (os.DwmDefWindowProc(hwnd, msg, wparam, lparam, &dwm_result) != 0) {
        return dwm_result;
    }

    // WT: NonClientIslandWindow::MessageHandler
    switch (msg) {
        os.WM_NCCALCSIZE => return onNcCalcSize(hwnd, wparam, lparam),
        os.WM_NCHITTEST => return onNcHitTest(hwnd, lparam),

        os.WM_PAINT => {
            // WT: _OnPaint — fill top border with black, rest with background.
            // Simplified: just validate the paint region.
            var ps: os.PAINTSTRUCT = .{};
            const hdc = os.BeginPaint(hwnd, &ps);
            if (hdc) |dc| {
                // Fill top border area with black (1px in normal mode).
                const top_h = getTopBorderHeight(hwnd);
                if (ps.rcPaint.top < top_h) {
                    var rc_top = ps.rcPaint;
                    rc_top.bottom = top_h;
                    if (os.GetStockObject(os.BLACK_BRUSH)) |brush| {
                        _ = os.FillRect(dc, &rc_top, brush);
                    }
                }
            }
            _ = os.EndPaint(hwnd, &ps);
            return 0;
        },

        os.WM_ERASEBKGND => return 1,

        os.WM_DESTROY => {
            os.PostQuitMessage(0);
            return 0;
        },

        else => {},
    }

    // Delegate App-specific messages.
    const app_ptr_raw = os.GetWindowLongPtrW(hwnd, os.GWLP_USERDATA);
    if (app_ptr_raw != 0) {
        const app: *App = @ptrFromInt(app_ptr_raw);
        if (app.handleWndProcMessage(hwnd, msg, wparam, lparam)) |result| {
            return result;
        }
    }

    return os.DefWindowProcW(hwnd, msg, wparam, lparam);
}
