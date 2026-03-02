//! D3D11 sampler state wrapper.
const Self = @This();

const std = @import("std");
const com = @import("com.zig");

/// Options for initializing a sampler.
pub const Options = struct {
    /// D3D11 device — needed for sampler state creation.
    device: ?*com.ID3D11Device = null,
    filter: com.D3D11_FILTER = .MIN_MAG_MIP_LINEAR,
    address_u: com.D3D11_TEXTURE_ADDRESS_MODE = .CLAMP,
    address_v: com.D3D11_TEXTURE_ADDRESS_MODE = .CLAMP,
};

sampler: ?*com.ID3D11SamplerState = null,

pub const Error = error{
    D3D11Failed,
};

/// Initialize a sampler state.
/// Matches OpenGL's Sampler.init(opts) signature.
pub fn init(
    opts: Options,
) Error!Self {
    const device = opts.device orelse return error.D3D11Failed;

    const desc = com.D3D11_SAMPLER_DESC{
        .Filter = opts.filter,
        .AddressU = opts.address_u,
        .AddressV = opts.address_v,
        .AddressW = .CLAMP,
    };

    const sampler = device.createSamplerState(&desc) catch return error.D3D11Failed;
    return .{ .sampler = sampler };
}

pub fn deinit(self: Self) void {
    if (self.sampler) |s| s.release();
}
