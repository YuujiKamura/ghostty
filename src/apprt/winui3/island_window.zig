/// XAML Islands host window — Windows Terminal IslandWindow equivalent.
///
/// Responsibilities:
///   - MakeWindow: RegisterClassExW + CreateWindowEx(WS_EX_NOREDIRECTIONBITMAP)
///   - Initialize: DesktopWindowXamlSource.Initialize(WindowId)
///   - OnSize: SiteBridge child HWND sizing (manual fallback if ResizePolicy unavailable)
///   - SetContent/Close: XAML root element lifecycle
///
/// Ref: github.com/microsoft/terminal/blob/main/src/cascadia/WindowsTerminal/IslandWindow.cpp
const std = @import("std");
const com = @import("com.zig");
const os = @import("os.zig");
const winrt = @import("winrt.zig");

const log = std.log.scoped(.winui3);

const IslandWindow = @This();

/// The top-level Win32 window HWND.
hwnd: os.HWND,

/// The DesktopWindowXamlSource COM object that hosts XAML content.
/// null until initialize() is called.
xaml_source: ?*com.IDesktopWindowXamlSource = null,

/// The SiteBridge child HWND (used for manual sizing when ResizePolicy is unavailable).
interop_hwnd: ?os.HWND = null,

/// Whether ResizePolicy is active (auto-sizes the island to match the parent).
/// If false, we fall back to manual SetWindowPos in onSize().
auto_resize: bool = false,

/// Window class name (UTF-16LE, null-terminated).
const CLASS_NAME = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindow");

/// Whether the window class has been registered.
var class_registered: bool = false;

/// WT: IslandWindow::MakeWindow()
///
/// Registers the window class (once) and creates the top-level HWND.
/// `app_ptr` is stored via lpParam → WM_CREATE → GWLP_USERDATA so the
/// wndproc can retrieve it.
pub fn makeWindow(app_ptr: *anyopaque, wndproc_fn: os.WNDPROC) !IslandWindow {
    const hinstance = os.GetModuleHandleW(null) orelse return error.WinRTFailed;

    // Register the window class once.
    if (!class_registered) {
        const wc = os.WNDCLASSEXW{
            .style = os.CS_HREDRAW | os.CS_VREDRAW,
            .lpfnWndProc = wndproc_fn,
            .hInstance = hinstance,
            .hCursor = os.LoadCursorW(null, os.IDC_ARROW),
            .hbrBackground = null,
            .lpszClassName = CLASS_NAME,
        };
        const atom = os.RegisterClassExW(&wc);
        if (atom == 0) {
            const err = os.GetLastError();
            // ERROR_CLASS_ALREADY_EXISTS (1410) is OK — class was registered
            // in a previous run or by another code path.
            if (err == 1410) {
                log.info("IslandWindow class already registered (err=1410), continuing", .{});
            } else {
                log.err("RegisterClassExW failed: err={}", .{err});
                return error.WinRTFailed;
            }
        } else {
            log.info("IslandWindow class registered (atom={})", .{atom});
        }
        class_registered = true;
    }

    const title = std.unicode.utf8ToUtf16LeStringLiteral("Ghostty");

    // Use a sensible default size (HD) instead of CW_USEDEFAULT which often
    // creates oversized windows.  Scale by system DPI so the window looks the
    // same size regardless of display scaling.  If config specifies
    // window-width/height, Surface.recomputeInitialSize will resize later.
    const base_width: c_int = 1280;
    const base_height: c_int = 960;
    const sys_dpi = os.GetDpiForSystem();
    const width = @divTrunc(base_width * @as(c_int, @intCast(sys_dpi)), 96);
    const height = @divTrunc(base_height * @as(c_int, @intCast(sys_dpi)), 96);

    const hwnd = os.CreateWindowExW(
        os.WS_EX_NOREDIRECTIONBITMAP,
        CLASS_NAME,
        title,
        os.WS_OVERLAPPEDWINDOW | os.WS_CLIPCHILDREN,
        os.CW_USEDEFAULT,
        os.CW_USEDEFAULT,
        width,
        height,
        null, // no parent
        null, // no menu
        hinstance,
        app_ptr, // passed to WM_CREATE as CREATESTRUCTW.lpCreateParams
    ) orelse {
        log.err("CreateWindowExW failed: err={}", .{os.GetLastError()});
        return error.WinRTFailed;
    };

    log.info("IslandWindow HWND created: 0x{x}", .{@intFromPtr(hwnd)});

    return IslandWindow{
        .hwnd = hwnd,
    };
}

