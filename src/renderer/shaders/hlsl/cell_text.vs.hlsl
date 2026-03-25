#include "common.hlsl"

// Values `atlas` can take.
static const uint ATLAS_GRAYSCALE = 0u;
static const uint ATLAS_COLOR = 1u;

// Masks for the `glyph_bools` attribute
static const uint NO_MIN_CONTRAST = 1u;
static const uint IS_CURSOR_GLYPH = 2u;

struct VSInput {
    uint2 glyph_pos   : TEXCOORD0; // The position of the glyph in the texture (x, y)
    uint2 glyph_size  : TEXCOORD1; // The size of the glyph in the texture (w, h)
    int2  bearings    : TEXCOORD2; // The left and top bearings for the glyph (x, y)
    uint2 grid_pos    : TEXCOORD3; // The grid coordinates (x, y) where x < columns and y < rows
    uint4 color       : TEXCOORD4; // The color of the rendered text glyph.
    uint  atlas       : TEXCOORD5; // Which atlas this glyph is in.
    uint  glyph_bools : TEXCOORD6; // Misc glyph properties.
    uint  vertexID    : SV_VertexID;
};

struct VSOutput {
    float4 position : SV_Position;
    nointerpolation uint   atlas    : TEXCOORD0;
    nointerpolation float4 color    : TEXCOORD1;
    nointerpolation float4 bg_color : TEXCOORD2;
    float2 tex_coord : TEXCOORD3;
};

StructuredBuffer<uint> bg_cells : register(t2);

VSOutput vs_main(VSInput input) {
    VSOutput output;

    uint2 grid_size = unpack2u16(grid_size_packed_2u16);
    uint2 cursor_pos = unpack2u16(cursor_pos_packed_2u16);
    bool cursor_wide = (bools & CURSOR_WIDE) != 0;
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;

    // Convert the grid x, y into world space x, y by accounting for cell size
    float2 cell_pos = cell_size * float2(input.grid_pos);

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

    output.atlas = input.atlas;

    float2 size = float2(input.glyph_size);
    float2 offset = float2(input.bearings);

    offset.y = cell_size.y - offset.y;

    // Calculate the final position of the cell which uses our glyph size
    // and glyph offset to create the correct bounding box for the glyph.
    cell_pos = cell_pos + size * corner + offset;
    output.position = mul(projection_matrix, float4(cell_pos.x, cell_pos.y, 0.0f, 1.0f));

    // Calculate the texture coordinate in pixels. This is NOT normalized
    // (between 0.0 and 1.0), and does not need to be, since the texture will
    // be sampled with pixel coordinate mode (Load).
    output.tex_coord = float2(input.glyph_pos) + float2(input.glyph_size) * corner;

    // Get our color. We always fetch a linearized version to
    // make it easier to handle minimum contrast calculations.
    output.color = load_color(input.color, true);
    // Get the BG color
    output.bg_color = load_color(
        unpack4u8(bg_cells[input.grid_pos.y * grid_size.x + input.grid_pos.x]),
        true
    );
    // Blend it with the global bg color
    float4 global_bg = load_color(
        unpack4u8(bg_color_packed_4u8),
        true
    );
    output.bg_color += global_bg * float4(1.0 - output.bg_color.a, 1.0 - output.bg_color.a, 1.0 - output.bg_color.a, 1.0 - output.bg_color.a);

    // If we have a minimum contrast, we need to check if we need to
    // change the color of the text to ensure it has enough contrast
    // with the background.
    if (min_contrast > 1.0f && (input.glyph_bools & NO_MIN_CONTRAST) == 0) {
        // Ensure our minimum contrast
        output.color = contrasted_color(min_contrast, output.color, output.bg_color);
    }

    // Check if current position is under cursor (including wide cursor)
    bool is_cursor_pos = ((input.grid_pos.x == cursor_pos.x) || (cursor_wide && (input.grid_pos.x == (cursor_pos.x + 1)))) && (input.grid_pos.y == cursor_pos.y);

    // If this cell is the cursor cell, but we're not processing
    // the cursor glyph itself, then we need to change the color.
    if ((input.glyph_bools & IS_CURSOR_GLYPH) == 0 && is_cursor_pos) {
        output.color = load_color(unpack4u8(cursor_color_packed_4u8), true);
    }

    return output;
}
