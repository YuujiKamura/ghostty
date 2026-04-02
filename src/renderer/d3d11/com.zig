//! D3D11/DXGI COM interface definitions for Zig.
//!
//! Each interface is an extern struct whose first field is a pointer to
//! its vtable. Vtable entries use *anyopaque for the self parameter to
//! avoid circular-type issues. Convenience methods cast and forward.
//!
//! IMPORTANT: vtable slot order MUST match the Windows SDK headers exactly.
//! A single missing or misplaced slot will silently call the wrong function.
//!
//! Slot ordering references:
//!   - d3d11.h from Windows SDK
//!   - dxgi1_2.h from Windows SDK
//!   - d3dcompiler.h from Windows SDK
//!
//! Pattern follows src/font/directwrite.zig.

const std = @import("std");
const log = std.log.scoped(.d3d11);

// --- Windows base types ---
pub const BOOL = c_int;
pub const HRESULT = c_long;
pub const UINT = c_uint;
pub const UINT64 = u64;
pub const INT = c_int;
pub const LONG = c_long;
pub const FLOAT = f32;
pub const HANDLE = std.os.windows.HANDLE;
pub const HWND = std.os.windows.HANDLE;
pub const GUID = std.os.windows.GUID;
pub const LPCWSTR = [*:0]const u16;

/// Placeholder for vtable slots we don't call.
const VtblPlaceholder = *const anyopaque;

// ============================================================================
// Helper for HRESULT checking
// ============================================================================

pub const D3D11Error = error{D3D11Failed};

pub inline fn hrCheck(hr: HRESULT) D3D11Error!void {
    if (hr >= 0) return;
    log.err("D3D11 HRESULT failed: 0x{x:0>8}", .{@as(u32, @bitCast(hr))});
    return error.D3D11Failed;
}

// ============================================================================
// DXGI_FORMAT (subset)
// ============================================================================

pub const DXGI_FORMAT = enum(UINT) {
    UNKNOWN = 0,
    R8G8B8A8_UNORM = 28,
    R8G8B8A8_UNORM_SRGB = 29,
    B8G8R8A8_UNORM = 87,
    B8G8R8A8_UNORM_SRGB = 91,
    R8_UNORM = 61,
    R32G32B32A32_FLOAT = 2,
    R32G32_FLOAT = 16,
    R32G32_UINT = 17,
    R32_FLOAT = 41,
    R16G16_SINT = 38,
    R16G16_UINT = 36,
    R8G8B8A8_UINT = 30,
    R16G16B16A16_FLOAT = 10,
    R32_UINT = 42,
    R16_UINT = 57,
    R8_UINT = 62,
};

// ============================================================================
// Enums and Constants
// ============================================================================

pub const D3D_FEATURE_LEVEL = enum(UINT) {
    @"11_0" = 0xb000,
    @"11_1" = 0xb100,
};

pub const D3D_DRIVER_TYPE = enum(UINT) {
    UNKNOWN = 0,
    HARDWARE = 1,
    REFERENCE = 2,
    NULL = 3,
    SOFTWARE = 4,
    WARP = 5,
};

pub const D3D11_USAGE = enum(UINT) {
    DEFAULT = 0,
    IMMUTABLE = 1,
    DYNAMIC = 2,
    STAGING = 3,
};

pub const D3D11_BIND_FLAG = UINT;
pub const D3D11_BIND_VERTEX_BUFFER: UINT = 0x1;
pub const D3D11_BIND_INDEX_BUFFER: UINT = 0x2;
pub const D3D11_BIND_CONSTANT_BUFFER: UINT = 0x4;
pub const D3D11_BIND_SHADER_RESOURCE: UINT = 0x8;
pub const D3D11_BIND_RENDER_TARGET: UINT = 0x20;

pub const D3D11_CPU_ACCESS_FLAG = UINT;
pub const D3D11_CPU_ACCESS_WRITE: UINT = 0x10000;
pub const D3D11_CPU_ACCESS_READ: UINT = 0x20000;

pub const D3D11_MAP = enum(UINT) {
    READ = 1,
    WRITE = 2,
    READ_WRITE = 3,
    WRITE_DISCARD = 4,
    WRITE_NO_OVERWRITE = 5,
};

pub const D3D11_PRIMITIVE_TOPOLOGY = enum(UINT) {
    undefined = 0,
    point = 1,
    line = 2,
    line_strip = 3,
    triangle = 4,
    triangle_strip = 5,
};

pub const D3D11_FILTER = enum(UINT) {
    MIN_MAG_MIP_POINT = 0,
    MIN_MAG_MIP_LINEAR = 0x15,
    MIN_MAG_LINEAR_MIP_POINT = 0x14,
};

pub const D3D11_TEXTURE_ADDRESS_MODE = enum(UINT) {
    WRAP = 1,
    MIRROR = 2,
    CLAMP = 3,
    BORDER = 4,
};

pub const D3D11_BLEND = enum(UINT) {
    ZERO = 1,
    ONE = 2,
    SRC_ALPHA = 5,
    INV_SRC_ALPHA = 6,
    SRC_COLOR = 3,
    INV_SRC_COLOR = 4,
};

pub const D3D11_BLEND_OP = enum(UINT) {
    ADD = 1,
    SUBTRACT = 2,
    REV_SUBTRACT = 3,
    MIN = 4,
    MAX = 5,
};

pub const D3D11_INPUT_CLASSIFICATION = enum(UINT) {
    PER_VERTEX_DATA = 0,
    PER_INSTANCE_DATA = 1,
};

pub const D3D11_FILL_MODE = enum(UINT) {
    WIREFRAME = 2,
    SOLID = 3,
};

pub const D3D11_CULL_MODE = enum(UINT) {
    NONE = 1,
    FRONT = 2,
    BACK = 3,
};

pub const DXGI_SWAP_EFFECT = enum(UINT) {
    DISCARD = 0,
    SEQUENTIAL = 1,
    FLIP_SEQUENTIAL = 3,
    FLIP_DISCARD = 4,
};

pub const DXGI_SCALING = enum(UINT) {
    STRETCH = 0,
    NONE = 1,
    ASPECT_RATIO_STRETCH = 2,
};

pub const DXGI_ALPHA_MODE = enum(UINT) {
    UNSPECIFIED = 0,
    PREMULTIPLIED = 1,
    STRAIGHT = 2,
    IGNORE = 3,
};

pub const DXGI_PRESENT_ALLOW_TEARING: UINT = 0x00000200;

pub const D3D11_COLOR_WRITE_ENABLE_ALL: u8 = 0xf;

// ============================================================================
// Structures
// ============================================================================

