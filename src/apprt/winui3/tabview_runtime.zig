const std = @import("std");
const com = @import("com.zig");
const winrt = @import("winrt.zig");

const log = std.log.scoped(.winui3);

/// Creates the RootGrid layout with TabView in Row 0 and TabContent Grid in Row 1.
/// Returns the ITabView pointer (owned by caller) or null if TabView is disabled.
///
/// Layout:
///   RootGrid (2-row Grid, set as Window.Content)
///     ├─ Row 0 (Auto): TabView (tab strip only)
///     └─ Row 1 (Star): TabContent Grid (SwapChainPanel swapped on SelectionChanged)
pub fn createRoot(
    self: anytype,
    window: *com.IWindow,
    comptime tabview_class_name: [:0]const u8,
) !?*com.ITabView {
    if (!self.debug_cfg.enable_tabview) {
        log.info("initXaml step 7.5: SKIPPED (GHOSTTY_WINUI3_ENABLE_TABVIEW=false)", .{});
        return null;
    }

    log.info("initXaml step 7.5: Creating RootGrid + TabView (Issue #28 architecture)...", .{});

    // 1. Create the RootGrid. XAML tree takes ownership via putContent.
    const root_grid_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Grid");
    defer winrt.deleteHString(root_grid_class);
    const root_grid_insp = try winrt.activateInstance(root_grid_class);
    defer _ = root_grid_insp.release(); // putContent AddRef's; release our local ref.

    // Set black background on the RootGrid.
    self.setControlBackground(root_grid_insp, .{ .A = 255, .R = 0, .G = 0, .B = 0 });

    // 2. Define two rows: Row 0 = Auto (TabView), Row 1 = 1* (content).
    const igrid = try root_grid_insp.queryInterface(com.IGrid);
    defer igrid.release();
    const row_defs_raw = try igrid.RowDefinitions();
    const row_defs: *com.IVector = @ptrCast(@alignCast(row_defs_raw));
    defer row_defs.release();

    const row_def_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.RowDefinition");
    defer winrt.deleteHString(row_def_class);

    // Row 0: Fixed 40px height for TabView tab strip, matching DWM extended titlebar.
    // NOTE: Auto (GridUnitType.Auto) collapses to 0 when the TabView control template
    // has not been fully applied (e.g. missing XamlControlsResources theme resources).
    // Using a fixed Pixel height guarantees the tab strip is always visible.
    {
        const row0_insp = try winrt.activateInstance(row_def_class);
        defer _ = row0_insp.release(); // Collection AddRef's on append.
        const row0 = try row0_insp.queryInterface(com.IRowDefinition);
        defer row0.release();
        try row0.SetHeight(.{ .Value = 40, .GridUnitType = com.GridUnitType.Pixel });
        try row_defs.append(@ptrCast(row0_insp));
    }

    // Row 1: Star (fill remaining space) for content.
    {
        const row1_insp = try winrt.activateInstance(row_def_class);
        defer _ = row1_insp.release(); // Collection AddRef's on append.
        const row1 = try row1_insp.queryInterface(com.IRowDefinition);
        defer row1.release();
        try row1.SetHeight(.{ .Value = 1.0, .GridUnitType = com.GridUnitType.Star });
        try row_defs.append(@ptrCast(row1_insp));
    }

    log.info("initXaml step 7.5: RootGrid created with 2 row definitions", .{});

    // 3. Get IGridStatics for setting Grid.Row attached property.
    const grid_class_for_statics = try winrt.hstring("Microsoft.UI.Xaml.Controls.Grid");
    defer winrt.deleteHString(grid_class_for_statics);
    const grid_statics = try winrt.getActivationFactory(com.IGridStatics, grid_class_for_statics);
    defer grid_statics.release();

    // 4. Create TabView and place in Row 0.
    const tv_inspectable = self.activateXamlType(tabview_class_name) catch |err| {
        log.err("TabView creation failed ({}), fail-fast because tabview is enabled", .{err});
        return err;
    };
    const tv = tv_inspectable.queryInterface(com.ITabView) catch |err| {
        log.err("TabView QI for ITabView failed ({}), fail-fast because tabview is enabled", .{err});
        return err;
    };

    self.setControlBackground(@ptrCast(tv_inspectable), .{ .A = 255, .R = 0, .G = 0, .B = 0 });

    // Ensure TabView stretches to fill its grid cell.
    {
        const tv_fe = try tv_inspectable.queryInterface(com.IFrameworkElement);
        defer tv_fe.release();
        try tv_fe.SetHorizontalAlignment(com.HorizontalAlignment.Stretch);
        try tv_fe.SetVerticalAlignment(com.VerticalAlignment.Stretch);
    }

    // Add TabView to RootGrid children and set Grid.Row = 0.
    const root_panel = try root_grid_insp.queryInterface(com.IPanel);
    defer root_panel.release();
    const root_children_raw = try root_panel.Children();
    const root_children: *com.IVector = @ptrCast(@alignCast(root_children_raw));
    defer root_children.release();
    try root_children.append(@ptrCast(tv_inspectable));
    // Grid.Row defaults to 0, no SetRow needed for TabView.

    log.info("initXaml step 7.5: TabView added to RootGrid Row 0", .{});

    // 5. Create TabContent Grid and place in Row 1.
    const tab_content_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Grid");
    defer winrt.deleteHString(tab_content_class);
    const tab_content_insp = try winrt.activateInstance(tab_content_class);

    self.setControlBackground(tab_content_insp, .{ .A = 255, .R = 0, .G = 0, .B = 0 });

    try root_children.append(@ptrCast(tab_content_insp));

    // Set Grid.Row=1 on tab_content_grid.
    // SetRow ABI requires IFrameworkElement*, not IInspectable*.
    const tab_content_fe = try tab_content_insp.queryInterface(com.IFrameworkElement);
    defer tab_content_fe.release();
    try grid_statics.setRow(@ptrCast(tab_content_fe), 1);
    log.info("initXaml step 7.5: SetRow(tab_content, 1) succeeded", .{});

    // Store the tab_content_grid on the App for later use.
    self.tab_content_grid = tab_content_insp;

    log.info("initXaml step 7.5: TabContent Grid added to RootGrid Row 1", .{});

    // 6. Set RootGrid as Window.Content.
    window.SetContent(@ptrCast(root_grid_insp)) catch |err| {
        log.err("RootGrid putContent failed ({}), fail-fast because tabview is enabled", .{err});
        _ = tv.release();
        return err;
    };

    log.info("initXaml step 7.5 OK: RootGrid set as Window content (TabView Row 0, TabContent Row 1)", .{});

    // 7. SetTitleBar(tabView) — makes the TabView act as the custom title bar.
    // Disabled until ExtendsContentIntoTitleBar is re-enabled.
    // window.setTitleBar(tv_inspectable) catch |err| {
    //     log.warn("initXaml step 7.5: SetTitleBar(TabView) failed: {}", .{err});
    // };
    log.info("initXaml step 7.5: SetTitleBar SKIPPED (pending TabView template fix)", .{});

    return tv;
}

pub fn configureDefaults(tab_view: ?*com.ITabView) void {
    if (tab_view) |tv| {
        tv.SetIsAddTabButtonVisible(true) catch {};
        tv.SetCloseButtonOverlayMode(0) catch {}; // Always = 0, show close button always
        tv.SetCanReorderTabs(true) catch {};
        tv.SetCanDragTabs(true) catch {};
        tv.SetTabWidthMode(0) catch {}; // TabViewWidthMode.Equal = 0
    }
}
