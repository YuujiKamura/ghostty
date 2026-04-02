//! Graphics API wrapper for OpenGL.
pub const OpenGL = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const build_config = @import("../build_config.zig");
const gl = @import("opengl");
const shadertoy = @import("shadertoy.zig");
const apprt = @import("../apprt.zig");
const font = @import("../font/main.zig");
const configpkg = @import("../config.zig");
const rendererpkg = @import("../renderer.zig");
const Renderer = rendererpkg.GenericRenderer(OpenGL);

pub const GraphicsAPI = OpenGL;
pub const Target = @import("opengl/Target.zig");
pub const Frame = @import("opengl/Frame.zig");
pub const RenderPass = @import("opengl/RenderPass.zig");
pub const Pipeline = @import("opengl/Pipeline.zig");
const bufferpkg = @import("opengl/buffer.zig");
pub const Buffer = bufferpkg.Buffer;
pub const Sampler = @import("opengl/Sampler.zig");
pub const Texture = @import("opengl/Texture.zig");
pub const shaders = @import("opengl/shaders.zig");

pub const custom_shader_target: shadertoy.Target = .glsl;
// The fragCoord for OpenGL shaders is +Y = up.
pub const custom_shader_y_is_down = false;

/// On Windows, use double buffering to allow CPU-GPU overlap.
/// On other platforms, OpenGL frame completion is sync so no need.
pub const swap_chain_count = if (builtin.os.tag == .windows) 2 else 1;

const log = std.log.scoped(.opengl);

/// We require at least OpenGL 4.3
pub const MIN_VERSION_MAJOR = 4;
pub const MIN_VERSION_MINOR = 3;

alloc: std.mem.Allocator,

/// Alpha blending mode
blending: configpkg.Config.AlphaBlending,

/// The most recently presented target, in case we need to present it again.
last_target: ?Target = null,

/// Cached viewport dimensions to avoid redundant Win32 API calls.
cached_viewport_width: u32 = 0,
cached_viewport_height: u32 = 0,

/// GL fence from the previous frame for async GPU completion tracking.
/// Used with swap_chain_count=2 on Windows to ensure the GPU is done
/// with the previous frame before reusing its buffers.
prev_fence: ?gl.GLsync = null,

/// Frame timing stats for performance monitoring (Win32 only).
/// Logs min/avg/max frame times and fence wait times every 300 frames (~5s at 60fps).
perf: if (builtin.os.tag == .windows) PerfStats else void = if (builtin.os.tag == .windows) .{} else {},

const PerfStats = struct {
    frame_start: ?std.time.Instant = null,
    fence_wait_ns: u64 = 0,
    /// Lifetime totals (never reset)
    lifetime_count: u64 = 0,
    lifetime_frame_ns: u64 = 0,
    lifetime_fence_ns: u64 = 0,
    lifetime_min_ns: u64 = std.math.maxInt(u64),
    lifetime_max_ns: u64 = 0,

    fn recordFrameStart(self: *PerfStats) void {
        self.frame_start = std.time.Instant.now() catch null;
        self.fence_wait_ns = 0;
    }

    fn recordFenceWait(self: *PerfStats, ns: u64) void {
        self.fence_wait_ns = ns;
    }

    fn recordFrameEnd(self: *PerfStats) void {
        const start = self.frame_start orelse return;
        const end = std.time.Instant.now() catch return;
        const elapsed = end.since(start);

        self.lifetime_count += 1;
        self.lifetime_frame_ns += elapsed;
        self.lifetime_fence_ns += self.fence_wait_ns;
        if (elapsed < self.lifetime_min_ns) self.lifetime_min_ns = elapsed;
        if (elapsed > self.lifetime_max_ns) self.lifetime_max_ns = elapsed;
    }

    /// Write lifetime summary to a fixed path. Called from deinit.
    fn writeSummary(self: *const PerfStats) void {
        if (self.lifetime_count == 0) return;
        const avg_us = self.lifetime_frame_ns / self.lifetime_count / std.time.ns_per_us;
        const min_us = self.lifetime_min_ns / std.time.ns_per_us;
        const max_us = self.lifetime_max_ns / std.time.ns_per_us;
        const avg_fence_us = self.lifetime_fence_ns / self.lifetime_count / std.time.ns_per_us;

        var buf: [512]u8 = undefined;
        const content = std.fmt.bufPrint(&buf, "frames={d}\navg_us={d}\nmin_us={d}\nmax_us={d}\nfence_avg_us={d}\n", .{
            self.lifetime_count,
            avg_us,
            min_us,
            max_us,
            avg_fence_us,
        }) catch return;

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const temp_path = std.process.getEnvVarOwned(allocator, "TEMP") catch ".";
        const perf_path = std.fs.path.join(allocator, &.{ temp_path, "ghostty_perf.txt" }) catch return;

        const file = std.fs.createFileAbsolute(perf_path, .{}) catch return;
        defer file.close();
        _ = file.writeAll(content) catch {};
    }
};

