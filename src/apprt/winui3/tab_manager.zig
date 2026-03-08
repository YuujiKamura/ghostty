const std = @import("std");
const configpkg = @import("../../config.zig");
const Surface = @import("Surface.zig");
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const os = @import("os.zig");
const tab_index = @import("tab_index.zig");
const input_runtime = @import("input_runtime.zig");
const surface_binding = @import("surface_binding.zig");

const log = std.log.scoped(.winui3);

pub fn closeActiveTab(self: anytype) bool {
    if (self.surfaces.items.len == 0) return false;
    return closeTab(self, self.active_surface_idx);
}

pub fn newTab(
    self: anytype,
    comptime tabview_item_class: [:0]const u8,
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

    // Sync surface size with actual HWND client area.
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
    try tvi.SetHeader(boxed_guard.get());
    try tvi.SetIsClosable(true);

    // Set dummy Border as TabViewItem.Content (Issue #28: not for rendering, just for drag-drop).
    const border_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Border");
    defer winrt.deleteHString(border_class);
    var border_guard = winrt.ComRef(winrt.IInspectable).init(try winrt.activateInstance(border_class));
    defer border_guard.deinit();
    try surface_binding.setTabItemContent(tvi_inspectable, border_guard.get());

    // Add to TabItems collection.
    const tab_items = try tab_view.TabItems();
    try tab_items.append(@ptrCast(tvi_inspectable));

    // Store the IInspectable reference on the surface for later title updates.
    surface.tab_view_item_inspectable = tvi_inspectable;

    // Select the new tab (this triggers SelectionChanged which swaps panel in tab_content_grid).
    const size = try tab_items.getSize();
    const prev_idx = self.active_surface_idx;
    try tab_view.SetSelectedIndex(@intCast(size - 1));
    self.active_surface_idx = @intCast(size - 1);

    // Swap SwapChainPanel into tab_content_grid.
    self.attachSurfaceToTabItem(if (self.surfaces.items.len > 1) prev_idx else null, self.active_surface_idx) catch |err| {
        log.warn("newTab: attachSurfaceToTabItem({}) failed: {}", .{ self.active_surface_idx, err });
    };

    // Ensure keyboard focus returns to our input overlay.
    input_runtime.focusInputOverlay(self);

    log.info("newTab completed: idx={} total={}", .{ self.active_surface_idx, self.surfaces.items.len });
}

pub fn closeTab(self: anytype, idx: usize) bool {
    if (idx >= self.surfaces.items.len) return false;

    const surface = self.surfaces.items[idx];

    // 1. Cleanup surface FIRST (before removing from TabView, to avoid
    //    onSelectionChanged referencing a stale surface array).
    surface.deinit();
    self.core_app.alloc.destroy(surface);
    _ = self.surfaces.orderedRemove(idx);

    // 2. Adjust active index before TabView triggers SelectionChanged.
    if (self.surfaces.items.len == 0) {
        // Remove from TabView last (triggers SelectionChanged with -1).
        if (self.tab_view) |tv| {
            const tab_items = tv.TabItems() catch return true;
            tab_items.removeAt(@intCast(idx)) catch {};
        }
        return true;
    }

    // Clamp active index to valid range.
    if (self.active_surface_idx >= self.surfaces.items.len) {
        self.active_surface_idx = self.surfaces.items.len - 1;
    } else if (idx < self.active_surface_idx) {
        self.active_surface_idx -= 1;
    }

    // 3. Remove from TabView (triggers onSelectionChanged).
    if (self.tab_view) |tv| {
        const tab_items = tv.TabItems() catch return false;
        tab_items.removeAt(@intCast(idx)) catch |err| {
            log.warn("closeTab: removeAt({}) failed: {}", .{ idx, err });
        };

        // 4. Force-select the correct tab and swap SwapChainPanel.
        tv.SetSelectedIndex(@intCast(self.active_surface_idx)) catch {};
        surface_binding.attachSurfaceToTabItem(self, null, self.active_surface_idx) catch |err| {
            log.warn("closeTab: attachSurfaceToTabItem({}) failed: {}", .{ self.active_surface_idx, err });
        };
        input_runtime.focusInputOverlay(self);
    }

    log.info("closeTab: closed idx={}, active now={}, total={}", .{ idx, self.active_surface_idx, self.surfaces.items.len });
    return false;
}