pub const DXGI_SAMPLE_DESC = extern struct {
    Count: UINT = 1,
    Quality: UINT = 0,
};

pub const DXGI_MATRIX_3X2_F = extern struct {
    _11: FLOAT = 1.0,
    _12: FLOAT = 0.0,
    _21: FLOAT = 0.0,
    _22: FLOAT = 1.0,
    _31: FLOAT = 0.0,
    _32: FLOAT = 0.0,
};

pub const DXGI_SWAP_CHAIN_DESC1 = extern struct {
    Width: UINT = 0,
    Height: UINT = 0,
    Format: DXGI_FORMAT = .B8G8R8A8_UNORM,
    Stereo: BOOL = 0,
    SampleDesc: DXGI_SAMPLE_DESC = .{},
    BufferUsage: UINT = 0x20, // DXGI_USAGE_RENDER_TARGET_OUTPUT
    BufferCount: UINT = 2,
    Scaling: DXGI_SCALING = .NONE,
    SwapEffect: DXGI_SWAP_EFFECT = .FLIP_DISCARD,
    AlphaMode: DXGI_ALPHA_MODE = .UNSPECIFIED,
    Flags: UINT = 0,
};

pub const D3D11_BUFFER_DESC = extern struct {
    ByteWidth: UINT,
    Usage: D3D11_USAGE,
    BindFlags: UINT,
    CPUAccessFlags: UINT = 0,
    MiscFlags: UINT = 0,
    StructureByteStride: UINT = 0,
};

pub const D3D11_TEXTURE2D_DESC = extern struct {
    Width: UINT,
    Height: UINT,
    MipLevels: UINT = 1,
    ArraySize: UINT = 1,
    Format: DXGI_FORMAT,
    SampleDesc: DXGI_SAMPLE_DESC = .{},
    Usage: D3D11_USAGE = .DEFAULT,
    BindFlags: UINT = 0,
    CPUAccessFlags: UINT = 0,
    MiscFlags: UINT = 0,
};

pub const D3D11_SUBRESOURCE_DATA = extern struct {
    pSysMem: ?*const anyopaque = null,
    SysMemPitch: UINT = 0,
    SysMemSlicePitch: UINT = 0,
};

pub const D3D11_MAPPED_SUBRESOURCE = extern struct {
    pData: ?*anyopaque = null,
    RowPitch: UINT = 0,
    DepthPitch: UINT = 0,
};

pub const D3D11_SHADER_RESOURCE_VIEW_DESC = extern struct {
    Format: DXGI_FORMAT,
    ViewDimension: UINT, // D3D11_SRV_DIMENSION
    u: extern union {
        Texture2D: extern struct {
            MostDetailedMip: UINT,
            MipLevels: UINT,
        },
        Buffer: extern struct {
            FirstElement: UINT,
            NumElements: UINT,
        },
        raw: [2]UINT,
    },
};

pub const D3D11_RENDER_TARGET_VIEW_DESC = extern struct {
    Format: DXGI_FORMAT,
    ViewDimension: UINT, // D3D11_RTV_DIMENSION
    u: extern union {
        Texture2D: extern struct {
            MipSlice: UINT,
        },
        raw: [3]UINT,
    },
};

pub const D3D11_SAMPLER_DESC = extern struct {
    Filter: D3D11_FILTER = .MIN_MAG_MIP_LINEAR,
    AddressU: D3D11_TEXTURE_ADDRESS_MODE = .CLAMP,
    AddressV: D3D11_TEXTURE_ADDRESS_MODE = .CLAMP,
    AddressW: D3D11_TEXTURE_ADDRESS_MODE = .CLAMP,
    MipLODBias: FLOAT = 0,
    MaxAnisotropy: UINT = 1,
    ComparisonFunc: UINT = 0, // D3D11_COMPARISON_NEVER
    BorderColor: [4]FLOAT = .{ 0, 0, 0, 0 },
    MinLOD: FLOAT = 0,
    MaxLOD: FLOAT = 3.402823466e+38, // D3D11_FLOAT32_MAX
};

pub const D3D11_BLEND_DESC = extern struct {
    AlphaToCoverageEnable: BOOL = 0,
    IndependentBlendEnable: BOOL = 0,
    RenderTarget: [8]D3D11_RENDER_TARGET_BLEND_DESC = [1]D3D11_RENDER_TARGET_BLEND_DESC{.{}} ** 8,
};

pub const D3D11_RENDER_TARGET_BLEND_DESC = extern struct {
    BlendEnable: BOOL = 0,
    SrcBlend: D3D11_BLEND = .ONE,
    DestBlend: D3D11_BLEND = .ZERO,
    BlendOp: D3D11_BLEND_OP = .ADD,
    SrcBlendAlpha: D3D11_BLEND = .ONE,
    DestBlendAlpha: D3D11_BLEND = .ZERO,
    BlendOpAlpha: D3D11_BLEND_OP = .ADD,
    RenderTargetWriteMask: u8 = D3D11_COLOR_WRITE_ENABLE_ALL,
};

pub const D3D11_RASTERIZER_DESC = extern struct {
    FillMode: D3D11_FILL_MODE = .SOLID,
    CullMode: D3D11_CULL_MODE = .BACK,
    FrontCounterClockwise: BOOL = 0,
    DepthBias: INT = 0,
    DepthBiasClamp: FLOAT = 0,
    SlopeScaledDepthBias: FLOAT = 0,
    DepthClipEnable: BOOL = 1,
    ScissorEnable: BOOL = 0,
    MultisampleEnable: BOOL = 0,
    AntialiasedLineEnable: BOOL = 0,
};

pub const D3D11_INPUT_ELEMENT_DESC = extern struct {
    SemanticName: [*:0]const u8,
    SemanticIndex: UINT,
    Format: DXGI_FORMAT,
    InputSlot: UINT = 0,
    AlignedByteOffset: UINT,
    InputSlotClass: D3D11_INPUT_CLASSIFICATION,
    InstanceDataStepRate: UINT = 0,
};

pub const D3D11_VIEWPORT = extern struct {
    TopLeftX: FLOAT = 0,
    TopLeftY: FLOAT = 0,
    Width: FLOAT,
    Height: FLOAT,
    MinDepth: FLOAT = 0,
    MaxDepth: FLOAT = 1,
};

pub const D3D11_BOX = extern struct {
    left: UINT,
    top: UINT,
    front: UINT,
    right: UINT,
    bottom: UINT,
    back: UINT,
};

// ============================================================================
// COM Interfaces
// ============================================================================

// --- IUnknown base (slots 0-2) ---
// All COM interfaces inherit from IUnknown.

