//! WinUI 3 COM interface definitions for Zig.
//! GENERATED CODE - DO NOT EDIT.
const std = @import("std");
const log = std.log.scoped(.winui3_com);
const native = @import("com_native.zig");
const IVector = native.IVector;
const GridLength = native.GridLength;
pub const Size = extern struct { Width: f32, Height: f32 };
pub const Point = extern struct { X: f32, Y: f32 };
pub const Rect = extern struct { X: f32, Y: f32, Width: f32, Height: f32 };
pub const Thickness = extern struct { Left: f64, Top: f64, Right: f64, Bottom: f64 };
pub const Color = extern struct { a: u8, r: u8, g: u8, b: u8 };
pub const CornerRadius = extern struct { TopLeft: f64, TopRight: f64, BottomRight: f64, BottomLeft: f64 };
pub const GUID = @import("winrt.zig").GUID;
pub const HRESULT = i32;
pub const BOOL = i32;
pub const FARPROC = ?*anyopaque;
pub const HSTRING = ?*anyopaque;
pub const HANDLE = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const HWND = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const HINSTANCE = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const HMODULE = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const WPARAM = extern struct { Value: usize };
pub const LPARAM = extern struct { Value: isize };
pub const LPCWSTR = [*]const u16;
pub const LPWSTR = [*]u16;
pub const POINT = extern struct {
    x: i32,
    y: i32,
};
pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};
pub const EventRegistrationToken = i64;

pub const VtblPlaceholder = ?*const anyopaque;

pub const IID_RoutedEventHandler = GUID{ .data1 = 0xaf8dae19, .data2 = 0x0794, .data3 = 0x5695, .data4 = .{ 0x96, 0x8a, 0x07, 0x33, 0x3f, 0x92, 0x32, 0xe0 } };
pub const IID_SizeChangedEventHandler = GUID{ .data1 = 0x8d7b1a58, .data2 = 0x14c6, .data3 = 0x51c9, .data4 = .{ 0x89, 0x2c, 0x9f, 0xcc, 0xe3, 0x68, 0xe7, 0x7d } };
pub const IID_TypedEventHandler_TabCloseRequested = GUID{ .data1 = 0x7093974b, .data2 = 0x0900, .data3 = 0x52ae, .data4 = .{ 0xaf, 0xd8, 0x70, 0xe5, 0x62, 0x3f, 0x45, 0x95 } };
pub const IID_TypedEventHandler_AddTabButtonClick = GUID{ .data1 = 0x13df6907, .data2 = 0xbbb4, .data3 = 0x5f16, .data4 = .{ 0xbe, 0xac, 0x29, 0x38, 0xc1, 0x5e, 0x1d, 0x85 } };
pub const IID_SelectionChangedEventHandler = GUID{ .data1 = 0xa232390d, .data2 = 0x0e34, .data3 = 0x595e, .data4 = .{ 0x89, 0x31, 0xfa, 0x92, 0x8a, 0x99, 0x09, 0xf4 } };
pub const IID_TypedEventHandler_WindowClosed = GUID{ .data1 = 0x2a954d28, .data2 = 0x7f8b, .data3 = 0x5479, .data4 = .{ 0x8c, 0xe9, 0x90, 0x04, 0x24, 0xa0, 0x40, 0x9f } };

pub fn comRelease(self: anytype) void {
    const obj: *IUnknown = @ptrCast(@alignCast(self));
    _ = obj.lpVtbl.Release(@ptrCast(obj));
}

pub fn comQueryInterface(self: anytype, comptime T: type) !*T {
    const obj: *IUnknown = @ptrCast(@alignCast(self));
    var out: ?*anyopaque = null;
    const hr = obj.lpVtbl.QueryInterface(@ptrCast(obj), &T.IID, &out);
    if (hr < 0) return error.WinRTFailed;
    return @ptrCast(@alignCast(out.?));
}

pub fn hrCheck(hr: HRESULT) !void {
    if (hr < 0) return error.WinRTFailed;
}

/// Check if a COM pointer looks valid (not null-page, properly aligned).
pub fn isValidComPtr(ptr: usize) bool {
    return ptr >= 0x10000;
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
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
};

pub const IInspectable = extern struct {
    pub const IID = GUID{ .data1 = 0xAFDBDF05, .data2 = 0x2D12, .data3 = 0x4D31, .data4 = .{ 0x84, 0x1F, 0x72, 0x71, 0x50, 0x51, 0x46, 0x46 } };
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
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
};
pub const IApplicationStatics = extern struct {
    pub const IID = GUID{ .data1 = 0x4e0d09f5, .data2 = 0x4358, .data3 = 0x512c, .data4 = .{ 0xa9, 0x87, 0x50, 0x3b, 0x52, 0x84, 0x8e, 0x95 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Current: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Start: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        LoadComponent: *const fn (*anyopaque, HSTRING, ?*anyopaque) callconv(.winapi) HRESULT,
        LoadComponent_1: *const fn (*anyopaque, HSTRING, ?*anyopaque, i32) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Current(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Current(self, &out)); return out orelse error.WinRTFailed; }
    pub fn start(self: *@This(), callback: ?*anyopaque) !void { try hrCheck(self.lpVtbl.Start(self, callback)); }
    pub fn Start(self: *@This(), callback: ?*anyopaque) !void { try self.start(callback); }
    pub fn loadComponent(self: *@This(), component: anytype, resourceLocator: ?*anyopaque) !void { try hrCheck(self.lpVtbl.LoadComponent(self, @ptrCast(component), resourceLocator)); }
    pub fn LoadComponent(self: *@This(), component: anytype, resourceLocator: ?*anyopaque) !void { try self.loadComponent(component, resourceLocator); }
    pub fn loadComponent_1(self: *@This(), component: anytype, resourceLocator: ?*anyopaque, componentResourceLocation: i32) !void { try hrCheck(self.lpVtbl.LoadComponent_1(self, @ptrCast(component), resourceLocator, componentResourceLocation)); }
    pub fn LoadComponent_1(self: *@This(), component: anytype, resourceLocator: ?*anyopaque, componentResourceLocation: i32) !void { try self.loadComponent_1(component, resourceLocator, componentResourceLocation); }
};

pub const IApplicationFactory = extern struct {
    pub const IID = GUID{ .data1 = 0x9fd96657, .data2 = 0x5294, .data3 = 0x5a65, .data4 = .{ 0xa1, 0xdb, 0x4f, 0xea, 0x14, 0x35, 0x97, 0xda } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        CreateInstance: *const fn (*anyopaque, HSTRING, *HSTRING, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn CreateInstance(self: *@This(), outer: ?*anyopaque) !struct { inner: ?*anyopaque, instance: *IInspectable } { var inner: ?*anyopaque = null; var instance: ?*anyopaque = null; try hrCheck(self.lpVtbl.CreateInstance(self, outer, &inner, &instance)); return .{ .inner = inner, .instance = @ptrCast(@alignCast(instance.?)) }; }
};

pub const IApplication = extern struct {
    pub const IID = GUID{ .data1 = 0x06a8f4e7, .data2 = 0x1146, .data3 = 0x55af, .data4 = .{ 0x82, 0x0d, 0xeb, 0xd5, 0x56, 0x43, 0xb0, 0x21 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Resources: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetResources: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        DebugSettings: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        RequestedTheme: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetRequestedTheme: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        FocusVisualKind: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetFocusVisualKind: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        HighContrastAdjustment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetHighContrastAdjustment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        UnhandledException: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveUnhandledException: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Exit: *const fn (*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Resources(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Resources(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetResources(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetResources(self, value)); }
    pub fn DebugSettings(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.DebugSettings(self, &out)); return out orelse error.WinRTFailed; }
    pub fn RequestedTheme(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.RequestedTheme(self, &out)); return out; }
    pub fn SetRequestedTheme(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetRequestedTheme(self, value)); }
    pub fn FocusVisualKind(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.FocusVisualKind(self, &out)); return out; }
    pub fn SetFocusVisualKind(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetFocusVisualKind(self, value)); }
    pub fn HighContrastAdjustment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.HighContrastAdjustment(self, &out)); return out; }
    pub fn SetHighContrastAdjustment(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetHighContrastAdjustment(self, value)); }
    pub fn AddUnhandledException(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.UnhandledException(self, p0, &out0)); return out0; }
    pub fn UnhandledException(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddUnhandledException(p0); }
    pub fn RemoveUnhandledException(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveUnhandledException(self, token)); }
    pub fn exit(self: *@This()) !void { try hrCheck(self.lpVtbl.Exit(self)); }
    pub fn Exit(self: *@This()) !void { try self.exit(); }
};

pub const IWindow = extern struct {
    pub const IID = GUID{ .data1 = 0x61f0ec79, .data2 = 0x5d52, .data3 = 0x56b5, .data4 = .{ 0x86, 0xfb, 0x40, 0xfa, 0x4a, 0xf2, 0x88, 0xb0 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Bounds: *const fn (*anyopaque, *Rect) callconv(.winapi) HRESULT,
        Visible: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        Content: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetContent: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CoreWindow: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Compositor: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Dispatcher: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        DispatcherQueue: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Title: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTitle: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        ExtendsContentIntoTitleBar: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetExtendsContentIntoTitleBar: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        Activated: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveActivated: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Closed: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveClosed: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        SizeChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveSizeChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        VisibilityChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveVisibilityChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Activate: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        Close: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        SetTitleBar: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Bounds(self: *@This()) !Rect { var out: Rect = undefined; try hrCheck(self.lpVtbl.Bounds(self, &out)); return out; }
    pub fn Visible(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.Visible(self, &out)); return out; }
    pub fn Content(self: *@This()) !?*IInspectable { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Content(self, &out)); if (out) |p| return @ptrCast(@alignCast(p)); return null; }
    pub fn SetContent(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetContent(self, value)); }
    pub fn CoreWindow(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.CoreWindow(self, &out)); return out orelse error.WinRTFailed; }
    pub fn Compositor(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Compositor(self, &out)); return out orelse error.WinRTFailed; }
    pub fn Dispatcher(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Dispatcher(self, &out)); return out orelse error.WinRTFailed; }
    pub fn DispatcherQueue(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.DispatcherQueue(self, &out)); return out orelse error.WinRTFailed; }
    pub fn Title(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Title(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTitle(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTitle(self, value)); }
    pub fn ExtendsContentIntoTitleBar(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.ExtendsContentIntoTitleBar(self, &out)); return out; }
    pub fn SetExtendsContentIntoTitleBar(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetExtendsContentIntoTitleBar(self, value)); }
    pub fn AddActivated(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.Activated(self, p0, &out0)); return out0; }
    pub fn Activated(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddActivated(p0); }
    pub fn RemoveActivated(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveActivated(self, token)); }
    pub fn AddClosed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.Closed(self, p0, &out0)); return out0; }
    pub fn Closed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddClosed(p0); }
    pub fn RemoveClosed(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveClosed(self, token)); }
    pub fn AddSizeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.SizeChanged(self, p0, &out0)); return out0; }
    pub fn SizeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddSizeChanged(p0); }
    pub fn RemoveSizeChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveSizeChanged(self, token)); }
    pub fn AddVisibilityChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.VisibilityChanged(self, p0, &out0)); return out0; }
    pub fn VisibilityChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddVisibilityChanged(p0); }
    pub fn RemoveVisibilityChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveVisibilityChanged(self, token)); }
    pub fn activate(self: *@This()) !void { try hrCheck(self.lpVtbl.Activate(self)); }
    pub fn Activate(self: *@This()) !void { try self.activate(); }
    pub fn close(self: *@This()) !void { try hrCheck(self.lpVtbl.Close(self)); }
    pub fn Close(self: *@This()) !void { try self.close(); }
    pub fn setTitleBar(self: *@This(), titleBar: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTitleBar(self, titleBar)); }
    pub fn SetTitleBar(self: *@This(), titleBar: ?*anyopaque) !void { try self.setTitleBar(titleBar); }
};

