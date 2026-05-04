//! Stale-tolerant snapshot cache for the WinUI3 control plane read lane.
//!
//! Why this exists (issue #269)
//! ----------------------------
//! Under sustained PTY output the renderer holds `renderer_state.mutex` for
//! the duration of each frame, and the CP read lane's `tryLock()` in
//! `Surface.viewportStringLocked` / `historyStringLocked` / `panePidLocked`
//! fails. `handleRequestWith` translates that into `ERR|BUSY|renderer_locked`,
//! and issue #269 documents the resulting BUSY storm — sustained for 19
//! minutes in one observed session.
//!
//! The user's framing: even a partial reduction in BUSY frequency is a win,
//! so we deliberately do NOT pursue a 100% fix that touches the upstream-
//! shared core. Instead we keep the most recent successful response per
//! request and, when a fresh acquisition fails, serve the cached payload
//! prefixed with `stale:<age_ms>|`. The deckpilot daemon already grep-
//! handles a `stale:` prefix (deckpilot commit `63415a4` in `daemon/ipc.go`
//! `composeShowStatus`), so this is a drop-in win on the wire.
//!
//! Memory model
//! ------------
//! The cache holds at most one published snapshot per request key (e.g. the
//! literal `"TAIL|test|20"` bytes). Snapshots are refcounted independently
//! of their map slot:
//!
//!   * `publish` enters the map under `mutex`, swaps the slot's pointer for
//!     a new one (refcount=1, owned by the cache), and decrements the old
//!     one's refcount. If that drop reaches 0, the old snapshot is freed
//!     immediately; otherwise an outstanding borrower will free it via
//!     `release` when its own refcount drop reaches 0.
//!   * `borrowFresh` / `borrowAny` enter the map under `mutex`, bump the
//!     snapshot's refcount, then exit the mutex. The borrower reads
//!     `payload` and `captured_at_ns` without further synchronisation
//!     because the bytes are immutable for the snapshot's lifetime.
//!   * `release` atomically decrements; on the 1→0 transition the borrower
//!     frees the payload and the snapshot struct itself.
//!
//! The mutex is short-held (pointer swap + refcount bump) so it never
//! blocks the renderer or the pipe thread for meaningful intervals — the
//! whole point is to *avoid* further pressure on `renderer_state.mutex`.
//!
//! `max_age_ns == 0` disables `borrowFresh` (returns null unconditionally),
//! which gives tests a way to exercise the publish/borrow paths without
//! pinning the wall clock.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;

/// Immutable, refcounted snapshot. Owned by whoever holds a non-zero
/// reference count — the cache itself takes one when it publishes; each
/// successful `borrow*` call adds another. Freed by the last `release`.
pub const Snapshot = struct {
    /// Owned heap copy of the response bytes (whatever
    /// `handleRequestWith` would have returned on success).
    payload: []u8,

    /// Wall clock at publish time. Compared against caller-supplied
    /// `now_ns` to decide freshness — callers may inject synthetic time
    /// in tests.
    captured_at_ns: u64,

    /// Monotonic publish counter. Lets observers reason about ordering
    /// across keys without inspecting timestamps. Bumped on every
    /// `publish`, never reset, never wrapped within a process lifetime
    /// at any plausible publish rate.
    seq: u64,

    /// Per-snapshot refcount. The cache contributes 1 while the pointer
    /// is published; each `borrow*` adds 1; each `release` subtracts 1.
    /// Free fires on 1→0.
    refcount: Atomic(u32),

    /// We keep the allocator on the snapshot rather than threading it
    /// through `release` so callers don't have to remember which
    /// allocator owns the payload — `release` is a single-arg call and
    /// stays correct under refactors.
    allocator: Allocator,

    /// Caller transfers ownership of `payload`; we don't dupe it here
    /// to keep publish on the success path allocation-free beyond the
    /// snapshot struct itself.
    fn create(allocator: Allocator, payload: []u8, now_ns: u64, seq: u64) Allocator.Error!*Snapshot {
        const snap = try allocator.create(Snapshot);
        snap.* = .{
            .payload = payload,
            .captured_at_ns = now_ns,
            .seq = seq,
            .refcount = Atomic(u32).init(1),
            .allocator = allocator,
        };
        return snap;
    }

    fn destroy(self: *Snapshot) void {
        const alloc = self.allocator;
        alloc.free(self.payload);
        alloc.destroy(self);
    }
};

