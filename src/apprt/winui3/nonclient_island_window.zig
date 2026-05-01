/// Custom titlebar window — Windows Terminal NonClientIslandWindow equivalent.
///
/// Extends IslandWindow with:
///   - DwmExtendFrameIntoClientArea (glass titlebar)
///   - WM_NCCALCSIZE (system titlebar removal)
///   - WM_NCHITTEST (resize borders + caption)
///   - Drag bar child window (input sink for titlebar mouse events)
///   - Dark mode + caption color via DWM attributes
///
// Ref: microsoft/terminal src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp#NonClientIslandWindow @ e4e3f08efca9 — custom titlebar via WM_NCCALCSIZE + DwmExtendFrameIntoClientArea + transparent drag-bar child HWND
const std = @import("std");
const os = @import("os.zig");
const IslandWindow = @import("island_window.zig");
const log = std.log.scoped(.winui3);

fn postMessageWarn(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM, msg_name: []const u8) bool {
    const result = os.PostMessageW(hwnd, msg, wparam, lparam);
    if (result == 0) {
        log.warn("PostMessageW failed msg={s} err={}", .{ msg_name, os.GetLastError() });
        return false;
    }
    return true;
}

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
var g_debug_dragbar: ?bool = null;

fn isDebugDragBarStatic() bool {
    if (g_debug_dragbar) |d| return d;
    const val = std.process.getEnvVarOwned(std.heap.page_allocator, "GHOSTTY_DEBUG_DRAGBAR") catch {
        g_debug_dragbar = false;
        return false;
    };
    defer std.heap.page_allocator.free(val);
    const d = std.mem.eql(u8, val, "1");
    g_debug_dragbar = d;
    return d;
}

// ---------------------------------------------------------------------------
// Construction — WT: NonClientIslandWindow::MakeWindow()
// Ref: microsoft/terminal src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp#MakeWindow @ e4e3f08efca9 — wrap IslandWindow + apply WS_CLIPCHILDREN so parent does not paint over the drag bar child HWND
// ---------------------------------------------------------------------------

pub fn init(self: *NonClientIslandWindow, app_ptr: *anyopaque) !void {
    self.* = .{
        .island = try IslandWindow.makeWindow(app_ptr, &nonclientWndProc),
        .drag_bar_hwnd = null,
    };

    // Add WS_CLIPCHILDREN to parent to ensure it doesn't paint over the drag bar.
    // Also add WS_CLIPSIBLINGS just in case.
    const hwnd = self.island.hwnd;
    const style = os.GetWindowLongPtrW(hwnd, os.GWL_STYLE);
    _ = os.SetWindowLongPtrW(hwnd, os.GWL_STYLE, style | os.WS_CLIPCHILDREN | os.WS_CLIPSIBLINGS);

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
        // WT: interop HWND stays at default z-order. The drag bar (HWND_TOP)
        // sits above it only where it's positioned (after tabs). The tab area
        // is not covered, so XAML receives input there directly.
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
// Ref: microsoft/terminal src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp#_UpdateFrameMargins @ e4e3f08efca9 — compute -frame.top via AdjustWindowRectExForDpi as the cyTopHeight margin for DwmExtendFrameIntoClientArea
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
// Ref: microsoft/terminal src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp#_OnNcCalcSize @ e4e3f08efca9 — let DefWindowProc compute borders, then restore original top to remove system titlebar; offset by resize-handle height when zoomed
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
// Ref: microsoft/terminal src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp#_OnNcHitTest @ e4e3f08efca9 — defer to DefWindowProc; only override HTCLIENT into HTTOP/HTCAPTION for resize handle and titlebar drag area
// ---------------------------------------------------------------------------

pub fn onNcHitTest(hwnd: os.HWND, lparam: os.LPARAM) os.LRESULT {
    const App = @import("App.zig");

    const original_ret = os.DefWindowProcW(hwnd, os.WM_NCHITTEST, 0, lparam);
    if (original_ret != os.HTCLIENT) {
        return original_ret;
    }

    const lp: usize = @bitCast(lparam);
    const mouse_x = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp)))));
    const mouse_y = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp >> 16)))));

    var wrect: os.RECT = .{};
    _ = os.GetWindowRect(hwnd, &wrect);

    const resize_h = getResizeHandleHeight(hwnd);
    if (os.IsZoomed(hwnd) == 0 and mouse_y < wrect.top + resize_h) {
        return os.HTTOP;
    }

    // Tab area: return HTCLIENT so clicks reach the XAML island.
    // Drag area (after tabs): return HTCAPTION for window dragging.
    const app_ptr_raw = os.GetWindowLongPtrW(hwnd, os.GWLP_USERDATA);
    if (app_ptr_raw != 0) {
        const app: *App = @ptrFromInt(@as(usize, @bitCast(app_ptr_raw)));
        if (app.nci_window) |nci| {
            const tab_right = nci.getDragAreaLeft();
            if (mouse_x < wrect.left + tab_right) {
                return os.HTCLIENT;
            }
        }
    }

    return os.HTCAPTION;
}