pub const ITabView = extern struct {
    pub const IID = GUID{ .data1 = 0x07b509e1, .data2 = 0x1d38, .data3 = 0x551b, .data4 = .{ 0x95, 0xf4, 0x47, 0x32, 0xb0, 0x49, 0xf6, 0xa6 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        TabWidthMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetTabWidthMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        CloseButtonOverlayMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetCloseButtonOverlayMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        TabStripHeader: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetTabStripHeader: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        TabStripHeaderTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTabStripHeaderTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        TabStripFooter: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetTabStripFooter: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        TabStripFooterTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTabStripFooterTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        IsAddTabButtonVisible: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsAddTabButtonVisible: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        AddTabButtonCommand: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetAddTabButtonCommand: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        AddTabButtonCommandParameter: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetAddTabButtonCommandParameter: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        TabCloseRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTabCloseRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TabDroppedOutside: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTabDroppedOutside: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        AddTabButtonClick: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveAddTabButtonClick: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TabItemsChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTabItemsChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TabItemsSource: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetTabItemsSource: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        TabItems: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        TabItemTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTabItemTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        TabItemTemplateSelector: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTabItemTemplateSelector: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CanDragTabs: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetCanDragTabs: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        CanReorderTabs: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetCanReorderTabs: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        AllowDropTabs: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetAllowDropTabs: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        SelectedIndex: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetSelectedIndex: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SelectedItem: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetSelectedItem: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        ContainerFromItem: *const fn (*anyopaque, HSTRING, *?*anyopaque) callconv(.winapi) HRESULT,
        ContainerFromIndex: *const fn (*anyopaque, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        SelectionChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveSelectionChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TabDragStarting: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTabDragStarting: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TabDragCompleted: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTabDragCompleted: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TabStripDragOver: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTabStripDragOver: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TabStripDrop: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTabStripDrop: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn TabWidthMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.TabWidthMode(self, &out)); return out; }
    pub fn SetTabWidthMode(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetTabWidthMode(self, value)); }
    pub fn CloseButtonOverlayMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.CloseButtonOverlayMode(self, &out)); return out; }
    pub fn SetCloseButtonOverlayMode(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetCloseButtonOverlayMode(self, value)); }
    pub fn TabStripHeader(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.TabStripHeader(self, &out)); return out; }
    pub fn SetTabStripHeader(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetTabStripHeader(self, @ptrCast(value))); }
    pub fn TabStripHeaderTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.TabStripHeaderTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTabStripHeaderTemplate(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTabStripHeaderTemplate(self, value)); }
    pub fn TabStripFooter(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.TabStripFooter(self, &out)); return out; }
    pub fn SetTabStripFooter(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetTabStripFooter(self, @ptrCast(value))); }
    pub fn TabStripFooterTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.TabStripFooterTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTabStripFooterTemplate(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTabStripFooterTemplate(self, value)); }
    pub fn IsAddTabButtonVisible(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsAddTabButtonVisible(self, &out)); return out; }
    pub fn SetIsAddTabButtonVisible(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsAddTabButtonVisible(self, value)); }
    pub fn AddTabButtonCommand(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.AddTabButtonCommand(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetAddTabButtonCommand(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetAddTabButtonCommand(self, value)); }
    pub fn AddTabButtonCommandParameter(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.AddTabButtonCommandParameter(self, &out)); return out; }
    pub fn SetAddTabButtonCommandParameter(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetAddTabButtonCommandParameter(self, @ptrCast(value))); }
    pub fn AddTabCloseRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TabCloseRequested(self, p0, &out0)); return out0; }
    pub fn TabCloseRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTabCloseRequested(p0); }
    pub fn RemoveTabCloseRequested(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTabCloseRequested(self, token)); }
    pub fn AddTabDroppedOutside(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TabDroppedOutside(self, p0, &out0)); return out0; }
    pub fn TabDroppedOutside(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTabDroppedOutside(p0); }
    pub fn RemoveTabDroppedOutside(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTabDroppedOutside(self, token)); }
    pub fn AddAddTabButtonClick(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.AddTabButtonClick(self, p0, &out0)); return out0; }
    pub fn AddTabButtonClick(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddAddTabButtonClick(p0); }
    pub fn RemoveAddTabButtonClick(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveAddTabButtonClick(self, token)); }
    pub fn AddTabItemsChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TabItemsChanged(self, p0, &out0)); return out0; }
    pub fn TabItemsChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTabItemsChanged(p0); }
    pub fn RemoveTabItemsChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTabItemsChanged(self, token)); }
    pub fn TabItemsSource(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.TabItemsSource(self, &out)); return out; }
    pub fn SetTabItemsSource(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetTabItemsSource(self, @ptrCast(value))); }
    pub fn TabItems(self: *@This()) !*IVector { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.TabItems(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn TabItemTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.TabItemTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTabItemTemplate(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTabItemTemplate(self, value)); }
    pub fn TabItemTemplateSelector(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.TabItemTemplateSelector(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTabItemTemplateSelector(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTabItemTemplateSelector(self, value)); }
    pub fn CanDragTabs(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.CanDragTabs(self, &out)); return out; }
    pub fn SetCanDragTabs(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetCanDragTabs(self, value)); }
    pub fn CanReorderTabs(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.CanReorderTabs(self, &out)); return out; }
    pub fn SetCanReorderTabs(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetCanReorderTabs(self, value)); }
    pub fn AllowDropTabs(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.AllowDropTabs(self, &out)); return out; }
    pub fn SetAllowDropTabs(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetAllowDropTabs(self, value)); }
    pub fn SelectedIndex(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.SelectedIndex(self, &out)); return out; }
    pub fn SetSelectedIndex(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetSelectedIndex(self, value)); }
    pub fn SelectedItem(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.SelectedItem(self, &out)); return out; }
    pub fn SetSelectedItem(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetSelectedItem(self, @ptrCast(value))); }
    pub fn containerFromItem(self: *@This(), p0: anytype) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.ContainerFromItem(self, @ptrCast(p0), &out0)); return out0; }
    pub fn ContainerFromItem(self: *@This(), p0: anytype) !?*anyopaque { return self.containerFromItem(p0); }
    pub fn containerFromIndex(self: *@This(), p0: i32) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.ContainerFromIndex(self, p0, &out0)); return out0; }
    pub fn ContainerFromIndex(self: *@This(), p0: i32) !?*anyopaque { return self.containerFromIndex(p0); }
    pub fn AddSelectionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.SelectionChanged(self, p0, &out0)); return out0; }
    pub fn SelectionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddSelectionChanged(p0); }
    pub fn RemoveSelectionChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveSelectionChanged(self, token)); }
    pub fn AddTabDragStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TabDragStarting(self, p0, &out0)); return out0; }
    pub fn TabDragStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTabDragStarting(p0); }
    pub fn RemoveTabDragStarting(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTabDragStarting(self, token)); }
    pub fn AddTabDragCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TabDragCompleted(self, p0, &out0)); return out0; }
    pub fn TabDragCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTabDragCompleted(p0); }
    pub fn RemoveTabDragCompleted(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTabDragCompleted(self, token)); }
    pub fn AddTabStripDragOver(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TabStripDragOver(self, p0, &out0)); return out0; }
    pub fn TabStripDragOver(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTabStripDragOver(p0); }
    pub fn RemoveTabStripDragOver(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTabStripDragOver(self, token)); }
    pub fn AddTabStripDrop(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TabStripDrop(self, p0, &out0)); return out0; }
    pub fn TabStripDrop(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTabStripDrop(p0); }
    pub fn RemoveTabStripDrop(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTabStripDrop(self, token)); }
};

pub const ITabViewItem = extern struct {
    pub const IID = GUID{ .data1 = 0x64980afa, .data2 = 0x97af, .data3 = 0x5190, .data4 = .{ 0x90, 0xb3, 0x4b, 0xa2, 0x77, 0xb1, 0x11, 0x3d } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Header: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetHeader: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        HeaderTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetHeaderTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        IconSource: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetIconSource: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        IsClosable: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsClosable: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        TabViewTemplateSettings: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CloseRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveCloseRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Header(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.Header(self, &out)); return out; }
    pub fn SetHeader(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetHeader(self, @ptrCast(value))); }
    pub fn HeaderTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.HeaderTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetHeaderTemplate(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetHeaderTemplate(self, value)); }
    pub fn IconSource(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.IconSource(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetIconSource(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetIconSource(self, value)); }
    pub fn IsClosable(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsClosable(self, &out)); return out; }
    pub fn SetIsClosable(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsClosable(self, value)); }
    pub fn TabViewTemplateSettings(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.TabViewTemplateSettings(self, &out)); return out orelse error.WinRTFailed; }
    pub fn AddCloseRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.CloseRequested(self, p0, &out0)); return out0; }
    pub fn CloseRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddCloseRequested(p0); }
    pub fn RemoveCloseRequested(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveCloseRequested(self, token)); }
};

pub const ITabViewTabCloseRequestedEventArgs = extern struct {
    pub const IID = GUID{ .data1 = 0xd56ab9b2, .data2 = 0xe264, .data3 = 0x5c7e, .data4 = .{ 0xa1, 0xcb, 0xe4, 0x1a, 0x16, 0xa6, 0xc6, 0xc6 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Item: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        Tab: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Item(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.Item(self, &out)); return out; }
    pub fn Tab(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Tab(self, &out)); return out orelse error.WinRTFailed; }
};

pub const IContentControl = extern struct {
    pub const IID = GUID{ .data1 = 0x07e81761, .data2 = 0x11b2, .data3 = 0x52ae, .data4 = .{ 0x8f, 0x8b, 0x4d, 0x53, 0xd2, 0xb5, 0x90, 0x0a } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Content: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetContent: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        ContentTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetContentTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        ContentTemplateSelector: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetContentTemplateSelector: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        ContentTransitions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetContentTransitions: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        ContentTemplateRoot: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Content(self: *@This()) !?*IInspectable { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Content(self, &out)); if (out) |p| return @ptrCast(@alignCast(p)); return null; }
    pub fn SetContent(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetContent(self, @ptrCast(value))); }
    pub fn ContentTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ContentTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetContentTemplate(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetContentTemplate(self, value)); }
    pub fn ContentTemplateSelector(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ContentTemplateSelector(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetContentTemplateSelector(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetContentTemplateSelector(self, value)); }
    pub fn ContentTransitions(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ContentTransitions(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetContentTransitions(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetContentTransitions(self, value)); }
    pub fn ContentTemplateRoot(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ContentTemplateRoot(self, &out)); return out orelse error.WinRTFailed; }
};