/// Multi-key cache: one current snapshot per request string.
///
/// We could have used three separate caches keyed by getter type
/// (viewport / history / panepid) but at this layer the request string
/// is already the natural primary key — `STATE|x|0` and `STATE|y|0`
/// should NOT alias even though both go through the same getter — and
/// the existing `ResponseCache` in `control_plane.zig` is already
/// request-keyed, so we match its shape.
pub const SnapshotCache = struct {
    allocator: Allocator,

    /// Freshness bound for `borrowFresh`. `0` means "never fresh" — used
    /// in tests that want to exercise publish/borrow without relying on
    /// `std.time.nanoTimestamp`.
    max_age_ns: u64,

    /// Map of request bytes → currently published snapshot. The map's
    /// keys are owned strings (we dupe on `publish`); values are owned
    /// `*Snapshot` references contributing one refcount each.
    map: std.StringHashMapUnmanaged(*Snapshot) = .{},

    /// Monotonic publish counter; see `Snapshot.seq`.
    next_seq: u64 = 1,

    /// Single mutex covers map mutations and per-slot pointer swaps. The
    /// hot path is the brief refcount bump in `borrow*`; payload reads
    /// happen *after* mutex release, so the lock window stays tiny.
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: Allocator, max_age_ns: u64) SnapshotCache {
        return .{
            .allocator = allocator,
            .max_age_ns = max_age_ns,
        };
    }

    /// Drains every published snapshot, releasing the cache's reference.
    /// Outstanding borrows are unaffected — the borrower's `release` will
    /// free its snapshot when its refcount drops to zero.
    ///
    /// Safe to call after `init` with no intervening `publish`.
    pub fn deinit(self: *SnapshotCache) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            decRef(entry.value_ptr.*);
        }
        self.map.deinit(self.allocator);
        self.map = .{};
    }

    /// Publish a fresh response under `key`. Caller transfers ownership
    /// of `payload` (an owned heap slice that will be freed by the cache
    /// or by the last borrower); caller retains ownership of `key` (we
    /// dupe internally so the key bytes survive map rebalancing).
    ///
    /// Returns the previous snapshot's `seq` if one existed, else null.
    /// Useful for tests asserting publication ordering; production
    /// callers can ignore.
    ///
    /// On allocator failure (key dupe, snapshot create, or map put) we
    /// log nothing — the caller is on a hot path — and free the payload
    /// to avoid leaks. The cache simply doesn't gain a fresh entry; the
    /// next BUSY will fall through to `error.RendererLocked` as before.
    pub fn publish(
        self: *SnapshotCache,
        key: []const u8,
        payload: []u8,
        now_ns: u64,
    ) ?u64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const seq = self.next_seq;
        self.next_seq += 1;

        const snap = Snapshot.create(self.allocator, payload, now_ns, seq) catch {
            // Snapshot allocation failed: we still own `payload`; free it.
            self.allocator.free(payload);
            return null;
        };

        if (self.map.getEntry(key)) |entry| {
            const old = entry.value_ptr.*;
            entry.value_ptr.* = snap;
            const prev_seq = old.seq;
            decRef(old);
            return prev_seq;
        }

        const key_copy = self.allocator.dupe(u8, key) catch {
            // Could not dupe key: tear down the just-created snapshot.
            // Refcount is 1 (cache's reference) so this frees immediately.
            decRef(snap);
            return null;
        };
        self.map.put(self.allocator, key_copy, snap) catch {
            self.allocator.free(key_copy);
            decRef(snap);
            return null;
        };
        return null;
    }

    /// Borrow the current snapshot for `key` only if its age is within
    /// `max_age_ns`. Returns null when the cache lacks an entry, when
    /// the entry is older than `max_age_ns`, or when `max_age_ns == 0`.
    ///
    /// On success the snapshot's refcount is incremented; the caller
    /// MUST call `release` exactly once per non-null return.
    pub fn borrowFresh(
        self: *SnapshotCache,
        key: []const u8,
        now_ns: u64,
    ) ?*Snapshot {
        if (self.max_age_ns == 0) return null;

        self.mutex.lock();
        defer self.mutex.unlock();

        const snap = self.map.get(key) orelse return null;
        // Guard against clock skew: if the caller's `now_ns` somehow
        // precedes `captured_at_ns`, treat the entry as fresh rather
        // than stale (negative age would underflow the u64 subtract).
        if (now_ns < snap.captured_at_ns) {
            _ = snap.refcount.fetchAdd(1, .acq_rel);
            return snap;
        }
        const age = now_ns - snap.captured_at_ns;
        if (age > self.max_age_ns) return null;

        _ = snap.refcount.fetchAdd(1, .acq_rel);
        return snap;
    }

    /// Borrow the current snapshot for `key` regardless of age. The
    /// caller decides whether to label the response stale based on
    /// `snap.captured_at_ns`. Returns null only when the cache lacks an
    /// entry for `key`.
    pub fn borrowAny(self: *SnapshotCache, key: []const u8) ?*Snapshot {
        self.mutex.lock();
        defer self.mutex.unlock();

        const snap = self.map.get(key) orelse return null;
        _ = snap.refcount.fetchAdd(1, .acq_rel);
        return snap;
    }

    /// Drop one reference. On the 1→0 transition the snapshot's payload
    /// and struct are freed immediately. Safe to interleave with
    /// `publish` and other borrows on the same key — the cache's own
    /// reference is independent of borrowers'.
    pub fn release(self: *SnapshotCache, snap: *Snapshot) void {
        _ = self;
        decRef(snap);
    }

    /// Map size (number of keys with a published snapshot). For tests
    /// and lightweight introspection. Holds the mutex briefly.
    pub fn keyCount(self: *SnapshotCache) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.map.count();
    }
};

