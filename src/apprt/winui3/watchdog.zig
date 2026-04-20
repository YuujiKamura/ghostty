//! Dispatcher watchdog log sink for the WinUI3 apprt (Team G, issue #214).
//!
//! Writes per-pid pulse/stall events to a log file that external monitors
//! (e.g. deckpilot) can tail to determine whether the UI-thread dispatcher
//! of a given Ghostty session is still pumping.
//!
//! File path: `%LOCALAPPDATA%\ghostty\dispatcher-watchdog-<pid>.log`
//!
//! Line format (one event per line, ASCII, CRLF-free):
//!   PULSE t_ms=<unix_ms> pid=<u32> hb_age_ms=<u64> stalled=<0|1>
//!   STALL t_ms=<unix_ms> pid=<u32> elapsed_ms=<u64> last_pulse_t_ms=<unix_ms>
//!   # <free-form comment> (session_start / session_end markers)
//!
//! Design goals:
//!   * UI-thread writes (PULSE) are cheap: bounded-stack format buffer, one
//!     `WriteFile` per tick, no allocation on the hot path.
//!   * Watchdog-thread writes (STALL) are serialised against PULSE via a
//!     mutex so interleaved ticks never truncate each other.
//!   * `FlushFileBuffers` after every write: if the process crashes between
//!     ticks, the last pulse is on disk already — that is how an external
//!     monitor distinguishes a crash from a stall.

const std = @import("std");
const os = @import("os.zig");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.winui3_watchdog);

pub const DispatcherWatchdog = struct {
    allocator: Allocator,
    file: std.fs.File,
    path: []u8,
    pid: u32,
    mutex: std.Thread.Mutex = .{},

    /// Open (or create + append) the per-pid log file under %LOCALAPPDATA%\ghostty.
    /// Returns a heap-allocated DispatcherWatchdog so the watchdog background
    /// thread can access it safely via a stable pointer.
    pub fn init(allocator: Allocator, pid: u32) !*DispatcherWatchdog {
        const local_appdata = try std.process.getEnvVarOwned(allocator, "LOCALAPPDATA");
        defer allocator.free(local_appdata);

        const dir = try std.fs.path.join(allocator, &.{ local_appdata, "ghostty" });
        defer allocator.free(dir);
        std.fs.cwd().makePath(dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const file_name = try std.fmt.allocPrint(allocator, "dispatcher-watchdog-{d}.log", .{pid});
        defer allocator.free(file_name);
        const path = try std.fs.path.join(allocator, &.{ dir, file_name });
        errdefer allocator.free(path);

        var file = std.fs.openFileAbsolute(path, .{ .mode = .read_write }) catch blk: {
            break :blk try std.fs.createFileAbsolute(path, .{ .truncate = false, .read = true });
        };
        errdefer file.close();
        file.seekFromEnd(0) catch |err| {
            log.warn("seekFromEnd failed: {}", .{err});
        };

        const self = try allocator.create(DispatcherWatchdog);
        self.* = .{
            .allocator = allocator,
            .file = file,
            .path = path,
            .pid = pid,
        };

        const now_ms = std.time.milliTimestamp();
        self.writeLine("# session_start pid={d} t_ms={d}\n", .{ pid, now_ms });
        log.info("watchdog log opened path={s}", .{path});
        return self;
    }

    pub fn deinit(self: *DispatcherWatchdog) void {
        const now_ms = std.time.milliTimestamp();
        self.writeLine("# session_end pid={d} t_ms={d}\n", .{ self.pid, now_ms });

        self.mutex.lock();
        self.file.close();
        self.mutex.unlock();

        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    /// 1 Hz pulse from the UI thread — emits a PULSE entry.
    /// `heartbeat_age_ms` is the delta between now and the last ~100ms
    /// `HEARTBEAT_TIMER_ID` stamp, which reflects actual dispatcher latency.
    pub fn writePulse(
        self: *DispatcherWatchdog,
        heartbeat_age_ms: u64,
        stalled: bool,
    ) void {
        const now_ms = std.time.milliTimestamp();
        self.writeLine("PULSE t_ms={d} pid={d} hb_age_ms={d} stalled={d}\n", .{
            now_ms,
            self.pid,
            heartbeat_age_ms,
            @as(u8, if (stalled) 1 else 0),
        });
    }

    /// Called from the watchdog background thread when the UI-thread
    /// heartbeat has gone stale for >= threshold.
    pub fn writeStall(
        self: *DispatcherWatchdog,
        elapsed_ms: u64,
        last_pulse_t_ms: i64,
    ) void {
        const now_ms = std.time.milliTimestamp();
        self.writeLine("STALL t_ms={d} pid={d} elapsed_ms={d} last_pulse_t_ms={d}\n", .{
            now_ms,
            self.pid,
            elapsed_ms,
            last_pulse_t_ms,
        });
    }

    fn writeLine(self: *DispatcherWatchdog, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch |err| {
            log.warn("bufPrint failed: {}", .{err});
            return;
        };

        self.mutex.lock();
        defer self.mutex.unlock();

        self.file.writeAll(msg) catch |err| {
            log.warn("writeAll failed: {}", .{err});
            return;
        };
        // Best-effort flush so a crash does not swallow the last pulse.
        _ = os.FlushFileBuffers(self.file.handle);
    }
};
