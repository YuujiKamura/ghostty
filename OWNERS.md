# WinUI3 Ownership Rules

このファイルは、`Codex` と `Gemini` の同時作業で同一ファイル競合を防ぐための運用ルールです。

## 1. Ownership (編集担当)

- `Codex` 専有:
  - `src/apprt/winui3/App.zig`
  - `src/apprt/winui3/Surface.zig`
- `Gemini` 専有:
  - `src/apprt/winui3/com.zig`
  - `src/apprt/winui3/winrt.zig`
  - `scripts/winui3-test-lib.ps1`
  - `visual_smoke_test_run.ps1`

## 2. 原則

- 専有ファイルは、担当者以外が直接編集しない。
- どうしても他担当ファイルを変更したい場合は、直接編集せず「パッチ提案（diff）」を渡す。
- 途中状態を共有しない。共有は「ビルド成功」かつ「smoke実行結果付き」のみ。

## 3. 受け渡し手順

1. 変更担当がローカルで検証する:
   - `zig build -Dapp-runtime=winui3 -Drenderer=d3d11 -Doptimize=ReleaseSafe`
2. 変更担当が証跡を添えて共有する:
   - 変更ファイル一覧
   - ビルド結果
   - `debug.log` / `multitab_audit.log` の要点
3. 受け手は自担当ファイルに反映し、再度同じコマンドで検証する。

## 4. Merge Gate

以下を満たさない変更はコミットしない:

- `runtime=.winui3` が監査ログで確認できること
- `zig build -Dapp-runtime=winui3 -Drenderer=d3d11 -Doptimize=ReleaseSafe` が成功すること
- `WinRT HRESULT failed: 0x80004002` が新規増加していないこと

## 5. 非担当への依頼テンプレート

```text
[REQUEST]
target-file:
reason:
expected-behavior:
verification:
```

## 6. 外部リポジトリ保護

- `origin`（本家）へは Push / PR / Issue を行わない。
- 外部リポジトリ操作は、明示指示がある場合のみ実施する。
