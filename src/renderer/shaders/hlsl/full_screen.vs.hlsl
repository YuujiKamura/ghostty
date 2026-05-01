// UPSTREAM-SHARED-OK: fork-only file in src/renderer/shaders/hlsl/ — D3D11 shaders
struct VSInput {
    uint vertexID : SV_VertexID;
};

struct VSOutput {
    float4 position : SV_Position;
};

VSOutput vs_main(VSInput input) {
    VSOutput output;

    output.position.x = (input.vertexID == 2) ? 3.0 : -1.0;
    output.position.y = (input.vertexID == 0) ? -3.0 : 1.0;
    output.position.z = 1.0;
    output.position.w = 1.0;

    // Single triangle is clipped to viewport.
    //
    // X <- vid == 0: (-1, -3)
    // |\
    // | \
    // |  \
    // |###\
    // |#+# \ `+` is (0, 0). `#`s are viewport area.
    // |###  \
    // X------X <- vid == 2: (3, 1)
    // ^
    // vid == 1: (-1, 1)

    return output;
}
