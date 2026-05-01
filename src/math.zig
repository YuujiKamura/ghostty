/// Matrix type
pub const Mat = [4]F32x4;
pub const F32x4 = @Vector(4, f32);

/// 2D orthographic projection matrix
pub fn ortho2d(left: f32, right: f32, bottom: f32, top: f32) Mat {
    const w = right - left;
    const h = top - bottom;
    return .{
        .{ 2 / w, 0, 0, 0 },
        .{ 0, 2 / h, 0, 0 },
        .{ 0.0, 0.0, -1.0, 0.0 },
        .{ -(right + left) / w, -(top + bottom) / h, 0.0, 1.0 },
    };
}

const std = @import("std");
const testing = std.testing;

/// Apply ortho2d-produced matrix to an input vec4, mimicking HLSL `mul(M, v)`
/// with the matrix interpreted as column-major (D3D11 default). Zig stores
/// the matrix row-major; in HLSL column-major view, our row N becomes column N.
fn applyHLSLColumnMajor(m: Mat, v: [4]f32) [4]f32 {
    var out: [4]f32 = .{ 0, 0, 0, 0 };
    inline for (0..4) |i| {
        // out[i] = sum over j of (column j)[i] * v[j]
        // (column j)[i] = m[j][i]   (row-major Zig storage interpreted as columns)
        var acc: f32 = 0;
        inline for (0..4) |j| acc += m[j][i] * v[j];
        out[i] = acc;
    }
    return out;
}

test "ortho2d maps pixel x in [0, W] to NDC x in [-1, 1]" {
    const W: f32 = 800;
    const H: f32 = 600;
    const m = ortho2d(0, W, H, 0);
    const left = applyHLSLColumnMajor(m, .{ 0, 0, 0, 1 });
    const right = applyHLSLColumnMajor(m, .{ W, 0, 0, 1 });
    try testing.expectApproxEqAbs(@as(f32, -1), left[0] / left[3], 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 1), right[0] / right[3], 1e-5);
}

test "ortho2d maps pixel y in [0, H] to NDC y in [1, -1] (D3D11 y-flipped)" {
    const W: f32 = 800;
    const H: f32 = 600;
    const m = ortho2d(0, W, H, 0);
    const top = applyHLSLColumnMajor(m, .{ 0, 0, 0, 1 });
    const bot = applyHLSLColumnMajor(m, .{ 0, H, 0, 1 });
    try testing.expectApproxEqAbs(@as(f32, 1), top[1] / top[3], 1e-5);
    try testing.expectApproxEqAbs(@as(f32, -1), bot[1] / bot[3], 1e-5);
}

test "ortho2d clips quads when input z = 1.0 (D3D11 NDC z must be in [0, 1])" {
    // This is the regression test for the long-standing "image .overlay never
    // appears" bug on D3D11. ortho2d's z-row is (0, 0, -1, 0), so an input
    // z of 1.0 produces clip.z = -1 and NDC z = -1 — outside D3D11's [0, 1]
    // depth range, which clips the entire primitive.
    const W: f32 = 800;
    const H: f32 = 600;
    const m = ortho2d(0, W, H, 0);
    const z1 = applyHLSLColumnMajor(m, .{ 100, 100, 1.0, 1.0 });
    const ndc_z = z1[2] / z1[3];
    // The bug: NDC z is -1 (out of D3D11 [0, 1] range) when input z is 1.0.
    // image.vs.hlsl previously did exactly this and the quad was always
    // clipped — invisible overlay.
    try testing.expectApproxEqAbs(@as(f32, -1.0), ndc_z, 1e-5);
    try testing.expect(ndc_z < 0.0 or ndc_z > 1.0); // out of D3D11 range
}

test "ortho2d keeps quads visible when input z = 0.0 (D3D11 valid)" {
    // Companion of the previous test: input z = 0.0 produces NDC z = 0,
    // which is the near plane and inside D3D11's [0, 1] range. This is what
    // cell_text.vs.hlsl does, and what the fixed image.vs.hlsl now does.
    const W: f32 = 800;
    const H: f32 = 600;
    const m = ortho2d(0, W, H, 0);
    const z0 = applyHLSLColumnMajor(m, .{ 100, 100, 0.0, 1.0 });
    const ndc_z = z0[2] / z0[3];
    try testing.expectApproxEqAbs(@as(f32, 0.0), ndc_z, 1e-5);
    try testing.expect(ndc_z >= 0.0 and ndc_z <= 1.0); // inside D3D11 range
}
