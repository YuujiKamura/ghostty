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
            .style = os.CS_HREDRAW | os.CS_VREDRAW,
            .lpfnWndProc = &inputWndProc,
            .hInstance = os.GetModuleHandleW(null) orelse return null,
            .hbrBackground = null, // Ensure NO background brush is used (transparent)
            .lpszClassName = INPUT_CLASS_NAME,
        };
        const atom = os.RegisterClassExW(&wc);
        if (atom == 0) {
            log.err("createInputWindow: RegisterClassExW failed", .{});
            return null;
        }
        input_class_registered = true;
    }

    const hinstance = os.GetModuleHandleW(null) orelse return null;

    // Use WS_EX_TRANSPARENT to pass mouse events through.
    // Removed WS_EX_LAYERED as it can cause failures for child windows on some Windows versions
    // when combined with certain parent window styles.
    const hwnd = os.CreateWindowExW(
        os.WS_EX_TRANSPARENT,
        INPUT_CLASS_NAME,
        INPUT_CLASS_NAME,
        os.WS_CHILD | os.WS_VISIBLE,
        0,
        0,
        1,
        1,
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

    const err = os.GetLastError();
    log.err("INPUT_OVERLAY_FATAL: CreateWindowExW failed, parent=0x{x}, error=0x{x}", .{ @intFromPtr(parent), err });
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

    // input_hwnd only handles IME messages. Keyboard, mouse, and focus
    // events are handled via XAML events on the SwapChainPanel.
    switch (msg) {
        os.WM_KEYDOWN, os.WM_SYSKEYDOWN => {
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_KEYUP, os.WM_SYSKEYUP => {
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_CHAR => {
            // IME commit text arrives as WM_CHAR on input_hwnd.
            const wp: usize = @bitCast(wparam);
            if (app.activeSurface()) |surface| {
                surface.handleCharEvent(@truncate(wp));
            }
            return 0;
        },
        os.WM_IME_STARTCOMPOSITION => return ime.handleIMEStartComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_COMPOSITION => return ime.handleIMEComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_ENDCOMPOSITION => return ime.handleIMEEndComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_SETCONTEXT => {
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_IME_NOTIFY => {
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_PAINT => {
            var ps: os.PAINTSTRUCT = .{};
            _ = os.BeginPaint(hwnd, &ps);
            _ = os.EndPaint(hwnd, &ps);
            return 0;
        },
        os.WM_ERASEBKGND => return 1,
        os.WM_SETFOCUS => {
            log.info("inputWndProc: WM_SETFOCUS received on input HWND=0x{x} (IME mode)", .{@intFromPtr(hwnd)});
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_KILLFOCUS => {
            log.info("inputWndProc: WM_KILLFOCUS on input HWND=0x{x} (IME mode)", .{@intFromPtr(hwnd)});
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

test "imeUtf16ToUtf8 conversion" {
    const testing = std.testing;
    var buf: [64]u8 = undefined;

    // ASCII
    const src1 = [_]u16{ 'h', 'e', 'l', 'l', 'o' };
    const len1 = imeUtf16ToUtf8(&buf, &src1);
    try testing.expectEqualStrings("hello", buf[0..len1]);

    // Japanese (Hiragana)
    const src2 = [_]u16{ 0x3042, 0x3044, 0x3046 }; // あいう
    const len2 = imeUtf16ToUtf8(&buf, &src2);
    try testing.expectEqualStrings("あいう", buf[0..len2]);

    // Emoji (Surrogate pair)
    const src3 = [_]u16{ 0xD83D, 0xDE00 }; // 😀
    const len3 = imeUtf16ToUtf8(&buf, &src3);
    try testing.expectEqualStrings("😀", buf[0..len3]);
}
