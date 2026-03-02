/// Win32 application runtime for Ghostty.
const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const build_config = @import("../../build_config.zig");
const apprt = @import("../../apprt.zig");
const CoreApp = @import("../../App.zig");
const CoreSurface = @import("../../Surface.zig");
const configpkg = @import("../../config.zig");
const input = @import("../../input.zig");
const Surface = @import("Surface.zig");
const key = @import("key.zig");
const os = @import("os.zig");

const use_d3d11 = build_config.renderer == .d3d11;

const log = std.log.scoped(.win32);

/// Timer ID for live resize preview.
const RESIZE_TIMER_ID: usize = 1;

/// The core application.
core_app: *CoreApp,

/// The main window handle.
hwnd: ?os.HWND = null,

/// The device context for the main window.
hdc: ?os.HDC = null,

/// The OpenGL rendering context.
hglrc: ?os.HGLRC = null,

/// The single surface (MVP: one window = one surface).
surface: ?*Surface = null,

/// Whether the app is running.
running: bool = false,

/// Whether the user is currently in a modal resize/move loop.
/// Set by WM_ENTERSIZEMOVE / WM_EXITSIZEMOVE.
resizing: bool = false,

/// Pending size from WM_SIZE during modal resize. Applied on WM_EXITSIZEMOVE.
pending_size: ?struct { width: u32, height: u32 } = null,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    // Request 1ms timer resolution for smooth animation timing.
    _ = os.timeBeginPeriod(1);

    const hinstance = os.GetModuleHandleW(null) orelse return error.Win32Error;

    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindowClass");

    const wc = os.WNDCLASSEXW{
        .style = os.CS_OWNDC | os.CS_HREDRAW | os.CS_VREDRAW,
        .lpfnWndProc = wndProc,
        .hInstance = hinstance,
        .hCursor = os.LoadCursorW(null, os.IDC_ARROW),
        .lpszClassName = class_name,
    };

    if (os.RegisterClassExW(&wc) == 0) {
        return error.Win32Error;
    }

    const window_name = std.unicode.utf8ToUtf16LeStringLiteral("Ghostty");

    const hwnd = os.CreateWindowExW(
        0,
        class_name,
        window_name,
        os.WS_OVERLAPPEDWINDOW | os.WS_VISIBLE,
        os.CW_USEDEFAULT,
        os.CW_USEDEFAULT,
        800,
        600,
        null,
        null,
        hinstance,
        null,
    ) orelse return error.Win32Error;
    errdefer _ = os.DestroyWindow(hwnd);

    // Store the App pointer in the window's user data
    _ = os.SetWindowLongPtrW(hwnd, os.GWLP_USERDATA, @intFromPtr(self));

    if (comptime !use_d3d11) {
        // Set up OpenGL context
        const hdc = os.GetDC(hwnd) orelse return error.Win32Error;
        errdefer _ = os.ReleaseDC(hwnd, hdc);

        const pfd = os.PIXELFORMATDESCRIPTOR{
            .dwFlags = os.PFD_DRAW_TO_WINDOW | os.PFD_SUPPORT_OPENGL | os.PFD_DOUBLEBUFFER,
            .iPixelType = os.PFD_TYPE_RGBA,
            .cColorBits = 32,
            .cDepthBits = 24,
            .cStencilBits = 8,
            .iLayerType = os.PFD_MAIN_PLANE,
        };

        const pixel_format = os.ChoosePixelFormat(hdc, &pfd);
        if (pixel_format == 0) return error.Win32Error;

        if (os.SetPixelFormat(hdc, pixel_format, &pfd) == 0) return error.Win32Error;

        const hglrc = os.wglCreateContext(hdc) orelse return error.Win32Error;
        errdefer _ = os.wglDeleteContext(hglrc);
        if (os.wglMakeCurrent(hdc, hglrc) == 0) return error.Win32Error;

        self.* = .{
            .core_app = core_app,
            .hwnd = hwnd,
            .hdc = hdc,
            .hglrc = hglrc,
            .running = true,
        };
    } else {
        // D3D11: no OpenGL context needed; device creation happens in renderer threadEnter.
        self.* = .{
            .core_app = core_app,
            .hwnd = hwnd,
            .running = true,
        };
    }
    // If anything below fails, reset self so the caller doesn't see
    // dangling handles (the local-variable errdefers handle actual cleanup).
    errdefer self.* = .{ .core_app = core_app };

    // Load config once and share with the surface
    var config = try configpkg.Config.load(core_app.alloc);
    defer config.deinit();

    // Create the surface
    var surface = try core_app.alloc.create(Surface);
    errdefer core_app.alloc.destroy(surface);
    try surface.init(self, core_app, &config);
    self.surface = surface;

    _ = os.ShowWindow(hwnd, os.SW_SHOW);
    _ = os.UpdateWindow(hwnd);

    log.info("Win32 application initialized", .{});
}