pub const IUIElement = extern struct {
    pub const IID = GUID{ .data1 = 0xc3c01020, .data2 = 0x320c, .data3 = 0x5cf6, .data4 = .{ 0x9d, 0x24, 0xd3, 0x96, 0xbb, 0xfa, 0x4d, 0x8b } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        DesiredSize: *const fn (*anyopaque, *Size) callconv(.winapi) HRESULT,
        AllowDrop: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetAllowDrop: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        Opacity: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetOpacity: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        Clip: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetClip: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        RenderTransform: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetRenderTransform: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Projection: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetProjection: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Transform3D: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTransform3D: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        RenderTransformOrigin: *const fn (*anyopaque, *Point) callconv(.winapi) HRESULT,
        SetRenderTransformOrigin: *const fn (*anyopaque, Point) callconv(.winapi) HRESULT,
        IsHitTestVisible: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsHitTestVisible: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        Visibility: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetVisibility: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        RenderSize: *const fn (*anyopaque, *Size) callconv(.winapi) HRESULT,
        UseLayoutRounding: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetUseLayoutRounding: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        Transitions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTransitions: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CacheMode: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetCacheMode: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        IsTapEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsTapEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        IsDoubleTapEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsDoubleTapEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        CanDrag: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetCanDrag: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        IsRightTapEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsRightTapEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        IsHoldingEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsHoldingEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        ManipulationMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetManipulationMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        PointerCaptures: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        ContextFlyout: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetContextFlyout: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CompositeMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetCompositeMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        Lights: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CanBeScrollAnchor: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetCanBeScrollAnchor: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        ExitDisplayModeOnAccessKeyInvoked: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetExitDisplayModeOnAccessKeyInvoked: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        IsAccessKeyScope: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsAccessKeyScope: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        AccessKeyScopeOwner: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetAccessKeyScopeOwner: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        AccessKey: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetAccessKey: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        KeyTipPlacementMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetKeyTipPlacementMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        KeyTipHorizontalOffset: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetKeyTipHorizontalOffset: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        KeyTipVerticalOffset: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetKeyTipVerticalOffset: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        KeyTipTarget: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetKeyTipTarget: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        XYFocusKeyboardNavigation: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetXYFocusKeyboardNavigation: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        XYFocusUpNavigationStrategy: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetXYFocusUpNavigationStrategy: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        XYFocusDownNavigationStrategy: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetXYFocusDownNavigationStrategy: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        XYFocusLeftNavigationStrategy: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetXYFocusLeftNavigationStrategy: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        XYFocusRightNavigationStrategy: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetXYFocusRightNavigationStrategy: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        KeyboardAccelerators: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        KeyboardAcceleratorPlacementTarget: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetKeyboardAcceleratorPlacementTarget: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        KeyboardAcceleratorPlacementMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetKeyboardAcceleratorPlacementMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        HighContrastAdjustment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetHighContrastAdjustment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        TabFocusNavigation: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetTabFocusNavigation: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        OpacityTransition: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetOpacityTransition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Translation: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTranslation: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        TranslationTransition: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTranslationTransition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Rotation: *const fn (*anyopaque, *f32) callconv(.winapi) HRESULT,
        SetRotation: *const fn (*anyopaque, f32) callconv(.winapi) HRESULT,
        RotationTransition: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetRotationTransition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Scale: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetScale: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        ScaleTransition: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetScaleTransition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        TransformMatrix: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTransformMatrix: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CenterPoint: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetCenterPoint: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        RotationAxis: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetRotationAxis: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        ActualOffset: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        ActualSize: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        XamlRoot: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetXamlRoot: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Shadow: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetShadow: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        RasterizationScale: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetRasterizationScale: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        FocusState: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        UseSystemFocusVisuals: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetUseSystemFocusVisuals: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        XYFocusLeft: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetXYFocusLeft: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        XYFocusRight: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetXYFocusRight: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        XYFocusUp: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetXYFocusUp: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        XYFocusDown: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetXYFocusDown: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        IsTabStop: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsTabStop: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        TabIndex: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetTabIndex: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        KeyUp: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveKeyUp: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        KeyDown: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveKeyDown: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        GotFocus: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveGotFocus: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        LostFocus: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveLostFocus: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        DragStarting: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveDragStarting: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        DropCompleted: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveDropCompleted: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        CharacterReceived: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveCharacterReceived: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        DragEnter: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveDragEnter: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        DragLeave: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveDragLeave: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        DragOver: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveDragOver: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Drop: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveDrop: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        PointerPressed: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePointerPressed: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        PointerMoved: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePointerMoved: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        PointerReleased: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePointerReleased: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        PointerEntered: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePointerEntered: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        PointerExited: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePointerExited: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        PointerCaptureLost: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePointerCaptureLost: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        PointerCanceled: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePointerCanceled: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        PointerWheelChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePointerWheelChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Tapped: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTapped: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        DoubleTapped: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveDoubleTapped: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Holding: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveHolding: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        ContextRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveContextRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        ContextCanceled: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveContextCanceled: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        RightTapped: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveRightTapped: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        ManipulationStarting: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveManipulationStarting: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        ManipulationInertiaStarting: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveManipulationInertiaStarting: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        ManipulationStarted: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveManipulationStarted: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        ManipulationDelta: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveManipulationDelta: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        ManipulationCompleted: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveManipulationCompleted: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        AccessKeyDisplayRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveAccessKeyDisplayRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        AccessKeyDisplayDismissed: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveAccessKeyDisplayDismissed: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        AccessKeyInvoked: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveAccessKeyInvoked: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        ProcessKeyboardAccelerators: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveProcessKeyboardAccelerators: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        GettingFocus: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveGettingFocus: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        LosingFocus: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveLosingFocus: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        NoFocusCandidateFound: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveNoFocusCandidateFound: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        PreviewKeyDown: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePreviewKeyDown: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        PreviewKeyUp: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePreviewKeyUp: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        BringIntoViewRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveBringIntoViewRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Measure: *const fn (*anyopaque, Size) callconv(.winapi) HRESULT,
        Arrange: *const fn (*anyopaque, Rect) callconv(.winapi) HRESULT,
        CapturePointer: *const fn (*anyopaque, ?*anyopaque, *bool) callconv(.winapi) HRESULT,
        ReleasePointerCapture: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        ReleasePointerCaptures: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        AddHandler: *const fn (*anyopaque, ?*anyopaque, HSTRING, bool) callconv(.winapi) HRESULT,
        RemoveHandler: *const fn (*anyopaque, ?*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        TransformToVisual: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        InvalidateMeasure: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        InvalidateArrange: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        UpdateLayout: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        CancelDirectManipulations: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        StartDragAsync: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        StartBringIntoView: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        StartBringIntoView_1: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        TryInvokeKeyboardAccelerator: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Focus: *const fn (*anyopaque, i32, *bool) callconv(.winapi) HRESULT,
        StartAnimation: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        StopAnimation: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn DesiredSize(self: *@This()) !Size { var out: Size = undefined; try hrCheck(self.lpVtbl.DesiredSize(self, &out)); return out; }
    pub fn AllowDrop(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.AllowDrop(self, &out)); return out; }
    pub fn SetAllowDrop(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetAllowDrop(self, value)); }
    pub fn Opacity(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.Opacity(self, &out)); return out; }
    pub fn SetOpacity(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetOpacity(self, value)); }
    pub fn Clip(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Clip(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetClip(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetClip(self, value)); }
    pub fn RenderTransform(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.RenderTransform(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetRenderTransform(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetRenderTransform(self, value)); }
    pub fn Projection(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Projection(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetProjection(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetProjection(self, value)); }
    pub fn Transform3D(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Transform3D(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTransform3D(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTransform3D(self, value)); }
    pub fn RenderTransformOrigin(self: *@This()) !Point { var out: Point = undefined; try hrCheck(self.lpVtbl.RenderTransformOrigin(self, &out)); return out; }
    pub fn SetRenderTransformOrigin(self: *@This(), value: Point) !void { try hrCheck(self.lpVtbl.SetRenderTransformOrigin(self, value)); }
    pub fn IsHitTestVisible(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsHitTestVisible(self, &out)); return out; }
    pub fn SetIsHitTestVisible(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsHitTestVisible(self, value)); }
    pub fn Visibility(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.Visibility(self, &out)); return out; }
    pub fn SetVisibility(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetVisibility(self, value)); }
    pub fn RenderSize(self: *@This()) !Size { var out: Size = undefined; try hrCheck(self.lpVtbl.RenderSize(self, &out)); return out; }
    pub fn UseLayoutRounding(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.UseLayoutRounding(self, &out)); return out; }
    pub fn SetUseLayoutRounding(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetUseLayoutRounding(self, value)); }
    pub fn Transitions(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Transitions(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTransitions(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTransitions(self, value)); }
    pub fn CacheMode(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.CacheMode(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetCacheMode(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetCacheMode(self, value)); }
    pub fn IsTapEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsTapEnabled(self, &out)); return out; }
    pub fn SetIsTapEnabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsTapEnabled(self, value)); }
    pub fn IsDoubleTapEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsDoubleTapEnabled(self, &out)); return out; }
    pub fn SetIsDoubleTapEnabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsDoubleTapEnabled(self, value)); }
    pub fn CanDrag(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.CanDrag(self, &out)); return out; }
    pub fn SetCanDrag(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetCanDrag(self, value)); }
    pub fn IsRightTapEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsRightTapEnabled(self, &out)); return out; }
    pub fn SetIsRightTapEnabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsRightTapEnabled(self, value)); }
    pub fn IsHoldingEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsHoldingEnabled(self, &out)); return out; }
    pub fn SetIsHoldingEnabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsHoldingEnabled(self, value)); }
    pub fn ManipulationMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.ManipulationMode(self, &out)); return out; }
    pub fn SetManipulationMode(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetManipulationMode(self, value)); }
    pub fn PointerCaptures(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.PointerCaptures(self, &out)); return out orelse error.WinRTFailed; }
    pub fn ContextFlyout(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ContextFlyout(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetContextFlyout(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetContextFlyout(self, value)); }
    pub fn CompositeMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.CompositeMode(self, &out)); return out; }
    pub fn SetCompositeMode(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetCompositeMode(self, value)); }
    pub fn Lights(self: *@This()) !*IVector { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Lights(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn CanBeScrollAnchor(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.CanBeScrollAnchor(self, &out)); return out; }
    pub fn SetCanBeScrollAnchor(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetCanBeScrollAnchor(self, value)); }
    pub fn ExitDisplayModeOnAccessKeyInvoked(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.ExitDisplayModeOnAccessKeyInvoked(self, &out)); return out; }
    pub fn SetExitDisplayModeOnAccessKeyInvoked(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetExitDisplayModeOnAccessKeyInvoked(self, value)); }
    pub fn IsAccessKeyScope(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsAccessKeyScope(self, &out)); return out; }
    pub fn SetIsAccessKeyScope(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsAccessKeyScope(self, value)); }
    pub fn AccessKeyScopeOwner(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.AccessKeyScopeOwner(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetAccessKeyScopeOwner(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetAccessKeyScopeOwner(self, value)); }
    pub fn AccessKey(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.AccessKey(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetAccessKey(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetAccessKey(self, value)); }
    pub fn KeyTipPlacementMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.KeyTipPlacementMode(self, &out)); return out; }
    pub fn SetKeyTipPlacementMode(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetKeyTipPlacementMode(self, value)); }
    pub fn KeyTipHorizontalOffset(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.KeyTipHorizontalOffset(self, &out)); return out; }
    pub fn SetKeyTipHorizontalOffset(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetKeyTipHorizontalOffset(self, value)); }
    pub fn KeyTipVerticalOffset(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.KeyTipVerticalOffset(self, &out)); return out; }
    pub fn SetKeyTipVerticalOffset(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetKeyTipVerticalOffset(self, value)); }
    pub fn KeyTipTarget(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.KeyTipTarget(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetKeyTipTarget(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetKeyTipTarget(self, value)); }
    pub fn XYFocusKeyboardNavigation(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.XYFocusKeyboardNavigation(self, &out)); return out; }
    pub fn SetXYFocusKeyboardNavigation(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetXYFocusKeyboardNavigation(self, value)); }
    pub fn XYFocusUpNavigationStrategy(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.XYFocusUpNavigationStrategy(self, &out)); return out; }
    pub fn SetXYFocusUpNavigationStrategy(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetXYFocusUpNavigationStrategy(self, value)); }
    pub fn XYFocusDownNavigationStrategy(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.XYFocusDownNavigationStrategy(self, &out)); return out; }
    pub fn SetXYFocusDownNavigationStrategy(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetXYFocusDownNavigationStrategy(self, value)); }
    pub fn XYFocusLeftNavigationStrategy(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.XYFocusLeftNavigationStrategy(self, &out)); return out; }
    pub fn SetXYFocusLeftNavigationStrategy(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetXYFocusLeftNavigationStrategy(self, value)); }
    pub fn XYFocusRightNavigationStrategy(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.XYFocusRightNavigationStrategy(self, &out)); return out; }
    pub fn SetXYFocusRightNavigationStrategy(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetXYFocusRightNavigationStrategy(self, value)); }
    pub fn KeyboardAccelerators(self: *@This()) !*IVector { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.KeyboardAccelerators(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn KeyboardAcceleratorPlacementTarget(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.KeyboardAcceleratorPlacementTarget(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetKeyboardAcceleratorPlacementTarget(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetKeyboardAcceleratorPlacementTarget(self, value)); }
    pub fn KeyboardAcceleratorPlacementMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.KeyboardAcceleratorPlacementMode(self, &out)); return out; }
    pub fn SetKeyboardAcceleratorPlacementMode(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetKeyboardAcceleratorPlacementMode(self, value)); }
    pub fn HighContrastAdjustment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.HighContrastAdjustment(self, &out)); return out; }
    pub fn SetHighContrastAdjustment(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetHighContrastAdjustment(self, value)); }
    pub fn TabFocusNavigation(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.TabFocusNavigation(self, &out)); return out; }
    pub fn SetTabFocusNavigation(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetTabFocusNavigation(self, value)); }
    pub fn OpacityTransition(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.OpacityTransition(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetOpacityTransition(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetOpacityTransition(self, value)); }
    pub fn Translation(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Translation(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTranslation(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTranslation(self, value)); }
    pub fn TranslationTransition(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.TranslationTransition(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTranslationTransition(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTranslationTransition(self, value)); }
    pub fn Rotation(self: *@This()) !f32 { var out: f32 = 0; try hrCheck(self.lpVtbl.Rotation(self, &out)); return out; }
    pub fn SetRotation(self: *@This(), value: f32) !void { try hrCheck(self.lpVtbl.SetRotation(self, value)); }
    pub fn RotationTransition(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.RotationTransition(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetRotationTransition(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetRotationTransition(self, value)); }
    pub fn Scale(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Scale(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetScale(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetScale(self, value)); }
    pub fn ScaleTransition(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ScaleTransition(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetScaleTransition(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetScaleTransition(self, value)); }
    pub fn TransformMatrix(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.TransformMatrix(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTransformMatrix(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTransformMatrix(self, value)); }
    pub fn CenterPoint(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.CenterPoint(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetCenterPoint(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetCenterPoint(self, value)); }
    pub fn RotationAxis(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.RotationAxis(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetRotationAxis(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetRotationAxis(self, value)); }
    pub fn ActualOffset(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ActualOffset(self, &out)); return out orelse error.WinRTFailed; }
    pub fn ActualSize(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ActualSize(self, &out)); return out orelse error.WinRTFailed; }
    pub fn XamlRoot(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.XamlRoot(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetXamlRoot(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetXamlRoot(self, value)); }
    pub fn Shadow(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Shadow(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetShadow(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetShadow(self, value)); }
    pub fn RasterizationScale(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.RasterizationScale(self, &out)); return out; }
    pub fn SetRasterizationScale(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetRasterizationScale(self, value)); }
    pub fn FocusState(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.FocusState(self, &out)); return out; }
    pub fn UseSystemFocusVisuals(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.UseSystemFocusVisuals(self, &out)); return out; }
    pub fn SetUseSystemFocusVisuals(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetUseSystemFocusVisuals(self, value)); }
    pub fn XYFocusLeft(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.XYFocusLeft(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetXYFocusLeft(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetXYFocusLeft(self, value)); }
    pub fn XYFocusRight(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.XYFocusRight(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetXYFocusRight(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetXYFocusRight(self, value)); }
    pub fn XYFocusUp(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.XYFocusUp(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetXYFocusUp(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetXYFocusUp(self, value)); }
    pub fn XYFocusDown(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.XYFocusDown(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetXYFocusDown(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetXYFocusDown(self, value)); }
    pub fn IsTabStop(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsTabStop(self, &out)); return out; }
    pub fn SetIsTabStop(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsTabStop(self, value)); }
    pub fn TabIndex(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.TabIndex(self, &out)); return out; }
    pub fn SetTabIndex(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetTabIndex(self, value)); }
    pub fn AddKeyUp(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.KeyUp(self, p0, &out0)); return out0; }
    pub fn KeyUp(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddKeyUp(p0); }
    pub fn RemoveKeyUp(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveKeyUp(self, token)); }
    pub fn AddKeyDown(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.KeyDown(self, p0, &out0)); return out0; }
    pub fn KeyDown(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddKeyDown(p0); }
    pub fn RemoveKeyDown(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveKeyDown(self, token)); }
    pub fn AddGotFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.GotFocus(self, p0, &out0)); return out0; }
    pub fn GotFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddGotFocus(p0); }
    pub fn RemoveGotFocus(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveGotFocus(self, token)); }
    pub fn AddLostFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.LostFocus(self, p0, &out0)); return out0; }
    pub fn LostFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddLostFocus(p0); }
    pub fn RemoveLostFocus(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveLostFocus(self, token)); }
    pub fn AddDragStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.DragStarting(self, p0, &out0)); return out0; }
    pub fn DragStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddDragStarting(p0); }
    pub fn RemoveDragStarting(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveDragStarting(self, token)); }
    pub fn AddDropCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.DropCompleted(self, p0, &out0)); return out0; }
    pub fn DropCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddDropCompleted(p0); }
    pub fn RemoveDropCompleted(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveDropCompleted(self, token)); }
    pub fn AddCharacterReceived(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.CharacterReceived(self, p0, &out0)); return out0; }
    pub fn CharacterReceived(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddCharacterReceived(p0); }
    pub fn RemoveCharacterReceived(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveCharacterReceived(self, token)); }
    pub fn AddDragEnter(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.DragEnter(self, p0, &out0)); return out0; }
    pub fn DragEnter(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddDragEnter(p0); }
    pub fn RemoveDragEnter(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveDragEnter(self, token)); }
    pub fn AddDragLeave(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.DragLeave(self, p0, &out0)); return out0; }
    pub fn DragLeave(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddDragLeave(p0); }
    pub fn RemoveDragLeave(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveDragLeave(self, token)); }
    pub fn AddDragOver(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.DragOver(self, p0, &out0)); return out0; }
    pub fn DragOver(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddDragOver(p0); }
    pub fn RemoveDragOver(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveDragOver(self, token)); }
    pub fn AddDrop(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.Drop(self, p0, &out0)); return out0; }
    pub fn Drop(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddDrop(p0); }
    pub fn RemoveDrop(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveDrop(self, token)); }
    pub fn AddPointerPressed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.PointerPressed(self, p0, &out0)); return out0; }
    pub fn PointerPressed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPointerPressed(p0); }
    pub fn RemovePointerPressed(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePointerPressed(self, token)); }
    pub fn AddPointerMoved(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.PointerMoved(self, p0, &out0)); return out0; }
    pub fn PointerMoved(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPointerMoved(p0); }
    pub fn RemovePointerMoved(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePointerMoved(self, token)); }
    pub fn AddPointerReleased(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.PointerReleased(self, p0, &out0)); return out0; }
    pub fn PointerReleased(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPointerReleased(p0); }
    pub fn RemovePointerReleased(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePointerReleased(self, token)); }
    pub fn AddPointerEntered(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.PointerEntered(self, p0, &out0)); return out0; }
    pub fn PointerEntered(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPointerEntered(p0); }
    pub fn RemovePointerEntered(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePointerEntered(self, token)); }
    pub fn AddPointerExited(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.PointerExited(self, p0, &out0)); return out0; }
    pub fn PointerExited(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPointerExited(p0); }
    pub fn RemovePointerExited(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePointerExited(self, token)); }
    pub fn AddPointerCaptureLost(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.PointerCaptureLost(self, p0, &out0)); return out0; }
    pub fn PointerCaptureLost(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPointerCaptureLost(p0); }
    pub fn RemovePointerCaptureLost(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePointerCaptureLost(self, token)); }
    pub fn AddPointerCanceled(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.PointerCanceled(self, p0, &out0)); return out0; }
    pub fn PointerCanceled(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPointerCanceled(p0); }
    pub fn RemovePointerCanceled(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePointerCanceled(self, token)); }
    pub fn AddPointerWheelChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.PointerWheelChanged(self, p0, &out0)); return out0; }
    pub fn PointerWheelChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPointerWheelChanged(p0); }
    pub fn RemovePointerWheelChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePointerWheelChanged(self, token)); }
    pub fn AddTapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.Tapped(self, p0, &out0)); return out0; }
    pub fn Tapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTapped(p0); }
    pub fn RemoveTapped(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTapped(self, token)); }
    pub fn AddDoubleTapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.DoubleTapped(self, p0, &out0)); return out0; }
    pub fn DoubleTapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddDoubleTapped(p0); }
    pub fn RemoveDoubleTapped(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveDoubleTapped(self, token)); }
    pub fn AddHolding(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.Holding(self, p0, &out0)); return out0; }
    pub fn Holding(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddHolding(p0); }
    pub fn RemoveHolding(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveHolding(self, token)); }
    pub fn AddContextRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.ContextRequested(self, p0, &out0)); return out0; }
    pub fn ContextRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddContextRequested(p0); }
    pub fn RemoveContextRequested(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveContextRequested(self, token)); }
    pub fn AddContextCanceled(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.ContextCanceled(self, p0, &out0)); return out0; }
    pub fn ContextCanceled(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddContextCanceled(p0); }
    pub fn RemoveContextCanceled(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveContextCanceled(self, token)); }
    pub fn AddRightTapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.RightTapped(self, p0, &out0)); return out0; }
    pub fn RightTapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddRightTapped(p0); }
    pub fn RemoveRightTapped(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveRightTapped(self, token)); }
    pub fn AddManipulationStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.ManipulationStarting(self, p0, &out0)); return out0; }
    pub fn ManipulationStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddManipulationStarting(p0); }
    pub fn RemoveManipulationStarting(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveManipulationStarting(self, token)); }
    pub fn AddManipulationInertiaStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.ManipulationInertiaStarting(self, p0, &out0)); return out0; }
    pub fn ManipulationInertiaStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddManipulationInertiaStarting(p0); }
    pub fn RemoveManipulationInertiaStarting(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveManipulationInertiaStarting(self, token)); }
    pub fn AddManipulationStarted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.ManipulationStarted(self, p0, &out0)); return out0; }
    pub fn ManipulationStarted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddManipulationStarted(p0); }
    pub fn RemoveManipulationStarted(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveManipulationStarted(self, token)); }
    pub fn AddManipulationDelta(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.ManipulationDelta(self, p0, &out0)); return out0; }
    pub fn ManipulationDelta(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddManipulationDelta(p0); }
    pub fn RemoveManipulationDelta(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveManipulationDelta(self, token)); }
    pub fn AddManipulationCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.ManipulationCompleted(self, p0, &out0)); return out0; }
    pub fn ManipulationCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddManipulationCompleted(p0); }
    pub fn RemoveManipulationCompleted(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveManipulationCompleted(self, token)); }
    pub fn AddAccessKeyDisplayRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.AccessKeyDisplayRequested(self, p0, &out0)); return out0; }
    pub fn AccessKeyDisplayRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddAccessKeyDisplayRequested(p0); }
    pub fn RemoveAccessKeyDisplayRequested(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveAccessKeyDisplayRequested(self, token)); }
    pub fn AddAccessKeyDisplayDismissed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.AccessKeyDisplayDismissed(self, p0, &out0)); return out0; }
    pub fn AccessKeyDisplayDismissed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddAccessKeyDisplayDismissed(p0); }
    pub fn RemoveAccessKeyDisplayDismissed(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveAccessKeyDisplayDismissed(self, token)); }
    pub fn AddAccessKeyInvoked(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.AccessKeyInvoked(self, p0, &out0)); return out0; }
    pub fn AccessKeyInvoked(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddAccessKeyInvoked(p0); }
    pub fn RemoveAccessKeyInvoked(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveAccessKeyInvoked(self, token)); }
    pub fn AddProcessKeyboardAccelerators(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.ProcessKeyboardAccelerators(self, p0, &out0)); return out0; }
    pub fn ProcessKeyboardAccelerators(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddProcessKeyboardAccelerators(p0); }
    pub fn RemoveProcessKeyboardAccelerators(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveProcessKeyboardAccelerators(self, token)); }
    pub fn AddGettingFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.GettingFocus(self, p0, &out0)); return out0; }
    pub fn GettingFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddGettingFocus(p0); }
    pub fn RemoveGettingFocus(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveGettingFocus(self, token)); }
    pub fn AddLosingFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.LosingFocus(self, p0, &out0)); return out0; }
    pub fn LosingFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddLosingFocus(p0); }
    pub fn RemoveLosingFocus(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveLosingFocus(self, token)); }
    pub fn AddNoFocusCandidateFound(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.NoFocusCandidateFound(self, p0, &out0)); return out0; }
    pub fn NoFocusCandidateFound(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddNoFocusCandidateFound(p0); }
    pub fn RemoveNoFocusCandidateFound(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveNoFocusCandidateFound(self, token)); }
    pub fn AddPreviewKeyDown(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.PreviewKeyDown(self, p0, &out0)); return out0; }
    pub fn PreviewKeyDown(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPreviewKeyDown(p0); }
    pub fn RemovePreviewKeyDown(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePreviewKeyDown(self, token)); }
    pub fn AddPreviewKeyUp(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.PreviewKeyUp(self, p0, &out0)); return out0; }
    pub fn PreviewKeyUp(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPreviewKeyUp(p0); }
    pub fn RemovePreviewKeyUp(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePreviewKeyUp(self, token)); }
    pub fn AddBringIntoViewRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.BringIntoViewRequested(self, p0, &out0)); return out0; }
    pub fn BringIntoViewRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddBringIntoViewRequested(p0); }
    pub fn RemoveBringIntoViewRequested(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveBringIntoViewRequested(self, token)); }
    pub fn measure(self: *@This(), availableSize: Size) !void { try hrCheck(self.lpVtbl.Measure(self, availableSize)); }
    pub fn Measure(self: *@This(), availableSize: Size) !void { try self.measure(availableSize); }
    pub fn arrange(self: *@This(), finalRect: Rect) !void { try hrCheck(self.lpVtbl.Arrange(self, finalRect)); }
    pub fn Arrange(self: *@This(), finalRect: Rect) !void { try self.arrange(finalRect); }
    pub fn capturePointer(self: *@This(), p0: ?*anyopaque) !bool { var out0: bool = false; try hrCheck(self.lpVtbl.CapturePointer(self, p0, &out0)); return out0; }
    pub fn CapturePointer(self: *@This(), p0: ?*anyopaque) !bool { return self.capturePointer(p0); }
    pub fn releasePointerCapture(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.ReleasePointerCapture(self, value)); }
    pub fn ReleasePointerCapture(self: *@This(), value: ?*anyopaque) !void { try self.releasePointerCapture(value); }
    pub fn releasePointerCaptures(self: *@This()) !void { try hrCheck(self.lpVtbl.ReleasePointerCaptures(self)); }
    pub fn ReleasePointerCaptures(self: *@This()) !void { try self.releasePointerCaptures(); }
    pub fn addHandler(self: *@This(), routedEvent: ?*anyopaque, handler: anytype, handledEventsToo: bool) !void { try hrCheck(self.lpVtbl.AddHandler(self, routedEvent, @ptrCast(handler), handledEventsToo)); }
    pub fn AddHandler(self: *@This(), routedEvent: ?*anyopaque, handler: anytype, handledEventsToo: bool) !void { try self.addHandler(routedEvent, handler, handledEventsToo); }
    pub fn removeHandler(self: *@This(), routedEvent: ?*anyopaque, handler: anytype) !void { try hrCheck(self.lpVtbl.RemoveHandler(self, routedEvent, @ptrCast(handler))); }
    pub fn RemoveHandler(self: *@This(), routedEvent: ?*anyopaque, handler: anytype) !void { try self.removeHandler(routedEvent, handler); }
    pub fn transformToVisual(self: *@This(), p0: ?*anyopaque) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.TransformToVisual(self, p0, &out0)); return out0; }
    pub fn TransformToVisual(self: *@This(), p0: ?*anyopaque) !?*anyopaque { return self.transformToVisual(p0); }
    pub fn invalidateMeasure(self: *@This()) !void { try hrCheck(self.lpVtbl.InvalidateMeasure(self)); }
    pub fn InvalidateMeasure(self: *@This()) !void { try self.invalidateMeasure(); }
    pub fn invalidateArrange(self: *@This()) !void { try hrCheck(self.lpVtbl.InvalidateArrange(self)); }
    pub fn InvalidateArrange(self: *@This()) !void { try self.invalidateArrange(); }
    pub fn updateLayout(self: *@This()) !void { try hrCheck(self.lpVtbl.UpdateLayout(self)); }
    pub fn UpdateLayout(self: *@This()) !void { try self.updateLayout(); }
    pub fn cancelDirectManipulations(self: *@This()) !bool { var out0: bool = false; try hrCheck(self.lpVtbl.CancelDirectManipulations(self, &out0)); return out0; }
    pub fn CancelDirectManipulations(self: *@This()) !bool { return self.cancelDirectManipulations(); }
    pub fn startDragAsync(self: *@This(), p0: ?*anyopaque) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.StartDragAsync(self, p0, &out0)); return out0; }
    pub fn StartDragAsync(self: *@This(), p0: ?*anyopaque) !?*anyopaque { return self.startDragAsync(p0); }
    pub fn startBringIntoView(self: *@This()) !void { try hrCheck(self.lpVtbl.StartBringIntoView(self)); }
    pub fn StartBringIntoView(self: *@This()) !void { try self.startBringIntoView(); }
    pub fn startBringIntoView_1(self: *@This(), options: ?*anyopaque) !void { try hrCheck(self.lpVtbl.StartBringIntoView_1(self, options)); }
    pub fn StartBringIntoView_1(self: *@This(), options: ?*anyopaque) !void { try self.startBringIntoView_1(options); }
    pub fn tryInvokeKeyboardAccelerator(self: *@This(), args: ?*anyopaque) !void { try hrCheck(self.lpVtbl.TryInvokeKeyboardAccelerator(self, args)); }
    pub fn TryInvokeKeyboardAccelerator(self: *@This(), args: ?*anyopaque) !void { try self.tryInvokeKeyboardAccelerator(args); }
    pub fn focus(self: *@This(), p0: i32) !bool { var out0: bool = false; try hrCheck(self.lpVtbl.Focus(self, p0, &out0)); return out0; }
    pub fn Focus(self: *@This(), p0: i32) !bool { return self.focus(p0); }
    pub fn startAnimation(self: *@This(), animation: ?*anyopaque) !void { try hrCheck(self.lpVtbl.StartAnimation(self, animation)); }
    pub fn StartAnimation(self: *@This(), animation: ?*anyopaque) !void { try self.startAnimation(animation); }
    pub fn stopAnimation(self: *@This(), animation: ?*anyopaque) !void { try hrCheck(self.lpVtbl.StopAnimation(self, animation)); }
    pub fn StopAnimation(self: *@This(), animation: ?*anyopaque) !void { try self.stopAnimation(animation); }
};

