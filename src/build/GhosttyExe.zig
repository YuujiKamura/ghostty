const Ghostty = @This();

const std = @import("std");
const Config = @import("Config.zig");
const SharedDeps = @import("SharedDeps.zig");

/// The primary Ghostty executable.
exe: *std.Build.Step.Compile,

/// The install step for the executable.
install_step: *std.Build.Step.InstallArtifact,

pub fn init(b: *std.Build, cfg: *const Config, deps: *const SharedDeps) !Ghostty {
    const exe: *std.Build.Step.Compile = b.addExecutable(.{
        .name = "ghostty",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = cfg.target,
            .optimize = cfg.optimize,
            .strip = cfg.strip,
            .omit_frame_pointer = cfg.strip,
            .unwind_tables = if (cfg.strip) .none else .sync,
        }),
        // Crashes on x86_64 self-hosted on 0.15.1
        .use_llvm = true,
    });
    const install_step = b.addInstallArtifact(exe, .{});

    // Set PIE if requested
    if (cfg.pie) exe.pie = true;

    // Add the shared dependencies. When building only lib-vt we skip
    // heavy deps so cross-compilation doesn't pull in GTK, etc.
    if (!cfg.emit_lib_vt) _ = try deps.add(exe);

    // Check for possible issues
    try checkNixShell(exe, cfg);

    // Patch our rpath if that option is specified.
    if (cfg.patch_rpath) |rpath| {
        if (rpath.len > 0) {
            const run = std.Build.Step.Run.create(b, "patchelf rpath");
            run.addArgs(&.{ "patchelf", "--set-rpath", rpath });
            run.addArtifactArg(exe);
            install_step.step.dependOn(&run.step);
        }
    }

    // OS-specific
    // UPSTREAM-SHARED-OK: .windows branch wires win32_manifest + .rc bundle at the build-step level, can't be moved to apprt/winui3.
    switch (cfg.target.result.os.tag) {
        .windows => {
            // Mark as a GUI application (PE subsystem = IMAGE_SUBSYSTEM_WINDOWS_GUI).
            //
            // Why this matters: with the previous CONSOLE subsystem setting,
            // Windows auto-allocated a conhost terminal on launch and the
            // shell could not detect "input idle" via WaitForInputIdle, so
            // the IDC_APPSTARTING cursor lingered for ~2s after launch even
            // though the in-process work finished by ~340ms. See
            // tests/winui3/test-10-cold-start-perf.ps1 for the measurement.
            //
            // Verified empirically (2026-05-06) by post-link byte-flipping
            // the PE subsystem field from CONSOLE → GUI: WaitForInputIdle
            // returns at ~276ms, the conhost no longer auto-allocates, and
            // the binary launches and runs normally. The historical TODO
            // about Zig 0.15 start.zig integration appears to no longer
            // apply with the current Zig — the loader still calls Zig's
            // standard entry point, the subsystem field only affects OS
            // policy (console allocation, WaitForInputIdle eligibility,
            // shell cursor handling).
            //
            // REVERT-PATH: this switch coordinates with two other call sites
            // — to revert to CONSOLE subsystem cleanly, all three must change
            // together, otherwise the binary will fail to link or leak a
            // conhost on launch:
            //   1. (this file) drop `exe.subsystem = .Windows` AND drop the
            //      `exe.entry = .{ .symbol_name = "mainCRTStartup" }` pin
            //      below — without the subsystem switch, the linker will
            //      still try to find WinMain unless the entry pin is also
            //      removed.
            //   2. src/apprt/winui3/App.zig — remove the `os.FreeConsole()`
            //      call early in App.init (~line 553). Under CONSOLE
            //      subsystem, the auto-allocated conhost is the process's
            //      controlling terminal; tearing it down at startup is only
            //      correct because we also set subsystem = GUI here.
            exe.subsystem = .Windows;
            // Pin the linker entry to the standard CRT entry rather than
            // letting the linker fall through to WinMain (which Zig does
            // not generate). The subsystem flag controls OS policy
            // (console allocation, WaitForInputIdle, shell cursor); the
            // entry point is independent and we keep Zig's std startup
            // path intact. NOTE: also remove this `exe.entry` pin if you
            // are reverting `exe.subsystem` above (see REVERT-PATH note).
            exe.entry = .{ .symbol_name = "mainCRTStartup" };
            exe.win32_manifest = b.path("dist/windows/ghostty.manifest");
            exe.addWin32ResourceFile(.{
                .file = b.path("dist/windows/ghostty.rc"),
            });
        },

        else => {},
    }

    return .{
        .exe = exe,
        .install_step = install_step,
    };
}

/// Add the ghostty exe to the install target.
pub fn install(self: *const Ghostty) void {
    const b = self.install_step.step.owner;
    b.getInstallStep().dependOn(&self.install_step.step);
}

/// If we're in NixOS but not in the shell environment then we issue
/// a warning because the rpath may not be setup properly. This doesn't modify
/// our build in any way but addresses a common build-from-source issue
/// for a subset of users.
fn checkNixShell(exe: *std.Build.Step.Compile, cfg: *const Config) !void {
    // Non-Linux doesn't have rpath issues.
    if (cfg.target.result.os.tag != .linux) return;

    // When cross-compiling, we don't need to worry about matching our
    // Nix shell rpath since the resulting binary will be run on a
    // separate system.
    if (!cfg.target.query.isNativeCpu()) return;
    if (!cfg.target.query.isNativeOs()) return;

    // Verify we're in NixOS
    std.fs.accessAbsolute("/etc/NIXOS", .{}) catch return;

    // If we're in a nix shell, not a problem
    if (cfg.env.get("IN_NIX_SHELL") != null) return;

    try exe.step.addError(
        "\x1b[" ++ color_map.get("yellow").? ++
            "\x1b[" ++ color_map.get("d").? ++
            \\Detected building on and for NixOS outside of the Nix shell environment.
            \\
            \\The resulting ghostty binary will likely fail on launch because it is
            \\unable to dynamically load the windowing libs (X11, Wayland, etc.).
            \\We highly recommend running only within the Nix build environment
            \\and the resulting binary will be portable across your system.
            \\
            \\To run in the Nix build environment, use the following command.
            \\Append any additional options like (`-Doptimize` flags). The resulting
            \\binary will be in zig-out as usual.
            \\
            \\  nix develop -c zig build
            \\
        ++
            "\x1b[0m",
        .{},
    );
}

/// ANSI escape codes for colored log output
const color_map = std.StaticStringMap([]const u8).initComptime(.{
    &.{ "black", "30m" },
    &.{ "blue", "34m" },
    &.{ "b", "1m" },
    &.{ "d", "2m" },
    &.{ "cyan", "36m" },
    &.{ "green", "32m" },
    &.{ "magenta", "35m" },
    &.{ "red", "31m" },
    &.{ "white", "37m" },
    &.{ "yellow", "33m" },
});
