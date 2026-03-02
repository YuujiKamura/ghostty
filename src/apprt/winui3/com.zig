//! WinUI 3 COM interface definitions for Zig.
//!
//! Each interface is an extern struct whose first field is a pointer to
//! its vtable. WinRT interfaces use IInspectable (6 base slots) instead
//! of IUnknown (3 base slots).
//!
//! IMPORTANT: vtable slot order MUST match the Windows SDK headers exactly.
//! A single missing or misplaced slot will silently call the wrong function.
//!
//! Slot ordering references:
//!   - microsoft.ui.xaml.h from Windows App SDK
//!   - microsoft.ui.xaml.controls.h from Windows App SDK
//!   - Inspectable.h from Windows SDK
//!
//! Pattern follows src/renderer/d3d11/com.zig.

const std = @import("std");
const winrt = @import("winrt.zig");

const HRESULT = winrt.HRESULT;
const GUID = winrt.GUID;
const HSTRING = winrt.HSTRING;
const HWND = winrt.HWND;
const VtblPlaceholder = winrt.VtblPlaceholder;
const IInspectable = winrt.IInspectable;
const hrCheck = winrt.hrCheck;
const WinRTError = winrt.WinRTError;

// ============================================================================
// IApplicationStatics — Microsoft.UI.Xaml.IApplicationStatics
// Used to call Application.Start(callback)
// ============================================================================

