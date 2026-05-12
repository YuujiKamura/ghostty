//! Pure-logic functions extracted from App.zig / Surface.zig for TSF IME handling.
//! These are free of COM / WinUI3 dependencies and can be unit-tested standalone.

const std = @import("std");

// ---------------------------------------------------------------
// UTF-8 → codepoint decode + UTF-16 emission
// ---------------------------------------------------------------

/// Decode a UTF-8 byte slice into codepoints, calling `emit_fn` for each
/// UTF-16 code unit (surrogate pairs produce two calls).
/// Returns the number of *codepoints* successfully decoded.
pub fn decodeAndEmitUtf16(utf8: []const u8, emit_fn: *const fn (u16) void) usize {
    var i: usize = 0;
    var count: usize = 0;
    while (i < utf8.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(utf8[i]) catch {
            i += 1; // skip bad lead byte
            continue;
        };
        if (i + cp_len > utf8.len) break; // truncated sequence
        const codepoint = std.unicode.utf8Decode(utf8[i..][0..cp_len]) catch {
            i += cp_len;
            continue;
        };
        if (codepoint <= 0xFFFF) {
            emit_fn(@intCast(codepoint));
        } else {
            // Surrogate pair for supplementary planes.
            const high: u16 = @intCast(((codepoint - 0x10000) >> 10) + 0xD800);
            const low: u16 = @intCast(((codepoint - 0x10000) & 0x3FF) + 0xDC00);
            emit_fn(high);
            emit_fn(low);
        }
        count += 1;
        i += cp_len;
    }
    return count;
}

/// Above this age (ms), a `tsf_just_committed_at_ms` timestamp is treated
/// as stale: the duplicate WM_CHAR we would have suppressed must have
/// arrived in the same Win32 message-pump cycle as the TSF commit, so a
/// gap exceeding 100ms almost certainly means CharacterReceived was
/// never going to fire for that commit (e.g. focus moved away or the
/// user just paused) and a later unrelated char would otherwise be
/// silently swallowed.
pub const STALE_COMMIT_THRESHOLD_MS: i64 = 100;

/// After TSF commits text, the same finalized non-ASCII characters may
/// also arrive via CharacterReceived (WM_CHAR). To deduplicate, callers
/// set `tsf_just_committed_at_ms` to a fresh timestamp at commit time;
/// the first CharacterReceived after the commit then consumes the flag
/// and, if non-ASCII, is suppressed.
///
/// The flag is consumed (set to 0) on every call, regardless of whether
/// the event is suppressed. If the timestamp is 0 (never set) or older
/// than `threshold_ms` (stale, e.g. the user paused before typing the
/// next char), this function returns `false` so the incoming char is
/// processed normally — preventing the "first Japanese char dropped
/// after a stale commit" bug observed via mobile/remote input bridges.
///
/// Pure -- the caller supplies `now_ms` so tests do not need a real clock.
pub fn shouldSuppressCharAfterCommit(
    tsf_just_committed_at_ms: *i64,
    now_ms: i64,
    char_code: u16,
    threshold_ms: i64,
) bool {
    const at_ms = tsf_just_committed_at_ms.*;
    tsf_just_committed_at_ms.* = 0; // always consume the flag
    if (at_ms == 0) return false; // never set
    if (now_ms - at_ms > threshold_ms) return false; // stale
    return char_code > 0x7F;
}

// ===================================================================
// Tests
// ===================================================================

// Thread-local storage for test emit callback.
threadlocal var test_emit_buf: [32]u16 = undefined;
threadlocal var test_emit_count: usize = 0;

fn testEmit(code_unit: u16) void {
    if (test_emit_count < test_emit_buf.len) {
        test_emit_buf[test_emit_count] = code_unit;
    }
    test_emit_count += 1;
}

fn resetTestEmit() void {
    test_emit_count = 0;
    test_emit_buf = .{0} ** 32;
}

// ---------------------------------------------------------------
// decodeAndEmitUtf16 tests
// ---------------------------------------------------------------

test "decodeAndEmitUtf16 - Japanese テスト (3 codepoints)" {
    resetTestEmit();
    // テスト = U+30C6 U+30B9 U+30C8
    // UTF-8: E3 83 86  E3 82 B9  E3 83 88
    const count = decodeAndEmitUtf16("テスト", &testEmit);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(usize, 3), test_emit_count); // all BMP → 3 code units
    try std.testing.expectEqual(@as(u16, 0x30C6), test_emit_buf[0]); // テ
    try std.testing.expectEqual(@as(u16, 0x30B9), test_emit_buf[1]); // ス
    try std.testing.expectEqual(@as(u16, 0x30C8), test_emit_buf[2]); // ト
}

test "decodeAndEmitUtf16 - ASCII passthrough" {
    resetTestEmit();
    const count = decodeAndEmitUtf16("Hi", &testEmit);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(@as(u16, 'H'), test_emit_buf[0]);
    try std.testing.expectEqual(@as(u16, 'i'), test_emit_buf[1]);
}

