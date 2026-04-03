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

const HStringDebugName = struct {
    slice: []const u8,
    owned: bool,
};

fn hstringDebugName(class_name: HSTRING) HStringDebugName {
    const utf16 = hstringSliceRaw(@ptrCast(class_name));
    const slice = std.unicode.utf16LeToUtf8Alloc(std.heap.page_allocator, utf16) catch
        return .{ .slice = "<utf16-conversion-failed>", .owned = false };
    return .{ .slice = slice, .owned = true };
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
    const hr = RoGetActivationFactory(class_name, &T.IID, &factory);
    const class_utf8 = hstringDebugName(class_name);
    defer if (class_utf8.owned) std.heap.page_allocator.free(class_utf8.slice);

    log.debug("getActivationFactory class={s} hr=0x{x:0>8} factory=0x{x}", .{
        class_utf8.slice,
        @as(u32, @bitCast(hr)),
        @intFromPtr(factory),
    });

    if (hr >= 0) return @ptrCast(@alignCast(factory orelse return error.WinRTFailed));

    // Fallback for self-contained/unpackaged mode where registration is missing.
    // If RoGetActivationFactory fails with CLASS_NOT_REGISTERED (0x80040154),
    // try to load the implementation DLL directly and call DllGetActivationFactory.
    if (@as(u32, @bitCast(hr)) == 0x80040154) {
        // Map namespaces to implementation DLLs.
        const dll_name: ?[*:0]const u16 = if (std.mem.startsWith(u8, class_utf8.slice, "Microsoft.UI.Xaml"))
            std.unicode.utf8ToUtf16LeStringLiteral("Microsoft.ui.xaml.dll")
        else if (std.mem.startsWith(u8, class_utf8.slice, "Microsoft.UI.Dispatching"))
            std.unicode.utf8ToUtf16LeStringLiteral("Microsoft.WindowsAppRuntime.dll")
        else if (std.mem.startsWith(u8, class_utf8.slice, "Microsoft.Windows.ApplicationModel.Resources"))
            std.unicode.utf8ToUtf16LeStringLiteral("Microsoft.Windows.ApplicationModel.Resources.dll")
        else
            null;

        if (dll_name) |name| {
            const module = std.os.windows.kernel32.GetModuleHandleW(name) orelse
                std.os.windows.kernel32.LoadLibraryW(name);

            if (module) |mod| {
                // DllGetActivationFactory signature: (HSTRING, IActivationFactory**) -> HRESULT
                // Returns a generic IActivationFactory; caller must QI for the specific interface.
                const DllGetActivationFactoryFn = *const fn (HSTRING, *?*anyopaque) callconv(.winapi) HRESULT;
                const get_factory_fn: ?DllGetActivationFactoryFn = @ptrCast(std.os.windows.kernel32.GetProcAddress(mod, "DllGetActivationFactory"));

                if (get_factory_fn) |f| {
                    var activation_factory: ?*anyopaque = null;
                    const mhr = f(class_name, &activation_factory);
                    log.debug("DllGetActivationFactory hr=0x{x:0>8} factory=0x{x}", .{ @as(u32, @bitCast(mhr)), @intFromPtr(activation_factory) });
                    if (mhr >= 0 and activation_factory != null) {
                        // DllGetActivationFactory returns IActivationFactory.
                        // Its vtable starts with IUnknown (QI/AddRef/Release).
                        // Call QueryInterface to get the specific interface T.
                        const VTable = extern struct {
                            QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
                            AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
                            Release: *const fn (*anyopaque) callconv(.winapi) u32,
                        };
                        const obj: *const *const VTable = @ptrCast(@alignCast(activation_factory.?));
                        var specific: ?*anyopaque = null;
                        const qhr = obj.*.QueryInterface(activation_factory.?, &T.IID, &specific);
                        if (qhr >= 0 and specific != null) {
                            log.info("Self-contained activation success for class={s}", .{class_utf8.slice});
                            // Release the activation factory, keep the specific interface
                            _ = obj.*.Release(activation_factory.?);
                            return @ptrCast(@alignCast(specific.?));
                        }
                        _ = obj.*.Release(activation_factory.?);
                    }
                }
            } else {
                log.warn("LoadLibraryW failed for DLL, self-contained fallback unavailable", .{});
            }
        }

        log.err(
            "RoGetActivationFactory failed class={s} hr=0x{x:0>8}",
            .{ class_utf8.slice, @as(u32, @bitCast(hr)) },
        );
    }

    try hrCheck(hr);
    return @ptrCast(@alignCast(factory orelse return error.WinRTFailed));
}

/// Activate a default instance of a WinRT class by name.
pub fn activateInstance(class_name: HSTRING) WinRTError!*IInspectable {
    var instance: ?*IInspectable = null;
    const hr = RoActivateInstance(class_name, &instance);
    if (hr >= 0) return instance orelse error.WinRTFailed;

    // Fallback for self-contained/unpackaged mode.
    if (@as(u32, @bitCast(hr)) == 0x80040154) {
        const class_utf8 = hstringDebugName(class_name);
        defer if (class_utf8.owned) std.heap.page_allocator.free(class_utf8.slice);

        // Map namespaces to implementation DLLs.
        const dll_name: ?[*:0]const u16 = if (std.mem.startsWith(u8, class_utf8.slice, "Microsoft.UI.Xaml"))
            std.unicode.utf8ToUtf16LeStringLiteral("Microsoft.ui.xaml.dll")
        else if (std.mem.startsWith(u8, class_utf8.slice, "Microsoft.UI.Dispatching"))
            std.unicode.utf8ToUtf16LeStringLiteral("Microsoft.WindowsAppRuntime.dll")
        else if (std.mem.startsWith(u8, class_utf8.slice, "Microsoft.Windows.ApplicationModel.Resources"))
            std.unicode.utf8ToUtf16LeStringLiteral("Microsoft.Windows.ApplicationModel.Resources.dll")
        else
            null;

        if (dll_name) |name| {
            const module = std.os.windows.kernel32.GetModuleHandleW(name) orelse
                std.os.windows.kernel32.LoadLibraryW(name);

            if (module) |mod| {
                const DllGetActivationFactoryFn = *const fn (HSTRING, *?*anyopaque) callconv(.winapi) HRESULT;
                const get_factory_fn: ?DllGetActivationFactoryFn = @ptrCast(std.os.windows.kernel32.GetProcAddress(mod, "DllGetActivationFactory"));

                if (get_factory_fn) |f| {
                    var raw_factory: ?*anyopaque = null;
                    if (f(class_name, &raw_factory) >= 0) {
                        if (raw_factory) |fac| {
                            // DllGetActivationFactory returns IActivationFactory
                            const act_factory: *IActivationFactory = @ptrCast(@alignCast(fac));
                            defer act_factory.release();
                            log.info("Self-contained activation success for class={s}", .{class_utf8.slice});
                            return act_factory.activateInstance();
                        }
                    }
                }
            }
        }

        log.err(
            "RoActivateInstance failed class={s} hr=0x{x:0>8}",
            .{ class_utf8.slice, @as(u32, @bitCast(hr)) },
        );
    }

    try hrCheck(hr);
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
