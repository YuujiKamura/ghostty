const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = @import("../quirks.zig").inlineAssert;
const wuffs = @import("wuffs");
const terminal = @import("../terminal/main.zig");

const Renderer = @import("../renderer.zig").Renderer;
const GraphicsAPI = Renderer.API;
const Texture = GraphicsAPI.Texture;
const CellSize = @import("size.zig").CellSize;
const Overlay = @import("Overlay.zig");

const log = std.log.scoped(.renderer_image);

/// Generic image rendering state for the renderer. This stores all
/// images and their placements and exposes only a limited public API
/// for adding images and placements and drawing them.
pub const State = struct {
    /// The full image state for the renderer that specifies what images
    /// need to be uploaded, pruned, etc.
    images: ImageMap,

    /// The placements for the Kitty image protocol.
    kitty_placements: std.ArrayListUnmanaged(Placement),

    /// The end index (exclusive) for placements that should be
    /// drawn below the background, below the text, etc.
    kitty_bg_end: u32,
    kitty_text_end: u32,

    /// True if there are any virtual placements. This needs to be known
    /// because virtual placements need to be recalculated more often
    /// on frame builds and are generally more expensive to handle.
    kitty_virtual: bool,

    /// Overlays
    overlay_placements: std.ArrayListUnmanaged(Placement),

    pub const empty: State = .{
        .images = .empty,
        .kitty_placements = .empty,
        .kitty_bg_end = 0,
        .kitty_text_end = 0,
        .kitty_virtual = false,
        .overlay_placements = .empty,
    };

    pub fn deinit(self: *State, alloc: Allocator) void {
        {
            var it = self.images.iterator();
            while (it.next()) |kv| kv.value_ptr.image.deinit(alloc);
            self.images.deinit(alloc);
        }
        self.kitty_placements.deinit(alloc);
        self.overlay_placements.deinit(alloc);
    }

    /// Upload any images to the GPU that need to be uploaded,
    /// and remove any images that are no longer needed on the GPU.
    ///
    /// If any uploads fail, they are ignored. The return value
    /// can be used to detect if upload was a total success (true)
    /// or not (false).
    pub fn upload(
        self: *State,
        alloc: Allocator,
        api: *GraphicsAPI,
    ) bool {
        var success: bool = true;
        var image_it = self.images.iterator();
        while (image_it.next()) |kv| {
            const img = &kv.value_ptr.image;
            if (img.isUnloading()) {
                img.deinit(alloc);
                self.images.removeByPtr(kv.key_ptr);
                continue;
            }

            if (img.isPending()) {
                img.upload(
                    alloc,
                    api,
                ) catch |err| {
                    log.warn("error uploading image to GPU err={}", .{err});
                    success = false;
                };
            }
        }

        return success;
    }

    pub const DrawPlacements = enum {
        kitty_below_bg,
        kitty_below_text,
        kitty_above_text,
        overlay,
    };

    /// Draw the given named set of placements.
    ///
    /// Any placements that have non-uploaded images are ignored. Any
    /// graphics API errors during drawing are also ignored.
    ///
    /// `sampler` is used by the image pixel shader to sample the texture. If
    /// none is provided, the GPU falls back to its default sampler — which
    /// works but emits a `DEVICE_DRAW_SAMPLER_NOT_SET` D3D11 debug warning
    /// and shouldn't be relied on.
    pub fn draw(
        self: *State,
        api: *GraphicsAPI,
        pipeline: GraphicsAPI.Pipeline,
        pass: *GraphicsAPI.RenderPass,
        placement_type: DrawPlacements,
        sampler: ?GraphicsAPI.Sampler,
    ) void {
        const placements: []const Placement = switch (placement_type) {
            .kitty_below_bg => self.kitty_placements.items[0..self.kitty_bg_end],
            .kitty_below_text => self.kitty_placements.items[self.kitty_bg_end..self.kitty_text_end],
            .kitty_above_text => self.kitty_placements.items[self.kitty_text_end..],
            .overlay => self.overlay_placements.items,
        };

        for (placements) |p| {
            // Look up the image
            const image = self.images.get(p.image_id) orelse {
                log.warn("image not found for placement image_id={}", .{p.image_id});
                continue;
            };

            // Get the texture
            const texture = switch (image.image) {
                .ready,
                .unload_ready,
                => |t| t,
                else => {
                    log.warn("image not ready for placement image_id={}", .{p.image_id});
                    continue;
                },
            };

            // Create our vertex buffer, which is always exactly one item.
            // future(mitchellh): we can group rendering multiple instances of a single image
            var buf = GraphicsAPI.Buffer(GraphicsAPI.shaders.Image).initFill(
                api.imageBufferOptions(),
                &.{.{
                    .grid_pos = .{
                        @as(f32, @floatFromInt(p.x)),
                        @as(f32, @floatFromInt(p.y)),
                    },

                    .cell_offset = .{
                        @as(f32, @floatFromInt(p.cell_offset_x)),
                        @as(f32, @floatFromInt(p.cell_offset_y)),
                    },

                    .source_rect = .{
                        @as(f32, @floatFromInt(p.source_x)),
                        @as(f32, @floatFromInt(p.source_y)),
                        @as(f32, @floatFromInt(p.source_width)),
                        @as(f32, @floatFromInt(p.source_height)),
                    },

                    .dest_size = .{
                        @as(f32, @floatFromInt(p.width)),
                        @as(f32, @floatFromInt(p.height)),
                    },
                }},
            ) catch |err| {
                log.warn("error creating image vertex buffer err={}", .{err});
                continue;
            };
            defer buf.deinit();

            pass.step(.{
                .pipeline = pipeline,
                .buffers = &.{buf.buffer},
                .textures = &.{texture},
                .samplers = &.{sampler},
                .draw = .{
                    .type = .triangle_strip,
                    .vertex_count = 4,
                },
            });
        }
    }

    /// Update our overlay state. Null value deletes any existing overlay.
    pub fn overlayUpdate(
        self: *State,
        alloc: Allocator,
        overlay_: ?Overlay,
    ) !void {
        const overlay = overlay_ orelse {
            // If we don't have an overlay, remove any existing one.
            if (self.images.getPtr(.overlay)) |data| {
                data.image.markForUnload();
            }
            return;
        };

        // For transmit time we always just use the current time
        // and overwrite the overlay.
        const transmit_time = try std.time.Instant.now();

        // Ensure we have space for our overlay placement. Do this before
        // we upload our image so we don't have to deal with cleaning
        // that up.
        self.overlay_placements.clearRetainingCapacity();
        try self.overlay_placements.ensureUnusedCapacity(alloc, 1);

        // Setup our image.
        const pending = overlay.pendingImage();
        try self.prepImage(
            alloc,
            .overlay,
            transmit_time,
            pending,
        );
        errdefer comptime unreachable;

        // Setup our placement
        self.overlay_placements.appendAssumeCapacity(.{
            .image_id = .overlay,
            .x = 0,
            .y = 0,
            .z = 0,
            .width = pending.width,
            .height = pending.height,
            .cell_offset_x = 0,
            .cell_offset_y = 0,
            .source_x = 0,
            .source_y = 0,
            .source_width = pending.width,
            .source_height = pending.height,
        });
    }

    /// Returns true if the Kitty graphics state requires an update based
    /// on the terminal state and our internal state.
    ///
    /// This does not read/write state used by drawing.
    pub fn kittyRequiresUpdate(
        self: *const State,
        t: *const terminal.Terminal,
    ) bool {
        // If the terminal kitty image state is dirty, we must update.
        if (t.screens.active.kitty_images.dirty) return true;

        // If we have any virtual references, we must also rebuild our
        // kitty state on every frame because any cell change can move
        // an image. If the virtual placements were removed, this will
        // be set to false on the next update.
        if (self.kitty_virtual) return true;

        return false;
    }

    /// Update the Kitty graphics state from the terminal.
    ///
    /// This reads/writes state used by drawing.
    pub fn kittyUpdate(
        self: *State,
        alloc: Allocator,
        t: *const terminal.Terminal,
        cell_size: CellSize,
    ) void {
        const storage = &t.screens.active.kitty_images;
        defer storage.dirty = false;

        // We always clear our previous placements no matter what because
        // we rebuild them from scratch.
        self.kitty_placements.clearRetainingCapacity();
        self.kitty_virtual = false;

        // Go through our known images and if there are any that are no longer
        // in use then mark them to be freed.
        //
        // This never conflicts with the below because a placement can't
        // reference an image that doesn't exist.
        {
            var it = self.images.iterator();
            while (it.next()) |kv| {
                switch (kv.key_ptr.*) {
                    // We're only looking at Kitty images
                    .kitty => |id| if (storage.imageById(id) == null) {
                        kv.value_ptr.image.markForUnload();
                    },

                    .overlay => {},
                }
            }
        }

        // The top-left and bottom-right corners of our viewport in screen
        // points. This lets us determine offsets and containment of placements.
        const top = t.screens.active.pages.getTopLeft(.viewport);
        const bot = t.screens.active.pages.getBottomRight(.viewport).?;
        const top_y = t.screens.active.pages.pointFromPin(.screen, top).?.screen.y;
        const bot_y = t.screens.active.pages.pointFromPin(.screen, bot).?.screen.y;

        // Go through the placements and ensure the image is
        // on the GPU or else is ready to be sent to the GPU.
        var it = storage.placements.iterator();
        while (it.next()) |kv| {
            const p = kv.value_ptr;

            // Special logic based on location
            switch (p.location) {
                .pin => {},
                .virtual => {
                    // We need to mark virtual placements on our renderer so that
                    // we know to rebuild in more scenarios since cell changes can
                    // now trigger placement changes.
                    self.kitty_virtual = true;

                    // We also continue out because virtual placements are
                    // only triggered by the unicode placeholder, not by the
                    // placement itself.
                    continue;
                },
            }

            // Get the image for the placement
            const image = storage.imageById(kv.key_ptr.image_id) orelse {
                log.warn(
                    "missing image for placement, ignoring image_id={}",
                    .{kv.key_ptr.image_id},
                );
                continue;
            };

            self.prepKittyPlacement(
                alloc,
                t,
                top_y,
                bot_y,
                &image,
                p,
            ) catch |err| {
                // For errors we log and continue. We try to place
                // other placements even if one fails.
                log.warn("error preparing kitty placement err={}", .{err});
            };
        }

        // If we have virtual placements then we need to scan for placeholders.
        if (self.kitty_virtual) {
            var v_it = terminal.kitty.graphics.unicode.placementIterator(top, bot);
            while (v_it.next()) |virtual_p| {
                self.prepKittyVirtualPlacement(
                    alloc,
                    t,
                    &virtual_p,
                    cell_size,
                ) catch |err| {
                    // For errors we log and continue. We try to place
                    // other placements even if one fails.
                    log.warn("error preparing kitty placement err={}", .{err});
                };
            }
        }

        // Sort the placements by their Z value.
        std.mem.sortUnstable(
            Placement,
            self.kitty_placements.items,
            {},
            struct {
                fn lessThan(
                    ctx: void,
                    lhs: Placement,
                    rhs: Placement,
                ) bool {
                    _ = ctx;
                    return lhs.z < rhs.z or
                        (lhs.z == rhs.z and lhs.image_id.zLessThan(rhs.image_id));
                }
            }.lessThan,
        );

        // Find our indices. The values are sorted by z so we can
        // find the first placement out of bounds to find the limits.
        const bg_limit = std.math.minInt(i32) / 2;
        var bg_end: ?u32 = null;
        var text_end: ?u32 = null;
        for (self.kitty_placements.items, 0..) |p, i| {
            if (bg_end == null and p.z >= bg_limit) bg_end = @intCast(i);
            if (text_end == null and p.z >= 0) text_end = @intCast(i);
        }

        // If we didn't see any images with a z > the bg limit,
        // then our bg end is the end of our placement list.
        self.kitty_bg_end =
            bg_end orelse @intCast(self.kitty_placements.items.len);
        // Same idea for the image_text_end.
        self.kitty_text_end =
            text_end orelse @intCast(self.kitty_placements.items.len);
    }

    const PrepImageError = error{
        OutOfMemory,
        ImageConversionError,
    };

    /// Get the viewport-relative position for this
    /// placement and add it to the placements list.
    fn prepKittyPlacement(
        self: *State,
        alloc: Allocator,
        t: *const terminal.Terminal,
        top_y: u32,
        bot_y: u32,
        image: *const terminal.kitty.graphics.Image,
        p: *const terminal.kitty.graphics.ImageStorage.Placement,
    ) PrepImageError!void {
        // Get the rect for the placement. If this placement doesn't have
        // a rect then its virtual or something so skip it.
        const rect = p.rect(image.*, t) orelse return;

        // This is expensive but necessary.
        const img_top_y = t.screens.active.pages.pointFromPin(.screen, rect.top_left).?.screen.y;
        const img_bot_y = t.screens.active.pages.pointFromPin(.screen, rect.bottom_right).?.screen.y;

        // If the selection isn't within our viewport then skip it.
        if (img_top_y > bot_y) return;
        if (img_bot_y < top_y) return;

        // We need to prep this image for upload if it isn't in the
        // cache OR it is in the cache but the transmit time doesn't
        // match meaning this image is different.
        try self.prepKittyImage(alloc, image);

        // Calculate the dimensions of our image, taking in to
        // account the rows / columns specified by the placement.
        const dest_size = p.pixelSize(image.*, t);

        // Calculate the source rectangle
        const source_x = @min(image.width, p.source_x);
        const source_y = @min(image.height, p.source_y);
        const source_width = if (p.source_width > 0)
            @min(image.width - source_x, p.source_width)
        else
            image.width;
        const source_height = if (p.source_height > 0)
            @min(image.height - source_y, p.source_height)
        else
            image.height;

        // Get the viewport-relative Y position of the placement.
        const y_pos: i32 = @as(i32, @intCast(img_top_y)) - @as(i32, @intCast(top_y));

        // Accumulate the placement
        if (dest_size.width > 0 and dest_size.height > 0) {
            try self.kitty_placements.append(alloc, .{
                .image_id = .{ .kitty = image.id },
                .x = @intCast(rect.top_left.x),
                .y = y_pos,
                .z = p.z,
                .width = dest_size.width,
                .height = dest_size.height,
                .cell_offset_x = p.x_offset,
                .cell_offset_y = p.y_offset,
                .source_x = source_x,
                .source_y = source_y,
                .source_width = source_width,
                .source_height = source_height,
            });
        }
    }

    fn prepKittyVirtualPlacement(
        self: *State,
        alloc: Allocator,
        t: *const terminal.Terminal,
        p: *const terminal.kitty.graphics.unicode.Placement,
        cell_size: CellSize,
    ) PrepImageError!void {
        const storage = &t.screens.active.kitty_images;
        const image = storage.imageById(p.image_id) orelse {
            log.warn(
                "missing image for virtual placement, ignoring image_id={}",
                .{p.image_id},
            );
            return;
        };

        const rp = p.renderPlacement(
            storage,
            &image,
            cell_size.width,
            cell_size.height,
        ) catch |err| {
            log.warn("error rendering virtual placement err={}", .{err});
            return;
        };

        // If our placement is zero sized then we don't do anything.
        if (rp.dest_width == 0 or rp.dest_height == 0) return;

        const viewport: terminal.point.Point = t.screens.active.pages.pointFromPin(
            .viewport,
            rp.top_left,
        ) orelse {
            // This is unreachable with virtual placements because we should
            // only ever be looking at virtual placements that are in our
            // viewport in the renderer and virtual placements only ever take
            // up one row.
            unreachable;
        };

        // Prepare the image for the GPU and store the placement.
        try self.prepKittyImage(alloc, &image);
        try self.kitty_placements.append(alloc, .{
            .image_id = .{ .kitty = image.id },
            .x = @intCast(rp.top_left.x),
            .y = @intCast(viewport.viewport.y),
            .z = -1,
            .width = rp.dest_width,
            .height = rp.dest_height,
            .cell_offset_x = rp.offset_x,
            .cell_offset_y = rp.offset_y,
            .source_x = rp.source_x,
            .source_y = rp.source_y,
            .source_width = rp.source_width,
            .source_height = rp.source_height,
        });
    }

    /// Prepare an image for upload to the GPU.
    fn prepImage(
        self: *State,
        alloc: Allocator,
        id: Id,
        transmit_time: std.time.Instant,
        pending: Image.Pending,
    ) PrepImageError!void {
        // If this image exists and its transmit time is the same we assume
        // it is the identical image so we don't need to send it to the GPU.
        const gop = try self.images.getOrPut(alloc, id);
        if (gop.found_existing and
            gop.value_ptr.transmit_time.order(transmit_time) == .eq)
        {
            return;
        }

        // Copy the data so we own it.
        const data = if (alloc.dupe(
            u8,
            pending.dataSlice(),
        )) |v| v else |_| {
            if (!gop.found_existing) {
                // If this is a new entry we can just remove it since it
                // was never sent to the GPU.
                _ = self.images.remove(id);
            } else {
                // If this was an existing entry, it is invalid and
                // we must unload it.
                gop.value_ptr.image.markForUnload();
            }

            return error.OutOfMemory;
        };
        // Note: we don't need to errdefer free the data because it is
        // put into the map immediately below and our errdefer to
        // handle our map state will fix this up.

        // Store it in the map
        const new_image: Image = .{
            .pending = .{
                .width = pending.width,
                .height = pending.height,
                .pixel_format = pending.pixel_format,
                .data = data.ptr,
            },
        };
        if (!gop.found_existing) {
            gop.value_ptr.* = .{
                .image = new_image,
                .transmit_time = undefined,
            };
        } else {
            gop.value_ptr.image.markForReplace(
                alloc,
                new_image,
            );
        }

        // If any error happens, we unload the image and it is invalid.
        errdefer gop.value_ptr.image.markForUnload();

        gop.value_ptr.image.prepForUpload(alloc) catch |err| {
            log.warn("error preparing image for upload err={}", .{err});
            return error.ImageConversionError;
        };
        gop.value_ptr.transmit_time = transmit_time;
    }

    /// Prepare the provided Kitty image for upload to the GPU by copying its
    /// data with our allocator and setting it to the pending state.
    fn prepKittyImage(
        self: *State,
        alloc: Allocator,
        image: *const terminal.kitty.graphics.Image,
    ) PrepImageError!void {
        try self.prepImage(
            alloc,
            .{ .kitty = image.id },
            image.transmit_time,
            .{
                .width = image.width,
                .height = image.height,
                .pixel_format = switch (image.format) {
                    .gray => .gray,
                    .gray_alpha => .gray_alpha,
                    .rgb => .rgb,
                    .rgba => .rgba,
                    .png => unreachable, // should be decoded by now
                },

                // constCasts are always gross but this one is safe is because
                // the data is only read from here and copied into its own
                // buffer.
                .data = @constCast(image.data.ptr),
            },
        );
    }
};

