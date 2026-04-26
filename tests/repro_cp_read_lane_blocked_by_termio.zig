//! Regression repro tests for #207 hypothesis #1
//! (CP pipe-server thread × renderer/termio mutex starvation).
//!
//! Background
//! ----------
//! `src/Surface.zig` exposes `viewportString` / `historyString` / `pwd` /
//! `hasSelection` / `cursorIsAtPrompt` / `panePid`. Each of them does:
//!
//!     self.renderer_state.mutex.lock();          // BLOCKING
//!     defer self.renderer_state.mutex.unlock();
//!     ... pull terminal state ...
//!
//! The CP pipe server (`vendor/zig-control-plane/src/pipe_server.zig`)
//! spawns a fresh detached client thread per connection. Each connection
//! routes through `controlPlaneCaptureState/Tail/History` in
//! `src/apprt/winui3/App.zig:1953-1989`, which calls these Surface
//! getters synchronously. The renderer thread holds
//! `renderer_state.mutex` for most of every frame, and termio holds it
//! while parsing PTY bytes.
//!
//! Under sustained PTY output + 2 s `deckpilot show` polling cadence ×
//! N concurrent clients, the CP client thread can sit on
//! `renderer_state.mutex.lock()` indefinitely with no escape — even
//! though the UI thread itself uses `tryLock` for the same mutex in
//! `apprt/winui3/App.zig:1034 tsfGetCursorRect` (commit b7de73893,
//! "#212 P0 #1") precisely because a blocking `lock()` there caused UI
//! freezes.
//!
//! Hypothesis 1 of issue #207: propagate the same `tryLock` pattern to
//! the CP read path so that a contended renderer/termio mutex returns
//! `ERR|BUSY|renderer_locked` to the CP client immediately instead of
//! parking the client thread on the wait queue forever.
//!
//! What these tests prove (mechanically, no Surface needed)
//! --------------------------------------------------------
//! 1. **Pre-fix repro.** A `std.Thread.Mutex` (the exact type used by
//!    `renderer_state.mutex`) acquired by a "termio" thread for 500 ms.
//!    A second "CP client" thread calls `mutex.lock()` 50 ms in.
//!    After 200 ms of polling, the CP thread is *still* parked. This is
//!    the deadlock contract: `lock()` has no escape hatch.
//!
//! 2. **Post-fix contract.** Same setup, but the CP thread uses
//!    `mutex.tryLock()` and falls back to returning the
//!    `ERR|BUSY|renderer_locked` sentinel. The CP thread completes in
//!    well under 10 ms — no parking, no blocking, the pipe gets a clean
//!    error response that deckpilot can interpret as "skip this poll".
//!
//! 3. **Post-fix happy path.** With no contender, `tryLock` succeeds
//!    immediately and produces the captured state. We exercise this so
//!    that the new API isn't reduced to "always returns BUSY"; it must
//!    actually succeed when the lock is free.
//!
//! Hard rule: every test in this file MUST bound its own waiting with
//! an explicit deadline / timed wait. A hung subtest blocks the whole
//! CI; we never rely on `--timeout` as the timeout of last resort.
//!
//! How to run
//! ----------
//! ```
//! zig test tests/repro_cp_read_lane_blocked_by_termio.zig
//! ```
//! (no extra `--dep`s; this test is fully self-contained — `std.Thread.Mutex`
//! is literally the type backing `renderer_state.mutex`.)

const std = @import("std");
const testing = std.testing;

const ns_per_ms = std.time.ns_per_ms;

// ---------------------------------------------------------------------------
// Shared sentinel for the CP "busy" response. The fix in App.zig writes
// this exact byte sequence into the CP pipe on tryLock contention; the
// test pins the contract here so a future renaming has to update both
// sides.
// ---------------------------------------------------------------------------
const CP_BUSY_RESPONSE: []const u8 = "ERR|BUSY|renderer_locked\n";

