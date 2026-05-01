# AGENTS.md

## Project Scope

`ghostty-win` is the WinUI3 consumer of the external `win-zig-bindgen` and `win-zig-core` workflow.

Read [NON-NEGOTIABLES.md](NON-NEGOTIABLES.md) first.
Then read:
- [docs/winui3-playbook.md](docs/winui3-playbook.md)
- [docs/winui3-known-good-apis.md](docs/winui3-known-good-apis.md)

## Remote convention (this fork)

This repo is `YuujiKamura/ghostty`, a personal **fork** of `ghostty-org/ghostty`.
Mis-targeting the remote causes branches to be cut from upstream
(hundreds of commits behind) and makes the resulting work unmergeable.
See issue #237 for the original incident.

- `origin` historically points to **upstream** (`ghostty-org/ghostty`) — **DO NOT push there.**
- `fork` is the canonical push target (`YuujiKamura/ghostty`).
- New clones MUST run `bash scripts/setup-fork-remote.sh` immediately after
  `git clone` to set `remote.pushDefault=fork` and `push.default=current`.
- Worktree-isolated agents inherit git config from the parent repo IF the parent
  has it configured; if not, run the setup script in the worktree first.
- When in doubt, run `git remote -v` and verify the destination URL before any push.
- New branches MUST be cut from `fork/main` (not `origin/master`) unless you are
  explicitly preparing an upstream contribution. Verify with
  `git log --oneline -1 fork/main` and confirm the SHA before branching.

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
6. Any change to mailbox / blocking queue / Win32 wait / pipe / `SendMessage` code MUST be reviewed against the [`docs/deadlock-discipline.md`](docs/deadlock-discipline.md) checklist. Pre-push lint (`tools/lint-deadlock.sh`) catches mechanical violations; the doc covers the intent.
7. **apprt contract**: `src/apprt/<platform>/` is upstream's explicit extension point — fork-driven changes belong inside `src/apprt/winui3/` (or `src/apprt/win32/`). Allowed fork-owned paths: `src/apprt/winui3/`, `src/apprt/win32/`, `src/apprt/win32_replacement/`, `vendor/zig-control-plane/`, `xaml/`, `tests/winui3/`, `scripts/`, `docs/`, `tools/`, `notes/`, `.github/`, `.dispatch/`, `.kiro/`, `.githooks/`, `.config/`, `lefthook.yml`, `AGENTS.md`, `CLAUDE.md`, `NON-NEGOTIABLES.md`, `AI_POLICY.md`, `APPRT_INTERFACE.md`, `PLAN.md`, `CODEOWNERS`, `OWNERS.md`, `build-winui3.sh`, plus top-level `*.md` and scratch files.

   Editing anything outside the fork-owned path list requires:
   - **Maintainer self-check** in commit message body: "If upstream received this as a PR, would they merge it? If no, why is wrapper-isolation impossible?"
   - `// UPSTREAM-SHARED-OK: <reason>` marker on the modified line(s), or `UPSTREAM-SHARED-OK: <reason>` trailer in the commit message body for diffs that span many lines.

   `tools/lint-fork-isolation.sh` (pre-push) enforces this mechanically. **Upstream PR is not a relief valve** — fork-local maintenance is our job; we do not propose changes to upstream's architecture. See [`docs/apprt-contract.md`](docs/apprt-contract.md) for wrapper patterns and the maintainer self-check examples; see [`notes/2026-04-27_fork_isolation_audit.md`](notes/2026-04-27_fork_isolation_audit.md) for the existing-violation backlog.

8. **Dispatch-time conventions**: every `.dispatch/*.md` brief inherits the rules in [`.dispatch/RULES.md`](.dispatch/RULES.md) — explicit `git add <path>`, `LEFTHOOK=0` for commit/push (the harness blocks `--no-verify`), single objective per brief, no scope expansion, GUI changes need visual verification (test PASS ≠ ship), file scope discipline so sister sessions don't collide. Brief authors should reference `.dispatch/RULES.md` rather than restate.

## Verification before commit

Pre-push hooks enforce most of these automatically (`lefthook.yml`), but agents
must understand WHY each gate exists so they can debug failures. See issue #236.

| Scope of change | Required local verification |
|---|---|
| Any `src/apprt/winui3/**` | `pwsh -NoProfile -File tests/winui3/run-all-tests.ps1` |
| Any `src/apprt/winui3/control_plane*` or `vendor/zig-control-plane/**` | UIA smoke + `zig build test` |
| Drag bar / window chrome (`nonclient_island_window.zig`) | UIA smoke (specifically `test-02c-drag-bar.ps1`) |
| Mailbox / message dispatch / focus | UIA smoke + `tests/repro_*` related tests |
| Build scripts / lefthook / CI | Push to a feature branch first, observe Actions before merging to main |

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
