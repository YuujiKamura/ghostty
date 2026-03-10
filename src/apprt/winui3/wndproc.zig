const std = @import("std");
const os = @import("os.zig");
const App = @import("App.zig");
const Surface = @import("Surface.zig");
const ime = @import("ime.zig");
const input_runtime = @import("input_runtime.zig");

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
    _: usize,
    ref_data: usize,
) callconv(.winapi) os.LRESULT {
    const app: *App = @ptrFromInt(ref_data);

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
        os.WM_NCHITTEST => return titleBarHitTest(hwnd, lparam),
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
        os.WM_KEYDOWN, os.WM_SYSKEYDOWN => return handleKeyInput(app, hwnd, msg, wparam, lparam, true),
        os.WM_KEYUP, os.WM_SYSKEYUP => return handleKeyInput(app, hwnd, msg, wparam, lparam, false),
        os.WM_CHAR => return handleChar(app, hwnd, msg, wparam, lparam),
        os.WM_PAINT => return handlePaint(hwnd, msg, wparam, lparam),
        os.WM_ERASEBKGND => return 1,
        os.WM_DPICHANGED => return handleDpiChanged(app, hwnd, msg, wparam, lparam),
        os.WM_USER => return handleWakeup(app, hwnd, msg, wparam, lparam),
        os.WM_APP_BIND_SWAP_CHAIN => return handleBindSwapChain(app, wparam, lparam),
        os.WM_APP_BIND_SWAP_CHAIN_HANDLE => return handleBindSwapChainHandle(app, wparam, lparam),
        // IME messages only handled in subclass as fallback (when input_hwnd failed).
        // When input_hwnd is active, IME messages go directly to inputWndProc.
        os.WM_IME_STARTCOMPOSITION => return ime.handleIMEStartComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_COMPOSITION => return ime.handleIMEComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_ENDCOMPOSITION => return ime.handleIMEEndComposition(app, hwnd, msg, wparam, lparam),
        os.WM_SETFOCUS => {
            // Restore whichever keyboard target currently owns text input.
            log.info("subclassProc: WM_SETFOCUS on HWND=0x{x}, restoring keyboard focus target={s}", .{
                @intFromPtr(hwnd),
                @tagName(app.keyboard_focus_target),
            });
            input_runtime.restoreDesiredKeyboardTarget(app);
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
        if (app.activeSurface()) |surface| surface.updateSize(sz.width, sz.height);
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
        if (app.activeSurface()) |surface| surface.updateSize(sz.width, sz.height);
        app.pending_size = null;
    }
    app.drainMailbox();
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleSize(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const width: u32 = @intCast(lp & 0xFFFF);
    const height: u32 = @intCast((lp >> 16) & 0xFFFF);
    if (app.resizing) {
        app.pending_size = .{ .width = width, .height = height };
    } else {
        if (app.activeSurface()) |surface| surface.updateSize(width, height);
    }
    // Keep input HWND as a tiny focus target; never cover the render surface.
    if (app.input_hwnd) |input_hwnd| {
        _ = os.MoveWindow(input_hwnd, 0, 0, 1, 1, 0);
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handlePaint(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    // Let WinUI 3 handle painting entirely via DefSubclassProc.
    // Do NOT call BeginPaint/EndPaint here — that would validate the
    // paint region and prevent WinUI 3's own rendering from running.
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleKeyInput(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM, pressed: bool) os.LRESULT {
    if (app.ime_composing) {
        return os.DefSubclassProc(hwnd, msg, wparam, lparam);
    }
    if (app.activeSurface()) |surface| {
        const wp: usize = @bitCast(wparam);
        surface.handleKeyEvent(@truncate(wp), pressed);
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleChar(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (app.activeSurface()) |surface| {
        const wp: usize = @bitCast(wparam);
        surface.handleCharEvent(@truncate(wp));
    }
    _ = hwnd;
    _ = msg;
    _ = lparam;
    return 0;
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

// ---------------------------------------------------------------
// DWM title bar hit-testing (Windows Terminal style)
// ---------------------------------------------------------------

/// DWM titlebar height in pixels at 96 DPI.
const TITLEBAR_HEIGHT_96DPI: c_int = 40;
/// Resize border width at 96 DPI.
const RESIZE_BORDER_96DPI: c_int = 6;
/// Caption button width at 96 DPI (Min/Max/Close each ~46px).
const CAPTION_BUTTON_WIDTH_96DPI: c_int = 46;

fn titleBarHitTest(hwnd: os.HWND, lparam: os.LPARAM) os.LRESULT {
    // Extract screen coordinates from lparam (sign-extended for multi-monitor).
    const lp: usize = @bitCast(lparam);
    const pt = os.POINT{
        .x = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp))))),
        .y = @as(c_int, @as(i16, @bitCast(@as(u16, @truncate(lp >> 16))))),
    };

    var rect: os.RECT = .{};
    _ = os.GetClientRect(hwnd, &rect);

    // Convert client rect to screen coords for comparison.
    var client_top_left = os.POINT{ .x = rect.left, .y = rect.top };
    var client_bottom_right = os.POINT{ .x = rect.right, .y = rect.bottom };
    _ = os.ClientToScreen(hwnd, &client_top_left);
    _ = os.ClientToScreen(hwnd, &client_bottom_right);

    // DPI-scale the titlebar height and resize border.
    const dpi = os.GetDpiForWindow(hwnd);
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    const titlebar_h: c_int = @intFromFloat(@as(f32, @floatFromInt(TITLEBAR_HEIGHT_96DPI)) * scale);
    const resize_border: c_int = @intFromFloat(@as(f32, @floatFromInt(RESIZE_BORDER_96DPI)) * scale);
    const button_w: c_int = @intFromFloat(@as(f32, @floatFromInt(CAPTION_BUTTON_WIDTH_96DPI)) * scale);

    // Bottom resize border.
    if (pt.y >= client_bottom_right.y - resize_border) {
        if (pt.x < client_top_left.x + resize_border) return os.HTBOTTOMLEFT;
        if (pt.x >= client_bottom_right.x - resize_border) return os.HTBOTTOMRIGHT;
        return os.HTBOTTOM;
    }

    // Top resize border (above the titlebar content area).
    if (pt.y >= client_top_left.y and pt.y < client_top_left.y + resize_border) {
        if (pt.x < client_top_left.x + resize_border) return os.HTTOPLEFT;
        if (pt.x >= client_bottom_right.x - resize_border) return os.HTTOPRIGHT;
        return os.HTTOP;
    }

    // Left resize border.
    if (pt.x < client_top_left.x + resize_border) return os.HTLEFT;

    // Right resize border.
    if (pt.x >= client_bottom_right.x - resize_border) return os.HTRIGHT;

    // Titlebar region: between top resize border and titlebar bottom.
    if (pt.y >= client_top_left.y + resize_border and pt.y < client_top_left.y + titlebar_h) {
        // Caption buttons area (right side): Close / Maximize / Minimize.
        // 3 buttons, each ~button_w wide, from right edge.
        const buttons_left = client_bottom_right.x - button_w * 3;
        if (pt.x >= buttons_left) {
            // Determine which button: rightmost = Close, then Max, then Min.
            if (pt.x >= client_bottom_right.x - button_w) return os.HTCLOSE;
            if (pt.x >= client_bottom_right.x - button_w * 2) return os.HTMAXBUTTON;
            return os.HTMINBUTTON;
        }
        // Everything else in the titlebar is draggable caption.
        return os.HTCAPTION;
    }

    // Below the titlebar: normal client area.
    return os.HTCLIENT;
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