// --- ID3D11Device ---
// Inherits: IUnknown (slots 0-2)
// d3d11.h: ID3D11Device methods start at slot 3
pub const ID3D11Device = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: VtblPlaceholder, // 0
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32, // 1
        Release: *const fn (*anyopaque) callconv(.winapi) u32, // 2

        // ID3D11Device (slots 3-42)
        CreateBuffer: *const fn (*anyopaque, *const D3D11_BUFFER_DESC, ?*const D3D11_SUBRESOURCE_DATA, *?*ID3D11Buffer) callconv(.winapi) HRESULT, // 3
        CreateTexture1D: VtblPlaceholder, // 4
        CreateTexture2D: *const fn (*anyopaque, *const D3D11_TEXTURE2D_DESC, ?*const D3D11_SUBRESOURCE_DATA, *?*ID3D11Texture2D) callconv(.winapi) HRESULT, // 5
        CreateTexture3D: VtblPlaceholder, // 6
        CreateShaderResourceView: *const fn (*anyopaque, *anyopaque, ?*const D3D11_SHADER_RESOURCE_VIEW_DESC, *?*ID3D11ShaderResourceView) callconv(.winapi) HRESULT, // 7
        CreateUnorderedAccessView: VtblPlaceholder, // 8
        CreateRenderTargetView: *const fn (*anyopaque, *anyopaque, ?*const D3D11_RENDER_TARGET_VIEW_DESC, *?*ID3D11RenderTargetView) callconv(.winapi) HRESULT, // 9
        CreateDepthStencilView: VtblPlaceholder, // 10
        CreateInputLayout: *const fn (*anyopaque, [*]const D3D11_INPUT_ELEMENT_DESC, UINT, ?*const anyopaque, usize, *?*ID3D11InputLayout) callconv(.winapi) HRESULT, // 11
        CreateVertexShader: *const fn (*anyopaque, ?*const anyopaque, usize, ?*anyopaque, *?*ID3D11VertexShader) callconv(.winapi) HRESULT, // 12
        CreateGeometryShader: VtblPlaceholder, // 13
        CreateGeometryShaderWithStreamOutput: VtblPlaceholder, // 14
        CreatePixelShader: *const fn (*anyopaque, ?*const anyopaque, usize, ?*anyopaque, *?*ID3D11PixelShader) callconv(.winapi) HRESULT, // 15
        CreateHullShader: VtblPlaceholder, // 16
        CreateDomainShader: VtblPlaceholder, // 17
        CreateComputeShader: VtblPlaceholder, // 18
        CreateClassLinkage: VtblPlaceholder, // 19
        CreateBlendState: *const fn (*anyopaque, *const D3D11_BLEND_DESC, *?*ID3D11BlendState) callconv(.winapi) HRESULT, // 20
        CreateDepthStencilState: VtblPlaceholder, // 21
        CreateRasterizerState: *const fn (*anyopaque, *const D3D11_RASTERIZER_DESC, *?*ID3D11RasterizerState) callconv(.winapi) HRESULT, // 22
        CreateSamplerState: *const fn (*anyopaque, *const D3D11_SAMPLER_DESC, *?*ID3D11SamplerState) callconv(.winapi) HRESULT, // 23
        CreateQuery: VtblPlaceholder, // 24
        CreatePredicate: VtblPlaceholder, // 25
        CreateCounter: VtblPlaceholder, // 26
        CreateDeferredContext: VtblPlaceholder, // 27
        OpenSharedResource: VtblPlaceholder, // 28
        CheckFormatSupport: VtblPlaceholder, // 29
        CheckMultisampleQualityLevels: VtblPlaceholder, // 30
        CheckCounterInfo: VtblPlaceholder, // 31
        CheckCounter: VtblPlaceholder, // 32
        CheckFeatureSupport: VtblPlaceholder, // 33
        GetPrivateData: VtblPlaceholder, // 34
        SetPrivateData: VtblPlaceholder, // 35
        SetPrivateDataInterface: VtblPlaceholder, // 36
        GetFeatureLevel: VtblPlaceholder, // 37
        GetCreationFlags: VtblPlaceholder, // 38
        GetDeviceRemovedReason: VtblPlaceholder, // 39
        GetImmediateContext: VtblPlaceholder, // 40
        SetExceptionMode: VtblPlaceholder, // 41
        GetExceptionMode: VtblPlaceholder, // 42
    };

    pub fn release(self: *ID3D11Device) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    pub fn createBuffer(self: *ID3D11Device, desc: *const D3D11_BUFFER_DESC, init_data: ?*const D3D11_SUBRESOURCE_DATA) D3D11Error!*ID3D11Buffer {
        var buf: ?*ID3D11Buffer = null;
        try hrCheck(self.lpVtbl.CreateBuffer(@ptrCast(self), desc, init_data, &buf));
        return buf orelse error.D3D11Failed;
    }

    pub fn createTexture2D(self: *ID3D11Device, desc: *const D3D11_TEXTURE2D_DESC, init_data: ?*const D3D11_SUBRESOURCE_DATA) D3D11Error!*ID3D11Texture2D {
        var tex: ?*ID3D11Texture2D = null;
        try hrCheck(self.lpVtbl.CreateTexture2D(@ptrCast(self), desc, init_data, &tex));
        return tex orelse error.D3D11Failed;
    }

    pub fn createShaderResourceView(self: *ID3D11Device, resource: *anyopaque, desc: ?*const D3D11_SHADER_RESOURCE_VIEW_DESC) D3D11Error!*ID3D11ShaderResourceView {
        var srv: ?*ID3D11ShaderResourceView = null;
        try hrCheck(self.lpVtbl.CreateShaderResourceView(@ptrCast(self), resource, desc, &srv));
        return srv orelse error.D3D11Failed;
    }

    pub fn createRenderTargetView(self: *ID3D11Device, resource: *anyopaque, desc: ?*const D3D11_RENDER_TARGET_VIEW_DESC) D3D11Error!*ID3D11RenderTargetView {
        var rtv: ?*ID3D11RenderTargetView = null;
        try hrCheck(self.lpVtbl.CreateRenderTargetView(@ptrCast(self), resource, desc, &rtv));
        return rtv orelse error.D3D11Failed;
    }

    pub fn createInputLayout(self: *ID3D11Device, descs: []const D3D11_INPUT_ELEMENT_DESC, bytecode: []const u8) D3D11Error!*ID3D11InputLayout {
        var layout: ?*ID3D11InputLayout = null;
        try hrCheck(self.lpVtbl.CreateInputLayout(@ptrCast(self), descs.ptr, @intCast(descs.len), @ptrCast(bytecode.ptr), bytecode.len, &layout));
        return layout orelse error.D3D11Failed;
    }

    pub fn createInputLayoutFromBytecode(self: *ID3D11Device, descs: []const D3D11_INPUT_ELEMENT_DESC, bytecode_ptr: *const anyopaque, bytecode_len: usize) D3D11Error!*ID3D11InputLayout {
        var layout: ?*ID3D11InputLayout = null;
        try hrCheck(self.lpVtbl.CreateInputLayout(@ptrCast(self), descs.ptr, @intCast(descs.len), bytecode_ptr, bytecode_len, &layout));
        return layout orelse error.D3D11Failed;
    }

    pub fn createVertexShader(self: *ID3D11Device, bytecode: []const u8) D3D11Error!*ID3D11VertexShader {
        var vs: ?*ID3D11VertexShader = null;
        try hrCheck(self.lpVtbl.CreateVertexShader(@ptrCast(self), @ptrCast(bytecode.ptr), bytecode.len, null, &vs));
        return vs orelse error.D3D11Failed;
    }

    pub fn createPixelShader(self: *ID3D11Device, bytecode: []const u8) D3D11Error!*ID3D11PixelShader {
        var ps: ?*ID3D11PixelShader = null;
        try hrCheck(self.lpVtbl.CreatePixelShader(@ptrCast(self), @ptrCast(bytecode.ptr), bytecode.len, null, &ps));
        return ps orelse error.D3D11Failed;
    }

    pub fn createBlendState(self: *ID3D11Device, desc: *const D3D11_BLEND_DESC) D3D11Error!*ID3D11BlendState {
        var state: ?*ID3D11BlendState = null;
        try hrCheck(self.lpVtbl.CreateBlendState(@ptrCast(self), desc, &state));
        return state orelse error.D3D11Failed;
    }

    pub fn createRasterizerState(self: *ID3D11Device, desc: *const D3D11_RASTERIZER_DESC) D3D11Error!*ID3D11RasterizerState {
        var state: ?*ID3D11RasterizerState = null;
        try hrCheck(self.lpVtbl.CreateRasterizerState(@ptrCast(self), desc, &state));
        return state orelse error.D3D11Failed;
    }

    pub fn createSamplerState(self: *ID3D11Device, desc: *const D3D11_SAMPLER_DESC) D3D11Error!*ID3D11SamplerState {
        var state: ?*ID3D11SamplerState = null;
        try hrCheck(self.lpVtbl.CreateSamplerState(@ptrCast(self), desc, &state));
        return state orelse error.D3D11Failed;
    }
};