/// NOTE: This is an error{}!OpenGL instead of just OpenGL for parity with
///       Metal, since it needs to be fallible so does this, even though it
///       can't actually fail.
pub fn init(alloc: Allocator, opts: rendererpkg.Options) error{}!OpenGL {
    return .{
        .alloc = alloc,
        .blending = opts.config.blending,
    };
}

pub fn deinit(self: *OpenGL) void {
    if (comptime builtin.os.tag == .windows) {
        self.perf.writeSummary();
    }
    if (self.prev_fence) |fence| gl.deleteSync(fence);
    self.* = undefined;
}

/// 32-bit windows cross-compilation breaks with `.c` for some reason, so...
const gl_debug_proc_callconv =
    @typeInfo(
        @typeInfo(
            @typeInfo(
                gl.c.GLDEBUGPROC,
            ).optional.child,
        ).pointer.child,
    ).@"fn".calling_convention;

fn glDebugMessageCallback(
    src: gl.c.GLenum,
    typ: gl.c.GLenum,
    id: gl.c.GLuint,
    severity: gl.c.GLenum,
    len: gl.c.GLsizei,
    msg: [*c]const gl.c.GLchar,
    user_param: ?*const anyopaque,
) callconv(gl_debug_proc_callconv) void {
    _ = user_param;

    const src_str: []const u8 = switch (src) {
        gl.c.GL_DEBUG_SOURCE_API => "OpenGL API",
        gl.c.GL_DEBUG_SOURCE_WINDOW_SYSTEM => "Window System",
        gl.c.GL_DEBUG_SOURCE_SHADER_COMPILER => "Shader Compiler",
        gl.c.GL_DEBUG_SOURCE_THIRD_PARTY => "Third Party",
        gl.c.GL_DEBUG_SOURCE_APPLICATION => "User",
        gl.c.GL_DEBUG_SOURCE_OTHER => "Other",
        else => "Unknown",
    };

    const typ_str: []const u8 = switch (typ) {
        gl.c.GL_DEBUG_TYPE_ERROR => "Error",
        gl.c.GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR => "Deprecated Behavior",
        gl.c.GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR => "Undefined Behavior",
        gl.c.GL_DEBUG_TYPE_PORTABILITY => "Portability Issue",
        gl.c.GL_DEBUG_TYPE_PERFORMANCE => "Performance Issue",
        gl.c.GL_DEBUG_TYPE_MARKER => "Marker",
        gl.c.GL_DEBUG_TYPE_PUSH_GROUP => "Group Push",
        gl.c.GL_DEBUG_TYPE_POP_GROUP => "Group Pop",
        gl.c.GL_DEBUG_TYPE_OTHER => "Other",
        else => "Unknown",
    };

    const msg_str = msg[0..@intCast(len)];

    (switch (severity) {
        gl.c.GL_DEBUG_SEVERITY_HIGH => log.err(
            "[{d}] ({s}: {s}) {s}",
            .{ id, src_str, typ_str, msg_str },
        ),
        gl.c.GL_DEBUG_SEVERITY_MEDIUM => log.warn(
            "[{d}] ({s}: {s}) {s}",
            .{ id, src_str, typ_str, msg_str },
        ),
        gl.c.GL_DEBUG_SEVERITY_LOW => log.info(
            "[{d}] ({s}: {s}) {s}",
            .{ id, src_str, typ_str, msg_str },
        ),
        gl.c.GL_DEBUG_SEVERITY_NOTIFICATION => log.debug(
            "[{d}] ({s}: {s}) {s}",
            .{ id, src_str, typ_str, msg_str },
        ),
        else => log.warn(
            "UNKNOWN SEVERITY [{d}] ({s}: {s}) {s}",
            .{ id, src_str, typ_str, msg_str },
        ),
    });
}

