/// TabView runtime for XAML Islands — creates the RootGrid layout with TabView.
///
/// Adapted from winui3/tabview_runtime.zig for the XAML Islands architecture.
/// Key difference: uses IDesktopWindowXamlSource.setContent() instead of IWindow.SetContent()
/// to set the root XAML element on the XAML Islands host.
///
/// Layout:
///   RootGrid (2-row Grid, set as XamlSource.Content)
///     +-- Row 0 (40px): TabView (tab strip only)
///     +-- Row 1 (Star): TabContent Grid (SwapChainPanel swapped on SelectionChanged)
const std = @import("std");
const com = @import("../winui3/com.zig");
const winrt = @import("../winui3/winrt.zig");

const log = std.log.scoped(.winui3_islands);
const App = @import("App.zig");
const profiles = @import("profiles.zig"); // Import profiles.zig
const fileLog = App.fileLog;

/// Creates the RootGrid layout with TabView in Row 0 and TabContent Grid in Row 1.
/// Returns the ITabView pointer (owned by caller) or null if TabView is disabled.
///
/// Unlike winui3/tabview_runtime.zig which takes *com.IWindow, this version takes
/// *com.IDesktopWindowXamlSource and uses setContent() to attach the root element.
pub fn createRoot(
    self: anytype,
    xaml_source: *com.IDesktopWindowXamlSource,
    comptime tabview_class_name: [:0]const u8,
) !?*com.ITabView {
    _ = tabview_class_name;
    if (!self.debug_cfg.enable_tabview) {
        fileLog("initXaml step 7.5: SKIPPED (GHOSTTY_WINUI3_ENABLE_TABVIEW=false)", .{});
        return null;
    }

    fileLog("initXaml step 7.5: Creating RootGrid + TabView from TabViewRoot.xbf (Issue #28 architecture)...", .{});

    // 1. Create the RootGrid. XAML tree takes ownership via setContent.
    const root_grid_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.Grid");
    defer winrt.deleteHString(root_grid_class);
    const root_grid_insp = try winrt.activateInstance(root_grid_class);
    defer _ = root_grid_insp.release(); // setContent AddRef's; release our local ref.

    // 2. Load TabViewRoot.xbf into the RootGrid.
    {
        const app_class = try winrt.hstring("Microsoft.UI.Xaml.Application");
        defer winrt.deleteHString(app_class);
        const app_statics = try winrt.getActivationFactory(com.IApplicationStatics, app_class);
        defer app_statics.release();

        const uri_class = try winrt.hstring("Windows.Foundation.Uri");
        defer winrt.deleteHString(uri_class);
        const uri_factory = try winrt.getActivationFactory(com.IUriRuntimeClassFactory, uri_class);
        defer uri_factory.release();

        // Use ms-appx:/// with .xaml extension — framework resolves to .xbf internally.
        // Requires ghostty.pri (resources.pri) with correct resource map.
        const uri_str = try winrt.hstring("ms-appx:///TabViewRoot.xaml");
        defer winrt.deleteHString(uri_str);
        const uri = try uri_factory.createUri(uri_str);
        defer uri.release();

        try app_statics.loadComponent(@ptrCast(root_grid_insp), @ptrCast(uri));
        fileLog("initXaml step 7.5: TabViewRoot.xbf loaded into RootGrid", .{});
    }

    // Set dark gray background on the RootGrid (RGB 32,32,32 matches WinUI3 dark theme;
    // pure black makes the TabView AddButton "+" icon invisible).
    self.setControlBackground(root_grid_insp, .{ .A = 255, .R = 32, .G = 32, .B = 32 });

    // 3. Find named elements in the loaded XAML.
    const root_fe = try root_grid_insp.queryInterface(com.IFrameworkElement);
    defer root_fe.release();

    const tv_name = try winrt.hstring("TabView");
    defer winrt.deleteHString(tv_name);
    const tv_inspectable = try root_fe.FindName(tv_name);
    defer _ = tv_inspectable.release();

    const tv = try tv_inspectable.queryInterface(com.ITabView);
    // tv is returned to caller.

    const tc_name = try winrt.hstring("TabContentGrid");
    defer winrt.deleteHString(tc_name);
    const tab_content_insp = try root_fe.FindName(tc_name);
    const tab_content_winrt: *winrt.IInspectable = @ptrCast(tab_content_insp);

    self.setControlBackground(tab_content_winrt, .{ .A = 255, .R = 32, .G = 32, .B = 32 });

    // Store the tab_content_grid on the App for later use.
    self.tab_content_grid = tab_content_winrt;

    fileLog("initXaml step 7.5: Found TabView and TabContentGrid via FindName", .{});

    // Find AddTabSplitButton
    const spltbtn_name = try winrt.hstring("AddTabSplitButton");
    defer winrt.deleteHString(spltbtn_name);
    const spltbtn_inspectable = try root_fe.FindName(spltbtn_name);
    defer _ = spltbtn_inspectable.release();
    self.add_tab_split_button = try spltbtn_inspectable.queryInterface(com.ISplitButton);
    log.info("initXaml step 7.5: Found AddTabSplitButton", .{});

    // Find ProfileFlyout
    const proflyout_name = try winrt.hstring("ProfileFlyout");
    defer winrt.deleteHString(proflyout_name); // Corrected from prof_name
    const proflyout_inspectable = try root_fe.FindName(proflyout_name);
    defer _ = proflyout_inspectable.release();
    self.profile_menu_flyout = try proflyout_inspectable.queryInterface(com.IMenuFlyout);
    log.info("initXaml step 7.5: Found ProfileFlyout", .{});

    // 4. Set RootGrid as XamlSource content (XAML Islands: setContent instead of Window.SetContent).
    xaml_source.setContent(@ptrCast(root_grid_insp)) catch |err| {
        fileLog("RootGrid setContent failed ({}), fail-fast because tabview is enabled", .{err});
        _ = tv.release();
        return err;
    };

    // Store root grid reference for explicit sizing on WM_SIZE (Windows Terminal pattern).
    _ = root_grid_insp.addRef();
    self.root_grid = root_grid_insp;

    fileLog("initXaml step 7.5 OK: RootGrid set as XamlSource content (TabView Row 0, TabContent Row 1)", .{});

    // SetTitleBar is NOT used — NonClientIslandWindow owns the drag-bar child
    // input sink directly, matching Windows Terminal's structure.

    // Explicitly hide the default AddTabButton, as we are using a custom SplitButton.
    tv.SetIsAddTabButtonVisible(false) catch {};

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
