# AGENTS.md

## Project Scope

`ghostty-win` is the WinUI3 consumer of the external `win-zig-bindgen` and `win-zig-core` workflow.

Read [NON-NEGOTIABLES.md](C:\Users\yuuji\ghostty-win\NON-NEGOTIABLES.md) first.
Then read:
- [docs/winui3-playbook.md](C:\Users\yuuji\ghostty-win\docs\winui3-playbook.md)
- [docs/winui3-known-good-apis.md](C:\Users\yuuji\ghostty-win\docs\winui3-known-good-apis.md)

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
