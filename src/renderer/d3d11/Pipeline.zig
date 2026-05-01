//! D3D11 render pipeline state (VS + PS + InputLayout + BlendState + RasterizerState).
const Self = @This();

const std = @import("std");
const com = @import("com.zig");

const log = std.log.scoped(.d3d11);

/// Options for initializing a render pipeline.
pub const Options = struct {
    /// HLSL source for the vertex shader.
    vertex_fn: [:0]const u8,
    /// HLSL source for the pixel (fragment) shader.
    fragment_fn: [:0]const u8,
    /// Vertex step function.
    step_fn: StepFunction = .per_vertex,
    /// Whether to enable alpha blending.
    blending_enabled: bool = true,

    pub const StepFunction = enum {
        constant,
        per_vertex,
        per_instance,
    };
};

vertex_shader: ?*com.ID3D11VertexShader = null,
pixel_shader: ?*com.ID3D11PixelShader = null,
input_layout: ?*com.ID3D11InputLayout = null,
blend_state: ?*com.ID3D11BlendState = null,
rasterizer_state: ?*com.ID3D11RasterizerState = null,
stride: usize = 0,
blending_enabled: bool = true,
vs_bytecode: ?[]const u8 = null,
vs_bytecode_alloc: ?std.mem.Allocator = null,

pub fn init(
    device: *com.ID3D11Device,
    alloc: std.mem.Allocator,
    comptime VertexAttributes: ?type,
    opts: Options,
) !Self {
    // Compile vertex shader
    var vs_blob: ?*com.ID3DBlob = null;
    var vs_errors: ?*com.ID3DBlob = null;
    const vs_hr = com.D3DCompile(
        opts.vertex_fn.ptr,
        opts.vertex_fn.len,
        null,
        null,
        null,
        "vs_main",
        "vs_5_0",
        0,
        0,
        &vs_blob,
        &vs_errors,
    );
    if (vs_errors) |errs| {
        if (errs.getBufferPointer()) |ptr| {
            const msg: [*]const u8 = @ptrCast(ptr);
            log.err("VS compile error: {s}", .{msg[0..errs.getBufferSize()]});
        } else {
            log.err("VS compile error: unknown", .{});
        }
        errs.release();
    }
    if (vs_hr < 0) return error.ShaderCompileFailed;
    const vs_b = vs_blob orelse return error.ShaderCompileFailed;
    defer vs_b.release();

    const vs_ptr = vs_b.getBufferPointer() orelse return error.ShaderCompileFailed;
    const vs_size = vs_b.getBufferSize();
    const vs_data: [*]const u8 = @ptrCast(vs_ptr);

    // Save bytecode for input layout creation
    const bytecode_copy = try alloc.alloc(u8, vs_size);
    @memcpy(bytecode_copy, vs_data[0..vs_size]);

    const vertex_shader = device.createVertexShader(vs_data[0..vs_size]) catch return error.ShaderCompileFailed;
    errdefer vertex_shader.release();

    // Compile pixel shader
    var ps_blob: ?*com.ID3DBlob = null;
    var ps_errors: ?*com.ID3DBlob = null;
    const ps_hr = com.D3DCompile(
        opts.fragment_fn.ptr,
        opts.fragment_fn.len,
        null,
        null,
        null,
        "ps_main",
        "ps_5_0",
        0,
        0,
        &ps_blob,
        &ps_errors,
    );
    if (ps_errors) |errs| {
        if (errs.getBufferPointer()) |ptr| {
            const msg: [*]const u8 = @ptrCast(ptr);
            log.err("PS compile error: {s}", .{msg[0..errs.getBufferSize()]});
        } else {
            log.err("PS compile error: unknown", .{});
        }
        errs.release();
    }
    if (ps_hr < 0) return error.ShaderCompileFailed;
    const ps_b = ps_blob orelse return error.ShaderCompileFailed;
    defer ps_b.release();

    const ps_ptr = ps_b.getBufferPointer() orelse return error.ShaderCompileFailed;
    const ps_size = ps_b.getBufferSize();
    const ps_data: [*]const u8 = @ptrCast(ps_ptr);

    const pixel_shader = device.createPixelShader(ps_data[0..ps_size]) catch return error.ShaderCompileFailed;
    errdefer pixel_shader.release();

    // Create input layout from vertex attributes (if any)
    var input_layout: ?*com.ID3D11InputLayout = null;
    if (VertexAttributes) |VA| {
        const descs = comptime buildInputElementDescs(VA);
        input_layout = device.createInputLayoutFromBytecode(
            &descs,
            vs_ptr,
            vs_size,
        ) catch return error.ShaderCompileFailed;
    }

    // Create blend state
    var blend_desc = com.D3D11_BLEND_DESC{};
    if (opts.blending_enabled) {
        blend_desc.RenderTarget[0] = .{
            .BlendEnable = 1,
            .SrcBlend = .ONE,
            .DestBlend = .INV_SRC_ALPHA,
            .BlendOp = .ADD,
            .SrcBlendAlpha = .ONE,
            .DestBlendAlpha = .INV_SRC_ALPHA,
            .BlendOpAlpha = .ADD,
            .RenderTargetWriteMask = com.D3D11_COLOR_WRITE_ENABLE_ALL,
        };
    }
    const blend_state = device.createBlendState(&blend_desc) catch return error.ShaderCompileFailed;

    // Create rasterizer state
    const rast_desc = com.D3D11_RASTERIZER_DESC{
        .CullMode = .NONE,
        .FrontCounterClockwise = 0,
    };
    const rasterizer_state = device.createRasterizerState(&rast_desc) catch return error.ShaderCompileFailed;

    return .{
        .vertex_shader = vertex_shader,
        .pixel_shader = pixel_shader,
        .input_layout = input_layout,
        .blend_state = blend_state,
        .rasterizer_state = rasterizer_state,
        .stride = if (VertexAttributes) |VA| @sizeOf(VA) else 0,
        .blending_enabled = opts.blending_enabled,
        .vs_bytecode = bytecode_copy,
        .vs_bytecode_alloc = alloc,
    };
}

