# WinUI3 Contract-Check Usage

この仕組みの目的は、推測デバッグをやめて「契約が満たされているか」を一発判定すること。

## 1. 一発チェック

```powershell
pwsh -File .\scripts\winui3-contract-check.ps1 -Build
```

出力:
- `OVERALL: PASS/FAIL`
- 詳細レポート: `tmp/winui3-contract-report.md`
- 生成物差分: `tmp/winui3-artifact-diff.md`

## 1.5 一発修正 + 判定

```powershell
pwsh -File .\scripts\winui3-contract-run.ps1 -Fix -Build
```

`-Fix` は現在、次を自動適用する:
- `create(...)` を `createWithIid(...)` に置換
- TabView ハンドラ登録ブロックを Step8 後へ移動

## 1.6 zig build への統合

WinUI3 ビルド時に契約ワークフローを呼ぶ専用ステップ:

```powershell
zig build -Dapp-runtime=winui3 -Drenderer=d3d11 winui-contract
```

インストール + 契約チェックを直列実行:

```powershell
zig build -Dapp-runtime=winui3 -Drenderer=d3d11 install-winui-validated
```

## 2. ログからIIDを機械抽出

```powershell
pwsh -File .\scripts\winui3-extract-iids.ps1
```

出力:
- `tmp/winui3-iids.json`

## 2.5 Delegate IID 補助スクリプト（パス指定）

`winui3-sync-delegate-iids.ps1` / `winui3-delegate-iid-check.ps1` / `winui3-inspect-event-params.ps1` は、固定絶対パスなしで使える。

- `-RepoRoot`: 対象リポジトリルート（省略時はスクリプト位置から自動解決）
- `-ToolDir`: `winmd2zig` 実体ディレクトリ（`sync` と `inspect` で利用）
- `-ComPath`: 対象 `com.zig` のパス（`sync` で利用）

例:

```powershell
pwsh -File .\scripts\winui3-sync-delegate-iids.ps1 -Check `
  -RepoRoot C:\work\ghostty-win `
  -ToolDir C:\work\win-zig-bindgen `
  -ComPath C:\work\ghostty-win\src\apprt\winui3\com.zig
```

## 3. 契約の編集場所

- 契約定義: `contracts/winui-contract.json`
  - `required_artifact_filenames`
  - `required_reference_filenames`
  - `source_must_contain`
  - `line_order_checks`

## 4. 運用ルール

- `OVERALL=FAIL` の間は個別パッチを入れない。
- 失敗項目を契約単位で潰す。
- 新しいチェックを追加したら、まず契約に反映してから修正する。