/// Prepares the provided GL context, loading it with glad.
fn prepareContext(getProcAddress: anytype) !void {
    const version = try gl.glad.load(getProcAddress);
    const major = gl.glad.versionMajor(@intCast(version));
    const minor = gl.glad.versionMinor(@intCast(version));
    errdefer gl.glad.unload();
    log.info("loaded OpenGL {}.{}", .{ major, minor });

    // Need to check version before trying to enable it
    if (major < MIN_VERSION_MAJOR or
        (major == MIN_VERSION_MAJOR and minor < MIN_VERSION_MINOR))
    {
        log.warn(
            "OpenGL version is too old. Ghostty requires OpenGL {d}.{d}",
            .{ MIN_VERSION_MAJOR, MIN_VERSION_MINOR },
        );
        return error.OpenGLOutdated;
    }

    // Enable debug output for the context.
    try gl.enable(gl.c.GL_DEBUG_OUTPUT);

    // Register our debug message callback with the OpenGL context.
    gl.glad.context.DebugMessageCallback.?(glDebugMessageCallback, null);

    // Enable SRGB framebuffer for linear blending support.
    try gl.enable(gl.c.GL_FRAMEBUFFER_SRGB);
}

/// This is called early right after surface creation.
pub fn surfaceInit(surface: *apprt.Surface) !void {
    _ = surface;

    switch (build_config.app_runtime) {
        .none => {},

        // GTK uses global OpenGL context so we load from null.
        .gtk => try prepareContext(null),

        .win32, .winui3 => {
            // Win32/WinUI 3 manages its own OpenGL context via WGL.
            // The context is already current when this is called.
            try prepareContext(null);
        },
    }

    // These are very noisy so this is commented, but easy to uncomment
    // whenever we need to check the OpenGL extension list
    // if (builtin.mode == .Debug) {
    //     var ext_iter = try gl.ext.iterator();
    //     while (try ext_iter.next()) |ext| {
    //         log.debug("OpenGL extension available name={s}", .{ext});
    //     }
    // }
}

/// This is called just prior to spinning up the renderer
/// thread for final main thread setup requirements.
pub fn finalizeSurfaceInit(self: *const OpenGL, surface: *apprt.Surface) !void {
    _ = self;

    switch (build_config.app_runtime) {
        .win32, .winui3 => {
            // Release the OpenGL context from the main thread so the
            // renderer thread can acquire it.
            surface.app.releaseGLContext();
        },
        else => {},
    }
}

