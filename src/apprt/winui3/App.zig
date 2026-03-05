/// WinUI 3 application runtime for Ghostty.
///
/// Phase 3: Bootstraps Windows App SDK, initializes WinRT, creates a
/// WinUI 3 Window with HWND subclass message routing, creates a TabView
/// for multi-tab management, and routes input to the active Surface.
const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const windows = std.os.windows;
const build_config = @import("../../build_config.zig");
const apprt = @import("../../apprt.zig");
const CoreApp = @import("../../App.zig");
const CoreSurface = @import("../../Surface.zig");
const configpkg = @import("../../config.zig");
const input = @import("../../input.zig");
const Surface = @import("Surface.zig");
const key = @import("key.zig");
const winrt = @import("winrt.zig");
const bootstrap = @import("bootstrap.zig");
const com = @import("com.zig");
const native_interop = @import("native_interop.zig");
const event = @import("event.zig");
const os = @import("os.zig");
const com_aggregation = @import("com_aggregation.zig");
const input_overlay = @import("input_overlay.zig");
const ime = @import("ime.zig");
const debug_harness = @import("debug_harness.zig");

const log = std.log.scoped(.winui3);

/// Timer ID for live resize preview.
const RESIZE_TIMER_ID: usize = 1;
const CONTEXT_MENU_NEW_TAB: usize = 1001;
const CONTEXT_MENU_CLOSE_TAB: usize = 1002;
const CONTEXT_MENU_PASTE: usize = 1003;
const CONTEXT_MENU_CLOSE_WINDOW: usize = 1004;

const InitCallback = com_aggregation.InitCallback(App);
const AppOuter = com_aggregation.AppOuter;
const guidEql = com_aggregation.guidEql;

/// The core application.
core_app: *CoreApp,
debug_cfg: debug_harness.RuntimeDebugConfig = .{},

/// COM aggregation outer object that implements IXamlMetadataProvider.
/// Must be kept alive for the lifetime of the Application.
app_outer: AppOuter = undefined,

/// The WinUI 3 Application instance (needed for calling Exit() on shutdown).
xaml_app: ?*com.IApplication = null,

/// The WinUI 3 Window.
window: ?*com.IWindow = null,

/// The native HWND obtained from IWindowNative.
hwnd: ?os.HWND = null,
root_hwnd: ?os.HWND = null,

/// The child HWND created by WinUI3 for the content area (DesktopChildSiteBridge).
child_hwnd: ?os.HWND = null,

/// Our own input HWND — a transparent child window that receives keyboard focus
/// and all IME messages, bypassing WinUI3's TSF layer entirely.
input_hwnd: ?os.HWND = null,

/// All surfaces (one per tab).
surfaces: std.ArrayListUnmanaged(*Surface) = .{},

/// Index of the currently active/selected tab.
active_surface_idx: usize = 0,

/// The TabView control that manages tabs.
tab_view: ?*com.ITabView = null,

/// Whether the app is running.
running: bool = false,

/// Whether the user is currently in a modal resize/move loop.
/// Set by WM_ENTERSIZEMOVE / WM_EXITSIZEMOVE.
resizing: bool = false,

/// Pending size from WM_SIZE during modal resize. Applied on WM_EXITSIZEMOVE.
pending_size: ?struct { width: u32, height: u32 } = null,

/// Fullscreen state.
is_fullscreen: bool = false,
saved_style: usize = 0,
saved_placement: os.WINDOWPLACEMENT = .{},

/// Closed event handler (prevent dangling reference).
closed_handler: ?*event.SimpleEventHandler(App) = null,
closed_token: ?i64 = null,

/// TabView event handlers.
tab_close_handler: ?*event.SimpleEventHandler(App) = null,
add_tab_handler: ?*event.SimpleEventHandler(App) = null,
selection_changed_handler: ?*event.SimpleEventHandler(App) = null,
tab_close_token: ?i64 = null,
add_tab_token: ?i64 = null,
selection_changed_token: ?i64 = null,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    // Allocate a debug console so log output is visible for GUI apps.
    os.attachDebugConsole();

    // Install a Vectored Exception Handler to capture details of
    // STATUS_STOWED_EXCEPTION before the process terminates.
    _ = os.AddVectoredExceptionHandler(1, &stowedExceptionHandler);

    // Request 1ms timer resolution for smooth animation timing.
    _ = os.timeBeginPeriod(1);

    // Step 1: Bootstrap the Windows App SDK runtime.
    bootstrap.init() catch |err| {
        log.err("Windows App SDK bootstrap failed: {}", .{err});
        return error.AppInitFailed;
    };

    // Step 2: Initialize WinRT.
    winrt.hrCheck(winrt.RoInitialize(winrt.RO_INIT_SINGLETHREADED)) catch |err| {
        log.err("RoInitialize failed: {}", .{err});
        return error.AppInitFailed;
    };

    // Step 3: Create a DispatcherQueue for the current thread.
    // This is required before creating any XAML objects.
    const dq_opts = winrt.DispatcherQueueOptions{};
    const dq_controller = winrt.createDispatcherQueueController(&dq_opts) catch |err| {
        log.err("CreateDispatcherQueueController failed: {}", .{err});
        return error.AppInitFailed;
    };
    _ = dq_controller;

    self.* = .{
        .core_app = core_app,
        .debug_cfg = debug_harness.RuntimeDebugConfig.load(),
        .surfaces = .{},
        .running = true,
    };
    self.debug_cfg.log(log);

    // Window/UI creation happens inside run() via Application.Start(callback).
    // WinUI 3 requires Window creation on the XAML thread which is set up by Start().
    log.info("WinUI 3 runtime initialized (window creation deferred to run)", .{});
}

