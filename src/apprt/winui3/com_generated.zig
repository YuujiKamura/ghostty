//! WinUI 3 COM interface definitions for Zig.
//! GENERATED CODE - DO NOT EDIT.
const std = @import("std");
const GUID = std.os.windows.GUID;
const HRESULT = std.os.windows.HRESULT;
const HSTRING = ?*anyopaque;
const EventRegistrationToken = i64;
const log = std.log.scoped(.winui3_com);
const native = @import("com_native.zig");
const IVector = native.IVector;
const GridLength = native.GridLength;

pub const VtblPlaceholder = ?*const anyopaque;

pub const IID_RoutedEventHandler = GUID{ .Data1 = 0xaf8dae19, .Data2 = 0x0794, .Data3 = 0x5695, .Data4 = .{ 0x96, 0x8a, 0x07, 0x33, 0x3f, 0x92, 0x32, 0xe0 } };
pub const IID_SizeChangedEventHandler = GUID{ .Data1 = 0x8d7b1a58, .Data2 = 0x14c6, .Data3 = 0x51c9, .Data4 = .{ 0x89, 0x2c, 0x9f, 0xcc, 0xe3, 0x68, 0xe7, 0x7d } };
pub const IID_TypedEventHandler_TabCloseRequested = GUID{ .Data1 = 0x7093974b, .Data2 = 0x0900, .Data3 = 0x52ae, .Data4 = .{ 0xaf, 0xd8, 0x70, 0xe5, 0x62, 0x3f, 0x45, 0x95 } };
pub const IID_TypedEventHandler_AddTabButtonClick = GUID{ .Data1 = 0x13df6907, .Data2 = 0xbbb4, .Data3 = 0x5f16, .Data4 = .{ 0xbe, 0xac, 0x29, 0x38, 0xc1, 0x5e, 0x1d, 0x85 } };
pub const IID_SelectionChangedEventHandler = GUID{ .Data1 = 0xa232390d, .Data2 = 0x0e34, .Data3 = 0x595e, .Data4 = .{ 0x89, 0x31, 0xfa, 0x92, 0x8a, 0x99, 0x09, 0xf4 } };
pub const IID_TypedEventHandler_WindowClosed = GUID{ .Data1 = 0x2a954d28, .Data2 = 0x7f8b, .Data3 = 0x5479, .Data4 = .{ 0x8c, 0xe9, 0x90, 0x04, 0x24, 0xa0, 0x40, 0x9f } };

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
    pub const IID = GUID{ .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
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
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
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
        get_Current: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Start: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        LoadComponent: *const fn (*anyopaque, HSTRING, ?*anyopaque) callconv(.winapi) HRESULT,
        LoadComponent_1: *const fn (*anyopaque, HSTRING, ?*anyopaque, i32) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getCurrent(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Current(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Current(self: *@This()) !*anyopaque { return self.getCurrent(); }
    pub fn start(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.Start(self, p0)); }
    pub fn Start(self: *@This(), p0: ?*anyopaque) !void { try self.start(p0); }
    pub fn loadComponent(self: *@This(), p0: anytype, p1: ?*anyopaque) !void { try hrCheck(self.lpVtbl.LoadComponent(self, @ptrCast(p0), p1)); }
    pub fn LoadComponent(self: *@This(), p0: anytype, p1: ?*anyopaque) !void { try self.loadComponent(p0, p1); }
    pub fn loadComponent_1(self: *@This(), p0: anytype, p1: ?*anyopaque, p2: i32) !void { try hrCheck(self.lpVtbl.LoadComponent_1(self, @ptrCast(p0), p1, p2)); }
    pub fn LoadComponent_1(self: *@This(), p0: anytype, p1: ?*anyopaque, p2: i32) !void { try self.loadComponent_1(p0, p1, p2); }
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
        CreateInstance: *const fn (*anyopaque, HSTRING, *HSTRING, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn createInstance(self: *@This(), outer: ?*anyopaque) !struct { inner: ?*anyopaque, instance: *IInspectable } { var inner: ?*anyopaque = null; var instance: ?*anyopaque = null; try hrCheck(self.lpVtbl.CreateInstance(self, outer, &inner, &instance)); return .{ .inner = inner, .instance = @ptrCast(@alignCast(instance.?)) }; }
    pub fn CreateInstance(self: *@This(), outer: ?*anyopaque) !struct { inner: ?*anyopaque, instance: *IInspectable } { return self.createInstance(outer); }
};

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
        get_Resources: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Resources: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_DebugSettings: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_RequestedTheme: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_RequestedTheme: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_FocusVisualKind: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_FocusVisualKind: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_HighContrastAdjustment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_HighContrastAdjustment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        add_UnhandledException: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_UnhandledException: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Exit: *const fn (*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getResources(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Resources(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Resources(self: *@This()) !*anyopaque { return self.getResources(); }
    pub fn putResources(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Resources(self, p0)); }
    pub fn put_Resources(self: *@This(), p0: ?*anyopaque) !void { try self.putResources(p0); }
    pub fn getDebugSettings(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_DebugSettings(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_DebugSettings(self: *@This()) !*anyopaque { return self.getDebugSettings(); }
    pub fn getRequestedTheme(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_RequestedTheme(self, &out)); return out; }
    pub fn get_RequestedTheme(self: *@This()) !i32 { return self.getRequestedTheme(); }
    pub fn putRequestedTheme(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_RequestedTheme(self, p0)); }
    pub fn put_RequestedTheme(self: *@This(), p0: i32) !void { try self.putRequestedTheme(p0); }
    pub fn getFocusVisualKind(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_FocusVisualKind(self, &out)); return out; }
    pub fn get_FocusVisualKind(self: *@This()) !i32 { return self.getFocusVisualKind(); }
    pub fn putFocusVisualKind(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_FocusVisualKind(self, p0)); }
    pub fn put_FocusVisualKind(self: *@This(), p0: i32) !void { try self.putFocusVisualKind(p0); }
    pub fn getHighContrastAdjustment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_HighContrastAdjustment(self, &out)); return out; }
    pub fn get_HighContrastAdjustment(self: *@This()) !i32 { return self.getHighContrastAdjustment(); }
    pub fn putHighContrastAdjustment(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_HighContrastAdjustment(self, p0)); }
    pub fn put_HighContrastAdjustment(self: *@This(), p0: i32) !void { try self.putHighContrastAdjustment(p0); }
    pub fn addUnhandledException(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_UnhandledException(self, p0, &out0)); return out0; }
    pub fn add_UnhandledException(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addUnhandledException(p0); }
    pub fn removeUnhandledException(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_UnhandledException(self, p0)); }
    pub fn remove_UnhandledException(self: *@This(), p0: EventRegistrationToken) !void { try self.removeUnhandledException(p0); }
    pub fn exit(self: *@This()) !void { try hrCheck(self.lpVtbl.Exit(self)); }
    pub fn Exit(self: *@This()) !void { try self.exit(); }
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
        get_Bounds: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_Visible: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_Content: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Content: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_CoreWindow: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_Compositor: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_Dispatcher: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_DispatcherQueue: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_Title: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Title: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_ExtendsContentIntoTitleBar: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_ExtendsContentIntoTitleBar: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        add_Activated: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_Activated: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_Closed: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_Closed: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_SizeChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_SizeChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_VisibilityChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_VisibilityChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Activate: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        Close: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        SetTitleBar: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getBounds(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Bounds(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Bounds(self: *@This()) !*anyopaque { return self.getBounds(); }
    pub fn getVisible(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_Visible(self, &out)); return out; }
    pub fn get_Visible(self: *@This()) !bool { return self.getVisible(); }
    pub fn getContent(self: *@This()) !?*IInspectable { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Content(self, &out)); if (out) |p| return @ptrCast(@alignCast(p)); return null; }
    pub fn get_Content(self: *@This()) !?*IInspectable { return self.getContent(); }
    pub fn putContent(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Content(self, p0)); }
    pub fn put_Content(self: *@This(), p0: ?*anyopaque) !void { try self.putContent(p0); }
    pub fn getCoreWindow(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_CoreWindow(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_CoreWindow(self: *@This()) !*anyopaque { return self.getCoreWindow(); }
    pub fn getCompositor(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Compositor(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Compositor(self: *@This()) !*anyopaque { return self.getCompositor(); }
    pub fn getDispatcher(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Dispatcher(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Dispatcher(self: *@This()) !*anyopaque { return self.getDispatcher(); }
    pub fn getDispatcherQueue(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_DispatcherQueue(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_DispatcherQueue(self: *@This()) !*anyopaque { return self.getDispatcherQueue(); }
    pub fn getTitle(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Title(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Title(self: *@This()) !*anyopaque { return self.getTitle(); }
    pub fn putTitle(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Title(self, p0)); }
    pub fn put_Title(self: *@This(), p0: ?*anyopaque) !void { try self.putTitle(p0); }
    pub fn getExtendsContentIntoTitleBar(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_ExtendsContentIntoTitleBar(self, &out)); return out; }
    pub fn get_ExtendsContentIntoTitleBar(self: *@This()) !bool { return self.getExtendsContentIntoTitleBar(); }
    pub fn putExtendsContentIntoTitleBar(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_ExtendsContentIntoTitleBar(self, p0)); }
    pub fn put_ExtendsContentIntoTitleBar(self: *@This(), p0: bool) !void { try self.putExtendsContentIntoTitleBar(p0); }
    pub fn addActivated(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Activated(self, p0, &out0)); return out0; }
    pub fn add_Activated(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addActivated(p0); }
    pub fn removeActivated(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_Activated(self, p0)); }
    pub fn remove_Activated(self: *@This(), p0: EventRegistrationToken) !void { try self.removeActivated(p0); }
    pub fn addClosed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Closed(self, p0, &out0)); return out0; }
    pub fn add_Closed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addClosed(p0); }
    pub fn removeClosed(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_Closed(self, p0)); }
    pub fn remove_Closed(self: *@This(), p0: EventRegistrationToken) !void { try self.removeClosed(p0); }
    pub fn addSizeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_SizeChanged(self, p0, &out0)); return out0; }
    pub fn add_SizeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addSizeChanged(p0); }
    pub fn removeSizeChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_SizeChanged(self, p0)); }
    pub fn remove_SizeChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeSizeChanged(p0); }
    pub fn addVisibilityChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_VisibilityChanged(self, p0, &out0)); return out0; }
    pub fn add_VisibilityChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addVisibilityChanged(p0); }
    pub fn removeVisibilityChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_VisibilityChanged(self, p0)); }
    pub fn remove_VisibilityChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeVisibilityChanged(p0); }
    pub fn activate(self: *@This()) !void { try hrCheck(self.lpVtbl.Activate(self)); }
    pub fn Activate(self: *@This()) !void { try self.activate(); }
    pub fn close(self: *@This()) !void { try hrCheck(self.lpVtbl.Close(self)); }
    pub fn Close(self: *@This()) !void { try self.close(); }
    pub fn setTitleBar(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTitleBar(self, p0)); }
    pub fn SetTitleBar(self: *@This(), p0: ?*anyopaque) !void { try self.setTitleBar(p0); }
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
        get_TabWidthMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_TabWidthMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_CloseButtonOverlayMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_CloseButtonOverlayMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_TabStripHeader: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_TabStripHeader: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        get_TabStripHeaderTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_TabStripHeaderTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_TabStripFooter: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_TabStripFooter: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        get_TabStripFooterTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_TabStripFooterTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_IsAddTabButtonVisible: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsAddTabButtonVisible: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_AddTabButtonCommand: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_AddTabButtonCommand: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_AddTabButtonCommandParameter: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_AddTabButtonCommandParameter: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        add_TabCloseRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TabCloseRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_TabDroppedOutside: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TabDroppedOutside: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_AddTabButtonClick: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_AddTabButtonClick: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_TabItemsChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TabItemsChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        get_TabItemsSource: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_TabItemsSource: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        get_TabItems: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_TabItemTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_TabItemTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_TabItemTemplateSelector: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_TabItemTemplateSelector: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_CanDragTabs: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_CanDragTabs: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_CanReorderTabs: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_CanReorderTabs: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_AllowDropTabs: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_AllowDropTabs: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_SelectedIndex: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_SelectedIndex: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_SelectedItem: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_SelectedItem: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        ContainerFromItem: *const fn (*anyopaque, HSTRING, *?*anyopaque) callconv(.winapi) HRESULT,
        ContainerFromIndex: *const fn (*anyopaque, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        add_SelectionChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_SelectionChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_TabDragStarting: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TabDragStarting: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_TabDragCompleted: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TabDragCompleted: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_TabStripDragOver: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TabStripDragOver: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_TabStripDrop: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TabStripDrop: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getTabWidthMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_TabWidthMode(self, &out)); return out; }
    pub fn get_TabWidthMode(self: *@This()) !i32 { return self.getTabWidthMode(); }
    pub fn putTabWidthMode(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_TabWidthMode(self, p0)); }
    pub fn put_TabWidthMode(self: *@This(), p0: i32) !void { try self.putTabWidthMode(p0); }
    pub fn getCloseButtonOverlayMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_CloseButtonOverlayMode(self, &out)); return out; }
    pub fn get_CloseButtonOverlayMode(self: *@This()) !i32 { return self.getCloseButtonOverlayMode(); }
    pub fn putCloseButtonOverlayMode(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_CloseButtonOverlayMode(self, p0)); }
    pub fn put_CloseButtonOverlayMode(self: *@This(), p0: i32) !void { try self.putCloseButtonOverlayMode(p0); }
    pub fn getTabStripHeader(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_TabStripHeader(self, &out)); return out; }
    pub fn get_TabStripHeader(self: *@This()) !HSTRING { return self.getTabStripHeader(); }
    pub fn putTabStripHeader(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_TabStripHeader(self, @ptrCast(p0))); }
    pub fn put_TabStripHeader(self: *@This(), p0: anytype) !void { try self.putTabStripHeader(p0); }
    pub fn getTabStripHeaderTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_TabStripHeaderTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_TabStripHeaderTemplate(self: *@This()) !*anyopaque { return self.getTabStripHeaderTemplate(); }
    pub fn putTabStripHeaderTemplate(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_TabStripHeaderTemplate(self, p0)); }
    pub fn put_TabStripHeaderTemplate(self: *@This(), p0: ?*anyopaque) !void { try self.putTabStripHeaderTemplate(p0); }
    pub fn getTabStripFooter(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_TabStripFooter(self, &out)); return out; }
    pub fn get_TabStripFooter(self: *@This()) !HSTRING { return self.getTabStripFooter(); }
    pub fn putTabStripFooter(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_TabStripFooter(self, @ptrCast(p0))); }
    pub fn put_TabStripFooter(self: *@This(), p0: anytype) !void { try self.putTabStripFooter(p0); }
    pub fn getTabStripFooterTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_TabStripFooterTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_TabStripFooterTemplate(self: *@This()) !*anyopaque { return self.getTabStripFooterTemplate(); }
    pub fn putTabStripFooterTemplate(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_TabStripFooterTemplate(self, p0)); }
    pub fn put_TabStripFooterTemplate(self: *@This(), p0: ?*anyopaque) !void { try self.putTabStripFooterTemplate(p0); }
    pub fn getIsAddTabButtonVisible(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsAddTabButtonVisible(self, &out)); return out; }
    pub fn get_IsAddTabButtonVisible(self: *@This()) !bool { return self.getIsAddTabButtonVisible(); }
    pub fn putIsAddTabButtonVisible(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsAddTabButtonVisible(self, p0)); }
    pub fn put_IsAddTabButtonVisible(self: *@This(), p0: bool) !void { try self.putIsAddTabButtonVisible(p0); }
    pub fn getAddTabButtonCommand(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_AddTabButtonCommand(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_AddTabButtonCommand(self: *@This()) !*anyopaque { return self.getAddTabButtonCommand(); }
    pub fn putAddTabButtonCommand(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_AddTabButtonCommand(self, p0)); }
    pub fn put_AddTabButtonCommand(self: *@This(), p0: ?*anyopaque) !void { try self.putAddTabButtonCommand(p0); }
    pub fn getAddTabButtonCommandParameter(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_AddTabButtonCommandParameter(self, &out)); return out; }
    pub fn get_AddTabButtonCommandParameter(self: *@This()) !HSTRING { return self.getAddTabButtonCommandParameter(); }
    pub fn putAddTabButtonCommandParameter(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_AddTabButtonCommandParameter(self, @ptrCast(p0))); }
    pub fn put_AddTabButtonCommandParameter(self: *@This(), p0: anytype) !void { try self.putAddTabButtonCommandParameter(p0); }
    pub fn addTabCloseRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TabCloseRequested(self, p0, &out0)); return out0; }
    pub fn add_TabCloseRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTabCloseRequested(p0); }
    pub fn removeTabCloseRequested(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TabCloseRequested(self, p0)); }
    pub fn remove_TabCloseRequested(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTabCloseRequested(p0); }
    pub fn addTabDroppedOutside(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TabDroppedOutside(self, p0, &out0)); return out0; }
    pub fn add_TabDroppedOutside(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTabDroppedOutside(p0); }
    pub fn removeTabDroppedOutside(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TabDroppedOutside(self, p0)); }
    pub fn remove_TabDroppedOutside(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTabDroppedOutside(p0); }
    pub fn addAddTabButtonClick(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_AddTabButtonClick(self, p0, &out0)); return out0; }
    pub fn add_AddTabButtonClick(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addAddTabButtonClick(p0); }
    pub fn removeAddTabButtonClick(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_AddTabButtonClick(self, p0)); }
    pub fn remove_AddTabButtonClick(self: *@This(), p0: EventRegistrationToken) !void { try self.removeAddTabButtonClick(p0); }
    pub fn addTabItemsChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TabItemsChanged(self, p0, &out0)); return out0; }
    pub fn add_TabItemsChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTabItemsChanged(p0); }
    pub fn removeTabItemsChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TabItemsChanged(self, p0)); }
    pub fn remove_TabItemsChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTabItemsChanged(p0); }
    pub fn getTabItemsSource(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_TabItemsSource(self, &out)); return out; }
    pub fn get_TabItemsSource(self: *@This()) !HSTRING { return self.getTabItemsSource(); }
    pub fn putTabItemsSource(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_TabItemsSource(self, @ptrCast(p0))); }
    pub fn put_TabItemsSource(self: *@This(), p0: anytype) !void { try self.putTabItemsSource(p0); }
    pub fn getTabItems(self: *@This()) !*IVector { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_TabItems(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn get_TabItems(self: *@This()) !*IVector { return self.getTabItems(); }
    pub fn getTabItemTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_TabItemTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_TabItemTemplate(self: *@This()) !*anyopaque { return self.getTabItemTemplate(); }
    pub fn putTabItemTemplate(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_TabItemTemplate(self, p0)); }
    pub fn put_TabItemTemplate(self: *@This(), p0: ?*anyopaque) !void { try self.putTabItemTemplate(p0); }
    pub fn getTabItemTemplateSelector(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_TabItemTemplateSelector(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_TabItemTemplateSelector(self: *@This()) !*anyopaque { return self.getTabItemTemplateSelector(); }
    pub fn putTabItemTemplateSelector(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_TabItemTemplateSelector(self, p0)); }
    pub fn put_TabItemTemplateSelector(self: *@This(), p0: ?*anyopaque) !void { try self.putTabItemTemplateSelector(p0); }
    pub fn getCanDragTabs(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_CanDragTabs(self, &out)); return out; }
    pub fn get_CanDragTabs(self: *@This()) !bool { return self.getCanDragTabs(); }
    pub fn putCanDragTabs(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_CanDragTabs(self, p0)); }
    pub fn put_CanDragTabs(self: *@This(), p0: bool) !void { try self.putCanDragTabs(p0); }
    pub fn getCanReorderTabs(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_CanReorderTabs(self, &out)); return out; }
    pub fn get_CanReorderTabs(self: *@This()) !bool { return self.getCanReorderTabs(); }
    pub fn putCanReorderTabs(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_CanReorderTabs(self, p0)); }
    pub fn put_CanReorderTabs(self: *@This(), p0: bool) !void { try self.putCanReorderTabs(p0); }
    pub fn getAllowDropTabs(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_AllowDropTabs(self, &out)); return out; }
    pub fn get_AllowDropTabs(self: *@This()) !bool { return self.getAllowDropTabs(); }
    pub fn putAllowDropTabs(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_AllowDropTabs(self, p0)); }
    pub fn put_AllowDropTabs(self: *@This(), p0: bool) !void { try self.putAllowDropTabs(p0); }
    pub fn getSelectedIndex(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_SelectedIndex(self, &out)); return out; }
    pub fn get_SelectedIndex(self: *@This()) !i32 { return self.getSelectedIndex(); }
    pub fn putSelectedIndex(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_SelectedIndex(self, p0)); }
    pub fn put_SelectedIndex(self: *@This(), p0: i32) !void { try self.putSelectedIndex(p0); }
    pub fn getSelectedItem(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_SelectedItem(self, &out)); return out; }
    pub fn get_SelectedItem(self: *@This()) !HSTRING { return self.getSelectedItem(); }
    pub fn putSelectedItem(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_SelectedItem(self, @ptrCast(p0))); }
    pub fn put_SelectedItem(self: *@This(), p0: anytype) !void { try self.putSelectedItem(p0); }
    pub fn containerFromItem(self: *@This(), p0: anytype) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.ContainerFromItem(self, @ptrCast(p0), &out0)); return out0; }
    pub fn ContainerFromItem(self: *@This(), p0: anytype) !?*anyopaque { return self.containerFromItem(p0); }
    pub fn containerFromIndex(self: *@This(), p0: i32) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.ContainerFromIndex(self, p0, &out0)); return out0; }
    pub fn ContainerFromIndex(self: *@This(), p0: i32) !?*anyopaque { return self.containerFromIndex(p0); }
    pub fn addSelectionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_SelectionChanged(self, p0, &out0)); return out0; }
    pub fn add_SelectionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addSelectionChanged(p0); }
    pub fn removeSelectionChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_SelectionChanged(self, p0)); }
    pub fn remove_SelectionChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeSelectionChanged(p0); }
    pub fn addTabDragStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TabDragStarting(self, p0, &out0)); return out0; }
    pub fn add_TabDragStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTabDragStarting(p0); }
    pub fn removeTabDragStarting(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TabDragStarting(self, p0)); }
    pub fn remove_TabDragStarting(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTabDragStarting(p0); }
    pub fn addTabDragCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TabDragCompleted(self, p0, &out0)); return out0; }
    pub fn add_TabDragCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTabDragCompleted(p0); }
    pub fn removeTabDragCompleted(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TabDragCompleted(self, p0)); }
    pub fn remove_TabDragCompleted(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTabDragCompleted(p0); }
    pub fn addTabStripDragOver(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TabStripDragOver(self, p0, &out0)); return out0; }
    pub fn add_TabStripDragOver(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTabStripDragOver(p0); }
    pub fn removeTabStripDragOver(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TabStripDragOver(self, p0)); }
    pub fn remove_TabStripDragOver(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTabStripDragOver(p0); }
    pub fn addTabStripDrop(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TabStripDrop(self, p0, &out0)); return out0; }
    pub fn add_TabStripDrop(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTabStripDrop(p0); }
    pub fn removeTabStripDrop(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TabStripDrop(self, p0)); }
    pub fn remove_TabStripDrop(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTabStripDrop(p0); }
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
        get_Header: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_Header: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        get_HeaderTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_HeaderTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_IconSource: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_IconSource: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_IsClosable: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsClosable: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_TabViewTemplateSettings: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        add_CloseRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_CloseRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getHeader(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_Header(self, &out)); return out; }
    pub fn get_Header(self: *@This()) !HSTRING { return self.getHeader(); }
    pub fn putHeader(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_Header(self, @ptrCast(p0))); }
    pub fn put_Header(self: *@This(), p0: anytype) !void { try self.putHeader(p0); }
    pub fn getHeaderTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_HeaderTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_HeaderTemplate(self: *@This()) !*anyopaque { return self.getHeaderTemplate(); }
    pub fn putHeaderTemplate(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_HeaderTemplate(self, p0)); }
    pub fn put_HeaderTemplate(self: *@This(), p0: ?*anyopaque) !void { try self.putHeaderTemplate(p0); }
    pub fn getIconSource(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_IconSource(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_IconSource(self: *@This()) !*anyopaque { return self.getIconSource(); }
    pub fn putIconSource(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_IconSource(self, p0)); }
    pub fn put_IconSource(self: *@This(), p0: ?*anyopaque) !void { try self.putIconSource(p0); }
    pub fn getIsClosable(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsClosable(self, &out)); return out; }
    pub fn get_IsClosable(self: *@This()) !bool { return self.getIsClosable(); }
    pub fn putIsClosable(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsClosable(self, p0)); }
    pub fn put_IsClosable(self: *@This(), p0: bool) !void { try self.putIsClosable(p0); }
    pub fn getTabViewTemplateSettings(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_TabViewTemplateSettings(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_TabViewTemplateSettings(self: *@This()) !*anyopaque { return self.getTabViewTemplateSettings(); }
    pub fn addCloseRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_CloseRequested(self, p0, &out0)); return out0; }
    pub fn add_CloseRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addCloseRequested(p0); }
    pub fn removeCloseRequested(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_CloseRequested(self, p0)); }
    pub fn remove_CloseRequested(self: *@This(), p0: EventRegistrationToken) !void { try self.removeCloseRequested(p0); }
};

