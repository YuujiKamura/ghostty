// UPSTREAM-SHARED-OK: fork-only file in src/renderer/shaders/hlsl/ — D3D11 shaders
#include "common.hlsl"

Texture2D<float4> image_tex : register(t0);

struct VSInput {
    float2 grid_pos    : TEXCOORD0;
    float2 cell_offset : TEXCOORD1;
    float4 source_rect : TEXCOORD2;
    float2 dest_size   : TEXCOORD3;
    uint   vertexID    : SV_VertexID;
};

struct VSOutput {
    float4 position  : SV_Position;
    float2 tex_coord : TEXCOORD0;
};

VSOutput vs_main(VSInput input) {
    VSOutput output;
    int vid = input.vertexID;

    // We use a triangle strip with 4 vertices to render quads,
    // so we determine which corner of the cell this vertex is in
    // based on the vertex ID.
    //
    //   0 --> 1
    //   |   .'|
    //   |  /  |
    //   | L   |
    //   2 --> 3
    //
    // 0 = top-left  (0, 0)
    // 1 = top-right (1, 0)
    // 2 = bot-left  (0, 1)
    // 3 = bot-right (1, 1)
    float2 corner;
    corner.x = float(vid == 1 || vid == 3);
    corner.y = float(vid == 2 || vid == 3);

    // The texture coordinates start at our source x/y
    // and add the width/height depending on the corner.
    output.tex_coord = input.source_rect.xy;
    output.tex_coord += input.source_rect.zw * corner;

    // Normalize the coordinates.
    uint2 tex_dims;
    image_tex.GetDimensions(tex_dims.x, tex_dims.y);
    output.tex_coord /= float2(tex_dims);

    // The position of our image starts at the top-left of the grid cell and
    // adds the source rect width/height components.
    float2 image_pos = (cell_size * input.grid_pos) + input.cell_offset;
    image_pos += input.dest_size * corner;

    // z = 0.0 (D3D11 NDC depth is [0, 1]; ortho2d's z-scale is -1, so input
    // z = 1.0 maps to NDC z = -1 which is outside the valid range and the
    // entire quad gets clipped — invisible overlay. cell_text passes 0.0
    // for the same reason. This was the root cause of the long-standing
    // "image .overlay never appears" bug on the D3D11 backend.
    output.position = mul(projection_matrix, float4(image_pos.xy, 0.0, 1.0));

    return output;
}
