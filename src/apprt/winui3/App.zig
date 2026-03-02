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

const log = std.log.scoped(.winui3);

/// Timer ID for live resize preview.
const RESIZE_TIMER_ID: usize = 1;

// ---------------------------------------------------------------
// ApplicationInitializationCallback — WinRT delegate for Application.Start()
// IID: {D8EEF1C9-1234-56F1-9963-45DD9C80A661}
// WinMD blob: 01 00 C9 F1 EE D8 34 12 F1 56 99 63 45 DD 9C 80 A6 61 00 00
// vtable: IUnknown(0-2) + Invoke(3)
// ---------------------------------------------------------------

const InitCallback = struct {
    /// COM-visible part — extern struct with lpVtbl at offset 0.
    com: Com,
    app: *App,

    const Com = extern struct {
        lpVtbl: *const VTable,

        const VTable = extern struct {
            QueryInterface: *const fn (*anyopaque, *const winrt.GUID, *?*anyopaque) callconv(.winapi) winrt.HRESULT,
            AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
            Release: *const fn (*anyopaque) callconv(.winapi) u32,
            Invoke: *const fn (*anyopaque, *anyopaque) callconv(.winapi) winrt.HRESULT,
        };
    };

    const vtable_inst = Com.VTable{
        .QueryInterface = &qiFn,
        .AddRef = &addRefFn,
        .Release = &releaseFn,
        .Invoke = &invokeFn,
    };

    fn create(app: *App) InitCallback {
        return .{
            .com = .{ .lpVtbl = &vtable_inst },
            .app = app,
        };
    }

    fn comPtr(self: *InitCallback) *anyopaque {
        return @ptrCast(&self.com);
    }

    fn fromComPtr(ptr: *anyopaque) *InitCallback {
        const com_ptr: *Com = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("com", com_ptr);
    }

    fn qiFn(this: *anyopaque, riid: *const winrt.GUID, ppv: *?*anyopaque) callconv(.winapi) winrt.HRESULT {
        const IID_IUnknown = winrt.GUID{ .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
        const IID_IAgileObject = winrt.GUID{ .Data1 = 0x94ea2b94, .Data2 = 0xe9cc, .Data3 = 0x49e0, .Data4 = .{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 } };
        const IID_Self = winrt.GUID{ .Data1 = 0xd8eef1c9, .Data2 = 0x1234, .Data3 = 0x56f1, .Data4 = .{ 0x99, 0x63, 0x45, 0xdd, 0x9c, 0x80, 0xa6, 0x61 } };

        if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IAgileObject) or guidEql(riid, &IID_Self)) {
            ppv.* = this;
            return 0; // S_OK
        }
        ppv.* = null;
        return @bitCast(@as(u32, 0x80004002)); // E_NOINTERFACE
    }

    fn addRefFn(_: *anyopaque) callconv(.winapi) u32 {
        return 1;
    }

    fn releaseFn(_: *anyopaque) callconv(.winapi) u32 {
        return 1;
    }

    fn invokeFn(this: *anyopaque, _: *anyopaque) callconv(.winapi) winrt.HRESULT {
        const self = fromComPtr(this);
        self.app.initXaml() catch |err| {
            log.err("initXaml failed in Application.Start callback: {}", .{err});
            return @bitCast(@as(u32, 0x80004005)); // E_FAIL
        };
        return 0; // S_OK
    }
};

fn guidEql(a: *const winrt.GUID, b: *const winrt.GUID) bool {
    return a.Data1 == b.Data1 and a.Data2 == b.Data2 and a.Data3 == b.Data3 and
        std.mem.eql(u8, &a.Data4, &b.Data4);
}

// ---------------------------------------------------------------
// AppOuter — COM aggregation wrapper for Application
//
// WinUI 3 custom controls (TabView, etc.) require their XAML templates to be
// loaded via XamlControlsResources. The XAML framework discovers these templates
// by calling IXamlMetadataProvider on the Application object. In normal C++/WinRT
// apps, the XAML compiler generates this. Without a XAML compiler, we must
// implement the COM aggregation pattern manually:
//
//   1. AppOuter acts as the "outer" (controlling) IUnknown
//   2. IApplicationFactory::CreateInstance receives AppOuter as outer
//   3. The WinRT Application becomes the "inner" (non-delegating) object
//   4. QI for IXamlMetadataProvider → AppOuter handles it, delegating to
//      an activated XamlControlsXamlMetaDataProvider instance
//   5. QI for anything else → delegates to inner
// ---------------------------------------------------------------

