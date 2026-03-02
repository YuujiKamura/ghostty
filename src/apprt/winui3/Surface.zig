/// WinUI 3 surface implementation for Ghostty.
///
/// Phase 3: Multi-tab support via TabView. Each Surface owns a SwapChainPanel
/// that is set as the Content of a TabViewItem by App.newTab().
const Surface = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const CoreSurface = @import("../../Surface.zig");
const CoreApp = @import("../../App.zig");
const configpkg = @import("../../config.zig");
const input = @import("../../input.zig");
const App = @import("App.zig");
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const key = @import("key.zig");
const os = @import("os.zig");

const log = std.log.scoped(.winui3);

/// The App that owns this surface.
app: *App,

/// The core surface state.
core_surface: CoreSurface,

/// Current surface size.
size: apprt.SurfaceSize = .{ .width = 800, .height = 600 },

/// Current content scale.
content_scale: apprt.ContentScale = .{ .x = 1.0, .y = 1.0 },

/// Whether the core surface has been initialized.
core_initialized: bool = false,

/// The SwapChainPanel for composition rendering.
swap_chain_panel: ?*winrt.IInspectable = null,

/// Native interface for binding DXGI swap chain to panel.
swap_chain_panel_native: ?*com.ISwapChainPanelNative = null,

/// The IInspectable of the TabViewItem this surface belongs to (for title updates).
tab_view_item_inspectable: ?*winrt.IInspectable = null,

/// Pending high surrogate from a previous WM_CHAR for characters outside BMP.
pending_high_surrogate: u16 = 0,

/// Last known cursor position (updated on every WM_MOUSEMOVE).
cursor_pos: apprt.CursorPos = .{ .x = 0, .y = 0 },

/// Tracks WM_KEYDOWN -> WM_CHAR coordination.
///
/// Three states:
///   .none     -- no pending keydown; WM_CHAR passes through as standalone
///               (e.g. IME commit generates WM_CHAR without a mapped keydown)
///   .consumed -- WM_KEYDOWN was handled by the core; suppress next WM_CHAR
///   .pending  -- WM_KEYDOWN deferred to WM_CHAR; merge physical key info
///               with the character text into one unified KeyEvent
pending_keydown: PendingKeydown = .none,

const PendingKeydown = union(enum) {
    /// No keydown state -- let WM_CHAR through as a standalone event.
    none,
    /// WM_KEYDOWN was consumed -- suppress the next WM_CHAR.
    consumed,
    /// WM_KEYDOWN returned .ignored -- merge with next WM_CHAR.
    pending: PendingKey,
};

const PendingKey = struct {
    key_code: input.Key,
    mods: input.Mods,
    unshifted_codepoint: u21,
};

pub fn init(self: *Surface, app: *App, core_app: *CoreApp, config: *const configpkg.Config) !void {
    self.* = .{
        .app = app,
        .core_surface = undefined,
        .size = .{ .width = 800, .height = 600 },
        .content_scale = .{ .x = 1.0, .y = 1.0 },
    };

    // Update content scale from DPI
    self.updateContentScale();

    // Create SwapChainPanel for composition rendering.
    const panel_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.SwapChainPanel");
    defer winrt.deleteHString(panel_class);
    const panel = try winrt.activateInstance(panel_class);
    self.swap_chain_panel = panel;

    // Get the native interface for later swap chain binding.
    self.swap_chain_panel_native = try panel.queryInterface(com.ISwapChainPanelNative);

    // NOTE: SwapChainPanel is set as TabViewItem content by App.newTab(),
    // not here. We only create the panel and query the native interface.

    try self.core_surface.init(
        core_app.alloc,
        config,
        core_app,
        app,
        self,
    );
    self.core_initialized = true;
    errdefer {
        self.core_surface.deinit();
        self.core_initialized = false;
    }

    // Register with core app
    try core_app.addSurface(self);

    log.info("WinUI 3 surface initialized ({d}x{d})", .{ self.size.width, self.size.height });
}

pub fn deinit(self: *Surface) void {
    if (self.swap_chain_panel_native) |native| {
        native.release();
        self.swap_chain_panel_native = null;
    }
    if (self.swap_chain_panel) |panel| {
        _ = panel.release();
        self.swap_chain_panel = null;
    }
    if (self.tab_view_item_inspectable) |tvi| {
        _ = tvi.release();
        self.tab_view_item_inspectable = null;
    }

    if (self.core_initialized) {
        self.app.core_app.deleteSurface(self);
        self.core_surface.deinit();
        self.core_initialized = false;
    }
}