pub const ITabViewTabCloseRequestedEventArgs = extern struct {
    pub const IID = GUID{ .Data1 = 0xd56ab9b2, .Data2 = 0xe264, .Data3 = 0x5c7e, .Data4 = .{ 0xa1, 0xcb, 0xe4, 0x1a, 0x16, 0xa6, 0xc6, 0xc6 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Item: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        get_Tab: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getItem(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_Item(self, &out)); return out; }
    pub fn get_Item(self: *@This()) !HSTRING { return self.getItem(); }
    pub fn getTab(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Tab(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Tab(self: *@This()) !*anyopaque { return self.getTab(); }
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
        get_Content: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_Content: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        get_ContentTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_ContentTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_ContentTemplateSelector: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_ContentTemplateSelector: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_ContentTransitions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_ContentTransitions: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_ContentTemplateRoot: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getContent(self: *@This()) !?*IInspectable { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Content(self, &out)); if (out) |p| return @ptrCast(@alignCast(p)); return null; }
    pub fn get_Content(self: *@This()) !?*IInspectable { return self.getContent(); }
    pub fn putContent(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_Content(self, @ptrCast(p0))); }
    pub fn put_Content(self: *@This(), p0: anytype) !void { try self.putContent(p0); }
    pub fn getContentTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ContentTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ContentTemplate(self: *@This()) !*anyopaque { return self.getContentTemplate(); }
    pub fn putContentTemplate(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_ContentTemplate(self, p0)); }
    pub fn put_ContentTemplate(self: *@This(), p0: ?*anyopaque) !void { try self.putContentTemplate(p0); }
    pub fn getContentTemplateSelector(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ContentTemplateSelector(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ContentTemplateSelector(self: *@This()) !*anyopaque { return self.getContentTemplateSelector(); }
    pub fn putContentTemplateSelector(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_ContentTemplateSelector(self, p0)); }
    pub fn put_ContentTemplateSelector(self: *@This(), p0: ?*anyopaque) !void { try self.putContentTemplateSelector(p0); }
    pub fn getContentTransitions(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ContentTransitions(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ContentTransitions(self: *@This()) !*anyopaque { return self.getContentTransitions(); }
    pub fn putContentTransitions(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_ContentTransitions(self, p0)); }
    pub fn put_ContentTransitions(self: *@This(), p0: ?*anyopaque) !void { try self.putContentTransitions(p0); }
    pub fn getContentTemplateRoot(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ContentTemplateRoot(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ContentTemplateRoot(self: *@This()) !*anyopaque { return self.getContentTemplateRoot(); }
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
        get_DesiredSize: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_AllowDrop: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_AllowDrop: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_Opacity: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_Opacity: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_Clip: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Clip: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_RenderTransform: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_RenderTransform: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Projection: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Projection: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Transform3D: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Transform3D: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_RenderTransformOrigin: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_RenderTransformOrigin: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_IsHitTestVisible: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsHitTestVisible: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_Visibility: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_Visibility: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_RenderSize: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_UseLayoutRounding: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_UseLayoutRounding: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_Transitions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Transitions: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_CacheMode: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_CacheMode: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_IsTapEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsTapEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_IsDoubleTapEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsDoubleTapEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_CanDrag: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_CanDrag: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_IsRightTapEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsRightTapEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_IsHoldingEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsHoldingEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_ManipulationMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_ManipulationMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_PointerCaptures: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_ContextFlyout: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_ContextFlyout: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_CompositeMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_CompositeMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_Lights: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_CanBeScrollAnchor: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_CanBeScrollAnchor: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_ExitDisplayModeOnAccessKeyInvoked: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_ExitDisplayModeOnAccessKeyInvoked: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_IsAccessKeyScope: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsAccessKeyScope: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_AccessKeyScopeOwner: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_AccessKeyScopeOwner: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_AccessKey: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_AccessKey: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_KeyTipPlacementMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_KeyTipPlacementMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_KeyTipHorizontalOffset: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_KeyTipHorizontalOffset: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_KeyTipVerticalOffset: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_KeyTipVerticalOffset: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_KeyTipTarget: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_KeyTipTarget: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_XYFocusKeyboardNavigation: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_XYFocusKeyboardNavigation: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_XYFocusUpNavigationStrategy: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_XYFocusUpNavigationStrategy: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_XYFocusDownNavigationStrategy: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_XYFocusDownNavigationStrategy: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_XYFocusLeftNavigationStrategy: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_XYFocusLeftNavigationStrategy: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_XYFocusRightNavigationStrategy: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_XYFocusRightNavigationStrategy: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_KeyboardAccelerators: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_KeyboardAcceleratorPlacementTarget: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_KeyboardAcceleratorPlacementTarget: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_KeyboardAcceleratorPlacementMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_KeyboardAcceleratorPlacementMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_HighContrastAdjustment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_HighContrastAdjustment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_TabFocusNavigation: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_TabFocusNavigation: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_OpacityTransition: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_OpacityTransition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Translation: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Translation: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_TranslationTransition: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_TranslationTransition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Rotation: *const fn (*anyopaque, *f32) callconv(.winapi) HRESULT,
        put_Rotation: *const fn (*anyopaque, f32) callconv(.winapi) HRESULT,
        get_RotationTransition: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_RotationTransition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Scale: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Scale: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_ScaleTransition: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_ScaleTransition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_TransformMatrix: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_TransformMatrix: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_CenterPoint: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_CenterPoint: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_RotationAxis: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_RotationAxis: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_ActualOffset: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_ActualSize: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_XamlRoot: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_XamlRoot: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Shadow: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Shadow: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_RasterizationScale: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_RasterizationScale: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_FocusState: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        get_UseSystemFocusVisuals: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_UseSystemFocusVisuals: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_XYFocusLeft: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_XYFocusLeft: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_XYFocusRight: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_XYFocusRight: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_XYFocusUp: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_XYFocusUp: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_XYFocusDown: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_XYFocusDown: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_IsTabStop: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsTabStop: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_TabIndex: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_TabIndex: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        add_KeyUp: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_KeyUp: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_KeyDown: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_KeyDown: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_GotFocus: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_GotFocus: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_LostFocus: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_LostFocus: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_DragStarting: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_DragStarting: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_DropCompleted: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_DropCompleted: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_CharacterReceived: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_CharacterReceived: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_DragEnter: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_DragEnter: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_DragLeave: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_DragLeave: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_DragOver: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_DragOver: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_Drop: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_Drop: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_PointerPressed: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_PointerPressed: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_PointerMoved: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_PointerMoved: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_PointerReleased: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_PointerReleased: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_PointerEntered: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_PointerEntered: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_PointerExited: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_PointerExited: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_PointerCaptureLost: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_PointerCaptureLost: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_PointerCanceled: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_PointerCanceled: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_PointerWheelChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_PointerWheelChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_Tapped: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_Tapped: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_DoubleTapped: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_DoubleTapped: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_Holding: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_Holding: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_ContextRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_ContextRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_ContextCanceled: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_ContextCanceled: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_RightTapped: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_RightTapped: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_ManipulationStarting: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_ManipulationStarting: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_ManipulationInertiaStarting: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_ManipulationInertiaStarting: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_ManipulationStarted: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_ManipulationStarted: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_ManipulationDelta: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_ManipulationDelta: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_ManipulationCompleted: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_ManipulationCompleted: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_AccessKeyDisplayRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_AccessKeyDisplayRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_AccessKeyDisplayDismissed: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_AccessKeyDisplayDismissed: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_AccessKeyInvoked: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_AccessKeyInvoked: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_ProcessKeyboardAccelerators: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_ProcessKeyboardAccelerators: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_GettingFocus: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_GettingFocus: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_LosingFocus: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_LosingFocus: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_NoFocusCandidateFound: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_NoFocusCandidateFound: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_PreviewKeyDown: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_PreviewKeyDown: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_PreviewKeyUp: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_PreviewKeyUp: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_BringIntoViewRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_BringIntoViewRequested: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Measure: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        Arrange: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
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
    pub fn getDesiredSize(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_DesiredSize(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_DesiredSize(self: *@This()) !*anyopaque { return self.getDesiredSize(); }
    pub fn getAllowDrop(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_AllowDrop(self, &out)); return out; }
    pub fn get_AllowDrop(self: *@This()) !bool { return self.getAllowDrop(); }
    pub fn putAllowDrop(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_AllowDrop(self, p0)); }
    pub fn put_AllowDrop(self: *@This(), p0: bool) !void { try self.putAllowDrop(p0); }
    pub fn getOpacity(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_Opacity(self, &out)); return out; }
    pub fn get_Opacity(self: *@This()) !f64 { return self.getOpacity(); }
    pub fn putOpacity(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_Opacity(self, p0)); }
    pub fn put_Opacity(self: *@This(), p0: f64) !void { try self.putOpacity(p0); }
    pub fn getClip(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Clip(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Clip(self: *@This()) !*anyopaque { return self.getClip(); }
    pub fn putClip(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Clip(self, p0)); }
    pub fn put_Clip(self: *@This(), p0: ?*anyopaque) !void { try self.putClip(p0); }
    pub fn getRenderTransform(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_RenderTransform(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_RenderTransform(self: *@This()) !*anyopaque { return self.getRenderTransform(); }
    pub fn putRenderTransform(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_RenderTransform(self, p0)); }
    pub fn put_RenderTransform(self: *@This(), p0: ?*anyopaque) !void { try self.putRenderTransform(p0); }
    pub fn getProjection(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Projection(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Projection(self: *@This()) !*anyopaque { return self.getProjection(); }
    pub fn putProjection(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Projection(self, p0)); }
    pub fn put_Projection(self: *@This(), p0: ?*anyopaque) !void { try self.putProjection(p0); }
    pub fn getTransform3D(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Transform3D(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Transform3D(self: *@This()) !*anyopaque { return self.getTransform3D(); }
    pub fn putTransform3D(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Transform3D(self, p0)); }
    pub fn put_Transform3D(self: *@This(), p0: ?*anyopaque) !void { try self.putTransform3D(p0); }
    pub fn getRenderTransformOrigin(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_RenderTransformOrigin(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_RenderTransformOrigin(self: *@This()) !*anyopaque { return self.getRenderTransformOrigin(); }
    pub fn putRenderTransformOrigin(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_RenderTransformOrigin(self, p0)); }
    pub fn put_RenderTransformOrigin(self: *@This(), p0: ?*anyopaque) !void { try self.putRenderTransformOrigin(p0); }
    pub fn getIsHitTestVisible(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsHitTestVisible(self, &out)); return out; }
    pub fn get_IsHitTestVisible(self: *@This()) !bool { return self.getIsHitTestVisible(); }
    pub fn putIsHitTestVisible(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsHitTestVisible(self, p0)); }
    pub fn put_IsHitTestVisible(self: *@This(), p0: bool) !void { try self.putIsHitTestVisible(p0); }
    pub fn getVisibility(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_Visibility(self, &out)); return out; }
    pub fn get_Visibility(self: *@This()) !i32 { return self.getVisibility(); }
    pub fn putVisibility(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_Visibility(self, p0)); }
    pub fn put_Visibility(self: *@This(), p0: i32) !void { try self.putVisibility(p0); }
    pub fn getRenderSize(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_RenderSize(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_RenderSize(self: *@This()) !*anyopaque { return self.getRenderSize(); }
    pub fn getUseLayoutRounding(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_UseLayoutRounding(self, &out)); return out; }
    pub fn get_UseLayoutRounding(self: *@This()) !bool { return self.getUseLayoutRounding(); }
    pub fn putUseLayoutRounding(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_UseLayoutRounding(self, p0)); }
    pub fn put_UseLayoutRounding(self: *@This(), p0: bool) !void { try self.putUseLayoutRounding(p0); }
    pub fn getTransitions(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Transitions(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Transitions(self: *@This()) !*anyopaque { return self.getTransitions(); }
    pub fn putTransitions(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Transitions(self, p0)); }
    pub fn put_Transitions(self: *@This(), p0: ?*anyopaque) !void { try self.putTransitions(p0); }
    pub fn getCacheMode(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_CacheMode(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_CacheMode(self: *@This()) !*anyopaque { return self.getCacheMode(); }
    pub fn putCacheMode(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_CacheMode(self, p0)); }
    pub fn put_CacheMode(self: *@This(), p0: ?*anyopaque) !void { try self.putCacheMode(p0); }
    pub fn getIsTapEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsTapEnabled(self, &out)); return out; }
    pub fn get_IsTapEnabled(self: *@This()) !bool { return self.getIsTapEnabled(); }
    pub fn putIsTapEnabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsTapEnabled(self, p0)); }
    pub fn put_IsTapEnabled(self: *@This(), p0: bool) !void { try self.putIsTapEnabled(p0); }
    pub fn getIsDoubleTapEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsDoubleTapEnabled(self, &out)); return out; }
    pub fn get_IsDoubleTapEnabled(self: *@This()) !bool { return self.getIsDoubleTapEnabled(); }
    pub fn putIsDoubleTapEnabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsDoubleTapEnabled(self, p0)); }
    pub fn put_IsDoubleTapEnabled(self: *@This(), p0: bool) !void { try self.putIsDoubleTapEnabled(p0); }
    pub fn getCanDrag(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_CanDrag(self, &out)); return out; }
    pub fn get_CanDrag(self: *@This()) !bool { return self.getCanDrag(); }
    pub fn putCanDrag(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_CanDrag(self, p0)); }
    pub fn put_CanDrag(self: *@This(), p0: bool) !void { try self.putCanDrag(p0); }
    pub fn getIsRightTapEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsRightTapEnabled(self, &out)); return out; }
    pub fn get_IsRightTapEnabled(self: *@This()) !bool { return self.getIsRightTapEnabled(); }
    pub fn putIsRightTapEnabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsRightTapEnabled(self, p0)); }
    pub fn put_IsRightTapEnabled(self: *@This(), p0: bool) !void { try self.putIsRightTapEnabled(p0); }
    pub fn getIsHoldingEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsHoldingEnabled(self, &out)); return out; }
    pub fn get_IsHoldingEnabled(self: *@This()) !bool { return self.getIsHoldingEnabled(); }
    pub fn putIsHoldingEnabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsHoldingEnabled(self, p0)); }
    pub fn put_IsHoldingEnabled(self: *@This(), p0: bool) !void { try self.putIsHoldingEnabled(p0); }
    pub fn getManipulationMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_ManipulationMode(self, &out)); return out; }
    pub fn get_ManipulationMode(self: *@This()) !i32 { return self.getManipulationMode(); }
    pub fn putManipulationMode(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_ManipulationMode(self, p0)); }
    pub fn put_ManipulationMode(self: *@This(), p0: i32) !void { try self.putManipulationMode(p0); }
    pub fn getPointerCaptures(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_PointerCaptures(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_PointerCaptures(self: *@This()) !*anyopaque { return self.getPointerCaptures(); }
    pub fn getContextFlyout(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ContextFlyout(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ContextFlyout(self: *@This()) !*anyopaque { return self.getContextFlyout(); }
    pub fn putContextFlyout(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_ContextFlyout(self, p0)); }
    pub fn put_ContextFlyout(self: *@This(), p0: ?*anyopaque) !void { try self.putContextFlyout(p0); }
    pub fn getCompositeMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_CompositeMode(self, &out)); return out; }
    pub fn get_CompositeMode(self: *@This()) !i32 { return self.getCompositeMode(); }
    pub fn putCompositeMode(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_CompositeMode(self, p0)); }
    pub fn put_CompositeMode(self: *@This(), p0: i32) !void { try self.putCompositeMode(p0); }
    pub fn getLights(self: *@This()) !*IVector { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Lights(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn get_Lights(self: *@This()) !*IVector { return self.getLights(); }
    pub fn getCanBeScrollAnchor(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_CanBeScrollAnchor(self, &out)); return out; }
    pub fn get_CanBeScrollAnchor(self: *@This()) !bool { return self.getCanBeScrollAnchor(); }
    pub fn putCanBeScrollAnchor(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_CanBeScrollAnchor(self, p0)); }
    pub fn put_CanBeScrollAnchor(self: *@This(), p0: bool) !void { try self.putCanBeScrollAnchor(p0); }
    pub fn getExitDisplayModeOnAccessKeyInvoked(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_ExitDisplayModeOnAccessKeyInvoked(self, &out)); return out; }
    pub fn get_ExitDisplayModeOnAccessKeyInvoked(self: *@This()) !bool { return self.getExitDisplayModeOnAccessKeyInvoked(); }
    pub fn putExitDisplayModeOnAccessKeyInvoked(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_ExitDisplayModeOnAccessKeyInvoked(self, p0)); }
    pub fn put_ExitDisplayModeOnAccessKeyInvoked(self: *@This(), p0: bool) !void { try self.putExitDisplayModeOnAccessKeyInvoked(p0); }
    pub fn getIsAccessKeyScope(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsAccessKeyScope(self, &out)); return out; }
    pub fn get_IsAccessKeyScope(self: *@This()) !bool { return self.getIsAccessKeyScope(); }
    pub fn putIsAccessKeyScope(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsAccessKeyScope(self, p0)); }
    pub fn put_IsAccessKeyScope(self: *@This(), p0: bool) !void { try self.putIsAccessKeyScope(p0); }
    pub fn getAccessKeyScopeOwner(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_AccessKeyScopeOwner(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_AccessKeyScopeOwner(self: *@This()) !*anyopaque { return self.getAccessKeyScopeOwner(); }
    pub fn putAccessKeyScopeOwner(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_AccessKeyScopeOwner(self, p0)); }
    pub fn put_AccessKeyScopeOwner(self: *@This(), p0: ?*anyopaque) !void { try self.putAccessKeyScopeOwner(p0); }
    pub fn getAccessKey(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_AccessKey(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_AccessKey(self: *@This()) !*anyopaque { return self.getAccessKey(); }
    pub fn putAccessKey(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_AccessKey(self, p0)); }
    pub fn put_AccessKey(self: *@This(), p0: ?*anyopaque) !void { try self.putAccessKey(p0); }
    pub fn getKeyTipPlacementMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_KeyTipPlacementMode(self, &out)); return out; }
    pub fn get_KeyTipPlacementMode(self: *@This()) !i32 { return self.getKeyTipPlacementMode(); }
    pub fn putKeyTipPlacementMode(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_KeyTipPlacementMode(self, p0)); }
    pub fn put_KeyTipPlacementMode(self: *@This(), p0: i32) !void { try self.putKeyTipPlacementMode(p0); }
    pub fn getKeyTipHorizontalOffset(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_KeyTipHorizontalOffset(self, &out)); return out; }
    pub fn get_KeyTipHorizontalOffset(self: *@This()) !f64 { return self.getKeyTipHorizontalOffset(); }
    pub fn putKeyTipHorizontalOffset(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_KeyTipHorizontalOffset(self, p0)); }
    pub fn put_KeyTipHorizontalOffset(self: *@This(), p0: f64) !void { try self.putKeyTipHorizontalOffset(p0); }
    pub fn getKeyTipVerticalOffset(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_KeyTipVerticalOffset(self, &out)); return out; }
    pub fn get_KeyTipVerticalOffset(self: *@This()) !f64 { return self.getKeyTipVerticalOffset(); }
    pub fn putKeyTipVerticalOffset(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_KeyTipVerticalOffset(self, p0)); }
    pub fn put_KeyTipVerticalOffset(self: *@This(), p0: f64) !void { try self.putKeyTipVerticalOffset(p0); }
    pub fn getKeyTipTarget(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_KeyTipTarget(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_KeyTipTarget(self: *@This()) !*anyopaque { return self.getKeyTipTarget(); }
    pub fn putKeyTipTarget(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_KeyTipTarget(self, p0)); }
    pub fn put_KeyTipTarget(self: *@This(), p0: ?*anyopaque) !void { try self.putKeyTipTarget(p0); }
    pub fn getXYFocusKeyboardNavigation(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_XYFocusKeyboardNavigation(self, &out)); return out; }
    pub fn get_XYFocusKeyboardNavigation(self: *@This()) !i32 { return self.getXYFocusKeyboardNavigation(); }
    pub fn putXYFocusKeyboardNavigation(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_XYFocusKeyboardNavigation(self, p0)); }
    pub fn put_XYFocusKeyboardNavigation(self: *@This(), p0: i32) !void { try self.putXYFocusKeyboardNavigation(p0); }
    pub fn getXYFocusUpNavigationStrategy(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_XYFocusUpNavigationStrategy(self, &out)); return out; }
    pub fn get_XYFocusUpNavigationStrategy(self: *@This()) !i32 { return self.getXYFocusUpNavigationStrategy(); }
    pub fn putXYFocusUpNavigationStrategy(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_XYFocusUpNavigationStrategy(self, p0)); }
    pub fn put_XYFocusUpNavigationStrategy(self: *@This(), p0: i32) !void { try self.putXYFocusUpNavigationStrategy(p0); }
    pub fn getXYFocusDownNavigationStrategy(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_XYFocusDownNavigationStrategy(self, &out)); return out; }
    pub fn get_XYFocusDownNavigationStrategy(self: *@This()) !i32 { return self.getXYFocusDownNavigationStrategy(); }
    pub fn putXYFocusDownNavigationStrategy(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_XYFocusDownNavigationStrategy(self, p0)); }
    pub fn put_XYFocusDownNavigationStrategy(self: *@This(), p0: i32) !void { try self.putXYFocusDownNavigationStrategy(p0); }
    pub fn getXYFocusLeftNavigationStrategy(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_XYFocusLeftNavigationStrategy(self, &out)); return out; }
    pub fn get_XYFocusLeftNavigationStrategy(self: *@This()) !i32 { return self.getXYFocusLeftNavigationStrategy(); }
    pub fn putXYFocusLeftNavigationStrategy(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_XYFocusLeftNavigationStrategy(self, p0)); }
    pub fn put_XYFocusLeftNavigationStrategy(self: *@This(), p0: i32) !void { try self.putXYFocusLeftNavigationStrategy(p0); }
    pub fn getXYFocusRightNavigationStrategy(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_XYFocusRightNavigationStrategy(self, &out)); return out; }
    pub fn get_XYFocusRightNavigationStrategy(self: *@This()) !i32 { return self.getXYFocusRightNavigationStrategy(); }
    pub fn putXYFocusRightNavigationStrategy(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_XYFocusRightNavigationStrategy(self, p0)); }
    pub fn put_XYFocusRightNavigationStrategy(self: *@This(), p0: i32) !void { try self.putXYFocusRightNavigationStrategy(p0); }
    pub fn getKeyboardAccelerators(self: *@This()) !*IVector { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_KeyboardAccelerators(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn get_KeyboardAccelerators(self: *@This()) !*IVector { return self.getKeyboardAccelerators(); }
    pub fn getKeyboardAcceleratorPlacementTarget(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_KeyboardAcceleratorPlacementTarget(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_KeyboardAcceleratorPlacementTarget(self: *@This()) !*anyopaque { return self.getKeyboardAcceleratorPlacementTarget(); }
    pub fn putKeyboardAcceleratorPlacementTarget(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_KeyboardAcceleratorPlacementTarget(self, p0)); }
    pub fn put_KeyboardAcceleratorPlacementTarget(self: *@This(), p0: ?*anyopaque) !void { try self.putKeyboardAcceleratorPlacementTarget(p0); }
    pub fn getKeyboardAcceleratorPlacementMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_KeyboardAcceleratorPlacementMode(self, &out)); return out; }
    pub fn get_KeyboardAcceleratorPlacementMode(self: *@This()) !i32 { return self.getKeyboardAcceleratorPlacementMode(); }
    pub fn putKeyboardAcceleratorPlacementMode(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_KeyboardAcceleratorPlacementMode(self, p0)); }
    pub fn put_KeyboardAcceleratorPlacementMode(self: *@This(), p0: i32) !void { try self.putKeyboardAcceleratorPlacementMode(p0); }
    pub fn getHighContrastAdjustment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_HighContrastAdjustment(self, &out)); return out; }
    pub fn get_HighContrastAdjustment(self: *@This()) !i32 { return self.getHighContrastAdjustment(); }
    pub fn putHighContrastAdjustment(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_HighContrastAdjustment(self, p0)); }
    pub fn put_HighContrastAdjustment(self: *@This(), p0: i32) !void { try self.putHighContrastAdjustment(p0); }
    pub fn getTabFocusNavigation(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_TabFocusNavigation(self, &out)); return out; }
    pub fn get_TabFocusNavigation(self: *@This()) !i32 { return self.getTabFocusNavigation(); }
    pub fn putTabFocusNavigation(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_TabFocusNavigation(self, p0)); }
    pub fn put_TabFocusNavigation(self: *@This(), p0: i32) !void { try self.putTabFocusNavigation(p0); }
    pub fn getOpacityTransition(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_OpacityTransition(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_OpacityTransition(self: *@This()) !*anyopaque { return self.getOpacityTransition(); }
    pub fn putOpacityTransition(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_OpacityTransition(self, p0)); }
    pub fn put_OpacityTransition(self: *@This(), p0: ?*anyopaque) !void { try self.putOpacityTransition(p0); }
    pub fn getTranslation(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Translation(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Translation(self: *@This()) !*anyopaque { return self.getTranslation(); }
    pub fn putTranslation(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Translation(self, p0)); }
    pub fn put_Translation(self: *@This(), p0: ?*anyopaque) !void { try self.putTranslation(p0); }
    pub fn getTranslationTransition(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_TranslationTransition(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_TranslationTransition(self: *@This()) !*anyopaque { return self.getTranslationTransition(); }
    pub fn putTranslationTransition(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_TranslationTransition(self, p0)); }
    pub fn put_TranslationTransition(self: *@This(), p0: ?*anyopaque) !void { try self.putTranslationTransition(p0); }
    pub fn getRotation(self: *@This()) !f32 { var out: f32 = 0; try hrCheck(self.lpVtbl.get_Rotation(self, &out)); return out; }
    pub fn get_Rotation(self: *@This()) !f32 { return self.getRotation(); }
    pub fn putRotation(self: *@This(), p0: f32) !void { try hrCheck(self.lpVtbl.put_Rotation(self, p0)); }
    pub fn put_Rotation(self: *@This(), p0: f32) !void { try self.putRotation(p0); }
    pub fn getRotationTransition(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_RotationTransition(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_RotationTransition(self: *@This()) !*anyopaque { return self.getRotationTransition(); }
    pub fn putRotationTransition(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_RotationTransition(self, p0)); }
    pub fn put_RotationTransition(self: *@This(), p0: ?*anyopaque) !void { try self.putRotationTransition(p0); }
    pub fn getScale(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Scale(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Scale(self: *@This()) !*anyopaque { return self.getScale(); }
    pub fn putScale(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Scale(self, p0)); }
    pub fn put_Scale(self: *@This(), p0: ?*anyopaque) !void { try self.putScale(p0); }
    pub fn getScaleTransition(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ScaleTransition(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ScaleTransition(self: *@This()) !*anyopaque { return self.getScaleTransition(); }
    pub fn putScaleTransition(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_ScaleTransition(self, p0)); }
    pub fn put_ScaleTransition(self: *@This(), p0: ?*anyopaque) !void { try self.putScaleTransition(p0); }
    pub fn getTransformMatrix(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_TransformMatrix(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_TransformMatrix(self: *@This()) !*anyopaque { return self.getTransformMatrix(); }
    pub fn putTransformMatrix(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_TransformMatrix(self, p0)); }
    pub fn put_TransformMatrix(self: *@This(), p0: ?*anyopaque) !void { try self.putTransformMatrix(p0); }
    pub fn getCenterPoint(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_CenterPoint(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_CenterPoint(self: *@This()) !*anyopaque { return self.getCenterPoint(); }
    pub fn putCenterPoint(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_CenterPoint(self, p0)); }
    pub fn put_CenterPoint(self: *@This(), p0: ?*anyopaque) !void { try self.putCenterPoint(p0); }
    pub fn getRotationAxis(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_RotationAxis(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_RotationAxis(self: *@This()) !*anyopaque { return self.getRotationAxis(); }
    pub fn putRotationAxis(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_RotationAxis(self, p0)); }
    pub fn put_RotationAxis(self: *@This(), p0: ?*anyopaque) !void { try self.putRotationAxis(p0); }
    pub fn getActualOffset(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ActualOffset(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ActualOffset(self: *@This()) !*anyopaque { return self.getActualOffset(); }
    pub fn getActualSize(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ActualSize(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ActualSize(self: *@This()) !*anyopaque { return self.getActualSize(); }
    pub fn getXamlRoot(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_XamlRoot(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_XamlRoot(self: *@This()) !*anyopaque { return self.getXamlRoot(); }
    pub fn putXamlRoot(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_XamlRoot(self, p0)); }
    pub fn put_XamlRoot(self: *@This(), p0: ?*anyopaque) !void { try self.putXamlRoot(p0); }
    pub fn getShadow(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Shadow(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Shadow(self: *@This()) !*anyopaque { return self.getShadow(); }
    pub fn putShadow(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Shadow(self, p0)); }
    pub fn put_Shadow(self: *@This(), p0: ?*anyopaque) !void { try self.putShadow(p0); }
    pub fn getRasterizationScale(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_RasterizationScale(self, &out)); return out; }
    pub fn get_RasterizationScale(self: *@This()) !f64 { return self.getRasterizationScale(); }
    pub fn putRasterizationScale(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_RasterizationScale(self, p0)); }
    pub fn put_RasterizationScale(self: *@This(), p0: f64) !void { try self.putRasterizationScale(p0); }
    pub fn getFocusState(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_FocusState(self, &out)); return out; }
    pub fn get_FocusState(self: *@This()) !i32 { return self.getFocusState(); }
    pub fn getUseSystemFocusVisuals(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_UseSystemFocusVisuals(self, &out)); return out; }
    pub fn get_UseSystemFocusVisuals(self: *@This()) !bool { return self.getUseSystemFocusVisuals(); }
    pub fn putUseSystemFocusVisuals(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_UseSystemFocusVisuals(self, p0)); }
    pub fn put_UseSystemFocusVisuals(self: *@This(), p0: bool) !void { try self.putUseSystemFocusVisuals(p0); }
    pub fn getXYFocusLeft(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_XYFocusLeft(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_XYFocusLeft(self: *@This()) !*anyopaque { return self.getXYFocusLeft(); }
    pub fn putXYFocusLeft(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_XYFocusLeft(self, p0)); }
    pub fn put_XYFocusLeft(self: *@This(), p0: ?*anyopaque) !void { try self.putXYFocusLeft(p0); }
    pub fn getXYFocusRight(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_XYFocusRight(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_XYFocusRight(self: *@This()) !*anyopaque { return self.getXYFocusRight(); }
    pub fn putXYFocusRight(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_XYFocusRight(self, p0)); }
    pub fn put_XYFocusRight(self: *@This(), p0: ?*anyopaque) !void { try self.putXYFocusRight(p0); }
    pub fn getXYFocusUp(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_XYFocusUp(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_XYFocusUp(self: *@This()) !*anyopaque { return self.getXYFocusUp(); }
    pub fn putXYFocusUp(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_XYFocusUp(self, p0)); }
    pub fn put_XYFocusUp(self: *@This(), p0: ?*anyopaque) !void { try self.putXYFocusUp(p0); }
    pub fn getXYFocusDown(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_XYFocusDown(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_XYFocusDown(self: *@This()) !*anyopaque { return self.getXYFocusDown(); }
    pub fn putXYFocusDown(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_XYFocusDown(self, p0)); }
    pub fn put_XYFocusDown(self: *@This(), p0: ?*anyopaque) !void { try self.putXYFocusDown(p0); }
    pub fn getIsTabStop(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsTabStop(self, &out)); return out; }
    pub fn get_IsTabStop(self: *@This()) !bool { return self.getIsTabStop(); }
    pub fn putIsTabStop(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsTabStop(self, p0)); }
    pub fn put_IsTabStop(self: *@This(), p0: bool) !void { try self.putIsTabStop(p0); }
    pub fn getTabIndex(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_TabIndex(self, &out)); return out; }
    pub fn get_TabIndex(self: *@This()) !i32 { return self.getTabIndex(); }
    pub fn putTabIndex(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_TabIndex(self, p0)); }
    pub fn put_TabIndex(self: *@This(), p0: i32) !void { try self.putTabIndex(p0); }
    pub fn addKeyUp(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_KeyUp(self, p0, &out0)); return out0; }
    pub fn add_KeyUp(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addKeyUp(p0); }
    pub fn removeKeyUp(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_KeyUp(self, p0)); }
    pub fn remove_KeyUp(self: *@This(), p0: EventRegistrationToken) !void { try self.removeKeyUp(p0); }
    pub fn addKeyDown(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_KeyDown(self, p0, &out0)); return out0; }
    pub fn add_KeyDown(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addKeyDown(p0); }
    pub fn removeKeyDown(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_KeyDown(self, p0)); }
    pub fn remove_KeyDown(self: *@This(), p0: EventRegistrationToken) !void { try self.removeKeyDown(p0); }
    pub fn addGotFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_GotFocus(self, p0, &out0)); return out0; }
    pub fn add_GotFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addGotFocus(p0); }
    pub fn removeGotFocus(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_GotFocus(self, p0)); }
    pub fn remove_GotFocus(self: *@This(), p0: EventRegistrationToken) !void { try self.removeGotFocus(p0); }
    pub fn addLostFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_LostFocus(self, p0, &out0)); return out0; }
    pub fn add_LostFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addLostFocus(p0); }
    pub fn removeLostFocus(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_LostFocus(self, p0)); }
    pub fn remove_LostFocus(self: *@This(), p0: EventRegistrationToken) !void { try self.removeLostFocus(p0); }
    pub fn addDragStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_DragStarting(self, p0, &out0)); return out0; }
    pub fn add_DragStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addDragStarting(p0); }
    pub fn removeDragStarting(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_DragStarting(self, p0)); }
    pub fn remove_DragStarting(self: *@This(), p0: EventRegistrationToken) !void { try self.removeDragStarting(p0); }
    pub fn addDropCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_DropCompleted(self, p0, &out0)); return out0; }
    pub fn add_DropCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addDropCompleted(p0); }
    pub fn removeDropCompleted(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_DropCompleted(self, p0)); }
    pub fn remove_DropCompleted(self: *@This(), p0: EventRegistrationToken) !void { try self.removeDropCompleted(p0); }
    pub fn addCharacterReceived(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_CharacterReceived(self, p0, &out0)); return out0; }
    pub fn add_CharacterReceived(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addCharacterReceived(p0); }
    pub fn removeCharacterReceived(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_CharacterReceived(self, p0)); }
    pub fn remove_CharacterReceived(self: *@This(), p0: EventRegistrationToken) !void { try self.removeCharacterReceived(p0); }
    pub fn addDragEnter(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_DragEnter(self, p0, &out0)); return out0; }
    pub fn add_DragEnter(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addDragEnter(p0); }
    pub fn removeDragEnter(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_DragEnter(self, p0)); }
    pub fn remove_DragEnter(self: *@This(), p0: EventRegistrationToken) !void { try self.removeDragEnter(p0); }
    pub fn addDragLeave(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_DragLeave(self, p0, &out0)); return out0; }
    pub fn add_DragLeave(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addDragLeave(p0); }
    pub fn removeDragLeave(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_DragLeave(self, p0)); }
    pub fn remove_DragLeave(self: *@This(), p0: EventRegistrationToken) !void { try self.removeDragLeave(p0); }
    pub fn addDragOver(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_DragOver(self, p0, &out0)); return out0; }
    pub fn add_DragOver(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addDragOver(p0); }
    pub fn removeDragOver(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_DragOver(self, p0)); }
    pub fn remove_DragOver(self: *@This(), p0: EventRegistrationToken) !void { try self.removeDragOver(p0); }
    pub fn addDrop(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Drop(self, p0, &out0)); return out0; }
    pub fn add_Drop(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addDrop(p0); }
    pub fn removeDrop(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_Drop(self, p0)); }
    pub fn remove_Drop(self: *@This(), p0: EventRegistrationToken) !void { try self.removeDrop(p0); }
    pub fn addPointerPressed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_PointerPressed(self, p0, &out0)); return out0; }
    pub fn add_PointerPressed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPointerPressed(p0); }
    pub fn removePointerPressed(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_PointerPressed(self, p0)); }
    pub fn remove_PointerPressed(self: *@This(), p0: EventRegistrationToken) !void { try self.removePointerPressed(p0); }
    pub fn addPointerMoved(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_PointerMoved(self, p0, &out0)); return out0; }
    pub fn add_PointerMoved(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPointerMoved(p0); }
    pub fn removePointerMoved(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_PointerMoved(self, p0)); }
    pub fn remove_PointerMoved(self: *@This(), p0: EventRegistrationToken) !void { try self.removePointerMoved(p0); }
    pub fn addPointerReleased(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_PointerReleased(self, p0, &out0)); return out0; }
    pub fn add_PointerReleased(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPointerReleased(p0); }
    pub fn removePointerReleased(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_PointerReleased(self, p0)); }
    pub fn remove_PointerReleased(self: *@This(), p0: EventRegistrationToken) !void { try self.removePointerReleased(p0); }
    pub fn addPointerEntered(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_PointerEntered(self, p0, &out0)); return out0; }
    pub fn add_PointerEntered(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPointerEntered(p0); }
    pub fn removePointerEntered(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_PointerEntered(self, p0)); }
    pub fn remove_PointerEntered(self: *@This(), p0: EventRegistrationToken) !void { try self.removePointerEntered(p0); }
    pub fn addPointerExited(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_PointerExited(self, p0, &out0)); return out0; }
    pub fn add_PointerExited(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPointerExited(p0); }
    pub fn removePointerExited(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_PointerExited(self, p0)); }
    pub fn remove_PointerExited(self: *@This(), p0: EventRegistrationToken) !void { try self.removePointerExited(p0); }
    pub fn addPointerCaptureLost(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_PointerCaptureLost(self, p0, &out0)); return out0; }
    pub fn add_PointerCaptureLost(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPointerCaptureLost(p0); }
    pub fn removePointerCaptureLost(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_PointerCaptureLost(self, p0)); }
    pub fn remove_PointerCaptureLost(self: *@This(), p0: EventRegistrationToken) !void { try self.removePointerCaptureLost(p0); }
    pub fn addPointerCanceled(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_PointerCanceled(self, p0, &out0)); return out0; }
    pub fn add_PointerCanceled(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPointerCanceled(p0); }
    pub fn removePointerCanceled(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_PointerCanceled(self, p0)); }
    pub fn remove_PointerCanceled(self: *@This(), p0: EventRegistrationToken) !void { try self.removePointerCanceled(p0); }
    pub fn addPointerWheelChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_PointerWheelChanged(self, p0, &out0)); return out0; }
    pub fn add_PointerWheelChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPointerWheelChanged(p0); }
    pub fn removePointerWheelChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_PointerWheelChanged(self, p0)); }
    pub fn remove_PointerWheelChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removePointerWheelChanged(p0); }
    pub fn addTapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Tapped(self, p0, &out0)); return out0; }
    pub fn add_Tapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTapped(p0); }
    pub fn removeTapped(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_Tapped(self, p0)); }
    pub fn remove_Tapped(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTapped(p0); }
    pub fn addDoubleTapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_DoubleTapped(self, p0, &out0)); return out0; }
    pub fn add_DoubleTapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addDoubleTapped(p0); }
    pub fn removeDoubleTapped(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_DoubleTapped(self, p0)); }
    pub fn remove_DoubleTapped(self: *@This(), p0: EventRegistrationToken) !void { try self.removeDoubleTapped(p0); }
    pub fn addHolding(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Holding(self, p0, &out0)); return out0; }
    pub fn add_Holding(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addHolding(p0); }
    pub fn removeHolding(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_Holding(self, p0)); }
    pub fn remove_Holding(self: *@This(), p0: EventRegistrationToken) !void { try self.removeHolding(p0); }
    pub fn addContextRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_ContextRequested(self, p0, &out0)); return out0; }
    pub fn add_ContextRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addContextRequested(p0); }
    pub fn removeContextRequested(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_ContextRequested(self, p0)); }
    pub fn remove_ContextRequested(self: *@This(), p0: EventRegistrationToken) !void { try self.removeContextRequested(p0); }
    pub fn addContextCanceled(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_ContextCanceled(self, p0, &out0)); return out0; }
    pub fn add_ContextCanceled(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addContextCanceled(p0); }
    pub fn removeContextCanceled(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_ContextCanceled(self, p0)); }
    pub fn remove_ContextCanceled(self: *@This(), p0: EventRegistrationToken) !void { try self.removeContextCanceled(p0); }
    pub fn addRightTapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_RightTapped(self, p0, &out0)); return out0; }
    pub fn add_RightTapped(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addRightTapped(p0); }
    pub fn removeRightTapped(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_RightTapped(self, p0)); }
    pub fn remove_RightTapped(self: *@This(), p0: EventRegistrationToken) !void { try self.removeRightTapped(p0); }
    pub fn addManipulationStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_ManipulationStarting(self, p0, &out0)); return out0; }
    pub fn add_ManipulationStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addManipulationStarting(p0); }
    pub fn removeManipulationStarting(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_ManipulationStarting(self, p0)); }
    pub fn remove_ManipulationStarting(self: *@This(), p0: EventRegistrationToken) !void { try self.removeManipulationStarting(p0); }
    pub fn addManipulationInertiaStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_ManipulationInertiaStarting(self, p0, &out0)); return out0; }
    pub fn add_ManipulationInertiaStarting(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addManipulationInertiaStarting(p0); }
    pub fn removeManipulationInertiaStarting(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_ManipulationInertiaStarting(self, p0)); }
    pub fn remove_ManipulationInertiaStarting(self: *@This(), p0: EventRegistrationToken) !void { try self.removeManipulationInertiaStarting(p0); }
    pub fn addManipulationStarted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_ManipulationStarted(self, p0, &out0)); return out0; }
    pub fn add_ManipulationStarted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addManipulationStarted(p0); }
    pub fn removeManipulationStarted(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_ManipulationStarted(self, p0)); }
    pub fn remove_ManipulationStarted(self: *@This(), p0: EventRegistrationToken) !void { try self.removeManipulationStarted(p0); }
    pub fn addManipulationDelta(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_ManipulationDelta(self, p0, &out0)); return out0; }
    pub fn add_ManipulationDelta(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addManipulationDelta(p0); }
    pub fn removeManipulationDelta(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_ManipulationDelta(self, p0)); }
    pub fn remove_ManipulationDelta(self: *@This(), p0: EventRegistrationToken) !void { try self.removeManipulationDelta(p0); }
    pub fn addManipulationCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_ManipulationCompleted(self, p0, &out0)); return out0; }
    pub fn add_ManipulationCompleted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addManipulationCompleted(p0); }
    pub fn removeManipulationCompleted(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_ManipulationCompleted(self, p0)); }
    pub fn remove_ManipulationCompleted(self: *@This(), p0: EventRegistrationToken) !void { try self.removeManipulationCompleted(p0); }
    pub fn addAccessKeyDisplayRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_AccessKeyDisplayRequested(self, p0, &out0)); return out0; }
    pub fn add_AccessKeyDisplayRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addAccessKeyDisplayRequested(p0); }
    pub fn removeAccessKeyDisplayRequested(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_AccessKeyDisplayRequested(self, p0)); }
    pub fn remove_AccessKeyDisplayRequested(self: *@This(), p0: EventRegistrationToken) !void { try self.removeAccessKeyDisplayRequested(p0); }
    pub fn addAccessKeyDisplayDismissed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_AccessKeyDisplayDismissed(self, p0, &out0)); return out0; }
    pub fn add_AccessKeyDisplayDismissed(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addAccessKeyDisplayDismissed(p0); }
    pub fn removeAccessKeyDisplayDismissed(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_AccessKeyDisplayDismissed(self, p0)); }
    pub fn remove_AccessKeyDisplayDismissed(self: *@This(), p0: EventRegistrationToken) !void { try self.removeAccessKeyDisplayDismissed(p0); }
    pub fn addAccessKeyInvoked(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_AccessKeyInvoked(self, p0, &out0)); return out0; }
    pub fn add_AccessKeyInvoked(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addAccessKeyInvoked(p0); }
    pub fn removeAccessKeyInvoked(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_AccessKeyInvoked(self, p0)); }
    pub fn remove_AccessKeyInvoked(self: *@This(), p0: EventRegistrationToken) !void { try self.removeAccessKeyInvoked(p0); }
    pub fn addProcessKeyboardAccelerators(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_ProcessKeyboardAccelerators(self, p0, &out0)); return out0; }
    pub fn add_ProcessKeyboardAccelerators(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addProcessKeyboardAccelerators(p0); }
    pub fn removeProcessKeyboardAccelerators(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_ProcessKeyboardAccelerators(self, p0)); }
    pub fn remove_ProcessKeyboardAccelerators(self: *@This(), p0: EventRegistrationToken) !void { try self.removeProcessKeyboardAccelerators(p0); }
    pub fn addGettingFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_GettingFocus(self, p0, &out0)); return out0; }
    pub fn add_GettingFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addGettingFocus(p0); }
    pub fn removeGettingFocus(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_GettingFocus(self, p0)); }
    pub fn remove_GettingFocus(self: *@This(), p0: EventRegistrationToken) !void { try self.removeGettingFocus(p0); }
    pub fn addLosingFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_LosingFocus(self, p0, &out0)); return out0; }
    pub fn add_LosingFocus(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addLosingFocus(p0); }
    pub fn removeLosingFocus(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_LosingFocus(self, p0)); }
    pub fn remove_LosingFocus(self: *@This(), p0: EventRegistrationToken) !void { try self.removeLosingFocus(p0); }
    pub fn addNoFocusCandidateFound(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_NoFocusCandidateFound(self, p0, &out0)); return out0; }
    pub fn add_NoFocusCandidateFound(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addNoFocusCandidateFound(p0); }
    pub fn removeNoFocusCandidateFound(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_NoFocusCandidateFound(self, p0)); }
    pub fn remove_NoFocusCandidateFound(self: *@This(), p0: EventRegistrationToken) !void { try self.removeNoFocusCandidateFound(p0); }
    pub fn addPreviewKeyDown(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_PreviewKeyDown(self, p0, &out0)); return out0; }
    pub fn add_PreviewKeyDown(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPreviewKeyDown(p0); }
    pub fn removePreviewKeyDown(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_PreviewKeyDown(self, p0)); }
    pub fn remove_PreviewKeyDown(self: *@This(), p0: EventRegistrationToken) !void { try self.removePreviewKeyDown(p0); }
    pub fn addPreviewKeyUp(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_PreviewKeyUp(self, p0, &out0)); return out0; }
    pub fn add_PreviewKeyUp(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPreviewKeyUp(p0); }
    pub fn removePreviewKeyUp(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_PreviewKeyUp(self, p0)); }
    pub fn remove_PreviewKeyUp(self: *@This(), p0: EventRegistrationToken) !void { try self.removePreviewKeyUp(p0); }
    pub fn addBringIntoViewRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_BringIntoViewRequested(self, p0, &out0)); return out0; }
    pub fn add_BringIntoViewRequested(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addBringIntoViewRequested(p0); }
    pub fn removeBringIntoViewRequested(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_BringIntoViewRequested(self, p0)); }
    pub fn remove_BringIntoViewRequested(self: *@This(), p0: EventRegistrationToken) !void { try self.removeBringIntoViewRequested(p0); }
    pub fn measure(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.Measure(self, p0)); }
    pub fn Measure(self: *@This(), p0: ?*anyopaque) !void { try self.measure(p0); }
    pub fn arrange(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.Arrange(self, p0)); }
    pub fn Arrange(self: *@This(), p0: ?*anyopaque) !void { try self.arrange(p0); }
    pub fn capturePointer(self: *@This(), p0: ?*anyopaque) !bool { var out0: bool = false; try hrCheck(self.lpVtbl.CapturePointer(self, p0, &out0)); return out0; }
    pub fn CapturePointer(self: *@This(), p0: ?*anyopaque) !bool { return self.capturePointer(p0); }
    pub fn releasePointerCapture(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.ReleasePointerCapture(self, p0)); }
    pub fn ReleasePointerCapture(self: *@This(), p0: ?*anyopaque) !void { try self.releasePointerCapture(p0); }
    pub fn releasePointerCaptures(self: *@This()) !void { try hrCheck(self.lpVtbl.ReleasePointerCaptures(self)); }
    pub fn ReleasePointerCaptures(self: *@This()) !void { try self.releasePointerCaptures(); }
    pub fn addHandler(self: *@This(), p0: ?*anyopaque, p1: anytype, p2: bool) !void { try hrCheck(self.lpVtbl.AddHandler(self, p0, @ptrCast(p1), p2)); }
    pub fn AddHandler(self: *@This(), p0: ?*anyopaque, p1: anytype, p2: bool) !void { try self.addHandler(p0, p1, p2); }
    pub fn removeHandler(self: *@This(), p0: ?*anyopaque, p1: anytype) !void { try hrCheck(self.lpVtbl.RemoveHandler(self, p0, @ptrCast(p1))); }
    pub fn RemoveHandler(self: *@This(), p0: ?*anyopaque, p1: anytype) !void { try self.removeHandler(p0, p1); }
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
    pub fn startBringIntoView_1(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.StartBringIntoView_1(self, p0)); }
    pub fn StartBringIntoView_1(self: *@This(), p0: ?*anyopaque) !void { try self.startBringIntoView_1(p0); }
    pub fn tryInvokeKeyboardAccelerator(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.TryInvokeKeyboardAccelerator(self, p0)); }
    pub fn TryInvokeKeyboardAccelerator(self: *@This(), p0: ?*anyopaque) !void { try self.tryInvokeKeyboardAccelerator(p0); }
    pub fn focus(self: *@This(), p0: i32) !bool { var out0: bool = false; try hrCheck(self.lpVtbl.Focus(self, p0, &out0)); return out0; }
    pub fn Focus(self: *@This(), p0: i32) !bool { return self.focus(p0); }
    pub fn startAnimation(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.StartAnimation(self, p0)); }
    pub fn StartAnimation(self: *@This(), p0: ?*anyopaque) !void { try self.startAnimation(p0); }
    pub fn stopAnimation(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.StopAnimation(self, p0)); }
    pub fn StopAnimation(self: *@This(), p0: ?*anyopaque) !void { try self.stopAnimation(p0); }
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
        get_Triggers: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_Resources: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Resources: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Tag: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_Tag: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        get_Language: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Language: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_ActualWidth: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        get_ActualHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        get_Width: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_Width: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_Height: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_Height: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_MinWidth: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_MinWidth: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_MaxWidth: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_MaxWidth: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_MinHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_MinHeight: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_MaxHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_MaxHeight: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_HorizontalAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_HorizontalAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_VerticalAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_VerticalAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_Margin: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Margin: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Name: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Name: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_BaseUri: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_DataContext: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_DataContext: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        get_AllowFocusOnInteraction: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_AllowFocusOnInteraction: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_FocusVisualMargin: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_FocusVisualMargin: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_FocusVisualSecondaryThickness: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_FocusVisualSecondaryThickness: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_FocusVisualPrimaryThickness: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_FocusVisualPrimaryThickness: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_FocusVisualSecondaryBrush: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_FocusVisualSecondaryBrush: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_FocusVisualPrimaryBrush: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_FocusVisualPrimaryBrush: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_AllowFocusWhenDisabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_AllowFocusWhenDisabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_Style: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Style: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Parent: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_FlowDirection: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_FlowDirection: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_RequestedTheme: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_RequestedTheme: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_IsLoaded: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_ActualTheme: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        add_Loaded: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_Loaded: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_Unloaded: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_Unloaded: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_DataContextChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_DataContextChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_SizeChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_SizeChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_LayoutUpdated: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_LayoutUpdated: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_Loading: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_Loading: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_ActualThemeChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_ActualThemeChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_EffectiveViewportChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_EffectiveViewportChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        FindName: *const fn (*anyopaque, ?*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        SetBinding: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        GetBindingExpression: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getTriggers(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Triggers(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Triggers(self: *@This()) !*anyopaque { return self.getTriggers(); }
    pub fn getResources(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Resources(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Resources(self: *@This()) !*anyopaque { return self.getResources(); }
    pub fn putResources(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Resources(self, p0)); }
    pub fn put_Resources(self: *@This(), p0: ?*anyopaque) !void { try self.putResources(p0); }
    pub fn getTag(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_Tag(self, &out)); return out; }
    pub fn get_Tag(self: *@This()) !HSTRING { return self.getTag(); }
    pub fn putTag(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_Tag(self, @ptrCast(p0))); }
    pub fn put_Tag(self: *@This(), p0: anytype) !void { try self.putTag(p0); }
    pub fn getLanguage(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Language(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Language(self: *@This()) !*anyopaque { return self.getLanguage(); }
    pub fn putLanguage(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Language(self, p0)); }
    pub fn put_Language(self: *@This(), p0: ?*anyopaque) !void { try self.putLanguage(p0); }
    pub fn getActualWidth(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_ActualWidth(self, &out)); return out; }
    pub fn get_ActualWidth(self: *@This()) !f64 { return self.getActualWidth(); }
    pub fn getActualHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_ActualHeight(self, &out)); return out; }
    pub fn get_ActualHeight(self: *@This()) !f64 { return self.getActualHeight(); }
    pub fn getWidth(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_Width(self, &out)); return out; }
    pub fn get_Width(self: *@This()) !f64 { return self.getWidth(); }
    pub fn putWidth(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_Width(self, p0)); }
    pub fn put_Width(self: *@This(), p0: f64) !void { try self.putWidth(p0); }
    pub fn getHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_Height(self, &out)); return out; }
    pub fn get_Height(self: *@This()) !f64 { return self.getHeight(); }
    pub fn putHeight(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_Height(self, p0)); }
    pub fn put_Height(self: *@This(), p0: f64) !void { try self.putHeight(p0); }
    pub fn getMinWidth(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_MinWidth(self, &out)); return out; }
    pub fn get_MinWidth(self: *@This()) !f64 { return self.getMinWidth(); }
    pub fn putMinWidth(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_MinWidth(self, p0)); }
    pub fn put_MinWidth(self: *@This(), p0: f64) !void { try self.putMinWidth(p0); }
    pub fn getMaxWidth(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_MaxWidth(self, &out)); return out; }
    pub fn get_MaxWidth(self: *@This()) !f64 { return self.getMaxWidth(); }
    pub fn putMaxWidth(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_MaxWidth(self, p0)); }
    pub fn put_MaxWidth(self: *@This(), p0: f64) !void { try self.putMaxWidth(p0); }
    pub fn getMinHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_MinHeight(self, &out)); return out; }
    pub fn get_MinHeight(self: *@This()) !f64 { return self.getMinHeight(); }
    pub fn putMinHeight(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_MinHeight(self, p0)); }
    pub fn put_MinHeight(self: *@This(), p0: f64) !void { try self.putMinHeight(p0); }
    pub fn getMaxHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_MaxHeight(self, &out)); return out; }
    pub fn get_MaxHeight(self: *@This()) !f64 { return self.getMaxHeight(); }
    pub fn putMaxHeight(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_MaxHeight(self, p0)); }
    pub fn put_MaxHeight(self: *@This(), p0: f64) !void { try self.putMaxHeight(p0); }
    pub fn getHorizontalAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_HorizontalAlignment(self, &out)); return out; }
    pub fn get_HorizontalAlignment(self: *@This()) !i32 { return self.getHorizontalAlignment(); }
    pub fn putHorizontalAlignment(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_HorizontalAlignment(self, p0)); }
    pub fn put_HorizontalAlignment(self: *@This(), p0: i32) !void { try self.putHorizontalAlignment(p0); }
    pub fn getVerticalAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_VerticalAlignment(self, &out)); return out; }
    pub fn get_VerticalAlignment(self: *@This()) !i32 { return self.getVerticalAlignment(); }
    pub fn putVerticalAlignment(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_VerticalAlignment(self, p0)); }
    pub fn put_VerticalAlignment(self: *@This(), p0: i32) !void { try self.putVerticalAlignment(p0); }
    pub fn getMargin(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Margin(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Margin(self: *@This()) !*anyopaque { return self.getMargin(); }
    pub fn putMargin(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Margin(self, p0)); }
    pub fn put_Margin(self: *@This(), p0: ?*anyopaque) !void { try self.putMargin(p0); }
    pub fn getName(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Name(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Name(self: *@This()) !*anyopaque { return self.getName(); }
    pub fn putName(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Name(self, p0)); }
    pub fn put_Name(self: *@This(), p0: ?*anyopaque) !void { try self.putName(p0); }
    pub fn getBaseUri(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BaseUri(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_BaseUri(self: *@This()) !*anyopaque { return self.getBaseUri(); }
    pub fn getDataContext(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_DataContext(self, &out)); return out; }
    pub fn get_DataContext(self: *@This()) !HSTRING { return self.getDataContext(); }
    pub fn putDataContext(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_DataContext(self, @ptrCast(p0))); }
    pub fn put_DataContext(self: *@This(), p0: anytype) !void { try self.putDataContext(p0); }
    pub fn getAllowFocusOnInteraction(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_AllowFocusOnInteraction(self, &out)); return out; }
    pub fn get_AllowFocusOnInteraction(self: *@This()) !bool { return self.getAllowFocusOnInteraction(); }
    pub fn putAllowFocusOnInteraction(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_AllowFocusOnInteraction(self, p0)); }
    pub fn put_AllowFocusOnInteraction(self: *@This(), p0: bool) !void { try self.putAllowFocusOnInteraction(p0); }
    pub fn getFocusVisualMargin(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_FocusVisualMargin(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_FocusVisualMargin(self: *@This()) !*anyopaque { return self.getFocusVisualMargin(); }
    pub fn putFocusVisualMargin(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_FocusVisualMargin(self, p0)); }
    pub fn put_FocusVisualMargin(self: *@This(), p0: ?*anyopaque) !void { try self.putFocusVisualMargin(p0); }
    pub fn getFocusVisualSecondaryThickness(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_FocusVisualSecondaryThickness(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_FocusVisualSecondaryThickness(self: *@This()) !*anyopaque { return self.getFocusVisualSecondaryThickness(); }
    pub fn putFocusVisualSecondaryThickness(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_FocusVisualSecondaryThickness(self, p0)); }
    pub fn put_FocusVisualSecondaryThickness(self: *@This(), p0: ?*anyopaque) !void { try self.putFocusVisualSecondaryThickness(p0); }
    pub fn getFocusVisualPrimaryThickness(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_FocusVisualPrimaryThickness(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_FocusVisualPrimaryThickness(self: *@This()) !*anyopaque { return self.getFocusVisualPrimaryThickness(); }
    pub fn putFocusVisualPrimaryThickness(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_FocusVisualPrimaryThickness(self, p0)); }
    pub fn put_FocusVisualPrimaryThickness(self: *@This(), p0: ?*anyopaque) !void { try self.putFocusVisualPrimaryThickness(p0); }
    pub fn getFocusVisualSecondaryBrush(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_FocusVisualSecondaryBrush(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_FocusVisualSecondaryBrush(self: *@This()) !*anyopaque { return self.getFocusVisualSecondaryBrush(); }
    pub fn putFocusVisualSecondaryBrush(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_FocusVisualSecondaryBrush(self, p0)); }
    pub fn put_FocusVisualSecondaryBrush(self: *@This(), p0: ?*anyopaque) !void { try self.putFocusVisualSecondaryBrush(p0); }
    pub fn getFocusVisualPrimaryBrush(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_FocusVisualPrimaryBrush(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_FocusVisualPrimaryBrush(self: *@This()) !*anyopaque { return self.getFocusVisualPrimaryBrush(); }
    pub fn putFocusVisualPrimaryBrush(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_FocusVisualPrimaryBrush(self, p0)); }
    pub fn put_FocusVisualPrimaryBrush(self: *@This(), p0: ?*anyopaque) !void { try self.putFocusVisualPrimaryBrush(p0); }
    pub fn getAllowFocusWhenDisabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_AllowFocusWhenDisabled(self, &out)); return out; }
    pub fn get_AllowFocusWhenDisabled(self: *@This()) !bool { return self.getAllowFocusWhenDisabled(); }
    pub fn putAllowFocusWhenDisabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_AllowFocusWhenDisabled(self, p0)); }
    pub fn put_AllowFocusWhenDisabled(self: *@This(), p0: bool) !void { try self.putAllowFocusWhenDisabled(p0); }
    pub fn getStyle(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Style(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Style(self: *@This()) !*anyopaque { return self.getStyle(); }
    pub fn putStyle(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Style(self, p0)); }
    pub fn put_Style(self: *@This(), p0: ?*anyopaque) !void { try self.putStyle(p0); }
    pub fn getParent(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Parent(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Parent(self: *@This()) !*anyopaque { return self.getParent(); }
    pub fn getFlowDirection(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_FlowDirection(self, &out)); return out; }
    pub fn get_FlowDirection(self: *@This()) !i32 { return self.getFlowDirection(); }
    pub fn putFlowDirection(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_FlowDirection(self, p0)); }
    pub fn put_FlowDirection(self: *@This(), p0: i32) !void { try self.putFlowDirection(p0); }
    pub fn getRequestedTheme(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_RequestedTheme(self, &out)); return out; }
    pub fn get_RequestedTheme(self: *@This()) !i32 { return self.getRequestedTheme(); }
    pub fn putRequestedTheme(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_RequestedTheme(self, p0)); }
    pub fn put_RequestedTheme(self: *@This(), p0: i32) !void { try self.putRequestedTheme(p0); }
    pub fn getIsLoaded(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsLoaded(self, &out)); return out; }
    pub fn get_IsLoaded(self: *@This()) !bool { return self.getIsLoaded(); }
    pub fn getActualTheme(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_ActualTheme(self, &out)); return out; }
    pub fn get_ActualTheme(self: *@This()) !i32 { return self.getActualTheme(); }
    pub fn addLoaded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Loaded(self, p0, &out0)); return out0; }
    pub fn add_Loaded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addLoaded(p0); }
    pub fn removeLoaded(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_Loaded(self, p0)); }
    pub fn remove_Loaded(self: *@This(), p0: EventRegistrationToken) !void { try self.removeLoaded(p0); }
    pub fn addUnloaded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Unloaded(self, p0, &out0)); return out0; }
    pub fn add_Unloaded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addUnloaded(p0); }
    pub fn removeUnloaded(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_Unloaded(self, p0)); }
    pub fn remove_Unloaded(self: *@This(), p0: EventRegistrationToken) !void { try self.removeUnloaded(p0); }
    pub fn addDataContextChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_DataContextChanged(self, p0, &out0)); return out0; }
    pub fn add_DataContextChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addDataContextChanged(p0); }
    pub fn removeDataContextChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_DataContextChanged(self, p0)); }
    pub fn remove_DataContextChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeDataContextChanged(p0); }
    pub fn addSizeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_SizeChanged(self, p0, &out0)); return out0; }
    pub fn add_SizeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addSizeChanged(p0); }
    pub fn removeSizeChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_SizeChanged(self, p0)); }
    pub fn remove_SizeChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeSizeChanged(p0); }
    pub fn addLayoutUpdated(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_LayoutUpdated(self, p0, &out0)); return out0; }
    pub fn add_LayoutUpdated(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addLayoutUpdated(p0); }
    pub fn removeLayoutUpdated(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_LayoutUpdated(self, p0)); }
    pub fn remove_LayoutUpdated(self: *@This(), p0: EventRegistrationToken) !void { try self.removeLayoutUpdated(p0); }
    pub fn addLoading(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Loading(self, p0, &out0)); return out0; }
    pub fn add_Loading(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addLoading(p0); }
    pub fn removeLoading(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_Loading(self, p0)); }
    pub fn remove_Loading(self: *@This(), p0: EventRegistrationToken) !void { try self.removeLoading(p0); }
    pub fn addActualThemeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_ActualThemeChanged(self, p0, &out0)); return out0; }
    pub fn add_ActualThemeChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addActualThemeChanged(p0); }
    pub fn removeActualThemeChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_ActualThemeChanged(self, p0)); }
    pub fn remove_ActualThemeChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeActualThemeChanged(p0); }
    pub fn addEffectiveViewportChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_EffectiveViewportChanged(self, p0, &out0)); return out0; }
    pub fn add_EffectiveViewportChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addEffectiveViewportChanged(p0); }
    pub fn removeEffectiveViewportChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_EffectiveViewportChanged(self, p0)); }
    pub fn remove_EffectiveViewportChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeEffectiveViewportChanged(p0); }
    pub fn findName(self: *@This(), p0: ?*anyopaque) !HSTRING { var out0: HSTRING = undefined; try hrCheck(self.lpVtbl.FindName(self, p0, &out0)); return out0; }
    pub fn FindName(self: *@This(), p0: ?*anyopaque) !HSTRING { return self.findName(p0); }
    pub fn setBinding(self: *@This(), p0: ?*anyopaque, p1: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetBinding(self, p0, p1)); }
    pub fn SetBinding(self: *@This(), p0: ?*anyopaque, p1: ?*anyopaque) !void { try self.setBinding(p0, p1); }
    pub fn getBindingExpression(self: *@This(), p0: ?*anyopaque) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetBindingExpression(self, p0, &out0)); return out0; }
    pub fn GetBindingExpression(self: *@This(), p0: ?*anyopaque) !?*anyopaque { return self.getBindingExpression(p0); }
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
        GetXamlType_2: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetXmlnsDefinitions: *const fn (*anyopaque, *u32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getXamlType(self: *@This(), p0: ?*anyopaque) !*IXamlType { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetXamlType(self, p0, &out0)); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed)); }
    pub fn GetXamlType(self: *@This(), p0: ?*anyopaque) !*IXamlType { return self.getXamlType(p0); }
    pub fn getXamlType_1(self: *@This(), p0: ?*anyopaque) !*IXamlType { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetXamlType_2(self, p0, &out0)); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed)); }
    pub fn GetXamlType_2(self: *@This(), p0: ?*anyopaque) !*IXamlType { return self.getXamlType_1(p0); }
    pub fn getXmlnsDefinitions(self: *@This()) !struct { count: u32, definitions: ?*anyopaque } { var count: u32 = 0; var definitions: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetXmlnsDefinitions(self, &count, &definitions)); return .{ .count = count, .definitions = definitions }; }
    pub fn GetXmlnsDefinitions(self: *@This()) !struct { count: u32, definitions: ?*anyopaque } { return self.getXmlnsDefinitions(); }
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
        get_BaseType: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_ContentProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_FullName: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_IsArray: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsCollection: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsConstructible: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsDictionary: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsMarkupExtension: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_IsBindable: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_ItemType: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_KeyType: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_BoxedType: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_UnderlyingType: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        ActivateInstance: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        CreateFromString: *const fn (*anyopaque, ?*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        GetMember: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        AddToVector: *const fn (*anyopaque, HSTRING, HSTRING) callconv(.winapi) HRESULT,
        AddToMap: *const fn (*anyopaque, HSTRING, HSTRING, HSTRING) callconv(.winapi) HRESULT,
        RunInitializer: *const fn (*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getBaseType(self: *@This()) !*IXamlType { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BaseType(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn get_BaseType(self: *@This()) !*IXamlType { return self.getBaseType(); }
    pub fn getContentProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ContentProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ContentProperty(self: *@This()) !*anyopaque { return self.getContentProperty(); }
    pub fn getFullName(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_FullName(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_FullName(self: *@This()) !*anyopaque { return self.getFullName(); }
    pub fn getIsArray(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsArray(self, &out)); return out; }
    pub fn get_IsArray(self: *@This()) !bool { return self.getIsArray(); }
    pub fn getIsCollection(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsCollection(self, &out)); return out; }
    pub fn get_IsCollection(self: *@This()) !bool { return self.getIsCollection(); }
    pub fn getIsConstructible(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsConstructible(self, &out)); return out; }
    pub fn get_IsConstructible(self: *@This()) !bool { return self.getIsConstructible(); }
    pub fn getIsDictionary(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsDictionary(self, &out)); return out; }
    pub fn get_IsDictionary(self: *@This()) !bool { return self.getIsDictionary(); }
    pub fn getIsMarkupExtension(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsMarkupExtension(self, &out)); return out; }
    pub fn get_IsMarkupExtension(self: *@This()) !bool { return self.getIsMarkupExtension(); }
    pub fn getIsBindable(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsBindable(self, &out)); return out; }
    pub fn get_IsBindable(self: *@This()) !bool { return self.getIsBindable(); }
    pub fn getItemType(self: *@This()) !*IXamlType { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ItemType(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn get_ItemType(self: *@This()) !*IXamlType { return self.getItemType(); }
    pub fn getKeyType(self: *@This()) !*IXamlType { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_KeyType(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn get_KeyType(self: *@This()) !*IXamlType { return self.getKeyType(); }
    pub fn getBoxedType(self: *@This()) !*IXamlType { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BoxedType(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn get_BoxedType(self: *@This()) !*IXamlType { return self.getBoxedType(); }
    pub fn getUnderlyingType(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_UnderlyingType(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_UnderlyingType(self: *@This()) !*anyopaque { return self.getUnderlyingType(); }
    pub fn activateInstance(self: *@This()) !HSTRING { var out0: HSTRING = undefined; try hrCheck(self.lpVtbl.ActivateInstance(self, &out0)); return out0; }
    pub fn ActivateInstance(self: *@This()) !HSTRING { return self.activateInstance(); }
    pub fn createFromString(self: *@This(), p0: ?*anyopaque) !HSTRING { var out0: HSTRING = undefined; try hrCheck(self.lpVtbl.CreateFromString(self, p0, &out0)); return out0; }
    pub fn CreateFromString(self: *@This(), p0: ?*anyopaque) !HSTRING { return self.createFromString(p0); }
    pub fn getMember(self: *@This(), p0: ?*anyopaque) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetMember(self, p0, &out0)); return out0; }
    pub fn GetMember(self: *@This(), p0: ?*anyopaque) !?*anyopaque { return self.getMember(p0); }
    pub fn addToVector(self: *@This(), p0: anytype, p1: anytype) !void { try hrCheck(self.lpVtbl.AddToVector(self, @ptrCast(p0), @ptrCast(p1))); }
    pub fn AddToVector(self: *@This(), p0: anytype, p1: anytype) !void { try self.addToVector(p0, p1); }
    pub fn addToMap(self: *@This(), p0: anytype, p1: anytype, p2: anytype) !void { try hrCheck(self.lpVtbl.AddToMap(self, @ptrCast(p0), @ptrCast(p1), @ptrCast(p2))); }
    pub fn AddToMap(self: *@This(), p0: anytype, p1: anytype, p2: anytype) !void { try self.addToMap(p0, p1, p2); }
    pub fn runInitializer(self: *@This()) !void { try hrCheck(self.lpVtbl.RunInitializer(self)); }
    pub fn RunInitializer(self: *@This()) !void { try self.runInitializer(); }
};

pub const ITextBox = extern struct {
    pub const IID = GUID{ .Data1 = 0x873af7c2, .Data2 = 0xab89, .Data3 = 0x5d76, .Data4 = .{ 0x8d, 0xbe, 0x3d, 0x63, 0x25, 0x66, 0x9d, 0xf5 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Text: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Text: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_SelectedText: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_SelectedText: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_SelectionLength: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_SelectionLength: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_SelectionStart: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_SelectionStart: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_MaxLength: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_MaxLength: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_IsReadOnly: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsReadOnly: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_AcceptsReturn: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_AcceptsReturn: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_TextAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_TextAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_TextWrapping: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_TextWrapping: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_IsSpellCheckEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsSpellCheckEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_IsTextPredictionEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsTextPredictionEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_InputScope: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_InputScope: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Header: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_Header: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        get_HeaderTemplate: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_HeaderTemplate: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_PlaceholderText: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_PlaceholderText: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_SelectionHighlightColor: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_SelectionHighlightColor: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_PreventKeyboardDisplayOnProgrammaticFocus: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_PreventKeyboardDisplayOnProgrammaticFocus: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_IsColorFontEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsColorFontEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_SelectionHighlightColorWhenNotFocused: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_SelectionHighlightColorWhenNotFocused: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_HorizontalTextAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_HorizontalTextAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_CharacterCasing: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_CharacterCasing: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_PlaceholderForeground: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_PlaceholderForeground: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_CanPasteClipboardContent: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_CanUndo: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_CanRedo: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_SelectionFlyout: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_SelectionFlyout: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_ProofingMenuFlyout: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_Description: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        put_Description: *const fn (*anyopaque, HSTRING) callconv(.winapi) HRESULT,
        add_TextChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TextChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_SelectionChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_SelectionChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_ContextMenuOpening: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_ContextMenuOpening: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_Paste: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_Paste: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_TextCompositionStarted: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TextCompositionStarted: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_TextCompositionChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TextCompositionChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_TextCompositionEnded: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TextCompositionEnded: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_CopyingToClipboard: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_CopyingToClipboard: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_CuttingToClipboard: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_CuttingToClipboard: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_BeforeTextChanging: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_BeforeTextChanging: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_SelectionChanging: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_SelectionChanging: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        Select: *const fn (*anyopaque, i32, i32) callconv(.winapi) HRESULT,
        SelectAll: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        GetRectFromCharacterIndex: *const fn (*anyopaque, i32, bool, *?*anyopaque) callconv(.winapi) HRESULT,
        GetLinguisticAlternativesAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Undo: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        Redo: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        PasteFromClipboard: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        CopySelectionToClipboard: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        CutSelectionToClipboard: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        ClearUndoRedoHistory: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        get_TextReadingOrder: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_TextReadingOrder: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_DesiredCandidateWindowAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_DesiredCandidateWindowAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        add_CandidateWindowBoundsChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_CandidateWindowBoundsChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_TextChanging: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_TextChanging: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getText(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Text(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Text(self: *@This()) !*anyopaque { return self.getText(); }
    pub fn putText(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Text(self, p0)); }
    pub fn put_Text(self: *@This(), p0: ?*anyopaque) !void { try self.putText(p0); }
    pub fn getSelectedText(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_SelectedText(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_SelectedText(self: *@This()) !*anyopaque { return self.getSelectedText(); }
    pub fn putSelectedText(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_SelectedText(self, p0)); }
    pub fn put_SelectedText(self: *@This(), p0: ?*anyopaque) !void { try self.putSelectedText(p0); }
    pub fn getSelectionLength(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_SelectionLength(self, &out)); return out; }
    pub fn get_SelectionLength(self: *@This()) !i32 { return self.getSelectionLength(); }
    pub fn putSelectionLength(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_SelectionLength(self, p0)); }
    pub fn put_SelectionLength(self: *@This(), p0: i32) !void { try self.putSelectionLength(p0); }
    pub fn getSelectionStart(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_SelectionStart(self, &out)); return out; }
    pub fn get_SelectionStart(self: *@This()) !i32 { return self.getSelectionStart(); }
    pub fn putSelectionStart(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_SelectionStart(self, p0)); }
    pub fn put_SelectionStart(self: *@This(), p0: i32) !void { try self.putSelectionStart(p0); }
    pub fn getMaxLength(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_MaxLength(self, &out)); return out; }
    pub fn get_MaxLength(self: *@This()) !i32 { return self.getMaxLength(); }
    pub fn putMaxLength(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_MaxLength(self, p0)); }
    pub fn put_MaxLength(self: *@This(), p0: i32) !void { try self.putMaxLength(p0); }
    pub fn getIsReadOnly(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsReadOnly(self, &out)); return out; }
    pub fn get_IsReadOnly(self: *@This()) !bool { return self.getIsReadOnly(); }
    pub fn putIsReadOnly(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsReadOnly(self, p0)); }
    pub fn put_IsReadOnly(self: *@This(), p0: bool) !void { try self.putIsReadOnly(p0); }
    pub fn getAcceptsReturn(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_AcceptsReturn(self, &out)); return out; }
    pub fn get_AcceptsReturn(self: *@This()) !bool { return self.getAcceptsReturn(); }
    pub fn putAcceptsReturn(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_AcceptsReturn(self, p0)); }
    pub fn put_AcceptsReturn(self: *@This(), p0: bool) !void { try self.putAcceptsReturn(p0); }
    pub fn getTextAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_TextAlignment(self, &out)); return out; }
    pub fn get_TextAlignment(self: *@This()) !i32 { return self.getTextAlignment(); }
    pub fn putTextAlignment(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_TextAlignment(self, p0)); }
    pub fn put_TextAlignment(self: *@This(), p0: i32) !void { try self.putTextAlignment(p0); }
    pub fn getTextWrapping(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_TextWrapping(self, &out)); return out; }
    pub fn get_TextWrapping(self: *@This()) !i32 { return self.getTextWrapping(); }
    pub fn putTextWrapping(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_TextWrapping(self, p0)); }
    pub fn put_TextWrapping(self: *@This(), p0: i32) !void { try self.putTextWrapping(p0); }
    pub fn getIsSpellCheckEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsSpellCheckEnabled(self, &out)); return out; }
    pub fn get_IsSpellCheckEnabled(self: *@This()) !bool { return self.getIsSpellCheckEnabled(); }
    pub fn putIsSpellCheckEnabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsSpellCheckEnabled(self, p0)); }
    pub fn put_IsSpellCheckEnabled(self: *@This(), p0: bool) !void { try self.putIsSpellCheckEnabled(p0); }
    pub fn getIsTextPredictionEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsTextPredictionEnabled(self, &out)); return out; }
    pub fn get_IsTextPredictionEnabled(self: *@This()) !bool { return self.getIsTextPredictionEnabled(); }
    pub fn putIsTextPredictionEnabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsTextPredictionEnabled(self, p0)); }
    pub fn put_IsTextPredictionEnabled(self: *@This(), p0: bool) !void { try self.putIsTextPredictionEnabled(p0); }
    pub fn getInputScope(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_InputScope(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_InputScope(self: *@This()) !*anyopaque { return self.getInputScope(); }
    pub fn putInputScope(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_InputScope(self, p0)); }
    pub fn put_InputScope(self: *@This(), p0: ?*anyopaque) !void { try self.putInputScope(p0); }
    pub fn getHeader(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_Header(self, &out)); return out; }
    pub fn get_Header(self: *@This()) !HSTRING { return self.getHeader(); }
    pub fn putHeader(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_Header(self, @ptrCast(p0))); }
    pub fn put_Header(self: *@This(), p0: anytype) !void { try self.putHeader(p0); }
    pub fn getHeaderTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_HeaderTemplate(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_HeaderTemplate(self: *@This()) !*anyopaque { return self.getHeaderTemplate(); }
    pub fn putHeaderTemplate(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_HeaderTemplate(self, p0)); }
    pub fn put_HeaderTemplate(self: *@This(), p0: ?*anyopaque) !void { try self.putHeaderTemplate(p0); }
    pub fn getPlaceholderText(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_PlaceholderText(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_PlaceholderText(self: *@This()) !*anyopaque { return self.getPlaceholderText(); }
    pub fn putPlaceholderText(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_PlaceholderText(self, p0)); }
    pub fn put_PlaceholderText(self: *@This(), p0: ?*anyopaque) !void { try self.putPlaceholderText(p0); }
    pub fn getSelectionHighlightColor(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_SelectionHighlightColor(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_SelectionHighlightColor(self: *@This()) !*anyopaque { return self.getSelectionHighlightColor(); }
    pub fn putSelectionHighlightColor(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_SelectionHighlightColor(self, p0)); }
    pub fn put_SelectionHighlightColor(self: *@This(), p0: ?*anyopaque) !void { try self.putSelectionHighlightColor(p0); }
    pub fn getPreventKeyboardDisplayOnProgrammaticFocus(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_PreventKeyboardDisplayOnProgrammaticFocus(self, &out)); return out; }
    pub fn get_PreventKeyboardDisplayOnProgrammaticFocus(self: *@This()) !bool { return self.getPreventKeyboardDisplayOnProgrammaticFocus(); }
    pub fn putPreventKeyboardDisplayOnProgrammaticFocus(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_PreventKeyboardDisplayOnProgrammaticFocus(self, p0)); }
    pub fn put_PreventKeyboardDisplayOnProgrammaticFocus(self: *@This(), p0: bool) !void { try self.putPreventKeyboardDisplayOnProgrammaticFocus(p0); }
    pub fn getIsColorFontEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsColorFontEnabled(self, &out)); return out; }
    pub fn get_IsColorFontEnabled(self: *@This()) !bool { return self.getIsColorFontEnabled(); }
    pub fn putIsColorFontEnabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsColorFontEnabled(self, p0)); }
    pub fn put_IsColorFontEnabled(self: *@This(), p0: bool) !void { try self.putIsColorFontEnabled(p0); }
    pub fn getSelectionHighlightColorWhenNotFocused(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_SelectionHighlightColorWhenNotFocused(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_SelectionHighlightColorWhenNotFocused(self: *@This()) !*anyopaque { return self.getSelectionHighlightColorWhenNotFocused(); }
    pub fn putSelectionHighlightColorWhenNotFocused(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_SelectionHighlightColorWhenNotFocused(self, p0)); }
    pub fn put_SelectionHighlightColorWhenNotFocused(self: *@This(), p0: ?*anyopaque) !void { try self.putSelectionHighlightColorWhenNotFocused(p0); }
    pub fn getHorizontalTextAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_HorizontalTextAlignment(self, &out)); return out; }
    pub fn get_HorizontalTextAlignment(self: *@This()) !i32 { return self.getHorizontalTextAlignment(); }
    pub fn putHorizontalTextAlignment(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_HorizontalTextAlignment(self, p0)); }
    pub fn put_HorizontalTextAlignment(self: *@This(), p0: i32) !void { try self.putHorizontalTextAlignment(p0); }
    pub fn getCharacterCasing(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_CharacterCasing(self, &out)); return out; }
    pub fn get_CharacterCasing(self: *@This()) !i32 { return self.getCharacterCasing(); }
    pub fn putCharacterCasing(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_CharacterCasing(self, p0)); }
    pub fn put_CharacterCasing(self: *@This(), p0: i32) !void { try self.putCharacterCasing(p0); }
    pub fn getPlaceholderForeground(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_PlaceholderForeground(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_PlaceholderForeground(self: *@This()) !*anyopaque { return self.getPlaceholderForeground(); }
    pub fn putPlaceholderForeground(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_PlaceholderForeground(self, p0)); }
    pub fn put_PlaceholderForeground(self: *@This(), p0: ?*anyopaque) !void { try self.putPlaceholderForeground(p0); }
    pub fn getCanPasteClipboardContent(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_CanPasteClipboardContent(self, &out)); return out; }
    pub fn get_CanPasteClipboardContent(self: *@This()) !bool { return self.getCanPasteClipboardContent(); }
    pub fn getCanUndo(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_CanUndo(self, &out)); return out; }
    pub fn get_CanUndo(self: *@This()) !bool { return self.getCanUndo(); }
    pub fn getCanRedo(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_CanRedo(self, &out)); return out; }
    pub fn get_CanRedo(self: *@This()) !bool { return self.getCanRedo(); }
    pub fn getSelectionFlyout(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_SelectionFlyout(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_SelectionFlyout(self: *@This()) !*anyopaque { return self.getSelectionFlyout(); }
    pub fn putSelectionFlyout(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_SelectionFlyout(self, p0)); }
    pub fn put_SelectionFlyout(self: *@This(), p0: ?*anyopaque) !void { try self.putSelectionFlyout(p0); }
    pub fn getProofingMenuFlyout(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ProofingMenuFlyout(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ProofingMenuFlyout(self: *@This()) !*anyopaque { return self.getProofingMenuFlyout(); }
    pub fn getDescription(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.get_Description(self, &out)); return out; }
    pub fn get_Description(self: *@This()) !HSTRING { return self.getDescription(); }
    pub fn putDescription(self: *@This(), p0: anytype) !void { try hrCheck(self.lpVtbl.put_Description(self, @ptrCast(p0))); }
    pub fn put_Description(self: *@This(), p0: anytype) !void { try self.putDescription(p0); }
    pub fn addTextChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TextChanged(self, p0, &out0)); return out0; }
    pub fn add_TextChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTextChanged(p0); }
    pub fn removeTextChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TextChanged(self, p0)); }
    pub fn remove_TextChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTextChanged(p0); }
    pub fn addSelectionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_SelectionChanged(self, p0, &out0)); return out0; }
    pub fn add_SelectionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addSelectionChanged(p0); }
    pub fn removeSelectionChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_SelectionChanged(self, p0)); }
    pub fn remove_SelectionChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeSelectionChanged(p0); }
    pub fn addContextMenuOpening(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_ContextMenuOpening(self, p0, &out0)); return out0; }
    pub fn add_ContextMenuOpening(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addContextMenuOpening(p0); }
    pub fn removeContextMenuOpening(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_ContextMenuOpening(self, p0)); }
    pub fn remove_ContextMenuOpening(self: *@This(), p0: EventRegistrationToken) !void { try self.removeContextMenuOpening(p0); }
    pub fn addPaste(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_Paste(self, p0, &out0)); return out0; }
    pub fn add_Paste(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addPaste(p0); }
    pub fn removePaste(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_Paste(self, p0)); }
    pub fn remove_Paste(self: *@This(), p0: EventRegistrationToken) !void { try self.removePaste(p0); }
    pub fn addTextCompositionStarted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TextCompositionStarted(self, p0, &out0)); return out0; }
    pub fn add_TextCompositionStarted(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTextCompositionStarted(p0); }
    pub fn removeTextCompositionStarted(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TextCompositionStarted(self, p0)); }
    pub fn remove_TextCompositionStarted(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTextCompositionStarted(p0); }
    pub fn addTextCompositionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TextCompositionChanged(self, p0, &out0)); return out0; }
    pub fn add_TextCompositionChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTextCompositionChanged(p0); }
    pub fn removeTextCompositionChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TextCompositionChanged(self, p0)); }
    pub fn remove_TextCompositionChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTextCompositionChanged(p0); }
    pub fn addTextCompositionEnded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TextCompositionEnded(self, p0, &out0)); return out0; }
    pub fn add_TextCompositionEnded(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTextCompositionEnded(p0); }
    pub fn removeTextCompositionEnded(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TextCompositionEnded(self, p0)); }
    pub fn remove_TextCompositionEnded(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTextCompositionEnded(p0); }
    pub fn addCopyingToClipboard(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_CopyingToClipboard(self, p0, &out0)); return out0; }
    pub fn add_CopyingToClipboard(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addCopyingToClipboard(p0); }
    pub fn removeCopyingToClipboard(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_CopyingToClipboard(self, p0)); }
    pub fn remove_CopyingToClipboard(self: *@This(), p0: EventRegistrationToken) !void { try self.removeCopyingToClipboard(p0); }
    pub fn addCuttingToClipboard(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_CuttingToClipboard(self, p0, &out0)); return out0; }
    pub fn add_CuttingToClipboard(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addCuttingToClipboard(p0); }
    pub fn removeCuttingToClipboard(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_CuttingToClipboard(self, p0)); }
    pub fn remove_CuttingToClipboard(self: *@This(), p0: EventRegistrationToken) !void { try self.removeCuttingToClipboard(p0); }
    pub fn addBeforeTextChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_BeforeTextChanging(self, p0, &out0)); return out0; }
    pub fn add_BeforeTextChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addBeforeTextChanging(p0); }
    pub fn removeBeforeTextChanging(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_BeforeTextChanging(self, p0)); }
    pub fn remove_BeforeTextChanging(self: *@This(), p0: EventRegistrationToken) !void { try self.removeBeforeTextChanging(p0); }
    pub fn addSelectionChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_SelectionChanging(self, p0, &out0)); return out0; }
    pub fn add_SelectionChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addSelectionChanging(p0); }
    pub fn removeSelectionChanging(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_SelectionChanging(self, p0)); }
    pub fn remove_SelectionChanging(self: *@This(), p0: EventRegistrationToken) !void { try self.removeSelectionChanging(p0); }
    pub fn select(self: *@This(), p0: i32, p1: i32) !void { try hrCheck(self.lpVtbl.Select(self, p0, p1)); }
    pub fn Select(self: *@This(), p0: i32, p1: i32) !void { try self.select(p0, p1); }
    pub fn selectAll(self: *@This()) !void { try hrCheck(self.lpVtbl.SelectAll(self)); }
    pub fn SelectAll(self: *@This()) !void { try self.selectAll(); }
    pub fn getRectFromCharacterIndex(self: *@This(), p0: i32, p1: bool) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetRectFromCharacterIndex(self, p0, p1, &out0)); return out0; }
    pub fn GetRectFromCharacterIndex(self: *@This(), p0: i32, p1: bool) !?*anyopaque { return self.getRectFromCharacterIndex(p0, p1); }
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
    pub fn getTextReadingOrder(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_TextReadingOrder(self, &out)); return out; }
    pub fn get_TextReadingOrder(self: *@This()) !i32 { return self.getTextReadingOrder(); }
    pub fn putTextReadingOrder(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_TextReadingOrder(self, p0)); }
    pub fn put_TextReadingOrder(self: *@This(), p0: i32) !void { try self.putTextReadingOrder(p0); }
    pub fn getDesiredCandidateWindowAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_DesiredCandidateWindowAlignment(self, &out)); return out; }
    pub fn get_DesiredCandidateWindowAlignment(self: *@This()) !i32 { return self.getDesiredCandidateWindowAlignment(); }
    pub fn putDesiredCandidateWindowAlignment(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_DesiredCandidateWindowAlignment(self, p0)); }
    pub fn put_DesiredCandidateWindowAlignment(self: *@This(), p0: i32) !void { try self.putDesiredCandidateWindowAlignment(p0); }
    pub fn addCandidateWindowBoundsChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_CandidateWindowBoundsChanged(self, p0, &out0)); return out0; }
    pub fn add_CandidateWindowBoundsChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addCandidateWindowBoundsChanged(p0); }
    pub fn removeCandidateWindowBoundsChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_CandidateWindowBoundsChanged(self, p0)); }
    pub fn remove_CandidateWindowBoundsChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeCandidateWindowBoundsChanged(p0); }
    pub fn addTextChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_TextChanging(self, p0, &out0)); return out0; }
    pub fn add_TextChanging(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addTextChanging(p0); }
    pub fn removeTextChanging(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_TextChanging(self, p0)); }
    pub fn remove_TextChanging(self: *@This(), p0: EventRegistrationToken) !void { try self.removeTextChanging(p0); }
};

