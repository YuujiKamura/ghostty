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
const Rect = gen.Rect;

/// IApplication ABI — provides access to Application.Resources (get/put).
/// Used by xaml_helpers.loadXamlResources to set XamlControlsResources.
pub const IApplicationAbi = extern struct {
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Resources: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Resources: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
};

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

pub const GridUnitType = struct {
    pub const Pixel: i32 = 0;
    pub const Auto: i32 = 1;
    pub const Star: i32 = 2;
};

pub const HorizontalAlignment = struct {
    pub const Left: i32 = 0;
    pub const Center: i32 = 1;
    pub const Right: i32 = 2;
    pub const Stretch: i32 = 3;
};

pub const VerticalAlignment = struct {
    pub const Top: i32 = 0;
    pub const Center: i32 = 1;
    pub const Bottom: i32 = 2;
    pub const Stretch: i32 = 3;
};

pub const GridLength = extern struct {
    Value: f64,
    GridUnitType: i32,
};

// --- XAML Input event handler delegate IIDs ---

pub const IID_KeyEventHandler = GUID{ .data1 = 0xDB68E7CC, .data2 = 0x9A2B, .data3 = 0x527D, .data4 = .{ 0x99, 0x89, 0x25, 0x28, 0x4D, 0xAC, 0xCC, 0x03 } };
pub const IID_PointerEventHandler = GUID{ .data1 = 0xA48A71E1, .data2 = 0x8BB4, .data3 = 0x5597, .data4 = .{ 0x9E, 0x31, 0x90, 0x3A, 0x3F, 0x6A, 0x04, 0xFB } };
// TypedEventHandler<UIElement, CharacterReceivedRoutedEventArgs> — computed via WinRT pinterface SHA-1
pub const IID_CharacterReceivedHandler = GUID{ .data1 = 0x553240fb, .data2 = 0x75d9, .data3 = 0x5641, .data4 = .{ 0x9c, 0xce, 0x2d, 0x14, 0xb7, 0x43, 0xf0, 0xec } };

// --- XAML Input event args interfaces ---

/// Windows.Foundation.Point — value type used by IPointerPoint.get_Position.
pub const Point = extern struct {
    X: f32,
    Y: f32,
};

pub const IKeyRoutedEventArgs = extern struct {
    pub const IID = GUID{ .data1 = 0xEE357007, .data2 = 0xA2D6, .data3 = 0x5C75, .data4 = .{ 0x94, 0x31, 0x05, 0xFD, 0x66, 0xEC, 0x79, 0x15 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Key: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        get_KeyStatus: *const fn (*anyopaque, *u32) callconv(.winapi) HRESULT,
        get_Handled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_Handled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_OriginalKey: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        get_DeviceId: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getKey(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_Key(@ptrCast(self), &out)); return out; }
    pub fn getOriginalKey(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_OriginalKey(@ptrCast(self), &out)); return out; }
    pub fn getHandled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_Handled(@ptrCast(self), &out)); return out; }
    pub fn putHandled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.put_Handled(@ptrCast(self), value)); }
};

pub const ICharacterReceivedRoutedEventArgs = extern struct {
    pub const IID = GUID{ .data1 = 0xE26CA5BB, .data2 = 0x34C3, .data3 = 0x5C1E, .data4 = .{ 0x9A, 0x16, 0x00, 0xB8, 0x0B, 0x07, 0xA8, 0x99 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Character: *const fn (*anyopaque, *u16) callconv(.winapi) HRESULT,
        get_KeyStatus: *const fn (*anyopaque, *u32) callconv(.winapi) HRESULT,
        get_Handled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_Handled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getCharacter(self: *@This()) !u16 { var out: u16 = 0; try hrCheck(self.lpVtbl.get_Character(@ptrCast(self), &out)); return out; }
    pub fn getHandled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_Handled(@ptrCast(self), &out)); return out; }
    pub fn putHandled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.put_Handled(@ptrCast(self), value)); }
};

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
    pub fn getHandled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_Handled(@ptrCast(self), &out)); return out; }
    pub fn putHandled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.put_Handled(@ptrCast(self), value)); }
    pub fn getCurrentPoint(self: *@This(), relative_to: ?*anyopaque) !*IPointerPoint {
        var out: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.GetCurrentPoint(@ptrCast(self), relative_to, &out));
        return @ptrCast(@alignCast(out orelse return error.WinRTFailed));
    }
};

