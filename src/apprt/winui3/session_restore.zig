//! Restart-with-restore: save the window's tabs, start the (possibly freshly
//! rebuilt) ghostty.exe, and reopen the same tabs there. Running processes
//! cannot move between processes (ConPTY dies with its owner), but Claude
//! Code and Codex keep their conversations on disk, so their tabs come back
//! as `claude --resume <id>` / `codex resume <id>` in the same folder.
//!
//! How the running session is found (verified 2026-11-23, Claude Code
//! 2.1.330 / codex-cli 0.170.0):
//!   - Claude Code writes `~/.claude/sessions/<pid>.json` {sessionId, cwd}.
//!   - Codex has no pid map: match `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
//!     (first line `session_meta` with id, cwd, timestamp) against the
//!     process start time, unless the command line already says `resume <id>`.
//!
//! Pure logic (plan JSON, argv filtering, restore command, codex matching)
//! is at the top and unit-tested; Win32 process inspection is below.
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.session_restore);

pub const Kind = enum { shell, claude, codex };

pub const Tab = struct {
    kind: Kind = .shell,
    /// Working folder to reopen the tab in (null = default).
    cwd: ?[]const u8 = null,
    /// Conversation id for claude / codex.
    session_id: ?[]const u8 = null,
    /// Original CLI options, minus any resume/continue options.
    args: []const []const u8 = &.{},
};

pub const Plan = struct {
    version: u32 = 1,
    active: usize = 0,
    /// "none" | "top_bottom" | "left_right"
    split_mode: []const u8 = "none",
    split_first: usize = 0,
    split_second: usize = 1,
    tabs: []const Tab = &.{},
};

pub const ENV_FILE = "KS_RESTORE_FILE";
pub const ENV_WAIT_PID = "KS_RESTORE_WAIT_PID";

pub fn writePlan(alloc: Allocator, plan: Plan) ![]u8 {
    var out: std.io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    try std.json.Stringify.value(plan, .{ .whitespace = .indent_2 }, &out.writer);
    return out.toOwnedSlice();
}

pub fn parsePlan(alloc: Allocator, bytes: []const u8) !std.json.Parsed(Plan) {
    return std.json.parseFromSlice(Plan, alloc, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
}

/// Options that pick a conversation; dropped from the saved args because the
/// restore command supplies its own `--resume <id>` / `resume <id>`.
/// Value = true when the option takes a following value.
fn claudeSessionOption(arg: []const u8) ?bool {
    const with_value = [_][]const u8{ "--resume", "-r", "--session-id", "--from-pr", "--teleport" };
    const flags = [_][]const u8{ "--continue", "-c", "--fork-session" };
    for (with_value) |o| if (std.mem.eql(u8, arg, o)) return true;
    for (flags) |o| if (std.mem.eql(u8, arg, o)) return false;
    for (with_value) |o| {
        if (std.mem.startsWith(u8, arg, o) and arg.len > o.len and arg[o.len] == '=') return false;
    }
    return null;
}

/// Keep the user's options (model, permission mode, ...) and drop the
/// program name and any session-picking options. `argv[0]` is the program.
pub fn keepArgs(alloc: Allocator, kind: Kind, argv: []const []const u8) ![]const []const u8 {
    var kept: std.ArrayList([]const u8) = .empty;
    errdefer kept.deinit(alloc);
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        switch (kind) {
            .claude => if (claudeSessionOption(a)) |takes_value| {
                // --resume's value is optional: only skip a following
                // non-option token.
                if (takes_value and i + 1 < argv.len and argv[i + 1].len > 0 and argv[i + 1][0] != '-') i += 1;
                continue;
            },
            .codex => {
                if (std.mem.eql(u8, a, "resume") or std.mem.eql(u8, a, "fork")) {
                    // Subcommand: drop it, its session id and --last.
                    if (i + 1 < argv.len and argv[i + 1].len > 0 and argv[i + 1][0] != '-') i += 1;
                    continue;
                }
                if (std.mem.eql(u8, a, "--last")) continue;
            },
            .shell => {},
        }
        try kept.append(alloc, a);
    }
    return kept.toOwnedSlice(alloc);
}

