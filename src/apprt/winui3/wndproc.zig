const std = @import("std");
const os = @import("os.zig");
const App = @import("App.zig");
const Surface = @import("Surface.zig");
const ime = @import("ime.zig");
const input_runtime = @import("input_runtime.zig");
const drag_bar = @import("drag_bar.zig");

const log = std.log.scoped(.winui3_wndproc);

const CONTEXT_MENU_NEW_TAB: usize = 1;
const CONTEXT_MENU_CLOSE_TAB: usize = 2;
const CONTEXT_MENU_PASTE: usize = 3;
const CONTEXT_MENU_CLOSE_WINDOW: usize = 4;
const CONTEXT_MENU_TOGGLE_TABVIEW: usize = 5;
const RESIZE_TIMER_ID: usize = 1;
const DEFERRED_TABVIEW_TIMER_ID: usize = 997;

/// Installed via SetWindowSubclass on the WinUI 3 window's HWND to intercept
/// input messages before WinUI 3's own window procedure processes them.
pub fn subclassProc(
    hwnd: os.HWND,
    msg: os.UINT,
    wparam: os.WPARAM,
    lparam: os.LPARAM,
    uid: usize,
    ref_data: usize,
) callconv(.winapi) os.LRESULT {
    const app: *App = @ptrFromInt(ref_data);

    // ---- Titlebar drag via WM_LBUTTONDOWN (uid=3: XAML island child) ----
    // WinUI3's DesktopChildSiteBridge processes mouse input via InputPointerSource,
    // bypassing standard WM_NCHITTEST dispatch. So HTTRANSPARENT has no effect on
    // real mouse input. Instead, intercept WM_LBUTTONDOWN on the XAML island and
    // initiate drag via SC_MOVE when the click is in the titlebar region.
    if (uid == 3 and (msg == os.WM_LBUTTONDOWN or msg == os.WM_LBUTTONDBLCLK)) {
        const parent_hwnd = app.hwnd orelse return os.DefSubclassProc(hwnd, msg, wparam, lparam);
        const in_titlebar = isInTitlebarRegion(parent_hwnd, lparam);
        const lp_dbg: usize = @bitCast(lparam);
        const cx_dbg = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp_dbg)))));
        const cy_dbg = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp_dbg >> 16)))));
        App.fileLog("uid=3 LBUTTONDOWN at ({},{}) inTitlebar={}", .{ cx_dbg, cy_dbg, @intFromBool(in_titlebar) });
        if (in_titlebar) {
            if (msg == os.WM_LBUTTONDBLCLK) {
                // Double-click: toggle maximize/restore.
                const sc = if (os.IsZoomed(parent_hwnd) != 0) os.SC_RESTORE else os.SC_MAXIMIZE;
                _ = os.SendMessageW(parent_hwnd, os.WM_SYSCOMMAND, @bitCast(@as(isize, @intCast(sc))), 0);
            } else {
                // Single click: start drag via SC_MOVE (0x0002 = mouse-initiated).
                _ = os.ReleaseCapture();
                _ = os.SendMessageW(parent_hwnd, os.WM_SYSCOMMAND, @bitCast(@as(isize, @intCast(os.SC_MOVE | 2))), 0);
            }
            return 0;
        }
    }

    // ---- WM_NCHITTEST (parent uid=0): resize borders + titlebar ----
    if (msg == os.WM_NCHITTEST and uid == 0) {
        var wrect: os.RECT = .{};
        _ = os.GetWindowRect(hwnd, &wrect);
        const lp: usize = @bitCast(lparam);
        const mouse_x = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp)))));
        const mouse_y = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp >> 16)))));

        const dpi = os.GetDpiForWindow(hwnd);
        const resize_h = os.GetSystemMetricsForDpi(os.SM_CXPADDEDBORDER, dpi) +
            os.GetSystemMetricsForDpi(os.SM_CYSIZEFRAME, dpi);

        // Top resize border
        if (mouse_y < wrect.top + resize_h) {
            if (mouse_x < wrect.left + resize_h) return os.HTTOPLEFT;
            if (mouse_x >= wrect.right - resize_h) return os.HTTOPRIGHT;
            return os.HTTOP;
        }
        // Bottom resize border
        if (mouse_y >= wrect.bottom - resize_h) {
            if (mouse_x < wrect.left + resize_h) return os.HTBOTTOMLEFT;
            if (mouse_x >= wrect.right - resize_h) return os.HTBOTTOMRIGHT;
            return os.HTBOTTOM;
        }
        // Left/right resize borders
        if (mouse_x < wrect.left + resize_h) return os.HTLEFT;
        if (mouse_x >= wrect.right - resize_h) return os.HTRIGHT;

        // Titlebar (for cursor + system menu)
        const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
        const titlebar_h: c_int = @intFromFloat(40.0 * scale);
        if (mouse_y < wrect.top + titlebar_h) {
            return os.HTCAPTION;
        }

        return os.DefSubclassProc(hwnd, msg, wparam, lparam);
    }

    // Other uid WM_NCHITTEST: passthrough.
    if (msg == os.WM_NCHITTEST and uid != 0) {
        return os.DefSubclassProc(hwnd, msg, wparam, lparam);
    }

    // For other messages, let DWM handle caption button rendering.
    var dwm_result: os.LRESULT = 0;
    if (os.DwmDefWindowProc(hwnd, msg, wparam, lparam, &dwm_result) != 0) {
        return dwm_result;
    }

    switch (msg) {
        os.WM_NCCALCSIZE => {
            if (wparam != 0) {
                // Windows Terminal style: let DefSubclassProc calculate the standard
                // non-client area, then restore the original top so the client area
                // extends into the titlebar while keeping left/right/bottom borders.
                // This preserves DWM-drawn caption buttons (Min/Max/Close).
                const params: *os.NCCALCSIZE_PARAMS = @ptrFromInt(@as(usize, @bitCast(lparam)));
                const original_top = params.rgrc[0].top;
                const ret = os.DefSubclassProc(hwnd, msg, wparam, lparam);
                params.rgrc[0].top = original_top;
                return ret;
            }
        },
        os.WM_CLOSE => {
            App.fileLog("WM_CLOSE received on HWND=0x{x}", .{@intFromPtr(hwnd)});
            app.requestCloseWindow();
            return 0;
        },
        os.WM_SYSCOMMAND => {
            const wp: usize = @bitCast(wparam);
            if ((wp & 0xFFF0) == os.SC_CLOSE) {
                app.requestCloseWindow();
                return 0;
            }
        },
        os.WM_COMMAND => return handleCommand(app, hwnd, msg, wparam, lparam),
        os.WM_ENTERSIZEMOVE => return handleEnterSizeMove(app, hwnd),
        os.WM_EXITSIZEMOVE => return handleExitSizeMove(app, hwnd),
        os.WM_TIMER => return handleTimer(app, hwnd, msg, wparam, lparam),
        os.WM_SIZE => return handleSize(app, hwnd, msg, wparam, lparam),
        // Keyboard/text input is owned by the hidden XAML TextBox. Do not
        // forward raw WM_KEY* traffic into input_hwnd or we duplicate input.
        os.WM_KEYDOWN, os.WM_SYSKEYDOWN, os.WM_KEYUP, os.WM_SYSKEYUP, os.WM_CHAR => {
            return os.DefSubclassProc(hwnd, msg, wparam, lparam);
        },
        os.WM_PAINT => return handlePaint(hwnd, msg, wparam, lparam),
        os.WM_ERASEBKGND => return 1,
        os.WM_DPICHANGED => return handleDpiChanged(app, hwnd, msg, wparam, lparam),
        os.WM_USER => return handleWakeup(app, hwnd, msg, wparam, lparam),
        os.WM_APP_BIND_SWAP_CHAIN => return handleBindSwapChain(app, wparam, lparam),
        os.WM_APP_BIND_SWAP_CHAIN_HANDLE => return handleBindSwapChainHandle(app, wparam, lparam),
        os.WM_APP_CONTROL_INPUT => return handleControlInput(app),
        os.WM_APP_CONTROL_ACTION => return handleControlAction(app, wparam, lparam),
        // IME messages only handled in subclass as fallback (when input_hwnd failed).
        // When input_hwnd is active, IME messages go directly to inputWndProc.
        os.WM_IME_STARTCOMPOSITION => return ime.handleIMEStartComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_COMPOSITION => return ime.handleIMEComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_ENDCOMPOSITION => return ime.handleIMEEndComposition(app, hwnd, msg, wparam, lparam),
        os.WM_SETFOCUS => {
            log.info("subclassProc: WM_SETFOCUS on HWND=0x{x} -> restoring ime_text_box focus", .{
                @intFromPtr(hwnd),
            });
            input_runtime.focusKeyboardTarget(app);
            return 0;
        },
        else => {},
    }

    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

