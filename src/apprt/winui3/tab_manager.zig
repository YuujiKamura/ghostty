/// Tab management for winui3 — local copy with correct Surface/App imports.
const std = @import("std");
const configpkg = @import("../../config.zig");
const App = @import("App.zig");
const Surface = @import("Surface.zig").Surface(App);
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const os = @import("os.zig");
const tab_index = @import("tab_index.zig");
const input_runtime = @import("input_runtime.zig");
const surface_binding = @import("surface_binding.zig");
const profiles = @import("profiles.zig"); // Added import for profiles

const log = std.log.scoped(.winui3);

const DeferredSurfaceClose = struct {
    alloc: std.mem.Allocator,
    surface: *Surface,
    had_core_initialized: bool,

    fn run(self: DeferredSurfaceClose) void {
        if (self.had_core_initialized) {
            self.surface.app.core_app.deleteSurface(self.surface);
            self.surface.core_surface.deinit();
        }

        self.surface.deinit();
        self.alloc.destroy(self.surface);
    }
};

pub fn closeActiveTab(self: anytype) bool {
    if (self.countSurfaces() == 0) return false;
    return closeTab(self, self.active_surface_idx);
}

pub fn newTab(
    self: anytype,
    comptime tabview_item_class: [:0]const u8,
    initial_tab_title: []const u8,
) !void {
    try newTabWithProfile(self, tabview_item_class, initial_tab_title, null);
}

pub fn newTabWithProfile(
    self: anytype,
    comptime tabview_item_class: [:0]const u8,
    initial_tab_title: []const u8,
    profile_opt: ?profiles.Profile,
) !void {
    const alloc = self.core_app.alloc;
    // Use the cached Config (populated at App.init) to avoid synchronous disk
    // I/O on the UI thread Ctrl+T hot path. Issue #212 P0 #4.
    var config = try self.cloneCachedConfig();
    defer config.deinit();

    var surface = try alloc.create(Surface);
    errdefer alloc.destroy(surface);
    try surface.init(self, self.core_app, &config, profile_opt); // Pass profile_opt
    errdefer surface.deinit();

    // Assign a stable monotonic tab ID.
    surface.tab_id = self.next_tab_id;
    self.next_tab_id += 1;

    {
        self.surfaces_mutex.lock();
        defer self.surfaces_mutex.unlock();
        try self.surfaces.append(alloc, surface);
    }
    try self.updateSurfacesSnapshot();

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

    const hstring_title = try winrt.hstringRuntime(alloc, initial_tab_title); // Use alloc here
    defer winrt.deleteHString(hstring_title);
    var boxed_guard = winrt.ComRef(winrt.IInspectable).init(try self.boxString(hstring_title));
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
    const tab_items_raw = try tab_view.TabItems();
    const tab_items: *com.IVector = @ptrCast(@alignCast(tab_items_raw));
    defer tab_items.release();

    // Guard: suppress onSelectionChanged side effects during mutation (Issue #127).
    self.tab_mutation_in_progress = true;
    defer self.tab_mutation_in_progress = false;

    try tab_items.append(@ptrCast(tvi_inspectable));

    // Store the IInspectable reference on the surface for later title updates.
    surface.tab_view_item_inspectable = tvi_inspectable;

    // Re-apply the initial title through setTabTitle so that the CP tab ID
    // prefix is added when control plane is active.
    if (alloc.dupeZ(u8, initial_tab_title)) |title_z| {
        defer alloc.free(title_z);
        surface.setTabTitle(title_z);
    } else |_| {}

    // Select the new tab and switch content (WT-style Clear+Append).
    const size = try tab_items.getSize();
    const new_idx: usize = @intCast(size - 1);
    try tab_view.SetSelectedIndex(@intCast(new_idx));
    self.active_surface_idx = new_idx;

    // Single authoritative panel switch (no more triple-fire).
    surface_binding.updateSelectedTab(self, new_idx);

    // Keep normal keyboard focus on the XAML surface after tab creation.
    input_runtime.focusKeyboardTarget(self);

    log.info("newTabWithProfile completed: idx={} total={}", .{ self.active_surface_idx, self.surfaces.items.len });
}