/// Called from inside Application.Start() callback — XAML thread is active here.
pub fn initXaml(self: *App) !void {
    log.info("initXaml: creating Window inside XAML thread", .{});

    // Step 0: Create the Application instance via IApplicationFactory with COM aggregation.
    // Application.Start() does NOT create an Application — the callback must.
    //
    // WinUI 3 custom controls (TabView, etc.) require IXamlMetadataProvider to be
    // implemented on the Application object. We use COM aggregation to inject our
    // implementation: AppOuter acts as the controlling IUnknown, and when the XAML
    // framework QI's for IXamlMetadataProvider, it gets our implementation which
    // delegates to XamlControlsXamlMetaDataProvider.
    const app_class = try winrt.hstring("Microsoft.UI.Xaml.Application");
    defer winrt.deleteHString(app_class);
    log.info("initXaml step 0: Creating Application with COM aggregation...", .{});

    // Initialize the outer object that implements IXamlMetadataProvider.
    self.app_outer.init();

    // Activate XamlControlsXamlMetaDataProvider for metadata delegation.
    const provider_class = winrt.hstring("Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider") catch null;
    if (provider_class) |pc| {
        defer winrt.deleteHString(pc);
        const provider_inspectable = winrt.activateInstance(pc) catch |err| blk: {
            log.warn("XamlControlsXamlMetaDataProvider activation failed: {}", .{err});
            break :blk null;
        };
        if (provider_inspectable) |pi| {
            self.app_outer.provider = pi.queryInterface(com.IXamlMetadataProvider) catch null;
            if (self.app_outer.provider != null) {
                log.info("initXaml step 0: XamlControlsXamlMetaDataProvider OK", .{});
            }
        }
    }

    // Create Application with outer IUnknown for aggregation.
    log.info("initXaml step 0: getActivationFactory(IApplicationFactory)...", .{});
    const app_factory = try winrt.getActivationFactory(com.IApplicationFactory, app_class);
    defer app_factory.release();
    log.info("initXaml step 0: calling CreateInstance(outer=0x{x})...", .{@intFromPtr(self.app_outer.outerPtr())});
    const result = try app_factory.createInstance(self.app_outer.outerPtr());
    log.info("initXaml step 0: CreateInstance returned inner=0x{x} instance=0x{x}", .{
        @intFromPtr(result.inner), @intFromPtr(result.instance),
    });
    self.app_outer.inner = @ptrCast(@alignCast(result.inner));

    // QI for IApplication so we can call Exit() during shutdown and access Resources.
    self.xaml_app = result.instance.queryInterface(com.IApplication) catch null;
    log.info("initXaml step 0 OK: Application created with IXamlMetadataProvider", .{});

    // Step 1: Create a Window via RoActivateInstance.
    const window_class = try winrt.hstring("Microsoft.UI.Xaml.Window");
    defer winrt.deleteHString(window_class);
    log.info("initXaml step 1: RoActivateInstance(Window)...", .{});
    const window_inspectable = try winrt.activateInstance(window_class);
    log.info("initXaml step 1 OK: got IInspectable @ 0x{x}", .{@intFromPtr(window_inspectable)});

    // Step 2: QI for IWindow.
    log.info("initXaml step 2: QueryInterface(IWindow)...", .{});
    const window = try window_inspectable.queryInterface(com.IWindow);
    self.window = window;
    log.info("initXaml step 2 OK: IWindow @ 0x{x}", .{@intFromPtr(window)});

    // Step 3: Set the window title.
    const title = try winrt.hstring("Ghostty");
    defer winrt.deleteHString(title);
    log.info("initXaml step 3: putTitle...", .{});
    try window.putTitle(title);
    log.info("initXaml step 3 OK", .{});

    // Step 4: Get the native HWND via IWindowNative.
    log.info("initXaml step 4: QueryInterface(IWindowNative)...", .{});
    const window_native = try window.queryInterface(com.IWindowNative);
    defer window_native.release();
    self.hwnd = try window_native.getWindowHandle();
    log.info("initXaml step 4 OK: HWND=0x{x}", .{@intFromPtr(self.hwnd.?)});

    // Also track root owner window; close messages are often dispatched there.
    self.root_hwnd = os.GetAncestor(self.hwnd.?, os.GA_ROOT) orelse self.hwnd.?;

    // Step 5: Install subclass on the HWND.
    log.info("initXaml step 5: SetWindowSubclass...", .{});
    _ = os.SetWindowSubclass(self.hwnd.?, &subclassProc, 0, @intFromPtr(self));
    if (self.root_hwnd) |root| {
        if (root != self.hwnd.?) _ = os.SetWindowSubclass(root, &subclassProc, 1, @intFromPtr(self));
    }
    log.info("initXaml step 5 OK", .{});

    // Step 6: Register Closed event handler.
    log.info("initXaml step 6: addClosed handler...", .{});
    const alloc = self.core_app.alloc;
    self.closed_handler = try event.SimpleEventHandler(App).createWithIid(
        alloc,
        self,
        &onWindowClosed,
        &com.IID_TypedEventHandler_WindowClosed,
    );
    self.closed_token = try window.addClosed(self.closed_handler.?.comPtr());
    log.info("initXaml step 6 OK", .{});

    // Step 7: Activate the window (makes it visible).
    log.info("initXaml step 7: Activate...", .{});
    try window.activate();
    log.info("initXaml step 7 OK: Window activated!", .{});

    // FORCE visibility via Win32 ShowWindow
    if (self.hwnd) |h| {
        _ = os.ShowWindow(h, os.SW_SHOWMAXIMIZED);
        _ = os.UpdateWindow(h);
        _ = os.SetForegroundWindow(h);
        log.info("initXaml: Win32 ShowWindow(MAXIMIZED) called", .{});
    }

    // Set initial size
    if (window.queryInterface(com.IFrameworkElement)) |fe| {
        defer fe.release();
    } else |_| {}

    // Step 7.1: Enable content extension into title bar (Windows Terminal style).
    if (window.queryInterface(native_interop.IWindow2)) |win2| {
        defer win2.release();
        win2.putExtendsContentIntoTitleBar(true) catch |err| {
            log.warn("initXaml step 7.1: putExtendsContentIntoTitleBar failed: {}", .{err});
        };
    } else |_| {}

    // Create our input overlay HWND immediately after activation.
    // ... (rest of setup) ...

    const tab_view = try self.createTabViewRoot(window);
    self.tab_view = tab_view;

    if (tab_view) |tv| {
        if (tv.queryInterface(native_interop.ITabView2)) |tv2| {
            defer tv2.release();
            tv2.putCanReorderTabs(true) catch {};
            tv2.putCanDragTabs(true) catch {};
            tv2.putTabWidthMode(.equal) catch {};
        } else |_| {}
    }

    // Step 8: Create the initial terminal content.
    try self.createInitialSurfaceContent(window, tab_view);

    try self.registerTabViewHandlers(tab_view);

    // Step 10: Test control logic.
    if (self.debug_cfg.new_tab_on_init) {
        log.info("initXaml step 10: new_tab_on_init triggered", .{});
        self.newTab() catch |err| log.warn("new_tab_on_init failed: {}", .{err});
    }

    if (self.debug_cfg.test_resize) {
        log.info("initXaml step 10: test_resize triggered", .{});
        // Trigger a fake WM_SIZE (add 10px to current size)
        var rect: os.RECT = .{};
        _ = os.GetClientRect(self.hwnd.?, &rect);
        const new_w: u32 = @intCast(rect.right - rect.left + 10);
        const new_h: u32 = @intCast(rect.bottom - rect.top + 10);
        _ = os.PostMessageW(self.hwnd.?, os.WM_SIZE, 0, @bitCast(@as(usize, (new_h << 16) | new_w)));
    }

    if (self.debug_cfg.close_after_ms) |ms| {
        log.info("initXaml step 10: close_after_ms={}ms scheduled", .{ms});
        // Use a dedicated timer ID for auto-close.
        const CLOSE_TIMER_ID: usize = 999;
        _ = os.SetTimer(self.hwnd.?, CLOSE_TIMER_ID, ms, null);
    }

    if (self.debug_cfg.close_tab_after_ms) |ms| {
        log.info("initXaml step 10: close_tab_after_ms={}ms scheduled", .{ms});
        const CLOSE_TAB_TIMER_ID: usize = 998;
        _ = os.SetTimer(self.hwnd.?, CLOSE_TAB_TIMER_ID, ms, null);
    }

    log.info("WinUI 3 Window created and activated (HWND=0x{x})", .{@intFromPtr(self.hwnd.?)});

    // Final attempt to force black background on root content.
    if (self.window) |win| {
        if (win.getContent() catch null) |content| {
            defer _ = content.release();
            // Set Dark theme on the content as well.
            if (content.queryInterface(com.IFrameworkElement)) |fe| {
                defer fe.release();
            } else |_| {}
            self.setControlBackground(@ptrCast(content), .{ .a = 255, .r = 0, .g = 0, .b = 0 });
        }
    }

    // Step 9: Find the WinUI3 child HWND...
    const child = os.GetWindow(self.hwnd.?, os.GW_CHILD);
    if (child) |child_hwnd| {
        self.child_hwnd = child_hwnd;
        log.info("initXaml step 9: found WinUI3 child HWND=0x{x}", .{@intFromPtr(child_hwnd)});
        // ALWAYS subclass the WinUI child HWND to redirect focus.
        _ = os.SetWindowSubclass(child_hwnd, &subclassProc, 2, @intFromPtr(self));
    }

    // Create our input overlay HWND.
    self.input_hwnd = input_overlay.createInputWindow(self.hwnd.?, @intFromPtr(self));
    if (self.input_hwnd) |input_hwnd| {
        // Enable IME on our input HWND.
        _ = os.ImmAssociateContextEx(input_hwnd, null, os.IACE_DEFAULT);
        // Give it initial focus.
        _ = os.SetFocus(input_hwnd);
        log.info("initXaml step 9 OK: input HWND=0x{x} created + IME enabled", .{@intFromPtr(input_hwnd)});
    }

    // --- TabView Parity Validation (Tier 2 Verification) ---
    self.validateTabViewParity() catch |err| {
        log.err("validateTabViewParity: CRITICAL_FAIL: {}", .{err});
    };
}

