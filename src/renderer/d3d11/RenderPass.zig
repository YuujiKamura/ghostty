//! D3D11 render pass wrapper.
const Self = @This();

const std = @import("std");
const com = @import("com.zig");
const Sampler = @import("Sampler.zig");
const Target = @import("Target.zig");
const Texture = @import("Texture.zig");
const Pipeline = @import("Pipeline.zig");
const Buffer = @import("buffer.zig").Buffer;

/// Constant buffer slot for uniforms.
const UNIFORM_SLOT: com.UINT = 0;

/// Options for beginning a render pass.
pub const Options = struct {
    attachments: []const Attachment,

    pub const Attachment = struct {
        target: union(enum) {
            texture: Texture,
            target: Target,
        },
        clear_color: ?[4]f32 = null,
    };
};

/// Describes a step in a render pass.
pub const Step = struct {
    pipeline: Pipeline,
    uniforms: ?*com.ID3D11Buffer = null,
    buffers: []const ?*com.ID3D11Buffer = &.{},
    textures: []const ?Texture = &.{},
    samplers: []const ?Sampler = &.{},
    draw: Draw,

    pub const Draw = struct {
        type: com.D3D11_PRIMITIVE_TOPOLOGY,
        vertex_count: usize,
        instance_count: usize = 1,
    };
};

attachments: []const Options.Attachment,
step_number: usize = 0,
context: ?*com.ID3D11DeviceContext = null,

/// Begin a render pass.
pub fn begin(opts: Options) Self {
    return .{
        .attachments = opts.attachments,
    };
}

/// Set the device context for this pass (called by the API layer).
pub fn setContext(self: *Self, ctx: *com.ID3D11DeviceContext) void {
    self.context = ctx;
}

/// Add a step to this render pass.
pub fn step(self: *Self, s: Step) void {
    if (s.draw.instance_count == 0) return;
    const ctx = self.context orelse return;
    s.pipeline.bind(ctx);
    self.bindRenderTarget(ctx);
    bindResources(ctx, s);
    executeDraw(ctx, s);
    self.step_number += 1;
}

/// Bind the render target and optionally clear it.
fn bindRenderTarget(self: *Self, ctx: *com.ID3D11DeviceContext) void {
    if (self.step_number != 0 or self.attachments.len == 0) return;
    const rtv: ?*com.ID3D11RenderTargetView = switch (self.attachments[0].target) {
        .target => |t| t.rtv,
        .texture => null, // TODO: texture-as-target
    };
    if (rtv) |r| {
        const rtvs = [1]?*com.ID3D11RenderTargetView{r};
        ctx.omSetRenderTargets(&rtvs, null);
    }
    if (self.attachments[0].clear_color) |c| {
        if (rtv) |r| ctx.clearRenderTargetView(r, &c);
    }
}

/// Bind uniforms, textures, samplers, and vertex buffers.
fn bindResources(ctx: *com.ID3D11DeviceContext, s: Step) void {
    // Uniform buffer
    if (s.uniforms) |ubo| {
        const cbs = [1]?*com.ID3D11Buffer{ubo};
        ctx.vsSetConstantBuffers(UNIFORM_SLOT, &cbs);
        ctx.psSetConstantBuffers(UNIFORM_SLOT, &cbs);
    }
    // Textures
    for (s.textures, 0..) |t, i| if (t) |tex| {
        if (tex.srv) |srv| {
            const srvs = [1]?*com.ID3D11ShaderResourceView{srv};
            ctx.psSetShaderResources(@intCast(i), &srvs);
        }
    };
    // Samplers
    for (s.samplers, 0..) |sampler, i| if (sampler) |samp| {
        if (samp.sampler) |ss| {
            const samps = [1]?*com.ID3D11SamplerState{ss};
            ctx.psSetSamplers(@intCast(i), &samps);
        }
    };
    // Vertex buffer (first in buffers array)
    if (s.buffers.len > 0) {
        if (s.buffers[0]) |vbo| {
            const bufs = [1]?*com.ID3D11Buffer{vbo};
            const strides = [1]com.UINT{@intCast(s.pipeline.stride)};
            const offsets = [1]com.UINT{0};
            ctx.iaSetVertexBuffers(0, &bufs, &strides, &offsets);
        }
        // Additional buffers as SRVs would need StructuredBuffer support - TODO
    }
}

/// Set topology and issue draw call.
fn executeDraw(ctx: *com.ID3D11DeviceContext, s: Step) void {
    ctx.iaSetPrimitiveTopology(s.draw.type);
    if (s.draw.instance_count > 1) {
        ctx.drawInstanced(
            @intCast(s.draw.vertex_count),
            @intCast(s.draw.instance_count),
            0,
            0,
        );
    } else {
        ctx.draw(@intCast(s.draw.vertex_count), 0);
    }
}

/// Complete this render pass.
pub fn complete(self: *const Self) void {
    _ = self;
    // D3D11 doesn't need explicit pass completion.
}
