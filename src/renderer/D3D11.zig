//! Graphics API wrapper for Direct3D 11.
//!
//! Implements the GraphicsAPI interface required by GenericRenderer,
//! using D3D11 for rendering and DXGI FLIP_DISCARD for presentation.
//! The DwmFlush thread is retained as a periodic heartbeat for frame pacing
//! at the monitor's refresh rate.
pub const D3D11 = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const apprt = @import("../apprt.zig");
const font = @import("../font/main.zig");
const configpkg = @import("../config.zig");
const rendererpkg = @import("../renderer.zig");
const shadertoy = @import("shadertoy.zig");
const com = @import("d3d11/com.zig");
const win32 = @import("d3d11/win32.zig");

const Renderer = rendererpkg.GenericRenderer(D3D11);

pub const GraphicsAPI = D3D11;
pub const Target = @import("d3d11/Target.zig");
pub const Frame = @import("d3d11/Frame.zig");
pub const RenderPass = @import("d3d11/RenderPass.zig");
pub const Pipeline = @import("d3d11/Pipeline.zig");
const bufferpkg = @import("d3d11/buffer.zig");
pub const Buffer = bufferpkg.Buffer;
pub const Sampler = @import("d3d11/Sampler.zig");
pub const Texture = @import("d3d11/Texture.zig");
pub const shaders = @import("d3d11/shaders.zig");

pub const custom_shader_target: shadertoy.Target = .hlsl;
/// D3D11: +Y = down (screen coordinates), unlike OpenGL.
pub const custom_shader_y_is_down = true;
/// Double buffering with FLIP_DISCARD.
pub const swap_chain_count = 2;
/// D3D11 uses DXGI Present, but still needs the DwmFlush thread as a
/// periodic heartbeat to trigger redraws at monitor refresh rate.
pub const needs_vsync_thread = true;

const log = std.log.scoped(.d3d11);

alloc: std.mem.Allocator,
blending: configpkg.Config.AlphaBlending,

device: ?*com.ID3D11Device = null,
context: ?*com.ID3D11DeviceContext = null,
swap_chain: ?*com.IDXGISwapChain1 = null,
factory: ?*com.IDXGIFactory2 = null,

/// The most recently presented target for re-presentation.
last_target: ?Target = null,

/// Cached surface dimensions.
surface_width: u32 = 0,
surface_height: u32 = 0,

/// HWND to bind the swap chain to.
hwnd: ?com.HWND = null,

/// Performance stats.
perf: PerfStats = .{},

const PerfStats = @import("perf_stats.zig").PerfStats;

