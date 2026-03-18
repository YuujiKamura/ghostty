const std = @import("std");
const winrt = @import("winrt.zig");
const com = @import("com.zig");

const log = std.log.scoped(.winui3_util);

fn dumpInspectableIids(ins: *winrt.IInspectable) void {
    var count: u32 = 0;
    var iids: ?*winrt.GUID = null;
    const hr = ins.lpVtbl.GetIids(@ptrCast(ins), &count, &iids);
    if (hr < 0 or iids == null) {
        log.err("dumpInspectableIids: GetIids failed hr=0x{x:0>8}", .{@as(u32, @bitCast(hr))});
        return;
    }
    defer winrt.coTaskMemFree(@ptrCast(iids));

    log.err("dumpInspectableIids: count={d}", .{count});
    const arr: [*]const winrt.GUID = @ptrCast(iids.?);
    const n: u32 = @min(count, 8);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const g = arr[i];
        log.err(
            "  iid[{d}]={x:0>8}-{x:0>4}-{x:0>4}-..",
            .{ i, g.data1, g.data2, g.data3 },
        );
    }
}

fn inspectableHasIid(ins: *winrt.IInspectable, iid: winrt.GUID) bool {
    var count: u32 = 0;
    var iids: ?*winrt.GUID = null;
    const hr = ins.lpVtbl.GetIids(@ptrCast(ins), &count, &iids);
    if (hr < 0 or iids == null) return false;
    defer winrt.coTaskMemFree(@ptrCast(iids));

    const arr: [*]const winrt.GUID = @ptrCast(iids.?);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (std.mem.eql(u8, std.mem.asBytes(&arr[i]), std.mem.asBytes(&iid))) return true;
    }
    return false;
}

/// Box an HSTRING into an IInspectable using Windows.Foundation.PropertyValue.
pub fn boxString(str: winrt.HSTRING) !*winrt.IInspectable {
    const class_name = try winrt.hstring("Windows.Foundation.PropertyValue");
    defer winrt.deleteHString(class_name);
    const factory = try winrt.getActivationFactory(com.IPropertyValueStatics, class_name);
    defer factory.release();
    const boxed = try factory.createString(str);
    return @ptrCast(@alignCast(boxed));
}

/// Unbox an IInspectable back into an HSTRING. (Utility for testing/debugging)
pub fn unboxString(ins: *winrt.IInspectable) !winrt.HSTRING {
    if (ins.getRuntimeClassName()) |name| {
        // Log class name for debugging (HSTRING -> simple log)
        _ = name;
        log.info("unboxString: class name check OK", .{});
    } else |_| {}

    var pv_raw: ?*anyopaque = null;
    const hr = ins.lpVtbl.QueryInterface(@ptrCast(ins), &com.IPropertyValue.IID, &pv_raw);
    if (hr < 0) {
        log.err(
            "unboxString: QI(IPropertyValue) failed hr=0x{x:0>8} iid={x:0>8}-{x:0>4}-{x:0>4}",
            .{
                @as(u32, @bitCast(hr)),
                com.IPropertyValue.IID.data1,
                com.IPropertyValue.IID.data2,
                com.IPropertyValue.IID.data3,
            },
        );
        dumpInspectableIids(ins);
        return error.WinRTFailed;
    }
    const pv: *com.IPropertyValue = @ptrCast(@alignCast(pv_raw orelse return error.WinRTFailed));
    defer pv.release();
    const raw = try pv.getString();
    return @ptrCast(raw);
}

test "WinRT string boxing" {
    // Initialize WinRT for the test thread
    try winrt.hrCheck(winrt.RoInitialize(winrt.RO_INIT_SINGLETHREADED));
    defer winrt.RoUninitialize();

    const raw = try winrt.hstring("Ghostty Test");
    defer winrt.deleteHString(raw);

    const boxed = try boxString(raw);
    defer _ = boxed.release();

    const unboxed = try unboxString(boxed);
    defer _ = winrt.WindowsDeleteString(unboxed);
}

test "E2E-like: PropertyValue boxed string supports IPropertyValue QI" {
    const testing = std.testing;

    try winrt.hrCheck(winrt.RoInitialize(winrt.RO_INIT_SINGLETHREADED));
    defer winrt.RoUninitialize();

    const raw = try winrt.hstring("E2E QI Test");
    defer winrt.deleteHString(raw);

    const boxed = try boxString(raw);
    defer _ = boxed.release();

    // E2E-like assertion: runtime object must expose IPropertyValue.
    try testing.expect(inspectableHasIid(boxed, com.IPropertyValue.IID));

    var pv_raw: ?*anyopaque = null;
    const hr = boxed.lpVtbl.QueryInterface(@ptrCast(boxed), &com.IPropertyValue.IID, &pv_raw);
    try testing.expect(hr >= 0);
    const pv: *com.IPropertyValue = @ptrCast(@alignCast(pv_raw orelse return error.WinRTFailed));
    defer pv.release();

    const h = try pv.getString();
    defer _ = winrt.WindowsDeleteString(@ptrCast(h));
}