/// Callback called by renderer.Thread when it begins.
pub fn threadEnter(self: *const OpenGL, surface: *apprt.Surface) !void {
    _ = self;

    switch (build_config.app_runtime) {
        .none => {},

        .win32, .winui3 => {
            // Make the OpenGL context current on this (renderer) thread.
            try surface.app.makeGLContextCurrent();
            try prepareContext(null);

            // Disable driver-level VSync (swap interval = 0) so that SwapBuffers
            // returns immediately. VSync timing is handled externally by the
            // DwmFlush-based VSync thread in the renderer.
            const wgl = struct {
                extern "opengl32" fn wglGetProcAddress(lpszProc: [*:0]const u8) callconv(.winapi) ?*const anyopaque;
            };
            const wglSwapIntervalEXT: ?*const fn (c_int) callconv(.winapi) std.os.windows.BOOL =
                @ptrCast(wgl.wglGetProcAddress("wglSwapIntervalEXT"));
            if (wglSwapIntervalEXT) |setSwapInterval| {
                const result = setSwapInterval(0);
                log.info("wglSwapIntervalEXT(0) = {}", .{result});
            } else {
                log.warn("wglSwapIntervalEXT not available", .{});
            }
            // Verify the swap interval was actually set.
            const wglGetSwapIntervalEXT: ?*const fn () callconv(.winapi) c_int =
                @ptrCast(wgl.wglGetProcAddress("wglGetSwapIntervalEXT"));
            if (wglGetSwapIntervalEXT) |getSwapInterval| {
                log.info("swap interval = {}", .{getSwapInterval()});
            }
        },

        .gtk => {
            // GTK doesn't support threaded OpenGL operations as far as I can
            // tell, so we use the renderer thread to setup all the state
            // but then do the actual draws and texture syncs and all that
            // on the main thread. As such, we don't do anything here.
        },
    }
}

/// Callback called by renderer.Thread when it exits.
pub fn threadExit(self: *const OpenGL) void {
    _ = self;

    switch (build_config.app_runtime) {
        .none => {},

        .gtk => {
            // We don't need to do any unloading for GTK because we may
            // be sharing the global bindings with other windows.
        },

        .win32, .winui3 => {
            // Release the OpenGL context from the renderer thread.
            const win32_gl = struct {
                extern "opengl32" fn wglMakeCurrent(hdc: ?std.os.windows.HANDLE, hglrc: ?std.os.windows.HANDLE) callconv(.winapi) std.os.windows.BOOL;
            };
            _ = win32_gl.wglMakeCurrent(null, null);
        },
    }
}

pub fn displayRealized(self: *const OpenGL) void {
    _ = self;

    switch (build_config.app_runtime) {
        .none, .win32, .winui3 => {},

        .gtk => prepareContext(null) catch |err| {
            log.warn(
                "Error preparing GL context in displayRealized, err={}",
                .{err},
            );
        },
    }
}

/// Actions taken before doing anything in `drawFrame`.
///
/// On Win32, we must manually update the OpenGL viewport to match the
/// current window client area, because there is no GLArea equivalent
/// that does this automatically (unlike GTK).
pub fn drawFrameStart(self: *OpenGL) void {
    switch (build_config.app_runtime) {
        .win32, .winui3 => {
            self.perf.recordFrameStart();

            // Wait on the previous frame's GL fence to ensure the GPU
            // has finished reading from the frame buffers we're about to reuse.
            // With swap_chain_count=2, this gives the GPU one full frame
            // of CPU processing time to complete, so the wait is typically free.
            if (self.prev_fence) |fence| {
                const fence_start = std.time.Instant.now() catch null;
                // 1 second timeout as safety; should complete near-instantly.
                _ = gl.clientWaitSync(fence, 1_000_000_000);
                gl.deleteSync(fence);
                self.prev_fence = null;
                if (fence_start) |fs| {
                    if (std.time.Instant.now() catch null) |fe| {
                        self.perf.recordFenceWait(fe.since(fs));
                    }
                }
            }

            const win32_api = struct {
                const HWND = std.os.windows.HANDLE;
                const BOOL = std.os.windows.BOOL;
                const LONG = c_long;
                const RECT = extern struct {
                    left: LONG = 0,
                    top: LONG = 0,
                    right: LONG = 0,
                    bottom: LONG = 0,
                };
                extern "opengl32" fn wglGetCurrentDC() callconv(.winapi) ?std.os.windows.HANDLE;
                extern "user32" fn WindowFromDC(hdc: std.os.windows.HANDLE) callconv(.winapi) ?HWND;
                extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
            };
            const hdc = win32_api.wglGetCurrentDC() orelse return;
            const hwnd = win32_api.WindowFromDC(hdc) orelse return;
            var rect: win32_api.RECT = .{};
            if (win32_api.GetClientRect(hwnd, &rect) != 0) {
                const w: u32 = @intCast(rect.right - rect.left);
                const h: u32 = @intCast(rect.bottom - rect.top);
                if (w != self.cached_viewport_width or h != self.cached_viewport_height) {
                    self.cached_viewport_width = w;
                    self.cached_viewport_height = h;
                    gl.glad.context.Viewport.?(0, 0, @intCast(w), @intCast(h));
                }
            }
        },
        else => {},
    }
}

