/// WinUI 3 application runtime for Ghostty.
///
/// Phase 3: Bootstraps Windows App SDK, initializes WinRT, creates a
/// WinUI 3 Window with HWND subclass message routing, creates a TabView
/// for multi-tab management, and routes input to the active Surface.
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
        const IID_IUnknown = winrt.GUID{ .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000,
            .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
        const IID_IAgileObject = winrt.GUID{ .Data1 = 0x94ea2b94, .Data2 = 0xe9cc, .Data3 = 0x49e0,
            .Data4 = .{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 } };
        const IID_Self = winrt.GUID{ .Data1 = 0xd8eef1c9, .Data2 = 0x1234, .Data3 = 0x56f1,
            .Data4 = .{ 0x99, 0x63, 0x45, 0xdd, 0x9c, 0x80, 0xa6, 0x61 } };

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

/// The core application.
core_app: *CoreApp,

/// The WinUI 3 Window.
window: ?*com.IWindow = null,

/// The native HWND obtained from IWindowNative.
hwnd: ?os.HWND = null,

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

/// TabView event handlers.
tab_close_handler: ?*event.SimpleEventHandler(App) = null,
add_tab_handler: ?*event.SimpleEventHandler(App) = null,
selection_changed_handler: ?*event.SimpleEventHandler(App) = null,

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

    // Step 0: Create the Application instance via IApplicationFactory.
    // Application.Start() does NOT create an Application — the callback must.
    // This sets Application.Current and initializes XAML resource management.
    const app_class = try winrt.hstring("Microsoft.UI.Xaml.Application");
    defer winrt.deleteHString(app_class);
    log.info("initXaml step 0: Creating Application instance...", .{});
    const app_factory = try winrt.getActivationFactory(com.IApplicationFactory, app_class);
    defer app_factory.release();
    const app_instance = try app_factory.createInstance();
    _ = app_instance; // Kept alive — Application.Current is now set
    log.info("initXaml step 0 OK: Application created", .{});

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

    // Step 5: Install subclass on the HWND.
    log.info("initXaml step 5: SetWindowSubclass...", .{});
    _ = os.SetWindowSubclass(self.hwnd.?, &subclassProc, 0, @intFromPtr(self));
    log.info("initXaml step 5 OK", .{});

    // Step 6: Register Closed event handler.
    log.info("initXaml step 6: addClosed handler...", .{});
    const alloc = self.core_app.alloc;
    self.closed_handler = try event.SimpleEventHandler(App).create(alloc, self, &onWindowClosed);
    _ = try window.addClosed(self.closed_handler.?.comPtr());
    log.info("initXaml step 6 OK", .{});

    // Step 7: Activate the window (makes it visible).
    log.info("initXaml step 7: Activate...", .{});
    try window.activate();
    log.info("initXaml step 7 OK: Window activated!", .{});

    log.info("WinUI 3 Window created and activated (HWND=0x{x})", .{@intFromPtr(self.hwnd.?)});
}

/// Closed event callback — triggered when the user closes the window.
fn onWindowClosed(self: *App, _: *anyopaque, _: *anyopaque) void {
    self.running = false;
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
    // Close all surfaces.
    for (self.surfaces.items) |surface| {
        surface.deinit();
        self.core_app.alloc.destroy(surface);
    }
    self.surfaces.deinit(self.core_app.alloc);

    // Remove the HWND subclass before closing the window.
    if (self.hwnd) |hwnd| {
        _ = os.RemoveWindowSubclass(hwnd, &subclassProc, 0);
    }

    // Release event handlers.
    if (self.closed_handler) |handler| {
        self.core_app.alloc.destroy(handler);
        self.closed_handler = null;
    }
    if (self.tab_close_handler) |handler| {
        self.core_app.alloc.destroy(handler);
        self.tab_close_handler = null;
    }
    if (self.add_tab_handler) |handler| {
        self.core_app.alloc.destroy(handler);
        self.add_tab_handler = null;
    }
    if (self.selection_changed_handler) |handler| {
        self.core_app.alloc.destroy(handler);
        self.selection_changed_handler = null;
    }

    // Release TabView.
    if (self.tab_view) |tv| {
        tv.release();
        self.tab_view = null;
    }

    if (self.window) |window| {
        window.close() catch {};
        window.release();
        self.window = null;
    }

    self.hwnd = null;

    // Shutdown WinRT and Windows App SDK.
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
    const tvi_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.TabViewItem");
    defer winrt.deleteHString(tvi_class);
    const tvi_inspectable = try winrt.activateInstance(tvi_class);

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
        os.WM_IME_STARTCOMPOSITION => return handleIMEStartComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_COMPOSITION => return handleIMEComposition(app, hwnd, msg, wparam, lparam),
        os.WM_IME_ENDCOMPOSITION => return handleIMEEndComposition(app, hwnd, msg, wparam, lparam),
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

// ---------------------------------------------------------------
// IME (Input Method Editor) handlers for CJK text input
// ---------------------------------------------------------------

fn handleIMEStartComposition(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (app.activeSurface()) |surface| {
        if (surface.core_initialized) {
            const himc = os.ImmGetContext(hwnd) orelse
                return os.DefSubclassProc(hwnd, msg, wparam, lparam);
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
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleIMEComposition(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    const lp: usize = @bitCast(lparam);
    const lp_flags: u32 = @truncate(lp);

    if (app.activeSurface()) |surface| {
        if (surface.core_initialized) {
            const himc = os.ImmGetContext(hwnd) orelse
                return os.DefSubclassProc(hwnd, msg, wparam, lparam);
            defer _ = os.ImmReleaseContext(hwnd, himc);

            // If a result string is ready, clear preedit.
            // The actual committed text arrives via WM_CHAR from DefSubclassProc.
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
    // Must call DefSubclassProc so the system generates WM_CHAR for committed text.
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
}

fn handleIMEEndComposition(app: *App, hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT {
    if (app.activeSurface()) |surface| {
        if (surface.core_initialized) {
            surface.core_surface.preeditCallback(null) catch |err| {
                log.warn("IME preedit end error: {}", .{err});
            };
        }
    }
    return os.DefSubclassProc(hwnd, msg, wparam, lparam);
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
