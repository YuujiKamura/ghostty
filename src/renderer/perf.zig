//! Cold-start timing instrumentation shared across renderer backends.
//!
//! The apprt sets a wall-clock baseline once at process startup;
//! renderers stamp PERF_INIT lines (e.g. "first Present") relative to
//! that baseline. Owned by the renderer namespace so backends don't
//! reach across into apprt for an unrelated mutable global.
//!
//! Single-writer / multi-reader is intentional: write happens once on
//! the apprt thread before any renderer thread is spawned, reads happen
//! from renderer threads later. No synchronisation primitive is needed
//! because the write strictly happens-before any read via the renderer
//! thread spawn.

const std = @import("std");

/// 0 = "not initialised". Real timestamps from std.time.nanoTimestamp()
/// are wall-clock so practically can never be 0; we exploit that for a
/// cheap "is this set?" check without an extra bool.
var startup_baseline_ns: i128 = 0;

/// Publish the cold-start baseline. Called by the apprt at the very
/// top of its init path. Idempotent — if the apprt re-runs init for any
/// reason, the latest call wins (the metric is only meaningful once
/// per process anyway).
pub fn setStartupBaseline(ns: i128) void {
    startup_baseline_ns = ns;
}

/// Returns elapsed milliseconds since the baseline, or null if no
/// baseline has been set yet (e.g. headless tests, or a renderer that
/// runs without an apprt that publishes one).
pub fn elapsedMsSinceStartup() ?f64 {
    if (startup_baseline_ns == 0) return null;
    const now = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(now - startup_baseline_ns)) / 1_000_000.0;
}