// --- ID3D11DeviceContext ---
// Inherits: ID3D11DeviceChild (slots 0-6) -> IUnknown (slots 0-2)
// d3d11.h: ID3D11DeviceContext methods start at slot 7
pub const ID3D11DeviceContext = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT, // 0
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32, // 1
        Release: *const fn (*anyopaque) callconv(.winapi) u32, // 2

        // ID3D11DeviceChild (slots 3-6)
        GetDevice: VtblPlaceholder, // 3
        GetPrivateData: VtblPlaceholder, // 4
        SetPrivateData: VtblPlaceholder, // 5
        SetPrivateDataInterface: VtblPlaceholder, // 6

        // ID3D11DeviceContext (slots 7-115)
        VSSetConstantBuffers: *const fn (*anyopaque, UINT, UINT, [*]const ?*ID3D11Buffer) callconv(.winapi) void, // 7
        PSSetShaderResources: *const fn (*anyopaque, UINT, UINT, [*]const ?*ID3D11ShaderResourceView) callconv(.winapi) void, // 8
        PSSetShader: *const fn (*anyopaque, ?*ID3D11PixelShader, ?*?*anyopaque, UINT) callconv(.winapi) void, // 9
        PSSetSamplers: *const fn (*anyopaque, UINT, UINT, [*]const ?*ID3D11SamplerState) callconv(.winapi) void, // 10
        VSSetShader: *const fn (*anyopaque, ?*ID3D11VertexShader, ?*?*anyopaque, UINT) callconv(.winapi) void, // 11
        DrawIndexed: VtblPlaceholder, // 12
        Draw: *const fn (*anyopaque, UINT, UINT) callconv(.winapi) void, // 13
        Map: *const fn (*anyopaque, *anyopaque, UINT, D3D11_MAP, UINT, *D3D11_MAPPED_SUBRESOURCE) callconv(.winapi) HRESULT, // 14
        Unmap: *const fn (*anyopaque, *anyopaque, UINT) callconv(.winapi) void, // 15
        PSSetConstantBuffers: *const fn (*anyopaque, UINT, UINT, [*]const ?*ID3D11Buffer) callconv(.winapi) void, // 16
        IASetInputLayout: *const fn (*anyopaque, ?*ID3D11InputLayout) callconv(.winapi) void, // 17
        IASetVertexBuffers: *const fn (*anyopaque, UINT, UINT, [*]const ?*ID3D11Buffer, [*]const UINT, [*]const UINT) callconv(.winapi) void, // 18
        IASetIndexBuffer: VtblPlaceholder, // 19
        DrawIndexedInstanced: VtblPlaceholder, // 20
        DrawInstanced: *const fn (*anyopaque, UINT, UINT, UINT, UINT) callconv(.winapi) void, // 21
        GSSetConstantBuffers: VtblPlaceholder, // 22
        GSSetShader: VtblPlaceholder, // 23
        IASetPrimitiveTopology: *const fn (*anyopaque, D3D11_PRIMITIVE_TOPOLOGY) callconv(.winapi) void, // 24
        VSSetShaderResources: *const fn (*anyopaque, UINT, UINT, [*]const ?*ID3D11ShaderResourceView) callconv(.winapi) void, // 25
        VSSetSamplers: VtblPlaceholder, // 26
        Begin: VtblPlaceholder, // 27
        End: VtblPlaceholder, // 28
        GetData: VtblPlaceholder, // 29
        SetPredication: VtblPlaceholder, // 30
        GSSetShaderResources: VtblPlaceholder, // 31
        GSSetSamplers: VtblPlaceholder, // 32
        OMSetRenderTargets: *const fn (*anyopaque, UINT, [*]const ?*ID3D11RenderTargetView, ?*anyopaque) callconv(.winapi) void, // 33
        OMSetRenderTargetsAndUnorderedAccessViews: VtblPlaceholder, // 34
        OMSetBlendState: *const fn (*anyopaque, ?*ID3D11BlendState, ?*const [4]FLOAT, UINT) callconv(.winapi) void, // 35
        OMSetDepthStencilState: VtblPlaceholder, // 36
        SOSetTargets: VtblPlaceholder, // 37
        DrawAuto: VtblPlaceholder, // 38
        DrawIndexedInstancedIndirect: VtblPlaceholder, // 39
        DrawInstancedIndirect: VtblPlaceholder, // 40
        Dispatch: VtblPlaceholder, // 41
        DispatchIndirect: VtblPlaceholder, // 42
        RSSetState: *const fn (*anyopaque, ?*ID3D11RasterizerState) callconv(.winapi) void, // 43
        RSSetViewports: *const fn (*anyopaque, UINT, [*]const D3D11_VIEWPORT) callconv(.winapi) void, // 44
        RSSetScissorRects: VtblPlaceholder, // 45
        CopySubresourceRegion: *const fn (*anyopaque, *anyopaque, UINT, UINT, UINT, UINT, *anyopaque, UINT, ?*const D3D11_BOX) callconv(.winapi) void, // 46
        CopyResource: *const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.winapi) void, // 47
        UpdateSubresource: *const fn (*anyopaque, *anyopaque, UINT, ?*const D3D11_BOX, *const anyopaque, UINT, UINT) callconv(.winapi) void, // 48
        CopyStructureCount: VtblPlaceholder, // 49
        ClearRenderTargetView: *const fn (*anyopaque, *ID3D11RenderTargetView, *const [4]FLOAT) callconv(.winapi) void, // 50
        ClearUnorderedAccessViewUint: VtblPlaceholder, // 51
        ClearUnorderedAccessViewFloat: VtblPlaceholder, // 52
        ClearDepthStencilView: VtblPlaceholder, // 53
        GenerateMips: VtblPlaceholder, // 54
        SetResourceMinLOD: VtblPlaceholder, // 55
        GetResourceMinLOD: VtblPlaceholder, // 56
        ResolveSubresource: VtblPlaceholder, // 57
        ExecuteCommandList: VtblPlaceholder, // 58
        HSSetShaderResources: VtblPlaceholder, // 59
        HSSetShader: VtblPlaceholder, // 60
        HSSetSamplers: VtblPlaceholder, // 61
        HSSetConstantBuffers: VtblPlaceholder, // 62
        DSSetShaderResources: VtblPlaceholder, // 63
        DSSetShader: VtblPlaceholder, // 64
        DSSetSamplers: VtblPlaceholder, // 65
        DSSetConstantBuffers: VtblPlaceholder, // 66
        CSSetShaderResources: VtblPlaceholder, // 67
        CSSetUnorderedAccessViews: VtblPlaceholder, // 68
        CSSetShader: VtblPlaceholder, // 69
        CSSetSamplers: VtblPlaceholder, // 70
        CSSetConstantBuffers: VtblPlaceholder, // 71
        VSGetConstantBuffers: VtblPlaceholder, // 72
        PSGetShaderResources: VtblPlaceholder, // 73
        PSGetShader: VtblPlaceholder, // 74
        PSGetSamplers: VtblPlaceholder, // 75
        VSGetShader: VtblPlaceholder, // 76
        PSGetConstantBuffers: VtblPlaceholder, // 77
        IAGetInputLayout: VtblPlaceholder, // 78
        IAGetVertexBuffers: VtblPlaceholder, // 79
        IAGetIndexBuffer: VtblPlaceholder, // 80
        GSGetConstantBuffers: VtblPlaceholder, // 81
        GSGetShader: VtblPlaceholder, // 82
        IAGetPrimitiveTopology: VtblPlaceholder, // 83
        VSGetShaderResources: VtblPlaceholder, // 84
        VSGetSamplers: VtblPlaceholder, // 85
        GetPredication: VtblPlaceholder, // 86
        GSGetShaderResources: VtblPlaceholder, // 87
        GSGetSamplers: VtblPlaceholder, // 88
        OMGetRenderTargets: VtblPlaceholder, // 89
        OMGetRenderTargetsAndUnorderedAccessViews: VtblPlaceholder, // 90
        OMGetBlendState: VtblPlaceholder, // 91
        OMGetDepthStencilState: VtblPlaceholder, // 92
        SOGetTargets: VtblPlaceholder, // 93
        RSGetState: VtblPlaceholder, // 94
        RSGetViewports: VtblPlaceholder, // 95
        RSGetScissorRects: VtblPlaceholder, // 96
        HSGetShaderResources: VtblPlaceholder, // 97
        HSGetShader: VtblPlaceholder, // 98
        HSGetSamplers: VtblPlaceholder, // 99
        HSGetConstantBuffers: VtblPlaceholder, // 100
        DSGetShaderResources: VtblPlaceholder, // 101
        DSGetShader: VtblPlaceholder, // 102
        DSGetSamplers: VtblPlaceholder, // 103
        DSGetConstantBuffers: VtblPlaceholder, // 104
        CSGetShaderResources: VtblPlaceholder, // 105
        CSGetUnorderedAccessViews: VtblPlaceholder, // 106
        CSGetShader: VtblPlaceholder, // 107
        CSGetSamplers: VtblPlaceholder, // 108
        CSGetConstantBuffers: VtblPlaceholder, // 109
        ClearState: *const fn (*anyopaque) callconv(.winapi) void, // 110
        Flush: *const fn (*anyopaque) callconv(.winapi) void, // 111
        GetType: VtblPlaceholder, // 112
        GetContextFlags: VtblPlaceholder, // 113
        FinishCommandList: VtblPlaceholder, // 114
    };

    pub fn release(self: *ID3D11DeviceContext) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    pub fn vsSetConstantBuffers(self: *ID3D11DeviceContext, start: UINT, buffers: []const ?*ID3D11Buffer) void {
        self.lpVtbl.VSSetConstantBuffers(@ptrCast(self), start, @intCast(buffers.len), buffers.ptr);
    }

    pub fn psSetConstantBuffers(self: *ID3D11DeviceContext, start: UINT, buffers: []const ?*ID3D11Buffer) void {
        self.lpVtbl.PSSetConstantBuffers(@ptrCast(self), start, @intCast(buffers.len), buffers.ptr);
    }

    pub fn psSetShaderResources(self: *ID3D11DeviceContext, start: UINT, views: []const ?*ID3D11ShaderResourceView) void {
        self.lpVtbl.PSSetShaderResources(@ptrCast(self), start, @intCast(views.len), views.ptr);
    }

    pub fn vsSetShaderResources(self: *ID3D11DeviceContext, start: UINT, views: []const ?*ID3D11ShaderResourceView) void {
        self.lpVtbl.VSSetShaderResources(@ptrCast(self), start, @intCast(views.len), views.ptr);
    }

    pub fn psSetShader(self: *ID3D11DeviceContext, shader: ?*ID3D11PixelShader) void {
        self.lpVtbl.PSSetShader(@ptrCast(self), shader, null, 0);
    }

    pub fn vsSetShader(self: *ID3D11DeviceContext, shader: ?*ID3D11VertexShader) void {
        self.lpVtbl.VSSetShader(@ptrCast(self), shader, null, 0);
    }

    pub fn psSetSamplers(self: *ID3D11DeviceContext, start: UINT, samplers: []const ?*ID3D11SamplerState) void {
        self.lpVtbl.PSSetSamplers(@ptrCast(self), start, @intCast(samplers.len), samplers.ptr);
    }

    pub fn draw(self: *ID3D11DeviceContext, vertex_count: UINT, start_vertex: UINT) void {
        self.lpVtbl.Draw(@ptrCast(self), vertex_count, start_vertex);
    }

    pub fn drawInstanced(self: *ID3D11DeviceContext, vertex_count: UINT, instance_count: UINT, start_vertex: UINT, start_instance: UINT) void {
        self.lpVtbl.DrawInstanced(@ptrCast(self), vertex_count, instance_count, start_vertex, start_instance);
    }

    pub fn map(self: *ID3D11DeviceContext, resource: *anyopaque, subresource: UINT, map_type: D3D11_MAP, flags: UINT) D3D11Error!D3D11_MAPPED_SUBRESOURCE {
        var mapped: D3D11_MAPPED_SUBRESOURCE = .{};
        try hrCheck(self.lpVtbl.Map(@ptrCast(self), resource, subresource, map_type, flags, &mapped));
        return mapped;
    }

    pub fn unmap(self: *ID3D11DeviceContext, resource: *anyopaque, subresource: UINT) void {
        self.lpVtbl.Unmap(@ptrCast(self), resource, subresource);
    }

    pub fn iaSetInputLayout(self: *ID3D11DeviceContext, layout: ?*ID3D11InputLayout) void {
        self.lpVtbl.IASetInputLayout(@ptrCast(self), layout);
    }

    pub fn iaSetVertexBuffers(self: *ID3D11DeviceContext, start_slot: UINT, buffers: []const ?*ID3D11Buffer, strides: []const UINT, offsets: []const UINT) void {
        self.lpVtbl.IASetVertexBuffers(@ptrCast(self), start_slot, @intCast(buffers.len), buffers.ptr, strides.ptr, offsets.ptr);
    }

    pub fn iaSetPrimitiveTopology(self: *ID3D11DeviceContext, topology: D3D11_PRIMITIVE_TOPOLOGY) void {
        self.lpVtbl.IASetPrimitiveTopology(@ptrCast(self), topology);
    }

    pub fn omSetRenderTargets(self: *ID3D11DeviceContext, views: []const ?*ID3D11RenderTargetView, dsv: ?*anyopaque) void {
        self.lpVtbl.OMSetRenderTargets(@ptrCast(self), @intCast(views.len), views.ptr, dsv);
    }

    pub fn omSetBlendState(self: *ID3D11DeviceContext, state: ?*ID3D11BlendState, blend_factor: ?*const [4]FLOAT, sample_mask: UINT) void {
        self.lpVtbl.OMSetBlendState(@ptrCast(self), state, blend_factor, sample_mask);
    }

    pub fn rsSetState(self: *ID3D11DeviceContext, state: ?*ID3D11RasterizerState) void {
        self.lpVtbl.RSSetState(@ptrCast(self), state);
    }

    pub fn rsSetViewports(self: *ID3D11DeviceContext, viewports: []const D3D11_VIEWPORT) void {
        self.lpVtbl.RSSetViewports(@ptrCast(self), @intCast(viewports.len), viewports.ptr);
    }

    pub fn copySubresourceRegion(self: *ID3D11DeviceContext, dst: *anyopaque, dst_subresource: UINT, dst_x: UINT, dst_y: UINT, dst_z: UINT, src: *anyopaque, src_subresource: UINT, src_box: ?*const D3D11_BOX) void {
        self.lpVtbl.CopySubresourceRegion(@ptrCast(self), dst, dst_subresource, dst_x, dst_y, dst_z, src, src_subresource, src_box);
    }

    pub fn copyResource(self: *ID3D11DeviceContext, dst: *anyopaque, src: *anyopaque) void {
        self.lpVtbl.CopyResource(@ptrCast(self), dst, src);
    }

    pub fn updateSubresource(self: *ID3D11DeviceContext, resource: *anyopaque, subresource: UINT, box: ?*const D3D11_BOX, data: *const anyopaque, row_pitch: UINT, depth_pitch: UINT) void {
        self.lpVtbl.UpdateSubresource(@ptrCast(self), resource, subresource, box, data, row_pitch, depth_pitch);
    }

    pub fn clearRenderTargetView(self: *ID3D11DeviceContext, rtv: *ID3D11RenderTargetView, color: *const [4]FLOAT) void {
        self.lpVtbl.ClearRenderTargetView(@ptrCast(self), rtv, color);
    }

    pub fn clearState(self: *ID3D11DeviceContext) void {
        self.lpVtbl.ClearState(@ptrCast(self));
    }

    pub fn flush(self: *ID3D11DeviceContext) void {
        self.lpVtbl.Flush(@ptrCast(self));
    }
};

