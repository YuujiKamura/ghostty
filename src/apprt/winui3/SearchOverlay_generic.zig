//! Unified WinUI 3 Search Overlay implementation for Ghostty.
const std = @import("std");
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const os = @import("os.zig");

const log = std.log.scoped(.winui3_search);

pub fn SearchOverlay(comptime Surface: type) type {
    return struct {
        const Self = @This();

        surface: *Surface,
        container: ?*com.IUIElement = null, // Floating container (Canvas or Grid)
        text_box: ?*com.ITextBox = null,    // The actual input box

        pub fn init(surface: *Surface) !Self {
            return Self{
                .surface = surface,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.text_box) |tb| _ = tb.release();
            if (self.container) |c| _ = c.release();
        }

        /// Show the search overlay.
        pub fn show(self: *Self) !void {
            if (self.container != null) return; // Already showing

            log.info("SearchOverlay.show: Creating search UI", .{});
            
            // 1. Create a TextBox for search input
            const tb_insp = try self.surface.app.activateXamlType("Microsoft.UI.Xaml.Controls.TextBox");
            self.text_box = try tb_insp.queryInterface(com.ITextBox);

            // 2. Wrap in a container (Grid) to position it
            const grid_insp = try self.surface.app.activateXamlType("Microsoft.UI.Xaml.Controls.Grid");
            self.container = try grid_insp.queryInterface(com.IUIElement);

            log.info("SearchOverlay.show: UI elements created (MVP stub)", .{});
        }

        /// Hide the search overlay.
        pub fn hide(self: *Self) void {
            log.info("SearchOverlay.hide", .{});
            self.deinit();
            self.container = null;
            self.text_box = null;
        }
    };
}