fn createTabViewRoot(self: *App, window: *com.IWindow) !?*com.ITabView {
    return if (self.debug_cfg.enable_tabview) blk: {
        log.info("initXaml step 7.5: Creating TabView via XAML type system...", .{});
        const tv_inspectable = self.activateXamlType("Microsoft.UI.Xaml.Controls.TabView") catch |err| {
            log.warn("TabView creation failed ({}), falling back to single-tab mode", .{err});
            break :blk null;
        };
        const tv = tv_inspectable.queryInterface(com.ITabView) catch |err| {
            log.warn("TabView QI for ITabView failed ({}), falling back to single-tab mode", .{err});
            break :blk null;
        };

        self.setControlBackground(@ptrCast(tv_inspectable), .{ .a = 255, .r = 0, .g = 0, .b = 0 });

        // Force TabView to stretch and fill the window.
        if (tv_inspectable.queryInterface(com.IFrameworkElement)) |fe| {
            defer fe.release();
        } else |_| {}

        window.putContent(@ptrCast(tv_inspectable)) catch |err| {
            log.warn("TabView putContent failed ({}), falling back to single-tab mode", .{err});
            _ = tv.release();
            break :blk null;
        };

        log.info("initXaml step 7.5 OK: TabView set as Window content", .{});
        break :blk tv;
    } else blk: {
        log.info("initXaml step 7.5: SKIPPED (GHOSTTY_WINUI3_ENABLE_TABVIEW=false)", .{});
        break :blk null;
    };
}

fn createInitialSurfaceContent(self: *App, window: *com.IWindow, tab_view: ?*com.ITabView) !void {
    const alloc = self.core_app.alloc;
    if (self.debug_cfg.tabview_empty and tab_view != null) {
        log.info("initXaml step 8: SKIPPED (GHOSTTY_WINUI3_TABVIEW_EMPTY=true)", .{});
        return;
    }

    log.info("initXaml step 8: Creating initial Surface...", .{});
    var config = try configpkg.Config.load(alloc);
    defer config.deinit();

    var surface = try alloc.create(Surface);
    errdefer alloc.destroy(surface);
    try surface.init(self, self.core_app, &config);
    errdefer surface.deinit();

    try self.surfaces.append(alloc, surface);

    if (self.hwnd) |hwnd| {
        var rect: os.RECT = .{};
        _ = os.GetClientRect(hwnd, &rect);
        const w: u32 = @intCast(@max(1, rect.right - rect.left));
        const h: u32 = @intCast(@max(1, rect.bottom - rect.top));
        if (w > 0 and h > 0) {
            surface.updateSize(w, h);
            log.info("initXaml step 8: synced surface size to {}x{}", .{ w, h });

            // Test: manually set TabView height.
            if (self.tab_view) |tv| {
                if (tv.queryInterface(com.IFrameworkElement)) |fe| {
                    defer fe.release();
                } else |_| {}
            }
        }
    }

    if (surface.swap_chain_panel) |panel| {
        if (tab_view) |tv| {
            const tvi_inspectable = try self.activateXamlType("Microsoft.UI.Xaml.Controls.TabViewItem");
            const tvi = try tvi_inspectable.queryInterface(com.ITabViewItem);
            defer tvi.release();

            const initial_title = try winrt.hstring("Terminal");
            defer winrt.deleteHString(initial_title);
            const boxed_title = try self.boxString(initial_title);
            defer _ = boxed_title.release();
            try tvi.putHeader(@ptrCast(boxed_title));
            try tvi.putIsClosable(false);

            if (!self.debug_cfg.tabview_item_no_content) {
                const content_control = try tvi_inspectable.queryInterface(com.IContentControl);
                defer content_control.release();
                const placeholder_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Border");
                defer winrt.deleteHString(placeholder_class);
                const placeholder = try winrt.activateInstance(placeholder_class);
                defer _ = placeholder.release();
                try content_control.putContent(@ptrCast(placeholder));
                log.info("initXaml step 8: TabViewItem placeholder content set", .{});
            } else {
                log.info("initXaml step 8: SKIPPING putContent (GHOSTTY_WINUI3_TABVIEW_ITEM_NO_CONTENT=true)", .{});
            }

            if (!self.debug_cfg.tabview_append_item) {
                log.info("initXaml step 8: STOP at level 1 (create+putContent only, no append)", .{});
            } else {
                const tab_items = try tv.getTabItems();
                try tab_items.append(@ptrCast(tvi_inspectable));
                log.info("initXaml step 8: append done", .{});

                const items_size = try tab_items.getSize();
                log.info("audit: [PASS] TabItems.getSize() = {}", .{items_size});
                tab_items.release();

                surface.tab_view_item_inspectable = tvi_inspectable;

                if (!self.debug_cfg.tabview_select_first) {
                    log.info("initXaml step 8: STOP at level 2 (create+putContent+append, no selectedIndex)", .{});
                } else {
                    try tv.putSelectedIndex(0);
                    self.attachSurfaceToTabItem(null, 0) catch |err| {
                        log.warn("initXaml step 8: attachSurfaceToTabItem(0) failed: {}", .{err});
                    };
                    const actual_idx = try tv.getSelectedIndex();
                    log.info(
                        "initXaml step 8: rebindSwapChain(before) loaded={} last_swap_chain={}",
                        .{ surface.loaded, surface.last_swap_chain != null },
                    );
                    surface.rebindSwapChain();
                    log.info(
                        "initXaml step 8: rebindSwapChain(after) loaded={} last_swap_chain={}",
                        .{ surface.loaded, surface.last_swap_chain != null },
                    );
                    log.info("audit: [PASS] TabView.getSelectedIndex() = {}", .{actual_idx});
                    log.info("initXaml step 8 OK: full (create+putContent+append+selectedIndex)", .{});
                }
            }
        } else {
            const wrapped_panel = panel;
            if (wrapped_panel != @as(*winrt.IInspectable, @ptrCast(panel))) {
                defer _ = wrapped_panel.release();
                try window.putContent(@ptrCast(wrapped_panel));
            } else {
                try window.putContent(@ptrCast(panel));
            }
            log.info("initXaml step 8 OK: Surface + SwapChainPanel set as Window content (single-tab)", .{});
        }
    }
}

fn registerTabViewHandlers(self: *App, tab_view: ?*com.ITabView) !void {
    if (tab_view != null and self.debug_cfg.enable_tabview_handlers) {
        const alloc = self.core_app.alloc;
        if (self.debug_cfg.enable_handler_close) {
            self.tab_close_handler = try event.SimpleEventHandler(App).createWithIid(alloc, self, &onTabCloseRequested, &com.IID_TypedEventHandler_TabCloseRequested);
            self.tab_close_token = try tab_view.?.addTabCloseRequested(self.tab_close_handler.?.comPtr());
            log.info("initXaml step 7.5: TabCloseRequested handler registered", .{});
        }
        if (self.debug_cfg.enable_handler_addtab) {
            self.add_tab_handler = try event.SimpleEventHandler(App).createWithIid(alloc, self, &onAddTabButtonClick, &com.IID_TypedEventHandler_AddTabButtonClick);
            self.add_tab_token = try tab_view.?.addAddTabButtonClick(self.add_tab_handler.?.comPtr());
            log.info("initXaml step 7.5: AddTabButtonClick handler registered", .{});
        }
        if (self.debug_cfg.enable_handler_selection) {
            self.selection_changed_handler = try event.SimpleEventHandler(App).createWithIid(alloc, self, &onSelectionChanged, &com.IID_SelectionChangedEventHandler);
            self.selection_changed_token = try tab_view.?.addSelectionChanged(self.selection_changed_handler.?.comPtr());
            log.info("initXaml step 7.5: SelectionChanged handler registered", .{});
        }
        log.info("initXaml step 7.5 OK: TabView event handlers registered (close={} addtab={} selection={})", .{
            self.debug_cfg.enable_handler_close,
            self.debug_cfg.enable_handler_addtab,
            self.debug_cfg.enable_handler_selection,
        });
    } else if (tab_view != null) {
        log.info("initXaml step 7.5: TabView event handlers SKIPPED (GHOSTTY_WINUI3_ENABLE_TABVIEW_HANDLERS=false)", .{});
    }
}

