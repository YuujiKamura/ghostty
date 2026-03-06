const std = @import("std");
const com = @import("com.zig");
const native_interop = @import("native_interop.zig");

const log = std.log.scoped(.winui3);

pub fn createRoot(self: anytype, window: *com.IWindow, comptime tabview_class_name: [:0]const u8) !?*com.ITabView {
    return if (self.debug_cfg.enable_tabview) blk: {
        log.info("initXaml step 7.5: Creating TabView via XAML type system...", .{});
        const tv_inspectable = self.activateXamlType(tabview_class_name) catch |err| {
            log.err("TabView creation failed ({}), fail-fast because tabview is enabled", .{err});
            return err;
        };
        const tv = tv_inspectable.queryInterface(com.ITabView) catch |err| {
            log.err("TabView QI for ITabView failed ({}), fail-fast because tabview is enabled", .{err});
            return err;
        };

        self.setControlBackground(@ptrCast(tv_inspectable), .{ .a = 255, .r = 0, .g = 0, .b = 0 });

        // Force TabView to stretch and fill the window.
        if (tv_inspectable.queryInterface(com.IFrameworkElement)) |fe| {
            defer fe.release();
        } else |_| {}

        window.putContent(@ptrCast(tv_inspectable)) catch |err| {
            log.err("TabView putContent failed ({}), fail-fast because tabview is enabled", .{err});
            _ = tv.release();
            return err;
        };

        log.info("initXaml step 7.5 OK: TabView set as Window content", .{});
        break :blk tv;
    } else blk: {
        log.info("initXaml step 7.5: SKIPPED (GHOSTTY_WINUI3_ENABLE_TABVIEW=false)", .{});
        break :blk null;
    };
}

pub fn configureDefaults(tab_view: ?*com.ITabView) void {
    if (tab_view) |tv| {
        if (tv.queryInterface(native_interop.ITabView2)) |tv2| {
            defer tv2.release();
            tv2.putCanReorderTabs(true) catch {};
            tv2.putCanDragTabs(true) catch {};
            tv2.putTabWidthMode(.equal) catch {};
        } else |_| {}
    }
}
