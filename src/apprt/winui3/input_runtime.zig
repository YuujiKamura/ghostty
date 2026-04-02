const std = @import("std");
const os = @import("os.zig");
const input_overlay = @import("input_overlay.zig");

const log = std.log.scoped(.winui3);

pub fn setupNativeInputWindows(self: anytype, subclass_proc: os.SUBCLASSPROC) void {
    // Find the WinUI3 child HWND and subclass it for non-keyboard messages
    // (WM_SIZE, WM_CLOSE, WM_NCHITTEST, etc.).
    const child = os.GetWindow(self.hwnd.?, os.GW_CHILD);
    if (child) |child_hwnd| {
        self.child_hwnd = child_hwnd;
        log.info("step 9: found WinUI3 child HWND=0x{x}", .{@intFromPtr(child_hwnd)});
        _ = os.SetWindowSubclass(child_hwnd, subclass_proc, 2, @intFromPtr(self));
    } else {
        log.warn("step 9: WARNING no child HWND found", .{});
    }

    // Create our input overlay HWND as a fallback/native companion window.
    self.input_hwnd = input_overlay.createInputWindow(self.hwnd.?, @intFromPtr(self));
    if (self.input_hwnd) |input_hwnd| {
        // Keep IME enabled on the fallback HWND for legacy/native paths, but do
        // not make it the default text owner.
        _ = os.ImmAssociateContextEx(input_hwnd, null, os.IACE_DEFAULT);
        self.keyboard_focus_target = .ime_text_box;
        log.info("step 9 OK: input HWND=0x{x} created (fallback only); text owner=ime_text_box", .{@intFromPtr(input_hwnd)});
    } else {
        log.warn("step 9: WARNING input_hwnd creation FAILED", .{});
    }
}

/// Focus the appropriate target based on keyboard_focus_target setting.
/// Returns true if focus was successfully set.
fn focusCurrentTarget(self: anytype) bool {
    return switch (self.keyboard_focus_target) {
        .xaml_surface => blk: {
            if (self.activeSurface()) |surface| {
                surface.focusSwapChainPanel();
                break :blk true;
            }
            break :blk false;
        },
        .ime_text_box => blk: {
            if (self.activeSurface()) |surface| {
                break :blk surface.focusImeTextBox();
            }
            break :blk false;
        },
    };
}

/// Restore focus to the appropriate keyboard target.
/// Called on WM_SETFOCUS, pointer clicks, and any other focus-restoring event.
pub fn ensureInputFocus(self: anytype) void {
    _ = focusCurrentTarget(self);
}

pub fn focusInputOverlay(self: anytype) void {
    _ = focusCurrentTarget(self);
}

pub fn focusKeyboardTarget(self: anytype) void {
    _ = focusCurrentTarget(self);
}

pub fn restoreDesiredKeyboardTarget(self: anytype) void {
    _ = focusCurrentTarget(self);
}
