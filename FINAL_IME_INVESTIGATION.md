# Ghostty WinUI3 TSF Position Issue - Technical Investigation Report

## 問題の概要

Ghostty WinUI3 環境において、日本語 IME の composition text（変換前ひらがな）と候補ウィンドウの表示位置が不安定：

- **Gemini CLI**: 画面右下や中央に誤配置
- **Claude Code**: 比較的正しくインライン表示
- **Windows Terminal**: 同様の問題が報告されており、完全解決されていない

## 技術的障壁の分析

### 1. 根本的な非同期性問題

```
TUI App              Terminal Core           TSF System
--------              -------------           ----------
CSI H送信      →      cursor更新       ?      GetTextExt呼び出し
(高速連続)            (即座)               (IME判断タイミング)
```

**問題**: TSF は同期的に座標を問い合わせるが、TUI のカーソル更新は非同期。この設計上の乖離は解決不可能。

### 2. WinUI3 座標系の複雑性

```
Terminal Cursor (0,5) 
    ↓ *cell_size + padding
Surface Pixel (120, 100)
    ↓ /content_scale  
Unscaled (60, 50)
    ↓ ClientToScreen(nci.island.hwnd)
Screen (1680, 450) ← TSF に返す座標
```

**問題点**:
- 各段階で精度ロス/タイミングずれが発生
- `app.hwnd = nci.island.hwnd` が適切な基準点か不明
- XAML Islands の複雑な HWND 階層

### 3. レンダリングサイクル競合

```cpp
// 現在の座標計算 (Surface.zig:2150-2220)
pub fn imePoint(self: *const Surface) apprt.IMEPos {
    self.renderer_state.mutex.lock();  // ← mutex で保護
    const cursor = self.renderer_state.terminal.screens.active.cursor;
    const preedit_width: usize = if (self.renderer_state.preedit) |preedit| preedit.width() else 0;
    self.renderer_state.mutex.unlock();
    
    // しかし以下は mutex 外で計算
    const content_scale = self.rt_surface.getContentScale() catch .{ .x = 1, .y = 1 };
    // self.size も mutex で保護されていない
    var x: f64 = @floatFromInt(cursor.x * self.size.cell.width + self.size.padding.left);
}
```

**競合ポイント**:
- `cursor` は mutex 保護済み
- `self.size`, `content_scale` は保護外 → レンダリング中に変動の可能性

### 4. TUI アプリ固有の挙動

**Gemini CLI の特徴**:
- 高速なカーソル位置更新
- プロンプト表示時の連続 CSI H
- IME 開始時のカーソル位置が不定

**Claude Code の特徴**:
- 比較的安定したカーソル管理
- IME 開始前にカーソル位置が確定

## 現在の実装の問題箇所

### 1. tsfGetCursorRect (App.zig:867-884)

```zig
fn tsfGetCursorRect(userdata: ?*anyopaque) os.RECT {
    // ...
    const ime_pos = surface.core_surface.imePoint();  // ← ここで競合の可能性
    var pt = os.POINT{ .x = @intFromFloat(ime_pos.x), .y = @intFromFloat(ime_pos.y) };
    _ = os.ClientToScreen(hwnd, &pt);  // ← hwnd が適切か不明
    // ...
}
```

**問題**:
- imePoint() が内部で複数の非同期要素を参照
- ClientToScreen に nci.island.hwnd を使用（正しい基準点か？）

### 2. imePoint座標計算 (Surface.zig:2150-2220)

```zig
// mutex 保護外の要素
const content_scale = self.rt_surface.getContentScale() catch .{ .x = 1, .y = 1 };
var x: f64 = @floatFromInt(cursor.x * self.size.cell.width + self.size.padding.left);
```

**問題**:
- `self.size` がレンダリングサイクルで変動する可能性
- `content_scale` の取得タイミングで値が変わる可能性

## 推奨する改善アプローチ

### Phase 1: 詳細ログによる問題特定

TSF 座標関連に詳細ログを追加：

```zig
// tsfGetCursorRect にログ追加
fn tsfGetCursorRect(userdata: ?*anyopaque) os.RECT {
    const ime_pos = surface.core_surface.imePoint();
    log.info("TSF GetTextExt: cursor=({d},{d}) ime_pos=({d:.2},{d:.2}) scale=({d:.2},{d:.2})", .{
        surface.renderer_state.terminal.screens.active.cursor.x,
        surface.renderer_state.terminal.screens.active.cursor.y,
        ime_pos.x, ime_pos.y, content_scale.x, content_scale.y
    });
    // ClientToScreen前後の座標をログ
}
```

### Phase 2: 座標系の検証と修正

1. **HWND の妥当性確認**: nci.island.hwnd が適切な基準点か検証
2. **スケーリング処理の見直し**: content_scale の適用タイミング
3. **mutex 保護範囲の拡大**: size, padding も保護下で取得

### Phase 3: 非同期性への対処

1. **座標キャッシュ**: 最後の確定座標を保持し、急激な変化を緩和
2. **TSF 更新の遅延**: カーソル移動後、短時間の遅延後に TSF 座標を更新
3. **フォールバック座標**: 計算失敗時のデフォルト位置を改善

## 限界と受容すべき制約

1. **完全な解決は不可能**: TSF 設計上、TUI との完全同期は困難
2. **Windows Terminal も未解決**: Microsoft の実装でも同様の問題
3. **アプリ依存性**: TUI アプリの実装により挙動が変わるのは避けられない

## 結論

この問題は単純な実装バグではなく、TSF とターミナルエミュレータの根本的な設計矛盾に起因する。完全解決は困難だが、以下により大幅改善は可能：

1. 詳細ログによる問題箇所の特定
2. 座標系変換の精密化
3. 競合状態の緩和策

最優先は Phase 1 の詳細ログ実装により、Gemini CLI と Claude Code の具体的な挙動差を可視化することである。# [WinUI3] TSF IME composition positioning unstable - coordinates misplaced for some TUI apps

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