pub fn init(alloc: Allocator, opts: rendererpkg.Options) !D3D11 {
    // Create D3D11 device eagerly — GenericRenderer needs it for buffer/texture creation.
    // SwapChain creation is deferred to threadEnter() where HWND is available.
    const feature_levels = [_]com.D3D_FEATURE_LEVEL{.@"11_0"};
    var device: ?*com.ID3D11Device = null;
    var context: ?*com.ID3D11DeviceContext = null;
    var feature_level: com.D3D_FEATURE_LEVEL = .@"11_0";

    const flags: com.UINT = if (builtin.mode == .Debug)
        com.D3D11_CREATE_DEVICE_BGRA_SUPPORT | com.D3D11_CREATE_DEVICE_DEBUG
    else
        com.D3D11_CREATE_DEVICE_BGRA_SUPPORT;

    const hr = com.D3D11CreateDevice(
        null,
        .HARDWARE,
        null,
        flags,
        &feature_levels,
        feature_levels.len,
        com.D3D11_SDK_VERSION,
        &device,
        &feature_level,
        &context,
    );
    if (hr < 0 or device == null or context == null) {
        log.err("D3D11CreateDevice failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
        return error.D3D11InitFailed;
    }
    log.info("D3D11 device created, feature level: 0x{x}", .{@intFromEnum(feature_level)});

    // Create DXGI factory for swap chain creation later.
    var factory_ptr: ?*anyopaque = null;
    const factory_hr = com.CreateDXGIFactory1(&com.IDXGIFactory2.IID, &factory_ptr);
    if (factory_hr < 0 or factory_ptr == null) {
        log.err("CreateDXGIFactory1 failed: hr=0x{x}", .{@as(u32, @bitCast(factory_hr))});
        return error.D3D11InitFailed;
    }

    return .{
        .alloc = alloc,
        .blending = opts.config.blending,
        .device = device,
        .context = context,
        .factory = @ptrCast(@alignCast(factory_ptr.?)),
    };
}

pub fn deinit(self: *D3D11) void {
    self.perf.logSummary();

    if (self.swap_chain) |sc| sc.release();
    if (self.factory) |f| f.release();
    if (self.context) |ctx| {
        ctx.clearState();
        ctx.flush();
        ctx.release();
    }
    if (self.device) |dev| dev.release();
    self.* = undefined;
}

/// Called early right after surface creation.
pub fn surfaceInit(surface: *apprt.Surface) !void {
    _ = surface;
    // D3D11 doesn't need global surface init like OpenGL context creation.
    // Device is created in init(), swap chain in threadEnter().
}

/// Called just prior to spinning up the renderer thread.
pub fn finalizeSurfaceInit(self: *const D3D11, surface: *apprt.Surface) !void {
    _ = self;
    _ = surface;
    // No-op for D3D11: no need to release GL context from main thread.
}

/// Callback when the renderer thread begins.
pub fn threadEnter(self: *D3D11, surface: *apprt.Surface) !void {
    // Device and factory already created in init().
    // Here we only create the swap chain which needs the HWND.
    const app = surface.app;
    self.hwnd = app.hwnd;
    const hwnd = self.hwnd orelse return error.D3D11InitFailed;
    const device = self.device orelse return error.D3D11InitFailed;

    // Get initial window size.
    var rect: win32.RECT = .{};
    _ = win32.GetClientRect(hwnd, &rect);
    self.surface_width = @intCast(@max(1, rect.right - rect.left));
    self.surface_height = @intCast(@max(1, rect.bottom - rect.top));

    // Create swap chain — composition path for WinUI 3, HWND path for win32.
    const use_composition = comptime @hasDecl(apprt.Surface, "bindSwapChain");

    if (comptime use_composition) {
        // Composition swap chain for WinUI 3 SwapChainPanel
        const sc_desc = com.DXGI_SWAP_CHAIN_DESC1{
            .Width = self.surface_width,
            .Height = self.surface_height,
            .Format = .B8G8R8A8_UNORM,
            .BufferCount = 2,
            .SwapEffect = .FLIP_DISCARD,
            .Scaling = .STRETCH,
            .Flags = com.DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING,
        };
        self.swap_chain = self.factory.?.createSwapChainForComposition(
            @ptrCast(device),
            &sc_desc,
        ) catch {
            log.err("CreateSwapChainForComposition failed", .{});
            return error.D3D11InitFailed;
        };
        // Post swap chain binding to the UI thread (async — will happen via WM_USER+1).
        surface.bindSwapChain(@ptrCast(self.swap_chain.?));
    } else {
        // HWND swap chain (win32 path)
        const sc_desc = com.DXGI_SWAP_CHAIN_DESC1{
            .Width = self.surface_width,
            .Height = self.surface_height,
            .Format = .B8G8R8A8_UNORM,
            .BufferCount = 2,
            .SwapEffect = .FLIP_DISCARD,
            .Scaling = .NONE,
            .Flags = com.DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING,
        };
        self.swap_chain = self.factory.?.createSwapChainForHwnd(
            @ptrCast(device),
            hwnd,
            &sc_desc,
        ) catch {
            log.err("CreateSwapChainForHwnd failed", .{});
            return error.D3D11InitFailed;
        };
    }

    log.info("D3D11 swap chain created: {}x{}", .{ self.surface_width, self.surface_height });
}

/// Callback when the renderer thread exits.
pub fn threadExit(self: *const D3D11) void {
    _ = self;
    // D3D11 context is not thread-bound like OpenGL.
}

pub fn displayRealized(self: *const D3D11) void {
    _ = self;
    // Only GTK calls this.
}

/// Actions taken before doing anything in drawFrame.
pub fn drawFrameStart(self: *D3D11) void {
    self.perf.recordFrameStart();

    // Query actual window size and resize swap chain if needed.
    if (self.hwnd) |hwnd| {
        var rect: win32.RECT = .{};
        _ = win32.GetClientRect(hwnd, &rect);
        const w: u32 = @intCast(@max(1, rect.right - rect.left));
        const h: u32 = @intCast(@max(1, rect.bottom - rect.top));
        if (w != self.surface_width or h != self.surface_height) {
            self.resizeSwapChain(w, h);
        }
    }

    // Set viewport for the frame.
    const ctx = self.context orelse return;
    const viewports = [1]com.D3D11_VIEWPORT{.{
        .Width = @floatFromInt(self.surface_width),
        .Height = @floatFromInt(self.surface_height),
    }};
    ctx.rsSetViewports(&viewports);
}

/// Actions taken after drawFrame is done.
pub fn drawFrameEnd(self: *D3D11) void {
    self.perf.recordFrameEnd();
}

pub fn initShaders(
    self: *const D3D11,
    alloc: Allocator,
    custom_shaders: []const [:0]const u8,
) !shaders.Shaders {
    const dev = self.device orelse return error.D3D11Failed;
    return try shaders.Shaders.init(dev, alloc, custom_shaders);
}

/// Get the current size of the runtime surface.
pub fn surfaceSize(self: *const D3D11) !struct { width: u32, height: u32 } {
    return .{
        .width = self.surface_width,
        .height = self.surface_height,
    };
}

/// Initialize a new render target which can be presented by this API.
pub fn initTarget(self: *const D3D11, width: usize, height: usize) !Target {
    const dev = self.device orelse return error.D3D11Failed;
    // Must match swap chain format (B8G8R8A8) for CopyResource compatibility.
    const format: com.DXGI_FORMAT = if (self.blending.isLinear()) .B8G8R8A8_UNORM_SRGB else .B8G8R8A8_UNORM;
    return Target.init(dev, .{
        .width = width,
        .height = height,
        .format = format,
    });
}

/// Present the provided target by copying it to the swap chain back buffer.
pub fn present(self: *D3D11, target: Target) !void {
    const ctx = self.context orelse return;
    const sc = self.swap_chain orelse return;

    // Copy offscreen target to back buffer, then release ALL references
    // before Present(). FLIP_DISCARD requires no outstanding refs on the
    // back buffer at present time.
    if (target.texture) |src_tex| {
        const back_buffer = sc.getBuffer(com.ID3D11Texture2D, 0) catch return;
        ctx.copyResource(@ptrCast(back_buffer), @ptrCast(src_tex));
        back_buffer.release();
    }

    // Present with ALLOW_TEARING for immediate, non-vsync presentation.
    // Frame pacing is handled externally by the DwmFlush heartbeat thread.
    _ = sc.present(0, com.DXGI_PRESENT_ALLOW_TEARING);

    self.last_target = target;
}

/// Present the last presented target again.
pub fn presentLastTarget(self: *D3D11) !void {
    if (self.last_target) |target| try self.present(target);
}

/// Returns the options to use when constructing buffers.
pub inline fn bufferOptions(self: D3D11) bufferpkg.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .bind_flags = com.D3D11_BIND_VERTEX_BUFFER,
        .dynamic = true,
    };
}

