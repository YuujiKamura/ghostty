const std = @import("std");
const win = std.os.windows;

const HRESULT = i32;

pub fn main() !void {
    std.debug.print("=== Ghostty WinUI3 Preflight Check (V4) ===\n\n", .{});

    // 1. Check if the DLL exists in the SAME directory
    const bootstrap_dll = "Microsoft.WindowsAppRuntime.Bootstrap.dll";
    std.debug.print("[1/2] Checking {s} in current directory: ", .{bootstrap_dll});
    
    std.fs.cwd().access(bootstrap_dll, .{}) catch |err| {
        std.debug.print("MISSING ({s})\n", .{@errorName(err)});
        return;
    };
    std.debug.print("EXISTS\n", .{});

    // 2. Try LoadLibraryW
    const bootstrap_dll_w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, bootstrap_dll) catch return;
    defer std.heap.page_allocator.free(bootstrap_dll_w);

    const h_bootstrap = win.kernel32.LoadLibraryW(@ptrCast(bootstrap_dll_w.ptr));
    if (h_bootstrap) |h| {
        defer _ = win.kernel32.FreeLibrary(h);
        std.debug.print("      OK (Loaded: {*})\n", .{h});
    } else {
        const err = win.kernel32.GetLastError();
        std.debug.print("      FAILED (Error: {d})\n", .{err});
    }

    // 3. Check XAML DLL
    const xaml_dll = "Microsoft.ui.xaml.dll";
    std.debug.print("[2/2] Checking {s}: ", .{xaml_dll});
    const xaml_dll_w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, xaml_dll) catch return;
    defer std.heap.page_allocator.free(xaml_dll_w);
    const h_xaml = win.kernel32.LoadLibraryW(@ptrCast(xaml_dll_w.ptr));
    if (h_xaml) |h| {
        defer _ = win.kernel32.FreeLibrary(h);
        std.debug.print("OK (Loaded: {*})\n", .{h});
    } else {
        const err = win.kernel32.GetLastError();
        std.debug.print("FAILED (Error: {d})\n", .{err});
    }
}
