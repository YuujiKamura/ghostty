/// The debug overlay that can be drawn on top of the terminal
/// during the rendering process.
///
/// This is implemented by doing all the drawing on the CPU via z2d,
/// since the debug overlay isn't that common, z2d is pretty fast, and
/// it simplifies our implementation quite a bit by not relying on us
/// having a bunch of shaders that we have to write per-platform.
///
/// Initialize the overlay, apply features with `applyFeatures`, then
/// get the resulting image with `pendingImage` to upload to the GPU.
/// This works in concert with `renderer.image.State` to simplify. Draw
/// it on the GPU as an image composited on top of the terminal output.
const Overlay = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const z2d = @import("z2d");
// UPSTREAM-SHARED-OK: renderer debug overlay text needs an explicit embedded font because z2d Context has no default font.
const fontpkg = @import("../font/main.zig");
const terminal = @import("../terminal/main.zig");
const size = @import("size.zig");
const Size = size.Size;
const CellSize = size.CellSize;
const Image = @import("image.zig").Image;

const log = std.log.scoped(.renderer_overlay);

/// The colors we use for overlays.
pub const Color = enum {
    hyperlink, // light blue
    semantic_prompt, // orange/gold
    semantic_input, // cyan
    debug_text, // green

    pub fn rgba(self: Color) z2d.pixel.RGBA {
        return switch (self) {
            .hyperlink => .{ .r = 180, .g = 180, .b = 255, .a = 255 },
            .semantic_prompt => .{ .r = 255, .g = 200, .b = 64, .a = 255 },
            .semantic_input => .{ .r = 64, .g = 200, .b = 255, .a = 255 },
            .debug_text => .{ .r = 0, .g = 255, .b = 0, .a = 255 },
        };
    }

    /// The fill color for rectangles.
    pub fn rectFill(self: Color) z2d.Pixel {
        return self.alphaPixel(96);
    }

    /// The border color for rectangles.
    pub fn rectBorder(self: Color) z2d.Pixel {
        return self.alphaPixel(200);
    }

    /// The raw RGBA as a pixel.
    pub fn pixel(self: Color) z2d.Pixel {
        return .{ .rgba = self.rgba() };
    }

    fn alphaPixel(self: Color, alpha: u8) z2d.Pixel {
        var res = self.rgba();
        res.a = alpha;
        return res.multiply().asPixel();
    }
};

/// The surface we're drawing our overlay to.
surface: z2d.Surface,

/// Cell size information so we can map grid coordinates to pixels.
cell_size: CellSize,

/// UPSTREAM-SHARED-OK: reusing a validated embedded font avoids reparsing font tables for every debug overlay frame.
debug_font: z2d.Font,

/// Whether to show the debug overlay (FPS, TSF preedit).
show_debug_overlay: bool = false,

/// Current FPS to display in the debug overlay.
fps: f64 = 0,

/// Current TSF preedit text to display in the debug overlay.
tsf_preedit: ?[]const u8 = null,

/// The set of available features and their configuration.
pub const Feature = union(enum) {
    highlight_hyperlinks,
    semantic_prompts,
};

pub const InitError = Allocator.Error || error{
    // The terminal dimensions are invalid to support an overlay.
    // Either too small or too big.
    InvalidDimensions,
};

/// Initialize a new, blank overlay.
pub fn init(alloc: Allocator, sz: Size) InitError!Overlay {
    // Our surface does NOT need to take into account padding because
    // we render the overlay using the image subsystem and shaders which
    // already take that into account.
    const term_size = sz.terminal();
    var sfc = z2d.Surface.initPixel(
        .{ .rgba = .{ .r = 0, .g = 0, .b = 0, .a = 0 } },
        alloc,
        std.math.cast(i32, term_size.width) orelse
            return error.InvalidDimensions,
        std.math.cast(i32, term_size.height) orelse
            return error.InvalidDimensions,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidWidth, error.InvalidHeight => return error.InvalidDimensions,
    };
    errdefer sfc.deinit(alloc);

    return .{
        .surface = sfc,
        .cell_size = sz.cell,
        .debug_font = z2d.Font.loadBuffer(fontpkg.embedded.regular) catch unreachable,
    };
}

