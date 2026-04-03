const std = @import("std");
const log = std.log.scoped(.winui3);
const winrt = @import("winrt.zig");
const sdk = @import("sdk_version.zig");

const HRESULT = winrt.HRESULT;

// Dynamic DLL directory registration to avoid manifest SxS hell.
extern "kernel32" fn SetDllDirectoryW(lpPathName: ?[*:0]const u16) callconv(.winapi) std.os.windows.BOOL;

const MddBootstrapInitializeFn = *const fn (u32, [*:0]const u16, u64) callconv(.winapi) HRESULT;
const MddBootstrapShutdownFn = *const fn () callconv(.winapi) void;

var module_handle: ?std.os.windows.HMODULE = null;
var shutdown_fn: ?MddBootstrapShutdownFn = null;

/// Initialize the Windows App SDK runtime.
/// Strategy: register DLL search path (always needed), then try MddBootstrapInitialize.
/// If DDLM is missing, log a warning and continue — winrt.zig has a DllGetActivationFactory
/// fallback that activates WinRT classes directly from app-local DLLs (#186).
pub fn init() winrt.WinRTError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Step 1: Resolve the path to bundled runtime DLLs relative to ghostty.exe.
    // Also check exe directory itself for self-contained deployments.
    const self_exe_path = std.fs.selfExeDirPathAlloc(alloc) catch ".";
    const prebuilt_dir = std.fs.path.join(alloc, &.{ self_exe_path, "..", "..", "xaml", "prebuilt", "runtime", "x64" }) catch ".";

    // Prefer exe-local DLLs (self-contained), fall back to prebuilt dir (dev builds).
    const app_local_dll = std.fs.path.join(alloc, &.{ self_exe_path, "Microsoft.WindowsAppRuntime.dll" }) catch ".";
    const runtime_dir = if (std.fs.accessAbsolute(app_local_dll, .{})) |_| self_exe_path else |_| prebuilt_dir;

    // Step 2: Register this directory so the OS can find all WinUI 3 dependencies.
    const runtime_dir_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, runtime_dir) catch return error.WinRTFailed;
    _ = SetDllDirectoryW(runtime_dir_w.ptr);
    log.info("Windows App SDK runtime DLL path: {s}", .{runtime_dir});

    // Step 3: Try MddBootstrapInitialize (framework-dependent path).
    // This succeeds when DDLM is installed. If it fails, we continue anyway —
    // winrt.zig's DllGetActivationFactory fallback handles class activation.
    const dll_name = "Microsoft.WindowsAppRuntime.Bootstrap.dll";
    const dll_name_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, dll_name) catch return error.WinRTFailed;

    const module = std.os.windows.kernel32.LoadLibraryW(@ptrCast(dll_name_w.ptr)) orelse {
        log.warn("Bootstrap DLL not found — running in self-contained mode", .{});
        return;
    };
    module_handle = module;

    const init_fn_ptr = std.os.windows.kernel32.GetProcAddress(module, "MddBootstrapInitialize") orelse {
        log.warn("MddBootstrapInitialize not found in Bootstrap DLL — running in self-contained mode", .{});
        return;
    };
    const init_fn: MddBootstrapInitializeFn = @ptrCast(init_fn_ptr);

    shutdown_fn = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "MddBootstrapShutdown") orelse null);

    const hr = init_fn(sdk.bootstrap_majorminor, &sdk.bootstrap_version_tag, sdk.runtime_version);
    if (hr < 0) {
        const hr_u = @as(u32, @bitCast(hr));
        if (hr_u == 0x80670016) {
            // DDLM not installed — not fatal, winrt.zig fallback will handle activation.
            log.warn("DDLM not installed (0x80670016) — continuing with DllGetActivationFactory fallback", .{});
            return;
        }
        // Other bootstrap errors are still fatal.
        log.err("MddBootstrapInitialize failed: 0x{x:0>8}", .{hr_u});
        return error.WinRTFailed;
    }

    log.info("Windows App SDK runtime initialized via MddBootstrapInitialize ({s})", .{runtime_dir});
}

pub fn deinit() void {
    if (shutdown_fn) |f| f();
    if (module_handle) |handle| _ = std.os.windows.kernel32.FreeLibrary(handle);
    // Reset DLL search path.
    _ = SetDllDirectoryW(null);
    log.info("Windows App SDK bootstrap shutdown", .{});
}
