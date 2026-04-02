/// WinUI 3 XAML Islands application runtime for Ghostty — AppHost.
///
/// Windows Terminal architecture: CreateWindowEx + DesktopWindowXamlSource
/// with NonClientIslandWindow for custom titlebar (DWM frame extension).
///
/// Key differences from winui3/App.zig:
///   - No IWindow — uses NonClientIslandWindow (own HWND + XAML Islands)
///   - No subclassing — wndproc is in nonclient_island_window.zig
///   - Window activation via ShowWindow/SetForegroundWindow (not IWindow.activate)
///   - XAML content set via DesktopWindowXamlSource.setContent (not IWindow.SetContent)
const App = @This();

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const windows = std.os.windows;
const build_config = @import("../../build_config.zig");
const apprt = @import("../../apprt.zig");
const CoreApp = @import("../../App.zig");
const CoreSurface = @import("../../Surface.zig");
const configpkg = @import("../../config.zig");
const input = @import("../../input.zig");
const Surface = @import("Surface.zig").Surface(App);
const key = @import("key.zig");
const winrt = @import("winrt.zig");
const bootstrap = @import("bootstrap.zig");
const com = @import("com.zig");
const gen = @import("com_generated.zig");
const os = @import("os.zig");
const com_aggregation = @import("com_aggregation.zig");
const ime = @import("ime.zig");
const debug_harness = @import("debug_harness.zig");
const tabview_runtime = @import("tabview_runtime.zig");
const profile_menu = @import("profile_menu.zig");
const tab_index = @import("tab_index.zig");
const tab_manager = @import("tab_manager.zig");
const input_runtime = @import("input_runtime.zig");
const caption_buttons_mod = @import("caption_buttons.zig");
const xaml_helpers = @import("xaml_helpers.zig");
const surface_binding = @import("surface_binding.zig");
const event_handlers = @import("event_handlers.zig");
const control_plane_mod = @import("control_plane.zig");
const ControlPlaneNative = control_plane_mod.ControlPlane;
const CpQuery = control_plane_mod.CpQuery;
const nonclient_island_window = @import("nonclient_island_window.zig");
const NonClientIslandWindow = nonclient_island_window.NonClientIslandWindow;
const Tsf = @import("tsf.zig");
const tsf_logic = @import("tsf_logic.zig");
const IpcServer = @import("ipc.zig");

const log = std.log.scoped(.winui3);

fn postMessageWarn(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM, msg_name: []const u8) bool {
    const result = os.PostMessageW(hwnd, msg, wparam, lparam);
    if (result == 0) {
        log.warn("PostMessageW failed msg={s} err={}", .{ msg_name, os.GetLastError() });
        return false;
    }
    return true;
}

/// Timer ID for live resize preview.
const RESIZE_TIMER_ID: usize = 1;
const TAB_CLOSE_POLL_INTERVAL_MS: u32 = 500;
const CLOSE_TAB_POLL_TIMER_ID: usize = 997;
const CLOSE_TAB_TIMER_ID: usize = 998;
const CLOSE_TIMER_ID: usize = 999;
const DUMP_VT_TIMER_ID: usize = 0xDEAD; // for debug VT dumps
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
    const VisualTreeHelper = "Microsoft.UI.Xaml.Media.VisualTreeHelper";
    const XamlControlsResources = "Microsoft.UI.Xaml.Controls.XamlControlsResources";
    const XamlMetadataProvider = "Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider";
    const SplitButton = "Microsoft.UI.Xaml.Controls.SplitButton";
    const MenuFlyout = "Microsoft.UI.Xaml.Controls.MenuFlyout";
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
    ime_text_box,
};

const TypedHandler = gen.TypedEventHandlerImpl(App, *const fn (*App, ?*anyopaque, ?*anyopaque) void);
const SelectionHandler = gen.SelectionChangedEventHandlerImpl(App, *const fn (*App, ?*anyopaque, ?*anyopaque) void);
const ResourceManagerRequestedHandler = gen.TypedEventHandlerImpl(App, *const fn (*App, ?*anyopaque, ?*anyopaque) void);

/// The core application.
core_app: *CoreApp,
debug_cfg: if (builtin.mode == .Debug) debug_harness.RuntimeDebugConfig else void = if (builtin.mode == .Debug) .{} else {},
/// COM aggregation outer object that implements IXamlMetadataProvider.
/// Must be kept alive for the lifetime of the Application.
app_outer: AppOuter = undefined,

/// The WinUI 3 Application instance (needed for calling Exit() on shutdown).
xaml_app: ?*com.IApplication = null,
xaml_controls_resources: ?*winrt.IInspectable = null,

/// NonClientIslandWindow — owns the HWND and DesktopWindowXamlSource.
nci_window: ?*NonClientIslandWindow = null,

/// The native HWND (alias for nci_window.island.hwnd).
hwnd: ?os.HWND = null,

/// Our own input HWND — kept as a transparent child window for fallback/native
/// behaviors, but no longer the default keyboard text owner.
input_hwnd: ?os.HWND = null,

/// Desired keyboard focus owner. With direct TSF, focus stays on the
/// SwapChainPanel — TSF is associated with the main HWND and handles
/// IME composition directly without needing the TextBox.
keyboard_focus_target: KeyboardFocusTarget = .xaml_surface,
ime_composing: bool = false,
ime_last_had_result: bool = false,

/// All surfaces (one per tab).
surfaces: std.ArrayListUnmanaged(*Surface) = .{},

/// Index of the currently active/selected tab.
active_surface_idx: usize = 0,

/// Monotonic counter for stable tab IDs (never reused across tab close/create cycles).
next_tab_id: u64 = 1,

/// Guard flag: true while newTab/closeTab are mutating tab state.
/// onSelectionChanged skips updateSelectedTab while this is true.
tab_mutation_in_progress: bool = false,

/// CP push: timestamp (ms) of last notifyStatus call. Throttles to 1/sec.
cp_last_notify_ts: i64 = 0,

/// The TabView control that manages tabs.
tab_view: ?*com.ITabView = null,
add_tab_split_button: ?*com.ISplitButton = null,
profile_menu_flyout: ?*com.IMenuFlyout = null,
last_polled_tab_items_size: ?u32 = null,

/// The root grid (XamlSource.Content) — must be explicitly sized on WM_SIZE.
/// Windows Terminal sets _rootGrid.Width/Height on every resize; without this,
/// XAML layout doesn't track the actual window size correctly.
root_grid: ?*winrt.IInspectable = null,

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

/// TabView event handlers.
tab_close_handler: ?*TypedHandler = null,
add_tab_handler: ?*TypedHandler = null,
selection_changed_handler: ?*SelectionHandler = null,
resource_manager_requested_handler: ?*ResourceManagerRequestedHandler = null,
tab_close_token: ?i64 = null,
add_tab_token: ?i64 = null,
selection_changed_token: ?i64 = null,
resource_manager_requested_token: ?i64 = null,
/// Optional side-channel control plane for session-aware automation.
/// Uses the Zig-native control plane (replaces Rust DLL).
control_plane: ?*ControlPlaneNative = null,

/// TSF (Text Services Framework) implementation for IME composition.
tsf_impl: ?Tsf.TsfImplementation = null,

/// Set by tsfHandleOutput when committed text is sent. Cleared by the next
/// PreviewKeyDown for VK_RETURN so the confirmation Enter doesn't leak
/// a raw newline into the PTY.
tsf_just_committed: bool = false,

/// DispatcherQueueController — must be kept alive for the lifetime of the app.
dq_controller: ?*winrt.IInspectable = null,

/// DispatcherQueue for thread-safe TryEnqueue wakeup (avoids PostMessageW deprioritization).
dispatcher_queue: ?*gen.IDispatcherQueue = null,

/// Named Pipe IPC server for cross-process communication.
ipc_server: ?*IpcServer = null,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    log.info("App.init: ENTRY (winui3)", .{});

    // Allocate a debug console so log output is visible for GUI apps.
    os.attachDebugConsole();
    log.debug("App.init: after attachDebugConsole", .{});

    // WT: BufferedPaintInit() — required once before BeginBufferedPaint in WM_PAINT.
    _ = os.BufferedPaintInit();

    // Install a Vectored Exception Handler to capture details of
    // STATUS_STOWED_EXCEPTION before the process terminates.
    _ = os.AddVectoredExceptionHandler(1, &stowedExceptionHandler);
    log.debug("App.init: after VEH install", .{});

    // Request 1ms timer resolution for smooth animation timing.
    _ = os.timeBeginPeriod(1);

    logPackageIdentity();
    log.debug("App.init: after logPackageIdentity", .{});

    // Step 1: Bootstrap the Windows App SDK runtime.
    bootstrap.init() catch |err| {
        log.err("App.init: bootstrap FAILED err={}", .{err});
        log.err("Windows App SDK bootstrap failed: {}", .{err});
        return error.AppInitFailed;
    };
    log.debug("App.init: after bootstrap.init", .{});

    // Step 2: Initialize WinRT.
    winrt.hrCheck(winrt.RoInitialize(winrt.RO_INIT_SINGLETHREADED)) catch |err| {
        log.err("App.init: RoInitialize FAILED err={}", .{err});
        log.err("RoInitialize failed: {}", .{err});
        return error.AppInitFailed;
    };
    log.debug("App.init: after RoInitialize", .{});

    // Step 3: Create a DispatcherQueue for the current thread.
    // This is required before creating any XAML objects.
    const dq_opts = winrt.DispatcherQueueOptions{};
    const dq_controller = winrt.createDispatcherQueueController(&dq_opts) catch |err| {
        log.err("App.init: DispatcherQueue FAILED err={}", .{err});
        log.err("CreateDispatcherQueueController failed: {}", .{err});
        return error.AppInitFailed;
    };
    log.debug("App.init: after DispatcherQueue", .{});

    // IDispatcherQueue QI is deferred to initXaml — XAML must be initialized first.

    self.* = .{
        .core_app = core_app,
        .debug_cfg = if (comptime builtin.mode == .Debug) debug_harness.RuntimeDebugConfig.load() else {},
        .surfaces = .{},
        .running = true,
        .dq_controller = dq_controller,
        .dispatcher_queue = null,
    };
    if (comptime builtin.mode == .Debug) {
        log.info("winui3 xaml_metadata_provider={s}", .{
            if (self.debug_cfg.use_ixaml_metadata_provider) "on" else "off",
        });
        self.debug_cfg.log(log);
    }

    // Window/UI creation happens inside run() via Application.Start(callback).
    // WinUI 3 requires Window creation on the XAML thread which is set up by Start().
    log.info("WinUI 3 Islands runtime initialized (window creation deferred to run)", .{});
    log.info("App.init: EXIT OK", .{});
}

