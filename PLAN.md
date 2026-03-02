# Ghostty Windows GUI 実装計画

## 方針

`win32` apprt を Zig で新規実装し、単一の `.exe` としてビルドする。
macOS が Swift アプリ + libghostty (embedded apprt) で実現しているのと異なり、
Linux の GTK apprt と同じパターン — Zig コードで直接 Win32 API を呼び、単一バイナリにする。

### なぜ embedded (C API) アプローチを取らないか
- `embedded.zig` は `@import("objc")` 等 macOS 固有コードに依存
- ghostty.h の platform enum に Windows が無い
- Win32 ホストを別途 C で書いてリンクするより、Zig で直接 apprt を書く方が統合が簡潔

## ステップ

### Step 1: ビルドシステムに `win32` runtime を追加

**ファイル: `src/apprt/runtime.zig`**
- `Runtime` enum に `win32` を追加
- `default()` で `.windows => .win32` を返す

**ファイル: `src/apprt.zig`**
- `runtime` の switch に `.win32 => win32` を追加
- `pub const win32 = @import("apprt/win32.zig");` を追加

**ファイル: `src/build/Config.zig`**
- `ApprtRuntime` に `win32` を追加（ビルドオプション `-Dapp-runtime=win32`）

### Step 2: 最小限の win32 apprt を作成

**新規ファイル: `src/apprt/win32.zig`**

GTK apprt (20K行) のような完全実装ではなく、まず「窓が出てターミナルが表示される」
最小構成を目指す。参考: `none.zig` (20行) → これを拡張する形。

```
App struct:
  - core_app: *CoreApp
  - hwnd: HWND (メインウィンドウ)
  - hglrc: HGLRC (OpenGL コンテキスト)

  init()   → RegisterClassW + CreateWindowExW + WGL初期化 + CoreApp初期化
  run()    → Win32 メッセージループ (GetMessage/TranslateMessage/DispatchMessage)
  terminate() → PostQuitMessage + クリーンアップ
  wakeup() → PostMessageW(WM_USER) でメッセージループを起こす
  performAction() → MVP では quit/new_window のみ処理、他は false 返却
  performIpc() → false 返却 (MVP)
  redrawInspector() → no-op (MVP)

Surface struct:
  - app: *App
  - core_surface: CoreSurface
  - size: apprt.SurfaceSize
  - content_scale: apprt.ContentScale

  init()  → CoreSurface 初期化、サイズ設定
  deinit() → CoreSurface クリーンアップ
  core() → &self.core_surface
  rtApp() → self.app
  close() → DestroyWindow
  getTitle() → ウィンドウタイトル取得
  getContentScale() → GetDpiForWindow で DPI スケール計算
  getSize() → self.size 返却
  getCursorPos() → GetCursorPos + ScreenToClient
  supportsClipboard() → standard のみ true
  clipboardRequest() → OpenClipboard + GetClipboardData
  setClipboard() → OpenClipboard + SetClipboardData
  defaultTermioEnv() → 環境変数マップ
```

### Step 3: Win32 ウィンドウプロシージャ

WndProc で以下のメッセージを処理:

| Win32 メッセージ | 処理 |
|---|---|
| WM_CREATE | OpenGL コンテキスト作成 |
| WM_SIZE | `surface.core_surface.updateSize()` |
| WM_PAINT | `surface.core_surface.renderer.drawFrame()` + SwapBuffers |
| WM_KEYDOWN/WM_KEYUP | VK → ghostty key enum 変換 → `core_surface.keyCallback()` |
| WM_CHAR | UTF-16 → UTF-8 変換 → `core_surface.textCallback()` |
| WM_MOUSEMOVE | `core_surface.mouseMotionCallback()` |
| WM_LBUTTONDOWN 等 | `core_surface.mouseButtonCallback()` |
| WM_MOUSEWHEEL | `core_surface.scrollCallback()` |
| WM_CLOSE | `surface.close()` |
| WM_DESTROY | PostQuitMessage |
| WM_DPICHANGED | content scale 更新 |
| WM_USER | wakeup 処理 (mailbox tick) |

### Step 4: OpenGL コンテキスト (WGL)

```
1. GetDC(hwnd)
2. ChoosePixelFormat (RGBA, 24bit depth, double buffer)
3. SetPixelFormat
4. wglCreateContext
5. wglMakeCurrent
6. GLAD で OpenGL 関数ロード (既に vendor/glad/ にある)
```

### Step 5: キーマッピング

Win32 VK_* → Ghostty `input.Key` のマッピングテーブルを作成。
W3C UIEvents spec ベースなので比較的素直に対応する:

```
VK_BACK → .backspace
VK_TAB → .tab
VK_RETURN → .enter
VK_ESCAPE → .escape
VK_SPACE → .space
0x41-0x5A → .a - .z
0x30-0x39 → .digit_0 - .digit_9
VK_F1-VK_F24 → .f1 - .f24
VK_LEFT/RIGHT/UP/DOWN → .arrow_*
VK_SHIFT → .shift_left (GetKeyState で左右判定)
VK_CONTROL → .control_left
VK_MENU → .alt_left
等
```

### Step 6: ビルド・テスト

```bash
zig build -Dapp-runtime=win32 -Drenderer=opengl
./zig-out/bin/ghostty.exe
```

## 並列タスク分割

| タスク | 依存 | 担当 |
|---|---|---|
| A: runtime.zig + apprt.zig + Config.zig 修正 | なし | agent-1 |
| B: win32.zig App 骨格 (init/run/terminate) | A | agent-2 |
| C: VK→Key マッピングテーブル | なし | agent-3 |
| D: WGL OpenGL 初期化 | B | agent-2 |
| E: WndProc イベントハンドリング | B, C | agent-2 |
| F: Surface 実装 + CoreSurface 統合 | B | agent-4 |
| G: ビルド・デバッグ | 全部 | lead |

