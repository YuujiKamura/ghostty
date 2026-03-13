const std = @import("std");
const os = @import("os.zig");
const input_overlay = @import("input_overlay.zig");

const log = std.log.scoped(.winui3);

pub fn setupNativeInputWindows(self: anytype, subclass_proc: os.SUBCLASSPROC) void {
    const App = @import("App.zig");
    // Find the WinUI3 child HWND and subclass it for non-keyboard messages
    // (WM_SIZE, WM_CLOSE, WM_NCHITTEST, etc.).
    const child = os.GetWindow(self.hwnd.?, os.GW_CHILD);
    if (child) |child_hwnd| {
        self.child_hwnd = child_hwnd;
        App.fileLog("step 9: found WinUI3 child HWND=0x{x}", .{@intFromPtr(child_hwnd)});
        _ = os.SetWindowSubclass(child_hwnd, subclass_proc, 2, @intFromPtr(self));
    } else {
        App.fileLog("step 9: WARNING no child HWND found", .{});
    }

    // Create our input overlay HWND as a fallback/native companion window.
    self.input_hwnd = input_overlay.createInputWindow(self.hwnd.?, @intFromPtr(self));
    if (self.input_hwnd) |input_hwnd| {
        // Keep IME enabled on the fallback HWND for legacy/native paths, but do
        // not make it the default text owner.
        _ = os.ImmAssociateContextEx(input_hwnd, null, os.IACE_DEFAULT);
        self.keyboard_focus_target = .ime_text_box;
        App.fileLog("step 9 OK: input HWND=0x{x} created (fallback only); text owner=ime_text_box", .{@intFromPtr(input_hwnd)});
    } else {
        App.fileLog("step 9: WARNING input_hwnd creation FAILED", .{});
    }
}

fn focusImeTextOwner(self: anytype) bool {
    self.keyboard_focus_target = .ime_text_box;
    if (self.activeSurface()) |surface| {
        return surface.focusImeTextBox();
    }
    return false;
}

/// Restore focus to the WinUI3 text owner.
/// Called on WM_SETFOCUS, pointer clicks, and any other focus-restoring event.
pub fn ensureInputFocus(self: anytype) void {
    _ = focusImeTextOwner(self);
}

pub fn focusInputOverlay(self: anytype) void {
    _ = focusImeTextOwner(self);
}

pub fn focusKeyboardTarget(self: anytype) void {
    _ = focusImeTextOwner(self);
}

pub fn restoreDesiredKeyboardTarget(self: anytype) void {
    _ = focusImeTextOwner(self);
}
