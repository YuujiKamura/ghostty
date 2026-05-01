const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const configpkg = @import("../config.zig");
const font = @import("../font/main.zig");
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");

/// The messages that can be sent to a renderer thread.
pub const Message = union(enum) {
    /// Purposely crash the renderer. This is used for testing and debugging.
    /// See the "crash" binding action.
    crash,

    /// A change in state in the window focus that this renderer is
    /// rendering within. This is only sent when a change is detected so
    /// the renderer is expected to handle all of these.
    focus: bool,

    /// A change in the view occlusion state. This can be used to determine
    /// if the window is visible or not. A window can be not visible (occluded)
    /// and still have focus.
    visible: bool,

    /// Reset the cursor blink by immediately showing the cursor then
    /// restarting the timer.
    reset_cursor_blink,

    /// Change the font grid. This can happen for any number of reasons
    /// including a font size change, family change, etc.
    font_grid: struct {
        grid: *font.SharedGrid,
        set: *font.SharedGridSet,

        // The key for the new grid. If adopting the new grid fails for any
        // reason, the old grid should be kept but the new key should be
        // dereferenced.
        new_key: font.SharedGridSet.Key,

        // After accepting the new grid, the old grid must be dereferenced
        // using the fields below.
        old_key: font.SharedGridSet.Key,
    },

    /// Changes the size. The screen size might change, padding, grid, etc.
    resize: renderer.Size,

    /// The derived configuration to update the renderer with.
    change_config: struct {
        alloc: Allocator,
        thread: *renderer.Thread.DerivedConfig,
        impl: *renderer.Renderer.DerivedConfig,
    },

    /// Matches for the current viewport from the search thread. These happen
    /// async so they may be off for a frame or two from the actually rendered
    /// viewport. The renderer must handle this gracefully.
    search_viewport_matches: SearchMatches,

    /// The selected match from the search thread. May be null to indicate
    /// no match currently.
    search_selected_match: ?SearchMatch,

    /// Activate or deactivate the inspector.
    inspector: bool,

    /// Toggle the debug overlay.
    toggle_debug_overlay,

    /// Set the TSF preedit text for the debug overlay.
    tsf_preedit: struct {
        alloc: Allocator,
        text: ?[:0]const u8,
    },

    /// Frame-specific constants (time, FPS, etc.) provided by the UI layer.
    frame_constants: struct {
        time_sec: f32,
        fps: f32,
    },

    /// The macOS display ID has changed for the window.
    macos_display_id: u32,

    pub const SearchMatches = struct {
        arena: ArenaAllocator,
        matches: []const terminal.highlight.Flattened,
    };

    pub const SearchMatch = struct {
        arena: ArenaAllocator,
        match: terminal.highlight.Flattened,
    };

    /// Initialize a change_config message.
    pub fn initChangeConfig(alloc: Allocator, config: *const configpkg.Config) !Message {
        const thread_ptr = try alloc.create(renderer.Thread.DerivedConfig);
        errdefer alloc.destroy(thread_ptr);
        const config_ptr = try alloc.create(renderer.Renderer.DerivedConfig);
        errdefer alloc.destroy(config_ptr);

        thread_ptr.* = renderer.Thread.DerivedConfig.init(config);
        config_ptr.* = try renderer.Renderer.DerivedConfig.init(alloc, config);
        errdefer config_ptr.deinit();

        return .{
            .change_config = .{
                .alloc = alloc,
                .thread = thread_ptr,
                .impl = config_ptr,
            },
        };
    }

    pub fn deinit(self: *const Message) void {
        switch (self.*) {
            .change_config => |v| {
                v.impl.deinit();
                v.alloc.destroy(v.impl);
                v.alloc.destroy(v.thread);
            },

            .tsf_preedit => |v| {
                if (v.text) |text| v.alloc.free(text);
            },

            else => {},
        }
    }
};

test "Message.deinit: tsf_preedit with text frees the duplicated buffer" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const dup = try alloc.dupeZ(u8, "preedit");
    const m: Message = .{ .tsf_preedit = .{ .alloc = alloc, .text = dup } };
    m.deinit(); // must not leak; testing.allocator detects leaks
}

test "Message.deinit: tsf_preedit with null text is a no-op" {
    const testing = std.testing;
    const m: Message = .{ .tsf_preedit = .{ .alloc = testing.allocator, .text = null } };
    m.deinit();
}

test "Message.deinit: payload-free variants are no-ops" {
    const variants = [_]Message{
        .crash,
        .reset_cursor_blink,
        .toggle_debug_overlay,
        .{ .focus = true },
        .{ .visible = false },
        .{ .inspector = true },
        .{ .macos_display_id = 42 },
        .{ .frame_constants = .{ .time_sec = 0.0, .fps = 60.0 } },
    };
    for (variants) |m| m.deinit();
}

test "Message.initChangeConfig: happy path round-trips through deinit without leaks" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try configpkg.Config.default(alloc);
    defer cfg.deinit();

    const m = try Message.initChangeConfig(alloc, &cfg);
    // testing.allocator's leak detector asserts both `thread` and `impl`
    // (plus the arena owned by Renderer.DerivedConfig) are freed by deinit.
    m.deinit();

    // Surface the variant tag so a future refactor can't silently change
    // which message kind initChangeConfig produces.
    try testing.expectEqual(
        @as(std.meta.Tag(Message), .change_config),
        std.meta.activeTag(m),
    );
}

test "Message.initChangeConfig: first allocation failure propagates with no leak" {
    const testing = std.testing;
    var cfg = try configpkg.Config.default(testing.allocator);
    defer cfg.deinit();

    // fail_index = 0 fails the very first allocation
    // (the `thread_ptr = try alloc.create(...)` call). No errdefer has
    // anything to clean up at that point, so this asserts the function
    // cleanly bubbles OutOfMemory without partial state.
    var fail = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(
        error.OutOfMemory,
        Message.initChangeConfig(fail.allocator(), &cfg),
    );
}

test "Message.initChangeConfig: second allocation failure runs errdefer for thread_ptr" {
    const testing = std.testing;
    var cfg = try configpkg.Config.default(testing.allocator);
    defer cfg.deinit();

    // fail_index = 1 lets the first `alloc.create` succeed and fails the
    // second one. The errdefer for `thread_ptr` must fire and free the
    // first allocation; otherwise the FailingAllocator's underlying
    // testing.allocator leak detector trips on teardown.
    var fail = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
    try testing.expectError(
        error.OutOfMemory,
        Message.initChangeConfig(fail.allocator(), &cfg),
    );
}
