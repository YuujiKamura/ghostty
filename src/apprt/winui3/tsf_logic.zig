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

// ---------------------------------------------------------------
// tsf_just_committed state machine
// ---------------------------------------------------------------

/// After TSF commits text, `tsf_just_committed` is true.
/// In PreviewKeyDown, VK_RETURN (0x0D) should be *suppressed* so that
/// the Enter that confirmed the composition doesn't leak a raw newline.
/// Any other key just clears the flag without suppression.
///
/// Returns `true` when the key should be suppressed (i.e. handled = true).
pub fn shouldSuppressAfterCommit(tsf_just_committed: *bool, vk: u32) bool {
    if (tsf_just_committed.* and vk == 0x0D) { // VK_RETURN
        tsf_just_committed.* = false;
        return true;
    }
    tsf_just_committed.* = false;
    return false;
}

/// After TSF commits text, the same characters may also arrive via
/// CharacterReceived (WM_CHAR). Non-ASCII chars should be suppressed
/// while `tsf_just_committed` is true to avoid doubled characters.
///
/// Returns `true` when the character event should be suppressed.
pub fn shouldSuppressCharAfterCommit(tsf_just_committed: bool, char_code: u16) bool {
    return tsf_just_committed and char_code > 0x7F;
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

// ---------------------------------------------------------------
// shouldSuppressAfterCommit tests
// ---------------------------------------------------------------

test "shouldSuppressAfterCommit - VK_RETURN suppressed when flag set" {
    var flag: bool = true;
    try std.testing.expect(shouldSuppressAfterCommit(&flag, 0x0D));
    try std.testing.expect(!flag); // flag cleared
}

test "shouldSuppressAfterCommit - non-Enter clears flag, no suppression" {
    var flag: bool = true;
    try std.testing.expect(!shouldSuppressAfterCommit(&flag, 0x41)); // 'A'
    try std.testing.expect(!flag); // flag still cleared
}

test "shouldSuppressAfterCommit - flag already false, VK_RETURN not suppressed" {
    var flag: bool = false;
    try std.testing.expect(!shouldSuppressAfterCommit(&flag, 0x0D));
    try std.testing.expect(!flag);
}

test "shouldSuppressAfterCommit - flag already false, other key" {
    var flag: bool = false;
    try std.testing.expect(!shouldSuppressAfterCommit(&flag, 0x41));
    try std.testing.expect(!flag);
}

// ---------------------------------------------------------------
// shouldSuppressCharAfterCommit tests
// ---------------------------------------------------------------

test "shouldSuppressCharAfterCommit - non-ASCII suppressed when flag set" {
    try std.testing.expect(shouldSuppressCharAfterCommit(true, 0x30C6)); // テ
}

test "shouldSuppressCharAfterCommit - ASCII not suppressed even when flag set" {
    try std.testing.expect(!shouldSuppressCharAfterCommit(true, 0x41)); // 'A'
}

test "shouldSuppressCharAfterCommit - boundary 0x7F not suppressed" {
    try std.testing.expect(!shouldSuppressCharAfterCommit(true, 0x7F)); // DEL
}

test "shouldSuppressCharAfterCommit - boundary 0x80 suppressed" {
    try std.testing.expect(shouldSuppressCharAfterCommit(true, 0x80));
}

test "shouldSuppressCharAfterCommit - flag false, nothing suppressed" {
    try std.testing.expect(!shouldSuppressCharAfterCommit(false, 0x30C6));
    try std.testing.expect(!shouldSuppressCharAfterCommit(false, 0x41));
}