pub fn core(self: *Surface) *CoreSurface {
    return &self.core_surface;
}

pub fn rtApp(self: *Surface) *App {
    return self.app;
}

pub fn close(self: *Surface, process_active: bool) void {
    _ = process_active;
    // Find this surface's index and close its tab
    for (self.app.surfaces.items, 0..) |s, i| {
        if (s == self) {
            self.app.closeTab(i);
            return;
        }
    }
    // Fallback: close the app if surface not found
    if (self.app.hwnd) |hwnd| {
        _ = os.PostMessageW(hwnd, os.WM_CLOSE, 0, 0);
    }
}

pub fn getTitle(_: *Surface) ?[:0]const u8 {
    return null;
}

pub fn getContentScale(self: *const Surface) !apprt.ContentScale {
    return self.content_scale;
}

pub fn getSize(self: *const Surface) !apprt.SurfaceSize {
    return self.size;
}

pub fn getCursorPos(self: *const Surface) !apprt.CursorPos {
    return self.cursor_pos;
}

pub fn supportsClipboard(
    _: *const Surface,
    clipboard_type: apprt.Clipboard,
) bool {
    return switch (clipboard_type) {
        .standard => true,
        .selection, .primary => false,
    };
}

pub fn clipboardRequest(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool {
    // Only standard clipboard is supported on Windows.
    if (clipboard_type != .standard) return false;

    const hwnd = self.app.hwnd orelse return false;
    const alloc = self.app.core_app.alloc;

    if (os.OpenClipboard(hwnd) == 0) return false;
    defer _ = os.CloseClipboard();

    const handle = os.GetClipboardData(os.CF_UNICODETEXT) orelse return false;
    const lock_ptr = os.GlobalLock(handle) orelse return false;
    defer _ = os.GlobalUnlock(handle);

    // Cast opaque pointer to UTF-16LE many-pointer via integer to avoid
    // Zig's ptrCast restrictions on *anyopaque -> [*]T.
    const ptr: [*]const u16 = @ptrFromInt(@intFromPtr(lock_ptr));

    // Find null terminator (sliceTo requires sentinel-typed pointers).
    var utf16_len: usize = 0;
    while (ptr[utf16_len] != 0) : (utf16_len += 1) {}
    if (utf16_len == 0) return false;
    const utf16 = ptr[0..utf16_len];

    const utf8 = std.unicode.utf16LeToUtf8Alloc(alloc, utf16) catch return false;
    defer alloc.free(utf8);

    const utf8z = alloc.dupeZ(u8, utf8) catch return false;
    defer alloc.free(utf8z);

    self.core_surface.completeClipboardRequest(state, utf8z, false) catch |err| switch (err) {
        error.UnsafePaste, error.UnauthorizedPaste => {
            self.core_surface.completeClipboardRequest(state, utf8z, true) catch |retry_err| {
                log.warn("clipboard request failed on confirmed retry: {}", .{retry_err});
                return false;
            };
        },
        else => {
            log.warn("clipboard request failed: {}", .{err});
            return false;
        },
    };

    return true;
}

pub fn setClipboard(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void {
    _ = confirm;

    // Only standard clipboard is supported on Windows.
    if (clipboard_type != .standard) return;

    // Find text/plain content.
    const text: [:0]const u8 = blk: {
        for (contents) |c| {
            if (std.mem.eql(u8, c.mime, "text/plain")) break :blk c.data;
        }
        return;
    };

    const hwnd = self.app.hwnd orelse return;

    // Calculate the required UTF-16LE buffer length.
    const utf16_len = std.unicode.calcUtf16LeLen(text) catch return;

    // Allocate global moveable memory for the clipboard (including null terminator).
    const hmem = os.GlobalAlloc(os.GMEM_MOVEABLE, (utf16_len + 1) * 2) orelse return;

    // Lock the memory and convert UTF-8 to UTF-16LE.
    const lock_ptr = os.GlobalLock(hmem) orelse {
        _ = os.GlobalFree(hmem);
        return;
    };

    const dest: [*]u16 = @ptrFromInt(@intFromPtr(lock_ptr));
    const written = std.unicode.utf8ToUtf16Le(dest[0..utf16_len], text) catch {
        _ = os.GlobalUnlock(hmem);
        _ = os.GlobalFree(hmem);
        return;
    };
    dest[written] = 0; // null-terminate

    _ = os.GlobalUnlock(hmem);

    // Open the clipboard, empty it, and set the new data.
    if (os.OpenClipboard(hwnd) == 0) {
        _ = os.GlobalFree(hmem);
        return;
    }
    _ = os.EmptyClipboard();

    if (os.SetClipboardData(os.CF_UNICODETEXT, hmem) == null) {
        // SetClipboardData failed; we still own the memory.
        _ = os.GlobalFree(hmem);
    }
    // On success, the OS owns hmem -- do NOT free it.

    _ = os.CloseClipboard();
}

pub fn defaultTermioEnv(self: *Surface) !std.process.EnvMap {
    const alloc = self.app.core_app.alloc;
    var env = try std.process.getEnvMap(alloc);
    errdefer env.deinit();
    try env.put("TERM", "xterm-256color");
    try env.put("COLORTERM", "truecolor");
    return env;
}

pub fn redrawInspector(_: *Surface) void {
    // No-op for MVP
}

/// Update the TabViewItem header with the given title.
/// For MVP, this is a no-op because WinRT requires IPropertyValueStatics
/// to box an HSTRING into IInspectable for put_Header. The window title
/// is set separately via IWindow.putTitle.
pub fn setTabTitle(self: *Surface, title: [:0]const u8) void {
    _ = self;
    _ = title;
}

// --- Event handlers called from WndProc ---

pub fn updateSize(self: *Surface, width: u32, height: u32) void {
    if (width == 0 or height == 0) return;
    self.size = .{ .width = width, .height = height };
    if (self.core_initialized) {
        self.core_surface.sizeCallback(self.size) catch |err| {
            log.warn("size callback error: {}", .{err});
        };
    }
}

pub fn updateContentScale(self: *Surface) void {
    if (self.app.hwnd) |hwnd| {
        const dpi = os.GetDpiForWindow(hwnd);
        if (dpi > 0) {
            const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
            self.content_scale = .{ .x = scale, .y = scale };
            if (self.core_initialized) {
                self.core_surface.contentScaleCallback(self.content_scale) catch |err| {
                    log.warn("content scale callback error: {}", .{err});
                };
            }
        }
    }
}

pub fn handleKeyEvent(self: *Surface, vk: u16, pressed: bool) void {
    if (!self.core_initialized) return;

    const ghostty_key = key.vkToKey(vk) orelse {
        // Unmapped VK (e.g. VK_PROCESSKEY from IME) -- reset to .none so
        // any subsequent WM_CHAR (IME commit text) passes through as a
        // standalone character event.
        if (pressed) self.pending_keydown = .none;
        return;
    };
    const mods = key.getModifiers();
    const unshifted = key.vkToUnshiftedCodepoint(vk);

    // For press events, determine whether to call keyCallback now
    // (function keys, modifier combos) or defer to WM_CHAR (text keys).
    // Text keys only call keyCallback ONCE from handleCharEvent with the
    // unified (.key + .utf8) event, matching the GTK backend pattern.
    if (pressed) {
        const binding_mods = mods.binding();
        const is_text_key = !ghostty_key.modifier() and
            !binding_mods.ctrl and !binding_mods.alt and !binding_mods.super and
            unshifted != 0;

        if (is_text_key) {
            self.pending_keydown = .{ .pending = .{
                .key_code = ghostty_key,
                .mods = mods,
                .unshifted_codepoint = unshifted,
            } };
            return;
        }
    }

    // Function key, modifier combo, modifier-only key, or release event
    // -- call keyCallback immediately.
    const event = input.KeyEvent{
        .action = if (pressed) .press else .release,
        .key = ghostty_key,
        .mods = mods,
        .unshifted_codepoint = unshifted,
    };

    _ = self.core_surface.keyCallback(event) catch |err| {
        log.warn("key callback error vk=0x{X:0>2}: {}", .{ vk, err });
        return;
    };

    // Suppress any subsequent WM_CHAR for consumed press events.
    // (Releases don't produce WM_CHAR.)
    if (pressed) {
        self.pending_keydown = .consumed;
    }
}

pub fn handleCharEvent(self: *Surface, char_code: u16) void {
    if (!self.core_initialized) return;

    // Capture and consume the pending keydown state.
    const state = self.pending_keydown;
    self.pending_keydown = .none;

    switch (state) {
        // WM_KEYDOWN was already consumed (function key, keybinding, etc.)
        // -- suppress this WM_CHAR to avoid double input.
        .consumed => return,

        // .pending or .none -- process the character below.
        .pending, .none => {},
    }

    var codepoint: u21 = undefined;

    if (char_code >= 0xD800 and char_code <= 0xDBFF) {
        // High surrogate -- store and wait for the low surrogate.
        // Restore pending state so the low surrogate WM_CHAR can use it.
        self.pending_high_surrogate = char_code;
        self.pending_keydown = state;
        return;
    } else if (char_code >= 0xDC00 and char_code <= 0xDFFF) {
        // Low surrogate -- combine with pending high surrogate.
        if (self.pending_high_surrogate != 0) {
            const high: u21 = self.pending_high_surrogate;
            const low: u21 = char_code;
            codepoint = ((high - 0xD800) << 10) + (low - 0xDC00) + 0x10000;
            self.pending_high_surrogate = 0;
        } else {
            // Orphaned low surrogate -- discard.
            return;
        }
    } else {
        // BMP character -- clear any stale pending surrogate.
        self.pending_high_surrogate = 0;
        codepoint = @intCast(char_code);
    }

    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(codepoint, &buf) catch return;

    // Build the KeyEvent.  If we have a pending physical key from
    // WM_KEYDOWN (.pending), merge it with the text into one unified
    // event.  Otherwise (.none -- e.g. IME commit), send standalone text.
    const ev: input.KeyEvent = switch (state) {
        .pending => |pk| .{
            .action = .press,
            .key = pk.key_code,
            .mods = pk.mods,
            .unshifted_codepoint = pk.unshifted_codepoint,
            .utf8 = buf[0..len],
        },
        .none => .{
            .action = .press,
            .key = .unidentified,
            .utf8 = buf[0..len],
        },
        .consumed => unreachable,
    };

    _ = self.core_surface.keyCallback(ev) catch |err| {
        log.warn("char callback error: {}", .{err});
    };
}

pub fn handleMouseMove(self: *Surface, x: f64, y: f64) void {
    if (!self.core_initialized) return;
    const pos: apprt.CursorPos = .{ .x = @floatCast(x), .y = @floatCast(y) };
    self.cursor_pos = pos;
    const mods = key.getModifiers();
    self.core_surface.cursorPosCallback(pos, mods) catch |err| {
        log.warn("cursor pos callback error: {}", .{err});
    };
}

pub fn handleMouseButton(self: *Surface, button: input.MouseButton, action: input.MouseButtonState) void {
    if (!self.core_initialized) return;
    const mods = key.getModifiers();

    // Capture/release the mouse so drag events are delivered even outside the window.
    if (action == .press) {
        if (self.app.hwnd) |hwnd| _ = os.SetCapture(hwnd);
    } else {
        _ = os.ReleaseCapture();
    }

    _ = self.core_surface.mouseButtonCallback(action, button, mods) catch |err| {
        log.warn("mouse button callback error: {}", .{err});
        return;
    };
}

pub fn handleScroll(self: *Surface, xoffset: f64, yoffset: f64) void {
    if (!self.core_initialized) return;
    self.core_surface.scrollCallback(xoffset, yoffset, .{}) catch |err| {
        log.warn("scroll callback error: {}", .{err});
    };
}

/// Bind a DXGI swap chain to the SwapChainPanel.
/// Called from the renderer thread after creating a composition swap chain.
pub fn bindSwapChain(self: *Surface, swap_chain: *anyopaque) !void {
    const native = self.swap_chain_panel_native orelse return error.SwapChainPanelNotReady;
    native.setSwapChain(swap_chain) catch |err| {
        log.err("ISwapChainPanelNative::SetSwapChain failed: {}", .{err});
        return err;
    };
    log.info("Swap chain bound to SwapChainPanel", .{});
}
