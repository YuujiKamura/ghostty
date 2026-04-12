# 要件ドキュメント — WinUI3 apprt 現状棚卸し

## はじめに

本ドキュメントは `ghostty-win` リポジトリにおける WinUI3 apprt（`src/apprt/winui3/`）の
現在の実装状態と残タスクを一箇所にまとめた棚卸しスペックです。

「何が動いているか」と「何が残っているか」を明確に分離し、
受け入れゲートとの対応関係を示します。

---

## 用語集

- **WinUI3_apprt**: `src/apprt/winui3/` 以下の Zig 実装。`-Dapp-runtime=winui3` でビルドされる。
- **XAML_Islands**: `DesktopWindowXamlSource` を使った WinUI3 ホスティング方式（Windows Terminal アーキテクチャ）。
- **CP（Control_Plane）**: `control_plane.zig` が実装する名前付きパイプ IPC サーバー。外部ツールからターミナルを操作する。
- **SwapChainPanel**: D3D11 レンダリング出力を XAML ツリーに埋め込む WinRT コントロール。
- **TabView**: WinUI3 の `Microsoft.UI.Xaml.Controls.TabView`。タブ UI を提供する。
- **IME**: Input Method Editor。日本語等の多バイト文字入力を処理する。
- **TSF**: Text Services Framework。Windows の標準テキスト入力フレームワーク。
- **Island_Window**: `island_window.zig` が実装するトップレベル Win32 ウィンドウ。
- **NonClient_Island_Window**: `nonclient_island_window.zig` が実装するカスタムタイトルバー付きウィンドウ。
- **ローカル受け入れゲート**: `pwsh -File .\scripts\winui3-contract-check.ps1 -Build`
- **クロスリポジトリゲート**: `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1`

---

## 要件

---

### 要件 1: ビルドシステム統合

**ユーザーストーリー:** 開発者として、`-Dapp-runtime=winui3` オプション一つで WinUI3 apprt をビルドできるようにしたい。そうすることで、ビルド手順を統一し CI/CD に組み込める。

#### 受け入れ条件

1. THE WinUI3_apprt SHALL `src/apprt/runtime.zig` の `Runtime` enum に `winui3` として登録されている。
2. WHEN `zig build -Dapp-runtime=winui3 -Drenderer=d3d11` を実行したとき、THE ビルドシステム SHALL エラーなくビルドを完了する。
3. WHEN ローカル受け入れゲートを実行したとき、THE ローカル受け入れゲート SHALL すべてのコントラクトチェックをパスする。

**実装状態: ✅ 完了**
- `runtime.zig` に `winui3` 登録済み（`winui3_islands` は統合済み）
- `winui3-contract-check.ps1` が存在し機能している

---

### 要件 2: XAML Islands ウィンドウ表示

**ユーザーストーリー:** ユーザーとして、ghostty を起動したときに WinUI3 ウィンドウが表示されるようにしたい。そうすることで、ネイティブ Windows アプリとして使用できる。

#### 受け入れ条件

1. WHEN ghostty を起動したとき、THE Island_Window SHALL `DesktopWindowXamlSource` を初期化し XAML コンテンツを表示する。
2. WHEN ghostty を起動したとき、THE NonClient_Island_Window SHALL カスタムタイトルバー（ドラッグバー）付きのウィンドウを表示する。
3. WHEN ウィンドウをリサイズしたとき、THE Island_Window SHALL XAML Islands の子 HWND サイズを更新する。
4. THE NonClient_Island_Window SHALL `WS_EX_NOREDIRECTIONBITMAP` フラグ付きで作成される。

**実装状態: ✅ 完了**
- `island_window.zig`、`nonclient_island_window.zig` 実装済み
- ドラッグバー実装済み（`nonclient_island_window.zig` 内）

---

### 要件 3: D3D11 レンダリング

**ユーザーストーリー:** ユーザーとして、ターミナルの内容が画面に正しく描画されるようにしたい。そうすることで、テキストやカーソルを視認できる。

#### 受け入れ条件

