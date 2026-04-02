# XAML Islands Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 新しいapprt `winui3_islands` を作成し、XAML Islands (`CreateWindowEx` + `DesktopWindowXamlSource`) でウィンドウを構築する。既存`winui3` apprtは一切変更しない。Windows Terminal準拠のモジュール構成でトレーサビリティを確保する。

**Architecture:** Windows Terminalと同じ3層構造:
- `IslandWindow` — Win32 HWND + DesktopWindowXamlSource
- `NonClientIslandWindow` — DWM frame拡張 + カスタムタイトルバー + ドラッグバー
- `App.zig` (AppHost) — オーケストレータ

**Tech Stack:** Zig, Win32 API, WinUI3 (Windows App SDK), COM vtables, D3D11, DWM

**ビルド:** `zig build -Dapp-runtime=winui3_islands --prefix zig-out-winui3-islands`

---

## モジュール対応表 (Windows Terminal → ghostty-win)

| Windows Terminal (C++) | ghostty-win `winui3_islands` (Zig) | 責務 |
|---|---|---|
| `IslandWindow` | `island_window.zig` | CreateWindowEx + DesktopWindowXamlSource + WM_SIZE |
| `NonClientIslandWindow` | `nonclient_island_window.zig` | DWM拡張 + WM_NCHITTEST + WM_NCCALCSIZE + ドラッグバー |
| `AppHost` | `App.zig` | オーケストレータ (core_app接続, performAction, wakeup) |
| `_dragBarWindow` | `drag_bar.zig` | 透明子ウィンドウ、タイトルバーマウス入力傍受 |
| `TerminalPage` | `tabview_runtime.zig` | TabView管理 |
| `TermControl` | `Surface.zig` | D3D11 SwapChainPanelレンダリング面 |

**Ghosttyコアとの関係:** コア(`src/App.zig`, `src/Surface.zig`)は変更不要。apprt境界 (`performAction`, `wakeup`, `core_surface`) は既存winui3と同一インターフェースで実装。

---

## Task 0: ビルドシステムに `winui3_islands` apprt を登録

**Files:**
- Modify: `src/apprt/runtime.zig` — enum に `winui3_islands` 追加
- Modify: `src/apprt.zig` — switch に `.winui3_islands` 追加
- Modify: `src/build/Config.zig` — renderer default条件更新
- Modify: `src/build/SharedDeps.zig` — non-GTK group に追加
- Modify: `build.zig` — WinUI3固有ビルドステップに `winui3_islands` 追加
- Create: `src/apprt/winui3_islands.zig` — モジュールエントリ
- Create: `build-winui3-islands.sh` — ビルドラッパー

**Step 1: runtime.zig に enum追加**

```zig
pub const Runtime = enum {
    none,
    gtk,
    win32,
    winui3,
    winui3_islands,  // ← 追加
```

**Step 2: apprt.zig に switch追加**

```zig
.winui3_islands => winui3_islands,
```

```zig
pub const winui3_islands = @import("apprt/winui3_islands.zig");
```

**Step 3: Config.zig renderer default**

```zig
) orelse if (config.app_runtime == .winui3 or config.app_runtime == .winui3_islands) .d3d11 else ...
```

**Step 4: SharedDeps.zig**

```zig
.none, .win32, .winui3, .winui3_islands => {},
```

**Step 5: build.zig WinUI3条件**

WinUI3のBootstrap DLLステージング等の条件に `winui3_islands` を追加。

**Step 6: winui3_islands.zig エントリ作成**

```zig
pub const App = @import("winui3_islands/App.zig");
pub const Surface = @import("winui3_islands/Surface.zig");
const internal_os = @import("../os/main.zig");
pub const resourcesDir = internal_os.resourcesDir;
```

**Step 7: build-winui3-islands.sh**

```bash
#!/bin/bash
exec zig build -Dapp-runtime=winui3_islands -Dslow-safety=false --prefix zig-out-winui3-islands "$@"
```

**Step 8: コミット**

```bash
git add src/apprt/runtime.zig src/apprt.zig src/apprt/winui3_islands.zig \
        src/build/Config.zig src/build/SharedDeps.zig build.zig build-winui3-islands.sh
git commit -m "feat: register winui3_islands apprt in build system"
```