pub const IPointerPoint = extern struct {
    pub const IID = GUID{ .data1 = 0x0d430ee6, .data2 = 0x252c, .data3 = 0x59a4, .data4 = .{ 0xb2, 0xa2, 0xd4, 0x42, 0x64, 0xdc, 0x6a, 0x40 } };
    lpVtbl: *const VTable,
    // Microsoft.UI.Input.IPointerPoint vtable (NOT Windows.UI.Input — different slot order!)
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
    pub fn getPosition(self: *@This()) !Point {
        var out: Point = .{ .X = 0, .Y = 0 };
        try hrCheck(self.lpVtbl.get_Position(@ptrCast(self), &out));
        return out;
    }
    pub fn getProperties(self: *@This()) !*IPointerPointProperties {
        var out: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.get_Properties(@ptrCast(self), &out));
        return @ptrCast(@alignCast(out orelse return error.WinRTFailed));
    }
};

pub const IPointerPointProperties = extern struct {
    pub const IID = GUID{ .data1 = 0xd760ed77, .data2 = 0x4b10, .data3 = 0x57a5, .data4 = .{ 0xb3, 0xcc, 0xd9, 0xbf, 0x34, 0x13, 0xe9, 0x96 } };
    lpVtbl: *const VTable,
    // Microsoft.UI.Input.IPointerPointProperties vtable (NOT Windows.UI.Input — different slots, fewer methods!)
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
    pub fn getIsLeftButtonPressed(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsLeftButtonPressed(@ptrCast(self), &out)); return out; }
    pub fn getIsRightButtonPressed(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsRightButtonPressed(@ptrCast(self), &out)); return out; }
    pub fn getIsMiddleButtonPressed(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsMiddleButtonPressed(@ptrCast(self), &out)); return out; }
    pub fn getMouseWheelDelta(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_MouseWheelDelta(@ptrCast(self), &out)); return out; }
    pub fn getIsHorizontalMouseWheel(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsHorizontalMouseWheel(@ptrCast(self), &out)); return out; }
    pub fn getPointerUpdateKind(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_PointerUpdateKind(@ptrCast(self), &out)); return out; }
};