pub const IFrameworkElement = extern struct {
    pub const IID = GUID{ .data1 = 0xfe08f13d, .data2 = 0xdc6a, .data3 = 0x5495, .data4 = .{ 0xad, 0x44, 0xc2, 0xd8, 0xd2, 0x18, 0x63, 0xb0 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Triggers: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Resources: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetResources: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Tag: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetTag: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        Language: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetLanguage: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        ActualWidth: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        ActualHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        Width: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetWidth: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        Height: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetHeight: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        MinWidth: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetMinWidth: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        MaxWidth: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetMaxWidth: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        MinHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetMinHeight: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        MaxHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetMaxHeight: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        HorizontalAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetHorizontalAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        VerticalAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetVerticalAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        Margin: *const fn (*anyopaque, *Thickness) callconv(.winapi) HRESULT,
        SetMargin: *const fn (*anyopaque, Thickness) callconv(.winapi) HRESULT,
        Name: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetName: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        BaseUri: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        DataContext: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetDataContext: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        AllowFocusOnInteraction: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetAllowFocusOnInteraction: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        FocusVisualMargin: *const fn (*anyopaque, *Thickness) callconv(.winapi) HRESULT,
        SetFocusVisualMargin: *const fn (*anyopaque, Thickness) callconv(.winapi) HRESULT,
        FocusVisualSecondaryThickness: *const fn (*anyopaque, *Thickness) callconv(.winapi) HRESULT,
        SetFocusVisualSecondaryThickness: *const fn (*anyopaque, Thickness) callconv(.winapi) HRESULT,
        FocusVisualPrimaryThickness: *const fn (*anyopaque, *Thickness) callconv(.winapi) HRESULT,
        SetFocusVisualPrimaryThickness: *const fn (*anyopaque, Thickness) callconv(.winapi) HRESULT,
        FocusVisualSecondaryBrush: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetFocusVisualSecondaryBrush: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        FocusVisualPrimaryBrush: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetFocusVisualPrimaryBrush: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        AllowFocusWhenDisabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetAllowFocusWhenDisabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        Style: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetStyle: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Parent: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        FlowDirection: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetFlowDirection: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        RequestedTheme: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetRequestedTheme: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        IsLoaded: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        ActualTheme: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        Loaded: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveLoaded: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Unloaded: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveUnloaded: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        DataContextChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveDataContextChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        SizeChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveSizeChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        LayoutUpdated: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveLayoutUpdated: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Loading: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveLoading: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        ActualThemeChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveActualThemeChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        EffectiveViewportChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveEffectiveViewportChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        FindName: *const fn (*anyopaque, ?*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetBinding: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        GetBindingExpression: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Triggers(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Triggers(self, &out)); return out orelse error.WinRTFailed; }
    pub fn Resources(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Resources(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetResources(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetResources(self, value)); }
    pub fn Tag(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.Tag(self, &out)); return out; }
    pub fn SetTag(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetTag(self, @ptrCast(value))); }
    pub fn Language(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Language(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetLanguage(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetLanguage(self, value)); }
    pub fn ActualWidth(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.ActualWidth(self, &out)); return out; }
    pub fn ActualHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.ActualHeight(self, &out)); return out; }
    pub fn Width(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.Width(self, &out)); return out; }
    pub fn SetWidth(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetWidth(self, value)); }
    pub fn Height(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.Height(self, &out)); return out; }
    pub fn SetHeight(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetHeight(self, value)); }
    pub fn MinWidth(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.MinWidth(self, &out)); return out; }
    pub fn SetMinWidth(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetMinWidth(self, value)); }
    pub fn MaxWidth(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.MaxWidth(self, &out)); return out; }
    pub fn SetMaxWidth(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetMaxWidth(self, value)); }
    pub fn MinHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.MinHeight(self, &out)); return out; }
    pub fn SetMinHeight(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetMinHeight(self, value)); }
    pub fn MaxHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.MaxHeight(self, &out)); return out; }
    pub fn SetMaxHeight(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetMaxHeight(self, value)); }
    pub fn HorizontalAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.HorizontalAlignment(self, &out)); return out; }
    pub fn SetHorizontalAlignment(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetHorizontalAlignment(self, value)); }
    pub fn VerticalAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.VerticalAlignment(self, &out)); return out; }
    pub fn SetVerticalAlignment(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetVerticalAlignment(self, value)); }
    pub fn Margin(self: *@This()) !Thickness { var out: Thickness = undefined; try hrCheck(self.lpVtbl.Margin(self, &out)); return out; }
    pub fn SetMargin(self: *@This(), value: Thickness) !void { try hrCheck(self.lpVtbl.SetMargin(self, value)); }
    pub fn Name(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Name(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetName(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetName(self, value)); }
    pub fn BaseUri(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.BaseUri(self, &out)); return out orelse error.WinRTFailed; }
    pub fn DataContext(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.DataContext(self, &out)); return out; }
    pub fn SetDataContext(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetDataContext(self, @ptrCast(value))); }
    pub fn AllowFocusOnInteraction(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.AllowFocusOnInteraction(self, &out)); return out; }
    pub fn SetAllowFocusOnInteraction(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetAllowFocusOnInteraction(self, value)); }
    pub fn FocusVisualMargin(self: *@This()) !Thickness { var out: Thickness = undefined; try hrCheck(self.lpVtbl.FocusVisualMargin(self, &out)); return out; }
    pub fn SetFocusVisualMargin(self: *@This(), value: Thickness) !void { try hrCheck(self.lpVtbl.SetFocusVisualMargin(self, value)); }
    pub fn FocusVisualSecondaryThickness(self: *@This()) !Thickness { var out: Thickness = undefined; try hrCheck(self.lpVtbl.FocusVisualSecondaryThickness(self, &out)); return out; }
    pub fn SetFocusVisualSecondaryThickness(self: *@This(), value: Thickness) !void { try hrCheck(self.lpVtbl.SetFocusVisualSecondaryThickness(self, value)); }
    pub fn FocusVisualPrimaryThickness(self: *@This()) !Thickness { var out: Thickness = undefined; try hrCheck(self.lpVtbl.FocusVisualPrimaryThickness(self, &out)); return out; }
    pub fn SetFocusVisualPrimaryThickness(self: *@This(), value: Thickness) !void { try hrCheck(self.lpVtbl.SetFocusVisualPrimaryThickness(self, value)); }
    pub fn FocusVisualSecondaryBrush(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.FocusVisualSecondaryBrush(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetFocusVisualSecondaryBrush(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFocusVisualSecondaryBrush(self, value)); }
    pub fn FocusVisualPrimaryBrush(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.FocusVisualPrimaryBrush(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetFocusVisualPrimaryBrush(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFocusVisualPrimaryBrush(self, value)); }
    pub fn AllowFocusWhenDisabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.AllowFocusWhenDisabled(self, &out)); return out; }
    pub fn SetAllowFocusWhenDisabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetAllowFocusWhenDisabled(self, value)); }
    pub fn Style(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Style(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetStyle(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetStyle(self, value)); }
    pub fn Parent(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Parent(self, &out)); return out orelse error.WinRTFailed; }
    pub fn FlowDirection(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.FlowDirection(self, &out)); return out; }
    pub fn SetFlowDirection(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetFlowDirection(self, value)); }
    pub fn RequestedTheme(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.RequestedTheme(self, &out)); return out; }
    pub fn SetRequestedTheme(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetRequestedTheme(self, value)); }
    pub fn IsLoaded(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsLoaded(self, &out)); return out; }
    pub fn ActualTheme(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.ActualTheme(self, &out)); return out; }
    pub fn AddLoaded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.Loaded(self, p0, &out0)); return out0; }
    pub fn Loaded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddLoaded(p0); }
    pub fn RemoveLoaded(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveLoaded(self, token)); }
    pub fn AddUnloaded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.Unloaded(self, p0, &out0)); return out0; }
    pub fn Unloaded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddUnloaded(p0); }
    pub fn RemoveUnloaded(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveUnloaded(self, token)); }
    pub fn AddDataContextChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.DataContextChanged(self, p0, &out0)); return out0; }
    pub fn DataContextChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddDataContextChanged(p0); }
    pub fn RemoveDataContextChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveDataContextChanged(self, token)); }
    pub fn AddSizeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.SizeChanged(self, p0, &out0)); return out0; }
    pub fn SizeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddSizeChanged(p0); }
    pub fn RemoveSizeChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveSizeChanged(self, token)); }
    pub fn AddLayoutUpdated(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.LayoutUpdated(self, p0, &out0)); return out0; }
    pub fn LayoutUpdated(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddLayoutUpdated(p0); }
    pub fn RemoveLayoutUpdated(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveLayoutUpdated(self, token)); }
    pub fn AddLoading(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.Loading(self, p0, &out0)); return out0; }
    pub fn Loading(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddLoading(p0); }
    pub fn RemoveLoading(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveLoading(self, token)); }
    pub fn AddActualThemeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.ActualThemeChanged(self, p0, &out0)); return out0; }
    pub fn ActualThemeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddActualThemeChanged(p0); }
    pub fn RemoveActualThemeChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveActualThemeChanged(self, token)); }
    pub fn AddEffectiveViewportChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.EffectiveViewportChanged(self, p0, &out0)); return out0; }
    pub fn EffectiveViewportChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddEffectiveViewportChanged(p0); }
    pub fn RemoveEffectiveViewportChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveEffectiveViewportChanged(self, token)); }
    pub fn findName(self: *@This(), p0: ?*anyopaque) !HSTRING { var out0: HSTRING = undefined; try hrCheck(self.lpVtbl.FindName(self, p0, &out0)); return out0; }
    pub fn FindName(self: *@This(), p0: ?*anyopaque) !HSTRING { return self.findName(p0); }
    pub fn setBinding(self: *@This(), dp: ?*anyopaque, binding: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetBinding(self, dp, binding)); }
    pub fn SetBinding(self: *@This(), dp: ?*anyopaque, binding: ?*anyopaque) !void { try self.setBinding(dp, binding); }
    pub fn getBindingExpression(self: *@This(), p0: ?*anyopaque) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetBindingExpression(self, p0, &out0)); return out0; }
    pub fn GetBindingExpression(self: *@This(), p0: ?*anyopaque) !?*anyopaque { return self.getBindingExpression(p0); }
};