/// Actions taken after `drawFrame` is done.
pub fn drawFrameEnd(self: *OpenGL) void {
    switch (build_config.app_runtime) {
        .win32, .winui3 => {
            // Swap the front and back buffers to display the rendered frame.
            const win32_gl = struct {
                extern "opengl32" fn wglGetCurrentDC() callconv(.winapi) ?std.os.windows.HANDLE;
                extern "gdi32" fn SwapBuffers(hdc: std.os.windows.HANDLE) callconv(.winapi) std.os.windows.BOOL;
            };
            if (win32_gl.wglGetCurrentDC()) |hdc| {
                _ = win32_gl.SwapBuffers(hdc);
            }

            // Insert a fence after SwapBuffers to track when the GPU finishes
            // this frame. The next drawFrameStart() will wait on this fence
            // before reusing the frame's buffers.
            self.prev_fence = gl.fenceSync();

            self.perf.recordFrameEnd();
        },
        else => {},
    }
}

pub fn initShaders(
    self: *const OpenGL,
    alloc: Allocator,
    custom_shaders: []const [:0]const u8,
) !shaders.Shaders {
    _ = alloc;
    return try shaders.Shaders.init(
        self.alloc,
        custom_shaders,
    );
}

/// Get the current size of the runtime surface.
pub fn surfaceSize(self: *const OpenGL) !struct { width: u32, height: u32 } {
    // On Win32, use the cached viewport from drawFrameStart to avoid
    // a redundant glGetIntegerv call every frame.
    if (comptime build_config.app_runtime == .win32 or build_config.app_runtime == .winui3) {
        return .{
            .width = self.cached_viewport_width,
            .height = self.cached_viewport_height,
        };
    }
    var viewport: [4]gl.c.GLint = undefined;
    gl.glad.context.GetIntegerv.?(gl.c.GL_VIEWPORT, &viewport);
    return .{
        .width = @intCast(viewport[2]),
        .height = @intCast(viewport[3]),
    };
}

/// Initialize a new render target which can be presented by this API.
pub fn initTarget(self: *const OpenGL, width: usize, height: usize) !Target {
    return Target.init(.{
        .internal_format = if (self.blending.isLinear()) .srgba else .rgba,
        .width = width,
        .height = height,
    });
}

/// Present the provided target.
pub fn present(self: *OpenGL, target: Target) !void {
    // In order to present a target we blit it to the default framebuffer.

    // We disable GL_FRAMEBUFFER_SRGB while doing this blit, otherwise the
    // values may be linearized as they're copied, but even though the draw
    // framebuffer has a linear internal format, the values in it should be
    // sRGB, not linear!
    try gl.disable(gl.c.GL_FRAMEBUFFER_SRGB);
    defer gl.enable(gl.c.GL_FRAMEBUFFER_SRGB) catch |err| {
        log.err("Error re-enabling GL_FRAMEBUFFER_SRGB, err={}", .{err});
    };

    // Bind the target for reading.
    const fbobind = try target.framebuffer.bind(.read);
    defer fbobind.unbind();

    // Blit
    gl.glad.context.BlitFramebuffer.?(
        0,
        0,
        @intCast(target.width),
        @intCast(target.height),
        0,
        0,
        @intCast(target.width),
        @intCast(target.height),
        gl.c.GL_COLOR_BUFFER_BIT,
        gl.c.GL_NEAREST,
    );

    // Keep track of this target in case we need to repeat it.
    self.last_target = target;
}