/// Release the OpenGL context from the current thread.
/// Called from the main thread before the renderer thread starts.
pub fn releaseGLContext(self: *App) void {
    if (comptime use_d3d11) return; // D3D11 doesn't use GL context
    _ = os.wglMakeCurrent(null, null);
    _ = self;
}

/// Make the OpenGL context current on the calling thread.
/// Called from the renderer thread in threadEnter.
pub fn makeGLContextCurrent(self: *App) !void {
    if (comptime use_d3d11) return; // D3D11 doesn't use GL context
    if (self.hdc == null or self.hglrc == null) return error.GLInitFailed;
    if (os.wglMakeCurrent(self.hdc, self.hglrc) == 0) return error.GLInitFailed;
}

pub fn run(self: *App) !void {
    var msg: os.MSG = .{};

    while (self.running) {
        // Process all pending Win32 messages
        while (os.PeekMessageW(&msg, null, 0, 0, os.PM_REMOVE) != 0) {
            if (msg.message == os.WM_QUIT) {
                self.running = false;
                break;
            }
            _ = os.TranslateMessage(&msg);
            _ = os.DispatchMessageW(&msg);
        }

        if (!self.running) break;

        // Drain the CoreApp mailbox (set_title, redraw_surface, quit, etc.)
        self.drainMailbox();

        // Wait for Win32 messages indefinitely.
        // wakeup() sends PostMessageW(WM_USER) which wakes this immediately.
        // INFINITE avoids wasteful 16ms polling when idle.
        _ = os.MsgWaitForMultipleObjectsEx(0, null, os.INFINITE, os.QS_ALLINPUT, os.MWMO_INPUTAVAILABLE);
    }
}

pub fn terminate(self: *App) void {
    if (self.surface) |surface| {
        surface.deinit();
        self.core_app.alloc.destroy(surface);
        self.surface = null;
    }

    if (comptime !use_d3d11) {
        if (self.hglrc) |hglrc| {
            _ = os.wglMakeCurrent(null, null);
            _ = os.wglDeleteContext(hglrc);
            self.hglrc = null;
        }

        if (self.hdc) |hdc| {
            if (self.hwnd) |hwnd| {
                _ = os.ReleaseDC(hwnd, hdc);
            }
            self.hdc = null;
        }
    }

    if (self.hwnd) |hwnd| {
        _ = os.DestroyWindow(hwnd);
        self.hwnd = null;
    }

    // Unregister the window class to avoid leaking the registration.
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindowClass");
    _ = os.UnregisterClassW(class_name, os.GetModuleHandleW(null));

    // Restore default timer resolution.
    _ = os.timeEndPeriod(1);

    self.running = false;
    log.info("Win32 application terminated", .{});
}

/// Called by CoreApp to wake up the event loop.
pub fn wakeup(self: *App) void {
    if (self.hwnd) |hwnd| {
        _ = os.PostMessageW(hwnd, os.WM_USER, 0, 0);
    }
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    _ = target;

    switch (action) {
        .quit => {
            self.running = false;
            if (self.hwnd) |hwnd| {
                _ = os.PostMessageW(hwnd, os.WM_CLOSE, 0, 0);
            }
            return true;
        },
        .new_window => {
            // MVP: single window only
            return false;
        },
        .set_title => {
            if (self.hwnd) |hwnd| {
                setWindowTitle(hwnd, value.title);
            }
            return true;
        },
        else => return false,
    }
}

