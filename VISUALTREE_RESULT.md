# IVisualTreeHelperStatics Zig Bindings

This document contains the generated Zig bindings for `IVisualTreeHelperStatics` from `Microsoft.UI.Xaml.Media` and a sample debug function to dump the visual tree.

## 1. WinRT Types & Helpers

```zig
const std = @import("std");

pub const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

pub const HRESULT = i32;
pub const HSTRING = ?*anyopaque;
pub const VtblPlaceholder = ?*const anyopaque;

pub const Point = extern struct {
    X: f32,
    Y: f32,
};

pub const Rect = extern struct {
    X: f32,
    Y: f32,
    Width: f32,
    Height: f32,
};

pub fn hrCheck(hr: HRESULT) !void {
    if (hr < 0) return error.WinRTFailed;
}

pub fn comRelease(self: anytype) void {
    const obj: *IUnknown = @ptrCast(@alignCast(self));
    _ = obj.lpVtbl.Release(@ptrCast(obj));
}

pub const IUnknown = extern struct {
    pub const IID = GUID{ .data1 = 0x00000000, .data2 = 0x0000, .data3 = 0x0000, .data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
};

pub const IInspectable = extern struct {
    pub const IID = GUID{ .data1 = 0xAFDBDF05, .data2 = 0x2D12, .data3 = 0x4D31, .data4 = .{ 0x84, 0x1F, 0x72, 0x71, 0x50, 0x51, 0x46, 0x46 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        GetTrustLevel: VtblPlaceholder,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
};
```

## 2. IVisualTreeHelperStatics VTable & Bindings

Generated from `Microsoft.UI.Xaml.Media.VisualTreeHelper`.

```zig
pub const IVisualTreeHelperStatics = extern struct {
    pub const IID = GUID{ .data1 = 0x5aece43c, .data2 = 0x7651, .data3 = 0x5bb5, .data4 = .{ 0x85, 0x5c, 0x21, 0x98, 0x49, 0x6e, 0x45, 0x5e } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        FindElementsInHostCoordinates: *const fn (*anyopaque, Point, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        FindElementsInHostCoordinates_2: *const fn (*anyopaque, Rect, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        FindElementsInHostCoordinates_3: *const fn (*anyopaque, Point, ?*anyopaque, bool, *?*anyopaque) callconv(.winapi) HRESULT,
        FindElementsInHostCoordinates_4: *const fn (*anyopaque, Rect, ?*anyopaque, bool, *?*anyopaque) callconv(.winapi) HRESULT,
        GetChild: *const fn (*anyopaque, ?*anyopaque, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetChildrenCount: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        GetParent: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        DisconnectChildrenRecursive: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        GetOpenPopups: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetOpenPopupsForXamlRoot: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };

    pub fn release(self: *@This()) void { comRelease(self); }

    pub fn getChildrenCount(self: *@This(), element: ?*anyopaque) !i32 {
        var out: i32 = 0;
        try hrCheck(self.lpVtbl.GetChildrenCount(self, element, &out));
        return out;
    }

    pub fn getChild(self: *@This(), element: ?*anyopaque, index: i32) !*IDependencyObject {
        var out: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.GetChild(self, element, index, &out));
        return @ptrCast(@alignCast(out orelse return error.WinRTFailed));
    }

    pub fn getParent(self: *@This(), element: ?*anyopaque) !*IDependencyObject {
        var out: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.GetParent(self, element, &out));
        return @ptrCast(@alignCast(out orelse return error.WinRTFailed));
    }
};
```

## 3. IDependencyObject VTable & Bindings

```zig
pub const IDependencyObject = extern struct {
    pub const IID = GUID{ .data1 = 0xe7beaee7, .data2 = 0x160e, .data3 = 0x50f7, .data4 = .{ 0x87, 0x89, 0xd6, 0x34, 0x63, 0xf9, 0x79, 0xfa } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        GetTrustLevel: VtblPlaceholder,
        GetValue: VtblPlaceholder,
        SetValue: VtblPlaceholder,
        ClearValue: VtblPlaceholder,
        ReadLocalValue: VtblPlaceholder,
        GetAnimationBaseValue: VtblPlaceholder,
        RegisterPropertyChangedCallback: VtblPlaceholder,
        UnregisterPropertyChangedCallback: VtblPlaceholder,
        Dispatcher: VtblPlaceholder,
        DispatcherQueue: VtblPlaceholder,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
};
```

## 4. dumpVisualTree() Debug Sample

This sample traverses the visual tree and prints the class names of each element.

```zig
pub fn dumpVisualTree(vth: *IVisualTreeHelperStatics, element: ?*anyopaque, indent: usize) void {
    if (element == null) return;
    const inspectable: *IInspectable = @ptrCast(@alignCast(element.?));

    var name_hstr: HSTRING = null;
    if (inspectable.lpVtbl.GetRuntimeClassName(inspectable, &name_hstr) == 0) {
        // Note: You need a helper to convert HSTRING to Zig string (e.g. WindowsGetStringRawBuffer)
        // For debugging, you can just print the pointer if you don't have HSTRING helpers ready.
        std.debug.print("{s: >[1]} [{p}]\n", .{ "", indent, element });
    }

    const count = vth.getChildrenCount(element) catch 0;
    var i: i32 = 0;
    while (i < count) : (i += 1) {
        if (vth.getChild(element, i)) |child| {
            defer child.release();
            dumpVisualTree(vth, child, indent + 2);
        } else |_| {}
    }
}
```

### Usage Example

```zig
// 1. Get the activation factory for VisualTreeHelper
// 2. Cast it to IVisualTreeHelperStatics
// 3. Call dumpVisualTree(vth, root_element, 0)
```
