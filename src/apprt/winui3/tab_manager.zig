const std = @import("std");
const configpkg = @import("../../config.zig");
const Surface = @import("Surface.zig");
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const os = @import("os.zig");
const tab_index = @import("tab_index.zig");
const input_runtime = @import("input_runtime.zig");

const log = std.log.scoped(.winui3);

pub fn closeActiveTab(self: anytype) bool {
    if (self.surfaces.items.len == 0) return false;
    return closeTab(self, self.active_surface_idx);
}

pub fn newTab(
    self: anytype,
    tabview_item_class: []const u8,
    border_class_name: []const u8,
    initial_tab_title: []const u8,
) !void {
    const alloc = self.core_app.alloc;
    var config = try configpkg.Config.load(alloc);
    defer config.deinit();

    var surface = try alloc.create(Surface);
    errdefer alloc.destroy(surface);
    try surface.init(self, self.core_app, &config);
    errdefer surface.deinit();

    try self.surfaces.append(alloc, surface);
    errdefer _ = self.surfaces.pop();

    // Sync surface size with actual HWND client area (same fix as initXaml step 8).
    if (self.hwnd) |hwnd| {
        var rect: os.RECT = .{};
        _ = os.GetClientRect(hwnd, &rect);
        const w: u32 = @intCast(@max(1, rect.right - rect.left));
        const h: u32 = @intCast(@max(1, rect.bottom - rect.top));
        if (w > 0 and h > 0) surface.updateSize(w, h);
    }

    // Create TabViewItem and add to TabView.
    const tab_view = self.tab_view orelse return error.AppInitFailed;
    const tvi_inspectable = try self.activateXamlType(tabview_item_class);
    var tvi_guard = winrt.ComRef(com.ITabViewItem).init(try tvi_inspectable.queryInterface(com.ITabViewItem));
    defer tvi_guard.deinit();
    const tvi = tvi_guard.get();

    const initial_title = try winrt.hstringRuntime(self.core_app.alloc, initial_tab_title);
    defer winrt.deleteHString(initial_title);
    var boxed_guard = winrt.ComRef(winrt.IInspectable).init(try self.boxString(initial_title));
    defer boxed_guard.deinit();
    const boxed_title = boxed_guard.get();
    try tvi.putHeader(@ptrCast(boxed_title));
    try tvi.putIsClosable(false);

    // Set placeholder content on tab item. Active panel is attached on selection.
    var content_control_guard = winrt.ComRef(com.IContentControl).init(try tvi_inspectable.queryInterface(com.IContentControl));
    defer content_control_guard.deinit();
    const content_control = content_control_guard.get();
    const placeholder_class = try winrt.hstring(border_class_name);
    defer winrt.deleteHString(placeholder_class);
    var placeholder_guard = winrt.ComRef(winrt.IInspectable).init(try winrt.activateInstance(placeholder_class));
    defer placeholder_guard.deinit();
    const placeholder = placeholder_guard.get();
    try content_control.putContent(@ptrCast(placeholder));

    // Add to TabItems collection.
    const tab_items = try tab_view.getTabItems();
    try tab_items.append(@ptrCast(tvi_inspectable));

    // Store the IInspectable reference on the surface for later title updates.
    surface.tab_view_item_inspectable = tvi_inspectable;

    // Select the new tab.
    const size = try tab_items.getSize();
    try tab_view.putSelectedIndex(@intCast(size - 1));
    self.active_surface_idx = @intCast(size - 1);
    self.attachSurfaceToTabItem(if (self.surfaces.items.len > 1) self.active_surface_idx - 1 else null, self.active_surface_idx) catch |err| {
        log.warn("newTab: attachSurfaceToTabItem({}) failed: {}", .{ self.active_surface_idx, err });
    };

    // Ensure keyboard focus returns to our input overlay.
    input_runtime.focusInputOverlay(self);

    log.info("newTab completed: idx={} total={}", .{ self.active_surface_idx, self.surfaces.items.len });
}

pub fn closeTab(self: anytype, idx: usize) bool {
    if (idx >= self.surfaces.items.len) return false;

    const surface = self.surfaces.items[idx];

    // Remove from TabView.
    if (self.tab_view) |tv| {
        const tab_items = tv.getTabItems() catch |err| {
            log.warn("closeTab: getTabItems failed: {}", .{err});
            return false;
        };
        tab_items.removeAt(@intCast(idx)) catch |err| {
            log.warn("closeTab: removeAt({}) failed: {}", .{ idx, err });
        };
    }

    // Cleanup surface.
    surface.deinit();
    self.core_app.alloc.destroy(surface);
    _ = self.surfaces.orderedRemove(idx);

    // Adjust active index and report whether this closed the final tab.
    if (self.surfaces.items.len == 0) {
        return true;
    } else if (tab_index.clampActiveIndex(self.active_surface_idx, self.surfaces.items.len)) |clamped| {
        self.active_surface_idx = clamped;
    }
    return false;
}