1. WHEN Surface が初期化されたとき、THE Surface SHALL D3D11 デバイスと SwapChainPanel を作成する。
2. WHEN レンダラースレッドが描画フレームを生成したとき、THE SwapChainPanel SHALL `ISwapChainPanelNative::SetSwapChain` を UI スレッドで呼び出す。
3. WHEN ウィンドウがリサイズされたとき、THE Surface SHALL スワップチェーンのバッファサイズを更新する。
4. THE D3D11_レンダラー SHALL カーソルのテキスト反転をシェーダーで実装する（`test_cursor_d3d11_inversion.ps1` で検証済み）。

**実装状態: ✅ 完了**
- SwapChainPanel + D3D11 動作確認済み
- カーソル反転シェーダー実装済み（Issue #130）

---

### 要件 4: TabView タブ管理

**ユーザーストーリー:** ユーザーとして、複数のターミナルタブを開いて切り替えられるようにしたい。そうすることで、複数のシェルセッションを一つのウィンドウで管理できる。

#### 受け入れ条件

1. WHEN Ctrl+T を押したとき、THE TabView SHALL 新しいタブを追加し、そのタブをアクティブにする。
2. WHEN Ctrl+W を押したとき、THE TabView SHALL アクティブなタブを閉じる。
3. WHEN タブを切り替えたとき、THE TabView SHALL 旧 Surface に `focusCallback(false)` を、新 Surface に `focusCallback(true)` を送信する。
4. WHEN タブを閉じたとき、THE Tab_Manager SHALL `surfaces_mutex` を保持した状態でモデルを更新し、その後 XAML 操作を行う。
5. WHEN ターミナルタイトルが変更されたとき、THE Surface SHALL TabViewItem のヘッダーテキストを更新する（60Hz スロットリング付き）。
6. IF タブが最後の 1 枚のとき、THEN THE Tab_Manager SHALL タブを閉じた後にアプリを終了する。

**実装状態: ✅ 完了**
- `tab_manager.zig` 実装済み
- Issue #127（SelectionChanged 副作用）、Issue #129（closeTab indexOf 修正）対応済み

---

### 要件 5: キーボード入力

**ユーザーストーリー:** ユーザーとして、英語キーボードでターミナルに文字を入力できるようにしたい。そうすることで、シェルコマンドを実行できる。

#### 受け入れ条件

1. WHEN 英語キーボードのキーを押したとき、THE Input_Runtime SHALL キーイベントをターミナルコアに転送する。
2. WHEN `ime_text_box` が XAML フォーカスを持つとき、THE Input_Runtime SHALL `PreviewKeyDown` イベントで修飾キーを処理する。
3. WHEN フォーカスが XAML ツリー外に移ったとき、THE Input_Runtime SHALL `ime_text_box` にフォーカスを戻す。
4. THE Input_Runtime SHALL `input_hwnd` をフォールバック専用として使用し、通常入力は `ime_text_box` 経由で処理する。

**実装状態: ✅ 完了**
- `input_runtime.zig` 実装済み
- 英語キーボード入力動作確認済み

---

### 要件 6: IME 日本語入力インフラ

**ユーザーストーリー:** ユーザーとして、日本語 IME でターミナルに文字を入力できるようにしたい。そうすることで、日本語コマンドやテキストを入力できる。

#### 受け入れ条件

1. WHEN IME で文字を変換中のとき、THE IME SHALL `preeditCallback` でプリエディット文字列をターミナルに表示する。
2. WHEN IME で文字を確定したとき、THE IME SHALL 確定文字列をターミナルコアに送信する。
3. THE TSF SHALL WinUI3 の TSF パスを使用して IME ライフサイクルを管理する。
4. WHEN `WM_IME_CHAR(0x0286)` を受信したとき、THE IME SHALL 文字をターミナルコアに転送する（Issue #133）。
5. WHEN VK_OEM_CLEAR(0xFF) を受信したとき、THE IME SHALL IME パススルーとして処理する（CRD 対応、Issue #133）。
6. WHEN preedit が終了したとき、THE Surface SHALL カーソル行を dirty としてマークする（Issue #133）。

**実装状態: ✅ インフラ実装済み / ⚠️ 実機確認待ち**
- `ime.zig`、`tsf.zig`、`input_overlay.zig`、`tsf_bindings.zig`、`tsf_logic.zig` 実装済み
- PLAN.md Phase 6 の実機確認（日本語入力）は未完了
- `test-06-ime-input.ps1`、`test-07-tsf-ime.ps1` でテスト定義済み