pub inline fn uniformBufferOptions(self: D3D11) bufferpkg.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .bind_flags = com.D3D11_BIND_CONSTANT_BUFFER,
        .dynamic = true,
    };
}

pub inline fn fgBufferOptions(self: D3D11) bufferpkg.Options {
    return self.bufferOptions();
}

pub inline fn bgBufferOptions(self: D3D11) bufferpkg.Options {
    return self.bufferOptions();
}

pub inline fn instanceBufferOptions(self: D3D11) bufferpkg.Options {
    return self.bufferOptions();
}

pub inline fn imageBufferOptions(self: D3D11) bufferpkg.Options {
    return self.bufferOptions();
}

pub inline fn bgImageBufferOptions(self: D3D11) bufferpkg.Options {
    return self.bufferOptions();
}

/// Returns the options to use when constructing textures.
pub inline fn textureOptions(self: D3D11) Texture.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .format = .R8G8B8A8_UNORM_SRGB,
    };
}

/// Returns the options to use when constructing samplers.
pub inline fn samplerOptions(self: D3D11) Sampler.Options {
    return .{
        .device = self.device,
        .filter = .MIN_MAG_MIP_LINEAR,
        .address_u = .CLAMP,
        .address_v = .CLAMP,
    };
}

/// Pixel format for image texture options.
pub const ImageTextureFormat = enum {
    gray,
    rgba,
    bgra,

    fn toFormat(self: ImageTextureFormat) com.DXGI_FORMAT {
        return switch (self) {
            .gray => .R8_UNORM,
            .rgba => .R8G8B8A8_UNORM,
            .bgra => .B8G8R8A8_UNORM,
        };
    }
};

pub inline fn imageTextureOptions(
    self: D3D11,
    format: ImageTextureFormat,
    srgb: bool,
) Texture.Options {
    const f = format.toFormat();
    // If sRGB requested, upgrade to the _SRGB variant where applicable.
    const final_format: com.DXGI_FORMAT = if (srgb) switch (f) {
        .R8G8B8A8_UNORM => .R8G8B8A8_UNORM_SRGB,
        .B8G8R8A8_UNORM => .B8G8R8A8_UNORM_SRGB,
        else => f,
    } else f;
    return .{
        .device = self.device,
        .context = self.context,
        .format = final_format,
    };
}

/// Initializes a Texture suitable for the provided font atlas.
pub fn initAtlasTexture(
    self: *const D3D11,
    atlas: *const font.Atlas,
) Texture.Error!Texture {
    const format: com.DXGI_FORMAT = switch (atlas.format) {
        .grayscale => .R8_UNORM,
        .bgra => .B8G8R8A8_UNORM_SRGB,
        else => return error.D3D11Failed,
    };

    return try Texture.init(
        .{
            .device = self.device,
            .context = self.context,
            .format = format,
            .pixel_coords = true,
        },
        atlas.size,
        atlas.size,
        null,
    );
}

/// Begin a frame.
pub inline fn beginFrame(
    self: *const D3D11,
    renderer: *Renderer,
    target: *Target,
) !Frame {
    _ = self;
    return try Frame.begin(.{}, renderer, target);
}

/// Handle window resize by resizing swap chain buffers.
pub fn resizeSwapChain(self: *D3D11, width: u32, height: u32) void {
    if (width == 0 or height == 0) return;
    if (width == self.surface_width and height == self.surface_height) return;

    const sc = self.swap_chain orelse return;
    sc.resizeBuffers(0, width, height, .UNKNOWN, com.DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING) catch {
        log.err("ResizeBuffers failed", .{});
        return;
    };

    self.surface_width = width;
    self.surface_height = height;
    log.info("Swap chain resized to {}x{}", .{ width, height });
}

const error_set = error{D3D11InitFailed};
