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
const event = @import("event.zig");
const os = @import("os.zig");
const com_aggregation = @import("com_aggregation.zig");
const ime = @import("ime.zig");
const debug_harness = @import("debug_harness.zig");
const tabview_runtime = @import("tabview_runtime.zig");
const tab_index = @import("tab_index.zig");
const tab_manager = @import("tab_manager.zig");
const input_runtime = @import("input_runtime.zig");
const window_runtime = @import("window_runtime.zig");
const xaml_helpers = @import("xaml_helpers.zig");
const surface_binding = @import("surface_binding.zig");
const event_handlers = @import("event_handlers.zig");
const ControlPlane = @import("control_plane.zig").ControlPlane;

const log = std.log.scoped(.winui3);

/// Temporary file logger for debugging GUI app (no stderr visible).
pub fn fileLog(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt ++ "\n", args) catch return;
    const K32 = std.os.windows.kernel32;
    const path_w = std.unicode.utf8ToUtf16LeStringLiteral("C:\\Users\\yuuji\\ghostty_debug.log");
    const h = K32.CreateFileW(
        path_w,
        0x40000000, // GENERIC_WRITE
        1, // FILE_SHARE_READ
        null,
        4, // OPEN_ALWAYS
        0x80, // FILE_ATTRIBUTE_NORMAL
        null,
    );
    if (h == std.os.windows.INVALID_HANDLE_VALUE) return;
    defer _ = windows.ntdll.NtClose(h);
    _ = K32.SetFilePointerEx(h, @bitCast(@as(i64, 0)), null, 2); // FILE_END
    _ = K32.WriteFile(h, msg.ptr, @intCast(msg.len), null, null);
}

/// Timer ID for live resize preview.
const RESIZE_TIMER_ID: usize = 1;
const CONTEXT_MENU_NEW_TAB: usize = 1001;
const CONTEXT_MENU_CLOSE_TAB: usize = 1002;
const CONTEXT_MENU_PASTE: usize = 1003;
const CONTEXT_MENU_CLOSE_WINDOW: usize = 1004;
const APPMODEL_ERROR_NO_PACKAGE: i32 = 15700;
const XamlClass = struct {
    const Application = "Microsoft.UI.Xaml.Application";
    const Window = "Microsoft.UI.Xaml.Window";
    const TabView = "Microsoft.UI.Xaml.Controls.TabView";
    const TabViewItem = "Microsoft.UI.Xaml.Controls.TabViewItem";
    const Border = "Microsoft.UI.Xaml.Controls.Border";
    const Grid = "Microsoft.UI.Xaml.Controls.Grid";
    const SolidColorBrush = "Microsoft.UI.Xaml.Media.SolidColorBrush";
    const XamlControlsResources = "Microsoft.UI.Xaml.Controls.XamlControlsResources";
    const XamlMetadataProvider = "Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider";
};
const InitialTabTitle = "Terminal";

const InitCallback = com_aggregation.InitCallback(App);
const AppOuter = com_aggregation.AppOuter;
const guidEql = com_aggregation.guidEql;

extern "kernel32" fn GetCurrentPackageFullName(package_full_name_length: *u32, package_full_name: ?[*]u16) callconv(.winapi) i32;

const StartupStage = enum {
    not_started,
    xaml_entered,
    application_ready,
    window_ready,
    window_activated,
    content_ready,
    parity_checked,
    init_complete,
    failed,
};

const ExitIntent = enum {
    none,
    window_closed,
    terminate,
    request_close_window,
    quit_action,
    close_all_windows,
};

pub const KeyboardFocusTarget = enum {
    xaml_surface,
    input_overlay,
};

/// The core application.
core_app: *CoreApp,
debug_cfg: debug_harness.RuntimeDebugConfig = .{},

/// COM aggregation outer object that implements IXamlMetadataProvider.
/// Must be kept alive for the lifetime of the Application.
app_outer: AppOuter = undefined,

/// The WinUI 3 Application instance (needed for calling Exit() on shutdown).
xaml_app: ?*com.IApplication = null,
xaml_controls_resources: ?*winrt.IInspectable = null,

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

/// Desired keyboard focus owner. Normal typing stays on the XAML surface; IME
/// composition temporarily switches to the dedicated input overlay HWND.
keyboard_focus_target: KeyboardFocusTarget = .xaml_surface,
ime_composing: bool = false,
ime_last_had_result: bool = false,

/// All surfaces (one per tab).
surfaces: std.ArrayListUnmanaged(*Surface) = .{},

/// Index of the currently active/selected tab.
active_surface_idx: usize = 0,

/// The TabView control that manages tabs.
tab_view: ?*com.ITabView = null,

/// The content grid (Row 1 of RootGrid) where SwapChainPanel is placed.
/// In Issue #28 architecture, SwapChainPanel lives here, NOT in TabViewItem.Content.
tab_content_grid: ?*winrt.IInspectable = null,

/// Whether the app is running.
running: bool = false,
startup_stage: StartupStage = .not_started,
startup_bootstrapped: bool = false,
parity_verified: bool = false,
exit_intent: ExitIntent = .none,
close_event_seen: bool = false,

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

/// Optional side-channel control plane for session-aware automation.
control_plane: ?*ControlPlane = null,

