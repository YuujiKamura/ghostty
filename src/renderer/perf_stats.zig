const std = @import("std");

const log = std.log.scoped(.renderer_perf);

pub const PerfStats = struct {
    frame_start: ?std.time.Instant = null,
    lifetime_count: u64 = 0,
    lifetime_frame_ns: u64 = 0,
    lifetime_min_ns: u64 = std.math.maxInt(u64),
    lifetime_max_ns: u64 = 0,

    pub fn recordFrameStart(self: *PerfStats) void {
        self.frame_start = std.time.Instant.now() catch null;
    }

    pub fn recordFrameEnd(self: *PerfStats) void {
        const start = self.frame_start orelse return;
        const end = std.time.Instant.now() catch return;
        const elapsed = end.since(start);
        self.lifetime_count += 1;
        self.lifetime_frame_ns += elapsed;
        if (elapsed < self.lifetime_min_ns) self.lifetime_min_ns = elapsed;
        if (elapsed > self.lifetime_max_ns) self.lifetime_max_ns = elapsed;
    }

    pub fn logSummary(self: *const PerfStats) void {
        if (self.lifetime_count == 0) return;
        const avg_us = self.lifetime_frame_ns / self.lifetime_count / std.time.ns_per_us;
        const min_us = self.lifetime_min_ns / std.time.ns_per_us;
        const max_us = self.lifetime_max_ns / std.time.ns_per_us;
        log.info("perf: frames={d} avg_us={d} min_us={d} max_us={d}", .{
            self.lifetime_count, avg_us, min_us, max_us,
        });
    }
};