// --- Individual message handlers ---

fn handleEnterSizeMove(app: *App, hwnd: os.HWND) os.LRESULT {
    app.resizing = true;
    _ = os.SetTimer(hwnd, RESIZE_TIMER_ID, 16, null);
    return 0;
}

fn handleExitSizeMove(app: *App, hwnd: os.HWND) os.LRESULT {
    _ = os.KillTimer(hwnd, RESIZE_TIMER_ID);
    app.resizing = false;
    if (app.pending_size) |sz| {
        // Set RootGrid size → triggers XAML layout → SwapChainPanel SizeChanged → sizeCallback.
        updateRootGridSize(app, hwnd, sz.width, sz.height);
        app.pending_size = null;
    }
    return 0;
}

fn handleTimer(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const wp: usize = @bitCast(wparam);
    if (wp == 999) {
        log.info("handleTimer: close_after_ms triggered, requesting close", .{});
        app.requestCloseWindow();
        return 0;
    }
    if (wp == 998) {
        log.info("handleTimer: close_tab_after_ms triggered, closing active tab", .{});
        app.closeActiveTab();
        return 0;
    }
    if (wp == DEFERRED_TABVIEW_TIMER_ID) {
        _ = os.KillTimer(hwnd, DEFERRED_TABVIEW_TIMER_ID);
        app.toggleTabViewContainer() catch {};
        return 0;
    }
    if (app.pending_size) |sz| {
        // Update RootGrid → XAML layout → SwapChainPanel SizeChanged → sizeCallback.
        updateRootGridSize(app, hwnd, sz.width, sz.height);
        app.pending_size = null;
    }
    app.drainMailbox();
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleSize(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const width: u32 = @intCast(lp & 0xFFFF);
    const height: u32 = @intCast((lp >> 16) & 0xFFFF);

    // Windows Terminal pattern: explicitly set RootGrid Width/Height in DIPs
    // on every WM_SIZE. Without this, XAML layout doesn't track the actual
    // window size, causing titlebar disappearance and scroll range issues.
    updateRootGridSize(app, hwnd, width, height);

    // During modal resize, defer RootGrid update until WM_EXITSIZEMOVE.
    // Otherwise, set RootGrid size immediately → XAML layout propagates to
    // SwapChainPanel SizeChanged → core_surface.sizeCallback().
    if (app.resizing) {
        app.pending_size = .{ .width = width, .height = height };
    }
    // Keep input HWND as a tiny focus target; never cover the render surface.
    if (app.input_hwnd) |input_hwnd| {
        _ = os.MoveWindow(input_hwnd, 0, 0, 1, 1, 0);
    }
    // Resize drag bar to cover the titlebar area.
    if (app.drag_bar_hwnd) |db| {
        drag_bar.resizeDragBar(db, hwnd, @intCast(width));
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

/// Convert pixel dimensions to DIPs and set RootGrid Width/Height.
/// Mirrors Windows Terminal's OnSize: `_rootGrid.Width(size.Width); _rootGrid.Height(size.Height);`
fn updateRootGridSize(app: *App, hwnd: os.HWND, width_px: u32, height_px: u32) void {
    const root_grid = app.root_grid orelse return;
    if (width_px == 0 or height_px == 0) return;

    const dpi = os.GetDpiForWindow(hwnd);
    const scale: f64 = if (dpi > 0) @as(f64, @floatFromInt(dpi)) / 96.0 else 1.0;
    const width_dips: f64 = @as(f64, @floatFromInt(width_px)) / scale;
    const height_dips: f64 = @as(f64, @floatFromInt(height_px)) / scale;

    const com = @import("com.zig");
    const fe = root_grid.queryInterface(com.IFrameworkElement) catch return;
    defer fe.release();
    fe.SetWidth(width_dips) catch {};
    fe.SetHeight(height_dips) catch {};
}

fn handlePaint(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    // Let WinUI 3 handle painting entirely via DefSubclassProc.
    // Do NOT call BeginPaint/EndPaint here — that would validate the
    // paint region and prevent WinUI 3's own rendering from running.
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

/// Fallback keyboard handler — only used if input_hwnd doesn't exist.
fn handleKeyInputFallback(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (msg == os.WM_CHAR) {
        if (app.activeSurface()) |surface| {
            const wp: usize = @bitCast(wparam);
            surface.handleCharEvent(@truncate(wp));
        }
        return 0;
    }
    const pressed = (msg == os.WM_KEYDOWN or msg == os.WM_SYSKEYDOWN);
    const wp: usize = @bitCast(wparam);
    if (app.activeSurface()) |surface| {
        surface.handleKeyEvent(@truncate(wp), pressed);
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn showContextMenu(app: *App, hwnd: os.HWND) void {
    const menu = os.CreatePopupMenu() orelse return;
    defer _ = os.DestroyMenu(menu);

    const new_tab = std.unicode.utf8ToUtf16LeStringLiteral("New Tab");
    const close_tab = std.unicode.utf8ToUtf16LeStringLiteral("Close Tab");
    const paste = std.unicode.utf8ToUtf16LeStringLiteral("Paste");
    const close_window = std.unicode.utf8ToUtf16LeStringLiteral("Close Window");
    const toggle_tabview = std.unicode.utf8ToUtf16LeStringLiteral("Toggle TabView Container");

    _ = os.AppendMenuW(menu, os.MF_STRING, CONTEXT_MENU_NEW_TAB, new_tab);
    _ = os.AppendMenuW(menu, os.MF_STRING, CONTEXT_MENU_CLOSE_TAB, close_tab);
    _ = os.AppendMenuW(menu, os.MF_SEPARATOR, 0, null);
    _ = os.AppendMenuW(menu, os.MF_STRING, CONTEXT_MENU_PASTE, paste);
    _ = os.AppendMenuW(menu, os.MF_STRING, CONTEXT_MENU_TOGGLE_TABVIEW, toggle_tabview);
    _ = os.AppendMenuW(menu, os.MF_SEPARATOR, 0, null);
    _ = os.AppendMenuW(menu, os.MF_STRING, CONTEXT_MENU_CLOSE_WINDOW, close_window);

    var pt: os.POINT = .{};
    if (os.GetCursorPos(&pt) == 0) return;

    const cmd = os.TrackPopupMenuEx(
        menu,
        os.TPM_RIGHTBUTTON | os.TPM_RETURNCMD,
        pt.x,
        pt.y,
        hwnd,
        null,
    );
    if (cmd == 0) return;
    handleContextCommand(app, @intCast(cmd));
}

pub fn showContextMenuAtCursor(app: *App) void {
    const hwnd = app.hwnd orelse return;
    showContextMenu(app, hwnd);
}

fn handleCommand(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const wp: usize = @bitCast(wparam);
    const cmd_id: usize = wp & 0xFFFF;
    switch (cmd_id) {
        CONTEXT_MENU_NEW_TAB,
        CONTEXT_MENU_CLOSE_TAB,
        CONTEXT_MENU_PASTE,
        CONTEXT_MENU_TOGGLE_TABVIEW,
        CONTEXT_MENU_CLOSE_WINDOW,
        => {
            handleContextCommand(app, cmd_id);
            return 0;
        },
        else => return os.DefSubclassProc(hwnd, msg, wparam, lparam),
    }
}

fn handleContextCommand(app: *App, cmd_id: usize) void {
    switch (cmd_id) {
        CONTEXT_MENU_NEW_TAB => {
            app.newTab() catch |err| log.warn("context menu new tab failed: {}", .{err});
        },
        CONTEXT_MENU_CLOSE_TAB => app.closeActiveTab(),
        CONTEXT_MENU_PASTE => {
            if (app.activeSurface()) |surface| {
                _ = surface.clipboardRequest(.standard, .{ .paste = {} }) catch {};
            }
        },
        CONTEXT_MENU_TOGGLE_TABVIEW => {
            app.toggleTabViewContainer() catch |err| {
                log.warn("context menu toggle tabview failed: {}", .{err});
            };
        },
        CONTEXT_MENU_CLOSE_WINDOW => app.requestCloseWindow(),
        else => {},
    }
}

fn handleDpiChanged(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (app.activeSurface()) |surface| surface.updateContentScale();
    // lparam points to the recommended new window rect from Windows.
    // Apply it so the window scales correctly on DPI change.
    const rect_ptr: ?*const os.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
    if (rect_ptr) |rect| {
        _ = os.SetWindowPos(
            hwnd,
            null,
            rect.left,
            rect.top,
            rect.right - rect.left,
            rect.bottom - rect.top,
            os.SWP_NOZORDER | os.SWP_NOACTIVATE,
        );
        // Resize drag bar for new DPI.
        if (app.drag_bar_hwnd) |db| {
            drag_bar.resizeDragBar(db, hwnd, rect.right - rect.left);
        }
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleWakeup(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    log.info("handleWakeup: drainMailbox...", .{});
    app.drainMailbox();
    log.info("handleWakeup: drainMailbox done", .{});
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

/// Handle WM_APP_BIND_SWAP_CHAIN: complete swap chain binding on the UI thread.
/// wparam carries the swap chain pointer, lparam carries the Surface pointer.
fn handleBindSwapChain(app: *App, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const surface: *Surface = @ptrFromInt(@as(usize, @bitCast(lparam)));
    const swap_chain: *anyopaque = @ptrFromInt(@as(usize, @bitCast(wparam)));

    // Drop stale bind requests that arrive after a surface was removed.
    var alive = false;
    for (app.surfaces.items) |s| {
        if (s == surface) {
            alive = true;
            break;
        }
    }
    if (!alive) {
        log.warn("handleBindSwapChain: drop stale surface ptr=0x{x}", .{@intFromPtr(surface)});
        return 0;
    }

    surface.completeBindSwapChain(swap_chain);
    return 0;
}

/// Handle WM_APP_BIND_SWAP_CHAIN_HANDLE: complete handle-based binding on the UI thread.
/// wparam carries the composition surface handle, lparam carries the Surface pointer.
fn handleBindSwapChainHandle(app: *App, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const surface: *Surface = @ptrFromInt(@as(usize, @bitCast(lparam)));
    const swap_chain_handle: usize = @as(usize, @bitCast(wparam));

    var alive = false;
    for (app.surfaces.items) |s| {
        if (s == surface) {
            alive = true;
            break;
        }
    }
    if (!alive) {
        log.warn("handleBindSwapChainHandle: drop stale surface ptr=0x{x}", .{@intFromPtr(surface)});
        return 0;
    }

    surface.completeBindSwapChainHandle(swap_chain_handle);
    return 0;
}

/// Handle WM_APP_CONTROL_INPUT: drain pending inputs from the control plane.
fn handleControlInput(app: *App) os.LRESULT {
    if (app.control_plane) |cp| {
        if (app.activeSurface()) |surface| {
            cp.drainPendingInputs(&surface.core_surface);
        }
    }
    return 0;
}

/// Handle WM_APP_CONTROL_ACTION: execute a tab/window action from the control plane.
fn handleControlAction(app: *App, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const ControlPlane = @import("control_plane.zig").ControlPlane;
    const action: ControlPlane.Action = @enumFromInt(@as(usize, @bitCast(wparam)));
    const param: usize = @bitCast(lparam);

    switch (action) {
        .new_tab => {
            app.newTab() catch |err| log.warn("control plane NEW_TAB failed: {}", .{err});
        },
        .close_tab => {
            if (param < app.surfaces.items.len) {
                app.closeTab(param);
            }
        },
        .switch_tab => {
            if (param < app.surfaces.items.len) {
                app.switchToTab(param);
            }
        },
        .focus_window => {
            if (app.hwnd) |hwnd| {
                _ = os.SetForegroundWindow(hwnd);
            }
        },
    }
    return 0;
}

/// Check if lparam (client-relative coordinates of the XAML island child) falls
/// within the titlebar region of the parent window.
fn isInTitlebarRegion(parent_hwnd: os.HWND, lparam: os.LPARAM) bool {
    // WM_LBUTTONDOWN lparam: client-relative x,y of the receiving window.
    // The XAML island child is positioned inside the parent, so its client (0,0)
    // maps to the parent's client origin. Use GetWindowRect for screen coords.
    const lp: usize = @bitCast(lparam);
    const client_y = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp >> 16)))));
    const client_x = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp)))));

    // The XAML island's client (0,0) ≈ parent's client (0,0).
    // Parent's client area starts at window top (because WM_NCCALCSIZE restores top).
    // So client_y directly corresponds to distance from window top.
    const dpi = os.GetDpiForWindow(parent_hwnd);
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    const titlebar_h: c_int = @intFromFloat(40.0 * scale);
    const button_zone: c_int = @intFromFloat(138.0 * scale);

    // Get parent window width to exclude caption button area.
    var wrect: os.RECT = .{};
    _ = os.GetWindowRect(parent_hwnd, &wrect);
    const win_width = wrect.right - wrect.left;

    return client_y < titlebar_h and client_x < win_width - button_zone;
}

