//! Unified WinUI 3 surface implementation for Ghostty.
//! Supports both traditional WinUI 3 and XAML Islands.

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const apprt = @import("../../apprt.zig");
const CoreSurface = @import("../../Surface.zig");
const CoreApp = @import("../../App.zig");
const configpkg = @import("../../config.zig");
const input = @import("../../input.zig");
const terminal = @import("../../terminal/main.zig");
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const native_interop = @import("native_interop.zig");
const input_runtime = @import("input_runtime.zig");
const key = @import("key.zig");
const os = @import("os.zig");
const log = std.log.scoped(.winui3_surface);

pub fn Surface(comptime App: type) type {
    const is_islands = @hasDecl(App, "tsf_impl");

    return struct {
        const Self = @This();
        const SearchOverlay = @import("SearchOverlay_generic.zig").SearchOverlay(Self);

        /// Set to true to enable verbose per-frame / per-event debug logs (scroll bar, etc.).
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

        // TextBox composition tokens (non-Islands only)
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
        pending_keydown: PendingKeydown = .none,

        const PendingKeydown = union(enum) {
            none,
            consumed,
            pending: PendingKey,
        };

        const PendingKey = struct {
            key_code: input.Key,
            mods: input.Mods,
            unshifted_codepoint: u21,
        };

        pub fn init(self: *Self, app: *App, core_app: *CoreApp, config: *const configpkg.Config, profile_opt: anytype) !void {
            _ = profile_opt; // Reserved for Islands profiles.zig

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

            // Set background color. Islands uses DarkGray (32,32,32) to match theme.
            const bg_color = if (is_islands)
                com.Color{ .A = 255, .R = 32, .G = 32, .B = 32 }
            else
                com.Color{ .A = 255, .R = 0, .G = 0, .B = 0 };
            self.app.setControlBackground(panel, bg_color);

            // Create inner surface grid.
            if (is_islands) {
                // Islands uses compiled XBF (SurfaceRoot.xbf).
                const grid_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Grid");
                defer winrt.deleteHString(grid_class);
                const grid_insp = try winrt.activateInstance(grid_class);
                errdefer _ = grid_insp.release();

                {
                    const app_class = try winrt.hstring("Microsoft.UI.Xaml.Application");
                    defer winrt.deleteHString(app_class);
                    const app_statics = try winrt.getActivationFactory(com.IApplicationStatics, app_class);
                    defer app_statics.release();

                    const uri_class = try winrt.hstring("Windows.Foundation.Uri");
                    defer winrt.deleteHString(uri_class);
                    const uri_factory = try winrt.getActivationFactory(com.IUriRuntimeClassFactory, uri_class);
                    defer uri_factory.release();

                    const uri_str = try winrt.hstring("ms-appx:///Surface.xaml");
                    defer winrt.deleteHString(uri_str);
                    const uri = try uri_factory.createUri(uri_str);
                    defer uri.release();

                    try app_statics.loadComponent(@ptrCast(grid_insp), @ptrCast(uri));
                }

                const root_fe = try grid_insp.queryInterface(com.IFrameworkElement);
                defer root_fe.release();

                const sb_name = try winrt.hstring("ScrollBar");
                defer winrt.deleteHString(sb_name);
                const sb_insp_raw = try root_fe.FindName(sb_name);
                self.scroll_bar_insp = @ptrCast(sb_insp_raw);
                self.surface_grid = grid_insp;
            } else {
                // Non-islands uses XamlReader.load with string.
                const xaml_str =
                    \\<Grid xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'>
                    \\  <Grid.ColumnDefinitions>
                    \\    <ColumnDefinition Width='*'/>
                    \\    <ColumnDefinition Width='17'/>
                    \\  </Grid.ColumnDefinitions>
                    \\  <ScrollBar Grid.Column='1' Orientation='Vertical'
                    \\             Width='17' MinWidth='17' MaxWidth='17'
                    \\             HorizontalAlignment='Stretch' VerticalAlignment='Stretch'
                    \\             IndicatorMode='MouseIndicator' IsTabStop='False'
                    \\             Minimum='0' Maximum='0' Value='0'
                    \\             SmallChange='1' LargeChange='10'
                    \\             ViewportSize='10'/>
                    \\</Grid>
                ;
                const xaml_hstr = try winrt.hstring(xaml_str);
                defer winrt.deleteHString(xaml_hstr);

                const reader_class = try winrt.hstring("Microsoft.UI.Xaml.Markup.XamlReader");
                defer winrt.deleteHString(reader_class);
                const reader = try winrt.getActivationFactory(com.IXamlReaderStatics, reader_class);
                defer reader.release();
                const grid_insp: *winrt.IInspectable = @ptrCast(@alignCast(try reader.load(xaml_hstr)));
                errdefer _ = grid_insp.release();

                self.surface_grid = grid_insp;

                const grid_panel = try grid_insp.queryInterface(com.IPanel);
                defer grid_panel.release();
                const grid_children_raw = try grid_panel.Children();
                const grid_children: *com.IVector = @ptrCast(@alignCast(grid_children_raw));
                defer grid_children.release();

                const sb_raw = try grid_children.getAt(1);
                self.scroll_bar_insp = @ptrCast(@alignCast(sb_raw));
            }

            // Assembly children.
            {
                const grid_panel = try self.surface_grid.?.queryInterface(com.IPanel);
                defer grid_panel.release();
                const grid_children_raw = try grid_panel.Children();
                const grid_children: *com.IVector = @ptrCast(@alignCast(grid_children_raw));
                defer grid_children.release();

                // SwapChainPanel at index 0.
                if (is_islands) {
                    try grid_children.insertAt(0, @ptrCast(panel));
                } else {
                    try grid_children.insertAt(0, @ptrCast(panel));
                }

                // Register ScrollBar ValueChanged.
                const range_base = try self.scroll_bar_insp.?.queryInterface(com.IRangeBase);
                defer range_base.release();
                const gen = @import("com_generated.zig");
                const ValueChangedDelegate = gen.RangeBaseValueChangedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const vc_delegate = try ValueChangedDelegate.createWithIid(
                    self.app.core_app.alloc,
                    self,
                    &onScrollBarValueChanged,
                    &com.IID_RangeBaseValueChangedEventHandler,
                );
                defer vc_delegate.release();
                self.scroll_bar_value_changed_token = try range_base.AddValueChanged(vc_delegate.comPtr());

                // Create hidden TextBox for IME focus.
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
                if (ime_tb_insp.queryInterface(com.IFrameworkElement)) |ime_fe| {
                    defer ime_fe.release();
                    ime_fe.SetWidth(16) catch {};
                    ime_fe.SetHeight(16) catch {};
                    ime_fe.SetAllowFocusOnInteraction(true) catch {};
                } else |_| {}

                try grid_children.append(@ptrCast(ime_tb_insp));
                self.ime_text_box = ime_tb;
                _ = ime_tb_insp.release();
            }

            // Hook up events on SwapChainPanel.
            const framework_element = try panel.queryInterface(com.IFrameworkElement);
            defer framework_element.release();
            const gen = @import("com_generated.zig");

            const LoadedDelegate = gen.RoutedEventHandlerImpl(Self, *const fn (*Self, *anyopaque, *anyopaque) void);
            const loaded_delegate = try LoadedDelegate.createWithIid(self.app.core_app.alloc, self, &onLoaded, &com.IID_RoutedEventHandler);
            defer loaded_delegate.release();
            self.loaded_token = try framework_element.AddLoaded(loaded_delegate.comPtr());

            const SizeChangedDelegate = gen.SizeChangedEventHandlerImpl(Self, *const fn (*Self, *anyopaque, *anyopaque) void);
            const size_changed_delegate = try SizeChangedDelegate.createWithIid(self.app.core_app.alloc, self, &onSizeChanged, &com.IID_SizeChangedEventHandler);
            defer size_changed_delegate.release();
            self.size_changed_token = try framework_element.AddSizeChanged(size_changed_delegate.comPtr());

            {
                const ui_element = try panel.queryInterface(com.IUIElement);
                defer ui_element.release();
                ui_element.SetIsTabStop(true) catch {};

                const PointerDelegate = gen.PointerEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const KeyDelegate = gen.KeyEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const RoutedDelegate = gen.RoutedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const CharRecvDelegate = gen.TypedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);

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

                const key_down = try KeyDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPreviewKeyDown, &com.IID_KeyEventHandler);
                defer key_down.release();
                self.preview_key_down_token = ui_element.AddPreviewKeyDown(key_down.comPtr()) catch 0;

                const key_up = try KeyDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPreviewKeyUp, &com.IID_KeyEventHandler);
                defer key_up.release();
                self.preview_key_up_token = ui_element.AddPreviewKeyUp(key_up.comPtr()) catch 0;

                const char_recv = try CharRecvDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlCharacterReceived, &com.IID_CharacterReceivedHandler);
                defer char_recv.release();
                self.character_received_token = ui_element.AddCharacterReceived(char_recv.comPtr()) catch 0;

                const got_focus = try RoutedDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlGotFocus, &com.IID_RoutedEventHandler);
                defer got_focus.release();
                self.got_focus_token = ui_element.AddGotFocus(got_focus.comPtr()) catch 0;

                const lost_focus = try RoutedDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlLostFocus, &com.IID_RoutedEventHandler);
                defer lost_focus.release();
                self.lost_focus_token = ui_element.AddLostFocus(lost_focus.comPtr()) catch 0;
            }

            // Hook up hidden TextBox events.
            if (self.ime_text_box) |ime_tb| {
                const ui_element = try ime_tb.queryInterface(com.IUIElement);
                defer ui_element.release();

                const KeyDelegate = gen.KeyEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const RoutedDelegate = gen.RoutedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const CharRecvDelegate = gen.TypedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);

                const key_down = try KeyDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxPreviewKeyDown, &com.IID_KeyEventHandler);
                defer key_down.release();
                self.ime_preview_key_down_token = ui_element.AddPreviewKeyDown(key_down.comPtr()) catch 0;

                const key_up = try KeyDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxPreviewKeyUp, &com.IID_KeyEventHandler);
                defer key_up.release();
                self.ime_preview_key_up_token = ui_element.AddPreviewKeyUp(key_up.comPtr()) catch 0;

                const char_recv = try CharRecvDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxCharacterReceived, &com.IID_CharacterReceivedHandler);
                defer char_recv.release();
                self.ime_character_received_token = ui_element.AddCharacterReceived(char_recv.comPtr()) catch 0;

                const got_focus = try RoutedDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxGotFocus, &com.IID_RoutedEventHandler);
                defer got_focus.release();
                self.ime_got_focus_token = ui_element.AddGotFocus(got_focus.comPtr()) catch 0;

                const lost_focus = try RoutedDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxLostFocus, &com.IID_RoutedEventHandler);
                defer lost_focus.release();
                self.lost_focus_token = ui_element.AddLostFocus(lost_focus.comPtr()) catch 0;

                const TextChangedDelegate = gen.TextChangedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const text_changed = try TextChangedDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxTextChanged, &com.IID_TextChangedEventHandler);
                defer text_changed.release();
                self.ime_text_changed_token = try ime_tb.AddTextChanged(text_changed.comPtr());

                if (!is_islands) {
                    const CompositionDelegate = gen.TypedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                    const comp_start = try CompositionDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxCompositionStarted, &com.IID_TextCompositionStartedHandler);
                    defer comp_start.release();
                    self.ime_text_comp_start_token = try ime_tb.AddTextCompositionStarted(comp_start.comPtr());

                    const comp_change = try CompositionDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxCompositionChanged, &com.IID_TextCompositionChangedHandler);
                    defer comp_change.release();
                    self.ime_text_comp_change_token = try ime_tb.AddTextCompositionChanged(comp_change.comPtr());

                    const comp_end = try CompositionDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxCompositionEnded, &com.IID_TextCompositionEndedHandler);
                    defer comp_end.release();
                    self.ime_text_comp_end_token = try ime_tb.AddTextCompositionEnded(comp_end.comPtr());
                }
            }

            try self.core_surface.init(core_app.alloc, config, core_app, app, self);
            self.core_initialized = true;
            errdefer {
                self.core_surface.deinit();
                self.core_initialized = false;
            }

            try core_app.addSurface(self);
            log.info("WinUI 3 surface initialized ({d}x{d})", .{ self.size.width, self.size.height });
        }

        pub fn deinit(self: *Self) void {
            self.search_overlay.deinit();
            if (self.core_initialized) {
                self.app.core_app.deleteSurface(self);
                self.core_surface.deinit();
                self.core_initialized = false;
            }

            if (self.swap_chain_panel_native2) |native2| {
                native2.release();
                self.swap_chain_panel_native2 = null;
            }
            if (self.swap_chain_panel_native) |native| {
                if (self.swap_chain_panel) |panel| {
                    if (panel.queryInterface(com.IFrameworkElement)) |fe| {
                        defer fe.release();
                        if (self.loaded_token != 0) fe.RemoveLoaded(self.loaded_token) catch {};
                        if (self.size_changed_token != 0) fe.RemoveSizeChanged(self.size_changed_token) catch {};
                    } else |_| {}

                    if (panel.queryInterface(com.IUIElement)) |ue| {
                        defer ue.release();
                        if (self.pointer_pressed_token != 0) ue.RemovePointerPressed(self.pointer_pressed_token) catch {};
                        if (self.pointer_moved_token != 0) ue.RemovePointerMoved(self.pointer_moved_token) catch {};
                        if (self.pointer_released_token != 0) ue.RemovePointerReleased(self.pointer_released_token) catch {};
                        if (self.pointer_wheel_changed_token != 0) ue.RemovePointerWheelChanged(self.pointer_wheel_changed_token) catch {};
                        if (self.preview_key_down_token != 0) ue.RemovePreviewKeyDown(self.preview_key_down_token) catch {};
                        if (self.preview_key_up_token != 0) ue.RemovePreviewKeyUp(self.preview_key_up_token) catch {};
                        if (self.character_received_token != 0) ue.RemoveCharacterReceived(self.character_received_token) catch {};
                        if (self.got_focus_token != 0) ue.RemoveGotFocus(self.got_focus_token) catch {};
                        if (self.lost_focus_token != 0) ue.RemoveLostFocus(self.lost_focus_token) catch {};
                    } else |_| {}
                }
                native.release();
                self.swap_chain_panel_native = null;
            }

            if (self.ime_text_box) |ime_tb| {
                if (ime_tb.queryInterface(com.IUIElement)) |ue| {
                    defer ue.release();
                    if (self.ime_preview_key_down_token != 0) ue.RemovePreviewKeyDown(self.ime_preview_key_down_token) catch {};
                    if (self.ime_preview_key_up_token != 0) ue.RemovePreviewKeyUp(self.ime_preview_key_up_token) catch {};
                    if (self.ime_character_received_token != 0) ue.RemoveCharacterReceived(self.ime_character_received_token) catch {};
                    if (self.ime_got_focus_token != 0) ue.RemoveGotFocus(self.ime_got_focus_token) catch {};
                    if (self.lost_focus_token != 0) ue.RemoveLostFocus(self.lost_focus_token) catch {};
                } else |_| {}
                if (self.ime_text_changed_token != 0) ime_tb.RemoveTextChanged(self.ime_text_changed_token) catch {};
                if (!is_islands) {
                    if (self.ime_text_comp_start_token != 0) ime_tb.RemoveTextCompositionStarted(self.ime_text_comp_start_token) catch {};
                    if (self.ime_text_comp_change_token != 0) ime_tb.RemoveTextCompositionChanged(self.ime_text_comp_change_token) catch {};
                    if (self.ime_text_comp_end_token != 0) ime_tb.RemoveTextCompositionEnded(self.ime_text_comp_end_token) catch {};
                }
            }

            if (self.scroll_bar_insp) |sb| {
                if (self.scroll_bar_value_changed_token != 0) {
                    const rb = sb.queryInterface(com.IRangeBase) catch null;
                    if (rb) |r| {
                        defer r.release();
                        r.RemoveValueChanged(self.scroll_bar_value_changed_token) catch {};
                    }
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

        pub fn core(self: *Self) *CoreSurface { return &self.core_surface; }
        pub fn rtApp(self: *Self) *App { return self.app; }
        pub fn close(self: *Self, process_active: bool) void { _ = process_active; self.app.closeSurface(self); }
        pub fn getTitle(self: *Self) ?[:0]const u8 { return self.title; }
        pub fn getContentScale(self: *const Self) !apprt.ContentScale { return self.content_scale; }
        pub fn getSize(self: *const Self) !apprt.SurfaceSize { return self.size; }
        pub fn pwd(self: *Self, alloc: std.mem.Allocator) !?[]const u8 {
            if (!self.core_initialized) return null;
            return try self.core_surface.pwd(alloc);
        }
        pub fn hasSelection(self: *const Self) bool {
            if (!self.core_initialized) return false;
            return self.core_surface.hasSelection();
        }
        pub fn cursorIsAtPrompt(self: *Self) bool {
            if (!self.core_initialized) return false;
            return self.core_surface.cursorIsAtPrompt();
        }
        pub fn viewportString(self: *Self, alloc: std.mem.Allocator) ![]const u8 {
            if (!self.core_initialized) return alloc.dupe(u8, "");
            return try self.core_surface.viewportString(alloc);
        }
        pub fn getCursorPos(self: *const Self) !apprt.CursorPos { return self.cursor_pos; }
        pub fn supportsSwapChainHandle(self: *const Self) bool { return self.swap_chain_panel_native2 != null; }
        pub fn supportsClipboard(_: *const Self, clipboard_type: apprt.Clipboard) bool {
            return switch (clipboard_type) { .standard => true, .selection, .primary => false };
        }

        pub fn clipboardRequest(self: *Self, clipboard_type: apprt.Clipboard, state: apprt.ClipboardRequest) !bool {
            if (clipboard_type != .standard) return false;
            const hwnd = self.app.hwnd orelse return false;
            const alloc = self.app.core_app.alloc;
            if (os.OpenClipboard(hwnd) == 0) return false;
            defer _ = os.CloseClipboard();
            const handle = os.GetClipboardData(os.CF_UNICODETEXT) orelse return false;
            const lock_ptr = os.GlobalLock(handle) orelse return false;
            defer _ = os.GlobalUnlock(handle);
            const ptr: [*]const u16 = @ptrFromInt(@intFromPtr(lock_ptr));
            var utf16_len: usize = 0;
            while (ptr[utf16_len] != 0) : (utf16_len += 1) {}
            if (utf16_len == 0) return false;
            const utf8 = std.unicode.utf16LeToUtf8Alloc(alloc, ptr[0..utf16_len]) catch return false;
            defer alloc.free(utf8);
            const utf8z = alloc.dupeZ(u8, utf8) catch return false;
            defer alloc.free(utf8z);
            self.core_surface.completeClipboardRequest(state, utf8z, false) catch |err| switch (err) {
                error.UnsafePaste, error.UnauthorizedPaste => {
                    log.warn("unsafe paste blocked", .{});
                    return false;
                },
                else => {
                    log.warn("clipboard request failed: {}", .{err});
                    return false;
                },
            };
            return true;
        }

        pub fn setClipboard(self: *Self, clipboard_type: apprt.Clipboard, contents: []const apprt.ClipboardContent, confirm: bool) !void {
            _ = confirm;
            if (clipboard_type != .standard) return;
            const text: [:0]const u8 = blk: {
                for (contents) |c| if (std.mem.eql(u8, c.mime, "text/plain")) break :blk c.data;
                return;
            };
            const hwnd = self.app.hwnd orelse return;
            const utf16_len = std.unicode.calcUtf16LeLen(text) catch return;
            const hmem = os.GlobalAlloc(os.GMEM_MOVEABLE, (utf16_len + 1) * 2) orelse return;
            const lock_ptr = os.GlobalLock(hmem) orelse { _ = os.GlobalFree(hmem); return; };
            const dest: [*]u16 = @ptrFromInt(@intFromPtr(lock_ptr));
            const written = std.unicode.utf8ToUtf16Le(dest[0..utf16_len], text) catch { _ = os.GlobalUnlock(hmem); _ = os.GlobalFree(hmem); return; };
            dest[written] = 0;
            _ = os.GlobalUnlock(hmem);
            if (os.OpenClipboard(hwnd) == 0) { _ = os.GlobalFree(hmem); return; }
            _ = os.EmptyClipboard();
            if (os.SetClipboardData(os.CF_UNICODETEXT, hmem) == null) { _ = os.GlobalFree(hmem); }
            _ = os.CloseClipboard();
        }

        pub fn defaultTermioEnv(self: *Self) !std.process.EnvMap {
            const alloc = self.app.core_app.alloc;
            var env = try std.process.getEnvMap(alloc);
            errdefer env.deinit();
            try env.put("TERM", "xterm-256color");
            try env.put("COLORTERM", "truecolor");
            return env;
        }

        pub fn redrawInspector(_: *Self) void {}

        pub fn setTabTitle(self: *Self, title: [:0]const u8) void {
            const alloc = self.app.core_app.alloc;
            if (self.title) |old_title| alloc.free(old_title);
            self.title = alloc.dupeZ(u8, title) catch return;
            if (self.tab_view_item_inspectable) |tvi_insp| {
                if (tvi_insp.queryInterface(com.ITabViewItem)) |tvi| {
                    defer tvi.release();
                    const utf16 = std.unicode.utf8ToUtf16LeAlloc(alloc, self.title.?) catch return;
                    defer alloc.free(utf16);
                    if (winrt.createHString(utf16)) |hstr| {
                        defer winrt.deleteHString(hstr);
                        if (@import("util.zig").boxString(hstr)) |boxed| {
                            defer _ = boxed.release();
                            _ = tvi.SetHeader(boxed) catch {};
                        } else |_| {}
                    } else |_| {}
                } else |_| {}
            }
        }

        pub fn updateSize(self: *Self, width: u32, height: u32) void {
            if (width == 0 or height == 0) return;
            if (is_islands) App.fileLog("Surface.updateSize: {}x{} -> {}x{}", .{ self.size.width, self.size.height, width, height });
            self.size = .{ .width = width, .height = height };
            if (self.core_initialized) {
                self.core_surface.sizeCallback(self.size) catch {};
            }
        }

        pub fn updateContentScale(self: *Self) void {
            if (self.app.hwnd) |hwnd| {
                const dpi = os.GetDpiForWindow(hwnd);
                if (dpi > 0) {
                    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
                    self.content_scale = .{ .x = scale, .y = scale };
                    if (self.core_initialized) {
                        self.core_surface.contentScaleCallback(self.content_scale) catch {};
                    }
                }
            }
        }

        pub fn handleKeyEvent(self: *Self, vk: u16, pressed: bool) void {
            if (!self.core_initialized) return;
            const ghostty_key = key.vkToKey(vk) orelse {
                if (pressed) self.pending_keydown = .none;
                return;
            };
            if (is_islands) App.fileLog("handleKeyEvent: vk=0x{X:0>4} pressed={} key={s}", .{ vk, pressed, @tagName(ghostty_key) });
            const mods = key.getModifiers();
            const unshifted = key.vkToUnshiftedCodepoint(vk);

            if (pressed) {
                const binding_mods = mods.binding();
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

            const event = input.KeyEvent{
                .action = if (pressed) .press else .release,
                .key = ghostty_key,
                .mods = mods,
                .unshifted_codepoint = unshifted,
            };

            const app_ref = self.app;
            _ = self.core_surface.keyCallback(event) catch return;
            if (!isSurfaceAlive(app_ref, self)) return;
            if (pressed) self.pending_keydown = .consumed;
        }

        fn isSurfaceAlive(app: *App, surface: *const Self) bool {
            for (app.surfaces.items) |s| if (s == surface) return true;
            return false;
        }

        pub fn handleCharEvent(self: *Self, char_code: u16) void {
            if (!self.core_initialized) return;
            const state = self.pending_keydown;
            self.pending_keydown = .none;
            if (state == .consumed) return;

            var codepoint: u21 = undefined;
            if (char_code >= 0xD800 and char_code <= 0xDBFF) {
                self.pending_high_surrogate = char_code;
                self.pending_keydown = state;
                return;
            } else if (char_code >= 0xDC00 and char_code <= 0xDFFF) {
                if (self.pending_high_surrogate != 0) {
                    codepoint = ((@as(u21, self.pending_high_surrogate) - 0xD800) << 10) + (@as(u21, char_code) - 0xDC00) + 0x10000;
                    self.pending_high_surrogate = 0;
                } else return;
            } else {
                self.pending_high_surrogate = 0;
                codepoint = @intCast(char_code);
            }

            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(codepoint, &buf) catch return;
            const ev: input.KeyEvent = switch (state) {
                .pending => |pk| .{ .action = .press, .key = pk.key_code, .mods = pk.mods, .unshifted_codepoint = pk.unshifted_codepoint, .utf8 = buf[0..len] },
                .none => .{ .action = .press, .key = .unidentified, .utf8 = buf[0..len] },
                .consumed => unreachable,
            };
            _ = self.core_surface.keyCallback(ev) catch {};
        }

        pub fn handleMouseMove(self: *Self, x: f64, y: f64) void {
            if (!self.core_initialized) return;
            const pos = apprt.CursorPos{ .x = @floatCast(x), .y = @floatCast(y) };
            self.cursor_pos = pos;
            self.core_surface.cursorPosCallback(pos, key.getModifiers()) catch {};
        }

        pub fn handleMouseButton(self: *Self, button: input.MouseButton, action: input.MouseButtonState) void {
            if (!self.core_initialized) return;
            if (action == .press) {
                const capture_hwnd = if (@hasField(App, "input_hwnd")) self.app.input_hwnd orelse self.app.hwnd else self.app.hwnd;
                if (capture_hwnd) |h| _ = os.SetCapture(h);
            } else _ = os.ReleaseCapture();
            _ = self.core_surface.mouseButtonCallback(action, button, key.getModifiers()) catch false;
        }

        pub fn handleScroll(self: *Self, xoffset: f64, yoffset: f64) void {
            if (!self.core_initialized) return;
            self.core_surface.scrollCallback(xoffset, yoffset, .{}) catch {};
        }

        fn onXamlPointerPressed(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const point = ea.getCurrentPoint(null) catch return;
            defer point.release();
            const pos = point.Position() catch return;
            self.handleMouseMove(@floatCast(pos.X), @floatCast(pos.Y));
            const props = point.Properties() catch return;
            defer props.release();
            const update_kind = props.PointerUpdateKind() catch return;
            const button: input.MouseButton = switch (update_kind) { 1 => .left, 3 => .right, 5 => .middle, else => return };
            if (@hasDecl(App, "resizing") and !self.app.resizing) {
                input_runtime.focusKeyboardTarget(self.app);
                if (is_islands) if (self.app.tsf_impl) |*tsf| tsf.focus();
            } else if (!is_islands) input_runtime.focusKeyboardTarget(self.app);
            self.handleMouseButton(button, .press);
            ea.SetHandled(true) catch {};
        }

        fn onXamlPointerMoved(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const point = ea.getCurrentPoint(null) catch return;
            defer point.release();
            const pos = point.Position() catch return;
            self.handleMouseMove(@floatCast(pos.X), @floatCast(pos.Y));
            ea.SetHandled(true) catch {};
        }

        fn onXamlPointerReleased(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const point = ea.getCurrentPoint(null) catch return;
            defer point.release();
            const pos = point.Position() catch return;
            self.handleMouseMove(@floatCast(pos.X), @floatCast(pos.Y));
            const props = point.Properties() catch return;
            defer props.release();
            const update_kind = props.PointerUpdateKind() catch return;
            const button: input.MouseButton = switch (update_kind) { 2 => .left, 4 => .right, 6 => .middle, else => return };
            self.handleMouseButton(button, .release);
            if (button == .right) self.app.showContextMenuAtCursor();
            ea.SetHandled(true) catch {};
        }

        fn onXamlPointerWheelChanged(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const point = ea.getCurrentPoint(null) catch return;
            defer point.release();
            const props = point.Properties() catch return;
            defer props.release();
            const delta = props.MouseWheelDelta() catch return;
            const is_horizontal = props.IsHorizontalMouseWheel() catch false;
            if (!is_horizontal and key.getModifiers().ctrl) {
                if (delta > 0) _ = self.core_surface.performBindingAction(.{ .increase_font_size = 1 }) catch {};
                if (delta < 0) _ = self.core_surface.performBindingAction(.{ .decrease_font_size = 1 }) catch {};
                ea.SetHandled(true) catch {}; return;
            }
            const offset = @as(f64, @floatFromInt(delta)) / 120.0;
            if (is_horizontal) self.handleScroll(offset, 0) else self.handleScroll(0, offset);
            ea.SetHandled(true) catch {};
        }

        fn onXamlPreviewKeyDown(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const vk = ea.Key() catch return;
            const vk_u32 = @as(u32, @bitCast(vk));
            if (isImePassthroughVirtualKey(vk_u32)) {
                if (is_islands) {
                    if (self.app.tsf_impl) |*tsf| tsf.focus();
                    return;
                } else {
                    self.app.keyboard_focus_target = .ime_text_box;
                    _ = self.focusImeTextBox();
                    return;
                }
            }
            const app_ref = self.app;
            self.handleKeyEvent(@intCast(vk_u32), true);
            if (!isSurfaceAlive(app_ref, self)) return;
            switch (self.pending_keydown) { .pending => {}, else => ea.SetHandled(true) catch {} }
        }

        fn onXamlPreviewKeyUp(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const vk = ea.Key() catch return;
            const app_ref = self.app;
            self.handleKeyEvent(@intCast(@as(u32, @bitCast(vk))), false);
            if (!isSurfaceAlive(app_ref, self)) return;
            ea.SetHandled(true) catch {};
        }

        fn onXamlCharacterReceived(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.ICharacterReceivedRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const ch = ea.Character() catch return;
            const app_ref = self.app;
            self.handleCharEvent(ch);
            if (!isSurfaceAlive(app_ref, self)) return;
            ea.SetHandled(true) catch {};
        }

        fn onImeTextBoxPreviewKeyDown(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const vk = ea.Key() catch return;
            const vk_u32 = @as(u32, @bitCast(vk));
            if (isImePassthroughVirtualKey(vk_u32)) return;
            const app_ref = self.app;
            self.handleKeyEvent(@intCast(vk_u32), true);
            if (!isSurfaceAlive(app_ref, self)) return;
            switch (self.pending_keydown) { .pending => {}, else => ea.SetHandled(true) catch {} }
        }

        fn onImeTextBoxPreviewKeyUp(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
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

        fn onImeTextBoxCharacterReceived(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            _ = self; _ = args;
        }

        fn onImeTextBoxTextChanged(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
            if (!self.core_initialized or self.app.keyboard_focus_target != .ime_text_box or self.ime_text_box_internal_update) return;
            const text_h = self.ime_text_box.?.Text() catch return;
            defer if (text_h) |h| winrt.deleteHString(@ptrCast(h));
            const utf16 = winrt.hstringSliceRaw(text_h);
            if (utf16.len == 0) {
                self.ime_text_box_last_text.clearRetainingCapacity();
                if (!self.ime_text_box_composing) self.ime_text_box_sent_text.clearRetainingCapacity();
                return;
            }
            self.setImeTextBoxSnapshot(utf16);
            if (self.ime_text_box_composing) return;
            self.flushImeTextBoxCommittedDelta(utf16);
        }

        fn onImeTextBoxCompositionStarted(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void { self.ime_text_box_composing = true; }
        fn onImeTextBoxCompositionChanged(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void { self.ime_text_box_composing = true; }
        fn onImeTextBoxCompositionEnded(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
            self.ime_text_box_composing = false;
            self.flushImeTextBoxCommittedText();
        }

        fn onXamlGotFocus(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
            if (!self.core_initialized or self.has_focus) return;
            self.has_focus = true;
            self.core_surface.focusCallback(true) catch {};
            if (self.app.keyboard_focus_target == .ime_text_box) _ = self.focusImeTextBox();
            if (is_islands) if (self.app.tsf_impl) |*tsf| tsf.focus();
        }

        fn onXamlLostFocus(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
            if (!self.core_initialized or self.app.keyboard_focus_target == .ime_text_box or !self.has_focus) return;
            self.has_focus = false;
            self.core_surface.focusCallback(false) catch {};
            if (is_islands) if (self.app.tsf_impl) |*tsf| tsf.unfocus();
        }

        fn onImeTextBoxGotFocus(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
            if (!self.core_initialized or self.has_focus) return;
            self.has_focus = true;
            self.core_surface.focusCallback(true) catch {};
        }

        fn onImeTextBoxLostFocus(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
            if (!self.core_initialized or self.app.keyboard_focus_target != .ime_text_box or !self.has_focus) return;
            self.has_focus = false;
            self.core_surface.focusCallback(false) catch {};
            if (is_islands) if (self.app.tsf_impl) |*tsf| tsf.unfocus();
        }

        pub fn focusSwapChainPanel(self: *Self) void {
            if (self.swap_chain_panel) |panel| {
                if (panel.queryInterface(com.IUIElement)) |ue| {
                    defer ue.release();
                    _ = ue.focus(com.FocusState.Programmatic) catch false;
                } else |_| {}
            }
        }

        pub fn focusImeTextBox(self: *Self) bool {
            if (self.ime_text_box) |ime_tb| {
                self.clearImeTextBoxText();
                self.positionImeTextBox();
                if (ime_tb.queryInterface(com.IUIElement)) |ue| {
                    defer ue.release();
                    return (ue.focus(com.FocusState.Programmatic)) catch false;
                } else |_| {}
            }
            return false;
        }

        pub fn clearImeTextBoxText(self: *Self) void {
            if (self.ime_text_box) |ime_tb| {
                self.ime_text_box_internal_update = true;
                defer self.ime_text_box_internal_update = false;
                if (ime_tb.SetText(@as(?*anyopaque, null))) |_| {
                    self.ime_text_box_last_text.clearRetainingCapacity();
                    self.ime_text_box_sent_text.clearRetainingCapacity();
                    self.ime_text_box_composing = false;
                } else |_| {}
                _ = ime_tb.Select(0, 0) catch {};
            }
        }

        fn positionImeTextBox(self: *Self) void {
            if (!self.core_initialized or self.ime_text_box == null) return;
            const ime_pos = self.core_surface.imePoint();
            const scale_x: f64 = if (self.content_scale.x > 0) @floatCast(self.content_scale.x) else 1.0;
            const scale_y: f64 = if (self.content_scale.y > 0) @floatCast(self.content_scale.y) else 1.0;
            if (self.ime_text_box.?.queryInterface(com.IFrameworkElement)) |fe| {
                defer fe.release();
                _ = fe.SetMargin(.{ .Left = @as(f64, @floatCast(ime_pos.x)) / scale_x, .Top = @as(f64, @floatCast(ime_pos.y)) / scale_y, .Right = 0, .Bottom = 0 }) catch {};
            } else |_| {}
        }

        fn setImeTextBoxSnapshot(self: *Self, utf16: []const u16) void {
            self.ime_text_box_last_text.resize(self.app.core_app.alloc, utf16.len) catch return;
            std.mem.copyForwards(u16, self.ime_text_box_last_text.items, utf16);
        }

        fn setImeTextBoxSentSnapshot(self: *Self, utf16: []const u16) void {
            self.ime_text_box_sent_text.resize(self.app.core_app.alloc, utf16.len) catch return;
            std.mem.copyForwards(u16, self.ime_text_box_sent_text.items, utf16);
        }

        fn flushImeTextBoxCommittedText(self: *Self) void {
            const text_h = self.ime_text_box.?.Text() catch return;
            defer if (text_h) |h| winrt.deleteHString(@ptrCast(h));
            self.flushImeTextBoxCommittedDelta(winrt.hstringSliceRaw(text_h));
        }

        fn flushImeTextBoxCommittedDelta(self: *Self, utf16: []const u16) void {
            const sent = self.ime_text_box_sent_text.items;
            if (sent.len == 0 and utf16.len > 0) {
                for (utf16) |cu| { self.handleCharEvent(cu); if (!isSurfaceAlive(self.app, self)) return; }
                self.setImeTextBoxSentSnapshot(utf16); return;
            }
            const append_only = commonPrefixLen(u16, sent, utf16) == sent.len and utf16.len > sent.len;
            if (!append_only) { self.setImeTextBoxSentSnapshot(utf16); return; }
            for (utf16[sent.len..]) |cu| { self.handleCharEvent(cu); if (!isSurfaceAlive(self.app, self)) return; }
            self.setImeTextBoxSentSnapshot(utf16);
        }

        fn commonPrefixLen(comptime T: type, a: []const T, b: []const T) usize {
            const max_len = @min(a.len, b.len);
            var i: usize = 0;
            while (i < max_len and a[i] == b[i]) : (i += 1) {}
            return i;
        }

        pub fn setTsfPreedit(self: *Self, preedit_utf8: ?[]const u8) void {
            if (self.core_initialized) self.core_surface.preeditCallback(preedit_utf8) catch {};
        }

        pub fn handleTsfOutput(self: *Self, text_utf8: []const u8) void {
            if (!self.core_initialized or text_utf8.len == 0) return;
            const view = std.unicode.Utf8View.initUnchecked(text_utf8);
            var it = view.iterator();
            while (it.nextCodepoint()) |cp| {
                if (cp <= 0xFFFF) {
                    self.handleCharEvent(@intCast(cp));
                    if (!isSurfaceAlive(self.app, self)) return;
                } else {
                    const v = cp - 0x10000;
                    self.handleCharEvent(@intCast(0xD800 + (v >> 10)));
                    if (!isSurfaceAlive(self.app, self)) return;
                    self.handleCharEvent(@intCast(0xDC00 + (v & 0x3FF)));
                    if (!isSurfaceAlive(self.app, self)) return;
                }
            }
        }

        pub fn getTsfCursorRect(self: *Self) os.RECT {
            if (!self.core_initialized) return .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
            const ime_pos = self.core_surface.imePoint();
            const scale_x: f64 = if (self.content_scale.x > 0) @floatCast(self.content_scale.x) else 1.0;
            const scale_y: f64 = if (self.content_scale.y > 0) @floatCast(self.content_scale.y) else 1.0;
            const left_px: i32 = @intFromFloat(ime_pos.x * scale_x);
            const top_px: i32 = @intFromFloat(ime_pos.y * scale_y);
            const bottom_px: i32 = @intFromFloat((ime_pos.y + ime_pos.height) * scale_y);
            const hwnd = self.app.hwnd orelse return .{ .left = left_px, .top = top_px, .right = left_px + 1, .bottom = bottom_px };
            var pt_tl = os.POINT{ .x = left_px, .y = top_px };
            var pt_br = os.POINT{ .x = left_px + 1, .y = bottom_px };
            _ = os.ClientToScreen(hwnd, &pt_tl); _ = os.ClientToScreen(hwnd, &pt_br);
            return .{ .left = pt_tl.x, .top = pt_tl.y, .right = pt_br.x, .bottom = pt_br.y };
        }

        fn isImePassthroughVirtualKey(vk: u32) bool {
            return switch (vk) { 0x15...0x1A, 0x1C...0x1F, 0xE5, 0xF3, 0xF4 => true, else => false };
        }

        pub fn bindSwapChain(self: *Self, swap_chain: *anyopaque) void {
            self.last_swap_chain = swap_chain;
            if (self.app.hwnd) |hwnd| _ = os.PostMessageW(hwnd, os.WM_APP_BIND_SWAP_CHAIN, @bitCast(@intFromPtr(swap_chain)), @bitCast(@intFromPtr(self)));
        }

        pub fn bindSwapChainHandle(self: *Self, swap_chain_handle: usize) void {
            self.last_swap_chain_handle = swap_chain_handle;
            if (self.app.hwnd) |hwnd| _ = os.PostMessageW(hwnd, os.WM_APP_BIND_SWAP_CHAIN_HANDLE, @bitCast(swap_chain_handle), @bitCast(@intFromPtr(self)));
        }

        pub fn completeBindSwapChain(self: *Self, swap_chain: *anyopaque) void {
            self.last_swap_chain = swap_chain; self.pending_swap_chain = null;
            if (self.swap_chain_panel_native) |native| { native.setSwapChain(swap_chain) catch {}; }
        }

        pub fn completeBindSwapChainHandle(self: *Self, swap_chain_handle: usize) void {
            self.last_swap_chain_handle = swap_chain_handle; self.pending_swap_chain_handle = null;
            if (self.swap_chain_panel_native2) |native2| { native2.setSwapChainHandle(@ptrFromInt(swap_chain_handle)) catch {}; }
        }

        fn maybeBindPendingSwapChain(self: *Self, _: []const u8) void {
            const sc = self.pending_swap_chain orelse return;
            if (self.loaded and self.size.width >= 2 and self.size.height >= 2) self.completeBindSwapChain(sc);
        }

        fn maybeBindPendingSwapChainHandle(self: *Self, _: []const u8) void {
            const h = self.pending_swap_chain_handle orelse return;
            if (self.loaded and self.size.width >= 2 and self.size.height >= 2) self.completeBindSwapChainHandle(h);
        }

        pub fn updateScrollbarUi(self: *Self, total: usize, offset: usize, len: usize) void {
            const sb = self.scroll_bar_insp orelse return;
            self.is_internal_scroll_update = true;
            defer self.is_internal_scroll_update = false;
            const rb = sb.queryInterface(com.IRangeBase) catch return;
            defer rb.release();
            const tf: f64 = @floatFromInt(total); const of: f64 = @floatFromInt(offset); const lf: f64 = @floatFromInt(len);
            const maximum = if (tf > lf) tf - lf else 0.0;
            _ = rb.SetMinimum(0.0) catch {}; _ = rb.SetMaximum(maximum) catch {}; _ = rb.SetValue(of) catch {}; _ = rb.SetLargeChange(lf) catch {}; _ = rb.SetSmallChange(1.0) catch {};
            const isb = sb.queryInterface(com.IScrollBar) catch return;
            defer isb.release();
            _ = isb.SetViewportSize(lf) catch {};
        }

        fn onScrollBarValueChanged(self: *Self, _: ?*anyopaque, args_raw: ?*anyopaque) void {
            if (self.is_internal_scroll_update) return;
            const args: *com.IRangeBaseValueChangedEventArgs = @ptrCast(@alignCast(args_raw orelse return));
            const row: usize = @intFromFloat(@max(0.0, @round(args.NewValue() catch return)));
            _ = self.core_surface.performBindingAction(.{ .scroll_to_row = row }) catch {};
        }

        fn onLoaded(self: *Self, _: *anyopaque, _: *anyopaque) void {
            if (self.in_loaded_handler or self.loaded) return;
            self.in_loaded_handler = true; defer self.in_loaded_handler = false;
            self.loaded = true;
            maybeBindPendingSwapChain(self, "onLoaded");
            maybeBindPendingSwapChainHandle(self, "onLoaded");
            self.app.ensureVisibleSurfaceAttached(self);
            if (self.app.activeSurface()) |as| if (as == self) input_runtime.focusKeyboardTarget(self.app);
        }

        fn onSizeChanged(self: *Self, _: *anyopaque, _: *anyopaque) void {
            const fe = self.swap_chain_panel.?.queryInterface(com.IFrameworkElement) catch return;
            defer fe.release();
            const dw = fe.ActualWidth() catch 0; const dh = fe.ActualHeight() catch 0;
            if (dw <= 0 or dh <= 0) return;
            const dip_w: u32 = @intFromFloat(dw); const dip_h: u32 = @intFromFloat(dh);
            if (is_islands) {
                self.size = .{ .width = dip_w, .height = dip_h };
            } else {
                const scale: f64 = @floatCast(self.content_scale.x);
                self.size = .{ .width = @intFromFloat(dw * scale), .height = @intFromFloat(dh * scale) };
            }
            if (self.core_initialized) self.core_surface.sizeCallback(self.size) catch {};
            maybeBindPendingSwapChain(self, "onSizeChanged");
            maybeBindPendingSwapChainHandle(self, "onSizeChanged");
        }

        pub fn rebindSwapChain(self: *Self) void {
            if (self.last_swap_chain_handle) |h| { self.bindSwapChainHandle(h); return; }
            if (self.last_swap_chain) |sc| self.bindSwapChain(sc);
        }

        pub fn setMouseShape(self: *Self, shape: terminal.MouseShape) void {
            _ = self;
            const cursor = os.LoadCursorW(null, switch (shape) {
                .default, .context_menu, .pointer, .alias, .copy, .grab, .grabbing, .zoom_in, .zoom_out => os.IDC_ARROW,
                .text, .vertical_text, .cell => os.IDC_IBEAM,
                .help => os.IDC_HELP, .progress => os.IDC_APPSTARTING, .wait => os.IDC_WAIT, .crosshair => os.IDC_CROSS,
                .move, .all_scroll => os.IDC_SIZEALL, .no_drop, .not_allowed => os.IDC_NO,
                .col_resize, .e_resize, .w_resize, .ew_resize => os.IDC_SIZEWE,
                .row_resize, .n_resize, .s_resize, .ns_resize => os.IDC_SIZENS,
                .ne_resize, .sw_resize, .nesw_resize => os.IDC_SIZENESW,
                .nw_resize, .se_resize, .nwse_resize => os.IDC_SIZENWSE,
            }) orelse return;
            _ = os.SetCursor(cursor);
        }

        pub fn setProgressReport(_: *Self, value: terminal.osc.Command.ProgressReport) void {
            if (value.state == .@"error") _ = os.MessageBeep(os.MB_OK);
        }

        pub fn commandFinished(_: *Self, value: apprt.Action.Value(.command_finished)) bool {
            if (value.exit_code) |code| {
                if (code != 0) _ = os.MessageBeep(os.MB_OK);
            }
            return true;
        }

        pub fn setBellRinging(_: *Self, value: bool) void {
            if (value) _ = os.MessageBeep(os.MB_OK);
        }
    };
}
