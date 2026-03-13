//! Hand-written COM interface definitions that cannot be auto-generated.
//! These include Windows.Foundation types (not in WinUI3 winmd),
//! native COM interfaces, and ghostty-specific definitions.
const std = @import("std");
const winrt = @import("winrt.zig");
const GUID = winrt.GUID;
const HRESULT = winrt.HRESULT;
const HSTRING = ?*anyopaque;
const EventRegistrationToken = i64;
const VtblPlaceholder = gen.VtblPlaceholder;
const log = std.log.scoped(.winui3_com);
const gen = @import("com_generated.zig");
const hrCheck = gen.hrCheck;
const comRelease = gen.comRelease;
const comQueryInterface = gen.comQueryInterface;
const IUnknown = gen.IUnknown;
const IInspectable = gen.IInspectable;
const Point = gen.Point;
const Rect = gen.Rect;

pub const IVector = extern struct {
    // Windows.Foundation.Collections.IVector<IInspectable>
    pub const IID = GUID{ .data1 = 0xb32bdca4, .data2 = 0x5e52, .data3 = 0x5b27, .data4 = .{ 0xbc, 0x5d, 0xd6, 0x6a, 0x1a, 0x26, 0x8c, 0x2a } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        GetAt: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        get_Size: *const fn (*anyopaque, *u32) callconv(.winapi) HRESULT,
        GetView: VtblPlaceholder,
        IndexOf: VtblPlaceholder,
        SetAt: VtblPlaceholder,
        InsertAt: *const fn (*anyopaque, u32, ?*anyopaque) callconv(.winapi) HRESULT,
        RemoveAt: *const fn (*anyopaque, u32) callconv(.winapi) HRESULT,
        Append: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        RemoveAtEnd: VtblPlaceholder,
        Clear: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        GetMany: VtblPlaceholder,
        ReplaceAll: VtblPlaceholder,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getSize(self: *@This()) !u32 { var out: u32 = 0; try hrCheck(self.lpVtbl.get_Size(self, &out)); return out; }
    pub fn getAt(self: *@This(), i: u32) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetAt(self, i, &out)); return out orelse error.WinRTFailed; }
    pub fn insertAt(self: *@This(), i: u32, item: ?*anyopaque) !void { try hrCheck(self.lpVtbl.InsertAt(self, i, item)); }
    pub fn append(self: *@This(), item: ?*anyopaque) !void { try hrCheck(self.lpVtbl.Append(self, item)); }
    pub fn removeAt(self: *@This(), i: u32) !void { try hrCheck(self.lpVtbl.RemoveAt(self, i)); }
    pub fn clear(self: *@This()) !void { try hrCheck(self.lpVtbl.Clear(self)); }
    /// Find item by pointer identity. Returns index or null.
    pub fn indexOf(self: *@This(), target: *anyopaque) !?u32 {
        const count = try self.getSize();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const item = self.getAt(i) catch continue;
            if (@intFromPtr(item) == @intFromPtr(target)) {
                // Release the queried reference before returning.
                const unk: *IUnknown = @ptrCast(@alignCast(item));
                _ = unk.lpVtbl.Release(@ptrCast(unk));
                return i;
            }
            // Release the queried reference.
            const unk: *IUnknown = @ptrCast(@alignCast(item));
            _ = unk.lpVtbl.Release(@ptrCast(unk));
        }
        return null;
    }
};