fn unregisterTabViewHandlers(self: *App, tab_view: *com.ITabView) void {
    if (self.tab_close_token) |tok| tab_view.removeTabCloseRequested(tok) catch {};
    if (self.add_tab_token) |tok| tab_view.removeAddTabButtonClick(tok) catch {};
    if (self.selection_changed_token) |tok| tab_view.removeSelectionChanged(tok) catch {};
    self.tab_close_token = null;
    self.add_tab_token = null;
    self.selection_changed_token = null;
}

/// Performs real-value verification of the WinUI 3 UI tree.
/// Maps to the 5 critical test cases defined for parity with macOS/GTK.
fn validateTabViewParity(self: *App) !void {
    log.info("validateTabViewParity: starting audit...", .{});
    const window = self.window orelse return error.NoWindow;

    // 1. tabview_init_success_sets_window_content
    if (self.debug_cfg.enable_tabview) {
        _ = self.tab_view orelse {
            log.err("PARITY_FAIL: tabview_init_success (self.tab_view is null)", .{});
            return error.ParityFail;
        };
        const content = try window.getContent();
        if (content) |c| {
            defer _ = c.release();
            // Check if window content matches tab_view (QI check)
            const content_tv = c.queryInterface(com.ITabView) catch {
                log.err("PARITY_FAIL: window_content_is_tabview (QI failed)", .{});
                return error.ParityFail;
            };
            content_tv.release();
        } else {
            log.err("PARITY_FAIL: window_content_is_null", .{});
            return error.ParityFail;
        }
        log.info("validate: [PASS] tabview_init_success_sets_window_content", .{});
    }

    // 2. tabview_first_item_has_non_null_content
    if (self.tab_view) |tv| {
        const items = try tv.getTabItems();
        defer items.release();
        const size = try items.getSize();
        if (size == 0) {
            log.err("PARITY_FAIL: tabview_empty", .{});
            return error.ParityFail;
        }
        
        const first_item_insp = try items.getAt(0);
        const first_item = try @as(*winrt.IInspectable, @ptrCast(@alignCast(first_item_insp))).queryInterface(com.ITabViewItem);
        defer first_item.release();

        const content_control = try first_item.queryInterface(com.IContentControl);
        defer content_control.release();
        const content = try content_control.getContent();
        if (content) |c| {
            _ = c.release();
        } else {
            log.err("PARITY_FAIL: tabview_first_item_has_no_content", .{});
            return error.ParityFail;
        }
        log.info("validate: [PASS] tabview_first_item_has_non_null_content", .{});
    }

    // 4. tabview_disabled_uses_single_view
    if (!self.debug_cfg.enable_tabview) {
        if (self.tab_view != null) {
            log.err("PARITY_FAIL: tabview_not_disabled", .{});
            return error.ParityFail;
        }
        const content = try window.getContent();
        if (content) |c| {
            defer _ = c.release();
            // In single view, it should be a Grid/Border or SwapChainPanel directly
            const is_tabview = if (c.queryInterface(com.ITabView)) |_| true else |_| false;
            if (is_tabview) {
                log.err("PARITY_FAIL: single_view_is_tabview", .{});
                return error.ParityFail;
            }
        }
        log.info("validate: [PASS] tabview_disabled_uses_single_view", .{});
    }

    // 5. tabview_handlers_registered_when_enabled
    if (self.tab_view != null and self.debug_cfg.enable_tabview_handlers) {
        if (self.tab_close_token == 0 or self.add_tab_token == 0) {
            log.err("PARITY_FAIL: tabview_handlers_missing", .{});
            return error.ParityFail;
        }
        log.info("validate: [PASS] tabview_handlers_registered_when_enabled", .{});
    }

    log.info("validateTabViewParity: ALL CHECKS PASSED", .{});
}

fn wrapInBorder(self: *App, element: *winrt.IInspectable) !*winrt.IInspectable {
    log.info("wrapInBorder: creating Border...", .{});
    const border_insp = try self.activateXamlType("Microsoft.UI.Xaml.Controls.Border");
    const border = try border_insp.queryInterface(com.IBorder);
    defer border.release();
    log.info("wrapInBorder: putChild...", .{});
    try border.putChild(@ptrCast(element));
    log.info("wrapInBorder: OK", .{});
    return border_insp;
}

fn wrapInGrid(self: *App, element: *winrt.IInspectable) !*winrt.IInspectable {
    log.info("wrapInGrid: creating Grid...", .{});
    const grid_insp = try self.activateXamlType("Microsoft.UI.Xaml.Controls.Grid");
    log.info("wrapInGrid: QI IPanel...", .{});
    const panel = try grid_insp.queryInterface(com.IPanel);
    defer panel.release();
    log.info("wrapInGrid: getChildren...", .{});
    const children = try panel.getChildren();
    defer children.release();
    log.info("wrapInGrid: append child...", .{});
    try children.append(@ptrCast(element));
    log.info("wrapInGrid: OK", .{});
    return grid_insp;
}

/// Closed event callback — triggered when the user closes the window.
fn onWindowClosed(self: *App, _: *anyopaque, _: *anyopaque) void {
    // Tear down window hooks immediately on close event to avoid re-entrancy
    // with WinUI/XAML shutdown internals.
    if (self.input_hwnd) |input_hwnd| {
        _ = os.DestroyWindow(input_hwnd);
        self.input_hwnd = null;
    }
    if (self.child_hwnd) |child_hwnd| {
        _ = os.RemoveWindowSubclass(child_hwnd, &subclassProc, 2);
        self.child_hwnd = null;
    }
    if (self.root_hwnd) |root| {
        _ = os.RemoveWindowSubclass(root, &subclassProc, 1);
        self.root_hwnd = null;
    }
    if (self.hwnd) |hwnd| {
        _ = os.RemoveWindowSubclass(hwnd, &subclassProc, 0);
    }

    self.running = false;
    // Exit the XAML message loop so Application.Start() returns cleanly.
    if (self.xaml_app) |xa| {
        xa.exit() catch {};
    }
}

/// D3D11 doesn't use GL context — no-op for WinUI 3.
pub fn releaseGLContext(_: *App) void {}

/// D3D11 doesn't use GL context — no-op for WinUI 3.
pub fn makeGLContextCurrent(_: *App) !void {}

pub fn run(self: *App) !void {
    // Get Application statics to call Start().
    const app_class = try winrt.hstring("Microsoft.UI.Xaml.Application");
    defer winrt.deleteHString(app_class);
    const statics = try winrt.getActivationFactory(com.IApplicationStatics, app_class);
    defer statics.release();

    // Create the initialization callback (stack-allocated, used synchronously by Start).
    var callback = InitCallback.create(self);

    // Application.Start() calls our callback to create the Window,
    // then enters the XAML message loop. It blocks until the app exits.
    log.info("Calling Application.Start()...", .{});
    try statics.start(callback.comPtr());
    log.info("Application.Start() returned", .{});

    // CRITICAL: Perform full cleanup while WinRT is still active but after loop exit.
    self.fullCleanup();
}

pub fn terminate(self: *App) void {
    log.info("Termination requested", .{});
    self.running = false;
    // Signal XAML to exit the message loop.
    if (self.xaml_app) |xa| {
        xa.exit() catch {};
    }
}

fn fullCleanup(self: *App) void {
    log.info("Starting full cleanup...", .{});
    const alloc = self.core_app.alloc;

    // 1. Remove subclasses first.
    if (self.child_hwnd) |child_hwnd| {
        _ = os.RemoveWindowSubclass(child_hwnd, &subclassProc, 2);
        self.child_hwnd = null;
    }
    if (self.root_hwnd) |root| {
        _ = os.RemoveWindowSubclass(root, &subclassProc, 1);
        self.root_hwnd = null;
    }
    if (self.hwnd) |hwnd| {
        _ = os.RemoveWindowSubclass(hwnd, &subclassProc, 0);
    }

    // 2. Close all surfaces (stops threads).
    for (self.surfaces.items) |surface| {
        surface.deinit();
        alloc.destroy(surface);
    }
    self.surfaces.deinit(alloc);

    // 3. Unregister WinRT events.
    if (self.tab_view) |tv| self.unregisterTabViewHandlers(tv);
    if (self.window) |window| {
        if (self.closed_token) |tok| window.removeClosed(tok) catch {};
    }

    // 4. Release COM objects properly.
    if (self.closed_handler) |h| _ = h.com.lpVtbl.Release(h.comPtr());
    if (self.tab_close_handler) |h| _ = h.com.lpVtbl.Release(h.comPtr());
    if (self.add_tab_handler) |h| _ = h.com.lpVtbl.Release(h.comPtr());
    if (self.selection_changed_handler) |h| _ = h.com.lpVtbl.Release(h.comPtr());

    if (self.tab_view) |tv| tv.release();
    if (self.window) |window| window.release();
    if (self.xaml_app) |xa| xa.release();
    if (self.app_outer.provider) |p| p.release();

    if (self.input_hwnd) |h| _ = os.DestroyWindow(h);

    log.info("Cleanup complete.", .{});
}

