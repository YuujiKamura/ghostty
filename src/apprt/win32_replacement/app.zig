const std = @import("std");
const window = @import("window.zig");
const surface = @import("surface.zig");

pub fn run() !void {
    _ = window.bootstrapTag();
    _ = surface.bootstrapTag();
    std.debug.print("win32 replacement app-layer bootstrap\n", .{});
}