pub fn performIpc(
    _: Allocator,
    _: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    _: apprt.ipc.Action.Value(action),
) !bool {
    return false;
}

pub fn redrawInspector(_: *App, _: *Surface) void {
    // No-op for MVP
}

fn drainMailbox(self: *App) void {
    self.core_app.tick(self) catch |err| {
        log.warn("tick error: {}", .{err});
    };
}

// ---------------------------------------------------------------
// Window title helper
// ---------------------------------------------------------------

/// Convert a UTF-8 title to UTF-16 and set it on the window.
/// Uses a stack buffer (512 code units) which covers virtually all real titles.
/// If the title is too long, it is truncated at a safe codepoint boundary
/// to avoid splitting a UTF-16 surrogate pair.
fn setWindowTitle(hwnd: os.HWND, title: [:0]const u8) void {
    var buf: [512]u16 = [_]u16{0} ** 512;
    const len = std.unicode.utf8ToUtf16Le(&buf, title) catch {
        // Conversion error (overflow or invalid UTF-8).
        // buf is zero-initialized, so partially written data is safe.
        // Walk back to find the last non-zero code unit for truncation.
        var safe_len: usize = buf.len - 1;
        while (safe_len > 0 and buf[safe_len - 1] == 0) safe_len -= 1;
        // If the last written code unit is a high surrogate, skip it.
        if (safe_len > 0 and buf[safe_len - 1] >= 0xD800 and buf[safe_len - 1] <= 0xDBFF) {
            safe_len -= 1;
        }
        buf[safe_len] = 0;
        _ = os.SetWindowTextW(hwnd, @ptrCast(&buf));
        return;
    };
    if (len < buf.len) {
        buf[len] = 0;
    } else {
        // Exactly filled — null-terminate safely, checking for orphaned high surrogate.
        var safe_len: usize = buf.len - 1;
        if (safe_len > 0 and buf[safe_len - 1] >= 0xD800 and buf[safe_len - 1] <= 0xDBFF) {
            safe_len -= 1;
        }
        buf[safe_len] = 0;
    }
    _ = os.SetWindowTextW(hwnd, @ptrCast(&buf));
}

// ---------------------------------------------------------------
// wndProc and per-message handlers
// ---------------------------------------------------------------

/// Win32 window procedure callback.
fn wndProc(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) callconv(.winapi) os.LRESULT {
    const app: ?*App = blk: {
        const ptr = os.GetWindowLongPtrW(hwnd, os.GWLP_USERDATA);
        break :blk if (ptr == 0) null else @ptrFromInt(ptr);
    };

    switch (msg) {
        os.WM_CLOSE => return handleClose(app),
        os.WM_DESTROY => return handleDestroy(),
        os.WM_ENTERSIZEMOVE => return handleEnterSizeMove(app, hwnd),
        os.WM_EXITSIZEMOVE => return handleExitSizeMove(app, hwnd),
        os.WM_TIMER => return handleTimer(app),
        os.WM_SIZE => return handleSize(app, lparam),
        os.WM_PAINT => return handlePaint(hwnd),
        os.WM_ERASEBKGND => return 1,
        os.WM_KEYDOWN, os.WM_SYSKEYDOWN => return handleKeyInput(app, wparam, true),
        os.WM_KEYUP, os.WM_SYSKEYUP => return handleKeyInput(app, wparam, false),
        os.WM_CHAR => return handleChar(app, wparam),
        os.WM_MOUSEMOVE => return handleMouseMove(app, lparam),
        os.WM_LBUTTONDOWN => return handleMouseButton(app, .left, .press),
        os.WM_RBUTTONDOWN => return handleMouseButton(app, .right, .press),
        os.WM_MBUTTONDOWN => return handleMouseButton(app, .middle, .press),
        os.WM_LBUTTONUP => return handleMouseButton(app, .left, .release),
        os.WM_RBUTTONUP => return handleMouseButton(app, .right, .release),
        os.WM_MBUTTONUP => return handleMouseButton(app, .middle, .release),
        os.WM_MOUSEWHEEL => return handleScroll(app, wparam, .vertical),
        os.WM_MOUSEHWHEEL => return handleScroll(app, wparam, .horizontal),
        os.WM_DPICHANGED => return handleDpiChanged(app, hwnd, lparam),
        os.WM_USER => return handleWakeup(app),
        os.WM_IME_STARTCOMPOSITION => return handleIMEStartComposition(app, hwnd),
        os.WM_IME_COMPOSITION => return handleIMEComposition(app, hwnd, lparam),
        os.WM_IME_ENDCOMPOSITION => return handleIMEEndComposition(app, hwnd),
        else => {},
    }

    return os.DefWindowProcW(hwnd, msg, wparam, lparam);
}