// ---------------------------------------------------------------------------
// Island positioning — WT: _UpdateIslandPosition
// Ref: microsoft/terminal src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp#_UpdateIslandPosition @ e4e3f08efca9 — shift the XAML island down by topBorderHeight so the 1px top stripe is reserved for resize / Fitt's Law
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

    // Position interop HWND. Don't force HWND_BOTTOM — the drag bar
    // only covers the area after tabs (HWND_TOP), so the tab region
    // needs XAML island to receive input at its natural z-order.
    _ = os.SetWindowPos(
        ih,
        null,
        0,
        top_offset,
        width,
        content_height,
        os.SWP_SHOWWINDOW | os.SWP_NOACTIVATE | os.SWP_NOZORDER,
    );

    // Resize drag bar to match new width.
    log.debug("updateIslandPosition: width={} height={} top_offset={} interop=0x{x}", .{ width, height, top_offset, @intFromPtr(ih) });
    self.resizeDragBarWindow(width);
}

/// WT: _ResizeDragBarWindow + _GetDragAreaRect
/// Positions drag bar at HWND_TOP, starting from the tab area's right edge
/// so that tabs receive XAML input directly (no HTTRANSPARENT needed).
pub fn resizeDragBarWindow(self: *NonClientIslandWindow, width_px: c_int) void {
    const drag_bar_hwnd = self.drag_bar_hwnd orelse return;
    const top_offset = getTopBorderHeight(self.island.hwnd);

    const dpi = os.GetDpiForWindow(self.island.hwnd);
    var frame: os.RECT = .{};
    const style = os.GetWindowLongPtrW(self.island.hwnd, os.GWL_STYLE);
    _ = os.AdjustWindowRectExForDpi(&frame, @truncate(@as(usize, @bitCast(style))), 0, 0, dpi);
    const titlebar_h: c_int = -frame.top;

    // WT: _GetDragAreaRect — compute tab area right edge via XAML layout.
    // Drag bar starts AFTER the tabs so tabs receive input directly.
    const tab_right_px = self.getDragAreaLeft();

    // WT: drag bar ends before the DWM caption buttons (right-aligned).
    // Subtract frame border + caption button zone so drag bar doesn't
    // cover the DWM-rendered Min/Max/Close buttons.
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    const caption_buttons_w: c_int = @intFromFloat(@as(f32, @floatFromInt(CAPTION_BUTTON_ZONE_96DPI)) * scale);
    const border_w = os.GetSystemMetricsForDpi(os.SM_CXSIZEFRAME, dpi) +
        os.GetSystemMetricsForDpi(os.SM_CXPADDEDBORDER, dpi);

    log.debug("resizeDragBarWindow: width={} titlebar_h={} tab_right={} caption_w={} top_offset={}", .{
        width_px, titlebar_h, tab_right_px, caption_buttons_w, top_offset,
    });

    const drag_width = width_px - tab_right_px - caption_buttons_w - border_w;
    if (drag_width > 0 and titlebar_h > 0) {
        _ = os.SetWindowPos(
            drag_bar_hwnd,
            os.HWND_TOP,
            tab_right_px,
            top_offset,
            drag_width,
            titlebar_h,
            os.SWP_NOACTIVATE | os.SWP_SHOWWINDOW | os.SWP_NOSENDCHANGING,
        );

        const debug_dragbar = self.isDebugDragBar();
        if (debug_dragbar) {
            _ = os.SetLayeredWindowAttributes(drag_bar_hwnd, 0, 180, os.LWA_ALPHA);
        } else {
            _ = os.SetLayeredWindowAttributes(drag_bar_hwnd, 0, 255, os.LWA_ALPHA);
        }
    } else {
        _ = os.SetWindowPos(drag_bar_hwnd, os.HWND_BOTTOM, 0, 0, 0, 0, os.SWP_HIDEWINDOW | os.SWP_NOMOVE | os.SWP_NOSIZE | os.SWP_NOSENDCHANGING);
    }
}

