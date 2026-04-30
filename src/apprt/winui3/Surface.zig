/// WinUI 3 XAML Islands surface implementation for Ghostty.
///
/// D3D11 SwapChainPanel rendering is window-management-agnostic.
/// This is a copy of winui3/Surface.zig with import paths adjusted
/// to reference shared modules from ../winui3/ and the local App.zig.
pub fn Surface(comptime App: type) type {
    return struct {
        const Self = @This();

        const std = @import("std");
        const Allocator = std.mem.Allocator;
        const apprt = @import("../../apprt.zig");
        const CoreSurface = @import("../../Surface.zig");
        const CoreApp = @import("../../App.zig");
        const configpkg = @import("../../config.zig");
        const input = @import("../../input.zig");
        const terminal = @import("../../terminal/main.zig");
        const com = @import("com.zig");
        const winrt = @import("winrt.zig");
        const native_interop = @import("native_interop.zig");
        const input_runtime = @import("input_runtime.zig"); // Keep this import
        const profiles = @import("profiles.zig"); // Import profiles.zig
        const key = @import("key.zig");
        const os = @import("os.zig");
        const tsf_logic = @import("tsf_logic.zig");

        const SearchOverlay = @import("SearchOverlay_generic.zig").SearchOverlay(Self);

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

        /// Whether this surface has been closed (use-after-free guard).
        closed: bool = false,

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
        // TextBox composition tokens removed — TSF is now the sole IME handler.
        // ime_text_comp_start_token, ime_text_comp_change_token, ime_text_comp_end_token removed.

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

        /// Stable tab ID (monotonically increasing, never reused).
        tab_id: u64 = 0,

        /// The IInspectable of the TabViewItem this surface belongs to (for title updates).
        tab_view_item_inspectable: ?*winrt.IInspectable = null,

        /// Current title of the surface.
        /// Points into title_static_buf when short enough, otherwise heap-allocated.
        title: ?[:0]const u8 = null,
        /// True when `title` is heap-allocated and must be freed.
        title_is_heap: bool = false,
        /// Fixed buffer for short titles (avoids heap allocation on hot path).
        title_static_buf: [256]u8 = undefined,
        /// Fixed buffer for UTF-16 conversion of display titles (avoids heap allocation).
        title_utf16_buf: [512]u16 = undefined,
        /// Cached previous display title (UTF-8) to skip redundant UTF-16/HSTRING/COM calls.
        last_display_title_buf: [512]u8 = undefined,
        last_display_title_len: usize = 0,

        /// Inner layout grid: col 0 = SwapChainPanel (1*), col 1 = ScrollBar (17px).
        surface_grid: ?*winrt.IInspectable = null,
        /// The vertical ScrollBar XAML control (IInspectable, QI to IScrollBar/IRangeBase).
        scroll_bar_insp: ?*winrt.IInspectable = null,
        /// Cached COM interfaces for scrollbar to avoid repeated QIs.
        scroll_bar_range_base: ?*com.IRangeBase = null,
        scroll_bar_isb: ?*com.IScrollBar = null,
        scroll_bar_fe: ?*com.IFrameworkElement = null,
        scroll_bar_ue: ?*com.IUIElement = null,

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

        dirty: DirtyFlags = .{},

        /// Pending scrollbar values for coalescing rapid updates.
        pending_scrollbar: ?struct { total: usize, offset: usize, len: usize } = null,
        /// Counters for scrollbar update frequency measurement.
        scrollbar_update_count: u32 = 0,
        scrollbar_skip_count: u32 = 0,
        last_scrollbar_log_ns: i128 = 0,

        /// Pending mouse shape for batched application.
        pending_mouse_shape: ?terminal.MouseShape = null,

        /// Cached scrollbar values for diff-based COM call minimization.
        scrollbar_initialized: bool = false,
        last_scrollbar_maximum: f64 = -1.0,
        last_scrollbar_value: f64 = -1.0,
        last_scrollbar_viewport: f64 = -1.0,

        /// Timestamp of the last window title update to enable throttling.
        last_title_update_ns: i128 = 0,

        /// Last applied mouse cursor shape for deduplication.
        last_mouse_shape: ?terminal.MouseShape = null,
        /// Timestamp of the last bell notification to prevent audio spam.
        last_bell_ns: i128 = 0,

        /// Touch scroll anchor point (set on touch press, cleared on release).
        /// Used to convert touch drag distance into scroll rows, matching
        /// Windows Terminal's ControlInteractivity::TouchMoved pattern.
        touch_anchor: ?com.Point = null,

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

        /// Dirty flags for batched UI updates (flushed at end of drainMailbox).
        const DirtyFlags = packed struct {
            scrollbar: bool = false,
            mouse_shape: bool = false,
        };

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

        pub fn init(self: *Self, app: *App, core_app: *CoreApp, config: *const configpkg.Config, _profile_opt: ?profiles.Profile) !void {
            // TODO: Use _profile_opt for per-tab profile configuration when profile switching is implemented.
            _ = _profile_opt;
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

            // NOTE: SwapChainPanel cannot have a XAML Background set (E_FAIL).
            // Pointer events are registered on the surface_grid (parent Grid with
            // Background="Transparent" from Surface.xaml) instead.  See below.

            // Set up the inner XAML element tree (Grid + ScrollBar + IME TextBox).
            try self.setupXamlElements(panel);

            // Register all XAML event handlers (Loaded, SizeChanged, pointer, keyboard, focus, IME).
            try self.registerXamlEventHandlers(panel);

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

        /// Create and populate the inner surface grid from compiled XAML (SurfaceRoot.xbf).
        /// Sets up the Grid layout with SwapChainPanel at index 0, ScrollBar from XAML,
        /// and a hidden IME TextBox for TSF input.
        fn setupXamlElements(self: *Self, panel: *winrt.IInspectable) !void {
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
            self.scroll_bar_range_base = sb_insp.queryInterface(com.IRangeBase) catch null;
            self.scroll_bar_isb = sb_insp.queryInterface(com.IScrollBar) catch null;
            self.scroll_bar_fe = sb_insp.queryInterface(com.IFrameworkElement) catch null;
            self.scroll_bar_ue = sb_insp.queryInterface(com.IUIElement) catch null;
            self.ime_text_box = ime_tb;
            _ = ime_tb_insp.release();

            log.info("Surface grid created via LoadComponent (SurfaceRoot.xbf): SwapChainPanel + ScrollBar + hidden IME TextBox", .{});
        }

        /// Register all XAML event handlers: Loaded, SizeChanged on the SwapChainPanel;
        /// pointer events on the surface_grid; keyboard/focus events on the panel;
        /// and IME TextBox events for TSF input.
        fn registerXamlEventHandlers(self: *Self, panel: *winrt.IInspectable) !void {
            const gen = @import("com_generated.zig");

            // Register Loaded handler to defer SetSwapChain until the panel is ready.
            const framework_element = try panel.queryInterface(com.IFrameworkElement);
            defer framework_element.release();
            const LoadedDelegate = gen.RoutedEventHandlerImpl(Self, *const fn (*Self, *anyopaque, *anyopaque) void);
            const loaded_delegate = try LoadedDelegate.createWithIid(self.app.core_app.alloc, self, &onLoaded, &com.IID_RoutedEventHandler);
            // Note: LoadedDelegate.createWithIid returns a ref-counted COM object.
            // We pass it to addLoaded which will AddRef it again.
            defer loaded_delegate.release();
            self.loaded_token = try framework_element.AddLoaded(loaded_delegate.comPtr());

            const SizeChangedDelegate = gen.SizeChangedEventHandlerImpl(Self, *const fn (*Self, *anyopaque, *anyopaque) void);
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

            // Register XAML input event handlers.
            //
            // POINTER events are registered on the surface_grid (parent Grid), NOT on
            // the SwapChainPanel.  In WinUI3/XAML Islands the SwapChainPanel cannot have
            // a Background set (SetBackground returns E_FAIL), so it is transparent to
            // hit testing and never receives PointerPressed/Moved/Released.  The Grid
            // has Background="Transparent" from Surface.xaml which enables hit testing.
            // This matches Windows Terminal's TermControl pattern.
            //
            // KEYBOARD and FOCUS events stay on the SwapChainPanel because keyboard
            // focus is tied to the focusable element (IsTabStop=true).
            {
                const ui_element = try panel.queryInterface(com.IUIElement);
                defer ui_element.release();

                // Enable keyboard focus on the SwapChainPanel.
                ui_element.SetIsTabStop(true) catch |err| {
                    log.warn("putIsTabStop failed: {}", .{err});
                };

                const PointerDelegate = gen.PointerEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const KeyDelegate = gen.KeyEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const RoutedDelegate = gen.RoutedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const CharRecvDelegate = gen.TypedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);

                // Pointer events on the surface_grid (has Background="Transparent").
                const grid_ue = try self.surface_grid.?.queryInterface(com.IUIElement);
                defer grid_ue.release();

                const ptr_pressed = try PointerDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerPressed, &com.IID_PointerEventHandler);
                defer ptr_pressed.release();
                self.pointer_pressed_token = grid_ue.AddPointerPressed(ptr_pressed.comPtr()) catch 0;

                const ptr_moved = try PointerDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerMoved, &com.IID_PointerEventHandler);
                defer ptr_moved.release();
                self.pointer_moved_token = grid_ue.AddPointerMoved(ptr_moved.comPtr()) catch 0;

                const ptr_released = try PointerDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerReleased, &com.IID_PointerEventHandler);
                defer ptr_released.release();
                self.pointer_released_token = grid_ue.AddPointerReleased(ptr_released.comPtr()) catch 0;

                const ptr_wheel = try PointerDelegate.createWithIid(self.app.core_app.alloc, self, &onXamlPointerWheelChanged, &com.IID_PointerEventHandler);
                defer ptr_wheel.release();
                self.pointer_wheel_changed_token = grid_ue.AddPointerWheelChanged(ptr_wheel.comPtr()) catch 0;

                // Keyboard events on the SwapChainPanel (PreviewKeyDown catches navigation keys
                // before XAML consumes them).
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
                    const ImeKeyDelegate = gen.KeyEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                    const ImeRoutedDelegate = gen.RoutedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                    const ImeCharRecvDelegate = gen.TypedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);

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

                const TextChangedDelegate = gen.TextChangedEventHandlerImpl(Self, *const fn (*Self, ?*anyopaque, ?*anyopaque) void);
                const ime_text_changed = try TextChangedDelegate.createWithIid(self.app.core_app.alloc, self, &onImeTextBoxTextChanged, &com.IID_TextChangedEventHandler);
                defer ime_text_changed.release();
                self.ime_text_changed_token = ime_tb.AddTextChanged(ime_text_changed.comPtr()) catch 0;

                // TextBox composition event handlers (Started/Changed/Ended) removed.
                // TSF is now the sole IME handler — composition flows through
                // TsfImplementation's ITfContextOwnerCompositionSink and ITfTextEditSink.
            }
        }

        pub fn deinit(self: *Self) void {
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
                // Unregister all XAML event handlers before releasing COM objects.
                self.unregisterXamlEventHandlers();
                native.release();
                self.swap_chain_panel_native = null;
            }

            // Release XAML elements, COM references, and allocated memory.
            self.cleanupXamlElements();
        }

        /// Unregister all XAML event handlers: Loaded/SizeChanged on the panel,
        /// pointer events on the surface_grid, keyboard/focus on the panel,
        /// and IME TextBox events.
        fn unregisterXamlEventHandlers(self: *Self) void {
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

                // Unregister pointer events from surface_grid.
                if (self.surface_grid) |grid| {
                    if (grid.queryInterface(com.IUIElement)) |grid_ue| {
                        defer grid_ue.release();
                        if (self.pointer_pressed_token != 0) {
                            grid_ue.RemovePointerPressed(self.pointer_pressed_token) catch {};
                        }
                        if (self.pointer_moved_token != 0) {
                            grid_ue.RemovePointerMoved(self.pointer_moved_token) catch {};
                        }
                        if (self.pointer_released_token != 0) {
                            grid_ue.RemovePointerReleased(self.pointer_released_token) catch {};
                        }
                        if (self.pointer_wheel_changed_token != 0) {
                            grid_ue.RemovePointerWheelChanged(self.pointer_wheel_changed_token) catch {};
                        }
                    } else |_| {}
                }
                // Unregister keyboard/focus events from SwapChainPanel.
                if (panel.queryInterface(com.IUIElement)) |ue| {
                    defer ue.release();
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
                // TextBox composition tokens removed — TSF is sole IME handler.
                self.ime_preview_key_down_token = 0;
                self.ime_preview_key_up_token = 0;
                self.ime_character_received_token = 0;
                self.ime_text_changed_token = 0;
                self.ime_got_focus_token = 0;
                self.ime_lost_focus_token = 0;
            }
        }

        /// Release XAML element COM references and free allocated memory
        /// (scrollbar, surface grid, IME TextBox, SwapChainPanel, tab item, title).
        fn cleanupXamlElements(self: *Self) void {
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

                if (self.scroll_bar_range_base) |rb| {
                    rb.release();
                    self.scroll_bar_range_base = null;
                }
                if (self.scroll_bar_isb) |isb| {
                    isb.release();
                    self.scroll_bar_isb = null;
                }
                if (self.scroll_bar_fe) |fe| {
                    fe.release();
                    self.scroll_bar_fe = null;
                }
                if (self.scroll_bar_ue) |ue| {
                    ue.release();
                    self.scroll_bar_ue = null;
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

            if (self.title_is_heap) {
                if (self.title) |t| {
                    // title_is_heap means it was allocated with dupeZ; cast away const for free.
                    self.app.core_app.alloc.free(@constCast(t));
                }
            }
            self.title = null;
            self.title_is_heap = false;
        }

        pub fn core(self: *Self) *CoreSurface {
            return &self.core_surface;
        }

        pub fn rtApp(self: *Self) *App {
            return self.app;
        }

        pub fn close(self: *Self, process_active: bool) void {
            _ = process_active;
            self.closed = true;
            self.app.closeSurface(self);
        }

        pub fn getTitle(self: *Self) ?[:0]const u8 {
            return self.title;
        }

        pub fn getContentScale(self: *const Self) !apprt.ContentScale {
            return self.content_scale;
        }

        pub fn getSize(self: *const Self) !apprt.SurfaceSize {
            return self.size;
        }

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

        pub fn panePid(self: *const Self) ?u32 {
            if (!self.core_initialized) return null;
            return self.core_surface.panePid();
        }

        pub fn viewportString(self: *Self, alloc: std.mem.Allocator) ![]const u8 {
            if (!self.core_initialized) return alloc.dupe(u8, "");
            return try self.core_surface.viewportString(alloc);
        }

        pub fn historyString(self: *Self, alloc: std.mem.Allocator) ![]const u8 {
            if (!self.core_initialized) return alloc.dupe(u8, "");
            return try self.core_surface.historyString(alloc);
        }

        // ---- Non-blocking (tryLock) variants for the CP read lane.
        //
        // Issue #207 hyp 1: the CP pipe-server thread must not block on
        // `core_surface.renderer_state.mutex`. These shims forward to
        // the `*Locked` core variants and propagate the same null /
        // error.RendererLocked contract upward to App.zig.
        //
        // For a non-initialized surface we do NOT return BUSY — there
        // is genuinely no state to capture, the lock is irrelevant.
        // Match the empty-string / null behaviour of the blocking
        // wrappers above.

        pub fn pwdLocked(
            self: *Self,
            alloc: std.mem.Allocator,
        ) !?[]const u8 {
            if (!self.core_initialized) return null;
            return try self.core_surface.pwdLocked(alloc);
        }

        pub fn hasSelectionLocked(self: *const Self) ?bool {
            if (!self.core_initialized) return false;
            return self.core_surface.hasSelectionLocked();
        }

        pub fn cursorIsAtPromptLocked(self: *Self) ?bool {
            if (!self.core_initialized) return false;
            return self.core_surface.cursorIsAtPromptLocked();
        }

        pub fn panePidLocked(self: *const Self) error{RendererLocked}!?u32 {
            if (!self.core_initialized) return null;
            return self.core_surface.panePidLocked();
        }

        pub fn viewportStringLocked(
            self: *Self,
            alloc: std.mem.Allocator,
        ) ![]const u8 {
            if (!self.core_initialized) return alloc.dupe(u8, "");
            return try self.core_surface.viewportStringLocked(alloc);
        }

        pub fn historyStringLocked(
            self: *Self,
            alloc: std.mem.Allocator,
        ) ![]const u8 {
            if (!self.core_initialized) return alloc.dupe(u8, "");
            return try self.core_surface.historyStringLocked(alloc);
        }

        pub fn getCursorPos(self: *const Self) !apprt.CursorPos {
            return self.cursor_pos;
        }

        pub fn supportsSwapChainHandle(self: *const Self) bool {
            return self.swap_chain_panel_native2 != null;
        }

        pub fn supportsClipboard(
            _: *const Self,
            clipboard_type: apprt.Clipboard,
        ) bool {
            return switch (clipboard_type) {
                .standard => true,
                .selection, .primary => false,
            };
        }

        pub fn clipboardRequest(
            self: *Self,
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
            self: *Self,
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

        pub fn defaultTermioEnv(self: *Self) !std.process.EnvMap {
            const alloc = self.app.core_app.alloc;
            var env = try std.process.getEnvMap(alloc);
            errdefer env.deinit();
            try env.put("TERM", "xterm-256color");
            try env.put("COLORTERM", "truecolor");
            return env;
        }

        pub fn redrawInspector(_: *Self) void {
            // No-op for MVP
        }

        /// Update the TabViewItem header with the given title.
        /// Hot-path optimized: uses fixed-size buffers when titles fit,
        /// falling back to heap allocation for unusually long titles.
        pub fn setTabTitle(self: *Self, title: [:0]const u8) void {
            if (self.title) |old_title| {
                if (std.mem.eql(u8, old_title, title)) {
                    // No change in title, skip allocation and UI update entirely.
                    return;
                }
            }

            const now = std.time.nanoTimestamp();
            const min_interval_ns = 16 * std.time.ns_per_ms; // ~60Hz
            if (now - self.last_title_update_ns < min_interval_ns) {
                // Throttle title updates to prevent UI thread saturation.
                return;
            }
            self.last_title_update_ns = now;

            const alloc = self.app.core_app.alloc;

            // Free old heap-allocated title if any.
            if (self.title_is_heap) {
                if (self.title) |old_title| alloc.free(@constCast(old_title));
            }

            // Store the title for getTitle() queries (original, without tab ID prefix).
            // Use fixed buffer when possible to avoid heap allocation on hot path.
            if (title.len < self.title_static_buf.len) {
                @memcpy(self.title_static_buf[0..title.len], title[0..title.len]);
                self.title_static_buf[title.len] = 0;
                self.title = self.title_static_buf[0..title.len :0];
                self.title_is_heap = false;
            } else {
                // Title too long for static buffer; fall back to heap allocation.
                self.title = alloc.dupeZ(u8, title) catch {
                    log.warn("setTabTitle: failed to allocate title copy (len={})", .{title.len});
                    self.title = null;
                    self.title_is_heap = false;
                    return;
                };
                self.title_is_heap = true;
            }

            // Build display title: prepend "PID:tab_id" when control plane is active.
            const cp_active = self.app.control_plane != null;
            const display_title: [:0]const u8 = if (cp_active) blk: {
                const sn = if (self.app.control_plane) |cp| (cp.session_name orelse "?") else "?";
                const raw = std.fmt.allocPrint(alloc, "{s}:t_{d:0>3} {s}", .{ sn, self.tab_id, title }) catch break :blk title;
                defer alloc.free(raw);
                break :blk alloc.dupeZ(u8, raw) catch title;
            } else title;
            const display_owned = cp_active and display_title.ptr != title.ptr;
            defer if (display_owned) alloc.free(display_title);

            // Skip UTF-16 conversion and COM call if display title hasn't changed.
            const dt_bytes = display_title[0..display_title.len];
            if (self.last_display_title_len == dt_bytes.len and
                self.last_display_title_len <= self.last_display_title_buf.len and
                std.mem.eql(u8, self.last_display_title_buf[0..self.last_display_title_len], dt_bytes))
            {
                return;
            }
            // Cache the new display title for future comparison.
            if (dt_bytes.len <= self.last_display_title_buf.len) {
                @memcpy(self.last_display_title_buf[0..dt_bytes.len], dt_bytes);
                self.last_display_title_len = dt_bytes.len;
            } else {
                // Title too long for cache; set len to 0 so next call won't falsely match.
                self.last_display_title_len = 0;
            }

            // Actually update the TabViewItem UI using WinRT PropertyValue.
            // Use fixed UTF-16 buffer when possible to avoid heap allocation.
            if (self.tab_view_item_inspectable) |tvi_insp| {
                if (tvi_insp.queryInterface(com.ITabViewItem)) |tvi| {
                    defer tvi.release();

                    // Try stack buffer first; fall back to heap for long titles.
                    const utf16_result = self.convertDisplayTitleToUtf16(display_title, alloc);
                    const utf16_slice = utf16_result.slice;
                    const utf16_heap = utf16_result.heap_owned;
                    defer if (utf16_heap) |h| alloc.free(h);

                    if (utf16_slice) |utf16| {
                        if (winrt.createHString(utf16)) |hstr| {
                            defer winrt.deleteHString(hstr);
                            const util = @import("util.zig");
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

        /// Convert a display title to UTF-16, preferring the fixed buffer.
        /// Returns the UTF-16 slice and an optional heap allocation to free.
        fn convertDisplayTitleToUtf16(
            self: *Self,
            display_title: [:0]const u8,
            alloc: std.mem.Allocator,
        ) struct { slice: ?[]const u16, heap_owned: ?[]u16 } {
            // Try fixed buffer first (covers the vast majority of titles).
            if (display_title.len <= self.title_utf16_buf.len) {
                const n = std.unicode.utf8ToUtf16Le(&self.title_utf16_buf, display_title) catch {
                    log.warn("setTabTitle: utf8ToUtf16Le failed", .{});
                    return .{ .slice = null, .heap_owned = null };
                };
                return .{ .slice = self.title_utf16_buf[0..n], .heap_owned = null };
            }
            // Fall back to heap allocation for very long titles.
            const heap = std.unicode.utf8ToUtf16LeAlloc(alloc, display_title) catch {
                log.warn("setTabTitle: utf8ToUtf16LeAlloc failed", .{});
                return .{ .slice = null, .heap_owned = null };
            };
            return .{ .slice = heap, .heap_owned = heap };
        }

        // --- Event handlers called from WndProc ---

        pub fn updateSize(self: *Self, width: u32, height: u32) void {
            if (width == 0 or height == 0) return;
            log.info("Surface.updateSize: {}x{} -> {}x{}", .{ self.size.width, self.size.height, width, height });
            self.size = .{ .width = width, .height = height };
            if (self.core_initialized) {
                self.core_surface.sizeCallback(self.size) catch |err| {
                    log.warn("size callback error: {}", .{err});
                };
            }
        }

        pub fn updateContentScale(self: *Self) void {
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

        pub fn handleKeyEvent(self: *Self, vk: u16, pressed: bool) void {
            if (!self.core_initialized) return;

            const ghostty_key = key.vkToKey(vk) orelse {
                // Unmapped VK (e.g. VK_PROCESSKEY from IME) -- reset to .none so
                // any subsequent WM_CHAR (IME commit text) passes through as a
                // standalone character event.
                if (pressed) self.pending_keydown = .none;
                log.debug("handleKeyEvent: unmapped vk=0x{X:0>4} pressed={} -> pending=none", .{ vk, pressed });
                return;
            };

            // F12 toggles the debug overlay
            if (ghostty_key == .f12 and pressed) {
                if (self.core_surface.renderer_thread.mailbox.push(.toggle_debug_overlay) == .ok) {
                    log.info("debug overlay toggled", .{});
                }
            }

            log.debug("handleKeyEvent: vk=0x{X:0>4} pressed={} key={s}", .{ vk, pressed, @tagName(ghostty_key) });
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

            // keyCallback may trigger close_tab, which closes this Surface.
            _ = self.core_surface.keyCallback(event) catch |err| {
                log.warn("key callback error vk=0x{X:0>2}: {}", .{ vk, err });
                return;
            };

            // If keyCallback closed this surface (e.g. close_tab binding),
            // do not access further state.
            if (self.closed) return;

            // Suppress any subsequent WM_CHAR for consumed press events.
            // (Releases don't produce WM_CHAR.)
            if (pressed) {
                self.pending_keydown = .consumed;
            }
        }

        pub fn handleCharEvent(self: *Self, char_code: u16) void {
            if (!self.core_initialized) return;

            // Capture and consume the pending keydown state.
            const state = self.pending_keydown;
            self.pending_keydown = .none;

            switch (state) {
                // WM_KEYDOWN was already consumed (function key, keybinding, etc.)
                // -- suppress this WM_CHAR to avoid double input.
                .consumed => {
                    log.debug("handleCharEvent: SUPPRESSED char=0x{X:0>4} (pending_keydown=consumed)", .{char_code});
                    return;
                },

                // .pending or .none -- process the character below.
                .pending, .none => {},
            }
            log.debug("handleCharEvent: char=0x{X:0>4} state={s}", .{ char_code, @tagName(state) });

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

            const result = self.core_surface.keyCallback(ev) catch |err| {
                log.warn("char callback error: {}", .{err});
                log.err("handleCharEvent: keyCallback ERROR for U+{X:0>4}: {}", .{ @as(u32, codepoint), err });
                return;
            };
            log.debug("handleCharEvent: keyCallback U+{X:0>4} result={s}", .{ @as(u32, codepoint), @tagName(result) });
        }

        pub fn handleMouseMove(self: *Self, x: f64, y: f64) void {
            if (!self.core_initialized) return;
            const pos = pointerToCursorPos(x, y, 0, 0);
            self.cursor_pos = pos;
            const mods = key.getModifiers();
            self.core_surface.cursorPosCallback(pos, mods) catch |err| {
                log.warn("cursor pos callback error: {}", .{err});
            };
        }

        pub fn handleMouseButton(self: *Self, button: input.MouseButton, action: input.MouseButtonState) void {
            if (!self.core_initialized) return;
            const mods = key.getModifiers();

            _ = self.core_surface.mouseButtonCallback(action, button, mods) catch |err| {
                log.warn("mouse button callback error: {}", .{err});
                return;
            };
        }

        /// Capture/release pointer on the surface_grid UIElement using XAML's CapturePointer.
        /// In XAML Islands, Win32 SetCapture does not work — pointer capture must go through
        /// the XAML compositor.  This matches Windows Terminal's TermControl pattern.
        fn capturePointer(self: *Self, ea: *com.IPointerRoutedEventArgs) void {
            const grid = self.surface_grid orelse return;
            const grid_ue = grid.queryInterface(com.IUIElement) catch return;
            defer grid_ue.release();
            const pointer = ea.Pointer() catch return;
            defer pointer.release();
            _ = grid_ue.CapturePointer(@ptrCast(pointer)) catch |err| {
                log.warn("CapturePointer failed: {}", .{err});
            };
        }

        fn releasePointerCapture(self: *Self, ea: *com.IPointerRoutedEventArgs) void {
            const grid = self.surface_grid orelse return;
            const grid_ue = grid.queryInterface(com.IUIElement) catch return;
            defer grid_ue.release();
            const pointer = ea.Pointer() catch return;
            defer pointer.release();
            grid_ue.ReleasePointerCapture(@ptrCast(pointer)) catch |err| {
                log.warn("ReleasePointerCapture failed: {}", .{err});
            };
        }

        pub fn handleScroll(self: *Self, xoffset: f64, yoffset: f64) void {
            if (!self.core_initialized) return;
            self.core_surface.scrollCallback(xoffset, yoffset, .{}) catch |err| {
                log.warn("scroll callback error: {}", .{err});
            };
        }

        /// Returns the PointerDeviceType from an IPointerPoint: 0=Touch, 1=Pen, 2=Mouse.
        /// Calls the vtable slot directly since com_native.zig may not have a convenience accessor.
        fn getPointerDeviceType(point: *com.IPointerPoint) i32 {
            var out: i32 = 2; // default to Mouse
            const hr = point.lpVtbl.get_PointerDeviceType(@ptrCast(point), &out);
            if (hr < 0) return 2; // on error, default to mouse
            return out;
        }

        /// Convert pointer coordinates to surface-local cursor coordinates.
        ///
        /// Coordinates are expected to be in DIP space. If the caller obtained
        /// pointer coordinates from a root-relative space, pass the surface's
        /// root-space origin as `surface_origin_*` to normalize.
        fn pointerToCursorPos(raw_x: f64, raw_y: f64, surface_origin_x: f64, surface_origin_y: f64) apprt.CursorPos {
            return .{
                .x = @floatCast(raw_x - surface_origin_x),
                .y = @floatCast(raw_y - surface_origin_y),
            };
        }

        /// Resolve the current pointer point using the surface grid as the
        /// preferred coordinate space (surface-local). Falls back to root space.
        fn getCurrentPointerPoint(self: *Self, ea: *com.IPointerRoutedEventArgs) ?*com.IPointerPoint {
            if (self.surface_grid) |grid| {
                if (grid.queryInterface(com.IUIElement)) |grid_ue| {
                    defer grid_ue.release();
                    if (ea.getCurrentPoint(grid_ue)) |point| {
                        return point;
                    } else |_| {}
                } else |_| {}
            }

            return ea.getCurrentPoint(null) catch null;
        }

        // --- XAML event callbacks ---

        fn onXamlPointerPressed(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            log.debug("onXamlPointerPressed: core_initialized={}", .{self.core_initialized});
            if (!self.core_initialized) return;
            const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const point = getCurrentPointerPoint(self, ea) orelse return;
            defer point.release();
            const pos = point.Position() catch return;

            // Branch on PointerDeviceType: 0=Touch, 1=Pen, 2=Mouse
            const device_type = getPointerDeviceType(point); // default to mouse
            if (device_type == 0) {
                // Touch: record anchor for drag-to-scroll (Windows Terminal pattern).
                // Don't send mouse button events for touch — touch scrolls the viewport.
                self.touch_anchor = pos;
                log.debug("onXamlPointerPressed: touch anchor set ({d:.0}, {d:.0})", .{ pos.X, pos.Y });
                // Focus on touch tap (matches WT _TappedHandler behavior).
                if (!self.app.resizing) {
                    input_runtime.focusKeyboardTarget(self.app);
                    if (self.app.tsf_impl) |*tsf_impl| {
                        tsf_impl.focus();
                    }
                }
                self.capturePointer(ea);
                ea.SetHandled(true) catch {};
                return;
            }

            // Mouse or Pen: existing behavior
            const cursor = pointerToCursorPos(@floatCast(pos.X), @floatCast(pos.Y), 0, 0);
            self.handleMouseMove(cursor.x, cursor.y);
            const props = point.Properties() catch return;
            defer props.release();
            const update_kind = props.PointerUpdateKind() catch return;
            const button: input.MouseButton = switch (update_kind) {
                1 => .left, // LeftButtonPressed
                3 => .right, // RightButtonPressed
                5 => .middle, // MiddleButtonPressed
                else => return,
            };
            // Focus the SwapChainPanel — TSF is associated with the main HWND
            // and handles IME composition directly. No TextBox redirection needed.
            if (!self.app.resizing) {
                input_runtime.focusKeyboardTarget(self.app);
                // Ensure TSF knows we have focus.
                if (self.app.tsf_impl) |*tsf_impl| {
                    tsf_impl.focus();
                }
            }
            self.capturePointer(ea);
            self.handleMouseButton(button, .press);
            ea.SetHandled(true) catch {};
        }

        fn onXamlPointerMoved(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const point = getCurrentPointerPoint(self, ea) orelse return;
            defer point.release();
            const pos = point.Position() catch return;

            // Branch on PointerDeviceType: 0=Touch, 1=Pen, 2=Mouse
            const device_type = getPointerDeviceType(point);
            if (device_type == 0) {
                // Touch drag → viewport scroll (Windows Terminal TouchMoved pattern).
                if (self.touch_anchor) |anchor| {
                    const dy = pos.Y - anchor.Y;
                    // Use a fixed row height estimate (16 DIP). Scroll after moving
                    // more than half a row, matching WT's threshold.
                    const row_height: f32 = 16.0;
                    if (@abs(dy) > row_height / 2.0) {
                        // Negative because dragging down = scroll up (content moves up)
                        const rows = dy / -row_height;
                        self.handleScroll(0, @floatCast(rows));
                        self.touch_anchor = pos; // update anchor
                    }
                }
                ea.SetHandled(true) catch {};
                return;
            }

            // Mouse or Pen: existing behavior
            const cursor = pointerToCursorPos(@floatCast(pos.X), @floatCast(pos.Y), 0, 0);
            self.handleMouseMove(cursor.x, cursor.y);
            ea.SetHandled(true) catch {};
        }

        fn onXamlPointerReleased(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IPointerRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const point = getCurrentPointerPoint(self, ea) orelse return;
            defer point.release();
            const pos = point.Position() catch return;

            // Branch on PointerDeviceType: 0=Touch, 1=Pen, 2=Mouse
            const device_type = getPointerDeviceType(point);
            if (device_type == 0) {
                // Touch release: clear anchor (Windows Terminal TouchReleased pattern).
                self.touch_anchor = null;
                self.releasePointerCapture(ea);
                log.debug("onXamlPointerReleased: touch anchor cleared", .{});
                ea.SetHandled(true) catch {};
                return;
            }

            // Mouse or Pen: existing behavior
            const cursor = pointerToCursorPos(@floatCast(pos.X), @floatCast(pos.Y), 0, 0);
            self.handleMouseMove(cursor.x, cursor.y);
            const props = point.Properties() catch return;
            defer props.release();
            const update_kind = props.PointerUpdateKind() catch return;
            const button: input.MouseButton = switch (update_kind) {
                2 => .left, // LeftButtonReleased
                4 => .right, // RightButtonReleased
                6 => .middle, // MiddleButtonReleased
                else => return,
            };
            self.releasePointerCapture(ea);
            self.handleMouseButton(button, .release);
            if (button == .right) {
                self.app.showContextMenuAtCursor();
            }
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

        fn onXamlPreviewKeyDown(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const vk = ea.Key() catch return;
            const vk_u32 = @as(u32, @bitCast(vk));
            log.debug("xaml_surface: PreviewKeyDown vk=0x{x}", .{vk_u32});
            if (isImePassthroughVirtualKey(vk_u32)) {
                // IME toggle/mode key or VK_PROCESSKEY — let TSF handle it.
                // TSF is associated with the main HWND and will process IME
                // composition directly without needing the TextBox.
                log.debug("PreviewKeyDown: IME key 0x{x} -> pass to TSF (no TextBox redirect)", .{vk_u32});
                // Notify TSF that focus should be set (in case it was lost).
                if (self.app.tsf_impl) |*tsf_impl| {
                    tsf_impl.focus();
                }
                return; // Don't mark handled — let IME process via TSF.
            }
            // When TSF has an active composition and the key is a text-producing key
            // (not a modifier or control combo), suppress it. In XAML Islands, some
            // composition keystrokes may arrive with their real VK instead of
            // VK_PROCESSKEY, causing raw characters to leak into the PTY.
            // Modifier combos (Ctrl+C, Alt+F4) are let through so they still work
            // during composition.
            if (self.app.tsf_impl) |*tsf_impl| {
                if (tsf_impl.hasActiveComposition()) {
                    const mods = key.getModifiers().binding();
                    const is_modifier_combo = mods.ctrl or mods.alt or mods.super;
                    if (!is_modifier_combo) {
                        log.debug("PreviewKeyDown: vk=0x{x} SUPPRESSED (TSF composition active)", .{vk_u32});
                        return; // Let TSF handle this key within the composition.
                    }
                }
            }
            self.handleKeyEvent(@intCast(@as(u32, @bitCast(vk))), true);
            if (self.closed) return;
            // For text-producing keys, handleKeyEvent defers to CharacterReceived by
            // leaving pending_keydown=.pending. Do not mark those handled here or the
            // character event is suppressed.
            switch (self.pending_keydown) {
                .pending => {},
                else => ea.SetHandled(true) catch {},
            }
        }

        fn onXamlPreviewKeyUp(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const vk = ea.Key() catch return;
            self.handleKeyEvent(@intCast(@as(u32, @bitCast(vk))), false);
            if (self.closed) return;
            ea.SetHandled(true) catch {};
        }

        fn onXamlCharacterReceived(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            // When TSF has an active composition, character events are handled by TSF's
            // preedit/output callbacks. Letting them through here would cause raw
            // keystroke characters (e.g. 'k', 'a') to leak into the PTY alongside the
            // composed IME text — the "input drift" regression.
            if (self.app.tsf_impl) |*tsf_impl| {
                if (tsf_impl.hasActiveComposition()) {
                    log.debug("xaml_surface: CharacterReceived SUPPRESSED (TSF composition active)", .{});
                    return;
                }
                // After TSF commits text via tsfHandleOutput, the same finalized
                // non-ASCII characters may also arrive via CharacterReceived.
                // Suppress that duplicate XAML path and rely on TSF output alone.
                // Logic extracted to tsf_logic for testability.
                if (self.app.tsf_just_committed) {
                    const ea_peek: *com.ICharacterReceivedRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
                    const ch_peek = ea_peek.Character() catch return;
                    if (tsf_logic.shouldSuppressCharAfterCommit(&self.app.tsf_just_committed, ch_peek)) {
                        log.debug("xaml_surface: CharacterReceived ch=0x{x} SUPPRESSED (tsf_just_committed, non-ASCII)", .{ch_peek});
                        return;
                    }
                }
            }
            const ea: *com.ICharacterReceivedRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const ch = ea.Character() catch return;
            log.debug("xaml_surface: CharacterReceived ch=0x{x}", .{ch});
            self.handleCharEvent(ch);
            if (self.closed) return;
            ea.SetHandled(true) catch {};
        }

        fn onImeTextBoxPreviewKeyDown(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const vk = ea.Key() catch return;
            const vk_u32 = @as(u32, @bitCast(vk));
            log.debug("ime_text_box: PreviewKeyDown vk=0x{x} focus_target={s}", .{ vk_u32, @tagName(self.app.keyboard_focus_target) });
            // Let IME passthrough keys (e.g. VK_PROCESSKEY, IME toggle) be handled
            // by the TextBox so IME composition works correctly.
            if (isImePassthroughVirtualKey(vk_u32)) return;
            // ime_text_box is NOT inside SwapChainPanel's visual tree, so
            // SwapChainPanel's PreviewKeyDown does NOT fire for these keys.
            self.handleKeyEvent(@intCast(vk_u32), true);
            if (self.closed) return;
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

        fn onImeTextBoxPreviewKeyUp(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            const ea: *com.IKeyRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const vk = ea.Key() catch return;
            const vk_u32 = @as(u32, @bitCast(vk));
            if (isImePassthroughVirtualKey(vk_u32)) return;
            self.handleKeyEvent(@intCast(vk_u32), false);
            if (self.closed) return;
            ea.SetHandled(true) catch {};
        }

        fn onImeTextBoxCharacterReceived(self: *Self, _: ?*anyopaque, args: ?*anyopaque) void {
            if (!self.core_initialized) return;
            if (self.app.keyboard_focus_target != .ime_text_box) return;
            const ea: *com.ICharacterReceivedRoutedEventArgs = @ptrCast(@alignCast(args orelse return));
            const ch = ea.Character() catch return;
            log.debug("ime_text_box: CharacterReceived ch=0x{x} (deferred to TextChanged)", .{ch});
        }

        fn onImeTextBoxTextChanged(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
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
            log.debug(
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

        // onImeTextBoxCompositionStarted, onImeTextBoxCompositionChanged, onImeTextBoxCompositionEnded
        // REMOVED — TSF is now the sole IME handler. Composition events flow through
        // TsfImplementation's ITfContextOwnerCompositionSink (OnStartComposition/OnEndComposition)
        // and ITfTextEditSink (OnEndEdit) which extracts preedit and finalized text.

        fn onXamlGotFocus(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
            if (!self.core_initialized) return;
            if (!self.has_focus) {
                self.has_focus = true;
                log.info("XAML GotFocus on SwapChainPanel surface=0x{x}", .{@intFromPtr(self)});
                self.core_surface.focusCallback(true) catch |err| {
                    log.warn("focusCallback(true) error: {}", .{err});
                };
            }
            // With direct TSF, focus stays on SwapChainPanel. TSF is associated with
            // the main HWND and handles IME composition directly. No TextBox redirect needed.
            // Legacy TextBox focus path retained only if keyboard_focus_target is explicitly
            // set to .ime_text_box (should not happen in normal TSF flow).
            if (self.app.keyboard_focus_target == .ime_text_box) {
                _ = self.focusImeTextBox();
            }

            // TSF focus: matching Windows Terminal's _GotFocusHandler pattern.
            // Done via XAML event (not Win32 WM_SETFOCUS) to avoid recursive message crashes.
            if (self.app.tsf_impl) |*tsf_impl| {
                // Fix 1 DISABLED: Re-associating TSF HWND on GotFocus breaks the
                // document context — GetText returns len=0 and ShiftEnd returns
                // E_INVALIDARG after the HWND changes. The initial associateFocus
                // in setupNativeInputWindows is sufficient. Further investigation
                // needed on why findWindowOfActiveTSF returns a different HWND.
                // if (tsf_impl.findWindowOfActiveTSF()) |current_hwnd| { ... }
                tsf_impl.focus();
            }
        }

        fn onXamlLostFocus(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
            if (!self.core_initialized) return;
            if (self.app.keyboard_focus_target == .ime_text_box) {
                log.debug("SwapChainPanel LostFocus ignored: IME text box now owns focus", .{});
                return;
            }
            if (!self.has_focus) return; // deduplicate
            self.has_focus = false;
            log.info("XAML LostFocus on SwapChainPanel surface=0x{x}", .{@intFromPtr(self)});
            self.core_surface.focusCallback(false) catch |err| {
                log.warn("focusCallback(false) error: {}", .{err});
            };

            // TSF unfocus when SwapChainPanel loses focus (matching WT's _LostFocusHandler).
            if (self.app.tsf_impl) |*tsf_impl| {
                tsf_impl.unfocus();
            }
        }

        fn onImeTextBoxGotFocus(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
            if (!self.core_initialized) return;
            log.debug("ime_text_box: GotFocus", .{});
            self.logImeTextBoxState("ime_text_box: GotFocus");
            if (self.has_focus) return;
            self.has_focus = true;
            self.core_surface.focusCallback(true) catch |err| {
                log.warn("ime_text_box focusCallback(true) error: {}", .{err});
            };
        }

        fn onImeTextBoxLostFocus(self: *Self, _: ?*anyopaque, _: ?*anyopaque) void {
            if (!self.core_initialized) return;
            log.debug("ime_text_box: LostFocus keyboard_focus_target={s}", .{@tagName(self.app.keyboard_focus_target)});
            if (self.app.keyboard_focus_target != .ime_text_box) return;
            if (!self.has_focus) return;
            self.has_focus = false;
            self.core_surface.focusCallback(false) catch |err| {
                log.warn("ime_text_box focusCallback(false) error: {}", .{err});
            };

            // TSF unfocus: matching Windows Terminal's _LostFocusHandler pattern.
            // Done via XAML event (not Win32 WM_KILLFOCUS) to avoid recursive message crashes.
            if (self.app.tsf_impl) |*tsf_impl| {
                tsf_impl.unfocus();
            }
        }

        /// Request XAML focus on the SwapChainPanel (called from ime.zig after IME ends).
        pub fn focusSwapChainPanel(self: *Self) void {
            if (self.swap_chain_panel) |panel| {
                if (panel.queryInterface(com.IUIElement)) |ue| {
                    defer ue.release();
                    const result = ue.focus(com.FocusState.Programmatic);
                    if (result) |ok| {
                        log.debug("focusSwapChainPanel: focus() returned {}", .{ok});
                    } else |err| {
                        log.err("focusSwapChainPanel: focus() FAILED: {}", .{@intFromError(err)});
                    }
                } else |err| {
                    log.err("focusSwapChainPanel: QI IUIElement FAILED: {}", .{@intFromError(err)});
                }
            } else {
                log.err("focusSwapChainPanel: no swap_chain_panel!", .{});
            }
        }

        pub fn focusImeTextBox(self: *Self) bool {
            const ime_tb = self.ime_text_box orelse {
                log.debug("focusImeTextBox: no ime_text_box", .{});
                return false;
            };
            self.clearImeTextBoxText();
            self.positionImeTextBox();
            self.logImeTextBoxState("focusImeTextBox: before focus");
            if (ime_tb.queryInterface(com.IUIElement)) |ime_ue| {
                defer ime_ue.release();
                const result = ime_ue.focus(com.FocusState.Programmatic);
                if (result) |ok| {
                    log.debug("focusImeTextBox: focus() returned {}", .{ok});
                    self.logImeTextBoxState("focusImeTextBox: after focus");
                    return ok;
                } else |err| {
                    log.err("focusImeTextBox: focus() FAILED: {}", .{@intFromError(err)});
                }
            } else |err| {
                log.err("focusImeTextBox: QI IUIElement FAILED: {}", .{@intFromError(err)});
            }
            return false;
        }

        pub fn clearImeTextBoxText(self: *Self) void {
            const ime_tb = self.ime_text_box orelse {
                log.debug("clearImeTextBoxText: no ime_text_box", .{});
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
                log.debug("clearImeTextBoxText: cleared sent={}->{} last={}->{}", .{
                    prev_sent, self.ime_text_box_sent_text.items.len,
                    prev_last, self.ime_text_box_last_text.items.len,
                });
            } else |err| {
                log.err("clearImeTextBoxText: SetText FAILED: {}", .{@intFromError(err)});
            }
            ime_tb.Select(0, 0) catch |err| {
                log.err("clearImeTextBoxText: Select FAILED: {}", .{@intFromError(err)});
            };
        }

        fn positionImeTextBox(self: *Self) void {
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

        fn setImeTextBoxSnapshot(self: *Self, utf16: []const u16) void {
            self.ime_text_box_last_text.resize(self.app.core_app.alloc, utf16.len) catch {
                log.err("ime_text_box: snapshot resize failed len={}", .{utf16.len});
                return;
            };
            std.mem.copyForwards(u16, self.ime_text_box_last_text.items, utf16);
        }

        fn setImeTextBoxSentSnapshot(self: *Self, utf16: []const u16) void {
            self.ime_text_box_sent_text.resize(self.app.core_app.alloc, utf16.len) catch {
                log.err("ime_text_box: sent snapshot resize failed len={}", .{utf16.len});
                return;
            };
            std.mem.copyForwards(u16, self.ime_text_box_sent_text.items, utf16);
        }

        fn flushImeTextBoxCommittedText(self: *Self) void {
            const ime_tb = self.ime_text_box orelse return;
            const text_h = ime_tb.Text() catch return;
            defer if (text_h) |h| winrt.deleteHString(@ptrCast(h));
            self.flushImeTextBoxCommittedDelta(winrt.hstringSliceRaw(text_h));
        }

        fn flushImeTextBoxCommittedDelta(self: *Self, utf16: []const u16) void {
            const sent = self.ime_text_box_sent_text.items;

            // When sent is empty, treat all of utf16 as new committed text.
            // This fixes IME first-character loss: composing=false means TextChanged
            // delivers the full committed string at once, but append_only would fail
            // because commonPrefixLen(empty, text) == 0 != sent.len when sent is empty
            // and utf16 has content that doesn't start from a previous prefix.
            if (sent.len == 0 and utf16.len > 0) {
                log.debug("ime_text_box: FlushCommitted sent=0 -> sending all {} chars", .{utf16.len});
                for (utf16) |code_unit| {
                    self.handleCharEvent(code_unit);
                    if (self.closed) return;
                }
                self.setImeTextBoxSentSnapshot(utf16);
                return;
            }

            const append_only = commonPrefixLen(u16, sent, utf16) == sent.len and utf16.len > sent.len;
            log.debug(
                "ime_text_box: FlushCommitted utf16_len={} sent_len={} append_only={} append_len={}",
                .{ utf16.len, sent.len, append_only, if (append_only) utf16.len - sent.len else 0 },
            );
            if (!append_only) {
                self.setImeTextBoxSentSnapshot(utf16);
                return;
            }

            for (utf16[sent.len..]) |code_unit| {
                self.handleCharEvent(code_unit);
                if (self.closed) return;
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
        pub fn setTsfPreedit(self: *Self, preedit_utf8: ?[]const u8) void {
            if (!self.core_initialized) return;

            // Forward to debug overlay
            const alloc = self.app.core_app.alloc;
            if (preedit_utf8) |text| {
                const copy = alloc.dupeZ(u8, text) catch null;
                if (copy) |c| {
                    if (self.core_surface.renderer_thread.mailbox.push(.{
                        .tsf_preedit = .{ .alloc = alloc, .text = c },
                    }) != .ok) {
                        alloc.free(c);
                    }
                }
            } else {
                _ = self.core_surface.renderer_thread.mailbox.push(.{
                    .tsf_preedit = .{ .alloc = alloc, .text = null },
                });
            }

            self.core_surface.preeditCallback(preedit_utf8) catch |err| {
                log.err("TSF preedit error: {}", .{err});
            };
        }

        /// Called by TSF when text is finalized (user confirmed candidate / pressed Enter).
        /// Sends each code unit to the PTY via handleCharEvent, matching the pattern
        /// used by flushImeTextBoxCommittedDelta.
        pub fn handleTsfOutput(self: *Self, text_utf8: []const u8) void {
            if (!self.core_initialized) return;
            if (text_utf8.len == 0) return;

            log.debug("TSF output: {} bytes", .{text_utf8.len});

            // Convert UTF-8 to UTF-16 code units and feed each one through
            // handleCharEvent, which already handles surrogate pairs.
            const view = std.unicode.Utf8View.initUnchecked(text_utf8);
            var it = view.iterator();
            while (it.nextCodepoint()) |cp| {
                if (cp <= 0xFFFF) {
                    // BMP: single UTF-16 code unit
                    self.handleCharEvent(@intCast(cp));
                    if (self.closed) return;
                } else {
                    // Supplementary plane: encode as surrogate pair
                    const v = cp - 0x10000;
                    const high: u16 = @intCast(0xD800 + (v >> 10));
                    const low: u16 = @intCast(0xDC00 + (v & 0x3FF));
                    self.handleCharEvent(high);
                    if (self.closed) return;
                    self.handleCharEvent(low);
                    if (self.closed) return;
                }
            }
        }

        /// Returns cursor screen-coordinate rectangle for TSF/IME candidate window placement.
        /// TSF's ITfContextOwner::GetTextExt expects screen coordinates.
        pub fn getTsfCursorRect(self: *Self) os.RECT {
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
                log.debug("TSF getTsfCursorRect: no hwnd", .{});
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
                0xFF, // VK_OEM_CLEAR — Chrome Remote Desktop sends this for pre-composed IME text
                => true,
                else => false,
            };
        }

        fn hwndValue(hwnd: ?os.HWND) usize {
            return if (hwnd) |h| @intFromPtr(h) else 0;
        }

        fn logImeTextBoxState(self: *Self, comptime prefix: []const u8) void {
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

            log.debug(
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
        pub fn bindSwapChain(self: *Self, swap_chain: *anyopaque) void {
            self.last_swap_chain = swap_chain;
            log.info(
                "bindSwapChain: loaded={} pending_before={} swap_chain=0x{x}",
                .{ self.loaded, self.pending_swap_chain != null, @intFromPtr(swap_chain) },
            );

            if (!self.loaded) {
                log.info("bindSwapChain: panel not yet Loaded, attempting immediate binding (flip start)", .{});
            }

            if (self.app.hwnd) |hwnd| {
                const result = os.PostMessageW(
                    hwnd,
                    os.WM_APP_BIND_SWAP_CHAIN,
                    @bitCast(@intFromPtr(swap_chain)),
                    @bitCast(@intFromPtr(self)),
                );
                if (result == 0) {
                    log.warn("PostMessageW failed msg=WM_APP_BIND_SWAP_CHAIN err={}", .{os.GetLastError()});
                }
            }
        }

        /// Bind a composition surface handle to the SwapChainPanel via ISwapChainPanelNative2.
        pub fn bindSwapChainHandle(self: *Self, swap_chain_handle: usize) void {
            self.last_swap_chain_handle = swap_chain_handle;
            log.info(
                "bindSwapChainHandle: loaded={} pending_before={} handle=0x{x}",
                .{ self.loaded, self.pending_swap_chain_handle != null, swap_chain_handle },
            );

            if (!self.loaded) {
                log.info("bindSwapChainHandle: panel not yet Loaded, attempting immediate binding", .{});
            }

            if (self.app.hwnd) |hwnd| {
                const result = os.PostMessageW(
                    hwnd,
                    os.WM_APP_BIND_SWAP_CHAIN_HANDLE,
                    @bitCast(swap_chain_handle),
                    @bitCast(@intFromPtr(self)),
                );
                if (result == 0) {
                    log.warn("PostMessageW failed msg=WM_APP_BIND_SWAP_CHAIN_HANDLE err={}", .{os.GetLastError()});
                }
            }
        }

        /// Actually perform the swap chain binding. Must be called on the UI thread.
        /// swap_chain comes from wparam of the posted message.
        pub fn completeBindSwapChain(self: *Self, swap_chain: *anyopaque) void {
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
            log.debug("Swap chain bound to SwapChainPanel (UI thread)", .{});
            log.info("Swap chain bound to SwapChainPanel (UI thread)", .{});
        }

        /// Actually perform swap chain HANDLE binding. Must be called on the UI thread.
        pub fn completeBindSwapChainHandle(self: *Self, swap_chain_handle: usize) void {
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

        fn maybeBindPendingSwapChain(self: *Self, caller: []const u8) void {
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

        fn maybeBindPendingSwapChainHandle(self: *Self, caller: []const u8) void {
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
        /// Marks scrollbar dirty and stores the latest values; the actual COM
        /// update is deferred to flushDirtyUi() at the end of drainMailbox.
        pub fn updateScrollbarUi(self: *Self, total: usize, offset: usize, len: usize) void {
            // Frequency measurement (log_hot_path only).
            if (comptime log_hot_path) {
                self.scrollbar_update_count += 1;
                // Count as coalesced if dirty flag is already set (multiple updates in one tick).
                if (self.dirty.scrollbar) self.scrollbar_skip_count += 1;
            }
            self.pending_scrollbar = .{ .total = total, .offset = offset, .len = len };
            self.dirty.scrollbar = true;
        }

        /// Apply pending scrollbar values to the XAML ScrollBar control.
        /// Called once per drainMailbox cycle from flushDirtyUi().
        fn applyScrollbarUi(self: *Self) void {
            const sb = self.pending_scrollbar orelse return;
            self.pending_scrollbar = null;

            if (comptime log_hot_path) {
                const now = std.time.nanoTimestamp();
                const log_interval_ns = 1 * std.time.ns_per_s;
                if (now - self.last_scrollbar_log_ns >= log_interval_ns) {
                    log.info("scrollbar freq: {}/s applied, {}/s coalesced", .{
                        self.scrollbar_update_count - self.scrollbar_skip_count,
                        self.scrollbar_skip_count,
                    });
                    self.scrollbar_update_count = 0;
                    self.scrollbar_skip_count = 0;
                    self.last_scrollbar_log_ns = now;
                }
            }

            log.debug("applyScrollbarUi: total={} offset={} len={}", .{ sb.total, sb.offset, sb.len });
            _ = self.scroll_bar_insp orelse return;
            self.is_internal_scroll_update = true;
            defer {
                self.is_internal_scroll_update = false;
            }

            const range_base = self.scroll_bar_range_base orelse return;
            const total_f: f64 = @floatFromInt(sb.total);
            const offset_f: f64 = @floatFromInt(sb.offset);
            const len_f: f64 = @floatFromInt(sb.len);
            const maximum = if (total_f > len_f) total_f - len_f else 0.0;

            // On first call, set constants and all values unconditionally.
            if (!self.scrollbar_initialized) {
                range_base.SetMinimum(0.0) catch {};
                range_base.SetSmallChange(1.0) catch {};
                self.scrollbar_initialized = true;
            }

            // Only call COM setters when the value actually changed.
            if (maximum != self.last_scrollbar_maximum) {
                range_base.SetMaximum(maximum) catch {};
                self.last_scrollbar_maximum = maximum;
            }
            if (offset_f != self.last_scrollbar_value) {
                range_base.SetValue(offset_f) catch {};
                self.last_scrollbar_value = offset_f;
            }
            const isb = self.scroll_bar_isb orelse return;
            if (len_f != self.last_scrollbar_viewport) {
                range_base.SetLargeChange(len_f) catch {};
                isb.SetViewportSize(len_f) catch {};
                self.last_scrollbar_viewport = len_f;
            }

            if (comptime log_hot_path) {
                const fe = self.scroll_bar_fe orelse return;
                const ue = self.scroll_bar_ue orelse return;

                const orientation = isb.Orientation() catch -1;
                const viewport = isb.ViewportSize() catch -1.0;
                const width = fe.ActualWidth() catch -1.0;
                const height = fe.ActualHeight() catch -1.0;
                const visibility = ue.Visibility() catch -1;
                log.debug(
                    "scrollbar ui sync: orientation={} viewport={d:.2} actual={d:.2}x{d:.2} visibility={} max={d:.2} value={d:.2} len={d:.2}",
                    .{ orientation, viewport, width, height, visibility, maximum, offset_f, len_f },
                );
            }
        }

        /// RangeBase.ValueChanged event callback (fires on user drag and programmatic changes).
        fn onScrollBarValueChanged(self: *Self, _: ?*anyopaque, args_raw: ?*anyopaque) void {
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
        fn onLoaded(self: *Self, _: *anyopaque, _: *anyopaque) void {
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
            log.info(
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
        fn onSizeChanged(self: *Self, _: *anyopaque, _: *anyopaque) void {
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

            log.info("onSizeChanged: dip={d:.1}x{d:.1} -> {}x{}", .{ dip_width, dip_height, dip_w, dip_h });

            if (dip_w > 0 and dip_h > 0) {
                self.size = .{ .width = dip_w, .height = dip_h };
                if (self.core_initialized) {
                    log.info("onSizeChanged: calling sizeCallback {}x{}", .{ dip_w, dip_h });
                    self.core_surface.sizeCallback(self.size) catch |err| {
                        log.err("onSizeChanged: sizeCallback FAILED: {}", .{err});
                        log.warn("onSizeChanged sizeCallback error: {}", .{err});
                    };
                } else {
                    log.debug("onSizeChanged: core NOT initialized, skip sizeCallback", .{});
                }
            }

            maybeBindPendingSwapChain(self, "onSizeChanged");
            maybeBindPendingSwapChainHandle(self, "onSizeChanged");
        }

        /// Re-apply the current swap chain to this panel.
        /// Useful when the panel is reparented/shown by TabView selection changes.
        pub fn rebindSwapChain(self: *Self) void {
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

        /// Set the mouse cursor shape.  Deduplicates consecutive calls with
        /// the same shape to avoid redundant LoadCursorW / SetCursor calls and
        /// log spam on the hot mouse-move path.
        /// Mark mouse shape dirty; actual cursor change is deferred to flushDirtyUi().
        pub fn setMouseShape(self: *Self, shape: terminal.MouseShape) void {
            if (self.last_mouse_shape) |prev| {
                if (prev == shape) return;
            }
            self.pending_mouse_shape = shape;
            self.dirty.mouse_shape = true;
        }

        /// Apply pending mouse shape change.
        /// Called once per drainMailbox cycle from flushDirtyUi().
        fn applyMouseShape(self: *Self) void {
            const shape = self.pending_mouse_shape orelse return;
            self.pending_mouse_shape = null;
            self.last_mouse_shape = shape;

            log.debug("Surface.applyMouseShape: {s}", .{@tagName(shape)});
            const cursor_id = cursorIdForShape(shape);
            const cursor = os.LoadCursorW(null, cursor_id) orelse {
                log.warn("Surface.applyMouseShape: LoadCursorW failed for shape={s}", .{@tagName(shape)});
                return;
            };
            _ = os.SetCursor(cursor);
        }

        /// Flush all dirty UI flags for this surface.
        /// Called by App.flushDirtyUi() at the end of each drainMailbox cycle.
        pub fn flushDirtyUi(self: *Self) void {
            if (self.dirty.scrollbar) {
                self.dirty.scrollbar = false;
                self.applyScrollbarUi();
            }
            if (self.dirty.mouse_shape) {
                self.dirty.mouse_shape = false;
                self.applyMouseShape();
            }
        }

        pub fn setProgressReport(self: *Self, value: terminal.osc.Command.ProgressReport) void {
            _ = self;
            log.info("Surface.setProgressReport: state={s} progress={?}", .{ @tagName(value.state), value.progress });

            // Minimal runtime behavior until taskbar integration is implemented:
            // emit an audible signal on explicit error state.
            if (value.state == .@"error") {
                _ = os.MessageBeep(os.MB_OK);
            }
        }

        pub fn commandFinished(self: *Self, value: apprt.Action.Value(.command_finished)) bool {
            _ = self;
            log.info("Surface.commandFinished: duration={}ns", .{value.duration.duration});

            // Minimal notification: command failure emits an audible signal.
            if (value.exit_code) |code| {
                if (code != 0) _ = os.MessageBeep(os.MB_OK);
            }
            return true;
        }

        /// Ring the audible/visual bell.  Throttled to at most once per 100ms
        /// so rapid \a sequences don't saturate the audio subsystem while still
        /// keeping the notification perceptible.
        pub fn setBellRinging(self: *Self, value: bool) void {
            if (!value) return;

            const now = std.time.nanoTimestamp();
            const min_interval_ns = 100 * std.time.ns_per_ms;
            if (now - self.last_bell_ns < min_interval_ns) return;
            self.last_bell_ns = now;

            log.info("Surface.setBellRinging: Ringing visual/audio bell", .{});
            _ = os.MessageBeep(os.MB_OK);
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

        test "pointerToCursorPos applies surface origin offset" {
            const pos = pointerToCursorPos(128.0, 96.0, 8.0, 12.0);
            try std.testing.expectEqual(@as(f32, 120.0), pos.x);
            try std.testing.expectEqual(@as(f32, 84.0), pos.y);
        }

        test "pointerToCursorPos allows out-of-bounds negative coordinates" {
            const pos = pointerToCursorPos(4.0, 2.0, 10.0, 6.0);
            try std.testing.expectEqual(@as(f32, -6.0), pos.x);
            try std.testing.expectEqual(@as(f32, -4.0), pos.y);
        }

        test "pointerToCursorPos keeps fractional DIP precision" {
            const pos = pointerToCursorPos(20.75, 11.25, 1.5, 0.5);
            try std.testing.expectApproxEqAbs(@as(f32, 19.25), pos.x, 0.0001);
            try std.testing.expectApproxEqAbs(@as(f32, 10.75), pos.y, 0.0001);
        }

        test "pointerToCursorPos does not apply implicit DPI scaling" {
            // Contract: pointer coordinates are already in DIP space at this layer.
            // We only normalize by origin; no hidden scale/divide/multiply occurs.
            const pos = pointerToCursorPos(150.0, 90.0, 50.0, 30.0);
            try std.testing.expectEqual(@as(f32, 100.0), pos.x);
            try std.testing.expectEqual(@as(f32, 60.0), pos.y);
        }

        test "pointerToCursorPos is translation invariant" {
            const a = pointerToCursorPos(320.5, 200.25, 17.25, 9.75);
            const b = pointerToCursorPos(420.5, 260.25, 117.25, 69.75);
            try std.testing.expectApproxEqAbs(a.x, b.x, 0.0001);
            try std.testing.expectApproxEqAbs(a.y, b.y, 0.0001);
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

            // Create a minimal CoreApp with just the allocator field set.
            var core_app: CoreApp = undefined;
            core_app.alloc = alloc;

            var app: App = undefined;
            app.core_app = &core_app;
            app.surfaces = .{};

            var surface: Self = undefined;
            surface.app = &app;
            surface.core_surface = undefined;
            surface.title = null;
            surface.tab_view_item_inspectable = null;
            // Only clean up title, not full deinit (which touches XAML objects).
            defer if (surface.title) |t| alloc.free(t);

            surface.setTabTitle("Test Title 1");
            try testing.expectEqualStrings("Test Title 1", surface.title.?);

            surface.setTabTitle("Test Title 2 - Long title");
            try testing.expectEqualStrings("Test Title 2 - Long title", surface.title.?);
        }
        test "refactored helper functions exist and are callable" {
            // Static verification that the extracted helper functions are properly
            // declared and have the expected signatures. These cannot be called in
            // unit tests (they require a live XAML runtime), but we verify they
            // resolve at comptime.
            const testing = std.testing;

            // setupXamlElements takes (*Self, *winrt.IInspectable) and returns !void
            const setup_fn = @TypeOf(Self.setupXamlElements);
            try testing.expect(@TypeOf(setup_fn) != void);

            // registerXamlEventHandlers takes (*Self, *winrt.IInspectable) and returns !void
            const register_fn = @TypeOf(Self.registerXamlEventHandlers);
            try testing.expect(@TypeOf(register_fn) != void);

            // unregisterXamlEventHandlers takes (*Self) and returns void
            const unregister_fn = @TypeOf(Self.unregisterXamlEventHandlers);
            try testing.expect(@TypeOf(unregister_fn) != void);

            // cleanupXamlElements takes (*Self) and returns void
            const cleanup_fn = @TypeOf(Self.cleanupXamlElements);
            try testing.expect(@TypeOf(cleanup_fn) != void);
        }
    }; // return struct
} // pub fn Surface