// --- Individual message handlers ---

fn handleClose(app: ?*App) os.LRESULT {
    if (app) |a| a.running = false;
    os.PostQuitMessage(0);
    return 0;
}

fn handleDestroy() os.LRESULT {
    os.PostQuitMessage(0);
    return 0;
}

fn handleEnterSizeMove(app: ?*App, hwnd: os.HWND) os.LRESULT {
    if (app) |a| {
        a.resizing = true;
        _ = os.SetTimer(hwnd, RESIZE_TIMER_ID, 16, null);
    }
    return 0;
}

fn handleExitSizeMove(app: ?*App, hwnd: os.HWND) os.LRESULT {
    if (app) |a| {
        _ = os.KillTimer(hwnd, RESIZE_TIMER_ID);
        a.resizing = false;
        if (a.pending_size) |sz| {
            if (a.surface) |surface| surface.updateSize(sz.width, sz.height);
            a.pending_size = null;
        }
    }
    return 0;
}

fn handleTimer(app: ?*App) os.LRESULT {
    if (app) |a| {
        if (a.pending_size) |sz| {
            if (a.surface) |surface| surface.updateSize(sz.width, sz.height);
            a.pending_size = null;
        }
        a.drainMailbox();
    }
    return 0;
}

fn handleSize(app: ?*App, lparam: os.LPARAM) os.LRESULT {
    if (app) |a| {
        const lp: usize = @bitCast(lparam);
        const width: u32 = @intCast(lp & 0xFFFF);
        const height: u32 = @intCast((lp >> 16) & 0xFFFF);
        if (a.resizing) {
            a.pending_size = .{ .width = width, .height = height };
        } else {
            if (a.surface) |surface| surface.updateSize(width, height);
        }
    }
    return 0;
}

fn handlePaint(hwnd: os.HWND) os.LRESULT {
    var ps: os.PAINTSTRUCT = .{};
    _ = os.BeginPaint(hwnd, &ps);
    _ = os.EndPaint(hwnd, &ps);
    return 0;
}

fn handleKeyInput(app: ?*App, wparam: os.WPARAM, pressed: bool) os.LRESULT {
    if (app) |a| {
        if (a.surface) |surface| {
            const wp: usize = @bitCast(wparam);
            surface.handleKeyEvent(@truncate(wp), pressed);
        }
    }
    return 0;
}

fn handleChar(app: ?*App, wparam: os.WPARAM) os.LRESULT {
    if (app) |a| {
        if (a.surface) |surface| {
            const wp: usize = @bitCast(wparam);
            surface.handleCharEvent(@truncate(wp));
        }
    }
    return 0;
}

fn handleMouseMove(app: ?*App, lparam: os.LPARAM) os.LRESULT {
    if (app) |a| {
        if (a.surface) |surface| {
            const lp: usize = @bitCast(lparam);
            const x: i16 = @bitCast(@as(u16, @truncate(lp)));
            const y: i16 = @bitCast(@as(u16, @truncate(lp >> 16)));
            surface.handleMouseMove(@floatFromInt(x), @floatFromInt(y));
        }
    }
    return 0;
}

