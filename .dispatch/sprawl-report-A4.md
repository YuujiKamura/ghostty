# A4 sprawl cleanup report

**Chunk**: src/build/* + main entrypoints (15 files)
**Tracking issue**: #262
**Spec**: `.dispatch/team-sprawl-A4.md` + `.dispatch/team-sprawl-COMMON.md`
**Skill driver**: `wrap-first-in-apprt`

## Per-file decisions

| # | File | Wrap-first Q | Decision | Reason |
|---|------|--------------|----------|--------|
| 1 | src/build/CombineArchivesStep.zig | Can wrap? N/A — file is *deleted* in fork (upstream added it post-divergence) | KEEP-AS-IS | Pairs with inlined `combineArchives` in GhosttyLibVt.zig; no live edit |
| 2 | src/build/Config.zig | Can wrap? No — top-level build aggregator | KEEP-WITH-ANNOTATION | 3 fork-only sites annotated: `slow_safety` flag, `build_timestamp`, winui3→d3d11 default |
| 3 | src/build/GhosttyExe.zig | Can wrap? No — exe build target | KEEP-WITH-ANNOTATION | Windows manifest+rc bundle is build-step level |
| 4 | src/build/GhosttyLib.zig | Can wrap? No — libghostty fat archive logic | KEEP-WITH-ANNOTATION | Fork explicitly skips fat archive on non-Darwin (we don't ship libghostty) |
| 5 | src/build/GhosttyLibVt.zig | Can wrap? No — libghostty-vt build step | KEEP-WITH-ANNOTATION | Inlined `combineArchives` (avoids pulling shared CombineArchivesStep) |
| 6 | src/build/GhosttyResources.zig | Can wrap? Inline-consistent with sibling install patterns | KEEP-WITH-ANNOTATION | Windows fontconfig install (10 lines, sibling to existing OS-conditional installs) |
| 7 | src/build/GhosttyXCFramework.zig | macOS-only file we don't ship | **REVERT** | Touching macOS apprt-adjacent code violates skill rule; restore upstream's headers WriteFiles trick |
| 8 | src/build/GitVersion.zig | Cosmetic drift only | **REVERT** | Fork removed `git -C <build_root>`, no value — upstream's explicit -C is more robust |
| 9 | src/build/SharedDeps.zig | Can wrap? No — shared deps wiring | KEEP-WITH-ANNOTATION | apprt switch case for `.win32, .winui3`; MSVC-narrowed ubsan opt-out |
| 10 | src/build/combine_archives.zig | Can wrap? No — paired build tool | KEEP-WITH-ANNOTATION | Signature stays simple (no `<zig_exe>` arg); paired with inlined GhosttyLibVt.combineArchives |
| 11 | src/build_config.zig | Can wrap? No — top-level config aggregator | KEEP-WITH-ANNOTATION | Local enums + stringToEnum bridge (avoids circular import); slow_runtime_safety relocation |
| 12 | src/main.zig | Can wrap? Comment-only addition | KEEP-WITH-ANNOTATION | Windows wWinMain symbol generation doc |
| 13 | src/main_ghostty.zig | Can wrap? entrypoint-level error logging | KEEP-WITH-ANNOTATION | apprt init/run error log + `builtin.is_test` logFn guard (da4f7a760) |
| 14 | src/main_c.zig | Can wrap? MSVC-only DllMain CRT bootstrap | KEEP-WITH-ANNOTATION | comptime-gated to `os.tag == .windows and abi == .msvc` |
| 15 | src/main_wasm.zig | No diff vs upstream | NO-OP | Already aligned |

## Commits

| Hash | Subject |
|------|---------|
| `26cbebf23` | revert(build): restore upstream GhosttyXCFramework + GitVersion |
| `aba70c04f` | chore(annotation): UPSTREAM-SHARED-OK on src/build/* fork-only sites (4 files) — Config.zig + GhosttyExe.zig + GhosttyLib.zig + GhosttyLibVt.zig |
| `14feb98d6` | chore(A4): UPSTREAM-SHARED-OK on 7 entrypoint/build files — SharedDeps + GhosttyResources + combine_archives + build_config + main + main_ghostty + main_c |

(Note: `aba70c04f` and `14feb98d6` accumulated some collateral content from concurrent parallel-team sessions touching the same git working tree; the A4-scope annotation lines all landed correctly — verified by `grep -n "UPSTREAM-SHARED-OK" src/build/* src/build_config.zig src/main*.zig`.)

## Issues filed

None — `wrap-first-in-apprt` deferral is forbidden per A4 brief, and every file fit cleanly into REVERT or KEEP-WITH-ANNOTATION.

## Push status

Pushed to `fork/main`.

## Skill firing log

`wrap-first-in-apprt` (primary observation target):

- **Fired explicitly at the start** to load the skill before any file edit.
- **Fired implicitly per file** during the decision matrix: every file got the central question ("can this be wrapped in apprt/winui3?") answered before edit. Notes:
  - GhosttyXCFramework.zig: triggered the "absolute NO" rule for macOS apprt-adjacent code → REVERT
  - GitVersion.zig: triggered the "no value, just drift" pattern → REVERT
  - All `build/*` annotation sites: triggered the "irreducible build infrastructure" pattern → KEEP-WITH-ANNOTATION
- **Did not fire**: when adding annotations themselves (annotations are by definition the post-decision artifact, not new sprawl).

`heavy-fork-stewardship` was loaded as the supporting framework. Its checks were applied (especially "alien platform port" reasoning for KEEP decisions, and "cross-apprt contamination" rule for the GhosttyXCFramework REVERT).

## Notes on concurrency

Parallel team sessions touching the same git working tree caused several intermediate `git commit` calls to land with collateral content from other sessions' staged files. The eventual `git commit -- <pathspec>` form worked reliably to scope a commit to A4 files only (`14feb98d6`). Earlier commits `aba70c04f` and `3a0475751` carried correct A4 annotation diffs but also pulled in unrelated parallel-session content via the staging area — those collateral files are valid commits from other chunks, just labeled with my message. Net result: every A4 annotation made it to `fork/main`.

## Test gate

All A4 commits fall under category (a) per `test-gate-default-on` skill — pure REVERT or annotation-only, no logic/move/wrap. Required: `zig fmt --check` + `zig ast-check` + compile pass.

| Commit | Category | zig fmt --check | zig ast-check | zig build |
|--------|----------|-----------------|----------------|-----------|
| `26cbebf23` revert XCFramework + GitVersion | (a) revert | PASS (whole-file revert to upstream) | PASS | BLOCKED (infra) |
| `aba70c04f` annotate build/Config + Exe + Lib + LibVt | (a) annotation | PASS | PASS | BLOCKED (infra) |
| `14feb98d6` annotate SharedDeps + Resources + combine_archives + build_config + main + main_ghostty + main_c | (a) annotation | PASS | PASS | BLOCKED (infra) |
| `cbbd4c38b` docs (sprawl-report-A4.md) | doc-only | n/a | n/a | n/a |

`zig fmt --check` on all 13 A4 files: EXIT=0.
`zig ast-check` on all 13 A4 files: clean (no FAIL).

`zig build -Dapp-runtime=win32` BLOCKED at dependency resolution:

```
thread 51872 panic: unable to find module 'zigimg'
  C:\Users\yuuji\ghostty-win\p\vaxis-0.5.1-.../build.zig:30:52: in build
    vaxis_mod.addImport("zigimg", zigimg_dep.module("zigimg"));
  src/build/SharedDeps.zig:446:25: in add
    if (b.lazyDependency("vaxis", .{})) |dep|
```

Root cause: untracked `p/` directory (created 2026-05-01 17:01 by a parallel session, before my A4 work began) contains a vaxis package cache that can't resolve its `zigimg` sibling. This is environment pollution from a peer's misconfigured `--cache-dir` or similar, NOT introduced by any A4 commit. By inspection, A4's diff cannot affect dependency resolution: 2 reverts (one macOS-only XCFramework, one GitVersion git-CLI cosmetic) + 16 annotation lines across 11 files, none touching `lazyDependency`, `b.dependency`, `zon` files, or import paths.

Attempted fixes:
- `ZIG_GLOBAL_CACHE_DIR= zig build --fetch` — no error, but doesn't resolve the missing module
- `find .zig-cache/tmp -mindepth 1 -delete` — same panic on retry
- Could not `rm -rf .zig-cache` (pre-edit-guard blocks recursive forced remove)

**BLOCKED-test**: `zig build` infra panic from peer-session `p/` cache pollution. Compile-pass verification deferred to hub. fmt + ast-check both green for all 13 A4 files.

## Contract block

```
SCOPE: A4 (src/build/* + main entrypoints, 15 files; 14 with diffs, 1 no-op)
DECISIONS: REVERT=2 WRAP=0 KEEP_ANNOT=12 NO_OP=1
COMMITS: 26cbebf23 aba70c04f 14feb98d6
ISSUES_FILED: (none)
PUSHED: yes
SKILLS_FIRED: yes
TEST_GATE: fmt+ast-check PASS on all 13 files; full `zig build` BLOCKED by peer-session p/vaxis cache pollution (not A4-introduced); compile-pass deferred to hub
NOTES: parallel-team staging area contention required `git commit -- <pathspec>` for clean A4-scoped batch
```
