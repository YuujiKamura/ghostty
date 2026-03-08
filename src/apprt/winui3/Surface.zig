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
const terminal = @import("../../terminal/main.zig");
const App = @import("App.zig");
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const native_interop = @import("native_interop.zig");
const key = @import("key.zig");
const os = @import("os.zig");

const SearchOverlay = @import("search_overlay.zig").SearchOverlay;

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

/// Whether the SwapChainPanel has fired its Loaded event.
loaded: bool = false,

/// Guard against re-entrant Loaded events (clear+append in content can re-fire Loaded).
in_loaded_handler: bool = false,

/// Holds a swap chain from the renderer thread if it arrives before Loaded.
pending_swap_chain: ?*anyopaque = null,
/// Holds a swap chain handle from the renderer thread if it arrives before Loaded.
pending_swap_chain_handle: ?usize = null,

/// Token for the Loaded event registration.
loaded_token: i64 = 0,

/// Token for the SizeChanged event registration.
size_changed_token: i64 = 0,

/// Tokens for XAML input event registrations.
pointer_pressed_token: i64 = 0,
pointer_moved_token: i64 = 0,
pointer_released_token: i64 = 0,
pointer_wheel_changed_token: i64 = 0,
preview_key_down_token: i64 = 0,
preview_key_up_token: i64 = 0,
character_received_token: i64 = 0,
got_focus_token: i64 = 0,
lost_focus_token: i64 = 0,

/// The SwapChainPanel for composition rendering.
swap_chain_panel: ?*winrt.IInspectable = null,

/// Native interface for binding DXGI swap chain to panel.
swap_chain_panel_native: ?*com.ISwapChainPanelNative = null,
/// Native2 interface for binding composition surface handles.
swap_chain_panel_native2: ?*native_interop.ISwapChainPanelNative2 = null,

/// Last DXGI swap-chain pointer observed from renderer thread.
/// Used to rebind when TabView selection changes and panel realization timing differs.
last_swap_chain: ?*anyopaque = null,
/// Last composition surface handle observed from renderer thread.
last_swap_chain_handle: ?usize = null,

/// The IInspectable of the TabViewItem this surface belongs to (for title updates).
tab_view_item_inspectable: ?*winrt.IInspectable = null,


/// Current title of the surface, allocated dynamically.
title: ?[:0]u8 = null,

/// Inner layout grid: col 0 = SwapChainPanel (1*), col 1 = ScrollBar (17px).
surface_grid: ?*winrt.IInspectable = null,
/// The vertical ScrollBar XAML control (IInspectable, QI to IScrollBar/IRangeBase).
scroll_bar_insp: ?*winrt.IInspectable = null,
/// Event token for ScrollBar.Scroll.
scroll_bar_scroll_token: i64 = 0,
/// Flag to prevent feedback loops when programmatically updating scrollbar.
is_internal_scroll_update: bool = false,