/// DispatcherQueueController — must be kept alive for the lifetime of the app.
dq_controller: ?*winrt.IInspectable = null,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    os.OutputDebugStringA("MARKER-APP-INIT-ENTRY\n");
    fileLog("App.init: ENTRY", .{});

    // Allocate a debug console so log output is visible for GUI apps.
    os.attachDebugConsole();
    fileLog("App.init: after attachDebugConsole", .{});

    // Install a Vectored Exception Handler to capture details of
    // STATUS_STOWED_EXCEPTION before the process terminates.
    _ = os.AddVectoredExceptionHandler(1, &stowedExceptionHandler);
    _ = os.SetUnhandledExceptionFilter(&@import("wndproc.zig").unhandledExceptionFilter);
    fileLog("App.init: after VEH install", .{});

    // Request 1ms timer resolution for smooth animation timing.
    _ = os.timeBeginPeriod(1);

    logPackageIdentity();
    fileLog("App.init: after logPackageIdentity", .{});

    // Step 1: Bootstrap the Windows App SDK runtime.
    bootstrap.init() catch |err| {
        fileLog("App.init: bootstrap FAILED err={}", .{err});
        log.err("Windows App SDK bootstrap failed: {}", .{err});
        return error.AppInitFailed;
    };
    fileLog("App.init: after bootstrap.init", .{});

    // Step 2: Initialize WinRT.
    winrt.hrCheck(winrt.RoInitialize(winrt.RO_INIT_SINGLETHREADED)) catch |err| {
        fileLog("App.init: RoInitialize FAILED err={}", .{err});
        log.err("RoInitialize failed: {}", .{err});
        return error.AppInitFailed;
    };
    fileLog("App.init: after RoInitialize", .{});

    // Step 3: Create a DispatcherQueue for the current thread.
    // This is required before creating any XAML objects.
    const dq_opts = winrt.DispatcherQueueOptions{};
    const dq_controller = winrt.createDispatcherQueueController(&dq_opts) catch |err| {
        fileLog("App.init: DispatcherQueue FAILED err={}", .{err});
        log.err("CreateDispatcherQueueController failed: {}", .{err});
        return error.AppInitFailed;
    };
    fileLog("App.init: after DispatcherQueue", .{});
    self.* = .{
        .core_app = core_app,
        .debug_cfg = debug_harness.RuntimeDebugConfig.load(),
        .surfaces = .{},
        .running = true,
        .dq_controller = dq_controller,
    };
    log.info("winui3 xaml_metadata_provider={s}", .{
        if (self.debug_cfg.use_ixaml_metadata_provider) "on" else "off",
    });
    self.debug_cfg.log(log);

    // Window/UI creation happens inside run() via Application.Start(callback).
    // WinUI 3 requires Window creation on the XAML thread which is set up by Start().
    log.info("WinUI 3 runtime initialized (window creation deferred to run)", .{});
    fileLog("App.init: EXIT OK", .{});
}

/// Called from inside Application.Start() callback — XAML thread is active here.
pub fn initXaml(self: *App) !void {
    fileLog("initXaml: START", .{});
    log.info("initXaml: creating Window inside XAML thread", .{});
    self.startup_bootstrapped = false;
    self.parity_verified = false;
    self.setStartupStage(.xaml_entered);
    errdefer self.setStartupStage(.failed);

    try self.createAggregatedApplication();
    self.setStartupStage(.application_ready);

    const window = try self.createWindowAndHooks();
    self.setStartupStage(.window_ready);

    try self.activateWindowAndLoadResources(window);
    self.setStartupStage(.window_activated);

    try self.createWindowContent(window);
    try self.scheduleDebugActions();
    self.syncVisualDiagnostics();
    self.setupNativeInputWindows();
    input_runtime.focusKeyboardTarget(self);
    self.startup_bootstrapped = true;
    self.setStartupStage(.content_ready);
    fileLog("initXaml: content_ready, entering message loop", .{});

    // --- Control Plane (optional, env-gated) ---
    if (ControlPlane.isEnabled(self.core_app.alloc)) {
        if (self.hwnd) |hwnd| {
            self.control_plane = ControlPlane.create(
                self.core_app.alloc,
                hwnd,
                @ptrCast(self),
                controlPlaneCaptureState,
                controlPlaneCaptureTail,
                controlPlaneCaptureTabList,
            ) catch |err| blk: {
                log.warn("failed to start control plane: {}", .{err});
                break :blk null;
            };
        }
    }

    // --- TabView Parity Validation (Tier 2 Verification) ---
    self.validateTabViewParity() catch |err| {
        log.err("validateTabViewParity: CRITICAL_FAIL: {}", .{err});
        return;
    };
    self.parity_verified = true;
    self.setStartupStage(.parity_checked);
    self.setStartupStage(.init_complete);
}

fn setStartupStage(self: *App, stage: StartupStage) void {
    self.startup_stage = stage;
    log.info("startup stage: {s}", .{startupStageLabel(stage)});
}

fn startupStageLabel(stage: StartupStage) []const u8 {
    return switch (stage) {
        .not_started => "not_started",
        .xaml_entered => "xaml_entered",
        .application_ready => "application_ready",
        .window_ready => "window_ready",
        .window_activated => "window_activated",
        .content_ready => "content_ready",
        .parity_checked => "parity_checked",
        .init_complete => "init_complete",
        .failed => "failed",
    };
}

fn setExitIntent(self: *App, intent: ExitIntent) void {
    if (self.exit_intent == .none) {
        self.exit_intent = intent;
    }
    log.info("exit intent: {s}", .{exitIntentLabel(self.exit_intent)});
}

fn exitIntentLabel(intent: ExitIntent) []const u8 {
    return switch (intent) {
        .none => "none",
        .window_closed => "window_closed",
        .terminate => "terminate",
        .request_close_window => "request_close_window",
        .quit_action => "quit_action",
        .close_all_windows => "close_all_windows",
    };
}

fn createAggregatedApplication(self: *App) !void {
    // Step 0: Create the Application instance via IApplicationFactory with COM aggregation.
    // Application.Start() does NOT create an Application — the callback must.
    //
    // WinUI 3 custom controls (TabView, etc.) require IXamlMetadataProvider to be
    // implemented on the Application object. We use COM aggregation to inject our
    // implementation: AppOuter acts as the controlling IUnknown, and when the XAML
    // framework QI's for IXamlMetadataProvider, it gets our implementation which
    // delegates to XamlControlsXamlMetaDataProvider.
    const app_class = try winrt.hstring(XamlClass.Application);
    defer winrt.deleteHString(app_class);
    log.info("initXaml step 0: Creating Application with COM aggregation...", .{});

    // Initialize the outer object that implements IXamlMetadataProvider.
    self.app_outer.init();

    // Activate XamlControlsXamlMetaDataProvider for metadata delegation.
    const provider_class = winrt.hstring(XamlClass.XamlMetadataProvider) catch null;
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
    var app_factory_guard = winrt.ComRef(com.IApplicationFactory).init(try winrt.getActivationFactory(com.IApplicationFactory, app_class));
    defer app_factory_guard.deinit();
    const app_factory = app_factory_guard.get();
    log.info("initXaml step 0: calling CreateInstance(outer=0x{x})...", .{@intFromPtr(self.app_outer.outerPtr())});
    const result = try app_factory.CreateInstance(self.app_outer.outerPtr());
    log.info("initXaml step 0: CreateInstance returned inner=0x{x} instance=0x{x}", .{
        @intFromPtr(result.inner), @intFromPtr(result.instance),
    });
    self.app_outer.inner = @ptrCast(@alignCast(result.inner));

    // QI for IApplication so we can call Exit() during shutdown and access Resources.
    self.xaml_app = result.instance.queryInterface(com.IApplication) catch null;
    log.info("initXaml step 0 OK: Application created with IXamlMetadataProvider", .{});
}

