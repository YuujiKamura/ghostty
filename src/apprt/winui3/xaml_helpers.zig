const std = @import("std");
const winrt = @import("winrt.zig");
const com = @import("com.zig");

const log = std.log.scoped(.winui3);

pub fn activateXamlType(self: anytype, comptime class_name: [:0]const u8) !*winrt.IInspectable {
    if (self.debug_cfg.use_ixaml_metadata_provider and self.app_outer.provider != null) {
        const provider = self.app_outer.provider.?;
        const name = try winrt.hstring(class_name);
        defer winrt.deleteHString(name);
        log.info(
            "activateXamlType(provider): class={s} provider=0x{x} name=0x{x} name_len={}",
            .{ class_name, @intFromPtr(provider), @intFromPtr(name), class_name.len },
        );

        var xaml_type_raw: ?*anyopaque = null;
        const provider_hr = provider.lpVtbl.GetXamlType_2(@ptrCast(provider), @ptrCast(name), &xaml_type_raw);
        if (provider_hr < 0) {
            log.info(
                "activateXamlType(provider): GetXamlType_2 failed class={s} hr=0x{x:0>8}, fallback",
                .{ class_name, @as(u32, @bitCast(provider_hr)) },
            );
        } else if (xaml_type_raw) |xaml_type_raw_non_null| {
            const xaml_type: *com.IXamlType = @ptrCast(@alignCast(xaml_type_raw_non_null));
            const xaml_type_ptr = @intFromPtr(xaml_type);
            if (!com.isValidComPtr(xaml_type_ptr)) {
                log.err("activateXamlType(provider): suspicious IXamlType pointer 0x{x}", .{xaml_type_ptr});
                return error.WinRTFailed;
            }
            if ((xaml_type_ptr & 0x7) != 0) {
                log.warn("activateXamlType(provider): unaligned IXamlType pointer 0x{x}", .{xaml_type_ptr});
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
            log.info("activateXamlType(provider): GetXamlType_2 returned null class={s}, fallback", .{class_name});
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
    log.info("loadXamlResources: starting deterministic bootstrap...", .{});
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

    const xa_abi: *com.IApplicationAbi = @ptrCast(xa);
    const put_resources_hr = xa_abi.lpVtbl.put_Resources(xa, @ptrCast(xcr));
    if (put_resources_hr < 0) {
        log.err("loadXamlResources: FAIL api=Application.put_Resources(XamlControlsResources) hr=0x{x:0>8}", .{@as(u32, @bitCast(put_resources_hr))});
        return;
    }
    log.info("loadXamlResources: OK primary path (Application.put_Resources(XamlControlsResources))", .{});

    if (true) {
        const brush_class = winrt.hstring("Microsoft.UI.Xaml.Media.SolidColorBrush") catch return;
        defer winrt.deleteHString(brush_class);
        var brush_insp_guard = winrt.ComRef(winrt.IInspectable).init(winrt.activateInstance(brush_class) catch return);
        defer brush_insp_guard.deinit();
        var brush_guard = winrt.ComRef(com.ISolidColorBrush).init(brush_insp_guard.get().queryInterface(com.ISolidColorBrush) catch return);
        defer brush_guard.deinit();
        brush_guard.get().putColor(.{ .a = 255, .r = 0, .g = 0, .b = 0 }) catch {};

        log.info("loadXamlResources: TabView resource overrides ready", .{});
    }
}