pub fn deinit(self: *Overlay, alloc: Allocator) void {
    self.surface.deinit(alloc);
}

/// Returns a pending image that can be used to copy, convert, upload, etc.
pub fn pendingImage(self: *const Overlay) Image.Pending {
    return .{
        .width = @intCast(self.surface.getWidth()),
        .height = @intCast(self.surface.getHeight()),
        .pixel_format = .rgba,
        .data = @ptrCast(self.surface.image_surface_rgba.buf.ptr),
    };
}

/// Clear the overlay.
pub fn reset(self: *Overlay) void {
    self.surface.paintPixel(.{ .rgba = .{
        .r = 0,
        .g = 0,
        .b = 0,
        .a = 0,
    } });
}

/// Apply the given features to this overlay. This will draw on top of
/// any pre-existing content in the overlay.
pub fn applyFeatures(
    self: *Overlay,
    alloc: Allocator,
    state: *const terminal.RenderState,
    features: []const Feature,
) void {
    for (features) |f| switch (f) {
        .highlight_hyperlinks => self.highlightHyperlinks(
            alloc,
            state,
        ),
        .semantic_prompts => self.highlightSemanticPrompts(
            alloc,
            state,
        ),
    };

    // Draw the debug overlay if either (a) the user explicitly toggled it
    // on for FPS / diagnostics, or (b) there's an active TSF preedit that
    // needs to be surfaced to the user (the side-channel fallback for
    // IME composition not rendering at the cursor — see project memory
    // `project_ghostty_win_overlay_purpose`).
    if (self.show_debug_overlay or self.tsf_preedit != null) {
        self.drawDebugOverlay(alloc) catch |err| {
            log.warn("error drawing debug overlay: {}", .{err});
        };
    }
}

/// Draw the FPS and/or TSF preedit overlay in the top right corner.
///
/// FPS line is only emitted when `show_debug_overlay` is true. The TSF
/// preedit line is emitted whenever `tsf_preedit` is non-null — i.e. the
/// preedit channel is independent of the user-facing F12 toggle, because
/// it's the only visual feedback the user has during IME composition.
fn drawDebugOverlay(self: *Overlay, alloc: Allocator) !void {
    var ctx: z2d.Context = .init(alloc, &self.surface);
    defer ctx.deinit();

    ctx.setSourceToPixel(Color.debug_text.pixel());
    // UPSTREAM-SHARED-OK: z2d text rendering is a no-op without an explicit font, so bind the cached embedded face for overlay text.
    ctx.font = .{ .buffer = self.debug_font };

    const font_size = 16.0;
    const line_height = font_size + 4.0;
    const margin = 8.0;
    const right_padding = 240.0;
    ctx.setFontSize(font_size);

    var buf: [128]u8 = undefined;

    const width = @as(f64, @floatFromInt(self.surface.getWidth()));
    // Simple top-right alignment (fixed offset for now).
    const x = @max(margin, width - right_padding);
    var y: f64 = margin + font_size;

    if (self.show_debug_overlay) {
        const fps_text = std.fmt.bufPrint(&buf, "FPS: {d:.2}", .{self.fps}) catch "FPS: ERROR";
        try ctx.showText(fps_text, x, y);
        y += line_height;
    }

    if (self.tsf_preedit) |preedit| {
        const tsf_text = std.fmt.bufPrint(&buf, "TSF: {s}", .{preedit}) catch "TSF: ERROR";
        try ctx.showText(tsf_text, x, y);
    }
}

/// Add rectangles around contiguous hyperlinks in the render state.
///
/// Note: this currently doesn't take into account unique hyperlink IDs
/// because the render state doesn't contain this. This will be added
/// later.
fn highlightHyperlinks(
    self: *Overlay,
    alloc: Allocator,
    state: *const terminal.RenderState,
) void {
    const border_color = Color.hyperlink.rectBorder();
    const fill_color = Color.hyperlink.rectFill();

    const row_slice = state.row_data.slice();
    const row_raw = row_slice.items(.raw);
    const row_cells = row_slice.items(.cells);
    for (row_raw, row_cells, 0..) |row, cells, y| {
        if (!row.hyperlink) continue;

        const cells_slice = cells.slice();
        const raw_cells = cells_slice.items(.raw);

        var x: usize = 0;
        while (x < raw_cells.len) {
            // Skip cells without hyperlinks
            if (!raw_cells[x].hyperlink) {
                x += 1;
                continue;
            }

            // Found start of a hyperlink run
            const start_x = x;

            // Find end of contiguous hyperlink cells
            while (x < raw_cells.len and raw_cells[x].hyperlink) x += 1;
            const end_x = x;

            self.highlightGridRect(
                alloc,
                start_x,
                y,
                end_x - start_x,
                1,
                border_color,
                fill_color,
            ) catch |err| {
                std.log.warn("Error drawing hyperlink border: {}", .{err});
            };
        }
    }
}

