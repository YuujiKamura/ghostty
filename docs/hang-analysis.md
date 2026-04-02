# Issue #139: UI Thread Hang Analysis

Analysis of `src/apprt/winui3/` for UIスレッドブロック箇所。

## TL;DR — 危険度順

| # | 箇所 | 危険度 | 原因 |
|---|------|--------|------|
| H1 | CP provReadBuffer/provTabCount等 | **CRITICAL** | パイプスレッドからApp状態を排他ロックなしに読み取り — データ競合 + UIスレッドとの相互ブロック |
| H2 | controlPlaneCaptureTail → viewportString | **HIGH** | パイプスレッドからターミナルバッファ全走査。大量スクロールバックでO(n) |
| H3 | logDiagnosticSnapshot page walk | **MEDIUM** | Debug buildのみ。linked list全走査 O(pages)。Issue #138で認識済み |
| H4 | drainMailbox → core_app.tick | **MEDIUM** | tick内のPTY I/Oや端末処理が重い場合にUIスレッドをブロック |
| H5 | SendMessageW in drag bar | **LOW** | 同期SendMessage — 親WndProcが重いとdrag barスレッドもハング |
| H6 | DwmDefWindowProc | **LOW** | DWMサービス応答遅延時にWndProcがブロック |

---

## (1) CPパイプIOがUIスレッドで同期実行されていないか

### 結論: パイプIO自体はバックグラウンドスレッドだが、コールバックがUIスレッドのApp状態を**ロックなしに直接読む**

#### 安全な部分（PostMessageW経由）
- `provSendInput` → `PostMessageW(WM_APP_CONTROL_INPUT)` → UIスレッドで`drainPendingInputs`
- `provNewTab/closeTab/switchTab/focus` → `PostMessageW(WM_APP_CONTROL_ACTION)`
- `ipc.zig` listener → `PostMessageW` dispatch

これらは正しくUIスレッドに委譲している。

#### **CRITICAL: 読み取りコールバックがパイプスレッドからApp状態を直接読む**

以下のProvider callbacksはパイプサーバースレッドから呼ばれるが、`self.callback_ctx`経由で**App.zigの関数を直接呼ぶ**:

```
control_plane.zig:321  provReadBuffer   → capture_tail_fn(cb_ctx, ...)
control_plane.zig:358  provTabCount     → capture_state_fn(cb_ctx, ...)
control_plane.zig:367  provActiveTab    → capture_state_fn(cb_ctx, ...)
control_plane.zig:394  provTabWorkingDir → capture_state_fn(cb_ctx, ...)
control_plane.zig:406  provTabHasSelection → capture_state_fn(cb_ctx, ...)
control_plane.zig:376  provTabTitle     → GetWindowTextW (Win32 API, スレッドセーフ)
```

これらが呼ぶApp.zigの関数:

```zig
// App.zig:1615 — パイプスレッドから呼ばれる
fn controlPlaneCaptureState(ctx, allocator, tab_idx) {
    const surface = self.surfaces.items[idx];  // ← ArrayListをロックなしに読む
    return .{
        .pwd = s.pwd(allocator),               // ← core_surface内部状態を読む
        .has_selection = s.hasSelection(),       // ← 同上
        .at_prompt = s.cursorIsAtPrompt(),       // ← 同上
        .tab_count = self.surfaces.items.len,    // ← ロックなし
    };
}

// App.zig:1631 — パイプスレッドから呼ばれる
fn controlPlaneCaptureTail(ctx, allocator, tab_idx) {
    const viewport = s.viewportString(allocator);  // ← ターミナルバッファ全走査
}

// App.zig:1642 — パイプスレッドから呼ばれる
fn controlPlaneCaptureTabList(ctx, allocator) {
    for (self.surfaces.items) |surface| { ... }    // ← ロックなしにイテレート
}
```

**問題点:**
1. `self.surfaces`はUIスレッドが`newTab/closeTab`で変更する。パイプスレッドが同時にイテレートするとUB
2. `viewportString`はターミナルの内部ロックを取得する可能性がある。UIスレッドのdrainMailbox/tickが同じロックを取ると**デッドロック**
3. `pwd()`、`hasSelection()`、`cursorIsAtPrompt()`もcore_surfaceの内部状態に触る

**ハングシナリオ:**
```
パイプスレッド: provReadBuffer → controlPlaneCaptureTail → viewportString → terminal lock 待ち
UIスレッド:    drainMailbox → tick → terminal lock 保持中 → メッセージポンプ停止 → ハング
```

#### 修正案
- 読み取りコールバックもUIスレッドに委譲する（SendMessageWで同期、またはスナップショットをatomicに取得）
- または`surfaces`アクセスをMutexで保護する（ただしUIスレッドのパフォーマンスに影響）

---

## (2) drainMailboxでロックを長時間保持してないか

### drainMailbox自体はシンプル

