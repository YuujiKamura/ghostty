/// WinUI 3 XAML Islands surface implementation for Ghostty.
///
/// D3D11 SwapChainPanel rendering is window-management-agnostic.
/// This is a copy of winui3/Surface.zig with import paths adjusted
/// to reference shared modules from ../winui3/ and the local App.zig.
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
const com = @import("../winui3/com.zig");
const winrt = @import("../winui3/winrt.zig");
const native_interop = @import("../winui3/native_interop.zig");
const input_runtime = @import("../winui3/input_runtime.zig");
const key = @import("../winui3/key.zig");
const os = @import("../winui3/os.zig");

const SearchOverlay = @import("search_overlay.zig").SearchOverlay;

const log = std.log.scoped(.winui3);

/// Set to true to enable verbose per-frame / per-event debug logs (scroll bar, etc.).
/// These are disabled by default to reduce Debug build overhead.
const log_hot_path = false;

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

/// Tracks XAML focus state to deduplicate focusCallback calls.
has_focus: bool = false,

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
ime_preview_key_down_token: i64 = 0,
ime_preview_key_up_token: i64 = 0,
ime_character_received_token: i64 = 0,
ime_text_changed_token: i64 = 0,
ime_got_focus_token: i64 = 0,
ime_lost_focus_token: i64 = 0,
ime_text_comp_start_token: i64 = 0,
ime_text_comp_change_token: i64 = 0,
ime_text_comp_end_token: i64 = 0,

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
/// Hidden XAML TextBox used as the WinUI3/TSF-backed IME focus target.
ime_text_box: ?*com.ITextBox = null,
ime_text_box_internal_update: bool = false,
ime_text_box_last_text: std.ArrayListUnmanaged(u16) = .{},
ime_text_box_sent_text: std.ArrayListUnmanaged(u16) = .{},
ime_text_box_composing: bool = false,
/// Event token for RangeBase.ValueChanged.
scroll_bar_value_changed_token: i64 = 0,
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
    self.app.setControlBackground(panel, .{ .A = 255, .R = 0, .G = 0, .B = 0 });

    // Create inner surface grid via LoadComponent + SurfaceRoot.xbf:
    // Layout is defined in compiled XAML (xbf), event hookup remains in Zig.
    {
        const grid_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Grid");
        defer winrt.deleteHString(grid_class);
        const grid_insp = try winrt.activateInstance(grid_class);
        errdefer _ = grid_insp.release();

        // Load SurfaceRoot.xbf into the Grid via LoadComponent.
        {
            const app_class = try winrt.hstring("Microsoft.UI.Xaml.Application");
            defer winrt.deleteHString(app_class);
            const app_statics = try winrt.getActivationFactory(com.IApplicationStatics, app_class);
            defer app_statics.release();

            const uri_class = try winrt.hstring("Windows.Foundation.Uri");
            defer winrt.deleteHString(uri_class);
            const uri_factory = try winrt.getActivationFactory(com.IUriRuntimeClassFactory, uri_class);
            defer uri_factory.release();

            // Use ms-appx:/// with .xaml extension — framework resolves to .xbf internally.
            const uri_str = try winrt.hstring("ms-appx:///Surface.xaml");
            defer winrt.deleteHString(uri_str);
            const uri = try uri_factory.createUri(uri_str);
            defer uri.release();

            try app_statics.loadComponent(@ptrCast(grid_insp), @ptrCast(uri));
            log.info("Surface.xbf loaded into Grid via LoadComponent", .{});
        }

        // Find ScrollBar by name from the loaded XAML tree.
        const root_fe = try grid_insp.queryInterface(com.IFrameworkElement);
        defer root_fe.release();

        const sb_name = try winrt.hstring("ScrollBar");
        defer winrt.deleteHString(sb_name);
        const sb_insp_raw = try root_fe.FindName(sb_name);
        const sb_insp: *winrt.IInspectable = @ptrCast(sb_insp_raw);
        errdefer _ = sb_insp.release();

        // Insert SwapChainPanel at position 0 in the Grid's children.
        const grid_panel = try grid_insp.queryInterface(com.IPanel);
        defer grid_panel.release();
        const grid_children_raw = try grid_panel.Children();
        const grid_children: *com.IVector = @ptrCast(@alignCast(grid_children_raw));
        defer grid_children.release();
        try grid_children.insertAt(0, @ptrCast(panel));

        // Register ValueChanged event on RangeBase (more reliable than Scroll event).
        // Windows Terminal also uses ValueChanged for scrollbar interaction.
        const range_base = try sb_insp.queryInterface(com.IRangeBase);
        defer range_base.release();
        const gen = @import("../winui3/com_generated.zig");
        const ValueChangedDelegate = gen.RangeBaseValueChangedEventHandlerImpl(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);
        const vc_delegate = try ValueChangedDelegate.createWithIid(
            self.app.core_app.alloc,
            self,
            &onScrollBarValueChanged,
            &com.IID_RangeBaseValueChangedEventHandler,
        );
        defer vc_delegate.release();
        self.scroll_bar_value_changed_token = try range_base.AddValueChanged(vc_delegate.comPtr());

        const ime_tb_insp = try self.app.activateXamlType("Microsoft.UI.Xaml.Controls.TextBox");
        errdefer _ = ime_tb_insp.release();
        const ime_tb = try ime_tb_insp.queryInterface(com.ITextBox);
        errdefer ime_tb.release();
        ime_tb.SetIsSpellCheckEnabled(false) catch {};
        ime_tb.SetIsTextPredictionEnabled(false) catch {};
        ime_tb.SetPreventKeyboardDisplayOnProgrammaticFocus(true) catch {};
        ime_tb.SetDesiredCandidateWindowAlignment(1) catch {}; // BottomEdge

        if (ime_tb_insp.queryInterface(com.IUIElement)) |ime_ue| {
            defer ime_ue.release();
            ime_ue.SetOpacity(0.01) catch {};
            ime_ue.SetIsHitTestVisible(true) catch {};
            ime_ue.SetIsTabStop(true) catch {};
            ime_ue.SetVisibility(0) catch {};
        } else |_| {}
        if (ime_tb_insp.queryInterface(com.IControl)) |ime_ctrl| {
            defer ime_ctrl.release();
            ime_ctrl.SetIsEnabled(true) catch {};
        } else |_| {}
        if (ime_tb_insp.queryInterface(com.IFrameworkElement)) |ime_fe| {
            defer ime_fe.release();
            ime_fe.SetWidth(16) catch {};
            ime_fe.SetHeight(16) catch {};
            ime_fe.SetHorizontalAlignment(com.HorizontalAlignment.Left) catch {};
            ime_fe.SetVerticalAlignment(com.VerticalAlignment.Top) catch {};
            ime_fe.SetAllowFocusOnInteraction(true) catch {};
            ime_fe.SetMargin(.{ .Left = 0, .Top = 0, .Right = 0, .Bottom = 0 }) catch {};
        } else |_| {}

        try grid_children.append(@ptrCast(ime_tb_insp));

        // Store references.
        self.surface_grid = grid_insp;
        self.scroll_bar_insp = sb_insp;
        self.ime_text_box = ime_tb;
        _ = ime_tb_insp.release();

        log.info("Surface grid created via LoadComponent (SurfaceRoot.xbf): SwapChainPanel + ScrollBar + hidden IME TextBox", .{});
    }

    // Register Loaded handler to defer SetSwapChain until the panel is ready.
    const framework_element = try panel.queryInterface(com.IFrameworkElement);
    defer framework_element.release();
    const gen = @import("../winui3/com_generated.zig");
    const LoadedDelegate = gen.RoutedEventHandlerImpl(Surface, *const fn (*Surface, *anyopaque, *anyopaque) void);
    const loaded_delegate = try LoadedDelegate.createWithIid(self.app.core_app.alloc, self, &onLoaded, &com.IID_RoutedEventHandler);
    // Note: LoadedDelegate.createWithIid returns a ref-counted COM object.
    // We pass it to addLoaded which will AddRef it again.
    defer loaded_delegate.release();
    self.loaded_token = try framework_element.AddLoaded(loaded_delegate.comPtr());

    const SizeChangedDelegate = gen.SizeChangedEventHandlerImpl(Surface, *const fn (*Surface, *anyopaque, *anyopaque) void);
    const size_changed_delegate = try SizeChangedDelegate.createWithIid(
        self.app.core_app.alloc,
        self,
        &onSizeChanged,
        &com.IID_SizeChangedEventHandler,
    );
    defer size_changed_delegate.release();
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

        const PointerDelegate = gen.PointerEventHandlerImpl(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);
        const KeyDelegate = gen.KeyEventHandlerImpl(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);
        const RoutedDelegate = gen.RoutedEventHandlerImpl(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);
        const CharRecvDelegate = gen.TypedEventHandlerImpl(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);

        // Pointer events
        const ptr_pressed = try PointerDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerPressed, &com.IID_PointerEventHandler);
        defer ptr_pressed.release();
        self.pointer_pressed_token = ui_element.AddPointerPressed(ptr_pressed.comPtr()) catch 0;

        const ptr_moved = try PointerDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerMoved, &com.IID_PointerEventHandler);
        defer ptr_moved.release();
        self.pointer_moved_token = ui_element.AddPointerMoved(ptr_moved.comPtr()) catch 0;

        const ptr_released = try PointerDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerReleased, &com.IID_PointerEventHandler);
        defer ptr_released.release();
        self.pointer_released_token = ui_element.AddPointerReleased(ptr_released.comPtr()) catch 0;

        const ptr_wheel = try PointerDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerWheelChanged, &com.IID_PointerEventHandler);
        defer ptr_wheel.release();
        self.pointer_wheel_changed_token = ui_element.AddPointerWheelChanged(ptr_wheel.comPtr()) catch 0;

        // Keyboard events (PreviewKeyDown catches navigation keys before XAML consumes them)
        const key_down = try KeyDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPreviewKeyDown, &com.IID_KeyEventHandler);
        defer key_down.release();
        self.preview_key_down_token = ui_element.AddPreviewKeyDown(key_down.comPtr()) catch 0;

        const key_up = try KeyDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPreviewKeyUp, &com.IID_KeyEventHandler);
        defer key_up.release();
        self.preview_key_up_token = ui_element.AddPreviewKeyUp(key_up.comPtr()) catch 0;

        // CharacterReceived — text input (uses generated TypedEventHandlerImpl)
        const char_recv = try CharRecvDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlCharacterReceived, &com.IID_CharacterReceivedHandler);
        defer char_recv.release();
        self.character_received_token = ui_element.AddCharacterReceived(char_recv.comPtr()) catch 0;

        // Focus events
        const got_focus = try RoutedDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlGotFocus, &com.IID_RoutedEventHandler);
        defer got_focus.release();
        self.got_focus_token = ui_element.AddGotFocus(got_focus.comPtr()) catch 0;

        const lost_focus = try RoutedDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlLostFocus, &com.IID_RoutedEventHandler);
        defer lost_focus.release();
        self.lost_focus_token = ui_element.AddLostFocus(lost_focus.comPtr()) catch 0;
    }

    if (self.ime_text_box) |ime_tb| {
        if (ime_tb.queryInterface(com.IUIElement)) |ime_ue| {
            defer ime_ue.release();
            const ImeKeyDelegate = gen.KeyEventHandlerImpl(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);
            const ImeRoutedDelegate = gen.RoutedEventHandlerImpl(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);
            const ImeCharRecvDelegate = gen.TypedEventHandlerImpl(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);

            const ime_key_down = try ImeKeyDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxPreviewKeyDown, &com.IID_KeyEventHandler);
            defer ime_key_down.release();
            self.ime_preview_key_down_token = ime_ue.AddPreviewKeyDown(ime_key_down.comPtr()) catch 0;

            const ime_key_up = try ImeKeyDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxPreviewKeyUp, &com.IID_KeyEventHandler);
            defer ime_key_up.release();
            self.ime_preview_key_up_token = ime_ue.AddPreviewKeyUp(ime_key_up.comPtr()) catch 0;

            const ime_char_recv = try ImeCharRecvDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxCharacterReceived, &com.IID_CharacterReceivedHandler);
            defer ime_char_recv.release();
            self.ime_character_received_token = ime_ue.AddCharacterReceived(ime_char_recv.comPtr()) catch 0;

            const ime_got_focus = try ImeRoutedDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxGotFocus, &com.IID_RoutedEventHandler);
            defer ime_got_focus.release();
            self.ime_got_focus_token = ime_ue.AddGotFocus(ime_got_focus.comPtr()) catch 0;

            const ime_lost_focus = try ImeRoutedDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxLostFocus, &com.IID_RoutedEventHandler);
            defer ime_lost_focus.release();
            self.ime_lost_focus_token = ime_ue.AddLostFocus(ime_lost_focus.comPtr()) catch 0;
        } else |_| {}

        const TextChangedDelegate = gen.TextChangedEventHandlerImpl(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);
        const ime_text_changed = try TextChangedDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxTextChanged, &com.IID_TextChangedEventHandler);
        defer ime_text_changed.release();
        self.ime_text_changed_token = ime_tb.AddTextChanged(ime_text_changed.comPtr()) catch 0;

        const CompositionDelegate = gen.TypedEventHandlerImpl(Surface, *const fn (*Surface, ?*anyopaque, ?*anyopaque) void);
        const comp_start = try CompositionDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxCompositionStarted, &com.IID_TextCompositionStartedHandler);
        defer comp_start.release();
        self.ime_text_comp_start_token = ime_tb.AddTextCompositionStarted(comp_start.comPtr()) catch |err| blk: {
            log.warn("ime AddTextCompositionStarted failed: {}", .{err});
            break :blk 0;
        };

        const comp_change = try CompositionDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxCompositionChanged, &com.IID_TextCompositionChangedHandler);
        defer comp_change.release();
        self.ime_text_comp_change_token = ime_tb.AddTextCompositionChanged(comp_change.comPtr()) catch |err| blk: {
            log.warn("ime AddTextCompositionChanged failed: {}", .{err});
            break :blk 0;
        };

        const comp_end = try CompositionDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxCompositionEnded, &com.IID_TextCompositionEndedHandler);
        defer comp_end.release();
        self.ime_text_comp_end_token = ime_tb.AddTextCompositionEnded(comp_end.comPtr()) catch |err| blk: {
            log.warn("ime AddTextCompositionEnded failed: {}", .{err});
            break :blk 0;
        };
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
                if (self.pointer_pressed_token != 0) {
                    ue.RemovePointerPressed(self.pointer_pressed_token) catch {};
                }
                if (self.pointer_moved_token != 0) {
                    ue.RemovePointerMoved(self.pointer_moved_token) catch {};
                }
                if (self.pointer_released_token != 0) {
                    ue.RemovePointerReleased(self.pointer_released_token) catch {};
                }
                if (self.pointer_wheel_changed_token != 0) {
                    ue.RemovePointerWheelChanged(self.pointer_wheel_changed_token) catch {};
                }
                if (self.preview_key_down_token != 0) {
                    ue.RemovePreviewKeyDown(self.preview_key_down_token) catch {};
                }
                if (self.preview_key_up_token != 0) {
                    ue.RemovePreviewKeyUp(self.preview_key_up_token) catch {};
                }
                if (self.character_received_token != 0) {
                    ue.RemoveCharacterReceived(self.character_received_token) catch {};
                }
                if (self.got_focus_token != 0) {
                    ue.RemoveGotFocus(self.got_focus_token) catch {};
                }
                if (self.lost_focus_token != 0) {
                    ue.RemoveLostFocus(self.lost_focus_token) catch {};
                }
            } else |_| {}
        }
        native.release();
        self.swap_chain_panel_native = null;
    }
    if (self.ime_text_box) |ime_tb| {
        if (ime_tb.queryInterface(com.IUIElement)) |ime_ue| {
            defer ime_ue.release();
            if (self.ime_preview_key_down_token != 0) {
                ime_ue.RemovePreviewKeyDown(self.ime_preview_key_down_token) catch {};
            }
            if (self.ime_preview_key_up_token != 0) {
                ime_ue.RemovePreviewKeyUp(self.ime_preview_key_up_token) catch {};
            }
            if (self.ime_character_received_token != 0) {
                ime_ue.RemoveCharacterReceived(self.ime_character_received_token) catch {};
            }
            if (self.ime_got_focus_token != 0) {
                ime_ue.RemoveGotFocus(self.ime_got_focus_token) catch {};
            }
            if (self.ime_lost_focus_token != 0) {
                ime_ue.RemoveLostFocus(self.ime_lost_focus_token) catch {};
            }
        } else |_| {}
        if (self.ime_text_changed_token != 0) {
            ime_tb.RemoveTextChanged(self.ime_text_changed_token) catch {};
        }
        if (self.ime_text_comp_start_token != 0) {
            ime_tb.RemoveTextCompositionStarted(self.ime_text_comp_start_token) catch {};
        }
        if (self.ime_text_comp_change_token != 0) {
            ime_tb.RemoveTextCompositionChanged(self.ime_text_comp_change_token) catch {};
        }
        if (self.ime_text_comp_end_token != 0) {
            ime_tb.RemoveTextCompositionEnded(self.ime_text_comp_end_token) catch {};
        }
        self.ime_preview_key_down_token = 0;
        self.ime_preview_key_up_token = 0;
        self.ime_character_received_token = 0;
        self.ime_text_changed_token = 0;
        self.ime_got_focus_token = 0;
        self.ime_lost_focus_token = 0;
        self.ime_text_comp_start_token = 0;
        self.ime_text_comp_change_token = 0;
        self.ime_text_comp_end_token = 0;
    }
    // Release scrollbar and surface grid.
    if (self.scroll_bar_insp) |sb| {
        if (self.scroll_bar_value_changed_token != 0) {
            const rb = sb.queryInterface(com.IRangeBase) catch null;
            if (rb) |r| {
                defer r.release();
                r.RemoveValueChanged(self.scroll_bar_value_changed_token) catch {};
            }
            self.scroll_bar_value_changed_token = 0;
        }
        _ = sb.release();
        self.scroll_bar_insp = null;
    }
    if (self.surface_grid) |sg| {
        _ = sg.release();
        self.surface_grid = null;
    }
    if (self.ime_text_box) |ime_tb| {
        ime_tb.release();
        self.ime_text_box = null;
    }
    self.ime_text_box_last_text.deinit(self.app.core_app.alloc);
    self.ime_text_box_sent_text.deinit(self.app.core_app.alloc);
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