pub const IPropertyValue = extern struct {
    pub const IID = GUID{ .data1 = 0x4bd682dd, .data2 = 0x7554, .data3 = 0x40e9, .data4 = .{ 0x9a, 0x9b, 0x82, 0x65, 0x4e, 0xde, 0x7e, 0x62 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Type: VtblPlaceholder,
        get_IsNumericScalar: VtblPlaceholder,
        GetUInt8: VtblPlaceholder,
        GetInt16: VtblPlaceholder,
        GetUInt16: VtblPlaceholder,
        GetInt32: VtblPlaceholder,
        GetUInt32: VtblPlaceholder,
        GetInt64: VtblPlaceholder,
        GetUInt64: VtblPlaceholder,
        GetSingle: VtblPlaceholder,
        GetDouble: VtblPlaceholder,
        GetChar16: VtblPlaceholder,
        GetBoolean: VtblPlaceholder,
        GetString: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getString(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.GetString(self, &out)); return out; }
};

pub const IPropertyValueStatics = extern struct {
    pub const IID = GUID{ .data1 = 0x629bdbc8, .data2 = 0xd932, .data3 = 0x4ff4, .data4 = .{ 0x96, 0xb9, 0x8d, 0x96, 0xc5, 0xc1, 0xe8, 0x58 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        CreateEmpty: VtblPlaceholder,
        CreateUInt8: VtblPlaceholder,
        CreateInt16: VtblPlaceholder,
        CreateUInt16: VtblPlaceholder,
        CreateInt32: VtblPlaceholder,
        CreateUInt32: VtblPlaceholder,
        CreateInt64: VtblPlaceholder,
        CreateUInt64: VtblPlaceholder,
        CreateSingle: VtblPlaceholder,
        CreateDouble: VtblPlaceholder,
        CreateChar16: VtblPlaceholder,
        CreateBoolean: VtblPlaceholder,
        CreateString: *const fn (*anyopaque, HSTRING, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn createString(self: *@This(), s: HSTRING) !*IInspectable { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.CreateString(self, s, &out)); return @ptrCast(@alignCast(out.?)); }
};

/// Microsoft.UI.Xaml.Input.IPointerRoutedEventArgs — WinUI3 version.
/// DIFFERENT IID and vtable layout from Windows.UI.Xaml.Input (UWP).
pub const IPointerRoutedEventArgs = extern struct {
    pub const IID = GUID{ .data1 = 0x66E78A9A, .data2 = 0x1BEC, .data3 = 0x5F92, .data4 = .{ 0xB1, 0xA1, 0xEA, 0x63, 0x34, 0xEE, 0x51, 0x1C } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Pointer: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_KeyModifiers: *const fn (*anyopaque, *u32) callconv(.winapi) HRESULT,
        get_Handled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_Handled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_IsGenerated: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        GetCurrentPoint: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetIntermediatePoints: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getCurrentPoint(self: *@This(), relative_to: ?*anyopaque) !*IPointerPoint {
        var out: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.GetCurrentPoint(@ptrCast(self), relative_to, &out));
        return @ptrCast(@alignCast(out orelse return error.WinRTFailed));
    }
    pub fn SetHandled(self: *@This(), value: bool) !void {
        try hrCheck(self.lpVtbl.put_Handled(@ptrCast(self), value));
    }
};

/// Microsoft.UI.Input.IPointerPoint — WinUI3 version.
/// DIFFERENT IID and vtable layout from Windows.UI.Input.IPointerPoint (UWP).
/// UWP has: PointerDevice, Position, RawPosition, PointerId, FrameId, Timestamp, IsInContact, Properties
/// WinUI3 has: FrameId, IsInContact, PointerDeviceType, PointerId, Position, Properties, Timestamp, GetTransformedPoint
pub const IPointerPoint = extern struct {
    pub const IID = GUID{ .data1 = 0x0d430ee6, .data2 = 0x252c, .data3 = 0x59a4, .data4 = .{ 0xb2, 0xa2, 0xd4, 0x42, 0x64, 0xdc, 0x6a, 0x40 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_FrameId: *const fn (*anyopaque, *u32) callconv(.winapi) HRESULT,
        get_IsInContact: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_PointerDeviceType: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        get_PointerId: *const fn (*anyopaque, *u32) callconv(.winapi) HRESULT,
        get_Position: *const fn (*anyopaque, *Point) callconv(.winapi) HRESULT,
        get_Properties: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_Timestamp: *const fn (*anyopaque, *u64) callconv(.winapi) HRESULT,
        GetTransformedPoint: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Position(self: *@This()) !Point {
        var out: Point = .{ .X = 0, .Y = 0 };
        try hrCheck(self.lpVtbl.get_Position(@ptrCast(self), &out));
        return out;
    }
    pub fn Properties(self: *@This()) !*IPointerPointProperties {
        var out: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.get_Properties(@ptrCast(self), &out));
        return @ptrCast(@alignCast(out orelse return error.WinRTFailed));
    }
};

/// Microsoft.UI.Input.IPointerPointProperties — WinUI3 version.
/// DIFFERENT IID and vtable layout from Windows.UI.Input (UWP).
/// WinUI3 uses alphabetical property ordering and has fewer methods (no HasUsage/GetUsageValue).
pub const IPointerPointProperties = extern struct {
    pub const IID = GUID{ .data1 = 0xd760ed77, .data2 = 0x4b10, .data3 = 0x57a5, .data4 = .{ 0xb3, 0xcc, 0xd9, 0xbf, 0x34, 0x13, 0xe9, 0x96 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_ContactRect: *const fn (*anyopaque, *Rect) callconv(.winapi) HRESULT,
        get_IsBarrelButtonPressed: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsCanceled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsEraser: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsHorizontalMouseWheel: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsInRange: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsInverted: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsLeftButtonPressed: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsMiddleButtonPressed: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsPrimary: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsRightButtonPressed: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsXButton1Pressed: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsXButton2Pressed: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_MouseWheelDelta: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        get_Orientation: *const fn (*anyopaque, *f32) callconv(.winapi) HRESULT,
        get_PointerUpdateKind: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        get_Pressure: *const fn (*anyopaque, *f32) callconv(.winapi) HRESULT,
        get_TouchConfidence: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_Twist: *const fn (*anyopaque, *f32) callconv(.winapi) HRESULT,
        get_XTilt: *const fn (*anyopaque, *f32) callconv(.winapi) HRESULT,
        get_YTilt: *const fn (*anyopaque, *f32) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn IsLeftButtonPressed(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsLeftButtonPressed(@ptrCast(self), &out)); return out; }
    pub fn IsRightButtonPressed(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsRightButtonPressed(@ptrCast(self), &out)); return out; }
    pub fn IsMiddleButtonPressed(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsMiddleButtonPressed(@ptrCast(self), &out)); return out; }
    pub fn MouseWheelDelta(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_MouseWheelDelta(@ptrCast(self), &out)); return out; }
    pub fn IsHorizontalMouseWheel(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsHorizontalMouseWheel(@ptrCast(self), &out)); return out; }
    pub fn PointerUpdateKind(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_PointerUpdateKind(@ptrCast(self), &out)); return out; }
};

