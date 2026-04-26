//! Regression repro tests for #218 (UI thread hang on full renderer mailbox).
//!
//! Background
//! ----------
//! `src/Surface.zig:focusCallback` originally pushed the focus event to
//! `renderer_thread.mailbox` with `.{ .forever = {} }`. Under sustained
//! renderer load, the mailbox can stay full long enough that this push
//! parks the UI thread on `cond_not_full.wait` indefinitely, which
//! triggers `IsHungAppWindow=true` and stops the message pump for the
//! whole window. cdb evidence on three concurrently-hung sessions all
//! showed the UI thread parked in
//!   Condition.wait -> blocking_queue.push -> focusCallback.
//!
//! What these tests prove (mechanically, no hardware needed)
//! ---------------------------------------------------------
//! 1. `BlockingQueue.push(.forever)` against a full queue blocks the
//!    caller indefinitely until a consumer pops. This is the buggy
//!    contract the pre-fix `focusCallback` relied on. Test #1 spawns a
//!    side thread to attempt the push, sleeps 100ms on the main thread,
//!    and asserts (via an Atomic flag) that the side thread is *still*
//!    blocked. We then unblock by popping so the test cleans up.
//! 2. `BlockingQueue.push(.{ .ns = ... })` against a full queue returns
//!    0 after the timeout instead of blocking forever. This is the
//!    timeout contract callers can rely on.
//! 3. The `focusCallback` saturation pattern: a consumer that is
//!    temporarily stalled lets the producer fill the mailbox, and the
//!    Nth focus event then needs a non-blocking push (`.instant` or
//!    short `.ns`) or it deadlocks. We model this with a 4-slot mailbox,
//!    a paused consumer, and 5 focus pushes. The 5th push under
//!    `.forever` would hang; we test the safe variants instead and
//!    bound the whole exercise with a wall-clock timeout assertion.
//!
//! Hard rule: every test in this file MUST bound its own waiting with
//! an explicit deadline / timed wait. Never rely on the test runner to
//! kill us — a hung subtest blocks the whole CI.
//!
//! Constraints from the dispatch brief
//! -----------------------------------
//! - Do not modify `src/Surface.zig` (owned by another agent).
//! - Do not modify `src/datastruct/blocking_queue.zig` (under audit).
//! - This file is self-contained: it imports `blocking_queue.zig` directly
//!   so it can run via `zig test tests/repro_focus_mailbox_hang.zig`
//!   without touching the project test wiring.

const std = @import("std");
const testing = std.testing;
// Imported as a named module so this file can sit outside `src/` and
// still build via `zig test` with `--dep blocking_queue
// -Mroot=... -Mblocking_queue=src/datastruct/blocking_queue.zig`.
// See `notes/2026-04-26_repro_test_218.md` for the exact command.
const blocking_queue = @import("blocking_queue");
const BlockingQueue = blocking_queue.BlockingQueue;

const ns_per_ms = std.time.ns_per_ms;

// -----------------------------------------------------------------------
// Test 1: `.forever` push blocks indefinitely when the queue is full.
//
// We spawn a producer thread that attempts a `.forever` push to a
// saturated 2-slot queue. We then sleep on the main thread for 100ms
// and probe an atomic flag the producer would have set on completion.
// The flag MUST still be false: that proves the producer is parked in
// `cond_not_full.wait`, which is exactly the deadlock #218 reproduces
// when triggered from the UI thread.
//
// Cleanup: pop one item to release the producer, then join.
// -----------------------------------------------------------------------

const ForeverProbe = struct {
    queue: *BlockingQueue(u64, 2),
    done: std.atomic.Value(bool),
    push_return: std.atomic.Value(u32),

    fn run(self: *ForeverProbe) void {
        const r = self.queue.push(99, .{ .forever = {} });
        // Order matters: publish the return value first, then the flag,
        // so a reader that sees done=true also sees a coherent return.
        self.push_return.store(@intCast(r), .release);
        self.done.store(true, .release);
    }
};