pub const IDXGISwapChain = extern struct {
    pub const IID = GUID{
        .Data1 = 0x310d36a0,
        .Data2 = 0xd2e7,
        .Data3 = 0x4c0a,
        .Data4 = .{ 0xaa, 0x04, 0x6a, 0x9d, 0x23, 0xb8, 0x88, 0x6a },
    };

    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT, // 0
        AddRef: VtblPlaceholder, // 1
        Release: *const fn (*anyopaque) callconv(.winapi) u32, // 2
    };

    pub fn release(self: *IDXGISwapChain) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// --- IDXGISwapChain1 ---
// Inherits: IDXGISwapChain (slots 0-17) -> IDXGIDeviceSubObject -> IDXGIObject -> IUnknown
// dxgi1_2.h
pub const IDXGISwapChain1 = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT, // 0
        AddRef: VtblPlaceholder, // 1
        Release: *const fn (*anyopaque) callconv(.winapi) u32, // 2

        // IDXGIObject (slots 3-6)
        SetPrivateData: VtblPlaceholder, // 3
        SetPrivateDataInterface: VtblPlaceholder, // 4
        GetPrivateData: VtblPlaceholder, // 5
        GetParent: VtblPlaceholder, // 6

        // IDXGIDeviceSubObject (slot 7)
        GetDevice: VtblPlaceholder, // 7

        // IDXGISwapChain (slots 8-17)
        Present: *const fn (*anyopaque, UINT, UINT) callconv(.winapi) HRESULT, // 8
        GetBuffer: *const fn (*anyopaque, UINT, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT, // 9
        SetFullscreenState: VtblPlaceholder, // 10
        GetFullscreenState: VtblPlaceholder, // 11
        GetDesc: VtblPlaceholder, // 12
        ResizeBuffers: *const fn (*anyopaque, UINT, UINT, UINT, DXGI_FORMAT, UINT) callconv(.winapi) HRESULT, // 13
        ResizeTarget: VtblPlaceholder, // 14
        GetContainingOutput: VtblPlaceholder, // 15
        GetFrameStatistics: VtblPlaceholder, // 16
        GetLastPresentCount: VtblPlaceholder, // 17

        // IDXGISwapChain1 (slots 18-28)
        GetDesc1: VtblPlaceholder, // 18
        GetFullscreenDesc: VtblPlaceholder, // 19
        GetHwnd: VtblPlaceholder, // 20
        GetCoreWindow: VtblPlaceholder, // 21
        Present1: VtblPlaceholder, // 22
        IsTemporaryMonoSupported: VtblPlaceholder, // 23
        GetRestrictToOutput: VtblPlaceholder, // 24
        SetBackgroundColor: VtblPlaceholder, // 25
        GetBackgroundColor: VtblPlaceholder, // 26
        SetRotation: VtblPlaceholder, // 27
        GetRotation: VtblPlaceholder, // 28

        // IDXGISwapChain2 (slots 29-33)
        SetSourceSize: VtblPlaceholder, // 29
        GetSourceSize: VtblPlaceholder, // 30
        SetMaximumFrameLatency: VtblPlaceholder, // 31
        GetMaximumFrameLatency: VtblPlaceholder, // 32
        GetFrameLatencyWaitableObject: VtblPlaceholder, // 33
        SetMatrixTransform: *const fn (*anyopaque, *const DXGI_MATRIX_3X2_F) callconv(.winapi) HRESULT, // 34
        GetMatrixTransform: VtblPlaceholder, // 35
    };

    pub fn release(self: *IDXGISwapChain1) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    pub fn present(self: *IDXGISwapChain1, sync_interval: UINT, flags: UINT) HRESULT {
        return self.lpVtbl.Present(@ptrCast(self), sync_interval, flags);
    }

    pub fn getBuffer(self: *IDXGISwapChain1, comptime T: type, buffer_index: UINT) D3D11Error!*T {
        var buf: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.GetBuffer(@ptrCast(self), buffer_index, &ID3D11Texture2D.IID, &buf));
        return @ptrCast(@alignCast(buf orelse return error.D3D11Failed));
    }

    pub fn resizeBuffers(self: *IDXGISwapChain1, count: UINT, width: UINT, height: UINT, format: DXGI_FORMAT, flags: UINT) D3D11Error!void {
        try hrCheck(self.lpVtbl.ResizeBuffers(@ptrCast(self), count, width, height, format, flags));
    }

    pub fn queryInterface(self: *IDXGISwapChain1, comptime T: type) D3D11Error!*T {
        var result: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.QueryInterface(@ptrCast(self), &T.IID, &result));
        return @ptrCast(@alignCast(result orelse return error.D3D11Failed));
    }

    /// Set inverse-DPI-scale transform so physical pixels map correctly to DIP-sized SwapChainPanel.
    pub fn setMatrixTransform(self: *IDXGISwapChain1, matrix: *const DXGI_MATRIX_3X2_F) D3D11Error!void {
        try hrCheck(self.lpVtbl.SetMatrixTransform(@ptrCast(self), matrix));
    }
};

