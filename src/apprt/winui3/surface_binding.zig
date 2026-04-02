/// Surface binding for winui3 — WT-style Clear+Append tab content switching.
/// Mirrors Windows Terminal's TerminalPage::_UpdatedSelectedTab() pattern.
const std = @import("std");
const App = @import("App.zig");
const Surface = @import("Surface.zig").Surface(App);
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const os = @import("os.zig");

const log = std.log.scoped(.winui3);

pub fn setTabItemContent(tvi_insp: *winrt.IInspectable, content: ?*winrt.IInspectable) !void {
    var cc_guard = winrt.ComRef(com.IContentControl).init(try tvi_insp.queryInterface(com.IContentControl));
    defer cc_guard.deinit();
    const cc = cc_guard.get();
    if (content) |c| {
        try cc.SetContent(c);
    } else {
        try cc.SetContent(@as(?*anyopaque, null));
    }
}

/// WT-style tab content switch: Clear tab_content_grid children, then Append the active tab's panel.
/// This is the direct equivalent of TerminalPage::_UpdatedSelectedTab() in Windows Terminal.
pub fn updateSelectedTab(self: anytype, idx: usize) void {
    if (idx >= self.surfaces.items.len) return;
    const tab_content = self.tab_content_grid orelse return;

    const content_panel = tab_content.queryInterface(com.IPanel) catch |err| {
        log.warn("updateSelectedTab: QI IPanel failed: {}", .{err});
        return;
    };
    defer content_panel.release();
    const children_raw = content_panel.Children() catch |err| {
        log.warn("updateSelectedTab: Children() failed: {}", .{err});
        return;
    };
    // Same @ptrCast as App.zig initXaml step 8 (line 954) — proven to work for append/clear.
    const children: *com.IVector = @ptrCast(@alignCast(children_raw));
    defer children.release();

    // WT pattern: Clear + Append (not Visibility toggling)
    children.clear() catch |err| {
        log.warn("updateSelectedTab: clear() failed: {}", .{err});
        return;
    };

    const surface = self.surfaces.items[idx];
    const panel: *winrt.IInspectable = surface.surface_grid orelse surface.swap_chain_panel orelse {
        log.warn("updateSelectedTab: idx={} has no panel", .{idx});
        return;
    };
    children.append(@ptrCast(panel)) catch |err| {
        log.warn("updateSelectedTab: append() failed: {}", .{err});
        return;
    };

    // Re-bind swap chain — entering the visual tree may require compositor re-attachment.
    surface.rebindSwapChain();

    log.info("updateSelectedTab: idx={} panel=0x{x}", .{ idx, @intFromPtr(panel) });
}

/// Ensure the currently active surface's panel is displayed.
/// Called from Surface.onLoaded() when a SwapChainPanel enters the visual tree.
pub fn ensureVisibleSurfaceAttached(self: anytype, surface: *Surface) void {
    if (self.tab_view == null) return;
    for (self.surfaces.items, 0..) |s, i| {
        if (s == surface and i == self.active_surface_idx) {
            updateSelectedTab(self, i);
            return;
        }
    }
}
