#include "common.hlsl"

struct PSInput {
    float4 position : SV_Position;
};

float4 ps_main(PSInput input) : SV_Target {
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;

    return load_color(
        unpack4u8(bg_color_packed_4u8),
        use_linear_blending
    );
}