// --- IDXGIFactory2 ---
// Inherits: IDXGIFactory1 (slots 0-14) -> IDXGIFactory -> IDXGIObject -> IUnknown
// dxgi1_2.h
pub const IDXGIFactory2 = extern struct {
    pub const IID = GUID{
        .Data1 = 0x50c83a1c,
        .Data2 = 0xe072,
        .Data3 = 0x4c48,
        .Data4 = .{ 0x87, 0xb0, 0x36, 0x30, 0xfa, 0x36, 0xa6, 0xd0 },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT, // 0
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32, // 1
        Release: *const fn (*anyopaque) callconv(.winapi) u32, // 2

        // IDXGIObject (slots 3-6)
        SetPrivateData: VtblPlaceholder, // 3
        SetPrivateDataInterface: VtblPlaceholder, // 4
        GetPrivateData: VtblPlaceholder, // 5
        GetParent: VtblPlaceholder, // 6

        // IDXGIFactory (slots 7-10)
        EnumAdapters: VtblPlaceholder, // 7
        MakeWindowAssociation: VtblPlaceholder, // 8
        GetWindowAssociation: VtblPlaceholder, // 9
        CreateSwapChain: VtblPlaceholder, // 10
        CreateSoftwareAdapter: VtblPlaceholder, // 11

        // IDXGIFactory1 (slots 12-13)
        EnumAdapters1: VtblPlaceholder, // 12
        IsCurrent: VtblPlaceholder, // 13

        // IDXGIFactory2 (slots 14-24)
        IsWindowedStereoEnabled: VtblPlaceholder, // 14
        CreateSwapChainForHwnd: *const fn (*anyopaque, *anyopaque, HWND, *const DXGI_SWAP_CHAIN_DESC1, ?*const anyopaque, ?*anyopaque, *?*IDXGISwapChain1) callconv(.winapi) HRESULT, // 15
        CreateSwapChainForCoreWindow: VtblPlaceholder, // 16
        GetSharedResourceAdapterLuid: VtblPlaceholder, // 17
        RegisterStereoStatusWindow: VtblPlaceholder, // 18
        RegisterStereoStatusEvent: VtblPlaceholder, // 19
        UnregisterStereoStatus: VtblPlaceholder, // 20
        RegisterOcclusionStatusWindow: VtblPlaceholder, // 21
        RegisterOcclusionStatusEvent: VtblPlaceholder, // 22
        UnregisterOcclusionStatus: VtblPlaceholder, // 23
        CreateSwapChainForComposition: *const fn (*anyopaque, *anyopaque, *const DXGI_SWAP_CHAIN_DESC1, ?*anyopaque, *?*IDXGISwapChain1) callconv(.winapi) HRESULT, // 24
    };

    pub fn release(self: *IDXGIFactory2) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    pub fn createSwapChainForHwnd(
        self: *IDXGIFactory2,
        device: *anyopaque,
        hwnd: HWND,
        desc: *const DXGI_SWAP_CHAIN_DESC1,
    ) D3D11Error!*IDXGISwapChain1 {
        var sc: ?*IDXGISwapChain1 = null;
        try hrCheck(self.lpVtbl.CreateSwapChainForHwnd(@ptrCast(self), device, hwnd, desc, null, null, &sc));
        return sc orelse error.D3D11Failed;
    }

    pub fn createSwapChainForComposition(
        self: *IDXGIFactory2,
        device: *anyopaque,
        desc: *const DXGI_SWAP_CHAIN_DESC1,
    ) D3D11Error!*IDXGISwapChain1 {
        var sc: ?*IDXGISwapChain1 = null;
        try hrCheck(self.lpVtbl.CreateSwapChainForComposition(@ptrCast(self), device, desc, null, &sc));
        return sc orelse error.D3D11Failed;
    }

    pub fn queryInterface(self: *IDXGIFactory2, comptime T: type) D3D11Error!*T {
        var result: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.QueryInterface(@ptrCast(self), &T.IID, &result));
        return @ptrCast(@alignCast(result orelse return error.D3D11Failed));
    }
};

