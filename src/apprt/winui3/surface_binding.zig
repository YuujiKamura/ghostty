const std = @import("std");
const Surface = @import("Surface.zig");
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

/// Swap the SwapChainPanel in tab_content_grid on tab switch.
/// Issue #28 architecture: tab_content_grid.Children.Clear() + Append(new panel).
pub fn attachSurfaceToTabItem(self: anytype, prev_idx_opt: ?usize, idx: usize) !void {
    if (self.tab_view == null) return;
    if (idx >= self.surfaces.items.len) return;

    // Same tab → nothing to do.
    if (prev_idx_opt) |prev_idx| {
        if (prev_idx == idx) return;
    }

    const surface = self.surfaces.items[idx];
    const panel: *winrt.IInspectable = surface.surface_grid orelse surface.swap_chain_panel orelse return;
    const tab_content = self.tab_content_grid orelse return;

    // Clear current content from tab_content_grid and add the new panel.
    const content_panel = try tab_content.queryInterface(com.IPanel);
    defer content_panel.release();
    const children_raw = try content_panel.Children();
    const children: *com.IVector = @ptrCast(@alignCast(children_raw));
    defer children.release();
    try children.clear();
    try children.append(@ptrCast(panel));

    log.info("attachSurfaceToTabItem: idx={} panel=0x{x} swapped into tab_content_grid", .{ idx, @intFromPtr(panel) });
}

pub fn ensureVisibleSurfaceAttached(self: anytype, surface: *Surface) void {
    if (self.tab_view == null) return;
    for (self.surfaces.items, 0..) |s, i| {
        if (s == surface and i == self.active_surface_idx) {
            attachSurfaceToTabItem(self, null, i) catch |err| {
                log.warn("ensureVisibleSurfaceAttached: attach failed: {}", .{err});
            };
            return;
        }
    }
}

pub fn auditActiveTabBinding(self: anytype) void {
    if (self.active_surface_idx >= self.surfaces.items.len) return;
    const s = self.surfaces.items[self.active_surface_idx];
    const panel: *winrt.IInspectable = s.surface_grid orelse s.swap_chain_panel orelse return;
    const tab_content = self.tab_content_grid orelse return;

    const content_panel = tab_content.queryInterface(com.IPanel) catch return;
    defer content_panel.release();
    const children_raw2 = content_panel.Children() catch return;
    const children2: *com.IVector = @ptrCast(@alignCast(children_raw2));
    defer children2.release();
    const size = children2.getSize() catch return;
    if (size > 0) {
        const first = children2.getAt(0) catch return;
        defer {
            const unk: *com.IUnknown = @ptrCast(@alignCast(first));
            unk.release();
        }
        log.info(
            "auditActiveTabBinding: idx={} tab_content_child=0x{x} panel=0x{x} match={}",
            .{ self.active_surface_idx, @intFromPtr(first), @intFromPtr(panel), @intFromPtr(first) == @intFromPtr(panel) },
        );
    } else {
        log.warn("auditActiveTabBinding: idx={} tab_content_grid has no children", .{self.active_surface_idx});
    }
}
