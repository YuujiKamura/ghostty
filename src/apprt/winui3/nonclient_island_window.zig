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
const os = @import("os.zig");
const IslandWindow = @import("island_window.zig");
const log = std.log.scoped(.winui3);



pub const NonClientIslandWindow = @This();

/// The underlying IslandWindow (Win32 HWND + DesktopWindowXamlSource).
island: IslandWindow,

/// Input-sink child window that catches mouse events in the titlebar region.
/// WT: _dragBarWindow (wil::unique_hwnd)
drag_bar_hwnd: ?os.HWND = null,

/// Whether the window is currently maximized.
/// WT: _isMaximized
is_maximized: bool = false,

/// Cached cyTopHeight to avoid redundant DwmExtendFrameIntoClientArea calls.
cached_top_height: c_int = -1,

/// WT: topBorderVisibleHeight = 1
const TOP_BORDER_VISIBLE_HEIGHT: c_int = 1;

/// Caption button zone width at 96 DPI (Min + Max + Close ≈ 138px).
const CAPTION_BUTTON_ZONE_96DPI: c_int = 138;

/// Extra drag space (at 96 DPI) to the left of caption buttons for window dragging.
/// WT dynamically sizes this from XAML; we use a generous fixed value.
const DRAG_SPACE_96DPI: c_int = 400;

/// Total drag zone at 96 DPI = caption buttons + extra drag space.
const DRAG_ZONE_96DPI: c_int = CAPTION_BUTTON_ZONE_96DPI + DRAG_SPACE_96DPI;

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

    // Drag bar creation is DEFERRED to createDragBarIfNeeded(), called
    // after DXWS initialization (island.initialize()). WS_EX_LAYERED on
    // child windows may require the WinUI3 runtime to be initialized first.

    // Apply initial DWM settings before the window is shown.
    self.initFrameMargins();
}

