//! WinRT foundation types and functions.
//!
//! Provides HSTRING management, IInspectable base interface, RoActivateInstance,
//! RoGetActivationFactory, and HRESULT checking for WinRT/WinUI 3 interop.
//!
//! All WinRT objects inherit from IInspectable (6 base vtable slots):
//!   IUnknown (0-2): QueryInterface, AddRef, Release
//!   IInspectable (3-5): GetIids, GetRuntimeClassName, GetTrustLevel
//!
//! Pattern follows src/renderer/d3d11/com.zig.

const std = @import("std");
const Allocator = std.mem.Allocator;
const os = @import("os.zig");
const log = std.log.scoped(.winui3);

// --- Windows base types ---
pub const BOOL = c_int;
pub const HRESULT = c_long;
pub const UINT = c_uint;
pub const UINT32 = u32;
pub const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,

    pub fn equals(self: GUID, other: GUID) bool {
        return self.data1 == other.data1 and self.data2 == other.data2 and self.data3 == other.data3 and std.mem.eql(u8, &self.data4, &other.data4);
    }
};
pub const HANDLE = std.os.windows.HANDLE;
pub const HWND = std.os.windows.HANDLE;
pub const HMODULE = std.os.windows.HANDLE;

/// Placeholder for vtable slots we don't call.
pub const VtblPlaceholder = *const anyopaque;
pub const IID_IUnknown = GUID{
    .data1 = 0x00000000,
    .data2 = 0x0000,
    .data3 = 0x0000,
    .data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};
pub const IID_IAgileObject = GUID{
    .data1 = 0x94ea2b94,
    .data2 = 0xe9cc,
    .data3 = 0x49e0,
    .data4 = .{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 },
};

// ============================================================================
// HRESULT checking
// ============================================================================

pub const WinRTError = error{WinRTFailed};
pub const S_OK: HRESULT = 0;
pub const E_FAIL: HRESULT = @bitCast(@as(u32, 0x80004005));
pub const E_NOINTERFACE: HRESULT = @bitCast(@as(u32, 0x80004002));

/// Scoped COM pointer guard. Call `init(ptr)` and `defer guard.deinit()`
/// to ensure `Release()` is called on scope exit.
pub fn ComRef(comptime T: type) type {
    return struct {
        ptr: *T,

        const Self = @This();

        pub fn init(ptr: *T) Self {
            return .{ .ptr = ptr };
        }

        pub fn deinit(self: *Self) void {
            _ = self.ptr.release();
        }

        pub fn get(self: *const Self) *T {
            return self.ptr;
        }
    };
}

pub inline fn hrCheck(hr: HRESULT) WinRTError!void {
    if (hr >= 0) return;
    log.err("WinRT HRESULT failed: 0x{x:0>8}", .{@as(u32, @bitCast(hr))});
    return error.WinRTFailed;
}

// ============================================================================
// HSTRING — WinRT immutable string handle
// ============================================================================

pub const HSTRING = *opaque {};

pub fn createHString(str: []const u16) WinRTError!HSTRING {
    var result: ?HSTRING = null;
    try hrCheck(WindowsCreateString(str.ptr, @intCast(str.len), &result));
    return result orelse error.WinRTFailed;
}

pub fn deleteHString(str: HSTRING) void {
    _ = WindowsDeleteString(str);
}

pub fn hstringSliceRaw(str: ?*anyopaque) []const u16 {
    var len: u32 = 0;
    const ptr = WindowsGetStringRawBuffer(str, &len);
    return ptr[0..len];
}

/// Helper: create HSTRING from comptime UTF-8 literal.
/// The returned HSTRING must be freed with deleteHString.
pub fn hstring(comptime utf8: []const u8) WinRTError!HSTRING {
    const utf16 = comptime blk: {
        var buf: [utf8.len * 2]u16 = undefined;
        const len = std.unicode.utf8ToUtf16Le(&buf, utf8) catch @compileError("invalid UTF-8");
        break :blk buf[0..len].*;
    };
    return createHString(&utf16);
}

/// Create HSTRING from a runtime UTF-8 string.
/// Uses a stack buffer (512 code units) for short strings; heap-allocates for longer ones.
/// The returned HSTRING must be freed with deleteHString.
pub fn hstringRuntime(alloc: Allocator, utf8: []const u8) WinRTError!HSTRING {
    var stack_buf: [512]u16 = undefined;
    if (utf8.len <= stack_buf.len) {
        const len = std.unicode.utf8ToUtf16Le(&stack_buf, utf8) catch return error.WinRTFailed;
        return createHString(stack_buf[0..len]);
    }
    // Heap allocate for long strings (utf8.len >= UTF-16 code unit count)
    const heap_buf = alloc.alloc(u16, utf8.len) catch return error.WinRTFailed;
    defer alloc.free(heap_buf);
    const len = std.unicode.utf8ToUtf16Le(heap_buf, utf8) catch return error.WinRTFailed;
    return createHString(heap_buf[0..len]);
}