/// Represents a single image placement on the grid.
/// A placement is a request to render an instance of an image.
pub const Placement = struct {
    /// The image being rendered. This MUST be in the image map.
    image_id: Id,

    /// The grid x/y where this placement is located.
    x: i32,
    y: i32,
    z: i32,

    /// The width/height of the placed image.
    width: u32,
    height: u32,

    /// The offset in pixels from the top left of the cell.
    /// This is clamped to the size of a cell.
    cell_offset_x: u32,
    cell_offset_y: u32,

    /// The source rectangle of the placement.
    source_x: u32,
    source_y: u32,
    source_width: u32,
    source_height: u32,
};

/// Image identifier used to store and lookup images.
///
/// This is tagged by different image types to make it easier to
/// store different kinds of images in the same map without having
/// to worry about ID collisions.
pub const Id = union(enum) {
    /// Image sent to the terminal state via the kitty graphics protocol.
    /// The value is the ID assigned by the terminal.
    kitty: u32,

    /// Debug overlay. This is always composited down to a single
    /// image for now. In the future we can support layers here if we want.
    overlay,

    /// Z-ordering tie-breaker for images with the same z value.
    pub fn zLessThan(lhs: Id, rhs: Id) bool {
        // If our tags aren't the same, we sort by tag.
        if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) {
            return switch (lhs) {
                // Kitty images always sort before (lower z) non-kitty images.
                .kitty => true,

                .overlay => false,
            };
        }

        switch (lhs) {
            .kitty => |lhs_id| {
                const rhs_id = rhs.kitty;
                return lhs_id < rhs_id;
            },

            // No sensical ordering
            .overlay => return false,
        }
    }
};

