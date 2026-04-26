//! Regression tests for YuujiKamura/ghostty#220.
//!
//! `BlockingQueue` previously implemented `.forever` push as an unguarded
//! `cond_not_full.wait(&self.mutex)` with no way to interrupt. If the
//! consumer thread died or stopped draining, any producer parked on
//! `.forever` would hang permanently with no escape valve.
//!
//! These tests exercise the structural fix: a `shutdown()` method backed by
//! an atomic `closed` flag, which broadcasts the not-full condvar and causes
//! parked `.forever` waiters to drop out and return 0.
//!
//! All assertions are self-bounded: every blocked thread must observe the
//! shutdown within a small wall-clock budget, and on failure the test reports
//! the bug rather than relying on the test runner's outer timeout.

const std = @import("std");
const BlockingQueue = @import("blocking_queue").BlockingQueue;

const Q = BlockingQueue(u64, 2);

const PushCtx = struct {
    queue: *Q,
    started: std.atomic.Value(bool) = .init(false),
    finished: std.atomic.Value(bool) = .init(false),
    result: std.atomic.Value(u32) = .init(std.math.maxInt(u32)),

    fn run(self: *PushCtx) void {
        self.started.store(true, .seq_cst);
        const r = self.queue.push(99, .{ .forever = {} });
        self.result.store(@intCast(r), .seq_cst);
        self.finished.store(true, .seq_cst);
    }
};

/// Block the calling thread (with a hard deadline) until `flag` is true.
/// Returns whether the flag was observed within the deadline.
fn waitForFlag(flag: *std.atomic.Value(bool), deadline_ns: u64) bool {
    var elapsed: u64 = 0;
    const step_ns: u64 = 1 * std.time.ns_per_ms;
    while (elapsed < deadline_ns) : (elapsed += step_ns) {
        if (flag.load(.seq_cst)) return true;
        std.Thread.sleep(step_ns);
    }
    return flag.load(.seq_cst);
}

test "issue #220: shutdown() unblocks .forever push waiter" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const q = try Q.create(alloc);
    defer q.destroy(alloc);

    // Fill the queue so the next push will block.
    try testing.expectEqual(@as(Q.Size, 1), q.push(1, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 2), q.push(2, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 0), q.push(3, .{ .instant = {} }));

    var ctx: PushCtx = .{ .queue = q };
    const t = try std.Thread.spawn(.{}, PushCtx.run, .{&ctx});

    // Wait for the producer to enter the wait. Give it 100ms; if push() returns
    // before then, something else is wrong (queue isn't really full).
    try testing.expect(waitForFlag(&ctx.started, 100 * std.time.ns_per_ms));
    std.Thread.sleep(100 * std.time.ns_per_ms);
    try testing.expect(!ctx.finished.load(.seq_cst));

    // Trigger shutdown — this is the new escape valve.
    q.shutdown();

    // The producer must observe the shutdown and bail out within 100ms. Before
    // the fix this never happens, so we detach the thread and fail loudly
    // rather than hang the test process on join().
    const drained = waitForFlag(&ctx.finished, 100 * std.time.ns_per_ms);
    if (!drained) {
        t.detach();
        // Drain the queue so any future producer wake-up doesn't leak data
        // (the detached thread may still resume eventually).
        _ = q.pop();
        _ = q.pop();
        try testing.expect(false);
        return;
    }
    t.join();

    try testing.expectEqual(@as(u32, 0), ctx.result.load(.seq_cst));
}

const PopCtx = struct {
    queue: *Q,
    started: std.atomic.Value(bool) = .init(false),
    finished: std.atomic.Value(bool) = .init(false),
    got_value: std.atomic.Value(bool) = .init(false),

    fn run(self: *PopCtx) void {
        self.started.store(true, .seq_cst);
        const r = self.queue.popBlocking(.{ .forever = {} });
        self.got_value.store(r != null, .seq_cst);
        self.finished.store(true, .seq_cst);
    }
};

test "issue #220: shutdown() unblocks .forever popBlocking waiter" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const q = try Q.create(alloc);
    defer q.destroy(alloc);

    // Queue is empty — popBlocking(.forever) will park.
    var ctx: PopCtx = .{ .queue = q };
    const t = try std.Thread.spawn(.{}, PopCtx.run, .{&ctx});

    try testing.expect(waitForFlag(&ctx.started, 100 * std.time.ns_per_ms));
    std.Thread.sleep(100 * std.time.ns_per_ms);
    try testing.expect(!ctx.finished.load(.seq_cst));

    q.shutdown();

    const drained = waitForFlag(&ctx.finished, 100 * std.time.ns_per_ms);
    if (!drained) {
        t.detach();
        try testing.expect(false);
        return;
    }
    t.join();

    try testing.expect(!ctx.got_value.load(.seq_cst));
}

test "issue #220: push after shutdown returns 0 immediately" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const q = try Q.create(alloc);
    defer q.destroy(alloc);

    q.shutdown();

    // Even when the queue has free capacity, a push to a closed queue must
    // refuse rather than enqueue silently. This is the contract callers rely
    // on to know the consumer is gone.
    try testing.expectEqual(@as(Q.Size, 0), q.push(1, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 0), q.push(2, .{ .forever = {} }));
}
