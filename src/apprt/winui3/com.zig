//! WinUI 3 COM interface definitions for Zig.
//! GENERATED CODE - DO NOT EDIT.
//! Manual/Native interop interfaces should be maintained in a separate file (e.g. native_interop.zig).

const winrt = @import("winrt.zig");
const os = @import("os.zig");
const GUID = winrt.GUID;
const HRESULT = winrt.HRESULT;
const HSTRING = winrt.HSTRING;
const WinRTError = winrt.WinRTError;
const hrCheck = winrt.hrCheck;
const EventRegistrationToken = i64;

pub const S_OK: HRESULT = 0;
pub const E_NOINTERFACE: HRESULT = @bitCast(@as(u32, 0x80004002));

pub const VtblPlaceholder = ?*const anyopaque;

// Helper for COM release
pub fn comRelease(ptr: anytype) void {
    const obj: *IUnknown = @ptrCast(@alignCast(ptr));
    _ = obj.lpVtbl.Release(@ptrCast(obj));
}

// Helper for COM QueryInterface
pub fn comQueryInterface(ptr: anytype, comptime T: type) WinRTError!*T {
    const obj: *IUnknown = @ptrCast(@alignCast(ptr));
    var out: ?*anyopaque = null;
    try hrCheck(obj.lpVtbl.QueryInterface(@ptrCast(obj), &T.IID, &out));
    return @ptrCast(@alignCast(out.?));
}

