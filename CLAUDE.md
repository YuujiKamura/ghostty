# ghostty-win プロジェクトルール

## ビルド
- **WinUI3**: `./build-winui3.sh`（ラッパーが --prefix zig-out-winui3 を強制）
- **Win32**: `zig build -Dapp-runtime=win32 --prefix zig-out-win32`
- `zig build` を直接叩くな。必ずラッパーか `--prefix` を使え

## テスト gate（毎 commit・スコープ限定）
- 触った module だけテスト、フルスイート全件は脳死
  - 例: `Overlay.zig` 触ったら `ZIG_GLOBAL_CACHE_DIR= zig build test -Dapp-runtime=win32 -Dtest-filter="renderer.Overlay"`
  - `git diff --name-only` で範囲確認 → 関連 module を `-Dtest-filter` で指定
- スコープ内 1 fail = commit 禁止
- 関数単位ピンポイントで commit するな (隣の関数を壊している可能性が残る)。module 単位で回せ
- フルスイート (`zig build test -Dapp-runtime=win32` 無 filter) は **release 前 / broad refactor 後 / 一日の終わり** に回す
- WinUI3 build (`./build-winui3.sh`) は GUI/apprt 触ったときの gate、render/terminal だけなら不要
- 通らないコミットを残すな

## Git
- push先: `git push fork main`（`fork` = YuujiKamura/ghostty）
- `origin` は ghostty-org/ghostty（upstream、push禁止）
- **upstream（ghostty-org/ghostty）への PR 作成は明示的指示なしに禁止**
- イシュー起票先: `YuujiKamura/ghostty`（fork側）。upstream への issue 作成も禁止

## ハードコードパス禁止
ユーザープロファイルパス、ホームディレクトリ、ドライブレター付き絶対パスをコードに書くな。動的解決（相対パス、環境変数展開等）を使え。

## 生成物が古いときはジェネレーター側を疑え（最頻出バグ）
XBF, PRI, com_generated.zig などの生成物と XAML/WinMD ソースの乖離は **最も頻繁に起きるバグ** である。
ランタイムエラー（特に WinRTFailed, RPC_E_WRONG_THREAD, FindName null）が出たら、
コードを疑う **前に** 以下の機械的チェックを実行しろ:

```bash
# 1. prebuilt XBF のタイムスタンプとXAMLソースの最終変更コミットを比較
ls -la xaml/prebuilt/*.xbf
git log --oneline -1 -- xaml/TabViewRoot.xaml xaml/Surface.xaml

# 2. XBF のサイズが XAML の要素数と釣り合ってるか（古いと小さい）
wc -c xaml/prebuilt/*.xbf xaml/obj/x64/Debug/net9.0-windows10.0.22621.0/*.xbf

# 3. 不一致なら再生成コピー（MSBuild 済みの obj/ から）
cp xaml/obj/x64/Debug/net9.0-windows10.0.22621.0/*.xbf xaml/prebuilt/
```

- XBF/PRI 再ビルド: `./build-winui3.sh --release --update-prebuilt` または `zig-xaml-xbf`
- com_generated.zig: `win-zig-bindgen` で再生成
- **不一致なら生成し直せ。コード側をいじるな**

## COM バインディング生成チェーン

### com_generated.zig は手書き禁止
`src/apprt/winui3/com_generated.zig` は **GENERATED CODE - DO NOT EDIT**。
`win-zig-bindgen` が WinMD メタデータから自動生成する。手で書き換えるな。

### ファイル構成
```
com.zig              ← facade（generated + native を re-export）
com_generated.zig    ← win-zig-bindgen が生成（手書き禁止）
com_native.zig       ← 手書きの native COM interop（ISwapChainPanelNative 等）
```

### 関連ツールリポジトリ
| リポ | 場所 | 役割 |
|------|------|------|
| **win-zig-bindgen** | `~/win-zig-bindgen` | WinMD → Zig COM バインディング生成。`com_generated.zig` を出力 |
| **zig-xaml-xbf** | `~/zig-xaml-xbf` | XAML → XBF/PRI コンパイル。MSBuild を経由して XAML バイナリを生成 |

### 再生成コマンド（参考）
`com_generated.zig` 先頭の `//! Command:` 行に生成時のコマンドが記録されている。
新しいインターフェースを追加する場合は `--iface` フラグを追加して再生成。

### インターフェース追加時の手順
1. `win-zig-bindgen` で `--iface` を追加して `com_generated.zig` を再生成
2. `com.zig` に re-export を追加
3. ビルドして型が通ることを確認
4. **com_generated.zig を手で編集して済ませるな**