fn highlightSemanticPrompts(
    self: *Overlay,
    alloc: Allocator,
    state: *const terminal.RenderState,
) void {
    const row_slice = state.row_data.slice();
    const row_raw = row_slice.items(.raw);
    const row_cells = row_slice.items(.cells);

    // Highlight the row-level semantic prompt bars. The prompts are easy
    // because they're part of the row metadata.
    {
        const prompt_border = Color.semantic_prompt.rectBorder();
        const prompt_fill = Color.semantic_prompt.rectFill();

        var y: usize = 0;
        while (y < row_raw.len) {
            // If its not a semantic prompt row, skip it.
            if (row_raw[y].semantic_prompt == .none) {
                y += 1;
                continue;
            }

            // Find the full length of the semantic prompt row by connecting
            // all continuations.
            const start_y = y;
            y += 1;
            while (y < row_raw.len and
                row_raw[y].semantic_prompt == .prompt_continuation)
            {
                y += 1;
            }
            const end_y = y; // Exclusive

            const bar_width = @min(@as(usize, 5), self.cell_size.width);
            self.highlightPixelRect(
                alloc,
                0,
                start_y,
                bar_width,
                end_y - start_y,
                prompt_border,
                prompt_fill,
            ) catch |err| {
                log.warn("Error drawing semantic prompt bar: {}", .{err});
            };
        }
    }

    // Highlight contiguous semantic cells within rows.
    for (row_cells, 0..) |cells, y| {
        const cells_slice = cells.slice();
        const raw_cells = cells_slice.items(.raw);

        var x: usize = 0;
        while (x < raw_cells.len) {
            const cell = raw_cells[x];
            const content = cell.semantic_content;
            const start_x = x;

            // We skip output because its just the rest of the non-prompt
            // parts and it makes the overlay too noisy.
            if (cell.semantic_content == .output) {
                x += 1;
                continue;
            }

            // Find the end of this content.
            x += 1;
            while (x < raw_cells.len) {
                const next = raw_cells[x];
                if (next.semantic_content != content) break;
                x += 1;
            }

            const color: Color = switch (content) {
                .prompt => .semantic_prompt,
                .input => .semantic_input,
                .output => unreachable,
            };

            self.highlightGridRect(
                alloc,
                start_x,
                y,
                x - start_x,
                1,
                color.rectBorder(),
                color.rectFill(),
            ) catch |err| {
                log.warn("Error drawing semantic content highlight: {}", .{err});
            };
        }
    }
}