pub const IUnknown = extern struct {
    pub const IID = GUID{ .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
};

pub const IInspectable = extern struct {
    pub const IID = GUID{ .Data1 = 0xAFDBDF05, .Data2 = 0x2D12, .Data3 = 0x4D31, .Data4 = .{ 0x84, 0x1F, 0x72, 0x71, 0x50, 0x51, 0x46, 0x46 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
};

pub const IApplicationStatics = extern struct {
    pub const IID = GUID{ .Data1 = 0x4e0d09f5, .Data2 = 0x4358, .Data3 = 0x512c, .Data4 = .{ 0xa9, 0x87, 0x50, 0x3b, 0x52, 0x84, 0x8e, 0x95 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Current: VtblPlaceholder,
        Start: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn start(self: *@This(), cb: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.Start(self, cb)); }
};

pub const IApplicationFactory = extern struct {
    pub const IID = GUID{ .Data1 = 0x9fd96657, .Data2 = 0x5294, .Data3 = 0x5a65, .Data4 = .{ 0xa1, 0xdb, 0x4f, 0xea, 0x14, 0x35, 0x97, 0xda } };
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
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn createInstance(self: *@This(), outer: ?*anyopaque) WinRTError!struct { inner: ?*anyopaque, instance: *IInspectable } {
        var inner: ?*anyopaque = null;
        var instance: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.CreateInstance(self, outer, &inner, &instance));
        return .{ .inner = inner, .instance = @ptrCast(@alignCast(instance.?)) };
    }
};

pub const ApplicationTheme = enum(i32) { light = 0, dark = 1 };

pub const IApplication = extern struct {
    pub const IID = GUID{ .Data1 = 0x06a8f4e7, .Data2 = 0x1146, .Data3 = 0x55af, .Data4 = .{ 0x82, 0x0d, 0xeb, 0xd5, 0x56, 0x43, 0xb0, 0x21 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Resources: VtblPlaceholder,
        put_Resources: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        p8: VtblPlaceholder, p9: VtblPlaceholder, p10: VtblPlaceholder, p11: VtblPlaceholder,
        p12: VtblPlaceholder, p13: VtblPlaceholder,
        put_RequestedTheme: *const fn (*anyopaque, ApplicationTheme) callconv(.winapi) HRESULT,
        p15: VtblPlaceholder, p16: VtblPlaceholder,
        Exit: *const fn (*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn exit(self: *@This()) WinRTError!void { try hrCheck(self.lpVtbl.Exit(self)); }
    pub fn putResources(self: *@This(), rd: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.put_Resources(self, rd)); }
    pub fn putRequestedTheme(self: *@This(), theme: ApplicationTheme) WinRTError!void { try hrCheck(self.lpVtbl.put_RequestedTheme(self, theme)); }
};

pub const IWindow = extern struct {
    pub const IID = GUID{ .Data1 = 0x61f0ec79, .Data2 = 0x5d52, .Data3 = 0x56b5, .Data4 = .{ 0x86, 0xfb, 0x40, 0xfa, 0x4a, 0xf2, 0x88, 0xb0 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        p6: VtblPlaceholder, p7: VtblPlaceholder,
        get_Content: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Content: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        p10: VtblPlaceholder, p11: VtblPlaceholder, p12: VtblPlaceholder, p13: VtblPlaceholder,
        p14: VtblPlaceholder,
        put_Title: *const fn (*anyopaque, ?HSTRING) callconv(.winapi) HRESULT,
        p16: VtblPlaceholder, p17: VtblPlaceholder, p18: VtblPlaceholder, p19: VtblPlaceholder,
        add_Closed: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_Closed: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        p22: VtblPlaceholder, p23: VtblPlaceholder, p24: VtblPlaceholder, p25: VtblPlaceholder,
        Activate: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        Close: *const fn (*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn activate(self: *@This()) WinRTError!void { try hrCheck(self.lpVtbl.Activate(self)); }
    pub fn close(self: *@This()) WinRTError!void { try hrCheck(self.lpVtbl.Close(self)); }
    pub fn putTitle(self: *@This(), t: ?HSTRING) WinRTError!void { try hrCheck(self.lpVtbl.put_Title(self, t)); }
    pub fn putContent(self: *@This(), c: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.put_Content(self, c)); }
    pub fn getContent(self: *@This()) WinRTError!?*IInspectable { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Content(self, &out)); return @ptrCast(@alignCast(out)); }
    pub fn addClosed(self: *@This(), h: ?*anyopaque) WinRTError!EventRegistrationToken { var t: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Closed(self, h, &t)); return t; }
    pub fn removeClosed(self: *@This(), t: EventRegistrationToken) WinRTError!void { try hrCheck(self.lpVtbl.remove_Closed(self, t)); }
};

pub const ITabView = extern struct {
    pub const IID = GUID{ .Data1 = 0x07b509e1, .Data2 = 0x1d38, .Data3 = 0x551b, .Data4 = .{ 0x95, 0xf4, 0x47, 0x32, 0xb0, 0x49, 0xf6, 0xa6 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        p6: VtblPlaceholder, p7: VtblPlaceholder, p8: VtblPlaceholder, p9: VtblPlaceholder,
        p10: VtblPlaceholder, p11: VtblPlaceholder, p12: VtblPlaceholder, p13: VtblPlaceholder,
        p14: VtblPlaceholder, p15: VtblPlaceholder, p16: VtblPlaceholder, p17: VtblPlaceholder,
        p18: VtblPlaceholder, p19: VtblPlaceholder, p20: VtblPlaceholder, p21: VtblPlaceholder,
        p22: VtblPlaceholder, p23: VtblPlaceholder,
        add_TabCloseRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT, // 24
        remove_TabCloseRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT, // 25
        p26: VtblPlaceholder, p27: VtblPlaceholder,
        add_AddTabButtonClick: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT, // 28
        remove_AddTabButtonClick: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT, // 29
        p30: VtblPlaceholder, p31: VtblPlaceholder, p32: VtblPlaceholder, p33: VtblPlaceholder,
        get_TabItems: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT, // 34
        p35: VtblPlaceholder, p36: VtblPlaceholder, p37: VtblPlaceholder, p38: VtblPlaceholder,
        p39: VtblPlaceholder, p40: VtblPlaceholder, p41: VtblPlaceholder, p42: VtblPlaceholder,
        p43: VtblPlaceholder, p44: VtblPlaceholder,
        get_SelectedIndex: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT, // 45
        put_SelectedIndex: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT, // 46
        p47: VtblPlaceholder, p48: VtblPlaceholder, p49: VtblPlaceholder, p50: VtblPlaceholder,
        add_SelectionChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT, // 51
        remove_SelectionChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT, // 52
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn getTabItems(self: *@This()) WinRTError!*IVector { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_TabItems(self, &out)); return @ptrCast(@alignCast(out.?)); }
    pub fn getSelectedIndex(self: *@This()) WinRTError!i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_SelectedIndex(self, &out)); return out; }
    pub fn putSelectedIndex(self: *@This(), i: i32) WinRTError!void { try hrCheck(self.lpVtbl.put_SelectedIndex(self, i)); }
    pub fn addTabCloseRequested(self: *@This(), h: ?*anyopaque) WinRTError!EventRegistrationToken { var t: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TabCloseRequested(self, h, &t)); return t; }
    pub fn removeTabCloseRequested(self: *@This(), t: EventRegistrationToken) WinRTError!void { try hrCheck(self.lpVtbl.remove_TabCloseRequested(self, t)); }
    pub fn addAddTabButtonClick(self: *@This(), h: ?*anyopaque) WinRTError!EventRegistrationToken { var t: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_AddTabButtonClick(self, h, &t)); return t; }
    pub fn removeAddTabButtonClick(self: *@This(), t: EventRegistrationToken) WinRTError!void { try hrCheck(self.lpVtbl.remove_AddTabButtonClick(self, t)); }
    pub fn addSelectionChanged(self: *@This(), h: ?*anyopaque) WinRTError!EventRegistrationToken { var t: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_SelectionChanged(self, h, &t)); return t; }
    pub fn removeSelectionChanged(self: *@This(), t: EventRegistrationToken) WinRTError!void { try hrCheck(self.lpVtbl.remove_SelectionChanged(self, t)); }
};

pub const IVector = extern struct {
    // Windows.Foundation.Collections.IVector<IInspectable>
    // pinterface({913337e9-11a1-4345-a3a2-4e7f956e222d};cinterface(IInspectable))
    pub const IID = GUID{
        .Data1 = 0xb32bdca4,
        .Data2 = 0x5e52,
        .Data3 = 0x5b27,
        .Data4 = .{ 0xbc, 0x5d, 0xd6, 0x6a, 0x1a, 0x26, 0x8c, 0x2a },
    };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IVector<IInspectable> (slots 6-17)
        GetAt: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) HRESULT, // 6
        get_Size: *const fn (*anyopaque, *u32) callconv(.winapi) HRESULT, // 7
        GetView: VtblPlaceholder, // 8
        IndexOf: VtblPlaceholder, // 9
        SetAt: VtblPlaceholder, // 10
        InsertAt: *const fn (*anyopaque, u32, ?*anyopaque) callconv(.winapi) HRESULT, // 11
        RemoveAt: *const fn (*anyopaque, u32) callconv(.winapi) HRESULT, // 12
        Append: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT, // 13
        RemoveAtEnd: VtblPlaceholder, // 14
        Clear: VtblPlaceholder, // 15
        GetMany: VtblPlaceholder, // 16
        ReplaceAll: VtblPlaceholder, // 17
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn getSize(self: *@This()) WinRTError!u32 { var out: u32 = 0; try hrCheck(self.lpVtbl.get_Size(self, &out)); return out; }
    pub fn getAt(self: *@This(), i: u32) WinRTError!*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetAt(self, i, &out)); return out.?; }
    pub fn insertAt(self: *@This(), i: u32, item: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.InsertAt(self, i, item)); }
    pub fn append(self: *@This(), item: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.Append(self, item)); }
    pub fn removeAt(self: *@This(), i: u32) WinRTError!void { try hrCheck(self.lpVtbl.RemoveAt(self, i)); }
};