pub fn pwd(self: *Surface, alloc: std.mem.Allocator) !?[]const u8 {
    if (!self.core_initialized) return null;
    return try self.core_surface.pwd(alloc);
}

pub fn hasSelection(self: *const Surface) bool {
    if (!self.core_initialized) return false;
    return self.core_surface.hasSelection();
}

pub fn cursorIsAtPrompt(self: *Surface) bool {
    if (!self.core_initialized) return false;
    return self.core_surface.cursorIsAtPrompt();
}

pub fn viewportString(self: *Surface, alloc: std.mem.Allocator) ![]const u8 {
    if (!self.core_initialized) return alloc.dupe(u8, "");
    return try self.core_surface.viewportString(alloc);
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
                    const util = @import("../winui3/util.zig");
                    if (util.boxString(hstr)) |boxed| {
                        defer _ = boxed.release();
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
    App.fileLog("Surface.updateSize: {}x{} -> {}x{}", .{ self.size.width, self.size.height, width, height });
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
        // Control characters (Enter, Tab, Backspace, Escape) have non-zero
        // unshifted codepoints but must NOT be deferred as text keys —
        // they need immediate keyCallback processing.
        const is_control_char = unshifted != 0 and unshifted < 0x20;
        const is_text_key = !ghostty_key.modifier() and
            !binding_mods.ctrl and !binding_mods.alt and !binding_mods.super and
            unshifted != 0 and !is_control_char;

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

    // keyCallback may trigger close_tab, which destroys this Surface.
    // Save app pointer before the call so we can check liveness after.
    const app_ref = self.app;
    _ = self.core_surface.keyCallback(event) catch |err| {
        log.warn("key callback error vk=0x{X:0>2}: {}", .{ vk, err });
        return;
    };

    // If keyCallback destroyed this surface (e.g. close_tab binding),
    // self is freed memory — do not access it.
    if (!isSurfaceAlive(app_ref, self)) return;

    // Suppress any subsequent WM_CHAR for consumed press events.
    // (Releases don't produce WM_CHAR.)
    if (pressed) {
        self.pending_keydown = .consumed;
    }
}

/// Check if a Surface pointer is still in the app's surface list.
/// Used to detect use-after-free when a keybinding destroys the surface
/// during keyCallback (e.g. close_tab).
fn isSurfaceAlive(app: *App, surface: *const Surface) bool {
    for (app.surfaces.items) |s| {
        if (s == surface) return true;
    }
    return false;
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
    App.fileLog("onXamlPointerPressed: core_initialized={}", .{self.core_initialized});
    if (!self.core_initialized) return;
    const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const point = ea.getCurrentPoint(null) catch return;
    defer point.release();
    const pos = point.Position() catch return;
    self.handleMouseMove(@floatCast(pos.X), @floatCast(pos.Y));
    const props = point.Properties() catch return;
    defer props.release();
    const update_kind = props.PointerUpdateKind() catch return;
    const button: input.MouseButton = switch (update_kind) {
        1 => .left, // LeftButtonPressed
        3 => .right, // RightButtonPressed
        5 => .middle, // MiddleButtonPressed
        else => return,
    };
    // Keep the hidden ime_text_box as the single WinUI3 text owner so TSF
    // handles both normal text and IME composition on one path.
    if (!self.app.resizing) {
        input_runtime.focusKeyboardTarget(self.app);
    }
    self.handleMouseButton(button, .press);
    ea.SetHandled(true) catch {};
}

fn onXamlPointerMoved(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const point = ea.getCurrentPoint(null) catch return;
    defer point.release();
    const pos = point.Position() catch return;
    self.handleMouseMove(@floatCast(pos.X), @floatCast(pos.Y));
    ea.SetHandled(true) catch {};
}

fn onXamlPointerReleased(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const point = ea.getCurrentPoint(null) catch return;
    defer point.release();
    const pos = point.Position() catch return;
    self.handleMouseMove(@floatCast(pos.X), @floatCast(pos.Y));
    const props = point.Properties() catch return;
    defer props.release();
    const update_kind = props.PointerUpdateKind() catch return;
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
    ea.SetHandled(true) catch {};
}

fn onXamlPointerWheelChanged(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const point = ea.getCurrentPoint(null) catch return;
    defer point.release();
    const props = point.Properties() catch return;
    defer props.release();
    const delta = props.MouseWheelDelta() catch return;
    const is_horizontal = props.IsHorizontalMouseWheel() catch false;

    // Ctrl+Wheel = font size change (Windows Terminal behavior).
    if (!is_horizontal and key.getModifiers().ctrl) {
        if (delta > 0) {
            _ = self.core_surface.performBindingAction(.{ .increase_font_size = 1 }) catch {};
        } else if (delta < 0) {
            _ = self.core_surface.performBindingAction(.{ .decrease_font_size = 1 }) catch {};
        }
        ea.SetHandled(true) catch {};
        return;
    }

    const offset = @as(f64, @floatFromInt(delta)) / 120.0;
    if (is_horizontal) {
        self.handleScroll(offset, 0);
    } else {
        self.handleScroll(0, offset);
    }
    ea.SetHandled(true) catch {};
}

fn onXamlPreviewKeyDown(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const vk = ea.Key() catch return;
    const vk_u32 = @as(u32, @bitCast(vk));
    App.fileLog("xaml_surface: PreviewKeyDown vk=0x{x}", .{vk_u32});
    if (isImePassthroughVirtualKey(vk_u32)) {
        // IME toggle/mode key or VK_PROCESSKEY — focus the XAML ime_text_box
        // which handles IME composition via TSF. The TextBox has an IME context
        // associated with it; the SwapChainPanel does not, so IME toggle keys
        // must be forwarded to the TextBox to actually activate/deactivate IME.
        App.fileLog("PreviewKeyDown: IME key 0x{x} -> focusImeTextBox", .{vk_u32});
        self.app.keyboard_focus_target = .ime_text_box;
        _ = self.focusImeTextBox();
        return; // Don't mark handled — let IME process.
    }
    // Save app pointer before handleKeyEvent — a keybinding (e.g. close_tab)
    // may destroy this Surface, freeing self.
    const app_ref = self.app;
    self.handleKeyEvent(@intCast(@as(u32, @bitCast(vk))), true);
    // If the surface was destroyed during handleKeyEvent, self is freed.
    if (!isSurfaceAlive(app_ref, self)) return;
    // For text-producing keys, handleKeyEvent defers to CharacterReceived by
    // leaving pending_keydown=.pending. Do not mark those handled here or the
    // character event is suppressed.
    switch (self.pending_keydown) {
        .pending => {},
        else => ea.SetHandled(true) catch {},
    }
}

fn onXamlPreviewKeyUp(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const vk = ea.Key() catch return;
    const app_ref = self.app;
    self.handleKeyEvent(@intCast(@as(u32, @bitCast(vk))), false);
    if (!isSurfaceAlive(app_ref, self)) return;
    ea.SetHandled(true) catch {};
}

fn onXamlCharacterReceived(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.ICharacterReceivedRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const ch = ea.Character() catch return;
    App.fileLog("xaml_surface: CharacterReceived ch=0x{x}", .{ch});
    const app_ref = self.app;
    self.handleCharEvent(ch);
    if (!isSurfaceAlive(app_ref, self)) return;
    ea.SetHandled(true) catch {};
}

fn onImeTextBoxPreviewKeyDown(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const vk = ea.Key() catch return;
    const vk_u32 = @as(u32, @bitCast(vk));
    App.fileLog("ime_text_box: PreviewKeyDown vk=0x{x} focus_target={s}", .{ vk_u32, @tagName(self.app.keyboard_focus_target) });
    // Let IME passthrough keys (e.g. VK_PROCESSKEY, IME toggle) be handled
    // by the TextBox so IME composition works correctly.
    if (isImePassthroughVirtualKey(vk_u32)) return;
    // ime_text_box is NOT inside SwapChainPanel's visual tree, so
    // SwapChainPanel's PreviewKeyDown does NOT fire for these keys.
    const app_ref = self.app;
    self.handleKeyEvent(@intCast(vk_u32), true);
    if (!isSurfaceAlive(app_ref, self)) return;
    // Text keys (a-z, 0-9, etc.): handleKeyEvent sets pending_keydown = .pending
    // and defers to CharacterReceived/TextChanged. Do NOT SetHandled — let the
    // TextBox process the character so TextChanged fires and sends it to PTY.
    // Non-text keys (Enter, Tab, arrows, F-keys): handleKeyEvent calls
    // keyCallback immediately. SetHandled to prevent TextBox from consuming
    // them (e.g. Enter as newline, Tab as indent).
    switch (self.pending_keydown) {
        .pending => {}, // Text key — let TextBox handle it for CharacterReceived/TextChanged
        else => ea.SetHandled(true) catch {}, // Non-text key — block TextBox
    }
}

fn onImeTextBoxPreviewKeyUp(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const vk = ea.Key() catch return;
    const vk_u32 = @as(u32, @bitCast(vk));
    if (isImePassthroughVirtualKey(vk_u32)) return;
    const app_ref = self.app;
    self.handleKeyEvent(@intCast(vk_u32), false);
    if (!isSurfaceAlive(app_ref, self)) return;
    ea.SetHandled(true) catch {};
}

fn onImeTextBoxCharacterReceived(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    if (self.app.keyboard_focus_target != .ime_text_box) return;
    const ea: *com.ICharacterReceivedRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
    const ch = ea.Character() catch return;
    App.fileLog("ime_text_box: CharacterReceived ch=0x{x} (deferred to TextChanged)", .{ch});
}

fn onImeTextBoxTextChanged(self: *Surface, _: ?*anyopaque, _: ?*anyopaque) void {
    if (!self.core_initialized) return;
    if (self.app.keyboard_focus_target != .ime_text_box) return;
    if (self.ime_text_box_internal_update) return;
    const ime_tb = self.ime_text_box orelse return;
    const text_h = ime_tb.Text() catch return;
    defer if (text_h) |h| winrt.deleteHString(@ptrCast(h));
    const utf16 = winrt.hstringSliceRaw(text_h);
    const prev = self.ime_text_box_last_text.items;
    const sent = self.ime_text_box_sent_text.items;
    if (utf16.len == 0) {
        self.ime_text_box_last_text.clearRetainingCapacity();
        if (!self.ime_text_box_composing) self.ime_text_box_sent_text.clearRetainingCapacity();
        return;
    }

    const append_only = commonPrefixLen(u16, prev, utf16) == prev.len and utf16.len > prev.len;
    App.fileLog(
        "ime_text_box: TextChanged utf16_len={} prev_len={} sent_len={} composing={} append_only={} append_len={}",
        .{
            utf16.len,
            prev.len,
            sent.len,
            self.ime_text_box_composing,
            append_only,
            if (append_only) utf16.len - prev.len else 0,
        },
    );

    self.setImeTextBoxSnapshot(utf16);
    if (self.ime_text_box_composing) return;
    self.flushImeTextBoxCommittedDelta(utf16);
}

fn onImeTextBoxCompositionStarted(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.ITextCompositionStartedEventArgs = @ptrCast(@alignCast(args orelse return));
    const start = ea.StartIndex() catch -1;
    const len = ea.Length() catch -1;
    self.ime_text_box_composing = true;
    App.fileLog("ime_text_box: CompositionStarted start={} len={}", .{ start, len });
}

fn onImeTextBoxCompositionChanged(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.ITextCompositionChangedEventArgs = @ptrCast(@alignCast(args orelse return));
    const start = ea.StartIndex() catch -1;
    const len = ea.Length() catch -1;
    self.ime_text_box_composing = true;
    App.fileLog("ime_text_box: CompositionChanged start={} len={}", .{ start, len });

    // Extract composition text from TextBox and show as preedit
    if (start >= 0 and len > 0) {
        const ime_tb = self.ime_text_box orelse return;
        const text_h = ime_tb.Text() catch return;
        defer if (text_h) |h| winrt.deleteHString(@ptrCast(h));
        const utf16 = winrt.hstringSliceRaw(text_h);
        const ustart: usize = @intCast(start);
        const ulen: usize = @intCast(len);
        if (ustart + ulen <= utf16.len) {
            const comp_utf16 = utf16[ustart..ustart + ulen];
            // Convert UTF-16 to UTF-8 for preeditCallback
            var utf8_buf: [256]u8 = undefined;
            var utf8_len: usize = 0;
            for (comp_utf16) |cu| {
                if (utf8_len + 4 > utf8_buf.len) break;
                const cp: u21 = cu;
                const seq_len = std.unicode.utf8Encode(cp, utf8_buf[utf8_len..]) catch break;
                utf8_len += seq_len;
            }
            if (utf8_len > 0) {
                self.core_surface.preeditCallback(utf8_buf[0..utf8_len]) catch {};
            }
        }
    }
}

fn onImeTextBoxCompositionEnded(self: *Surface, _: ?*anyopaque, args: ?*anyopaque) void {
    if (!self.core_initialized) return;
    const ea: *com.ITextCompositionEndedEventArgs = @ptrCast(@alignCast(args orelse return));
    const start = ea.StartIndex() catch -1;
    const len = ea.Length() catch -1;
    self.ime_text_box_composing = false;
    App.fileLog("ime_text_box: CompositionEnded start={} len={}", .{ start, len });
    // Clear preedit display
    self.core_surface.preeditCallback(null) catch {};
    self.flushImeTextBoxCommittedText();
}

fn onXamlGotFocus(self: *Surface, _: ?*anyopaque, _: ?*anyopaque) void {
    if (!self.core_initialized) return;
    if (!self.has_focus) {
        self.has_focus = true;
        log.info("XAML GotFocus on SwapChainPanel surface=0x{x}", .{@intFromPtr(self)});
        self.core_surface.focusCallback(true) catch |err| {
            log.warn("focusCallback(true) error: {}", .{err});
        };
    }
    // Always redirect XAML focus from SwapChainPanel to the hidden IME TextBox.
    // The TextBox has a TSF/IME context; without this, IME toggle keys
    // (Hankaku/Zenkaku, Alt+`, etc.) have no IME context to act on and are
    // silently swallowed.
    if (self.app.keyboard_focus_target == .ime_text_box) {
        _ = self.focusImeTextBox();
    }

    // TSF focus: matching Windows Terminal's _GotFocusHandler pattern.
    // Done via XAML event (not Win32 WM_SETFOCUS) to avoid recursive message crashes.
    if (self.app.tsf_impl) |*tsf| {
        tsf.focus();
    }
}

fn onXamlLostFocus(self: *Surface, _: ?*anyopaque, _: ?*anyopaque) void {
    if (!self.core_initialized) return;
    if (self.app.keyboard_focus_target == .ime_text_box) {
        App.fileLog("SwapChainPanel LostFocus ignored: IME text box now owns focus", .{});
        return;
    }
    if (!self.has_focus) return; // deduplicate
    self.has_focus = false;
    log.info("XAML LostFocus on SwapChainPanel surface=0x{x}", .{@intFromPtr(self)});
    self.core_surface.focusCallback(false) catch |err| {
        log.warn("focusCallback(false) error: {}", .{err});
    };
}

fn onImeTextBoxGotFocus(self: *Surface, _: ?*anyopaque, _: ?*anyopaque) void {
    if (!self.core_initialized) return;
    App.fileLog("ime_text_box: GotFocus", .{});
    self.logImeTextBoxState("ime_text_box: GotFocus");
    if (self.has_focus) return;
    self.has_focus = true;
    self.core_surface.focusCallback(true) catch |err| {
        log.warn("ime_text_box focusCallback(true) error: {}", .{err});
    };
}

fn onImeTextBoxLostFocus(self: *Surface, _: ?*anyopaque, _: ?*anyopaque) void {
    if (!self.core_initialized) return;
    App.fileLog("ime_text_box: LostFocus keyboard_focus_target={s}", .{@tagName(self.app.keyboard_focus_target)});
    if (self.app.keyboard_focus_target != .ime_text_box) return;
    if (!self.has_focus) return;
    self.has_focus = false;
    self.core_surface.focusCallback(false) catch |err| {
        log.warn("ime_text_box focusCallback(false) error: {}", .{err});
    };

    // TSF unfocus: matching Windows Terminal's _LostFocusHandler pattern.
    // Done via XAML event (not Win32 WM_KILLFOCUS) to avoid recursive message crashes.
    if (self.app.tsf_impl) |*tsf| {
        tsf.unfocus();
    }
}

/// Request XAML focus on the SwapChainPanel (called from ime.zig after IME ends).
pub fn focusSwapChainPanel(self: *Surface) void {
    if (self.swap_chain_panel) |panel| {
        if (panel.queryInterface(com.IUIElement)) |ue| {
            defer ue.release();
            const result = ue.focus(com.FocusState.Programmatic);
            if (result) |ok| {
                App.fileLog("focusSwapChainPanel: focus() returned {}", .{ok});
            } else |err| {
                App.fileLog("focusSwapChainPanel: focus() FAILED: {}", .{@intFromError(err)});
            }
        } else |err| {
            App.fileLog("focusSwapChainPanel: QI IUIElement FAILED: {}", .{@intFromError(err)});
        }
    } else {
        App.fileLog("focusSwapChainPanel: no swap_chain_panel!", .{});
    }
}

pub fn focusImeTextBox(self: *Surface) bool {
    const ime_tb = self.ime_text_box orelse {
        App.fileLog("focusImeTextBox: no ime_text_box", .{});
        return false;
    };
    self.clearImeTextBoxText();
    self.positionImeTextBox();
    self.logImeTextBoxState("focusImeTextBox: before focus");
    if (ime_tb.queryInterface(com.IUIElement)) |ime_ue| {
        defer ime_ue.release();
        const result = ime_ue.focus(com.FocusState.Programmatic);
        if (result) |ok| {
            App.fileLog("focusImeTextBox: focus() returned {}", .{ok});
            self.logImeTextBoxState("focusImeTextBox: after focus");
            return ok;
        } else |err| {
            App.fileLog("focusImeTextBox: focus() FAILED: {}", .{@intFromError(err)});
        }
    } else |err| {
        App.fileLog("focusImeTextBox: QI IUIElement FAILED: {}", .{@intFromError(err)});
    }
    return false;
}

pub fn clearImeTextBoxText(self: *Surface) void {
    const ime_tb = self.ime_text_box orelse {
        App.fileLog("clearImeTextBoxText: no ime_text_box", .{});
        return;
    };
    // WinRT: null HSTRING == empty string. winrt.hstring("") may fail
    // because WindowsCreateString with length 0 returns null HSTRING,
    // which our wrapper rejects. Pass null directly.
    const empty: ?*anyopaque = null;
    const prev_sent = self.ime_text_box_sent_text.items.len;
    const prev_last = self.ime_text_box_last_text.items.len;
    self.ime_text_box_internal_update = true;
    defer self.ime_text_box_internal_update = false;
    if (ime_tb.SetText(empty)) |_| {
        self.ime_text_box_last_text.clearRetainingCapacity();
        self.ime_text_box_sent_text.clearRetainingCapacity();
        self.ime_text_box_composing = false;
        App.fileLog("clearImeTextBoxText: cleared sent={}->{} last={}->{}", .{
            prev_sent, self.ime_text_box_sent_text.items.len,
            prev_last, self.ime_text_box_last_text.items.len,
        });
    } else |err| {
        App.fileLog("clearImeTextBoxText: SetText FAILED: {}", .{@intFromError(err)});
    }
    ime_tb.Select(0, 0) catch |err| {
        App.fileLog("clearImeTextBoxText: Select FAILED: {}", .{@intFromError(err)});
    };
}

fn positionImeTextBox(self: *Surface) void {
    if (!self.core_initialized) return;
    const ime_tb = self.ime_text_box orelse return;
    const ime_pos = self.core_surface.imePoint();
    const scale_x: f64 = if (self.content_scale.x > 0) @as(f64, @floatCast(self.content_scale.x)) else 1.0;
    const scale_y: f64 = if (self.content_scale.y > 0) @as(f64, @floatCast(self.content_scale.y)) else 1.0;
    const margin = com.Thickness{
        .Left = @as(f64, @floatCast(ime_pos.x)) / scale_x,
        .Top = @as(f64, @floatCast(ime_pos.y)) / scale_y,
        .Right = 0,
        .Bottom = 0,
    };
    if (ime_tb.queryInterface(com.IFrameworkElement)) |ime_fe| {
        defer ime_fe.release();
        ime_fe.SetMargin(margin) catch {};
    } else |_| {}
}

fn setImeTextBoxSnapshot(self: *Surface, utf16: []const u16) void {
    self.ime_text_box_last_text.resize(self.app.core_app.alloc, utf16.len) catch {
        App.fileLog("ime_text_box: snapshot resize failed len={}", .{utf16.len});
        return;
    };
    std.mem.copyForwards(u16, self.ime_text_box_last_text.items, utf16);
}

fn setImeTextBoxSentSnapshot(self: *Surface, utf16: []const u16) void {
    self.ime_text_box_sent_text.resize(self.app.core_app.alloc, utf16.len) catch {
        App.fileLog("ime_text_box: sent snapshot resize failed len={}", .{utf16.len});
        return;
    };
    std.mem.copyForwards(u16, self.ime_text_box_sent_text.items, utf16);
}

fn flushImeTextBoxCommittedText(self: *Surface) void {
    const ime_tb = self.ime_text_box orelse return;
    const text_h = ime_tb.Text() catch return;
    defer if (text_h) |h| winrt.deleteHString(@ptrCast(h));
    self.flushImeTextBoxCommittedDelta(winrt.hstringSliceRaw(text_h));
}

fn flushImeTextBoxCommittedDelta(self: *Surface, utf16: []const u16) void {
    const sent = self.ime_text_box_sent_text.items;

    // When sent is empty, treat all of utf16 as new committed text.
    // This fixes IME first-character loss: composing=false means TextChanged
    // delivers the full committed string at once, but append_only would fail
    // because commonPrefixLen(empty, text) == 0 != sent.len when sent is empty
    // and utf16 has content that doesn't start from a previous prefix.
    if (sent.len == 0 and utf16.len > 0) {
        App.fileLog("ime_text_box: FlushCommitted sent=0 -> sending all {} chars", .{utf16.len});
        const app_ref = self.app;
        for (utf16) |code_unit| {
            self.handleCharEvent(code_unit);
            if (!isSurfaceAlive(app_ref, self)) return;
        }
        self.setImeTextBoxSentSnapshot(utf16);
        return;
    }

    const append_only = commonPrefixLen(u16, sent, utf16) == sent.len and utf16.len > sent.len;
    App.fileLog(
        "ime_text_box: FlushCommitted utf16_len={} sent_len={} append_only={} append_len={}",
        .{ utf16.len, sent.len, append_only, if (append_only) utf16.len - sent.len else 0 },
    );
    if (!append_only) {
        self.setImeTextBoxSentSnapshot(utf16);
        return;
    }

    const app_ref = self.app;
    for (utf16[sent.len..]) |code_unit| {
        self.handleCharEvent(code_unit);
        if (!isSurfaceAlive(app_ref, self)) return;
    }
    self.setImeTextBoxSentSnapshot(utf16);
}

fn commonPrefixLen(comptime T: type, a: []const T, b: []const T) usize {
    const max_len = @min(a.len, b.len);
    var i: usize = 0;
    while (i < max_len and a[i] == b[i]) : (i += 1) {}
    return i;
}

// -----------------------------------------------------------------------
// TSF bridge helpers — called from App.zig TSF callbacks
// -----------------------------------------------------------------------

/// Called by TSF when composition text changes (preedit display).
/// Bridges to core Surface.preeditCallback.
pub fn setTsfPreedit(self: *Surface, preedit_utf8: ?[]const u8) void {
    if (!self.core_initialized) return;
    self.core_surface.preeditCallback(preedit_utf8) catch |err| {
        App.fileLog("TSF preedit error: {}", .{err});
    };
}

/// Called by TSF when text is finalized (user confirmed candidate / pressed Enter).
/// Sends each code unit to the PTY via handleCharEvent, matching the pattern
/// used by flushImeTextBoxCommittedDelta.
pub fn handleTsfOutput(self: *Surface, text_utf8: []const u8) void {
    if (!self.core_initialized) return;
    if (text_utf8.len == 0) return;

    App.fileLog("TSF output: {} bytes", .{text_utf8.len});

    // Convert UTF-8 to UTF-16 code units and feed each one through
    // handleCharEvent, which already handles surrogate pairs.
    const view = std.unicode.Utf8View.initUnchecked(text_utf8);
    var it = view.iterator();
    const app_ref = self.app;
    while (it.nextCodepoint()) |cp| {
        if (cp <= 0xFFFF) {
            // BMP: single UTF-16 code unit
            self.handleCharEvent(@intCast(cp));
            if (!isSurfaceAlive(app_ref, self)) return;
        } else {
            // Supplementary plane: encode as surrogate pair
            const v = cp - 0x10000;
            const high: u16 = @intCast(0xD800 + (v >> 10));
            const low: u16 = @intCast(0xDC00 + (v & 0x3FF));
            self.handleCharEvent(high);
            if (!isSurfaceAlive(app_ref, self)) return;
            self.handleCharEvent(low);
            if (!isSurfaceAlive(app_ref, self)) return;
        }
    }
}

/// Returns cursor screen-coordinate rectangle for TSF/IME candidate window placement.
/// TSF's ITfContextOwner::GetTextExt expects screen coordinates.
pub fn getTsfCursorRect(self: *Surface) os.RECT {
    if (!self.core_initialized) {
        return .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    }

    // imePoint() returns coordinates in DIPs (already divided by content_scale),
    // relative to the surface's top-left corner.
    const ime_pos = self.core_surface.imePoint();

    // Convert to integer pixel coordinates.
    // imePoint divides by content_scale, so we need to multiply back to get
    // physical pixels for ClientToScreen.
    const scale_x: f64 = if (self.content_scale.x > 0) @as(f64, @floatCast(self.content_scale.x)) else 1.0;
    const scale_y: f64 = if (self.content_scale.y > 0) @as(f64, @floatCast(self.content_scale.y)) else 1.0;

    const left_px: i32 = @intFromFloat(ime_pos.x * scale_x);
    const top_px: i32 = @intFromFloat(ime_pos.y * scale_y);
    const bottom_px: i32 = @intFromFloat((ime_pos.y + ime_pos.height) * scale_y);

    // Convert client coordinates to screen coordinates using the main HWND.
    const hwnd = self.app.hwnd orelse {
        App.fileLog("TSF getTsfCursorRect: no hwnd", .{});
        return .{ .left = left_px, .top = top_px, .right = left_px + 1, .bottom = bottom_px };
    };

    var pt_top_left = os.POINT{ .x = left_px, .y = top_px };
    var pt_bottom_right = os.POINT{ .x = left_px + 1, .y = bottom_px };
    _ = os.ClientToScreen(hwnd, &pt_top_left);
    _ = os.ClientToScreen(hwnd, &pt_bottom_right);

    return .{
        .left = pt_top_left.x,
        .top = pt_top_left.y,
        .right = pt_bottom_right.x,
        .bottom = pt_bottom_right.y,
    };
}

fn isImePassthroughVirtualKey(vk: u32) bool {
    return switch (vk) {
        0x15, // VK_KANA / VK_HANGUL — IME Kana/Hangul mode toggle
        0x16, // VK_IME_ON
        0x17, // VK_JUNJA — IME Junja mode
        0x18, // VK_FINAL — IME Final mode
        0x19, // VK_HANJA / VK_KANJI — IME Hanja/Kanji mode (半角/全角 key)
        0x1A, // VK_IME_OFF
        0x1C, // VK_CONVERT (変換)
        0x1D, // VK_NONCONVERT (無変換)
        0x1E, // VK_ACCEPT
        0x1F, // VK_MODECHANGE
        0xE5, // VK_PROCESSKEY
        0xF3, // IME toggle reported by WinUI3 on Japanese layout in Phase 6
        0xF4, // IME off reported by WinUI3 on Japanese layout in Phase 6
        => true,
        else => false,
    };
}

fn hwndValue(hwnd: ?os.HWND) usize {
    return if (hwnd) |h| @intFromPtr(h) else 0;
}

fn logImeTextBoxState(self: *Surface, comptime prefix: []const u8) void {
    const ime_tb = self.ime_text_box orelse return;
    var opacity: f64 = -1;
    var is_hit_test_visible = false;
    var visibility: i32 = -1;
    var is_tab_stop = false;
    var focus_state: i32 = -1;
    var is_enabled = false;
    var allow_focus_on_interaction = false;
    var actual_width: f64 = -1;
    var actual_height: f64 = -1;

    if (ime_tb.queryInterface(com.IUIElement)) |ime_ue| {
        defer ime_ue.release();
        opacity = ime_ue.Opacity() catch -1;
        is_hit_test_visible = ime_ue.IsHitTestVisible() catch false;
        visibility = ime_ue.Visibility() catch -1;
        is_tab_stop = ime_ue.IsTabStop() catch false;
        focus_state = ime_ue.FocusState() catch -1;
    } else |_| {}

    if (ime_tb.queryInterface(com.IControl)) |ime_ctrl| {
        defer ime_ctrl.release();
        is_enabled = ime_ctrl.IsEnabled() catch false;
    } else |_| {}

    if (ime_tb.queryInterface(com.IFrameworkElement)) |ime_fe| {
        defer ime_fe.release();
        allow_focus_on_interaction = ime_fe.AllowFocusOnInteraction() catch false;
        actual_width = ime_fe.ActualWidth() catch -1;
        actual_height = ime_fe.ActualHeight() catch -1;
    } else |_| {}

    App.fileLog(
        prefix ++ " state: win32_focus=0x{x} hwnd=0x{x} opacity={d:.2} visible={} hit_test={} tab_stop={} enabled={} allow_focus_on_interaction={} focus_state={} actual={d:.2}x{d:.2}",
        .{
            hwndValue(os.GetFocus()),
            hwndValue(self.app.hwnd),
            opacity,
            visibility,
            is_hit_test_visible,
            is_tab_stop,
            is_enabled,
            allow_focus_on_interaction,
            focus_state,
            actual_width,
            actual_height,
        },
    );
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
    App.fileLog("Swap chain bound to SwapChainPanel (UI thread)", .{});
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
    App.fileLog("updateScrollbarUi: total={} offset={} len={}", .{ total, offset, len });
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

    range_base.SetMinimum(0.0) catch {};
    range_base.SetMaximum(maximum) catch {};
    range_base.SetValue(offset_f) catch {};
    range_base.SetLargeChange(len_f) catch {};
    range_base.SetSmallChange(1.0) catch {};

    const isb = sb.queryInterface(com.IScrollBar) catch |err| {
        log.warn("scrollbar ui sync: IScrollBar QI failed: {}", .{err});
        return;
    };
    defer isb.release();
    isb.SetViewportSize(len_f) catch {};

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

    const orientation = isb.Orientation() catch -1;
    const viewport = isb.ViewportSize() catch -1.0;
    const width = fe.ActualWidth() catch -1.0;
    const height = fe.ActualHeight() catch -1.0;
    const visibility = ue.Visibility() catch -1;
    if (comptime log_hot_path) {
        log.debug(
            "scrollbar ui sync: orientation={} viewport={d:.2} actual={d:.2}x{d:.2} visibility={} max={d:.2} value={d:.2} len={d:.2}",
            .{ orientation, viewport, width, height, visibility, maximum, offset_f, len_f },
        );
    }
}

/// RangeBase.ValueChanged event callback (fires on user drag and programmatic changes).
fn onScrollBarValueChanged(self: *Surface, _: ?*anyopaque, args_raw: ?*anyopaque) void {
    if (self.is_internal_scroll_update) return;

    const args: *com.IRangeBaseValueChangedEventArgs = @ptrCast(@alignCast(args_raw orelse return));
    const new_value = args.NewValue() catch return;
    const row: usize = @intFromFloat(@max(0.0, @round(new_value)));

    if (comptime log_hot_path) {
        log.debug("onScrollBarValueChanged: new_value={d:.2} row={}", .{ new_value, row });
    }

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

    // Query actual XAML layout size of SwapChainPanel.
    var actual_w: f64 = 0;
    var actual_h: f64 = 0;
    if (self.swap_chain_panel) |panel| {
        const fe = panel.queryInterface(com.IFrameworkElement) catch null;
        if (fe) |f| {
            defer f.release();
            actual_w = f.ActualWidth() catch 0;
            actual_h = f.ActualHeight() catch 0;
        }
    }
    const scale: f64 = @floatCast(self.content_scale.x);
    App.fileLog(
        "SwapChainPanel.Loaded: surface_size={}x{} actual_dip={d:.1}x{d:.1} actual_px={d:.0}x{d:.0} scale={d:.2}",
        .{ self.size.width, self.size.height, actual_w, actual_h, actual_w * scale, actual_h * scale, scale },
    );
    self.loaded = true;

    // Keep deferred binding until we have a non-trivial cached size.
    // `onSizeChanged` may fire before `Loaded`, so we also retry here.
    maybeBindPendingSwapChain(self, "onLoaded");
    maybeBindPendingSwapChainHandle(self, "onLoaded");
    // In TabView mode, enforce that the active tab item still points to this panel.
    self.app.ensureVisibleSurfaceAttached(self);
    if (self.app.activeSurface()) |active_surface| {
        if (active_surface == self) {
            input_runtime.focusKeyboardTarget(self.app);
        }
    }
}

/// SizeChanged event callback. Triggered when the SwapChainPanel's layout size changes.
/// This is the XAML-driven resize path (matching Windows Terminal's architecture):
///   WM_SIZE → RootGrid Width/Height → XAML layout → SwapChainPanel SizeChanged → sizeCallback
/// The core terminal size is derived from XAML layout, NOT from WM_SIZE directly.
fn onSizeChanged(self: *Surface, _: *anyopaque, _: *anyopaque) void {
    // Get actual panel dimensions from XAML layout (in DIPs).
    const panel = self.swap_chain_panel orelse return;
    const fe = panel.queryInterface(com.IFrameworkElement) catch return;
    defer fe.release();
    const dip_width = fe.ActualWidth() catch return;
    const dip_height = fe.ActualHeight() catch return;

    if (dip_width <= 0 or dip_height <= 0) return;

    // Use DIP dimensions for swap chain size.
    // STRETCH scaling maps swap chain pixels to panel DIPs 1:1.
    // Physical pixel rendering would overflow because STRETCH treats
    // the swap chain buffer as logical (DIP) units.
    const dip_w: u32 = @intFromFloat(dip_width);
    const dip_h: u32 = @intFromFloat(dip_height);

    App.fileLog("onSizeChanged: dip={d:.1}x{d:.1} -> {}x{}", .{ dip_width, dip_height, dip_w, dip_h });

    if (dip_w > 0 and dip_h > 0) {
        self.size = .{ .width = dip_w, .height = dip_h };
        if (self.core_initialized) {
            App.fileLog("onSizeChanged: calling sizeCallback {}x{}", .{ dip_w, dip_h });
            self.core_surface.sizeCallback(self.size) catch |err| {
                App.fileLog("onSizeChanged: sizeCallback FAILED: {}", .{err});
                log.warn("onSizeChanged sizeCallback error: {}", .{err});
            };
        } else {
            App.fileLog("onSizeChanged: core NOT initialized, skip sizeCallback", .{});
        }
    }

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