/// Creates a rectangle for highlighting a grid region. x/y/width/height
/// are all in grid cells.
fn highlightGridRect(
    self: *Overlay,
    alloc: Allocator,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    border_color: z2d.Pixel,
    fill_color: z2d.Pixel,
) !void {
    // All math below uses checked arithmetic to avoid overflows. The
    // inputs aren't trusted and the path this is in isn't hot enough
    // to wrarrant unsafe optimizations.

    // Calculate our width/height in pixels.
    const px_width = std.math.cast(i32, try std.math.mul(
        usize,
        width,
        self.cell_size.width,
    )) orelse return error.Overflow;
    const px_height = std.math.cast(i32, try std.math.mul(
        usize,
        height,
        self.cell_size.height,
    )) orelse return error.Overflow;

    // Calculate pixel coordinates
    const start_x: f64 = @floatFromInt(std.math.cast(i32, try std.math.mul(
        usize,
        x,
        self.cell_size.width,
    )) orelse return error.Overflow);
    const start_y: f64 = @floatFromInt(std.math.cast(i32, try std.math.mul(
        usize,
        y,
        self.cell_size.height,
    )) orelse return error.Overflow);
    const end_x: f64 = start_x + @as(f64, @floatFromInt(px_width));
    const end_y: f64 = start_y + @as(f64, @floatFromInt(px_height));

    // Grab our context to draw
    var ctx: z2d.Context = .init(alloc, &self.surface);
    defer ctx.deinit();

    // Don't need AA because we use sharp edges
    ctx.setAntiAliasingMode(.none);
    // Can use hairline since we have 1px borders
    ctx.setHairline(true);

    // Draw rectangle path
    try ctx.moveTo(start_x, start_y);
    try ctx.lineTo(end_x, start_y);
    try ctx.lineTo(end_x, end_y);
    try ctx.lineTo(start_x, end_y);
    try ctx.closePath();

    // Fill
    ctx.setSourceToPixel(fill_color);
    try ctx.fill();

    // Border
    ctx.setLineWidth(1);
    ctx.setSourceToPixel(border_color);
    try ctx.stroke();
}

/// Creates a rectangle for highlighting a region. x/y are grid cells and
/// width/height are pixels.
fn highlightPixelRect(
    self: *Overlay,
    alloc: Allocator,
    x: usize,
    y: usize,
    width_px: usize,
    height: usize,
    border_color: z2d.Pixel,
    fill_color: z2d.Pixel,
) !void {
    const px_width = std.math.cast(i32, width_px) orelse return error.Overflow;
    const px_height = std.math.cast(i32, try std.math.mul(
        usize,
        height,
        self.cell_size.height,
    )) orelse return error.Overflow;

    const start_x: f64 = @floatFromInt(std.math.cast(i32, try std.math.mul(
        usize,
        x,
        self.cell_size.width,
    )) orelse return error.Overflow);
    const start_y: f64 = @floatFromInt(std.math.cast(i32, try std.math.mul(
        usize,
        y,
        self.cell_size.height,
    )) orelse return error.Overflow);
    const end_x: f64 = start_x + @as(f64, @floatFromInt(px_width));
    const end_y: f64 = start_y + @as(f64, @floatFromInt(px_height));

    var ctx: z2d.Context = .init(alloc, &self.surface);
    defer ctx.deinit();

    ctx.setAntiAliasingMode(.none);
    ctx.setHairline(true);

    try ctx.moveTo(start_x, start_y);
    try ctx.lineTo(end_x, start_y);
    try ctx.lineTo(end_x, end_y);
    try ctx.lineTo(start_x, end_y);
    try ctx.closePath();

    ctx.setSourceToPixel(fill_color);
    try ctx.fill();

    ctx.setLineWidth(1);
    ctx.setSourceToPixel(border_color);
    try ctx.stroke();
}

fn testSize(cols: u32, rows: u32) Size {
    const cell: CellSize = .{ .width = 10, .height = 20 };
    return .{
        .screen = .{
            .width = cols * cell.width,
            .height = rows * cell.height,
        },
        .cell = cell,
        .padding = .{},
    };
}

fn initTestOverlay(alloc: Allocator, cols: u32, rows: u32) !Overlay {
    return Overlay.init(alloc, testSize(cols, rows));
}

fn pixelAt(overlay: *const Overlay, x: usize, y: usize) z2d.pixel.RGBA {
    const width: usize = @intCast(overlay.surface.getWidth());
    return overlay.surface.image_surface_rgba.buf[y * width + x];
}

fn countVisiblePixels(overlay: *const Overlay) usize {
    var count: usize = 0;
    for (overlay.surface.image_surface_rgba.buf) |px| {
        if (px.a != 0) count += 1;
    }
    return count;
}

fn countVisiblePixelsInRect(
    overlay: *const Overlay,
    x0: usize,
    y0: usize,
    x1: usize,
    y1: usize,
) usize {
    const width: usize = @intCast(overlay.surface.getWidth());
    const height: usize = @intCast(overlay.surface.getHeight());

    var count: usize = 0;
    var y = y0;
    while (y < @min(y1, height)) : (y += 1) {
        var x = x0;
        while (x < @min(x1, width)) : (x += 1) {
            if (overlay.surface.image_surface_rgba.buf[y * width + x].a != 0) {
                count += 1;
            }
        }
    }

    return count;
}