pub const ITabViewItem = extern struct {
    pub const IID = GUID{ .Data1 = 0x64980afa, .Data2 = 0x97af, .Data3 = 0x5190, .Data4 = .{ 0x90, 0xb3, 0x4b, 0xa2, 0x77, 0xb1, 0x11, 0x3d } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Header: VtblPlaceholder,
        put_Header: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        p8: VtblPlaceholder, p9: VtblPlaceholder, p10: VtblPlaceholder, p11: VtblPlaceholder,
        get_IsClosable: VtblPlaceholder,
        put_IsClosable: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn putHeader(self: *@This(), h: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.put_Header(self, h)); }
    pub fn putIsClosable(self: *@This(), v: bool) WinRTError!void { try hrCheck(self.lpVtbl.put_IsClosable(self, v)); }
};

pub const IContentControl = extern struct {
    pub const IID = GUID{ .Data1 = 0x07e81761, .Data2 = 0x11b2, .Data3 = 0x52ae, .Data4 = .{ 0x8f, 0x8b, 0x4d, 0x53, 0xd2, 0xb5, 0x90, 0x0a } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Content: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Content: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn putContent(self: *@This(), c: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.put_Content(self, c)); }
    pub fn getContent(self: *@This()) WinRTError!?*IInspectable { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Content(self, &out)); return @ptrCast(@alignCast(out)); }
};

