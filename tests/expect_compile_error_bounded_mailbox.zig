//! Negative compile test for `BoundedMailbox(T, N, null).push()`.
//!
//! This file MUST FAIL to compile. The failure proves the Phase 2 §2
//! design point 2 contract: a mailbox declared with
//! `default_timeout_ms = null` cannot accept a one-arg `.push()` — the
//! caller must spell their SLO via `pushTimeout(value, ms)`.
//!
//! How to verify
//! -------------
//! From repo root, run:
//!
//!     zig build-obj tests/expect_compile_error_bounded_mailbox.zig \
//!         --dep bounded_mailbox \
//!         -Mroot=tests/expect_compile_error_bounded_mailbox.zig \
//!         -Mbounded_mailbox=src/datastruct/bounded_mailbox.zig
//!
//! Expected output (the @compileError text from bounded_mailbox.zig):
//!
//!     error: BoundedMailbox(T, N, null).push() is unbounded — use
//!     pushTimeout(value, ms) to spell your SLO at the callsite, or
//!     declare the type with a default_timeout_ms to bake the SLO at
//!     the type.
//!
//! If this file *successfully* compiles, the type-level guarantee is
//! broken and #218 can recur in any code path that picks the wrong
//! `push()` overload.

const bounded_mailbox = @import("bounded_mailbox");

export fn try_to_push_without_bound() void {
    const Q = bounded_mailbox.BoundedMailbox(u64, 2, null);
    var q: Q = .{};
    _ = q.push(1); // <-- @compileError must fire here
}