const AppOuter = struct {
    /// The COM-visible IUnknown vtable pointer — must be at offset 0.
    iunknown: IUnknownVtblPtr,
    /// The IXamlMetadataProvider vtable pointer — at offset 8.
    imetadata: IMetadataVtblPtr,
    /// Reference count.
    ref_count: u32,
    /// The inner (non-delegating) IInspectable from Application.
    inner: ?*winrt.IInspectable,
    /// XamlControlsXamlMetaDataProvider instance for IXamlMetadataProvider delegation.
    provider: ?*com.IXamlMetadataProvider,

    const IUnknownVtblPtr = extern struct {
        lpVtbl: *const IUnknownVtbl,
    };
    const IUnknownVtbl = extern struct {
        QueryInterface: *const fn (*anyopaque, *const winrt.GUID, *?*anyopaque) callconv(.winapi) winrt.HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };

    const IMetadataVtblPtr = extern struct {
        lpVtbl: *const IMetadataVtbl,
    };
    const IMetadataVtbl = extern struct {
        // IUnknown (slots 0-2) — delegating to outer
        QueryInterface: *const fn (*anyopaque, *const winrt.GUID, *?*anyopaque) callconv(.winapi) winrt.HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: *const fn (*anyopaque, *u32, *?[*]winrt.GUID) callconv(.winapi) winrt.HRESULT,
        GetRuntimeClassName: *const fn (*anyopaque, *?winrt.HSTRING) callconv(.winapi) winrt.HRESULT,
        GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.winapi) winrt.HRESULT,
        // IXamlMetadataProvider (slots 6-8)
        GetXamlType: *const fn (*anyopaque, [*]const u8, *?*anyopaque) callconv(.winapi) winrt.HRESULT,
        GetXamlType_2: *const fn (*anyopaque, ?winrt.HSTRING, *?*anyopaque) callconv(.winapi) winrt.HRESULT,
        GetXmlnsDefinitions: *const fn (*anyopaque, *u32, *?[*]*anyopaque) callconv(.winapi) winrt.HRESULT,
    };

    const iunknown_vtable = IUnknownVtbl{
        .QueryInterface = &outerQueryInterface,
        .AddRef = &outerAddRef,
        .Release = &outerRelease,
    };

    const imetadata_vtable = IMetadataVtbl{
        .QueryInterface = &metadataQueryInterface,
        .AddRef = &metadataAddRef,
        .Release = &metadataRelease,
        .GetIids = &metadataGetIids,
        .GetRuntimeClassName = &metadataGetRuntimeClassName,
        .GetTrustLevel = &metadataGetTrustLevel,
        .GetXamlType = &metadataGetXamlType,
        .GetXamlType_2 = &metadataGetXamlType2,
        .GetXmlnsDefinitions = &metadataGetXmlnsDefinitions,
    };

    fn init(self: *AppOuter) void {
        self.* = .{
            .iunknown = .{ .lpVtbl = &iunknown_vtable },
            .imetadata = .{ .lpVtbl = &imetadata_vtable },
            .ref_count = 1,
            .inner = null,
            .provider = null,
        };
    }

    fn outerPtr(self: *AppOuter) *anyopaque {
        return @ptrCast(&self.iunknown);
    }

    fn fromIUnknownPtr(ptr: *anyopaque) *AppOuter {
        const p: *IUnknownVtblPtr = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("iunknown", p);
    }

    fn fromIMetadataPtr(ptr: *anyopaque) *AppOuter {
        const p: *IMetadataVtblPtr = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("imetadata", p);
    }

    // --- Outer IUnknown (controlling unknown) ---

    fn outerQueryInterface(this: *anyopaque, riid: *const winrt.GUID, ppv: *?*anyopaque) callconv(.winapi) winrt.HRESULT {
        const self = fromIUnknownPtr(this);
        const IID_IUnknown = winrt.GUID{ .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
        const IID_IAgileObject = winrt.GUID{ .Data1 = 0x94ea2b94, .Data2 = 0xe9cc, .Data3 = 0x49e0, .Data4 = .{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 } };

        // IXamlMetadataProvider → return our metadata interface
        if (guidEql(riid, &com.IXamlMetadataProvider.IID)) {
            ppv.* = @ptrCast(&self.imetadata);
            _ = outerAddRef(this);
            return 0; // S_OK
        }

        // IUnknown or IAgileObject → return outer
        if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IAgileObject)) {
            ppv.* = this;
            _ = outerAddRef(this);
            return 0; // S_OK
        }

        // Everything else → delegate to inner (non-delegating QI)
        if (self.inner) |inner| {
            return inner.lpVtbl.QueryInterface(@ptrCast(inner), riid, ppv);
        }

        ppv.* = null;
        return @bitCast(@as(u32, 0x80004002)); // E_NOINTERFACE
    }

    fn outerAddRef(this: *anyopaque) callconv(.winapi) u32 {
        const self = fromIUnknownPtr(this);
        self.ref_count += 1;
        return self.ref_count;
    }

    fn outerRelease(this: *anyopaque) callconv(.winapi) u32 {
        const self = fromIUnknownPtr(this);
        self.ref_count -= 1;
        return self.ref_count;
    }

    // --- IXamlMetadataProvider interface (delegating IUnknown to outer) ---

    fn metadataQueryInterface(this: *anyopaque, riid: *const winrt.GUID, ppv: *?*anyopaque) callconv(.winapi) winrt.HRESULT {
        const self = fromIMetadataPtr(this);
        return outerQueryInterface(@ptrCast(&self.iunknown), riid, ppv);
    }

    fn metadataAddRef(this: *anyopaque) callconv(.winapi) u32 {
        const self = fromIMetadataPtr(this);
        return outerAddRef(@ptrCast(&self.iunknown));
    }

    fn metadataRelease(this: *anyopaque) callconv(.winapi) u32 {
        const self = fromIMetadataPtr(this);
        return outerRelease(@ptrCast(&self.iunknown));
    }

    fn metadataGetIids(_: *anyopaque, count: *u32, iids: *?[*]winrt.GUID) callconv(.winapi) winrt.HRESULT {
        count.* = 0;
        iids.* = null;
        return 0; // S_OK
    }

    fn metadataGetRuntimeClassName(_: *anyopaque, name: *?winrt.HSTRING) callconv(.winapi) winrt.HRESULT {
        name.* = null;
        return 0; // S_OK
    }

    fn metadataGetTrustLevel(_: *anyopaque, level: *u32) callconv(.winapi) winrt.HRESULT {
        level.* = 0; // BaseTrust
        return 0; // S_OK
    }

    fn metadataGetXamlType(this: *anyopaque, type_name: [*]const u8, result: *?*anyopaque) callconv(.winapi) winrt.HRESULT {
        const self = fromIMetadataPtr(this);
        if (self.provider) |provider| {
            return provider.lpVtbl.GetXamlType(@ptrCast(provider), type_name, result);
        }
        result.* = null;
        return 0; // S_OK — return null IXamlType (type not found)
    }

    fn metadataGetXamlType2(this: *anyopaque, full_name: ?winrt.HSTRING, result: *?*anyopaque) callconv(.winapi) winrt.HRESULT {
        const self = fromIMetadataPtr(this);
        if (self.provider) |provider| {
            return provider.lpVtbl.GetXamlType_2(@ptrCast(provider), full_name, result);
        }
        result.* = null;
        return 0; // S_OK — return null IXamlType (type not found)
    }

    fn metadataGetXmlnsDefinitions(this: *anyopaque, count: *u32, definitions: *?[*]*anyopaque) callconv(.winapi) winrt.HRESULT {
        const self = fromIMetadataPtr(this);
        if (self.provider) |provider| {
            return provider.lpVtbl.GetXmlnsDefinitions(@ptrCast(provider), count, definitions);
        }
        count.* = 0;
        definitions.* = null;
        return 0; // S_OK
    }
};

