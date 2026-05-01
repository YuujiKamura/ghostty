//! UPSTREAM-SHARED-OK: fork-only file in src/renderer/d3d11/ — D3D11 backend
//! D3D11 GPU buffer wrapper.
//!
//! Provides a Buffer(T) type similar to OpenGL's buffer.zig,
//! wrapping ID3D11Buffer with dynamic mapping support.
//!
//! The Options struct carries device/context references so that
//! init(opts, len) and sync(data) match the GenericRenderer interface.
const std = @import("std");
const com = @import("com.zig");

const log = std.log.scoped(.d3d11);
var trace_bg_loaded: bool = false;
var trace_bg_enabled: bool = false;
var buffer_trace_counter: u64 = 0;

fn traceBgEnabled() bool {
    if (!trace_bg_loaded) {
        trace_bg_loaded = true;
        const value = std.process.getEnvVarOwned(
            std.heap.page_allocator,
            "GHOSTTY_TRACE_BG_CELLS",
        ) catch {
            trace_bg_enabled = false;
            return false;
        };
        defer std.heap.page_allocator.free(value);

        trace_bg_enabled = value.len == 0 or
            (!std.ascii.eqlIgnoreCase(value, "0") and
                !std.ascii.eqlIgnoreCase(value, "false"));
    }
    return trace_bg_enabled;
}

/// Options for initializing a buffer.
pub const Options = struct {
    /// D3D11 device — needed for buffer creation.
    device: ?*com.ID3D11Device = null,
    /// D3D11 device context — needed for Map/Unmap.
    context: ?*com.ID3D11DeviceContext = null,
    /// Buffer bind flags.
    bind_flags: com.UINT = com.D3D11_BIND_VERTEX_BUFFER,
    /// Whether the buffer should be dynamic (CPU-writable).
    dynamic: bool = true,
    /// Whether to create as a structured buffer for SRV access.
    structured: bool = false,
};

