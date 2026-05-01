// UPSTREAM-SHARED-OK: fork-only file in src/renderer/shaders/hlsl/ — D3D11 shaders
#include "common.hlsl"

Texture2D<float4> image_tex : register(t0);
SamplerState image_sampler : register(s0);

struct PSInput {
    float4 position  : SV_Position;
    float2 tex_coord : TEXCOORD0;
};

float4 ps_main(PSInput input) : SV_Target {
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;

    float4 rgba = image_tex.Sample(image_sampler, input.tex_coord);

    if (!use_linear_blending) {
        rgba = unlinearize4(rgba);
    }

    rgba.rgb *= float3(rgba.a, rgba.a, rgba.a);

    return rgba;
}