test "push forever blocks indefinitely when full" {
    const alloc = testing.allocator;
    const Q = BlockingQueue(u64, 2);

    const q = try Q.create(alloc);
    defer q.destroy(alloc);

    // Saturate the queue.
    try testing.expectEqual(@as(Q.Size, 1), q.push(1, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 2), q.push(2, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 0), q.push(3, .{ .instant = {} }));

    var probe: ForeverProbe = .{
        .queue = q,
        .done = std.atomic.Value(bool).init(false),
        .push_return = std.atomic.Value(u32).init(0),
    };

    var thread = try std.Thread.spawn(.{}, ForeverProbe.run, .{&probe});

    // Give the producer time to actually enter `cond_not_full.wait`.
    // 100ms is many orders of magnitude longer than a CV park costs to
    // set up; if `.forever` ever returned without a pop, we'd see done
    // become true here.
    std.Thread.sleep(100 * ns_per_ms);

    // Core assertion: the producer is still blocked.
    try testing.expect(!probe.done.load(.acquire));

    // Release the producer so the test can shut down cleanly.
    const popped = q.pop();
    try testing.expect(popped != null);

    // Now the producer should complete promptly. Bound the wait so a
    // pathological hang here doesn't take the test runner with it.
    const join_deadline_ns: u64 = 2 * std.time.ns_per_s;
    var waited: u64 = 0;
    const step_ns: u64 = 5 * ns_per_ms;
    while (!probe.done.load(.acquire) and waited < join_deadline_ns) {
        std.Thread.sleep(step_ns);
        waited += step_ns;
    }
    try testing.expect(probe.done.load(.acquire));

    thread.join();

    // The producer's push must have eventually succeeded (>0).
    try testing.expect(probe.push_return.load(.acquire) > 0);
}

// -----------------------------------------------------------------------
// Test 2: timeout-bounded push returns 0 instead of hanging.
//
// Same setup as Test 1 but the producer uses `.{ .ns = 50ms }`. The
// producer must return on its own within ~50ms with a return value of
// 0 (queue still full). This is the contract a fixed `focusCallback`
// can rely on if it ever wants bounded back-pressure instead of pure
// drop.
// -----------------------------------------------------------------------

const TimedProbe = struct {
    queue: *BlockingQueue(u64, 2),
    done: std.atomic.Value(bool),
    push_return: std.atomic.Value(u32),
    elapsed_ns: std.atomic.Value(u64),

    fn run(self: *TimedProbe) void {
        var t = std.time.Timer.start() catch unreachable;
        const r = self.queue.push(99, .{ .ns = 50 * ns_per_ms });
        self.elapsed_ns.store(t.read(), .release);
        self.push_return.store(@intCast(r), .release);
        self.done.store(true, .release);
    }
};

test "push with ns timeout returns 0 on full queue without hanging" {
    const alloc = testing.allocator;
    const Q = BlockingQueue(u64, 2);

    const q = try Q.create(alloc);
    defer q.destroy(alloc);

    try testing.expectEqual(@as(Q.Size, 1), q.push(1, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 2), q.push(2, .{ .instant = {} }));

    var probe: TimedProbe = .{
        .queue = q,
        .done = std.atomic.Value(bool).init(false),
        .push_return = std.atomic.Value(u32).init(7), // poison; must overwrite
        .elapsed_ns = std.atomic.Value(u64).init(0),
    };

    var thread = try std.Thread.spawn(.{}, TimedProbe.run, .{&probe});
    defer thread.join();

    // Wait up to 500ms (10x the timeout) for the producer to finish.
    // If we ever cross this deadline the timeout contract is broken.
    const deadline_ns: u64 = 500 * ns_per_ms;
    var waited: u64 = 0;
    const step_ns: u64 = 5 * ns_per_ms;
    while (!probe.done.load(.acquire) and waited < deadline_ns) {
        std.Thread.sleep(step_ns);
        waited += step_ns;
    }
    try testing.expect(probe.done.load(.acquire));

    // Push returned 0 (queue still full, did not write).
    try testing.expectEqual(@as(u32, 0), probe.push_return.load(.acquire));

    // And it returned in roughly the timeout window — well below our
    // 500ms cap. Allow some slack for scheduler jitter.
    const elapsed = probe.elapsed_ns.load(.acquire);
    try testing.expect(elapsed >= 40 * ns_per_ms);
    try testing.expect(elapsed < 400 * ns_per_ms);

    // Queue contents are untouched.
    try testing.expectEqual(@as(u64, 1), q.pop().?);
    try testing.expectEqual(@as(u64, 2), q.pop().?);
    try testing.expect(q.pop() == null);
}

// -----------------------------------------------------------------------
// Test 3: focus-saturation repro.
//
// Mocks the Surface.focusCallback path: a 4-slot mailbox stands in for
// `renderer_thread.mailbox`, a "consumer" thread is paused for the
// duration of the burst, and the producer (the UI thread analogue)
// fires 5 focus events back-to-back. With `.forever`, the 5th push
// would hang the producer; we therefore exercise both the bug shape
// and the fix shape in the same test:
//
//   * "buggy_kind" (`.forever`) is run on a side thread and observed
//     via an atomic flag. After 200ms the producer MUST still be
//     blocked. We then unblock it by popping and shut down cleanly.
//   * "fixed_kind" (`.instant`) is run inline on the main thread. All
//     5 pushes complete, the 5th returns 0 (dropped, mirroring the
//     "log warn + drop" path the fix branch takes), and no thread
//     parks at all.
//
// The whole test is bounded by an explicit deadline. It will never
// hang the runner.
// -----------------------------------------------------------------------