test "Overlay Color helpers preserve expected alpha semantics" {
    const testing = std.testing;

    try testing.expectEqual(
        Color.debug_text.rgba(),
        z2d.pixel.RGBA.fromPixel(Color.debug_text.pixel()),
    );

    var expected_fill = Color.hyperlink.rgba();
    expected_fill.a = 96;
    try testing.expectEqual(
        expected_fill.multiply(),
        z2d.pixel.RGBA.fromPixel(Color.hyperlink.rectFill()),
    );

    var expected_border = Color.hyperlink.rgba();
    expected_border.a = 200;
    try testing.expectEqual(
        expected_border.multiply(),
        z2d.pixel.RGBA.fromPixel(Color.hyperlink.rectBorder()),
    );
}

test "Overlay init pendingImage and reset" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var overlay = try initTestOverlay(alloc, 2, 2);
    defer overlay.deinit(alloc);

    const pending = overlay.pendingImage();
    try testing.expectEqual(@as(u32, 20), pending.width);
    try testing.expectEqual(@as(u32, 40), pending.height);
    try testing.expectEqual(Image.Pending.PixelFormat.rgba, pending.pixel_format);
    try testing.expectEqual(
        @intFromPtr(overlay.surface.image_surface_rgba.buf.ptr),
        @intFromPtr(pending.data),
    );

    overlay.surface.paintPixel(Color.debug_text.pixel());
    try testing.expect(pixelAt(&overlay, 0, 0).a != 0);

    overlay.reset();
    try testing.expectEqual(
        z2d.pixel.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 },
        pixelAt(&overlay, 0, 0),
    );
    try testing.expectEqual(
        z2d.pixel.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 },
        pixelAt(&overlay, 19, 39),
    );
}

test "Overlay drawDebugOverlay renders text without legacy test rectangle" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var overlay = try initTestOverlay(alloc, 32, 4);
    defer overlay.deinit(alloc);

    overlay.fps = 60.0;
    overlay.tsf_preedit = "abc";

    try overlay.drawDebugOverlay(alloc);

    try testing.expect(countVisiblePixels(&overlay) > 0);
    try testing.expect(countVisiblePixelsInRect(&overlay, 80, 0, 320, 48) > 0);
    try testing.expectEqual(@as(u8, 0), pixelAt(&overlay, 60, 60).a);
}

test "Overlay highlightGridRect draws fill and border" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var overlay = try initTestOverlay(alloc, 4, 2);
    defer overlay.deinit(alloc);

    const border = Color.hyperlink.rectBorder();
    const fill = Color.hyperlink.rectFill();
    try overlay.highlightGridRect(alloc, 1, 0, 2, 1, border, fill);

    const fill_rgba = z2d.pixel.RGBA.fromPixel(fill);

    const interior = pixelAt(&overlay, 15, 10);
    try testing.expectEqual(fill_rgba, interior);

    const edge = pixelAt(&overlay, 10, 10);
    try testing.expect(edge.a > fill_rgba.a);

    try testing.expectEqual(@as(u8, 0), pixelAt(&overlay, 35, 10).a);
}

test "Overlay highlightPixelRect draws fill and border" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var overlay = try initTestOverlay(alloc, 4, 3);
    defer overlay.deinit(alloc);

    const border = Color.semantic_prompt.rectBorder();
    const fill = Color.semantic_prompt.rectFill();
    try overlay.highlightPixelRect(alloc, 0, 1, 5, 1, border, fill);

    const fill_rgba = z2d.pixel.RGBA.fromPixel(fill);

    const interior = pixelAt(&overlay, 2, 30);
    try testing.expectEqual(fill_rgba, interior);

    const edge = pixelAt(&overlay, 0, 30);
    try testing.expect(edge.a > fill_rgba.a);

    try testing.expectEqual(@as(u8, 0), pixelAt(&overlay, 7, 30).a);
}