pub const IXamlMetadataProvider = extern struct {
    pub const IID = GUID{ .data1 = 0xa96251f0, .data2 = 0x2214, .data3 = 0x5d53, .data4 = .{ 0x87, 0x46, 0xce, 0x99, 0xa2, 0x59, 0x3c, 0xd7 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        GetXamlType: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetXamlType_2: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetXmlnsDefinitions: *const fn (*anyopaque, *u32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getXamlType(self: *@This(), p0: ?*anyopaque) !*IXamlType { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetXamlType(self, p0, &out0)); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed)); }
    pub fn GetXamlType(self: *@This(), p0: ?*anyopaque) !*IXamlType { return self.getXamlType(p0); }
    pub fn getXamlType_1(self: *@This(), p0: ?*anyopaque) !*IXamlType { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetXamlType_2(self, p0, &out0)); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed)); }
    pub fn GetXamlType_2(self: *@This(), p0: ?*anyopaque) !*IXamlType { return self.getXamlType_1(p0); }
    pub fn getXmlnsDefinitions(self: *@This()) !struct { count: u32, definitions: ?*anyopaque } { var out0: u32 = 0; var out1: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetXmlnsDefinitions(self, &out0, &out1)); return .{ .count = out0, .definitions = out1 }; }
    pub fn GetXmlnsDefinitions(self: *@This()) !struct { count: u32, definitions: ?*anyopaque } { return self.getXmlnsDefinitions(); }
};