/// The map used for storing images.
pub const ImageMap = std.AutoHashMapUnmanaged(Id, struct {
    image: Image,
    transmit_time: std.time.Instant,
});

/// The state for a single image that is to be rendered.
pub const Image = union(enum) {
    /// The image data is pending upload to the GPU.
    ///
    /// This data is owned by this union so it must be freed once uploaded.
    pending: Pending,

    /// This is the same as the pending states but there is
    /// a texture already allocated that we want to replace.
    replace: Replace,

    /// The image is uploaded and ready to be used.
    ready: Texture,

    /// The image isn't uploaded yet but is scheduled to be unloaded.
    unload_pending: Pending,
    /// The image is uploaded and is scheduled to be unloaded.
    unload_ready: Texture,
    /// The image is uploaded and scheduled to be replaced
    /// with new data, but it's also scheduled to be unloaded.
    unload_replace: Replace,

    pub const Replace = struct {
        texture: Texture,
        pending: Pending,
    };

    /// Pending image data that needs to be uploaded to the GPU.
    pub const Pending = struct {
        height: u32,
        width: u32,
        pixel_format: PixelFormat,

        /// Data is always expected to be (width * height * bpp).
        data: [*]u8,

        pub fn dataSlice(self: Pending) []u8 {
            return self.data[0..self.len()];
        }

        pub fn len(self: Pending) usize {
            return self.width * self.height * self.pixel_format.bpp();
        }

        pub const PixelFormat = enum {
            /// 1 byte per pixel grayscale.
            gray,
            /// 2 bytes per pixel grayscale + alpha.
            gray_alpha,
            /// 3 bytes per pixel RGB.
            rgb,
            /// 3 bytes per pixel BGR.
            bgr,
            /// 4 byte per pixel RGBA.
            rgba,
            /// 4 byte per pixel BGRA.
            bgra,

            /// Get bytes per pixel for this format.
            pub inline fn bpp(self: PixelFormat) usize {
                return switch (self) {
                    .gray => 1,
                    .gray_alpha => 2,
                    .rgb => 3,
                    .bgr => 3,
                    .rgba => 4,
                    .bgra => 4,
                };
            }
        };
    };

    pub fn deinit(self: Image, alloc: Allocator) void {
        switch (self) {
            .pending,
            .unload_pending,
            => |p| alloc.free(p.dataSlice()),

            .replace, .unload_replace => |r| {
                alloc.free(r.pending.dataSlice());
                r.texture.deinit();
            },

            .ready,
            .unload_ready,
            => |t| t.deinit(),
        }
    }

    /// Mark this image for unload whatever state it is in.
    pub fn markForUnload(self: *Image) void {
        self.* = switch (self.*) {
            .unload_pending,
            .unload_replace,
            .unload_ready,
            => return,

            .ready => |t| .{ .unload_ready = t },
            .pending => |p| .{ .unload_pending = p },
            .replace => |r| .{ .unload_replace = r },
        };
    }

    /// Mark the current image to be replaced with a pending one. This will
    /// attempt to update the existing texture if we have one, otherwise it
    /// will act like a new upload.
    pub fn markForReplace(self: *Image, alloc: Allocator, img: Image) void {
        assert(img.isPending());

        // If we have pending data right now, free it.
        if (self.getPending()) |p| {
            alloc.free(p.dataSlice());
        }
        // If we have an existing texture, use it in the replace.
        if (self.getTexture()) |t| {
            self.* = .{ .replace = .{
                .texture = t,
                .pending = img.getPending().?,
            } };
            return;
        }
        // Otherwise we just become a pending image.
        self.* = .{ .pending = img.getPending().? };
    }

    /// Returns true if this image is pending upload.
    pub fn isPending(self: Image) bool {
        return self.getPending() != null;
    }

    /// Returns true if this image has an associated texture.
    pub fn hasTexture(self: Image) bool {
        return self.getTexture() != null;
    }

    /// Returns true if this image is marked for unload.
    pub fn isUnloading(self: Image) bool {
        return switch (self) {
            .unload_pending,
            .unload_replace,
            .unload_ready,
            => true,

            .pending,
            .replace,
            .ready,
            => false,
        };
    }

    /// Converts the image data to a format that can be uploaded to the GPU.
    /// If the data is already in a format that can be uploaded, this is a
    /// no-op.
    fn convert(self: *Image, alloc: Allocator) wuffs.Error!void {
        const p = self.getPendingPointer().?;
        // As things stand, we currently convert all images to RGBA before
        // uploading to the GPU. This just makes things easier. In the future
        // we may want to support other formats.
        if (p.pixel_format == .rgba) return;
        // If the pending data isn't RGBA we'll need to swizzle it.
        const data = p.dataSlice();
        const rgba = try switch (p.pixel_format) {
            .gray => wuffs.swizzle.gToRgba(alloc, data),
            .gray_alpha => wuffs.swizzle.gaToRgba(alloc, data),
            .rgb => wuffs.swizzle.rgbToRgba(alloc, data),
            .bgr => wuffs.swizzle.bgrToRgba(alloc, data),
            .rgba => unreachable,
            .bgra => wuffs.swizzle.bgraToRgba(alloc, data),
        };
        alloc.free(data);
        p.data = rgba.ptr;
        p.pixel_format = .rgba;
    }

    /// Prepare the pending image data for upload to the GPU.
    /// This doesn't need GPU access so is safe to call any time.
    fn prepForUpload(self: *Image, alloc: Allocator) wuffs.Error!void {
        assert(self.isPending());
        try self.convert(alloc);
    }

    /// Upload the pending image to the GPU and change the state of this
    /// image to ready.
    pub fn upload(
        self: *Image,
        alloc: Allocator,
        api: *const GraphicsAPI,
    ) (wuffs.Error || error{
        /// Texture creation failed, usually a GPU memory issue.
        UploadFailed,
    })!void {
        assert(self.isPending());

        // No error recover is required after this call because it just
        // converts in place and is idempotent.
        try self.prepForUpload(alloc);

        // Get our pending info
        const p = self.getPending().?;

        // Create our texture
        const texture = Texture.init(
            api.imageTextureOptions(.rgba, true),
            @intCast(p.width),
            @intCast(p.height),
            p.dataSlice(),
        ) catch return error.UploadFailed;
        errdefer comptime unreachable;

        // Uploaded. We can now clear our data and change our state.
        //
        // NOTE: For the `replace` state, this will free the old texture.
        //       We don't currently actually replace the existing texture
        //       in-place but that is an optimization we can do later.
        self.deinit(alloc);
        self.* = .{ .ready = texture };
    }

    /// Returns any pending image data for this image that requires upload.
    ///
    /// If there is no pending data to upload, returns null.
    fn getPending(self: Image) ?Pending {
        return switch (self) {
            .pending,
            .unload_pending,
            => |p| p,

            .replace,
            .unload_replace,
            => |r| r.pending,

            else => null,
        };
    }

    /// Returns the texture for this image.
    ///
    /// If there is no texture for it yet, returns null.
    fn getTexture(self: Image) ?Texture {
        return switch (self) {
            .ready,
            .unload_ready,
            => |t| t,

            .replace,
            .unload_replace,
            => |r| r.texture,

            else => null,
        };
    }

    // Same as getPending but returns a pointer instead of a copy.
    fn getPendingPointer(self: *Image) ?*Pending {
        return switch (self.*) {
            .pending => return &self.pending,
            .unload_pending => return &self.unload_pending,

            .replace => return &self.replace.pending,
            .unload_replace => return &self.unload_replace.pending,

            else => null,
        };
    }
};