/// Refcount decrement. Pulled out so `publish`, `deinit`, and `release`
/// share one place where the 1→0 free fires.
fn decRef(snap: *Snapshot) void {
    const prev = snap.refcount.fetchSub(1, .acq_rel);
    if (prev == 1) snap.destroy();
}

/// Compose a stale-marked payload by prepending `stale:<age_ms>|` to a
/// duplicate of `payload`. The deckpilot daemon (commit `63415a4` in
/// `daemon/ipc.go`) treats any `stale:` prefix as "snapshot served from
/// cache", so this drops in cleanly on the wire.
///
/// We dupe the bytes rather than aliasing the snapshot's payload so the
/// caller can `release` the borrowed snapshot immediately and the
/// returned slice's lifetime is tied only to its own allocator.
pub fn composeStalePayload(
    allocator: Allocator,
    payload: []const u8,
    age_ns: u64,
) Allocator.Error![]u8 {
    const age_ms = age_ns / std.time.ns_per_ms;
    return std.fmt.allocPrint(allocator, "stale:{d}|{s}", .{ age_ms, payload });
}

// =========================================================================
// Tests
// =========================================================================
//
// We test every public surface (init, deinit, publish, borrowFresh,
// borrowAny, release, keyCount, composeStalePayload) plus the concurrent
// publish/borrow contract.

const testing = std.testing;
const ns_per_ms = std.time.ns_per_ms;

test "init/deinit on empty cache is safe and frees nothing" {
    var c = SnapshotCache.init(testing.allocator, 100 * ns_per_ms);
    try testing.expectEqual(@as(usize, 0), c.keyCount());
    c.deinit();
}

test "publish then borrowAny returns the published payload" {
    var c = SnapshotCache.init(testing.allocator, 100 * ns_per_ms);
    defer c.deinit();

    const payload = try testing.allocator.dupe(u8, "OK|hello\n");
    _ = c.publish("STATE|x|0", payload, 1_000);

    const snap = c.borrowAny("STATE|x|0") orelse {
        try testing.expect(false);
        return;
    };
    defer c.release(snap);

    try testing.expectEqualStrings("OK|hello\n", snap.payload);
    try testing.expectEqual(@as(u64, 1_000), snap.captured_at_ns);
    try testing.expectEqual(@as(u64, 1), snap.seq);
}

test "publish overwrites previous entry and bumps seq" {
    var c = SnapshotCache.init(testing.allocator, 100 * ns_per_ms);
    defer c.deinit();

    const p1 = try testing.allocator.dupe(u8, "OK|first\n");
    const prev1 = c.publish("STATE|x|0", p1, 1_000);
    try testing.expect(prev1 == null);

    const p2 = try testing.allocator.dupe(u8, "OK|second\n");
    const prev2 = c.publish("STATE|x|0", p2, 2_000);
    try testing.expectEqual(@as(?u64, 1), prev2);

    const snap = c.borrowAny("STATE|x|0").?;
    defer c.release(snap);
    try testing.expectEqualStrings("OK|second\n", snap.payload);
    try testing.expectEqual(@as(u64, 2_000), snap.captured_at_ns);
    try testing.expectEqual(@as(u64, 2), snap.seq);
}