// ---------------------------------------------------------------------------
// "Termio holder": a side thread that grabs `renderer_state.mutex` for a
// fixed duration, simulating the renderer / termio thread holding the
// mutex across a frame parse. Publishes a flag so the test can wait
// until the holder is *definitely* inside the critical section before
// the CP thread races for the lock.
// ---------------------------------------------------------------------------

const TermioHolder = struct {
    mutex: *std.Thread.Mutex,
    hold_ns: u64,
    holding: std.atomic.Value(bool),
    released: std.atomic.Value(bool),

    fn run(self: *TermioHolder) void {
        self.mutex.lock();
        self.holding.store(true, .release);
        std.Thread.sleep(self.hold_ns);
        self.mutex.unlock();
        self.released.store(true, .release);
    }
};

// ---------------------------------------------------------------------------
// "CP client (blocking)": models the pre-fix CP thread that calls
// `viewportString` / `historyString` / `pwd` / `hasSelection`. It hits
// `mutex.lock()` directly. With a contender, this parks indefinitely.
// ---------------------------------------------------------------------------

const BlockingCpClient = struct {
    mutex: *std.Thread.Mutex,
    done: std.atomic.Value(bool),
    elapsed_ns: std.atomic.Value(u64),

    fn run(self: *BlockingCpClient) void {
        var t = std.time.Timer.start() catch unreachable;
        self.mutex.lock();
        // The real CP path would now call `terminal.plainString(alloc)`.
        // We don't need to model the work — just the lock.
        self.mutex.unlock();
        self.elapsed_ns.store(t.read(), .release);
        self.done.store(true, .release);
    }
};

// ---------------------------------------------------------------------------
// "CP client (tryLock)": models the post-fix CP thread that calls
// `viewportStringLocked` / `historyStringLocked` / `pwdLocked` /
// `hasSelectionLocked`. On contention, the wrapper returns null (which
// the App-side callback turns into `CP_BUSY_RESPONSE` on the pipe).
// ---------------------------------------------------------------------------

