const std = @import("std");

pub fn computeGotoIndex(current: usize, tab_count: usize, mode: anytype) usize {
    if (tab_count == 0) return 0;
    return switch (mode) {
        .previous => if (current > 0) current - 1 else tab_count - 1,
        .next => if (current + 1 < tab_count) current + 1 else 0,
        .last => tab_count - 1,
        else => @min(@as(usize, @intCast(@intFromEnum(mode))), tab_count - 1),
    };
}

pub fn clampActiveIndex(active_index: usize, tab_count: usize) ?usize {
    if (tab_count == 0) return null;
    if (active_index >= tab_count) return tab_count - 1;
    return active_index;
}

pub fn isValid(active_index: usize, tab_count: usize) bool {
    return active_index < tab_count;
}

test "computeGotoIndex wraps and clamps" {
    try std.testing.expectEqual(@as(usize, 2), computeGotoIndex(0, 3, .previous));
    try std.testing.expectEqual(@as(usize, 0), computeGotoIndex(2, 3, .next));
    try std.testing.expectEqual(@as(usize, 2), computeGotoIndex(0, 3, .last));
}

test "clampActiveIndex" {
    try std.testing.expectEqual(@as(?usize, null), clampActiveIndex(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), clampActiveIndex(5, 2));
    try std.testing.expectEqual(@as(?usize, 1), clampActiveIndex(1, 2));
}