pub const ISolidColorBrush = extern struct {
    pub const IID = GUID{ .Data1 = 0xb3865c31, .Data2 = 0x37c8, .Data3 = 0x55c1, .Data4 = .{ 0x8a, 0x72, 0xd4, 0x1c, 0x67, 0x64, 0x2e, 0x2a } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Color: *const fn (*anyopaque, *Color) callconv(.winapi) HRESULT,
        put_Color: *const fn (*anyopaque, Color) callconv(.winapi) HRESULT,
    };
    pub const Color = extern struct { a: u8, r: u8, g: u8, b: u8 };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getColor(self: *@This()) !Color { var out: Color = .{ .a = 0, .r = 0, .g = 0, .b = 0 }; try hrCheck(self.lpVtbl.get_Color(self, &out)); return out; }
    pub fn get_Color(self: *@This()) !Color { return self.getColor(); }
    pub fn putColor(self: *@This(), p0: Color) !void { try hrCheck(self.lpVtbl.put_Color(self, p0)); }
    pub fn put_Color(self: *@This(), p0: Color) !void { try self.putColor(p0); }
};

pub const IControl = extern struct {
    pub const IID = GUID{ .Data1 = 0x857d6e8a, .Data2 = 0xd45a, .Data3 = 0x5c69, .Data4 = .{ 0xa9, 0x9c, 0xbf, 0x6a, 0x5c, 0x54, 0xfb, 0x38 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_IsFocusEngagementEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsFocusEngagementEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_IsFocusEngaged: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsFocusEngaged: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_RequiresPointer: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_RequiresPointer: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_FontSize: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_FontSize: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_FontFamily: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_FontFamily: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_FontWeight: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_FontWeight: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_FontStyle: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_FontStyle: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_FontStretch: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_FontStretch: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_CharacterSpacing: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_CharacterSpacing: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_Foreground: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Foreground: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_IsTextScaleFactorEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsTextScaleFactorEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_IsEnabled: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        put_IsEnabled: *const fn (*anyopaque, bool) callconv(.winapi) HRESULT,
        get_TabNavigation: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_TabNavigation: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_Template: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Template: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Padding: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Padding: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_HorizontalContentAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_HorizontalContentAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_VerticalContentAlignment: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_VerticalContentAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_Background: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Background: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_BackgroundSizing: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_BackgroundSizing: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_BorderThickness: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_BorderThickness: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_BorderBrush: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_BorderBrush: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_DefaultStyleResourceUri: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_DefaultStyleResourceUri: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_ElementSoundMode: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_ElementSoundMode: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_CornerRadius: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_CornerRadius: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        add_FocusEngaged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_FocusEngaged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_FocusDisengaged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_FocusDisengaged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        add_IsEnabledChanged: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT,
        remove_IsEnabledChanged: *const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT,
        RemoveFocusEngagement: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        ApplyTemplate: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getIsFocusEngagementEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsFocusEngagementEnabled(self, &out)); return out; }
    pub fn get_IsFocusEngagementEnabled(self: *@This()) !bool { return self.getIsFocusEngagementEnabled(); }
    pub fn putIsFocusEngagementEnabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsFocusEngagementEnabled(self, p0)); }
    pub fn put_IsFocusEngagementEnabled(self: *@This(), p0: bool) !void { try self.putIsFocusEngagementEnabled(p0); }
    pub fn getIsFocusEngaged(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsFocusEngaged(self, &out)); return out; }
    pub fn get_IsFocusEngaged(self: *@This()) !bool { return self.getIsFocusEngaged(); }
    pub fn putIsFocusEngaged(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsFocusEngaged(self, p0)); }
    pub fn put_IsFocusEngaged(self: *@This(), p0: bool) !void { try self.putIsFocusEngaged(p0); }
    pub fn getRequiresPointer(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_RequiresPointer(self, &out)); return out; }
    pub fn get_RequiresPointer(self: *@This()) !i32 { return self.getRequiresPointer(); }
    pub fn putRequiresPointer(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_RequiresPointer(self, p0)); }
    pub fn put_RequiresPointer(self: *@This(), p0: i32) !void { try self.putRequiresPointer(p0); }
    pub fn getFontSize(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_FontSize(self, &out)); return out; }
    pub fn get_FontSize(self: *@This()) !f64 { return self.getFontSize(); }
    pub fn putFontSize(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_FontSize(self, p0)); }
    pub fn put_FontSize(self: *@This(), p0: f64) !void { try self.putFontSize(p0); }
    pub fn getFontFamily(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_FontFamily(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_FontFamily(self: *@This()) !*anyopaque { return self.getFontFamily(); }
    pub fn putFontFamily(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_FontFamily(self, p0)); }
    pub fn put_FontFamily(self: *@This(), p0: ?*anyopaque) !void { try self.putFontFamily(p0); }
    pub fn getFontWeight(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_FontWeight(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_FontWeight(self: *@This()) !*anyopaque { return self.getFontWeight(); }
    pub fn putFontWeight(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_FontWeight(self, p0)); }
    pub fn put_FontWeight(self: *@This(), p0: ?*anyopaque) !void { try self.putFontWeight(p0); }
    pub fn getFontStyle(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_FontStyle(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_FontStyle(self: *@This()) !*anyopaque { return self.getFontStyle(); }
    pub fn putFontStyle(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_FontStyle(self, p0)); }
    pub fn put_FontStyle(self: *@This(), p0: ?*anyopaque) !void { try self.putFontStyle(p0); }
    pub fn getFontStretch(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_FontStretch(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_FontStretch(self: *@This()) !*anyopaque { return self.getFontStretch(); }
    pub fn putFontStretch(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_FontStretch(self, p0)); }
    pub fn put_FontStretch(self: *@This(), p0: ?*anyopaque) !void { try self.putFontStretch(p0); }
    pub fn getCharacterSpacing(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_CharacterSpacing(self, &out)); return out; }
    pub fn get_CharacterSpacing(self: *@This()) !i32 { return self.getCharacterSpacing(); }
    pub fn putCharacterSpacing(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_CharacterSpacing(self, p0)); }
    pub fn put_CharacterSpacing(self: *@This(), p0: i32) !void { try self.putCharacterSpacing(p0); }
    pub fn getForeground(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Foreground(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Foreground(self: *@This()) !*anyopaque { return self.getForeground(); }
    pub fn putForeground(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Foreground(self, p0)); }
    pub fn put_Foreground(self: *@This(), p0: ?*anyopaque) !void { try self.putForeground(p0); }
    pub fn getIsTextScaleFactorEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsTextScaleFactorEnabled(self, &out)); return out; }
    pub fn get_IsTextScaleFactorEnabled(self: *@This()) !bool { return self.getIsTextScaleFactorEnabled(); }
    pub fn putIsTextScaleFactorEnabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsTextScaleFactorEnabled(self, p0)); }
    pub fn put_IsTextScaleFactorEnabled(self: *@This(), p0: bool) !void { try self.putIsTextScaleFactorEnabled(p0); }
    pub fn getIsEnabled(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsEnabled(self, &out)); return out; }
    pub fn get_IsEnabled(self: *@This()) !bool { return self.getIsEnabled(); }
    pub fn putIsEnabled(self: *@This(), p0: bool) !void { try hrCheck(self.lpVtbl.put_IsEnabled(self, p0)); }
    pub fn put_IsEnabled(self: *@This(), p0: bool) !void { try self.putIsEnabled(p0); }
    pub fn getTabNavigation(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_TabNavigation(self, &out)); return out; }
    pub fn get_TabNavigation(self: *@This()) !i32 { return self.getTabNavigation(); }
    pub fn putTabNavigation(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_TabNavigation(self, p0)); }
    pub fn put_TabNavigation(self: *@This(), p0: i32) !void { try self.putTabNavigation(p0); }
    pub fn getTemplate(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Template(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Template(self: *@This()) !*anyopaque { return self.getTemplate(); }
    pub fn putTemplate(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Template(self, p0)); }
    pub fn put_Template(self: *@This(), p0: ?*anyopaque) !void { try self.putTemplate(p0); }
    pub fn getPadding(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Padding(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Padding(self: *@This()) !*anyopaque { return self.getPadding(); }
    pub fn putPadding(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Padding(self, p0)); }
    pub fn put_Padding(self: *@This(), p0: ?*anyopaque) !void { try self.putPadding(p0); }
    pub fn getHorizontalContentAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_HorizontalContentAlignment(self, &out)); return out; }
    pub fn get_HorizontalContentAlignment(self: *@This()) !i32 { return self.getHorizontalContentAlignment(); }
    pub fn putHorizontalContentAlignment(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_HorizontalContentAlignment(self, p0)); }
    pub fn put_HorizontalContentAlignment(self: *@This(), p0: i32) !void { try self.putHorizontalContentAlignment(p0); }
    pub fn getVerticalContentAlignment(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_VerticalContentAlignment(self, &out)); return out; }
    pub fn get_VerticalContentAlignment(self: *@This()) !i32 { return self.getVerticalContentAlignment(); }
    pub fn putVerticalContentAlignment(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_VerticalContentAlignment(self, p0)); }
    pub fn put_VerticalContentAlignment(self: *@This(), p0: i32) !void { try self.putVerticalContentAlignment(p0); }
    pub fn getBackground(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Background(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Background(self: *@This()) !*anyopaque { return self.getBackground(); }
    pub fn putBackground(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Background(self, p0)); }
    pub fn put_Background(self: *@This(), p0: ?*anyopaque) !void { try self.putBackground(p0); }
    pub fn getBackgroundSizing(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_BackgroundSizing(self, &out)); return out; }
    pub fn get_BackgroundSizing(self: *@This()) !i32 { return self.getBackgroundSizing(); }
    pub fn putBackgroundSizing(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_BackgroundSizing(self, p0)); }
    pub fn put_BackgroundSizing(self: *@This(), p0: i32) !void { try self.putBackgroundSizing(p0); }
    pub fn getBorderThickness(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BorderThickness(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_BorderThickness(self: *@This()) !*anyopaque { return self.getBorderThickness(); }
    pub fn putBorderThickness(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_BorderThickness(self, p0)); }
    pub fn put_BorderThickness(self: *@This(), p0: ?*anyopaque) !void { try self.putBorderThickness(p0); }
    pub fn getBorderBrush(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BorderBrush(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_BorderBrush(self: *@This()) !*anyopaque { return self.getBorderBrush(); }
    pub fn putBorderBrush(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_BorderBrush(self, p0)); }
    pub fn put_BorderBrush(self: *@This(), p0: ?*anyopaque) !void { try self.putBorderBrush(p0); }
    pub fn getDefaultStyleResourceUri(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_DefaultStyleResourceUri(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_DefaultStyleResourceUri(self: *@This()) !*anyopaque { return self.getDefaultStyleResourceUri(); }
    pub fn putDefaultStyleResourceUri(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_DefaultStyleResourceUri(self, p0)); }
    pub fn put_DefaultStyleResourceUri(self: *@This(), p0: ?*anyopaque) !void { try self.putDefaultStyleResourceUri(p0); }
    pub fn getElementSoundMode(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_ElementSoundMode(self, &out)); return out; }
    pub fn get_ElementSoundMode(self: *@This()) !i32 { return self.getElementSoundMode(); }
    pub fn putElementSoundMode(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_ElementSoundMode(self, p0)); }
    pub fn put_ElementSoundMode(self: *@This(), p0: i32) !void { try self.putElementSoundMode(p0); }
    pub fn getCornerRadius(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_CornerRadius(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_CornerRadius(self: *@This()) !*anyopaque { return self.getCornerRadius(); }
    pub fn putCornerRadius(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_CornerRadius(self, p0)); }
    pub fn put_CornerRadius(self: *@This(), p0: ?*anyopaque) !void { try self.putCornerRadius(p0); }
    pub fn addFocusEngaged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_FocusEngaged(self, p0, &out0)); return out0; }
    pub fn add_FocusEngaged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addFocusEngaged(p0); }
    pub fn removeFocusEngaged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_FocusEngaged(self, p0)); }
    pub fn remove_FocusEngaged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeFocusEngaged(p0); }
    pub fn addFocusDisengaged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_FocusDisengaged(self, p0, &out0)); return out0; }
    pub fn add_FocusDisengaged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addFocusDisengaged(p0); }
    pub fn removeFocusDisengaged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_FocusDisengaged(self, p0)); }
    pub fn remove_FocusDisengaged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeFocusDisengaged(p0); }
    pub fn addIsEnabledChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { var out0: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.add_IsEnabledChanged(self, p0, &out0)); return out0; }
    pub fn add_IsEnabledChanged(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken { return self.addIsEnabledChanged(p0); }
    pub fn removeIsEnabledChanged(self: *@This(), p0: EventRegistrationToken) !void { try hrCheck(self.lpVtbl.remove_IsEnabledChanged(self, p0)); }
    pub fn remove_IsEnabledChanged(self: *@This(), p0: EventRegistrationToken) !void { try self.removeIsEnabledChanged(p0); }
    pub fn removeFocusEngagement(self: *@This()) !void { try hrCheck(self.lpVtbl.RemoveFocusEngagement(self)); }
    pub fn RemoveFocusEngagement(self: *@This()) !void { try self.removeFocusEngagement(); }
    pub fn applyTemplate(self: *@This()) !bool { var out0: bool = false; try hrCheck(self.lpVtbl.ApplyTemplate(self, &out0)); return out0; }
    pub fn ApplyTemplate(self: *@This()) !bool { return self.applyTemplate(); }
};

