/// Surface binding for winui3 — local copy with correct Surface type.
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

/// Helper: set Visibility on a panel (IInspectable → IUIElement).
fn setPanelVisibility(panel: *winrt.IInspectable, visibility: i32) void {
    const ue = panel.queryInterface(com.IUIElement) catch |err| {
        log.warn("setPanelVisibility: QI IUIElement failed: {}", .{err});
        return;
    };
    defer ue.release();
    ue.SetVisibility(visibility) catch |err| {
        log.warn("setPanelVisibility: SetVisibility({}) failed: {}", .{ visibility, err });
    };
}

/// Swap the visible SwapChainPanel in tab_content_grid on tab switch.
/// Instead of removing/adding children (which invalidates swap chains),
/// keep ALL surface panels in the grid and toggle Visibility.
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

    const content_panel = try tab_content.queryInterface(com.IPanel);
    defer content_panel.release();
    const children_raw = try content_panel.Children();
    const children: *com.IVector = @ptrCast(@alignCast(children_raw));
    defer children.release();

    // Ensure the active panel is in the grid (add if not already present).
    // IVector.indexOf (com_native) returns !?u32 — null means not found.
    const already_in_grid = children.indexOf(@ptrCast(panel)) catch null;
    if (already_in_grid == null) {
        try children.append(@ptrCast(panel));
    }

    // Collapse all panels, then make the active one visible.
    // Visibility values: 0 = Visible, 1 = Collapsed.
    for (self.surfaces.items) |s| {
        const p: *winrt.IInspectable = s.surface_grid orelse s.swap_chain_panel orelse continue;
        setPanelVisibility(p, 1); // Collapsed
    }
    setPanelVisibility(panel, 0); // Visible

    // Re-bind swap chain after Visible restore — Collapsed may have detached
    // the panel from the compositor, invalidating the DXGI surface (Issue #128).
    surface.rebindSwapChain();

    log.info("attachSurfaceToTabItem: idx={} panel=0x{x} made Visible + rebind in tab_content_grid", .{ idx, @intFromPtr(panel) });
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

    // Check that active surface's panel is present in the grid and Visible.
    // IVector.indexOf (com_native) returns !?u32 — null means not found.
    const found = (children2.indexOf(@ptrCast(panel)) catch null) != null;
    const ue = panel.queryInterface(com.IUIElement) catch null;
    const vis: i32 = if (ue) |u| blk: {
        defer u.release();
        break :blk u.Visibility() catch -1;
    } else -1;
    const size = children2.getSize() catch 0;

    log.info(
        "auditActiveTabBinding: active_idx={} panel=0x{x} in_grid={} visibility={} total_children={}",
        .{ self.active_surface_idx, @intFromPtr(panel), found, vis, size },
    );
}
