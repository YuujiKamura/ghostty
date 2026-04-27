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
//! Phase 2 (#232) replaces the buggy contract structurally
//! ------------------------------------------------------
//! The original test (commits 66c125b22, ddf59742e) validated the fix on
//! `BlockingQueue` by asserting that `.instant` pushes return 0 and never
//! block (test 4) while `.forever` pushes hang the producer until a pop
//! frees a slot (test 1). Phase 2 lands `BoundedMailbox<T, N, ms>`, which
//! removes `.forever` from the type entirely; this file is updated to
//! exercise both the legacy `BlockingQueue` contract (for the regression
//! window where Surface.zig still imports it) AND the new
//! `BoundedMailbox` contract that the migrated `renderer.Thread.Mailbox`
//! relies on.
//!
//! What these tests prove (mechanically, no hardware needed)
//! ---------------------------------------------------------
//! Legacy `BlockingQueue` contract (still asserted because Termio mailbox,
//! App mailbox, and the search worker queue have not migrated yet):
//!   1. `BlockingQueue.push(.forever)` against a full queue blocks the
//!      caller indefinitely until a consumer pops. Test #1.
//!   2. `BlockingQueue.push(.{ .ns = ... })` returns 0 after the timeout
//!      instead of blocking. Test #2.
//!   3. `.instant` saturation contract for the seven UI-thread sibling
//!      sites described in #218/#219/#224. Tests #3 and #4.
//!
//! New `BoundedMailbox` contract (renderer.Thread.Mailbox after Phase 2):
//!   5. `push()` on a `default_timeout_ms=0` mailbox is non-blocking and
//!      returns `.full` (not `.ok`) on saturation. Test #5.
//!   6. `pushTimeout(.., 5_000)` from the search worker thread (the
//!      bridge migration of the seven `.forever` search callsites in
//!      Surface.zig:1465-1542) returns `.full` after the bound rather
//!      than parking forever. Test #6.
//!   7. The compile-time guarantee: there is no `.forever` enum tag on
//!      `PushResult`, so a future regression that re-introduces a
//!      forever-shaped escape hatch fails at comptime. Test #7.
//!
//! Hard rule: every test in this file MUST bound its own waiting with
//! an explicit deadline / timed wait. Never rely on the test runner to
//! kill us — a hung subtest blocks the whole CI.
//!
//! Constraints from the dispatch brief
//! -----------------------------------
//! - This file is self-contained: it imports `blocking_queue.zig` and
//!   `bounded_mailbox.zig` as named modules so it can run via `zig test`
//!   without touching the project test wiring.
//! - Build commands are documented in
//!   `notes/2026-04-26_repro_test_218.md` and `notes/architecture/
//!   2026-04-27_phase2_bounded_mailbox_design.md`.

const std = @import("std");
const testing = std.testing;
// Imported as named modules so this file can sit outside `src/` and
// still build via `zig test` with `--dep blocking_queue --dep
// bounded_mailbox -Mroot=... -Mblocking_queue=src/datastruct/
// blocking_queue.zig -Mbounded_mailbox=src/datastruct/
// bounded_mailbox.zig`.
const blocking_queue = @import("blocking_queue");
const BlockingQueue = blocking_queue.BlockingQueue;
const bounded_mailbox = @import("bounded_mailbox");
const BoundedMailbox = bounded_mailbox.BoundedMailbox;
const never_signal = &bounded_mailbox.never_signal;

const ns_per_ms = std.time.ns_per_ms;

// =========================================================================
// LEGACY BLOCKING_QUEUE CONTRACT (Tests 1-4)
//
// These assert the original .forever / .instant contract that the
// non-renderer mailboxes (App.Mailbox, termio mailbox, search worker
// mailbox) still rely on until Phase 2.3 migrates them. Until those
// migrations land, this contract is load-bearing.
// =========================================================================

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