/// The search overlay UI.
search_overlay: SearchOverlay,

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
        .search_overlay = try SearchOverlay.init(self),
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
    errdefer {
        _ = panel.release();
        self.swap_chain_panel = null;
    }

    // Get the native interface for later swap chain binding.
    self.swap_chain_panel_native = try panel.queryInterface(com.ISwapChainPanelNative);
    errdefer {
        self.swap_chain_panel_native.?.release();
        self.swap_chain_panel_native = null;
    }
    var native2_raw: ?*anyopaque = null;
    const native2_hr = panel.lpVtbl.QueryInterface(@ptrCast(panel), &native_interop.ISwapChainPanelNative2.IID, &native2_raw);
    if (native2_hr >= 0 and native2_raw != null) {
        self.swap_chain_panel_native2 = @ptrCast(@alignCast(native2_raw.?));
    } else {
        self.swap_chain_panel_native2 = null;
        const hr_u32: u32 = @bitCast(native2_hr);
        if (hr_u32 != 0x80004002) {
            log.warn("SwapChainPanel QI(ISwapChainPanelNative2) failed hr=0x{x:0>8}", .{hr_u32});
        }
    }

    // Set SwapChainPanel background to black.
    self.app.setControlBackground(panel, .{ .a = 255, .r = 0, .g = 0, .b = 0 });

    // Create inner surface grid: col 0 = SwapChainPanel (Star), col 1 = ScrollBar (17px).
    {
        const grid_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Grid");
        defer winrt.deleteHString(grid_class);
        const grid_insp = try winrt.activateInstance(grid_class);
        errdefer _ = grid_insp.release();

        // Define two columns.
        const igrid = try grid_insp.queryInterface(com.IGrid);
        defer igrid.release();
        const col_defs_raw = try igrid.ColumnDefinitions();
        const col_defs: *com.IVector = @ptrCast(@alignCast(col_defs_raw));
        defer col_defs.release();

        const col_def_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.ColumnDefinition");
        defer winrt.deleteHString(col_def_class);

        // Col 0: Star (1*) for SwapChainPanel.
        {
            const col0_insp = try winrt.activateInstance(col_def_class);
            defer _ = col0_insp.release();
            const col0 = try col0_insp.queryInterface(com.IColumnDefinition);
            defer col0.release();
            const star_width = com.GridLength{ .Value = 1.0, .GridUnitType = com.GridUnitType.Star };
            try com.hrCheck(col0.lpVtbl.SetWidth(@ptrCast(col0), star_width));
            try col_defs.append(@ptrCast(col0_insp));
        }

        // Col 1: Pixel (17px) for ScrollBar.
        {
            const col1_insp = try winrt.activateInstance(col_def_class);
            defer _ = col1_insp.release();
            const col1 = try col1_insp.queryInterface(com.IColumnDefinition);
            defer col1.release();
            const pixel_width = com.GridLength{ .Value = 17.0, .GridUnitType = com.GridUnitType.Pixel };
            try com.hrCheck(col1.lpVtbl.SetWidth(@ptrCast(col1), pixel_width));
            try col_defs.append(@ptrCast(col1_insp));
        }

        // Create vertical ScrollBar.
        const sb_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Primitives.ScrollBar");
        defer winrt.deleteHString(sb_class);
        const sb_insp = try winrt.activateInstance(sb_class);
        errdefer _ = sb_insp.release();

        // Set Orientation = Vertical (1).
        const isb = try sb_insp.queryInterface(com.IScrollBar);
        defer isb.release();
        try isb.setOrientation(1);

        // Set initial range values.
        const irb = try sb_insp.queryInterface(com.IRangeBase);
        defer irb.release();
        try irb.setMinimum(0.0);
        try irb.setMaximum(0.0);
        try irb.setValue(0.0);
        try irb.setSmallChange(1.0);
        try irb.setLargeChange(10.0);

        // Set VerticalAlignment = Stretch on ScrollBar.
        const sb_fe = try sb_insp.queryInterface(com.IFrameworkElement);
        defer sb_fe.release();
        try sb_fe.SetWidth(17.0);
        try sb_fe.SetMinWidth(17.0);
        try sb_fe.SetMaxWidth(17.0);
        try sb_fe.SetHorizontalAlignment(com.HorizontalAlignment.Stretch);
        try sb_fe.SetVerticalAlignment(com.VerticalAlignment.Stretch);

        const sb_ue = try sb_insp.queryInterface(com.IUIElement);
        defer sb_ue.release();
        try sb_ue.SetVisibility(0);
        try sb_ue.SetIsHitTestVisible(true);

        // Add SwapChainPanel (col 0) and ScrollBar (col 1) to the grid.
        const grid_panel = try grid_insp.queryInterface(com.IPanel);
        defer grid_panel.release();
        const grid_children_raw = try grid_panel.Children();
        const grid_children: *com.IVector = @ptrCast(@alignCast(grid_children_raw));
        defer grid_children.release();

        // Append SwapChainPanel (Grid.Column defaults to 0).
        try grid_children.append(@ptrCast(panel));

        // Append ScrollBar and set Grid.Column = 1.
        try grid_children.append(@ptrCast(sb_insp));

        const grid_statics_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Grid");
        defer winrt.deleteHString(grid_statics_class);
        const grid_statics = try winrt.getActivationFactory(com.IGridStatics, grid_statics_class);
        defer grid_statics.release();
        try grid_statics.setColumn(@ptrCast(sb_fe), 1);

        // Register Scroll event on ScrollBar.
        const delegate_runtime_sb = @import("delegate_runtime.zig");
        const ScrollDelegate = delegate_runtime_sb.TypedDelegate(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);
        const scroll_delegate = try ScrollDelegate.createWithIid(
            self.app.core_app.alloc,
            self,
            &onScrollBarScroll,
            &com.IID_ScrollEventHandler,
        );
        defer scroll_delegate.release();
        self.scroll_bar_scroll_token = try isb.addScroll(scroll_delegate.comPtr());

        // Store references.
        self.surface_grid = grid_insp;
        self.scroll_bar_insp = sb_insp;

        log.info("Surface grid created: SwapChainPanel (col 0) + ScrollBar (col 1)", .{});
    }

    // Register Loaded handler to defer SetSwapChain until the panel is ready.
    const framework_element = try panel.queryInterface(com.IFrameworkElement);
    defer framework_element.release();
    const delegate_runtime = @import("delegate_runtime.zig");
    const LoadedDelegate = delegate_runtime.TypedDelegate(Surface, *const fn (*Surface, *anyopaque, *anyopaque) void);
    const loaded_delegate = try LoadedDelegate.createWithIid(self.app.core_app.alloc, self, &onLoaded, &com.IID_RoutedEventHandler);
    // Note: LoadedDelegate.createWithIid returns a ref-counted COM object.
    // We pass it to addLoaded which will AddRef it again.
    defer _ = loaded_delegate.com.lpVtbl.Release(loaded_delegate.comPtr());
    self.loaded_token = try framework_element.AddLoaded(loaded_delegate.comPtr());

    const SizeChangedDelegate = delegate_runtime.TypedDelegate(Surface, *const fn (*Surface, *anyopaque, *anyopaque) void);
    const size_changed_delegate = try SizeChangedDelegate.createWithIid(
        self.app.core_app.alloc,
        self,
        &onSizeChanged,
        &com.IID_SizeChangedEventHandler,
    );
    defer _ = size_changed_delegate.com.lpVtbl.Release(size_changed_delegate.comPtr());
    self.size_changed_token = framework_element.AddSizeChanged(size_changed_delegate.comPtr()) catch |err| blk: {
        log.warn("SwapChainPanel.SizeChanged handler registration failed: {}", .{err});
        break :blk 0;
    };

    // Register XAML input event handlers on the SwapChainPanel.
    // These bypass the input_overlay HWND and receive events directly from
    // the XAML dispatcher, solving the issue where WinUI3 consumes navigation
    // keys and mouse wheel events before they reach Win32 message queues.
    {
        const ui_element = try panel.queryInterface(com.IUIElement);
        defer ui_element.release();

        // Enable keyboard focus on the SwapChainPanel.
        ui_element.SetIsTabStop(true) catch |err| {
            log.warn("putIsTabStop failed: {}", .{err});
        };

        const XamlDelegate = delegate_runtime.TypedDelegate(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);

        // Pointer events
        const ptr_pressed = try XamlDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerPressed, &com.IID_PointerEventHandler);
        defer ptr_pressed.release();
        self.pointer_pressed_token = ui_element.AddPointerPressed(ptr_pressed.comPtr()) catch 0;

        const ptr_moved = try XamlDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerMoved, &com.IID_PointerEventHandler);
        defer ptr_moved.release();
        self.pointer_moved_token = ui_element.AddPointerMoved(ptr_moved.comPtr()) catch 0;

        const ptr_released = try XamlDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerReleased, &com.IID_PointerEventHandler);
        defer ptr_released.release();
        self.pointer_released_token = ui_element.AddPointerReleased(ptr_released.comPtr()) catch 0;

        const ptr_wheel = try XamlDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerWheelChanged, &com.IID_PointerEventHandler);
        defer ptr_wheel.release();
        self.pointer_wheel_changed_token = ui_element.AddPointerWheelChanged(ptr_wheel.comPtr()) catch 0;

        // Keyboard events (PreviewKeyDown catches navigation keys before XAML consumes them)
        const key_down = try XamlDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPreviewKeyDown, &com.IID_KeyEventHandler);
        defer key_down.release();
        self.preview_key_down_token = ui_element.AddPreviewKeyDown(key_down.comPtr()) catch 0;

        const key_up = try XamlDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPreviewKeyUp, &com.IID_KeyEventHandler);
        defer key_up.release();
        self.preview_key_up_token = ui_element.AddPreviewKeyUp(key_up.comPtr()) catch 0;

        // CharacterReceived — text input
        const char_recv = try XamlDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlCharacterReceived, &com.IID_CharacterReceivedHandler);
        defer char_recv.release();
        self.character_received_token = ui_element.AddCharacterReceived(char_recv.comPtr()) catch 0;

        // Focus events
        const got_focus = try XamlDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlGotFocus, &com.IID_RoutedEventHandler);
        defer got_focus.release();
        self.got_focus_token = ui_element.AddGotFocus(got_focus.comPtr()) catch 0;

        const lost_focus = try XamlDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlLostFocus, &com.IID_RoutedEventHandler);
        defer lost_focus.release();
        self.lost_focus_token = ui_element.AddLostFocus(lost_focus.comPtr()) catch 0;
    }

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
    self.search_overlay.deinit();
    // Stop the renderer/IO threads FIRST by tearing down core_surface.
    // This joins the renderer thread, ensuring no further bindSwapChain
    // calls (or WM_APP_BIND_SWAP_CHAIN posts) can occur after we release
    // the COM objects below.
    if (self.core_initialized) {
        self.app.core_app.deleteSurface(self);
        self.core_surface.deinit();
        self.core_initialized = false;
    }

    // Now safe to release COM objects -- renderer thread is stopped.
    if (self.swap_chain_panel_native2) |native2| {
        native2.release();
        self.swap_chain_panel_native2 = null;
    }
    if (self.swap_chain_panel_native) |native| {
        // Unregister event handlers if we have tokens.
        if (self.swap_chain_panel) |panel| {
            if (panel.queryInterface(com.IFrameworkElement)) |fe| {
                defer fe.release();
                if (self.loaded_token != 0) {
                    fe.RemoveLoaded(self.loaded_token) catch {};
                    self.loaded_token = 0;
                }
                if (self.size_changed_token != 0) {
                    fe.RemoveSizeChanged(self.size_changed_token) catch {};
                    self.size_changed_token = 0;
                }
            } else |_| {}

            // Unregister XAML input event handlers.
            if (panel.queryInterface(com.IUIElement)) |ue| {
                defer ue.release();
                if (self.pointer_pressed_token != 0) { ue.RemovePointerPressed(self.pointer_pressed_token) catch {}; }
                if (self.pointer_moved_token != 0) { ue.RemovePointerMoved(self.pointer_moved_token) catch {}; }
                if (self.pointer_released_token != 0) { ue.RemovePointerReleased(self.pointer_released_token) catch {}; }
                if (self.pointer_wheel_changed_token != 0) { ue.RemovePointerWheelChanged(self.pointer_wheel_changed_token) catch {}; }
                if (self.preview_key_down_token != 0) { ue.RemovePreviewKeyDown(self.preview_key_down_token) catch {}; }
                if (self.preview_key_up_token != 0) { ue.RemovePreviewKeyUp(self.preview_key_up_token) catch {}; }
                if (self.character_received_token != 0) { ue.RemoveCharacterReceived(self.character_received_token) catch {}; }
                if (self.got_focus_token != 0) { ue.RemoveGotFocus(self.got_focus_token) catch {}; }
                if (self.lost_focus_token != 0) { ue.RemoveLostFocus(self.lost_focus_token) catch {}; }
            } else |_| {}
        }
        native.release();
        self.swap_chain_panel_native = null;
    }
    // Release scrollbar and surface grid.
    if (self.scroll_bar_insp) |sb| {
        if (self.scroll_bar_scroll_token != 0) {
            const isb = sb.queryInterface(com.IScrollBar) catch null;
            if (isb) |s| {
                defer s.release();
                s.removeScroll(self.scroll_bar_scroll_token) catch {};
            }
            self.scroll_bar_scroll_token = 0;
        }
        _ = sb.release();
        self.scroll_bar_insp = null;
    }
    if (self.surface_grid) |sg| {
        _ = sg.release();
        self.surface_grid = null;
    }
    if (self.swap_chain_panel) |panel| {
        _ = panel.release();
        self.swap_chain_panel = null;
    }
    if (self.tab_view_item_inspectable) |tvi| {
        _ = tvi.release();
        self.tab_view_item_inspectable = null;
    }

    if (self.title) |t| {
        self.app.core_app.alloc.free(t);
        self.title = null;
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
    self.app.closeSurface(self);
}