/// COM callback entry point for Application.Start() delegate.
/// Called from com_aggregation.InitCallback.invokeFn.
pub fn onApplicationStart(self: *App) winrt.HRESULT {
    self.initXaml() catch |err| {
        log.err("initXaml failed in Application.Start callback: {}", .{err});
        return winrt.E_FAIL;
    };
    return winrt.S_OK;
}

/// Internal XAML initialization — called from onApplicationStart.
fn initXaml(self: *App) !void {
    log.info("initXaml: START (winui3)", .{});
    log.info("initXaml: creating NonClientIslandWindow inside XAML thread", .{});
    self.startup_bootstrapped = false;
    self.parity_verified = false;
    self.setStartupStage(.xaml_entered);
    errdefer self.setStartupStage(.failed);

    // Step 0: Create the Application instance via COM aggregation — UNCHANGED.
    try self.createAggregatedApplication();
    self.setStartupStage(.application_ready);

    // Step 1: Create NonClientIslandWindow (CreateWindowEx + DWM frame).
    log.debug("initXaml step 1: NonClientIslandWindow.init...", .{});
    const nci = try self.core_app.alloc.create(NonClientIslandWindow);
    errdefer self.core_app.alloc.destroy(nci);
    try nci.init(self);
    log.debug("initXaml step 1 OK: HWND=0x{x}", .{@intFromPtr(nci.island.hwnd)});

    // Step 2: Initialize DesktopWindowXamlSource with our window's WindowId.
    log.debug("initXaml step 2: island.initialize...", .{});
    try nci.island.initialize();
    log.debug("initXaml step 2 OK: DesktopWindowXamlSource initialized", .{});

    // Step 3: Create drag bar AFTER DXWS initialization.
    // WS_EX_LAYERED on child windows fails (err=183) if called before
    // the WinUI3 runtime is initialized. Deferring to after step 2.
    nci.createDragBarIfNeeded();
    if (nci.drag_bar_hwnd) |db| {
        log.debug("initXaml step 3: drag_bar_hwnd=0x{x}", .{@intFromPtr(db)});
    } else {
        log.warn("initXaml step 3: drag_bar creation FAILED", .{});
    }

    self.nci_window = nci;
    self.hwnd = nci.island.hwnd;
    self.setStartupStage(.window_ready);

    // Obtain IDispatcherQueue via GetForCurrentThread() (WT pattern).
    // DispatcherQueueController.QI fails, but the static factory works after XAML init.
    dq_init: {
        const class_name = winrt.hstring("Microsoft.UI.Dispatching.DispatcherQueue") catch |err| {
            log.warn("initXaml: hstring creation failed err={}", .{err});
            break :dq_init;
        };
        defer winrt.deleteHString(class_name);
        if (winrt.getActivationFactory(gen.IDispatcherQueueStatics, class_name)) |statics| {
            defer statics.release();
            self.dispatcher_queue = statics.getForCurrentThread() catch |err| blk: {
                log.warn("initXaml: GetForCurrentThread failed err={}, falling back to PostMessageW", .{err});
                break :blk null;
            };
            if (self.dispatcher_queue != null) {
                log.info("initXaml: IDispatcherQueue obtained via GetForCurrentThread — TryEnqueue wakeup enabled", .{});
            }
        } else |err| {
            log.warn("initXaml: DispatcherQueue activation factory failed err={}, falling back to PostMessageW", .{err});
        }
    } // dq_init

    // Step 3.5: Enable XAML debug diagnostics.
    if (self.xaml_app) |xa| {
        self.enableDebugSettings(xa);
    }

    // Step 4: Load XamlControlsResources (themes).
    if (self.xaml_app) |xa| {
        self.loadXamlResources(xa);
    }

    // Step 5: Show the window.
    _ = os.ShowWindow(self.hwnd.?, os.SW_SHOWNORMAL);
    _ = os.UpdateWindow(self.hwnd.?);
    _ = os.SetForegroundWindow(self.hwnd.?);
    log.debug("initXaml step 5: ShowWindow + SetForegroundWindow OK", .{});
    self.setStartupStage(.window_activated);

    // Step 6: Create XAML content (TabView + SwapChainPanel).
    try self.createWindowContent();
    try self.scheduleDebugActions();
    self.syncVisualDiagnostics();

    // Install caption buttons (minimize, maximize, close) in the TabView footer.
    if (self.tab_view) |tv| {
        caption_buttons_mod.install(tv, self.hwnd.?);
    }

    // Step 6.5: Re-assert drag bar Z-order after XAML content is set.
    // setContent() may internally reposition the interop HWND, pushing it
    // above the drag bar. Force interop back to BOTTOM and drag bar to TOP.
    if (self.nci_window) |nci2| {
        if (nci2.island.interop_hwnd) |ih| {
            _ = os.SetWindowPos(ih, os.HWND_BOTTOM, 0, 0, 0, 0, os.SWP_NOMOVE | os.SWP_NOSIZE | os.SWP_NOACTIVATE);
        }
        if (nci2.drag_bar_hwnd) |db| {
            _ = os.SetWindowPos(db, os.HWND_TOP, 0, 0, 0, 0, os.SWP_NOMOVE | os.SWP_NOSIZE | os.SWP_NOACTIVATE);
        }
        log.debug("initXaml step 6.5: drag bar Z-order re-asserted", .{});
    }

    // Step 7: Create native input windows (input overlay for IME).
    self.setupNativeInputWindows();

    input_runtime.focusKeyboardTarget(self);
    self.startup_bootstrapped = true;
    self.setStartupStage(.content_ready);
    log.info("initXaml: content_ready, entering message loop", .{});

    // --- IPC Server (Named Pipe) ---
    self.ipc_server = if (self.hwnd) |hwnd|
        IpcServer.init(self.core_app.alloc, hwnd) catch |err| blk: {
            log.err("IPC server init failed: {}", .{err});
            break :blk null;
        }
    else
        null;
    if (self.ipc_server != null) log.info("IPC server started", .{});

    // --- Control Plane (optional, env-gated) ---
    const cp_enabled = ControlPlaneNative.isEnabled(self.core_app.alloc);
    log.debug("control_plane: isEnabled={}", .{@intFromBool(cp_enabled)});
    if (cp_enabled) {
        log.debug("control_plane: hwnd={}", .{@intFromPtr(self.hwnd)});
        if (self.hwnd) |hwnd| {
            self.control_plane = ControlPlaneNative.create(
                self.core_app.alloc,
                hwnd,
                @ptrCast(self),
                controlPlaneCaptureState,
                controlPlaneCaptureTail,
                controlPlaneCaptureHistory,
                controlPlaneCaptureTabList,
            ) catch |err| blk: {
                log.err("control_plane: create FAILED err={s}", .{@errorName(err)});
                break :blk null;
            };
            log.info("control_plane: create OK ptr={}", .{@intFromPtr(self.control_plane)});

            // Now that CP is active, refresh tab titles and window title
            // to include the tab ID prefix and session name.
            for (self.surfaces.items) |surface| {
                if (surface.getTitle()) |t| {
                    surface.setTabTitle(t);
                }
            }
            self.syncWindowTitleToActiveSurface();
        }
    }

    // --- Parity Validation ---
    self.validateIslandsParity() catch |err| {
        log.err("validateIslandsParity: CRITICAL_FAIL: {}", .{err});
        return;
    };
    self.parity_verified = true;
    self.setStartupStage(.parity_checked);
    self.setStartupStage(.init_complete);

    // Dump visual tree after layout pass (needs message pump running).
    // Use SetTimer with 500ms delay so XAML has time to measure+arrange.
    if (comptime builtin.mode == .Debug) {
        _ = os.SetTimer(self.hwnd.?, DUMP_VT_TIMER_ID, 500, null);
    }
}

fn dumpVisualTreeRoot(self: *App) void {
    const vth_class = winrt.hstring(XamlClass.VisualTreeHelper) catch return;
    defer winrt.deleteHString(vth_class);
    var vth_guard = winrt.ComRef(com.IVisualTreeHelperStatics).init(winrt.getActivationFactory(com.IVisualTreeHelperStatics, vth_class) catch |err| {
        log.warn("dumpVisualTreeRoot: getActivationFactory failed: {}", .{err});
        return;
    });
    defer vth_guard.deinit();
    const vth = vth_guard.get();

    // The root of the visual tree in XAML Islands is the content of the DesktopWindowXamlSource.
    const xaml_source = self.nci_window.?.island.xaml_source orelse return;
    const root_raw = xaml_source.getContent() catch return;
    const root_insp: *winrt.IInspectable = @ptrCast(@alignCast(root_raw));
    defer _ = root_insp.release();
    log.info("--- VISUAL TREE DUMP START ---", .{});
    self.dumpVisualTree(vth, root_insp, 0);
    log.info("--- VISUAL TREE DUMP END ---", .{});
    // Dump surface vs panel size comparison.
    for (self.surfaces.items) |surface| {
        const ssize = surface.getSize() catch continue;
        var panel_w: f64 = 0;
        var panel_h: f64 = 0;
        if (surface.swap_chain_panel) |panel| {
            if (panel.queryInterface(com.IFrameworkElement)) |fe| {
                defer fe.release();
                panel_w = fe.ActualWidth() catch 0;
                panel_h = fe.ActualHeight() catch 0;
            } else |_| {}
        }
        const sc = @as(f64, @floatCast(surface.content_scale.x));
        log.debug("SIZE COMPARE: surface={}x{} panel_dip={d:.1}x{d:.1} panel_px={d:.0}x{d:.0} scale={d:.2}", .{
            ssize.width, ssize.height, panel_w, panel_h, panel_w * sc, panel_h * sc, sc,
        });
    }
}

fn dumpVisualTree(_: *App, vth: *com.IVisualTreeHelperStatics, element: ?*winrt.IInspectable, depth: usize) void {
    dumpVisualTreeImpl(vth, element, depth);
}