pub const IXamlType = extern struct {
    pub const IID = GUID{ .data1 = 0xd24219df, .data2 = 0x7ec9, .data3 = 0x57f1, .data4 = .{ 0xa2, 0x7b, 0x6a, 0xf2, 0x51, 0xd9, 0xc5, 0xbc } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        BaseType: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        ContentProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        FullName: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        IsArray: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        IsCollection: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        IsConstructible: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        IsDictionary: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        IsMarkupExtension: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        IsBindable: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        ItemType: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        KeyType: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        BoxedType: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        UnderlyingType: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        ActivateInstance: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        CreateFromString: *const fn (*anyopaque, ?*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        GetMember: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        AddToVector: *const fn (*anyopaque, HSTRING, HSTRING) callconv(.winapi) HRESULT,
        AddToMap: *const fn (*anyopaque, HSTRING, HSTRING, HSTRING) callconv(.winapi) HRESULT,
        RunInitializer: *const fn (*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn BaseType(self: *@This()) !*IXamlType { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.BaseType(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn ContentProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ContentProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn FullName(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.FullName(self, &out)); return out orelse error.WinRTFailed; }
    pub fn IsArray(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsArray(self, &out)); return out; }
    pub fn IsCollection(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsCollection(self, &out)); return out; }
    pub fn IsConstructible(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsConstructible(self, &out)); return out; }
    pub fn IsDictionary(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsDictionary(self, &out)); return out; }
    pub fn IsMarkupExtension(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsMarkupExtension(self, &out)); return out; }
    pub fn IsBindable(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsBindable(self, &out)); return out; }
    pub fn ItemType(self: *@This()) !*IXamlType { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ItemType(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn KeyType(self: *@This()) !*IXamlType { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.KeyType(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn BoxedType(self: *@This()) !*IXamlType { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.BoxedType(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn UnderlyingType(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.UnderlyingType(self, &out)); return out orelse error.WinRTFailed; }
    pub fn activateInstance(self: *@This()) !HSTRING { var out0: HSTRING = undefined; try hrCheck(self.lpVtbl.ActivateInstance(self, &out0)); return out0; }
    pub fn ActivateInstance(self: *@This()) !HSTRING { return self.activateInstance(); }
    pub fn createFromString(self: *@This(), p0: ?*anyopaque) !HSTRING { var out0: HSTRING = undefined; try hrCheck(self.lpVtbl.CreateFromString(self, p0, &out0)); return out0; }
    pub fn CreateFromString(self: *@This(), p0: ?*anyopaque) !HSTRING { return self.createFromString(p0); }
    pub fn getMember(self: *@This(), p0: ?*anyopaque) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetMember(self, p0, &out0)); return out0; }
    pub fn GetMember(self: *@This(), p0: ?*anyopaque) !?*anyopaque { return self.getMember(p0); }
    pub fn addToVector(self: *@This(), instance: anytype, value: anytype) !void { try hrCheck(self.lpVtbl.AddToVector(self, @ptrCast(instance), @ptrCast(value))); }
    pub fn AddToVector(self: *@This(), instance: anytype, value: anytype) !void { try self.addToVector(instance, value); }
    pub fn addToMap(self: *@This(), instance: anytype, key: anytype, value: anytype) !void { try hrCheck(self.lpVtbl.AddToMap(self, @ptrCast(instance), @ptrCast(key), @ptrCast(value))); }
    pub fn AddToMap(self: *@This(), instance: anytype, key: anytype, value: anytype) !void { try self.addToMap(instance, key, value); }
    pub fn runInitializer(self: *@This()) !void { try hrCheck(self.lpVtbl.RunInitializer(self)); }
    pub fn RunInitializer(self: *@This()) !void { try self.runInitializer(); }
};

pub const ITextBox = extern struct {
    pub const IID = GUID{ .data1 = 0x873af7c2, .data2 = 0xab89, .data3 = 0x5d76, .data4 = .{ 0x8d, 0xbe, 0x3d, 0x63, 0x25, 0x66, 0x9d, 0xf5 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Text: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetText: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SelectedText: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetSelectedText: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SelectionLength: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetSelectionLength: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SelectionStart: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetSelectionStart: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        MaxLength: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetMaxLength: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        IsReadOnly: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsReadOnly: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        AcceptsReturn: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetAcceptsReturn: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        TextAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetTextAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        TextWrapping: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetTextWrapping: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        IsSpellCheckEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsSpellCheckEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        IsTextPredictionEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsTextPredictionEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        InputScope: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetInputScope: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Header: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetHeader: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        HeaderTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetHeaderTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        PlaceholderText: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetPlaceholderText: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SelectionHighlightColor: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetSelectionHighlightColor: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        PreventKeyboardDisplayOnProgrammaticFocus: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetPreventKeyboardDisplayOnProgrammaticFocus: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        IsColorFontEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsColorFontEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        SelectionHighlightColorWhenNotFocused: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetSelectionHighlightColorWhenNotFocused: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        HorizontalTextAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetHorizontalTextAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        CharacterCasing: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetCharacterCasing: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        PlaceholderForeground: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetPlaceholderForeground: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CanPasteClipboardContent: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        CanUndo: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        CanRedo: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SelectionFlyout: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetSelectionFlyout: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        ProofingMenuFlyout: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Description: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetDescription: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        TextChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTextChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        SelectionChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveSelectionChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        ContextMenuOpening: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveContextMenuOpening: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Paste: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemovePaste: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TextCompositionStarted: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTextCompositionStarted: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TextCompositionChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTextCompositionChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TextCompositionEnded: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTextCompositionEnded: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        CopyingToClipboard: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveCopyingToClipboard: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        CuttingToClipboard: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveCuttingToClipboard: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        BeforeTextChanging: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveBeforeTextChanging: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        SelectionChanging: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveSelectionChanging: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Select: *const fn (*anyopaque, i32, i32) callconv(.winapi) HRESULT,
        SelectAll: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        GetRectFromCharacterIndex: *const fn (*anyopaque, i32, bool, *Rect) callconv(.winapi) HRESULT,
        GetLinguisticAlternativesAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Undo: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        Redo: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        PasteFromClipboard: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        CopySelectionToClipboard: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        CutSelectionToClipboard: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        ClearUndoRedoHistory: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        TextReadingOrder: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetTextReadingOrder: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        DesiredCandidateWindowAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetDesiredCandidateWindowAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        CandidateWindowBoundsChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveCandidateWindowBoundsChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        TextChanging: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveTextChanging: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Text(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Text(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetText(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetText(self, value)); }
    pub fn SelectedText(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.SelectedText(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetSelectedText(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetSelectedText(self, value)); }
    pub fn SelectionLength(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.SelectionLength(self, &out)); return out; }
    pub fn SetSelectionLength(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetSelectionLength(self, value)); }
    pub fn SelectionStart(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.SelectionStart(self, &out)); return out; }
    pub fn SetSelectionStart(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetSelectionStart(self, value)); }
    pub fn MaxLength(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.MaxLength(self, &out)); return out; }
    pub fn SetMaxLength(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetMaxLength(self, value)); }
    pub fn IsReadOnly(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsReadOnly(self, &out)); return out; }
    pub fn SetIsReadOnly(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsReadOnly(self, value)); }
    pub fn AcceptsReturn(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.AcceptsReturn(self, &out)); return out; }
    pub fn SetAcceptsReturn(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetAcceptsReturn(self, value)); }
    pub fn TextAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.TextAlignment(self, &out)); return out; }
    pub fn SetTextAlignment(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetTextAlignment(self, value)); }
    pub fn TextWrapping(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.TextWrapping(self, &out)); return out; }
    pub fn SetTextWrapping(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetTextWrapping(self, value)); }
    pub fn IsSpellCheckEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsSpellCheckEnabled(self, &out)); return out; }
    pub fn SetIsSpellCheckEnabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsSpellCheckEnabled(self, value)); }
    pub fn IsTextPredictionEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsTextPredictionEnabled(self, &out)); return out; }
    pub fn SetIsTextPredictionEnabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsTextPredictionEnabled(self, value)); }
    pub fn InputScope(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.InputScope(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetInputScope(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetInputScope(self, value)); }
    pub fn Header(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.Header(self, &out)); return out; }
    pub fn SetHeader(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetHeader(self, @ptrCast(value))); }
    pub fn HeaderTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.HeaderTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetHeaderTemplate(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetHeaderTemplate(self, value)); }
    pub fn PlaceholderText(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.PlaceholderText(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetPlaceholderText(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetPlaceholderText(self, value)); }
    pub fn SelectionHighlightColor(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.SelectionHighlightColor(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetSelectionHighlightColor(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetSelectionHighlightColor(self, value)); }
    pub fn PreventKeyboardDisplayOnProgrammaticFocus(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.PreventKeyboardDisplayOnProgrammaticFocus(self, &out)); return out; }
    pub fn SetPreventKeyboardDisplayOnProgrammaticFocus(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetPreventKeyboardDisplayOnProgrammaticFocus(self, value)); }
    pub fn IsColorFontEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsColorFontEnabled(self, &out)); return out; }
    pub fn SetIsColorFontEnabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsColorFontEnabled(self, value)); }
    pub fn SelectionHighlightColorWhenNotFocused(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.SelectionHighlightColorWhenNotFocused(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetSelectionHighlightColorWhenNotFocused(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetSelectionHighlightColorWhenNotFocused(self, value)); }
    pub fn HorizontalTextAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.HorizontalTextAlignment(self, &out)); return out; }
    pub fn SetHorizontalTextAlignment(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetHorizontalTextAlignment(self, value)); }
    pub fn CharacterCasing(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.CharacterCasing(self, &out)); return out; }
    pub fn SetCharacterCasing(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetCharacterCasing(self, value)); }
    pub fn PlaceholderForeground(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.PlaceholderForeground(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetPlaceholderForeground(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetPlaceholderForeground(self, value)); }
    pub fn CanPasteClipboardContent(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.CanPasteClipboardContent(self, &out)); return out; }
    pub fn CanUndo(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.CanUndo(self, &out)); return out; }
    pub fn CanRedo(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.CanRedo(self, &out)); return out; }
    pub fn SelectionFlyout(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.SelectionFlyout(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetSelectionFlyout(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetSelectionFlyout(self, value)); }
    pub fn ProofingMenuFlyout(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ProofingMenuFlyout(self, &out)); return out orelse error.WinRTFailed; }
    pub fn Description(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.Description(self, &out)); return out; }
    pub fn SetDescription(self: *@This(), value: anytype) !void { try hrCheck(self.lpVtbl.SetDescription(self, @ptrCast(value))); }
    pub fn AddTextChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TextChanged(self, p0, &out0)); return out0; }
    pub fn TextChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTextChanged(p0); }
    pub fn RemoveTextChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTextChanged(self, token)); }
    pub fn AddSelectionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.SelectionChanged(self, p0, &out0)); return out0; }
    pub fn SelectionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddSelectionChanged(p0); }
    pub fn RemoveSelectionChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveSelectionChanged(self, token)); }
    pub fn AddContextMenuOpening(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.ContextMenuOpening(self, p0, &out0)); return out0; }
    pub fn ContextMenuOpening(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddContextMenuOpening(p0); }
    pub fn RemoveContextMenuOpening(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveContextMenuOpening(self, token)); }
    pub fn AddPaste(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.Paste(self, p0, &out0)); return out0; }
    pub fn Paste(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddPaste(p0); }
    pub fn RemovePaste(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemovePaste(self, token)); }
    pub fn AddTextCompositionStarted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TextCompositionStarted(self, p0, &out0)); return out0; }
    pub fn TextCompositionStarted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTextCompositionStarted(p0); }
    pub fn RemoveTextCompositionStarted(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTextCompositionStarted(self, token)); }
    pub fn AddTextCompositionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TextCompositionChanged(self, p0, &out0)); return out0; }
    pub fn TextCompositionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTextCompositionChanged(p0); }
    pub fn RemoveTextCompositionChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTextCompositionChanged(self, token)); }
    pub fn AddTextCompositionEnded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TextCompositionEnded(self, p0, &out0)); return out0; }
    pub fn TextCompositionEnded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTextCompositionEnded(p0); }
    pub fn RemoveTextCompositionEnded(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTextCompositionEnded(self, token)); }
    pub fn AddCopyingToClipboard(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.CopyingToClipboard(self, p0, &out0)); return out0; }
    pub fn CopyingToClipboard(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddCopyingToClipboard(p0); }
    pub fn RemoveCopyingToClipboard(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveCopyingToClipboard(self, token)); }
    pub fn AddCuttingToClipboard(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.CuttingToClipboard(self, p0, &out0)); return out0; }
    pub fn CuttingToClipboard(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddCuttingToClipboard(p0); }
    pub fn RemoveCuttingToClipboard(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveCuttingToClipboard(self, token)); }
    pub fn AddBeforeTextChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.BeforeTextChanging(self, p0, &out0)); return out0; }
    pub fn BeforeTextChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddBeforeTextChanging(p0); }
    pub fn RemoveBeforeTextChanging(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveBeforeTextChanging(self, token)); }
    pub fn AddSelectionChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.SelectionChanging(self, p0, &out0)); return out0; }
    pub fn SelectionChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddSelectionChanging(p0); }
    pub fn RemoveSelectionChanging(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveSelectionChanging(self, token)); }
    pub fn select(self: *@This(), start: i32, length: i32) !void { try hrCheck(self.lpVtbl.Select(self, start, length)); }
    pub fn Select(self: *@This(), start: i32, length: i32) !void { try self.select(start, length); }
    pub fn selectAll(self: *@This()) !void { try hrCheck(self.lpVtbl.SelectAll(self)); }
    pub fn SelectAll(self: *@This()) !void { try self.selectAll(); }
    pub fn getRectFromCharacterIndex(self: *@This(), p0: i32, p1: bool) !Rect { var out0: Rect = undefined; try hrCheck(self.lpVtbl.GetRectFromCharacterIndex(self, p0, p1, &out0)); return out0; }
    pub fn GetRectFromCharacterIndex(self: *@This(), p0: i32, p1: bool) !Rect { return self.getRectFromCharacterIndex(p0, p1); }
    pub fn getLinguisticAlternativesAsync(self: *@This()) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetLinguisticAlternativesAsync(self, &out0)); return out0; }
    pub fn GetLinguisticAlternativesAsync(self: *@This()) !?*anyopaque { return self.getLinguisticAlternativesAsync(); }
    pub fn undo(self: *@This()) !void { try hrCheck(self.lpVtbl.Undo(self)); }
    pub fn Undo(self: *@This()) !void { try self.undo(); }
    pub fn redo(self: *@This()) !void { try hrCheck(self.lpVtbl.Redo(self)); }
    pub fn Redo(self: *@This()) !void { try self.redo(); }
    pub fn pasteFromClipboard(self: *@This()) !void { try hrCheck(self.lpVtbl.PasteFromClipboard(self)); }
    pub fn PasteFromClipboard(self: *@This()) !void { try self.pasteFromClipboard(); }
    pub fn copySelectionToClipboard(self: *@This()) !void { try hrCheck(self.lpVtbl.CopySelectionToClipboard(self)); }
    pub fn CopySelectionToClipboard(self: *@This()) !void { try self.copySelectionToClipboard(); }
    pub fn cutSelectionToClipboard(self: *@This()) !void { try hrCheck(self.lpVtbl.CutSelectionToClipboard(self)); }
    pub fn CutSelectionToClipboard(self: *@This()) !void { try self.cutSelectionToClipboard(); }
    pub fn clearUndoRedoHistory(self: *@This()) !void { try hrCheck(self.lpVtbl.ClearUndoRedoHistory(self)); }
    pub fn ClearUndoRedoHistory(self: *@This()) !void { try self.clearUndoRedoHistory(); }
    pub fn TextReadingOrder(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.TextReadingOrder(self, &out)); return out; }
    pub fn SetTextReadingOrder(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetTextReadingOrder(self, value)); }
    pub fn DesiredCandidateWindowAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.DesiredCandidateWindowAlignment(self, &out)); return out; }
    pub fn SetDesiredCandidateWindowAlignment(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetDesiredCandidateWindowAlignment(self, value)); }
    pub fn AddCandidateWindowBoundsChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.CandidateWindowBoundsChanged(self, p0, &out0)); return out0; }
    pub fn CandidateWindowBoundsChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddCandidateWindowBoundsChanged(p0); }
    pub fn RemoveCandidateWindowBoundsChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveCandidateWindowBoundsChanged(self, token)); }
    pub fn AddTextChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.TextChanging(self, p0, &out0)); return out0; }
    pub fn TextChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddTextChanging(p0); }
    pub fn RemoveTextChanging(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveTextChanging(self, token)); }
};

