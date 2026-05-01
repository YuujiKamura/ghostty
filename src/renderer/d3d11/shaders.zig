//! UPSTREAM-SHARED-OK: fork-only file in src/renderer/d3d11/ — D3D11 backend
//! D3D11 shader compilation and management.
//!
//! Mirrors the OpenGL shaders.zig structure: defines Shaders, Uniforms,
//! CellText, CellBg, Image, BgImage, and manages pipeline creation.
const std = @import("std");
const Allocator = std.mem.Allocator;
const math = @import("../../math.zig");
const shader_data = @import("../shader_data.zig");

const com = @import("com.zig");
const Pipeline = @import("Pipeline.zig");

const log = std.log.scoped(.d3d11);

const pipeline_descs: []const struct { [:0]const u8, PipelineDescription } =
    &.{
        .{ "bg_color", .{
            .vertex_fn = loadShaderCode("../shaders/hlsl/full_screen.vs.hlsl"),
            .fragment_fn = loadShaderCode("../shaders/hlsl/bg_color.ps.hlsl"),
            .blending_enabled = false,
        } },
        .{ "cell_bg", .{
            .vertex_fn = loadShaderCode("../shaders/hlsl/full_screen.vs.hlsl"),
            .fragment_fn = loadShaderCode("../shaders/hlsl/cell_bg.ps.hlsl"),
            .blending_enabled = true,
        } },
        .{ "cell_text", .{
            .vertex_attributes = CellText,
            .vertex_fn = loadShaderCode("../shaders/hlsl/cell_text.vs.hlsl"),
            .fragment_fn = loadShaderCode("../shaders/hlsl/cell_text.ps.hlsl"),
            .step_fn = .per_instance,
            .blending_enabled = true,
        } },
        .{ "image", .{
            .vertex_attributes = Image,
            .vertex_fn = loadShaderCode("../shaders/hlsl/image.vs.hlsl"),
            .fragment_fn = loadShaderCode("../shaders/hlsl/image.ps.hlsl"),
            .step_fn = .per_instance,
            .blending_enabled = true,
        } },
        .{ "bg_image", .{
            .vertex_attributes = BgImage,
            .vertex_fn = loadShaderCode("../shaders/hlsl/bg_image.vs.hlsl"),
            .fragment_fn = loadShaderCode("../shaders/hlsl/bg_image.ps.hlsl"),
            .step_fn = .per_instance,
            .blending_enabled = true,
        } },
    };

const PipelineDescription = struct {
    vertex_attributes: ?type = null,
    vertex_fn: [:0]const u8,
    fragment_fn: [:0]const u8,
    step_fn: Pipeline.Options.StepFunction = .per_vertex,
    blending_enabled: bool = true,

    fn initPipeline(self: PipelineDescription, device: *com.ID3D11Device, alloc: Allocator) !Pipeline {
        return try Pipeline.init(device, alloc, self.vertex_attributes, .{
            .vertex_fn = self.vertex_fn,
            .fragment_fn = self.fragment_fn,
            .step_fn = self.step_fn,
            .blending_enabled = self.blending_enabled,
        });
    }
};

/// Build the pipeline collection type from the desc array.
const PipelineCollection = t: {
    var fields: [pipeline_descs.len]std.builtin.Type.StructField = undefined;
    for (pipeline_descs, 0..) |pipeline, i| {
        fields[i] = .{
            .name = pipeline[0],
            .type = Pipeline,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Pipeline),
        };
    }
    break :t @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
};

/// Shader state for the D3D11 renderer.
pub const Shaders = struct {
    pipelines: PipelineCollection,
    post_pipelines: []const Pipeline,
    defunct: bool = false,

    pub fn init(
        device: *com.ID3D11Device,
        alloc: Allocator,
        post_shaders: []const [:0]const u8,
    ) !Shaders {
        var pipelines: PipelineCollection = undefined;
        var initialized: usize = 0;

        errdefer inline for (pipeline_descs, 0..) |pipeline, i| {
            if (i < initialized) {
                @field(pipelines, pipeline[0]).deinit();
            }
        };

        inline for (pipeline_descs) |pipeline| {
            @field(pipelines, pipeline[0]) = try pipeline[1].initPipeline(device, alloc);
            initialized += 1;
        }

        // TODO: custom post-process shaders for D3D11
        _ = post_shaders;
        const post_pipelines: []const Pipeline = &.{};

        return .{
            .pipelines = pipelines,
            .post_pipelines = post_pipelines,
        };
    }

    pub fn deinit(self: *Shaders, alloc: Allocator) void {
        if (self.defunct) return;
        self.defunct = true;

        inline for (pipeline_descs) |pipeline| {
            @field(self.pipelines, pipeline[0]).deinit();
        }

        if (self.post_pipelines.len > 0) {
            for (self.post_pipelines) |pipeline| {
                pipeline.deinit();
            }
            alloc.free(self.post_pipelines);
        }
    }
};

// Shared shader data types (re-exported for API compatibility).
pub const Uniforms = shader_data.Uniforms;
pub const CellText = shader_data.CellText;
pub const CellBg = shader_data.CellBg;
pub const Image = shader_data.Image;
pub const BgImage = shader_data.BgImage;

/// Load shader code from the target path, processing `#include` directives.
fn loadShaderCode(comptime path: []const u8) [:0]const u8 {
    return comptime processIncludes(@embedFile(path), std.fs.path.dirname(path).?);
}

fn processIncludes(contents: [:0]const u8, basedir: []const u8) [:0]const u8 {
    @setEvalBranchQuota(100_000);
    var i: usize = 0;
    while (i < contents.len) {
        if (std.mem.startsWith(u8, contents[i..], "#include")) {
            const quote_start = std.mem.indexOfScalarPos(u8, contents, i, '"').?;
            const start = quote_start + 1;
            const end = std.mem.indexOfScalarPos(u8, contents, start, '"').?;
            return std.fmt.comptimePrint(
                "{s}{s}{s}",
                .{
                    contents[0..i],
                    @embedFile(basedir ++ "/" ++ contents[start..end]),
                    processIncludes(contents[end + 1 ..], basedir),
                },
            );
        }
        if (std.mem.indexOfPos(u8, contents, i, "\n#")) |j| {
            i = (j + 1);
        } else {
            break;
        }
    }
    return contents;
}
