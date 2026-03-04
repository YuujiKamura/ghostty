const std = @import("std");
const Allocator = std.mem.Allocator;
const configpkg = @import("../../config.zig");
const CoreConfig = configpkg.Config;

const log = std.log.scoped(.winui3_config);

/// Windows-specific wrapper for Ghostty configuration.
/// For now, this is a simple struct, but it will eventually wrap
/// WinRT objects as the win-zig base matures.
pub const Config = struct {
    alloc: Allocator,
    config: CoreConfig,

    pub fn init(alloc: Allocator, core_config: *const CoreConfig) !*Config {
        const self = try alloc.create(Config);
        errdefer alloc.destroy(self);

        self.* = .{
            .alloc = alloc,
            .config = try core_config.clone(alloc),
        };

        return self;
    }

    pub fn deinit(self: *Config) void {
        self.config.deinit();
        self.alloc.destroy(self);
    }

    pub fn get(self: *const Config) *const CoreConfig {
        return &self.config;
    }
};

test "GhosttyConfig memory management" {
    const testing = std.testing;
    const alloc = testing.allocator;

    // Use default config as baseline
    var core_cfg = try CoreConfig.default(alloc);
    defer core_cfg.deinit();

    const wrapper = try Config.init(alloc, &core_cfg);
    // Verifying that deinit clears cloned memory without leaks
    // (std.testing.allocator will detect leaks)
    wrapper.deinit();
}

test "GhosttyConfig" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var core_cfg = try CoreConfig.default(alloc);
    defer core_cfg.deinit();

    const wrapper = try Config.init(alloc, &core_cfg);
    defer wrapper.deinit();

    try testing.expect(wrapper.get() != &core_cfg);
}
