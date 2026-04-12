# Test Audit Report — ghostty-win

最終更新: 2026-03-27
次回更新期限: 2026-04-26

> **注意**: 最終更新から 30 日以上経過している場合、このドキュメントは陳腐化している可能性があります。
> 「更新手順」セクションに従って状態を再確認してください。

## 0. 更新手順

### 静的テストの実行と記録

```powershell
# self_diagnosis/ の静的テストを一括実行
Get-ChildItem tests/self_diagnosis/test_*.ps1 | ForEach-Object {
    $result = pwsh -File $_.FullName 2>&1
    $status = if ($LASTEXITCODE -eq 0) { "パス" } else { "フェイル" }
    Write-Host "$($_.Name): $status"
}
```

### 更新後の記録方法

1. 上記コマンドを実行する
2. 各テストの結果を「テスト一覧」の「現在の状態」列に記録する
3. 先頭の「最終更新」日付を更新する
4. 「推奨アクション」セクションを見直し、解決済みの問題を削除する

## 1. テスト一覧

### tests/self_diagnosis/ (20 files)

| # | ファイル | 種別 | テスト対象 | 関連Issue | 現在の状態 |
|---|---------|------|-----------|----------|-----------|
| 1 | cursor_test.ps1 | 手動 | カーソル位置の目視確認 | — | 未実行（手動） |
| 2 | diagnose.ps1 | 統合 | CP全機能(PING/STATE/TAIL/INPUT)、並列PING、メモリ、耐久300s | — | 未実行（要Ghostty起動） |
| 3 | test_bg_color_blend.ps1 | 静的 | HLSL bg_color alpha blend簡素化（global_bgとの合成） | — | 未実行（静的） |
| 4 | test_crd_ime_passthrough.ps1 | 静的+RT | VK_OEM_CLEAR(0xFF)のIMEパススルー（CRD対応） | #133 | 未実行（静的+RT） |
| 5 | test_cursor.py | 手動 | カーソル移動の目視確認（Python版） | — | 未実行（手動） |
| 6 | test_cursor_blink.ps1 | RT | アイドル時のカーソルブリンク（CPU時間計測） | #131 | 未実行（要Ghostty起動） |
| 7 | test_cursor_color_override.ps1 | 静的 | CPUサイドカーソルカラーオーバーライド削除の回帰防止 | #133 | 未実行（静的） |
| 8 | test_cursor_d3d11_inversion.ps1 | 静的 | D3D11シェーダーによるカーソルテキスト反転（cursor_pos/color/wide） | #130 | 未実行（静的） |
| 9 | test_diagnose_ps1_syntax.ps1 | 静的 | diagnose.ps1他の構文エラー検出、$Pid→$ProcessIdリネーム | — | 未実行（静的） |
| 10 | test_eraseline_firstchar.ps1 | RT | 履歴リコール時の先頭文字消失（CP INPUT→TAIL検証） | #133 | 未実行（要Ghostty起動） |
| 11 | test_ime_char_handler.ps1 | 静的+RT | WM_IME_CHAR(0x0286)ハンドラ存在＋TSFインジェクト | #133 | 未実行（静的+RT） |
| 12 | test_lefthook_config.ps1 | 静的 | lefthook設定（zig-fmt、vtable-manifest、pre-push） | — | 未実行（静的） |
| 13 | test_preedit_dirty.ps1 | 静的 | preedit dirtyフラグのコード内存在確認 | #133 | 未実行（静的） |
| 14 | test_resize_crash.ps1 | RT | リサイズ中のクラッシュ（SetWindowPos×50回） | #86 | 未実行（要Ghostty起動） |
| 15 | test_surface_refactor.ps1 | 静的 | Surface.zig init/deinit分割の関数存在確認 | — | 未実行（静的） |
| 16 | test_tab_closetab_fix.ps1 | 静的 | closeTabのCOM indexOf使用、stale indexOfScalar排除 | #129 | 未実行（静的） |
| 17 | test_text_selection.ps1 | 静的+RT | XAML CapturePointer使用、Win32 SetCapture不使用 | #132 | 未実行（静的+RT） |
| 18 | test_touch_scroll.ps1 | 静的 | PointerDeviceType分岐、touch_anchorフィールド | #134 | 未実行（静的） |
| 19 | test_tsf_setfocus_null_guard.ps1 | 静的 | TSF focus() nullガード、WM_ACTIVATE移行 | #135 | 未実行（静的） |
| 20 | test_zig_native_cp.ps1 | 静的 | Zig-native CP移行完了（Rust DLL参照なし、named pipe IPC） | — | 未実行（静的） |

### tests/winui3/ (13 test files + 5 runners + 1 helper)

