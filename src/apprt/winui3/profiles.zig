/// Shell profile detection for Windows — discovers available terminal profiles
/// (Command Prompt, PowerShell, Git Bash, WSL) for the new-tab dropdown menu.
///
/// This is infrastructure for the Windows Terminal-style SplitButton/MenuFlyout
/// that will be added to TabStripFooter once the drag bar fix lands.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Profile = struct {
    name: []const u8,
    path: []const u8,
    args: ?[]const u8 = null,
};

/// Well-known shell locations on Windows.
const known_profiles = [_]struct {
    name: []const u8,
    path: []const u8,
    args: ?[]const u8,
    always: bool, // true = skip existence check (e.g. cmd.exe)
}{
    .{
        .name = "Command Prompt",
        .path = "C:\\Windows\\System32\\cmd.exe",
        .args = null,
        .always = true,
    },
    .{
        .name = "PowerShell",
        .path = "C:\\Program Files\\PowerShell\\7\\pwsh.exe",
        .args = null,
        .always = false,
    },
    .{
        .name = "Windows PowerShell",
        .path = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
        .args = null,
        .always = false,
    },
    .{
        .name = "Git Bash",
        .path = "C:\\Program Files\\Git\\bin\\bash.exe",
        .args = null,
        .always = false,
    },
    .{
        .name = "WSL",
        .path = "C:\\Windows\\System32\\wsl.exe",
        .args = null,
        .always = false,
    },
};

/// Detect available shell profiles on the system.
/// Caller owns the returned slice and its backing memory.
pub fn detectProfiles(alloc: Allocator) !std.ArrayListUnmanaged(Profile) {
    var profiles: std.ArrayListUnmanaged(Profile) = .{};
    errdefer profiles.deinit(alloc);

    for (known_profiles) |kp| {
        if (kp.always or fileExistsAbsolute(kp.path)) {
            try profiles.append(alloc, .{
                .name = kp.name,
                .path = kp.path,
                .args = kp.args,
            });
        }
    }

    return profiles;
}

/// Check whether a file exists at an absolute path.
/// Uses std.fs.accessAbsolute which works with Windows absolute paths.
fn fileExistsAbsolute(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

// --- Tests ---

test "detectProfiles returns at least cmd.exe" {
    const alloc = std.testing.allocator;
    var detected = try detectProfiles(alloc);
    defer detected.deinit(alloc);

    // cmd.exe is always=true, so at least 1 profile must exist.
    try std.testing.expect(detected.items.len >= 1);

    // First entry must be Command Prompt (always=true, listed first).
    try std.testing.expectEqualStrings("Command Prompt", detected.items[0].name);
    try std.testing.expectEqualStrings("C:\\Windows\\System32\\cmd.exe", detected.items[0].path);
    try std.testing.expect(detected.items[0].args == null);
}

test "detectProfiles names are unique" {
    const alloc = std.testing.allocator;
    var detected = try detectProfiles(alloc);
    defer detected.deinit(alloc);

    // No duplicate names.
    for (detected.items, 0..) |a, i| {
        for (detected.items[i + 1 ..]) |b| {
            if (std.mem.eql(u8, a.name, b.name)) {
                std.debug.print("duplicate profile name: {s}\n", .{a.name});
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "detectProfiles paths are absolute" {
    const alloc = std.testing.allocator;
    var detected = try detectProfiles(alloc);
    defer detected.deinit(alloc);

    for (detected.items) |p| {
        // Windows absolute paths start with a drive letter (e.g. "C:\").
        try std.testing.expect(p.path.len >= 3);
        try std.testing.expect(p.path[1] == ':');
        try std.testing.expect(p.path[2] == '\\');
    }
}

test "Profile struct layout" {
    const p = Profile{ .name = "test", .path = "C:\\test.exe", .args = "--flag" };
    try std.testing.expectEqualStrings("test", p.name);
    try std.testing.expectEqualStrings("C:\\test.exe", p.path);
    try std.testing.expectEqualStrings("--flag", p.args.?);

    const p2 = Profile{ .name = "no-args", .path = "C:\\x.exe" };
    try std.testing.expect(p2.args == null);
}

test "known_profiles has expected entries" {
    // Verify the static list has the shells we expect.
    try std.testing.expect(known_profiles.len == 5);

    // cmd.exe must be always=true.
    try std.testing.expect(known_profiles[0].always == true);
    try std.testing.expectEqualStrings("Command Prompt", known_profiles[0].name);

    // All others must be always=false.
    for (known_profiles[1..]) |kp| {
        try std.testing.expect(kp.always == false);
    }
}