---

## Task 1: 既存winui3から共有コードをコピー

**Files:**
- Create: `src/apprt/winui3_islands/` ディレクトリ

**方針:** 既存`winui3/`からファイルをコピーして出発点にする。共有可能なファイル（com, winrt, os, ime等）は直接importするか、コピーする。

**共有するファイル (winui3/から直接import):**
- `com.zig`, `com_native.zig`, `com_generated.zig` — COM vtable定義
- `winrt.zig` — WinRT基盤
- `os.zig` — Win32 API宣言
- `ime.zig` — IME処理
- `xaml_helpers.zig` — XAML要素生成ヘルパー
- `bootstrap.zig` — Windows App SDK初期化

**コピーして改変するファイル:**
- `App.zig` → 大幅書き換え (IWindow → IslandWindow)
- `Surface.zig` → 軽微変更 (SwapChainPanel接続は同じ)
- `tabview_runtime.zig` → SetContent先を変更
- `drag_bar.zig` → コピー (ほぼ同じだが親HWNDが違う)

**新規作成するファイル:**
- `island_window.zig` — WT: IslandWindow
- `nonclient_island_window.zig` — WT: NonClientIslandWindow

**Step 1: ディレクトリ作成 + 共有ファイルimport用モジュール**

```bash
mkdir -p src/apprt/winui3_islands
```

共有コードは `@import("../winui3/com.zig")` 等で参照。

**Step 2: Surface.zigをコピー**

Surface.zigはD3D11 SwapChainPanel + core_surface接続で、ウィンドウ方式に依存しない。
ほぼそのままコピーでimportパスだけ調整。

**Step 3: コミット**

```bash
git add src/apprt/winui3_islands/
git commit -m "feat(winui3_islands): scaffold directory with shared imports from winui3"
```

---

## Task 2: COM Interface追加 — IDesktopWindowXamlSource, IDesktopChildSiteBridge

**Files:**
- Modify: `src/apprt/winui3/com_native.zig` (共有ファイルなので既存winui3側に追加)
- Modify: `src/apprt/winui3/com.zig` (re-export)

**既存winui3への影響:** インターフェース定義の追加のみ。使用箇所がないのでwinui3ビルドに影響なし。

**Step 1: win-zig-bindgenでIID・vtable調査**

```bash
cd ~/win-zig-bindgen && cargo run -- --search DesktopWindowXamlSource
cd ~/win-zig-bindgen && cargo run -- --search DesktopChildSiteBridge
cd ~/win-zig-bindgen && cargo run -- --search ContentSizePolicy
```

**Step 2: com_native.zigに追加**

```zig
/// Microsoft.UI.Xaml.Hosting.DesktopWindowXamlSource
pub const IDesktopWindowXamlSource = extern struct {
    pub const IID = os.GUID{ ... };
    lpVtbl: *const VTable,
    const VTable = extern struct {
        // IUnknown (0-2) + IInspectable (3-5)
        ...
        // slot 6: get_Content
        // slot 7: put_Content
        // slot 8: Initialize(WindowId)
        // slot 9: get_SiteBridge
        // slot 10: Close
        // slot 11: add_Closed
        // slot 12: remove_Closed
    };
    // Helper methods
    pub fn SetContent(...) !void { ... }
    pub fn Initialize(...) !void { ... }
    pub fn getSiteBridge(...) !*IDesktopChildSiteBridge { ... }
    pub fn Close(...) void { ... }
};

/// Microsoft.UI.Content.DesktopChildSiteBridge
pub const IDesktopChildSiteBridge = extern struct {
    pub const IID = os.GUID{ ... };
    lpVtbl: *const VTable,
    const VTable = extern struct {
        // ResizePolicy, MoveAndResize, MoveInZOrderAtTop, get_WindowId, etc.
    };
};

pub const WindowId = extern struct { Value: u64 };
pub const ContentSizePolicy = enum(i32) { None = 0, ResizeContentToParentWindow = 1, ResizeParentWindowToContent = 2 };
```

**Step 3: コミット**

```bash
git add src/apprt/winui3/com_native.zig src/apprt/winui3/com.zig
git commit -m "feat(winui3): add IDesktopWindowXamlSource/IDesktopChildSiteBridge COM interfaces"
```

---

