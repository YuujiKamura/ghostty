const std = @import("std");

/// Windows settings keys with stable type mapping.
pub const Key = enum {
    @"gtk-enable-primary-paste",
    @"gtk-xft-dpi",
    @"gtk-font-name",

    fn Type(comptime self: Key) type {
        return switch (self) {
            .@"gtk-enable-primary-paste" => bool,
            .@"gtk-xft-dpi" => i32,
            .@"gtk-font-name" => []const u8,
        };
    }

    fn GValueType(comptime self: Key) type {
        return switch (self.Type()) {
            bool => i32,
            i32 => i32,
            []const u8 => ?[*:0]const u8,
            else => @compileError("unsupported settings type"),
        };
    }

    fn requiresAllocation(comptime self: Key) bool {
        return switch (self.Type()) {
            bool, i32 => false,
            else => true,
        };
    }
};

test "Key.Type returns correct types" {
    try std.testing.expectEqual(bool, Key.@"gtk-enable-primary-paste".Type());
    try std.testing.expectEqual(i32, Key.@"gtk-xft-dpi".Type());
    try std.testing.expectEqual([]const u8, Key.@"gtk-font-name".Type());
}

test "Key.requiresAllocation identifies allocating types" {
    try std.testing.expectEqual(false, Key.@"gtk-enable-primary-paste".requiresAllocation());
    try std.testing.expectEqual(false, Key.@"gtk-xft-dpi".requiresAllocation());
    try std.testing.expectEqual(true, Key.@"gtk-font-name".requiresAllocation());
}

test "Key.GValueType returns correct GObject types" {
    try std.testing.expectEqual(i32, Key.@"gtk-enable-primary-paste".GValueType());
    try std.testing.expectEqual(i32, Key.@"gtk-xft-dpi".GValueType());
    try std.testing.expectEqual(?[*:0]const u8, Key.@"gtk-font-name".GValueType());
}

test "@tagName returns correct GTK property names" {
    try std.testing.expectEqualStrings("gtk-enable-primary-paste", @tagName(Key.@"gtk-enable-primary-paste"));
    try std.testing.expectEqualStrings("gtk-xft-dpi", @tagName(Key.@"gtk-xft-dpi"));
    try std.testing.expectEqualStrings("gtk-font-name", @tagName(Key.@"gtk-font-name"));
}
