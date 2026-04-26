//! WinUI 3 Native Interop — true native-only COM interfaces.
//! Only types that cannot be auto-generated from WinMD belong here.
//! Consumer aliases (IWindow2, ITabView2, IFrameworkElement2, IPanel2)
//! were removed in #59 — use generated IWindow/ITabView/etc. instead.

const winrt = @import("winrt.zig");
const com = @import("com.zig");
const os = @import("os.zig");
const GUID = winrt.GUID;
const HRESULT = winrt.HRESULT;
const WinRTError = winrt.WinRTError;
const hrCheck = winrt.hrCheck;

pub const VtblPlaceholder = ?*const anyopaque;

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
    pub fn queryInterface(self: *@This(), comptime T: type) WinRTError!*T {
        return com.comQueryInterface(self, T);
    }
    pub fn release(self: *@This()) void {
        com.comRelease(self);
    }
    pub fn setSwapChain(self: *ISwapChainPanelNative2, sc: ?*anyopaque) WinRTError!void {
        try hrCheck(self.lpVtbl.SetSwapChain(self, sc));
    }
    pub fn setSwapChainHandle(self: *ISwapChainPanelNative2, h: os.HANDLE) WinRTError!void {
        try hrCheck(self.lpVtbl.SetSwapChainHandle(self, h));
    }
};
