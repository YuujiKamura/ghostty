# 要件ドキュメント — スペック管理の整備

## はじめに

本ドキュメントは `ghostty-win` リポジトリにおけるスペック管理の問題を解決するための要件を定義します。

現状、「今何をすべきか」「何が完了しているか」が一箇所にまとまっておらず、
PLAN.md の完了記録と TODO の混在、`docs/plans/` の完了追跡なし、
チャット記憶への依存、テスト実行可能性の不明確さという 4 つの問題が存在します。

本スペックは `NON-NEGOTIABLES.md` の「チャット記憶を WinUI3 の真実の源泉として扱うな」ルールを
構造的に強化し、既存の `docs/winui3-playbook.md` および `contracts/` の仕組みを壊さずに
スペック管理を整備することを目的とします。

---

## 用語集

- **Spec_System**: `.kiro/specs/` 以下のスペック管理システム全体。
- **PLAN_md**: リポジトリルートの `PLAN.md`。現在は完了記録と TODO が混在している。
- **Plan_Doc**: `docs/plans/` 以下の個別プランドキュメント（例: `2026-03-13-xaml-islands-migration.md`）。
- **Status_Marker**: タスクの完了状態を示すマーカー（`[x]` 完了 / `[ ]` 未着手 / `[-]` 進行中）。
- **Work_Frontier**: 現在着手すべきタスクの集合。一見して識別できる必要がある。
- **Durable_Finding**: チャット記憶ではなく、ドキュメント・テスト・Issue に記録された知見。
- **Test_Status_Record**: テストの現在のパス/フェイル状態を記録したドキュメント。
- **受け入れゲート**: `pwsh -File .\scripts\winui3-contract-check.ps1 -Build` によるローカル検証。
- **クロスリポジトリゲート**: `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1` による外部検証。

---

## 要件

---

### 要件 1: PLAN.md の完了記録と TODO の分離

**ユーザーストーリー:** 開発者として、PLAN.md を見たときに「今の作業フロンティア」が一目でわかるようにしたい。そうすることで、チャット記憶に頼らずに次に何をすべきかを判断できる。

#### 受け入れ条件

1. THE PLAN_md SHALL 完了済みフェーズ（Phase 0〜5）と未完了タスク（Phase 6 以降）を明確に分離したセクション構造を持つ。
2. WHEN 開発者が PLAN_md を開いたとき、THE PLAN_md SHALL 未完了タスクのセクションが完了済みセクションより視覚的に前面に配置されている。
3. THE PLAN_md SHALL 各フェーズに `Status: 完了 | 進行中 | 未着手` のいずれかを明示するヘッダーラベルを持つ。
4. WHEN 新しいタスクが完了したとき、THE PLAN_md SHALL 完了済みセクションへの移動または Status ラベルの更新によって状態変化を反映する。
5. THE PLAN_md SHALL 「現在の作業フロンティア」セクションを最上部に持ち、今着手すべきタスクのみを列挙する。

---

### 要件 2: docs/plans/ プランドキュメントの完了追跡

**ユーザーストーリー:** 開発者として、`docs/plans/` 以下のプランドキュメントを見たときに各タスクの実装状態がわかるようにしたい。そうすることで、ソースコードを読まずに何が実装済みかを判断できる。

#### 受け入れ条件

1. THE Plan_Doc SHALL 各タスクに Status_Marker（`[x]` 完了 / `[ ]` 未着手 / `[-]` 進行中）を付与する。
2. WHEN タスクが実装完了したとき、THE Plan_Doc SHALL 対応するタスクの Status_Marker を `[x]` に更新する。
3. THE Plan_Doc SHALL ドキュメント先頭に完了タスク数と全タスク数のサマリー（例: `完了: 3/8`）を持つ。
4. WHEN `docs/plans/2026-03-13-xaml-islands-migration.md` の 8 タスクを評価したとき、THE Plan_Doc SHALL 各タスクに現在の実装状態を反映した Status_Marker を持つ。
5. THE Plan_Doc SHALL 最終更新日時を先頭メタデータに記録する。

---

### 要件 3: チャット記憶依存の排除と Durable Finding の促進

**ユーザーストーリー:** 開発者として、WinUI3 の動作に関する知見がドキュメント・テスト・Issue に記録されるようにしたい。そうすることで、NON-NEGOTIABLES.md の「チャット記憶を真実の源泉にするな」ルールを構造的に守れる。

#### 受け入れ条件

1. THE Spec_System SHALL 新しい WinUI3 の知見を記録する際に `docs/winui3-playbook.md`、`docs/winui3-known-good-apis.md`、テストスクリプト、または GitHub Issue のいずれかを記録先として要求する。
2. WHEN 開発者が新しい WinUI3 の動作を発見したとき、THE Spec_System SHALL その知見を Durable_Finding として `docs/winui3-playbook.md` または `docs/winui3-known-good-apis.md` に追記することを要求する。
3. THE `docs/winui3-playbook.md` SHALL 「Working Rules For Future Agents」セクションに「チャット記憶を真実の源泉として使用してはならない」ルールを明示的に記載する（現在記載済み、維持すること）。
4. THE Spec_System SHALL `.kiro/specs/` 以下の各スペックに、対応する Durable_Finding の参照先（ドキュメント・テスト・Issue）を受け入れ条件として含める。
5. IF 開発者がチャット記憶のみを根拠として WinUI3 の動作を主張したとき、THEN THE Spec_System SHALL その主張を受け入れゲートまたはテストスクリプトで検証することを要求する。

