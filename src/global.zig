const std = @import("std");
const builtin = @import("builtin");
const build_config = @import("build_config.zig");
const cli = @import("cli.zig");
const internal_os = @import("os/main.zig");
// UPSTREAM-SHARED-OK: comptime-gated import of winui3-only helper relocated
// per #254 (2026-04-27 fork-isolation audit item 7); non-winui3 builds resolve
// to an empty struct, so this adds zero runtime cost and zero non-winui3 dep.
const winui3_fontconfig_env = if (build_config.app_runtime == .winui3)
    @import("apprt/winui3/font/env.zig")
else
    struct {};
const fontconfig = @import("fontconfig");
const glslang = @import("glslang");
const harfbuzz = @import("harfbuzz");
const oni = @import("oniguruma");
const crash = @import("crash/main.zig");
const renderer = @import("renderer.zig");
const apprt = @import("apprt.zig");

/// We export the xev backend we want to use so that the rest of
/// Ghostty can import this once and have access to the proper
/// backend.
pub const xev = @import("xev").Dynamic;

/// Global process state. This is initialized in main() for exe artifacts
/// and by ghostty_init() for lib artifacts. This should ONLY be used by
/// the C API. The Zig API should NOT use any global state and should
/// rely on allocators being passed in as parameters.
pub var state: GlobalState = undefined;

