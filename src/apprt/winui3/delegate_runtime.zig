const std = @import("std");
const rt = @import("com_runtime.zig");
const marshaler = @import("marshaler_runtime.zig");

const log = std.log.scoped(.winui3);

fn shouldLogUnknownIid(riid: *const rt.GUID) bool {
    // Frequently probed by WinUI/COM runtime; returning E_NOINTERFACE is expected.
    const ignored = [_]rt.GUID{
        // INoMarshal
        .{ .Data1 = 0xecc8691b, .Data2 = 0xc1db, .Data3 = 0x4dc0, .Data4 = .{ 0x85, 0x5e, 0x65, 0xf6, 0xc5, 0x51, 0xaf, 0x49 } },
        // IGlobalInterfaceTable
        .{ .Data1 = 0x00000039, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } },
        // IStdMarshalInfo
        .{ .Data1 = 0x0000001b, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } },
        // Runtime probes observed on TabView event handlers; not delegate IIDs.
        .{ .Data1 = 0xe7beaee7, .Data2 = 0x160e, .Data3 = 0x50f7, .Data4 = .{ 0x87, 0x89, 0xd6, 0x34, 0x63, 0xf9, 0x79, 0xfa } },
        .{ .Data1 = 0x02dd3ad0, .Data2 = 0xb9de, .Data3 = 0x4b55, .Data4 = .{ 0xa0, 0xc3, 0x50, 0x72, 0x35, 0xea, 0xe8, 0xea } },
        .{ .Data1 = 0x64bd43f8, .Data2 = 0xbfee, .Data3 = 0x4ec4, .Data4 = .{ 0xb7, 0xeb, 0x29, 0x35, 0x15, 0x8d, 0xae, 0x21 } },
    };
    for (ignored) |iid| {
        if (rt.guidEql(riid, &iid)) return false;
    }
    return true;
}

pub fn TypedDelegate(comptime Context: type, comptime CallbackFn: type) type {
    return struct {
        const Self = @This();

        pub const ComHeader = extern struct {
            lpVtbl: *const VTable,
        };

        pub const VTable = extern struct {
            QueryInterface: *const fn (*anyopaque, *const rt.GUID, *?*anyopaque) callconv(.winapi) rt.HRESULT,
            AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
            Release: *const fn (*anyopaque) callconv(.winapi) u32,
            Invoke: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) rt.HRESULT,
        };

        com: ComHeader,
        allocator: std.mem.Allocator,
        ref_count: std.atomic.Value(u32),
        context: *Context,
        callback: CallbackFn,
        delegate_iid: ?*const rt.GUID = null,

        const vtable_instance = VTable{
            .QueryInterface = &queryInterfaceFn,
            .AddRef = &addRefFn,
            .Release = &releaseFn,
            .Invoke = &invokeFn,
        };

        pub fn create(
            allocator: std.mem.Allocator,
            context: *Context,
            callback: CallbackFn,
        ) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .com = .{ .lpVtbl = &vtable_instance },
                .allocator = allocator,
                .ref_count = std.atomic.Value(u32).init(1),
                .context = context,
                .callback = callback,
            };
            return self;
        }

        pub fn createWithIid(
            allocator: std.mem.Allocator,
            context: *Context,
            callback: CallbackFn,
            iid: *const rt.GUID,
        ) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .com = .{ .lpVtbl = &vtable_instance },
                .allocator = allocator,
                .ref_count = std.atomic.Value(u32).init(1),
                .context = context,
                .callback = callback,
                .delegate_iid = iid,
            };
            return self;
        }

        pub fn comPtr(self: *Self) *anyopaque {
            return @ptrCast(&self.com);
        }

        pub fn release(self: *Self) void {
            _ = self.com.lpVtbl.Release(self.comPtr());
        }

        fn fromComPtr(ptr: *anyopaque) *Self {
            const header: *ComHeader = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("com", header);
        }

        fn queryInterfaceFn(
            this: *anyopaque,
            riid: *const rt.GUID,
            ppv: *?*anyopaque,
        ) callconv(.winapi) rt.HRESULT {
            const self = fromComPtr(this);
            if (rt.guidEql(riid, &rt.IID_IUnknown) or rt.guidEql(riid, &rt.IID_IAgileObject)) {
                ppv.* = this;
                _ = self.ref_count.fetchAdd(1, .monotonic);
                return rt.S_OK;
            }
            if (self.delegate_iid) |iid| {
                if (rt.guidEql(riid, iid)) {
                    ppv.* = this;
                    _ = self.ref_count.fetchAdd(1, .monotonic);
                    return rt.S_OK;
                }
            }
            if (rt.guidEql(riid, &rt.IID_IMarshal)) {
                return marshaler.queryInterfaceAsMarshaler(self.allocator, this, ppv);
            }

            if (shouldLogUnknownIid(riid)) {
                log.warn("delegate QI unknown iid={{{x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}}}", .{
                    riid.Data1,
                    riid.Data2,
                    riid.Data3,
                    riid.Data4[0],
                    riid.Data4[1],
                    riid.Data4[2],
                    riid.Data4[3],
                    riid.Data4[4],
                    riid.Data4[5],
                    riid.Data4[6],
                    riid.Data4[7],
                });
            }
            ppv.* = null;
            return rt.E_NOINTERFACE;
        }

        fn addRefFn(this: *anyopaque) callconv(.winapi) u32 {
            const self = fromComPtr(this);
            return self.ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseFn(this: *anyopaque) callconv(.winapi) u32 {
            const self = fromComPtr(this);
            const prev = self.ref_count.fetchSub(1, .monotonic);
            const next = prev - 1;
            if (next == 0) self.allocator.destroy(self);
            return next;
        }

        fn invokeFn(this: *anyopaque, sender: ?*anyopaque, args: ?*anyopaque) callconv(.winapi) rt.HRESULT {
            const self = fromComPtr(this);
            const iid_d1: u32 = if (self.delegate_iid) |iid| iid.Data1 else 0;
            const sender_ptr = if (sender) |p| @intFromPtr(p) else @as(usize, 0);
            const args_ptr = if (args) |p| @intFromPtr(p) else @as(usize, 0);
            log.info("delegate invoke enter iid_d1=0x{x} sender=0x{x} args=0x{x}", .{ iid_d1, sender_ptr, args_ptr });
            const cb_ptr_info = @typeInfo(CallbackFn).pointer;
            const fn_info = @typeInfo(cb_ptr_info.child).@"fn";
            const sender_t = fn_info.params[1].type.?;
            const args_t = fn_info.params[2].type.?;

            if (sender_t == ?*anyopaque and args_t == ?*anyopaque) {
                self.callback(self.context, sender, args);
            } else if (sender_t == ?*anyopaque and args_t == *anyopaque) {
                const a = args orelse return rt.S_OK;
                self.callback(self.context, sender, a);
            } else if (sender_t == *anyopaque and args_t == ?*anyopaque) {
                const s = sender orelse return rt.S_OK;
                self.callback(self.context, s, args);
            } else {
                const s = sender orelse return rt.S_OK;
                const a = args orelse return rt.S_OK;
                self.callback(self.context, s, a);
            }
            log.info("delegate invoke exit iid_d1=0x{x}", .{iid_d1});
            return rt.S_OK;
        }
    };
}