/// Session id given on a claude command line (`--resume <id>`, `-r <id>`,
/// `--resume=<id>`), if any.
pub fn claudeResumeArg(argv: []const []const u8) ?[]const u8 {
    for (argv, 0..) |a, i| {
        if (std.mem.startsWith(u8, a, "--resume=")) return a["--resume=".len..];
        if ((std.mem.eql(u8, a, "--resume") or std.mem.eql(u8, a, "-r")) and i + 1 < argv.len) {
            const v = argv[i + 1];
            if (v.len > 0 and v[0] != '-') return v;
        }
    }
    return null;
}

/// Session id given on a codex command line (`codex resume <id>`), if any.
pub fn codexResumeArg(argv: []const []const u8) ?[]const u8 {
    for (argv, 0..) |a, i| {
        if ((std.mem.eql(u8, a, "resume") or std.mem.eql(u8, a, "fork")) and i + 1 < argv.len) {
            const v = argv[i + 1];
            if (v.len > 0 and v[0] != '-') return v;
        }
    }
    return null;
}

fn needsQuote(a: []const u8) bool {
    if (a.len == 0) return true;
    for (a) |c| switch (c) {
        ' ', '\t', '"', '&', '|', '<', '>', '^', '(', ')' => return true,
        else => {},
    };
    return false;
}

fn appendQuoted(out: *std.ArrayList(u8), alloc: Allocator, a: []const u8) !void {
    if (!needsQuote(a)) return out.appendSlice(alloc, a);
    try out.append(alloc, '"');
    for (a) |c| {
        if (c == '"') try out.appendSlice(alloc, "\\\"") else try out.append(alloc, c);
    }
    try out.append(alloc, '"');
}

/// Command line the restored tab runs. `cmd.exe /k` so that quitting the
/// agent leaves a shell in the same folder, like the original tab.
/// Null for plain shell tabs (use the configured default command).
pub fn restoreCommand(alloc: Allocator, tab: Tab) !?[:0]u8 {
    const id = tab.session_id orelse return null;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    switch (tab.kind) {
        .shell => return null,
        .claude => try out.appendSlice(alloc, "cmd.exe /k claude --resume "),
        .codex => try out.appendSlice(alloc, "cmd.exe /k codex resume "),
    }
    try appendQuoted(&out, alloc, id);
    for (tab.args) |a| {
        try out.append(alloc, ' ');
        try appendQuoted(&out, alloc, a);
    }
    return try out.toOwnedSliceSentinel(alloc, 0);
}

pub const CodexCandidate = struct {
    id: []const u8,
    cwd: []const u8,
    /// session_meta timestamp, unix ms.
    created_ms: i64,
    /// file last-write, unix ms.
    modified_ms: i64,
};

/// The rollout a codex process started at `proc_start_ms` is writing: created
/// after the process started (5 s slack), most recently written. A known cwd
/// narrows it down when several codex tabs started at once.
pub fn pickCodexSession(cands: []const CodexCandidate, proc_start_ms: i64, cwd: ?[]const u8) ?usize {
    var best: ?usize = null;
    for (cands, 0..) |c, i| {
        if (c.created_ms < proc_start_ms - 5000) continue;
        if (cwd) |want| if (!std.ascii.eqlIgnoreCase(want, c.cwd)) continue;
        if (best == null or c.modified_ms > cands[best.?].modified_ms) best = i;
    }
    return best;
}

