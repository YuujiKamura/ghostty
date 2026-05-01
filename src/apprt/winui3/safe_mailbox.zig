//! Bounded mailbox for cross-thread message passing.
//!
//! Successor to `BlockingQueue` (see #232). The defining difference is that
//! the `.forever` timeout variant *does not exist*. Callers that need to
//! wait indefinitely must opt in via `pushUntilShutdown`, which requires a
//! shutdown token, making the lifecycle dependency explicit.
//!
//! Type parameters
//! ---------------
//!   T                    — message payload type
//!   capacity             — fixed ring-buffer slot count (compile-time)
//!   default_timeout_ms   — `?u32`. If non-null, `push` uses this as its
//!                          default bound; if null, `push` is a compile-
//!                          error and callers must use `pushTimeout`.
//!
//! `default_timeout_ms` lets each mailbox encode its own SLO at the type:
//!
//!   * UI → renderer mailbox  : `default_timeout_ms = 0`  (drop on full,
//!                              same semantics as today's `.instant`)
//!   * termio → renderer      : `default_timeout_ms = 5000`
//!   * worker → worker        : `default_timeout_ms = null`  (caller must
//!                              spell its own bound)
//!
//! Lifecycle
//! ---------
//! `shutdown()` inherits the semantics landed in #220: idempotent broadcast
//! that wakes every parked producer/consumer; subsequent operations
//! short-circuit with `.shutdown`.
//!
//! Why this exists (issue #232 Phase 2)
//! ------------------------------------
//! `BlockingQueue.push(value, .{ .forever = {} })` from the UI thread is
//! the failure mode behind the 2026-04-26 deadlock cluster (#218–#225).
//! `tools/lint-deadlock.sh` was a textual stop-gap; this type makes the
//! defect *structurally impossible*: there is no `.forever` variant to
//! mistype, and the only call that waits without a numeric bound is
//! `pushUntilShutdown`, whose mandatory token argument shows up in code
//! review.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Outcome of a `push*` call.
///
/// Modeled as a 3-state enum so callers can `switch` exhaustively. The
/// previous `BlockingQueue.push` returned `Size` and overloaded "depth"
/// with "did it succeed", which forced every callsite into either an
/// `_ = ...` or a `> 0` comparison and lost semantic information at the
/// type system layer.
pub const PushResultEnum = enum {
    /// Value was enqueued.
    ok,
    /// Queue was full at the bound; value was *not* enqueued.
    full,
    /// `shutdown()` has been called; value was *not* enqueued.
    shutdown,
};

/// Outcome of a `pop*` call. Symmetrical with `PushResult`.
pub fn PopResultUnion(comptime T: type) type {
    return union(enum) {
        /// A value was dequeued.
        value: T,
        /// Queue was empty at the bound; no value.
        empty: void,
        /// `shutdown()` has been called and the queue is drained.
        shutdown: void,
    };
}

/// Token broadcast by an `App`-scoped shutdown bus (Phase 3, future).
///
/// In Phase 2 we only need a *named* sentinel so `pushUntilShutdown` is
/// callable. The token's identity carries no behaviour today; the actual
/// shutdown signal is the mailbox's own `shutdown()`. Phase 3 will give
/// it teeth by routing `app.shutdown_token` into every worker mailbox so
/// a single `app.shutdown()` call wakes every parked producer in the
/// process.
///
/// Use `never_signal` when you want "wait until either (a) capacity frees
/// or (b) this mailbox itself is shut down". The well-known sentinel name
/// stands out in code review — that visibility is the entire point of
/// requiring a token argument.
pub const ShutdownToken = struct {
    /// Reserved for future Phase 3 signaling. Currently always false.
    /// Kept as `bool` (not `void`) so future extension is non-breaking.
    signaled: bool = false,
};

/// Shared sentinel: "no external signal source; rely on the mailbox's own
/// `shutdown()` to unblock". Use as the second arg to `pushUntilShutdown`
/// when you don't yet have an App-scoped bus to route in.
pub var never_signal: ShutdownToken = .{};

