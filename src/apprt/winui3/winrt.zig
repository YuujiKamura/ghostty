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
const log = std.log.scoped(.winui3);

// --- Windows base types ---
pub const BOOL = c_int;
pub const HRESULT = c_long;
pub const UINT = c_uint;
pub const UINT32 = u32;
pub const GUID = std.os.windows.GUID;
pub const HANDLE = std.os.windows.HANDLE;
pub const HWND = std.os.windows.HANDLE;
pub const HMODULE = std.os.windows.HANDLE;

/// Placeholder for vtable slots we don't call.
pub const VtblPlaceholder = *const anyopaque;

// ============================================================================
// HRESULT checking
// ============================================================================

pub const WinRTError = error{WinRTFailed};

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
/// Uses a stack buffer (512 code units) which covers virtually all real titles.
/// The returned HSTRING must be freed with deleteHString.
pub fn hstringRuntime(utf8: []const u8) WinRTError!HSTRING {
    var buf: [512]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&buf, utf8) catch {
        // Truncation or invalid UTF-8 — use what we have.
        var safe_len: usize = buf.len;
        while (safe_len > 0 and buf[safe_len - 1] == 0) safe_len -= 1;
        if (safe_len > 0 and buf[safe_len - 1] >= 0xD800 and buf[safe_len - 1] <= 0xDBFF) {
            safe_len -= 1;
        }
        return createHString(buf[0..safe_len]);
    };
    return createHString(buf[0..len]);
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
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
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
};

// ============================================================================
// IActivationFactory — creates WinRT objects via RoGetActivationFactory
// ============================================================================

pub const IActivationFactory = extern struct {
    pub const IID = GUID{
        .Data1 = 0x00000035,
        .Data2 = 0x0000,
        .Data3 = 0x0000,
        .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
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

var combase_loaded: bool = false;
var fn_RoInitialize: ?RoInitializeFn = null;
var fn_RoUninitialize: ?RoUninitializeFn = null;
var fn_RoActivateInstance: ?RoActivateInstanceFn = null;
var fn_RoGetActivationFactory: ?RoGetActivationFactoryFn = null;
var fn_WindowsCreateString: ?WindowsCreateStringFn = null;
var fn_WindowsDeleteString: ?WindowsDeleteStringFn = null;

fn loadCombase() WinRTError!void {
    if (combase_loaded) return;

    const dll_name = std.unicode.utf8ToUtf16LeStringLiteral("combase.dll");
    const module = std.os.windows.kernel32.LoadLibraryW(dll_name) orelse {
        log.err("Failed to load combase.dll", .{});
        return error.WinRTFailed;
    };

    fn_RoInitialize = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "RoInitialize") orelse {
        log.err("RoInitialize not found in combase.dll", .{});
        return error.WinRTFailed;
    });
    fn_RoUninitialize = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "RoUninitialize") orelse {
        log.err("RoUninitialize not found in combase.dll", .{});
        return error.WinRTFailed;
    });
    fn_RoActivateInstance = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "RoActivateInstance") orelse {
        log.err("RoActivateInstance not found in combase.dll", .{});
        return error.WinRTFailed;
    });
    fn_RoGetActivationFactory = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "RoGetActivationFactory") orelse {
        log.err("RoGetActivationFactory not found in combase.dll", .{});
        return error.WinRTFailed;
    });
    fn_WindowsCreateString = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "WindowsCreateString") orelse {
        log.err("WindowsCreateString not found in combase.dll", .{});
        return error.WinRTFailed;
    });
    fn_WindowsDeleteString = @ptrCast(std.os.windows.kernel32.GetProcAddress(module, "WindowsDeleteString") orelse {
        log.err("WindowsDeleteString not found in combase.dll", .{});
        return error.WinRTFailed;
    });

    combase_loaded = true;
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