/// Value of `"key":"..."` inside the `"payload":` object (key at object
/// start or after a comma, so `id` does not match `session_id`), unescaped.
fn jsonStringField(alloc: Allocator, text: []const u8, key: []const u8) ?[]const u8 {
    var i = std.mem.indexOf(u8, text, "\"payload\":") orelse return null;
    while (std.mem.indexOfPos(u8, text, i, key)) |k| : (i = k + 1) {
        if (k < 2 or text[k - 1] != '"' or (text[k - 2] != '{' and text[k - 2] != ',')) continue;
        var j = k + key.len;
        if (j + 2 > text.len or text[j] != '"' or text[j + 1] != ':') continue;
        j += 2;
        while (j < text.len and text[j] == ' ') j += 1;
        if (j >= text.len or text[j] != '"') continue;
        var e = j + 1;
        while (e < text.len and text[e] != '"') : (e += 1) {
            if (text[e] == '\\') e += 1;
        }
        if (e >= text.len) return null;
        return std.json.parseFromSliceLeaky([]const u8, alloc, text[j .. e + 1], .{}) catch null;
    }
    return null;
}

pub const CodexMeta = struct { id: []const u8, cwd: []const u8, created_ms: i64 };

/// Pick id / cwd / timestamp out of the head of a codex rollout file.
pub fn parseCodexMeta(alloc: Allocator, head: []const u8) ?CodexMeta {
    if (std.mem.indexOf(u8, head, "\"session_meta\"") == null) return null;
    // Codex sub-agents get their own rollout (thread_source "subagent");
    // only the user's own thread is resumable from the terminal.
    if (jsonStringField(alloc, head, "thread_source")) |src| {
        if (!std.mem.eql(u8, src, "user")) return null;
    }
    const id = jsonStringField(alloc, head, "id") orelse return null;
    const cwd = jsonStringField(alloc, head, "cwd") orelse return null;
    const ts = jsonStringField(alloc, head, "timestamp") orelse return null;
    return .{ .id = id, .cwd = cwd, .created_ms = parseIsoMs(ts) orelse return null };
}

/// Parse an RFC 3339 UTC timestamp ("2026-11-22T22:24:33.341Z") to unix ms.
pub fn parseIsoMs(s: []const u8) ?i64 {
    if (s.len < 19) return null;
    const num = struct {
        fn f(t: []const u8) ?i64 {
            return std.fmt.parseInt(i64, t, 10) catch null;
        }
    }.f;
    const y = num(s[0..4]) orelse return null;
    const mo = num(s[5..7]) orelse return null;
    const d = num(s[8..10]) orelse return null;
    const h = num(s[11..13]) orelse return null;
    const mi = num(s[14..16]) orelse return null;
    const se = num(s[17..19]) orelse return null;
    var ms: i64 = 0;
    if (s.len >= 23 and s[19] == '.') ms = num(s[20..23]) orelse 0;
    // Days from civil (Howard Hinnant).
    const yy = if (mo <= 2) y - 1 else y;
    const era = @divFloor(yy, 400);
    const yoe = yy - era * 400;
    const mp = @mod(mo + 9, 12);
    const doy = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    const days = era * 146097 + doe - 719468;
    return ((days * 24 + h) * 60 + mi) * 60_000 + se * 1000 + ms;
}

// ---------------------------------------------------------------------------
// Win32: find the agent running inside a tab.
// ---------------------------------------------------------------------------

const win = std.os.windows;

const PROCESSENTRY32W = extern struct {
    dwSize: u32,
    cntUsage: u32,
    th32ProcessID: u32,
    th32DefaultHeapID: usize,
    th32ModuleID: u32,
    cntThreads: u32,
    th32ParentProcessID: u32,
    pcPriClassBase: i32,
    dwFlags: u32,
    szExeFile: [260]u16,
};

extern "kernel32" fn Process32FirstW(h: win.HANDLE, pe: *PROCESSENTRY32W) callconv(.winapi) win.BOOL;
extern "kernel32" fn Process32NextW(h: win.HANDLE, pe: *PROCESSENTRY32W) callconv(.winapi) win.BOOL;
extern "kernel32" fn OpenProcess(access: u32, inherit: win.BOOL, pid: u32) callconv(.winapi) ?win.HANDLE;
extern "kernel32" fn GetProcessTimes(h: win.HANDLE, c: *win.FILETIME, e: *win.FILETIME, k: *win.FILETIME, u: *win.FILETIME) callconv(.winapi) win.BOOL;
extern "kernel32" fn WaitForSingleObject(h: win.HANDLE, ms: u32) callconv(.winapi) u32;
extern "ntdll" fn NtQueryInformationProcess(h: win.HANDLE, class: u32, buf: *anyopaque, len: u32, ret: ?*u32) callconv(.winapi) i32;

