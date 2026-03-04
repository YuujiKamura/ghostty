const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Resolved = struct {
    file: ?[]const u8 = null,
    path: ?[]const u8 = null,

    pub fn deinit(self: *Resolved, alloc: Allocator) void {
        if (self.file) |v| alloc.free(v);
        if (self.path) |v| alloc.free(v);
        self.* = .{};
    }
};

pub fn resolve(
    alloc: Allocator,
    resources_dir: ?[]const u8,
) Allocator.Error!Resolved {
    const dir = resources_dir orelse return .{};
    if (dir.len == 0) return .{};

    const trimmed = std.mem.trimRight(u8, dir, "/\\");
    if (trimmed.len == 0) return .{};

    const path = try std.fmt.allocPrint(alloc, "{s}/fontconfig", .{trimmed});
    errdefer alloc.free(path);

    const file = try std.fmt.allocPrint(alloc, "{s}/fonts.conf", .{path});

    return .{
        .file = file,
        .path = path,
    };
}

test "resolve builds file and path from resources dir" {
    const testing = std.testing;

    var result = try resolve(testing.allocator, "C:/x/share/ghostty");
    defer result.deinit(testing.allocator);

    try testing.expectEqualStrings("C:/x/share/ghostty/fontconfig/fonts.conf", result.file.?);
    try testing.expectEqualStrings("C:/x/share/ghostty/fontconfig", result.path.?);
}

test "resolve returns nulls for null resources dir" {
    const testing = std.testing;

    var result = try resolve(testing.allocator, null);
    defer result.deinit(testing.allocator);

    try testing.expect(result.file == null);
    try testing.expect(result.path == null);
}

test "resolve returns nulls for empty resources dir" {
    const testing = std.testing;

    var result = try resolve(testing.allocator, "");
    defer result.deinit(testing.allocator);

    try testing.expect(result.file == null);
    try testing.expect(result.path == null);
}
