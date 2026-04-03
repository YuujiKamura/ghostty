const std = @import("std");
const log = std.log.scoped(.winui3);
const winrt = @import("winrt.zig");

const HRESULT = winrt.HRESULT;

// Dynamic DLL directory registration to avoid manifest SxS hell.
extern "kernel32" fn SetDllDirectoryW(lpPathName: ?[*:0]const u16) callconv(.winapi) std.os.windows.BOOL;

/// Windows App SDK version constants.
const WINDOWSAPPSDK_RELEASE_MAJORMINOR: u32 = 0x00010006; // 1.6
const WINDOWSAPPSDK_RELEASE_VERSION_TAG_W = [_:0]u16{}; // stable
const WINDOWSAPPSDK_RUNTIME_VERSION_UINT64: u64 = 0;

const MddBootstrapInitializeFn = *const fn (u32, [*:0]const u16, u64) callconv(.winapi) HRESULT;
const MddBootstrapShutdownFn = *const fn () callconv(.winapi) void;

var module_handle: ?std.os.windows.HMODULE = null;
var shutdown_fn: ?MddBootstrapShutdownFn = null;

/// Initialize the Windows App SDK runtime.
pub fn init() winrt.WinRTError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Step 1: Resolve the path to bundled runtime DLLs relative to ghostty.exe.
    // In prebuilt mode, they are at: ../../xaml/prebuilt/runtime/x64/
    const self_exe_path = std.fs.selfExeDirPathAlloc(alloc) catch ".";
    const runtime_dir = std.fs.path.join(alloc, &.{ self_exe_path, "..", "..", "xaml", "prebuilt", "runtime", "x64" }) catch ".";

    // Step 2: Register this directory so the OS can find all WinUI 3 dependencies.
    const runtime_dir_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, runtime_dir) catch return error.WinRTFailed;
    _ = SetDllDirectoryW(runtime_dir_w.ptr);

    // Step 3: Load the bootstrap DLL by name (now that its directory is registered).
    const dll_name = "Microsoft.WindowsAppRuntime.Bootstrap.dll";
    const dll_name_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, dll_name) catch return error.WinRTFailed;

    const module = std.os.windows.kernel32.LoadLibraryW(@ptrCast(dll_name_w.ptr)) orelse {
        const err = std.os.windows.kernel32.GetLastError();
        log.err("Bootstrap DLL not found at {s}. Error: {d}", .{ runtime_dir, err });
        return error.WinRTFailed;
    };
    module_handle = module;

    // Step 4: Get function pointers and initialize.
    const init_fn_ptr = std.os.windows.kernel32.GetProcAddress(module, "MddBootstrapInitialize") orelse return error.WinRTFailed;
    const init_fn: MddBootstrapInitializeFn = @ptrCast(init_fn_ptr);

    shutdown_fn = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "MddBootstrapShutdown") orelse return error.WinRTFailed);

    const hr = init_fn(WINDOWSAPPSDK_RELEASE_MAJORMINOR, &WINDOWSAPPSDK_RELEASE_VERSION_TAG_W, WINDOWSAPPSDK_RUNTIME_VERSION_UINT64);
    if (hr < 0) {
        log.err("MddBootstrapInitialize failed: 0x{x:0>8}", .{@as(u32, @bitCast(hr))});
        if (@as(u32, @bitCast(hr)) == 0x80670016) {
            log.err("Windows App SDK Runtime is not installed or incomplete.", .{});
            log.err("Download and run: https://aka.ms/windowsappsdk/1.6/latest/windowsappruntimeinstall-x64.exe", .{});
        }
        return error.WinRTFailed;
    }

    log.info("Windows App SDK runtime initialized via dynamic path: {s}", .{runtime_dir});
}

pub fn deinit() void {
    if (shutdown_fn) |f| f();
    if (module_handle) |handle| _ = std.os.windows.kernel32.FreeLibrary(handle);
    // Reset DLL search path.
    _ = SetDllDirectoryW(null);
    log.info("Windows App SDK bootstrap shutdown", .{});
}