/// D3D11 data storage for a certain set of equal types.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: ?*com.ID3D11Buffer = null,
        srv: ?*com.ID3D11ShaderResourceView = null,
        opts: Options,
        len: usize,

        /// Initialize a buffer with the given length pre-allocated.
        /// Matches OpenGL's Buffer.init(opts, len) signature.
        pub fn init(opts: Options, len: usize) !Self {
            if (len == 0) return .{ .buffer = null, .srv = null, .opts = opts, .len = 0 };
            const device = opts.device orelse return error.D3D11Failed;
            return initWithDevice(device, opts, len);
        }

        fn initWithDevice(device: *com.ID3D11Device, opts: Options, len: usize) !Self {
            var byte_width: com.UINT = @intCast(len * @sizeOf(T));
            // D3D11 requires constant buffer ByteWidth to be 16-byte aligned.
            if (opts.bind_flags & com.D3D11_BIND_CONSTANT_BUFFER != 0) {
                byte_width = (byte_width + 15) & ~@as(com.UINT, 15);
            }
            var desc = com.D3D11_BUFFER_DESC{
                .ByteWidth = byte_width,
                .Usage = if (opts.dynamic) .DYNAMIC else .DEFAULT,
                .BindFlags = opts.bind_flags,
                .CPUAccessFlags = if (opts.dynamic) com.D3D11_CPU_ACCESS_WRITE else 0,
            };
            if (opts.structured) {
                desc.MiscFlags = 0x40; // D3D11_RESOURCE_MISC_BUFFER_STRUCTURED
                desc.StructureByteStride = @sizeOf(T);
            }

            if (traceBgEnabled()) {
                buffer_trace_counter += 1;
                const sample = buffer_trace_counter <= 64 or (buffer_trace_counter % 64) == 0;
                if (sample) {
                    log.info(
                        "buffer.init type_size={} len={} byte_width={} bind=0x{x} dynamic={} structured={} stride={}",
                        .{
                            @sizeOf(T),
                            len,
                            desc.ByteWidth,
                            desc.BindFlags,
                            opts.dynamic,
                            opts.structured,
                            desc.StructureByteStride,
                        },
                    );
                }
            }

            const buf = device.createBuffer(&desc, null) catch return error.D3D11Failed;
            errdefer buf.release();
            const srv = try createStructuredSrvIfNeeded(device, opts, buf, len);
            return .{ .buffer = buf, .srv = srv, .opts = opts, .len = len };
        }

        /// Init the buffer filled with the given data.
        /// Matches OpenGL's Buffer.initFill(opts, data) signature.
        pub fn initFill(opts: Options, data: []const T) !Self {
            if (data.len == 0) return .{ .buffer = null, .srv = null, .opts = opts, .len = 0 };
            const device = opts.device orelse return error.D3D11Failed;

            var byte_width: com.UINT = @intCast(data.len * @sizeOf(T));
            // D3D11 requires constant buffer ByteWidth to be 16-byte aligned.
            if (opts.bind_flags & com.D3D11_BIND_CONSTANT_BUFFER != 0) {
                byte_width = (byte_width + 15) & ~@as(com.UINT, 15);
            }
            var desc = com.D3D11_BUFFER_DESC{
                .ByteWidth = byte_width,
                .Usage = if (opts.dynamic) .DYNAMIC else .DEFAULT,
                .BindFlags = opts.bind_flags,
                .CPUAccessFlags = if (opts.dynamic) com.D3D11_CPU_ACCESS_WRITE else 0,
            };
            if (opts.structured) {
                desc.MiscFlags = 0x40;
                desc.StructureByteStride = @sizeOf(T);
            }

            if (traceBgEnabled()) {
                buffer_trace_counter += 1;
                const sample = buffer_trace_counter <= 64 or (buffer_trace_counter % 64) == 0;
                if (sample) {
                    log.info(
                        "buffer.initFill type_size={} len={} byte_width={} bind=0x{x} dynamic={} structured={} stride={}",
                        .{
                            @sizeOf(T),
                            data.len,
                            desc.ByteWidth,
                            desc.BindFlags,
                            opts.dynamic,
                            opts.structured,
                            desc.StructureByteStride,
                        },
                    );
                }
            }

            const init_data = com.D3D11_SUBRESOURCE_DATA{
                .pSysMem = @ptrCast(data.ptr),
                .SysMemPitch = byte_width,
            };

            const buf = device.createBuffer(&desc, &init_data) catch return error.D3D11Failed;
            errdefer buf.release();
            const srv = try createStructuredSrvIfNeeded(device, opts, buf, data.len);
            return .{ .buffer = buf, .srv = srv, .opts = opts, .len = data.len };
        }

        pub fn deinit(self: Self) void {
            if (self.srv) |srv| srv.release();
            if (self.buffer) |buf| buf.release();
        }

        /// Sync new contents to the buffer via Map/Unmap.
        /// If data is larger than current buffer, recreates it.
        /// Matches OpenGL's Buffer.sync(data) signature.
        pub fn sync(self: *Self, data: []const T) !void {
            if (data.len == 0) return;

            const device = self.opts.device orelse return;
            const context = self.opts.context orelse return;

            // If we need more space, recreate.
            if (data.len > self.len) {
                if (traceBgEnabled()) {
                    log.info(
                        "buffer.sync grow type_size={} old_len={} requested_len={}",
                        .{ @sizeOf(T), self.len, data.len },
                    );
                }
                if (self.srv) |srv| srv.release();
                if (self.buffer) |buf| buf.release();
                self.* = try initWithDevice(device, self.opts, data.len * 2);
            }

            const buf = self.buffer orelse return;

            if (self.opts.dynamic) {
                const mapped = context.map(@ptrCast(buf), 0, .WRITE_DISCARD, 0) catch return error.D3D11Failed;
                const dest: [*]T = @ptrCast(@alignCast(mapped.pData orelse return error.D3D11Failed));
                @memcpy(dest[0..data.len], data);
                context.unmap(@ptrCast(buf), 0);
            } else {
                context.updateSubresource(@ptrCast(buf), 0, null, @ptrCast(data.ptr), @intCast(data.len * @sizeOf(T)), 0);
            }
        }

        /// Like Buffer.sync but takes data from an array of ArrayLists.
        /// Returns the number of items synced.
        pub fn syncFromArrayLists(self: *Self, lists: []const std.ArrayListUnmanaged(T)) !usize {
            const device = self.opts.device orelse return 0;
            const context = self.opts.context orelse return 0;

            var total_len: usize = 0;
            for (lists) |list| {
                total_len += list.items.len;
            }
            if (total_len == 0) return 0;

            // If we need more space, recreate with double capacity.
            if (total_len > self.len) {
                if (self.srv) |srv| srv.release();
                if (self.buffer) |buf| buf.release();
                self.* = try initWithDevice(device, self.opts, total_len * 2);
            }

            const buf = self.buffer orelse return 0;

            if (self.opts.dynamic) {
                const mapped = context.map(@ptrCast(buf), 0, .WRITE_DISCARD, 0) catch return error.D3D11Failed;
                const dest: [*]T = @ptrCast(@alignCast(mapped.pData orelse return error.D3D11Failed));
                var offset: usize = 0;
                for (lists) |list| {
                    @memcpy(dest[offset..][0..list.items.len], list.items);
                    offset += list.items.len;
                }
                context.unmap(@ptrCast(buf), 0);
            } else {
                // For non-dynamic buffers, copy lists sequentially.
                var offset: usize = 0;
                for (lists) |list| {
                    if (list.items.len > 0) {
                        const box = com.D3D11_BOX{
                            .left = @intCast(offset * @sizeOf(T)),
                            .top = 0,
                            .front = 0,
                            .right = @intCast((offset + list.items.len) * @sizeOf(T)),
                            .bottom = 1,
                            .back = 1,
                        };
                        context.updateSubresource(@ptrCast(buf), 0, &box, @ptrCast(list.items.ptr), @intCast(list.items.len * @sizeOf(T)), 0);
                    }
                    offset += list.items.len;
                }
            }

            return total_len;
        }

        fn createStructuredSrvIfNeeded(
            device: *com.ID3D11Device,
            opts: Options,
            buf: *com.ID3D11Buffer,
            len: usize,
        ) !?*com.ID3D11ShaderResourceView {
            if (!opts.structured) return null;
            if ((opts.bind_flags & com.D3D11_BIND_SHADER_RESOURCE) == 0) return null;

            var desc = com.D3D11_SHADER_RESOURCE_VIEW_DESC{
                .Format = .UNKNOWN,
                .ViewDimension = com.D3D11_SRV_DIMENSION_BUFFER,
                .u = .{
                    .Buffer = .{
                        .FirstElement = 0,
                        .NumElements = @intCast(len),
                    },
                },
            };

            return device.createShaderResourceView(@ptrCast(buf), &desc) catch {
                log.err(
                    "buffer: createShaderResourceView failed structured={} bind=0x{x} len={} elem_size={}",
                    .{ opts.structured, opts.bind_flags, len, @sizeOf(T) },
                );
                return error.D3D11Failed;
            };
        }
    };
}