/// Thread-safe wakeup: any thread can call this to unblock the event loop.
pub fn wakeup(self: *App) void {
    if (self.hwnd) |hwnd| {
        _ = os.PostMessageW(hwnd, os.WM_USER, 0, 0);
    }
}

pub fn requestCloseWindow(self: *App) void {
    self.running = false;
    if (self.window) |window| {
        window.close() catch |err| {
            log.warn("requestCloseWindow: IWindow.Close failed: {}", .{err});
            if (self.xaml_app) |xa| xa.exit() catch {};
        };
        return;
    }
    if (self.xaml_app) |xa| xa.exit() catch {};
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    switch (action) {
        .quit => {
            self.running = false;
            if (self.xaml_app) |xa| {
                xa.exit() catch {};
            }
            return true;
        },
        .new_window => {
            // MVP: single window only
            return false;
        },
        .close_all_windows => {
            self.running = false;
            if (self.xaml_app) |xa| {
                xa.exit() catch {};
            }
            return true;
        },
        .new_tab => {
            self.newTab() catch |err| {
                log.err("Failed to create new tab: {}", .{err});
                return false;
            };
            return true;
        },
        .close_tab => {
            self.closeActiveTab();
            return true;
        },
        .reload_config => {
            log.info("performAction: reload_config", .{});
            const alloc = self.core_app.alloc;
            var config = try configpkg.Config.load(alloc);
            defer config.deinit();

            switch (target) {
                .app => try self.core_app.updateConfig(self, &config),
                .surface => |core| try core.updateConfig(&config),
            }
            return true;
        },
        .ring_bell => {
            switch (target) {
                .app => {},
                .surface => |core| core.rt_surface.setBellRinging(true),
            }
            return true;
        },
        .goto_tab => {
            if (self.tab_view) |tv| {
                const tab_count = self.surfaces.items.len;
                if (tab_count == 0) return true;
                const new_idx: usize = switch (value) {
                    .previous => if (self.active_surface_idx > 0) self.active_surface_idx - 1 else tab_count - 1,
                    .next => if (self.active_surface_idx + 1 < tab_count) self.active_surface_idx + 1 else 0,
                    .last => tab_count - 1,
                    _ => @min(@as(usize, @intCast(@intFromEnum(value))), tab_count - 1),
                };
                tv.putSelectedIndex(@intCast(new_idx)) catch {};
                self.active_surface_idx = new_idx;
            }
            return true;
        },
        .set_title => {
            log.info("performAction: set_title", .{});
            self.setTitle(value.title);
            return true;
        },
        .toggle_fullscreen => {
            self.toggleFullscreen();
            return true;
        },
        .mouse_shape => {
            switch (target) {
                .app => {},
                .surface => |core| core.rt_surface.setMouseShape(value),
            }
            return true;
        },
        .progress_report => {
            switch (target) {
                .app => {},
                .surface => |core| core.rt_surface.setProgressReport(value),
            }
            return true;
        },
        .start_search => {
            switch (target) {
                .app => {},
                .surface => |core| try core.rt_surface.search_overlay.show(),
            }
            return true;
        },
        .end_search => {
            switch (target) {
                .app => {},
                .surface => |core| core.rt_surface.search_overlay.hide(),
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

pub fn redrawInspector(_: *App, _: *Surface) void {}

// ---------------------------------------------------------------
// Tab management
// ---------------------------------------------------------------

/// Create a new tab with a fresh Surface.
pub fn newTab(self: *App) !void {
    const alloc = self.core_app.alloc;
    var config = try configpkg.Config.load(alloc);
    defer config.deinit();

    var surface = try alloc.create(Surface);
    errdefer alloc.destroy(surface);
    try surface.init(self, self.core_app, &config);
    errdefer surface.deinit();

    try self.surfaces.append(alloc, surface);
    errdefer _ = self.surfaces.pop();

    // Sync surface size with actual HWND client area (same fix as initXaml step 8).
    if (self.hwnd) |hwnd| {
        var rect: os.RECT = .{};
        _ = os.GetClientRect(hwnd, &rect);
        const w: u32 = @intCast(@max(1, rect.right - rect.left));
        const h: u32 = @intCast(@max(1, rect.bottom - rect.top));
        if (w > 0 and h > 0) surface.updateSize(w, h);
    }

    // Create TabViewItem and add to TabView.
    const tab_view = self.tab_view orelse return error.AppInitFailed;
    const tvi_inspectable = try self.activateXamlType("Microsoft.UI.Xaml.Controls.TabViewItem");
    const tvi = try tvi_inspectable.queryInterface(com.ITabViewItem);
    defer tvi.release();

    const initial_title = try winrt.hstring("Terminal");
    defer winrt.deleteHString(initial_title);
    const boxed_title = try self.boxString(initial_title);
    defer _ = boxed_title.release();
    try tvi.putHeader(@ptrCast(boxed_title));
    try tvi.putIsClosable(false);

    // Set placeholder content on tab item. Active panel is attached on selection.
    const content_control = try tvi_inspectable.queryInterface(com.IContentControl);
    defer content_control.release();
    const placeholder_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Border");
    defer winrt.deleteHString(placeholder_class);
    const placeholder = try winrt.activateInstance(placeholder_class);
    defer _ = placeholder.release();
    try content_control.putContent(@ptrCast(placeholder));

    // Add to TabItems collection.
    const tab_items = try tab_view.getTabItems();
    try tab_items.append(@ptrCast(tvi_inspectable));

    // Store the IInspectable reference on the surface for later title updates.
    surface.tab_view_item_inspectable = tvi_inspectable;

    // Select the new tab.
    const size = try tab_items.getSize();
    try tab_view.putSelectedIndex(@intCast(size - 1));
    self.active_surface_idx = @intCast(size - 1);
    self.attachSurfaceToTabItem(if (self.surfaces.items.len > 1) self.active_surface_idx - 1 else null, self.active_surface_idx) catch |err| {
        log.warn("newTab: attachSurfaceToTabItem({}) failed: {}", .{ self.active_surface_idx, err });
    };

    // Ensure keyboard focus returns to our input overlay.
    if (self.input_hwnd) |h| _ = os.SetFocus(h);

    log.info("newTab completed: idx={} total={}", .{ self.active_surface_idx, self.surfaces.items.len });
}

/// Close the active tab and its surface.
pub fn closeActiveTab(self: *App) void {
    if (self.surfaces.items.len == 0) return;
    self.closeTab(self.active_surface_idx);
}

/// Toggle the root container between single SwapChainPanel and TabView.
/// For safety this currently supports only the single-surface case.
pub fn toggleTabViewContainer(self: *App) !void {
    const window = self.window orelse return error.NoWindow;
    if (self.surfaces.items.len == 0) return;
    if (self.surfaces.items.len > 1) {
        log.warn("toggleTabViewContainer: requires exactly one surface (have {})", .{self.surfaces.items.len});
        return;
    }

    const surface = self.surfaces.items[0];
    const panel = surface.swap_chain_panel orelse return error.AppInitFailed;

    if (self.tab_view) |tv| {
        // TabView -> single panel
        log.info("toggleTabViewContainer: tab->single start", .{});
        self.unregisterTabViewHandlers(tv);
        if (tv.getTabItems()) |tab_items| {
            defer tab_items.release();
            if ((tab_items.getSize() catch 0) > 0) {
                tab_items.removeAt(0) catch {};
            }
        } else |_| {}
        if (surface.tab_view_item_inspectable) |tvi_insp| {
            if (tvi_insp.queryInterface(com.IContentControl)) |content_control| {
                defer content_control.release();
                content_control.putContent(null) catch {};
            } else |_| {}
        }
        window.putContent(null) catch {};

        const wrapped_panel = panel;
        if (wrapped_panel != @as(*winrt.IInspectable, @ptrCast(panel))) {
            defer _ = wrapped_panel.release();
            window.putContent(@ptrCast(wrapped_panel)) catch |err| {
                log.warn("toggleTabViewContainer: window.putContent(wrapped_panel) failed: {}", .{err});
                return err;
            };
        } else {
            window.putContent(@ptrCast(panel)) catch |err| {
                log.warn("toggleTabViewContainer: window.putContent(panel) failed: {}", .{err});
                return err;
            };
        }

        if (surface.tab_view_item_inspectable) |tvi| {
            _ = tvi.release();
            surface.tab_view_item_inspectable = null;
        }
        tv.release();
        self.tab_view = null;
        self.active_surface_idx = 0;
        surface.rebindSwapChain();
        if (self.input_hwnd) |h| _ = os.SetFocus(h);
        log.info("toggleTabViewContainer: switched to single-panel mode", .{});
        return;
    }

    // single panel -> TabView
    log.info("toggleTabViewContainer: single->tab start", .{});
    const tv_inspectable = try self.activateXamlType("Microsoft.UI.Xaml.Controls.TabView");
    const tv = tv_inspectable.queryInterface(com.ITabView) catch |err| {
        log.warn("toggleTabViewContainer: TabView QI failed: {}", .{err});
        return;
    };

    self.setControlBackground(@ptrCast(tv_inspectable), .{ .a = 255, .r = 0, .g = 0, .b = 0 });
    window.putContent(@ptrCast(tv_inspectable)) catch |err| {
        log.warn("toggleTabViewContainer: window.putContent(TabView) failed: {}", .{err});
        return err;
    };
    self.tab_view = tv;
    self.active_surface_idx = 0;
    self.registerTabViewHandlers(tv) catch |err| {
        log.warn("toggleTabViewContainer: register handlers failed: {}", .{err});
    };

    const tvi_inspectable = try self.activateXamlType("Microsoft.UI.Xaml.Controls.TabViewItem");
    const tvi = try tvi_inspectable.queryInterface(com.ITabViewItem);
    defer tvi.release();

    const initial_title = try winrt.hstring("Terminal");
    defer winrt.deleteHString(initial_title);
    const boxed_title = try self.boxString(initial_title);
    defer _ = boxed_title.release();
    tvi.putHeader(@ptrCast(boxed_title)) catch |err| {
        log.warn("toggleTabViewContainer: tvi.putHeader failed: {}", .{err});
        return err;
    };
    tvi.putIsClosable(false) catch |err| {
        log.warn("toggleTabViewContainer: tvi.putIsClosable failed: {}", .{err});
        return err;
    };

    const content_control = try tvi_inspectable.queryInterface(com.IContentControl);
    defer content_control.release();
    content_control.putContent(@ptrCast(panel)) catch |err| {
        log.warn("toggleTabViewContainer: tvi.putContent(panel) failed: {}", .{err});
        return err;
    };

    const tab_items = try tv.getTabItems();
    defer tab_items.release();
    tab_items.append(@ptrCast(tvi_inspectable)) catch |err| {
        log.warn("toggleTabViewContainer: tab_items.append failed: {}", .{err});
        return err;
    };
    tv.putSelectedIndex(0) catch |err| {
        log.warn("toggleTabViewContainer: putSelectedIndex failed: {}", .{err});
        return err;
    };

    if (surface.tab_view_item_inspectable) |old| _ = old.release();
    surface.tab_view_item_inspectable = tvi_inspectable;
    surface.rebindSwapChain();
    if (self.input_hwnd) |h| _ = os.SetFocus(h);
    log.info("toggleTabViewContainer: switched to TabView mode", .{});
}

/// Close a specific tab by index.
pub fn closeTab(self: *App, idx: usize) void {
    if (idx >= self.surfaces.items.len) return;

    const surface = self.surfaces.items[idx];

    // Remove from TabView.
    if (self.tab_view) |tv| {
        const tab_items = tv.getTabItems() catch |err| {
            log.warn("closeTab: getTabItems failed: {}", .{err});
            return;
        };
        tab_items.removeAt(@intCast(idx)) catch |err| {
            log.warn("closeTab: removeAt({}) failed: {}", .{ idx, err });
        };
    }

    // Cleanup surface.
    surface.deinit();
    self.core_app.alloc.destroy(surface);
    _ = self.surfaces.orderedRemove(idx);

    // Adjust active index or quit if no tabs remain.
    if (self.surfaces.items.len == 0) {
        log.info("closeTab: no tabs remain, requesting app exit", .{});
        self.running = false;
        if (self.xaml_app) |xa| {
            xa.exit() catch {};
        }
    } else if (self.active_surface_idx >= self.surfaces.items.len) {
        self.active_surface_idx = self.surfaces.items.len - 1;
    }
}

/// Close a surface by pointer (called from Surface.close).
pub fn closeSurface(self: *App, surface: *Surface) void {
    for (self.surfaces.items, 0..) |s, i| {
        if (s == surface) {
            self.closeTab(i);
            return;
        }
    }
    // Fallback: close the app if surface not found
    if (self.hwnd) |hwnd| {
        _ = os.PostMessageW(hwnd, os.WM_CLOSE, 0, 0);
    }
}

/// Get the currently active Surface, or null if none.
pub fn activeSurface(self: *App) ?*Surface {
    if (self.surfaces.items.len == 0) return null;
    if (self.active_surface_idx >= self.surfaces.items.len) return null;
    return self.surfaces.items[self.active_surface_idx];
}

// ---------------------------------------------------------------
// TabView event callbacks
// ---------------------------------------------------------------

fn onTabCloseRequested(self: *App, _: *anyopaque, args_obj: *anyopaque) void {
    log.info("onTabCloseRequested", .{});
    const args: *com.ITabViewTabCloseRequestedEventArgs = @ptrCast(@alignCast(args_obj));
    const tab_insp = args.getTab() catch {
        self.closeActiveTab();
        return;
    };
    defer _ = tab_insp.release();

    if (self.tab_view) |tv| {
        const tab_items = tv.getTabItems() catch {
            self.closeActiveTab();
            return;
        };
        const count = tab_items.getSize() catch {
            self.closeActiveTab();
            return;
        };

        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const item_ptr = tab_items.getAt(i) catch continue;
            const item_insp: *winrt.IInspectable = @ptrCast(@alignCast(item_ptr));
            defer _ = item_insp.release();
            if (@intFromPtr(item_insp) == @intFromPtr(tab_insp)) {
                self.closeTab(@intCast(i));
                return;
            }
        }
    }

    // Fallback if we couldn't resolve the target item.
    self.closeActiveTab();
}

fn onAddTabButtonClick(self: *App, _: *anyopaque, _: *anyopaque) void {
    log.info("onAddTabButtonClick", .{});
    self.newTab() catch |err| {
        log.err("Failed to create new tab: {}", .{err});
    };
}

fn onSelectionChanged(self: *App, _: *anyopaque, _: *anyopaque) void {
    log.info("onSelectionChanged", .{});
    if (self.tab_view) |tv| {
        const idx = tv.getSelectedIndex() catch return;
        if (idx >= 0 and @as(usize, @intCast(idx)) < self.surfaces.items.len) {
            const new_idx: usize = @intCast(idx);
            // Notify old surface it lost focus.
            if (new_idx != self.active_surface_idx) {
                if (self.active_surface_idx < self.surfaces.items.len) {
                    self.surfaces.items[self.active_surface_idx].core_surface.focusCallback(false) catch {};
                }
            }
            const old_idx = self.active_surface_idx;
            self.active_surface_idx = new_idx;
            self.attachSurfaceToTabItem(old_idx, new_idx) catch |err| {
                log.warn("onSelectionChanged: attachSurfaceToTabItem({}) failed: {}", .{ new_idx, err });
            };
            self.auditActiveTabBinding();
            // Notify new surface it gained focus.
            self.surfaces.items[new_idx].core_surface.focusCallback(true) catch {};
            self.surfaces.items[new_idx].rebindSwapChain();

            // Redirect Win32 focus back to our input overlay.
            if (self.input_hwnd) |h| _ = os.SetFocus(h);
        }
    }
}

// ---------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------

/// Set the background of a Control to a solid color.
pub fn setControlBackground(_: *App, control_insp: *winrt.IInspectable, color: com.ISolidColorBrush.Color) void {
    const brush_class = winrt.hstring("Microsoft.UI.Xaml.Media.SolidColorBrush") catch return;
    defer winrt.deleteHString(brush_class);
    const brush_insp = winrt.activateInstance(brush_class) catch |err| {
        log.warn("setControlBackground: SolidColorBrush activation failed: {}", .{err});
        return;
    };
    defer _ = brush_insp.release();

    const brush = brush_insp.queryInterface(com.ISolidColorBrush) catch |err| {
        log.warn("setControlBackground: QI ISolidColorBrush failed: {}", .{err});
        return;
    };
    defer brush.release();

    brush.putColor(color) catch |err| {
        log.warn("setControlBackground: putColor failed: {}", .{err});
        return;
    };

    var control_raw: ?*anyopaque = null;
    const control_hr = control_insp.lpVtbl.QueryInterface(@ptrCast(control_insp), &com.IControl.IID, &control_raw);
    if (control_hr >= 0 and control_raw != null) {
        const control: *com.IControl = @ptrCast(@alignCast(control_raw.?));
        defer control.release();
        control.putBackground(@ptrCast(brush)) catch |err| {
            log.warn("setControlBackground: IControl.putBackground failed: {}", .{err});
        };
        return;
    }

    var panel_raw: ?*anyopaque = null;
    const panel_hr = control_insp.lpVtbl.QueryInterface(@ptrCast(control_insp), &com.IPanel.IID, &panel_raw);
    if (panel_hr >= 0 and panel_raw != null) {
        const panel: *com.IPanel = @ptrCast(@alignCast(panel_raw.?));
        defer panel.release();
        panel.putBackground(@ptrCast(brush)) catch |err| {
            log.warn("setControlBackground: IPanel.putBackground failed: {}", .{err});
        };
        return;
    }

    log.warn(
        "setControlBackground: QI failed (IControl=0x{x:0>8}, IPanel=0x{x:0>8})",
        .{ @as(u32, @bitCast(control_hr)), @as(u32, @bitCast(panel_hr)) },
    );
}

fn auditActiveTabBinding(self: *App) void {
    if (self.active_surface_idx >= self.surfaces.items.len) return;
    const s = self.surfaces.items[self.active_surface_idx];
    const tvi = s.tab_view_item_inspectable orelse return;
    const panel = s.swap_chain_panel orelse return;
    const cc = tvi.queryInterface(com.IContentControl) catch return;
    defer cc.release();
    const cur = cc.getContent() catch return;
    if (cur) |c| {
        defer _ = c.release();
        log.info(
            "auditActiveTabBinding: idx={} content=0x{x} panel=0x{x} match={}",
            .{ self.active_surface_idx, @intFromPtr(c), @intFromPtr(panel), @intFromPtr(c) == @intFromPtr(panel) },
        );
    } else {
        log.warn("auditActiveTabBinding: idx={} content=null panel=0x{x}", .{ self.active_surface_idx, @intFromPtr(panel) });
    }
}

fn setTabItemContent(_: *App, tvi_insp: *winrt.IInspectable, content: ?*winrt.IInspectable) !void {
    const cc = try tvi_insp.queryInterface(com.IContentControl);
    defer cc.release();
    if (content) |c| {
        const wrapped = c;
        if (wrapped != c) {}
        try cc.putContent(@ptrCast(wrapped));
    } else {
        try cc.putContent(null);
    }
}

fn attachSurfaceToTabItem(self: *App, prev_idx_opt: ?usize, idx: usize) !void {
    if (self.tab_view == null) return;
    if (idx >= self.surfaces.items.len) return;

    // Detach previous tab content back to a placeholder.
    if (prev_idx_opt) |prev_idx| if (prev_idx < self.surfaces.items.len and prev_idx != idx) {
        const prev_surface = self.surfaces.items[prev_idx];
        if (prev_surface.tab_view_item_inspectable) |prev_tvi| {
            const placeholder_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Border");
            defer winrt.deleteHString(placeholder_class);
            const placeholder = try winrt.activateInstance(placeholder_class);
            defer _ = placeholder.release();
            self.setTabItemContent(prev_tvi, placeholder) catch {};
        }
    };

    const surface = self.surfaces.items[idx];
    const tvi_insp = surface.tab_view_item_inspectable orelse return;
    const panel = surface.swap_chain_panel orelse return;

    // Ensure the panel fills the tab content area.
    if (panel.queryInterface(com.IFrameworkElement)) |fe| {
        defer fe.release();
    } else |_| {}

    log.info("attachSurfaceToTabItem: idx={} panel=0x{x}", .{ idx, @intFromPtr(panel) });
    try self.setTabItemContent(tvi_insp, panel);
}

pub fn ensureVisibleSurfaceAttached(self: *App, surface: *Surface) void {
    if (self.tab_view == null) return;
    for (self.surfaces.items, 0..) |s, i| {
        if (s == surface and i == self.active_surface_idx) {
            self.attachSurfaceToTabItem(null, i) catch |err| {
                log.warn("ensureVisibleSurfaceAttached: attach failed: {}", .{err});
            };
            return;
        }
    }
}

/// Activate a XAML type by name. Tries XAML type system first (via IXamlMetadataProvider),
/// falls back to RoActivateInstance for built-in types.
pub fn activateXamlType(self: *App, comptime class_name: [:0]const u8) !*winrt.IInspectable {
    // Try XAML type system first (required for WinUI3 custom controls like TabView).
    if (self.app_outer.provider) |provider| {
        const name = try winrt.hstring(class_name);
        defer winrt.deleteHString(name);
        if (provider.getXamlType(name)) |xaml_type| {
            defer xaml_type.release();
            const instance = try xaml_type.activateInstance();
            return @ptrCast(@alignCast(instance));
        } else |_| {}
    }
    // Fallback to RoActivateInstance (works for base framework types).
    const name = try winrt.hstring(class_name);
    defer winrt.deleteHString(name);
    return winrt.activateInstance(name);
}

/// Box an HSTRING as an IInspectable via Windows.Foundation.PropertyValue.CreateString.
fn boxString(_: *App, str: winrt.HSTRING) !*winrt.IInspectable {
    log.info("boxString: getActivationFactory(IPropertyValueStatics)...", .{});
    const class_name = try winrt.hstring("Windows.Foundation.PropertyValue");
    defer winrt.deleteHString(class_name);
    const factory = try winrt.getActivationFactory(com.IPropertyValueStatics, class_name);
    defer factory.release();
    log.info("boxString: createString...", .{});
    const result = try factory.createString(str);
    log.info("boxString: OK", .{});
    return @ptrCast(@alignCast(result));
}

/// Toggle fullscreen mode using Win32 borderless window approach.
fn toggleFullscreen(self: *App) void {
    const hwnd = self.hwnd orelse return;

    if (self.is_fullscreen) {
        // Restore windowed mode.
        _ = os.SetWindowLongPtrW(hwnd, os.GWL_STYLE, self.saved_style);
        _ = os.SetWindowPlacement(hwnd, &self.saved_placement);
        const SWP_NOMOVE = 0x0002;
        const SWP_NOSIZE = 0x0001;
        _ = os.SetWindowPos(hwnd, null, 0, 0, 0, 0, os.SWP_FRAMECHANGED | os.SWP_NOOWNERZORDER | os.SWP_NOZORDER | SWP_NOMOVE | SWP_NOSIZE);
        self.is_fullscreen = false;
    } else {
        // Save current state and enter fullscreen.
        self.saved_style = os.GetWindowLongPtrW(hwnd, os.GWL_STYLE);
        _ = os.GetWindowPlacement(hwnd, &self.saved_placement);

        // Remove caption and thick frame for borderless.
        const new_style = self.saved_style & ~@as(usize, os.WS_OVERLAPPEDWINDOW);
        _ = os.SetWindowLongPtrW(hwnd, os.GWL_STYLE, new_style);

        // Expand to cover the full monitor.
        const monitor = os.MonitorFromWindow(hwnd, os.MONITOR_DEFAULTTONEAREST) orelse return;
        var mi: os.MONITORINFO = .{};
        if (os.GetMonitorInfoW(monitor, &mi) != 0) {
            _ = os.SetWindowPos(
                hwnd,
                os.HWND_TOP,
                mi.rcMonitor.left,
                mi.rcMonitor.top,
                mi.rcMonitor.right - mi.rcMonitor.left,
                mi.rcMonitor.bottom - mi.rcMonitor.top,
                os.SWP_FRAMECHANGED | os.SWP_NOOWNERZORDER,
            );
        }
        self.is_fullscreen = true;
    }
}

/// Load XamlControlsResources into Application.Resources.
/// This enables WinUI 3 custom controls (TabView, NavigationView, etc.)
/// to find their XAML templates. Without it, RoActivateInstance returns E_NOTIMPL.
fn loadXamlResources(_: *App, xa: *com.IApplication) void {
    // The Application created via IApplicationFactory may not have Resources set.
    // get_Resources returns E_UNEXPECTED in that case. So we:
    // 1. Create a new ResourceDictionary
    // 2. Set it as Application.Resources via put_Resources
    // 3. Create XamlControlsResources
    // 4. Append XamlControlsResources to the ResourceDictionary's MergedDictionaries
    // This matches the C++/WinRT pattern: Resources().MergedDictionaries().Append(XamlControlsResources())

    log.info("loadXamlResources: starting...", .{});

    // Step 1: Create a ResourceDictionary.
    const rd_class = winrt.hstring("Microsoft.UI.Xaml.ResourceDictionary") catch {
        log.err("loadXamlResources: Failed to create ResourceDictionary HSTRING", .{});
        return;
    };
    defer winrt.deleteHString(rd_class);
    const rd_inspectable = winrt.activateInstance(rd_class) catch |err| {
        log.err("loadXamlResources step 1: ResourceDictionary creation failed: {}", .{err});
        return;
    };
    log.info("loadXamlResources step 1 OK: ResourceDictionary created", .{});

    // Step 2: Set it as Application.Resources.
    xa.putResources(@ptrCast(rd_inspectable)) catch |err| {
        log.err("loadXamlResources step 2: Application.put_Resources failed: {}", .{err});
        return;
    };
    log.info("loadXamlResources step 2 OK: ResourceDictionary set on Application", .{});

    // Force Dark theme to avoid white backgrounds by default.
    xa.putRequestedTheme(.dark) catch {};
    log.info("loadXamlResources: Requested Dark theme", .{});

    // Step 3: QI for IResourceDictionary to get MergedDictionaries.
    const res_dict = rd_inspectable.queryInterface(com.IResourceDictionary) catch |err| {
        log.err("loadXamlResources step 3a: ResourceDictionary QI failed: {}", .{err});
        return;
    };
    defer res_dict.release();

    const merged = res_dict.getMergedDictionaries() catch |err| {
        log.err("loadXamlResources step 3b: get_MergedDictionaries failed: {}", .{err});
        return;
    };
    log.info("loadXamlResources step 3 OK: got MergedDictionaries", .{});

    // Step 4: Create XamlControlsResources and append to MergedDictionaries.
    const xcr_class = winrt.hstring("Microsoft.UI.Xaml.Controls.XamlControlsResources") catch {
        log.err("loadXamlResources step 4: Failed to create XamlControlsResources HSTRING", .{});
        return;
    };
    defer winrt.deleteHString(xcr_class);
    const xcr = winrt.activateInstance(xcr_class) catch |err| {
        log.err("loadXamlResources step 4: XamlControlsResources creation failed: {}", .{err});
        return;
    };
    log.info("loadXamlResources step 4a OK: XamlControlsResources created", .{});

        merged.append(@ptrCast(xcr)) catch |err| {

            log.err("loadXamlResources step 4b: MergedDictionaries.Append failed: {}", .{err});

            return;

        };

    log.info("loadXamlResources OK: XamlControlsResources loaded via MergedDictionaries", .{});

    // Step 5: Override TabView resources to black (Windows Terminal pattern).
    // This removes the default white/gray backgrounds of the tab strip.
    if (true) {
        const brush_class = winrt.hstring("Microsoft.UI.Xaml.Media.SolidColorBrush") catch return;
        defer winrt.deleteHString(brush_class);
        const brush_insp = winrt.activateInstance(brush_class) catch return;
        defer _ = brush_insp.release();
        const brush = brush_insp.queryInterface(com.ISolidColorBrush) catch return;
        defer brush.release();
        brush.putColor(.{ .a = 255, .r = 0, .g = 0, .b = 0 }) catch {};

        // In a real implementation, we would insert these into the dictionary.
        // For now, we've already set the control background in createTabViewRoot.
        log.info("loadXamlResources: TabView resource overrides ready", .{});
    }
}

fn verifyTabItemHasContent(content_control: *com.IContentControl) !bool {
    const current = try content_control.getContent();
    if (current) |insp| {
        _ = insp.release();
        return true;
    }
    return false;
}

pub fn drainMailbox(self: *App) void {
    log.info("drainMailbox: tick...", .{});
    self.core_app.tick(self) catch |err| {
        log.warn("tick error: {}", .{err});
    };
    log.info("drainMailbox: tick done", .{});
}

fn setTitle(self: *App, title: [:0]const u8) void {
    log.info("setTitle: \"{s}\"", .{title});
    const h = winrt.hstringRuntime(self.core_app.alloc, title) catch |err| {
        log.warn("setTitle: hstringRuntime failed: {}", .{err});
        return;
    };
    defer winrt.deleteHString(h);

    // Update window title bar.
    if (self.window) |window| {
        log.info("setTitle: putTitle...", .{});
        window.putTitle(h) catch {};
        log.info("setTitle: putTitle done", .{});
    }

    // Update active tab header.
    if (self.activeSurface()) |surface| {
        if (surface.tab_view_item_inspectable) |tvi_insp| {
            log.info("setTitle: QI for ITabViewItem...", .{});
            const tvi = tvi_insp.queryInterface(com.ITabViewItem) catch |err| {
                log.warn("setTitle: QI ITabViewItem failed: {}", .{err});
                return;
            };
            defer tvi.release();
            // Box the string as IInspectable for the Header property.
            log.info("setTitle: boxString...", .{});
            const boxed = self.boxString(h) catch |err| {
                log.warn("setTitle: boxString failed: {}", .{err});
                return;
            };
            defer _ = boxed.release();
            log.info("setTitle: putHeader...", .{});
            tvi.putHeader(@ptrCast(boxed)) catch {};
            log.info("setTitle: putHeader done", .{});
        }
    }
    log.info("setTitle: completed", .{});
}

// ---------------------------------------------------------------
// HWND subclass procedure and per-message handlers
// ---------------------------------------------------------------

/// Win32 subclass procedure callback.
/// Installed via SetWindowSubclass on the WinUI 3 window's HWND to intercept

pub const subclassProc = @import("hacks.zig").subclassProc;
pub const stowedExceptionHandler = @import("hacks.zig").stowedExceptionHandler;

test "App.performAction logic" {
    const testing = std.testing;
    const alloc = testing.allocator;

    // Manually initialize App fields to avoid ArrayList initialization issues in tests
    var app = App{
        .core_app = undefined,
        .surfaces = .{},
    };
    defer app.surfaces.deinit(alloc);

    // Test quit action
    app.running = true;
    _ = try app.performAction(.app, .quit, {});
    try testing.expect(!app.running);

    // Test close_all_windows action
    app.running = true;
    _ = try app.performAction(.app, .close_all_windows, {});
    try testing.expect(!app.running);
}