/// Returns a bounded mailbox type for messages of type `T`.
///
/// See the file doc comment for the full design rationale (#232).
pub fn BoundedMailbox(
    comptime T: type,
    comptime capacity: usize,
    comptime default_timeout_ms: ?u32,
) type {
    return struct {
        const Self = @This();

        pub const Size = u32;
        pub const Capacity: Size = @intCast(capacity);
        pub const DefaultTimeoutMs: ?u32 = default_timeout_ms;
        pub const Payload = T;
        /// Re-exposed at the generic boundary so call sites can write
        /// `Mailbox.PushResult.ok` instead of importing the file-scope enum.
        pub const PushResult = PushResultEnum;
        pub const PopResult = PopResultUnion(T);

        // The bounds of this queue, recast for arithmetic.
        const bounds: Size = @intCast(capacity);

        /// Ring buffer slots. Undefined until written.
        data: [bounds]T = undefined,

        write: Size = 0,
        read: Size = 0,
        len: Size = 0,

        mutex: std.Thread.Mutex = .{},

        cond_not_full: std.Thread.Condition = .{},
        not_full_waiters: usize = 0,

        cond_not_empty: std.Thread.Condition = .{},
        not_empty_waiters: usize = 0,

        /// Set by `shutdown()`. Atomic so waiters can poll without
        /// holding the mutex; the mutex still serialises CV signalling.
        closed: std.atomic.Value(bool) = .init(false),

        /// Phase-4 metrics seed: count of pushes that hit `.full`.
        full_drops: std.atomic.Value(u64) = .init(0),

        // --- lifecycle -------------------------------------------------

        /// Heap-allocate. Mirrors `BlockingQueue.create`.
        pub fn create(alloc: Allocator) Allocator.Error!*Self {
            const ptr = try alloc.create(Self);
            errdefer alloc.destroy(ptr);
            ptr.* = .{};
            return ptr;
        }

        /// Free. All producers/consumers must have exited (or `shutdown()`
        /// been called and observed) before this is called.
        pub fn destroy(self: *Self, alloc: Allocator) void {
            self.* = undefined;
            alloc.destroy(self);
        }

        /// Idempotent. Wakes every parked producer/consumer; subsequent
        /// `push*` returns `.shutdown`, subsequent `pop*` drains remaining
        /// items then returns `.shutdown`.
        ///
        /// Inherits the contract from `BlockingQueue.shutdown()` (#220).
        pub fn shutdown(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.closed.store(true, .seq_cst);
            self.cond_not_full.broadcast();
            self.cond_not_empty.broadcast();
        }

        /// Lock-free check.
        pub fn isClosed(self: *const Self) bool {
            return self.closed.load(.seq_cst);
        }

        // --- producer side --------------------------------------------

        /// Push using the type-baked default timeout.
        ///
        /// **Compile error** if `default_timeout_ms == null`. This forces
        /// the mailbox author to either bake the SLO into the type or
        /// require every callsite to spell its bound (`pushTimeout`).
        ///
        /// Behaviour for `default_timeout_ms == 0`: identical to the old
        /// `.instant` — non-blocking, returns `.full` on saturation. Use
        /// this for UI-thread → worker mailboxes (the #218 contract).
        ///
        /// Behaviour for `default_timeout_ms > 0`: bounded park on the
        /// not-full condvar; returns `.full` on timeout, `.shutdown` if
        /// the queue closes during the wait.
        pub fn push(self: *Self, value: T) PushResult {
            comptime {
                if (default_timeout_ms == null) {
                    @compileError(
                        "BoundedMailbox(T, N, null).push() is unbounded — " ++
                            "use pushTimeout(value, ms) to spell your SLO at " ++
                            "the callsite, or declare the type with a " ++
                            "default_timeout_ms to bake the SLO at the type.",
                    );
                }
            }
            return self.pushTimeout(value, default_timeout_ms.?);
        }

        /// Push with an explicit per-call bound. Always available regardless
        /// of `default_timeout_ms`.
        ///
        /// `timeout_ms == 0` is non-blocking (drop on full). The largest
        /// legal wait is `std.math.maxInt(u32)` ms (~49 days), which is
        /// finite and observable — i.e. *not* `.forever`. If you find
        /// yourself wanting "forever", reach for `pushUntilShutdown`.
        pub fn pushTimeout(self: *Self, value: T, timeout_ms: u32) PushResult {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed.load(.seq_cst)) return .shutdown;

            if (self.full()) {
                if (timeout_ms == 0) {
                    _ = self.full_drops.fetchAdd(1, .monotonic);
                    return .full;
                }

                self.not_full_waiters += 1;
                defer self.not_full_waiters -= 1;

                const timeout_ns: u64 = @as(u64, timeout_ms) * std.time.ns_per_ms;
                self.cond_not_full.timedWait(&self.mutex, timeout_ns) catch {
                    // Spurious wake-up vs real timeout: re-check state.
                    if (self.closed.load(.seq_cst)) return .shutdown;
                    if (self.full()) {
                        _ = self.full_drops.fetchAdd(1, .monotonic);
                        return .full;
                    }
                    // fall through to enqueue
                };

                if (self.closed.load(.seq_cst)) return .shutdown;
                if (self.full()) {
                    _ = self.full_drops.fetchAdd(1, .monotonic);
                    return .full;
                }
            }

            self.enqueueLocked(value);
            return .ok;
        }

        /// Push, parking until either (a) capacity frees, (b) `shutdown()`
        /// is called on this mailbox, or (c) the supplied shutdown token
        /// is signaled by an external authority.
        ///
        /// This is the *only* way to wait without a numeric bound, and
        /// the shutdown-token argument makes the lifecycle dependency
        /// syntactically obvious in code review.
        ///
        /// Recommended for: same-App-lifecycle worker→worker pushes where
        /// the consumer's death would already imply the producer's death,
        /// AND there is an App-scoped shutdown bus the token comes from.
        ///
        /// Forbidden by convention for: any function in the apprt callback
        /// surface (`*Callback`, `update*`, `activate*`, `deactivate*`).
        /// The Phase 2.4 lint update will enforce this.
        pub fn pushUntilShutdown(
            self: *Self,
            value: T,
            token: *ShutdownToken,
        ) PushResult {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed.load(.seq_cst)) return .shutdown;
            if (token.signaled) return .shutdown;

            if (self.full()) {
                self.not_full_waiters += 1;
                defer self.not_full_waiters -= 1;
                while (self.full() and
                    !self.closed.load(.seq_cst) and
                    !token.signaled)
                {
                    // Bounded re-check tick: even with no external
                    // signal, we wake every 100ms to re-poll the token
                    // pointer (which a Phase 3 bus may flip between our
                    // wait and broadcast). Cheap insurance.
                    self.cond_not_full.timedWait(
                        &self.mutex,
                        100 * std.time.ns_per_ms,
                    ) catch {};
                }
                if (self.closed.load(.seq_cst)) return .shutdown;
                if (token.signaled) return .shutdown;
                if (self.full()) {
                    // Loop exited without space: only happens if signaled
                    // races; treat as shutdown (caller can retry).
                    return .shutdown;
                }
            }

            self.enqueueLocked(value);
            return .ok;
        }

        // --- consumer side --------------------------------------------

        /// Non-blocking pop. Returns `.empty`, `.value{...}`, or
        /// `.shutdown` (only after the queue has drained).
        pub fn pop(self: *Self) PopResult {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.len == 0) {
                if (self.closed.load(.seq_cst)) return .{ .shutdown = {} };
                return .{ .empty = {} };
            }

            return .{ .value = self.dequeueLocked() };
        }

        /// Optional-style non-blocking pop. Returns `null` for both empty
        /// and shutdown — convenient adapter for `while (q.popOrNull())
        /// |msg|` loops that don't care to distinguish the two cases.
        ///
        /// Used by drainMailbox-style consumers that just want "give me
        /// the next message or stop" semantics.
        pub fn popOrNull(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.len == 0) return null;
            return self.dequeueLocked();
        }

        /// Bounded blocking pop. Symmetric with `pushTimeout`.
        pub fn popTimeout(self: *Self, timeout_ms: u32) PopResult {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed.load(.seq_cst) and self.len == 0) {
                return .{ .shutdown = {} };
            }

            if (self.len == 0) {
                if (timeout_ms == 0) return .{ .empty = {} };

                self.not_empty_waiters += 1;
                defer self.not_empty_waiters -= 1;

                const timeout_ns: u64 = @as(u64, timeout_ms) * std.time.ns_per_ms;
                self.cond_not_empty.timedWait(&self.mutex, timeout_ns) catch {
                    if (self.closed.load(.seq_cst) and self.len == 0)
                        return .{ .shutdown = {} };
                    if (self.len == 0) return .{ .empty = {} };
                };

                if (self.len == 0) {
                    if (self.closed.load(.seq_cst)) return .{ .shutdown = {} };
                    return .{ .empty = {} };
                }
            }

            return .{ .value = self.dequeueLocked() };
        }

        /// Bulk drain. Same semantics as `BlockingQueue.drain` — held
        /// mutex until the iterator's `deinit` is called.
        pub fn drain(self: *Self) DrainIterator {
            self.mutex.lock();
            return .{ .queue = self };
        }

        pub const DrainIterator = struct {
            queue: *Self,

            pub fn next(self: *DrainIterator) ?T {
                if (self.queue.len == 0) return null;

                const n = self.queue.read;
                self.queue.read += 1;
                if (self.queue.read >= bounds) self.queue.read -= bounds;
                self.queue.len -= 1;
                return self.queue.data[n];
            }

            pub fn deinit(self: *DrainIterator) void {
                if (self.queue.not_full_waiters > 0)
                    self.queue.cond_not_full.signal();
                self.queue.mutex.unlock();
            }
        };

        // --- introspection (for Phase 4 metrics) ----------------------

        /// Current depth. Holds the mutex briefly.
        pub fn lenApprox(self: *Self) Size {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.len;
        }

        /// Total push attempts that hit `.full`. Useful for the contention
        /// metric Phase 4 will collect. Lock-free.
        pub fn fullDropCount(self: *const Self) u64 {
            return self.full_drops.load(.monotonic);
        }

        // --- internal helpers -----------------------------------------

        inline fn full(self: *Self) bool {
            return self.len == bounds;
        }

        inline fn enqueueLocked(self: *Self, value: T) void {
            self.data[self.write] = value;
            self.write += 1;
            if (self.write >= bounds) self.write -= bounds;
            self.len += 1;
            if (self.not_empty_waiters > 0) self.cond_not_empty.signal();
        }

        inline fn dequeueLocked(self: *Self) T {
            const n = self.read;
            self.read += 1;
            if (self.read >= bounds) self.read -= bounds;
            self.len -= 1;
            if (self.not_full_waiters > 0) self.cond_not_full.signal();
            return self.data[n];
        }
    };
}