fn handleMouseButton(app: ?*App, button: input.MouseButton, action: input.MouseButtonState) os.LRESULT {
    if (app) |a| {
        if (a.surface) |surface| {
            surface.handleMouseButton(button, action);
        }
    }
    return 0;
}

const ScrollDirection = enum { vertical, horizontal };

fn handleScroll(app: ?*App, wparam: os.WPARAM, direction: ScrollDirection) os.LRESULT {
    if (app) |a| {
        if (a.surface) |surface| {
            const wp: usize = @bitCast(wparam);
            const delta: i16 = @bitCast(@as(u16, @truncate(wp >> 16)));
            const offset = @as(f64, @floatFromInt(delta)) / 120.0;
            switch (direction) {
                .vertical => surface.handleScroll(0, offset),
                .horizontal => surface.handleScroll(offset, 0),
            }
        }
    }
    return 0;
}

fn handleDpiChanged(app: ?*App, hwnd: os.HWND, lparam: os.LPARAM) os.LRESULT {
    if (app) |a| {
        if (a.surface) |surface| surface.updateContentScale();
    }
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
    return 0;
}

fn handleWakeup(app: ?*App) os.LRESULT {
    if (app) |a| a.drainMailbox();
    return 0;
}

// ---------------------------------------------------------------
// IME (Input Method Editor) handlers for CJK text input
// ---------------------------------------------------------------

fn handleIMEStartComposition(app: ?*App, hwnd: os.HWND) os.LRESULT {
    if (app) |a| {
        if (a.surface) |surface| {
            if (surface.core_initialized) {
                const himc = os.ImmGetContext(hwnd) orelse
                    return os.DefWindowProcW(hwnd, os.WM_IME_STARTCOMPOSITION, 0, 0);
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
    }
    return os.DefWindowProcW(hwnd, os.WM_IME_STARTCOMPOSITION, 0, 0);
}

fn handleIMEComposition(app: ?*App, hwnd: os.HWND, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const lp_flags: u32 = @truncate(lp);

    if (app) |a| {
        if (a.surface) |surface| {
            if (surface.core_initialized) {
                const himc = os.ImmGetContext(hwnd) orelse
                    return os.DefWindowProcW(hwnd, os.WM_IME_COMPOSITION, 0, lparam);
                defer _ = os.ImmReleaseContext(hwnd, himc);

                // If a result string is ready, clear preedit.
                // The actual committed text arrives via WM_CHAR from DefWindowProcW.
                if (lp_flags & os.GCS_RESULTSTR != 0) {
                    surface.core_surface.preeditCallback(null) catch |err| {
                        log.warn("IME preedit clear error: {}", .{err});
                    };
                }

                // If a composition string is present, send it as preedit text.
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
                            const utf8_len = imeUtf16ToUtf8(&utf8_buf, wide_buf[0..wide_count]);
                            if (utf8_len > 0) {
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
    }
    // Must call DefWindowProcW so the system generates WM_CHAR for committed text.
    return os.DefWindowProcW(hwnd, os.WM_IME_COMPOSITION, 0, lparam);
}

fn handleIMEEndComposition(app: ?*App, hwnd: os.HWND) os.LRESULT {
    if (app) |a| {
        if (a.surface) |surface| {
            if (surface.core_initialized) {
                surface.core_surface.preeditCallback(null) catch |err| {
                    log.warn("IME preedit end error: {}", .{err});
                };
            }
        }
    }
    return os.DefWindowProcW(hwnd, os.WM_IME_ENDCOMPOSITION, 0, 0);
}

/// Convert a UTF-16LE slice to UTF-8 in a destination buffer.
/// Returns the number of UTF-8 bytes written. Stops on invalid data or buffer overflow.
fn imeUtf16ToUtf8(dest: []u8, src: []const u16) usize {
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