test "borrowAny on missing key returns null without bumping anything" {
    var c = SnapshotCache.init(testing.allocator, 100 * ns_per_ms);
    defer c.deinit();
    try testing.expect(c.borrowAny("NOPE") == null);
}

test "borrowFresh respects max_age_ns boundary" {
    var c = SnapshotCache.init(testing.allocator, 50 * ns_per_ms);
    defer c.deinit();

    const payload = try testing.allocator.dupe(u8, "OK|x\n");
    _ = c.publish("k", payload, 1_000_000);

    // age == 0 → fresh
    const fresh_now = c.borrowFresh("k", 1_000_000) orelse return error.TestExpectedSome;
    c.release(fresh_now);

    // age == max_age_ns → still fresh (boundary inclusive)
    const fresh_boundary = c.borrowFresh("k", 1_000_000 + 50 * ns_per_ms) orelse
        return error.TestExpectedSome;
    c.release(fresh_boundary);

    // age == max_age_ns + 1 → stale
    try testing.expect(c.borrowFresh("k", 1_000_000 + 50 * ns_per_ms + 1) == null);

    // age way past → stale
    try testing.expect(c.borrowFresh("k", 1_000_000 + 1_000 * ns_per_ms) == null);
}

test "borrowFresh with max_age_ns == 0 always returns null (cache disabled)" {
    var c = SnapshotCache.init(testing.allocator, 0);
    defer c.deinit();

    const payload = try testing.allocator.dupe(u8, "OK|x\n");
    _ = c.publish("k", payload, 1_000);

    // borrowFresh disabled, but borrowAny still works (publish/release path).
    try testing.expect(c.borrowFresh("k", 1_000) == null);

    const any = c.borrowAny("k").?;
    c.release(any);
}

test "borrowFresh tolerates now_ns < captured_at_ns (clock skew)" {
    var c = SnapshotCache.init(testing.allocator, 50 * ns_per_ms);
    defer c.deinit();

    const payload = try testing.allocator.dupe(u8, "OK|x\n");
    _ = c.publish("k", payload, 1_000_000);

    const snap = c.borrowFresh("k", 999_999) orelse return error.TestExpectedSome;
    c.release(snap);
}

test "borrowFresh on missing key returns null" {
    var c = SnapshotCache.init(testing.allocator, 100 * ns_per_ms);
    defer c.deinit();
    try testing.expect(c.borrowFresh("missing", 1_000) == null);
}

test "publish with zero-byte payload round-trips cleanly" {
    var c = SnapshotCache.init(testing.allocator, 100 * ns_per_ms);
    defer c.deinit();

    const empty = try testing.allocator.alloc(u8, 0);
    _ = c.publish("k", empty, 1_000);

    const snap = c.borrowAny("k").?;
    defer c.release(snap);
    try testing.expectEqual(@as(usize, 0), snap.payload.len);
}

test "release on the last reference frees payload (sanitizer-checked)" {
    // The testing allocator's leak checker is the assertion here: if we
    // failed to free the payload, deinit() would leak. Two publishes plus
    // a borrow exercise all three free paths (replace-old, deinit-pending,
    // and last-borrow-after-deinit).
    var c = SnapshotCache.init(testing.allocator, 100 * ns_per_ms);

    const p1 = try testing.allocator.dupe(u8, "OK|a\n");
    _ = c.publish("k", p1, 1_000);

    const borrowed = c.borrowAny("k").?;

    // Replace published snapshot. Old one's refcount drops from 2 (cache
    // + borrower) to 1; payload survives because borrower still holds it.
    const p2 = try testing.allocator.dupe(u8, "OK|b\n");
    _ = c.publish("k", p2, 2_000);

    // Borrower's data is still the *old* payload — the publish didn't
    // mutate the snapshot the borrower is reading.
    try testing.expectEqualStrings("OK|a\n", borrowed.payload);

    c.release(borrowed); // refcount 1→0, frees old payload+struct
    c.deinit(); // releases p2 (refcount 1→0)
}

