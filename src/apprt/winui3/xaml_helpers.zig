const std = @import("std");
const builtin = @import("builtin");
const winrt = @import("winrt.zig");
const com = @import("com.zig");

const log = std.log.scoped(.winui3);

pub fn activateXamlType(self: anytype, comptime class_name: [:0]const u8) !*winrt.IInspectable {
    // Always try IXamlMetadataProvider first — WinUI3 custom controls (TabViewItem etc.)
    // cannot be created via RoActivateInstance. The comptime Debug gate was the root cause
    // of Issue #122: ReleaseFast skipped provider path → E_NOTIMPL on TabViewItem.
    if (self.app_outer.provider) |provider| {
        const name = try winrt.hstring(class_name);
        defer winrt.deleteHString(name);
        log.info(
            "activateXamlType(provider): class={s} provider=0x{x}",
            .{ class_name, @intFromPtr(provider) },
        );

        var xaml_type_raw: ?*anyopaque = null;
        const provider_hr = provider.lpVtbl.GetXamlType_2(@ptrCast(provider), @ptrCast(name), &xaml_type_raw);
        if (provider_hr < 0) {
            log.info(
                "activateXamlType(provider): GetXamlType_2 failed class={s} hr=0x{x:0>8}, fallback to RoActivateInstance",
                .{ class_name, @as(u32, @bitCast(provider_hr)) },
            );
        } else if (xaml_type_raw) |xaml_type_raw_non_null| {
            const xaml_type: *com.IXamlType = @ptrCast(@alignCast(xaml_type_raw_non_null));
            const xaml_type_ptr = @intFromPtr(xaml_type);
            if (!com.isValidComPtr(xaml_type_ptr)) {
                log.err("activateXamlType(provider): suspicious IXamlType pointer 0x{x}", .{xaml_type_ptr});
                return error.WinRTFailed;
            }
            log.info("activateXamlType(provider): got IXamlType=0x{x}", .{xaml_type_ptr});
            var xaml_type_guard = winrt.ComRef(com.IXamlType).init(xaml_type);
            defer xaml_type_guard.deinit();
            const instance = try xaml_type_guard.get().activateInstance();
            const instance_ptr = @intFromPtr(instance);
            if (!com.isValidComPtr(instance_ptr)) {
                log.err("activateXamlType(provider): suspicious activateInstance ptr 0x{x}", .{instance_ptr});
                return error.WinRTFailed;
            }
            log.info("activateXamlType(provider): activateInstance=0x{x}", .{instance_ptr});
            return @ptrCast(@alignCast(instance));
        } else {
            log.info("activateXamlType(provider): GetXamlType_2 returned null class={s}, fallback to RoActivateInstance", .{class_name});
        }
    }
    // Fallback to RoActivateInstance (works for base framework types).
    const name = try winrt.hstring(class_name);
    defer winrt.deleteHString(name);
    return winrt.activateInstance(name);
}

pub fn boxString(str: winrt.HSTRING) !*winrt.IInspectable {
    log.info("boxString: getActivationFactory(IPropertyValueStatics)...", .{});
    const class_name = try winrt.hstring("Windows.Foundation.PropertyValue");
    defer winrt.deleteHString(class_name);
    var factory_guard = winrt.ComRef(com.IPropertyValueStatics).init(try winrt.getActivationFactory(com.IPropertyValueStatics, class_name));
    defer factory_guard.deinit();
    log.info("boxString: createString...", .{});
    const result = try factory_guard.get().createString(str);
    log.info("boxString: OK", .{});
    return @ptrCast(@alignCast(result));
}

pub fn loadXamlResources(self: anytype, xa: *com.IApplication) void {
    log.info("loadXamlResources: starting...", .{});

    // 1. Create XamlControlsResources
    const xcr_class = winrt.hstring("Microsoft.UI.Xaml.Controls.XamlControlsResources") catch {
        log.err("loadXamlResources: Failed to create XamlControlsResources HSTRING", .{});
        return;
    };
    defer winrt.deleteHString(xcr_class);
    const xcr = winrt.activateInstance(xcr_class) catch |err| {
        log.err("loadXamlResources: XamlControlsResources creation failed: {}", .{err});
        return;
    };
    if (self.xaml_controls_resources) |old| _ = old.release();
    self.xaml_controls_resources = xcr;

    // 2. Try MergedDictionaries pattern (correct way)
    if (loadXamlResourcesMerged(xa, xcr)) {
        log.info("loadXamlResources: OK (MergedDictionaries pattern)", .{});
        return;
    } else |err| {
        log.warn("loadXamlResources: MergedDictionaries pattern failed: {}, falling back to direct SetResources", .{err});
    }

    // 3. Fallback: direct SetResources
    xa.SetResources(@ptrCast(xcr)) catch |err| {
        log.err("loadXamlResources: FAIL SetResources: {}", .{err});
        return;
    };
    log.info("loadXamlResources: OK (fallback direct SetResources)", .{});
}

fn loadXamlResourcesMerged(xa: *com.IApplication, xcr: *winrt.IInspectable) !void {
    // Create a new ResourceDictionary
    const rd_class = try winrt.hstring("Microsoft.UI.Xaml.ResourceDictionary");
    defer winrt.deleteHString(rd_class);
    const rd_insp = try winrt.activateInstance(rd_class);
    defer _ = rd_insp.release();

    // Get IResourceDictionary interface
    const ird = try rd_insp.queryInterface(com.IResourceDictionary);
    defer ird.release();

    // Get MergedDictionaries collection and add XamlControlsResources
    const merged_raw = try ird.MergedDictionaries();
    const merged: *com.IVector = @ptrCast(@alignCast(merged_raw));
    defer merged.release();
    try merged.append(@ptrCast(xcr));

    // Set the new ResourceDictionary (with XCR merged) as Application.Resources
    try xa.SetResources(@ptrCast(rd_insp));
}
