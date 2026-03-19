//! Windows App SDK bootstrap.
//!
//! Loads the Windows App SDK runtime via MddBootstrapInitialize.
//! This is the dynamic-dependency equivalent of linking against
//! Microsoft.WindowsAppRuntime.Bootstrap.dll.
//!
//! The bootstrap DLL is loaded dynamically via LoadLibrary so that
//! Ghostty can produce a meaningful error if the SDK is not installed.

const std = @import("std");
const log = std.log.scoped(.winui3);
const winrt = @import("winrt.zig");

const HRESULT = winrt.HRESULT;

/// Windows App SDK version constants.
/// Target 1.4 stable (has DDLM + Main packages on this machine).
/// MAJORMINOR is encoded as 0xMMMMNNNN where M=Major, N=Minor.
const WINDOWSAPPSDK_RELEASE_MAJORMINOR: u32 = 0x00010004; // 1.4
const WINDOWSAPPSDK_RELEASE_VERSION_TAG_W = [_:0]u16{}; // stable (no tag)
/// Minimum runtime package version. 0 = accept any version matching majorMinor.
const WINDOWSAPPSDK_RUNTIME_VERSION_UINT64: u64 = 0;

/// MddBootstrapInitialize takes 3 params: (majorMinor, versionTag, minVersion).
/// Note: MddBootstrapInitialize2 takes 4 params (adds options) — do NOT mix them up.
const MddBootstrapInitializeFn = *const fn (u32, [*:0]const u16, u64) callconv(.winapi) HRESULT;
const MddBootstrapShutdownFn = *const fn () callconv(.winapi) void;

var module_handle: ?std.os.windows.HMODULE = null;
var shutdown_fn: ?MddBootstrapShutdownFn = null;

/// Initialize the Windows App SDK runtime.
/// Must be called before any WinUI 3 / Windows App SDK APIs.
pub fn init() winrt.WinRTError!void {
    // Try to load the bootstrap DLL from PATH or system directory.
    const dll_name = comptime blk: {
        const name = "Microsoft.WindowsAppRuntime.Bootstrap.dll";
        var buf: [name.len:0]u16 = undefined;
        for (name, 0..) |c, i| buf[i] = c;
        break :blk buf;
    };

    const module = std.os.windows.kernel32.LoadLibraryW(&dll_name) orelse {
        log.err("Windows App SDK not found. Install from: https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads", .{});
        return error.WinRTFailed;
    };
    module_handle = module;

    const init_fn_ptr = std.os.windows.kernel32.GetProcAddress(
        module,
        "MddBootstrapInitialize",
    ) orelse {
        log.err("MddBootstrapInitialize not found in bootstrap DLL", .{});
        return error.WinRTFailed;
    };
    const init_fn: MddBootstrapInitializeFn = @ptrCast(init_fn_ptr);

    shutdown_fn = @ptrCast(std.os.windows.kernel32.GetProcAddress(
        module,
        "MddBootstrapShutdown",
    ) orelse {
        log.err("MddBootstrapShutdown not found in bootstrap DLL", .{});
        return error.WinRTFailed;
    });

    const v_major_minor = WINDOWSAPPSDK_RELEASE_MAJORMINOR;
    const v_tag: [*:0]const u16 = &WINDOWSAPPSDK_RELEASE_VERSION_TAG_W;
    const v_min_ver = WINDOWSAPPSDK_RUNTIME_VERSION_UINT64;

    std.debug.print("bootstrap: CALLING MddBootstrapInitialize(0x{x:0>8}, {*}, 0x{x:0>16})\n", .{
        v_major_minor,
        v_tag,
        v_min_ver,
    });

    const hr = init_fn(v_major_minor, v_tag, v_min_ver);

    std.debug.print("bootstrap: RETURNED hr=0x{x:0>8}\n", .{@as(u32, @bitCast(hr))});

    std.debug.print(
        "bootstrap: MddBootstrapInitialize hr=0x{x:0>8} majorMinor=0x{x:0>8} minVersion=0x{x:0>16}\n",
        .{
            @as(u32, @bitCast(hr)),
            WINDOWSAPPSDK_RELEASE_MAJORMINOR,
            WINDOWSAPPSDK_RUNTIME_VERSION_UINT64,
        },
    );

    log.err(
        "MddBootstrapInitialize hr=0x{x:0>8} majorMinor=0x{x:0>8} minVersion=0x{x:0>16}",
        .{
            @as(u32, @bitCast(hr)),
            WINDOWSAPPSDK_RELEASE_MAJORMINOR,
            WINDOWSAPPSDK_RUNTIME_VERSION_UINT64,
        },
    );

    if (hr < 0) {
        log.err("MddBootstrapInitialize failed: 0x{x:0>8}. Is Windows App SDK 1.4+ installed?", .{@as(u32, @bitCast(hr))});
        return error.WinRTFailed;
    }

    log.info("Windows App SDK bootstrap initialized", .{});
}

/// Shutdown the Windows App SDK runtime.
pub fn deinit() void {
    if (shutdown_fn) |f| {
        f();
        shutdown_fn = null;
    }
    if (module_handle) |handle| {
        _ = std.os.windows.kernel32.FreeLibrary(handle);
        module_handle = null;
    }
    log.info("Windows App SDK bootstrap shutdown", .{});
}