/// WT: _GetDragAreaRect().X — returns the left edge of the drag area in pixels.
/// Uses DragBar XAML element's TransformToVisual to find where tabs end.
/// DragBar is in Column 1 (Width="*") next to TabView in Column 0 (Width="Auto").
pub fn getDragAreaLeft(self: *NonClientIslandWindow) c_int {
    const App = @import("App.zig");
    const com = @import("com.zig");

    const app_ptr_raw = os.GetWindowLongPtrW(self.island.hwnd, os.GWLP_USERDATA);
    if (app_ptr_raw == 0) return 0;
    const app: *App = @ptrFromInt(@as(usize, @bitCast(app_ptr_raw)));

    const drag_bar = app.drag_bar orelse return 0;
    const root_grid = app.root_grid orelse return 0;

    const root_ui: *com.IUIElement = com.comQueryInterface(root_grid, com.IUIElement) catch return 0;
    defer com.comRelease(root_ui);

    // WT: _dragBar.TransformToVisual(_rootGrid)
    const transform = drag_bar.TransformToVisual(@ptrCast(root_ui)) catch return 0;
    defer transform.release();

    const origin = transform.TransformPoint(.{ .X = 0, .Y = 0 }) catch return 0;

    const dpi = os.GetDpiForWindow(self.island.hwnd);
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    return @intFromFloat(origin.X * scale);
}

// ---------------------------------------------------------------------------
// Helpers — WT: _GetTopBorderHeight, _GetResizeHandleHeight
// Ref: microsoft/terminal src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp#_GetTopBorderHeight @ e4e3f08efca9 — return topBorderVisibleHeight (1) when normal, 0 when maximized/fullscreen
// Ref: microsoft/terminal src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp#_GetResizeHandleHeight @ e4e3f08efca9 — SM_CXPADDEDBORDER + SM_CYSIZEFRAME at the window's DPI
// ---------------------------------------------------------------------------

fn isDebugDragBar(self: *const NonClientIslandWindow) bool {
    _ = self;
    return isDebugDragBarStatic();
}

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
// Ref: microsoft/terminal src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp#MakeWindow @ e4e3f08efca9 — register a private wndclass for the transparent drag-bar child HWND (cbWndExtra = sizeof(NonClientIslandWindow*)) sitting at HWND_TOP over the titlebar
// ---------------------------------------------------------------------------

