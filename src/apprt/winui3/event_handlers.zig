const std = @import("std");
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const input_runtime = @import("input_runtime.zig");
const surface_binding = @import("surface_binding.zig");

const log = std.log.scoped(.winui3);

pub fn onTabCloseRequested(self: anytype, _: ?*anyopaque, args_obj: ?*anyopaque) void {
    const args_raw = args_obj orelse {
        log.warn("handler guard: onTabCloseRequested args=null", .{});
        self.closeActiveTab();
        return;
    };
    const args_ptr = @intFromPtr(args_raw);
    log.info("handler enter: onTabCloseRequested args=0x{x}", .{args_ptr});
    if (!com.isValidComPtr(args_ptr)) {
        log.err("handler guard: onTabCloseRequested suspicious args=0x{x}", .{args_ptr});
        return;
    }
    const args: *com.ITabViewTabCloseRequestedEventArgs = @ptrCast(@alignCast(args_raw));
    const tab_insp = args.Tab() catch {
        self.closeActiveTab();
        return;
    };
    var tab_insp_guard = winrt.ComRef(winrt.IInspectable).init(@ptrCast(@alignCast(tab_insp)));
    defer tab_insp_guard.deinit();

    if (self.tab_view) |tv| {
        const tab_items_raw = tv.TabItems() catch {
            self.closeActiveTab();
            return;
        };
        const tab_items_vec: *com.IVector = @ptrCast(@alignCast(tab_items_raw));
        var tab_items_guard = winrt.ComRef(com.IVector).init(tab_items_vec);
        defer tab_items_guard.deinit();

        if (tab_items_guard.get().indexOf(@ptrCast(tab_insp_guard.get())) catch null) |idx| {
            self.closeTab(@intCast(idx));
            return;
        }
    }

    // Fallback if we couldn't resolve the target item.
    self.closeActiveTab();
}

pub fn onAddTabButtonClick(self: anytype, _: ?*anyopaque, _: ?*anyopaque) void {
    log.info("handler enter: onAddTabButtonClick", .{});
    self.newTab() catch |err| {
        log.err("Failed to create new tab: {}", .{err});
    };
}

pub fn onSelectionChanged(self: anytype, sender_obj: ?*anyopaque, args_obj: ?*anyopaque) void {
    const sender_ptr = if (sender_obj) |p| @intFromPtr(p) else @as(usize, 0);
    const args_ptr = if (args_obj) |p| @intFromPtr(p) else @as(usize, 0);
    log.info("handler enter: onSelectionChanged sender=0x{x} args=0x{x}", .{ sender_ptr, args_ptr });
    if (!com.isValidComPtr(sender_ptr) or !com.isValidComPtr(args_ptr)) {
        log.err("handler guard: onSelectionChanged suspicious sender/args sender=0x{x} args=0x{x}", .{ sender_ptr, args_ptr });
        return;
    }
    if (self.tab_view) |tv| {
        const idx = tv.SelectedIndex() catch return;
        if (idx >= 0 and @as(usize, @intCast(idx)) < self.surfaces.items.len) {
            const new_idx: usize = @intCast(idx);
            // Notify old surface it lost focus.
            if (new_idx != self.active_surface_idx) {
                if (self.active_surface_idx < self.surfaces.items.len) {
                    self.surfaces.items[self.active_surface_idx].has_focus = false;
                    self.surfaces.items[self.active_surface_idx].core_surface.focusCallback(false) catch {};
                }
            }
            const old_idx = self.active_surface_idx;
            self.active_surface_idx = new_idx;
            surface_binding.attachSurfaceToTabItem(self, old_idx, new_idx) catch |err| {
                log.warn("onSelectionChanged: attachSurfaceToTabItem({}) failed: {}", .{ new_idx, err });
            };
            surface_binding.auditActiveTabBinding(self);
            // Notify new surface it gained focus.
            self.surfaces.items[new_idx].has_focus = true;
            self.surfaces.items[new_idx].core_surface.focusCallback(true) catch {};
            self.surfaces.items[new_idx].rebindSwapChain();

            // Keep normal keyboard input on the XAML surface. IME focus is
            // redirected to input_hwnd only when composition starts.
            input_runtime.focusKeyboardTarget(self);
        }
    }
}
