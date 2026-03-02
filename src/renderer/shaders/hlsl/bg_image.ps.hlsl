#include "common.hlsl"

// D3D11 SV_Position in pixel shader is already in screen coords, origin upper-left.

Texture2D<float4> image_tex : register(t0);
SamplerState image_sampler : register(s0);

struct PSInput {
    float4 position : SV_Position;
    nointerpolation float4 bg_color    : TEXCOORD0;
    nointerpolation float2 offset      : TEXCOORD1;
    nointerpolation float2 scale       : TEXCOORD2;
    nointerpolation float  opacity     : TEXCOORD3;
    nointerpolation uint   repeat_flag : TEXCOORD4;
};

float4 ps_main(PSInput input) : SV_Target {
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;

    // Our texture coordinate is based on the screen position, offset by the
    // dest rect origin, and scaled by the ratio between the dest rect size
    // and the original texture size, which effectively scales the original
    // size of the texture to the dest rect size.
    float2 tex_coord = (input.position.xy - input.offset) * input.scale;

    uint2 tex_dims;
    image_tex.GetDimensions(tex_dims.x, tex_dims.y);
    float2 tex_size = float2(tex_dims);

    // If we need to repeat the texture, wrap the coordinates.
    if (input.repeat_flag != 0) {
        tex_coord = fmod(fmod(tex_coord, tex_size) + tex_size, tex_size);
    }

    float4 rgba;
    // If we're out of bounds, we have no color,
    // otherwise we sample the texture for it.
    bool out_of_bounds = (tex_coord.x < 0.0) || (tex_coord.y < 0.0) ||
                         (tex_coord.x > tex_size.x) || (tex_coord.y > tex_size.y);
    if (out_of_bounds) {
        rgba = float4(0.0, 0.0, 0.0, 0.0);
    } else {
        // We divide by the texture size to normalize for sampling.
        rgba = image_tex.Sample(image_sampler, tex_coord / tex_size);

        if (!use_linear_blending) {
            rgba = unlinearize4(rgba);
        }

        rgba.rgb *= rgba.a;
    }

    // Multiply it by the configured opacity, but cap it at
    // the value that will make it fully opaque relative to
    // the background color alpha, so it isn't overexposed.
    rgba *= min(input.opacity, 1.0 / input.bg_color.a);

    // Blend it on to a fully opaque version of the background color.
    rgba += max(float4(0.0, 0.0, 0.0, 0.0), float4(input.bg_color.rgb, 1.0) * float4(1.0 - rgba.a, 1.0 - rgba.a, 1.0 - rgba.a, 1.0 - rgba.a));

    // Multiply everything by the background color alpha.
    rgba *= input.bg_color.a;

    return rgba;
}