## Task 3: island_window.zig — WT: IslandWindow

**Files:**
- Create: `src/apprt/winui3_islands/island_window.zig`

**WT対応:** Windows Terminal `IslandWindow` と1:1対応。

```zig
/// XAML Islands host window — Windows Terminal IslandWindow equivalent.
///
/// Responsibilities:
///   - MakeWindow: RegisterClassExW + CreateWindowEx(WS_EX_NOREDIRECTIONBITMAP)
///   - Initialize: DesktopWindowXamlSource.Initialize(WindowId)
///   - OnSize: SiteBridge child HWND sizing
///   - SetContent/Close: XAML root element lifecycle
///
/// Ref: github.com/microsoft/terminal/blob/main/src/cascadia/WindowsTerminal/IslandWindow.cpp

hwnd: os.HWND,
xaml_source: *com.IDesktopWindowXamlSource,
interop_hwnd: ?os.HWND = null,  // SiteBridge child HWND

/// WT: IslandWindow::MakeWindow()
pub fn makeWindow(app_ptr: *anyopaque, wndproc_fn: os.WNDPROC) !IslandWindow

/// WT: IslandWindow::Initialize()
pub fn initialize(self: *IslandWindow) !void

/// WT: IslandWindow::SetContent()
pub fn setContent(self: *IslandWindow, content: ?*anyopaque) !void

/// WT: IslandWindow::OnSize()
pub fn onSize(self: *IslandWindow, width: c_int, height: c_int) void

/// WT: IslandWindow::Close()
pub fn close(self: *IslandWindow) void
```

**核心コード:**

makeWindow — `CreateWindowEx(WS_EX_NOREDIRECTIONBITMAP, WS_OVERLAPPEDWINDOW)`
initialize — `DesktopWindowXamlSource.Initialize(WindowId{.Value=@intFromPtr(hwnd)})` + SiteBridge取得
onSize — `SetWindowPos(interop_hwnd, 0, 0, width, height, SWP_SHOWWINDOW)`
close — `SetContent(null)` → `xaml_source.Close()` (WT leak prevention順序)

**コミット:**

```bash
git add src/apprt/winui3_islands/island_window.zig
git commit -m "feat(winui3_islands): add island_window.zig (WT: IslandWindow)"
```

---

## Task 4: nonclient_island_window.zig — WT: NonClientIslandWindow

**Files:**
- Create: `src/apprt/winui3_islands/nonclient_island_window.zig`

**WT対応:** `NonClientIslandWindow` = IslandWindow + カスタムタイトルバー。

```zig
/// Custom titlebar window — Windows Terminal NonClientIslandWindow equivalent.
///
/// Extends IslandWindow with:
///   - DwmExtendFrameIntoClientArea (glass titlebar)
///   - WM_NCCALCSIZE (system titlebar removal)
///   - WM_NCHITTEST (resize borders)
///   - Drag bar child window (input sink)
///   - Dark mode + caption color
///
/// Ref: github.com/microsoft/terminal/blob/main/src/cascadia/WindowsTerminal/NonClientIslandWindow.cpp

island: IslandWindow,
drag_bar_hwnd: ?os.HWND = null,

/// Create (calls IslandWindow.makeWindow + DWM setup + drag bar).
pub fn create(app_ptr: *anyopaque) !NonClientIslandWindow

/// WT: _OnNcCalcSize — restore original top to remove system titlebar.
pub fn onNcCalcSize(hwnd: os.HWND, wparam: os.WPARAM, lparam: os.LPARAM) os.LRESULT

/// WT: _OnNcHitTest — resize borders + HTCAPTION.
pub fn onNcHitTest(hwnd: os.HWND, lparam: os.LPARAM) os.LRESULT

/// WT: _UpdateFrameMargins — DwmExtendFrameIntoClientArea.
pub fn updateFrameMargins(self: *NonClientIslandWindow) void

/// WT: _UpdateIslandPosition — offset island for top border.
pub fn updateIslandPosition(self: *NonClientIslandWindow, width: c_int, height: c_int) void

/// WT: _InputSinkMessageHandler — drag bar wndproc.
/// (Reuses drag_bar.zig's dragBarWndProc)

/// Main window procedure.
pub fn wndProc(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM) callconv(.winapi) os.LRESULT
```

