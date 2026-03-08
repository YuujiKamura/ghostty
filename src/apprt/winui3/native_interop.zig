//! WinUI 3 Native Interop / Interface Extensions.
//! This file contains interface definitions that extend or complete
//! the generated com.zig without modifying it.

const winrt = @import("winrt.zig");
const com = @import("com.zig");
const os = @import("os.zig");
const GUID = winrt.GUID;
const HRESULT = winrt.HRESULT;
const HSTRING = winrt.HSTRING;
const WinRTError = winrt.WinRTError;
const hrCheck = winrt.hrCheck;

pub const VtblPlaceholder = ?*const anyopaque;

pub const IID_SizeChangedEventHandler = GUID{ .data1 = 0x8d7b1a58, .data2 = 0x14c6, .data3 = 0x51c9, .data4 = .{ 0x89, 0x2c, 0x9f, 0xcc, 0xe3, 0x68, 0xe7, 0x7d } };

pub const IWindow2 = extern struct {
    pub const IID = GUID{ .data1 = 0x61f0ec79, .data2 = 0x5d52, .data3 = 0x56b5, .data4 = .{ 0x86, 0xfb, 0x40, 0xfa, 0x4a, 0xf2, 0x88, 0xb0 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        p6: VtblPlaceholder, p7: VtblPlaceholder,
        get_Content: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT, // 8
        put_Content: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT, // 9
        p10: VtblPlaceholder, p11: VtblPlaceholder, p12: VtblPlaceholder, p13: VtblPlaceholder,
        p14: VtblPlaceholder,
        put_Title: *const fn (*anyopaque, ?HSTRING) callconv(.winapi) HRESULT, // 15
        get_ExtendsContentIntoTitleBar: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT, // 16
        put_ExtendsContentIntoTitleBar: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT, // 17
        p18: VtblPlaceholder, p19: VtblPlaceholder,
        add_Closed: *const fn (*anyopaque, ?*anyopaque, *i64) callconv(.winapi) HRESULT, // 20
        remove_Closed: *const fn (*anyopaque, i64) callconv(.winapi) HRESULT, // 21
        p22: VtblPlaceholder, p23: VtblPlaceholder, p24: VtblPlaceholder, p25: VtblPlaceholder,
        Activate: *const fn (*anyopaque) callconv(.winapi) HRESULT, // 26
        Close: *const fn (*anyopaque) callconv(.winapi) HRESULT, // 27
        SetTitleBar: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT, // 28
    };
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return com.comQueryInterface(self, T); }
    pub fn release(self: *@This()) void { com.comRelease(self); }
    pub fn putExtendsContentIntoTitleBar(self: *IWindow2, v: bool) WinRTError!void { try hrCheck(self.lpVtbl.put_ExtendsContentIntoTitleBar(self, v)); }
    pub fn setTitleBar(self: *IWindow2, e: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.SetTitleBar(self, e)); }
};

pub const TabViewWidthMode = enum(i32) { equal = 0, size_to_content = 1, compact = 2 };

pub const ITabView2 = extern struct {
    pub const IID = GUID{ .data1 = 0x07b509e1, .data2 = 0x1d38, .data3 = 0x551b, .data4 = .{ 0x95, 0xf4, 0x47, 0x32, 0xb0, 0x49, 0xf6, 0xa6 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_TabWidthMode: *const fn (*anyopaque, *TabViewWidthMode) callconv(.winapi) HRESULT, // 6
        put_TabWidthMode: *const fn (*anyopaque, TabViewWidthMode) callconv(.winapi) HRESULT, // 7
        p8: VtblPlaceholder, p9: VtblPlaceholder, p10: VtblPlaceholder, p11: VtblPlaceholder,
        p12: VtblPlaceholder, p13: VtblPlaceholder, p14: VtblPlaceholder, p15: VtblPlaceholder,
        p16: VtblPlaceholder, p17: VtblPlaceholder, p18: VtblPlaceholder, p19: VtblPlaceholder,
        p20: VtblPlaceholder, p21: VtblPlaceholder, p22: VtblPlaceholder, p23: VtblPlaceholder,
        add_TabCloseRequested: VtblPlaceholder, // 24
        remove_TabCloseRequested: VtblPlaceholder, // 25
        p26: VtblPlaceholder, p27: VtblPlaceholder,
        add_AddTabButtonClick: VtblPlaceholder, // 28
        remove_AddTabButtonClick: VtblPlaceholder, // 29
        p30: VtblPlaceholder, p31: VtblPlaceholder, p32: VtblPlaceholder, p33: VtblPlaceholder,
        get_TabItems: VtblPlaceholder, // 34
        p35: VtblPlaceholder, p36: VtblPlaceholder, p37: VtblPlaceholder, p38: VtblPlaceholder,
        get_CanDragTabs: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT, // 39
        put_CanDragTabs: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT, // 40
        get_CanReorderTabs: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT, // 41
        put_CanReorderTabs: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT, // 42
    };
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return com.comQueryInterface(self, T); }
    pub fn release(self: *@This()) void { com.comRelease(self); }
    pub fn putTabWidthMode(self: *ITabView2, m: TabViewWidthMode) WinRTError!void { try hrCheck(self.lpVtbl.put_TabWidthMode(self, m)); }
    pub fn putCanDragTabs(self: *ITabView2, v: bool) WinRTError!void { try hrCheck(self.lpVtbl.put_CanDragTabs(self, v)); }
    pub fn putCanReorderTabs(self: *ITabView2, v: bool) WinRTError!void { try hrCheck(self.lpVtbl.put_CanReorderTabs(self, v)); }
};