// ---------------------------------------------------------------
// Vectored Exception Handler — capture STATUS_STOWED_EXCEPTION details
// ---------------------------------------------------------------

fn writeRaw(msg: []const u8) void {
    const K32 = std.os.windows.kernel32;
    const handle = K32.GetStdHandle(@bitCast(@as(i32, -12))); // STD_ERROR_HANDLE
    if (handle != std.os.windows.INVALID_HANDLE_VALUE and handle != null) {
        _ = K32.WriteFile(handle.?, msg.ptr, @intCast(msg.len), null, null);
    }
}

pub fn stowedExceptionHandler(info: *os.EXCEPTION_POINTERS) callconv(.winapi) c_long {
    const record = info.ExceptionRecord orelse return os.EXCEPTION_CONTINUE_SEARCH;
    const code = record.ExceptionCode;

    App.fileLog("VEH-filter-v2-active", .{});

    // Skip noisy, harmless exceptions to keep log readable.
    // 0xe06d7363 = C++ exception (normal WinRT), 0x406d1388 = thread naming, 0x40010006 = debug print
    if (code == 0xe06d7363 or code == 0x406d1388 or code == 0x40010006) return os.EXCEPTION_CONTINUE_SEARCH;

    const first_chance: bool = (record.ExceptionFlags & 1) == 0; // bit 0 = EXCEPTION_NONCONTINUABLE
    const thread_id = os.GetCurrentThreadId();
    const addr = @intFromPtr(record.ExceptionAddress);

    App.fileLog("=== VEH Exception ===", .{});
    App.fileLog("  Code=0x{x:0>8} Addr=0x{x} Thread={} Chance={s}", .{
        code, addr, thread_id, if (first_chance) "first" else "second/noncontinuable",
    });

    // For ACCESS_VIOLATION (0xc0000005): param[0]=read(0)/write(1)/DEP(8), param[1]=target address
    if (code == 0xc0000005 and record.NumberParameters >= 2) {
        const rw = record.ExceptionInformation[0];
        const target = record.ExceptionInformation[1];
        const rw_str = switch (rw) {
            0 => "READ",
            1 => "WRITE",
            8 => "DEP",
            else => "UNKNOWN",
        };
        App.fileLog("  ACCESS_VIOLATION: {s} at 0x{x}", .{ rw_str, target });
    }

    // Dump raw parameters for other exceptions
    if (code != 0xc0000005) {
        const n = @min(record.NumberParameters, 15);
        for (0..n) |i| {
            App.fileLog("  Param[{}]=0x{x}", .{ i, record.ExceptionInformation[i] });
        }
    }

    // Identify faulting module by enumerating loaded modules
    identifyFaultingModule(addr);

    // Capture stack back trace (top 16 frames)
    captureStackTrace();

    // STATUS_STOWED_EXCEPTION (0xC000027B) — parse stowed entries
    if (code == os.STATUS_STOWED_EXCEPTION) {
        App.fileLog("  === Stowed Exception Details ===", .{});
        if (record.NumberParameters >= 2) {
            const count = record.ExceptionInformation[0];
            const array_ptr = record.ExceptionInformation[1];
            if (count > 0 and count < 100 and array_ptr != 0) {
                const entries: [*]const usize = @ptrFromInt(array_ptr);
                for (0..count) |i| {
                    const entry_ptr = entries[i];
                    if (entry_ptr == 0) continue;
                    const entry: *const os.STOWED_EXCEPTION_INFORMATION_V2 = @ptrFromInt(entry_ptr);
                    App.fileLog("  Stowed[{}] HRESULT=0x{x} sig=0x{x} form={}", .{
                        i, @as(u32, @bitCast(entry.result_code)), entry.signature, entry.exception_form,
                    });
                }
            }
        }
    }

    App.fileLog("=== End VEH ===", .{});
    return os.EXCEPTION_CONTINUE_SEARCH;
}