fn createDragBarWindow(self: *NonClientIslandWindow) ?os.HWND {
    const hinstance = os.GetModuleHandleW(null) orelse {
        log.err("createDragBarWindow: GetModuleHandleW returned null", .{});
        return null;
    };

    // WT: static lambda registers class once with CS_DBLCLKS,
    // cbWndExtra = sizeof(NonClientIslandWindow*).
    // Debug: hot pink brush so drag bar coverage is visible.
    if (!drag_bar_class_registered) {
        const debug = isDebugDragBarStatic();
        const bg_brush = if (debug) os.CreateSolidBrush(0x00B469FF) else os.GetStockObject(os.BLACK_BRUSH);
        const wc = os.WNDCLASSEXW{
            .style = os.CS_HREDRAW | os.CS_VREDRAW | os.CS_DBLCLKS,
            .lpfnWndProc = &dragBarStaticWndProc,
            .cbWndExtra = @sizeOf(usize), // WT: sizeof(NonClientIslandWindow*)
            .hInstance = hinstance,
            .hCursor = os.LoadCursorW(null, os.IDC_ARROW),
            .hbrBackground = bg_brush,
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

    // Debug mode: GHOSTTY_DEBUG_DRAGBAR=1 makes drag bar visible (semi-transparent red).
    // Normal mode: NOREDIRECTIONBITMAP = no surface → visually transparent, opaque to hit testing.
    const debug_dragbar = self.isDebugDragBar();
    const ex_style: os.DWORD = if (debug_dragbar)
        os.WS_EX_LAYERED
    else
        os.WS_EX_LAYERED | os.WS_EX_NOREDIRECTIONBITMAP;

    const hwnd = os.CreateWindowExW(
        ex_style,
        DRAG_BAR_CLASS_NAME,
        EMPTY_WINDOW_NAME,
        os.WS_CHILD | os.WS_VISIBLE | os.WS_CLIPSIBLINGS,
        0,
        0,
        0,
        0,
        self.island.hwnd,
        null,
        hinstance,
        @ptrCast(self),
    ) orelse {
        log.err("createDragBarWindow: FAILED err={} — check supportedOS in manifest", .{os.GetLastError()});
        return null;
    };
    if (debug_dragbar) {
        // Semi-transparent so drag region is visible as a colored overlay
        _ = os.SetLayeredWindowAttributes(hwnd, 0, 180, os.LWA_ALPHA);
        log.info("createDragBarWindow: DEBUG MODE — drag bar visible (alpha=180)", .{});
    } else {
        _ = os.SetLayeredWindowAttributes(hwnd, 0, 255, os.LWA_ALPHA);
    }
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
        os.WM_PAINT => {
            if (isDebugDragBarStatic()) {
                var ps: os.PAINTSTRUCT = .{};
                if (os.BeginPaint(hwnd, &ps)) |hdc| {
                    var rect: os.RECT = .{};
                    _ = os.GetClientRect(hwnd, &rect);
                    const brush = os.CreateSolidBrush(0x00B469FF);
                    _ = os.FillRect(hdc, &rect, brush);
                    _ = os.DeleteObject(brush);
                    _ = os.EndPaint(hwnd, &ps);
                }
                return 0;
            }
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },

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
                    _ = postMessageWarn(parent, os.WM_SYSCOMMAND, os.SC_MINIMIZE, 0, "WM_SYSCOMMAND");
                    break :blk 0;
                },
                os.HTMAXBUTTON => blk: {
                    const sc: usize = if (os.IsZoomed(parent) != 0) os.SC_RESTORE else os.SC_MAXIMIZE;
                    _ = postMessageWarn(parent, os.WM_SYSCOMMAND, sc, 0, "WM_SYSCOMMAND");
                    break :blk 0;
                },
                os.HTCLOSE => blk: {
                    _ = postMessageWarn(parent, os.WM_SYSCOMMAND, os.SC_CLOSE, 0, "WM_SYSCOMMAND");
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
/// Full-width drag bar: returns HT*BUTTON for caption buttons,
/// HTTOP for resize handle, HTTRANSPARENT for tab area (left side),
/// HTCAPTION for everything else (draggable space between tabs and buttons).
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

    // Caption buttons (rightmost)
    if ((right_border - pt.x) < button_w) {
        return os.HTCLOSE;
    }
    if ((right_border - pt.x) < button_w * 2) {
        return os.HTMAXBUTTON;
    }
    if ((right_border - pt.x) < button_w * 3) {
        return os.HTMINBUTTON;
    }

    // Resize handle at top edge
    const resize_h = getResizeHandleHeight(parent);
    if (pt.y < parent_rect.top + resize_h and os.IsZoomed(parent) == 0) {
        return os.HTTOP;
    }

    // WT: not on a caption button or resize border → draggable caption area.
    // Tabs are not covered by the drag bar (getDragAreaLeft positions it after tabs),
    // so no HTTRANSPARENT needed — XAML receives tab input directly.
    return os.HTCAPTION;
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

    // DwmDefWindowProc handles DWM caption button rendering and hit-testing.
    // Skip WM_NCHITTEST so our custom onNcHitTest (drag bar + tab area logic)
    // takes precedence. DWM still renders buttons at the right edge via other
    // messages (WM_NCPAINT etc).
    if (msg != os.WM_NCHITTEST) {
        var dwm_result: os.LRESULT = 0;
        if (os.DwmDefWindowProc(hwnd, msg, wparam, lparam, &dwm_result) != 0) {
            return dwm_result;
        }
    }

    // Diagnostic logging for keyboard/IME messages (CRD debugging).
    if ((msg >= 0x0100 and msg <= 0x010F) or (msg >= 0x0280 and msg <= 0x0290)) {
        log.debug("nonclientWndProc: msg=0x{x:0>4} wparam=0x{x} lparam=0x{x}", .{ msg, wparam, lparam });
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