---

### 要件 7: コントロールプレーン（IPC）

**ユーザーストーリー:** 外部ツールの開発者として、名前付きパイプ経由でターミナルの状態を取得・操作できるようにしたい。そうすることで、AI エージェントや自動化スクリプトからターミナルを制御できる。

#### 受け入れ条件

1. THE Control_Plane SHALL 名前付きパイプサーバーを起動し、PING/STATE/TAIL/INPUT コマンドを処理する。
2. WHEN PING コマンドを受信したとき、THE Control_Plane SHALL 応答を返す。
3. WHEN INPUT コマンドを受信したとき、THE Control_Plane SHALL テキストをアクティブな Surface に送信する。
4. WHEN STATE コマンドを受信したとき、THE Control_Plane SHALL タブ数・アクティブタブ・作業ディレクトリ・選択状態を返す。
5. WHEN TAIL コマンドを受信したとき、THE Control_Plane SHALL アクティブタブのビューポート文字列を返す。
6. THE Control_Plane SHALL Rust DLL に依存せず、Zig ネイティブ実装のみで動作する（`test_zig_native_cp.ps1` で検証済み）。

**実装状態: ✅ 完了**
- `control_plane.zig`、`ipc.zig` 実装済み
- `diagnose.ps1` で PING/STATE/TAIL/INPUT・並列 PING・耐久 300s テスト済み

---

### 要件 8: スクロールバー

**ユーザーストーリー:** ユーザーとして、ターミナルのスクロールバーを操作してスクロールバックを閲覧できるようにしたい。そうすることで、過去の出力を確認できる。

#### 受け入れ条件

1. THE Surface SHALL `surface_grid` に `SwapChainPanel` と `ScrollBar` を配置する。
2. WHEN スクロールバーを操作したとき、THE Surface SHALL ターミナルのビューポートを更新する。
3. WHEN `winui3-scrollbar-smoke.ps1 -NoBuild` を実行したとき、THE スクロールバー SHALL ピクセル差分テストをパスする。
4. WHERE UIA バウンディングレクタングルが不正確なとき、THE スクロールバー SHALL ランタイムメトリクスとピクセル差分を正とする（Issue #57）。

**実装状態: ✅ 完了**
- `winui3-scrollbar-smoke.ps1` で検証済み

---

### 要件 9: プロファイルメニュー

**ユーザーストーリー:** ユーザーとして、タブ追加ボタンの横のドロップダウンから使用するシェルプロファイルを選択して新しいタブを開きたい。そうすることで、cmd・PowerShell・Git Bash・WSL を素早く切り替えられる。

#### 受け入れ条件

1. WHEN プロファイルメニューを開いたとき、THE Profile_Menu SHALL 検出されたシェルプロファイル（cmd、pwsh、Git Bash、WSL）を MenuFlyoutItem として表示する。
2. WHEN MenuFlyoutItem をクリックしたとき、THE Profile_Menu SHALL 対応するプロファイルのコマンドで `newTab()` を呼び出す。
3. THE Profile_Menu SHALL `SplitButton` と `MenuFlyoutItem` を使用して実装される（`test-08-profile-menu.ps1` で検証済み）。

**実装状態: ⚠️ 部分実装**
- プロファイル一覧の表示は実装済み（`profile_menu.zig`）
- **クリックハンドラ未接続**（`profile_menu.zig:24` の TODO）
- `IMenuFlyoutItem.Click` の `RoutedEventHandler` デリゲート登録が必要

---

### 要件 10: コンテキストメニュー

**ユーザーストーリー:** ユーザーとして、ターミナル上で右クリックしてコンテキストメニューを表示したい。そうすることで、コピー・ペースト等の操作を素早く実行できる。

#### 受け入れ条件

1. WHEN ターミナル上で右クリックしたとき、THE Surface SHALL コンテキストメニューを表示する。
2. THE コンテキストメニュー SHALL 少なくともコピー・ペーストの操作を含む。
3. WHEN コンテキストメニューからペーストを選択したとき、THE Surface SHALL クリップボードの内容をターミナルに送信する。