pub fn deinit(self: *const Self) void {
    if (self.vs_bytecode) |bc| {
        if (self.vs_bytecode_alloc) |a| a.free(bc);
    }
    if (self.vertex_shader) |vs| vs.release();
    if (self.pixel_shader) |ps| ps.release();
    if (self.input_layout) |il| il.release();
    if (self.blend_state) |bs| bs.release();
    if (self.rasterizer_state) |rs| rs.release();
}

/// Bind this pipeline to the device context.
pub fn bind(self: *const Self, ctx: *com.ID3D11DeviceContext) void {
    ctx.vsSetShader(self.vertex_shader);
    ctx.psSetShader(self.pixel_shader);
    ctx.iaSetInputLayout(self.input_layout);
    ctx.omSetBlendState(self.blend_state, null, 0xffffffff);
    ctx.rsSetState(self.rasterizer_state);
}

/// Build input element descriptors from a Zig struct type at comptime.
pub fn buildInputElementDescs(comptime T: type) [std.meta.fields(T).len]com.D3D11_INPUT_ELEMENT_DESC {
    const fields = std.meta.fields(T);
    var descs: [fields.len]com.D3D11_INPUT_ELEMENT_DESC = undefined;

    inline for (fields, 0..) |field, i| {
        const FT = switch (@typeInfo(field.type)) {
            .@"struct" => |s| s.backing_integer.?,
            .@"enum" => |e| e.tag_type,
            else => field.type,
        };

        const format = comptime fieldToFormat(FT);

        descs[i] = .{
            .SemanticName = "TEXCOORD",
            .SemanticIndex = i,
            .Format = format,
            .InputSlot = 0,
            .AlignedByteOffset = @offsetOf(T, field.name),
            .InputSlotClass = .PER_INSTANCE_DATA,
            .InstanceDataStepRate = 1,
        };
    }

    return descs;
}

pub fn fieldToFormat(comptime FT: type) com.DXGI_FORMAT {
    return switch (FT) {
        [2]u32 => .R32G32_UINT,
        [2]u16 => .R16G16_UINT,
        [2]i16 => .R16G16_SINT,
        [4]u8 => .R8G8B8A8_UINT,
        u32 => .R32_UINT,
        u16 => .R16_UINT,
        u8 => .R8_UINT,
        [4]f32 => .R32G32B32A32_FLOAT,
        [2]f32 => .R32G32_FLOAT,
        f32 => .R32_FLOAT,
        else => .R32_UINT, // fallback
    };
}

