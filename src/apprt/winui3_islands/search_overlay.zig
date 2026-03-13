/// WinUI 3 Islands Search Overlay for Ghostty.
/// Implements the floating search box (typically Ctrl+F) using XAML controls.
/// Local copy for winui3_islands — uses the local Surface/App types.
const std = @import("std");
const App = @import("App.zig");
const Surface = @import("Surface.zig");
const com = @import("../winui3/com.zig");
const winrt = @import("../winui3/winrt.zig");
const os = @import("../winui3/os.zig");

const log = std.log.scoped(.winui3_search);

pub const SearchOverlay = struct {
    surface: *Surface,
    container: ?*com.IUIElement = null, // Floating container (Canvas or Grid)
    text_box: ?*com.ITextBox = null,    // The actual input box

    pub fn init(surface: *Surface) !SearchOverlay {
        return SearchOverlay{
            .surface = surface,
        };
    }

    pub fn deinit(self: *SearchOverlay) void {
        if (self.text_box) |tb| _ = tb.release();
        if (self.container) |c| _ = c.release();
    }

    /// Show the search overlay.
    pub fn show(self: *SearchOverlay) !void {
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
    pub fn hide(self: *SearchOverlay) void {
        log.info("SearchOverlay.hide", .{});
        self.deinit();
        self.container = null;
        self.text_box = null;
    }
};