| # | ファイル | Phase | テスト対象 | CP必要 | UIA必要 | 現在の状態 |
|---|---------|-------|-----------|--------|---------|-----------|
| 1 | test-01-lifecycle.ps1 | 1 | 起動→XAML init→シャットダウン（ログ検証） | No | No | 未実行（要Ghostty起動） |
| 2 | test-02a-tabview.ps1 | 2 | TabView/TabItem存在（UIA） | No | Yes | 未実行（要Ghostty起動） |
| 3 | test-02b-ime-overlay.ps1 | 2 | GhosttyInputOverlay HWND（WS_CHILD+VISIBLE+TRANSPARENT） | No | No | 未実行（要Ghostty起動） |
| 4 | test-02c-drag-bar.ps1 | 2 | GhosttyDragBar DPIスケーリング | No | No | 未実行（要Ghostty起動） |
| 5 | test-02d-control-plane.ps1 | 2b | CP smoke test (agent-ctl) | Yes | No | 環境依存（agent-deck 要インストール） |
| 6 | test-02e-agent-roundtrip.ps1 | 2b | claude -p PINEAPPLE 実行→バッファ確認 | Yes | No | 環境依存（agent-deck 要インストール） |
| 7 | test-03-window-ops.ps1 | 2 | 移動/リサイズ/最大化/最小化/復元 | No | Yes | 未実行（要Ghostty起動） |
| 8 | test-04-keyboard.ps1 | 2b | echo via CP→バッファ検証 | Yes | No | 環境依存（agent-deck 要インストール） |
| 9 | test-05-ghost-demo.ps1 | 3 | D3D11 Present、play.py 235フレーム | Yes | No | 環境依存（Python + agent-deck 要インストール） |
| 10 | test-06-ime-input.ps1 | 2b | 日本語UTF-8ラウンドトリップ、IME composing state | Yes | No | 環境依存（agent-deck 要インストール） |
| 11 | test-07-tsf-ime.ps1 | 2b | ESC[TSF:インジェクション、GotFocus再関連付け | Yes | No | 環境依存（MSYS2 bash + agent-deck 要インストール） |
| 12 | test-08-profile-menu.ps1 | 独立 | SplitButton+MenuFlyoutItem（プロファイル一覧） | No | Yes | 未実行（要Ghostty起動） |
| 13 | tsf-inject.sh | ユーティリティ | bash経由ESCバイト送信（PS文字化け回避） | — | — | ユーティリティ（直接実行不要） |

## 2. 重複・矛盾の検出

### 重複

| テストA | テストB | 重複内容 |
|---------|---------|---------|
| test_eraseline_firstchar.ps1 | test_preedit_dirty.ps1 | 両方とも#133の先頭文字消失を検証。前者はRT(TAIL)、後者は静的(コード存在確認)。**補完的であり問題なし** |
| test_crd_ime_passthrough.ps1 | test_ime_char_handler.ps1 | 両方ともWM_IME_CHAR関連を検証。前者はVK_OEM_CLEARパススルー、後者はWM_IME_CHARハンドラ。**対象が異なり問題なし** |
| test_resize_crash.ps1 (self_diagnosis) | test-03-window-ops.ps1 (winui3) | 両方ともリサイズを実行。前者はストレス(50回)+クラッシュ検出、後者はUIA TransformPattern。**目的が異なり問題なし** |

### 矛盾

| 問題 | 詳細 |
|------|------|
| **~~agent-ctl依存~~** | ~~winui3テスト群はagent-ctl (agent-relay) を前提~~ → **agent-deck に移行済み** (2026-03-27) |
| **test_preedit_dirty.ps1のアサーション** | render.zigに`flags.dirty.preedit`参照を期待するが、実際にはrender.zig:276-280でDirty全体を整数比較してる。個別フィールド参照はない。テストが誤検出する可能性 |

## 3. 今日のコミットとテストカバレッジの突合

| コミット | 内容 | テストカバレッジ |
|---------|------|----------------|
| `e70ec3856` | preedit終了時にcursorMarkDirty()追加 (#133) | **test_preedit_dirty.ps1**: `row.dirty = true`の存在をチェック → cursorMarkDirty()経由でセットされるので**カバー済み** |
| `e23f54878` | preedit dirty + cursor row dirtyのユニットテスト追加 | テスト自体がコミット。**自己カバー** |
| `5df235ecd` | 全2026-03-26コミットの包括テスト | テスト自体がコミット。**自己カバー** |
| `1a708a14b` | Surface.zig init/deinit分割リファクタ | **test_surface_refactor.ps1**: 4関数の存在確認。**カバー済み** |
| `9b1478041` | TSF SetFocus nullガード + WM_ACTIVATE移行 | **test_tsf_setfocus_null_guard.ps1**: nullガード・WM_ACTIVATE・WM_SETFOCUSのコード検証。**カバー済み** |
| `b34a7e7b2` | PointerDeviceType分岐（タッチスクロール） | **test_touch_scroll.ps1**: 静的コード検証。**カバー済み** |
| `7641780c9` | $Pid→$ProcessIdリネーム | **test_diagnose_ps1_syntax.ps1**: パラメータ名検証。**カバー済み** |
| `7468f2e68` | テキスト選択#132 + WM_IME_CHARテスト追加 | **test_text_selection.ps1** + **test_ime_char_handler.ps1**: **カバー済み** |
| `661fb06ec` | カーソルブリンク#131テスト追加 | **test_cursor_blink.ps1**: **カバー済み** |
| `da2cc266e` | eraseLine先頭文字#133 + リサイズクラッシュ#86テスト | **test_eraseline_firstchar.ps1** + **test_resize_crash.ps1**: **カバー済み** |
| `e2140bc1e` | CRD IMEパススルーテスト | **test_crd_ime_passthrough.ps1**: **カバー済み** |
| `91a690d18` | VK_OEM_CLEAR(0xFF)パススルー修正 | **test_crd_ime_passthrough.ps1**: 0xFFの存在確認。**カバー済み** |
| `e20eef6c7` | WM_IME_CHARハンドラ追加 | **test_ime_char_handler.ps1**: WM_IME_CHAR定義・ハンドラ検証。**カバー済み** |
| `3cc65ef47` | CPUサイドカーソルカラーオーバーライド削除 | **テストなし** — 静的検証で「cursor color override が存在しないこと」を確認するテストがない |
| `aef29c693` | カーソルブリンクタイマーリセット停止 | **test_cursor_blink.ps1**: CPU時間計測で間接検証。**カバー済み** |
| `1d12b715e` | XAML CapturePointer使用 | **test_text_selection.ps1**: SetCapture不使用＋CapturePointer使用の検証。**カバー済み** |

### カバーされていない修正

| コミット | 内容 | 不足テスト |
|---------|------|-----------|
| `3cc65ef47` | CPUサイドカーソルカラーオーバーライド削除 | **test_cursor_color_override.ps1で対応済み** |
| `e3933974f` | ブロックカーソルD3D11反転 (#130) | **test_cursor_d3d11_inversion.ps1で対応済み** |
| `42297d393` | Zig-native CP (Rust DLL除去) | **test_zig_native_cp.ps1で対応済み** |
| `b7faab7d3` | closeTab indexOf修正 (#129) | **test_tab_closetab_fix.ps1で対応済み** |
| `56859a505` | HLSL bg_color blend簡素化 | **test_bg_color_blend.ps1で対応済み** |
| `2b4c42f78` | GitHub Actions CI workflow追加 | テスト対象外（CI設定自体のテスト不要） |

## 4. 実行順序の依存関係

```
Phase 1 (独立):
  test-01-lifecycle
    - 自前でGhostty起動→終了
    - 他テストに依存しない
    - 必ず最初に実行（XAML init検証）

Phase 2 (共有Ghostty):
  [Ghostty起動 + CP=1]
    ├── test-02a-tabview     (UIA)     ─┐
    ├── test-02b-ime-overlay (Win32)    │ 並列可能
    ├── test-02c-drag-bar    (Win32)    │
    └── test-03-window-ops   (UIA)     ─┘ ※ウィンドウ位置変更するので最後推奨

Phase 2b (CP依存、同じGhostty):
    ├── test-02d-control-plane (smoke)  ─── 最初に実行（CP生存確認）
    ├── test-02e-agent-roundtrip        ─── test-02dの後
    ├── test-04-keyboard                ─── 順不同
    ├── test-06-ime-input               ─── 順不同
    └── test-07-tsf-ime                 ─── 順不同（tsf-inject.sh必要）

Phase 3 (独立):
  test-05-ghost-demo
    - 自前でGhostty起動
    - Phase 2のGhosttyを終了した後に実行

独立:
  test-08-profile-menu
    - 任意のタイミングで実行可能
    - 10s初期化待ち必要

self_diagnosis/:
  全テスト独立実行可能
  diagnose.ps1 のみ長時間（耐久300s）
  静的テストはGhostty不要で即実行可能
```

### 暗黙の依存

| テスト | 暗黙の前提 | リスク |
|--------|-----------|-------|
| test-02d, 02e, 04, 06, 07 | agent-deck (~/agent-deck/agent-deck.exe) | **agent-deck に移行済み** (2026-03-27) |
| test-07-tsf-ime | bash + tsf-inject.sh | MSYS2 bash がPATHにないと失敗 |
| test-05-ghost-demo | play.py + python3 | Python未インストールで失敗 |
| test-01-lifecycle | CLOSE_TAB_AFTER_MS | ReleaseFastではcomptime gateで無効。Stop-Processフォールバック |

## 5. 推奨アクション

1. **3cc65ef47のテスト追加**: カーソルカラーCPUオーバーライドが復活しないことを確認する静的テスト
2. ~~**agent-ctl → agent-deck移行**~~: **完了** (2026-03-27) — 全CP依存テストをagent-deck CLIに移行済み
3. **test_preedit_dirty.ps1のアサーション修正**: render.zigでの`flags.dirty.preedit`個別参照チェックを、整数比較パスのチェックに変更
4. **手動テスト(cursor_test.ps1, test_cursor.py)の自動化**: CP TAIL + テキスト検証で自動化可能
