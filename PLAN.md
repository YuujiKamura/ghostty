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

### Phase 1: winmd2zig で com.zig を再生成 — 未着手
- winmd2zig の出力で `src/apprt/winui3/com.zig` を置き換える
- 手書きバグ12件が全て解消されることを確認
- ビルドが通ることを確認

### Phase 2: WinUI3 ウィンドウ表示 — 未着手
- 正しい COM vtable でウィンドウが表示されることを確認
- Application.Start + IApplicationFactory.CreateInstance の順序修正

### Phase 3: レンダラ統合 — 未着手
- D3D11 or OpenGL レンダラと CoreSurface の統合

### Phase 4: 入力・イベント処理 — 未着手
- キーボード、マウス、リサイズ、DPI