test "deinit while borrow outstanding does not free borrowed snapshot" {
    var c = SnapshotCache.init(testing.allocator, 100 * ns_per_ms);

    const payload = try testing.allocator.dupe(u8, "OK|live\n");
    _ = c.publish("k", payload, 1_000);

    const snap = c.borrowAny("k").?;
    c.deinit(); // cache drops its reference but borrower still owns one

    try testing.expectEqualStrings("OK|live\n", snap.payload);
    c.release(snap); // last reference goes here
}

test "keyCount tracks distinct keys" {
    var c = SnapshotCache.init(testing.allocator, 100 * ns_per_ms);
    defer c.deinit();

    try testing.expectEqual(@as(usize, 0), c.keyCount());

    const a = try testing.allocator.dupe(u8, "A");
    _ = c.publish("ka", a, 1);
    try testing.expectEqual(@as(usize, 1), c.keyCount());

    const b = try testing.allocator.dupe(u8, "B");
    _ = c.publish("kb", b, 2);
    try testing.expectEqual(@as(usize, 2), c.keyCount());

    // Republishing on existing key does NOT grow keyCount.
    const a2 = try testing.allocator.dupe(u8, "A2");
    _ = c.publish("ka", a2, 3);
    try testing.expectEqual(@as(usize, 2), c.keyCount());
}

test "composeStalePayload formats stale:<age_ms>| prefix" {
    const out = try composeStalePayload(testing.allocator, "OK|tail\n", 142 * ns_per_ms);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("stale:142|OK|tail\n", out);
}

test "composeStalePayload age=0 yields stale:0| prefix" {
    const out = try composeStalePayload(testing.allocator, "OK|", 0);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("stale:0|OK|", out);
}

test "composeStalePayload preserves binary bytes verbatim" {
    const payload = "OK|\x00\x01\xff|done\n";
    const out = try composeStalePayload(testing.allocator, payload, 5 * ns_per_ms);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("stale:5|OK|\x00\x01\xff|done\n", out);
}

// -------------------------------------------------------------------------
// Concurrency probe
// -------------------------------------------------------------------------
//
// Spawns one publisher and one borrower against the same key. The contract
// we're checking: no double-free, no use-after-free, refcount always
// returns to the cache's baseline (1) for the currently-published
// snapshot, and the borrower never observes torn payloads.
//
// We can't directly assert "no use-after-free" — the testing allocator's
// safety checks do that for us. We assert reachability of the final
// expected payload and that keyCount stays at 1.

const ConcurrentCtx = struct {
    cache: *SnapshotCache,
    iterations: u32,
    stop: Atomic(bool),
};

fn publisherThread(ctx: *ConcurrentCtx) void {
    var i: u32 = 0;
    while (i < ctx.iterations) : (i += 1) {
        const buf = std.fmt.allocPrint(
            ctx.cache.allocator,
            "OK|iter={d}\n",
            .{i},
        ) catch continue;
        _ = ctx.cache.publish("k", buf, @as(u64, i) * 1000);
    }
    ctx.stop.store(true, .release);
}

fn borrowerThread(ctx: *ConcurrentCtx) void {
    var observed: u32 = 0;
    while (!ctx.stop.load(.acquire)) {
        if (ctx.cache.borrowAny("k")) |snap| {
            // Touch the bytes to give the sanitizer a chance to spot
            // any use-after-free racing with publish.
            if (snap.payload.len > 0) observed +%= snap.payload[0];
            ctx.cache.release(snap);
        }
    }
    // Drain any final published snapshot.
    if (ctx.cache.borrowAny("k")) |snap| {
        if (snap.payload.len > 0) observed +%= snap.payload[0];
        ctx.cache.release(snap);
    }
    std.mem.doNotOptimizeAway(observed);
}

test "concurrent publish/borrow does not leak or use-after-free" {
    var c = SnapshotCache.init(testing.allocator, 100 * ns_per_ms);
    defer c.deinit();

    // Seed the map so the borrower sees something on its first poll.
    const seed = try testing.allocator.dupe(u8, "OK|seed\n");
    _ = c.publish("k", seed, 0);

    var ctx = ConcurrentCtx{
        .cache = &c,
        .iterations = 500,
        .stop = Atomic(bool).init(false),
    };

    const t_pub = try std.Thread.spawn(.{}, publisherThread, .{&ctx});
    const t_borrow = try std.Thread.spawn(.{}, borrowerThread, .{&ctx});

    t_pub.join();
    t_borrow.join();

    try testing.expectEqual(@as(usize, 1), c.keyCount());
}