**実装状態: ❌ 未実装**
- `App.zig:1967` に TODO あり（`showContextMenuAtCursor` は no-op）
- XAML Islands apprt 向けの実装が必要

---

### 要件 11: ペースト確認ダイアログ

**ユーザーストーリー:** ユーザーとして、危険なペースト操作（複数行・制御文字を含む）を実行する前に確認ダイアログを表示してほしい。そうすることで、意図しないコマンド実行を防止できる。

#### 受け入れ条件

1. WHEN `UnsafePaste` または `UnauthorizedPaste` エラーが発生したとき、THE Surface SHALL WinUI3 ダイアログでユーザーに確認を求める。
2. WHEN ユーザーが確認ダイアログで「許可」を選択したとき、THE Surface SHALL `confirmed = true` で `completeClipboardRequest` を再試行する。
3. WHEN ユーザーが確認ダイアログで「拒否」を選択したとき、THE Surface SHALL ペーストを中止する。

**実装状態: ❌ 未実装**
- `Surface.zig:826` に TODO あり
- 現在は安全側に倒してペーストを拒否している

---

### 要件 12: CP の tab_index ルーティング

**ユーザーストーリー:** 外部ツールの開発者として、CP の INPUT コマンドで特定のタブ番号を指定してテキストを送信したい。そうすることで、複数タブを持つセッションで任意のタブを操作できる。

#### 受け入れ条件

1. WHEN INPUT コマンドに `tab_index` が指定されたとき、THE Control_Plane SHALL 指定されたインデックスの Surface にテキストを送信する。
2. WHEN `tab_index` が範囲外のとき、THE Control_Plane SHALL エラーを返す。
3. WHEN `tab_index` が未指定のとき、THE Control_Plane SHALL アクティブな Surface にテキストを送信する（既存動作を維持）。

**実装状態: ❌ 未実装**
- `control_plane.zig:532` に TODO あり（`_ = tab_index; // TODO: route to specific tab`）

---

### 要件 13: インスペクター

**ユーザーストーリー:** 開発者として、ターミナルのインスペクターウィンドウを開いてデバッグ情報を確認したい。そうすることで、レンダリングや状態の問題を診断できる。

#### 受け入れ条件

1. WHEN インスペクター表示コマンドを実行したとき、THE Surface SHALL インスペクターウィンドウを表示する。
2. THE インスペクター SHALL ターミナルの内部状態（セル情報、カーソル位置等）を表示する。

**実装状態: ❌ 未実装**
- `Surface.zig` の `redrawInspector()` は no-op（"No-op for MVP" コメントあり）

---

### 要件 14: 既知のハング問題への対処

**ユーザーストーリー:** ユーザーとして、大量の出力やタブ操作中にアプリがハングしないようにしたい。そうすることで、安定してターミナルを使用できる。

#### 受け入れ条件

1. WHEN CP の読み取りコールバック（`provReadBuffer`、`provTabCount` 等）が呼ばれたとき、THE Control_Plane SHALL UI スレッドの `surfaces` リストをロックなしに直接読まない（H1: CRITICAL）。
2. WHEN `controlPlaneCaptureTail` が呼ばれたとき、THE Control_Plane SHALL ターミナルバッファの全走査を避け、キャッシュされたスナップショットを返す（H2: HIGH）。
3. WHEN `drainMailbox` が長時間実行されるとき、THE App SHALL 一定時間または一定バイト数で処理を中断し、メッセージポンプに制御を返す（H4: MEDIUM）。
4. IF `surfaces` リストへの並行アクセスが発生したとき、THEN THE App SHALL データ競合を防ぐために Mutex で保護する（H1 の修正案）。

**実装状態: ❌ 未対処**
- `docs/hang-analysis.md` に詳細分析あり
- H1（CRITICAL）: パイプスレッドからの `surfaces` 直接読み取り
- H2（HIGH）: `viewportString` の O(n) 走査
- H4（MEDIUM）: `drainMailbox` の tick 上限なし

---

### 要件 15: Phase 6 実機確認

**ユーザーストーリー:** 開発者として、PLAN.md Phase 6 の未確認項目を実機で検証したい。そうすることで、実装が正しく動作することを確認できる。

#### 受け入れ条件