pub const ISolidColorBrush = extern struct {
    pub const IID = GUID{ .data1 = 0xb3865c31, .data2 = 0x37c8, .data3 = 0x55c1, .data4 = .{ 0x8a, 0x72, 0xd4, 0x1c, 0x67, 0x64, 0x2e, 0x2a } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Color: *const fn (*anyopaque, *Color) callconv(.winapi) HRESULT,
        SetColor: *const fn (*anyopaque, Color) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn GetColor(self: *@This()) !Color { var out: Color = .{ .a = 0, .r = 0, .g = 0, .b = 0 }; try hrCheck(self.lpVtbl.Color(self, &out)); return out; }
    pub fn SetColor(self: *@This(), value: Color) !void { try hrCheck(self.lpVtbl.SetColor(self, value)); }
};

pub const IControl = extern struct {
    pub const IID = GUID{ .data1 = 0x857d6e8a, .data2 = 0xd45a, .data3 = 0x5c69, .data4 = .{ 0xa9, 0x9c, 0xbf, 0x6a, 0x5c, 0x54, 0xfb, 0x38 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        IsFocusEngagementEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsFocusEngagementEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        IsFocusEngaged: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsFocusEngaged: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        RequiresPointer: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetRequiresPointer: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        FontSize: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetFontSize: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        FontFamily: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetFontFamily: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        FontWeight: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetFontWeight: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        FontStyle: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetFontStyle: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        FontStretch: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetFontStretch: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CharacterSpacing: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetCharacterSpacing: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        Foreground: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetForeground: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        IsTextScaleFactorEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsTextScaleFactorEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        IsEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        SetIsEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        TabNavigation: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetTabNavigation: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        Template: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Padding: *const fn (*anyopaque, *Thickness) callconv(.winapi) HRESULT,
        SetPadding: *const fn (*anyopaque, Thickness) callconv(.winapi) HRESULT,
        HorizontalContentAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetHorizontalContentAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        VerticalContentAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetVerticalContentAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        Background: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetBackground: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        BackgroundSizing: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetBackgroundSizing: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        BorderThickness: *const fn (*anyopaque, *Thickness) callconv(.winapi) HRESULT,
        SetBorderThickness: *const fn (*anyopaque, Thickness) callconv(.winapi) HRESULT,
        BorderBrush: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetBorderBrush: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        DefaultStyleResourceUri: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetDefaultStyleResourceUri: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        ElementSoundMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetElementSoundMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        CornerRadius: *const fn (*anyopaque, *CornerRadius) callconv(.winapi) HRESULT,
        SetCornerRadius: *const fn (*anyopaque, CornerRadius) callconv(.winapi) HRESULT,
        FocusEngaged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveFocusEngaged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        FocusDisengaged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveFocusDisengaged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        IsEnabledChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveIsEnabledChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveFocusEngagement: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        ApplyTemplate: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn IsFocusEngagementEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsFocusEngagementEnabled(self, &out)); return out; }
    pub fn SetIsFocusEngagementEnabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsFocusEngagementEnabled(self, value)); }
    pub fn IsFocusEngaged(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsFocusEngaged(self, &out)); return out; }
    pub fn SetIsFocusEngaged(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsFocusEngaged(self, value)); }
    pub fn RequiresPointer(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.RequiresPointer(self, &out)); return out; }
    pub fn SetRequiresPointer(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetRequiresPointer(self, value)); }
    pub fn FontSize(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.FontSize(self, &out)); return out; }
    pub fn SetFontSize(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetFontSize(self, value)); }
    pub fn FontFamily(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.FontFamily(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetFontFamily(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFontFamily(self, value)); }
    pub fn FontWeight(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.FontWeight(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetFontWeight(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFontWeight(self, value)); }
    pub fn FontStyle(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.FontStyle(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetFontStyle(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFontStyle(self, value)); }
    pub fn FontStretch(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.FontStretch(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetFontStretch(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFontStretch(self, value)); }
    pub fn CharacterSpacing(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.CharacterSpacing(self, &out)); return out; }
    pub fn SetCharacterSpacing(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetCharacterSpacing(self, value)); }
    pub fn Foreground(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Foreground(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetForeground(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetForeground(self, value)); }
    pub fn IsTextScaleFactorEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsTextScaleFactorEnabled(self, &out)); return out; }
    pub fn SetIsTextScaleFactorEnabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsTextScaleFactorEnabled(self, value)); }
    pub fn IsEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsEnabled(self, &out)); return out; }
    pub fn SetIsEnabled(self: *@This(), value: bool) !void { try hrCheck(self.lpVtbl.SetIsEnabled(self, value)); }
    pub fn TabNavigation(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.TabNavigation(self, &out)); return out; }
    pub fn SetTabNavigation(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetTabNavigation(self, value)); }
    pub fn Template(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Template(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetTemplate(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTemplate(self, value)); }
    pub fn Padding(self: *@This()) !Thickness { var out: Thickness = undefined; try hrCheck(self.lpVtbl.Padding(self, &out)); return out; }
    pub fn SetPadding(self: *@This(), value: Thickness) !void { try hrCheck(self.lpVtbl.SetPadding(self, value)); }
    pub fn HorizontalContentAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.HorizontalContentAlignment(self, &out)); return out; }
    pub fn SetHorizontalContentAlignment(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetHorizontalContentAlignment(self, value)); }
    pub fn VerticalContentAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.VerticalContentAlignment(self, &out)); return out; }
    pub fn SetVerticalContentAlignment(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetVerticalContentAlignment(self, value)); }
    pub fn Background(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Background(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetBackground(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetBackground(self, value)); }
    pub fn BackgroundSizing(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.BackgroundSizing(self, &out)); return out; }
    pub fn SetBackgroundSizing(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetBackgroundSizing(self, value)); }
    pub fn BorderThickness(self: *@This()) !Thickness { var out: Thickness = undefined; try hrCheck(self.lpVtbl.BorderThickness(self, &out)); return out; }
    pub fn SetBorderThickness(self: *@This(), value: Thickness) !void { try hrCheck(self.lpVtbl.SetBorderThickness(self, value)); }
    pub fn BorderBrush(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.BorderBrush(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetBorderBrush(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetBorderBrush(self, value)); }
    pub fn DefaultStyleResourceUri(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.DefaultStyleResourceUri(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetDefaultStyleResourceUri(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetDefaultStyleResourceUri(self, value)); }
    pub fn ElementSoundMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.ElementSoundMode(self, &out)); return out; }
    pub fn SetElementSoundMode(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetElementSoundMode(self, value)); }
    pub fn GetCornerRadius(self: *@This()) !CornerRadius { var out: CornerRadius = undefined; try hrCheck(self.lpVtbl.CornerRadius(self, &out)); return out; }
    pub fn SetCornerRadius(self: *@This(), value: CornerRadius) !void { try hrCheck(self.lpVtbl.SetCornerRadius(self, value)); }
    pub fn AddFocusEngaged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.FocusEngaged(self, p0, &out0)); return out0; }
    pub fn FocusEngaged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddFocusEngaged(p0); }
    pub fn RemoveFocusEngaged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveFocusEngaged(self, token)); }
    pub fn AddFocusDisengaged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.FocusDisengaged(self, p0, &out0)); return out0; }
    pub fn FocusDisengaged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddFocusDisengaged(p0); }
    pub fn RemoveFocusDisengaged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveFocusDisengaged(self, token)); }
    pub fn AddIsEnabledChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.IsEnabledChanged(self, p0, &out0)); return out0; }
    pub fn IsEnabledChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.AddIsEnabledChanged(p0); }
    pub fn RemoveIsEnabledChanged(self: *@This(), token: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.RemoveIsEnabledChanged(self, token)); }
    pub fn removeFocusEngagement(self: *@This()) !void { try hrCheck(self.lpVtbl.RemoveFocusEngagement(self)); }
    pub fn RemoveFocusEngagement(self: *@This()) !void { try self.removeFocusEngagement(); }
    pub fn applyTemplate(self: *@This()) !bool { var out0: bool = false; try hrCheck(self.lpVtbl.ApplyTemplate(self, &out0)); return out0; }
    pub fn ApplyTemplate(self: *@This()) !bool { return self.applyTemplate(); }
};