pub const IPanel = extern struct {
    pub const IID = GUID{ .Data1 = 0x27a1b418, .Data2 = 0x56f3, .Data3 = 0x525e, .Data4 = .{ 0xb8, 0x83, 0xce, 0xfe, 0xd9, 0x05, 0xee, 0xd3 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Children: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_Background: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Background: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_IsItemsHost: *const fn (*anyopaque, *bool) callconv(.winapi) HRESULT,
        get_ChildrenTransitions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_ChildrenTransitions: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_BackgroundTransition: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_BackgroundTransition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getChildren(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Children(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Children(self: *@This()) !*anyopaque { return self.getChildren(); }
    pub fn getBackground(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Background(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Background(self: *@This()) !*anyopaque { return self.getBackground(); }
    pub fn putBackground(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Background(self, p0)); }
    pub fn put_Background(self: *@This(), p0: ?*anyopaque) !void { try self.putBackground(p0); }
    pub fn getIsItemsHost(self: *@This()) !bool { var out: bool = false; try hrCheck(self.lpVtbl.get_IsItemsHost(self, &out)); return out; }
    pub fn get_IsItemsHost(self: *@This()) !bool { return self.getIsItemsHost(); }
    pub fn getChildrenTransitions(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ChildrenTransitions(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ChildrenTransitions(self: *@This()) !*anyopaque { return self.getChildrenTransitions(); }
    pub fn putChildrenTransitions(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_ChildrenTransitions(self, p0)); }
    pub fn put_ChildrenTransitions(self: *@This(), p0: ?*anyopaque) !void { try self.putChildrenTransitions(p0); }
    pub fn getBackgroundTransition(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BackgroundTransition(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_BackgroundTransition(self: *@This()) !*anyopaque { return self.getBackgroundTransition(); }
    pub fn putBackgroundTransition(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_BackgroundTransition(self, p0)); }
    pub fn put_BackgroundTransition(self: *@This(), p0: ?*anyopaque) !void { try self.putBackgroundTransition(p0); }
};

pub const IGrid = extern struct {
    pub const IID = GUID{ .Data1 = 0xc4496219, .Data2 = 0x9014, .Data3 = 0x58a1, .Data4 = .{ 0xb4, 0xad, 0xc5, 0x04, 0x49, 0x13, 0xa5, 0xbb } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_RowDefinitions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_ColumnDefinitions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_BackgroundSizing: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT,
        put_BackgroundSizing: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        get_BorderBrush: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_BorderBrush: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_BorderThickness: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_BorderThickness: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_CornerRadius: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_CornerRadius: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_Padding: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Padding: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_RowSpacing: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_RowSpacing: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_ColumnSpacing: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_ColumnSpacing: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getRowDefinitions(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_RowDefinitions(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_RowDefinitions(self: *@This()) !*anyopaque { return self.getRowDefinitions(); }
    pub fn getColumnDefinitions(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ColumnDefinitions(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ColumnDefinitions(self: *@This()) !*anyopaque { return self.getColumnDefinitions(); }
    pub fn getBackgroundSizing(self: *@This()) !i32 { var out: i32 = 0; try hrCheck(self.lpVtbl.get_BackgroundSizing(self, &out)); return out; }
    pub fn get_BackgroundSizing(self: *@This()) !i32 { return self.getBackgroundSizing(); }
    pub fn putBackgroundSizing(self: *@This(), p0: i32) !void { try hrCheck(self.lpVtbl.put_BackgroundSizing(self, p0)); }
    pub fn put_BackgroundSizing(self: *@This(), p0: i32) !void { try self.putBackgroundSizing(p0); }
    pub fn getBorderBrush(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BorderBrush(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_BorderBrush(self: *@This()) !*anyopaque { return self.getBorderBrush(); }
    pub fn putBorderBrush(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_BorderBrush(self, p0)); }
    pub fn put_BorderBrush(self: *@This(), p0: ?*anyopaque) !void { try self.putBorderBrush(p0); }
    pub fn getBorderThickness(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BorderThickness(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_BorderThickness(self: *@This()) !*anyopaque { return self.getBorderThickness(); }
    pub fn putBorderThickness(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_BorderThickness(self, p0)); }
    pub fn put_BorderThickness(self: *@This(), p0: ?*anyopaque) !void { try self.putBorderThickness(p0); }
    pub fn getCornerRadius(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_CornerRadius(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_CornerRadius(self: *@This()) !*anyopaque { return self.getCornerRadius(); }
    pub fn putCornerRadius(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_CornerRadius(self, p0)); }
    pub fn put_CornerRadius(self: *@This(), p0: ?*anyopaque) !void { try self.putCornerRadius(p0); }
    pub fn getPadding(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Padding(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Padding(self: *@This()) !*anyopaque { return self.getPadding(); }
    pub fn putPadding(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Padding(self, p0)); }
    pub fn put_Padding(self: *@This(), p0: ?*anyopaque) !void { try self.putPadding(p0); }
    pub fn getRowSpacing(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_RowSpacing(self, &out)); return out; }
    pub fn get_RowSpacing(self: *@This()) !f64 { return self.getRowSpacing(); }
    pub fn putRowSpacing(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_RowSpacing(self, p0)); }
    pub fn put_RowSpacing(self: *@This(), p0: f64) !void { try self.putRowSpacing(p0); }
    pub fn getColumnSpacing(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_ColumnSpacing(self, &out)); return out; }
    pub fn get_ColumnSpacing(self: *@This()) !f64 { return self.getColumnSpacing(); }
    pub fn putColumnSpacing(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_ColumnSpacing(self, p0)); }
    pub fn put_ColumnSpacing(self: *@This(), p0: f64) !void { try self.putColumnSpacing(p0); }
};

pub const IGridStatics = extern struct {
    pub const IID = GUID{ .Data1 = 0xef9cf81d, .Data2 = 0xa431, .Data3 = 0x50f4, .Data4 = .{ 0xab, 0xf5, 0x30, 0x23, 0xfe, 0x44, 0x77, 0x04 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_BackgroundSizingProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_BorderBrushProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_BorderThicknessProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_CornerRadiusProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_PaddingProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_RowSpacingProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_ColumnSpacingProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_RowProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetRow: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetRow: *const fn (*anyopaque, ?*anyopaque, i32) callconv(.winapi) HRESULT,
        get_ColumnProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetColumn: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetColumn: *const fn (*anyopaque, ?*anyopaque, i32) callconv(.winapi) HRESULT,
        get_RowSpanProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetRowSpan: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetRowSpan: *const fn (*anyopaque, ?*anyopaque, i32) callconv(.winapi) HRESULT,
        get_ColumnSpanProperty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetColumnSpan: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        SetColumnSpan: *const fn (*anyopaque, ?*anyopaque, i32) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getBackgroundSizingProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BackgroundSizingProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_BackgroundSizingProperty(self: *@This()) !*anyopaque { return self.getBackgroundSizingProperty(); }
    pub fn getBorderBrushProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BorderBrushProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_BorderBrushProperty(self: *@This()) !*anyopaque { return self.getBorderBrushProperty(); }
    pub fn getBorderThicknessProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_BorderThicknessProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_BorderThicknessProperty(self: *@This()) !*anyopaque { return self.getBorderThicknessProperty(); }
    pub fn getCornerRadiusProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_CornerRadiusProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_CornerRadiusProperty(self: *@This()) !*anyopaque { return self.getCornerRadiusProperty(); }
    pub fn getPaddingProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_PaddingProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_PaddingProperty(self: *@This()) !*anyopaque { return self.getPaddingProperty(); }
    pub fn getRowSpacingProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_RowSpacingProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_RowSpacingProperty(self: *@This()) !*anyopaque { return self.getRowSpacingProperty(); }
    pub fn getColumnSpacingProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ColumnSpacingProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ColumnSpacingProperty(self: *@This()) !*anyopaque { return self.getColumnSpacingProperty(); }
    pub fn getRowProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_RowProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_RowProperty(self: *@This()) !*anyopaque { return self.getRowProperty(); }
    pub fn getRow(self: *@This(), p0: ?*anyopaque) !i32 { var out0: i32 = 0; try hrCheck(self.lpVtbl.GetRow(self, p0, &out0)); return out0; }
    pub fn GetRow(self: *@This(), p0: ?*anyopaque) !i32 { return self.getRow(p0); }
    pub fn setRow(self: *@This(), p0: ?*anyopaque, p1: i32) !void { try hrCheck(self.lpVtbl.SetRow(self, p0, p1)); }
    pub fn SetRow(self: *@This(), p0: ?*anyopaque, p1: i32) !void { try self.setRow(p0, p1); }
    pub fn getColumnProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ColumnProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ColumnProperty(self: *@This()) !*anyopaque { return self.getColumnProperty(); }
    pub fn getColumn(self: *@This(), p0: ?*anyopaque) !i32 { var out0: i32 = 0; try hrCheck(self.lpVtbl.GetColumn(self, p0, &out0)); return out0; }
    pub fn GetColumn(self: *@This(), p0: ?*anyopaque) !i32 { return self.getColumn(p0); }
    pub fn setColumn(self: *@This(), p0: ?*anyopaque, p1: i32) !void { try hrCheck(self.lpVtbl.SetColumn(self, p0, p1)); }
    pub fn SetColumn(self: *@This(), p0: ?*anyopaque, p1: i32) !void { try self.setColumn(p0, p1); }
    pub fn getRowSpanProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_RowSpanProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_RowSpanProperty(self: *@This()) !*anyopaque { return self.getRowSpanProperty(); }
    pub fn getRowSpan(self: *@This(), p0: ?*anyopaque) !i32 { var out0: i32 = 0; try hrCheck(self.lpVtbl.GetRowSpan(self, p0, &out0)); return out0; }
    pub fn GetRowSpan(self: *@This(), p0: ?*anyopaque) !i32 { return self.getRowSpan(p0); }
    pub fn setRowSpan(self: *@This(), p0: ?*anyopaque, p1: i32) !void { try hrCheck(self.lpVtbl.SetRowSpan(self, p0, p1)); }
    pub fn SetRowSpan(self: *@This(), p0: ?*anyopaque, p1: i32) !void { try self.setRowSpan(p0, p1); }
    pub fn getColumnSpanProperty(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ColumnSpanProperty(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ColumnSpanProperty(self: *@This()) !*anyopaque { return self.getColumnSpanProperty(); }
    pub fn getColumnSpan(self: *@This(), p0: ?*anyopaque) !i32 { var out0: i32 = 0; try hrCheck(self.lpVtbl.GetColumnSpan(self, p0, &out0)); return out0; }
    pub fn GetColumnSpan(self: *@This(), p0: ?*anyopaque) !i32 { return self.getColumnSpan(p0); }
    pub fn setColumnSpan(self: *@This(), p0: ?*anyopaque, p1: i32) !void { try hrCheck(self.lpVtbl.SetColumnSpan(self, p0, p1)); }
    pub fn SetColumnSpan(self: *@This(), p0: ?*anyopaque, p1: i32) !void { try self.setColumnSpan(p0, p1); }
};

pub const IRowDefinition = extern struct {
    pub const IID = GUID{ .Data1 = 0xfe870f2f, .Data2 = 0x89ef, .Data3 = 0x5dac, .Data4 = .{ 0x9f, 0x33, 0x96, 0x8d, 0x0d, 0xc5, 0x77, 0xc3 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Height: *const fn (*anyopaque, *GridLength) callconv(.winapi) HRESULT,
        put_Height: *const fn (*anyopaque, GridLength) callconv(.winapi) HRESULT,
        get_MaxHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_MaxHeight: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_MinHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
        put_MinHeight: *const fn (*anyopaque, f64) callconv(.winapi) HRESULT,
        get_ActualHeight: *const fn (*anyopaque, *f64) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getHeight(self: *@This()) !GridLength { var out: GridLength = .{ .Value = 0, .GridUnitType = 0 }; try hrCheck(self.lpVtbl.get_Height(self, &out)); return out; }
    pub fn get_Height(self: *@This()) !GridLength { return self.getHeight(); }
    pub fn putHeight(self: *@This(), p0: GridLength) !void { try hrCheck(self.lpVtbl.put_Height(self, p0)); }
    pub fn put_Height(self: *@This(), p0: GridLength) !void { try self.putHeight(p0); }
    pub fn getMaxHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_MaxHeight(self, &out)); return out; }
    pub fn get_MaxHeight(self: *@This()) !f64 { return self.getMaxHeight(); }
    pub fn putMaxHeight(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_MaxHeight(self, p0)); }
    pub fn put_MaxHeight(self: *@This(), p0: f64) !void { try self.putMaxHeight(p0); }
    pub fn getMinHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_MinHeight(self, &out)); return out; }
    pub fn get_MinHeight(self: *@This()) !f64 { return self.getMinHeight(); }
    pub fn putMinHeight(self: *@This(), p0: f64) !void { try hrCheck(self.lpVtbl.put_MinHeight(self, p0)); }
    pub fn put_MinHeight(self: *@This(), p0: f64) !void { try self.putMinHeight(p0); }
    pub fn getActualHeight(self: *@This()) !f64 { var out: f64 = 0; try hrCheck(self.lpVtbl.get_ActualHeight(self, &out)); return out; }
    pub fn get_ActualHeight(self: *@This()) !f64 { return self.getActualHeight(); }
};

pub const IResourceDictionary = extern struct {
    pub const IID = GUID{ .Data1 = 0x1b690975, .Data2 = 0xa710, .Data3 = 0x5783, .Data4 = .{ 0xa6, 0xe1, 0x15, 0x83, 0x6f, 0x61, 0x86, 0xc2 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        get_Source: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        put_Source: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        get_MergedDictionaries: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        get_ThemeDictionaries: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getSource(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_Source(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_Source(self: *@This()) !*anyopaque { return self.getSource(); }
    pub fn putSource(self: *@This(), p0: ?*anyopaque) !void { try hrCheck(self.lpVtbl.put_Source(self, p0)); }
    pub fn put_Source(self: *@This(), p0: ?*anyopaque) !void { try self.putSource(p0); }
    pub fn getMergedDictionaries(self: *@This()) !*IVector { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_MergedDictionaries(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed)); }
    pub fn get_MergedDictionaries(self: *@This()) !*IVector { return self.getMergedDictionaries(); }
    pub fn getThemeDictionaries(self: *@This()) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.get_ThemeDictionaries(self, &out)); return out orelse error.WinRTFailed; }
    pub fn get_ThemeDictionaries(self: *@This()) !*anyopaque { return self.getThemeDictionaries(); }
};