/// Create the drag bar window if not already created.
/// Must be called AFTER island.initialize() so the WinUI3 runtime is active.
pub fn createDragBarIfNeeded(self: *NonClientIslandWindow) void {
    if (self.drag_bar_hwnd != null) return;
    self.drag_bar_hwnd = self.createDragBarWindow();
    if (self.drag_bar_hwnd != null) {
        // Force interop HWND to BOTTOM so drag bar receives mouse events.
        if (self.island.interop_hwnd) |ih| {
            _ = os.SetWindowPos(ih, os.HWND_BOTTOM, 0, 0, 0, 0,
                os.SWP_NOMOVE | os.SWP_NOSIZE | os.SWP_NOACTIVATE);
        }
        // Show the drag bar at the correct position.
        var rect: os.RECT = .{};
        _ = os.GetClientRect(self.island.hwnd, &rect);
        self.resizeDragBarWindow(rect.right - rect.left);
    }
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
/// Called once at init and on DPI change. Sets up DWM frame, triggers
/// WM_NCCALCSIZE, and configures dark mode + caption color.
pub fn initFrameMargins(self: *NonClientIslandWindow) void {
    self.updateFrameMargins();

    const hwnd = self.island.hwnd;

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

    // Dark mode for DWM caption buttons.
    const dark_mode: u32 = 1;
    _ = os.DwmSetWindowAttribute(hwnd, os.DWMWA_USE_IMMERSIVE_DARK_MODE, @ptrCast(&dark_mode), @sizeOf(u32));

    // Match XAML Dark theme background (#202020 = COLORREF 0x00202020).
    const caption_color: u32 = 0x00202020; // COLORREF: 0x00BBGGRR
    _ = os.DwmSetWindowAttribute(hwnd, os.DWMWA_CAPTION_COLOR, @ptrCast(&caption_color), @sizeOf(u32));
}

/// Called on every resize. Only updates DwmExtendFrameIntoClientArea when
/// the margin value actually changes (maximize/restore or DPI change).
/// Redundant calls kill DWM caption buttons.
pub fn updateFrameMargins(self: *NonClientIslandWindow) void {
    const hwnd = self.island.hwnd;
    const dpi = os.GetDpiForWindow(hwnd);

    var frame: os.RECT = .{};
    const style = os.GetWindowLongPtrW(hwnd, os.GWL_STYLE);
    _ = os.AdjustWindowRectExForDpi(&frame, @truncate(@as(usize, @bitCast(style))), 0, 0, dpi);
    const top_height: c_int = -frame.top;

    // Skip if margins haven't changed.
    if (top_height == self.cached_top_height) return;
    self.cached_top_height = top_height;

    const margins = os.MARGINS{
        .cxLeftWidth = 0,
        .cxRightWidth = 0,
        .cyTopHeight = top_height,
        .cyBottomHeight = 0,
    };
    const hr = os.DwmExtendFrameIntoClientArea(hwnd, &margins);
    if (hr >= 0) {
        log.debug("DwmExtendFrameIntoClientArea OK (cyTopHeight={} dpi={})", .{ top_height, dpi });
    } else {
        log.err("DwmExtendFrameIntoClientArea failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
    }
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
    const mouse_x = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp)))));
    const mouse_y = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp >> 16)))));

    const original_ret = os.DefWindowProcW(hwnd, os.WM_NCHITTEST, 0, lparam);
    if (original_ret != os.HTCLIENT) {
        return original_ret;
    }

    var wrect: os.RECT = .{};
    _ = os.GetWindowRect(hwnd, &wrect);

    const resize_h = getResizeHandleHeight(hwnd);
    const is_on_resize_border = mouse_y < wrect.top + resize_h;

    // WT: the top of the drag bar is used to resize the window (full width)
    if (os.IsZoomed(hwnd) == 0 and is_on_resize_border) {
        return os.HTTOP;
    }

    // The drag bar only covers the right portion of the titlebar.
    // For the left portion (tab area), return HTCLIENT so XAML gets clicks.
    const dpi = os.GetDpiForWindow(hwnd);
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    const drag_zone: c_int = @intFromFloat(@as(f32, @floatFromInt(DRAG_ZONE_96DPI)) * scale);
    const drag_x = wrect.right - drag_zone;

    // In the titlebar region but LEFT of drag zone → let XAML handle it
    if (mouse_x < drag_x) {
        return os.HTCLIENT;
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
        log.debug("updateIslandPosition: no interop_hwnd, skip", .{});
        return;
    };

    // WT: topBorderHeight. Bodgy: shift island up 1px when maximized
    // so the top row of pixels is clickable (Fitt's Law).
    const original_top = getTopBorderHeight(self.island.hwnd);
    const top_offset = if (original_top == 0) @as(c_int, -1) else original_top;
    const content_height = if (height > top_offset) height - top_offset else 0;

    // WT: position interop HWND at HWND_BOTTOM so the drag bar stays on top.
    const z_after = os.HWND_BOTTOM;
    _ = os.SetWindowPos(
        ih,
        z_after,
        0,
        top_offset,
        width,
        content_height,
        os.SWP_SHOWWINDOW | os.SWP_NOACTIVATE,
    );

    // Resize drag bar to match new width.
    log.debug("updateIslandPosition: width={} height={} top_offset={} interop=0x{x}", .{ width, height, top_offset, @intFromPtr(ih) });
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

    log.debug("resizeDragBarWindow: width={} titlebar_h={} frame.top={} top_offset={} style=0x{x}", .{
        width_px, titlebar_h, frame.top, top_offset, @as(usize, @bitCast(style)),
    });

    if (width_px > 0 and titlebar_h > 0) {
        // Drag bar covers the RIGHT portion of the titlebar only.
        // Left portion (tabs) is left uncovered so XAML receives clicks.
        // WT uses _GetDragAreaRect() from XAML to size this; we approximate
        // with a fixed zone = caption buttons + generous drag space.
        const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
        const drag_zone: c_int = @intFromFloat(@as(f32, @floatFromInt(DRAG_ZONE_96DPI)) * scale);
        // Clamp: don't exceed half the window width so tabs stay clickable.
        const max_zone = @divFloor(width_px, 2);
        const clamped_zone = @min(drag_zone, max_zone);
        const drag_x = width_px - clamped_zone;
        const drag_w = clamped_zone;

        _ = os.SetWindowPos(
            drag_bar_hwnd,
            os.HWND_TOP,
            drag_x,
            top_offset,
            drag_w,
            titlebar_h,
            os.SWP_NOACTIVATE | os.SWP_SHOWWINDOW | os.SWP_NOSENDCHANGING,
        );

        // WT: alpha=255 — opaque to hit testing, visually transparent via NOREDIRECTIONBITMAP.
        _ = os.SetLayeredWindowAttributes(drag_bar_hwnd, 0, 255, os.LWA_ALPHA);
    } else {
        _ = os.SetWindowPos(drag_bar_hwnd, os.HWND_BOTTOM, 0, 0, 0, 0, os.SWP_HIDEWINDOW | os.SWP_NOMOVE | os.SWP_NOSIZE | os.SWP_NOSENDCHANGING);
    }
}

// ---------------------------------------------------------------------------
// Helpers — WT: _GetTopBorderHeight, _GetResizeHandleHeight
// ---------------------------------------------------------------------------