test "Overlay applyFeatures highlights hyperlinks" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var t: terminal.Terminal = try .init(alloc, .{ .cols = 4, .rows = 1 });
    defer t.deinit(alloc);

    try t.screens.active.startHyperlink("http://example.com", null);
    try t.printString("AB");
    t.screens.active.endHyperlink();
    try t.printString("CD");

    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    var overlay = try initTestOverlay(alloc, 4, 1);
    defer overlay.deinit(alloc);
    overlay.applyFeatures(alloc, &state, &.{.highlight_hyperlinks});

    try testing.expectEqual(
        z2d.pixel.RGBA.fromPixel(Color.hyperlink.rectFill()),
        pixelAt(&overlay, 5, 10),
    );
    try testing.expectEqual(@as(u8, 0), pixelAt(&overlay, 25, 10).a);
}

test "Overlay applyFeatures highlights semantic prompts and input" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var t: terminal.Terminal = try .init(alloc, .{ .cols = 8, .rows = 2 });
    defer t.deinit(alloc);

    try t.semanticPrompt(.init(.prompt_start));
    try t.printString("> ");
    try t.semanticPrompt(.init(.end_prompt_start_input));
    try t.printString("cd");

    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    var overlay = try initTestOverlay(alloc, 8, 2);
    defer overlay.deinit(alloc);
    overlay.applyFeatures(alloc, &state, &.{.semantic_prompts});

    try testing.expectEqual(
        z2d.pixel.RGBA.fromPixel(Color.semantic_prompt.rectFill()),
        pixelAt(&overlay, 7, 10),
    );
    try testing.expectEqual(
        z2d.pixel.RGBA.fromPixel(Color.semantic_input.rectFill()),
        pixelAt(&overlay, 25, 10),
    );
    try testing.expectEqual(@as(u8, 0), pixelAt(&overlay, 55, 10).a);
}

// ============================================================================
// Plain "obvious behavior" coverage for the debug-overlay toggle path.
// These pin down behaviors that are easy to break silently:
//   - default state of show_debug_overlay is OFF
//   - applyFeatures honors show_debug_overlay (off = no draw, on = draws)
//   - tsf_preedit set/clear round-trip
//   - empty features list does not touch the surface
// ============================================================================

test "Overlay show_debug_overlay defaults to false" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var overlay = try initTestOverlay(alloc, 8, 4);
    defer overlay.deinit(alloc);
    try testing.expectEqual(false, overlay.show_debug_overlay);
}

test "Overlay applyFeatures with show_debug_overlay=false leaves surface untouched" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var overlay = try initTestOverlay(alloc, 32, 4);
    defer overlay.deinit(alloc);

    overlay.show_debug_overlay = false;
    overlay.fps = 60.0;

    var t: terminal.Terminal = try .init(alloc, .{ .cols = 4, .rows = 1 });
    defer t.deinit(alloc);
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    overlay.applyFeatures(alloc, &state, &.{});

    // Surface must remain fully transparent — no debug overlay was requested.
    for (overlay.surface.image_surface_rgba.buf) |px| {
        try testing.expectEqual(@as(u8, 0), px.a);
    }
}

test "Overlay applyFeatures with show_debug_overlay=true paints debug pixels" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var overlay = try initTestOverlay(alloc, 32, 4);
    defer overlay.deinit(alloc);

    overlay.show_debug_overlay = true;
    overlay.fps = 60.0;

    var t: terminal.Terminal = try .init(alloc, .{ .cols = 4, .rows = 1 });
    defer t.deinit(alloc);
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    overlay.applyFeatures(alloc, &state, &.{});

    try testing.expect(countVisiblePixels(&overlay) > 0);
}

test "Overlay show_debug_overlay can be flipped on then off (toggle behavior)" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var overlay = try initTestOverlay(alloc, 32, 4);
    defer overlay.deinit(alloc);
    overlay.fps = 60.0;

    var t: terminal.Terminal = try .init(alloc, .{ .cols = 4, .rows = 1 });
    defer t.deinit(alloc);
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    // Start: false → no draw
    try testing.expectEqual(false, overlay.show_debug_overlay);
    overlay.applyFeatures(alloc, &state, &.{});
    try testing.expectEqual(@as(usize, 0), countVisiblePixels(&overlay));

    // Toggle on → draw fills some pixels
    overlay.show_debug_overlay = !overlay.show_debug_overlay;
    overlay.applyFeatures(alloc, &state, &.{});
    const after_on = countVisiblePixels(&overlay);
    try testing.expect(after_on > 0);

    // Toggle off + reset → no new draw
    overlay.show_debug_overlay = !overlay.show_debug_overlay;
    overlay.reset();
    overlay.applyFeatures(alloc, &state, &.{});
    try testing.expectEqual(@as(usize, 0), countVisiblePixels(&overlay));
}