pub const IFrameworkElement2 = extern struct {
    pub const IID = GUID{ .data1 = 0xfe08f13d, .data2 = 0xdc6a, .data3 = 0x5495, .data4 = .{ 0xad, 0x44, 0xc2, 0xd8, 0xd2, 0x18, 0x63, 0xb0 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        p6: VtblPlaceholder, p7: VtblPlaceholder, p8: VtblPlaceholder, p9: VtblPlaceholder, p10: VtblPlaceholder,
        p11: VtblPlaceholder, p12: VtblPlaceholder,
        get_ActualWidth: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT, // 13
        get_ActualHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT, // 14
        get_Width: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT, // 15
        put_Width: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT, // 16
        get_Height: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT, // 17
        put_Height: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT, // 18
        p19: VtblPlaceholder, p20: VtblPlaceholder, p21: VtblPlaceholder, p22: VtblPlaceholder, p23: VtblPlaceholder,
        p24: VtblPlaceholder, p25: VtblPlaceholder, p26: VtblPlaceholder, p27: VtblPlaceholder, p28: VtblPlaceholder,
        p29: VtblPlaceholder, p30: VtblPlaceholder, p31: VtblPlaceholder, p32: VtblPlaceholder, p33: VtblPlaceholder,
        p34: VtblPlaceholder, p35: VtblPlaceholder, p36: VtblPlaceholder, p37: VtblPlaceholder, p38: VtblPlaceholder,
        p39: VtblPlaceholder, p40: VtblPlaceholder, p41: VtblPlaceholder, p42: VtblPlaceholder, p43: VtblPlaceholder,
        p44: VtblPlaceholder, p45: VtblPlaceholder, p46: VtblPlaceholder,
        get_HorizontalAlignment: VtblPlaceholder, // 47
        put_HorizontalAlignment: VtblPlaceholder, // 48
        p49: VtblPlaceholder, p50: VtblPlaceholder,
        get_VerticalAlignment: VtblPlaceholder, // 51
        put_VerticalAlignment: VtblPlaceholder, // 52
        p53: VtblPlaceholder, p54: VtblPlaceholder, p55: VtblPlaceholder,
        p56: VtblPlaceholder, p57: VtblPlaceholder, p58: VtblPlaceholder, p59: VtblPlaceholder, p60: VtblPlaceholder,
        add_Loaded: VtblPlaceholder, // 61
        remove_Loaded: VtblPlaceholder, // 62
        add_Unloaded: VtblPlaceholder, // 63
        remove_Unloaded: VtblPlaceholder, // 64
        p65: VtblPlaceholder, p66: VtblPlaceholder,
        add_SizeChanged: VtblPlaceholder, // 67
        remove_SizeChanged: *const fn (*anyopaque, i64) callconv(.winapi) HRESULT, // 68
    };
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return com.comQueryInterface(self, T); }
    pub fn release(self: *@This()) void { com.comRelease(self); }
    pub fn getActualWidth(self: *IFrameworkElement2) WinRTError!f64 { var v: f64 = 0; try hrCheck(self.lpVtbl.get_ActualWidth(self, &v)); return v; }
    pub fn removeSizeChanged(self: *IFrameworkElement2, t: i64) WinRTError!void { try hrCheck(self.lpVtbl.remove_SizeChanged(self, t)); }
};

pub const IPanel2 = extern struct {
    pub const IID = GUID{ .data1 = 0x2b02a69b, .data2 = 0x5af7, .data3 = 0x5ba1, .data4 = .{ 0xb0, 0x99, 0x63, 0xaf, 0x37, 0xaf, 0x96, 0xff } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Children: VtblPlaceholder,
        get_Background: VtblPlaceholder,
        put_Background: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return com.comQueryInterface(self, T); }
    pub fn release(self: *@This()) void { com.comRelease(self); }
    pub fn putBackground(self: *IPanel2, b: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.put_Background(self, b)); }
};

pub const ISwapChainPanelNative2 = extern struct {
    pub const IID = GUID{ .data1 = 0xd5a2f60c, .data2 = 0x37b2, .data3 = 0x44a2, .data4 = .{ 0x93, 0x7b, 0x8d, 0x8e, 0xb9, 0x72, 0x68, 0x21 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        SetSwapChain: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SetSwapChainHandle: *const fn (*anyopaque, os.HANDLE) callconv(.winapi) HRESULT,
    };
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T { return com.comQueryInterface(self, T); }
    pub fn release(self: *@This()) void { com.comRelease(self); }
    pub fn setSwapChain(self: *ISwapChainPanelNative2, sc: ?*anyopaque) WinRTError!void { try hrCheck(self.lpVtbl.SetSwapChain(self, sc)); }
    pub fn setSwapChainHandle(self: *ISwapChainPanelNative2, h: os.HANDLE) WinRTError!void { try hrCheck(self.lpVtbl.SetSwapChainHandle(self, h)); }
};
