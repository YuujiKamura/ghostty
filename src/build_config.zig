//! Build options, available at comptime. Used to configure features. This
//! will reproduce some of the fields from builtin and build_options just
//! so we can limit the amount of imports we need AND give us the ability
//! to shim logic and values into them later.
const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const assert = std.debug.assert;
const apprt = @import("apprt.zig");
const font = @import("font/main.zig");
const rendererpkg = @import("renderer.zig");

pub const ReleaseChannel = enum {
    tip,
    stable,
};

pub const ExeEntrypoint = enum {
    ghostty,
    helpgen,
    mdgen_ghostty_1,
    mdgen_ghostty_5,
    webgen_config,
    webgen_actions,
    webgen_commands,
};

/// The semantic version of this build.
pub const version = options.app_version;
pub const version_string = options.app_version_string;

/// The release channel for this build.
pub const release_channel = std.meta.stringToEnum(ReleaseChannel, @tagName(options.release_channel)).?;

/// The optimization mode as a string.
pub const mode_string = mode: {
    const m = @tagName(builtin.mode);
    if (std.mem.lastIndexOfScalar(u8, m, '.')) |i| break :mode m[i..];
    break :mode m;
};

/// The artifact we're producing. This can be used to determine if we're
/// building a standalone exe, an embedded lib, etc.
pub const artifact = Artifact.detect();

/// Our build configuration. We re-export a lot of these back at the
/// top-level so its a bit cleaner to use throughout the code.
// UPSTREAM-SHARED-OK: fork inlines local enums + stringToEnum bridge instead of importing build/Config.zig (avoids circular import: build_options is a Zig module, Config.zig is the build-script side).
pub const exe_entrypoint: ExeEntrypoint = std.meta.stringToEnum(ExeEntrypoint, @tagName(options.exe_entrypoint)).?;
pub const flatpak = options.flatpak;
pub const snap = options.snap;
pub const app_runtime: apprt.Runtime = std.meta.stringToEnum(apprt.Runtime, @tagName(options.app_runtime)).?;
pub const font_backend: font.Backend = std.meta.stringToEnum(font.Backend, @tagName(options.font_backend)).?;
pub const renderer: rendererpkg.Backend = std.meta.stringToEnum(rendererpkg.Backend, @tagName(options.renderer)).?;
pub const i18n: bool = options.i18n;

/// The bundle ID for the app. This is used in many places and is currently
/// hardcoded here. We could make this configurable in the future if there
/// is a reason to do so.
///
/// On macOS, this must match the App bundle ID. We can get that dynamically
/// via an API but I don't want to pay the cost of that at runtime.
///
/// On GTK, this should match the various folders with resources.
///
/// There are many places that don't use this variable so simply swapping
/// this variable is NOT ENOUGH to change the bundle ID. I just wanted to
/// avoid it in Zig coe as much as possible.
pub const bundle_id = "com.mitchellh.ghostty";

// UPSTREAM-SHARED-OK: fork relocated slow_runtime_safety into the -Dslow-safety build option (terminal/build_options.zig); upstream still has it as a comptime branch on builtin.mode here.
/// slow_runtime_safety is now controlled via -Dslow-safety build option.
/// See src/terminal/build_options.zig (terminal_options.slow_runtime_safety).
pub const Artifact = enum {
    /// Standalone executable
    exe,

    /// Embeddable library
    lib,

    /// The WASM-targeted module.
    wasm_module,

    pub fn detect() Artifact {
        if (builtin.target.cpu.arch.isWasm()) {
            assert(builtin.output_mode == .Obj);
            assert(builtin.link_mode == .Static);
            return .wasm_module;
        }

        return switch (builtin.output_mode) {
            .Exe => .exe,
            .Lib => .lib,
            else => {
                @compileLog(builtin.output_mode);
                @compileError("unsupported artifact output mode");
            },
        };
    }
};

/// True if runtime safety checks are enabled.
pub const is_debug = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};
