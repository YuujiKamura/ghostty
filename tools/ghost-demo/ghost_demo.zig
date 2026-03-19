const std = @import("std");
const windows = std.os.windows;

const FRAME_COUNT = 235;
const HIDE_CURSOR = "\x1b[?25l";
const SHOW_CURSOR = "\x1b[?25h";
const CURSOR_HOME = "\x1b[H";
const CLEAR_SCREEN = "\x1b[2J";
const RESET = "\x1b[0m";
const ALT_SCREEN_ON = "\x1b[?1049h";
const ALT_SCREEN_OFF = "\x1b[?1049l";

fn writeAll(handle: windows.HANDLE, data: []const u8) void {
    var offset: usize = 0;
    while (offset < data.len) {
        var written: u32 = 0;
        const rc = windows.kernel32.WriteFile(handle, data[offset..].ptr, @intCast(data.len - offset), &written, null);
        if (rc == 0) break;
        offset += written;
    }
}

fn getExeDir(allocator: std.mem.Allocator) ![]const u8 {
    const path = try std.fs.selfExePath(allocator);
    // Find last separator
    var last_sep: usize = 0;
    for (path, 0..) |c, idx| {
        if (c == '\\' or c == '/') last_sep = idx;
    }
    if (last_sep > 0) {
        allocator.free(path[last_sep..]);
        return path[0..last_sep];
    }
    allocator.free(path);
    return ".";
}

fn loadFrames(allocator: std.mem.Allocator) ![][]const u8 {
    // Resolve frames dir relative to exe location
    const exe_path_buf = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path_buf);
    // Strip exe filename to get dir
    const exe_dir = std.fs.path.dirname(exe_path_buf) orelse ".";
    const frames_dir = try std.fs.path.join(allocator, &.{ exe_dir, "frames" });
    defer allocator.free(frames_dir);

    var frames = try allocator.alloc([]const u8, FRAME_COUNT);
    for (0..FRAME_COUNT) |i| {
        var name_buf: [32]u8 = undefined;
        const fname = std.fmt.bufPrint(&name_buf, "frame_{d:0>3}.txt", .{i + 1}) catch unreachable;
        const full_path = try std.fs.path.join(allocator, &.{ frames_dir, fname });
        defer allocator.free(full_path);
        frames[i] = std.fs.cwd().readFileAlloc(allocator, full_path, 1 << 20) catch |err| {
            std.debug.print("Failed to load {s}: {}\n", .{ full_path, err });
            return err;
        };
    }
    return frames;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var fps: u32 = 60;
    var benchmark = false;
    var iterations: u32 = 3;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--fps") and i + 1 < args.len) {
            fps = std.fmt.parseInt(u32, args[i + 1], 10) catch 60;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--benchmark")) {
            benchmark = true;
        } else if (std.mem.eql(u8, args[i], "--iterations") and i + 1 < args.len) {
            iterations = std.fmt.parseInt(u32, args[i + 1], 10) catch 3;
            i += 1;
        }
    }

    const frames = try loadFrames(allocator);
    defer {
        for (frames) |f| allocator.free(f);
        allocator.free(frames);
    }

    const handle = windows.kernel32.GetStdHandle(windows.STD_OUTPUT_HANDLE) orelse return;

    if (benchmark) {
        writeAll(handle, ALT_SCREEN_ON ++ HIDE_CURSOR);
        var times: [32]f64 = undefined;
        const iter_count: usize = @min(iterations, 32);

        for (0..iter_count) |it| {
            writeAll(handle, CLEAR_SCREEN ++ CURSOR_HOME);
            var timer = try std.time.Timer.start();
            for (frames) |frame| {
                writeAll(handle, CURSOR_HOME);
                writeAll(handle, frame);
            }
            times[it] = @as(f64, @floatFromInt(timer.read())) / 1_000_000_000.0;
        }

        writeAll(handle, SHOW_CURSOR ++ RESET ++ ALT_SCREEN_OFF);

        const count_f: f64 = @floatFromInt(FRAME_COUNT);
        std.debug.print("Ghost Animation Benchmark ({d} frames x {d} iterations)\n", .{ FRAME_COUNT, iter_count });
        std.debug.print("============================================================\n", .{});
        std.debug.print("{s:>6} {s:>10} {s:>10} {s:>10}\n", .{ "Iter", "Time (s)", "FPS", "ms/frame" });
        std.debug.print("------------------------------------------------------------\n", .{});

        var sum: f64 = 0;
        for (0..iter_count) |it| {
            const t = times[it];
            sum += t;
            std.debug.print("{d:>6} {d:>10.3} {d:>10.1} {d:>10.2}\n", .{ it + 1, t, count_f / t, (t / count_f) * 1000.0 });
        }
        const avg_t = sum / @as(f64, @floatFromInt(iter_count));
        std.debug.print("------------------------------------------------------------\n", .{});
        std.debug.print("{s:>6} {d:>10.3} {d:>10.1} {d:>10.2}\n", .{ "avg", avg_t, count_f / avg_t, (avg_t / count_f) * 1000.0 });
    } else {
        const delay_ns: u64 = 1_000_000_000 / @as(u64, fps);
        writeAll(handle, ALT_SCREEN_ON ++ CLEAR_SCREEN ++ HIDE_CURSOR);

        var loop_count: u32 = 0;
        while (true) {
            loop_count += 1;
            for (frames, 0..) |frame, fi| {
                writeAll(handle, CURSOR_HOME);
                writeAll(handle, frame);
                var status_buf: [128]u8 = undefined;
                const status = std.fmt.bufPrint(&status_buf, "\x1b[999;1H\x1b[7m loop {d} | frame {d}/{d} | {d}fps | Ctrl+C to quit \x1b[0m", .{ loop_count, fi + 1, FRAME_COUNT, fps }) catch "";
                writeAll(handle, status);
                windows.kernel32.Sleep(@intCast(delay_ns / 1_000_000));
            }
        }
    }
}