**wndProc メッセージルーティング:**

```
DwmDefWindowProc → (caption buttons)
WM_NCCALCSIZE → onNcCalcSize
WM_NCHITTEST → onNcHitTest
WM_SIZE → updateIslandPosition + drag_bar.resizeDragBar + app.handleSize
WM_CLOSE → app.requestCloseWindow
WM_DESTROY → PostQuitMessage
WM_TIMER / WM_USER / WM_APP_* / WM_IME_* → app固有ハンドラ
else → DefWindowProcW
```

**コミット:**

```bash
git add src/apprt/winui3_islands/nonclient_island_window.zig
git commit -m "feat(winui3_islands): add nonclient_island_window.zig (WT: NonClientIslandWindow)"
```

---

## Task 5: App.zig — WT: AppHost

**Files:**
- Create: `src/apprt/winui3_islands/App.zig`

**方針:** 既存`winui3/App.zig`をコピーして、IWindow依存をNonClientIslandWindowに置換。

**変更点:**

```zig
// REMOVE:
window: ?*com.IWindow = null,
xaml_island_hwnd: ?os.HWND = null,
child_hwnd: ?os.HWND = null,

// ADD:
nci_window: ?NonClientIslandWindow = null,

// KEEP:
hwnd: ?os.HWND = null,  // nci_window.island.hwndのエイリアス
core_app: *CoreApp,
surfaces: std.ArrayListUnmanaged(*Surface),
// ... 他のapprt interfaceフィールド
```

**initXaml() — WT: AppHost初期化シーケンス:**

```zig
// Step 0: Application creation (COM aggregation) — 変更なし
// Step 1: NonClientIslandWindow.create(self)
var nci = try NonClientIslandWindow.create(self);
// Step 2: IslandWindow.initialize() — DesktopWindowXamlSource.Initialize(WindowId)
try nci.island.initialize();
// Step 3: DWM frame + drag bar
nci.updateFrameMargins();
nci.createDragBarWindow();
self.nci_window = nci;
self.hwnd = nci.island.hwnd;
// Step 4: XAML content (TabView + SwapChainPanel)
// XamlSource.SetContent(root_grid) instead of Window.SetContent(root_grid)
// Step 5: ShowWindow + SetForegroundWindow
```

**IWindow置換マップ:**

| 旧 (IWindow) | 新 (IslandWindow/Win32) |
|---|---|
| `window.activate()` | `ShowWindow(hwnd, SW_SHOWNORMAL)` |
| `window.SetContent(x)` | `nci_window.island.setContent(x)` |
| `window.Content()` | `nci_window.island.xaml_source.getContent()` |
| `window.Close()` | `DestroyWindow(hwnd)` |
| `window.SetTitle(s)` | `SetWindowTextW(hwnd, s)` |
| `IWindowNative.getWindowHandle()` | 不要（hwndは直接所有） |
| `SetWindowSubclass(hwnd, ...)` | 不要（wndprocは直接所有） |

**performAction, wakeup — 変更なし** (同じインターフェース)

**コミット:**

```bash
git add src/apprt/winui3_islands/App.zig
git commit -m "feat(winui3_islands): App.zig as AppHost with NonClientIslandWindow"
```

---

## Task 6: Surface.zig + tabview_runtime.zig + drag_bar.zig

**Files:**
- Create: `src/apprt/winui3_islands/Surface.zig` (winui3/Surface.zigからコピー、importパス調整)
- Create: `src/apprt/winui3_islands/tabview_runtime.zig` (SetContent先変更)
- Create: `src/apprt/winui3_islands/drag_bar.zig` (コピー、ほぼ同一)

**Surface.zig:** D3D11 SwapChainPanel + core_surface接続はウィンドウ方式に依存しない。importパスを`../winui3/`から共有ファイルを参照するよう調整するだけ。

**tabview_runtime.zig:**
```zig
// OLD: window.SetContent(@ptrCast(root_grid_insp))
// NEW: xaml_source.put_Content(@ptrCast(root_grid_insp))
```
関数シグネチャを `*com.IWindow` → `*com.IDesktopWindowXamlSource` に変更。

