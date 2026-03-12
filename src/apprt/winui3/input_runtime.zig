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

    // Create our input overlay HWND — the sole keyboard focus target.
    self.input_hwnd = input_overlay.createInputWindow(self.hwnd.?, @intFromPtr(self));
    if (self.input_hwnd) |input_hwnd| {
        // Enable IME on our input HWND.
        _ = os.ImmAssociateContextEx(input_hwnd, null, os.IACE_DEFAULT);
        // input_hwnd is always the keyboard target.
        self.keyboard_focus_target = .input_overlay;
        // Set initial focus to input_hwnd.
        _ = os.SetFocus(input_hwnd);
        App.fileLog("step 9 OK: input HWND=0x{x} created, IME enabled, focus set", .{@intFromPtr(input_hwnd)});
    } else {
        App.fileLog("step 9: WARNING input_hwnd creation FAILED", .{});
    }
}

/// Ensure keyboard focus is on input_hwnd.
/// Called on WM_SETFOCUS, pointer clicks, and any other focus-restoring event.
pub fn ensureInputFocus(self: anytype) void {
    if (self.input_hwnd) |h| {
        _ = os.SetFocus(h);
        // Re-establish IME context on focus restore
        _ = os.ImmAssociateContextEx(h, null, os.IACE_DEFAULT);
        const himc = os.ImmGetContext(h);
        if (himc != null) {
            _ = os.ImmSetOpenStatus(himc.?, 1);
            _ = os.ImmReleaseContext(h, himc.?);
        }
    }
}

/// Legacy API compatibility — both point to ensureInputFocus.
pub fn focusInputOverlay(self: anytype) void {
    self.keyboard_focus_target = .input_overlay;
    ensureInputFocus(self);
}

pub fn focusKeyboardTarget(self: anytype) void {
    // keyboard_focus_target stays .input_overlay — input_hwnd handles everything.
    self.keyboard_focus_target = .input_overlay;
    ensureInputFocus(self);
}

pub fn restoreDesiredKeyboardTarget(self: anytype) void {
    // Always restore to input_hwnd.
    ensureInputFocus(self);
}