1. WHEN 日本語 IME で文字を入力したとき、THE IME SHALL 変換・確定が正しく動作する（`winui3-phase6-ime-japanese.ps1` で検証）。
2. WHEN Ctrl+T でタブを追加したとき、THE TabView SHALL 新しいタブが表示され切り替えられる（`winui3-phase6-tabview-switch.ps1` で検証）。
3. WHEN ターミナルタイトルが変更されたとき、THE TabView SHALL タブヘッダーが追従する（`winui3-phase6-tab-title-follow.ps1` で検証）。
4. WHEN アプリを正常終了したとき、THE App SHALL segfault なしに終了する（`winui3-phase6-exit-clean.ps1` で検証）。
5. WHEN ウィンドウをリサイズしたとき、THE Surface SHALL クラッシュなしにリサイズを処理する（`winui3-phase6-resize.ps1` で検証）。
6. WHEN Ctrl+T/Ctrl+W を操作したとき、THE TabView SHALL タブの追加・削除が正しく動作する（`winui3-phase6-tab-shortcuts.ps1` で検証）。

**実装状態: ⚠️ 一部確認済み / 一部未確認**
- ReleaseSafe ビルド動作確認済み
- Debug ビルド動作確認済み
- IME 日本語入力・タブ表示・exit segfault・リサイズ・Ctrl+T/W は実機確認待ち

---

## 受け入れゲート一覧

| ゲート | コマンド | 用途 |
|--------|---------|------|
| ローカルビルドゲート | `zig build -Dapp-runtime=winui3 -Drenderer=d3d11` | ビルド確認 |
| ローカル受け入れゲート | `pwsh -File .\scripts\winui3-contract-check.ps1 -Build` | コントラクト検証 |
| クロスリポジトリゲート | `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1` | 外部リポジトリ整合性 |
| スクロールバー目視確認 | `pwsh -File .\scripts\winui3-scrollbar-smoke.ps1 -NoBuild` | スクロールバー表示確認 |

---

## 実装状態サマリー

### ✅ 完了済み

| 機能 | 主要ファイル |
|------|------------|
| ビルドシステム統合（winui3 apprt 登録） | `src/apprt/runtime.zig` |
| XAML Islands ウィンドウ表示 | `island_window.zig`、`nonclient_island_window.zig` |
| D3D11 レンダリング（SwapChainPanel） | `Surface.zig`、`surface_binding.zig` |
| TabView タブ追加・閉じ・切り替え | `tab_manager.zig`、`tabview_runtime.zig` |
| 英語キーボード入力 | `input_runtime.zig`、`key.zig` |
| IME インフラ（TSF パス） | `ime.zig`、`tsf.zig`、`tsf_bindings.zig`、`tsf_logic.zig` |
| ドラッグバー（カスタムタイトルバー） | `nonclient_island_window.zig` |
| コントロールプレーン（IPC） | `control_plane.zig`、`ipc.zig` |
| スクロールバー | `Surface.zig`（surface_grid） |
| プロファイルメニュー表示 | `profile_menu.zig`、`profiles.zig` |
| デバッグビルド最適化（`-Dslow-safety`） | ビルドシステム |

### ⚠️ 部分実装・実機確認待ち

| 機能 | 状態 | 参照 |
|------|------|------|
| IME 日本語入力（実機確認） | インフラ実装済み、実機未確認 | PLAN.md Phase 6 |
| プロファイルメニュー クリックハンドラ | 表示のみ、クリック未接続 | `profile_menu.zig:24` |
| Phase 6 実機確認項目 | 一部スクリプト準備済み | `scripts/winui3-phase6-*.ps1` |

### ❌ 未実装

| 機能 | 優先度 | 参照 |
|------|--------|------|
| コンテキストメニュー | 中 | `App.zig:1967` |
| ペースト確認ダイアログ | 中 | `Surface.zig:826` |
| CP の tab_index ルーティング | 低 | `control_plane.zig:532` |
| インスペクター | 低 | `Surface.zig` `redrawInspector()` |
| H1: CP 読み取りコールバックのスレッド安全化 | **CRITICAL** | `docs/hang-analysis.md` |
| H2: viewportString キャッシュ化 | HIGH | `docs/hang-analysis.md` |
| H4: drainMailbox tick 上限 | MEDIUM | `docs/hang-analysis.md` |