/// Present the last presented target again.
pub fn presentLastTarget(self: *OpenGL) !void {
    if (self.last_target) |target| try self.present(target);
}

/// Returns the options to use when constructing buffers.
pub inline fn bufferOptions(self: OpenGL) bufferpkg.Options {
    _ = self;
    return .{
        .target = .array,
        .usage = .dynamic_draw,
    };
}

pub const instanceBufferOptions = bufferOptions;
pub const uniformBufferOptions = bufferOptions;
pub const fgBufferOptions = bufferOptions;
pub const bgBufferOptions = bufferOptions;
pub const imageBufferOptions = bufferOptions;
pub const bgImageBufferOptions = bufferOptions;

/// Returns the options to use when constructing textures.
pub inline fn textureOptions(self: OpenGL) Texture.Options {
    _ = self;
    return .{
        .format = .rgba,
        .internal_format = .srgba,
        .target = .@"2D",
        .min_filter = .linear,
        .mag_filter = .linear,
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
    };
}

/// Returns the options to use when constructing samplers.
pub inline fn samplerOptions(self: OpenGL) Sampler.Options {
    _ = self;
    return .{
        .min_filter = .linear,
        .mag_filter = .linear,
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
    };
}

/// Pixel format for image texture options.
pub const ImageTextureFormat = enum {
    /// 1 byte per pixel grayscale.
    gray,
    /// 4 bytes per pixel RGBA.
    rgba,
    /// 4 bytes per pixel BGRA.
    bgra,

    fn toPixelFormat(self: ImageTextureFormat) gl.Texture.Format {
        return switch (self) {
            .gray => .red,
            .rgba => .rgba,
            .bgra => .bgra,
        };
    }
};

/// Returns the options to use when constructing textures for images.
pub inline fn imageTextureOptions(
    self: OpenGL,
    format: ImageTextureFormat,
    srgb: bool,
) Texture.Options {
    _ = self;
    return .{
        .format = format.toPixelFormat(),
        .internal_format = if (srgb) .srgba else .rgba,
        .target = .@"2D",
        // TODO: Generate mipmaps for image textures and use
        //       linear_mipmap_linear filtering so that they
        //       look good even when scaled way down.
        .min_filter = .linear,
        .mag_filter = .linear,
        // TODO: Separate out background image options, use
        //       repeating coordinate modes so we don't have
        //       to do the modulus in the shader.
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
    };
}

/// Initializes a Texture suitable for the provided font atlas.
pub fn initAtlasTexture(
    self: *const OpenGL,
    atlas: *const font.Atlas,
) Texture.Error!Texture {
    _ = self;
    const format: gl.Texture.Format, const internal_format: gl.Texture.InternalFormat =
        switch (atlas.format) {
            .grayscale => .{ .red, .red },
            .bgra => .{ .bgra, .srgba },
            else => @panic("unsupported atlas format for OpenGL texture"),
        };

    return try Texture.init(
        .{
            .format = format,
            .internal_format = internal_format,
            .target = .Rectangle,
            .min_filter = .nearest,
            .mag_filter = .nearest,
            .wrap_s = .clamp_to_edge,
            .wrap_t = .clamp_to_edge,
        },
        atlas.size,
        atlas.size,
        null,
    );
}

/// Begin a frame.
pub inline fn beginFrame(
    self: *const OpenGL,
    /// Once the frame has been completed, the `frameCompleted` method
    /// on the renderer is called with the health status of the frame.
    renderer: *Renderer,
    /// The target is presented via the provided renderer's API when completed.
    target: *Target,
) !Frame {
    _ = self;
    return try Frame.begin(.{}, renderer, target);
}
