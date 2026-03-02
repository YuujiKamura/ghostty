/// Dedicated input HWND — bypasses WinUI3's TSF input stack.
///
/// Extracted from App.zig — provides a transparent child window that receives
/// keyboard focus and all IME messages, bypassing WinUI3's TSF layer entirely.
const std = @import("std");
const os = @import("os.zig");
const input = @import("../../input.zig");
const App = @import("App.zig");
const ime = @import("ime.zig");

const log = std.log.scoped(.winui3);

/// Window class name for our input overlay (UTF-16LE, null-terminated).
const INPUT_CLASS_NAME = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyInputOverlay");

/// Whether the input window class has been registered.
var input_class_registered: bool = false;

/// Create a transparent child HWND for keyboard/IME input.
/// This HWND is a standard Win32 window (not part of WinUI3's XAML tree)
/// so it receives IME messages via the legacy IMM32 path without TSF interference.
pub fn createInputWindow(parent: os.HWND, app_ptr: usize) ?os.HWND {
    // Register the window class once.
    if (!input_class_registered) {
        const wc = os.WNDCLASSEXW{
            .style = 0,
            .lpfnWndProc = &inputWndProc,
            .hInstance = os.GetModuleHandleW(null) orelse return null,
            .lpszClassName = INPUT_CLASS_NAME,
        };
        const atom = os.RegisterClassExW(&wc);
        if (atom == 0) {
            log.err("createInputWindow: RegisterClassExW failed", .{});
            return null;
        }
        input_class_registered = true;
    }

    // Get parent client rect for initial size.
    var rc: os.RECT = .{};
    _ = os.GetClientRect(parent, &rc);

    const hinstance = os.GetModuleHandleW(null) orelse return null;

    const hwnd = os.CreateWindowExW(
        0, // no WS_EX_TRANSPARENT — we want this window to receive mouse clicks
        INPUT_CLASS_NAME,
        INPUT_CLASS_NAME, // window name (unused)
        os.WS_CHILD | os.WS_VISIBLE, // child, visible
        0,
        0,
        rc.right - rc.left,
        rc.bottom - rc.top,
        parent,
        null,
        hinstance,
        null,
    );
    if (hwnd) |h| {
        // Store the App pointer in GWLP_USERDATA for the wndproc.
        _ = os.SetWindowLongPtrW(h, os.GWLP_USERDATA, app_ptr);
        return h;
    }
    log.err("createInputWindow: CreateWindowExW failed", .{});
    return null;
}