test "decodeAndEmitUtf16 - surrogate pair emoji U+1F600" {
    resetTestEmit();
    // U+1F600 = F0 9F 98 80
    const count = decodeAndEmitUtf16("\xF0\x9F\x98\x80", &testEmit);
    try std.testing.expectEqual(@as(usize, 1), count); // 1 codepoint
    try std.testing.expectEqual(@as(usize, 2), test_emit_count); // 2 UTF-16 code units
    // High surrogate: ((0x1F600 - 0x10000) >> 10) + 0xD800 = 0xD83D
    try std.testing.expectEqual(@as(u16, 0xD83D), test_emit_buf[0]);
    // Low surrogate: ((0x1F600 - 0x10000) & 0x3FF) + 0xDC00 = 0xDE00
    try std.testing.expectEqual(@as(u16, 0xDE00), test_emit_buf[1]);
}

test "decodeAndEmitUtf16 - malformed UTF-8 skips bad bytes" {
    resetTestEmit();
    // 0xFF is not a valid UTF-8 lead byte → skip, then 'A'
    const count = decodeAndEmitUtf16(&[_]u8{ 0xFF, 'A' }, &testEmit);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u16, 'A'), test_emit_buf[0]);
}

test "decodeAndEmitUtf16 - truncated multi-byte sequence" {
    resetTestEmit();
    // E3 83 is a truncated 3-byte sequence (missing 3rd byte)
    const count = decodeAndEmitUtf16(&[_]u8{ 0xE3, 0x83 }, &testEmit);
    try std.testing.expectEqual(@as(usize, 0), count);
    try std.testing.expectEqual(@as(usize, 0), test_emit_count);
}

test "decodeAndEmitUtf16 - empty input" {
    resetTestEmit();
    const count = decodeAndEmitUtf16("", &testEmit);
    try std.testing.expectEqual(@as(usize, 0), count);
    try std.testing.expectEqual(@as(usize, 0), test_emit_count);
}

test "shouldSuppressCharAfterCommit - fresh non-ASCII suppressed" {
    var at_ms: i64 = 1000;
    try std.testing.expect(shouldSuppressCharAfterCommit(&at_ms, 1000, 0x30C6, STALE_COMMIT_THRESHOLD_MS)); // テ
    try std.testing.expectEqual(@as(i64, 0), at_ms); // consumed
}

test "shouldSuppressCharAfterCommit - fresh ASCII not suppressed" {
    var at_ms: i64 = 1000;
    try std.testing.expect(!shouldSuppressCharAfterCommit(&at_ms, 1000, 0x41, STALE_COMMIT_THRESHOLD_MS)); // 'A'
    try std.testing.expectEqual(@as(i64, 0), at_ms); // consumed
}

test "shouldSuppressCharAfterCommit - boundary 0x7F not suppressed" {
    var at_ms: i64 = 1000;
    try std.testing.expect(!shouldSuppressCharAfterCommit(&at_ms, 1000, 0x7F, STALE_COMMIT_THRESHOLD_MS)); // DEL
    try std.testing.expectEqual(@as(i64, 0), at_ms);
}

test "shouldSuppressCharAfterCommit - boundary 0x80 suppressed" {
    var at_ms: i64 = 1000;
    try std.testing.expect(shouldSuppressCharAfterCommit(&at_ms, 1000, 0x80, STALE_COMMIT_THRESHOLD_MS));
    try std.testing.expectEqual(@as(i64, 0), at_ms);
}

test "shouldSuppressCharAfterCommit - timestamp 0 (never set), nothing suppressed" {
    var at_ms: i64 = 0;
    try std.testing.expect(!shouldSuppressCharAfterCommit(&at_ms, 1000, 0x30C6, STALE_COMMIT_THRESHOLD_MS));
    try std.testing.expect(!shouldSuppressCharAfterCommit(&at_ms, 1000, 0x41, STALE_COMMIT_THRESHOLD_MS));
    try std.testing.expectEqual(@as(i64, 0), at_ms);
}

test "shouldSuppressCharAfterCommit - stale (>threshold) non-ASCII not suppressed (mobile/remote first-char FIX)" {
    // Issue #123 Fix 4 left tsf_just_committed=true persisting across the
    // gap between a TSF commit and the user's next typing burst from a
    // mobile/remote bridge. With the age check, a >100ms gap demotes the
    // suppression so the first Japanese char from the next burst emits.
    var at_ms: i64 = 1000;
    const now_ms: i64 = 1101; // 101ms later -- past threshold
    try std.testing.expect(!shouldSuppressCharAfterCommit(&at_ms, now_ms, 0x3069, STALE_COMMIT_THRESHOLD_MS)); // ど
    try std.testing.expectEqual(@as(i64, 0), at_ms); // still consumed
}

test "shouldSuppressCharAfterCommit - exactly at threshold (strict >) still suppresses" {
    var at_ms: i64 = 1000;
    const now_ms: i64 = 1100; // exactly 100ms -- still within
    try std.testing.expect(shouldSuppressCharAfterCommit(&at_ms, now_ms, 0x30C6, STALE_COMMIT_THRESHOLD_MS));
    try std.testing.expectEqual(@as(i64, 0), at_ms);
}

test "shouldSuppressCharAfterCommit - 1 second past threshold not suppressed" {
    var at_ms: i64 = 1000;
    try std.testing.expect(!shouldSuppressCharAfterCommit(&at_ms, 2000, 0x30C6, STALE_COMMIT_THRESHOLD_MS));
    try std.testing.expectEqual(@as(i64, 0), at_ms);
}
