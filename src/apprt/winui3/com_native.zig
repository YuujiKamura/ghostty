//! Hand-written COM interface definitions that cannot be auto-generated.
//! These include Windows.Foundation types (not in WinUI3 winmd),
//! native COM interfaces, and ghostty-specific definitions.
const std = @import("std");
const GUID = std.os.windows.GUID;
const HRESULT = std.os.windows.HRESULT;
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
    pub const IID = GUID{ .Data1 = 0xb32bdca4, .Data2 = 0x5e52, .Data3 = 0x5b27, .Data4 = .{ 0xbc, 0x5d, 0xd6, 0x6a, 0x1a, 0x26, 0x8c, 0x2a } };
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
            if (@intFromPtr(item) == @intFromPtr(target)) return i;
            // Release the queried reference.
            const unk: *IUnknown = @ptrCast(@alignCast(item));
            _ = unk.lpVtbl.Release(@ptrCast(unk));
        }
        return null;
    }
};

pub const IPropertyValue = extern struct {
    pub const IID = GUID{ .Data1 = 0x4bd682dd, .Data2 = 0x7554, .Data3 = 0x40e9, .Data4 = .{ 0x9a, 0x9b, 0x82, 0x65, 0x4e, 0xde, 0x7e, 0x62 } };
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
    pub const IID = GUID{ .Data1 = 0x629bdbc8, .Data2 = 0xd932, .Data3 = 0x4ff4, .Data4 = .{ 0x96, 0xb9, 0x8d, 0x96, 0xc5, 0xc1, 0xe8, 0x58 } };
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
    pub const IID = GUID{ .Data1 = 0x63aad0b8, .Data2 = 0x7c24, .Data3 = 0x40ff, .Data4 = .{ 0x85, 0xa8, 0x64, 0x0d, 0x94, 0x4c, 0xc3, 0x25 } };
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
    pub const IID = GUID{ .Data1 = 0xeecdbf0e, .Data2 = 0xbae9, .Data3 = 0x4cb6, .Data4 = .{ 0xa6, 0x8e, 0x95, 0x98, 0xe1, 0xcb, 0x57, 0xbb } };
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
