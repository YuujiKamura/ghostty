//! UPSTREAM-SHARED-OK: fork-only file in src/renderer/d3d11/ — D3D11 backend
//! Win32 types and functions used by the D3D11 renderer.

const std = @import("std");

pub const BOOL = @import("com.zig").BOOL;
pub const HWND = std.os.windows.HANDLE;
pub const LONG = c_long;

pub const RECT = extern struct {
    left: LONG = 0,
    top: LONG = 0,
    right: LONG = 0,
    bottom: LONG = 0,
};

pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