## MVP のスコープ

含む:
- 単一ウィンドウ
- ターミナル表示 (OpenGL レンダリング)
- キーボード入力 → シェル
- マウス基本操作
- ウィンドウリサイズ
- DPI 対応
- クリップボード (コピー/ペースト)

含まない (将来):
- タブ
- スプリット
- IME (日本語入力)
- 設定ダイアログ
- システムトレイ
- ドラッグ&ドロップ

---

## 進捗

### Phase 0: 手書き COM vtable で WinUI3 ウィンドウ表示 — 完了 (2026-03-02)
- `src/apprt/winui3/` に手書き COM vtable ベースの WinUI3 apprt を作成
- **発見したバグ (12件)**:
  - IID 4個全滅（WinMD 未参照で生成していた）
  - vtable スロット3箇所ズレ（get_Dispatcher 欠落、SetTitleBar/get_AppWindow 位置間違い）
  - Application.Start パターン、Application 生成順序の問題
- → 手書き COM は維持不可能。自動生成ツールが必要

### winmd2zig ツール — 完了 (2026-03-02)
- **リポ**: github.com/YuujiKamura/winmd2zig (private)
- **機能**: `.winmd` → Zig extern struct (IID + 全スロット順 VTable) を stdout 出力
- ECMA-335 バイナリパース: PE → CLI Header → Metadata Root → #~ Tables
- 検証済み: IWindow, IApplication, IApplicationStatics, IApplicationFactory, ITabView
- 全 IID + slot 順序が WinMD と完全一致

### Phase 1: winmd2zig で com.zig を検証 — 結果: 機能的変更なし (2026-03-02)
- winmd2zig 出力と手書き com.zig を突合 → IID・スロット順序が完全一致
- Phase 0 の手動修正が既に正しかったため、コメント追加のみで機能変更ゼロ
- **反省**: Phase 丸ごと使って実質コメント追加だけ。ウィンドウ表示に進捗なし
- ビルド確認: `zig build -Dapp-runtime=winui3 -Drenderer=d3d11` 成功

### Phase 2: WinUI3 ウィンドウ表示 + ターミナル描画 — 動作確認 (2026-03-02)
- initXaml 後に Surface (CoreSurface + SwapChainPanel) を作成
- SwapChainPanel を IWindow.putContent で直接設定 (TabView スキップ、MVP)
- **問題: `ISwapChainPanelNative::SetSwapChain` が `RPC_E_WRONG_THREAD` (0x8001010e)**
  - 原因: D3D11 renderer thread から UI thread 専用 COM を呼んでいた
  - 修正: `bindSwapChain` を非同期化。ポインタ保持 + `WM_USER+1` で UI thread に転送
- **結果**:
  - D3D11 device 作成 ✓, swap chain (composition) 作成 ✓
  - renderer thread 起動、~62fps (709 frames/11.5s)
  - cmd.exe シェル起動、ターミナルタイトル変更動作
  - JetBrains Mono フォントロード成功
  - **exit 時 segfault あり** (timeout 強制終了時。close 順序の問題、要修正)
- 未確認: 画面に実際にターミナルテキストが見えるか (ログ上は描画成功)

### Phase 3: キーボード入力 — 英語OK・日本語NG (2026-03-02)
- **問題: 親HWNDにキーイベントが来ない**
  - 原因: WinUI3が子HWNDを作り、そこにキーボードフォーカスを設定
  - 修正: 子HWNDにもサブクラスを設置 (`GetWindow(GW_CHILD)` → `SetWindowSubclass`)
- **結果**: 英語キーボード入力OK、cmd.exeに文字が送られる
- **未解決: 日本語IME入力不可**
- exit時segfault残存（timeout強制終了時のみ）

### Phase 4: IME・Tab・安定化 — 実装完了 (2026-03-02)
- **IME (日本語入力) 修正**
  - 原因: WinUI3 の TSF (Text Services Framework) が子HWND上のIMM32メッセージを横取り
  - 修正: 専用入力HWND (`GhosttyInputOverlay`) を作成し、WinUI3のXAML入力ツリー外でIMEメッセージを受信
  - WM_IME_STARTCOMPOSITION/COMPOSITION/ENDCOMPOSITION → preeditCallback + WM_CHAR で確定文字送信
  - WM_SETFOCUS リダイレクトで input_hwnd にフォーカスを集約
- **exit時segfault修正**
  - 原因: Application.Start() のXAMLメッセージループが終了せず、強制killで解放済みメモリにアクセス
  - 修正: IApplication.Exit() でメッセージループを正常終了。terminate()のクリーンアップ順序を修正（サブクラス除去→surfaces→COM→WinRT）
- **TabView復活**
  - initXaml step 7.5 で TabView 作成、Window.putContent に設定
  - 初期Surface を TabViewItem として追加
  - TabCloseRequested/AddTabButtonClick/SelectionChanged イベント登録
  - Ctrl+T (新規タブ) / Ctrl+W (閉じる) は performAction 経由で接続済み
- **未確認**: 実機テスト（IME動作、TabView表示、segfault解消）

### Phase 5: 実機テスト・安定化 — 未着手
- IME 日本語入力の実機確認
- TabView の表示・切り替え確認
- exit segfault が解消されたか確認
- リサイズ動作確認
- ReleaseSafe ビルドでの動作確認
