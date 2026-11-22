/// Profile menu population — adds detected shell profiles to the MenuFlyout
/// dropdown next to the add-tab SplitButton.
///
/// Each detected profile (cmd, pwsh, Git Bash, WSL) becomes a MenuFlyoutItem
/// in the flyout. Click handlers will be wired up once IMenuFlyoutItem's
/// event registration is available.
const std = @import("std");
const Allocator = std.mem.Allocator;
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const profiles_mod = @import("profiles.zig");
const gen = @import("com_generated.zig");
const os = @import("os.zig");

const log = std.log.scoped(.winui3);

/// Populate the MenuFlyout with detected shell profiles.
/// Each profile becomes a MenuFlyoutItem with its name as the display text.
///
/// `app` is *App passed as `anytype` to avoid circular import.
/// "再起動してタブを復元" — saves the tabs (Claude / Codex conversations
/// included) and restarts ghostty.exe, e.g. after a rebuild.
fn addRestartItem(alloc: Allocator, items: anytype, app: anytype) !void {
    const App = @typeInfo(@TypeOf(app)).pointer.child;
    const sep_class = try winrt.hstring("Microsoft.UI.Xaml.Controls.MenuFlyoutSeparator");
    defer winrt.deleteHString(sep_class);
    if (winrt.activateInstance(sep_class)) |sep| {
        defer _ = sep.release();
        items.append(@ptrCast(sep)) catch {};
    } else |_| {}

    const class_name = try winrt.hstring("Microsoft.UI.Xaml.Controls.MenuFlyoutItem");
    defer winrt.deleteHString(class_name);
    const item_insp = try winrt.activateInstance(class_name);
    defer _ = item_insp.release();
    const menu_item = try item_insp.queryInterface(com.IMenuFlyoutItem);
    defer menu_item.release();
    const label = try winrt.hstringRuntime(alloc, "再起動してタブを復元");
    defer winrt.deleteHString(label);
    try menu_item.SetText(label);

    const Handler = gen.RoutedEventHandlerImpl(App, *const fn (*App, ?*anyopaque, ?*anyopaque) void);
    const cb = struct {
        fn f(a: *App, _: ?*anyopaque, _: ?*anyopaque) void {
            // Leave the XAML callback before tearing the app down.
            if (a.hwnd) |h| _ = os.PostMessageW(h, os.WM_APP_RESTART_RESTORE, 0, 0);
        }
    }.f;
    const handler = try Handler.createWithIid(alloc, app, &cb, &com.IID_RoutedEventHandler);
    defer handler.release();
    var token: i64 = 0;
    try menu_item.Click(handler.comPtr(), &token);
    try items.append(@ptrCast(item_insp));
    log.info("ProfileMenu: added restart-and-restore item", .{});
}

pub fn populateProfileMenu(
    alloc: Allocator,
    menu_flyout: *com.IMenuFlyout,
    app: anytype,
) !void {
    var detected = try profiles_mod.detectProfiles(alloc);
    defer detected.deinit(alloc);

    const items = try menu_flyout.Items();
    defer items.release();

    for (detected.items) |profile| {
        // 1. Activate a MenuFlyoutItem instance via RoActivateInstance.
        const class_name = try winrt.hstring("Microsoft.UI.Xaml.Controls.MenuFlyoutItem");
        defer winrt.deleteHString(class_name);
        const item_insp = try winrt.activateInstance(class_name);
        defer _ = item_insp.release();

        // 2. QI to IMenuFlyoutItem to access SetText.
        const menu_item = try item_insp.queryInterface(com.IMenuFlyoutItem);
        defer menu_item.release();

        // 3. Set the display text to the profile name.
        //    Profile names are runtime strings, so use hstringRuntime.
        const name_hstr = try winrt.hstringRuntime(alloc, profile.name);
        defer winrt.deleteHString(name_hstr);
        try menu_item.SetText(name_hstr);

        // 4. TODO: Add Click handler (requires RoutedEventHandler delegate for
        //    IMenuFlyoutItem.Click). When wired, clicking the item should call
        //    app.newTab() with the profile's command/path. For now, items are
        //    visible in the flyout but non-functional on click.

        // 5. Append to the MenuFlyout's Items collection.
        //    IVector.append expects ?*anyopaque — cast the IInspectable pointer.
        //    The COM collection internally AddRef's the item, so no manual addRef needed.
        try items.append(@ptrCast(item_insp));

        log.info("ProfileMenu: added '{s}'", .{profile.name});
    }

    log.info("ProfileMenu: populated {d} profiles", .{detected.items.len});

    try addRestartItem(alloc, items, app);
}
