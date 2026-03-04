const std = @import("std");

const sdk_version: std.SemanticVersion = .{
    .major = 1,
    .minor = 7,
    .patch = 3,
};

pub fn getRuntimeVersion() std.SemanticVersion {
    // WinUI SDK version gate used for feature checks.
    return sdk_version;
}

pub inline fn atLeast(
    comptime major: u16,
    comptime minor: u16,
    comptime micro: u16,
) bool {
    if (comptime sdk_version.order(.{
        .major = major,
        .minor = minor,
        .patch = micro,
    }) == .lt) return false;

    if (@inComptime()) return true;
    return runtimeAtLeast(major, minor, micro);
}

pub inline fn runtimeAtLeast(
    comptime major: u16,
    comptime minor: u16,
    comptime micro: u16,
) bool {
    const runtime_version = getRuntimeVersion();
    return runtime_version.order(.{
        .major = major,
        .minor = minor,
        .patch = micro,
    }) != .lt;
}

pub inline fn runtimeUntil(
    comptime major: u16,
    comptime minor: u16,
    comptime micro: u16,
) bool {
    const runtime_version = getRuntimeVersion();
    return runtime_version.order(.{
        .major = major,
        .minor = minor,
        .patch = micro,
    }) == .lt;
}

pub inline fn versionAtLeast(
    comptime major: u16,
    comptime minor: u16,
    comptime micro: u16,
) bool {
    return atLeast(major, minor, micro);
}

test "atLeast" {
    const testing = std.testing;

    const funs = &.{ atLeast, runtimeAtLeast };
    inline for (funs) |fun| {
        try testing.expect(fun(sdk_version.major, sdk_version.minor, sdk_version.patch));

        try testing.expect(!fun(sdk_version.major, sdk_version.minor, sdk_version.patch + 1));
        try testing.expect(!fun(sdk_version.major, sdk_version.minor + 1, sdk_version.patch));
        try testing.expect(!fun(sdk_version.major + 1, sdk_version.minor, sdk_version.patch));

        try testing.expect(fun(sdk_version.major - 1, sdk_version.minor, sdk_version.patch));
        try testing.expect(fun(sdk_version.major - 1, sdk_version.minor + 1, sdk_version.patch));
        try testing.expect(fun(sdk_version.major - 1, sdk_version.minor, sdk_version.patch + 1));

        try testing.expect(fun(sdk_version.major, sdk_version.minor - 1, sdk_version.patch + 1));
    }
}

test "runtimeUntil" {
    const testing = std.testing;

    const funs = &.{runtimeUntil};
    inline for (funs) |fun| {
        try testing.expect(!fun(sdk_version.major, sdk_version.minor, sdk_version.patch));

        try testing.expect(fun(sdk_version.major, sdk_version.minor, sdk_version.patch + 1));
        try testing.expect(fun(sdk_version.major, sdk_version.minor + 1, sdk_version.patch));
        try testing.expect(fun(sdk_version.major + 1, sdk_version.minor, sdk_version.patch));

        try testing.expect(!fun(sdk_version.major - 1, sdk_version.minor, sdk_version.patch));
        try testing.expect(!fun(sdk_version.major - 1, sdk_version.minor + 1, sdk_version.patch));
        try testing.expect(!fun(sdk_version.major - 1, sdk_version.minor, sdk_version.patch + 1));

        try testing.expect(!fun(sdk_version.major, sdk_version.minor - 1, sdk_version.patch + 1));
    }
}

test "versionAtLeast" {
    const testing = std.testing;
    try testing.expect(versionAtLeast(sdk_version.major, sdk_version.minor, sdk_version.patch));
    try testing.expect(!versionAtLeast(sdk_version.major + 1, sdk_version.minor, sdk_version.patch));
}