/// The core application.
core_app: *CoreApp,

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
surfaces: std.ArrayList(*Surface),

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
        .surfaces = .{},
        .running = true,
    };

    // Window/UI creation happens inside run() via Application.Start(callback).
    // WinUI 3 requires Window creation on the XAML thread which is set up by Start().
    log.info("WinUI 3 runtime initialized (window creation deferred to run)", .{});
}

/// Called from inside Application.Start() callback — XAML thread is active here.
fn initXaml(self: *App) !void {
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
    const app_factory = try winrt.getActivationFactory(com.IApplicationFactory, app_class);
    defer app_factory.release();
    const result = try app_factory.createInstance(self.app_outer.outerPtr());
    self.app_outer.inner = result.inner;

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
    self.closed_handler = try event.SimpleEventHandler(App).create(alloc, self, &onWindowClosed);
    self.closed_token = try window.addClosed(self.closed_handler.?.comPtr());
    log.info("initXaml step 6 OK", .{});

    // Step 7: Activate the window (makes it visible).
    log.info("initXaml step 7: Activate...", .{});
    try window.activate();
    log.info("initXaml step 7 OK: Window activated!", .{});

    // Step 7.25: Load XamlControlsResources into Application.Resources.
    // Must be done AFTER Window creation/activation — the Application's Resources
    // property returns E_UNEXPECTED before the XAML framework is fully initialized.
    if (self.xaml_app) |xa| {
        loadXamlResources(xa);
    }

    // Step 7.5: Create TabView and set as Window content.
    // WinUI3 custom controls need XAML type system activation (IXamlType.ActivateInstance).
    // RoActivateInstance returns E_NOTIMPL for these controls.
    log.info("initXaml step 7.5: Creating TabView via XAML type system...", .{});
    const tab_view: ?*com.ITabView = blk: {
        const tv_inspectable = self.activateXamlType("Microsoft.UI.Xaml.Controls.TabView") catch |err| {
            log.warn("TabView creation failed ({}), falling back to single-tab mode", .{err});
            break :blk null;
        };
        const tv = tv_inspectable.queryInterface(com.ITabView) catch |err| {
            log.warn("TabView QI for ITabView failed ({}), falling back to single-tab mode", .{err});
            break :blk null;
        };
        window.putContent(@ptrCast(tv_inspectable)) catch |err| {
            log.warn("TabView putContent failed ({}), falling back to single-tab mode", .{err});
            tv.release();
            break :blk null;
        };
        log.info("initXaml step 7.5 OK: TabView set as Window content", .{});
        break :blk tv;
    };
    self.tab_view = tab_view;

    // Register TabView event handlers (only if TabView was created).
    if (tab_view != null) {
        self.tab_close_handler = try event.SimpleEventHandler(App).create(alloc, self, &onTabCloseRequested);
        self.tab_close_token = try tab_view.?.addTabCloseRequested(self.tab_close_handler.?.comPtr());
        self.add_tab_handler = try event.SimpleEventHandler(App).create(alloc, self, &onAddTabButtonClick);
        self.add_tab_token = try tab_view.?.addAddTabButtonClick(self.add_tab_handler.?.comPtr());
        self.selection_changed_handler = try event.SimpleEventHandler(App).create(alloc, self, &onSelectionChanged);
        self.selection_changed_token = try tab_view.?.addSelectionChanged(self.selection_changed_handler.?.comPtr());
        log.info("initXaml step 7.5 OK: TabView event handlers registered", .{});
    }

    // Step 8: Create the initial Surface (terminal) inside a TabViewItem.
    log.info("initXaml step 8: Creating initial Surface...", .{});
    var config = try configpkg.Config.load(alloc);
    defer config.deinit();

    var surface = try alloc.create(Surface);
    errdefer alloc.destroy(surface);
    try surface.init(self, self.core_app, &config);
    errdefer surface.deinit();

    try self.surfaces.append(alloc, surface);

    // Set the Surface's SwapChainPanel as content.
    if (surface.swap_chain_panel) |panel| {
        if (tab_view) |tv| {
            // TabView mode: wrap in TabViewItem.
            const tvi_inspectable = try self.activateXamlType("Microsoft.UI.Xaml.Controls.TabViewItem");

            const content_control = try tvi_inspectable.queryInterface(com.IContentControl);
            defer content_control.release();
            try content_control.putContent(@ptrCast(panel));

            const tab_items = try tv.getTabItems();
            try tab_items.append(@ptrCast(tvi_inspectable));

            surface.tab_view_item_inspectable = tvi_inspectable;

            try tv.putSelectedIndex(0);
            log.info("initXaml step 8 OK: Surface + TabViewItem added to TabView", .{});
        } else {
            // Fallback: set SwapChainPanel directly as Window content.
            try window.putContent(@ptrCast(panel));
            log.info("initXaml step 8 OK: Surface + SwapChainPanel set as Window content (single-tab)", .{});
        }
    }

    log.info("WinUI 3 Window created and activated (HWND=0x{x})", .{@intFromPtr(self.hwnd.?)});

    // Step 9: Find the WinUI3 child HWND (DesktopChildSiteBridge) for reference,
    // and create our own input HWND that sits on top for keyboard/IME focus.
    //
    // WinUI3's child HWND uses TSF (Text Services Framework) internally.
    // Subclassing it for IME doesn't work because TSF intercepts IME messages
    // at a higher level. Instead, we create a dedicated transparent child HWND
    // with a standard Win32 wndproc that receives all keyboard and IME messages
    // directly, completely bypassing WinUI3's input stack.
    const child = os.GetWindow(self.hwnd.?, os.GW_CHILD);
    if (child) |child_hwnd| {
        self.child_hwnd = child_hwnd;
        log.info("initXaml step 9: found WinUI3 child HWND=0x{x}", .{@intFromPtr(child_hwnd)});
    }

    // Create our input overlay HWND.
    self.input_hwnd = createInputWindow(self.hwnd.?, @intFromPtr(self));
    if (self.input_hwnd) |input_hwnd| {
        // Enable IME on our input HWND.
        _ = os.ImmAssociateContextEx(input_hwnd, null, os.IACE_DEFAULT);
        // Give it initial focus.
        _ = os.SetFocus(input_hwnd);
        log.info("initXaml step 9 OK: input HWND=0x{x} created + IME enabled", .{@intFromPtr(input_hwnd)});
    } else {
        log.warn("initXaml step 9: failed to create input HWND, falling back to child subclass", .{});
        // Fallback: subclass the child HWND directly (IME may not work).
        if (self.child_hwnd) |chw| {
            _ = os.SetWindowSubclass(chw, &subclassProc, 0, @intFromPtr(self));
            _ = os.ImmAssociateContextEx(chw, null, os.IACE_DEFAULT);
        }
    }
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
        _ = os.RemoveWindowSubclass(child_hwnd, &subclassProc, 0);
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
}