pub const IApplicationStatics = extern struct {
    // IID: Microsoft.UI.Xaml.IApplicationStatics
    // WinMD blob: 01 00 F5 09 0D 4E 58 43 2C 51 A9 87 50 3B 52 84 8E 95
    pub const IID = GUID{
        .Data1 = 0x4e0d09f5,
        .Data2 = 0x4358,
        .Data3 = 0x512c,
        .Data4 = .{ 0xa9, 0x87, 0x50, 0x3b, 0x52, 0x84, 0x8e, 0x95 },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IApplicationStatics (slots 6-9)
        get_Current: VtblPlaceholder, // 6
        Start: *const fn (*anyopaque, *anyopaque) callconv(.winapi) HRESULT, // 7
        LoadComponent: VtblPlaceholder, // 8
        LoadComponent_2: VtblPlaceholder, // 9
    };

    pub fn start(self: *IApplicationStatics, callback: *anyopaque) WinRTError!void {
        try hrCheck(self.lpVtbl.Start(@ptrCast(self), callback));
    }

    pub fn release(self: *IApplicationStatics) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// ============================================================================
// IApplicationFactory — Microsoft.UI.Xaml.IApplicationFactory
// Used to create Application instances
// ============================================================================

pub const IApplicationFactory = extern struct {
    // WinMD blob: 01 00 57 66 D9 9F 94 52 65 5A A1 DB 4F EA 14 35 97 DA
    pub const IID = GUID{
        .Data1 = 0x9fd96657,
        .Data2 = 0x5294,
        .Data3 = 0x5a65,
        .Data4 = .{ 0xa1, 0xdb, 0x4f, 0xea, 0x14, 0x35, 0x97, 0xda },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IApplicationFactory (slot 6)
        CreateInstance: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT, // 6
    };

    pub fn createInstance(self: *IApplicationFactory) WinRTError!*IInspectable {
        var inner: ?*anyopaque = null;
        var instance: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.CreateInstance(@ptrCast(self), null, &inner, &instance));
        return @ptrCast(@alignCast(instance orelse return error.WinRTFailed));
    }

    pub fn release(self: *IApplicationFactory) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// ============================================================================
// IApplication — Microsoft.UI.Xaml.IApplication
// ============================================================================

pub const IApplication = extern struct {
    // WinMD blob: 01 00 E7 F4 A8 06 46 11 AF 55 82 0D EB D5 56 43 B0 21
    pub const IID = GUID{
        .Data1 = 0x06a8f4e7,
        .Data2 = 0x1146,
        .Data3 = 0x55af,
        .Data4 = .{ 0x82, 0x0d, 0xeb, 0xd5, 0x56, 0x43, 0xb0, 0x21 },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IApplication (slots 6+)
        get_Resources: VtblPlaceholder, // 6
        put_Resources: VtblPlaceholder, // 7
        get_DebugSettings: VtblPlaceholder, // 8
        get_RequestedTheme: VtblPlaceholder, // 9
        put_RequestedTheme: VtblPlaceholder, // 10
        get_FocusVisualKind: VtblPlaceholder, // 11
        put_FocusVisualKind: VtblPlaceholder, // 12
        get_HighContrastAdjustment: VtblPlaceholder, // 13
        put_HighContrastAdjustment: VtblPlaceholder, // 14
        add_UnhandledException: VtblPlaceholder, // 15
        remove_UnhandledException: VtblPlaceholder, // 16
        Exit: *const fn (*anyopaque) callconv(.winapi) HRESULT, // 17
    };

    pub fn exit(self: *IApplication) WinRTError!void {
        try hrCheck(self.lpVtbl.Exit(@ptrCast(self)));
    }

    pub fn release(self: *IApplication) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// ============================================================================
// IWindow — Microsoft.UI.Xaml.IWindow
// Slot ordering from microsoft.ui.xaml.h
// ============================================================================

pub const IWindow = extern struct {
    // WinMD blob: 01 00 79 EC F0 61 52 5D B5 56 86 FB 40 FA 4A F2 88 B0
    pub const IID = GUID{
        .Data1 = 0x61f0ec79,
        .Data2 = 0x5d52,
        .Data3 = 0x56b5,
        .Data4 = .{ 0x86, 0xfb, 0x40, 0xfa, 0x4a, 0xf2, 0x88, 0xb0 },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IWindow (slots 6-28) — ordered per WinMD metadata
        // WinMD source: Microsoft.UI.Xaml.IWindow (line 193400 in winmd_dump.il)
        get_Bounds: VtblPlaceholder, // 6
        get_Visible: VtblPlaceholder, // 7
        get_Content: VtblPlaceholder, // 8
        put_Content: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT, // 9
        get_CoreWindow: VtblPlaceholder, // 10  (deprecated, always null)
        get_Compositor: VtblPlaceholder, // 11
        get_Dispatcher: VtblPlaceholder, // 12  (deprecated, always null — still occupies slot!)
        get_DispatcherQueue: VtblPlaceholder, // 13
        get_Title: VtblPlaceholder, // 14
        put_Title: *const fn (*anyopaque, ?HSTRING) callconv(.winapi) HRESULT, // 15
        get_ExtendsContentIntoTitleBar: VtblPlaceholder, // 16
        put_ExtendsContentIntoTitleBar: VtblPlaceholder, // 17
        add_Activated: VtblPlaceholder, // 18
        remove_Activated: VtblPlaceholder, // 19
        add_Closed: *const fn (*anyopaque, *anyopaque, *i64) callconv(.winapi) HRESULT, // 20
        remove_Closed: VtblPlaceholder, // 21
        add_SizeChanged: *const fn (*anyopaque, *anyopaque, *i64) callconv(.winapi) HRESULT, // 22
        remove_SizeChanged: VtblPlaceholder, // 23
        add_VisibilityChanged: VtblPlaceholder, // 24
        remove_VisibilityChanged: VtblPlaceholder, // 25
        Activate: *const fn (*anyopaque) callconv(.winapi) HRESULT, // 26
        Close: *const fn (*anyopaque) callconv(.winapi) HRESULT, // 27
        SetTitleBar: VtblPlaceholder, // 28
    };

    pub fn activate(self: *IWindow) WinRTError!void {
        try hrCheck(self.lpVtbl.Activate(@ptrCast(self)));
    }

    pub fn close(self: *IWindow) WinRTError!void {
        try hrCheck(self.lpVtbl.Close(@ptrCast(self)));
    }

    pub fn putContent(self: *IWindow, content: ?*anyopaque) WinRTError!void {
        try hrCheck(self.lpVtbl.put_Content(@ptrCast(self), content));
    }

    pub fn putTitle(self: *IWindow, title: ?HSTRING) WinRTError!void {
        try hrCheck(self.lpVtbl.put_Title(@ptrCast(self), title));
    }

    pub fn addClosed(self: *IWindow, handler: *anyopaque) WinRTError!i64 {
        var token: i64 = 0;
        try hrCheck(self.lpVtbl.add_Closed(@ptrCast(self), handler, &token));
        return token;
    }

    pub fn addSizeChanged(self: *IWindow, handler: *anyopaque) WinRTError!i64 {
        var token: i64 = 0;
        try hrCheck(self.lpVtbl.add_SizeChanged(@ptrCast(self), handler, &token));
        return token;
    }

    pub fn queryInterface(self: *IWindow, comptime T: type) WinRTError!*T {
        var result: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.QueryInterface(@ptrCast(self), &T.IID, &result));
        return @ptrCast(@alignCast(result orelse return error.WinRTFailed));
    }

    pub fn release(self: *IWindow) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// ============================================================================
// IWindowNative — classic COM interface (not WinRT) for getting HWND
// IID: {EECDBF0E-BAE9-4CB6-A68E-9598E1CB57BB}
// ============================================================================

pub const IWindowNative = extern struct {
    pub const IID = GUID{
        .Data1 = 0xeecdbf0e,
        .Data2 = 0xbae9,
        .Data3 = 0x4cb6,
        .Data4 = .{ 0xa6, 0x8e, 0x95, 0x98, 0xe1, 0xcb, 0x57, 0xbb },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IWindowNative (slot 3)
        get_WindowHandle: *const fn (*anyopaque, *?HWND) callconv(.winapi) HRESULT,
    };

    pub fn getWindowHandle(self: *IWindowNative) WinRTError!HWND {
        var hwnd: ?HWND = null;
        try hrCheck(self.lpVtbl.get_WindowHandle(@ptrCast(self), &hwnd));
        return hwnd orelse error.WinRTFailed;
    }

    pub fn release(self: *IWindowNative) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// ============================================================================
// ISwapChainPanelNative — classic COM interface for binding DXGI swap chain
// IID: {63AAD0B8-7C24-40FF-85A8-640D944CC325}
// From microsoft.ui.xaml.media.dxinterop.h
// ============================================================================

pub const ISwapChainPanelNative = extern struct {
    pub const IID = GUID{
        .Data1 = 0x63aad0b8,
        .Data2 = 0x7c24,
        .Data3 = 0x40ff,
        .Data4 = .{ 0x85, 0xa8, 0x64, 0x0d, 0x94, 0x4c, 0xc3, 0x25 },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // ISwapChainPanelNative (slot 3)
        SetSwapChain: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };

    pub fn setSwapChain(self: *ISwapChainPanelNative, swap_chain: ?*anyopaque) WinRTError!void {
        try hrCheck(self.lpVtbl.SetSwapChain(@ptrCast(self), swap_chain));
    }

    pub fn release(self: *ISwapChainPanelNative) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// ============================================================================
// ITabView — Microsoft.UI.Xaml.Controls.ITabView
// IID: {07B509E1-1D38-551B-95F4-4732B049F6A6}
// Slot ordering extracted from Microsoft.UI.Xaml.winmd (Windows App SDK 1.6)
// ============================================================================

pub const ITabView = extern struct {
    pub const IID = GUID{
        .Data1 = 0x07b509e1,
        .Data2 = 0x1d38,
        .Data3 = 0x551b,
        .Data4 = .{ 0x95, 0xf4, 0x47, 0x32, 0xb0, 0x49, 0xf6, 0xa6 },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // ITabView (slots 6-60) — ordered per WinMD metadata
        get_TabWidthMode: VtblPlaceholder, // 6
        put_TabWidthMode: VtblPlaceholder, // 7
        get_CloseButtonOverlayMode: VtblPlaceholder, // 8
        put_CloseButtonOverlayMode: VtblPlaceholder, // 9
        get_TabStripHeader: VtblPlaceholder, // 10
        put_TabStripHeader: VtblPlaceholder, // 11
        get_TabStripHeaderTemplate: VtblPlaceholder, // 12
        put_TabStripHeaderTemplate: VtblPlaceholder, // 13
        get_TabStripFooter: VtblPlaceholder, // 14
        put_TabStripFooter: VtblPlaceholder, // 15
        get_TabStripFooterTemplate: VtblPlaceholder, // 16
        put_TabStripFooterTemplate: VtblPlaceholder, // 17
        get_IsAddTabButtonVisible: VtblPlaceholder, // 18
        put_IsAddTabButtonVisible: VtblPlaceholder, // 19
        get_AddTabButtonCommand: VtblPlaceholder, // 20
        put_AddTabButtonCommand: VtblPlaceholder, // 21
        get_AddTabButtonCommandParameter: VtblPlaceholder, // 22
        put_AddTabButtonCommandParameter: VtblPlaceholder, // 23
        add_TabCloseRequested: *const fn (*anyopaque, *anyopaque, *i64) callconv(.winapi) HRESULT, // 24
        remove_TabCloseRequested: VtblPlaceholder, // 25
        add_TabDroppedOutside: VtblPlaceholder, // 26
        remove_TabDroppedOutside: VtblPlaceholder, // 27
        add_AddTabButtonClick: *const fn (*anyopaque, *anyopaque, *i64) callconv(.winapi) HRESULT, // 28
        remove_AddTabButtonClick: VtblPlaceholder, // 29
        add_TabItemsChanged: VtblPlaceholder, // 30
        remove_TabItemsChanged: VtblPlaceholder, // 31
        get_TabItemsSource: VtblPlaceholder, // 32
        put_TabItemsSource: VtblPlaceholder, // 33
        get_TabItems: *const fn (*anyopaque, *?*IVector) callconv(.winapi) HRESULT, // 34
        get_TabItemTemplate: VtblPlaceholder, // 35
        put_TabItemTemplate: VtblPlaceholder, // 36
        get_TabItemTemplateSelector: VtblPlaceholder, // 37
        put_TabItemTemplateSelector: VtblPlaceholder, // 38
        get_CanDragTabs: VtblPlaceholder, // 39
        put_CanDragTabs: VtblPlaceholder, // 40
        get_CanReorderTabs: VtblPlaceholder, // 41
        put_CanReorderTabs: VtblPlaceholder, // 42
        get_AllowDropTabs: VtblPlaceholder, // 43
        put_AllowDropTabs: VtblPlaceholder, // 44
        get_SelectedIndex: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT, // 45
        put_SelectedIndex: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT, // 46
        get_SelectedItem: VtblPlaceholder, // 47
        put_SelectedItem: VtblPlaceholder, // 48
        ContainerFromItem: VtblPlaceholder, // 49
        ContainerFromIndex: VtblPlaceholder, // 50
        add_SelectionChanged: *const fn (*anyopaque, *anyopaque, *i64) callconv(.winapi) HRESULT, // 51
        remove_SelectionChanged: VtblPlaceholder, // 52
        add_TabDragStarting: VtblPlaceholder, // 53
        remove_TabDragStarting: VtblPlaceholder, // 54
        add_TabDragCompleted: VtblPlaceholder, // 55
        remove_TabDragCompleted: VtblPlaceholder, // 56
        add_TabStripDragOver: VtblPlaceholder, // 57
        remove_TabStripDragOver: VtblPlaceholder, // 58
        add_TabStripDrop: VtblPlaceholder, // 59
        remove_TabStripDrop: VtblPlaceholder, // 60
    };

    pub fn getTabItems(self: *ITabView) WinRTError!*IVector {
        var result: ?*IVector = null;
        try hrCheck(self.lpVtbl.get_TabItems(@ptrCast(self), &result));
        return result orelse error.WinRTFailed;
    }

    pub fn getSelectedIndex(self: *ITabView) WinRTError!i32 {
        var idx: i32 = 0;
        try hrCheck(self.lpVtbl.get_SelectedIndex(@ptrCast(self), &idx));
        return idx;
    }

    pub fn putSelectedIndex(self: *ITabView, idx: i32) WinRTError!void {
        try hrCheck(self.lpVtbl.put_SelectedIndex(@ptrCast(self), idx));
    }

    pub fn addTabCloseRequested(self: *ITabView, handler: *anyopaque) WinRTError!i64 {
        var token: i64 = 0;
        try hrCheck(self.lpVtbl.add_TabCloseRequested(@ptrCast(self), handler, &token));
        return token;
    }

    pub fn addAddTabButtonClick(self: *ITabView, handler: *anyopaque) WinRTError!i64 {
        var token: i64 = 0;
        try hrCheck(self.lpVtbl.add_AddTabButtonClick(@ptrCast(self), handler, &token));
        return token;
    }

    pub fn addSelectionChanged(self: *ITabView, handler: *anyopaque) WinRTError!i64 {
        var token: i64 = 0;
        try hrCheck(self.lpVtbl.add_SelectionChanged(@ptrCast(self), handler, &token));
        return token;
    }

    pub fn queryInterface(self: *ITabView, comptime T: type) WinRTError!*T {
        var result: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.QueryInterface(@ptrCast(self), &T.IID, &result));
        return @ptrCast(@alignCast(result orelse return error.WinRTFailed));
    }

    pub fn release(self: *ITabView) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// ============================================================================
// ITabViewItem — Microsoft.UI.Xaml.Controls.ITabViewItem
// IID: {64980AFA-97AF-5190-90B3-4BA277B1113D}
// Slot ordering extracted from Microsoft.UI.Xaml.winmd
// ============================================================================

pub const ITabViewItem = extern struct {
    pub const IID = GUID{
        .Data1 = 0x64980afa,
        .Data2 = 0x97af,
        .Data3 = 0x5190,
        .Data4 = .{ 0x90, 0xb3, 0x4b, 0xa2, 0x77, 0xb1, 0x11, 0x3d },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // ITabViewItem (slots 6-16) — ordered per WinMD metadata
        get_Header: VtblPlaceholder, // 6
        put_Header: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT, // 7
        get_HeaderTemplate: VtblPlaceholder, // 8
        put_HeaderTemplate: VtblPlaceholder, // 9
        get_IconSource: VtblPlaceholder, // 10
        put_IconSource: VtblPlaceholder, // 11
        get_IsClosable: VtblPlaceholder, // 12
        put_IsClosable: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT, // 13
        get_TabViewTemplateSettings: VtblPlaceholder, // 14
        add_CloseRequested: VtblPlaceholder, // 15
        remove_CloseRequested: VtblPlaceholder, // 16
    };

    pub fn putHeader(self: *ITabViewItem, header: ?*anyopaque) WinRTError!void {
        try hrCheck(self.lpVtbl.put_Header(@ptrCast(self), header));
    }

    pub fn putIsClosable(self: *ITabViewItem, closable: bool) WinRTError!void {
        try hrCheck(self.lpVtbl.put_IsClosable(@ptrCast(self), @intFromBool(closable)));
    }

    pub fn queryInterface(self: *ITabViewItem, comptime T: type) WinRTError!*T {
        var result: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.QueryInterface(@ptrCast(self), &T.IID, &result));
        return @ptrCast(@alignCast(result orelse return error.WinRTFailed));
    }

    pub fn release(self: *ITabViewItem) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// ============================================================================
// IContentControl — Microsoft.UI.Xaml.Controls.IContentControl
// IID: {07E81761-11B2-52AE-8F8B-4D53D2B5900A}
// Used to set TabViewItem.Content (TabViewItem inherits ContentControl)
// ============================================================================

pub const IContentControl = extern struct {
    pub const IID = GUID{
        .Data1 = 0x07e81761,
        .Data2 = 0x11b2,
        .Data3 = 0x52ae,
        .Data4 = .{ 0x8f, 0x8b, 0x4d, 0x53, 0xd2, 0xb5, 0x90, 0x0a },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IContentControl (slots 6-14) — ordered per WinMD metadata
        get_Content: VtblPlaceholder, // 6
        put_Content: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT, // 7
        get_ContentTemplate: VtblPlaceholder, // 8
        put_ContentTemplate: VtblPlaceholder, // 9
        get_ContentTemplateSelector: VtblPlaceholder, // 10
        put_ContentTemplateSelector: VtblPlaceholder, // 11
        get_ContentTransitions: VtblPlaceholder, // 12
        put_ContentTransitions: VtblPlaceholder, // 13
        get_ContentTemplateRoot: VtblPlaceholder, // 14
    };

    pub fn putContent(self: *IContentControl, content: ?*anyopaque) WinRTError!void {
        try hrCheck(self.lpVtbl.put_Content(@ptrCast(self), content));
    }

    pub fn release(self: *IContentControl) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};

// ============================================================================
// IVector — Windows.Foundation.Collections.IVector<IInspectable>
// IID: {B32BDCA4-5E52-5B27-BC5D-D66A1A268C2A} (pinterface computed)
// Used for TabView.TabItems collection
// ============================================================================

pub const IVector = extern struct {
    pub const IID = GUID{
        .Data1 = 0xb32bdca4,
        .Data2 = 0x5e52,
        .Data3 = 0x5b27,
        .Data4 = .{ 0xbc, 0x5d, 0xd6, 0x6a, 0x1a, 0x26, 0x8c, 0x2a },
    };

    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        // IVector<IInspectable> (slots 6-17) — standard WinRT collection
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

    pub fn getAt(self: *IVector, index: u32) WinRTError!*anyopaque {
        var result: ?*anyopaque = null;
        try hrCheck(self.lpVtbl.GetAt(@ptrCast(self), index, &result));
        return result orelse error.WinRTFailed;
    }

    pub fn getSize(self: *IVector) WinRTError!u32 {
        var size: u32 = 0;
        try hrCheck(self.lpVtbl.get_Size(@ptrCast(self), &size));
        return size;
    }

    pub fn insertAt(self: *IVector, index: u32, item: ?*anyopaque) WinRTError!void {
        try hrCheck(self.lpVtbl.InsertAt(@ptrCast(self), index, item));
    }

    pub fn removeAt(self: *IVector, index: u32) WinRTError!void {
        try hrCheck(self.lpVtbl.RemoveAt(@ptrCast(self), index));
    }

    pub fn append(self: *IVector, item: ?*anyopaque) WinRTError!void {
        try hrCheck(self.lpVtbl.Append(@ptrCast(self), item));
    }

    pub fn release(self: *IVector) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }
};