pub fn getTitle(self: *Surface) ?[:0]const u8 {
    return self.title;
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

pub fn supportsSwapChainHandle(self: *const Surface) bool {
    return self.swap_chain_panel_native2 != null;
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
            // TODO: Implement a proper WinUI 3 dialog to ask the user for confirmation
            // before retrying with `confirmed = true`.
            // For now, securely deny the paste.
            log.warn("unsafe paste blocked pending user confirmation dialog implementation", .{});
            return false;
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
pub fn setTabTitle(self: *Surface, title: [:0]const u8) void {
    const alloc = self.app.core_app.alloc;
    if (self.title) |old_title| alloc.free(old_title);

    // Store the title for getTitle() queries
    self.title = alloc.dupeZ(u8, title) catch {
        log.warn("setTabTitle: failed to allocate title copy (len={})", .{title.len});
        return;
    };

    // Actually update the TabViewItem UI using WinRT PropertyValue
    if (self.tab_view_item_inspectable) |tvi_insp| {
        if (tvi_insp.queryInterface(com.ITabViewItem)) |tvi| {
            defer tvi.release();
            if (self.title) |t| {
                const utf16 = std.unicode.utf8ToUtf16LeAlloc(alloc, t) catch {
                    log.warn("setTabTitle: utf8ToUtf16LeAlloc failed", .{});
                    return;
                };
                defer alloc.free(utf16);
                if (winrt.createHString(utf16)) |hstr| {
                    defer winrt.deleteHString(hstr);
                    const util = @import("util.zig");
                    if (util.boxString(hstr)) |boxed| {
                        defer boxed.release();
                        _ = tvi.SetHeader(boxed) catch |err| {
                            log.warn("setTabTitle: putHeader failed: {}", .{err});
                        };
                    } else |err| {
                        log.warn("setTabTitle: boxString failed: {}", .{err});
                    }
                } else |err| {
                    log.warn("setTabTitle: createHString failed: {}", .{err});
                }
            }
        } else |_| {}
    }
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
    // Use input_hwnd when available — mouse events are routed through it.
    if (action == .press) {
        const capture_hwnd = self.app.input_hwnd orelse self.app.hwnd;
        if (capture_hwnd) |h| _ = os.SetCapture(h);
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

// --- XAML event callbacks ---

fn onXamlPointerPressed(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const point = ea.getCurrentPoint(null) catch return;
    defer point.release();
    const pos = point.getPosition() catch return;
    self.handleMouseMove(@floatCast(pos.X), @floatCast(pos.Y));
    const props = point.getProperties() catch return;
    defer props.release();
    const update_kind = props.getPointerUpdateKind() catch return;
    const button: input.MouseButton = switch (update_kind) {
        1 => .left, // LeftButtonPressed
        3 => .right, // RightButtonPressed
        5 => .middle, // MiddleButtonPressed
        else => return,
    };
    // Request XAML focus on click so keyboard events flow here.
    if (self.swap_chain_panel) |panel| {
        if (panel.queryInterface(com.IUIElement)) |ue| {
            defer ue.release();
            _ = ue.focus(1) catch {}; // FocusState.Programmatic = 1
        } else |_| {}
    }
    self.handleMouseButton(button, .press);
    ea.putHandled(true) catch {};
}

fn onXamlPointerMoved(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const point = ea.getCurrentPoint(null) catch return;
    defer point.release();
    const pos = point.getPosition() catch return;
    self.handleMouseMove(@floatCast(pos.X), @floatCast(pos.Y));
    ea.putHandled(true) catch {};
}

fn onXamlPointerReleased(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const point = ea.getCurrentPoint(null) catch return;
    defer point.release();
    const pos = point.getPosition() catch return;
    self.handleMouseMove(@floatCast(pos.X), @floatCast(pos.Y));
    const props = point.getProperties() catch return;
    defer props.release();
    // On release, the button is no longer "pressed" so we use PointerUpdateKind.
    const update_kind = props.getPointerUpdateKind() catch return;
    const button: input.MouseButton = switch (update_kind) {
        2 => .left, // LeftButtonReleased
        4 => .right, // RightButtonReleased
        6 => .middle, // MiddleButtonReleased
        else => return,
    };
    self.handleMouseButton(button, .release);
    if (button == .right) {
        self.app.showContextMenuAtCursor();
    }
    ea.putHandled(true) catch {};
}

fn onXamlPointerWheelChanged(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const point = ea.getCurrentPoint(null) catch return;
    defer point.release();
    const props = point.getProperties() catch return;
    defer props.release();
    const delta = props.getMouseWheelDelta() catch return;
    const offset = @as(f64, @floatFromInt(delta)) / 120.0;
    const is_horizontal = props.getIsHorizontalMouseWheel() catch false;
    if (is_horizontal) {
        self.handleScroll(offset, 0);
    } else {
        self.handleScroll(0, offset);
    }
    ea.putHandled(true) catch {};
}

fn onXamlPreviewKeyDown(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const vk = ea.getKey() catch return;
    if (vk == 0xE5) {
        // VK_PROCESSKEY — IME is active. Switch focus to input_hwnd for IME.
        if (self.app.input_hwnd) |h| _ = os.SetFocus(h);
        return; // Don't mark handled — let IME process.
    }
    self.handleKeyEvent(@intCast(@as(u32, @bitCast(vk))), true);
    ea.putHandled(true) catch {};
}

fn onXamlPreviewKeyUp(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const vk = ea.getKey() catch return;
    self.handleKeyEvent(@intCast(@as(u32, @bitCast(vk))), false);
    ea.putHandled(true) catch {};
}

fn onXamlCharacterReceived(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    const ea: *com.ICharacterReceivedRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const ch = ea.getCharacter() catch return;
    self.handleCharEvent(ch);
    ea.putHandled(true) catch {};
}

fn onXamlGotFocus(self: *Surface, _: ?*anyopaque, _: ?*anyopaque) void {
    if (!self.core_initialized) return;
    log.info("XAML GotFocus on SwapChainPanel surface=0x{x}", .{@intFromPtr(self)});
    self.core_surface.focusCallback(true) catch |err| {
        log.warn("focusCallback(true) error: {}", .{err});
    };
}

fn onXamlLostFocus(self: *Surface, _: ?*anyopaque, _: ?*anyopaque) void {
    if (!self.core_initialized) return;
    log.info("XAML LostFocus on SwapChainPanel surface=0x{x}", .{@intFromPtr(self)});
    self.core_surface.focusCallback(false) catch |err| {
        log.warn("focusCallback(false) error: {}", .{err});
    };
}

/// Request XAML focus on the SwapChainPanel (called from ime.zig after IME ends).
pub fn focusSwapChainPanel(self: *Surface) void {
    if (self.swap_chain_panel) |panel| {
        if (panel.queryInterface(com.IUIElement)) |ue| {
            defer ue.release();
            _ = ue.focus(1) catch {}; // FocusState.Programmatic = 1
        } else |_| {}
    }
}

/// Bind a DXGI swap chain to the SwapChainPanel.
/// Called from the renderer thread after creating a composition swap chain.
/// ISwapChainPanelNative::SetSwapChain must be called from the UI thread,
/// so we post WM_APP_BIND_SWAP_CHAIN with wparam=swap_chain, lparam=self.
pub fn bindSwapChain(self: *Surface, swap_chain: *anyopaque) void {
    self.last_swap_chain = swap_chain;
    log.info(
        "bindSwapChain: loaded={} pending_before={} swap_chain=0x{x}",
        .{ self.loaded, self.pending_swap_chain != null, @intFromPtr(swap_chain) },
    );

    if (!self.loaded) {
        log.info("bindSwapChain: panel not yet Loaded, attempting immediate binding (flip start)", .{});
    }

    if (self.app.hwnd) |hwnd| {
        _ = os.PostMessageW(
            hwnd,
            os.WM_APP_BIND_SWAP_CHAIN,
            @bitCast(@intFromPtr(swap_chain)),
            @bitCast(@intFromPtr(self)),
        );
    }
}

/// Bind a composition surface handle to the SwapChainPanel via ISwapChainPanelNative2.
pub fn bindSwapChainHandle(self: *Surface, swap_chain_handle: usize) void {
    self.last_swap_chain_handle = swap_chain_handle;
    log.info(
        "bindSwapChainHandle: loaded={} pending_before={} handle=0x{x}",
        .{ self.loaded, self.pending_swap_chain_handle != null, swap_chain_handle },
    );

    if (!self.loaded) {
        log.info("bindSwapChainHandle: panel not yet Loaded, attempting immediate binding", .{});
    }

    if (self.app.hwnd) |hwnd| {
        _ = os.PostMessageW(
            hwnd,
            os.WM_APP_BIND_SWAP_CHAIN_HANDLE,
            @bitCast(swap_chain_handle),
            @bitCast(@intFromPtr(self)),
        );
    }
}

/// Actually perform the swap chain binding. Must be called on the UI thread.
/// swap_chain comes from wparam of the posted message.
pub fn completeBindSwapChain(self: *Surface, swap_chain: *anyopaque) void {
    self.last_swap_chain = swap_chain;
    self.pending_swap_chain = null;

    const native = self.swap_chain_panel_native orelse {
        log.warn("SwapChainPanelNative not available for binding (shutdown race)", .{});
        return;
    };
    native.setSwapChain(swap_chain) catch |err| {
        log.err("ISwapChainPanelNative::SetSwapChain failed: {}", .{err});
        return;
    };
    log.info("Swap chain bound to SwapChainPanel (UI thread)", .{});
}

/// Actually perform swap chain HANDLE binding. Must be called on the UI thread.
pub fn completeBindSwapChainHandle(self: *Surface, swap_chain_handle: usize) void {
    self.last_swap_chain_handle = swap_chain_handle;
    self.pending_swap_chain_handle = null;

    const native2 = self.swap_chain_panel_native2 orelse {
        log.warn("SwapChainPanelNative2 not available for SetSwapChainHandle", .{});
        return;
    };
    const handle: os.HANDLE = @ptrFromInt(swap_chain_handle);
    native2.setSwapChainHandle(handle) catch |err| {
        log.err("ISwapChainPanelNative2::SetSwapChainHandle failed: {}", .{err});
        return;
    };
    log.info("Swap chain handle bound to SwapChainPanel (UI thread)", .{});
}

const min_bind_dimension: u32 = 2;

fn maybeBindPendingSwapChain(self: *Surface, caller: []const u8) void {
    const sc = self.pending_swap_chain orelse return;
    if (!self.loaded) {
        log.info("{s}: panel not loaded yet, keeping swap chain deferred", .{caller});
        return;
    }
    if (self.size.width >= min_bind_dimension and self.size.height >= min_bind_dimension) {
        log.info(
            "{s}: binding deferred swap chain at size {}x{}",
            .{ caller, self.size.width, self.size.height },
        );
        self.completeBindSwapChain(sc);
        return;
    }

    log.info(
        "{s}: keeping swap chain deferred until panel size is >= {}x{} (current={}x{})",
        .{ caller, min_bind_dimension, min_bind_dimension, self.size.width, self.size.height },
    );
}

fn maybeBindPendingSwapChainHandle(self: *Surface, caller: []const u8) void {
    const h = self.pending_swap_chain_handle orelse return;
    if (!self.loaded) {
        log.info("{s}: panel not loaded yet, keeping swap chain handle deferred", .{caller});
        return;
    }
    if (self.size.width >= min_bind_dimension and self.size.height >= min_bind_dimension) {
        log.info(
            "{s}: binding deferred swap chain handle at size {}x{}",
            .{ caller, self.size.width, self.size.height },
        );
        self.completeBindSwapChainHandle(h);
        return;
    }

    log.info(
        "{s}: keeping swap chain handle deferred until panel size is >= {}x{} (current={}x{})",
        .{ caller, min_bind_dimension, min_bind_dimension, self.size.width, self.size.height },
    );
}

/// Called from App.performAction(.scrollbar) on the UI thread.
pub fn updateScrollbarUi(self: *Surface, total: usize, offset: usize, len: usize) void {
    const sb = self.scroll_bar_insp orelse return;
    self.is_internal_scroll_update = true;
    defer {
        self.is_internal_scroll_update = false;
    }

    const range_base = sb.queryInterface(com.IRangeBase) catch |err| {
        log.warn("scrollbar ui sync: IRangeBase QI failed: {}", .{err});
        return;
    };
    defer range_base.release();

    const total_f: f64 = @floatFromInt(total);
    const offset_f: f64 = @floatFromInt(offset);
    const len_f: f64 = @floatFromInt(len);
    const maximum = if (total_f > len_f) total_f - len_f else 0.0;

    range_base.setMinimum(0.0) catch {};
    range_base.setMaximum(maximum) catch {};
    range_base.setValue(offset_f) catch {};
    range_base.setLargeChange(len_f) catch {};
    range_base.setSmallChange(1.0) catch {};

    const isb = sb.queryInterface(com.IScrollBar) catch |err| {
        log.warn("scrollbar ui sync: IScrollBar QI failed: {}", .{err});
        return;
    };
    defer isb.release();
    isb.setViewportSize(len_f) catch {};

    const fe = sb.queryInterface(com.IFrameworkElement) catch |err| {
        log.warn("scrollbar ui sync: IFrameworkElement QI failed: {}", .{err});
        return;
    };
    defer fe.release();
    const ue = sb.queryInterface(com.IUIElement) catch |err| {
        log.warn("scrollbar ui sync: IUIElement QI failed: {}", .{err});
        return;
    };
    defer ue.release();

    const orientation = isb.getOrientation() catch -1;
    const viewport = isb.getViewportSize() catch -1.0;
    const width = fe.ActualWidth() catch -1.0;
    const height = fe.ActualHeight() catch -1.0;
    const visibility = ue.Visibility() catch -1;
    log.debug(
        "scrollbar ui sync: orientation={} viewport={d:.2} actual={d:.2}x{d:.2} visibility={} max={d:.2} value={d:.2} len={d:.2}",
        .{ orientation, viewport, width, height, visibility, maximum, offset_f, len_f },
    );
}

/// ScrollBar.Scroll event callback.
fn onScrollBarScroll(self: *Surface, _: ?*anyopaque, args_raw: ?*anyopaque) void {
    if (self.is_internal_scroll_update) return;

    const args: *com.IScrollEventArgs = @ptrCast(@alignCast(args_raw orelse return));
    const new_value = args.getNewValue() catch return;
    const row: usize = @intFromFloat(@max(0.0, @round(new_value)));

    _ = self.core_surface.performBindingAction(.{ .scroll_to_row = row }) catch |err| {
        log.warn("scrollbar scroll_to_row failed: {}", .{err});
    };
}

/// Loaded event callback. Triggered when the SwapChainPanel is added to the visual tree.
fn onLoaded(self: *Surface, _: *anyopaque, _: *anyopaque) void {
    if (self.in_loaded_handler) return;
    self.in_loaded_handler = true;
    defer self.in_loaded_handler = false;

    // Guard: ensureVisibleSurfaceAttached does clear+append on tab content,
    // which re-fires Loaded asynchronously via the XAML event queue.
    // Only run the full handler on the first Loaded event.
    if (self.loaded) {
        return;
    }

    log.info(
        "SwapChainPanel.Loaded event fired surface=0x{x} size={}x{} pending_swap_chain={} last_swap_chain={}",
        .{ @intFromPtr(self), self.size.width, self.size.height, self.pending_swap_chain != null, self.last_swap_chain != null },
    );
    self.loaded = true;

    // Keep deferred binding until we have a non-trivial cached size.
    // `onSizeChanged` may fire before `Loaded`, so we also retry here.
    maybeBindPendingSwapChain(self, "onLoaded");
    maybeBindPendingSwapChainHandle(self, "onLoaded");
    // In TabView mode, enforce that the active tab item still points to this panel.
    self.app.ensureVisibleSurfaceAttached(self);
}

/// SizeChanged event callback. Triggered when the SwapChainPanel's layout size changes.
/// This gives us the actual panel dimensions (accounting for TabView header, etc.).
fn onSizeChanged(self: *Surface, _: *anyopaque, _: *anyopaque) void {
    log.info(
        "SwapChainPanel.SizeChanged event fired surface=0x{x} size={}x{} pending_swap_chain={} last_swap_chain={}",
        .{ @intFromPtr(self), self.size.width, self.size.height, self.pending_swap_chain != null, self.last_swap_chain != null },
    );
    maybeBindPendingSwapChain(self, "onSizeChanged");
    maybeBindPendingSwapChainHandle(self, "onSizeChanged");
}

/// Re-apply the current swap chain to this panel.
/// Useful when the panel is reparented/shown by TabView selection changes.
pub fn rebindSwapChain(self: *Surface) void {
    if (self.last_swap_chain_handle) |h| {
        self.bindSwapChainHandle(h);
        return;
    }
    const sc = self.last_swap_chain orelse return;
    // Rebind requests may arrive before the panel is realized (e.g. TabView
    // selection changes during initial layout). Route through bindSwapChain
    // so Loaded-gating remains effective.
    self.bindSwapChain(sc);
}

// --- Parity Audit / Apprt interface methods ---

pub fn setMouseShape(self: *Surface, shape: terminal.MouseShape) void {
    _ = self;
    log.info("Surface.setMouseShape: {s}", .{@tagName(shape)});
    const cursor_id = cursorIdForShape(shape);
    const cursor = os.LoadCursorW(null, cursor_id) orelse {
        log.warn("Surface.setMouseShape: LoadCursorW failed for shape={s}", .{@tagName(shape)});
        return;
    };
    _ = os.SetCursor(cursor);
}

pub fn setProgressReport(self: *Surface, value: terminal.osc.Command.ProgressReport) void {
    _ = self;
    log.info("Surface.setProgressReport: state={s} progress={?}", .{ @tagName(value.state), value.progress });

    // Minimal runtime behavior until taskbar integration is implemented:
    // emit an audible signal on explicit error state.
    if (value.state == .@"error") {
        _ = os.MessageBeep(os.MB_OK);
    }
}

pub fn commandFinished(self: *Surface, value: apprt.Action.Value(.command_finished)) bool {
    _ = self;
    log.info("Surface.commandFinished: duration={}ns", .{value.duration.duration});

    // Minimal notification: command failure emits an audible signal.
    if (value.exit_code) |code| {
        if (code != 0) _ = os.MessageBeep(os.MB_OK);
    }
    return true;
}

pub fn setBellRinging(self: *Surface, value: bool) void {
    _ = self;
    if (value) {
        log.info("Surface.setBellRinging: Ringing visual/audio bell", .{});
        // Win32 MessageBeep or Visual flash
        _ = os.MessageBeep(os.MB_OK);
    }
}

/// Compute a fraction [0.0, 1.0] from the supplied progress, which is clamped
/// to [0, 100].
fn computeFraction(progress: u8) f64 {
    return @as(f64, @floatFromInt(std.math.clamp(progress, 0, 100))) / 100.0;
}

test "computeFraction" {
    try std.testing.expectEqual(@as(f64, 1.0), computeFraction(100));
    try std.testing.expectEqual(@as(f64, 1.0), computeFraction(255));
    try std.testing.expectEqual(@as(f64, 0.0), computeFraction(0));
    try std.testing.expectEqual(@as(f64, 0.5), computeFraction(50));
}

fn cursorIdForShape(shape: terminal.MouseShape) os.LPCWSTR {
    return switch (shape) {
        .default, .context_menu, .pointer, .alias, .copy, .grab, .grabbing, .zoom_in, .zoom_out => os.IDC_ARROW,
        .text, .vertical_text, .cell => os.IDC_IBEAM,
        .help => os.IDC_HELP,
        .progress => os.IDC_APPSTARTING,
        .wait => os.IDC_WAIT,
        .crosshair => os.IDC_CROSS,
        .move, .all_scroll => os.IDC_SIZEALL,
        .no_drop, .not_allowed => os.IDC_NO,
        .col_resize, .e_resize, .w_resize, .ew_resize => os.IDC_SIZEWE,
        .row_resize, .n_resize, .s_resize, .ns_resize => os.IDC_SIZENS,
        .ne_resize, .sw_resize, .nesw_resize => os.IDC_SIZENESW,
        .nw_resize, .se_resize, .nwse_resize => os.IDC_SIZENWSE,
    };
}

test "Surface title memory management" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var app = App{
        .core_app = undefined,
        .surfaces = std.ArrayList(*Surface).init(alloc),
    };
    defer app.surfaces.deinit();

    var surface = Surface{
        .app = &app,
        .core_surface = undefined,
    };
    defer surface.deinit();

    surface.setTabTitle("Test Title 1");
    try testing.expectEqualStrings("Test Title 1", surface.title.?);

    surface.setTabTitle("Test Title 2 - Long title");
    try testing.expectEqualStrings("Test Title 2 - Long title", surface.title.?);
}