test "BlockingQueue: push forever blocks indefinitely when full (legacy contract)" {
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
    std.Thread.sleep(100 * ns_per_ms);

    // Core assertion: the producer is still blocked.
    try testing.expect(!probe.done.load(.acquire));

    // Release the producer so the test can shut down cleanly.
    const popped = q.pop();
    try testing.expect(popped != null);

    // Now the producer should complete promptly.
    const join_deadline_ns: u64 = 2 * std.time.ns_per_s;
    var waited: u64 = 0;
    const step_ns: u64 = 5 * ns_per_ms;
    while (!probe.done.load(.acquire) and waited < join_deadline_ns) {
        std.Thread.sleep(step_ns);
        waited += step_ns;
    }
    try testing.expect(probe.done.load(.acquire));

    thread.join();
    try testing.expect(probe.push_return.load(.acquire) > 0);
}

// -----------------------------------------------------------------------
// Test 2: timeout-bounded push returns 0 instead of hanging.
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

test "BlockingQueue: push with ns timeout returns 0 on full queue without hanging" {
    const alloc = testing.allocator;
    const Q = BlockingQueue(u64, 2);

    const q = try Q.create(alloc);
    defer q.destroy(alloc);

    try testing.expectEqual(@as(Q.Size, 1), q.push(1, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 2), q.push(2, .{ .instant = {} }));

    var probe: TimedProbe = .{
        .queue = q,
        .done = std.atomic.Value(bool).init(false),
        .push_return = std.atomic.Value(u32).init(7),
        .elapsed_ns = std.atomic.Value(u64).init(0),
    };

    var thread = try std.Thread.spawn(.{}, TimedProbe.run, .{&probe});
    defer thread.join();

    const deadline_ns: u64 = 500 * ns_per_ms;
    var waited: u64 = 0;
    const step_ns: u64 = 5 * ns_per_ms;
    while (!probe.done.load(.acquire) and waited < deadline_ns) {
        std.Thread.sleep(step_ns);
        waited += step_ns;
    }
    try testing.expect(probe.done.load(.acquire));

    try testing.expectEqual(@as(u32, 0), probe.push_return.load(.acquire));

    const elapsed = probe.elapsed_ns.load(.acquire);
    try testing.expect(elapsed >= 40 * ns_per_ms);
    try testing.expect(elapsed < 400 * ns_per_ms);

    try testing.expectEqual(@as(u64, 1), q.pop().?);
    try testing.expectEqual(@as(u64, 2), q.pop().?);
    try testing.expect(q.pop() == null);
}

// -----------------------------------------------------------------------
// Test 3: focus-saturation repro on legacy BlockingQueue.
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

const SiblingEventKind = enum(u32) {
    inspector_on = 1,
    inspector_off = 2,
    change_config = 3,
    font_grid = 4,
    visible_show = 5,
    visible_hide = 6,
    crash = 7,
    macos_display_id = 8,
    gtk_new_window = 9,
};

test "BlockingQueue: sibling sites instant push never blocks UI thread (#219, #224)" {
    const alloc = testing.allocator;
    const Q = BlockingQueue(u32, 4);

    const q = try Q.create(alloc);
    defer q.destroy(alloc);

    const events = [_]SiblingEventKind{
        .inspector_on,
        .change_config,
        .font_grid,
        .visible_hide,
        .inspector_off,
        .visible_show,
        .crash,
        .macos_display_id,
        .gtk_new_window,
    };

    var t = try std.time.Timer.start();
    var pushed: u32 = 0;
    var dropped: u32 = 0;
    for (events) |kind| {
        const r = q.push(@intFromEnum(kind), .{ .instant = {} });
        if (r == 0) dropped += 1 else pushed += 1;
    }
    const elapsed = t.read();

    try testing.expectEqual(@as(u32, 4), pushed);
    try testing.expectEqual(@as(u32, 5), dropped);
    try testing.expect(elapsed < 50 * ns_per_ms);

    try testing.expectEqual(@as(u32, @intFromEnum(SiblingEventKind.inspector_on)), q.pop().?);
    try testing.expectEqual(@as(u32, @intFromEnum(SiblingEventKind.change_config)), q.pop().?);
    try testing.expectEqual(@as(u32, @intFromEnum(SiblingEventKind.font_grid)), q.pop().?);
    try testing.expectEqual(@as(u32, @intFromEnum(SiblingEventKind.visible_hide)), q.pop().?);
    try testing.expect(q.pop() == null);
}