const PROCESS_QUERY_LIMITED_INFORMATION: u32 = 0x1000;
const SYNCHRONIZE: u32 = 0x00100000;
const ProcessCommandLineInformation: u32 = 60;
const TH32CS_SNAPPROCESS: u32 = 0x2;

const Proc = struct { pid: u32, ppid: u32, name: [64]u8 = undefined, name_len: usize = 0 };

fn snapshot(alloc: Allocator) ![]Proc {
    const h = win.kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (h == win.INVALID_HANDLE_VALUE) return error.Snapshot;
    defer win.CloseHandle(h);
    var list: std.ArrayList(Proc) = .empty;
    errdefer list.deinit(alloc);
    var pe: PROCESSENTRY32W = undefined;
    pe.dwSize = @sizeOf(PROCESSENTRY32W);
    var ok = Process32FirstW(h, &pe);
    while (ok != 0) : (ok = Process32NextW(h, &pe)) {
        var p = Proc{ .pid = pe.th32ProcessID, .ppid = pe.th32ParentProcessID };
        const wlen = std.mem.indexOfScalar(u16, &pe.szExeFile, 0) orelse pe.szExeFile.len;
        p.name_len = std.unicode.wtf16LeToWtf8(&p.name, pe.szExeFile[0..@min(wlen, 20)]);
        try list.append(alloc, p);
    }
    return list.toOwnedSlice(alloc);
}

fn procName(p: *const Proc) []const u8 {
    return p.name[0..p.name_len];
}

/// argv of another process (NtQueryInformationProcess class 60). Owned by `alloc`.
fn commandLine(alloc: Allocator, pid: u32) ![]const []const u8 {
    const h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) orelse return error.OpenProcess;
    defer win.CloseHandle(h);
    var buf: [16384]u8 align(8) = undefined;
    var ret: u32 = 0;
    if (NtQueryInformationProcess(h, ProcessCommandLineInformation, &buf, buf.len, &ret) != 0) return error.Query;
    const us: *const win.UNICODE_STRING = @ptrCast(&buf);
    const w = us.Buffer.?[0 .. us.Length / 2];
    var it = try std.process.ArgIteratorWindows.init(alloc, w);
    defer it.deinit();
    var args: std.ArrayList([]const u8) = .empty;
    while (it.next()) |a| try args.append(alloc, try alloc.dupe(u8, a));
    return args.toOwnedSlice(alloc);
}

fn processStartMs(pid: u32) ?i64 {
    const h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) orelse return null;
    defer win.CloseHandle(h);
    var c: win.FILETIME = undefined;
    var e: win.FILETIME = undefined;
    var k: win.FILETIME = undefined;
    var u: win.FILETIME = undefined;
    if (GetProcessTimes(h, &c, &e, &k, &u) == 0) return null;
    const ticks: i64 = @intCast((@as(u64, c.dwHighDateTime) << 32) | c.dwLowDateTime);
    return @divFloor(ticks - 116444736000000000, 10_000);
}

/// Wait (bounded) for the old window's process to exit before resuming the
/// same conversations, so two clients never run one session at once.
pub fn waitForPidExit(pid: u32, timeout_ms: u32) void {
    const h = OpenProcess(SYNCHRONIZE, 0, pid) orelse return;
    defer win.CloseHandle(h);
    _ = WaitForSingleObject(h, timeout_ms);
}

fn isNamed(p: *const Proc, name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(procName(p), name);
}

