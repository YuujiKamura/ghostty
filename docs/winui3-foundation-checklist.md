# WinUI3 基礎構築チェックリスト

目的は「デバッグ」ではなく、参照実装との差分を体系的に潰すこと。

## 0. ルール
- 推測パッチ禁止。差分証拠がある項目だけ触る。
- 1回の変更で1項目だけ進める。
- 変更前後で必ず同じテストコマンドを実行する。

## 1. 参照生成物の固定
- 参照プロジェクト (`winui3-reference`) をビルドした状態にする。
- 生成物を JSON に保存する:

```powershell
pwsh -File .\scripts\winui3-capture-artifacts.ps1 `
  -Root "..\winui3-reference" `
  -OutFile ".\tmp\ref-artifacts.json"
```

## 2. ghostty-win 生成物の収集

```powershell
cd .
zig build -Dapp-runtime=winui3 -Drenderer=d3d11
pwsh -File .\scripts\winui3-capture-artifacts.ps1 `
  -Root "." `
  -OutFile ".\tmp\ghostty-artifacts.json"
```

## 3. 差分レポート生成

```powershell
pwsh -File .\scripts\winui3-diff-artifacts.ps1 `
  -ReferenceJson ".\tmp\ref-artifacts.json" `
  -TargetJson ".\tmp\ghostty-artifacts.json" `
  -OutReport ".\tmp\winui3-artifact-diff.md"
```

## 4. 優先順位
- `*.pri`, `*.xbf`, `*.winmd`, `*.manifest` を最優先。
- つぎに `com.zig` の IID / vtable slot 整合。
- 最後にイベントライフサイクル順序。

## 5. 完了条件
- 差分レポート上で「必要生成物の欠落」が解消。
- `TabView + handlers ON` で再現テストが安定。
- 例外時ログが最小情報で確実に残る。