// ============================================================================
// Pipeline diagnostic tests for image .overlay.
//
// These tests fence off each stage of the image pipeline that runs on the
// CPU side. The on-screen overlay is invisible despite a known-good z2d
// surface (verified by writing PNG dumps), so we instrument every stage
// and compare against expected byte-for-byte / value-for-value behavior.
// Anything returning weird values is the suspect.
// ============================================================================

const testing = std.testing;

test "Image.Pending.PixelFormat.bpp matches expected byte counts" {
    try testing.expectEqual(@as(usize, 1), Image.Pending.PixelFormat.gray.bpp());
    try testing.expectEqual(@as(usize, 2), Image.Pending.PixelFormat.gray_alpha.bpp());
    try testing.expectEqual(@as(usize, 3), Image.Pending.PixelFormat.rgb.bpp());
    try testing.expectEqual(@as(usize, 3), Image.Pending.PixelFormat.bgr.bpp());
    try testing.expectEqual(@as(usize, 4), Image.Pending.PixelFormat.rgba.bpp());
    try testing.expectEqual(@as(usize, 4), Image.Pending.PixelFormat.bgra.bpp());
}

test "Image.Pending.len is width * height * bpp" {
    var buf: [16]u8 = undefined;
    const p: Image.Pending = .{
        .height = 4,
        .width = 1,
        .pixel_format = .rgba,
        .data = &buf,
    };
    try testing.expectEqual(@as(usize, 16), p.len());
    try testing.expectEqual(@as(usize, 16), p.dataSlice().len);
}