fn dumpVisualTreeImpl(vth: *com.IVisualTreeHelperStatics, element: ?*winrt.IInspectable, depth: usize) void {
    const elem = element orelse return;

    // Get runtime class name
    var name_hstr: ?winrt.HSTRING = null;
    const hr = elem.lpVtbl.GetRuntimeClassName(elem, &name_hstr);
    if (hr == 0) {
        if (name_hstr) |hs| {
            defer winrt.deleteHString(hs);
            const slice16 = winrt.hstringSliceRaw(hs);
            var utf8_buf: [256]u8 = undefined;
            const n = std.unicode.utf16LeToUtf8(&utf8_buf, slice16) catch 0;
            const name = if (n > 0) utf8_buf[0..n] else "Unknown";
            // Get ActualWidth/ActualHeight via IFrameworkElement
            var aw: f64 = -1;
            var ah: f64 = -1;
            if (elem.queryInterface(com.IFrameworkElement)) |fe| {
                defer fe.release();
                aw = fe.ActualWidth() catch -1;
                ah = fe.ActualHeight() catch -1;
            } else |_| {}
            log.debug("VT[{d}] {s} actual={d:.1}x{d:.1}", .{ depth, name, aw, ah });
        } else {
            log.debug("VT[{d}] <null-name>", .{depth});
        }
    } else {
        log.debug("VT[{d}] <no-name>", .{depth});
    }

    // QI for IDependencyObject — VisualTreeHelper methods require IDependencyObject, not IInspectable.
    const dep_obj = elem.queryInterface(com.IDependencyObject) catch {
        log.debug("VT[{d}] QI IDependencyObject failed", .{depth});
        return;
    };
    defer dep_obj.release();

    const count = vth.getChildrenCount(dep_obj) catch |err| blk: {
        log.debug("VT[{d}] getChildrenCount FAILED: {}", .{ depth, @intFromError(err) });
        break :blk @as(i32, 0);
    };
    log.debug("VT[{d}] children={d}", .{ depth, count });
    var i: i32 = 0;
    while (i < count) : (i += 1) {
        if (vth.getChild(dep_obj, i)) |child| {
            defer child.release();
            const child_insp: *winrt.IInspectable = @ptrCast(@alignCast(child));
            dumpVisualTreeImpl(vth, child_insp, depth + 1);
        } else |_| {}
    }
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
    const app_class = try winrt.hstring(XamlClass.Application);
    defer winrt.deleteHString(app_class);
    log.info("initXaml step 0: Creating Application with COM aggregation...", .{});

    self.app_outer.init();

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

    self.xaml_app = result.instance.queryInterface(com.IApplication) catch null;
    if (self.xaml_app) |xa| {
        self.resource_manager_requested_handler = ResourceManagerRequestedHandler.createWithIid(
            self.core_app.alloc,
            self,
            &onResourceManagerRequested,
            &com.IID_TypedEventHandler_ResourceManagerRequested,
        ) catch |err| blk: {
            log.warn("failed to create ResourceManagerRequested handler: {}", .{err});
            break :blk null;
        };
        if (self.resource_manager_requested_handler) |h| {
            // IApplication2 has ResourceManagerRequested event
            const xa2 = xa.queryInterface(gen.IApplication2) catch |err| blk: {
                log.warn("failed to QI IApplication2: {}", .{err});
                break :blk null;
            };
            if (xa2) |app2| {
                self.resource_manager_requested_token = app2.AddResourceManagerRequested(h.comPtr()) catch |err| blk2: {
                    log.warn("failed to register ResourceManagerRequested handler: {}", .{err});
                    break :blk2 null;
                };
            } else {
                self.resource_manager_requested_token = null;
            }
            log.info("initXaml step 0: ResourceManagerRequested handler registered token={}", .{
                self.resource_manager_requested_token orelse -1,
            });
        }
    }
    log.info("initXaml step 0 OK: Application created with IXamlMetadataProvider", .{});
}

fn createWindowContent(self: *App) !void {
    // Create TabView root (RootGrid) using the islands-specific tabview_runtime.
    const xaml_source = self.nci_window.?.island.xaml_source orelse return error.AppInitFailed;
    const tv = try self.createTabViewRoot(xaml_source);
    self.tab_view = tv;

    if (tv) |tab_view| {
        tabview_runtime.configureDefaults(tab_view);
    }

    // Populate the profile dropdown menu with detected shells.
    if (self.profile_menu_flyout) |flyout| {
        profile_menu.populateProfileMenu(self.core_app.alloc, flyout, self) catch |err| {
            log.warn("Failed to populate profile menu: {}", .{err});
        };
    }

    // Create initial Surface and content.
    try self.createInitialSurfaceContent(tv);

    if (tv) |tab_view| {
        try self.registerTabViewHandlers(tab_view);
    }
}

fn scheduleDebugActions(self: *App) !void {
    if (comptime builtin.mode == .Debug) {
        if (self.tab_view != null and self.hwnd != null) {
            self.last_polled_tab_items_size = try self.currentTabItemsSize();
            _ = os.SetTimer(self.hwnd.?, CLOSE_TAB_POLL_TIMER_ID, TAB_CLOSE_POLL_INTERVAL_MS, null);
        }

        if (self.debug_cfg.new_tab_on_init) {
            log.info("initXaml step 10: new_tab_on_init triggered", .{});
            self.newTab() catch |err| log.warn("new_tab_on_init failed: {}", .{err});
        }

        if (self.debug_cfg.test_resize) {
            log.info("initXaml step 10: test_resize triggered", .{});
            var rect: os.RECT = .{};
            _ = os.GetClientRect(self.hwnd.?, &rect);
            const new_w: u32 = @intCast(rect.right - rect.left + 10);
            const new_h: u32 = @intCast(rect.bottom - rect.top + 10);
            _ = postMessageWarn(self.hwnd.?, os.WM_SIZE, 0, @bitCast(@as(usize, (new_h << 16) | new_w)), "WM_SIZE");
        }

        if (self.debug_cfg.close_after_ms) |ms| {
            log.info("initXaml step 10: close_after_ms={}ms scheduled", .{ms});
            _ = os.SetTimer(self.hwnd.?, CLOSE_TIMER_ID, ms, null);
        }

        if (self.debug_cfg.close_tab_after_ms) |ms| {
            log.info("initXaml step 10: close_tab_after_ms={}ms scheduled", .{ms});
            _ = os.SetTimer(self.hwnd.?, CLOSE_TAB_TIMER_ID, ms, null);
        }
    }
}

fn syncVisualDiagnostics(self: *App) void {
    // In the islands variant, window_runtime diagnostics are not applicable
    // (they use IWindow). Just log the state.
    _ = self;
    log.info("syncVisualDiagnostics: islands mode (no IWindow diagnostics)", .{});
}

fn setupNativeInputWindows(self: *App) void {
    // In XAML Islands mode, we create the input overlay but do NOT subclass
    // child windows (we own the wndproc, no subclassing needed).
    const input_overlay = @import("input_overlay.zig");
    if (self.hwnd) |hwnd| {
        self.input_hwnd = input_overlay.createInputWindow(hwnd, @intFromPtr(self));
        if (self.input_hwnd) |input_hwnd| {
            _ = os.ImmAssociateContextEx(input_hwnd, null, os.IACE_DEFAULT);
            // keyboard_focus_target stays .xaml_surface — TSF is the sole IME handler.
            log.debug("setupNativeInputWindows: input HWND=0x{x} created; text owner=xaml_surface (TSF direct)", .{@intFromPtr(input_hwnd)});
        } else {
            log.warn("setupNativeInputWindows: WARNING input_hwnd creation FAILED", .{});
        }
    }

    // Initialize TSF for IME composition display.
    // CRITICAL: Initialize directly in self.tsf_impl, NOT a local variable.
    // TSF stores pointers to our inline COM objects (&self.tsf_impl._compositionSinkObj etc.)
    // during initialize(). If we init a local and copy, those pointers become dangling.
    self.tsf_impl = Tsf.TsfImplementation{};
    self.tsf_impl.?.initialize() catch |err| {
        log.err("TSF: initialize failed: {}", .{err});
        self.tsf_impl = null;
        return;
    };
    // Wire up callbacks for text output, preedit display, and cursor positioning.
    self.tsf_impl.?._userdata = @ptrCast(self);
    self.tsf_impl.?._handleOutput = &tsfHandleOutput;
    self.tsf_impl.?._handlePreedit = &tsfHandlePreedit;
    self.tsf_impl.?._getCursorRect = &tsfGetCursorRect;
    if (self.hwnd) |h| {
        self.tsf_impl.?.associateFocus(h);
    }
    log.info("setupNativeInputWindows: TSF initialized OK", .{});
}

// ---------------------------------------------------------------
// TSF callback infrastructure
// ---------------------------------------------------------------

/// TSF callback: finalized text — send each codepoint to the active surface's PTY.
fn tsfHandleOutput(userdata: ?*anyopaque, utf8: []const u8) void {
    const app: *App = @ptrCast(@alignCast(userdata orelse return));
    const surface = app.activeSurface() orelse return;
    log.debug("TSF tsfHandleOutput: {} bytes, pending_keydown={s}", .{ utf8.len, @tagName(surface.pending_keydown) });

    // CRITICAL: Clear pending_keydown before sending TSF output.
    // When IME confirms with Enter, WM_KEYDOWN sets pending_keydown=.consumed.
    // If we don't clear it, the first handleCharEvent call will see .consumed
    // and silently drop the first character — causing "kanji missing" bug.
    surface.pending_keydown = .none;

    // Fix 3: Signal that TSF just committed text. The next VK_RETURN in
    // PreviewKeyDown will be suppressed to avoid a raw Enter leaking
    // into the PTY after IME confirmation.
    app.tsf_just_committed = true;

    // Decode UTF-8 into codepoints and send each as a UTF-16 char event,
    // which follows the same path as IME commit via handleCharEvent.
    // Logic extracted to tsf_logic.decodeAndEmitUtf16 for testability.
    const emit_fn = struct {
        // Capture surface via a global — decodeAndEmitUtf16 takes a plain fn ptr.
        threadlocal var active_surface: ?*Surface = null;
        fn emit(code_unit: u16) void {
            if (active_surface) |s| s.handleCharEvent(code_unit);
        }
    };
    emit_fn.active_surface = surface;
    _ = tsf_logic.decodeAndEmitUtf16(utf8, &emit_fn.emit);
    emit_fn.active_surface = null;
    log.debug("TSF tsfHandleOutput: done, pending_keydown={s}", .{@tagName(surface.pending_keydown)});
}

/// TSF callback: preedit text — forward to the active surface's core preedit display.
fn tsfHandlePreedit(userdata: ?*anyopaque, text: ?[]const u8) void {
    const app: *App = @ptrCast(@alignCast(userdata orelse return));
    const surface = app.activeSurface() orelse return;
    surface.core_surface.preeditCallback(text) catch |err| {
        log.err("TSF tsfHandlePreedit error: {}", .{err});
    };
}

/// TSF callback: cursor screen rect — used for IME candidate window positioning.
fn tsfGetCursorRect(userdata: ?*anyopaque) os.RECT {
    const app: *App = @ptrCast(@alignCast(userdata orelse return os.RECT{}));
    const surface = app.activeSurface() orelse return os.RECT{};
    const hwnd = app.hwnd orelse return os.RECT{};
    const ime_pos = surface.core_surface.imePoint();
    // imePoint returns pixel coordinates relative to the client area.
    // Convert to screen coordinates for TSF.
    var pt = os.POINT{ .x = @intFromFloat(ime_pos.x), .y = @intFromFloat(ime_pos.y) };
    _ = os.ClientToScreen(hwnd, &pt);
    // Use the actual cell height from imePoint for accurate positioning.
    const cell_height: i32 = if (ime_pos.height > 0) @intFromFloat(ime_pos.height) else 20;
    return os.RECT{
        .left = pt.x,
        .top = pt.y,
        .right = pt.x + 1,
        .bottom = pt.y + cell_height,
    };
}

