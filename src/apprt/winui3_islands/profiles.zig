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
/// Caller owns the returned ArrayList and its backing memory.
pub fn detectProfiles(alloc: Allocator) !std.ArrayList(Profile) {
    var profiles = std.ArrayList(Profile).init(alloc);
    errdefer profiles.deinit();

    for (known_profiles) |kp| {
        if (kp.always or fileExistsAbsolute(kp.path)) {
            try profiles.append(.{
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