// =========================================================================
// Tests
// =========================================================================

const testing = std.testing;
const ns_per_ms = std.time.ns_per_ms;

test "push() with default_timeout_ms = 0 drops on full (#218 contract)" {
    const Q = BoundedMailbox(u64, 2, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    try testing.expectEqual(Q.PushResult.ok, q.push(1));
    try testing.expectEqual(Q.PushResult.ok, q.push(2));
    try testing.expectEqual(Q.PushResult.full, q.push(3));
    try testing.expectEqual(Q.PushResult.full, q.push(4));

    try testing.expectEqual(@as(u64, 2), q.fullDropCount());

    // Drain confirms only the first two values landed.
    switch (q.pop()) {
        .value => |v| try testing.expectEqual(@as(u64, 1), v),
        else => try testing.expect(false),
    }
    switch (q.pop()) {
        .value => |v| try testing.expectEqual(@as(u64, 2), v),
        else => try testing.expect(false),
    }
    try testing.expect(q.pop() == .empty);
}

test "pushTimeout(.., 0) is non-blocking equivalent" {
    const Q = BoundedMailbox(u64, 1, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    try testing.expectEqual(Q.PushResult.ok, q.pushTimeout(1, 0));
    try testing.expectEqual(Q.PushResult.full, q.pushTimeout(2, 0));
}

test "pushTimeout(.., 50ms) blocks at most ~50ms then returns .full" {
    const Q = BoundedMailbox(u64, 1, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    try testing.expectEqual(Q.PushResult.ok, q.pushTimeout(1, 0));

    var t = try std.time.Timer.start();
    const result = q.pushTimeout(2, 50);
    const elapsed = t.read();

    try testing.expectEqual(Q.PushResult.full, result);
    try testing.expect(elapsed >= 40 * ns_per_ms);
    try testing.expect(elapsed < 400 * ns_per_ms);
}

const ShutdownProbe = struct {
    queue: *BoundedMailbox(u64, 1, 0),
    done: std.atomic.Value(bool),
    result: std.atomic.Value(u32),

    fn run(self: *ShutdownProbe) void {
        const r = self.queue.pushUntilShutdown(99, &never_signal);
        self.result.store(@intFromEnum(r), .release);
        self.done.store(true, .release);
    }
};

test "pushUntilShutdown blocks until shutdown(), then returns .shutdown" {
    const Q = BoundedMailbox(u64, 1, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    try testing.expectEqual(Q.PushResult.ok, q.pushTimeout(1, 0));

    var probe: ShutdownProbe = .{
        .queue = q,
        .done = .init(false),
        .result = .init(255),
    };

    var thread = try std.Thread.spawn(.{}, ShutdownProbe.run, .{&probe});

    // Verify the producer is parked.
    std.Thread.sleep(150 * ns_per_ms);
    try testing.expect(!probe.done.load(.acquire));

    q.shutdown();

    // Bounded join.
    const deadline_ns: u64 = 2 * std.time.ns_per_s;
    var waited: u64 = 0;
    while (!probe.done.load(.acquire) and waited < deadline_ns) {
        std.Thread.sleep(5 * ns_per_ms);
        waited += 5 * ns_per_ms;
    }
    try testing.expect(probe.done.load(.acquire));
    thread.join();

    try testing.expectEqual(
        @intFromEnum(PushResultEnum.shutdown),
        probe.result.load(.acquire),
    );
}

test "shutdown() short-circuits subsequent push" {
    const Q = BoundedMailbox(u64, 4, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    try testing.expectEqual(Q.PushResult.ok, q.push(1));
    q.shutdown();

    try testing.expectEqual(Q.PushResult.shutdown, q.push(2));
    try testing.expectEqual(Q.PushResult.shutdown, q.pushTimeout(3, 100));
    try testing.expectEqual(
        Q.PushResult.shutdown,
        q.pushUntilShutdown(4, &never_signal),
    );
}

test "shutdown() drains remaining items before returning .shutdown on pop" {
    const Q = BoundedMailbox(u64, 4, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    try testing.expectEqual(Q.PushResult.ok, q.push(1));
    try testing.expectEqual(Q.PushResult.ok, q.push(2));
    q.shutdown();

    switch (q.pop()) {
        .value => |v| try testing.expectEqual(@as(u64, 1), v),
        else => try testing.expect(false),
    }
    switch (q.pop()) {
        .value => |v| try testing.expectEqual(@as(u64, 2), v),
        else => try testing.expect(false),
    }
    try testing.expect(q.pop() == .shutdown);
}

test "popOrNull returns null for empty and shutdown" {
    const Q = BoundedMailbox(u64, 4, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    try testing.expect(q.popOrNull() == null);

    try testing.expectEqual(Q.PushResult.ok, q.push(7));
    try testing.expectEqual(@as(u64, 7), q.popOrNull().?);
    try testing.expect(q.popOrNull() == null);

    q.shutdown();
    try testing.expect(q.popOrNull() == null);
}

test "popTimeout times out cleanly" {
    const Q = BoundedMailbox(u64, 4, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    var t = try std.time.Timer.start();
    const r = q.popTimeout(50);
    const elapsed = t.read();

    try testing.expect(r == .empty);
    try testing.expect(elapsed >= 40 * ns_per_ms);
    try testing.expect(elapsed < 400 * ns_per_ms);
}

test "popTimeout returns value if pushed mid-wait" {
    const Q = BoundedMailbox(u64, 4, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    const Producer = struct {
        fn run(qq: *Q) void {
            std.Thread.sleep(50 * ns_per_ms);
            _ = qq.push(42);
        }
    };

    var thread = try std.Thread.spawn(.{}, Producer.run, .{q});
    defer thread.join();

    const r = q.popTimeout(500);
    switch (r) {
        .value => |v| try testing.expectEqual(@as(u64, 42), v),
        else => try testing.expect(false),
    }
}

test "drain iterator empties queue" {
    const Q = BoundedMailbox(u64, 4, 0);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    try testing.expectEqual(Q.PushResult.ok, q.push(1));
    try testing.expectEqual(Q.PushResult.ok, q.push(2));
    try testing.expectEqual(Q.PushResult.ok, q.push(3));

    var it = q.drain();
    try testing.expectEqual(@as(?u64, 1), it.next());
    try testing.expectEqual(@as(?u64, 2), it.next());
    try testing.expectEqual(@as(?u64, 3), it.next());
    try testing.expect(it.next() == null);
    it.deinit();

    try testing.expect(q.pop() == .empty);
}

test "PushResult is exhaustively switchable" {
    const r: PushResultEnum = .ok;
    const tag: u8 = switch (r) {
        .ok => 0,
        .full => 1,
        .shutdown => 2,
    };
    try testing.expectEqual(@as(u8, 0), tag);
}

// -------------------------------------------------------------------------
// Compile-time guarantee tests (#232 §2 design point 2)
//
// `default_timeout_ms == null` is intended to make `push()` a compile
// error. We can't directly @compileError-test inside the test runner
// (the error fires at the call site, not inside an `expectError`), but
// we can:
//   - reference the type to prove it instantiates,
//   - use `pushTimeout` to confirm the queue still works without a
//     baked SLO, and
//   - verify via a comptime block that `DefaultTimeoutMs` is `null`.
// The actual @compileError on `push()` is exercised by the
// `compile_error_demo` test below which is *commented out*; uncomment
// to manually verify the compile error fires.
// -------------------------------------------------------------------------

test "default_timeout_ms = null compiles, pushTimeout works" {
    const Q = BoundedMailbox(u64, 2, null);
    const q = try Q.create(testing.allocator);
    defer q.destroy(testing.allocator);

    comptime try testing.expectEqual(@as(?u32, null), Q.DefaultTimeoutMs);

    try testing.expectEqual(Q.PushResult.ok, q.pushTimeout(1, 0));
    try testing.expectEqual(Q.PushResult.ok, q.pushTimeout(2, 0));
    try testing.expectEqual(Q.PushResult.full, q.pushTimeout(3, 0));
}

test "compile-time .forever variant does not exist (#232 structural guarantee)" {
    // The defining property of BoundedMailbox is that there is no
    // `.forever` variant to mistype. We prove this two ways:
    //
    // 1) `Q.PushResult` enumerates exactly {ok, full, shutdown}; no
    //    `.forever` tag exists, so a caller writing `Q.PushResult.forever`
    //    is a compile error.
    // 2) `pushTimeout`'s second argument is `u32`, not a tagged union; a
    //    caller writing `q.pushTimeout(.., .{ .forever = {} })` is a
    //    compile error (struct literal not assignable to u32).
    //
    // Both of these are observed below at comptime. If a future refactor
    // re-adds a `.forever`-shaped escape hatch, these comptime asserts
    // will still pass (you can have e.g. an enum field) but the migration
    // strategy in §4 of the design doc will break in code review.

    const Q = BoundedMailbox(u64, 2, 0);

    // 1. PushResult tag count is exactly 3.
    comptime {
        const tags = @typeInfo(Q.PushResult).@"enum".fields;
        if (tags.len != 3) @compileError("PushResult must be 3-state");
        var has_ok = false;
        var has_full = false;
        var has_shutdown = false;
        for (tags) |f| {
            if (std.mem.eql(u8, f.name, "ok")) has_ok = true;
            if (std.mem.eql(u8, f.name, "full")) has_full = true;
            if (std.mem.eql(u8, f.name, "shutdown")) has_shutdown = true;
            if (std.mem.eql(u8, f.name, "forever"))
                @compileError("BoundedMailbox.PushResult must NOT have a .forever variant (#232)");
        }
        if (!has_ok or !has_full or !has_shutdown)
            @compileError("PushResult must contain {ok, full, shutdown}");
    }

    // 2. pushTimeout's timeout argument is a u32, not a tagged union.
    comptime {
        const Fn = @TypeOf(Q.pushTimeout);
        const fn_info = @typeInfo(Fn).@"fn";
        // (self: *Self, value: T, timeout_ms: u32) PushResult
        if (fn_info.params.len != 3)
            @compileError("pushTimeout signature changed");
        const timeout_arg = fn_info.params[2].type.?;
        if (timeout_arg != u32)
            @compileError("pushTimeout timeout arg must be u32 (no .forever variant)");
    }
}

// To verify the compile-time guarantee experientially, uncomment this
// test and run `zig test src/apprt/winui3/safe_mailbox.zig`. It MUST
// fail with `BoundedMailbox(T, N, null).push() is unbounded — ...`.
//
// Leaving this active by default would prevent the file from compiling,
// which is exactly the contract — so we ship it commented and rely on
// reviewers to flip it as a one-off check.
//
// test "compile_error_demo: push() on null-default mailbox is a compile error" {
//     const Q = BoundedMailbox(u64, 2, null);
//     const q = try Q.create(testing.allocator);
//     defer q.destroy(testing.allocator);
//     _ = q.push(1); // <-- @compileError fires here
// }
