# 実装計画: スペック管理の整備

## 概要

`PLAN.md`、`docs/plans/*.md`、`AGENTS.md`、`tests/TEST_AUDIT.md` の 4 種類のドキュメントを整備し、
「今何をすべきか」が一目でわかるスペック管理体制を確立する。
ソースコードの変更はなく、すべてドキュメントファイルの編集と検証スクリプトの作成が対象。

## タスク

- [x] 1. PLAN.md を再構成する
  - [x] 1.1 PLAN.md の先頭に「現在の作業フロンティア」テーブルを追加する
    - ファイル先頭（方針セクションより前）に `## 現在の作業フロンティア` セクションを作成する
    - Phase 6 の進行中タスクを要約したテーブル（タスク / Status / 詳細）を記載する
    - _要件: 1.2, 1.5_
  - [x] 1.2 PLAN.md に「未完了タスク」セクションを作成し Phase 6 を移動する
    - `## 未完了タスク` セクションを作成する
    - 既存の「Phase 6: 実機テスト」ブロックをこのセクションに移動する
    - Phase 6 ヘッダーに `Status: 進行中` ラベルを付与する
    - _要件: 1.1, 1.3_
  - [x] 1.3 PLAN.md に「完了済みフェーズ」セクションを作成し Phase 0〜5 を集約する
    - `## 完了済みフェーズ` セクションを作成する
    - Phase 0〜5 の各ヘッダーに `Status: 完了` ラベルを付与する
    - 完了済みフェーズをこのセクションに集約する
    - _要件: 1.1, 1.3_
  - [x] 1.4 PLAN.md の方針・ステップ詳細を末尾の「参考」セクションに移動する
    - `## 方針・背景（参考）` セクションを末尾に作成する
    - 既存の「方針」「ステップ」「並列タスク分割」「MVP のスコープ」セクションをこのセクションに移動する
    - _要件: 1.2_
  - [ ]* 1.5 PLAN.md の構造を正規表現で検証する
    - `Status: (完了|進行中|未着手)` パターンが全フェーズヘッダーに存在することを確認する
    - 「現在の作業フロンティア」セクションがファイル先頭付近（100行以内）に存在することを確認する
    - _要件: 1.3, 1.5_