// ============================================================================
// IInspectable — base interface for all WinRT objects
// ============================================================================

pub const IInspectable = extern struct {
    lpVtbl: *const VTable,

    pub const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: *const fn (*anyopaque, *u32, *?*GUID) callconv(.winapi) HRESULT,
        GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.winapi) HRESULT,
        GetTrustLevel: *const fn (*anyopaque, *anyopaque) callconv(.winapi) HRESULT,
    };

    pub fn queryInterface(self: *IInspectable, comptime T: type) WinRTError!*T {
        var result: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.QueryInterface(@ptrCast(self), &T.IID, &result));
        return @ptrCast(@alignCast(result orelse return error.WinRTFailed));
    }

    pub fn addRef(self: *IInspectable) u32 {
        return self.lpVtbl.AddRef(@ptrCast(self));
    }

    pub fn release(self: *IInspectable) u32 {
        return self.lpVtbl.Release(@ptrCast(self));
    }

    pub fn getRuntimeClassName(self: *IInspectable) WinRTError!HSTRING {
        var result: ?HSTRING = null;
        try hrCheck(self.lpVtbl.GetRuntimeClassName(@ptrCast(self), &result));
        return result orelse error.WinRTFailed;
    }
};

// ============================================================================
// IActivationFactory — creates WinRT objects via RoGetActivationFactory
// ============================================================================

pub const IActivationFactory = extern struct {
    pub const IID = GUID{
        .data1 = 0x00000035,
        .data2 = 0x0000,
        .data3 = 0x0000,
        .data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IActivationFactory (slot 6)
        ActivateInstance: *const fn (*anyopaque, *?*IInspectable) callconv(.winapi) HRESULT,
    };

    pub fn activateInstance(self: *IActivationFactory) WinRTError!*IInspectable {
        var instance: ?*IInspectable = null;
        try hrCheck(self.lpVtbl.ActivateInstance(@ptrCast(self), &instance));
        return instance orelse error.WinRTFailed;
    }

    pub fn queryInterface(self: *IActivationFactory, comptime T: type) WinRTError!*T {
        var result: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.QueryInterface(@ptrCast(self), &T.IID, &result));
        return @ptrCast(@alignCast(result orelse return error.WinRTFailed));
    }

    pub fn release(self: *IActivationFactory) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// ============================================================================
// Activation helpers
// ============================================================================

/// Get an activation factory for a WinRT class.
pub fn getActivationFactory(comptime T: type, class_name: HSTRING) WinRTError!*T {
    var factory: ?*anyopaque = null;
    try hrCheck(RoGetActivationFactory(class_name, &T.IID, &factory));
    return @ptrCast(@alignCast(factory orelse return error.WinRTFailed));
}

/// Activate a default instance of a WinRT class by name.
pub fn activateInstance(class_name: HSTRING) WinRTError!*IInspectable {
    var instance: ?*IInspectable = null;
    try hrCheck(RoActivateInstance(class_name, &instance));
    return instance orelse error.WinRTFailed;
}

// ============================================================================
// WinRT functions — dynamically loaded from combase.dll
// (MinGW/Zig doesn't ship combase.lib for x86_64)
// ============================================================================

/// RO_INIT_SINGLETHREADED = 0, RO_INIT_MULTITHREADED = 1
pub const RO_INIT_SINGLETHREADED: u32 = 0;