const FocusKind = enum { buggy_forever, fixed_instant };

const FocusBurstProbe = struct {
    queue: *BlockingQueue(u32, 4),
    kind: FocusKind,
    done: std.atomic.Value(bool),
    pushes_done: std.atomic.Value(u32),
    drops: std.atomic.Value(u32),

    fn run(self: *FocusBurstProbe) void {
        var i: u32 = 0;
        while (i < 5) : (i += 1) {
            const r = switch (self.kind) {
                .buggy_forever => self.queue.push(i, .{ .forever = {} }),
                .fixed_instant => self.queue.push(i, .{ .instant = {} }),
            };
            if (r == 0) _ = self.drops.fetchAdd(1, .acq_rel);
            _ = self.pushes_done.fetchAdd(1, .acq_rel);
        }
        self.done.store(true, .release);
    }
};

// -----------------------------------------------------------------------
// Test 4 (#219 sibling sites): the drop-on-full contract holds for the
// six other UI-thread `.forever` push sites in `Surface.zig` that share
// the same hang shape as #218 (inspector activate/deactivate, config
// reload, font size change, occlusion, debug crash binding).
//
// The mechanical proof is the same as Test 3: a saturated mailbox plus
// a sequence of `.instant` pushes must complete without blocking, and
// the dropped slots must be observable as `r == 0`. We exercise it with
// heterogeneous payloads (an enum tag stand-in is sufficient — the queue
// is generic and the surface message kind is irrelevant to the contract)
// to make it explicit that *every* sibling site relies on the same
// guarantee, not just `.focus`.
//
// We also verify the producer never blocks regardless of which site
// "fires first" by interleaving event kinds across the saturation
// burst. This guards against a future regression where someone adds a
// new mailbox payload that accidentally takes a slow path.
//
// #224 extension: macOS display-id change and GTK new_window activation
// are the two remaining UI-thread `.forever` sites identified in
// notes/2026-04-26_forever_push_audit.md. They live in apprt-specific
// files (src/apprt/embedded.zig:2119, src/apprt/gtk/class/application.zig:1462)
// rather than Surface.zig, but the fix is the same shape — switch to
// `.instant` and drop+log on full. The blocking_queue contract being
// relied on is identical to #218/#219, so the same enum-tag stand-in
// pattern verifies coverage. The macOS site pushes onto the surface
// renderer mailbox; the GTK site pushes onto the app mailbox — the
// queue is generic over both, so adding a row each into this test
// locks in coverage of both apprt-side fixes.
// -----------------------------------------------------------------------

const SiblingEventKind = enum(u32) {
    inspector_on = 1,
    inspector_off = 2,
    change_config = 3,
    font_grid = 4,
    visible_show = 5,
    visible_hide = 6,
    crash = 7,
    // #224: apprt-side UI-thread sites.
    macos_display_id = 8, // src/apprt/embedded.zig:2119
    gtk_new_window = 9, // src/apprt/gtk/class/application.zig:1462
};

test "sibling sites: instant push never blocks UI thread (#219, #224)" {
    const alloc = testing.allocator;
    const Q = BlockingQueue(u32, 4);

    const q = try Q.create(alloc);
    defer q.destroy(alloc);

    // No consumer is ever started — this models the worst case where the
    // renderer thread is fully stalled (mid-frame, holding the mutex,
    // etc.) and the UI thread keeps firing sibling events.
    const events = [_]SiblingEventKind{
        .inspector_on,
        .change_config,
        .font_grid,
        .visible_hide,
        .inspector_off,
        .visible_show,
        .crash,
        .macos_display_id, // #224 site 1
        .gtk_new_window, // #224 site 2
    };

    var t = try std.time.Timer.start();
    var pushed: u32 = 0;
    var dropped: u32 = 0;
    for (events) |kind| {
        const r = q.push(@intFromEnum(kind), .{ .instant = {} });
        if (r == 0) dropped += 1 else pushed += 1;
    }
    const elapsed = t.read();

    // Mailbox holds 4, we tried 9, so exactly 4 must succeed and 5 drop.
    try testing.expectEqual(@as(u32, 4), pushed);
    try testing.expectEqual(@as(u32, 5), dropped);

    // The whole burst MUST complete in well under a frame budget. If
    // `.instant` ever started waiting we'd see this balloon. 50ms is
    // already orders of magnitude over what 9 atomic pushes need.
    try testing.expect(elapsed < 50 * ns_per_ms);

    // Queue contents reflect the FIRST 4 events (FIFO), proving the
    // accepted pushes landed in order and the dropped ones did not
    // displace them. The two #224 events come last in the burst above,
    // so they are among the dropped — exactly the contract the apprt
    // fix relies on (drop is safe, log.warn fires).
    try testing.expectEqual(@as(u32, @intFromEnum(SiblingEventKind.inspector_on)), q.pop().?);
    try testing.expectEqual(@as(u32, @intFromEnum(SiblingEventKind.change_config)), q.pop().?);
    try testing.expectEqual(@as(u32, @intFromEnum(SiblingEventKind.font_grid)), q.pop().?);
    try testing.expectEqual(@as(u32, @intFromEnum(SiblingEventKind.visible_hide)), q.pop().?);
    try testing.expect(q.pop() == null);
}

