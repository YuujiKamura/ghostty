# ghostty-win プロジェクトルール

## ビルド
- **WinUI3**: `./build-winui3.sh`（ラッパーが --prefix zig-out-winui3 を強制）
- **Win32**: `zig build -Dapp-runtime=win32 --prefix zig-out-win32`
- `zig build` を直接叩くな。必ずラッパーか `--prefix` を使え

## Git
- push先: `git push fork main`（`fork` = YuujiKamura/ghostty）
- `origin` は ghostty-org/ghostty（upstream、push禁止）

## ハードコードパス禁止
ユーザープロファイルパス、ホームディレクトリ、ドライブレター付き絶対パスをコードに書くな。動的解決（相対パス、環境変数展開等）を使え。

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