fn createTabViewRoot(self: *App, xaml_source: *com.IDesktopWindowXamlSource) !?*com.ITabView {
    return tabview_runtime.createRoot(self, xaml_source, XamlClass.TabView);
}

fn createInitialSurfaceContent(self: *App, tab_view: ?*com.ITabView) !void {
    const alloc = self.core_app.alloc;
    if (comptime builtin.mode == .Debug) {
        if (self.debug_cfg.tabview_empty and tab_view != null) {
            log.info("initXaml step 8: SKIPPED (GHOSTTY_WINUI3_TABVIEW_EMPTY=true)", .{});
            return;
        }
    }

    log.info("initXaml step 8: Creating initial Surface...", .{});
    var config = try configpkg.Config.load(alloc);
    defer config.deinit();

    var surface = try alloc.create(Surface);
    errdefer alloc.destroy(surface);
    try surface.init(self, self.core_app, &config, null);
    errdefer surface.deinit();

    // Assign a stable monotonic tab ID (same as newTabWithProfile).
    surface.tab_id = self.next_tab_id;
    self.next_tab_id += 1;

    try self.surfaces.append(alloc, surface);

    if (self.hwnd) |hwnd| {
        var rect: os.RECT = .{};
        _ = os.GetClientRect(hwnd, &rect);
        // Convert physical pixels to DIPs for STRETCH swap chain.
        const dpi_init = os.GetDpiForWindow(hwnd);
        const sc_init: f64 = @as(f64, @floatFromInt(dpi_init)) / 96.0;
        const w: u32 = @intFromFloat(@as(f64, @floatFromInt(rect.right - rect.left)) / sc_init);
        const h: u32 = @intFromFloat(@as(f64, @floatFromInt(rect.bottom - rect.top)) / sc_init);
        if (w > 0 and h > 0) {
            surface.updateSize(w, h);
            log.info("initXaml step 8: synced surface size to {}x{} (DIP)", .{ w, h });
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
        const use_content = if (comptime builtin.mode == .Debug) !self.debug_cfg.tabview_item_no_content else true;
        if (use_content) {
            var cc_guard = winrt.ComRef(com.IContentControl).init(try tvi_inspectable.queryInterface(com.IContentControl));
            defer cc_guard.deinit();
            const border_class = try winrt.hstring(XamlClass.Border);
            defer winrt.deleteHString(border_class);
            var border_guard = winrt.ComRef(winrt.IInspectable).init(try winrt.activateInstance(border_class));
            defer border_guard.deinit();
            try cc_guard.get().SetContent(@as(?*anyopaque, @ptrCast(border_guard.get())));
            log.info("initXaml step 8: TabViewItem dummy Border content set", .{});
        }

        if (comptime builtin.mode == .Debug) {
            if (!self.debug_cfg.tabview_append_item) {
                log.info("initXaml step 8: STOP at level 1 (no append)", .{});
                return;
            }
        }

        const tab_items_ptr: *com.IVector = @ptrCast(@alignCast(try tv.TabItems()));
        var tab_items_guard = winrt.ComRef(com.IVector).init(tab_items_ptr);
        defer tab_items_guard.deinit();
        try tab_items_guard.get().append(@ptrCast(tvi_inspectable));
        surface.tab_view_item_inspectable = tvi_inspectable;

        const items_size = try tab_items_guard.get().getSize();
        log.info("initXaml step 8: TabViewItem appended, TabItems.size={}", .{items_size});

        if (comptime builtin.mode == .Debug) {
            if (!self.debug_cfg.tabview_select_first) {
                log.info("initXaml step 8: STOP at level 2 (no selectedIndex)", .{});
                return;
            }
        }

        try tv.SetSelectedIndex(0);

        surface_binding.updateSelectedTab(self, 0);
        log.info("initXaml step 8: surface panel added via updateSelectedTab", .{});
    } else {
        // Single-panel mode: SwapChainPanel directly as XamlSource content.
        const xaml_source = self.nci_window.?.island.xaml_source orelse return error.AppInitFailed;
        try xaml_source.setContent(@as(?*anyopaque, @ptrCast(panel)));
        log.info("initXaml step 8 OK: SwapChainPanel set as XamlSource content (single-tab)", .{});
    }
}

fn registerTabViewHandlers(self: *App, tab_view: ?*com.ITabView) !void {
    const enable_handlers = if (comptime builtin.mode == .Debug) self.debug_cfg.enable_tabview_handlers else true;
    if (tab_view != null and enable_handlers) {
        const alloc = self.core_app.alloc;
        const enable_close = if (comptime builtin.mode == .Debug) self.debug_cfg.enable_handler_close else true;
        if (enable_close) {
            self.tab_close_handler = try TypedHandler.createWithIid(alloc, self, &onTabCloseRequested, &com.IID_TypedEventHandler_TabCloseRequested);
            log.debug(
                "registerTabViewHandlers: AddTabCloseRequested start tab_view=0x{x} handler=0x{x}",
                .{ @intFromPtr(tab_view.?), @intFromPtr(self.tab_close_handler.?) },
            );
            self.tab_close_token = try tab_view.?.AddTabCloseRequested(self.tab_close_handler.?.comPtr());
            log.debug("registerTabViewHandlers: AddTabCloseRequested success token={}", .{self.tab_close_token.?});
            log.info("initXaml step 7.5: TabCloseRequested handler registered", .{});
        }
        const enable_addtab = if (comptime builtin.mode == .Debug) self.debug_cfg.enable_handler_addtab else true;
        if (enable_addtab) {
            self.add_tab_handler = try TypedHandler.createWithIid(alloc, self, &onAddTabButtonClick, &com.IID_TypedEventHandler_AddTabButtonClick);
            self.add_tab_token = try tab_view.?.AddAddTabButtonClick(self.add_tab_handler.?.comPtr());
            log.info("initXaml step 7.5: AddTabButtonClick handler registered", .{});
        }
        const enable_selection = if (comptime builtin.mode == .Debug) self.debug_cfg.enable_handler_selection else true;
        if (enable_selection) {
            self.selection_changed_handler = try SelectionHandler.createWithIid(alloc, self, &onSelectionChanged, &com.IID_SelectionChangedEventHandler);
            self.selection_changed_token = try tab_view.?.AddSelectionChanged(self.selection_changed_handler.?.comPtr());
            log.info("initXaml step 7.5: SelectionChanged handler registered", .{});
        }
        log.info("initXaml step 7.5 OK: TabView event handlers registered (close={} addtab={} selection={})", .{
            enable_close,
            enable_addtab,
            enable_selection,
        });
    } else if (tab_view != null) {
        if (comptime builtin.mode == .Debug) {
            log.info("initXaml step 7.5: TabView event handlers SKIPPED (GHOSTTY_WINUI3_ENABLE_TABVIEW_HANDLERS=false)", .{});
        }
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

fn currentTabItemsSize(self: *App) !u32 {
    const tv = self.tab_view orelse return 0;
    const items_vec: *com.IVector = @ptrCast(@alignCast(try tv.TabItems()));
    var items_guard = winrt.ComRef(com.IVector).init(items_vec);
    defer items_guard.deinit();
    return try items_guard.get().getSize();
}

fn pollTabCloseState(self: *App) void {
    const current_size = self.currentTabItemsSize() catch |err| {
        log.warn("pollTabCloseState: currentTabItemsSize failed err={}", .{@intFromError(err)});
        return;
    };
    const previous_size = self.last_polled_tab_items_size orelse current_size;
    self.last_polled_tab_items_size = current_size;

    if (current_size < previous_size and current_size < self.surfaces.items.len) {
        log.debug(
            "pollTabCloseState: size decreased prev={} current={} surfaces={}, closing active tab",
            .{ previous_size, current_size, self.surfaces.items.len },
        );
        self.closeActiveTab();
        self.last_polled_tab_items_size = self.currentTabItemsSize() catch current_size;
    }
}

/// Islands-specific parity validation (simplified — no IWindow.Content check).
fn validateIslandsParity(self: *App) !void {
    if (comptime builtin.mode == .Debug) {
        log.info("validateIslandsParity: starting audit...", .{});

        // Check that nci_window and hwnd are set.
        _ = self.nci_window orelse {
            log.err("PARITY_FAIL: nci_window is null", .{});
            return error.ParityFail;
        };
        _ = self.hwnd orelse {
            log.err("PARITY_FAIL: hwnd is null", .{});
            return error.ParityFail;
        };

        // Canonical Step 1: RootGrid set as XamlSource content, tab_content_grid exists.
        if (self.debug_cfg.enable_tabview) {
            _ = self.tab_view orelse {
                log.err("PARITY_FAIL: step1_create_tabview_root", .{});
                return error.ParityFail;
            };
            _ = self.tab_content_grid orelse {
                log.err("PARITY_FAIL: step1_tab_content_grid_exists", .{});
                return error.ParityFail;
            };
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

        log.info("validateIslandsParity: ALL CHECKS PASSED", .{});
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
    if (self.ipc_server) |ipc| {
        ipc.deinit();
        self.ipc_server = null;
    }
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

/// Called when the window is being closed (from wndproc WM_CLOSE).
pub fn onWindowClose(self: *App) void {
    log.info("onWindowClose called! stage={s} exit_intent={s}", .{
        startupStageLabel(self.startup_stage),
        exitIntentLabel(self.exit_intent),
    });
    self.close_event_seen = true;
    self.setExitIntent(.window_closed);

    // Hide the window immediately so it doesn't linger as a transparent
    // rectangle while cleanup (fullCleanup / nci.close / DestroyWindow) runs.
    if (self.hwnd) |hwnd| {
        _ = os.ShowWindow(hwnd, os.SW_HIDE);
    }

    // Tear down TSF before the HWND is destroyed (TSF holds an HWND reference).
    if (self.tsf_impl) |*tsf| {
        tsf.uninitialize();
        self.tsf_impl = null;
    }

    // Tear down drag bar and input windows immediately.
    if (self.nci_window) |nci| {
        nci.destroyDragBarWindow();
    }
    if (self.input_hwnd) |input_hwnd| {
        _ = os.DestroyWindow(input_hwnd);
        self.input_hwnd = null;
    }

    self.running = false;
    // Exit the XAML message loop so Application.Start() returns cleanly.
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

    // 0. Uninitialize TSF before surfaces are destroyed (callbacks reference surfaces).
    if (self.tsf_impl) |*tsf| {
        tsf.uninitialize();
        self.tsf_impl = null;
    }

    // 0b. Stop control plane before surfaces are destroyed.
    if (self.control_plane) |cp| {
        cp.destroy();
        self.control_plane = null;
    }

    // 0c. Stop IPC server.
    if (self.ipc_server) |ipc| {
        ipc.deinit();
        self.ipc_server = null;
    }

    // 1. No subclassing to remove (we own the wndproc).

    // 2. Close all surfaces (stops threads).
    for (self.surfaces.items) |surface| {
        surface.deinit();
        alloc.destroy(surface);
    }
    self.surfaces.deinit(alloc);

    // 3. Unregister WinRT events.
    if (self.tab_view) |tv| self.unregisterTabViewHandlers(tv);
    if (self.xaml_app) |xa| {
        if (self.resource_manager_requested_token) |tok| {
            if (xa.queryInterface(gen.IApplication2)) |app2| {
                app2.RemoveResourceManagerRequested(tok) catch {};
            } else |_| {}
        }
    }

    // 4. Release COM objects properly.
    if (self.tab_close_handler) |h| h.release();
    if (self.add_tab_handler) |h| h.release();
    if (self.selection_changed_handler) |h| h.release();
    if (self.resource_manager_requested_handler) |h| h.release();

    if (self.root_grid) |rg| {
        _ = rg.release();
        self.root_grid = null;
    }
    if (self.tab_content_grid) |tcg| {
        _ = tcg.release();
        self.tab_content_grid = null;
    }
    if (self.tab_view) |tv| tv.release();

    // 5. Close the XAML Islands source and destroy the window.
    if (self.nci_window) |nci| {
        nci.close();
        alloc.destroy(nci);
        self.nci_window = null;
    }

    if (self.xaml_app) |xa| xa.release();
    if (self.xaml_controls_resources) |xcr| _ = xcr.release();
    self.app_outer.deinit();

    if (self.input_hwnd) |h| _ = os.DestroyWindow(h);

    // Release DispatcherQueue before controller.
    if (self.dispatcher_queue) |dq| {
        dq.release();
        self.dispatcher_queue = null;
    }
    WakeupHandler.g_app.store(null, .release);

    // Release DispatcherQueueController last — it owns the message loop infrastructure.
    if (self.dq_controller) |dqc| {
        _ = dqc.release();
        self.dq_controller = null;
    }

    // BufferedPaint cleanup (paired with BufferedPaintInit in init).
    _ = os.BufferedPaintUnInit();

    log.info("Cleanup complete.", .{});
}

/// Thread-safe wakeup: any thread can call this to unblock the event loop.
/// Uses DispatcherQueue.TryEnqueue to avoid OS deprioritization of background windows.
pub fn wakeup(self: *App) void {
    if (self.dispatcher_queue) |dq| {
        WakeupHandler.g_app.store(self, .release);
        _ = dq.tryEnqueue(@ptrCast(&WakeupHandler.instance)) catch {
            if (self.hwnd) |hwnd| _ = postMessageWarn(hwnd, os.WM_USER, 0, 0, "WM_USER");
        };
    } else {
        if (self.hwnd) |hwnd| _ = postMessageWarn(hwnd, os.WM_USER, 0, 0, "WM_USER");
    }
}

/// Static COM callback for DispatcherQueue.TryEnqueue that calls drainMailbox.
/// Uses a module-level atomic App pointer — no heap allocation per wakeup.
const WakeupHandler = struct {
    const HRESULT = gen.HRESULT;
    const GUID = gen.GUID;
    const S_OK: HRESULT = 0;
    const E_NOINTERFACE: HRESULT = @bitCast(@as(u32, 0x80004002));
    const IID_IUnknown = GUID{ .data1 = 0x00000000, .data2 = 0x0000, .data3 = 0x0000, .data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
    const IID_IAgileObject = GUID{ .data1 = 0x94ea2b94, .data2 = 0xe9cc, .data3 = 0x49e0, .data4 = .{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 } };

    lpVtbl: *const gen.DispatcherQueueHandler.VTable,

    /// Atomic App pointer set by wakeup(), read by invoke on the dispatcher thread.
    var g_app: std.atomic.Value(?*App) = std.atomic.Value(?*App).init(null);

    /// Single static instance — ref counting is no-op (static lifetime).
    var instance: WakeupHandler = .{ .lpVtbl = &vtable };

    const vtable = gen.DispatcherQueueHandler.VTable{
        .QueryInterface = &queryInterfaceFn,
        .AddRef = &addRefFn,
        .Release = &releaseFn,
        .Invoke = &invokeFn,
    };

    fn queryInterfaceFn(this: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(.winapi) HRESULT {
        const eql = com_aggregation.guidEql;
        if (eql(riid, &IID_IUnknown) or eql(riid, &IID_IAgileObject) or eql(riid, &gen.IID_DispatcherQueueHandler)) {
            ppv.* = this;
            return S_OK;
        }
        ppv.* = null;
        return E_NOINTERFACE;
    }

    fn addRefFn(_: *anyopaque) callconv(.winapi) u32 {
        return 1; // Static object, no-op.
    }

    fn releaseFn(_: *anyopaque) callconv(.winapi) u32 {
        return 1; // Static object, no-op.
    }

    fn invokeFn(_: *anyopaque) callconv(.winapi) HRESULT {
        if (g_app.load(.acquire)) |app| {
            app.drainMailbox();
        }
        return S_OK;
    }
};

pub fn requestCloseWindow(self: *App) void {
    log.info("requestCloseWindow called! stage={s} exit_intent={s}", .{
        startupStageLabel(self.startup_stage),
        exitIntentLabel(self.exit_intent),
    });
    self.setExitIntent(.request_close_window);
    self.running = false;
    // In XAML Islands mode, destroy our own window to trigger cleanup.
    if (self.hwnd) |hwnd| {
        _ = os.DestroyWindow(hwnd);
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
            log.info("performAction: .quit", .{});
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
            log.info("performAction: .close_all_windows", .{});
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
        .initial_size => {
            switch (target) {
                .app => return false,
                .surface => {
                    const hwnd = self.hwnd orelse return false;
                    const dpi = os.GetDpiForWindow(hwnd);
                    const style: os.DWORD = @truncate(@as(usize, @bitCast(os.GetWindowLongPtrW(hwnd, os.GWL_STYLE))));
                    const ex_style: os.DWORD = @truncate(@as(usize, @bitCast(os.GetWindowLongPtrW(hwnd, os.GWL_EXSTYLE))));

                    // Compute non-client area size via AdjustWindowRectExForDpi
                    var rect = os.RECT{
                        .left = 0,
                        .top = 0,
                        .right = @intCast(value.width),
                        .bottom = @intCast(value.height),
                    };
                    _ = os.AdjustWindowRectExForDpi(&rect, style, 0, ex_style, dpi);

                    const total_width = rect.right - rect.left;
                    const total_height = rect.bottom - rect.top;
                    log.info("performAction: initial_size client={}x{} window={}x{} dpi={}", .{
                        value.width, value.height, total_width, total_height, dpi,
                    });
                    _ = os.SetWindowPos(
                        hwnd,
                        null,
                        0,
                        0,
                        total_width,
                        total_height,
                        os.SWP_NOMOVE | os.SWP_NOZORDER | os.SWP_NOACTIVATE,
                    );
                    return true;
                },
            }
        },
        else => return false,
    }
}

pub fn performIpc(
    alloc: Allocator,
    _: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    _: apprt.ipc.Action.Value(action),
) !bool {
    // Map IPC action keys to named pipe action strings.
    const action_str = switch (action) {
        .new_window => "new-window",
    };
    return IpcServer.sendIpc(alloc, action_str) catch false;
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
    log.debug("closeActiveTab: ENTRY active={} total={}", .{ self.active_surface_idx, self.surfaces.items.len });
    if (tab_manager.closeActiveTab(self)) {
        log.info("closeActiveTab: no tabs remain, requesting app exit", .{});
        self.running = false;
        if (self.xaml_app) |xa| xa.Exit() catch {};
    }
    log.debug("closeActiveTab: EXIT total={}", .{self.surfaces.items.len});
}

/// Close a specific tab by index.
pub fn closeTab(self: *App, idx: usize) void {
    log.debug("closeTab: ENTRY idx={} total={}", .{ idx, self.surfaces.items.len });
    if (tab_manager.closeTab(self, idx)) {
        log.info("closeTab: no tabs remain, requesting app exit", .{});
        self.running = false;
        if (self.xaml_app) |xa| xa.Exit() catch {};
    }
    log.debug("closeTab: EXIT total={}", .{self.surfaces.items.len});
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
        _ = postMessageWarn(hwnd, os.WM_CLOSE, 0, 0, "WM_CLOSE");
    }
}

/// Switch to a specific tab by index.
pub fn switchToTab(self: *App, idx: usize) void {
    if (idx >= self.surfaces.items.len) return;
    if (self.tab_view) |tv| {
        tv.SetSelectedIndex(@intCast(idx)) catch {};
        self.active_surface_idx = idx;
        surface_binding.updateSelectedTab(self, idx);
        self.syncWindowTitleToActiveSurface();
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

fn controlPlaneCaptureState(ctx: *anyopaque, allocator: Allocator, tab_idx: ?usize) !?ControlPlaneNative.StateSnapshot {
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
        .pane_pid = s.panePid() orelse 0,
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

fn controlPlaneCaptureHistory(ctx: *anyopaque, allocator: Allocator, tab_idx: ?usize) !?[]u8 {
    const self: *App = @ptrCast(@alignCast(ctx));
    const surface = if (tab_idx) |idx|
        (if (idx < self.surfaces.items.len) self.surfaces.items[idx] else null)
    else
        self.activeSurface();
    const s = surface orelse return null;
    const history = try s.historyString(allocator);
    return try allocator.dupe(u8, history);
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
        try writer.print("TAB|{d}|{s}|pwd={s}|prompt={d}|selection={d}|id={d}\n", .{
            i,
            title,
            pwd_val orelse "",
            @as(u8, if (surface.cursorIsAtPrompt()) 1 else 0),
            @as(u8, if (surface.hasSelection()) 1 else 0),
            surface.tab_id,
        });
    }
    return try buf.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------
// TabView event callbacks
// ---------------------------------------------------------------

fn onTabCloseRequested(self: *App, sender: ?*anyopaque, args: ?*anyopaque) void {
    log.debug("onTabCloseRequested: ENTRY sender={} args={} tabs={}", .{
        @intFromPtr(sender),
        @intFromPtr(args),
        self.surfaces.items.len,
    });
    event_handlers.onTabCloseRequested(self, sender, args);
    log.debug("onTabCloseRequested: EXIT tabs={}", .{self.surfaces.items.len});
}

fn onAddTabButtonClick(self: *App, sender: ?*anyopaque, args: ?*anyopaque) void {
    log.debug("onAddTabButtonClick: ENTRY tabs={}", .{self.surfaces.items.len});
    event_handlers.onAddTabButtonClick(self, sender, args);
    log.debug("onAddTabButtonClick: EXIT tabs={}", .{self.surfaces.items.len});
}

fn onResourceManagerRequested(self: *App, sender: ?*anyopaque, args: ?*anyopaque) void {
    _ = self;
    _ = sender;
    log.debug("onResourceManagerRequested: ENTRY", .{});
    const args_insp: *winrt.IInspectable = @ptrCast(@alignCast(args orelse return));
    const e = args_insp.queryInterface(gen.IResourceManagerRequestedEventArgs) catch |err| {
        log.err("onResourceManagerRequested: QI IResourceManagerRequestedEventArgs failed: {}", .{@intFromError(err)});
        return;
    };
    defer e.release();

    const res_manager_class = winrt.hstring("Microsoft.Windows.ApplicationModel.Resources.ResourceManager") catch |err| {
        log.err("onResourceManagerRequested: hstring failed: {}", .{@intFromError(err)});
        return;
    };
    defer winrt.deleteHString(res_manager_class);

    // Fallback: DllGetActivationFactory → IActivationFactory.ActivateInstance (default ctor)
    // This creates a ResourceManager that auto-discovers resources.pri in the exe directory
    log.debug("onResourceManagerRequested: trying DllGetActivationFactory+ActivateInstance", .{});
    const resource_manager = activateResourceManagerDirect(res_manager_class) catch |err2| {
        log.err("onResourceManagerRequested: direct activation failed: {}", .{@intFromError(err2)});
        return;
    };
    // DO NOT release resource_manager here — XAML framework takes ownership
    // and will use it throughout the app lifetime.

    e.SetCustomResourceManager(@ptrCast(resource_manager)) catch |err| {
        log.err("onResourceManagerRequested: SetCustomResourceManager failed: {}", .{@intFromError(err)});
        return;
    };

    log.info("onResourceManagerRequested: SUCCESS - custom ResourceManager set", .{});
}

fn activateResourceManagerDirect(class_name: winrt.HSTRING) !*winrt.IInspectable {
    const dll_name_z = [_:0]u16{ 'M', 'i', 'c', 'r', 'o', 's', 'o', 'f', 't', '.', 'W', 'i', 'n', 'd', 'o', 'w', 's', '.', 'A', 'p', 'p', 'l', 'i', 'c', 'a', 't', 'i', 'o', 'n', 'M', 'o', 'd', 'e', 'l', '.', 'R', 'e', 's', 'o', 'u', 'r', 'c', 'e', 's', '.', 'd', 'l', 'l' };
    const module = std.os.windows.kernel32.LoadLibraryW(&dll_name_z) orelse {
        log.err("activateResourceManagerDirect: LoadLibrary failed", .{});
        return error.WinRTFailed;
    };

    const DllGetActivationFactoryFn = *const fn (winrt.HSTRING, *?*anyopaque) callconv(.winapi) i32;
    const get_factory_fn: DllGetActivationFactoryFn = @ptrCast(std.os.windows.kernel32.GetProcAddress(
        module,
        "DllGetActivationFactory",
    ) orelse {
        log.err("activateResourceManagerDirect: GetProcAddress failed", .{});
        return error.WinRTFailed;
    });

    var act_factory: ?*anyopaque = null;
    const hr1 = get_factory_fn(class_name, &act_factory);
    if (hr1 < 0 or act_factory == null) {
        log.err("activateResourceManagerDirect: DllGetActivationFactory failed: 0x{x}", .{@as(u32, @bitCast(hr1))});
        return error.WinRTFailed;
    }
    log.debug("activateResourceManagerDirect: DllGetActivationFactory OK", .{});

    // IActivationFactory vtable: slots 0-5 = IInspectable, slot 6 = ActivateInstance
    const IActivationFactoryVTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const winrt.GUID, *?*anyopaque) callconv(.winapi) i32,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: *const fn (*anyopaque, *u32, *?*anyopaque) callconv(.winapi) i32,
        GetRuntimeClassName: *const fn (*anyopaque, *?winrt.HSTRING) callconv(.winapi) i32,
        GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.winapi) i32,
        ActivateInstance: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) i32,
    };
    const act_vtbl: *const *const IActivationFactoryVTable = @ptrCast(@alignCast(act_factory.?));

    var instance: ?*anyopaque = null;
    const hr2 = act_vtbl.*.ActivateInstance(act_factory.?, &instance);
    // Release the factory
    _ = act_vtbl.*.Release(act_factory.?);

    if (hr2 < 0 or instance == null) {
        log.err("activateResourceManagerDirect: ActivateInstance failed: 0x{x}", .{@as(u32, @bitCast(hr2))});
        return error.WinRTFailed;
    }
    log.info("activateResourceManagerDirect: SUCCESS", .{});
    return @ptrCast(@alignCast(instance.?));
}

fn onSelectionChanged(self: *App, sender: ?*anyopaque, args: ?*anyopaque) void {
    event_handlers.onSelectionChanged(self, sender, args);
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

fn setTabItemContent(_: *App, tvi_insp: *winrt.IInspectable, content: ?*winrt.IInspectable) !void {
    return surface_binding.setTabItemContent(tvi_insp, content);
}

pub fn ensureVisibleSurfaceAttached(self: *App, surface: *Surface) void {
    surface_binding.ensureVisibleSurfaceAttached(self, surface);
}

/// Show context menu at cursor position (stub — not yet implemented for islands).
pub fn showContextMenuAtCursor(_: *App) void {
    // TODO: Implement context menu for XAML Islands apprt.
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

fn enableDebugSettings(_: *App, xa: *com.IApplication) void {
    // Only enable XAML debug tracing if explicitly requested via env var.
    // These fire on every layout pass and hurt debug build performance.
    const enable_tracing = if (std.process.getenvW(std.unicode.utf8ToUtf16LeStringLiteral("GHOSTTY_XAML_DEBUG_TRACING"))) |val|
        std.mem.eql(u16, val, std.unicode.utf8ToUtf16LeStringLiteral("1"))
    else
        false;

    if (!enable_tracing) {
        log.debug("DebugSettings: tracing disabled (set GHOSTTY_XAML_DEBUG_TRACING=1 to enable)", .{});
        return;
    }

    const ds = xa.DebugSettings() catch |err| {
        log.warn("DebugSettings: failed to get: {}", .{@intFromError(err)});
        return;
    };
    ds.SetIsBindingTracingEnabled(true) catch {};
    log.debug("DebugSettings: BindingTracing enabled", .{});

    // IDebugSettings2: resource reference tracing
    if (ds.queryInterface(com.IDebugSettings2)) |ds2| {
        ds2.SetIsXamlResourceReferenceTracingEnabled(true) catch {};
        log.debug("DebugSettings: XamlResourceReferenceTracing enabled", .{});
    } else |_| {
        log.debug("DebugSettings: IDebugSettings2 not available", .{});
    }
}

/// Counter for periodic diagnostic snapshots (every N ticks).
var diagnostic_tick_count: u32 = 0;
const diagnostic_interval: u32 = 500; // ~every 500 ticks

pub fn drainMailbox(self: *App) void {
    log.info("drainMailbox: tick...", .{});
    self.core_app.tick(self) catch |err| {
        log.warn("tick error: {}", .{err});
    };
    log.info("drainMailbox: tick done", .{});

    // CP push: drainMailbox is called when PTY output arrives (wakeup → WM_USER).
    // Emit "running" status, throttled to at most once per second.
    if (self.control_plane) |cp| {
        const now = std.time.milliTimestamp();
        const elapsed = now - self.cp_last_notify_ts;
        if (elapsed >= 1000 or self.cp_last_notify_ts == 0) {
            self.cp_last_notify_ts = now;
            cp.notifyStatus("running");
        }
    }

    // Periodic internal state snapshot
    diagnostic_tick_count += 1;
    if (diagnostic_tick_count % diagnostic_interval == 0) {
        self.logDiagnosticSnapshot();
    }
}

fn logDiagnosticSnapshot(self: *App) void {
    // Only run in Debug mode — the full page list walk is O(n) in the
    // number of scrollback pages and becomes expensive with large
    // scrollback buffers (Issue #138).
    if (comptime builtin.mode != .Debug) return;

    log.debug("=== DIAGNOSTIC tick={} ===", .{diagnostic_tick_count});
    log.debug("  surfaces={} active_idx={}", .{ self.surfaces.items.len, self.active_surface_idx });
    log.debug("  resizing={} pending_size={}", .{
        @intFromBool(self.resizing),
        @intFromBool(self.pending_size != null),
    });

    // Per-surface terminal stats
    for (self.surfaces.items, 0..) |surface, i| {
        if (surface.core_initialized) {
            const t = surface.core_surface.renderer_state.terminal;
            const screen = t.screens.active;
            var page_count: usize = 0;
            var it = screen.pages.pages.first;
            while (it) |node| : (it = node.next) {
                page_count += 1;
            }
            const tracked_pins = screen.pages.countTrackedPins();
            log.debug("  surface[{}] pages={} rows={} cols={} pins={} page_size={}", .{
                i,
                page_count,
                screen.pages.rows,
                screen.pages.cols,
                tracked_pins,
                screen.pages.page_size,
            });
        }
    }
    log.debug("=== END DIAGNOSTIC ===", .{});
}

fn setWindowTitle(self: *App, title: [:0]const u8) void {
    // In XAML Islands mode, use Win32 SetWindowTextW instead of IWindow.SetTitle.
    const hwnd = self.hwnd orelse return;
    // Convert UTF-8 to UTF-16 for SetWindowTextW.
    var wbuf: [512]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&wbuf, title) catch 0;
    if (len > 0 and len < wbuf.len) {
        wbuf[len] = 0;
        _ = os.SetWindowTextW(hwnd, @ptrCast(&wbuf));
    }
}

pub fn syncWindowTitleToActiveSurface(self: *App) void {
    const title = if (self.activeSurface()) |surface|
        (surface.getTitle() orelse "Ghostty")
    else
        "Ghostty";
    self.setWindowTitleWithSession(title);
}

fn setTitle(self: *App, title: [:0]const u8) void {
    log.info("setTitle: \"{s}\"", .{title});
    self.setWindowTitleWithSession(title);

    if (self.activeSurface()) |surface| {
        surface.setTabTitle(title);
    }
    log.info("setTitle: completed", .{});
}

/// Set the window title, using "Ghostty [session-name]" when CP is active.
fn setWindowTitleWithSession(self: *App, title: [:0]const u8) void {
    if (self.control_plane) |cp| {
        if (cp.session_name) |sn| {
            const alloc = self.core_app.alloc;
            const raw = std.fmt.allocPrint(alloc, "Ghostty [{s}]", .{sn}) catch {
                self.setWindowTitle(title);
                return;
            };
            defer alloc.free(raw);
            const decorated = alloc.dupeZ(u8, raw) catch {
                self.setWindowTitle(title);
                return;
            };
            defer alloc.free(decorated);
            self.setWindowTitle(decorated);
            return;
        }
    }
    self.setWindowTitle(title);
}

// ---------------------------------------------------------------
// WndProc message handler — called from nonclient_island_window.wndProc
// ---------------------------------------------------------------

/// Handle App-specific window messages forwarded from the wndproc.
/// Returns the LRESULT if handled, or null if the message should be
/// passed to DefWindowProcW.
pub fn handleWndProcMessage(self: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) ?os.LRESULT {
    switch (msg) {
        os.WM_USER => {
            // Wakeup / mailbox drain.
            self.drainMailbox();
            return 0;
        },
        os.WM_APP_CLOSE_TAB => {
            self.closeActiveTab();
            return 0;
        },
        os.WM_TIMER => {
            return self.handleTimer(hwnd, wparam);
        },
        os.WM_SIZE => {
            return self.handleSize(hwnd, wparam, lparam);
        },
        os.WM_ENTERSIZEMOVE => {
            self.resizing = true;
            return 0;
        },
        os.WM_EXITSIZEMOVE => {
            self.resizing = false;
            if (self.pending_size) |ps| {
                self.pending_size = null;
                self.applySizeChange(ps.width, ps.height);
            }
            return 0;
        },
        os.WM_SETFOCUS => {
            input_runtime.ensureInputFocus(self);
            // TSF focus/unfocus is managed via WM_ACTIVATE below (safe from
            // recursion). Do NOT call tsf.focus()/unfocus() here — SetFocus
            // triggers WM_SETFOCUS internally, causing infinite recursion.
            return 0;
        },
        os.WM_ACTIVATE => {
            // WM_ACTIVATE is safe for TSF focus management (no recursion risk).
            // WA_ACTIVE (1) or WA_CLICKACTIVE (2) = window activated;
            // WA_INACTIVE (0) = window deactivated.
            const activation: usize = @as(usize, @bitCast(wparam)) & 0xFFFF;
            if (activation != 0) {
                // Window activated — set TSF focus
                if (self.tsf_impl) |*tsf_inst| {
                    tsf_inst.focus();
                }
            } else {
                // Window deactivated — remove TSF focus
                if (self.tsf_impl) |*tsf_inst| {
                    tsf_inst.unfocus();
                }
            }
            // Pass through to DefWindowProc for default activation handling
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_CLOSE => {
            self.onWindowClose();
            return 0;
        },
        os.WM_IME_CHAR => {
            // Chrome Remote Desktop and similar tools send WM_IME_CHAR for
            // pre-composed CJK text instead of going through TSF/IMM.
            // Route to the active surface's char handler.
            const wp: usize = @bitCast(wparam);
            if (self.activeSurface()) |surface| {
                surface.handleCharEvent(@truncate(wp));
            }
            return 0;
        },
        os.WM_APP_BIND_SWAP_CHAIN => {
            // Complete swap chain binding on the UI thread.
            const surface: *Surface = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const swap_chain: *anyopaque = @ptrFromInt(@as(usize, @bitCast(wparam)));
            var alive = false;
            for (self.surfaces.items) |s| {
                if (s == surface) {
                    alive = true;
                    break;
                }
            }
            if (!alive) {
                log.warn("handleBindSwapChain: drop stale surface ptr=0x{x}", .{@intFromPtr(surface)});
                return 0;
            }
            surface.completeBindSwapChain(swap_chain);
            return 0;
        },
        os.WM_APP_BIND_SWAP_CHAIN_HANDLE => {
            // Complete handle-based swap chain binding on the UI thread.
            const surface: *Surface = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const swap_chain_handle: usize = @as(usize, @bitCast(wparam));
            var alive = false;
            for (self.surfaces.items) |s| {
                if (s == surface) {
                    alive = true;
                    break;
                }
            }
            if (!alive) {
                log.warn("handleBindSwapChainHandle: drop stale surface ptr=0x{x}", .{@intFromPtr(surface)});
                return 0;
            }
            surface.completeBindSwapChainHandle(swap_chain_handle);
            return 0;
        },
        os.WM_DPICHANGED => {
            // DPI change: full DWM re-init (frame + SWP_FRAMECHANGED + attributes).
            if (self.nci_window) |nci| {
                nci.initFrameMargins();
            }
            // Apply the recommended window rect.
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
        },
        os.WM_APP_CONTROL_INPUT => {
            // Drain pending control plane inputs to the active surface PTY.
            if (self.control_plane) |cp| {
                if (self.activeSurface()) |surface| {
                    log.info("WM_APP_CONTROL_INPUT: draining to surface idx={}", .{self.active_surface_idx});
                    cp.drainPendingInputs(&surface.core_surface);
                } else {
                    log.warn("WM_APP_CONTROL_INPUT: no active surface", .{});
                }
            } else {
                log.warn("WM_APP_CONTROL_INPUT: no control_plane", .{});
            }
            return 0;
        },
        os.WM_APP_IME_INJECT => {
            // Drain pending IME inject texts and set on the active surface's IME TextBox.
            // This simulates committed IME input: TextBox.Text is set, which triggers
            // TextChanged -> flushImeTextBoxCommittedDelta -> characters sent to PTY.
            if (self.control_plane) |cp| {
                if (self.activeSurface()) |surface| {
                    if (cp.drainPendingImeInjects()) |utf8_text| {
                        defer cp.allocator.free(utf8_text);
                        // Use hstringRuntime to convert runtime UTF-8 to HSTRING
                        const hstr = winrt.hstringRuntime(cp.allocator, utf8_text) catch {
                            log.warn("IME_INJECT: failed to create HSTRING", .{});
                            return 0;
                        };
                        defer winrt.deleteHString(hstr);
                        // Clear TextBox and delta tracking state first, so the
                        // sent.len==0 path in flushImeTextBoxCommittedDelta fires
                        // and sends all injected characters correctly.
                        surface.clearImeTextBoxText();
                        // Set TextBox.Text (do NOT set internal_update = true, so TextChanged fires)
                        if (surface.ime_text_box) |ime_tb| {
                            ime_tb.SetText(hstr) catch |err| {
                                log.warn("IME_INJECT: SetText failed: {}", .{err});
                                return 0;
                            };
                            log.info("IME_INJECT: set TextBox.Text len={}", .{utf8_text.len});
                        } else {
                            log.warn("IME_INJECT: no IME TextBox available", .{});
                        }
                    }
                }
            }
            return 0;
        },
        os.WM_APP_TSF_INJECT => {
            // Simulate the full TSF composition lifecycle:
            //   OnStartComposition → OnUpdateComposition → textEditSinkOnEndEdit
            //   → requestEditSession → doCompositionUpdate → tsfHandleOutput
            //   → OnEndComposition
            // This exercises Fix 1-4 code paths with real composition state.
            if (self.control_plane) |cp| {
                if (cp.drainPendingImeInjects()) |utf8_text| {
                    defer cp.allocator.free(utf8_text);
                    log.info("TSF_INJECT: simulating TSF commit len={}", .{utf8_text.len});

                    if (self.tsf_impl) |*tsf_impl| {
                        // 1. OnStartComposition
                        tsf_impl._compositions += 1;
                        log.debug("TSF_INJECT: OnStartComposition (compositions={})", .{tsf_impl._compositions});

                        // 2. OnUpdateComposition (preedit) — just log, no visual
                        log.debug("TSF_INJECT: OnUpdateComposition (compositions={})", .{tsf_impl._compositions});

                        // 3. textEditSinkOnEndEdit → requestEditSession
                        //    This is where Fix 2 (_compositions >= 1) matters.
                        if (tsf_impl._compositions >= 1) {
                            log.debug("TSF_INJECT: textEditSinkOnEndEdit requesting edit session (compositions={})", .{tsf_impl._compositions});
                        }

                        // 4. tsfHandleOutput — the real commit path (sets tsf_just_committed)
                        tsfHandleOutput(@ptrCast(self), utf8_text);

                        // 5. OnEndComposition
                        if (tsf_impl._compositions > 0) tsf_impl._compositions -= 1;
                        log.debug("TSF_INJECT: OnEndComposition (compositions={})", .{tsf_impl._compositions});
                    } else {
                        // No TSF — fallback to direct output
                        tsfHandleOutput(@ptrCast(self), utf8_text);
                    }
                }
            }
            return 0;
        },
        os.WM_APP_CONTROL_ACTION => {
            // Execute a tab/window action from the control plane.
            const action: ControlPlaneNative.Action = @enumFromInt(@as(usize, @bitCast(wparam)));
            const param: usize = @bitCast(lparam);
            switch (action) {
                .new_tab => self.newTab() catch |err| {
                    log.warn("control_plane new_tab failed: {}", .{err});
                },
                .close_tab => {
                    if (param < self.surfaces.items.len) {
                        self.closeTab(param);
                    } else {
                        self.closeActiveTab();
                    }
                },
                .switch_tab => {
                    if (self.tab_view) |tv| {
                        tv.SetSelectedIndex(@intCast(param)) catch {};
                    }
                },
                .focus_window => {
                    if (self.hwnd) |h| {
                        _ = os.SetForegroundWindow(h);
                    }
                },
            }
            return 0;
        },
        os.WM_APP_CP_QUERY => {
            // Synchronous control plane query from pipe thread (Issue #139 H1 fix).
            // SendMessageW blocks the pipe thread until we fill the result and return.
            const query: *CpQuery = @ptrFromInt(@as(usize, @bitCast(lparam)));
            self.handleCpQuery(query);
            return 0;
        },
        else => return null,
    }
}

/// Handle a synchronous CP query on the UI thread.
/// Called from WM_APP_CP_QUERY — all App state access is safe here.
fn handleCpQuery(self: *App, query: *CpQuery) void {
    switch (query.kind) {
        .read_buffer => {
            const result = controlPlaneCaptureTail(
                @ptrCast(self),
                query.allocator,
                query.tab_index,
            ) catch null;
            if (result) |viewport| {
                defer query.allocator.free(viewport);
                if (query.out_buf) |buf| {
                    const copy_len = @min(viewport.len, query.out_buf_len);
                    @memcpy(buf[0..copy_len], viewport[0..copy_len]);
                    query.result_len = copy_len;
                }
            }
        },
        .tab_count => {
            var snapshot = controlPlaneCaptureState(
                @ptrCast(self),
                query.allocator,
                null,
            ) catch null;
            if (snapshot) |*s| {
                query.result_usize = s.tab_count;
                s.deinit(query.allocator);
            }
        },
        .active_tab => {
            var snapshot = controlPlaneCaptureState(
                @ptrCast(self),
                query.allocator,
                null,
            ) catch null;
            if (snapshot) |*s| {
                query.result_usize = s.active_tab;
                s.deinit(query.allocator);
            }
        },
        .tab_working_dir => {
            var snapshot = controlPlaneCaptureState(
                @ptrCast(self),
                query.allocator,
                query.tab_index,
            ) catch null;
            if (snapshot) |*s| {
                defer s.deinit(query.allocator);
                if (s.pwd) |pwd| {
                    if (query.out_buf) |buf| {
                        const copy_len = @min(pwd.len, query.out_buf_len);
                        @memcpy(buf[0..copy_len], pwd[0..copy_len]);
                        query.result_len = copy_len;
                    }
                }
            }
        },
        .tab_has_selection => {
            var snapshot = controlPlaneCaptureState(
                @ptrCast(self),
                query.allocator,
                query.tab_index,
            ) catch null;
            if (snapshot) |*s| {
                query.result_bool = s.has_selection;
                s.deinit(query.allocator);
            }
        },
        .tab_title => {
            // provTabTitle uses GetWindowTextW (thread-safe), but handle here too for completeness.
            if (query.out_buf) |buf| {
                const title = self.activeSurface().?.getTitle() orelse "";
                const copy_len = @min(title.len, query.out_buf_len);
                @memcpy(buf[0..copy_len], title[0..copy_len]);
                query.result_len = copy_len;
            }
        },
        .capture_tab_list => {
            query.result_owned = controlPlaneCaptureTabList(
                @ptrCast(self),
                query.allocator,
            ) catch null;
        },
        .capture_snapshot => {
            // Issue #142: fill all snapshot fields in a single UI-thread call.
            // All error paths leave default values (0/false) — no panic/unreachable.
            var snapshot = controlPlaneCaptureState(
                @ptrCast(self),
                query.allocator,
                query.tab_index,
            ) catch |err| blk: {
                log.err("capture_snapshot: controlPlaneCaptureState failed: {}", .{err});
                break :blk null;
            };
            if (snapshot) |*s| {
                defer s.deinit(query.allocator);
                query.result_tab_count = s.tab_count;
                query.result_active_tab = s.active_tab;
                query.result_pane_pid = s.pane_pid;
                query.result_has_selection = s.has_selection;
                query.result_at_prompt = s.at_prompt;
                if (s.pwd) |pwd| {
                    const copy_len = @min(pwd.len, query.result_pwd.len);
                    if (pwd.len > query.result_pwd.len) {
                        log.warn("capture_snapshot: truncating pwd from {d} to {d} bytes", .{ pwd.len, query.result_pwd.len });
                    }
                    @memcpy(query.result_pwd[0..copy_len], pwd[0..copy_len]);
                    query.result_pwd_len = copy_len;
                }
            } else {
                log.err("capture_snapshot: no surface for tab_index={?}", .{query.tab_index});
            }
            // Capture viewport into out_buf.
            const viewport = controlPlaneCaptureTail(
                @ptrCast(self),
                query.allocator,
                query.tab_index,
            ) catch |err| blk: {
                log.err("capture_snapshot: controlPlaneCaptureTail failed: {}", .{err});
                break :blk null;
            };
            if (viewport) |vp| {
                defer query.allocator.free(vp);
                if (query.out_buf) |buf| {
                    const copy_len = @min(vp.len, query.out_buf_len);
                    @memcpy(buf[0..copy_len], vp[0..copy_len]);
                    query.result_len = copy_len;
                } else {
                    log.err("capture_snapshot: out_buf is null, viewport data dropped", .{});
                }
            }
            // Capture title.
            const surface = if (query.tab_index) |idx|
                (if (idx < self.surfaces.items.len) self.surfaces.items[idx] else null)
            else
                self.activeSurface();
            if (surface) |s| {
                const title = s.getTitle() orelse "";
                const copy_len = @min(title.len, query.result_title.len);
                if (title.len > query.result_title.len) {
                    log.warn("capture_snapshot: truncating title from {d} to {d} bytes", .{ title.len, query.result_title.len });
                }
                @memcpy(query.result_title[0..copy_len], title[0..copy_len]);
                query.result_title_len = copy_len;
            }
        },
        .capture_history => {
            // Fill state fields (same as capture_snapshot).
            var snapshot = controlPlaneCaptureState(
                @ptrCast(self),
                query.allocator,
                query.tab_index,
            ) catch |err| blk: {
                log.err("capture_history: controlPlaneCaptureState failed: {}", .{err});
                break :blk null;
            };
            if (snapshot) |*s| {
                defer s.deinit(query.allocator);
                query.result_tab_count = s.tab_count;
                query.result_active_tab = s.active_tab;
                query.result_pane_pid = s.pane_pid;
                query.result_has_selection = s.has_selection;
                query.result_at_prompt = s.at_prompt;
                if (s.pwd) |pwd| {
                    const copy_len = @min(pwd.len, query.result_pwd.len);
                    if (pwd.len > query.result_pwd.len) {
                        log.warn("capture_history: truncating pwd from {d} to {d} bytes", .{ pwd.len, query.result_pwd.len });
                    }
                    @memcpy(query.result_pwd[0..copy_len], pwd[0..copy_len]);
                    query.result_pwd_len = copy_len;
                }
            } else {
                log.err("capture_history: no surface for tab_index={?}", .{query.tab_index});
            }
            // Capture full scrollback history into out_buf.
            const history = controlPlaneCaptureHistory(
                @ptrCast(self),
                query.allocator,
                query.tab_index,
            ) catch |err| blk: {
                log.err("capture_history: controlPlaneCaptureHistory failed: {}", .{err});
                break :blk null;
            };
            if (history) |h| {
                defer query.allocator.free(h);
                if (query.out_buf) |buf| {
                    const copy_len = @min(h.len, query.out_buf_len);
                    @memcpy(buf[0..copy_len], h[0..copy_len]);
                    query.result_len = copy_len;
                } else {
                    log.err("capture_history: out_buf is null, history data dropped", .{});
                }
            }
            // Capture title.
            const surface = if (query.tab_index) |idx|
                (if (idx < self.surfaces.items.len) self.surfaces.items[idx] else null)
            else
                self.activeSurface();
            if (surface) |s| {
                const title = s.getTitle() orelse "";
                const copy_len = @min(title.len, query.result_title.len);
                if (title.len > query.result_title.len) {
                    log.warn("capture_history: truncating title from {d} to {d} bytes", .{ title.len, query.result_title.len });
                }
                @memcpy(query.result_title[0..copy_len], title[0..copy_len]);
                query.result_title_len = copy_len;
            }
        },
    }
}

fn handleTimer(self: *App, hwnd: os.HWND, wparam: os.WPARAM) os.LRESULT {
    const timer_id = wparam;
    switch (timer_id) {
        RESIZE_TIMER_ID => {
            // Live resize preview timer.
            if (self.pending_size) |ps| {
                self.applySizeChange(ps.width, ps.height);
            }
            return 0;
        },
        CLOSE_TAB_POLL_TIMER_ID => {
            self.pollTabCloseState();
            return 0;
        },
        CLOSE_TIMER_ID => {
            // Auto-close timer.
            _ = os.KillTimer(hwnd, CLOSE_TIMER_ID);
            self.requestCloseWindow();
            return 0;
        },
        CLOSE_TAB_TIMER_ID => {
            // Close-tab timer.
            _ = os.KillTimer(hwnd, CLOSE_TAB_TIMER_ID);
            self.closeActiveTab();
            return 0;
        },
        DUMP_VT_TIMER_ID => if (comptime builtin.mode == .Debug) {
            // One-shot visual tree dump after layout.
            _ = os.KillTimer(self.hwnd.?, DUMP_VT_TIMER_ID);
            self.dumpVisualTreeRoot();
            return 0;
        } else return 0,
        else => return 0,
    }
}

fn handleSize(self: *App, hwnd: os.HWND, _: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const width: u32 = @intCast(lp & 0xFFFF);
    const height: u32 = @intCast((lp >> 16) & 0xFFFF);

    // Update DWM frame margins on every resize (WT: _UpdateFrameMargins in OnSize).
    if (self.nci_window) |nci| {
        nci.updateFrameMargins();
    }

    // WT: OnSize → _UpdateIslandPosition (which also calls _ResizeDragBarWindow).
    if (self.nci_window) |nci| {
        nci.updateIslandPosition(@intCast(width), @intCast(height));
    }

    // Update RootGrid explicit dimensions (Windows Terminal pattern).
    // WT: GetLogicalSize() — convert physical pixels to DIPs.
    // Size must match the island (height - top_offset), not the full client area.
    if (self.root_grid) |rg| {
        const fe = rg.queryInterface(com.IFrameworkElement) catch null;
        if (fe) |framework| {
            defer framework.release();
            const dpi = os.GetDpiForWindow(hwnd);
            const scale: f64 = @as(f64, @floatFromInt(dpi)) / 96.0;
            const top_offset: u32 = if (self.nci_window) |nci|
                @intCast(@max(0, NonClientIslandWindow.getTopBorderHeight(nci.island.hwnd)))
            else
                0;
            const island_height = if (height > top_offset) height - top_offset else 0;
            framework.SetWidth(@floatCast(@as(f64, @floatFromInt(width)) / scale)) catch {};
            framework.SetHeight(@floatCast(@as(f64, @floatFromInt(island_height)) / scale)) catch {};
        }
    }

    // Do NOT call applySizeChange here — let XAML layout (onSizeChanged)
    // provide the correct SwapChainPanel size. handleSize only updates
    // RootGrid dimensions; the XAML layout cascade then fires SizeChanged
    // on the SwapChainPanel with the actual content area size.
    // Calling applySizeChange here would use a stale/incorrect height
    // (missing TabView strip, or self.tab_view not yet initialized).

    return 0;
}

fn applySizeChange(self: *App, width: u32, height: u32) void {
    if (width == 0 or height == 0) return;

    for (self.surfaces.items) |surface| {
        surface.updateSize(width, height);
    }
}

/// VEH for debugging — log only non-stowed exceptions (real crashes).
/// WinUI3/XAML runtime throws and catches stowed exceptions (0xC000027B)
/// internally as normal operation — logging those is just noise.
pub fn stowedExceptionHandler(exception_info: *os.EXCEPTION_POINTERS) callconv(.winapi) c_long {
    const rec = exception_info.ExceptionRecord orelse return 0;
    const code = rec.ExceptionCode;
    // Stowed exceptions are WinRT internal — ignore.
    if (code == os.STATUS_STOWED_EXCEPTION) return 0;
    // C++ exceptions (used by WinRT/COM internally).
    if (code == 0xE06D7363) return 0;
    // MS_VC_EXCEPTION: SetThreadName via RaiseException (debugger thread naming).
    if (code == 0x406D1388) return 0;
    log.err("!!! EXCEPTION code=0x{X:0>8} addr={?} !!!", .{ code, rec.ExceptionAddress });
    return 0; // EXCEPTION_CONTINUE_SEARCH
}

test "App.performAction logic" {
    const testing = std.testing;
    const alloc = testing.allocator;

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