test "Image.Pending.dataSlice points at provided buffer" {
    var buf = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    const p: Image.Pending = .{
        .height = 1,
        .width = 1,
        .pixel_format = .rgba,
        .data = &buf,
    };
    try testing.expectEqualSlices(u8, &buf, p.dataSlice());
    try testing.expectEqual(@intFromPtr(&buf[0]), @intFromPtr(p.dataSlice().ptr));
}

test "Image.Id ordering keeps overlay separate from kitty" {
    // zLessThan: kitty < overlay; same-tag kitty IDs ordered numerically.
    try testing.expect(!Id.zLessThan(.overlay, .overlay));
    try testing.expect(Id.zLessThan(.{ .kitty = 1 }, .{ .kitty = 2 }));
    try testing.expect(Id.zLessThan(.{ .kitty = 5 }, .overlay));
    try testing.expect(!Id.zLessThan(.overlay, .{ .kitty = 1 }));
}

test "State.overlayUpdate(null) when nothing exists is a no-op" {
    var s: State = .empty;
    defer s.deinit(testing.allocator);
    try s.overlayUpdate(testing.allocator, null);
    try testing.expectEqual(@as(usize, 0), s.overlay_placements.items.len);
    try testing.expect(s.images.get(.overlay) == null);
}

test "State.overlayUpdate stores image data byte-for-byte in image map" {
    var s: State = .empty;
    defer s.deinit(testing.allocator);

    const sz = @import("size.zig").Size{
        .screen = .{ .width = 8, .height = 4 },
        .cell = .{ .width = 4, .height = 4 },
        .padding = .{},
    };
    var overlay = try Overlay.init(testing.allocator, sz);
    defer overlay.deinit(testing.allocator);

    // Paint a recognizable pattern into the surface buffer.
    const buf = overlay.surface.image_surface_rgba.buf;
    for (buf, 0..) |*px, i| {
        const v: u8 = @intCast(i & 0xFF);
        px.* = .{ .r = v, .g = v +% 1, .b = v +% 2, .a = v +% 3 };
    }
    const expected_first_4 = [_]u8{ buf[0].r, buf[0].g, buf[0].b, buf[0].a };

    try s.overlayUpdate(testing.allocator, overlay);

    const entry = s.images.get(.overlay) orelse return error.TestFailed;
    // The image must own its own copy of the bytes (alloc.dupe). It can be in
    // either pending or replace state depending on whether this is a first
    // upload, but in both cases data should match the surface input.
    const stored_data = switch (entry.image) {
        .pending => |p| p.dataSlice(),
        .replace => |r| r.pending.dataSlice(),
        else => return error.TestFailed,
    };
    try testing.expectEqualSlices(u8, &expected_first_4, stored_data[0..4]);
    try testing.expectEqual(buf.len * 4, stored_data.len);
}