const RoInitializeFn = *const fn (u32) callconv(.winapi) HRESULT;
const RoUninitializeFn = *const fn () callconv(.winapi) void;
const RoActivateInstanceFn = *const fn (HSTRING, *?*IInspectable) callconv(.winapi) HRESULT;
const RoGetActivationFactoryFn = *const fn (HSTRING, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT;
const WindowsCreateStringFn = *const fn ([*]const u16, UINT32, *?HSTRING) callconv(.winapi) HRESULT;
const WindowsDeleteStringFn = *const fn (?HSTRING) callconv(.winapi) HRESULT;
const WindowsGetStringRawBufferFn = *const fn (?*anyopaque, ?*u32) callconv(.winapi) [*]const u16;

var combase_loaded = std.atomic.Value(bool).init(false);
var fn_RoInitialize: ?RoInitializeFn = null;
var fn_RoUninitialize: ?RoUninitializeFn = null;
var fn_RoActivateInstance: ?RoActivateInstanceFn = null;
var fn_RoGetActivationFactory: ?RoGetActivationFactoryFn = null;
var fn_WindowsCreateString: ?WindowsCreateStringFn = null;
var fn_WindowsDeleteString: ?WindowsDeleteStringFn = null;
var fn_WindowsGetStringRawBuffer: ?WindowsGetStringRawBufferFn = null;

var combase_module: ?HANDLE = null;

fn loadCombase() WinRTError!void {
    if (combase_loaded.load(.acquire)) return;

    // Use a simple spinlock or atomic check to ensure only one thread loads.
    // In a GUI app, this is usually called once during startup on the main thread anyway.
    const dll_name = std.unicode.utf8ToUtf16LeStringLiteral("combase.dll");
    const module = std.os.windows.kernel32.LoadLibraryW(dll_name) orelse {
        log.err("Failed to load combase.dll", .{});
        return error.WinRTFailed;
    };
    combase_module = module;

    fn_RoInitialize = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "RoInitialize") orelse return error.WinRTFailed);
    fn_RoUninitialize = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "RoUninitialize") orelse return error.WinRTFailed);
    fn_RoActivateInstance = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "RoActivateInstance") orelse return error.WinRTFailed);
    fn_RoGetActivationFactory = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "RoGetActivationFactory") orelse return error.WinRTFailed);
    fn_WindowsCreateString = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "WindowsCreateString") orelse return error.WinRTFailed);
    fn_WindowsDeleteString = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "WindowsDeleteString") orelse return error.WinRTFailed);
    fn_WindowsGetStringRawBuffer = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "WindowsGetStringRawBuffer") orelse return error.WinRTFailed);

    combase_loaded.store(true, .release);
}

pub fn RoInitialize(initType: u32) HRESULT {
    loadCombase() catch return @bitCast(@as(u32, 0x80004005)); // E_FAIL
    return fn_RoInitialize.?(initType);
}

pub fn RoUninitialize() void {
    if (fn_RoUninitialize) |f| f();
}

pub fn RoActivateInstance(classId: HSTRING, instance: *?*IInspectable) HRESULT {
    loadCombase() catch return @bitCast(@as(u32, 0x80004005));
    return fn_RoActivateInstance.?(classId, instance);
}

pub fn RoGetActivationFactory(classId: HSTRING, iid: *const GUID, factory: *?*anyopaque) HRESULT {
    loadCombase() catch return @bitCast(@as(u32, 0x80004005));
    return fn_RoGetActivationFactory.?(classId, iid, factory);
}

pub fn WindowsCreateString(src: [*]const u16, len: UINT32, out: *?HSTRING) HRESULT {
    loadCombase() catch return @bitCast(@as(u32, 0x80004005));
    return fn_WindowsCreateString.?(src, len, out);
}

pub fn WindowsDeleteString(str: ?HSTRING) HRESULT {
    loadCombase() catch return @bitCast(@as(u32, 0x80004005));
    return fn_WindowsDeleteString.?(str);
}

pub fn WindowsGetStringRawBuffer(str: ?*anyopaque, len: ?*u32) [*]const u16 {
    loadCombase() catch return &.{0};
    return fn_WindowsGetStringRawBuffer.?(str, len);
}

// ============================================================================
// DispatcherQueue creation (CoreMessaging.dll)
// ============================================================================

pub const DispatcherQueueOptions = extern struct {
    dwSize: u32 = @sizeOf(DispatcherQueueOptions),
    threadType: u32 = 2, // DQTAT_COM_STA
    apartmentType: u32 = 2, // DQTYPE_THREAD_CURRENT
};

/// Dynamically loaded from CoreMessaging.dll since it may not be available on all systems.
pub fn createDispatcherQueueController(options: *const DispatcherQueueOptions) WinRTError!*IInspectable {
    const module = std.os.windows.kernel32.LoadLibraryW(&[_:0]u16{ 'C', 'o', 'r', 'e', 'M', 'e', 's', 's', 'a', 'g', 'i', 'n', 'g', '.', 'd', 'l', 'l' }) orelse {
        log.err("Failed to load CoreMessaging.dll", .{});
        return error.WinRTFailed;
    };
    const CreateFn = *const fn (*const DispatcherQueueOptions, *?*IInspectable) callconv(.winapi) HRESULT;
    const create_fn: CreateFn = @ptrCast(std.os.windows.kernel32.GetProcAddress(
        module,
        "CreateDispatcherQueueController",
    ) orelse {
        log.err("Failed to find CreateDispatcherQueueController", .{});
        return error.WinRTFailed;
    });
    var controller: ?*IInspectable = null;
    try hrCheck(create_fn(options, &controller));
    return controller orelse error.WinRTFailed;
}

extern "ole32" fn CoTaskMemFree(pv: ?*anyopaque) callconv(.winapi) void;

pub inline fn coTaskMemFree(pv: ?*anyopaque) void {
    CoTaskMemFree(pv);
}
