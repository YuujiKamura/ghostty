//! WinRT event handler implementations.
//!
//! WinUI 3 requires Zig to "implement" COM interfaces for event callbacks.
//! WinRT generics (ITypedEventHandler<TSender, TResult>) are type-erased at
//! the ABI level, so all typed event handlers share the same vtable layout:
//!   IUnknown (slots 0-2) + Invoke (slot 3)
//!
//! Design: The COM object is an extern struct containing only lpVtbl (at offset 0,
//! required by COM). Zig-specific fields (ref_count, context, callback) live in
//! a wrapper struct, accessed via @fieldParentPtr from vtable callbacks.

const std = @import("std");
const winrt = @import("winrt.zig");

const HRESULT = winrt.HRESULT;
const GUID = winrt.GUID;

/// COM-visible header. Must be extern struct with lpVtbl at offset 0.
pub const ComHeader = extern struct {
    lpVtbl: *const VTable,

    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        Invoke: *const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.winapi) HRESULT,
    };
};

/// ITypedEventHandler<TSender, TArgs> — generic event handler.
/// At the ABI level, all specializations have the same vtable layout.
/// `Context` is the Zig struct that receives the callback.
pub fn TypedEventHandler(comptime Context: type, comptime CallbackFn: type) type {
    return struct {
        /// The COM header (lpVtbl at offset 0). This field is what WinRT sees.
        com: ComHeader,
        ref_count: std.atomic.Value(u32),
        context: *Context,
        callback: CallbackFn,

        const Self = @This();

        const vtable_instance = ComHeader.VTable{
            .QueryInterface = &queryInterfaceFn,
            .AddRef = &addRefFn,
            .Release = &releaseFn,
            .Invoke = &invokeFn,
        };

        /// Create a new event handler on the heap.
        /// Returns a pointer to the COM header, which can be passed directly to WinRT.
        pub fn create(allocator: std.mem.Allocator, context: *Context, callback: CallbackFn) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .com = .{ .lpVtbl = &vtable_instance },
                .ref_count = std.atomic.Value(u32).init(1),
                .context = context,
                .callback = callback,
            };
            return self;
        }

        /// Get a pointer suitable for passing to WinRT event registration.
        pub fn comPtr(self: *Self) *anyopaque {
            return @ptrCast(&self.com);
        }

        fn fromComPtr(ptr: *anyopaque) *Self {
            const header: *ComHeader = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("com", header);
        }

        fn queryInterfaceFn(this: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(.winapi) HRESULT {
            const IID_IUnknown = GUID{
                .Data1 = 0x00000000,
                .Data2 = 0x0000,
                .Data3 = 0x0000,
                .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
            };
            const IID_IAgileObject = GUID{
                .Data1 = 0x94ea2b94,
                .Data2 = 0xe9cc,
                .Data3 = 0x49e0,
                .Data4 = .{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 },
            };

            if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IAgileObject)) {
                ppv.* = this;
                const self = fromComPtr(this);
                _ = self.ref_count.fetchAdd(1, .monotonic);
                return 0; // S_OK
            }
            ppv.* = null;
            return @bitCast(@as(u32, 0x80004002)); // E_NOINTERFACE
        }

        fn addRefFn(this: *anyopaque) callconv(.winapi) u32 {
            const self = fromComPtr(this);
            return self.ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseFn(this: *anyopaque) callconv(.winapi) u32 {
            const self = fromComPtr(this);
            const prev = self.ref_count.fetchSub(1, .monotonic);
            return prev - 1;
        }

        fn invokeFn(this: *anyopaque, sender: *anyopaque, args: *anyopaque) callconv(.winapi) HRESULT {
            const self = fromComPtr(this);
            self.callback(self.context, sender, args);
            return 0; // S_OK
        }
    };
}

/// Simple event handler with no args distinction (e.g. Window.Closed).
/// Callback signature: fn(*Context, *anyopaque, *anyopaque) void
pub fn SimpleEventHandler(comptime Context: type) type {
    return TypedEventHandler(Context, *const fn (*Context, *anyopaque, *anyopaque) void);
}

fn guidEql(a: *const GUID, b: *const GUID) bool {
    return a.Data1 == b.Data1 and
        a.Data2 == b.Data2 and
        a.Data3 == b.Data3 and
        std.mem.eql(u8, &a.Data4, &b.Data4);
}