/// Window procedure for the dedicated input HWND.
/// Handles keyboard, IME, and mouse messages. Forwards everything else to DefWindowProc.
pub fn inputWndProc(
    hwnd: os.HWND,
    msg: os.UINT,
    wparam: os.WPARAM,
    lparam: os.LPARAM,
) callconv(.winapi) os.LRESULT {
    const app_ptr = os.GetWindowLongPtrW(hwnd, os.GWLP_USERDATA);
    if (app_ptr == 0) return os.DefWindowProcW(hwnd, msg, wparam, lparam);
    const app: *App = @ptrFromInt(app_ptr);

    switch (msg) {
        os.WM_KEYDOWN, os.WM_SYSKEYDOWN => {
            if (app.activeSurface()) |surface| {
                const wp: usize = @bitCast(wparam);
                surface.handleKeyEvent(@truncate(wp), true);
            }
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_KEYUP, os.WM_SYSKEYUP => {
            if (app.activeSurface()) |surface| {
                const wp: usize = @bitCast(wparam);
                surface.handleKeyEvent(@truncate(wp), false);
            }
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_CHAR => {
            if (app.activeSurface()) |surface| {
                const wp: usize = @bitCast(wparam);
                surface.handleCharEvent(@truncate(wp));
            }
            // Do NOT call DefWindowProcW for WM_CHAR — we consumed it.
            return 0;
        },
        os.WM_IME_STARTCOMPOSITION => return ime.handleIMEStartComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_COMPOSITION => return ime.handleIMEComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_ENDCOMPOSITION => return ime.handleIMEEndComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_SETCONTEXT => {
            // Let the system draw the default IME UI (candidate window etc.)
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_IME_NOTIFY => {
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_MOUSEMOVE => {
            if (app.activeSurface()) |surface| {
                const lp: usize = @bitCast(lparam);
                const x: i16 = @bitCast(@as(u16, @truncate(lp)));
                const y: i16 = @bitCast(@as(u16, @truncate(lp >> 16)));
                surface.handleMouseMove(@floatFromInt(x), @floatFromInt(y));
            }
            return 0;
        },
        os.WM_LBUTTONDOWN => {
            // Ensure we keep focus when clicked.
            _ = os.SetFocus(hwnd);
            if (app.activeSurface()) |surface| surface.handleMouseButton(.left, .press);
            return 0;
        },
        os.WM_RBUTTONDOWN => {
            if (app.activeSurface()) |surface| surface.handleMouseButton(.right, .press);
            return 0;
        },
        os.WM_MBUTTONDOWN => {
            if (app.activeSurface()) |surface| surface.handleMouseButton(.middle, .press);
            return 0;
        },
        os.WM_LBUTTONUP => {
            if (app.activeSurface()) |surface| surface.handleMouseButton(.left, .release);
            return 0;
        },
        os.WM_RBUTTONUP => {
            if (app.activeSurface()) |surface| surface.handleMouseButton(.right, .release);
            return 0;
        },
        os.WM_MBUTTONUP => {
            if (app.activeSurface()) |surface| surface.handleMouseButton(.middle, .release);
            return 0;
        },
        os.WM_MOUSEWHEEL => {
            if (app.activeSurface()) |surface| {
                const wp: usize = @bitCast(wparam);
                const delta: i16 = @bitCast(@as(u16, @truncate(wp >> 16)));
                const offset = @as(f64, @floatFromInt(delta)) / 120.0;
                surface.handleScroll(0, offset);
            }
            return 0;
        },
        os.WM_MOUSEHWHEEL => {
            if (app.activeSurface()) |surface| {
                const wp: usize = @bitCast(wparam);
                const delta: i16 = @bitCast(@as(u16, @truncate(wp >> 16)));
                const offset = @as(f64, @floatFromInt(delta)) / 120.0;
                surface.handleScroll(offset, 0);
            }
            return 0;
        },
        os.WM_PAINT => {
            // Validate the paint region so Windows doesn't keep sending WM_PAINT.
            var ps: os.PAINTSTRUCT = .{};
            _ = os.BeginPaint(hwnd, &ps);
            _ = os.EndPaint(hwnd, &ps);
            return 0;
        },
        os.WM_ERASEBKGND => return 1, // Don't erase — transparent overlay.
        os.WM_SETFOCUS => {
            log.info("inputWndProc: WM_SETFOCUS received on input HWND=0x{x}", .{@intFromPtr(hwnd)});
            if (app.activeSurface()) |surface| {
                surface.core_surface.focusCallback(true) catch |err| {
                    log.warn("focusCallback(true) error: {}", .{err});
                };
            }
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_KILLFOCUS => {
            log.info("inputWndProc: WM_KILLFOCUS on input HWND=0x{x}, new focus=0x{x}", .{ @intFromPtr(hwnd), wparam });
            if (app.activeSurface()) |surface| {
                surface.core_surface.focusCallback(false) catch |err| {
                    log.warn("focusCallback(false) error: {}", .{err});
                };
            }
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        else => {},
    }

    return os.DefWindowProcW(hwnd, msg, wparam, lparam);
}

/// Convert a UTF-16LE slice to UTF-8 in a destination buffer.
/// Returns the number of UTF-8 bytes written. Stops on invalid data or buffer overflow.
pub fn imeUtf16ToUtf8(dest: []u8, src: []const u16) usize {
    var dest_i: usize = 0;
    var src_i: usize = 0;
    while (src_i < src.len) {
        const cp: u21 = blk: {
            const high = src[src_i];
            if (high >= 0xD800 and high <= 0xDBFF) {
                // High surrogate — need a low surrogate next.
                src_i += 1;
                if (src_i >= src.len) return dest_i;
                const low = src[src_i];
                if (low < 0xDC00 or low > 0xDFFF) return dest_i;
                break :blk @as(u21, high - 0xD800) * 0x400 + @as(u21, low - 0xDC00) + 0x10000;
            } else if (high >= 0xDC00 and high <= 0xDFFF) {
                // Lone low surrogate — invalid.
                return dest_i;
            } else {
                break :blk @as(u21, high);
            }
        };
        src_i += 1;
        const len = std.unicode.utf8CodepointSequenceLength(cp) catch return dest_i;
        if (dest_i + len > dest.len) return dest_i;
        _ = std.unicode.utf8Encode(cp, dest[dest_i..][0..len]) catch return dest_i;
        dest_i += len;
    }
    return dest_i;
}
