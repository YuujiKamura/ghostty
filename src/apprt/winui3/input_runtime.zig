const std = @import("std");
const os = @import("os.zig");
const input_overlay = @import("input_overlay.zig");

const log = std.log.scoped(.winui3);

pub fn setupNativeInputWindows(self: anytype, subclass_proc: os.SUBCLASSPROC) void {
    // Step 9: Find the WinUI3 child HWND...
    const child = os.GetWindow(self.hwnd.?, os.GW_CHILD);
    if (child) |child_hwnd| {
        self.child_hwnd = child_hwnd;
        log.info("initXaml step 9: found WinUI3 child HWND=0x{x}", .{@intFromPtr(child_hwnd)});
        // ALWAYS subclass the WinUI child HWND to redirect focus.
        _ = os.SetWindowSubclass(child_hwnd, subclass_proc, 2, @intFromPtr(self));
    }

    // Create our input overlay HWND.
    self.input_hwnd = input_overlay.createInputWindow(self.hwnd.?, @intFromPtr(self));
    if (self.input_hwnd) |input_hwnd| {
        // Enable IME on our input HWND.
        _ = os.ImmAssociateContextEx(input_hwnd, null, os.IACE_DEFAULT);
        // Give it initial focus.
        _ = os.SetFocus(input_hwnd);
        log.info("initXaml step 9 OK: input HWND=0x{x} created + IME enabled", .{@intFromPtr(input_hwnd)});
    }
}

pub fn focusInputOverlay(self: anytype) void {
    if (self.input_hwnd) |h| _ = os.SetFocus(h);
}
