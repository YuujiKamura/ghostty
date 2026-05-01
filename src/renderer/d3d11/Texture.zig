//! UPSTREAM-SHARED-OK: fork-only file in src/renderer/d3d11/ — D3D11 backend
//! D3D11 texture wrapper (ID3D11Texture2D + ShaderResourceView).
const Self = @This();

const std = @import("std");
const com = @import("com.zig");

const log = std.log.scoped(.d3d11);

/// Options for initializing a texture.
pub const Options = struct {
    /// D3D11 device — needed for texture/SRV creation.
    device: ?*com.ID3D11Device = null,
    /// D3D11 device context — needed for replaceRegion.
    context: ?*com.ID3D11DeviceContext = null,
    format: com.DXGI_FORMAT = .R8G8B8A8_UNORM_SRGB,
    /// Whether to use pixel-coordinate sampling (Load) vs normalized (Sample).
    pixel_coords: bool = false,
};

/// The D3D11 texture resource.
texture: ?*com.ID3D11Texture2D = null,

/// Shader resource view for binding to shaders.
srv: ?*com.ID3D11ShaderResourceView = null,

/// Width of this texture.
width: usize,

/// Height of this texture.
height: usize,

/// Format of this texture.
format: com.DXGI_FORMAT,

/// Device context for replaceRegion.
context: ?*com.ID3D11DeviceContext = null,

pub const Error = error{
    D3D11Failed,
};

/// Initialize a texture.
/// Matches OpenGL's Texture.init(opts, width, height, data) signature.
pub fn init(
    opts: Options,
    width: usize,
    height: usize,
    data: ?[]const u8,
) Error!Self {
    const device = opts.device orelse return error.D3D11Failed;

    const desc = com.D3D11_TEXTURE2D_DESC{
        .Width = @intCast(width),
        .Height = @intCast(height),
        .Format = opts.format,
        .BindFlags = com.D3D11_BIND_SHADER_RESOURCE,
    };

    const init_data: ?*const com.D3D11_SUBRESOURCE_DATA = if (data) |d| &com.D3D11_SUBRESOURCE_DATA{
        .pSysMem = @ptrCast(d.ptr),
        .SysMemPitch = @intCast(width * formatBytesPerPixel(opts.format)),
    } else null;

    const tex = device.createTexture2D(&desc, init_data) catch return error.D3D11Failed;
    errdefer tex.release();

    // Create SRV with default view (matches texture format).
    const srv_desc = com.D3D11_SHADER_RESOURCE_VIEW_DESC{
        .Format = opts.format,
        .ViewDimension = com.D3D11_SRV_DIMENSION_TEXTURE2D,
        .u = .{ .Texture2D = .{ .MostDetailedMip = 0, .MipLevels = 1 } },
    };
    const srv = device.createShaderResourceView(@ptrCast(tex), &srv_desc) catch return error.D3D11Failed;

    return .{
        .texture = tex,
        .srv = srv,
        .width = width,
        .height = height,
        .format = opts.format,
        .context = opts.context,
    };
}

pub fn deinit(self: Self) void {
    if (self.srv) |srv| srv.release();
    if (self.texture) |tex| tex.release();
}

/// Replace a region of the texture with the provided data.
/// Matches OpenGL's Texture.replaceRegion(x, y, w, h, data) signature.
pub fn replaceRegion(
    self: Self,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    data: []const u8,
) Error!void {
    const tex = self.texture orelse return error.D3D11Failed;
    const context = self.context orelse return error.D3D11Failed;
    const box = com.D3D11_BOX{
        .left = @intCast(x),
        .top = @intCast(y),
        .front = 0,
        .right = @intCast(x + width),
        .bottom = @intCast(y + height),
        .back = 1,
    };
    const row_pitch: com.UINT = @intCast(width * formatBytesPerPixel(self.format));
    context.updateSubresource(@ptrCast(tex), 0, &box, @ptrCast(data.ptr), row_pitch, 0);
}

pub fn formatBytesPerPixel(format: com.DXGI_FORMAT) usize {
    return switch (format) {
        .R8_UNORM, .R8_UINT => 1,
        .R8G8B8A8_UNORM,
        .R8G8B8A8_UNORM_SRGB,
        .R8G8B8A8_UINT,
        .B8G8R8A8_UNORM,
        .B8G8R8A8_UNORM_SRGB,
        .R32_FLOAT,
        .R32_UINT,
        => 4,
        .R32G32_FLOAT, .R32G32_UINT => 8,
        .R16G16B16A16_FLOAT => 8,
        .R32G32B32A32_FLOAT => 16,
        else => 4,
    };
}

test "formatBytesPerPixel: table-driven coverage of DXGI formats" {
    const T = std.testing;

    // 1-byte formats.
    try T.expectEqual(@as(usize, 1), formatBytesPerPixel(.R8_UNORM));
    try T.expectEqual(@as(usize, 1), formatBytesPerPixel(.R8_UINT));

    // 4-byte formats (RGBA8 / BGRA8 / sRGB variants / R32 single-channel).
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.R8G8B8A8_UNORM));
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.R8G8B8A8_UNORM_SRGB));
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.R8G8B8A8_UINT));
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.B8G8R8A8_UNORM));
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.B8G8R8A8_UNORM_SRGB));
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.R32_FLOAT));
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.R32_UINT));

    // 8-byte formats.
    try T.expectEqual(@as(usize, 8), formatBytesPerPixel(.R32G32_FLOAT));
    try T.expectEqual(@as(usize, 8), formatBytesPerPixel(.R32G32_UINT));
    try T.expectEqual(@as(usize, 8), formatBytesPerPixel(.R16G16B16A16_FLOAT));

    // 16-byte format.
    try T.expectEqual(@as(usize, 16), formatBytesPerPixel(.R32G32B32A32_FLOAT));

    // Fallback: any format not in the explicit arms returns 4.
    // Pin this so a future change is forced to consider whether a default
    // of 4 still makes sense.
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.UNKNOWN));
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.R16G16_SINT));
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.R16G16_UINT));
    try T.expectEqual(@as(usize, 4), formatBytesPerPixel(.R16_UINT));
}
