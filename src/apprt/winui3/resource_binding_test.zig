const std = @import("std");
const builtin = @import("builtin");
const com = @import("com.zig");
const winrt = @import("winrt.zig");

const testing = std.testing;

const AssetMetadata = struct {
    sha256: []const u8,
    size: u64,
};

const Manifest = struct {
    sources: std.json.Value,
    prebuilt: struct {
        @"ghostty.pri": AssetMetadata,
        @"Surface.xbf": AssetMetadata,
        @"TabViewRoot.xbf": AssetMetadata,
    },
};

// --- External Windows APIs ---
extern "ole32" fn CoTaskMemFree(pv: ?*anyopaque) callconv(.winapi) void;
extern "kernel32" fn SetDllDirectoryW(lpPathName: ?[*:0]const u16) callconv(.winapi) std.os.windows.BOOL;

fn hashFileLower(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    const bytes = try std.fs.cwd().readFileAlloc(alloc, path, 2 * 1024 * 1024);
    defer alloc.free(bytes);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});

    var buf: [64]u8 = undefined;
    for (digest, 0..) |byte, i| {
        _ = try std.fmt.bufPrint(buf[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte});
    }
    return alloc.dupe(u8, &buf);
}

fn verifyAsset(alloc: std.mem.Allocator, path: []const u8, expected: AssetMetadata) !void {
    const stat = try std.fs.cwd().statFile(path);
    try testing.expectEqual(expected.size, stat.size);

    const hash = try hashFileLower(alloc, path);
    defer alloc.free(hash);
    try testing.expectEqualStrings(expected.sha256, hash);
}

fn createResourceManagerForPri(alloc: std.mem.Allocator, dll_path: []const u8, pri_path: []const u8) !void {
    const utf16 = try alloc.alloc(u16, dll_path.len + 1);
    defer alloc.free(utf16);
    const utf16_len = try std.unicode.utf8ToUtf16Le(utf16[0..dll_path.len], dll_path);
    utf16[utf16_len] = 0;

    const module = std.os.windows.kernel32.LoadLibraryW(@ptrCast(utf16.ptr)) orelse return error.WinRTFailed;
    
    // Log the actual loaded path
    var path_buf: [260:0]u16 = undefined;
    const path_len = std.os.windows.kernel32.GetModuleFileNameW(module, &path_buf, path_buf.len);
    const actual_path = try std.unicode.utf16LeToUtf8Alloc(alloc, path_buf[0..path_len]);
    defer alloc.free(actual_path);
    std.debug.print("\n[DEBUG] Loaded Resources DLL: {s}\n", .{actual_path});

    const DllGetActivationFactoryFn = *const fn (winrt.HSTRING, *?*anyopaque) callconv(.winapi) i32;
    const get_factory_fn: DllGetActivationFactoryFn = @ptrCast(std.os.windows.kernel32.GetProcAddress(
        module,
        "DllGetActivationFactory",
    ) orelse return error.WinRTFailed);

    const class_name = try winrt.hstring("Microsoft.Windows.ApplicationModel.Resources.ResourceManager");
    defer winrt.deleteHString(class_name);

    var factory_raw: ?*anyopaque = null;
    try winrt.hrCheck(get_factory_fn(class_name, &factory_raw));
    const activation_factory: *winrt.IActivationFactory = @ptrCast(@alignCast(factory_raw orelse return error.WinRTFailed));
    defer activation_factory.release();

    // PROBE: List all implemented IIDs
    const inspectable: *winrt.IInspectable = @ptrCast(activation_factory);
    var iid_count: u32 = 0;
    var iids_ptr: ?*winrt.GUID = null;
    // GetIids takes (*anyopaque, *u32, **GUID)
    try winrt.hrCheck(inspectable.lpVtbl.GetIids(inspectable, &iid_count, @ptrCast(&iids_ptr)));
    if (iids_ptr) |iids| {
        defer CoTaskMemFree(@ptrCast(iids));
        const iid_slice: [*]winrt.GUID = @ptrCast(iids);
        std.debug.print("\n[PROBE] Factory implements {d} interfaces:\n", .{iid_count});
        for (iid_slice[0..iid_count], 0..) |guid, i| {
            std.debug.print("  [{d}] {x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}\n", .{
                i,
                guid.data1,
                guid.data2,
                guid.data3,
                guid.data4[0],
                guid.data4[1],
                guid.data4[2],
                guid.data4[3],
                guid.data4[4],
                guid.data4[5],
                guid.data4[6],
                guid.data4[7],
            });
        }
    }

    std.debug.print("[DEBUG] Attempting QueryInterface for IResourceManagerFactory (Expected IID: {x:0>8}-...)\n", .{com.IResourceManagerFactory.IID.data1});
    const resource_factory = try activation_factory.queryInterface(com.IResourceManagerFactory);
    defer resource_factory.release();

    const pri_hstring = try winrt.hstringRuntime(alloc, pri_path);
    defer winrt.deleteHString(pri_hstring);

    const resource_manager = try resource_factory.CreateInstance(pri_hstring);
    defer resource_manager.release();
}

fn setupDllPath(alloc: std.mem.Allocator) !void {
    const runtime_dir = try std.fs.cwd().realpathAlloc(alloc, "xaml/prebuilt/runtime/x64");
    defer alloc.free(runtime_dir);
    const runtime_dir_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, runtime_dir);
    defer alloc.free(runtime_dir_w);
    _ = SetDllDirectoryW(runtime_dir_w.ptr);
}

test "prebuilt assets match manifest" {
    try setupDllPath(testing.allocator);
    const alloc = testing.allocator;
    const manifest_json = try std.fs.cwd().readFileAlloc(alloc, "xaml/prebuilt/manifest.json", 1024 * 1024);
    defer alloc.free(manifest_json);

    var parsed = try std.json.parseFromSlice(Manifest, alloc, manifest_json, .{});
    defer parsed.deinit();

    try verifyAsset(alloc, "xaml/prebuilt/ghostty.pri", parsed.value.prebuilt.@"ghostty.pri");
    try verifyAsset(alloc, "xaml/prebuilt/Surface.xbf", parsed.value.prebuilt.@"Surface.xbf");
    try verifyAsset(alloc, "xaml/prebuilt/TabViewRoot.xbf", parsed.value.prebuilt.@"TabViewRoot.xbf");
}

test "ghostty.pri can be opened by ResourceManagerFactory" {
    if (builtin.os.tag != .windows) return;
    try setupDllPath(testing.allocator);

    try winrt.hrCheck(winrt.RoInitialize(winrt.RO_INIT_SINGLETHREADED));
    defer winrt.RoUninitialize();

    const resources_dll_path = try std.fs.cwd().realpathAlloc(testing.allocator, "xaml/prebuilt/runtime/x64/Microsoft.Windows.ApplicationModel.Resources.dll");
    defer testing.allocator.free(resources_dll_path);

    const app_pri_path = try std.fs.cwd().realpathAlloc(testing.allocator, "xaml/prebuilt/ghostty.pri");
    defer testing.allocator.free(app_pri_path);

    try createResourceManagerForPri(testing.allocator, resources_dll_path, app_pri_path);
}