/// This represents the global process state. There should only
/// be one of these at any given moment. This is extracted into a dedicated
/// struct because it is reused by main and the static C lib.
pub const GlobalState = struct {
    const GPA = std.heap.GeneralPurposeAllocator(.{});

    gpa: ?GPA,
    alloc: std.mem.Allocator,
    action: ?cli.ghostty.Action,
    logging: Logging,
    rlimits: ResourceLimits = .{},

    /// The app resources directory, equivalent to zig-out/share when we build
    /// from source. This is null if we can't detect it.
    resources_dir: internal_os.ResourcesDir,

    /// Where logging should go
    pub const Logging = packed struct {
        /// Whether to log to stderr. For lib mode we always disable stderr
        /// logging by default. Otherwise it's enabled by default.
        stderr: bool = build_config.app_runtime != .none,
        /// Whether to log to macOS's unified logging. Enabled by default
        /// on macOS.
        macos: bool = builtin.os.tag.isDarwin(),
    };

    /// Initialize the global state.
    pub fn init(self: *GlobalState) !void {
        // const start = try std.time.Instant.now();
        // const start_micro = std.time.microTimestamp();
        // defer {
        //     const end = std.time.Instant.now() catch unreachable;
        //     // "[updateFrame critical time] <START us>\t<TIME_TAKEN us>"
        //     std.log.err("[global init time] start={}us duration={}ns", .{ start_micro, end.since(start) / std.time.ns_per_us });
        // }

        // Initialize ourself to nothing so we don't have any extra state.
        // IMPORTANT: this MUST be initialized before any log output because
        // the log function uses the global state.
        self.* = .{
            .gpa = null,
            .alloc = undefined,
            .action = null,
            .logging = .{},
            .rlimits = .{},
            .resources_dir = .{},
        };
        errdefer self.deinit();

        self.gpa = gpa: {
            // Use the libc allocator if it is available because it is WAY
            // faster than GPA. We only do this in release modes so that we
            // can get easy memory leak detection in debug modes.
            if (builtin.link_libc) {
                if (switch (builtin.mode) {
                    .ReleaseSafe, .ReleaseFast => true,

                    // We also use it if we can detect we're running under
                    // Valgrind since Valgrind only instruments the C allocator
                    else => std.valgrind.runningOnValgrind() > 0,
                }) break :gpa null;
            }

            break :gpa GPA{};
        };

        self.alloc = if (self.gpa) |*value|
            value.allocator()
        else if (builtin.link_libc)
            std.heap.c_allocator
        else
            unreachable;

        // We first try to parse any action that we may be executing.
        self.action = try cli.action.detectArgs(
            cli.ghostty.Action,
            self.alloc,
        );

        // If we have an action executing, we disable logging by default
        // since we write to stderr we don't want logs messing up our
        // output.
        if (self.action != null) self.logging.stderr = false;

        // I don't love the env var name but I don't have it in my heart
        // to parse CLI args 3 times (once for actions, once for config,
        // maybe once for logging) so for now this is an easy way to do
        // this. Env vars are useful for logging too because they are
        // easy to set.
        if ((try internal_os.getenv(self.alloc, "GHOSTTY_LOG"))) |v| {
            defer v.deinit(self.alloc);
            self.logging = cli.args.parsePackedStruct(Logging, v.value) catch .{};
        }

        // Setup our signal handlers before logging
        initSignals();

        // Setup our Xev backend if we're dynamic
        if (comptime xev.dynamic) xev.detect() catch |err| {
            std.log.warn("failed to detect xev backend, falling back to " ++
                "most compatible backend err={}", .{err});
        };

        // Output some debug information right away
        std.log.info("ghostty version={s}", .{build_config.version_string});
        std.log.info("ghostty build optimize={s}", .{build_config.mode_string});
        std.log.info("runtime={}", .{build_config.app_runtime});
        std.log.info("font_backend={}", .{build_config.font_backend});
        if (comptime build_config.font_backend.hasHarfbuzz()) {
            std.log.info("dependency harfbuzz={s}", .{harfbuzz.versionString()});
        }
        if (comptime build_config.font_backend.hasFontconfig()) {
            std.log.info("dependency fontconfig={d}", .{fontconfig.version()});
        }
        std.log.info("renderer={}", .{renderer.Renderer});
        std.log.info("libxev default backend={t}", .{xev.backend});

        // As early as possible, initialize our resource limits.
        self.rlimits = .init();

        // Initialize our crash reporting.
        crash.init(self.alloc) catch |err| {
            std.log.warn(
                "sentry init failed, no crash capture available err={}",
                .{err},
            );
        };

        // const sentrylib = @import("sentry");
        // if (sentrylib.captureEvent(sentrylib.Value.initMessageEvent(
        //     .info,
        //     null,
        //     "hello, world",
        // ))) |uuid| {
        //     std.log.warn("uuid={s}", .{uuid.string()});
        // } else std.log.warn("failed to capture event", .{});

        // We need to make sure the process locale is set properly. Locale
        // affects a lot of behaviors in a shell.
        try internal_os.ensureLocale(self.alloc);

        // Initialize glslang for shader compilation
        try glslang.init();

        // Initialize oniguruma for regex
        try oni.init(&.{oni.Encoding.utf8});

        // Find our resources directory once for the app so every launch
        // hereafter can use this cached value.
        self.resources_dir = try apprt.runtime.resourcesDir(self.alloc);
        errdefer self.resources_dir.deinit(self.alloc);

        // UPSTREAM-SHARED-OK: bootstrap call site for the winui3 fontconfig env
        // wrap (#254). The resources_dir is only available here, so the call has
        // to live in GlobalState.init; the helper itself is winui3-local.
        if (comptime build_config.font_backend.hasFontconfig() and
            build_config.app_runtime == .winui3)
        {
            if (self.resources_dir.app()) |resources_dir| {
                var env_vars = try winui3_fontconfig_env.buildEnvVars(self.alloc, resources_dir);
                defer env_vars.deinit(self.alloc);

                if (env_vars.file_value) |file_value| {
                    const path_value = env_vars.path_value.?;
                    var file_buf: [std.fs.max_path_bytes]u8 = undefined;
                    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

                    const file_z = std.fmt.bufPrintZ(&file_buf, "{s}", .{file_value}) catch null;
                    const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path_value}) catch null;

                    if (file_z == null or path_z == null) {
                        std.log.warn("failed to set fontconfig env: resolved value is too long", .{});
                    } else if (internal_os.setenv("FONTCONFIG_FILE", file_z.?) < 0 or
                        internal_os.setenv("FONTCONFIG_PATH", path_z.?) < 0)
                    {
                        std.log.warn("failed to export fontconfig env vars", .{});
                    } else {
                        std.log.info(
                            "fontconfig env set file={s} path={s}",
                            .{ file_value, path_value },
                        );
                    }
                } else {
                    std.log.warn("fontconfig env not set: resources dir is empty", .{});
                }
            } else {
                std.log.warn("fontconfig env not set: resources dir unavailable", .{});
            }
        }

        // Setup i18n
        if (self.resources_dir.app()) |v| internal_os.i18n.init(v) catch |err| {
            std.log.warn("failed to init i18n, translations will not be available err={}", .{err});
        };
    }

    /// Cleans up the global state. This doesn't _need_ to be called but
    /// doing so in dev modes will check for memory leaks.
    pub fn deinit(self: *GlobalState) void {
        self.resources_dir.deinit(self.alloc);

        // Flush our crash logs
        crash.deinit();

        if (self.gpa) |*value| {
            // We want to ensure that we deinit the GPA because this is
            // the point at which it will output if there were safety violations.
            _ = value.deinit();
        }
    }

    fn initSignals() void {
        // Only posix systems.
        if (comptime builtin.os.tag == .windows) return;

        const p = std.posix;

        var sa: p.Sigaction = .{
            .handler = .{ .handler = p.SIG.IGN },
            .mask = p.sigemptyset(),
            .flags = 0,
        };

        // We ignore SIGPIPE because it is a common signal we may get
        // due to how we implement termio. When a terminal is closed we
        // often write to a broken pipe to exit the read thread. This should
        // be fixed one day but for now this helps make this a bit more
        // robust.
        p.sigaction(p.SIG.PIPE, &sa, null);
    }
};

/// Maintains the Unix resource limits that we set for our process. This
/// can be used to restore the limits to their original values.
pub const ResourceLimits = struct {
    nofile: ?internal_os.rlimit = null,

    pub fn init() ResourceLimits {
        return .{
            // Maximize the number of file descriptors we can have open
            // because we can consume a lot of them if we make many terminals.
            .nofile = internal_os.fixMaxFiles(),
        };
    }

    pub fn restore(self: *const ResourceLimits) void {
        if (self.nofile) |lim| internal_os.restoreMaxFiles(lim);
    }
};