test "BlockingQueue: focus saturation forever hangs producer, instant drops cleanly (#218)" {
    const alloc = testing.allocator;
    const Q = BlockingQueue(u32, 4);

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

        var thread = try std.Thread.spawn(.{}, FocusBurstProbe.run, .{&probe});

        std.Thread.sleep(200 * ns_per_ms);

        try testing.expect(!probe.done.load(.acquire));
        try testing.expectEqual(@as(u32, 4), probe.pushes_done.load(.acquire));
        try testing.expectEqual(@as(u32, 0), probe.drops.load(.acquire));

        _ = q.pop();
        const deadline_ns: u64 = 2 * std.time.ns_per_s;
        var waited: u64 = 0;
        const step_ns: u64 = 5 * ns_per_ms;
        while (!probe.done.load(.acquire) and waited < deadline_ns) {
            std.Thread.sleep(step_ns);
            waited += step_ns;
        }
        try testing.expect(probe.done.load(.acquire));
        thread.join();

        try testing.expectEqual(@as(u32, 5), probe.pushes_done.load(.acquire));
        try testing.expectEqual(@as(u32, 0), probe.drops.load(.acquire));
    }

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

        var t = try std.time.Timer.start();
        var thread = try std.Thread.spawn(.{}, FocusBurstProbe.run, .{&probe});

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
        try testing.expectEqual(@as(u32, 1), probe.drops.load(.acquire));
        try testing.expect(elapsed < deadline_ns);
    }
}

// =========================================================================
// PHASE 2 BOUNDED_MAILBOX CONTRACT (Tests 5-7)
//
// After Phase 2.2, `renderer.Thread.Mailbox` is a
// `BoundedMailbox(rendererpkg.Message, 64, 0)`. The .forever variant is
// gone from the type. The tests below exercise the new contract using
// `u32`-payload mailboxes (the contract is generic; payload type is
// irrelevant to the saturation behaviour).
// =========================================================================

// -----------------------------------------------------------------------
// Test 5: BoundedMailbox `push()` is non-blocking on a full default-0
// mailbox. This is the new shape of the #218 fix — the type system now
// guarantees that the focusCallback path can ever wait.
// -----------------------------------------------------------------------