/// WT: IslandWindow::Initialize()
///
/// Creates a DesktopWindowXamlSource via the activation factory,
/// initializes it with this window's HWND, and attempts to set the
/// ResizePolicy for automatic child sizing.
pub fn initialize(self: *IslandWindow) !void {
    // Create DesktopWindowXamlSource via its factory.
    const class_name = try winrt.hstring("Microsoft.UI.Xaml.Hosting.DesktopWindowXamlSource");
    defer winrt.deleteHString(class_name);

    const factory = try winrt.getActivationFactory(com.IDesktopWindowXamlSourceFactory, class_name);
    defer factory.release();

    const xs = try factory.createInstance();
    self.xaml_source = xs;
    log.info("DesktopWindowXamlSource created", .{});

    // Initialize with our window's WindowId.
    try xs.initialize(com.WindowId{ .Value = @intFromPtr(self.hwnd) });
    log.info("DesktopWindowXamlSource.Initialize(WindowId=0x{x}) OK", .{@intFromPtr(self.hwnd)});

    // Get SiteBridge for resize policy or manual HWND sizing.
    const site_bridge = xs.getSiteBridge() catch |err| {
        log.warn("getSiteBridge failed: {} — manual sizing disabled", .{err});
        return;
    };
    defer site_bridge.release();

    // NonClientIslandWindow needs manual island positioning so the XAML
    // content is offset below the DWM titlebar. ResizeContentToParentWindow
    // would make the island cover the entire parent (including caption buttons).
    // Always use manual sizing via the SiteBridge child HWND.
    self.interop_hwnd = os.GetWindow(self.hwnd, os.GW_CHILD);
    if (self.interop_hwnd) |ih| {
        log.info("Manual island sizing: interop_hwnd=0x{x}", .{@intFromPtr(ih)});
    } else {
        log.warn("Manual island sizing: no child HWND found", .{});
    }
    self.auto_resize = false;
}

/// WT: IslandWindow::SetContent()
///
/// Sets (or clears) the XAML root element hosted by the DesktopWindowXamlSource.
pub fn setContent(self: *IslandWindow, content: ?*anyopaque) !void {
    const xs = self.xaml_source orelse return error.WinRTFailed;
    try xs.setContent(content);
    if (content != null) {
        log.info("IslandWindow.setContent: content set", .{});
    } else {
        log.info("IslandWindow.setContent: content cleared (null)", .{});
    }
}

/// WT: IslandWindow::OnSize()
///
/// When using manual sizing (no ResizePolicy), resizes the interop HWND
/// to match the given client dimensions. When auto_resize is true, this
/// is a no-op since the SiteBridge handles sizing automatically.
pub fn onSize(self: *IslandWindow, width: c_int, height: c_int) void {
    if (self.auto_resize) return;

    const ih = self.interop_hwnd orelse return;
    _ = os.SetWindowPos(
        ih,
        null, // HWND_TOP
        0,
        0,
        width,
        height,
        os.SWP_SHOWWINDOW,
    );
}

/// WT: IslandWindow::Close()
///
/// Follows Windows Terminal's close sequence to prevent leaks:
///   1. SetContent(null) — detach XAML tree
///   2. xaml_source.Close() — release the XAML Islands host
///   3. DestroyWindow — destroy the Win32 HWND
pub fn close(self: *IslandWindow) void {
    if (self.xaml_source) |xs| {
        // Step 1: detach content.
        xs.setContent(null) catch |err| {
            log.warn("IslandWindow.close: setContent(null) failed: {}", .{err});
        };

        // Step 2: close the xaml source (IClosable).
        xs.close() catch |err| {
            log.warn("IslandWindow.close: xaml_source.close() failed: {}", .{err});
        };

        // Step 3: release COM reference.
        xs.release();
        self.xaml_source = null;
    }

    // Step 4: destroy the Win32 HWND.
    _ = os.DestroyWindow(self.hwnd);

    log.info("IslandWindow closed", .{});
}

/// WNDPROC type alias matching os.zig's WNDCLASSEXW expectation.
pub const WNDPROC = *const fn (os.HWND, os.UINT, os.WPARAM, os.LPARAM) callconv(.winapi) os.LRESULT;