// -----------------------------------------------------------------------------
// Tests — device-free fast paths only. Anything that touches an ID3D11Device
// or context belongs in an integration suite; see .dispatch/team-B-report.md
// (Tier 3) for the list that requires a live device.

test "Buffer.init: len=0 returns device-free zero buffer with options forwarded" {
    const T = extern struct { x: u32 };
    const opts: Options = .{
        .device = null,
        .context = null,
        .bind_flags = com.D3D11_BIND_VERTEX_BUFFER,
        .dynamic = true,
        .structured = false,
    };

    const buf = try Buffer(T).init(opts, 0);

    try std.testing.expect(buf.buffer == null);
    try std.testing.expect(buf.srv == null);
    try std.testing.expectEqual(@as(usize, 0), buf.len);
    try std.testing.expectEqual(opts.bind_flags, buf.opts.bind_flags);
    try std.testing.expectEqual(opts.dynamic, buf.opts.dynamic);
    try std.testing.expectEqual(opts.structured, buf.opts.structured);
    try std.testing.expect(buf.opts.device == null);
    try std.testing.expect(buf.opts.context == null);
}

test "Buffer.init: len>0 with null device returns error.D3D11Failed" {
    const T = extern struct { x: u32 };
    const opts: Options = .{ .device = null };
    try std.testing.expectError(error.D3D11Failed, Buffer(T).init(opts, 4));
}

test "Buffer.initFill: empty data returns device-free zero buffer with options forwarded" {
    const T = extern struct { x: u32 };
    const opts: Options = .{
        .device = null,
        .bind_flags = com.D3D11_BIND_CONSTANT_BUFFER,
        .dynamic = false,
        .structured = false,
    };
    const empty: []const T = &.{};

    const buf = try Buffer(T).initFill(opts, empty);

    try std.testing.expect(buf.buffer == null);
    try std.testing.expect(buf.srv == null);
    try std.testing.expectEqual(@as(usize, 0), buf.len);
    try std.testing.expectEqual(opts.bind_flags, buf.opts.bind_flags);
    try std.testing.expectEqual(opts.dynamic, buf.opts.dynamic);
}

test "Buffer.initFill: non-empty data with null device returns error.D3D11Failed" {
    const T = extern struct { x: u32 };
    const opts: Options = .{ .device = null };
    const data = [_]T{.{ .x = 1 }, .{ .x = 2 }};
    try std.testing.expectError(error.D3D11Failed, Buffer(T).initFill(opts, &data));
}

test "Buffer.deinit: null-safe on default-constructed Buffer and idempotent" {
    const T = extern struct { x: u32 };
    // A default-constructed Buffer (e.g. via @"struct"(.{})) has buffer=null,
    // srv=null. deinit() must tolerate this and stay idempotent so that
    // double-deinit during error unwinding does not crash.
    var buf: Buffer(T) = .{ .opts = .{}, .len = 0 };
    buf.deinit();
    buf.deinit(); // call twice — must not double-release.
    try std.testing.expect(buf.buffer == null);
    try std.testing.expect(buf.srv == null);
}