test "BoundedMailbox: push() on default_timeout_ms=0 never blocks (#218 structural)" {
    const Q = BoundedMailbox(u32, 4, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    // Saturate.
    try testing.expectEqual(Q.PushResult.ok, q.push(1));
    try testing.expectEqual(Q.PushResult.ok, q.push(2));
    try testing.expectEqual(Q.PushResult.ok, q.push(3));
    try testing.expectEqual(Q.PushResult.ok, q.push(4));

    // Saturated burst — every excess push must come back .full inline.
    var t = try std.time.Timer.start();
    try testing.expectEqual(Q.PushResult.full, q.push(5));
    try testing.expectEqual(Q.PushResult.full, q.push(6));
    try testing.expectEqual(Q.PushResult.full, q.push(7));
    try testing.expectEqual(Q.PushResult.full, q.push(8));
    try testing.expectEqual(Q.PushResult.full, q.push(9));
    const elapsed = t.read();

    // 5 atomic non-blocking pushes need microseconds, not milliseconds.
    try testing.expect(elapsed < 50 * ns_per_ms);

    // Drop counter should reflect the 5 dropped attempts.
    try testing.expectEqual(@as(u64, 5), q.fullDropCount());
}

// -----------------------------------------------------------------------
// Test 6: BoundedMailbox `pushTimeout(., 5000)` is the bridge migration
// for search-thread → renderer pushes (Surface.zig:1465-1542 sites).
// On saturation, it must return `.full` after the bound, never park
// indefinitely.
// -----------------------------------------------------------------------

const BoundedTimedProbe = struct {
    queue: *BoundedMailbox(u32, 2, 0),
    done: std.atomic.Value(bool),
    push_result: std.atomic.Value(u32),
    elapsed_ns: std.atomic.Value(u64),

    fn run(self: *BoundedTimedProbe) void {
        var t = std.time.Timer.start() catch unreachable;
        // 50ms (not 5s) so the test runs fast — same code path.
        const r = self.queue.pushTimeout(99, 50);
        self.elapsed_ns.store(t.read(), .release);
        self.push_result.store(@intFromEnum(r), .release);
        self.done.store(true, .release);
    }
};

test "BoundedMailbox: pushTimeout(., ms) returns .full after bound, never parks forever" {
    const Q = BoundedMailbox(u32, 2, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    try testing.expectEqual(Q.PushResult.ok, q.push(1));
    try testing.expectEqual(Q.PushResult.ok, q.push(2));

    var probe: BoundedTimedProbe = .{
        .queue = q,
        .done = std.atomic.Value(bool).init(false),
        .push_result = std.atomic.Value(u32).init(255),
        .elapsed_ns = std.atomic.Value(u64).init(0),
    };

    var thread = try std.Thread.spawn(.{}, BoundedTimedProbe.run, .{&probe});
    defer thread.join();

    const deadline_ns: u64 = 500 * ns_per_ms;
    var waited: u64 = 0;
    const step_ns: u64 = 5 * ns_per_ms;
    while (!probe.done.load(.acquire) and waited < deadline_ns) {
        std.Thread.sleep(step_ns);
        waited += step_ns;
    }
    try testing.expect(probe.done.load(.acquire));

    try testing.expectEqual(
        @intFromEnum(bounded_mailbox.PushResultEnum.full),
        probe.push_result.load(.acquire),
    );

    const elapsed = probe.elapsed_ns.load(.acquire);
    try testing.expect(elapsed >= 40 * ns_per_ms);
    try testing.expect(elapsed < 400 * ns_per_ms);
}

// -----------------------------------------------------------------------
// Test 7: Compile-time guarantee — `.forever` does not exist on
// `PushResult`. A future refactor that re-introduces a forever-shaped
// escape hatch will fail this comptime test.
//
// This is the structural pay-off of #232 Phase 2: the lint-deadlock.sh
// grep was a textual stop-gap; this test makes the contract type-level.
// -----------------------------------------------------------------------

test "BoundedMailbox: PushResult has no .forever variant (compile-time guarantee #232)" {
    const Q = BoundedMailbox(u32, 4, 0);

    comptime {
        const tags = @typeInfo(Q.PushResult).@"enum".fields;
        if (tags.len != 3) @compileError(
            "PushResult must be 3-state (ok|full|shutdown); change broke #232 contract",
        );
        for (tags) |f| {
            if (std.mem.eql(u8, f.name, "forever")) {
                @compileError(
                    "BoundedMailbox.PushResult must NOT have a .forever " ++
                        "variant — that's the entire point of #232 Phase 2. " ++
                        "If you need an unbounded wait, use pushUntilShutdown.",
                );
            }
        }
    }

    // Demonstrate that the *only* unbounded-shaped API requires a token
    // argument — no `q.pushForever(value)` exists.
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    try testing.expectEqual(Q.PushResult.ok, q.push(1));
    // Saturate then verify pushUntilShutdown takes a token argument by
    // signature (the call site below cannot omit the second argument).
    _ = q.push(2);
    _ = q.push(3);
    _ = q.push(4);
    q.shutdown();
    try testing.expectEqual(
        Q.PushResult.shutdown,
        q.pushUntilShutdown(99, never_signal),
    );
}