test "State.overlayUpdate creates a single full-surface placement" {
    var s: State = .empty;
    defer s.deinit(testing.allocator);

    const sz = @import("size.zig").Size{
        .screen = .{ .width = 80, .height = 60 },
        .cell = .{ .width = 10, .height = 20 },
        .padding = .{},
    };
    var overlay = try Overlay.init(testing.allocator, sz);
    defer overlay.deinit(testing.allocator);

    try s.overlayUpdate(testing.allocator, overlay);

    try testing.expectEqual(@as(usize, 1), s.overlay_placements.items.len);
    const p = s.overlay_placements.items[0];
    try testing.expectEqual(Id.overlay, p.image_id);
    try testing.expectEqual(@as(i32, 0), p.x);
    try testing.expectEqual(@as(i32, 0), p.y);
    try testing.expectEqual(@as(u32, 0), p.cell_offset_x);
    try testing.expectEqual(@as(u32, 0), p.cell_offset_y);
    // The placement covers the full surface (terminal area, not the screen with padding).
    const term = sz.terminal();
    try testing.expectEqual(@as(u32, term.width), p.width);
    try testing.expectEqual(@as(u32, term.height), p.height);
    try testing.expectEqual(p.width, p.source_width);
    try testing.expectEqual(p.height, p.source_height);

    // Image was registered.
    try testing.expect(s.images.get(.overlay) != null);
}

