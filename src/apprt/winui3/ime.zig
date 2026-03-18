/// IME (Input Method Editor) handlers for CJK text input.
///
/// Extracted from App.zig — handles WM_IME_STARTCOMPOSITION,
/// WM_IME_COMPOSITION, and WM_IME_ENDCOMPOSITION messages.
const std = @import("std");
const os = @import("os.zig");
const App = @import("../winui3_islands/App.zig");
const input_overlay = @import("input_overlay.zig");
const input_runtime = @import("input_runtime.zig");

const log = std.log.scoped(.winui3);

/// Dispatch to the correct default handler depending on whether hwnd is the
/// input overlay (plain wndproc) or a subclassed HWND.
pub inline fn imeDefProc(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (app.input_hwnd != null and app.input_hwnd.? == hwnd)
        return os.DefWindowProcW(hwnd, msg, wparam, lparam);
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

pub fn handleIMEStartComposition(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    log.info("IME: WM_IME_STARTCOMPOSITION on HWND=0x{x}", .{@intFromPtr(hwnd)});
    app.ime_composing = true;
    app.ime_last_had_result = false;
    if (app.activeSurface()) |surface| {
        if (surface.core_initialized) {
            const himc = os.ImmGetContext(hwnd) orelse
                return imeDefProc(app, hwnd, msg, wparam, lparam);
            defer _ = os.ImmReleaseContext(hwnd, himc);

            const ime_pos = surface.core_surface.imePoint();
            const cf = os.COMPOSITIONFORM{
                .dwStyle = os.CFS_POINT,
                .ptCurrentPos = .{
                    .x = @intFromFloat(ime_pos.x),
                    .y = @intFromFloat(ime_pos.y),
                },
                .rcArea = .{},
            };
            _ = os.ImmSetCompositionWindow(himc, &cf);
        }
    }
    return imeDefProc(app, hwnd, msg, wparam, lparam);
}

pub fn handleIMEComposition(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const lp_flags: u32 = @truncate(lp);
    log.info("IME: WM_IME_COMPOSITION flags=0x{X:0>8} on HWND=0x{x}", .{ lp_flags, @intFromPtr(hwnd) });

    if (app.activeSurface()) |surface| {
        if (surface.core_initialized) {
            const himc = os.ImmGetContext(hwnd) orelse
                return imeDefProc(app, hwnd, msg, wparam, lparam);
            defer _ = os.ImmReleaseContext(hwnd, himc);

            // 1. Handle Committed Text (Result String)
            //
            // Keep this path side-effect free for committed text injection.
            // The default proc generates WM_CHAR for commit; if we also inject
            // key events here, committed text can be duplicated.
            if (lp_flags & os.GCS_RESULTSTR != 0) {
                app.ime_last_had_result = true;
                log.info("IME: GCS_RESULTSTR present — commit handled via WM_CHAR path", .{});
                // Clear preedit when committed
                surface.core_surface.preeditCallback(null) catch {};
            }

            // 2. Handle Active Composition (Preedit String)
            if (lp_flags & os.GCS_COMPSTR != 0) {
                const byte_len = os.ImmGetCompositionStringW(himc, os.GCS_COMPSTR, null, 0);
                if (byte_len > 0) {
                    const ulen: u32 = @intCast(byte_len);
                    var wide_buf: [256]u16 = undefined;
                    // Clamp to buffer size (in bytes).
                    const buf_bytes: u32 = @intCast(@min(ulen, wide_buf.len * 2));
                    const actual_bytes = os.ImmGetCompositionStringW(himc, os.GCS_COMPSTR, @ptrCast(&wide_buf), buf_bytes);
                    if (actual_bytes > 0) {
                        const actual_ulen: usize = @intCast(actual_bytes);
                        const wide_count = actual_ulen / 2;
                        var utf8_buf: [1024]u8 = undefined;
                        const utf8_len = input_overlay.imeUtf16ToUtf8(&utf8_buf, wide_buf[0..wide_count]);
                        if (utf8_len > 0) {
                            log.info("IME: preedit text ({d} bytes UTF-8)", .{utf8_len});
                            surface.core_surface.preeditCallback(utf8_buf[0..utf8_len]) catch |err| {
                                log.warn("IME preedit callback error: {}", .{err});
                            };
                        } else {
                            surface.core_surface.preeditCallback(null) catch {};
                        }
                    } else {
                        surface.core_surface.preeditCallback(null) catch {};
                    }
                } else {
                    surface.core_surface.preeditCallback(null) catch {};
                }
            }

            // Update IME window position.
            const ime_pos = surface.core_surface.imePoint();
            const cf = os.COMPOSITIONFORM{
                .dwStyle = os.CFS_POINT,
                .ptCurrentPos = .{
                    .x = @intFromFloat(ime_pos.x),
                    .y = @intFromFloat(ime_pos.y),
                },
                .rcArea = .{},
            };
            _ = os.ImmSetCompositionWindow(himc, &cf);
        }
    }

    return imeDefProc(app, hwnd, msg, wparam, lparam);
}

pub fn handleIMEEndComposition(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const action: []const u8 = if (app.ime_last_had_result) "commit" else "cancel";
    log.info("IME: WM_IME_ENDCOMPOSITION action={s} on HWND=0x{x}", .{ action, @intFromPtr(hwnd) });
    app.ime_composing = false;
    if (app.activeSurface()) |surface| {
        if (surface.core_initialized) {
            surface.core_surface.preeditCallback(null) catch |err| {
                log.warn("IME preedit end error: {}", .{err});
            };
            // Restore the normal keyboard focus owner now that IME composition
            // is done.
            input_runtime.focusKeyboardTarget(app);
        }
    }
    return imeDefProc(app, hwnd, msg, wparam, lparam);
}

test "IME composition source should not inject keyCallback directly" {
    const src = @embedFile("ime.zig");
    try std.testing.expect(std.mem.indexOf(u8, src, "keyCallback(") == null);
}