pub const ISwapChainPanelNative = extern struct {
    pub const IID = GUID{ .data1 = 0x63aad0b8, .data2 = 0x7c24, .data3 = 0x40ff, .data4 = .{ 0x85, 0xa8, 0x64, 0x0d, 0x94, 0x4c, 0xc3, 0x25 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        SetSwapChain: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *ISwapChainPanelNative) void { comRelease(self); }
    pub fn queryInterface(self: *ISwapChainPanelNative, comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn setSwapChain(self: *@This(), sc: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetSwapChain(self, sc)); }
};

pub const IWindowNative = extern struct {
    pub const IID = GUID{ .data1 = 0xeecdbf0e, .data2 = 0xbae9, .data3 = 0x4cb6, .data4 = .{ 0xa6, 0x8e, 0x95, 0x98, 0xe1, 0xcb, 0x57, 0xbb } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        getWindowHandle: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getWindowHandle(self: *@This()) !*anyopaque { var h: ?*anyopaque = null; try hrCheck(self.lpVtbl.getWindowHandle(self, &h)); return h orelse error.WinRTFailed; }
};

/// Microsoft.UI.WindowId — a simple value type wrapping a u64.
pub const WindowId = extern struct {
    Value: u64,
};

/// Microsoft.UI.Content.ContentSizePolicy enum.
pub const ContentSizePolicy = struct {
    pub const None: i32 = 0;
    pub const ResizeContentToParentWindow: i32 = 1;
    pub const ResizeParentWindowToContent: i32 = 2;
};

/// Microsoft.UI.Xaml.Hosting.IDesktopWindowXamlSource
/// WinUI3 XAML Islands host — embeds XAML content in a Win32 HWND.
/// IIDs verified via win-zig-bindgen from Microsoft.UI.Xaml.winmd (Windows App SDK 1.6).
pub const IDesktopWindowXamlSource = extern struct {
    pub const IID = GUID{ .data1 = 0x553af92c, .data2 = 0x1381, .data3 = 0x51d6, .data4 = .{ 0xbe, 0xe0, 0xf3, 0x4b, 0xeb, 0x04, 0x2e, 0xa8 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IDesktopWindowXamlSource (slots 6-17)
        Content: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetContent: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        HasFocus: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SystemBackdrop: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetSystemBackdrop: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SiteBridge: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        TakeFocusRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTakeFocusRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        GotFocus: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveGotFocus: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        NavigateFocus: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Initialize: *const fn (*anyopaque, WindowId) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getContent(self: *@This()) !*anyopaque {
        var out: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.Content(@ptrCast(self), &out));
        return out orelse error.WinRTFailed;
    }
    pub fn setContent(self: *@This(), value: ?*anyopaque) !void {
        try hrCheck(self.lpVtbl.SetContent(@ptrCast(self), value));
    }
    pub fn getSiteBridge(self: *@This()) !*IDesktopChildSiteBridge {
        var out: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.SiteBridge(@ptrCast(self), &out));
        return @ptrCast(@alignCast(out orelse return error.WinRTFailed));
    }
    pub fn initialize(self: *@This(), parentWindowId: WindowId) !void {
        try hrCheck(self.lpVtbl.Initialize(@ptrCast(self), parentWindowId));
    }
    pub fn close(self: *@This()) !void {
        // Close is on IClosable; QI for it.
        const closable = try self.queryInterface(IClosable);
        defer closable.release();
        try closable.close();
    }
};

/// Microsoft.UI.Xaml.Hosting.IDesktopWindowXamlSourceFactory
/// Activation factory for DesktopWindowXamlSource.
pub const IDesktopWindowXamlSourceFactory = extern struct {
    pub const IID = GUID{ .data1 = 0x7d2db617, .data2 = 0x14e7, .data3 = 0x5d49, .data4 = .{ 0xae, 0xec, 0xae, 0x10, 0x88, 0x7e, 0x59, 0x5d } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        CreateInstance: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn createInstance(self: *@This()) !*IDesktopWindowXamlSource {
        var inner: ?*anyopaque = null;
        var instance: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.CreateInstance(@ptrCast(self), null, &inner, &instance));
        // Release inner if non-null (non-aggregated creation).
        if (inner) |i| {
            const unk: *IUnknown = @ptrCast(@alignCast(i));
            _ = unk.lpVtbl.Release(@ptrCast(unk));
        }
        return @ptrCast(@alignCast(instance orelse return error.WinRTFailed));
    }
};

/// Microsoft.UI.Content.IDesktopChildSiteBridge
/// Provides resize policy control for XAML Islands child site.
/// IID verified via win-zig-bindgen from Microsoft.UI.winmd (Windows App SDK 1.6).
pub const IDesktopChildSiteBridge = extern struct {
    pub const IID = GUID{ .data1 = 0xb2f2ff7b, .data2 = 0x1825, .data3 = 0x51b0, .data4 = .{ 0xb8, 0x0b, 0x75, 0x99, 0x88, 0x9c, 0x56, 0x9f } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IDesktopChildSiteBridge (slots 6-8)
        ResizePolicy: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetResizePolicy: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SiteView: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getResizePolicy(self: *@This()) !i32 {
        var out: i32 = 0;
        try hrCheck(self.lpVtbl.ResizePolicy(@ptrCast(self), &out));
        return out;
    }
    pub fn setResizePolicy(self: *@This(), value: i32) !void {
        try hrCheck(self.lpVtbl.SetResizePolicy(@ptrCast(self), value));
    }
};

/// Windows.Foundation.IClosable (same IID for UWP and WinUI3).
pub const IClosable = extern struct {
    pub const IID = GUID{ .data1 = 0x30d5a829, .data2 = 0x7fa4, .data3 = 0x4026, .data4 = .{ 0x83, 0xbb, 0xd7, 0x5b, 0xae, 0x4e, 0xa9, 0x9e } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Close: *const fn (*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn close(self: *@This()) !void { try hrCheck(self.lpVtbl.Close(@ptrCast(self))); }
};

// CharacterReceived and TextComposition delegate IIDs are now auto-generated
// in com_generated.zig via TypedEventHandler pinterface IID computation.