fn hardExitNow() noreturn {
    // Last-resort workaround for WinUI3 teardown crash on this branch.
    _ = windows.kernel32.TerminateProcess(windows.kernel32.GetCurrentProcess(), 0);
    unreachable;
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
}

pub fn terminate(self: *App) void {
    // Step 1: Destroy/remove input HWND and subclasses FIRST.
    // This prevents any further window messages from routing to our
    // handlers, which reference surfaces that we are about to free.
    if (self.input_hwnd) |input_hwnd| {
        _ = os.DestroyWindow(input_hwnd);
        self.input_hwnd = null;
    }
    if (self.child_hwnd) |child_hwnd| {
        _ = os.RemoveWindowSubclass(child_hwnd, &subclassProc, 0);
        self.child_hwnd = null;
    }
    if (self.root_hwnd) |root| {
        _ = os.RemoveWindowSubclass(root, &subclassProc, 1);
        self.root_hwnd = null;
    }
    if (self.hwnd) |hwnd| {
        _ = os.RemoveWindowSubclass(hwnd, &subclassProc, 0);
    }

    // Step 2: Close all remaining surfaces.
    // Surface.deinit() stops renderer and IO threads (joins them) before
    // freeing surface data, so this is safe after subclass removal.
    for (self.surfaces.items) |surface| {
        surface.deinit();
        self.core_app.alloc.destroy(surface);
    }
    self.surfaces.deinit(self.core_app.alloc);

    // Step 3: Unregister WinRT event handlers before freeing callback objects.
    if (self.tab_view) |tv| {
        if (self.tab_close_token) |tok| tv.removeTabCloseRequested(tok) catch {};
        if (self.add_tab_token) |tok| tv.removeAddTabButtonClick(tok) catch {};
        if (self.selection_changed_token) |tok| tv.removeSelectionChanged(tok) catch {};
    }
    if (self.window) |window| {
        if (self.closed_token) |tok| window.removeClosed(tok) catch {};
    }
    self.tab_close_token = null;
    self.add_tab_token = null;
    self.selection_changed_token = null;
    self.closed_token = null;

    // Step 4: Free callback wrapper objects after unregistration.
    if (self.closed_handler) |handler| self.core_app.alloc.destroy(handler);
    if (self.tab_close_handler) |handler| self.core_app.alloc.destroy(handler);
    if (self.add_tab_handler) |handler| self.core_app.alloc.destroy(handler);
    if (self.selection_changed_handler) |handler| self.core_app.alloc.destroy(handler);
    self.closed_handler = null;
    self.tab_close_handler = null;
    self.add_tab_handler = null;
    self.selection_changed_handler = null;

    // Step 5: Release WinRT/XAML objects.
    if (self.tab_view) |tv| tv.release();
    if (self.window) |window| window.release();
    if (self.xaml_app) |xa| xa.release();
    // Release COM aggregation resources.
    if (self.app_outer.provider) |provider| provider.release();
    self.app_outer.provider = null;
    // Note: inner is released by the Application itself during shutdown.
    self.tab_view = null;
    self.window = null;
    self.xaml_app = null;
    self.hwnd = null;
    self.child_hwnd = null;

    // Step 6: Shutdown WinRT and Windows App SDK.
    winrt.RoUninitialize();
    bootstrap.deinit();

    _ = os.timeEndPeriod(1);

    log.info("WinUI 3 application terminated", .{});
}