fn createWindowAndHooks(self: *App) !*com.IWindow {
    // Step 1: Create a Window via RoActivateInstance.
    const window_class = try winrt.hstring(XamlClass.Window);
    defer winrt.deleteHString(window_class);
    log.info("initXaml step 1: RoActivateInstance(Window)...", .{});
    var window_inspectable_guard = winrt.ComRef(winrt.IInspectable).init(try winrt.activateInstance(window_class));
    defer window_inspectable_guard.deinit();
    const window_inspectable = window_inspectable_guard.get();
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
    try window.SetTitle(title);
    log.info("initXaml step 3 OK", .{});

    // Step 4: Get the native HWND via IWindowNative.
    log.info("initXaml step 4: QueryInterface(IWindowNative)...", .{});
    var window_native_guard = winrt.ComRef(com.IWindowNative).init(try window.queryInterface(com.IWindowNative));
    defer window_native_guard.deinit();
    self.hwnd = try window_native_guard.get().getWindowHandle();
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
    self.closed_token = try window.AddClosed(self.closed_handler.?.comPtr());
    log.info("initXaml step 6 OK", .{});
    return window;
}

fn activateWindowAndLoadResources(self: *App, window: *com.IWindow) !void {
    return window_runtime.activateAndLoadResources(self, window);
}

fn createWindowContent(self: *App, window: *com.IWindow) !void {
    // Step 7.5: Create TabView root (RootGrid) if enabled, otherwise single-panel.
    const tv = try self.createTabViewRoot(window);
    self.tab_view = tv;

    if (tv) |tab_view| {
        tabview_runtime.configureDefaults(tab_view);
    }

    // Step 8: Create initial Surface and content.
    try self.createInitialSurfaceContent(window, tv);

    if (tv) |tab_view| {
        try self.registerTabViewHandlers(tab_view);
    }
}

fn scheduleDebugActions(self: *App) !void {
    // Step 10: Test control logic.
    // TabView is now created during createWindowContent, no deferred toggle needed.
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
}

fn syncVisualDiagnostics(self: *App) void {
    window_runtime.syncVisualDiagnostics(self);
}

fn setupNativeInputWindows(self: *App) void {
    input_runtime.setupNativeInputWindows(self, &subclassProc);
}

fn createTabViewRoot(self: *App, window: *com.IWindow) !?*com.ITabView {
    return tabview_runtime.createRoot(self, window, XamlClass.TabView);
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
        }
    }

    // Prefer surface_grid (SwapChainPanel + ScrollBar layout) over bare SwapChainPanel.
    const panel: *winrt.IInspectable = surface.surface_grid orelse surface.swap_chain_panel orelse return;

    if (tab_view) |tv| {
        // Issue #28 architecture: TabViewItem.Content = dummy Border,
        // SwapChainPanel goes into tab_content_grid (Row 1 of RootGrid).
        const tvi_inspectable = try self.activateXamlType(XamlClass.TabViewItem);
        var tvi_guard = winrt.ComRef(com.ITabViewItem).init(try tvi_inspectable.queryInterface(com.ITabViewItem));
        defer tvi_guard.deinit();
        const tvi = tvi_guard.get();

        const initial_title = try winrt.hstring("Terminal");
        defer winrt.deleteHString(initial_title);
        var boxed_title_guard = winrt.ComRef(winrt.IInspectable).init(try self.boxString(initial_title));
        defer boxed_title_guard.deinit();
        try tvi.SetHeader(boxed_title_guard.get());
        try tvi.SetIsClosable(true);

        // Set dummy Border as TabViewItem.Content (required for drag-drop, not for rendering).
        if (!self.debug_cfg.tabview_item_no_content) {
            var cc_guard = winrt.ComRef(com.IContentControl).init(try tvi_inspectable.queryInterface(com.IContentControl));
            defer cc_guard.deinit();
            const border_class = try winrt.hstring(XamlClass.Border);
            defer winrt.deleteHString(border_class);
            var border_guard = winrt.ComRef(winrt.IInspectable).init(try winrt.activateInstance(border_class));
            defer border_guard.deinit();
            try cc_guard.get().SetContent(@as(?*anyopaque, @ptrCast(border_guard.get())));
            log.info("initXaml step 8: TabViewItem dummy Border content set", .{});
        }

        if (!self.debug_cfg.tabview_append_item) {
            log.info("initXaml step 8: STOP at level 1 (no append)", .{});
            return;
        }

        const tab_items_ptr: *com.IVector = @ptrCast(@alignCast(try tv.TabItems()));
        var tab_items_guard = winrt.ComRef(com.IVector).init(tab_items_ptr);
        defer tab_items_guard.deinit();
        try tab_items_guard.get().append(@ptrCast(tvi_inspectable));
        surface.tab_view_item_inspectable = tvi_inspectable;

        const items_size = try tab_items_guard.get().getSize();
        log.info("initXaml step 8: TabViewItem appended, TabItems.size={}", .{items_size});

        if (!self.debug_cfg.tabview_select_first) {
            log.info("initXaml step 8: STOP at level 2 (no selectedIndex)", .{});
            return;
        }

        try tv.SetSelectedIndex(0);

        // Place SwapChainPanel into tab_content_grid (Row 1).
        const tab_content = self.tab_content_grid orelse return error.AppInitFailed;
        const content_panel = try tab_content.queryInterface(com.IPanel);
        defer content_panel.release();
        const content_children_raw = try content_panel.Children();
        const content_children: *com.IVector = @ptrCast(@alignCast(content_children_raw));
        defer content_children.release();
        try content_children.append(@ptrCast(panel));
        log.info("initXaml step 8: surface panel added to tab_content_grid", .{});

        surface.rebindSwapChain();
        log.info("initXaml step 8 OK: full (TabViewItem+append+selectedIndex+SwapChainPanel in tab_content_grid)", .{});
    } else {
        // Single-panel mode: SwapChainPanel directly as Window.Content.
        try window.SetContent(@as(?*anyopaque, @ptrCast(panel)));
        log.info("initXaml step 8 OK: SwapChainPanel set as Window content (single-tab)", .{});
    }
}