// --- IDXGIFactoryMedia ---
// dxgi1_3.h
pub const IDXGIFactoryMedia = extern struct {
    pub const IID = GUID{
        .Data1 = 0x41e7d1f2,
        .Data2 = 0xa591,
        .Data3 = 0x4f7b,
        .Data4 = .{ 0xa2, 0xe5, 0xfa, 0x9c, 0x84, 0x3e, 0x1c, 0x12 },
    };

    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        CreateSwapChainForCompositionSurfaceHandle: *const fn (*anyopaque, *anyopaque, HANDLE, *const DXGI_SWAP_CHAIN_DESC1, ?*anyopaque, *?*IDXGISwapChain1) callconv(.winapi) HRESULT,
        CreateDecodeSwapChainForCompositionSurfaceHandle: VtblPlaceholder,
    };

    pub fn release(self: *IDXGIFactoryMedia) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    pub fn createSwapChainForCompositionSurfaceHandle(
        self: *IDXGIFactoryMedia,
        device: *anyopaque,
        surface_handle: HANDLE,
        desc: *const DXGI_SWAP_CHAIN_DESC1,
    ) D3D11Error!*IDXGISwapChain1 {
        var sc: ?*IDXGISwapChain1 = null;
        try hrCheck(self.lpVtbl.CreateSwapChainForCompositionSurfaceHandle(@ptrCast(self), device, surface_handle, desc, null, &sc));
        return sc orelse error.D3D11Failed;
    }
};