/// IColumnDefinition — Microsoft.UI.Xaml.Controls.IColumnDefinition
/// Used to set column widths in Grid layouts.
pub const IColumnDefinition = extern struct {
    pub const IID = GUID{ .data1 = 0x454cea14, .data2 = 0x87ec, .data3 = 0x5890, .data4 = .{ 0xbb, 0x62, 0xf1, 0xd8, 0x2a, 0x94, 0x75, 0x8e } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Width: *const fn (*anyopaque, *GridLength) callconv(.winapi) HRESULT,
        SetWidth: *const fn (*anyopaque, GridLength) callconv(.winapi) HRESULT,
        MaxWidth: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetMaxWidth: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        MinWidth: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetMinWidth: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        ActualWidth: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
};

/// IRangeBase — Microsoft.UI.Xaml.Controls.Primitives.IRangeBase
/// Base interface for ScrollBar, Slider, ProgressBar. Provides Value/Maximum/Minimum.
pub const IRangeBase = extern struct {
    pub const IID = GUID{ .data1 = 0x540d6d61, .data2 = 0x8fac, .data3 = 0x5d5c, .data4 = .{ 0xb5, 0xb0, 0xe1, 0x72, 0xa7, 0xdd, 0xe1, 0x03 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Minimum: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_Minimum: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_Maximum: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_Maximum: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_SmallChange: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_SmallChange: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_LargeChange: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_LargeChange: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_Value: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_Value: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        add_ValueChanged: *const fn (*anyopaque, ?*anyopaque, *i64) callconv(.winapi) HRESULT,
        remove_ValueChanged: *const fn (*anyopaque, i64) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn setValue(self: *@This(), v: f64) !void { try hrCheck(self.lpVtbl.put_Value(@ptrCast(self), v)); }
    pub fn setMaximum(self: *@This(), v: f64) !void { try hrCheck(self.lpVtbl.put_Maximum(@ptrCast(self), v)); }
    pub fn setMinimum(self: *@This(), v: f64) !void { try hrCheck(self.lpVtbl.put_Minimum(@ptrCast(self), v)); }
    pub fn setSmallChange(self: *@This(), v: f64) !void { try hrCheck(self.lpVtbl.put_SmallChange(@ptrCast(self), v)); }
    pub fn setLargeChange(self: *@This(), v: f64) !void { try hrCheck(self.lpVtbl.put_LargeChange(@ptrCast(self), v)); }
    pub fn getValue(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_Value(@ptrCast(self), &out)); return out; }
};

/// IScrollBar — Microsoft.UI.Xaml.Controls.Primitives.IScrollBar
pub const IScrollBar = extern struct {
    pub const IID = GUID{ .data1 = 0x568cbf41, .data2 = 0xf741, .data3 = 0x5f05, .data4 = .{ 0x8e, 0x08, 0xc0, 0xa5, 0x0a, 0xc1, 0x7c, 0x8c } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Orientation: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_Orientation: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_ViewportSize: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_ViewportSize: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_IndicatorMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_IndicatorMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        add_Scroll: *const fn (*anyopaque, ?*anyopaque, *i64) callconv(.winapi) HRESULT,
        remove_Scroll: *const fn (*anyopaque, i64) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getOrientation(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_Orientation(@ptrCast(self), &out)); return out; }
    pub fn getViewportSize(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_ViewportSize(@ptrCast(self), &out)); return out; }
    pub fn setOrientation(self: *@This(), v: i32) !void { try hrCheck(self.lpVtbl.put_Orientation(@ptrCast(self), v)); }
    pub fn setViewportSize(self: *@This(), v: f64) !void { try hrCheck(self.lpVtbl.put_ViewportSize(@ptrCast(self), v)); }
    pub fn addScroll(self: *@This(), handler: ?*anyopaque) !i64 {
        var token: i64 = 0;
        try hrCheck(self.lpVtbl.add_Scroll(@ptrCast(self), handler, &token));
        return token;
    }
    pub fn removeScroll(self: *@This(), token: i64) !void {
        try hrCheck(self.lpVtbl.remove_Scroll(@ptrCast(self), token));
    }
};

/// IScrollEventArgs — Microsoft.UI.Xaml.Controls.Primitives.IScrollEventArgs
pub const IScrollEventArgs = extern struct {
    pub const IID = GUID{ .data1 = 0xdbd27f11, .data2 = 0xf937, .data3 = 0x5ad0, .data4 = .{ 0x9f, 0x75, 0xb9, 0x62, 0xc3, 0x32, 0x54, 0xcf } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_NewValue: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        get_ScrollEventType: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getNewValue(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_NewValue(@ptrCast(self), &out)); return out; }
    pub fn getScrollEventType(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_ScrollEventType(@ptrCast(self), &out)); return out; }
};

/// ScrollEventHandler delegate IID — used for IScrollBar.add_Scroll.
/// This is a named delegate, NOT a TypedEventHandler pinterface.
pub const IID_ScrollEventHandler = GUID{ .data1 = 0xff661ba9, .data2 = 0x8c06, .data3 = 0x5785, .data4 = .{ 0xa2, 0x3c, 0x30, 0xd6, 0xb3, 0x16, 0x31, 0xe8 } };