test "Color.debug_text rgba is opaque pure green" {
    const c = Overlay.Color.debug_text.rgba();
    try testing.expectEqual(@as(u8, 0), c.r);
    try testing.expectEqual(@as(u8, 255), c.g);
    try testing.expectEqual(@as(u8, 0), c.b);
    try testing.expectEqual(@as(u8, 255), c.a);
}

test "Color.debug_text.pixel asPixel round-trip preserves color" {
    const p = Overlay.Color.debug_text.pixel();
    const back = @import("z2d").pixel.RGBA.fromPixel(p);
    try testing.expectEqual(@as(u8, 0), back.r);
    try testing.expectEqual(@as(u8, 255), back.g);
    try testing.expectEqual(@as(u8, 0), back.b);
    try testing.expectEqual(@as(u8, 255), back.a);
}

test "Overlay.init produces a fully transparent surface" {
    const sz = @import("size.zig").Size{
        .screen = .{ .width = 16, .height = 8 },
        .cell = .{ .width = 4, .height = 4 },
        .padding = .{},
    };
    var overlay = try Overlay.init(testing.allocator, sz);
    defer overlay.deinit(testing.allocator);

    for (overlay.surface.image_surface_rgba.buf) |px| {
        try testing.expectEqual(@as(u8, 0), px.r);
        try testing.expectEqual(@as(u8, 0), px.g);
        try testing.expectEqual(@as(u8, 0), px.b);
        try testing.expectEqual(@as(u8, 0), px.a);
    }
}