// --- Opaque COM objects (only need Release) ---

pub const ID3D11Buffer = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *ID3D11Buffer) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

pub const ID3D11Texture2D = extern struct {
    pub const IID = GUID{
        .Data1 = 0x6f15aaf2,
        .Data2 = 0xd208,
        .Data3 = 0x4e89,
        .Data4 = .{ 0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c },
    };

    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *ID3D11Texture2D) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

pub const ID3D11ShaderResourceView = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *ID3D11ShaderResourceView) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

pub const ID3D11RenderTargetView = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *ID3D11RenderTargetView) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

pub const ID3D11VertexShader = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *ID3D11VertexShader) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

pub const ID3D11PixelShader = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *ID3D11PixelShader) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

pub const ID3D11InputLayout = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *ID3D11InputLayout) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

pub const ID3D11SamplerState = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *ID3D11SamplerState) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

pub const ID3D11BlendState = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *ID3D11BlendState) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

pub const ID3D11RasterizerState = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *ID3D11RasterizerState) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// --- ID3DBlob ---
// Used for shader compilation output.
pub const ID3DBlob = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // ID3DBlob (slots 3-4)
        GetBufferPointer: *const fn (*anyopaque) callconv(.winapi) ?*anyopaque,
        GetBufferSize: *const fn (*anyopaque) callconv(.winapi) usize,
    };
    pub fn release(self: *ID3DBlob) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
    pub fn getBufferPointer(self: *ID3DBlob) ?*anyopaque {
        return self.lpVtbl.GetBufferPointer(@ptrCast(self));
    }
    pub fn getBufferSize(self: *ID3DBlob) usize {
        return self.lpVtbl.GetBufferSize(@ptrCast(self));
    }
};

// ============================================================================
// GUIDs
// ============================================================================

pub const IID_IDXGIDevice = GUID{
    .Data1 = 0x54ec77fa,
    .Data2 = 0x1377,
    .Data3 = 0x44e6,
    .Data4 = .{ 0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c },
};

// ============================================================================
// D3D11 / DXGI extern functions
// ============================================================================

pub extern "d3d11" fn D3D11CreateDevice(
    pAdapter: ?*anyopaque,
    DriverType: D3D_DRIVER_TYPE,
    Software: ?HANDLE,
    Flags: UINT,
    pFeatureLevels: ?[*]const D3D_FEATURE_LEVEL,
    FeatureLevels: UINT,
    SDKVersion: UINT,
    ppDevice: *?*ID3D11Device,
    pFeatureLevel: ?*D3D_FEATURE_LEVEL,
    ppImmediateContext: *?*ID3D11DeviceContext,
) callconv(.winapi) HRESULT;

pub extern "dxgi" fn CreateDXGIFactory1(
    riid: *const GUID,
    ppFactory: *?*anyopaque,
) callconv(.winapi) HRESULT;

pub extern "d3dcompiler_47" fn D3DCompile(
    pSrcData: [*]const u8,
    SrcDataSize: usize,
    pSourceName: ?[*:0]const u8,
    pDefines: ?*const anyopaque,
    pInclude: ?*const anyopaque,
    pEntrypoint: [*:0]const u8,
    pTarget: [*:0]const u8,
    Flags1: UINT,
    Flags2: UINT,
    ppCode: *?*ID3DBlob,
    ppErrorMsgs: *?*ID3DBlob,
) callconv(.winapi) HRESULT;

/// D3D11 SDK version constant (always 7 for Windows SDK).
pub const D3D11_SDK_VERSION: UINT = 7;

/// D3D11_CREATE_DEVICE flags
pub const D3D11_CREATE_DEVICE_DEBUG: UINT = 0x2;
pub const D3D11_CREATE_DEVICE_BGRA_SUPPORT: UINT = 0x20;

/// D3D11_SRV_DIMENSION
pub const D3D11_SRV_DIMENSION_TEXTURE2D: UINT = 4;
pub const D3D11_SRV_DIMENSION_BUFFER: UINT = 1;

/// D3D11_RTV_DIMENSION
pub const D3D11_RTV_DIMENSION_TEXTURE2D: UINT = 4;

/// DXGI_SWAP_CHAIN flags
pub const DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING: UINT = 2048;
