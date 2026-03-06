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
        try cc.putContent(@ptrCast(c));
    } else {
        try cc.putContent(null);
    }
}

pub fn attachSurfaceToTabItem(self: anytype, prev_idx_opt: ?usize, idx: usize) !void {
    if (self.tab_view == null) return;
    if (idx >= self.surfaces.items.len) return;

    // Detach previous tab content back to a placeholder.
    if (prev_idx_opt) |prev_idx| if (prev_idx < self.surfaces.items.len and prev_idx != idx) {
        const prev_surface = self.surfaces.items[prev_idx];
        if (prev_surface.tab_view_item_inspectable) |prev_tvi| {
            const placeholder_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Border");
            defer winrt.deleteHString(placeholder_class);
            var placeholder_guard = winrt.ComRef(winrt.IInspectable).init(try winrt.activateInstance(placeholder_class));
            defer placeholder_guard.deinit();
            setTabItemContent(prev_tvi, placeholder_guard.get()) catch {};
        }
    };

    const surface = self.surfaces.items[idx];
    const tvi_insp = surface.tab_view_item_inspectable orelse return;
    const panel = surface.swap_chain_panel orelse return;

    // Ensure the panel fills the tab content area.
    if (panel.queryInterface(com.IFrameworkElement)) |fe| {
        var fe_guard = winrt.ComRef(com.IFrameworkElement).init(fe);
        defer fe_guard.deinit();
    } else |_| {}

    log.info("attachSurfaceToTabItem: idx={} panel=0x{x}", .{ idx, @intFromPtr(panel) });
    try setTabItemContent(tvi_insp, panel);
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

pub fn verifyTabItemHasContent(content_control: *com.IContentControl) !bool {
    const current = try content_control.getContent();
    if (current) |insp| {
        var insp_guard = winrt.ComRef(winrt.IInspectable).init(insp);
        defer insp_guard.deinit();
        return true;
    }
    return false;
}

pub fn auditActiveTabBinding(self: anytype) void {
    if (self.active_surface_idx >= self.surfaces.items.len) return;
    const s = self.surfaces.items[self.active_surface_idx];
    const tvi = s.tab_view_item_inspectable orelse return;
    const panel = s.swap_chain_panel orelse return;
    var cc_guard = winrt.ComRef(com.IContentControl).init(tvi.queryInterface(com.IContentControl) catch return);
    defer cc_guard.deinit();
    const cur = cc_guard.get().getContent() catch return;
    if (cur) |c| {
        var c_guard = winrt.ComRef(winrt.IInspectable).init(@as(*winrt.IInspectable, @ptrCast(c)));
        defer c_guard.deinit();
        log.info(
            "auditActiveTabBinding: idx={} content=0x{x} panel=0x{x} match={}",
            .{ self.active_surface_idx, @intFromPtr(c), @intFromPtr(panel), @intFromPtr(c) == @intFromPtr(panel) },
        );
    } else {
        log.warn("auditActiveTabBinding: idx={} content=null panel=0x{x}", .{ self.active_surface_idx, @intFromPtr(panel) });
    }
}