pub fn closeTab(self: anytype, idx: usize) bool {
    const surface, const had_core_initialized = blk: {
        self.surfaces_mutex.lock();
        defer self.surfaces_mutex.unlock();

        if (idx >= self.surfaces.items.len) return false;

        const s = self.surfaces.items[idx];
        const hci = s.core_initialized;

        // 1. Remove from the model first.
        _ = self.surfaces.orderedRemove(idx);
        s.core_initialized = false;
        break :blk .{ s, hci };
    };
    self.updateSurfacesSnapshot() catch {};

    // --- LOCK RELEASED HERE ---
    // Now perform heavy XAML/WinRT work without holding surfaces_mutex.

    // 2. Adjust active index before TabView triggers SelectionChanged.
    const current_len = self.countSurfaces();
    if (current_len == 0) {
        // Guard: suppress onSelectionChanged during last-tab removal (Issue #129).
        self.tab_mutation_in_progress = true;
        defer self.tab_mutation_in_progress = false;

        // Remove from TabView last (triggers SelectionChanged with -1).
        if (self.tab_view) |tv| {
            const tab_items_raw = tv.TabItems() catch {
                DeferredSurfaceClose.run(.{
                    .alloc = self.core_app.alloc,
                    .surface = surface,
                    .had_core_initialized = had_core_initialized,
                });
                return true;
            };
            const tab_items: *com.IVector = @ptrCast(@alignCast(tab_items_raw));
            defer tab_items.release();
            tab_items.removeAt(@intCast(idx)) catch {};
        }
        const args = DeferredSurfaceClose{
            .alloc = self.core_app.alloc,
            .surface = surface,
            .had_core_initialized = had_core_initialized,
        };
        var cleanup_thread = std.Thread.spawn(.{}, DeferredSurfaceClose.run, .{args}) catch |err| {
            log.warn("closeTab: async cleanup spawn failed: {}", .{err});
            DeferredSurfaceClose.run(args);
            return true;
        };
        cleanup_thread.detach();
        return true;
    }

    // Clamp active index to valid range.
    if (self.active_surface_idx >= self.surfaces.items.len) {
        self.active_surface_idx = self.surfaces.items.len - 1;
    } else if (idx < self.active_surface_idx) {
        self.active_surface_idx -= 1;
    }

    // 3. Remove from TabView — guard SelectionChanged side effects (Issue #129).
    self.tab_mutation_in_progress = true;
    defer self.tab_mutation_in_progress = false;

    if (self.tab_view) |tv| {
        const tab_items_raw2 = tv.TabItems() catch {
            DeferredSurfaceClose.run(.{
                .alloc = self.core_app.alloc,
                .surface = surface,
                .had_core_initialized = had_core_initialized,
            });
            return false;
        };
        const tab_items: *com.IVector = @ptrCast(@alignCast(tab_items_raw2));
        defer tab_items.release();
        tab_items.removeAt(@intCast(idx)) catch |err| {
            log.warn("closeTab: removeAt({}) failed: {}", .{ idx, err });
        };

        // 4. Force-select the correct tab and swap SwapChainPanel.
        tv.SetSelectedIndex(@intCast(self.active_surface_idx)) catch {};
        surface_binding.updateSelectedTab(self, self.active_surface_idx);

        input_runtime.focusKeyboardTarget(self);
    }

    // 5. Finish teardown off the UI thread. Core shutdown still runs, but the
    //    expensive thread joins no longer block XAML message processing.
    const args2 = DeferredSurfaceClose{
        .alloc = self.core_app.alloc,
        .surface = surface,
        .had_core_initialized = had_core_initialized,
    };
    var cleanup_thread = std.Thread.spawn(.{}, DeferredSurfaceClose.run, .{args2}) catch |err| {
        log.warn("closeTab: async cleanup spawn failed: {}", .{err});
        DeferredSurfaceClose.run(args2);
        return false;
    };
    cleanup_thread.detach();

    log.info("closeTab: closed idx={}, active now={}, total={}", .{ idx, self.active_surface_idx, self.surfaces.items.len });
    return false;
}