**drag_bar.zig:** 既存コードそのまま。親HWNDが自前CreateWindowExウィンドウになるので`WS_EX_LAYERED`が正常動作するはず（WinUI3管理HWNDでは失敗していた問題が解消）。

**コミット:**

```bash
git add src/apprt/winui3_islands/Surface.zig src/apprt/winui3_islands/tabview_runtime.zig \
        src/apprt/winui3_islands/drag_bar.zig
git commit -m "feat(winui3_islands): Surface, tabview_runtime, drag_bar"
```

---

## Task 7: os.zig追加 + コンパイル通し

**Files:**
- Modify: `src/apprt/winui3/os.zig` (共有) — 不足API追加

**追加するAPI:**
- `WS_EX_NOREDIRECTIONBITMAP: u32 = 0x00200000`
- `GetWindowLongPtrW` / `SetWindowLongPtrW`
- `GWLP_USERDATA: c_int = -21`
- `CREATESTRUCTW` struct
- `WM_CREATE: UINT = 0x0001`, `WM_DESTROY: UINT = 0x0002`
- `PostQuitMessage` extern
- `CW_USEDEFAULT`
- `SetWindowTextW` extern

**Step 1: API追加**

**Step 2: コンパイル通し**

```bash
./build-winui3-islands.sh 2>&1 | head -50
```

コンパイルエラーを潰す。型の不一致、import不足等。

**Step 3: コミット**

```bash
git add src/apprt/winui3/os.zig
git commit -m "feat(winui3): add Win32 APIs for IslandWindow (shared with winui3_islands)"
```

---

## Task 8: 統合テスト

**ユーザー手動実行** (GUIテスト実行禁止ルール)

```bash
./build-winui3-islands.sh && zig-out-winui3-islands/bin/ghostty.exe
```

テストチェックリスト:
1. ウィンドウ表示
2. **タイトルバードラッグ** ← Issue #95の本題
3. タイトルバーダブルクリック（最大化/復元）
4. 4辺 + 4隅リサイズ
5. Min/Max/Closeボタン (DWM描画)
6. TabView表示 + タブ追加/閉じ
7. ターミナルレンダリング (D3D11)
8. キーボード入力
9. IME (日本語入力)
10. DPIスケーリング

**既存winui3ビルドが壊れていないことも確認:**

```bash
./build-winui3.sh
```

---

## 最終ディレクトリ構造

```
src/apprt/
├── winui3/                        ← 既存 (変更最小限: COM定義追加のみ)
│   ├── App.zig
│   ├── Surface.zig
│   ├── com.zig, com_native.zig    ← IDesktopWindowXamlSource追加 (共有)
│   ├── com_generated.zig          ← 共有
│   ├── os.zig                     ← Win32 API追加 (共有)
│   ├── winrt.zig                  ← 共有
│   ├── ime.zig                    ← 共有
│   ├── xaml_helpers.zig           ← 共有
│   ├── wndproc.zig
│   ├── window_runtime.zig
│   ├── drag_bar.zig
│   ├── tabview_runtime.zig
│   └── ...
│
├── winui3_islands/                ← 新規 (WT準拠モジュール構成)
│   ├── App.zig                    ← WT: AppHost
│   ├── island_window.zig          ← WT: IslandWindow
│   ├── nonclient_island_window.zig ← WT: NonClientIslandWindow
│   ├── Surface.zig                ← WT: TermControl相当
│   ├── tabview_runtime.zig        ← WT: TerminalPage相当
│   ├── drag_bar.zig               ← WT: _dragBarWindow
│   └── (com, os, winrt, ime等はwinui3/から@import)
│
└── winui3_islands.zig             ← モジュールエントリ
```

---

## リスク

1. **Application.Start + DesktopWindowXamlSource互換性**: Application.Start()内でCreateWindowExウィンドウを作り、そこにXamlSourceをInitializeする構成が動くか要検証。ダメなら自前メッセージループ。
2. **IID未確定**: IDesktopWindowXamlSourceのIIDはwin-zig-bindgenで要調査。WinMDから抽出。
3. **SiteBridge API**: ResizePolicyが使えるかは実行時に判明。フォールバックは手動SetWindowPos。
4. **既存winui3 apprt**: com_native.zig/os.zigへのインターフェース追加のみ。使用箇所が増えないのでビルド破壊リスクなし。
