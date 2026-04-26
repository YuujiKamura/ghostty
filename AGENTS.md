# AGENTS.md

## Project Scope

`ghostty-win` is the WinUI3 consumer of the external `win-zig-bindgen` and `win-zig-core` workflow.

Read [NON-NEGOTIABLES.md](NON-NEGOTIABLES.md) first.
Then read:
- [docs/winui3-playbook.md](docs/winui3-playbook.md)
- [docs/winui3-known-good-apis.md](docs/winui3-known-good-apis.md)

## Primary Commands

- WinUI3 build smoke: `zig build -Dapp-runtime=winui3 -Drenderer=d3d11`
- Contract build check: `pwsh -File .\scripts\winui3-contract-check.ps1 -Build`
- Full cross-repo acceptance: `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1`

## Workstreams

| Area | Owner | Typical Files |
|------|-------|---------------|
| WinUI3 app logic | one agent | `src/apprt/winui3/App.zig`, `Surface.zig`, `surface_binding.zig` |
| Generated/facade COM layer | one agent | `src/apprt/winui3/com*.zig` |
| Contract scripts/docs | one agent | `scripts/winui3-*.ps1`, `contracts/`, `docs/` |

### Ownership Rules

- Do not let multiple agents edit the same WinUI3 file.
- Treat `src/apprt/winui3/com*.zig` as generator-facing files; coordinate those edits with bindgen work.
- Keep screenshots, dumps, and temp scripts out of commits unless the user explicitly wants them versioned.

## Operating Rules

1. Do not declare WinUI3 work complete from app build alone.
2. `pwsh -File .\scripts\winui3-contract-check.ps1 -Build` is the local acceptance gate.
3. `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1` is the cross-repo acceptance gate.
4. Do not keep stale references to retired checks such as `winui3-inspect-event-params.ps1`.
5. Do not rediscover WinUI3 behavior from scratch if it is already captured in `docs/winui3-playbook.md` or `docs/winui3-known-good-apis.md`.

## GitHub Policy

- Issue and PR operations must target fork repos only.
- Do not open upstream issues or PRs from this fork workflow unless explicitly instructed.
- Recommended GitHub branch protection settings for `main` are documented in
  [docs/fork-branch-protection.md](docs/fork-branch-protection.md). They prevent
  the `zig fmt` drift class of regression tracked in issue #229.

## Spec Management

### 権威ある情報源

| 情報の種類 | 参照先 |
|-----------|--------|
| 次に実装すべきタスク | `.kiro/specs/` の `tasks.md` |
| 現在の作業フロンティア | `PLAN.md` の「現在の作業フロンティア」セクション |
| WinUI3 の知見・動作 | `docs/winui3-playbook.md`、`docs/winui3-known-good-apis.md` |
| 壊してはいけない定義 | `contracts/winui-contract.json`、`contracts/vtable_manifest.json` |
| テスト実行可能状態 | `tests/TEST_AUDIT.md` |

### スペック管理ルール

1. **新しい実装タスクは `.kiro/specs/` にスペックを作成してから着手する。**
   - `requirements.md` → `design.md` → `tasks.md` の順で作成する。
   - スペックなしで実装を開始してはならない。

2. **チャット記憶を WinUI3 の真実の源泉として使用してはならない。**
   - 根拠は `docs/winui3-playbook.md`、テストスクリプト、または GitHub Issue に記録すること。
   - 詳細は [NON-NEGOTIABLES.md](NON-NEGOTIABLES.md) を参照。

3. **PLAN.md と .kiro/specs/ の使い分け:**
   - `PLAN.md`: フェーズ単位の完了記録と現在の作業フロンティア（粗粒度）
   - `.kiro/specs/`: 個別機能の詳細要件・設計・タスク（細粒度）
   - 両者は補完関係であり、どちらか一方を廃止しない。

4. **新しい WinUI3 の知見を発見したとき:**
   - `docs/winui3-playbook.md` または `docs/winui3-known-good-apis.md` に追記する。
   - テストスクリプトで検証可能な知見はテストとして `tests/` に追加する。
