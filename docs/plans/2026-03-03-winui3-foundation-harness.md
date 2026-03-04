# WinUI3 Foundation Harness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** WinUI3 のクラッシュ切り分けを場当たり編集なしで再現できる「基礎プロジェクト」を確立する。

**Architecture:** `App.zig` の分岐条件を環境変数経由の `RuntimeDebugConfig` に一本化し、実験条件を外部化する。実行は `scripts/winui3-foundation-matrix.ps1` が担当し、同一手順で A/B 結果を再取得可能にする。これにより根因探索を「コード改変」から「実験設計」に分離する。

**Tech Stack:** Zig, WinUI3, PowerShell 7

---

### Task 1: 設定を外部化する

**Files:**
- Create: `src/apprt/winui3/debug_harness.zig`
- Modify: `src/apprt/winui3/App.zig`

**Step 1: 起動時設定の型を追加**
- `RuntimeDebugConfig` を定義し、TabView 経路の各スイッチを bool で保持する。

**Step 2: 環境変数のパースを実装**
- `GHOSTTY_WINUI3_*` 変数から設定をロードし、既存挙動をデフォルト値として維持する。

**Step 3: App 初期化で読み込み**
- `App.init` で設定を1回ロードし、ログに現在値を出力する。

**Step 4: initXaml の分岐を設定参照へ変更**
- ハードコード定数をすべて `self.debug_cfg.*` に置き換える。

### Task 2: 実験実行を自動化する

**Files:**
- Create: `scripts/winui3-foundation-matrix.ps1`

**Step 1: ケース定義を固定**
- baseline / tabview_off / handlers_off / empty_tabview / item_no_content / no_append / no_select を定義する。

**Step 2: 一定時間監視で成否を判定**
- 指定秒後にプロセスが存続しているかを記録する。

**Step 3: 表形式で比較結果を出力**
- `alive_after_wait` と `exit_code` を同時表示し、毎回同一フォーマットで比較可能にする。

### Task 3: 運用ルールを確立する

**Files:**
- This doc

**Step 1: 目的を明文化**
- 「修正前に原因層を特定する」を必須ルールにする。

**Step 2: 判定の順序を固定**
- 1) handlers, 2) append, 3) select, 4) content の順で切り分ける。

**Step 3: 収束条件を定義**
- 再現ケースが1つに収束したら、そのケースのみを対象に恒久修正へ進む。

### 実行コマンド

```powershell
cd C:\Users\yuuji\ghostty-win
zig build -Dapp-runtime=winui3 -Drenderer=d3d11
pwsh -File .\scripts\winui3-foundation-matrix.ps1
```

### 完了条件

- 環境変数だけで切り分け条件を変更できる。
- 毎回同じコマンドで同じ比較表が出る。
- `App.zig` に実験専用ハードコード定数が残っていない。