const error_set = error{ShaderCompileFailed};

test "fieldToFormat: full table coverage" {
    const testing = std.testing;
    try testing.expectEqual(com.DXGI_FORMAT.R32G32_UINT, fieldToFormat([2]u32));
    try testing.expectEqual(com.DXGI_FORMAT.R16G16_UINT, fieldToFormat([2]u16));
    try testing.expectEqual(com.DXGI_FORMAT.R16G16_SINT, fieldToFormat([2]i16));
    try testing.expectEqual(com.DXGI_FORMAT.R8G8B8A8_UINT, fieldToFormat([4]u8));
    try testing.expectEqual(com.DXGI_FORMAT.R32_UINT, fieldToFormat(u32));
    try testing.expectEqual(com.DXGI_FORMAT.R16_UINT, fieldToFormat(u16));
    try testing.expectEqual(com.DXGI_FORMAT.R8_UINT, fieldToFormat(u8));
    try testing.expectEqual(com.DXGI_FORMAT.R32G32B32A32_FLOAT, fieldToFormat([4]f32));
    try testing.expectEqual(com.DXGI_FORMAT.R32G32_FLOAT, fieldToFormat([2]f32));
    try testing.expectEqual(com.DXGI_FORMAT.R32_FLOAT, fieldToFormat(f32));
}

test "fieldToFormat: fallback for unsupported type pinned to R32_UINT" {
    const testing = std.testing;
    // Pin current fallback behavior — types not in the explicit table return R32_UINT.
    try testing.expectEqual(com.DXGI_FORMAT.R32_UINT, fieldToFormat(i32));
    try testing.expectEqual(com.DXGI_FORMAT.R32_UINT, fieldToFormat(f64));
    try testing.expectEqual(com.DXGI_FORMAT.R32_UINT, fieldToFormat([3]f32));
}

test "buildInputElementDescs: sample struct yields per-field descs" {
    const testing = std.testing;
    const Sample = extern struct { pos: [2]f32, uv: [2]f32, color: [4]f32 };

    const descs = comptime buildInputElementDescs(Sample);
    try testing.expectEqual(@as(usize, 3), descs.len);

    // Format matches fieldToFormat for each field type.
    try testing.expectEqual(fieldToFormat([2]f32), descs[0].Format);
    try testing.expectEqual(fieldToFormat([2]f32), descs[1].Format);
    try testing.expectEqual(fieldToFormat([4]f32), descs[2].Format);

    // AlignedByteOffset matches @offsetOf for each field.
    try testing.expectEqual(@as(com.UINT, @offsetOf(Sample, "pos")), descs[0].AlignedByteOffset);
    try testing.expectEqual(@as(com.UINT, @offsetOf(Sample, "uv")), descs[1].AlignedByteOffset);
    try testing.expectEqual(@as(com.UINT, @offsetOf(Sample, "color")), descs[2].AlignedByteOffset);

    // InputSlotClass is PER_INSTANCE_DATA for all entries.
    try testing.expectEqual(com.D3D11_INPUT_CLASSIFICATION.PER_INSTANCE_DATA, descs[0].InputSlotClass);
    try testing.expectEqual(com.D3D11_INPUT_CLASSIFICATION.PER_INSTANCE_DATA, descs[1].InputSlotClass);
    try testing.expectEqual(com.D3D11_INPUT_CLASSIFICATION.PER_INSTANCE_DATA, descs[2].InputSlotClass);

    // SemanticName matches what the impl emits.
    try testing.expectEqualStrings("TEXCOORD", std.mem.span(descs[0].SemanticName));
    try testing.expectEqualStrings("TEXCOORD", std.mem.span(descs[1].SemanticName));
    try testing.expectEqualStrings("TEXCOORD", std.mem.span(descs[2].SemanticName));

    // SemanticIndex is 0, 1, 2.
    try testing.expectEqual(@as(com.UINT, 0), descs[0].SemanticIndex);
    try testing.expectEqual(@as(com.UINT, 1), descs[1].SemanticIndex);
    try testing.expectEqual(@as(com.UINT, 2), descs[2].SemanticIndex);
}
