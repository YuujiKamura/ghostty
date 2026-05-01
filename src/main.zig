const std = @import("std");
const build_config = @import("build_config.zig");

/// See build_config.ExeEntrypoint for why we do this.
const entrypoint = switch (build_config.exe_entrypoint) {
    .ghostty => @import("main_ghostty.zig"),
    .helpgen => @import("helpgen.zig"),
    .mdgen_ghostty_1 => @import("build/mdgen/main_ghostty_1.zig"),
    .mdgen_ghostty_5 => @import("build/mdgen/main_ghostty_5.zig"),
    .webgen_config => @import("build/webgen/main_config.zig"),
    .webgen_actions => @import("build/webgen/main_actions.zig"),
    .webgen_commands => @import("build/webgen/main_commands.zig"),
};

/// The main entrypoint for the program.
pub const main = entrypoint.main;

// UPSTREAM-SHARED-OK: comment-only documentation of Windows wWinMain symbol generation (no behavior change); entrypoint dispatch must live at root.
/// Zig 0.15.2 + link_libc + subsystem=.Windows: the MSVC linker needs a
/// WinMain-family symbol. start.zig detects wWinMain in root and generates
/// wWinMainCRTStartup. We delegate to main() which delegates to the entrypoint.
/// Standard options such as logger overrides.
pub const std_options: std.Options = if (@hasDecl(entrypoint, "std_options"))
    entrypoint.std_options
else
    .{};

test {
    _ = entrypoint;
}
