//! UPSTREAM-SHARED-OK: fork-only file in src/renderer/d3d11/ — D3D11 backend
//! D3D11-specific shader constant definitions.
//!
//! This file defines the layout of dynamic data passed to shaders that
//! changes frequently (per-frame), such as time, FPS, or animation state.
//! Separating these from the static terminal uniforms allows for a cleaner
//! data flow between the UI layer and the rendering layer.

const std = @import("std");

/// Dynamic constants passed to terminal shaders.
/// This matches the layout of the constant buffer at slot 1 in HLSL.
pub const TerminalShaderConstants = extern struct {
    /// Time in seconds since the application started.
    time: f32,

    /// Current average frames per second.
    fps: f32,

    /// Pad to 16-byte alignment as required by D3D11 constant buffers.
    _padding: [2]f32 = .{ 0, 0 },
};

test "TerminalShaderConstants: extern struct layout pin (size=16, align=4, offsets)" {
    // The D3D11 constant buffer at slot 1 expects exactly 16 bytes of dynamic
    // per-frame data. If any field is added/reordered/resized, the HLSL side
    // must be updated in lockstep — pin the layout here so drift fails at test.
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(TerminalShaderConstants));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(TerminalShaderConstants));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(TerminalShaderConstants, "time"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(TerminalShaderConstants, "fps"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(TerminalShaderConstants, "_padding"));
}

test "TerminalShaderConstants: round-trip through bytes preserves field values" {
    const original: TerminalShaderConstants = .{
        .time = 1.5,
        .fps = 60.0,
        ._padding = .{ 0.25, -0.5 },
    };
    const bytes = std.mem.asBytes(&original);
    try std.testing.expectEqual(@as(usize, 16), bytes.len);
    const restored: *const TerminalShaderConstants =
        std.mem.bytesAsValue(TerminalShaderConstants, bytes);
    try std.testing.expectEqual(original.time, restored.time);
    try std.testing.expectEqual(original.fps, restored.fps);
    try std.testing.expectEqual(original._padding, restored._padding);
}

test "TerminalShaderConstants: padding default initializes to zeroes" {
    const c: TerminalShaderConstants = .{ .time = 0, .fps = 0 };
    try std.testing.expectEqual(@as(f32, 0), c._padding[0]);
    try std.testing.expectEqual(@as(f32, 0), c._padding[1]);
}

test "TerminalShaderConstants: byte-for-byte equality after @ptrCast write/read" {
    var buf: [16]u8 align(@alignOf(TerminalShaderConstants)) = undefined;
    const ptr: *TerminalShaderConstants = @ptrCast(&buf);
    ptr.* = .{ .time = 3.14, .fps = 144.0, ._padding = .{ 7.0, 8.0 } };
    const reread: *const TerminalShaderConstants = @ptrCast(&buf);
    try std.testing.expectEqual(@as(f32, 3.14), reread.time);
    try std.testing.expectEqual(@as(f32, 144.0), reread.fps);
    try std.testing.expectEqual(@as(f32, 7.0), reread._padding[0]);
    try std.testing.expectEqual(@as(f32, 8.0), reread._padding[1]);
    // And bytes are stable through asBytes.
    const back = std.mem.asBytes(reread);
    try std.testing.expectEqualSlices(u8, &buf, back);
}