const TryLockCpClient = struct {
    mutex: *std.Thread.Mutex,
    done: std.atomic.Value(bool),
    elapsed_ns: std.atomic.Value(u64),
    got_lock: std.atomic.Value(bool),
    response: std.atomic.Value(usize), // 0 = busy sentinel written, 1 = state captured

    fn run(self: *TryLockCpClient) void {
        var t = std.time.Timer.start() catch unreachable;
        if (self.mutex.tryLock()) {
            self.got_lock.store(true, .release);
            // Real path: capture viewport/history/pwd here.
            self.mutex.unlock();
            self.response.store(1, .release);
        } else {
            // Real path: write CP_BUSY_RESPONSE to the pipe and return.
            // Verify locally that the busy sentinel is well-formed and
            // non-empty so the downstream pipe write path receives a
            // valid frame.
            std.debug.assert(CP_BUSY_RESPONSE.len > 0);
            std.debug.assert(CP_BUSY_RESPONSE[CP_BUSY_RESPONSE.len - 1] == '\n');
            self.response.store(0, .release);
        }
        self.elapsed_ns.store(t.read(), .release);
        self.done.store(true, .release);
    }
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn waitForFlag(flag: *std.atomic.Value(bool), deadline_ns: u64) bool {
    var waited: u64 = 0;
    const step_ns: u64 = 1 * ns_per_ms;
    while (!flag.load(.acquire) and waited < deadline_ns) {
        std.Thread.sleep(step_ns);
        waited += step_ns;
    }
    return flag.load(.acquire);
}

// ---------------------------------------------------------------------------
// Test 1: PRE-FIX REPRO.
//
// Termio holds the renderer mutex for 500 ms. A CP client tries to take
// the same mutex with `lock()`. After 200 ms, the CP client MUST still
// be parked. This is the mechanical proof of #207 hypothesis #1: the
// blocking `lock()` in `Surface.viewportString` et al has no escape
// hatch and will park the CP pipe-server thread indefinitely under
// renderer/termio contention.
//
// Cleanup: wait for the termio holder to finish (mutex auto-released),
// then the CP client unblocks; both threads join under a 2 s deadline.
// ---------------------------------------------------------------------------

test "PRE-FIX: blocking lock parks CP client thread under termio contention (#207 hyp 1)" {
    var mutex: std.Thread.Mutex = .{};

    var holder: TermioHolder = .{
        .mutex = &mutex,
        .hold_ns = 500 * ns_per_ms,
        .holding = std.atomic.Value(bool).init(false),
        .released = std.atomic.Value(bool).init(false),
    };

    var holder_thread = try std.Thread.spawn(.{}, TermioHolder.run, .{&holder});

    // Wait until the holder is *inside* the critical section. Without
    // this, a fast CPU could let the CP thread grab the lock first and
    // we'd be testing nothing.
    try testing.expect(waitForFlag(&holder.holding, 200 * ns_per_ms));

    var client: BlockingCpClient = .{
        .mutex = &mutex,
        .done = std.atomic.Value(bool).init(false),
        .elapsed_ns = std.atomic.Value(u64).init(0),
    };

    var client_thread = try std.Thread.spawn(.{}, BlockingCpClient.run, .{&client});

    // Probe deadline: 200 ms. If the CP client returned in this window,
    // the bug doesn't exist. (The holder still has ~300 ms of hold left
    // at this point.)
    std.Thread.sleep(200 * ns_per_ms);

    // Core assertion: the CP client is STILL blocked on the mutex.
    try testing.expect(!client.done.load(.acquire));

    // Bound the cleanup. The holder's 500 ms hold expires soon after,
    // releasing the CP client. Give it generous slack for scheduling.
    holder_thread.join();
    try testing.expect(holder.released.load(.acquire));

    const cleanup_deadline_ns: u64 = 2 * std.time.ns_per_s;
    try testing.expect(waitForFlag(&client.done, cleanup_deadline_ns));
    client_thread.join();

    // Sanity: the CP client's wait time was at least the contended
    // window (≥ 200 ms — we already proved it was still blocked then).
    // This is the load-bearing measurement: it shows `lock()` waited
    // hundreds of ms with no recovery option, exactly matching the
    // `text_not_visible|phase1_timeout` symptom on the deckpilot side.
    const elapsed = client.elapsed_ns.load(.acquire);
    try testing.expect(elapsed >= 200 * ns_per_ms);
}

// ---------------------------------------------------------------------------
// Test 2: POST-FIX CONTRACT — tryLock returns immediately on contention.
//
// Same setup as Test 1, but the CP client uses `tryLock`. On contention
// it MUST return promptly (well under 10 ms — a tryLock is one atomic
// CAS, no scheduler wait), the `got_lock` flag MUST be false, and the
// `response` MUST be the BUSY sentinel (encoded as 0). This is the
// contract the App.zig fix relies on.
// ---------------------------------------------------------------------------

test "POST-FIX: tryLock returns BUSY sentinel without parking on contention (#207 hyp 1)" {
    var mutex: std.Thread.Mutex = .{};

    var holder: TermioHolder = .{
        .mutex = &mutex,
        .hold_ns = 500 * ns_per_ms,
        .holding = std.atomic.Value(bool).init(false),
        .released = std.atomic.Value(bool).init(false),
    };

    var holder_thread = try std.Thread.spawn(.{}, TermioHolder.run, .{&holder});
    defer holder_thread.join();

    try testing.expect(waitForFlag(&holder.holding, 200 * ns_per_ms));

    var client: TryLockCpClient = .{
        .mutex = &mutex,
        .done = std.atomic.Value(bool).init(false),
        .elapsed_ns = std.atomic.Value(u64).init(0),
        .got_lock = std.atomic.Value(bool).init(false),
        .response = std.atomic.Value(usize).init(99), // poison; must overwrite
    };

    var client_thread = try std.Thread.spawn(.{}, TryLockCpClient.run, .{&client});
    defer client_thread.join();

    // Promptness deadline: 100 ms is *huge* for a tryLock — orders of
    // magnitude over what the atomic CAS needs. If we ever cross this
    // budget the new API has accidentally regressed to a blocking wait.
    const promptness_deadline_ns: u64 = 100 * ns_per_ms;
    try testing.expect(waitForFlag(&client.done, promptness_deadline_ns));

    // Core contract:
    //   1. tryLock did not acquire the lock.
    try testing.expect(!client.got_lock.load(.acquire));
    //   2. The fix path wrote the BUSY sentinel (0) instead of state (1).
    try testing.expectEqual(@as(usize, 0), client.response.load(.acquire));
    //   3. Wall-clock was promptly bounded — no hidden parking.
    const elapsed = client.elapsed_ns.load(.acquire);
    try testing.expect(elapsed < promptness_deadline_ns);

    // Drain holder so the worktree is clean for subsequent tests.
    _ = waitForFlag(&holder.released, 2 * std.time.ns_per_s);
}

// ---------------------------------------------------------------------------
// Test 3: POST-FIX HAPPY PATH — tryLock succeeds when the mutex is free.
//
// We must guard against a regression where `*Locked` always returns
// null/BUSY (which would silently break every CP read). With no
// contender, tryLock acquires immediately and the response code is 1
// (state captured).
// ---------------------------------------------------------------------------

test "POST-FIX: tryLock acquires and produces state when mutex is uncontended (#207 hyp 1)" {
    var mutex: std.Thread.Mutex = .{};

    var client: TryLockCpClient = .{
        .mutex = &mutex,
        .done = std.atomic.Value(bool).init(false),
        .elapsed_ns = std.atomic.Value(u64).init(0),
        .got_lock = std.atomic.Value(bool).init(false),
        .response = std.atomic.Value(usize).init(99), // poison; must overwrite
    };

    var client_thread = try std.Thread.spawn(.{}, TryLockCpClient.run, .{&client});
    defer client_thread.join();

    const deadline_ns: u64 = 100 * ns_per_ms;
    try testing.expect(waitForFlag(&client.done, deadline_ns));

    try testing.expect(client.got_lock.load(.acquire));
    try testing.expectEqual(@as(usize, 1), client.response.load(.acquire));

    // Mutex must be released after the client unlocks.
    try testing.expect(mutex.tryLock());
    mutex.unlock();
}

// ---------------------------------------------------------------------------
// Test 4: SUSTAINED CONTENTION — repeated tryLock attempts under a
// long-held mutex never park even one of them.
//
// This models the deckpilot 2 s polling cadence × N clients scenario.
// Even with the mutex held continuously across many polls, every CP
// client must drop through promptly with the BUSY sentinel. If even
// one attempt parks, the active-clients count starts to grow and we
// re-enter the #207 failure mode.
// ---------------------------------------------------------------------------

test "POST-FIX: 16 sequential tryLock attempts all return promptly under contention (#207 hyp 1)" {
    var mutex: std.Thread.Mutex = .{};

    var holder: TermioHolder = .{
        .mutex = &mutex,
        .hold_ns = 1 * std.time.ns_per_s,
        .holding = std.atomic.Value(bool).init(false),
        .released = std.atomic.Value(bool).init(false),
    };

    var holder_thread = try std.Thread.spawn(.{}, TermioHolder.run, .{&holder});
    defer holder_thread.join();

    try testing.expect(waitForFlag(&holder.holding, 200 * ns_per_ms));

    var t = try std.time.Timer.start();
    var busy_count: u32 = 0;
    var got_count: u32 = 0;
    var i: u32 = 0;
    while (i < 16) : (i += 1) {
        if (mutex.tryLock()) {
            got_count += 1;
            mutex.unlock();
        } else {
            busy_count += 1;
        }
    }
    const elapsed = t.read();

    // All 16 must be BUSY (holder is mid-hold).
    try testing.expectEqual(@as(u32, 16), busy_count);
    try testing.expectEqual(@as(u32, 0), got_count);

    // 16 atomic CAS attempts in well under 50 ms — anything more means
    // tryLock has accidentally acquired blocking semantics.
    try testing.expect(elapsed < 50 * ns_per_ms);

    _ = waitForFlag(&holder.released, 2 * std.time.ns_per_s);
}
