# [WinUI3] TSF IME composition positioning unstable - coordinates misplaced for some TUI apps

## Problem Description

Japanese IME composition text (preedit) and candidate window positioning is inconsistent across different TUI applications:

- **Gemini CLI**: Composition text appears at bottom-right or center of screen instead of cursor position
- **Claude Code**: Composition text appears relatively correctly inline with cursor
- **Consistent Issue**: IME candidate window often floats in middle of terminal instead of near cursor

## Environment

- **Platform**: Windows 11
- **Ghostty**: WinUI3 implementation  
- **IME**: Japanese IME (tested with multiple IME implementations)
- **Reproduction**: Consistent with Gemini CLI, inconsistent with Claude Code

## Root Cause Analysis

This issue stems from fundamental design conflicts between:

1. **TSF synchronous coordinate requests** (`GetTextExt`) vs **TUI asynchronous cursor updates** (CSI H sequences)
2. **Complex WinUI3 coordinate system transformations**: Terminal → Surface → XAML Islands → Win32 screen coordinates
3. **Rendering cycle race conditions** between cursor position updates and IME coordinate calculations

### Technical Details

**Current coordinate calculation flow** (`tsfGetCursorRect` → `imePoint`):
```
TUI sends CSI H → terminal.cursor updated → TSF calls GetTextExt → 
imePoint() calculates pixels → ClientToScreen(nci.island.hwnd) → return to TSF
```

**Identified race conditions**:
- `cursor` position protected by mutex, but `surface.size` and `content_scale` are not
- `ClientToScreen` uses `nci.island.hwnd` which may not be the correct reference HWND
- Rapid cursor movements by TUI apps can cause stale coordinate calculations

## Implementation Issues

### 1. Coordinate System Complexity
```zig
// Surface.zig:imePoint() - potential race conditions
const content_scale = self.rt_surface.getContentScale() catch .{ .x = 1, .y = 1 };  // unprotected
var x: f64 = @floatFromInt(cursor.x * self.size.cell.width + self.size.padding.left);  // self.size unprotected
```

### 2. HWND Reference Uncertainty
```zig  
// App.zig:tsfGetCursorRect() - using XAML Islands HWND
_ = os.ClientToScreen(hwnd, &pt);  // hwnd = nci.island.hwnd - correct reference?
```

### 3. Missing Debug Visibility
No logging in critical coordinate calculation paths makes debugging difficult.

## Proposed Solution

### Phase 1: Add Comprehensive Debugging (High Priority)

Add detailed logging to coordinate calculation pipeline:

```zig
// In tsfGetCursorRect
log.info("TSF GetTextExt: cursor=({d},{d}) ime_pos=({d:.2},{d:.2}) content_scale=({d:.2},{d:.2}) hwnd=0x{x}", .{
    cursor.x, cursor.y, ime_pos.x, ime_pos.y, content_scale.x, content_scale.y, @intFromPtr(hwnd)
});
```

### Phase 2: Coordinate System Validation (Medium Priority)

1. **Verify HWND reference**: Test if `nci.island.hwnd` is appropriate for `ClientToScreen`
2. **Expand mutex protection**: Include `surface.size` and related fields in critical section
3. **Content scale timing**: Ensure `getContentScale()` called at consistent render state

### Phase 3: Race Condition Mitigation (Medium Priority)

1. **Coordinate caching**: Cache last known good coordinates to smooth rapid changes
2. **TSF update debouncing**: Delay TSF coordinate updates after rapid cursor movements  
3. **Fallback positioning**: Improve default coordinates when calculation fails

## Acceptance Criteria

- [ ] Detailed logging shows coordinate calculation values and timing
- [ ] Gemini CLI composition positioning improves to acceptable level
- [ ] No regression in Claude Code behavior
- [ ] Candidate window positioning becomes more predictable

## Notes

- **Windows Terminal has similar issues**: This is not unique to Ghostty - Microsoft's own implementation struggles with the same TSF/Terminal coordination problems
- **Complete solution may be impossible**: The fundamental async nature of TUI cursor updates vs synchronous TSF coordinate requests creates inherent timing issues
- **App-specific behavior is expected**: Different TUI apps will always have some variation due to their cursor management patterns

## Related Files

- `src/apprt/winui3/App.zig:867` - `tsfGetCursorRect()`
- `src/Surface.zig:2150` - `imePoint()`  
- `src/apprt/winui3/tsf.zig:693` - `ctxOwnerGetTextExt()`
- `src/termio/stream_handler.zig:229` - cursor position updates

## Priority: Medium

While frustrating for Japanese input users, this is a complex issue affecting professional terminal implementations. Focus on incremental improvements rather than perfect solution.