fn homeDir(alloc: Allocator) ![]u8 {
    return std.process.getEnvVarOwned(alloc, "USERPROFILE");
}

/// Describe what runs in a tab whose shell is `shell_pid`. Everything is
/// allocated in `alloc` (use an arena). Falls back to a plain shell tab.
pub fn inspectTab(alloc: Allocator, procs: []const Proc, shell_pid: u32, shell_cwd: ?[]const u8) Tab {
    const tab = Tab{ .cwd = shell_cwd };
    // Breadth-first over descendants of the shell.
    var queue: std.ArrayList(u32) = .empty;
    queue.append(alloc, shell_pid) catch return tab;
    var qi: usize = 0;
    while (qi < queue.items.len) : (qi += 1) {
        const parent = queue.items[qi];
        for (procs) |*p| {
            if (p.ppid != parent or p.pid == parent) continue;
            if (isNamed(p, "claude.exe")) {
                if (inspectClaude(alloc, p.pid, shell_cwd)) |t| return t;
            } else if (isNamed(p, "codex.exe")) {
                if (inspectCodex(alloc, procs, p, shell_cwd)) |t| return t;
                continue; // don't descend into codex helpers
            }
            queue.append(alloc, p.pid) catch return tab;
        }
    }
    return tab;
}

fn inspectClaude(alloc: Allocator, pid: u32, shell_cwd: ?[]const u8) ?Tab {
    const argv = commandLine(alloc, pid) catch &[_][]const u8{"claude"};
    const Rec = struct { sessionId: []const u8, cwd: ?[]const u8 = null };
    const rec: ?Rec = blk: {
        const home = homeDir(alloc) catch break :blk null;
        const path = std.fmt.allocPrint(alloc, "{s}\\.claude\\sessions\\{d}.json", .{ home, pid }) catch break :blk null;
        const bytes = std.fs.cwd().readFileAlloc(alloc, path, 1 << 20) catch break :blk null;
        break :blk std.json.parseFromSliceLeaky(Rec, alloc, bytes, .{ .ignore_unknown_fields = true }) catch null;
    };
    // No session record yet (e.g. restarted again right after a restore,
    // before Claude wrote it): fall back to `--resume <id>` on its command line.
    const id = if (rec) |r| r.sessionId else claudeResumeArg(argv) orelse return null;
    return .{
        .kind = .claude,
        .cwd = if (rec) |r| r.cwd orelse shell_cwd else shell_cwd,
        .session_id = id,
        .args = keepArgs(alloc, .claude, argv) catch &.{},
    };
}

fn inspectCodex(alloc: Allocator, procs: []const Proc, p: *const Proc, cwd: ?[]const u8) ?Tab {
    const own = commandLine(alloc, p.pid) catch return null;
    for (own) |a| if (std.mem.eql(u8, a, "app-server")) return null;
    // Options the user typed live on the `node ...codex.js` launcher above
    // the native binary; drop everything up to and including codex.js.
    var argv: []const []const u8 = own;
    for (procs) |*q| {
        if (q.pid != p.ppid or !isNamed(q, "node.exe")) continue;
        const nargv = commandLine(alloc, q.pid) catch break;
        for (nargv, 0..) |a, i| {
            if (std.mem.endsWith(u8, a, "codex.js")) {
                argv = nargv[i..];
                break;
            }
        }
        break;
    }
    const start = processStartMs(p.pid) orelse return null;
    const id: []const u8, const sess_cwd: ?[]const u8 = blk: {
        if (codexResumeArg(argv)) |given| break :blk .{ given, cwd };
        const found = findCodexRollout(alloc, start, cwd) orelse return null;
        break :blk .{ found.id, found.cwd };
    };
    return .{
        .kind = .codex,
        .cwd = sess_cwd,
        .session_id = id,
        .args = keepArgs(alloc, .codex, argv) catch &.{},
    };
}

