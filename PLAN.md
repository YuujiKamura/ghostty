# Ghostty Windows GUI 実装計画

## 現在の作業フロンティア

| タスク | Status | 詳細 |
|--------|--------|------|
| Phase 6: 実機テスト | 進行中 | IME・TabView・リサイズ・exit segfault の実機確認 |
| ハング問題対処 (H1/H2/H4) | 未着手 | `docs/hang-analysis.md` 参照。H1 は CRITICAL |
| プロファイルメニュー クリックハンドラ | 未着手 | `profile_menu.zig:24` の TODO |
| コンテキストメニュー | 未着手 | `App.zig:1967` の TODO |

詳細タスクは `.kiro/specs/winui3-current-state-inventory/` を参照。

---

## 未完了タスク

### Phase 6: 実機テスト — Status: 進行中 (2026-03-03)
- [ ] IME 日本語入力の実機確認（infrastructure は実装済み）
- [x] TabView の作成確認（ログ上は成功、IXamlType.ActivateInstance 経由）
- [ ] TabView の表示・切り替え実機確認（ユーザー操作が必要）
- [ ] タブタイトルがターミナルタイトルに追従するか確認
- [ ] exit segfault が解消されたか確認（ユーザー操作が必要）
- [ ] リサイズ動作確認（ユーザー操作が必要）
- [x] ReleaseSafe ビルド動作確認（ログ上は全ステップ成功、安定動作）
- [ ] Ctrl+T/Ctrl+W のタブ操作確認（ユーザー操作が必要）
- [x] Debug ビルド動作確認（TabView + Surface + D3D11 + cmd.exe 起動）

---

## 完了済みフェーズ

### Phase 0: 手書き COM vtable で WinUI3 ウィンドウ表示 — Status: 完了 (2026-03-02)
- `src/apprt/winui3/` に手書き COM vtable ベースの WinUI3 apprt を作成
- **発見したバグ (12件)**:
  - IID 4個全滅（WinMD 未参照で生成していた）
  - vtable スロット3箇所ズレ（get_Dispatcher 欠落、SetTitleBar/get_AppWindow 位置間違い）
  - Application.Start パターン、Application 生成順序の問題
- → 手書き COM は維持不可能。自動生成ツールが必要

### winmd2zig ツール — Status: 完了 (2026-03-02)
- **リポ**: github.com/YuujiKamura/winmd2zig (private)
- **機能**: `.winmd` → Zig extern struct (IID + 全スロット順 VTable) を stdout 出力
- ECMA-335 バイナリパース: PE → CLI Header → Metadata Root → #~ Tables
- 検証済み: IWindow, IApplication, IApplicationStatics, IApplicationFactory, ITabView
- 全 IID + slot 順序が WinMD と完全一致

### Phase 1: winmd2zig で com.zig を検証 — Status: 完了 (2026-03-02)
- winmd2zig 出力と手書き com.zig を突合 → IID・スロット順序が完全一致
- Phase 0 の手動修正が既に正しかったため、コメント追加のみで機能変更ゼロ
- **反省**: Phase 丸ごと使って実質コメント追加だけ。ウィンドウ表示に進捗なし
- ビルド確認: `zig build -Dapp-runtime=winui3 -Drenderer=d3d11` 成功

### Phase 2: WinUI3 ウィンドウ表示 + ターミナル描画 — Status: 完了 (2026-03-02)
- initXaml 後に Surface (CoreSurface + SwapChainPanel) を作成
- SwapChainPanel を IWindow.putContent で直接設定 (TabView スキップ、MVP)
- **問題: `ISwapChainPanelNative::SetSwapChain` が `RPC_E_WRONG_THREAD` (0x8001010e)**
  - 原因: D3D11 renderer thread から UI thread 専用 COM を呼んでいた
  - 修正: `bindSwapChain` を非同期化。ポインタ保持 + `WM_USER+1` で UI thread に転送
- **結果**: D3D11 device 作成 ✓, swap chain 作成 ✓, renderer thread 起動 ~62fps

### Phase 3: キーボード入力 — Status: 完了 (2026-03-02)
- **問題**: 親HWNDにキーイベントが来ない → 子HWNDにサブクラスを設置して解決
- **結果**: 英語キーボード入力OK

### Phase 4: IME・Tab・安定化 — Status: 完了 (2026-03-02)
- IME: 専用入力HWND (`GhosttyInputOverlay`) で TSF 横取り問題を解決
- exit segfault: `IApplication.Exit()` でメッセージループを正常終了
- TabView: IXamlType.ActivateInstance 経由で作成、イベントハンドラ登録済み

### Phase 4.5: TabView XAML type system 修正 — Status: 完了 (2026-03-03)
- **問題**: `RoActivateInstance` が E_NOTIMPL → XAML type system 経由に変更
- **バグ**: IXamlType vtable スロットずれ（get_BoxedType slot 17 が欠落）→ winmd2zig で修正
- **結果**: TabView + TabViewItem + イベントハンドラ全て動作

### Phase 5: バグ修正・機能追加 — Status: 完了 (2026-03-03)
- COM参照リーク修正（errdefer 追加）
- フォーカスコールバック追加（WM_SETFOCUS/WM_KILLFOCUS）
- タブタイトル更新（IPropertyValueStatics + boxString()）

---

## 方針・背景（参考）

`win32` apprt を Zig で新規実装し、単一の `.exe` としてビルドする。
macOS が Swift アプリ + libghostty (embedded apprt) で実現しているのと異なり、
Linux の GTK apprt と同じパターン — Zig コードで直接 Win32 API を呼び、単一バイナリにする。

### なぜ embedded (C API) アプローチを取らないか
- `embedded.zig` は `@import("objc")` 等 macOS 固有コードに依存
- ghostty.h の platform enum に Windows が無い
- Win32 ホストを別途 C で書いてリンクするより、Zig で直接 apprt を書く方が統合が簡潔

### MVP のスコープ（参考）

含む: 単一ウィンドウ、ターミナル表示、キーボード入力、マウス基本操作、リサイズ、DPI対応、クリップボード

含まない（将来）: タブ、スプリット、IME、設定ダイアログ、システムトレイ、ドラッグ&ドロップ
