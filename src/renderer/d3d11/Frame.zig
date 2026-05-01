//! UPSTREAM-SHARED-OK: fork-only file in src/renderer/d3d11/ — D3D11 backend
//! D3D11 frame context.
//!
//! Represents the context for drawing a single frame.
const Self = @This();

const std = @import("std");
const Target = @import("Target.zig");
const RenderPass = @import("RenderPass.zig");
const D3D11 = @import("../D3D11.zig");

const Health = @import("../../renderer.zig").Health;
const Renderer = @import("../generic.zig").Renderer(D3D11);

/// Options for beginning a frame.
pub const Options = struct {};

renderer: *Renderer,
target: *Target,

/// Begin encoding a frame.
pub fn begin(
    opts: Options,
    renderer: *Renderer,
    target: *Target,
) !Self {
    _ = opts;
    return .{
        .renderer = renderer,
        .target = target,
    };
}

/// Add a render pass to this frame with the provided attachments.
pub inline fn renderPass(
    self: *const Self,
    attachments: []const RenderPass.Options.Attachment,
) RenderPass {
    var pass = RenderPass.begin(.{ .attachments = attachments });
    // Wire up the D3D11 device context so draw calls actually execute.
    if (self.renderer.api.context) |ctx| pass.setContext(ctx);
    return pass;
}

/// Complete this frame and present the target.
pub fn complete(self: *const Self, sync: bool) void {
    _ = sync;

    // Present the rendered target.
    self.renderer.api.present(self.target.*) catch |err| {
        std.log.scoped(.d3d11).err("Failed to present render target: err={}", .{err});
        self.renderer.frameCompleted(.unhealthy);
        return;
    };

    self.renderer.frameCompleted(.healthy);
}
