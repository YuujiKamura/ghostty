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
/// Constant buffer slot for frame constants (time, fps, etc.).
const CONSTANTS_SLOT: com.UINT = 1;
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
    constants: ?*com.ID3D11Buffer = null,
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
    if (s.draw.instance_count == 0) {
        log.info("step EARLY RETURN: instance_count=0 stride={}", .{s.pipeline.stride});
        return;
    }
    const ctx = self.context orelse {
        log.info("step EARLY RETURN: context=null stride={}", .{s.pipeline.stride});
        return;
    };
    if (s.pipeline.stride == 48) {
        // Image pipeline only.
        const vb_ptr: usize = if (s.buffers.len > 0) (if (s.buffers[0]) |b| @intFromPtr(b) else 0) else 0;
        const tex_ptr: usize = if (s.textures.len > 0) (if (s.textures[0]) |t| (if (t.srv) |srv| @intFromPtr(srv) else 0) else 0) else 0;
        log.info(
            "step IMAGE: stride={} vb=0x{x} tex_srv=0x{x} ubo=0x{x} vc={} ic={}",
            .{
                s.pipeline.stride,
                vb_ptr,
                tex_ptr,
                if (s.uniforms) |u| @intFromPtr(u) else 0,
                s.draw.vertex_count,
                s.draw.instance_count,
            },
        );
    }
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
    // Constants buffer (time, FPS, etc.)
    if (s.constants) |cbo| {
        const cbs = [1]?*com.ID3D11Buffer{cbo};
        ctx.vsSetConstantBuffers(CONSTANTS_SLOT, &cbs);
        ctx.psSetConstantBuffers(CONSTANTS_SLOT, &cbs);
        if (trace_sample) {
            log.info("bindResources: cbo_ptr=0x{x}", .{@intFromPtr(cbo)});
        }
    }
    // Textures
    bindTexturesToShaderStages(ContextShaderBinder{ .ctx = ctx }, s.textures);
    for (s.textures, 0..) |t, i| if (t) |tex| {
        if (tex.srv) |srv| {
            if (trace_sample) {
                log.info(
                    "bindResources: srv slot={} ptr=0x{x}",
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
    // Always use DrawInstanced so PER_INSTANCE_DATA InputLayout elements get
    // per-instance fetched correctly even for single-instance draws.
    ctx.drawInstanced(
        @intCast(s.draw.vertex_count),
        @intCast(s.draw.instance_count),
        0,
        0,
    );
}

/// Complete this render pass.
pub fn complete(self: *const Self) void {
    _ = self;
    // D3D11 doesn't need explicit pass completion.
}

/// Texture binder contract: bind a texture SRV to one or more shader stages.
///
/// IMPORTANT: When the image vertex shader (`shaders/hlsl/image.vs.hlsl`) calls
/// `image_tex.GetDimensions(...)` to normalize tex_coord, the texture MUST be
/// bound to the vertex shader stage as well as the pixel shader stage. Binding
/// only to PS makes GetDimensions return zero in VS, which produces NaN/Inf
/// positions and an invisible quad — the original "overlay never appears on
/// screen" bug.
///
/// `Binder` must expose `vsSet(slot, srv)` and `psSet(slot, srv)`. We accept it
/// via `anytype` so we can pass either a real D3D11-context-wrapped binder or a
/// recorder for unit tests.
pub fn bindTexturesToShaderStages(
    binder: anytype,
    textures: []const ?Texture,
) void {
    for (textures, 0..) |t, i| if (t) |tex| {
        if (tex.srv) |srv| {
            const slot: com.UINT = @intCast(i);
            binder.vsSet(slot, srv);
            binder.psSet(slot, srv);
        }
    };
}

/// Real D3D11 binder used at runtime.
pub const ContextShaderBinder = struct {
    ctx: *com.ID3D11DeviceContext,

    pub fn vsSet(self: ContextShaderBinder, slot: com.UINT, srv: *com.ID3D11ShaderResourceView) void {
        const srvs = [1]?*com.ID3D11ShaderResourceView{srv};
        self.ctx.vsSetShaderResources(slot, &srvs);
    }

    pub fn psSet(self: ContextShaderBinder, slot: com.UINT, srv: *com.ID3D11ShaderResourceView) void {
        const srvs = [1]?*com.ID3D11ShaderResourceView{srv};
        self.ctx.psSetShaderResources(slot, &srvs);
    }
};

// ============================================================================
// Tests
// ============================================================================

/// Recording binder that captures every vsSet/psSet invocation. Used by tests
/// to assert which stages received which SRV at which slot.
const RecordingBinder = struct {
    vs_calls: std.ArrayListUnmanaged(struct { slot: com.UINT, srv: usize }) = .empty,
    ps_calls: std.ArrayListUnmanaged(struct { slot: com.UINT, srv: usize }) = .empty,

    pub fn deinit(self: *RecordingBinder, alloc: std.mem.Allocator) void {
        self.vs_calls.deinit(alloc);
        self.ps_calls.deinit(alloc);
    }

    pub fn vsSet(self: *RecordingBinder, slot: com.UINT, srv: *com.ID3D11ShaderResourceView) void {
        self.vs_calls.append(std.testing.allocator, .{ .slot = slot, .srv = @intFromPtr(srv) }) catch unreachable;
    }

    pub fn psSet(self: *RecordingBinder, slot: com.UINT, srv: *com.ID3D11ShaderResourceView) void {
        self.ps_calls.append(std.testing.allocator, .{ .slot = slot, .srv = @intFromPtr(srv) }) catch unreachable;
    }
};

test "bindTexturesToShaderStages binds non-null texture to BOTH vertex and pixel shader stages" {
    // Regression test: image.vs.hlsl uses image_tex.GetDimensions() so the
    // texture must be bound to VS as well as PS. Binding only to PS produces
    // GetDimensions == (0,0) in VS, NaN tex_coord and positions, invisible quad.
    var rec: RecordingBinder = .{};
    defer rec.deinit(std.testing.allocator);

    const fake_srv: *com.ID3D11ShaderResourceView = @ptrFromInt(0xDEADBEEF);
    const fake_textures = [_]?Texture{
        .{ .texture = null, .srv = fake_srv, .width = 0, .height = 0, .format = .R8G8B8A8_UNORM },
    };

    bindTexturesToShaderStages(&rec, &fake_textures);

    try std.testing.expectEqual(@as(usize, 1), rec.vs_calls.items.len);
    try std.testing.expectEqual(@as(usize, 1), rec.ps_calls.items.len);
    try std.testing.expectEqual(@as(com.UINT, 0), rec.vs_calls.items[0].slot);
    try std.testing.expectEqual(@as(com.UINT, 0), rec.ps_calls.items[0].slot);
    try std.testing.expectEqual(@as(usize, 0xDEADBEEF), rec.vs_calls.items[0].srv);
    try std.testing.expectEqual(@as(usize, 0xDEADBEEF), rec.ps_calls.items[0].srv);
}

test "bindTexturesToShaderStages skips null texture entries" {
    var rec: RecordingBinder = .{};
    defer rec.deinit(std.testing.allocator);

    const fake_textures = [_]?Texture{ null, null };
    bindTexturesToShaderStages(&rec, &fake_textures);

    try std.testing.expectEqual(@as(usize, 0), rec.vs_calls.items.len);
    try std.testing.expectEqual(@as(usize, 0), rec.ps_calls.items.len);
}

test "bindTexturesToShaderStages skips texture with null SRV" {
    var rec: RecordingBinder = .{};
    defer rec.deinit(std.testing.allocator);

    const fake_textures = [_]?Texture{
        .{ .texture = null, .srv = null, .width = 0, .height = 0, .format = .R8G8B8A8_UNORM },
    };
    bindTexturesToShaderStages(&rec, &fake_textures);

    try std.testing.expectEqual(@as(usize, 0), rec.vs_calls.items.len);
    try std.testing.expectEqual(@as(usize, 0), rec.ps_calls.items.len);
}

test "bindTexturesToShaderStages assigns slot index per array position" {
    var rec: RecordingBinder = .{};
    defer rec.deinit(std.testing.allocator);

    const srv0: *com.ID3D11ShaderResourceView = @ptrFromInt(0x1111);
    const srv2: *com.ID3D11ShaderResourceView = @ptrFromInt(0x3333);
    const fake_textures = [_]?Texture{
        .{ .texture = null, .srv = srv0, .width = 0, .height = 0, .format = .R8G8B8A8_UNORM },
        null,
        .{ .texture = null, .srv = srv2, .width = 0, .height = 0, .format = .R8G8B8A8_UNORM },
    };
    bindTexturesToShaderStages(&rec, &fake_textures);

    try std.testing.expectEqual(@as(usize, 2), rec.vs_calls.items.len);
    try std.testing.expectEqual(@as(usize, 2), rec.ps_calls.items.len);
    try std.testing.expectEqual(@as(com.UINT, 0), rec.vs_calls.items[0].slot);
    try std.testing.expectEqual(@as(com.UINT, 2), rec.vs_calls.items[1].slot);
    try std.testing.expectEqual(@as(com.UINT, 0), rec.ps_calls.items[0].slot);
    try std.testing.expectEqual(@as(com.UINT, 2), rec.ps_calls.items[1].slot);
}

test "begin: round-trips empty attachments slice with zero-init step_number/context" {
    const opts: Options = .{ .attachments = &.{} };
    const pass = begin(opts);
    try std.testing.expectEqual(@as(usize, 0), pass.step_number);
    try std.testing.expectEqual(@as(?*com.ID3D11DeviceContext, null), pass.context);
    try std.testing.expectEqual(@as(usize, 0), pass.attachments.len);
    // Empty slice: ptr equality is undefined for zero-length slices, so just
    // assert the length contract.
}

test "begin: round-trips non-empty attachments slice by pointer identity" {
    const sentinel_attachments = [_]Options.Attachment{
        .{ .target = .{ .texture = .{
            .texture = null,
            .srv = null,
            .width = 0,
            .height = 0,
            .format = .R8G8B8A8_UNORM,
        } }, .clear_color = null },
        .{ .target = .{ .texture = .{
            .texture = null,
            .srv = null,
            .width = 0,
            .height = 0,
            .format = .R8G8B8A8_UNORM,
        } }, .clear_color = .{ 1.0, 0.0, 0.0, 1.0 } },
    };
    const opts: Options = .{ .attachments = &sentinel_attachments };
    const pass = begin(opts);
    try std.testing.expectEqual(@as(usize, 2), pass.attachments.len);
    try std.testing.expectEqual(opts.attachments.ptr, pass.attachments.ptr);
    try std.testing.expectEqual(@as(usize, 0), pass.step_number);
    try std.testing.expectEqual(@as(?*com.ID3D11DeviceContext, null), pass.context);
}

test "setContext: assigns sentinel pointer verbatim" {
    var pass = begin(.{ .attachments = &.{} });
    const sentinel: *com.ID3D11DeviceContext = @ptrFromInt(0xCAFE);
    pass.setContext(sentinel);
    try std.testing.expectEqual(@as(?*com.ID3D11DeviceContext, sentinel), pass.context);
}

test "setContext: overwrite replaces a prior context" {
    var pass = begin(.{ .attachments = &.{} });
    const first: *com.ID3D11DeviceContext = @ptrFromInt(0xCAFE);
    const second: *com.ID3D11DeviceContext = @ptrFromInt(0xBEEF);
    pass.setContext(first);
    pass.setContext(second);
    try std.testing.expectEqual(@as(?*com.ID3D11DeviceContext, second), pass.context);
}

test "complete: is a no-op — state unchanged after the call" {
    // Pin the no-op contract: complete() must not mutate Self. Future
    // maintainers who silently introduce side effects here will fail this.
    const sentinel_attachments = [_]Options.Attachment{
        .{ .target = .{ .texture = .{
            .texture = null,
            .srv = null,
            .width = 0,
            .height = 0,
            .format = .R8G8B8A8_UNORM,
        } }, .clear_color = null },
    };
    var pass = begin(.{ .attachments = &sentinel_attachments });
    const ctx_sentinel: *com.ID3D11DeviceContext = @ptrFromInt(0xCAFE);
    pass.setContext(ctx_sentinel);
    pass.step_number = 7; // simulate post-step state

    const before_ptr = pass.attachments.ptr;
    const before_len = pass.attachments.len;
    const before_step = pass.step_number;
    const before_ctx = pass.context;

    pass.complete();

    try std.testing.expectEqual(before_ptr, pass.attachments.ptr);
    try std.testing.expectEqual(before_len, pass.attachments.len);
    try std.testing.expectEqual(before_step, pass.step_number);
    try std.testing.expectEqual(before_ctx, pass.context);
}

test "complete: callable on default-constructed pass (no context, no attachments)" {
    const pass = begin(.{ .attachments = &.{} });
    pass.complete();
    // Reaching here = no panic, no UB, no mutation of `const` self.
    try std.testing.expectEqual(@as(usize, 0), pass.step_number);
}

test "traceDiagnostics: shape and field types" {
    const diag = traceDiagnostics();
    // Compile-time shape check via @TypeOf.
    try std.testing.expectEqual(bool, @TypeOf(diag.enabled));
    try std.testing.expectEqual(u64, @TypeOf(diag.bind_counter));
    try std.testing.expectEqual(bool, @TypeOf(diag.sentinel_emitted));
}

test "traceDiagnostics: idempotent — two consecutive reads agree" {
    // Pure read of cached atomics; back-to-back calls in a single thread must
    // observe identical values.
    const a = traceDiagnostics();
    const b = traceDiagnostics();
    try std.testing.expectEqual(a.enabled, b.enabled);
    try std.testing.expectEqual(a.bind_counter, b.bind_counter);
    try std.testing.expectEqual(a.sentinel_emitted, b.sentinel_emitted);
}

test "traceDiagnostics: enabled implies sentinel_emitted; disabled implies !sentinel_emitted" {
    // Cross-field invariant: the sentinel print only fires when env-var-driven
    // tracing is on. Either both bits are set or both are clear.
    const diag = traceDiagnostics();
    try std.testing.expectEqual(diag.enabled, diag.sentinel_emitted);
}

test "traceDiagnostics: default-off path with GHOSTTY_TRACE_BG_CELLS unset" {
    // When the env var is absent, the predicate must cache `enabled=false`,
    // never print the sentinel, and leave bind_counter at zero (no
    // bindResources call has occurred — only this test file's free helpers).
    if (std.process.hasEnvVarConstant("GHOSTTY_TRACE_BG_CELLS")) return error.SkipZigTest;
    const diag = traceDiagnostics();
    try std.testing.expectEqual(false, diag.enabled);
    try std.testing.expectEqual(false, diag.sentinel_emitted);
    try std.testing.expectEqual(@as(u64, 0), diag.bind_counter);
}
