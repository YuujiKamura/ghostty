//! D3D11 render pass wrapper.
const Self = @This();

const std = @import("std");
const com = @import("com.zig");
const Sampler = @import("Sampler.zig");
const Target = @import("Target.zig");
const Texture = @import("Texture.zig");
const Pipeline = @import("Pipeline.zig");
const Buffer = @import("buffer.zig").Buffer;
const log = std.log.scoped(.d3d11);

/// Constant buffer slot for uniforms.
const UNIFORM_SLOT: com.UINT = 0;
var trace_bg_loaded = std.atomic.Value(u8).init(0);
var trace_bg_enabled = std.atomic.Value(u8).init(0);
var trace_bg_sentinel_emitted = std.atomic.Value(u8).init(0);
var bind_trace_counter = std.atomic.Value(u64).init(0);

pub const TraceDiagnostics = struct {
    enabled: bool,
    bind_counter: u64,
    sentinel_emitted: bool,
};

fn traceBgEnabled() bool {
    if (trace_bg_loaded.load(.acquire) == 0) {
        const value = std.process.getEnvVarOwned(
            std.heap.page_allocator,
            "GHOSTTY_TRACE_BG_CELLS",
        ) catch {
            trace_bg_enabled.store(0, .release);
            trace_bg_loaded.store(1, .release);
            return false;
        };
        defer std.heap.page_allocator.free(value);

        const enabled = value.len == 0 or
            (!std.ascii.eqlIgnoreCase(value, "0") and
                !std.ascii.eqlIgnoreCase(value, "false"));
        trace_bg_enabled.store(if (enabled) 1 else 0, .release);
        trace_bg_loaded.store(1, .release);

        if (enabled and trace_bg_sentinel_emitted.cmpxchgStrong(0, 1, .acq_rel, .acquire) == null) {
            // Scope-independent sentinel for runtime self-diagnosis.
            std.debug.print("TRACE_BG_CELLS_ENABLED\n", .{});
        }
    }
    return trace_bg_enabled.load(.acquire) == 1;
}

pub fn traceDiagnostics() TraceDiagnostics {
    const enabled = traceBgEnabled();
    return .{
        .enabled = enabled,
        .bind_counter = bind_trace_counter.load(.acquire),
        .sentinel_emitted = trace_bg_sentinel_emitted.load(.acquire) == 1,
    };
}

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
    buffer_srvs: []const ?*com.ID3D11ShaderResourceView = &.{},
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
    var trace_sample = false;
    if (traceBgEnabled()) {
        const step_no = bind_trace_counter.fetchAdd(1, .monotonic) + 1;
        trace_sample = step_no <= 120 or (step_no % 120) == 0;
        if (trace_sample) {
            log.info(
                "bindResources: step={} stride={} buffers={} textures={} samplers={}",
                .{
                    step_no,
                    s.pipeline.stride,
                    s.buffers.len,
                    s.textures.len,
                    s.samplers.len,
                },
            );
        }
    }

    // Uniform buffer
    if (s.uniforms) |ubo| {
        const cbs = [1]?*com.ID3D11Buffer{ubo};
        ctx.vsSetConstantBuffers(UNIFORM_SLOT, &cbs);
        ctx.psSetConstantBuffers(UNIFORM_SLOT, &cbs);
        if (trace_sample) {
            log.info("bindResources: ubo_ptr=0x{x}", .{@intFromPtr(ubo)});
        }
    }
    // Textures
    for (s.textures, 0..) |t, i| if (t) |tex| {
        if (tex.srv) |srv| {
            const srvs = [1]?*com.ID3D11ShaderResourceView{srv};
            ctx.psSetShaderResources(@intCast(i), &srvs);
            if (trace_sample) {
                log.info(
                    "bindResources: ps_srv slot={} ptr=0x{x}",
                    .{ i, @intFromPtr(srv) },
                );
            }
        }
    };
    // Samplers
    for (s.samplers, 0..) |sampler, i| if (sampler) |samp| {
        if (samp.sampler) |ss| {
            const samps = [1]?*com.ID3D11SamplerState{ss};
            ctx.psSetSamplers(@intCast(i), &samps);
        }
    };
    if (s.buffer_srvs.len > 0) {
        ctx.vsSetShaderResources(2, s.buffer_srvs);
        ctx.psSetShaderResources(2, s.buffer_srvs);
        if (trace_sample) {
            log.info(
                "bindResources: buffer_srvs bound at t2 count={} first=0x{x}",
                .{
                    s.buffer_srvs.len,
                    if (s.buffer_srvs[0]) |srv| @intFromPtr(srv) else @as(usize, 0),
                },
            );
        }
    }
    // Vertex buffer (first in buffers array)
    if (s.buffers.len > 0) {
        if (s.buffers[0]) |vbo| {
            const bufs = [1]?*com.ID3D11Buffer{vbo};
            const strides = [1]com.UINT{@intCast(s.pipeline.stride)};
            const offsets = [1]com.UINT{0};
            ctx.iaSetVertexBuffers(0, &bufs, &strides, &offsets);
            if (trace_sample) {
                log.info(
                    "bindResources: ia vb0=0x{x} stride={} offset={}",
                    .{ @intFromPtr(vbo), strides[0], offsets[0] },
                );
            }
        }
        // Additional buffers are consumed through s.buffer_srvs (t2+ bindings).
        // If extras exist without SRV bindings, keep warning loudly.
        if (s.buffers.len > 1) {
            var non_null_extra: usize = 0;
            for (s.buffers[1..]) |maybe_buf| {
                if (maybe_buf != null) non_null_extra += 1;
            }
            if (trace_sample and non_null_extra > 0 and s.buffer_srvs.len == 0) {
                log.warn(
                    "bindResources: extra buffers present but no SRV binding provided (count={}, first_extra=0x{x})",
                    .{
                        non_null_extra,
                        if (s.buffers[1]) |buf| @intFromPtr(buf) else @as(usize, 0),
                    },
                );
            }
        }
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