fn findCodexRollout(alloc: Allocator, start_ms: i64, cwd: ?[]const u8) ?CodexCandidate {
    const home = homeDir(alloc) catch return null;
    var cands: std.ArrayList(CodexCandidate) = .empty;
    // Today's and the start day's folders (UTC dates are what codex uses
    // in rollout names; scanning start day .. now covers midnight).
    var day_ms = start_ms - 86_400_000;
    const now_ms = std.time.milliTimestamp();
    while (day_ms <= now_ms + 86_400_000) : (day_ms += 86_400_000) {
        const es = std.time.epoch.EpochSeconds{ .secs = @intCast(@divFloor(day_ms, 1000)) };
        const yd = es.getEpochDay().calculateYearDay();
        const md = yd.calculateMonthDay();
        const dir_path = std.fmt.allocPrint(alloc, "{s}\\.codex\\sessions\\{d:0>4}\\{d:0>2}\\{d:0>2}", .{
            home, yd.year, md.month.numeric(), md.day_index + 1,
        }) catch continue;
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch continue;
        defer dir.close();
        var it = dir.iterate();
        while (it.next() catch null) |ent| {
            if (ent.kind != .file or !std.mem.endsWith(u8, ent.name, ".jsonl")) continue;
            const f = dir.openFile(ent.name, .{}) catch continue;
            defer f.close();
            const st = f.stat() catch continue;
            const modified: i64 = @intCast(@divFloor(st.mtime, std.time.ns_per_ms));
            if (modified < start_ms) continue;
            // The session_meta line also carries the full instructions (tens
            // of KB), so read only the head and pick the fields out of it.
            const head = alloc.alloc(u8, 16384) catch continue;
            const n = f.readAll(head) catch continue;
            const meta = parseCodexMeta(alloc, head[0..n]) orelse continue;
            cands.append(alloc, .{ .id = meta.id, .cwd = meta.cwd, .created_ms = meta.created_ms, .modified_ms = modified }) catch {};
        }
    }
    const i = pickCodexSession(cands.items, start_ms, cwd) orelse
        (if (cwd != null) pickCodexSession(cands.items, start_ms, null) else null) orelse return null;
    return cands.items[i];
}

