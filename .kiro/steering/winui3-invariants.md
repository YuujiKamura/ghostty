# WinUI3 物理的制約と失敗パターン

このファイルは **物理的制約と過去の失敗の記録** です。
設計判断・方針はここに書きません。
内容を変更する場合は、根拠となる WinMD 出力・ビルドログ・Issue 番号を示すこと。

---

## 受け入れゲート（ビルド成功 ≠ 完了）

WinUI3 のビルドは **必ず `./build-winui3.sh` 経由で実行すること**。

`zig build` を直打ちすると `ZIG_GLOBAL_CACHE_DIR=F:\...`（クロスドライブ）により
`build_runner` の `convertPathArg` で panic する。これは設計通りの挙動であり、
`build-winui3.sh` が `ZIG_GLOBAL_CACHE_DIR` を同一ドライブに強制することで回避している。

```
./build-winui3.sh          # WinUI3 → zig-out-winui3/bin/ghostty.exe
```

Win32 apprt の場合：
```
zig build -Dapp-runtime=win32 --prefix zig-out-win32
```

作業完了を宣言するには以下が全てパスすること：

```
./build-winui3.sh
pwsh -File .\scripts\winui3-contract-check.ps1 -Build
```

クロスリポジトリ変更の場合はさらに：

```
pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1
```

ScrollBar/レイアウト変更の場合はさらに：

```
pwsh -File .\scripts\winui3-scrollbar-smoke.ps1 -NoBuild
```

---

## COM vtable の物理的制約

**vtable スロット順は WinMD が決める。手書きは壊れる。**

- IID とスロット順の正解は `win-zig-bindgen` で WinMD から抽出する
- `com_generated.zig` はジェネレータ向け。手で編集しない
- `com_native.zig` は bindgen の真実ではない。グルーコードとして扱う
- スロットが1つずれると無関係な COM 呼び出しが壊れる（クラッシュ・E_NOINTERFACE）

**過去の失敗：**
- Phase 0 で手書き COM vtable を作成 → IID 4個全滅、スロット3箇所ズレ → 全て作り直し
- IXamlType の `get_BoxedType`（slot 17）を欠落させた → `ActivateInstance` が slot 18 を呼んで vtable 0x2200000000 を返した

**WinUI3 カスタムコントロール（TabView 等）は `RoActivateInstance` で作れない。**
XAML type system 経由（`IXamlMetadataProvider.GetXamlType` → `IXamlType.ActivateInstance`）が必要。

---

## UI スレッド制約

**`ISwapChainPanelNative::SetSwapChain` は UI スレッド専用。**

レンダラースレッドから直接呼ぶと `RPC_E_WRONG_THREAD (0x8001010e)` になる。
`WM_USER` 経由で UI スレッドに転送すること。

**COM の QI・プロパティ設定・XAML レイアウト操作は全て UI スレッドで行う。**

---

## apprt の構造（アップストリームの設計）

**1 ビルド = 1 apprt。コンパイル時に決定される。**

- `src/apprt/runtime.zig` の `Runtime` enum に値を追加する
- `src/apprt.zig` の switch に対応エントリを追加する
- 同じ Windows 向けに複数の apprt を並存させる必要はない

**過去の失敗：**
- `winui3_islands/` を別 apprt として作る計画を立てた → アップストリームの設計に反する
- 実際には `winui3/` apprt の中身を XAML Islands アーキテクチャに直接置き換えるのが正解だった
- `island_window.zig`、`nonclient_island_window.zig` は `winui3/` 直下に実装済み

---

## UIA（UI Automation）の信頼性

**UIA のバウンディングレクタングルは嘘をつく。**

ScrollBar が `is_offscreen` と報告されても、実際には描画されている場合がある。
視覚的な正しさの検証はピクセル差分とランタイムメトリクスで行う（Issue #57）。

---

## 過去に試して失敗したアプローチ

| アプローチ | 失敗の理由 |
|-----------|-----------|
| 手書き COM vtable | IID・スロット順の維持が不可能。WinMD と乖離する |
| `RoActivateInstance` で TabView 作成 | WinUI3 カスタムコントロールは非対応（E_NOTIMPL） |
| `winui3_islands/` を別 apprt として作成 | アップストリームの 1ビルド=1 apprt 設計に反する |
| レンダラースレッドから `SetSwapChain` 直接呼び出し | `RPC_E_WRONG_THREAD` |
| 子 HWND にサブクラスを設置してキー入力を取得 | WinUI3 が TSF を横取りして IME が壊れる |

---

## チャット記憶を使わない

WinUI3 の動作に関する主張は以下のいずれかで裏付けること：

- `docs/winui3-playbook.md` または `docs/winui3-known-good-apis.md` の記述
- テストスクリプトの実行結果
- GitHub Issue のコード参照付きコメント
- ビルドログ・WinMD 出力

チャット記憶だけを根拠にした主張は採用しない。