- [x] 2. docs/plans/*.md に完了追跡を追加する
  - [x] 2.1 docs/plans/2026-03-13-xaml-islands-migration.md の実装状態を調査する
    - 設計ドキュメントの完了判定基準に従い、各 Task の実装状態をファイル存在確認で評価する
    - 判定基準: Task 0 → `src/apprt/runtime.zig` に `winui3_islands` が存在するか
    - 判定基準: Task 1 → `src/apprt/winui3_islands/` ディレクトリが存在するか
    - 判定基準: Task 2 → `src/apprt/winui3/com_native.zig` に `IDesktopWindowXamlSource` が存在するか
    - 判定基準: Task 3 → `src/apprt/winui3_islands/island_window.zig` が存在するか
    - 判定基準: Task 4 → `src/apprt/winui3_islands/nonclient_island_window.zig` が存在するか
    - 判定基準: Task 5 → `src/apprt/winui3_islands/App.zig` が存在するか
    - 判定基準: Task 6 → `src/apprt/winui3_islands/Surface.zig` が存在するか
    - 判定基準: Task 7 → ビルドが通るか（ファイル存在確認のみ）
    - _要件: 2.1, 2.4_
  - [x] 2.2 docs/plans/2026-03-13-xaml-islands-migration.md にメタデータと Status_Marker を追加する
    - ファイル先頭に `---\n最終更新: YYYY-MM-DD\n完了: N/8 タスク\n---` メタデータブロックを追加する
    - 2.1 の調査結果に基づき、各 `## Task N:` ヘッダーに `[x]`/`[ ]`/`[-]` を付与する
    - 判断できない場合は `[-]` を使用し、コメントで不確実性を明記する
    - _要件: 2.1, 2.3, 2.4, 2.5_
  - [x] 2.3 docs/plans/2026-03-12-debug-perf-optimization.md の実装状態を調査する
    - Task 1: `src/build/Config.zig` に `slow_safety` フィールドが存在するか確認する
    - Task 2: `src/build_config.zig` の `slow_runtime_safety` が build_options 経由になっているか確認する
    - Task 3: `build-winui3.sh` に `-Dslow-safety=false` が含まれているか確認する
    - Task 4: `src/apprt/winui3/Surface.zig` のホットパスログが条件付きになっているか確認する
    - Task 5: 性能比較テストは手動実行タスクのため `[-]` とする
    - _要件: 2.1, 2.4_
  - [x] 2.4 docs/plans/2026-03-12-debug-perf-optimization.md にメタデータと Status_Marker を追加する
    - ファイル先頭にメタデータブロックを追加する
    - 2.3 の調査結果に基づき、各 `### Task N:` ヘッダーに Status_Marker を付与する
    - _要件: 2.1, 2.3, 2.5_
  - [x] 2.5 docs/plans/2026-03-03-winui3-foundation-harness.md の実装状態を調査する
    - Task 1: `src/apprt/winui3/debug_harness.zig` が存在するか確認する
    - Task 2: `scripts/winui3-foundation-matrix.ps1` が存在するか確認する
    - Task 3: このドキュメント自体が「運用ルール確立」タスクのため、存在すれば `[x]` とする
    - _要件: 2.1, 2.4_
  - [x] 2.6 docs/plans/2026-03-03-winui3-foundation-harness.md にメタデータと Status_Marker を追加する
    - ファイル先頭にメタデータブロックを追加する
    - 2.5 の調査結果に基づき、各 `### Task N:` ヘッダーに Status_Marker を付与する
    - _要件: 2.1, 2.3, 2.5_
  - [x] 2.7 docs/plans/2026-03-05-winui3-com-generator-requirements.md にメタデータを追加する
    - このファイルはタスク形式でなく要件定義のため、Status_Marker は不要
    - ファイル先頭に `---\n最終更新: YYYY-MM-DD\n種別: 要件定義（タスクなし）\n---` メタデータブロックのみ追加する
    - _要件: 2.3, 2.5_
  - [ ]* 2.8 Property 1 の検証: Plan_Doc の全タスクに Status_Marker が存在することを確認する
    - **Property 1: Plan_Doc の全タスクに Status_Marker が存在する**
    - `docs/plans/*.md` の `## Task` / `### Task` で始まる全ヘッダーに `[x]`/`[ ]`/`[-]` が付与されていることを確認する
    - **Validates: 要件 2.1, 2.4**
  - [ ]* 2.9 Property 2 の検証: Plan_Doc の先頭に完了サマリーが存在することを確認する
    - **Property 2: Plan_Doc の先頭に完了サマリーが存在する**
    - `docs/plans/*.md` の先頭 10 行以内に `完了: N/M` または `種別:` の記載があることを確認する
    - **Validates: 要件 2.3, 2.5**

- [ ] 3. チェックポイント — ここまでのドキュメント変更を確認する
  - PLAN.md を開き、「現在の作業フロンティア」が先頭にあることを目視確認する
  - `docs/plans/2026-03-13-xaml-islands-migration.md` を開き、先頭メタデータと Status_Marker があることを確認する
  - 問題があれば修正してから次のタスクに進む

- [x] 4. AGENTS.md に Spec Management セクションを追加する
  - [x] 4.1 AGENTS.md に「Spec Management」セクションを追加する
    - 既存セクションの末尾（GitHub Policy の後）に `## Spec Management` セクションを追加する
    - 設計ドキュメントで定義した「権威ある情報源」テーブルを追加する
    - 設計ドキュメントで定義した「スペック管理ルール」4 項目を追加する
    - _要件: 6.1, 6.2, 6.3, 6.4_
  - [ ]* 4.2 AGENTS.md の構造を確認する
    - `## Spec Management` セクションが存在することを確認する
    - 「新しい実装タスクは `.kiro/specs/` にスペックを作成してから着手する」ルールが記載されていることを確認する
    - 「チャット記憶を WinUI3 の真実の源泉として使用してはならない」ルールが記載されていることを確認する
    - _要件: 6.1, 6.2, 6.3, 6.5_

- [x] 5. tests/TEST_AUDIT.md を更新する
  - [x] 5.1 tests/TEST_AUDIT.md の先頭に最終更新日時と陳腐化警告を追加する
    - ファイル先頭のタイトル直下に「最終更新」日付と「次回更新期限」（30日後）を追加する
    - 30 日超過時の警告メッセージブロックを追加する
    - _要件: 5.1, 5.4_
  - [x] 5.2 tests/TEST_AUDIT.md に「更新手順」セクションを追加する
    - `## 0. 更新手順` セクションをテスト一覧の前に追加する
    - `tests/self_diagnosis/test_*.ps1` を一括実行する PowerShell コマンドを記載する
    - 更新後の記録方法（4 ステップ）を記載する
    - _要件: 5.2_
  - [x] 5.3 tests/TEST_AUDIT.md のテスト一覧テーブルに「現在の状態」列を追加する
    - `tests/self_diagnosis/` の 20 テストのテーブルに `現在の状態` 列を追加する
    - `tests/winui3/` の 13 テストのテーブルに `現在の状態` 列を追加する
    - 各テストの初期値を `未実行（手動）` または `未実行（静的）` 等で記録する
    - 環境依存テスト（agent-deck 要インストール等）には注記を追加する
    - _要件: 5.3_
  - [ ]* 5.4 Property 5 の検証: TEST_AUDIT.md の全テスト行に実行可能状態が記録されていることを確認する
    - **Property 5: TEST_AUDIT.md の全テスト行に実行可能状態が記録されている**
    - テスト一覧テーブルの全行に「現在の状態」列の値が存在することを確認する
    - **Validates: 要件 5.3**

- [ ] 6. ドキュメント構造検証スクリプトを作成する
  - [ ] 6.1 scripts/validate-spec-docs.ps1 を作成する
    - `docs/plans/*.md` の全タスクヘッダーに Status_Marker が存在することを検証する（Property 1）
    - `docs/plans/*.md` の先頭に完了サマリーが存在することを検証する（Property 2）
    - `.kiro/specs/` の全スペックディレクトリに `requirements.md`、`design.md`、`tasks.md` が揃っていることを検証する（Property 3）
    - `.kiro/specs/` の全 `tasks.md` のタスク行に Status_Marker が存在することを検証する（Property 4）
    - `tests/TEST_AUDIT.md` の全テスト行に「現在の状態」列の値が存在することを検証する（Property 5）
    - 全検証パスで `全プロパティ検証: OK` を出力し、失敗時は `Write-Error` でエラー内容を出力して `exit 1` する
    - _要件: 4.2, 4.6_
  - [ ]* 6.2 Property 3 の検証: 全スペックに 3 ドキュメントが揃っていることを確認する
    - **Property 3: 全スペックに 3 ドキュメントが揃っている**
    - `scripts/validate-spec-docs.ps1` を実行し、`.kiro/specs/` の全スペックに `requirements.md`、`design.md`、`tasks.md` が存在することを確認する
    - **Validates: 要件 4.2**
  - [ ]* 6.3 Property 4 の検証: 全 tasks.md のタスク行に Status_Marker が存在することを確認する
    - **Property 4: 全 tasks.md のタスク行に Status_Marker が存在する**
    - `scripts/validate-spec-docs.ps1` を実行し、全 `tasks.md` のタスク行に Status_Marker が付与されていることを確認する
    - **Validates: 要件 4.6**

- [ ] 7. 最終チェックポイント — 全変更を検証する
  - `scripts/validate-spec-docs.ps1` を実行し、全プロパティ検証が OK であることを確認する
  - `zig build -Dapp-runtime=winui3 -Drenderer=d3d11` を実行し、ビルドゲートがパスすることを確認する
  - `pwsh -File .\scripts\winui3-contract-check.ps1 -Build` を実行し、コントラクト検証がパスすることを確認する
  - 問題があれば修正してから完了とする

## 注記

- `*` 付きのサブタスクは省略可能（MVP では省略してもよい）
- 各タスクは前のタスクの成果物を前提とするため、順番に実行すること
- ソースコードの変更は一切含まない。ビルドゲートへの影響はないが、完了時に確認すること
- `docs/plans/2026-03-05-winrt-com-fix.md` と `docs/plans/2026-03-05-winui3-fontconfig-bootstrap.md` は設計ドキュメントの対象外のため、このスペックでは変更しない