```zig
// App.zig:1979
pub fn drainMailbox(self: *App) void {
    self.core_app.tick(self) catch {};    // ← ここが重い可能性
}
```

`core_app.tick()`はGhosttyコアのメインループ。内部で:
- PTYからの読み取り（buffered I/O）
- VTパーサー処理
- ターミナル状態更新
- レンダラーへの通知

これらはUIスレッドで実行される。大量の出力（`cat /dev/urandom`等）がある場合、tickが長時間かかりメッセージポンプが止まる。

### pending_inputs_lockは短時間

```zig
// control_plane.zig:249
pub fn drainPendingInputs(self, surface) {
    self.pending_inputs_lock.lock();    // ← 短時間：リスト入れ替えのみ
    var pending = self.pending_inputs;
    self.pending_inputs = .{};
    self.pending_inputs_lock.unlock();  // ← 即unlock
    // ... 以降はロックなしで処理
}
```

ロック保持時間は最小（swap and release）。問題なし。

### logDiagnosticSnapshot（Debug buildのみ）

```zig
// App.zig:2010-2013
var it = screen.pages.pages.first;
while (it) |node| : (it = node.next) {
    page_count += 1;                    // ← O(n) linked list walk
}
const tracked_pins = screen.pages.countTrackedPins();
```

Issue #138で認識済み。大量スクロールバック時にUIスレッドをブロック。
Release buildでは`comptime builtin.mode != .Debug`でスキップされるため影響なし。

---

## (3) DWM/XAML関連の同期呼び出し

### DwmDefWindowProc（nonclient_island_window.zig:553）

```zig
// WndProcの先頭で毎メッセージ呼ばれる（WM_NCHITTEST以外）
if (msg != os.WM_NCHITTEST) {
    var dwm_result: os.LRESULT = 0;
    if (os.DwmDefWindowProc(hwnd, msg, wparam, lparam, &dwm_result) != 0) {
        return dwm_result;   // ← DWMサービスへの同期IPC
    }
}
```

DWMサービスが応答しない場合（GPU負荷、ドライバ問題）にブロック。
ただしこれはWindows Terminalも同じパターンなので、ghostty固有の問題ではない。

### SendMessageW in drag bar（nonclient_island_window.zig:444,453,464,486）

```zig
// drag bar → parent への同期メッセージ転送
os.WM_NCMOUSEMOVE => os.SendMessageW(parent, msg, wparam, lparam),
os.WM_NCLBUTTONDOWN => os.SendMessageW(parent, msg, wparam, lparam),
os.WM_NCLBUTTONUP => os.SendMessageW(parent, msg, wparam, lparam),
os.WM_NCRBUTTONDOWN/UP => os.SendMessageW(parent, msg, wparam, lparam),
```

SendMessageWは同期呼び出し。親WndProcが`handleWndProcMessage`で重い処理をしている場合、
drag barのメッセージ処理もブロックされる。ただしこれもWTと同じパターン。

### XAML COM呼び出し

`handleSize`内の以下は全てUIスレッドで実行されるCOM呼び出し:

```zig
// App.zig:2387
rg.queryInterface(com.IFrameworkElement)  // ← COM QI
framework.SetWidth(...)                    // ← XAML layout trigger
framework.SetHeight(...)                   // ← XAML layout trigger
```

通常は高速だが、XAML layout cycleが走ると重くなる可能性がある。

### BufferedPaint（WM_PAINT、nonclient_island_window.zig:595-604）

```zig
const buf = os.BeginBufferedPaint(dc, &rc_rest, os.BPBF_TOPDOWNDIB, &params, &opaque_dc);
```

GDI操作。通常は高速だがGPUドライバの問題時にブロック可能。

---

## 追加の懸念事項

### WM_USER (drainMailbox) のスロットリング不在

`wakeup()`は毎回PostMessageW/TryEnqueueする。高頻度のPTY出力で`WM_USER`が
メッセージキューに大量に溜まり、他のメッセージ（WM_PAINT、WM_SIZE等）が
処理されない「メッセージスターベーション」が起きる可能性がある。

### tsf.focus()/unfocus()の再帰リスク

コメントで警告済み（WM_SETFOCUS内ではなくWM_ACTIVATEで処理）。
現在の実装は正しいが、将来の変更で再帰ハングの可能性。

---

## 推奨修正（優先順）

1. **H1: CP読み取りコールバックをUIスレッドに委譲** — `SendMessageW`で同期呼び出しに変更するか、スナップショットをatomicに取得
2. **H2: viewportStringの呼び出しをキャッシュ化** — 最後のTAIL結果をatomicスナップショットとして保持し、パイプスレッドからはそれを返す
3. **H4: drainMailboxにtick上限を設ける** — 一定時間/一定バイト数で中断してメッセージポンプに制御を返す
4. **H3: Debugビルドの page walk を削除 or サンプリング化** — Issue #138
