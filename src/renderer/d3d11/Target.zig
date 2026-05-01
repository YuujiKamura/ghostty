//! UPSTREAM-SHARED-OK: fork-only file in src/renderer/d3d11/ — D3D11 backend
//! D3D11 render target.
//!
//! Represents an offscreen render target backed by a Texture2D + RTV.
const Self = @This();

const std = @import("std");
const com = @import("com.zig");

/// Options for initializing a Target.
pub const Options = struct {
    width: usize,
    height: usize,
    format: com.DXGI_FORMAT = .R8G8B8A8_UNORM_SRGB,
};

texture: ?*com.ID3D11Texture2D = null,
rtv: ?*com.ID3D11RenderTargetView = null,
srv: ?*com.ID3D11ShaderResourceView = null,

width: usize,
height: usize,

pub fn init(device: *com.ID3D11Device, opts: Options) !Self {
    const desc = com.D3D11_TEXTURE2D_DESC{
        .Width = @intCast(opts.width),
        .Height = @intCast(opts.height),
        .Format = opts.format,
        .BindFlags = com.D3D11_BIND_RENDER_TARGET | com.D3D11_BIND_SHADER_RESOURCE,
    };

    const tex = device.createTexture2D(&desc, null) catch return error.D3D11Failed;
    errdefer tex.release();

    const rtv = device.createRenderTargetView(@ptrCast(tex), null) catch return error.D3D11Failed;
    errdefer rtv.release();

    const srv_desc = com.D3D11_SHADER_RESOURCE_VIEW_DESC{
        .Format = opts.format,
        .ViewDimension = com.D3D11_SRV_DIMENSION_TEXTURE2D,
        .u = .{ .Texture2D = .{ .MostDetailedMip = 0, .MipLevels = 1 } },
    };
    const srv = device.createShaderResourceView(@ptrCast(tex), &srv_desc) catch return error.D3D11Failed;

    return .{
        .texture = tex,
        .rtv = rtv,
        .srv = srv,
        .width = opts.width,
        .height = opts.height,
    };
}

pub fn deinit(self: *Self) void {
    if (self.srv) |srv| srv.release();
    if (self.rtv) |rtv| rtv.release();
    if (self.texture) |tex| tex.release();
    self.* = undefined;
}
