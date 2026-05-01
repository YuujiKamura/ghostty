// UPSTREAM-SHARED-OK: fork-only file in src/renderer/shaders/hlsl/ — D3D11 shaders
// These are common definitions to be shared across shaders, the first
// line of any shader that needs these should be `#include "common.hlsl"`.
//
// Included in this file are:
// - The constant buffer for the global uniforms.
// - Functions for unpacking values.
// - Functions for working with colors.

//----------------------------------------------------------------------------//
// Global Uniforms
//----------------------------------------------------------------------------//
cbuffer Globals : register(b0) {
    float4x4 projection_matrix;
    float2 screen_size;
    float2 cell_size;
    uint grid_size_packed_2u16;
    float4 grid_padding;
    uint padding_extend;
    float min_contrast;
    uint cursor_pos_packed_2u16;
    uint cursor_color_packed_4u8;
    uint bg_color_packed_4u8;
    uint bools;
};

// Bools
static const uint CURSOR_WIDE = 1u;
static const uint USE_DISPLAY_P3 = 2u;
static const uint USE_LINEAR_BLENDING = 4u;
static const uint USE_LINEAR_CORRECTION = 8u;

// Padding extend enum
static const uint EXTEND_LEFT = 1u;
static const uint EXTEND_RIGHT = 2u;
static const uint EXTEND_UP = 4u;
static const uint EXTEND_DOWN = 8u;

//----------------------------------------------------------------------------//
// Functions for Unpacking Values
//----------------------------------------------------------------------------//
// NOTE: These unpack functions assume little-endian.
//       If this ever becomes a problem... oh dear!

uint4 unpack4u8(uint packed_value) {
    return uint4(
        (packed_value >> 0u) & 0xFFu,
        (packed_value >> 8u) & 0xFFu,
        (packed_value >> 16u) & 0xFFu,
        (packed_value >> 24u) & 0xFFu
    );
}

uint2 unpack2u16(uint packed_value) {
    return uint2(
        (packed_value >> 0u) & 0xFFFFu,
        (packed_value >> 16u) & 0xFFFFu
    );
}

int2 unpack2i16(int packed_value) {
    return int2(
        (packed_value << 16) >> 16,
        (packed_value << 0) >> 16
    );
}

//----------------------------------------------------------------------------//
// Color Functions
//----------------------------------------------------------------------------//

// Compute the luminance of the provided color.
//
// Takes colors in linear RGB space. If your colors are gamma
// encoded, linearize them before using them with this function.
float luminance(float3 color) {
    return dot(color, float3(0.2126f, 0.7152f, 0.0722f));
}

// https://www.w3.org/TR/2008/REC-WCAG20-20081211/#contrast-ratiodef
//
// Takes colors in linear RGB space. If your colors are gamma
// encoded, linearize them before using them with this function.
float contrast_ratio(float3 color1, float3 color2) {
    float luminance1 = luminance(color1) + 0.05;
    float luminance2 = luminance(color2) + 0.05;
    return max(luminance1, luminance2) / min(luminance1, luminance2);
}

// Return the fg if the contrast ratio is greater than min, otherwise
// return a color that satisfies the contrast ratio. Currently, the color
// is always white or black, whichever has the highest contrast ratio.
//
// Takes colors in linear RGB space. If your colors are gamma
// encoded, linearize them before using them with this function.
float4 contrasted_color(float min_ratio, float4 fg, float4 bg) {
    float ratio = contrast_ratio(fg.rgb, bg.rgb);
    if (ratio < min_ratio) {
        float white_ratio = contrast_ratio(float3(1.0, 1.0, 1.0), bg.rgb);
        float black_ratio = contrast_ratio(float3(0.0, 0.0, 0.0), bg.rgb);
        if (white_ratio > black_ratio) {
            return float4(1.0, 1.0, 1.0, 1.0);
        } else {
            return float4(0.0, 0.0, 0.0, 1.0);
        }
    }

    return fg;
}

// Converts a color from sRGB gamma encoding to linear (vec4 version).
float4 linearize4(float4 srgb) {
    bool3 cutoff = (srgb.rgb <= float3(0.04045, 0.04045, 0.04045));
    float3 higher = pow(abs((srgb.rgb + float3(0.055, 0.055, 0.055)) / float3(1.055, 1.055, 1.055)), float3(2.4, 2.4, 2.4));
    float3 lower = srgb.rgb / float3(12.92, 12.92, 12.92);

    float3 result;
    result.r = cutoff.r ? lower.r : higher.r;
    result.g = cutoff.g ? lower.g : higher.g;
    result.b = cutoff.b ? lower.b : higher.b;
    return float4(result, srgb.a);
}

// Converts a color from sRGB gamma encoding to linear (scalar version).
float linearize1(float v) {
    return v <= 0.04045 ? v / 12.92 : pow(abs((v + 0.055) / 1.055), 2.4);
}

// Converts a color from linear to sRGB gamma encoding (vec4 version).
float4 unlinearize4(float4 lin) {
    bool3 cutoff = (lin.rgb <= float3(0.0031308, 0.0031308, 0.0031308));
    float3 higher = pow(abs(lin.rgb), float3(1.0 / 2.4, 1.0 / 2.4, 1.0 / 2.4)) * float3(1.055, 1.055, 1.055) - float3(0.055, 0.055, 0.055);
    float3 lower = lin.rgb * float3(12.92, 12.92, 12.92);

    float3 result;
    result.r = cutoff.r ? lower.r : higher.r;
    result.g = cutoff.g ? lower.g : higher.g;
    result.b = cutoff.b ? lower.b : higher.b;
    return float4(result, lin.a);
}

// Converts a color from linear to sRGB gamma encoding (scalar version).
float unlinearize1(float v) {
    return v <= 0.0031308 ? v * 12.92 : pow(abs(v), 1.0 / 2.4) * 1.055 - 0.055;
}

// Load a 4 byte RGBA non-premultiplied color and linearize
// and convert it as necessary depending on the provided info.
//
// `do_linear` controls whether the returned color is linear or gamma encoded.
float4 load_color(
    uint4 in_color,
    bool do_linear
) {
    // 0 .. 255 -> 0.0 .. 1.0
    float4 color = float4(in_color) / float4(255.0f, 255.0f, 255.0f, 255.0f);

    // Linearize if necessary.
    if (do_linear) color = linearize4(color);

    // Premultiply our color by its alpha.
    color.rgb *= color.a;

    return color;
}

//----------------------------------------------------------------------------//