/// WT: _GetTopBorderHeight — returns topBorderVisibleHeight (1) normally,
/// 0 when maximized or fullscreen.
pub fn getTopBorderHeight(hwnd: os.HWND) c_int {
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
        log.err("createDragBarWindow: GetModuleHandleW returned null", .{});
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
                log.debug("createDragBarWindow: class already registered (1410), continuing", .{});
            } else {
                log.err("createDragBarWindow: RegisterClassExW failed err={}", .{reg_err});
                return null;
            }
        } else {
            log.debug("createDragBarWindow: class registered atom={}", .{atom});
        }
        drag_bar_class_registered = true;
    }

    // WT: WS_EX_LAYERED | WS_EX_NOREDIRECTIONBITMAP.
    // NOREDIRECTIONBITMAP = no surface → DWM sees through (visually transparent).
    // Combined with alpha=255 → window is opaque to hit testing but invisible.
    const hwnd = os.CreateWindowExW(
        os.WS_EX_LAYERED | os.WS_EX_NOREDIRECTIONBITMAP,
        DRAG_BAR_CLASS_NAME,
        EMPTY_WINDOW_NAME,
        os.WS_CHILD | os.WS_VISIBLE,
        0, 0, 0, 0,
        self.island.hwnd,
        null,
        hinstance,
        @ptrCast(self),
    ) orelse {
        log.err("createDragBarWindow: FAILED err={} — check supportedOS in manifest", .{os.GetLastError()});
        return null;
    };
    // WT: alpha=255 (opaque to hit testing). NOREDIRECTIONBITMAP makes it
    // visually transparent since DWM has no surface to composite.
    _ = os.SetLayeredWindowAttributes(hwnd, 0, 255, os.LWA_ALPHA);
    _ = os.SetWindowPos(hwnd, os.HWND_TOP, 0, 0, 0, 0, os.SWP_NOMOVE | os.SWP_NOSIZE | os.SWP_NOACTIVATE);
    log.info("createDragBarWindow: OK hwnd=0x{x} (LAYERED visible child)", .{@intFromPtr(hwnd)});

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
            log.debug("dragBarWndProc: WM_NCCREATE hwnd=0x{x} nci=0x{x}", .{ @intFromPtr(hwnd), @intFromPtr(nci_ptr) });
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
    _ = self;
    if (msg == os.WM_NCHITTEST or msg == os.WM_NCLBUTTONDOWN or msg == os.WM_NCLBUTTONDBLCLK or msg == os.WM_NCLBUTTONUP) {
        std.debug.print("DEBUG inputSink: msg=0x{x} wparam=0x{x}\n", .{ msg, @as(usize, @bitCast(wparam)) });
    }

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
/// Right-portion drag bar: returns HT*BUTTON for caption buttons,
/// HTTOP for resize handle, HTCAPTION for everything else in the drag bar.
fn dragBarNcHitTest(hwnd: os.HWND, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const pt = os.POINT{
        .x = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp))))),
        .y = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp >> 16))))),
    };

    const parent = os.GetAncestor(hwnd, os.GA_PARENT) orelse return os.HTCAPTION;
    var parent_rect: os.RECT = .{};
    _ = os.GetWindowRect(parent, &parent_rect);

    const dpi = os.GetDpiForWindow(parent);
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    const button_zone: c_int = @intFromFloat(@as(f32, @floatFromInt(CAPTION_BUTTON_ZONE_96DPI)) * scale);
    const button_w = @divFloor(button_zone, 3);

    // WT: rightBorder = rcParent.right - nonClientFrame.right
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

    // DwmDefWindowProc handles DWM caption button rendering/hit-testing.
    // We use XAML caption buttons (via caption_buttons.zig) instead, so
    // skip DwmDefWindowProc for WM_NCHITTEST to prevent DWM from drawing
    // its own buttons that conflict with the DXWS visual layer.
    if (msg != os.WM_NCHITTEST) {
        var dwm_result: os.LRESULT = 0;
        if (os.DwmDefWindowProc(hwnd, msg, wparam, lparam, &dwm_result) != 0) {
            return dwm_result;
        }
    }

    // WT: NonClientIslandWindow::MessageHandler
    switch (msg) {
        os.WM_NCCALCSIZE => return onNcCalcSize(hwnd, wparam, lparam),
        os.WM_NCHITTEST => return onNcHitTest(hwnd, lparam),

        os.WM_PAINT => {
            // WT: _OnPaint — paint titlebar with alpha=255 so DWM can
            // composite caption buttons on top of the glass frame.
            var ps: os.PAINTSTRUCT = .{};
            const hdc = os.BeginPaint(hwnd, &ps);
            if (hdc) |dc| {
                const top_h = getTopBorderHeight(hwnd);

                // 1) Top border: 1px black (same as WT).
                if (ps.rcPaint.top < top_h) {
                    var rc_top = ps.rcPaint;
                    rc_top.bottom = top_h;
                    if (os.GetStockObject(os.BLACK_BRUSH)) |brush| {
                        _ = os.FillRect(dc, &rc_top, brush);
                    }
                }

                // 2) Rest of titlebar: BufferedPaint with alpha=255.
                // Without this, DWM caption buttons disappear on resize.
                if (ps.rcPaint.bottom > top_h) {
                    var rc_rest = ps.rcPaint;
                    rc_rest.top = top_h;

                    var params = os.BP_PAINTPARAMS{
                        .dwFlags = os.BPPF_NOCLIP | os.BPPF_ERASE,
                    };
                    var opaque_dc: ?os.HDC = null;
                    const buf = os.BeginBufferedPaint(dc, &rc_rest, os.BPBF_TOPDOWNDIB, &params, &opaque_dc);
                    if (buf) |bp| {
                        if (opaque_dc) |odc| {
                            if (os.GetStockObject(os.BLACK_BRUSH)) |brush| {
                                _ = os.FillRect(odc, &rc_rest, brush);
                            }
                        }
                        _ = os.BufferedPaintSetAlpha(bp, null, 255);
                        _ = os.EndBufferedPaint(bp, 1);
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