test "Overlay.init populates debug_font as a usable z2d Font" {
    const sz = @import("size.zig").Size{
        .screen = .{ .width = 16, .height = 8 },
        .cell = .{ .width = 4, .height = 4 },
        .padding = .{},
    };
    var overlay = try Overlay.init(testing.allocator, sz);
    defer overlay.deinit(testing.allocator);
    // The font must not be a zeroed/invalid handle; loadBuffer succeeded if init
    // returned (it's `catch unreachable`), so simply touch a property to prove it.
    // The mere ability to compile & call this without crash is the assertion.
    _ = overlay.debug_font;
}

test "shader_data.Image vertex struct layout: size, alignment, field offsets" {
    const ShaderImage = @import("shader_data.zig").Image;
    // For D3D11 InputLayout to read PER_INSTANCE_DATA correctly, the struct
    // must be extern with deterministic offsets and a stride that's a multiple
    // of the largest alignment.
    try testing.expectEqual(@as(usize, 0), @offsetOf(ShaderImage, "grid_pos"));
    try testing.expectEqual(@as(usize, 8), @offsetOf(ShaderImage, "cell_offset"));
    try testing.expectEqual(@as(usize, 16), @offsetOf(ShaderImage, "source_rect"));
    try testing.expectEqual(@as(usize, 32), @offsetOf(ShaderImage, "dest_size"));
    // align(16) on source_rect forces the struct alignment to 16, so the total
    // size must be a multiple of 16. dest_size ends at 32+8=40, so size=48.
    try testing.expectEqual(@as(usize, 16), @alignOf(ShaderImage));
    try testing.expectEqual(@as(usize, 48), @sizeOf(ShaderImage));
}

test "shader_data.Image: round-trip through bytes preserves field values" {
    const ShaderImage = @import("shader_data.zig").Image;
    const original: ShaderImage = .{
        .grid_pos = .{ 1.0, 2.0 },
        .cell_offset = .{ 3.0, 4.0 },
        .source_rect = .{ 5.0, 6.0, 7.0, 8.0 },
        .dest_size = .{ 1240.0, 904.0 },
    };
    const bytes = std.mem.asBytes(&original);
    const restored: *const ShaderImage = std.mem.bytesAsValue(ShaderImage, bytes);
    try testing.expectEqual(original.grid_pos, restored.grid_pos);
    try testing.expectEqual(original.cell_offset, restored.cell_offset);
    try testing.expectEqual(original.source_rect, restored.source_rect);
    try testing.expectEqual(original.dest_size, restored.dest_size);
}

test "Overlay.pendingImage byte layout matches Pending.rgba expectations" {
    const sz = @import("size.zig").Size{
        .screen = .{ .width = 8, .height = 4 },
        .cell = .{ .width = 4, .height = 4 },
        .padding = .{},
    };
    var overlay = try Overlay.init(testing.allocator, sz);
    defer overlay.deinit(testing.allocator);

    const p = overlay.pendingImage();
    try testing.expectEqual(Image.Pending.PixelFormat.rgba, p.pixel_format);
    try testing.expectEqual(@as(u32, 8), p.width);
    try testing.expectEqual(@as(u32, 4), p.height);
    try testing.expectEqual(@as(usize, 8 * 4 * 4), p.len());

    // The data pointer must point at the z2d surface buffer with the
    // exact layout {r,g,b,a, r,g,b,a, ...}.
    const buf = overlay.surface.image_surface_rgba.buf;
    try testing.expectEqual(@intFromPtr(buf.ptr), @intFromPtr(p.data));

    // Mutate the surface and verify the bytes are visible through Pending.
    buf[0] = .{ .r = 0xAB, .g = 0xCD, .b = 0xEF, .a = 0x12 };
    const ds = p.dataSlice();
    try testing.expectEqual(@as(u8, 0xAB), ds[0]);
    try testing.expectEqual(@as(u8, 0xCD), ds[1]);
    try testing.expectEqual(@as(u8, 0xEF), ds[2]);
    try testing.expectEqual(@as(u8, 0x12), ds[3]);
}
