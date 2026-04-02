const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const buildpkg = @import("src/build/main.zig");

const appVersion = @import("build.zig.zon").version;
const minimumZigVersion = @import("build.zig.zon").minimum_zig_version;
const default_winappsdk_version = "1.4.230822000";

comptime {
    buildpkg.requireZig(minimumZigVersion);
}

pub fn build(b: *std.Build) !void {
    // This defines all the available build options (e.g. `-D`). If you
    // want to know what options are available, you can run `--help` or
    // you can read `src/build/Config.zig`.

    const config = try buildpkg.Config.init(b, appVersion);
    const test_filters = b.option(
        [][]const u8,
        "test-filter",
        "Filter for test. Only applies to Zig tests.",
    ) orelse &[0][]const u8{};
    const winappsdk_version = b.option(
        []const u8,
        "winappsdk-version",
        "Version of Microsoft.WindowsAppSDK package used to locate Bootstrap DLL.",
    ) orelse default_winappsdk_version;

    // Ghostty dependencies used by many artifacts.
    const deps = try buildpkg.SharedDeps.init(b, &config);

    // The modules exported for Zig consumers of libghostty. If you're
    // writing a Zig program that uses libghostty, read this file.
    const mod = try buildpkg.GhosttyZig.init(
        b,
        &config,
        &deps,
    );

    // All our steps which we'll hook up later. The steps are shown
    // up here just so that they are more self-documenting.
    const libvt_step = b.step("lib-vt", "Build libghostty-vt");
    const run_step = b.step("run", "Run the app");
    const run_valgrind_step = b.step(
        "run-valgrind",
        "Run the app under valgrind",
    );
    const test_step = b.step("test", "Run tests");
    const test_lib_vt_step = b.step(
        "test-lib-vt",
        "Run libghostty-vt tests",
    );
    const test_valgrind_step = b.step(
        "test-valgrind",
        "Run tests under valgrind",
    );
    const translations_step = b.step(
        "update-translations",
        "Update translation files",
    );

    // Ghostty resources like terminfo, shell integration, themes, etc.
    const resources = try buildpkg.GhosttyResources.init(b, &config, &deps);
    const i18n = if (config.i18n) try buildpkg.GhosttyI18n.init(b, &config) else null;

    // Ghostty executable, the actual runnable Ghostty program.
    const exe = try buildpkg.GhosttyExe.init(b, &config, &deps);

    // Zig-native control plane (WinUI3 only)
    if (config.target.result.os.tag == .windows and config.app_runtime == .winui3) {
        const zcp_dep = b.dependency("zig_control_plane", .{
            .target = config.target,
            .optimize = config.optimize,
        });
        exe.exe.root_module.addImport("zig-control-plane", zcp_dep.module("zig-control-plane"));
    }

    // Ghostty docs
    const docs = try buildpkg.GhosttyDocs.init(b, &deps);
    if (config.emit_docs) {
        docs.install();
    } else if (config.target.result.os.tag.isDarwin()) {
        // If we aren't emitting docs we need to emit a placeholder so
        // our macOS xcodeproject builds since it expects the `share/man`
        // directory to exist to copy into the app bundle.
        docs.installDummy(b.getInstallStep());
    }

    // Ghostty webdata
    const webdata = try buildpkg.GhosttyWebdata.init(b, &deps);
    if (config.emit_webdata) webdata.install();

    // Ghostty bench tools
    const bench = try buildpkg.GhosttyBench.init(b, &deps);
    if (config.emit_bench) bench.install();

    // Ghostty dist tarball
    const dist = try buildpkg.GhosttyDist.init(b, &config);
    {
        const step = b.step("dist", "Build the dist tarball");
        step.dependOn(dist.install_step);
        const check_step = b.step("distcheck", "Install and validate the dist tarball");
        check_step.dependOn(dist.check_step);
        check_step.dependOn(dist.install_step);
    }

    // libghostty (internal, big)
    const libghostty_shared = try buildpkg.GhosttyLib.initShared(
        b,
        &deps,
    );
    const libghostty_static = try buildpkg.GhosttyLib.initStatic(
        b,
        &deps,
    );

    // libghostty-vt
    const libghostty_vt_shared = shared: {
        if (config.target.result.cpu.arch.isWasm()) {
            break :shared try buildpkg.GhosttyLibVt.initWasm(
                b,
                &mod,
            );
        }

        break :shared try buildpkg.GhosttyLibVt.initShared(
            b,
            &mod,
        );
    };
    libghostty_vt_shared.install(libvt_step);
    libghostty_vt_shared.install(b.getInstallStep());

    // Helpgen
    if (config.emit_helpgen) deps.help_strings.install();

    // Basal Test (WinUI 3)
    if (builtin.os.tag == .windows) {
        const basal_test_exe = b.addExecutable(.{
            .name = "basal_test",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/basal_test.zig"),
                .target = config.target,
                .optimize = config.optimize,
            }),
        });
        _ = try deps.add(basal_test_exe);
        basal_test_exe.root_module.addImport("build_config", b.createModule(.{
            .root_source_file = b.path("src/build/uucode_config.zig"),
        }));
        // Note: deps.add already adds build_options, so we don't need to add it manually here.
        const basal_test_install = b.addInstallArtifact(basal_test_exe, .{});
        const basal_test_step = b.step("basal-test", "Build WinUI 3 basal infrastructure test");
        basal_test_step.dependOn(&basal_test_install.step);

        const win32_replacement_exe = b.addExecutable(.{
            .name = "ghostty-win32-replacement",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/apprt/win32_replacement/main.zig"),
                .target = config.target,
                .optimize = config.optimize,
            }),
        });
        const win32_replacement_install = b.addInstallArtifact(win32_replacement_exe, .{});
        const win32_replacement_step = b.step(
            "win32-replacement-bootstrap",
            "Build replacement Win32 app-layer bootstrap",
        );
        win32_replacement_step.dependOn(&win32_replacement_install.step);
    }

    // Runtime "none" is libghostty, anything else is an executable.
    if (config.app_runtime != .none) {
        if (config.emit_exe) {
            exe.install();
            resources.install();
            if (i18n) |v| v.install();
        }
    } else {
        // Libghostty
        //
        // Note: libghostty is not stable for general purpose use. It is used
        // heavily by Ghostty on macOS but it isn't built to be reusable yet.
        // As such, these build steps are lacking. For example, the Darwin
        // build only produces an xcframework.

        // We shouldn't have this guard but we don't currently
        // build on macOS this way ironically so we need to fix that.
        if (!config.target.result.os.tag.isDarwin()) {
            libghostty_shared.installHeader(); // Only need one header
            libghostty_shared.install("libghostty.so");
            libghostty_static.install("libghostty.a");
        }
    }

    if (config.target.result.os.tag == .windows and (config.app_runtime == .winui3)) {
        // Stage the Windows App SDK bootstrap DLL next to the exe so LoadLibraryW finds it.
        const default_user_profile = std.process.getEnvVarOwned(b.allocator, "USERPROFILE") catch ".";
        const default_bootstrap_path = std.fs.path.join(b.allocator, &.{ default_user_profile, ".nuget", "packages", "microsoft.windowsappsdk", winappsdk_version, "runtimes", "win10-x64", "native", "Microsoft.WindowsAppRuntime.Bootstrap.dll" }) catch unreachable;
        const bootstrap_dll_path = b.option([]const u8, "winappsdk-bootstrap-dll", "Path to Microsoft.WindowsAppRuntime.Bootstrap.dll") orelse default_bootstrap_path;

        {
            const src: std.Build.LazyPath = .{ .cwd_relative = bootstrap_dll_path };
            const cp = b.addInstallBinFile(src, "Microsoft.WindowsAppRuntime.Bootstrap.dll");
            b.getInstallStep().dependOn(&cp.step);
        }

        // Vtable manifest verification: structural check against known-good slot ordering.
        const vtable_cmd = b.addSystemCommand(&.{
            "pwsh",
            "-NoProfile",
            "-File",
            b.pathFromRoot("scripts/verify-vtable-manifest.ps1"),
            "-ComGenPath",
            b.pathFromRoot("src/apprt/winui3/com_generated.zig"),
            "-ManifestPath",
            b.pathFromRoot("contracts/vtable_manifest.json"),
        });
        const check_contracts_step = b.step("check-contracts", "Verify vtable manifest contracts");
        check_contracts_step.dependOn(&vtable_cmd.step);

        // WinUI3 integration tests (PowerShell test suite)
        {
            const exe_install = b.addInstallArtifact(exe.exe, .{});

            // "test-winui3" runs the full test suite
            const run_all = b.addSystemCommand(&.{
                "powershell.exe",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                b.pathFromRoot("tests/winui3/run-all-tests.ps1"),
            });
            run_all.step.dependOn(&exe_install.step);

            const test_winui3_step = b.step("test-winui3", "Run all WinUI3 integration tests");
            test_winui3_step.dependOn(&run_all.step);

            // Individual test steps: "test-winui3-<name>" for each test-*.ps1
            // run-single-test.ps1 expects -TestName (base name without .ps1)
            const individual_tests = .{
                .{ "test-winui3-lifecycle", "test-01-lifecycle", "Run WinUI3 lifecycle test" },
                .{ "test-winui3-tabview", "test-02a-tabview", "Run WinUI3 tabview test" },
                .{ "test-winui3-ime-overlay", "test-02b-ime-overlay", "Run WinUI3 IME overlay test" },
                .{ "test-winui3-drag-bar", "test-02c-drag-bar", "Run WinUI3 drag bar test" },
                .{ "test-winui3-control-plane", "test-02d-control-plane", "Run WinUI3 control plane test" },
                .{ "test-winui3-agent-roundtrip", "test-02e-agent-roundtrip", "Run WinUI3 agent roundtrip test" },
                .{ "test-winui3-window-ops", "test-03-window-ops", "Run WinUI3 window ops test" },
                .{ "test-winui3-keyboard", "test-04-keyboard", "Run WinUI3 keyboard test" },
                .{ "test-winui3-ghost-demo", "test-05-ghost-demo", "Run WinUI3 ghost demo test" },
                .{ "test-winui3-ime-input", "test-06-ime-input", "Run WinUI3 IME input test" },
                .{ "test-winui3-tsf-ime", "test-07-tsf-ime", "Run WinUI3 TSF IME test" },
            };

            inline for (individual_tests) |entry| {
                const cmd = b.addSystemCommand(&.{
                    "powershell.exe",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    b.pathFromRoot("tests/winui3/run-single-test.ps1"),
                    "-TestName",
                    entry[1],
                });
                cmd.step.dependOn(&exe_install.step);

                const step = b.step(entry[0], entry[2]);
                step.dependOn(&cmd.step);
            }
        }
    }

    // macOS only artifacts. These will error if they're initialized for
    // other targets.
    if (config.target.result.os.tag.isDarwin()) {
        // Ghostty xcframework
        const xcframework = try buildpkg.GhosttyXCFramework.init(
            b,
            &deps,
            config.xcframework_target,
        );
        if (config.emit_xcframework) {
            xcframework.install();

            // The xcframework build always installs resources because our
            // macOS xcode project contains references to them.
            resources.install();
            if (i18n) |v| v.install();
        }

        // Ghostty macOS app
        const macos_app = try buildpkg.GhosttyXcodebuild.init(
            b,
            &config,
            .{
                .xcframework = &xcframework,
                .docs = &docs,
                .i18n = if (i18n) |v| &v else null,
                .resources = &resources,
            },
        );
        if (config.emit_macos_app) {
            macos_app.install();
        }
    }

    // Run step
    run: {
        if (config.app_runtime != .none) {
            const run_cmd = b.addRunArtifact(exe.exe);
            if (b.args) |args| run_cmd.addArgs(args);

            // Set the proper resources dir so things like shell integration
            // work correctly. If we're running `zig build run` in Ghostty,
            // this also ensures it overwrites the release one with our debug
            // build.
            run_cmd.setEnvironmentVariable(
                "GHOSTTY_RESOURCES_DIR",
                b.getInstallPath(.prefix, "share/ghostty"),
            );

            run_step.dependOn(&run_cmd.step);
            break :run;
        }

        assert(config.app_runtime == .none);

        // On macOS we can run the macOS app. For "run" we always force
        // a native-only build so that we can run as quickly as possible.
        if (config.target.result.os.tag.isDarwin()) {
            const xcframework_native = try buildpkg.GhosttyXCFramework.init(
                b,
                &deps,
                .native,
            );
            const macos_app_native_only = try buildpkg.GhosttyXcodebuild.init(
                b,
                &config,
                .{
                    .xcframework = &xcframework_native,
                    .docs = &docs,
                    .i18n = if (i18n) |v| &v else null,
                    .resources = &resources,
                },
            );

            // Run uses the native macOS app
            run_step.dependOn(&macos_app_native_only.open.step);

            // If we have no test filters, install the tests too
            if (test_filters.len == 0) {
                macos_app_native_only.addTestStepDependencies(test_step);
            }
        }
    }

    // Valgrind
    if (config.app_runtime != .none) {
        // We need to rebuild Ghostty with a baseline CPU target.
        const valgrind_exe = exe: {
            var valgrind_config = config;
            valgrind_config.target = valgrind_config.baselineTarget();
            break :exe try buildpkg.GhosttyExe.init(
                b,
                &valgrind_config,
                &deps,
            );
        };

        const run_cmd = b.addSystemCommand(&.{
            "valgrind",
            "--leak-check=full",
            "--num-callers=50",
            b.fmt("--suppressions={s}", .{b.pathFromRoot("valgrind.supp")}),
            "--gen-suppressions=all",
        });
        run_cmd.addArtifactArg(valgrind_exe.exe);
        if (b.args) |args| run_cmd.addArgs(args);
        run_valgrind_step.dependOn(&run_cmd.step);
    }

    // Zig module tests
    {
        const mod_vt_test = b.addTest(.{
            .root_module = mod.vt,
            .filters = test_filters,
        });
        const mod_vt_test_run = b.addRunArtifact(mod_vt_test);
        test_lib_vt_step.dependOn(&mod_vt_test_run.step);

        const mod_vt_c_test = b.addTest(.{
            .root_module = mod.vt_c,
            .filters = test_filters,
        });
        const mod_vt_c_test_run = b.addRunArtifact(mod_vt_c_test);
        test_lib_vt_step.dependOn(&mod_vt_c_test_run.step);
    }

    // Tests
    {
        // Full unit tests
        const test_exe = b.addTest(.{
            .name = "ghostty-test",
            .filters = test_filters,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = config.baselineTarget(),
                .optimize = .Debug,
                .strip = false,
                .omit_frame_pointer = false,
                .unwind_tables = .sync,
            }),
            // Crash on x86_64 without this
            .use_llvm = true,
        });
        if (config.emit_test_exe) b.installArtifact(test_exe);
        _ = try deps.add(test_exe);
        if (config.target.result.os.tag == .windows and config.app_runtime == .winui3) {
            const zcp_dep = b.dependency("zig_control_plane", .{
                .target = config.target,
                .optimize = config.optimize,
            });
            test_exe.root_module.addImport("zig-control-plane", zcp_dep.module("zig-control-plane"));
        }

        // Verify our internal libghostty header.
        const ghostty_h = b.addTranslateC(.{
            .root_source_file = b.path("include/ghostty.h"),
            .target = config.baselineTarget(),
            .optimize = .Debug,
        });
        test_exe.root_module.addImport("ghostty.h", ghostty_h.createModule());

        // Normal test running
        const test_run = b.addRunArtifact(test_exe);
        test_step.dependOn(&test_run.step);

        // Normal tests always test our libghostty modules
        //test_step.dependOn(test_lib_vt_step);

        // Valgrind test running
        const valgrind_run = b.addSystemCommand(&.{
            "valgrind",
            "--leak-check=full",
            "--num-callers=50",
            b.fmt("--suppressions={s}", .{b.pathFromRoot("valgrind.supp")}),
            "--gen-suppressions=all",
        });
        valgrind_run.addArtifactArg(test_exe);
        test_valgrind_step.dependOn(&valgrind_run.step);
    }

    // update-translations does what it sounds like and updates the "pot"
    // files. These should be committed to the repo.
    if (i18n) |v| {
        translations_step.dependOn(v.update_step);
    } else {
        try translations_step.addError("cannot update translations when i18n is disabled", .{});
    }
}
