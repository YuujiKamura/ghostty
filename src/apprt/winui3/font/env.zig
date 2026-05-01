//! WinUI3-local fontconfig env helper. Builds FONTCONFIG_FILE and
//! FONTCONFIG_PATH values from the resources dir so the bundled fontconfig
//! data ships under our app share dir without sprawling into upstream-shared
//! `src/os/`. Relocated from `src/os/fontconfig_env.zig` per #254 / the
//! 2026-04-27 fork-isolation audit (item 7).

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

pub const EnvVars = struct {
    file_key: ?[]const u8 = null,
    file_value: ?[]const u8 = null,
    path_key: ?[]const u8 = null,
    path_value: ?[]const u8 = null,

    pub fn deinit(self: *EnvVars, alloc: Allocator) void {
        if (self.file_value) |v| alloc.free(v);
        if (self.path_value) |v| alloc.free(v);
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

pub fn buildEnvVars(
    alloc: Allocator,
    resources_dir: ?[]const u8,
) Allocator.Error!EnvVars {
    var resolved = try resolve(alloc, resources_dir);
    errdefer resolved.deinit(alloc);

    const file_value = resolved.file orelse return .{};
    const path_value = resolved.path orelse return .{};

    resolved.file = null;
    resolved.path = null;

    return .{
        .file_key = "FONTCONFIG_FILE",
        .file_value = file_value,
        .path_key = "FONTCONFIG_PATH",
        .path_value = path_value,
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

test "env vars are built from resources dir" {
    const testing = std.testing;

    var env = try buildEnvVars(testing.allocator, "C:/x/share/ghostty");
    defer env.deinit(testing.allocator);

    try testing.expectEqualStrings("FONTCONFIG_FILE", env.file_key.?);
    try testing.expectEqualStrings("C:/x/share/ghostty/fontconfig/fonts.conf", env.file_value.?);
    try testing.expectEqualStrings("FONTCONFIG_PATH", env.path_key.?);
    try testing.expectEqualStrings("C:/x/share/ghostty/fontconfig", env.path_value.?);
}