fn registerTabViewHandlers(self: *App, tab_view: ?*com.ITabView) !void {
    if (tab_view != null and self.debug_cfg.enable_tabview_handlers) {
        const alloc = self.core_app.alloc;
        if (self.debug_cfg.enable_handler_close) {
            self.tab_close_handler = try event.SimpleEventHandler(App).createWithIid(alloc, self, &onTabCloseRequested, &com.IID_TypedEventHandler_TabCloseRequested);
            self.tab_close_token = try tab_view.?.AddTabCloseRequested(self.tab_close_handler.?.comPtr());
            log.info("initXaml step 7.5: TabCloseRequested handler registered", .{});
        }
        if (self.debug_cfg.enable_handler_addtab) {
            self.add_tab_handler = try event.SimpleEventHandler(App).createWithIid(alloc, self, &onAddTabButtonClick, &com.IID_TypedEventHandler_AddTabButtonClick);
            self.add_tab_token = try tab_view.?.AddAddTabButtonClick(self.add_tab_handler.?.comPtr());
            log.info("initXaml step 7.5: AddTabButtonClick handler registered", .{});
        }
        if (self.debug_cfg.enable_handler_selection) {
            self.selection_changed_handler = try event.SimpleEventHandler(App).createWithIid(alloc, self, &onSelectionChanged, &com.IID_SelectionChangedEventHandler);
            self.selection_changed_token = try tab_view.?.AddSelectionChanged(self.selection_changed_handler.?.comPtr());
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
    if (self.tab_close_token) |tok| tab_view.RemoveTabCloseRequested(tok) catch {};
    if (self.add_tab_token) |tok| tab_view.RemoveAddTabButtonClick(tok) catch {};
    if (self.selection_changed_token) |tok| tab_view.RemoveSelectionChanged(tok) catch {};
    self.tab_close_token = null;
    self.add_tab_token = null;
    self.selection_changed_token = null;
}

/// Performs real-value verification of the WinUI 3 UI tree.
/// Maps to the 5 critical test cases defined for parity with macOS/GTK.
fn validateTabViewParity(self: *App) !void {
    log.info("validateTabViewParity: starting audit...", .{});
    const window = self.window orelse return error.NoWindow;

    // Canonical Step 1: RootGrid set as Window.Content, tab_content_grid exists.
    if (self.debug_cfg.enable_tabview) {
        _ = self.tab_view orelse {
            log.err("PARITY_FAIL: step1_create_tabview_root", .{});
            return error.ParityFail;
        };
        _ = self.tab_content_grid orelse {
            log.err("PARITY_FAIL: step1_tab_content_grid_exists", .{});
            return error.ParityFail;
        };
        const content = try window.Content();
        if (content) |c| {
            var content_guard = winrt.ComRef(winrt.IInspectable).init(@as(*winrt.IInspectable, @ptrCast(c)));
            defer content_guard.deinit();
            // Window.Content should be a Grid (RootGrid), not TabView directly.
            var grid_guard = winrt.ComRef(com.IGrid).init(content_guard.get().queryInterface(com.IGrid) catch {
                log.err("PARITY_FAIL: step1_window_content_is_rootgrid", .{});
                return error.ParityFail;
            });
            defer grid_guard.deinit();
        } else {
            log.err("PARITY_FAIL: step1_window_content_non_null", .{});
            return error.ParityFail;
        }
        log.info("validate: [PASS] step1_rootgrid_architecture", .{});
    }

    // Canonical Step 2: register handlers before first tab realization.
    if (self.tab_view != null and self.debug_cfg.enable_tabview_handlers) {
        const close_ok = self.tab_close_token != null;
        const add_ok = self.add_tab_token != null;
        const selection_ok = if (self.debug_cfg.enable_handler_selection) self.selection_changed_token != null else true;
        if (!(close_ok and add_ok and selection_ok)) {
            log.err("PARITY_FAIL: step2_handlers_registered_before_first_tab", .{});
            return error.ParityFail;
        }
        log.info("validate: [PASS] step2_handlers_registered_before_first_tab", .{});
    }

    // Canonical Step 3-5: first item exists, selected, and content attached.
    if (self.tab_view) |tv| {
        const items_vec: *com.IVector = @ptrCast(@alignCast(try tv.TabItems()));
        var items_guard = winrt.ComRef(com.IVector).init(items_vec);
        defer items_guard.deinit();
        const size = try items_guard.get().getSize();
        if (size == 0) {
            log.err("PARITY_FAIL: step3_first_tab_created", .{});
            return error.ParityFail;
        }
        log.info("validate: [PASS] step3_first_tab_created", .{});

        const selected_idx = try tv.SelectedIndex();
        if (selected_idx < 0) {
            log.err("PARITY_FAIL: step5_selected_index_valid", .{});
            return error.ParityFail;
        }
        log.info("validate: [PASS] step5_selected_index_valid", .{});

        const first_item_insp = try items_guard.get().getAt(0);
        var first_item_guard = winrt.ComRef(com.ITabViewItem).init(
            try @as(*winrt.IInspectable, @ptrCast(@alignCast(first_item_insp))).queryInterface(com.ITabViewItem),
        );
        defer first_item_guard.deinit();

        var content_control_guard = winrt.ComRef(com.IContentControl).init(try first_item_guard.get().queryInterface(com.IContentControl));
        defer content_control_guard.deinit();
        const content = try content_control_guard.get().Content();
        if (content) |c| {
            var content_guard = winrt.ComRef(winrt.IInspectable).init(@as(*winrt.IInspectable, @ptrCast(c)));
            defer content_guard.deinit();
        } else {
            log.err("PARITY_FAIL: step4_first_tab_has_content", .{});
            return error.ParityFail;
        }
        log.info("validate: [PASS] step4_first_tab_has_content", .{});
    }

    // Canonical Step 6: Loaded/SizeChanged lifecycle tokens exist on initial surface.
    if (self.debug_cfg.enable_tabview and self.surfaces.items.len > 0) {
        const surf = self.surfaces.items[0];
        if (surf.loaded_token == 0 or surf.size_changed_token == 0) {
            log.err("PARITY_FAIL: step6_loaded_sizechanged_lifecycle_registered", .{});
            return error.ParityFail;
        }
        log.info("validate: [PASS] step6_loaded_sizechanged_lifecycle_registered", .{});
    }

    // tabview_disabled_uses_single_view
    if (!self.debug_cfg.enable_tabview) {
        if (self.tab_view != null) {
            log.err("PARITY_FAIL: tabview_not_disabled", .{});
            return error.ParityFail;
        }
        const content = try window.Content();
        if (content) |c| {
            var content_guard = winrt.ComRef(winrt.IInspectable).init(@as(*winrt.IInspectable, @ptrCast(c)));
            defer content_guard.deinit();
            // In single view, it should be a Grid/Border or SwapChainPanel directly
            const is_tabview = if (content_guard.get().queryInterface(com.ITabView)) |content_tv| blk: {
                var content_tv_guard = winrt.ComRef(com.ITabView).init(content_tv);
                defer content_tv_guard.deinit();
                break :blk true;
            } else |_| false;
            if (is_tabview) {
                log.err("PARITY_FAIL: single_view_is_tabview", .{});
                return error.ParityFail;
            }
        }
        log.info("validate: [PASS] tabview_disabled_uses_single_view", .{});
    }

    log.info("validateTabViewParity: ALL CHECKS PASSED", .{});
}

/// Closed event callback — triggered when the user closes the window.
fn onWindowClosed(self: *App, _: ?*anyopaque, _: ?*anyopaque) void {
    fileLog("onWindowClosed called! stage={s} exit_intent={s}", .{
        startupStageLabel(self.startup_stage),
        exitIntentLabel(self.exit_intent),
    });
    self.close_event_seen = true;
    self.setExitIntent(.window_closed);

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
        xa.Exit() catch {};
    }
}

/// D3D11 doesn't use GL context — no-op for WinUI 3.
pub fn releaseGLContext(_: *App) void {}

/// D3D11 doesn't use GL context — no-op for WinUI 3.
pub fn makeGLContextCurrent(_: *App) !void {}

pub fn run(self: *App) !void {
    // Get Application statics to call Start().
    const app_class = try winrt.hstring(XamlClass.Application);
    defer winrt.deleteHString(app_class);
    var statics_guard = winrt.ComRef(com.IApplicationStatics).init(try winrt.getActivationFactory(com.IApplicationStatics, app_class));
    defer statics_guard.deinit();
    const statics = statics_guard.get();

    // Create the initialization callback (stack-allocated, used synchronously by Start).
    var callback = InitCallback.create(self);

    // Application.Start() calls our callback to create the Window,
    // then enters the XAML message loop. It blocks until the app exits.
    log.info("Calling Application.Start()...", .{});
    try statics.Start(callback.comPtr());
    log.info(
        "Application.Start() returned (startup={s} bootstrapped={} parity={} close_event={} exit_intent={s})",
        .{
            startupStageLabel(self.startup_stage),
            self.startup_bootstrapped,
            self.parity_verified,
            self.close_event_seen,
            exitIntentLabel(self.exit_intent),
        },
    );

    // CRITICAL: Perform full cleanup while WinRT is still active but after loop exit.
    self.fullCleanup();
}

pub fn terminate(self: *App) void {
    log.info("Termination requested", .{});
    if (self.control_plane) |cp| {
        cp.destroy();
        self.control_plane = null;
    }
    self.setExitIntent(.terminate);
    self.running = false;
    // Signal XAML to exit the message loop.
    if (self.xaml_app) |xa| {
        xa.Exit() catch {};
    }
}

fn fullCleanup(self: *App) void {
    log.info(
        "Starting full cleanup (startup={s} bootstrapped={} parity={} close_event={} exit_intent={s})",
        .{
            startupStageLabel(self.startup_stage),
            self.startup_bootstrapped,
            self.parity_verified,
            self.close_event_seen,
            exitIntentLabel(self.exit_intent),
        },
    );
    const alloc = self.core_app.alloc;

    // 0. Stop control plane before surfaces are destroyed.
    if (self.control_plane) |cp| {
        cp.destroy();
        self.control_plane = null;
    }

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
        if (self.closed_token) |tok| window.RemoveClosed(tok) catch {};
    }

    // 4. Release COM objects properly.
    if (self.closed_handler) |h| h.release();
    if (self.tab_close_handler) |h| h.release();
    if (self.add_tab_handler) |h| h.release();
    if (self.selection_changed_handler) |h| h.release();

    if (self.tab_content_grid) |tcg| { _ = tcg.release(); self.tab_content_grid = null; }
    if (self.tab_view) |tv| tv.release();
    if (self.window) |window| window.release();
    if (self.xaml_app) |xa| xa.release();
    if (self.xaml_controls_resources) |xcr| _ = xcr.release();
    self.app_outer.deinit();

    if (self.input_hwnd) |h| _ = os.DestroyWindow(h);

    // Release DispatcherQueueController last — it owns the message loop infrastructure.
    if (self.dq_controller) |dqc| {
        _ = dqc.release();
        self.dq_controller = null;
    }

    log.info("Cleanup complete.", .{});
}