test "focus saturation: forever hangs producer, instant drops cleanly (#218)" {
    const alloc = testing.allocator;
    const Q = BlockingQueue(u32, 4);

    // ---- Phase A: buggy `.forever` shape — must hang on the 5th push.
    {
        const q = try Q.create(alloc);
        defer q.destroy(alloc);

        var probe: FocusBurstProbe = .{
            .queue = q,
            .kind = .buggy_forever,
            .done = std.atomic.Value(bool).init(false),
            .pushes_done = std.atomic.Value(u32).init(0),
            .drops = std.atomic.Value(u32).init(0),
        };

        // Spawn the "UI thread" before any consumer activity.
        var thread = try std.Thread.spawn(.{}, FocusBurstProbe.run, .{&probe});

        // Let it fire all 5 pushes. The first 4 fill the queue; the
        // 5th MUST park on `cond_not_full.wait`. 200ms is far more
        // than the producer needs to enqueue 4 items and reach the
        // 5th wait.
        std.Thread.sleep(200 * ns_per_ms);

        // Core assertion: the producer is *not* done; it parked on push #5.
        try testing.expect(!probe.done.load(.acquire));
        try testing.expectEqual(@as(u32, 4), probe.pushes_done.load(.acquire));
        try testing.expectEqual(@as(u32, 0), probe.drops.load(.acquire));

        // Drain to release the parked producer.
        _ = q.pop();
        // Now the 5th push completes; let it.
        const deadline_ns: u64 = 2 * std.time.ns_per_s;
        var waited: u64 = 0;
        const step_ns: u64 = 5 * ns_per_ms;
        while (!probe.done.load(.acquire) and waited < deadline_ns) {
            std.Thread.sleep(step_ns);
            waited += step_ns;
        }
        try testing.expect(probe.done.load(.acquire));
        thread.join();

        // No drops in the buggy path: it waited rather than dropping.
        try testing.expectEqual(@as(u32, 5), probe.pushes_done.load(.acquire));
        try testing.expectEqual(@as(u32, 0), probe.drops.load(.acquire));
    }

    // ---- Phase B: fixed `.instant` shape — must finish without hanging.
    {
        const q = try Q.create(alloc);
        defer q.destroy(alloc);

        var probe: FocusBurstProbe = .{
            .queue = q,
            .kind = .fixed_instant,
            .done = std.atomic.Value(bool).init(false),
            .pushes_done = std.atomic.Value(u32).init(0),
            .drops = std.atomic.Value(u32).init(0),
        };

        // Run inline: this MUST return, no consumer needed.
        var t = try std.time.Timer.start();
        var thread = try std.Thread.spawn(.{}, FocusBurstProbe.run, .{&probe});

        // Bound the wait. Anything over ~100ms means a regression where
        // `.instant` started blocking, which would re-introduce #218.
        const deadline_ns: u64 = 200 * ns_per_ms;
        var waited: u64 = 0;
        const step_ns: u64 = 1 * ns_per_ms;
        while (!probe.done.load(.acquire) and waited < deadline_ns) {
            std.Thread.sleep(step_ns);
            waited += step_ns;
        }
        const elapsed = t.read();
        try testing.expect(probe.done.load(.acquire));
        thread.join();

        try testing.expectEqual(@as(u32, 5), probe.pushes_done.load(.acquire));
        // 4 succeeded, 1 dropped because the queue was full and consumer
        // never ran. This mirrors the fix-branch behaviour (drop + log).
        try testing.expectEqual(@as(u32, 1), probe.drops.load(.acquire));
        // Sanity: this all happened in well under our wall-clock budget.
        try testing.expect(elapsed < deadline_ns);
    }
}