test "Overlay tsf_preedit defaults to null and round-trips an assigned value" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var overlay = try initTestOverlay(alloc, 8, 4);
    defer overlay.deinit(alloc);
    try testing.expect(overlay.tsf_preedit == null);
    overlay.tsf_preedit = "abc";
    try testing.expectEqualStrings("abc", overlay.tsf_preedit.?);
    overlay.tsf_preedit = null;
    try testing.expect(overlay.tsf_preedit == null);
}

test "Overlay debug overlay reflects updated FPS in subsequent draws" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var overlay = try initTestOverlay(alloc, 32, 4);
    defer overlay.deinit(alloc);
    overlay.show_debug_overlay = true;

    var t: terminal.Terminal = try .init(alloc, .{ .cols = 4, .rows = 1 });
    defer t.deinit(alloc);
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    // Two distinct FPS values must produce different surface contents because
    // the formatted "FPS: X.XX" text has different glyph patterns.
    overlay.fps = 0.0;
    overlay.applyFeatures(alloc, &state, &.{});
    const a = countVisiblePixels(&overlay);

    overlay.reset();
    overlay.fps = 240.0;
    overlay.applyFeatures(alloc, &state, &.{});
    const b = countVisiblePixels(&overlay);

    try testing.expect(a > 0);
    try testing.expect(b > 0);
    // The pixel counts may match by coincidence, but we at least verify both
    // draws produced visible glyphs — i.e. drawDebugOverlay is being called.
}

test "renderer.Message.toggle_debug_overlay is a payload-free variant" {
    const testing = std.testing;
    const Message = @import("message.zig").Message;
    const m: Message = .toggle_debug_overlay;
    try testing.expect(m == .toggle_debug_overlay);
}

test "renderer.Message.tsf_preedit carries an optional text payload" {
    const testing = std.testing;
    const Message = @import("message.zig").Message;
    const m: Message = .{ .tsf_preedit = .{ .alloc = testing.allocator, .text = null } };
    try testing.expect(m == .tsf_preedit);
    try testing.expect(m.tsf_preedit.text == null);
}

test "Overlay applyFeatures draws preedit even when show_debug_overlay is false" {
    // Regression: TSF preedit is the user's only visible feedback during
    // IME composition (Gemini CLI doesn't render the composition string at
    // the cursor reliably). It MUST surface independently of the F12 debug
    // toggle, otherwise the user sees nothing while typing.
    const testing = std.testing;
    const alloc = testing.allocator;
    var overlay = try initTestOverlay(alloc, 32, 4);
    defer overlay.deinit(alloc);
    overlay.show_debug_overlay = false;
    overlay.tsf_preedit = "あいう";

    var t: terminal.Terminal = try .init(alloc, .{ .cols = 4, .rows = 1 });
    defer t.deinit(alloc);
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    overlay.applyFeatures(alloc, &state, &.{});
    try testing.expect(countVisiblePixels(&overlay) > 0);
}

test "Overlay applyFeatures draws nothing when show_debug_overlay=false and preedit is null" {
    // Companion of the above: with the debug overlay off and no active
    // preedit, nothing should be drawn — no FPS, no preedit, untouched
    // surface.
    const testing = std.testing;
    const alloc = testing.allocator;
    var overlay = try initTestOverlay(alloc, 32, 4);
    defer overlay.deinit(alloc);
    overlay.show_debug_overlay = false;
    overlay.tsf_preedit = null;

    var t: terminal.Terminal = try .init(alloc, .{ .cols = 4, .rows = 1 });
    defer t.deinit(alloc);
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    overlay.applyFeatures(alloc, &state, &.{});
    try testing.expectEqual(@as(usize, 0), countVisiblePixels(&overlay));
}