pub fn snapshotProcesses(alloc: Allocator) []const Proc {
    if (builtin.os.tag != .windows) return &.{};
    return snapshot(alloc) catch &.{};
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "plan JSON round-trip keeps every field" {
    const tabs = [_]Tab{
        .{ .kind = .claude, .cwd = "C:\\work", .session_id = "abc", .args = &.{ "--model", "opus" } },
        .{ .kind = .codex, .cwd = "C:\\x y", .session_id = "019-1" },
        .{},
    };
    const plan = Plan{ .active = 1, .split_mode = "top_bottom", .split_first = 0, .split_second = 1, .tabs = &tabs };
    const bytes = try writePlan(testing.allocator, plan);
    defer testing.allocator.free(bytes);
    const parsed = try parsePlan(testing.allocator, bytes);
    defer parsed.deinit();
    const p = parsed.value;
    try testing.expectEqual(@as(usize, 1), p.active);
    try testing.expectEqualStrings("top_bottom", p.split_mode);
    try testing.expectEqual(@as(usize, 3), p.tabs.len);
    try testing.expectEqual(Kind.claude, p.tabs[0].kind);
    try testing.expectEqualStrings("opus", p.tabs[0].args[1]);
    try testing.expectEqualStrings("C:\\x y", p.tabs[1].cwd.?);
    try testing.expectEqual(Kind.shell, p.tabs[2].kind);
    try testing.expect(p.tabs[2].session_id == null);
}

test "keepArgs: claude drops every session-picking form, keeps the rest" {
    const A = testing.allocator;
    const cases = [_]struct { in: []const []const u8, out: []const []const u8 }{
        .{ .in = &.{"claude"}, .out = &.{} },
        .{ .in = &.{ "claude", "--dangerously-skip-permissions", "--model", "opus" }, .out = &.{ "--dangerously-skip-permissions", "--model", "opus" } },
        .{ .in = &.{ "claude", "--resume", "id1", "--model", "x" }, .out = &.{ "--model", "x" } },
        .{ .in = &.{ "claude", "-r", "id1" }, .out = &.{} },
        .{ .in = &.{ "claude", "--resume", "--model", "x" }, .out = &.{ "--model", "x" } },
        .{ .in = &.{ "claude", "--resume=id1", "-c", "--fork-session", "--session-id", "u" }, .out = &.{} },
        .{ .in = &.{ "claude", "--continue", "--effort", "high" }, .out = &.{ "--effort", "high" } },
    };
    for (cases) |c| {
        const got = try keepArgs(A, .claude, c.in);
        defer A.free(got);
        try testing.expectEqual(c.out.len, got.len);
        for (c.out, got) |e, g| try testing.expectEqualStrings(e, g);
    }
}

test "keepArgs / codexResumeArg: codex resume and fork forms" {
    const A = testing.allocator;
    const cases = [_]struct { in: []const []const u8, out: []const []const u8, id: ?[]const u8 }{
        .{ .in = &.{"codex.js"}, .out = &.{}, .id = null },
        .{ .in = &.{ "codex.js", "-m", "gpt" }, .out = &.{ "-m", "gpt" }, .id = null },
        .{ .in = &.{ "codex.js", "resume", "019a", "-m", "gpt" }, .out = &.{ "-m", "gpt" }, .id = "019a" },
        .{ .in = &.{ "codex.js", "resume", "--last" }, .out = &.{}, .id = null },
        .{ .in = &.{ "codex.js", "fork", "019b" }, .out = &.{}, .id = "019b" },
    };
    for (cases) |c| {
        const got = try keepArgs(A, .codex, c.in);
        defer A.free(got);
        try testing.expectEqual(c.out.len, got.len);
        for (c.out, got) |e, g| try testing.expectEqualStrings(e, g);
        if (c.id) |id| try testing.expectEqualStrings(id, codexResumeArg(c.in).?) else try testing.expect(codexResumeArg(c.in) == null);
    }
}

test "claudeResumeArg: every form" {
    try testing.expectEqualStrings("x", claudeResumeArg(&.{ "claude", "--resume", "x" }).?);
    try testing.expectEqualStrings("x", claudeResumeArg(&.{ "claude", "-r", "x", "--model", "m" }).?);
    try testing.expectEqualStrings("x", claudeResumeArg(&.{ "claude", "--resume=x" }).?);
    try testing.expect(claudeResumeArg(&.{ "claude", "--resume" }) == null);
    try testing.expect(claudeResumeArg(&.{ "claude", "--resume", "--model", "m" }) == null);
    try testing.expect(claudeResumeArg(&.{ "claude", "-c" }) == null);
}

test "restoreCommand: every kind x with/without args x quoting" {
    const A = testing.allocator;
    try testing.expect((try restoreCommand(A, .{})) == null);
    try testing.expect((try restoreCommand(A, .{ .kind = .claude })) == null); // no id
    const c1 = (try restoreCommand(A, .{ .kind = .claude, .session_id = "s1" })).?;
    defer A.free(c1);
    try testing.expectEqualStrings("cmd.exe /k claude --resume s1", c1);
    const c2 = (try restoreCommand(A, .{ .kind = .claude, .session_id = "s1", .args = &.{ "--model", "a b", "x\"y" } })).?;
    defer A.free(c2);
    try testing.expectEqualStrings("cmd.exe /k claude --resume s1 --model \"a b\" \"x\\\"y\"", c2);
    const c3 = (try restoreCommand(A, .{ .kind = .codex, .session_id = "019", .args = &.{"--full-auto"} })).?;
    defer A.free(c3);
    try testing.expectEqualStrings("cmd.exe /k codex resume 019 --full-auto", c3);
    // Shell metacharacters are quoted so cmd.exe does not interpret them.
    const c4 = (try restoreCommand(A, .{ .kind = .codex, .session_id = "a&b" })).?;
    defer A.free(c4);
    try testing.expectEqualStrings("cmd.exe /k codex resume \"a&b\"", c4);
}

test "pickCodexSession: start window, cwd filter, most recently written" {
    const start: i64 = 1_000_000;
    const c = [_]CodexCandidate{
        .{ .id = "old", .cwd = "C:\\a", .created_ms = start - 60_000, .modified_ms = start + 900 },
        .{ .id = "a1", .cwd = "C:\\a", .created_ms = start + 100, .modified_ms = start + 500 },
        .{ .id = "a2", .cwd = "c:\\A", .created_ms = start + 200, .modified_ms = start + 700 },
        .{ .id = "b", .cwd = "C:\\b", .created_ms = start - 1000, .modified_ms = start + 800 },
    };
    try testing.expectEqualStrings("b", c[pickCodexSession(&c, start, null).?].id);
    try testing.expectEqualStrings("a2", c[pickCodexSession(&c, start, "C:\\a").?].id);
    try testing.expectEqualStrings("b", c[pickCodexSession(&c, start, "C:\\B").?].id);
    try testing.expect(pickCodexSession(&c, start, "C:\\none") == null);
    try testing.expect(pickCodexSession(&c, start + 100_000, null) == null);
    try testing.expect(pickCodexSession(&.{}, start, null) == null);
}

test "parseCodexMeta: real head shape, truncated line, escapes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const head =
        \\{"timestamp":"2026-11-22T22:24:33.341Z","ordinal":0,"type":"session_meta","payload":{"account_scoped":true,"session_id":"PARENT","id":"01a2055c","forked_from_id":"PARENT","timestamp":"2026-11-22T22:24:33.339Z","cwd":"C:\\Users\\yuuji","base_instructions":{"text":"very long ...
    ;
    const m = parseCodexMeta(a, head).?;
    try testing.expectEqualStrings("01a2055c", m.id);
    try testing.expectEqualStrings("C:\\Users\\yuuji", m.cwd);
    try testing.expectEqual(parseIsoMs("2026-11-22T22:24:33.339Z").?, m.created_ms);
    try testing.expect(parseCodexMeta(a, "{\"type\":\"event_msg\",\"payload\":{\"id\":\"x\"}}") == null);
    // thread_source: user accepted, subagent rejected.
    const base = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"u1\",\"timestamp\":\"2026-11-22T22:24:33Z\",\"cwd\":\"C:\\\\a\",\"thread_source\":\"";
    try testing.expectEqualStrings("u1", parseCodexMeta(a, base ++ "user\"}").?.id);
    try testing.expect(parseCodexMeta(a, base ++ "subagent\"}") == null);
    try testing.expect(parseCodexMeta(a, "{\"type\":\"session_meta\",\"payload\":{\"id\":\"x\"") == null);
}

test "parseIsoMs: known instants" {
    try testing.expectEqual(@as(i64, 0), parseIsoMs("1970-01-01T00:00:00Z").?);
    try testing.expectEqual(@as(i64, 951_782_400_000), parseIsoMs("2000-02-29T00:00:00Z").?);
    // 2026-11-22T22:24:33.341Z
    try testing.expectEqual(@as(i64, 1_795_386_273_341), parseIsoMs("2026-11-22T22:24:33.341Z").?);
    try testing.expect(parseIsoMs("bad") == null);
}

test "inspectTab on this test process: plain shell, no crash" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const procs = snapshotProcesses(a);
    try testing.expect(procs.len > 0);
    const me = win.GetCurrentProcessId();
    const t = inspectTab(a, procs, me, "C:\tmp");
    try testing.expectEqual(Kind.shell, t.kind);
    try testing.expectEqualStrings("C:\tmp", t.cwd.?);
    // Command line of ourselves parses and starts with the test binary.
    const argv = try commandLine(a, me);
    try testing.expect(argv.len >= 1);
    try testing.expect(processStartMs(me).? <= std.time.milliTimestamp());
}