/// Thread-safe wakeup: any thread can call this to unblock the event loop.
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
            if (self.xaml_app) |xa| {
                xa.exit() catch {};
            }
            return true;
        },
        .new_window => {
            // MVP: single window only
            return false;
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
            self.setTitle(value.title);
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
fn newTab(self: *App) !void {
    const alloc = self.core_app.alloc;
    var config = try configpkg.Config.load(alloc);
    defer config.deinit();

    var surface = try alloc.create(Surface);
    errdefer alloc.destroy(surface);
    try surface.init(self, self.core_app, &config);

    try self.surfaces.append(alloc, surface);
    errdefer _ = self.surfaces.pop();

    // Create TabViewItem and add to TabView.
    const tab_view = self.tab_view orelse return error.AppInitFailed;
    const tvi_inspectable = try self.activateXamlType("Microsoft.UI.Xaml.Controls.TabViewItem");

    // Set tab content to the Surface's SwapChainPanel via IContentControl.
    const content_control = try tvi_inspectable.queryInterface(com.IContentControl);
    defer content_control.release();
    try content_control.putContent(@ptrCast(surface.swap_chain_panel));

    // Add to TabItems collection.
    const tab_items = try tab_view.getTabItems();
    try tab_items.append(@ptrCast(tvi_inspectable));

    // Store the IInspectable reference on the surface for later title updates.
    surface.tab_view_item_inspectable = tvi_inspectable;

    // Select the new tab.
    const size = try tab_items.getSize();
    try tab_view.putSelectedIndex(@intCast(size - 1));
    self.active_surface_idx = @intCast(size - 1);
}

/// Close the active tab and its surface.
fn closeActiveTab(self: *App) void {
    if (self.surfaces.items.len == 0) return;
    self.closeTab(self.active_surface_idx);
}

/// Close a specific tab by index.
pub fn closeTab(self: *App, idx: usize) void {
    if (idx >= self.surfaces.items.len) return;

    const surface = self.surfaces.items[idx];

    // Remove from TabView.
    if (self.tab_view) |tv| {
        const tab_items = tv.getTabItems() catch return;
        tab_items.removeAt(@intCast(idx)) catch {};
    }

    // Cleanup surface.
    surface.deinit();
    self.core_app.alloc.destroy(surface);
    _ = self.surfaces.orderedRemove(idx);

    // Adjust active index or quit if no tabs remain.
    if (self.surfaces.items.len == 0) {
        self.running = false;
        if (self.xaml_app) |xa| {
            xa.exit() catch {};
        }
    } else if (self.active_surface_idx >= self.surfaces.items.len) {
        self.active_surface_idx = self.surfaces.items.len - 1;
    }
}

/// Get the currently active Surface, or null if none.
fn activeSurface(self: *App) ?*Surface {
    if (self.surfaces.items.len == 0) return null;
    if (self.active_surface_idx >= self.surfaces.items.len) return null;
    return self.surfaces.items[self.active_surface_idx];
}

// ---------------------------------------------------------------
// TabView event callbacks
// ---------------------------------------------------------------

fn onTabCloseRequested(self: *App, _: *anyopaque, _: *anyopaque) void {
    self.closeActiveTab();
}

fn onAddTabButtonClick(self: *App, _: *anyopaque, _: *anyopaque) void {
    self.newTab() catch |err| {
        log.err("Failed to create new tab: {}", .{err});
    };
}

fn onSelectionChanged(self: *App, _: *anyopaque, _: *anyopaque) void {
    if (self.tab_view) |tv| {
        const idx = tv.getSelectedIndex() catch return;
        if (idx >= 0 and @as(usize, @intCast(idx)) < self.surfaces.items.len) {
            self.active_surface_idx = @intCast(idx);
        }
    }
}

// ---------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------

/// Activate a XAML type by name. Tries XAML type system first (via IXamlMetadataProvider),
/// falls back to RoActivateInstance for built-in types.
fn activateXamlType(self: *App, comptime class_name: [:0]const u8) !*winrt.IInspectable {
    // Try XAML type system first (required for WinUI3 custom controls like TabView).
    if (self.app_outer.provider) |provider| {
        const name = try winrt.hstring(class_name);
        defer winrt.deleteHString(name);
        if (provider.getXamlType(name)) |xaml_type| {
            defer xaml_type.release();
            return xaml_type.activateInstance();
        } else |_| {}
    }
    // Fallback to RoActivateInstance (works for base framework types).
    const name = try winrt.hstring(class_name);
    defer winrt.deleteHString(name);
    return winrt.activateInstance(name);
}

/// Load XamlControlsResources into Application.Resources.
/// This enables WinUI 3 custom controls (TabView, NavigationView, etc.)
/// to find their XAML templates. Without it, RoActivateInstance returns E_NOTIMPL.
fn loadXamlResources(xa: *com.IApplication) void {
    // The Application created via IApplicationFactory may not have Resources set.
    // get_Resources returns E_UNEXPECTED in that case. So we:
    // 1. Create a new ResourceDictionary
    // 2. Set it as Application.Resources via put_Resources
    // 3. Create XamlControlsResources
    // 4. Append XamlControlsResources to the ResourceDictionary's MergedDictionaries
    // This matches the C++/WinRT pattern: Resources().MergedDictionaries().Append(XamlControlsResources())

    // Step 1: Create a ResourceDictionary.
    const rd_class = winrt.hstring("Microsoft.UI.Xaml.ResourceDictionary") catch {
        log.warn("Failed to create ResourceDictionary HSTRING", .{});
        return;
    };
    defer winrt.deleteHString(rd_class);
    const rd_inspectable = winrt.activateInstance(rd_class) catch |err| {
        log.warn("ResourceDictionary creation failed: {}", .{err});
        return;
    };

    // Step 2: Set it as Application.Resources.
    xa.putResources(@ptrCast(rd_inspectable)) catch |err| {
        log.warn("Application.put_Resources failed: {}", .{err});
        return;
    };
    log.info("loadXamlResources: ResourceDictionary set on Application", .{});

    // Step 3: QI for IResourceDictionary to get MergedDictionaries.
    const res_dict = rd_inspectable.queryInterface(com.IResourceDictionary) catch |err| {
        log.warn("ResourceDictionary QI failed: {}", .{err});
        return;
    };
    defer res_dict.release();

    const merged = res_dict.getMergedDictionaries() catch |err| {
        log.warn("get_MergedDictionaries failed: {}", .{err});
        return;
    };

    // Step 4: Create XamlControlsResources and append to MergedDictionaries.
    const xcr_class = winrt.hstring("Microsoft.UI.Xaml.Controls.XamlControlsResources") catch {
        log.warn("Failed to create XamlControlsResources HSTRING", .{});
        return;
    };
    defer winrt.deleteHString(xcr_class);
    const xcr = winrt.activateInstance(xcr_class) catch |err| {
        log.warn("XamlControlsResources creation failed: {}", .{err});
        return;
    };

    merged.append(@ptrCast(xcr)) catch |err| {
        log.warn("MergedDictionaries.Append failed: {}", .{err});
        return;
    };
    log.info("initXaml step 0.5 OK: XamlControlsResources loaded via MergedDictionaries", .{});
}

fn drainMailbox(self: *App) void {
    self.core_app.tick(self) catch |err| {
        log.warn("tick error: {}", .{err});
    };
}

fn setTitle(self: *App, title: [:0]const u8) void {
    if (self.window) |window| {
        const h = winrt.hstringRuntime(title) catch return;
        defer winrt.deleteHString(h);
        window.putTitle(h) catch {};
    }
}

// ---------------------------------------------------------------
// HWND subclass procedure and per-message handlers
// ---------------------------------------------------------------

/// Win32 subclass procedure callback.
/// Installed via SetWindowSubclass on the WinUI 3 window's HWND to intercept
/// input messages before WinUI 3's own window procedure processes them.
fn subclassProc(
    hwnd: os.HWND,
    msg: os.UINT,
    wparam: os.WPARAM,
    lparam: os.LPARAM,
    _: usize,
    ref_data: usize,
) callconv(.winapi) os.LRESULT {
    const app: *App = @ptrFromInt(ref_data);

    switch (msg) {
        os.WM_CLOSE => hardExitNow(),
        os.WM_SYSCOMMAND => {
            const wp: usize = @bitCast(wparam);
            if ((wp & 0xFFF0) == os.SC_CLOSE) hardExitNow();
        },
        os.WM_ENTERSIZEMOVE => return handleEnterSizeMove(app, hwnd),
        os.WM_EXITSIZEMOVE => return handleExitSizeMove(app, hwnd),
        os.WM_TIMER => return handleTimer(app, hwnd, msg, wparam, lparam),
        os.WM_SIZE => return handleSize(app, hwnd, msg, wparam, lparam),
        os.WM_PAINT => return handlePaint(hwnd, msg, wparam, lparam),
        os.WM_ERASEBKGND => return 1,
        os.WM_KEYDOWN, os.WM_SYSKEYDOWN => return handleKeyInput(app, hwnd, msg, wparam, lparam, true),
        os.WM_KEYUP, os.WM_SYSKEYUP => return handleKeyInput(app, hwnd, msg, wparam, lparam, false),
        os.WM_CHAR => return handleChar(app, hwnd, msg, wparam, lparam),
        os.WM_MOUSEMOVE => return handleMouseMove(app, hwnd, msg, wparam, lparam),
        os.WM_LBUTTONDOWN => return handleMouseButton(app, hwnd, msg, wparam, lparam, .left, .press),
        os.WM_RBUTTONDOWN => return handleMouseButton(app, hwnd, msg, wparam, lparam, .right, .press),
        os.WM_MBUTTONDOWN => return handleMouseButton(app, hwnd, msg, wparam, lparam, .middle, .press),
        os.WM_LBUTTONUP => return handleMouseButton(app, hwnd, msg, wparam, lparam, .left, .release),
        os.WM_RBUTTONUP => return handleMouseButton(app, hwnd, msg, wparam, lparam, .right, .release),
        os.WM_MBUTTONUP => return handleMouseButton(app, hwnd, msg, wparam, lparam, .middle, .release),
        os.WM_MOUSEWHEEL => return handleScroll(app, hwnd, msg, wparam, lparam, .vertical),
        os.WM_MOUSEHWHEEL => return handleScroll(app, hwnd, msg, wparam, lparam, .horizontal),
        os.WM_DPICHANGED => return handleDpiChanged(app, hwnd, msg, wparam, lparam),
        os.WM_USER => return handleWakeup(app, hwnd, msg, wparam, lparam),
        os.WM_APP_BIND_SWAP_CHAIN => return handleBindSwapChain(wparam, lparam),
        // IME messages only handled in subclass as fallback (when input_hwnd failed).
        // When input_hwnd is active, IME messages go directly to inputWndProc.
        os.WM_IME_STARTCOMPOSITION => return handleIMEStartComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_COMPOSITION => return handleIMEComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_ENDCOMPOSITION => return handleIMEEndComposition(app, hwnd, msg, wparam, lparam),
        os.WM_SETFOCUS => {
            // When the main or child HWND receives focus, redirect to our input HWND
            // so that keyboard/IME messages go to inputWndProc instead of WinUI3's TSF.
            if (app.input_hwnd) |input_hwnd| {
                if (hwnd != input_hwnd) {
                    log.info("subclassProc: WM_SETFOCUS on HWND=0x{x}, redirecting to input HWND=0x{x}", .{ @intFromPtr(hwnd), @intFromPtr(input_hwnd) });
                    _ = os.SetFocus(input_hwnd);
                    return 0;
                }
            }
        },
        else => {},
    }

    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

// --- Individual message handlers ---

fn handleEnterSizeMove(app: *App, hwnd: os.HWND) os.LRESULT {
    app.resizing = true;
    _ = os.SetTimer(hwnd, RESIZE_TIMER_ID, 16, null);
    return 0;
}

fn handleExitSizeMove(app: *App, hwnd: os.HWND) os.LRESULT {
    _ = os.KillTimer(hwnd, RESIZE_TIMER_ID);
    app.resizing = false;
    if (app.pending_size) |sz| {
        if (app.activeSurface()) |surface| surface.updateSize(sz.width, sz.height);
        app.pending_size = null;
    }
    return 0;
}

fn handleTimer(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (app.pending_size) |sz| {
        if (app.activeSurface()) |surface| surface.updateSize(sz.width, sz.height);
        app.pending_size = null;
    }
    app.drainMailbox();
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleSize(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const width: u32 = @intCast(lp & 0xFFFF);
    const height: u32 = @intCast((lp >> 16) & 0xFFFF);
    if (app.resizing) {
        app.pending_size = .{ .width = width, .height = height };
    } else {
        if (app.activeSurface()) |surface| surface.updateSize(width, height);
    }
    // Resize the input overlay HWND to match.
    if (app.input_hwnd) |input_hwnd| {
        _ = os.MoveWindow(input_hwnd, 0, 0, @intCast(width), @intCast(height), 0);
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handlePaint(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    // Let WinUI 3 handle painting entirely via DefSubclassProc.
    // Do NOT call BeginPaint/EndPaint here — that would validate the
    // paint region and prevent WinUI 3's own rendering from running.
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleKeyInput(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM, pressed: bool) os.LRESULT {
    if (app.activeSurface()) |surface| {
        const wp: usize = @bitCast(wparam);
        surface.handleKeyEvent(@truncate(wp), pressed);
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleChar(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (app.activeSurface()) |surface| {
        const wp: usize = @bitCast(wparam);
        surface.handleCharEvent(@truncate(wp));
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleMouseMove(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (app.activeSurface()) |surface| {
        const lp: usize = @bitCast(lparam);
        const x: i16 = @bitCast(@as(u16, @truncate(lp)));
        const y: i16 = @bitCast(@as(u16, @truncate(lp >> 16)));
        surface.handleMouseMove(@floatFromInt(x), @floatFromInt(y));
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleMouseButton(
    app: *App,
    hwnd: os.HWND,
    msg: os.UINT,
    wparam: os.WPARAM,
    lparam: os.LPARAM,
    button: input.MouseButton,
    action: input.MouseButtonState,
) os.LRESULT {
    if (app.activeSurface()) |surface| {
        surface.handleMouseButton(button, action);
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

const ScrollDirection = enum { vertical, horizontal };

fn handleScroll(
    app: *App,
    hwnd: os.HWND,
    msg: os.UINT,
    wparam: os.WPARAM,
    lparam: os.LPARAM,
    direction: ScrollDirection,
) os.LRESULT {
    if (app.activeSurface()) |surface| {
        const wp: usize = @bitCast(wparam);
        const delta: i16 = @bitCast(@as(u16, @truncate(wp >> 16)));
        const offset = @as(f64, @floatFromInt(delta)) / 120.0;
        switch (direction) {
            .vertical => surface.handleScroll(0, offset),
            .horizontal => surface.handleScroll(offset, 0),
        }
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleDpiChanged(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (app.activeSurface()) |surface| surface.updateContentScale();
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
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleWakeup(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    app.drainMailbox();
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

/// Handle WM_APP_BIND_SWAP_CHAIN: complete swap chain binding on the UI thread.
/// wparam carries the swap chain pointer, lparam carries the Surface pointer.
fn handleBindSwapChain(wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const surface: *Surface = @ptrFromInt(@as(usize, @bitCast(lparam)));
    const swap_chain: *anyopaque = @ptrFromInt(@as(usize, @bitCast(wparam)));
    surface.completeBindSwapChain(swap_chain);
    return 0;
}

// ---------------------------------------------------------------
// IME (Input Method Editor) handlers for CJK text input
// ---------------------------------------------------------------

/// Dispatch to the correct default handler depending on whether hwnd is the
/// input overlay (plain wndproc) or a subclassed HWND.
inline fn imeDefProc(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (app.input_hwnd != null and app.input_hwnd.? == hwnd)
        return os.DefWindowProcW(hwnd, msg, wparam, lparam);
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleIMEStartComposition(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    log.info("IME: WM_IME_STARTCOMPOSITION on HWND=0x{x}", .{@intFromPtr(hwnd)});
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

fn handleIMEComposition(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const lp_flags: u32 = @truncate(lp);
    log.info("IME: WM_IME_COMPOSITION flags=0x{X:0>8} on HWND=0x{x}", .{ lp_flags, @intFromPtr(hwnd) });

    if (app.activeSurface()) |surface| {
        if (surface.core_initialized) {
            const himc = os.ImmGetContext(hwnd) orelse
                return imeDefProc(app, hwnd, msg, wparam, lparam);
            defer _ = os.ImmReleaseContext(hwnd, himc);

            // If a result string is ready, clear preedit.
            // The actual committed text arrives via WM_CHAR from DefWindowProc/DefSubclassProc.
            if (lp_flags & os.GCS_RESULTSTR != 0) {
                log.info("IME: GCS_RESULTSTR — clearing preedit, committed text via WM_CHAR", .{});
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
    // Must call the default handler so the system generates WM_CHAR for committed text.
    return imeDefProc(app, hwnd, msg, wparam, lparam);
}

fn handleIMEEndComposition(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    log.info("IME: WM_IME_ENDCOMPOSITION on HWND=0x{x}", .{@intFromPtr(hwnd)});
    if (app.activeSurface()) |surface| {
        if (surface.core_initialized) {
            surface.core_surface.preeditCallback(null) catch |err| {
                log.warn("IME preedit end error: {}", .{err});
            };
        }
    }
    return imeDefProc(app, hwnd, msg, wparam, lparam);
}

// ---------------------------------------------------------------
// Dedicated input HWND — bypasses WinUI3's TSF input stack
// ---------------------------------------------------------------

/// Window class name for our input overlay (UTF-16LE, null-terminated).
const INPUT_CLASS_NAME = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyInputOverlay");

/// Whether the input window class has been registered.
var input_class_registered: bool = false;

/// Create a transparent child HWND for keyboard/IME input.
/// This HWND is a standard Win32 window (not part of WinUI3's XAML tree)
/// so it receives IME messages via the legacy IMM32 path without TSF interference.
fn createInputWindow(parent: os.HWND, app_ptr: usize) ?os.HWND {
    // Register the window class once.
    if (!input_class_registered) {
        const wc = os.WNDCLASSEXW{
            .style = 0,
            .lpfnWndProc = &inputWndProc,
            .hInstance = os.GetModuleHandleW(null) orelse return null,
            .lpszClassName = INPUT_CLASS_NAME,
        };
        const atom = os.RegisterClassExW(&wc);
        if (atom == 0) {
            log.err("createInputWindow: RegisterClassExW failed", .{});
            return null;
        }
        input_class_registered = true;
    }

    // Get parent client rect for initial size.
    var rc: os.RECT = .{};
    _ = os.GetClientRect(parent, &rc);

    const hinstance = os.GetModuleHandleW(null) orelse return null;

    const hwnd = os.CreateWindowExW(
        0, // no WS_EX_TRANSPARENT — we want this window to receive mouse clicks
        INPUT_CLASS_NAME,
        INPUT_CLASS_NAME, // window name (unused)
        os.WS_CHILD | os.WS_VISIBLE, // child, visible
        0,
        0,
        rc.right - rc.left,
        rc.bottom - rc.top,
        parent,
        null,
        hinstance,
        null,
    );
    if (hwnd) |h| {
        // Store the App pointer in GWLP_USERDATA for the wndproc.
        _ = os.SetWindowLongPtrW(h, os.GWLP_USERDATA, app_ptr);
        return h;
    }
    log.err("createInputWindow: CreateWindowExW failed", .{});
    return null;
}

/// Window procedure for the dedicated input HWND.
/// Handles keyboard, IME, and mouse messages. Forwards everything else to DefWindowProc.
fn inputWndProc(
    hwnd: os.HWND,
    msg: os.UINT,
    wparam: os.WPARAM,
    lparam: os.LPARAM,
) callconv(.winapi) os.LRESULT {
    const app_ptr = os.GetWindowLongPtrW(hwnd, os.GWLP_USERDATA);
    if (app_ptr == 0) return os.DefWindowProcW(hwnd, msg, wparam, lparam);
    const app: *App = @ptrFromInt(app_ptr);

    switch (msg) {
        os.WM_KEYDOWN, os.WM_SYSKEYDOWN => {
            if (app.activeSurface()) |surface| {
                const wp: usize = @bitCast(wparam);
                surface.handleKeyEvent(@truncate(wp), true);
            }
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_KEYUP, os.WM_SYSKEYUP => {
            if (app.activeSurface()) |surface| {
                const wp: usize = @bitCast(wparam);
                surface.handleKeyEvent(@truncate(wp), false);
            }
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_CHAR => {
            if (app.activeSurface()) |surface| {
                const wp: usize = @bitCast(wparam);
                surface.handleCharEvent(@truncate(wp));
            }
            // Do NOT call DefWindowProcW for WM_CHAR — we consumed it.
            return 0;
        },
        os.WM_IME_STARTCOMPOSITION => return handleIMEStartComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_COMPOSITION => return handleIMEComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_ENDCOMPOSITION => return handleIMEEndComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_SETCONTEXT => {
            // Let the system draw the default IME UI (candidate window etc.)
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_IME_NOTIFY => {
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_MOUSEMOVE => {
            if (app.activeSurface()) |surface| {
                const lp: usize = @bitCast(lparam);
                const x: i16 = @bitCast(@as(u16, @truncate(lp)));
                const y: i16 = @bitCast(@as(u16, @truncate(lp >> 16)));
                surface.handleMouseMove(@floatFromInt(x), @floatFromInt(y));
            }
            return 0;
        },
        os.WM_LBUTTONDOWN => {
            // Ensure we keep focus when clicked.
            _ = os.SetFocus(hwnd);
            if (app.activeSurface()) |surface| surface.handleMouseButton(.left, .press);
            return 0;
        },
        os.WM_RBUTTONDOWN => {
            if (app.activeSurface()) |surface| surface.handleMouseButton(.right, .press);
            return 0;
        },
        os.WM_MBUTTONDOWN => {
            if (app.activeSurface()) |surface| surface.handleMouseButton(.middle, .press);
            return 0;
        },
        os.WM_LBUTTONUP => {
            if (app.activeSurface()) |surface| surface.handleMouseButton(.left, .release);
            return 0;
        },
        os.WM_RBUTTONUP => {
            if (app.activeSurface()) |surface| surface.handleMouseButton(.right, .release);
            return 0;
        },
        os.WM_MBUTTONUP => {
            if (app.activeSurface()) |surface| surface.handleMouseButton(.middle, .release);
            return 0;
        },
        os.WM_MOUSEWHEEL => {
            if (app.activeSurface()) |surface| {
                const wp: usize = @bitCast(wparam);
                const delta: i16 = @bitCast(@as(u16, @truncate(wp >> 16)));
                const offset = @as(f64, @floatFromInt(delta)) / 120.0;
                surface.handleScroll(0, offset);
            }
            return 0;
        },
        os.WM_MOUSEHWHEEL => {
            if (app.activeSurface()) |surface| {
                const wp: usize = @bitCast(wparam);
                const delta: i16 = @bitCast(@as(u16, @truncate(wp >> 16)));
                const offset = @as(f64, @floatFromInt(delta)) / 120.0;
                surface.handleScroll(offset, 0);
            }
            return 0;
        },
        os.WM_PAINT => {
            // Validate the paint region so Windows doesn't keep sending WM_PAINT.
            var ps: os.PAINTSTRUCT = .{};
            _ = os.BeginPaint(hwnd, &ps);
            _ = os.EndPaint(hwnd, &ps);
            return 0;
        },
        os.WM_ERASEBKGND => return 1, // Don't erase — transparent overlay.
        os.WM_SETFOCUS => {
            log.info("inputWndProc: WM_SETFOCUS received on input HWND=0x{x}", .{@intFromPtr(hwnd)});
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        os.WM_KILLFOCUS => {
            log.info("inputWndProc: WM_KILLFOCUS on input HWND=0x{x}, new focus=0x{x}", .{ @intFromPtr(hwnd), wparam });
            return os.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        else => {},
    }

    return os.DefWindowProcW(hwnd, msg, wparam, lparam);
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