/// Thread-safe wakeup: any thread can call this to unblock the event loop.
pub fn wakeup(self: *App) void {
    if (self.hwnd) |hwnd| {
        _ = os.PostMessageW(hwnd, os.WM_USER, 0, 0);
    }
}

pub fn requestCloseWindow(self: *App) void {
    fileLog("requestCloseWindow called! stage={s} exit_intent={s}", .{
        startupStageLabel(self.startup_stage),
        exitIntentLabel(self.exit_intent),
    });
    self.running = false;
    if (self.window) |window| {
        window.close() catch |err| {
            log.warn("requestCloseWindow: IWindow.Close failed: {}", .{err});
            if (self.xaml_app) |xa| xa.Exit() catch {};
        };
        return;
    }
    if (self.xaml_app) |xa| xa.Exit() catch {};
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    switch (action) {
        .quit => {
            fileLog("performAction: .quit", .{});
            self.setExitIntent(.quit_action);
            self.running = false;
            if (self.xaml_app) |xa| {
                xa.Exit() catch {};
            }
            return true;
        },
        .new_window => {
            // MVP: single window only
            return false;
        },
        .close_all_windows => {
            fileLog("performAction: .close_all_windows", .{});
            self.setExitIntent(.close_all_windows);
            self.running = false;
            if (self.xaml_app) |xa| {
                xa.Exit() catch {};
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
                const new_idx = tab_index.computeGotoIndex(self.active_surface_idx, tab_count, value);
                tv.SetSelectedIndex(@intCast(new_idx)) catch {};
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
        .command_finished => {
            switch (target) {
                .app => return true,
                .surface => |core| return core.rt_surface.commandFinished(value),
            }
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
        .scrollbar => {
            switch (target) {
                .app => {},
                .surface => |core| {
                    log.debug("performAction: scrollbar total={} offset={} len={}", .{ value.total, value.offset, value.len });
                    core.rt_surface.updateScrollbarUi(value.total, value.offset, value.len);
                },
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
    return tab_manager.newTab(self, XamlClass.TabViewItem, InitialTabTitle);
}

/// Close the active tab and its surface.
pub fn closeActiveTab(self: *App) void {
    if (tab_manager.closeActiveTab(self)) {
        log.info("closeActiveTab: no tabs remain, requesting app exit", .{});
        self.running = false;
        if (self.xaml_app) |xa| xa.Exit() catch {};
    }
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
        // TabView -> single panel: tear down RootGrid, set panel as Window.Content directly.
        log.info("toggleTabViewContainer: tab->single start", .{});
        self.unregisterTabViewHandlers(tv);

        // Remove panel from tab_content_grid first.
        if (self.tab_content_grid) |tcg| {
            if (tcg.queryInterface(com.IPanel)) |p| {
                defer p.release();
                if (p.Children()) |c_raw| {
                    const c: *com.IVector = @ptrCast(@alignCast(c_raw));
                    defer c.release();
                    c.clear() catch {};
                } else |_| {}
            } else |_| {}
            _ = tcg.release();
            self.tab_content_grid = null;
        }

        if (tv.TabItems()) |tab_items| {
            const tab_items_vec: *com.IVector = @ptrCast(@alignCast(tab_items));
            var tab_items_guard = winrt.ComRef(com.IVector).init(tab_items_vec);
            defer tab_items_guard.deinit();
            if ((tab_items_guard.get().getSize() catch 0) > 0) {
                tab_items_guard.get().removeAt(0) catch {};
            }
        } else |_| {}

        window.SetContent(null) catch {};
        window.SetContent(@ptrCast(panel)) catch |err| {
            log.warn("toggleTabViewContainer: window.SetContent(panel) failed: {}", .{err});
            return err;
        };

        if (surface.tab_view_item_inspectable) |tvi| {
            _ = tvi.release();
            surface.tab_view_item_inspectable = null;
        }
        tv.release();
        self.tab_view = null;
        self.active_surface_idx = 0;
        surface.rebindSwapChain();
        input_runtime.focusKeyboardTarget(self);
        log.info("toggleTabViewContainer: switched to single-panel mode", .{});
        return;
    }

    // single panel -> TabView: create RootGrid with Issue #28 architecture.
    log.info("toggleTabViewContainer: single->tab start", .{});

    // Remove panel from Window.Content before re-parenting.
    window.SetContent(null) catch {};

    // Use tabview_runtime.createRoot to build the RootGrid.
    const tv = try self.createTabViewRoot(window) orelse return error.AppInitFailed;
    self.tab_view = tv;
    self.active_surface_idx = 0;
    self.registerTabViewHandlers(tv) catch |err| {
        log.warn("toggleTabViewContainer: register handlers failed: {}", .{err});
    };

    // Create TabViewItem with dummy Border.
    const tvi_inspectable = try self.activateXamlType(XamlClass.TabViewItem);
    var tvi_guard = winrt.ComRef(com.ITabViewItem).init(try tvi_inspectable.queryInterface(com.ITabViewItem));
    defer tvi_guard.deinit();
    const tvi = tvi_guard.get();

    const initial_title = try winrt.hstring("Terminal");
    defer winrt.deleteHString(initial_title);
    var boxed_title_guard = winrt.ComRef(winrt.IInspectable).init(try self.boxString(initial_title));
    defer boxed_title_guard.deinit();
    tvi.SetHeader(boxed_title_guard.get()) catch |err| {
        log.warn("toggleTabViewContainer: tvi.putHeader failed: {}", .{err});
        return err;
    };
    tvi.SetIsClosable(false) catch |err| {
        log.warn("toggleTabViewContainer: tvi.putIsClosable failed: {}", .{err});
        return err;
    };

    // Dummy Border in TabViewItem.Content.
    const border_class = try winrt.hstring(XamlClass.Border);
    defer winrt.deleteHString(border_class);
    var border_guard = winrt.ComRef(winrt.IInspectable).init(try winrt.activateInstance(border_class));
    defer border_guard.deinit();
    surface_binding.setTabItemContent(tvi_inspectable, border_guard.get()) catch |err| {
        log.warn("toggleTabViewContainer: setTabItemContent failed: {}", .{err});
        return err;
    };

    const tab_items_ptr2: *com.IVector = @ptrCast(@alignCast(try tv.TabItems()));
    var tab_items_guard = winrt.ComRef(com.IVector).init(tab_items_ptr2);
    defer tab_items_guard.deinit();
    tab_items_guard.get().append(@ptrCast(tvi_inspectable)) catch |err| {
        log.warn("toggleTabViewContainer: tab_items.append failed: {}", .{err});
        return err;
    };
    tv.SetSelectedIndex(0) catch |err| {
        log.warn("toggleTabViewContainer: putSelectedIndex failed: {}", .{err});
        return err;
    };

    if (surface.tab_view_item_inspectable) |old| _ = old.release();
    surface.tab_view_item_inspectable = tvi_inspectable;

    // Place SwapChainPanel into tab_content_grid.
    self.attachSurfaceToTabItem(null, 0) catch |err| {
        log.warn("toggleTabViewContainer: attachSurfaceToTabItem failed: {}", .{err});
    };

    surface.rebindSwapChain();
    input_runtime.focusKeyboardTarget(self);
    log.info("toggleTabViewContainer: switched to TabView mode (Issue #28 RootGrid)", .{});
    if (self.hwnd) |hwnd| {
        var rect: os.RECT = .{};
        if (os.GetClientRect(hwnd, &rect) != 0) {
            const w = rect.right - rect.left;
            const h = rect.bottom - rect.top;
            _ = os.SetWindowPos(hwnd, null, 0, 0, w + 1, h, os.SWP_NOMOVE | os.SWP_NOZORDER | os.SWP_NOACTIVATE);
            _ = os.SetWindowPos(hwnd, null, 0, 0, w, h, os.SWP_NOMOVE | os.SWP_NOZORDER | os.SWP_NOACTIVATE);
            log.info("toggleTabViewContainer: forced Win32-level resize refresh", .{});
        }
    }
}

/// Close a specific tab by index.
pub fn closeTab(self: *App, idx: usize) void {
    if (tab_manager.closeTab(self, idx)) {
        log.info("closeTab: no tabs remain, requesting app exit", .{});
        self.running = false;
        if (self.xaml_app) |xa| xa.Exit() catch {};
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

/// Switch to a specific tab by index.
pub fn switchToTab(self: *App, idx: usize) void {
    if (idx >= self.surfaces.items.len) return;
    if (self.tab_view) |tv| {
        tv.SetSelectedIndex(@intCast(idx)) catch {};
        const prev_idx = self.active_surface_idx;
        self.active_surface_idx = idx;
        surface_binding.attachSurfaceToTabItem(self, prev_idx, idx) catch |err| {
            log.warn("switchToTab: attachSurfaceToTabItem({}) failed: {}", .{ idx, err });
        };
        input_runtime.focusKeyboardTarget(self);
    }
}

/// Get the currently active Surface, or null if none.
pub fn activeSurface(self: *App) ?*Surface {
    if (self.surfaces.items.len == 0) return null;
    if (!tab_index.isValid(self.active_surface_idx, self.surfaces.items.len)) return null;
    return self.surfaces.items[self.active_surface_idx];
}

// ---------------------------------------------------------------
// Control plane capture callbacks
// ---------------------------------------------------------------

fn controlPlaneCaptureState(ctx: *anyopaque, allocator: Allocator, tab_idx: ?usize) !?ControlPlane.StateSnapshot {
    const self: *App = @ptrCast(@alignCast(ctx));
    const surface = if (tab_idx) |idx|
        (if (idx < self.surfaces.items.len) self.surfaces.items[idx] else null)
    else
        self.activeSurface();
    const s = surface orelse return null;
    return .{
        .pwd = try s.pwd(allocator),
        .has_selection = s.hasSelection(),
        .at_prompt = s.cursorIsAtPrompt(),
        .tab_count = self.surfaces.items.len,
        .active_tab = self.active_surface_idx,
    };
}

fn controlPlaneCaptureTail(ctx: *anyopaque, allocator: Allocator, tab_idx: ?usize) !?[]u8 {
    const self: *App = @ptrCast(@alignCast(ctx));
    const surface = if (tab_idx) |idx|
        (if (idx < self.surfaces.items.len) self.surfaces.items[idx] else null)
    else
        self.activeSurface();
    const s = surface orelse return null;
    const viewport = try s.viewportString(allocator);
    return try allocator.dupe(u8, viewport);
}

fn controlPlaneCaptureTabList(ctx: *anyopaque, allocator: Allocator) !?[]u8 {
    const self: *App = @ptrCast(@alignCast(ctx));
    if (self.surfaces.items.len == 0) return null;

    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.print("LIST_TABS|{d}|{d}\n", .{ self.surfaces.items.len, self.active_surface_idx });
    for (self.surfaces.items, 0..) |surface, i| {
        const pwd_val = surface.pwd(allocator) catch null;
        defer if (pwd_val) |p| allocator.free(p);
        const title = surface.getTitle() orelse "";
        try writer.print("TAB|{d}|{s}|pwd={s}|prompt={d}|selection={d}\n", .{
            i,
            title,
            pwd_val orelse "",
            @as(u8, if (surface.cursorIsAtPrompt()) 1 else 0),
            @as(u8, if (surface.hasSelection()) 1 else 0),
        });
    }
    return try buf.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------
// TabView event callbacks
// ---------------------------------------------------------------

fn onTabCloseRequested(self: *App, sender: ?*anyopaque, args: ?*anyopaque) void {
    event_handlers.onTabCloseRequested(self, sender, args);
}

fn onAddTabButtonClick(self: *App, sender: ?*anyopaque, args: ?*anyopaque) void {
    event_handlers.onAddTabButtonClick(self, sender, args);
}

fn logPackageIdentity() void {
    var len: u32 = 0;
    const rc1 = GetCurrentPackageFullName(&len, null);
    if (rc1 == APPMODEL_ERROR_NO_PACKAGE) {
        log.info("pkgid: unpackaged (rc=15700 APPMODEL_ERROR_NO_PACKAGE)", .{});
        return;
    }
    if (rc1 != 0) {
        log.warn("pkgid: GetCurrentPackageFullName probe failed rc={} len={}", .{ rc1, len });
        return;
    }
    if (len == 0 or len > 512) {
        log.warn("pkgid: unexpected full name length={}", .{len});
        return;
    }

    var wbuf: [512]u16 = undefined;
    var len2 = len;
    const rc2 = GetCurrentPackageFullName(&len2, &wbuf);
    if (rc2 != 0 or len2 == 0) {
        log.warn("pkgid: GetCurrentPackageFullName read failed rc={} len={}", .{ rc2, len2 });
        return;
    }

    const slice = wbuf[0 .. len2 - 1];
    var utf8: [1024]u8 = undefined;
    const n = std.unicode.utf16LeToUtf8(&utf8, slice) catch {
        log.warn("pkgid: utf16->utf8 conversion failed", .{});
        return;
    };
    log.info("pkgid: packaged full={s}", .{utf8[0..n]});
}

fn onSelectionChanged(self: *App, sender: ?*anyopaque, args: ?*anyopaque) void {
    event_handlers.onSelectionChanged(self, sender, args);
}

// ---------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------

/// Set the background of a Control to a solid color.
pub fn setControlBackground(_: *App, control_insp: *winrt.IInspectable, color: com.Color) void {
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "GHOSTTY_WINUI3_DISABLE_BACKGROUNDS")) |v| {
        defer std.heap.page_allocator.free(v);
        if (std.mem.eql(u8, v, "1") or std.ascii.eqlIgnoreCase(v, "true")) {
            log.info("setControlBackground: disabled by env flag", .{});
            return;
        }
    } else |_| {}

    // SwapChainPanel background assignment can trigger InvalidOperation/E_FAIL in WinUI.
    // Skip this path entirely for SwapChainPanel and let parent containers own visuals.
    var scp_raw: ?*anyopaque = null;
    const scp_hr = control_insp.lpVtbl.QueryInterface(@ptrCast(control_insp), &com.ISwapChainPanelNative.IID, &scp_raw);
    if (scp_hr >= 0 and scp_raw != null) {
        var scp_native_guard = winrt.ComRef(com.ISwapChainPanelNative).init(@ptrCast(@alignCast(scp_raw.?)));
        defer scp_native_guard.deinit();
        log.info("setControlBackground: skip for ISwapChainPanelNative target", .{});
        return;
    }

    const brush_class = winrt.hstring(XamlClass.SolidColorBrush) catch return;
    defer winrt.deleteHString(brush_class);
    var brush_insp_guard = winrt.ComRef(winrt.IInspectable).init(winrt.activateInstance(brush_class) catch |err| {
        log.warn("setControlBackground: SolidColorBrush activation failed: {}", .{err});
        return;
    });
    defer brush_insp_guard.deinit();
    const brush_insp = brush_insp_guard.get();

    var brush_guard = winrt.ComRef(com.ISolidColorBrush).init(brush_insp.queryInterface(com.ISolidColorBrush) catch |err| {
        log.warn("setControlBackground: QI ISolidColorBrush failed: {}", .{err});
        return;
    });
    defer brush_guard.deinit();
    const brush = brush_guard.get();

    brush.SetColor(color) catch |err| {
        log.warn("setControlBackground: SetColor failed: {}", .{err});
        return;
    };

    var control_raw: ?*anyopaque = null;
    const control_hr = control_insp.lpVtbl.QueryInterface(@ptrCast(control_insp), &com.IControl.IID, &control_raw);
    if (control_hr >= 0 and control_raw != null) {
        var control_guard = winrt.ComRef(com.IControl).init(@ptrCast(@alignCast(control_raw.?)));
        defer control_guard.deinit();
        const control = control_guard.get();
        control.SetBackground(brush) catch |err| {
            log.warn("setControlBackground: IControl.putBackground failed: {}", .{err});
        };
        return;
    }

    var panel_raw: ?*anyopaque = null;
    const panel_hr = control_insp.lpVtbl.QueryInterface(@ptrCast(control_insp), &com.IPanel.IID, &panel_raw);
    if (panel_hr >= 0 and panel_raw != null) {
        var panel_guard = winrt.ComRef(com.IPanel).init(@ptrCast(@alignCast(panel_raw.?)));
        defer panel_guard.deinit();
        const panel = panel_guard.get();
        panel.SetBackground(brush) catch |err| {
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
    surface_binding.auditActiveTabBinding(self);
}

fn setTabItemContent(_: *App, tvi_insp: *winrt.IInspectable, content: ?*winrt.IInspectable) !void {
    return surface_binding.setTabItemContent(tvi_insp, content);
}

pub fn attachSurfaceToTabItem(self: *App, prev_idx_opt: ?usize, idx: usize) !void {
    return surface_binding.attachSurfaceToTabItem(self, prev_idx_opt, idx);
}

pub fn ensureVisibleSurfaceAttached(self: *App, surface: *Surface) void {
    surface_binding.ensureVisibleSurfaceAttached(self, surface);
}

pub fn activateXamlType(self: *App, comptime class_name: [:0]const u8) !*winrt.IInspectable {
    return xaml_helpers.activateXamlType(self, class_name);
}

pub fn boxString(_: *App, str: winrt.HSTRING) !*winrt.IInspectable {
    return xaml_helpers.boxString(str);
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

pub fn loadXamlResources(self: *App, xa: *com.IApplication) void {
    xaml_helpers.loadXamlResources(self, xa);
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
        window.SetTitle(h) catch {};
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
            var tvi_guard = winrt.ComRef(com.ITabViewItem).init(tvi);
            defer tvi_guard.deinit();
            // Box the string as IInspectable for the Header property.
            log.info("setTitle: boxString...", .{});
            const boxed = self.boxString(h) catch |err| {
                log.warn("setTitle: boxString failed: {}", .{err});
                return;
            };
            var boxed_guard = winrt.ComRef(winrt.IInspectable).init(boxed);
            defer boxed_guard.deinit();
            log.info("setTitle: putHeader...", .{});
            tvi_guard.get().SetHeader(boxed_guard.get()) catch {};
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
pub const subclassProc = @import("wndproc.zig").subclassProc;
pub const stowedExceptionHandler = @import("wndproc.zig").stowedExceptionHandler;
pub const showContextMenuAtCursor = @import("wndproc.zig").showContextMenuAtCursor;

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