/// Enumerate loaded modules to find which DLL contains the faulting address.
fn identifyFaultingModule(addr: usize) void {
    const K32 = std.os.windows.kernel32;
    const snap = os.CreateToolhelp32Snapshot(os.TH32CS_SNAPMODULE | os.TH32CS_SNAPMODULE32, 0);
    if (snap == std.os.windows.INVALID_HANDLE_VALUE) {
        App.fileLog("  Module: CreateToolhelp32Snapshot failed err={}", .{K32.GetLastError()});
        return;
    }
    defer _ = std.os.windows.ntdll.NtClose(snap);

    var me: os.MODULEENTRY32W = undefined;
    me.dwSize = @sizeOf(os.MODULEENTRY32W);

    if (os.Module32FirstW(snap, &me) == 0) return;

    while (true) {
        const base = @intFromPtr(me.modBaseAddr);
        const end = base + me.modBaseSize;
        if (addr >= base and addr < end) {
            // Found it — convert module name from UTF-16 to UTF-8
            var name_buf: [512]u8 = undefined;
            const name_len = std.unicode.utf16LeToUtf8(&name_buf, wideCStr(&me.szModule)) catch 0;
            const offset = addr - base;
            App.fileLog("  Module: {s} Base=0x{x} Offset=0x{x}", .{ name_buf[0..name_len], base, offset });
            return;
        }
        if (os.Module32NextW(snap, &me) == 0) break;
    }

    App.fileLog("  Module: UNKNOWN (addr 0x{x} not in any loaded module)", .{addr});
}

/// Get null-terminated length from a wide C string buffer.
fn wideCStr(buf: []const u16) []const u16 {
    for (buf, 0..) |c, i| {
        if (c == 0) return buf[0..i];
    }
    return buf;
}

/// Capture stack back trace and log frame addresses + module info.
fn captureStackTrace() void {
    var frames: [16]?*anyopaque = undefined;
    const count = os.RtlCaptureStackBackTrace(0, 16, &frames, null);
    if (count == 0) return;

    App.fileLog("  Stack ({} frames):", .{count});
    for (0..count) |i| {
        const frame_addr = @intFromPtr(frames[i]);
        App.fileLog("    [{:>2}] 0x{x}", .{ i, frame_addr });
    }
}

/// Unhandled exception filter — last resort before process termination.
pub fn unhandledExceptionFilter(info: *os.EXCEPTION_POINTERS) callconv(.winapi) c_long {
    App.fileLog("=== UNHANDLED EXCEPTION (last chance) ===", .{});
    _ = stowedExceptionHandler(info);
    return 0; // EXCEPTION_EXECUTE_HANDLER — let the process terminate
}