---

### 要件 4: .kiro/specs/ を権威ある単一ドキュメントとして確立

**ユーザーストーリー:** 開発者として、「次に何を実装すべきか」を `.kiro/specs/` を見れば判断できるようにしたい。そうすることで、PLAN.md・docs/plans/・チャット記憶の複数箇所を参照する必要をなくせる。

#### 受け入れ条件

1. THE Spec_System SHALL `ghostty-win` の実装タスクを `.kiro/specs/` 以下のスペックとして管理する。
2. THE Spec_System SHALL 各スペックに `requirements.md`、`design.md`、`tasks.md` の 3 ドキュメントを持つ。
3. WHEN 新しい実装タスクが発生したとき、THE Spec_System SHALL `.kiro/specs/` に対応するスペックを作成することを要求する。
4. THE Spec_System SHALL `contracts/winui-contract.json` が定義する「壊してはいけないもの」と、`.kiro/specs/` が定義する「次に実装すべきもの」を補完関係として維持する。
5. THE Spec_System SHALL `docs/winui3-playbook.md` および `contracts/` の既存の仕組みを上書きせず、参照関係として連携する。
6. WHEN 開発者が `.kiro/specs/` の `tasks.md` を参照したとき、THE Spec_System SHALL 各タスクに Status_Marker が付与されており、現在の作業フロンティアが識別できる状態を維持する。

---

### 要件 5: テスト実行可能性の継続的記録

**ユーザーストーリー:** 開発者として、現在どのテストがパスしているかを `tests/TEST_AUDIT.md` を見れば確認できるようにしたい。そうすることで、2026-03-27 時点のスナップショットに依存せず、最新のテスト状態を把握できる。

#### 受け入れ条件

1. THE Test_Status_Record SHALL `tests/TEST_AUDIT.md` に最終更新日時を記録する。
2. WHEN テストスクリプトを実行したとき、THE Test_Status_Record SHALL パス/フェイルの結果を `tests/TEST_AUDIT.md` に反映する手順を定義する。
3. THE Test_Status_Record SHALL `tests/self_diagnosis/` の 20 テストと `tests/winui3/` の 13 テストそれぞれについて、現在の実行可能状態（パス / フェイル / 環境依存 / 未実行）を記録する。
4. WHEN `tests/TEST_AUDIT.md` の内容が 30 日以上更新されていないとき、THE Test_Status_Record SHALL 更新が必要であることを先頭に警告として表示する。
5. THE Test_Status_Record SHALL `tests/TEST_AUDIT.md` の「推奨アクション」セクションに未解決の問題（`test_preedit_dirty.ps1` のアサーション修正等）を残存タスクとして記録する。

---

### 要件 6: スペック管理ルールの AGENTS.md への明文化

**ユーザーストーリー:** 開発者として、スペック管理のルールが `AGENTS.md` に記載されているようにしたい。そうすることで、新しいエージェントや開発者がスペック管理の方針を最初から把握できる。

#### 受け入れ条件

1. THE `AGENTS.md` SHALL `.kiro/specs/` を権威ある実装タスク管理の場所として明示するセクションを持つ。
2. THE `AGENTS.md` SHALL 「新しい実装タスクは `.kiro/specs/` にスペックを作成してから着手する」ルールを記載する。
3. THE `AGENTS.md` SHALL 「チャット記憶を WinUI3 の真実の源泉として使用してはならない」ルールを `NON-NEGOTIABLES.md` への参照とともに記載する。
4. THE `AGENTS.md` SHALL `PLAN.md` の役割（完了記録 + 現在フロンティア）と `.kiro/specs/` の役割（詳細スペック）の使い分けを説明する。
5. WHEN 開発者が `AGENTS.md` を読んだとき、THE `AGENTS.md` SHALL スペック管理に関するルールを 5 分以内に把握できる構成を持つ。

---

## 受け入れゲート一覧

| ゲート | コマンド | 用途 |
|--------|---------|------|
| ローカルビルドゲート | `zig build -Dapp-runtime=winui3 -Drenderer=d3d11` | ビルド確認 |
| ローカル受け入れゲート | `pwsh -File .\scripts\winui3-contract-check.ps1 -Build` | コントラクト検証 |
| クロスリポジトリゲート | `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1` | 外部リポジトリ整合性 |

本スペックの変更（ドキュメント整備）は上記ゲートに影響しないが、
変更後もゲートがパスすることを確認すること。

---

## 既存の仕組みとの関係

| 既存の仕組み | 本スペックとの関係 |
|------------|-----------------|
| `contracts/winui-contract.json` | 「壊してはいけないもの」を定義。本スペックは上書きしない。 |
| `contracts/vtable_manifest.json` | COM vtable の正しさを定義。本スペックは上書きしない。 |
| `docs/winui3-playbook.md` | WinUI3 の知見の記録先。本スペックは参照先として活用する。 |
| `NON-NEGOTIABLES.md` | 本スペックはこのルールを構造的に強化する方向で設計されている。 |
| `tests/TEST_AUDIT.md` | テスト状態の記録先。本スペックは更新手順を定義する。 |