pub const IPanel = extern struct {
    pub const IID = GUID{ .data1 = 0x27a1b418, .data2 = 0x56f3, .data3 = 0x525e, .data4 = .{ 0xb8, 0x83, 0xce, 0xfe, 0xd9, 0x05, 0xee, 0xd3 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Children: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Background: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetBackground: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        IsItemsHost: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        ChildrenTransitions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetChildrenTransitions: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        BackgroundTransition: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetBackgroundTransition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Children(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Children(self, &out)); return out orelse error.WinRTFailed; }
    pub fn Background(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Background(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetBackground(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetBackground(self, value)); }
    pub fn IsItemsHost(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.IsItemsHost(self, &out)); return out; }
    pub fn ChildrenTransitions(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ChildrenTransitions(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetChildrenTransitions(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetChildrenTransitions(self, value)); }
    pub fn BackgroundTransition(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.BackgroundTransition(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetBackgroundTransition(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetBackgroundTransition(self, value)); }
};

pub const IGrid = extern struct {
    pub const IID = GUID{ .data1 = 0xc4496219, .data2 = 0x9014, .data3 = 0x58a1, .data4 = .{ 0xb4, 0xad, 0xc5, 0x04, 0x49, 0x13, 0xa5, 0xbb } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        RowDefinitions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        ColumnDefinitions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        BackgroundSizing: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetBackgroundSizing: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        BorderBrush: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetBorderBrush: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        BorderThickness: *const fn (*anyopaque, *Thickness) callconv(.winapi) HRESULT,
        SetBorderThickness: *const fn (*anyopaque, Thickness) callconv(.winapi) HRESULT,
        CornerRadius: *const fn (*anyopaque, *CornerRadius) callconv(.winapi) HRESULT,
        SetCornerRadius: *const fn (*anyopaque, CornerRadius) callconv(.winapi) HRESULT,
        Padding: *const fn (*anyopaque, *Thickness) callconv(.winapi) HRESULT,
        SetPadding: *const fn (*anyopaque, Thickness) callconv(.winapi) HRESULT,
        RowSpacing: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetRowSpacing: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        ColumnSpacing: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetColumnSpacing: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn RowDefinitions(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.RowDefinitions(self, &out)); return out orelse error.WinRTFailed; }
    pub fn ColumnDefinitions(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ColumnDefinitions(self, &out)); return out orelse error.WinRTFailed; }
    pub fn BackgroundSizing(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.BackgroundSizing(self, &out)); return out; }
    pub fn SetBackgroundSizing(self: *@This(), value: i32) !void { try hrCheck(self.lpVtbl.SetBackgroundSizing(self, value)); }
    pub fn BorderBrush(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.BorderBrush(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetBorderBrush(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetBorderBrush(self, value)); }
    pub fn BorderThickness(self: *@This()) !Thickness { var out: Thickness = undefined; try hrCheck(self.lpVtbl.BorderThickness(self, &out)); return out; }
    pub fn SetBorderThickness(self: *@This(), value: Thickness) !void { try hrCheck(self.lpVtbl.SetBorderThickness(self, value)); }
    pub fn GetCornerRadius(self: *@This()) !CornerRadius { var out: CornerRadius = undefined; try hrCheck(self.lpVtbl.CornerRadius(self, &out)); return out; }
    pub fn SetCornerRadius(self: *@This(), value: CornerRadius) !void { try hrCheck(self.lpVtbl.SetCornerRadius(self, value)); }
    pub fn Padding(self: *@This()) !Thickness { var out: Thickness = undefined; try hrCheck(self.lpVtbl.Padding(self, &out)); return out; }
    pub fn SetPadding(self: *@This(), value: Thickness) !void { try hrCheck(self.lpVtbl.SetPadding(self, value)); }
    pub fn RowSpacing(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.RowSpacing(self, &out)); return out; }
    pub fn SetRowSpacing(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetRowSpacing(self, value)); }
    pub fn ColumnSpacing(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.ColumnSpacing(self, &out)); return out; }
    pub fn SetColumnSpacing(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetColumnSpacing(self, value)); }
};

pub const IGridStatics = extern struct {
    pub const IID = GUID{ .data1 = 0xef9cf81d, .data2 = 0xa431, .data3 = 0x50f4, .data4 = .{ 0xab, 0xf5, 0x30, 0x23, 0xfe, 0x44, 0x77, 0x04 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        BackgroundSizingProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        BorderBrushProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        BorderThicknessProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CornerRadiusProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        PaddingProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        RowSpacingProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        ColumnSpacingProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        RowProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetRow: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetRow: *const fn (*anyopaque, ?*anyopaque, i32) callconv(.winapi) HRESULT,
        ColumnProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetColumn: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetColumn: *const fn (*anyopaque, ?*anyopaque, i32) callconv(.winapi) HRESULT,
        RowSpanProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetRowSpan: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetRowSpan: *const fn (*anyopaque, ?*anyopaque, i32) callconv(.winapi) HRESULT,
        ColumnSpanProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetColumnSpan: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetColumnSpan: *const fn (*anyopaque, ?*anyopaque, i32) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn BackgroundSizingProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.BackgroundSizingProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn BorderBrushProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.BorderBrushProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn BorderThicknessProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.BorderThicknessProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn CornerRadiusProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.CornerRadiusProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn PaddingProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.PaddingProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn RowSpacingProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.RowSpacingProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn ColumnSpacingProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ColumnSpacingProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn RowProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.RowProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn getRow(self: *@This(), p0: ?*anyopaque) !i32 { var out0: i32 = 0; try hrCheck(self.lpVtbl.GetRow(self, p0, &out0)); return out0; }
    pub fn GetRow(self: *@This(), p0: ?*anyopaque) !i32 { return self.getRow(p0); }
    pub fn setRow(self: *@This(), element: ?*anyopaque, value: i32) !void { try hrCheck(self.lpVtbl.SetRow(self, element, value)); }
    pub fn SetRow(self: *@This(), element: ?*anyopaque, value: i32) !void { try self.setRow(element, value); }
    pub fn ColumnProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ColumnProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn getColumn(self: *@This(), p0: ?*anyopaque) !i32 { var out0: i32 = 0; try hrCheck(self.lpVtbl.GetColumn(self, p0, &out0)); return out0; }
    pub fn GetColumn(self: *@This(), p0: ?*anyopaque) !i32 { return self.getColumn(p0); }
    pub fn setColumn(self: *@This(), element: ?*anyopaque, value: i32) !void { try hrCheck(self.lpVtbl.SetColumn(self, element, value)); }
    pub fn SetColumn(self: *@This(), element: ?*anyopaque, value: i32) !void { try self.setColumn(element, value); }
    pub fn RowSpanProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.RowSpanProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn getRowSpan(self: *@This(), p0: ?*anyopaque) !i32 { var out0: i32 = 0; try hrCheck(self.lpVtbl.GetRowSpan(self, p0, &out0)); return out0; }
    pub fn GetRowSpan(self: *@This(), p0: ?*anyopaque) !i32 { return self.getRowSpan(p0); }
    pub fn setRowSpan(self: *@This(), element: ?*anyopaque, value: i32) !void { try hrCheck(self.lpVtbl.SetRowSpan(self, element, value)); }
    pub fn SetRowSpan(self: *@This(), element: ?*anyopaque, value: i32) !void { try self.setRowSpan(element, value); }
    pub fn ColumnSpanProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ColumnSpanProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn getColumnSpan(self: *@This(), p0: ?*anyopaque) !i32 { var out0: i32 = 0; try hrCheck(self.lpVtbl.GetColumnSpan(self, p0, &out0)); return out0; }
    pub fn GetColumnSpan(self: *@This(), p0: ?*anyopaque) !i32 { return self.getColumnSpan(p0); }
    pub fn setColumnSpan(self: *@This(), element: ?*anyopaque, value: i32) !void { try hrCheck(self.lpVtbl.SetColumnSpan(self, element, value)); }
    pub fn SetColumnSpan(self: *@This(), element: ?*anyopaque, value: i32) !void { try self.setColumnSpan(element, value); }
};

pub const IRowDefinition = extern struct {
    pub const IID = GUID{ .data1 = 0xfe870f2f, .data2 = 0x89ef, .data3 = 0x5dac, .data4 = .{ 0x9f, 0x33, 0x96, 0x8d, 0x0d, 0xc5, 0x77, 0xc3 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Height: *const fn (*anyopaque, *GridLength) callconv(.winapi) HRESULT,
        SetHeight: *const fn (*anyopaque, GridLength) callconv(.winapi) HRESULT,
        MaxHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetMaxHeight: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        MinHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        SetMinHeight: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        ActualHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Height(self: *@This()) !GridLength { var out: GridLength = .{ .Value = 0, .GridUnitType = 0 }; try hrCheck(self.lpVtbl.Height(self, &out)); return out; }
    pub fn SetHeight(self: *@This(), value: GridLength) !void { try hrCheck(self.lpVtbl.SetHeight(self, value)); }
    pub fn MaxHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.MaxHeight(self, &out)); return out; }
    pub fn SetMaxHeight(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetMaxHeight(self, value)); }
    pub fn MinHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.MinHeight(self, &out)); return out; }
    pub fn SetMinHeight(self: *@This(), value: f64) !void { try hrCheck(self.lpVtbl.SetMinHeight(self, value)); }
    pub fn ActualHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.ActualHeight(self, &out)); return out; }
};

pub const IResourceDictionary = extern struct {
    pub const IID = GUID{ .data1 = 0x1b690975, .data2 = 0xa710, .data3 = 0x5783, .data4 = .{ 0xa6, 0xe1, 0x15, 0x83, 0x6f, 0x61, 0x86, 0xc2 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        Source: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetSource: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        MergedDictionaries: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        ThemeDictionaries: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn Source(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.Source(self, &out)); return out orelse error.WinRTFailed; }
    pub fn SetSource(self: *@This(), value: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetSource(self, value)); }
    pub fn MergedDictionaries(self: *@This()) !*IVector { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.MergedDictionaries(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn ThemeDictionaries(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.ThemeDictionaries(self, &out)); return out orelse error.WinRTFailed; }
};