pub const IUIElement = extern struct {
    pub const IID = GUID{ .Data1 = 0xc3c01020, .Data2 = 0x320c, .Data3 = 0x5cf6, .Data4 = .{ 0x9d, 0x24, 0xd3, 0x96, 0xbb, 0xfa, 0x4d, 0x8b } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        p6: VtblPlaceholder,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
};

pub const IFrameworkElement = extern struct {
    pub const IID = GUID{ .Data1 = 0xfe08f13d, .Data2 = 0xdc6a, .Data3 = 0x5495, .Data4 = .{ 0xad, 0x44, 0xc2, 0xd8, 0xd2, 0x18, 0x63, 0xb0 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        p6: VtblPlaceholder, p7: VtblPlaceholder, p8: VtblPlaceholder, p9: VtblPlaceholder, p10: VtblPlaceholder,
        p11: VtblPlaceholder, p12: VtblPlaceholder, p13: VtblPlaceholder, p14: VtblPlaceholder, p15: VtblPlaceholder,
        p16: VtblPlaceholder, p17: VtblPlaceholder, p18: VtblPlaceholder, p19: VtblPlaceholder, p20: VtblPlaceholder,
        p21: VtblPlaceholder, p22: VtblPlaceholder, p23: VtblPlaceholder, p24: VtblPlaceholder, p25: VtblPlaceholder,
        p26: VtblPlaceholder, p27: VtblPlaceholder, p28: VtblPlaceholder, p29: VtblPlaceholder, p30: VtblPlaceholder,
        p31: VtblPlaceholder, p32: VtblPlaceholder, p33: VtblPlaceholder, p34: VtblPlaceholder, p35: VtblPlaceholder,
        p36: VtblPlaceholder, p37: VtblPlaceholder, p38: VtblPlaceholder, p39: VtblPlaceholder, p40: VtblPlaceholder,
        p41: VtblPlaceholder, p42: VtblPlaceholder, p43: VtblPlaceholder, p44: VtblPlaceholder, p45: VtblPlaceholder,
        p46: VtblPlaceholder, p47: VtblPlaceholder, p48: VtblPlaceholder, p49: VtblPlaceholder, p50: VtblPlaceholder,
        p51: VtblPlaceholder, p52: VtblPlaceholder, p53: VtblPlaceholder, p54: VtblPlaceholder, p55: VtblPlaceholder,
        p56: VtblPlaceholder, p57: VtblPlaceholder, p58: VtblPlaceholder, p59: VtblPlaceholder, p60: VtblPlaceholder,
        add_Loaded: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT, // 61
        remove_Loaded: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT, // 62
        add_Unloaded: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT, // 63
        remove_Unloaded: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT, // 64
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn addLoaded(self: *@This(), h: ?*anyopaque) WinRTError!EventRegistrationToken { var t: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Loaded(self, h, &t)); return t; }
    pub fn removeLoaded(self: *@This(), t: EventRegistrationToken) WinRTError!void { try hrCheck(self.lpVtbl.remove_Loaded(self, t)); }
};

pub const IXamlMetadataProvider = extern struct {
    pub const IID = GUID{ .Data1 = 0xa96251f0, .Data2 = 0x2214, .Data3 = 0x5d53, .Data4 = .{ 0x87, 0x46, 0xce, 0x99, 0xa2, 0x59, 0x3c, 0xd7 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        GetXamlType: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetXamlType_2: *const fn (*anyopaque, ?HSTRING, *?*anyopaque) callconv(.winapi) HRESULT,
        GetXmlnsDefinitions: *const fn (*anyopaque, *u32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn getXamlType(self: *@This(), n: winrt.HSTRING) WinRTError!*IXamlType { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetXamlType_2(self, n, &out)); return @ptrCast(@alignCast(out.?)); }
};

pub const IXamlType = extern struct {
    pub const IID = GUID{ .Data1 = 0xd24219df, .Data2 = 0x7ec9, .Data3 = 0x57f1, .Data4 = .{ 0xa2, 0x7b, 0x6a, 0xf2, 0x51, 0xd9, 0xc5, 0xbc } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        p6: VtblPlaceholder, p7: VtblPlaceholder, p8: VtblPlaceholder, p9: VtblPlaceholder,
        p10: VtblPlaceholder, p11: VtblPlaceholder, p12: VtblPlaceholder, p13: VtblPlaceholder,
        p14: VtblPlaceholder, p15: VtblPlaceholder, p16: VtblPlaceholder, p17: VtblPlaceholder,
        p18: VtblPlaceholder,
        ActivateInstance: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn activateInstance(self: *@This()) WinRTError!*winrt.IInspectable { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ActivateInstance(self, &out)); return @ptrCast(@alignCast(out.?)); }
};

pub const ITextBox = extern struct {
    pub const IID = GUID{ .Data1 = 0x873af7c2, .Data2 = 0xab89, .Data3 = 0x5d76, .Data4 = .{ 0x8d, 0xbe, 0x3d, 0x63, 0x25, 0x66, 0x9d, 0xf5 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        p3: VtblPlaceholder, p4: VtblPlaceholder, p5: VtblPlaceholder, p6: VtblPlaceholder,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
};

pub const IPropertyValueStatics = extern struct {
    // Windows.Foundation.IPropertyValueStatics (Windows SDK)
    pub const IID = GUID{ .Data1 = 0x629bdbc8, .Data2 = 0xd932, .Data3 = 0x4ff4, .Data4 = .{ 0x96, 0xb9, 0x8d, 0x96, 0xc5, 0xc1, 0xe8, 0x58 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IPropertyValueStatics (slots 6-25)
        CreateEmpty: VtblPlaceholder, // 6
        CreateUInt8: VtblPlaceholder, // 7
        CreateInt16: VtblPlaceholder, // 8
        CreateUInt16: VtblPlaceholder, // 9
        CreateInt32: VtblPlaceholder, // 10
        CreateUInt32: VtblPlaceholder, // 11
        CreateInt64: VtblPlaceholder, // 12
        CreateUInt64: VtblPlaceholder, // 13
        CreateSingle: VtblPlaceholder, // 14
        CreateDouble: VtblPlaceholder, // 15
        CreateChar16: VtblPlaceholder, // 16
        CreateBoolean: VtblPlaceholder, // 17
        CreateString: *const fn (*anyopaque, ?HSTRING, *?*IInspectable) callconv(.winapi) HRESULT, // 18
        CreateInspectable: VtblPlaceholder, // 19
        CreateGuid: VtblPlaceholder, // 20
        CreateDateTime: VtblPlaceholder, // 21
        CreateTimeSpan: VtblPlaceholder, // 22
        CreatePoint: VtblPlaceholder, // 23
        CreateSize: VtblPlaceholder, // 24
        CreateRect: VtblPlaceholder, // 25
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn createString(self: *@This(), s: HSTRING) WinRTError!*winrt.IInspectable {
        var out: ?*IInspectable = null;
        try hrCheck(self.lpVtbl.CreateString(self, s, &out));
        return @ptrCast(@alignCast(out orelse return error.WinRTFailed));
    }
};

pub const ISolidColorBrush = extern struct {
    pub const IID = GUID{ .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } };
    lpVtbl: *const VTable,
    pub const Color = extern struct { a: u8, r: u8, g: u8, b: u8 };
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        p3: VtblPlaceholder, p4: VtblPlaceholder, p5: VtblPlaceholder,
        get_Color: VtblPlaceholder,
        put_Color: *const fn (*anyopaque, Color) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn putColor(self: *@This(), c: Color) WinRTError!void { try hrCheck(self.lpVtbl.put_Color(self, c)); }
};

pub const IControl = extern struct {
    pub const IID = GUID{ .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        p3: VtblPlaceholder, p4: VtblPlaceholder, p5: VtblPlaceholder,
        p6: VtblPlaceholder, p7: VtblPlaceholder, p8: VtblPlaceholder, p9: VtblPlaceholder,
        put_Background: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn putBackground(self: *@This(), b: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.put_Background(self, b)); }
};

pub const IResourceDictionary = extern struct {
    // WinMD: Microsoft.UI.Xaml.IResourceDictionary
    pub const IID = GUID{ .Data1 = 0x1b690975, .Data2 = 0xa710, .Data3 = 0x5783, .Data4 = .{ 0xa6, 0xe1, 0x15, 0x83, 0x6f, 0x61, 0x86, 0xc2 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_MergedDictionaries: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn getMergedDictionaries(self: *@This()) WinRTError!*IVector {
        var out: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.get_MergedDictionaries(self, &out));
        return @ptrCast(@alignCast(out orelse return error.WinRTFailed));
    }
};

pub const ISwapChainPanelNative = extern struct {
    // microsoft.ui.xaml.media.dxinterop.h:
    // MIDL_INTERFACE("63AAD0B8-7C24-40FF-85A8-640D944CC325")
    pub const IID = GUID{ .Data1 = 0x63aad0b8, .Data2 = 0x7c24, .Data3 = 0x40ff, .Data4 = .{ 0x85, 0xa8, 0x64, 0x0d, 0x94, 0x4c, 0xc3, 0x25 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        SetSwapChain: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *ISwapChainPanelNative) void { comRelease(self); }
    pub fn queryInterface(self: *ISwapChainPanelNative, comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn setSwapChain(self: *ISwapChainPanelNative, sc: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.SetSwapChain(self, sc)); }
};

pub const IWindowNative = extern struct {
    // Microsoft.UI.Xaml.window.h:
    // MIDL_INTERFACE("EECDBF0E-BAE9-4CB6-A68E-9598E1CB57BB")
    pub const IID = GUID{ .Data1 = 0xeecdbf0e, .Data2 = 0xbae9, .Data3 = 0x4cb6, .Data4 = .{ 0xa6, 0x8e, 0x95, 0x98, 0xe1, 0xcb, 0x57, 0xbb } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        getWindowHandle: *const fn (*anyopaque, *?os.HWND) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *IWindowNative) void { comRelease(self); }
    pub fn queryInterface(self: *IWindowNative, comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn getWindowHandle(self: *IWindowNative) WinRTError!os.HWND { var h: ?os.HWND = null; try hrCheck(self.lpVtbl.getWindowHandle(self, &h)); return h orelse error.WinRTFailed; }
};

pub const IID_TypedEventHandler_TabCloseRequested = GUID{ .Data1 = 0x7093974b, .Data2 = 0x0900, .Data3 = 0x52ae, .Data4 = .{ 0xaf, 0xd8, 0x70, 0xe5, 0x62, 0x3f, 0x45, 0x95 } };
pub const IID_TypedEventHandler_AddTabButtonClick = GUID{ .Data1 = 0x13df6907, .Data2 = 0xbbb4, .Data3 = 0x5f16, .Data4 = .{ 0xbe, 0xac, 0x29, 0x38, 0xc1, 0x5e, 0x1d, 0x85 } };
pub const IID_SelectionChangedEventHandler = GUID{ .Data1 = 0xa232390d, .Data2 = 0x0e34, .Data3 = 0x595e, .Data4 = .{ 0x89, 0x31, 0xfa, 0x92, 0x8a, 0x99, 0x09, 0xf4 } };
pub const IID_TypedEventHandler_WindowClosed = GUID{ .Data1 = 0x2a954d28, .Data2 = 0x7f8b, .Data3 = 0x5479, .Data4 = .{ 0x8c, 0xe9, 0x90, 0x04, 0x24, 0xa0, 0x40, 0x9f } };
pub const IID_RoutedEventHandler = GUID{ .Data1 = 0xaf8dae19, .Data2 = 0x0794, .Data3 = 0x5695, .Data4 = .{ 0x96, 0x8a, 0x07, 0x33, 0x3f, 0x92, 0x32, 0xe0 } };

pub const ITabViewTabCloseRequestedEventArgs = extern struct {
    pub const IID = GUID{ .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Tab: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return comQueryInterface(self, T); }
    pub fn getTab(self: *@This()) WinRTError!*winrt.IInspectable { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Tab(self, &out)); return @ptrCast(@alignCast(out.?)); }
};
