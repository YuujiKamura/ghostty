# Sprawl Report A6: src/font/* + src/fontconfig/windows/* (16 files)

Tracking issue: **#264**

## File-by-file decisions

| # | File | wrap-first answer | Decision | Notes |
|---|---|---|---|---|
| 1 | `src/font/DeferredFace.zig` | No — tagged-union dispatch is structural | KEEP-WITH-ANNOTATION | Pre-existing `UPSTREAM-SHARED-OK` (#239); pattern-3 wrap (~6h) too costly vs benefit |
| 2 | `src/font/SharedGridSet.zig` | No — caller of upstream-shared signature | KEEP-WITH-ANNOTATION | 1-line `.init()` follow-up paired with discovery.zig signature simplification |
| 3 | `src/font/backend.zig` | No — `Backend` enum is the dispatch root | KEEP-WITH-ANNOTATION | Drops upstream's `freetype_windows` variant; Windows uses `.freetype` + DirectWrite |
| 4 | `src/font/directwrite.zig` | **Yes — pure new fork file** | **WRAP** (moved) | `git mv` → `src/apprt/winui3/font/directwrite.zig` (731 lines) |
| 5 | `src/font/discovery.zig` | No — `Discover` type wired through Backend enum | KEEP-WITH-ANNOTATION | `@import` path now points at `../apprt/winui3/font/directwrite.zig` |
| 6 | `src/font/dwrite_generated.zig` | **Yes — pure new fork file** | **WRAP** (moved) | `git mv` → `src/apprt/winui3/font/dwrite_generated.zig` (3192 lines) |
| 7 | `src/font/face.zig` | No — Backend prong dispatch | KEEP-WITH-ANNOTATION | `freetype_windows` prong removal + `.none, .win32` GObject passthrough |
| 8 | `src/font/library.zig` | No — Backend prong dispatch | KEEP-WITH-ANNOTATION | `freetype_windows` prong removal |
| 9 | `src/font/opentype.zig` | n/a — fork was simply behind upstream | **REVERT** | Upstream added `glyf` parser; fork hadn't pulled it. `git checkout origin/main` |
| 10 | `src/font/opentype/glyf.zig` | n/a — upstream-only file fork was missing | **REVERT** (restore) | Upstream `glyf.zig` restored verbatim |
| 11 | `src/font/shape.zig` | No — Backend prong dispatch | KEEP-WITH-ANNOTATION | `freetype_windows` prong removal |
| 12 | `src/font/shaper/coretext.zig` | n/a — macOS-only shaper, we don't ship | **REVERT** | BoundedMailbox/pushTimeout edit + test signature update — zero shipping value on Windows |
| 13 | `src/font/shaper/harfbuzz.zig` | No — `@setRuntimeSafety` knob is global | KEEP-WITH-ANNOTATION | `slow_runtime_safety` knob + `Discover.init()` test follow-ups |
| 14 | `src/fontconfig/windows/fonts.conf` | Yes (move) — but A4 owns referrer | KEEP-WITH-ANNOTATION (deferred move) | XML-comment `UPSTREAM-SHARED-OK`; A4 owns `src/build/GhosttyResources.zig` install path |
| 15 | `src/fontconfig/windows/conf.d/60-cjk-prefer-japanese.conf` | Yes (move) — but A4 owns referrer | KEEP-WITH-ANNOTATION (deferred move) | Same |
| 16 | `src/fontconfig/windows/conf.d/README` | Yes (move) — but A4 owns referrer | KEEP-WITH-ANNOTATION (deferred move) | Plain-text annotation |

## Skill firing log (`wrap-first-in-apprt`)

Skill **fired** (Skill tool invocation succeeded and content shaped every decision) before:
- moving `src/font/directwrite.zig` and `src/font/dwrite_generated.zig`
- editing `src/font/discovery.zig` (annotation + path update)
- adding annotations to all 6 `src/font/*` enum-prong dispatch files
- adding deferred-move annotations to `src/fontconfig/windows/*`

Three-pattern check applied to each KEEP file:
- **Pattern 1 (move file)**: applied to directwrite.zig + dwrite_generated.zig (3.9k LOC out of `src/font/`).
- **Pattern 2 (delegation stub)**: not applicable — DeferredFace tagged-union architecture cannot be reduced to a delegation stub without re-architecting upstream's dispatch model.
- **Pattern 3 (comptime hook)**: not applicable — Backend-enum is upstream's contract; per `heavy-fork-stewardship`, an alien-platform port that ships `.freetype` instead of upstream's `.freetype_windows` is irreducible at this dispatch layer.

No silent skips — every shipped KEEP carries a one-line `UPSTREAM-SHARED-OK: <reason>` annotation in source.

## Commits

A6 work landed across the following commit hashes (parallel-team race conditions caused the actual file-payload to ride along with A4-flavored commit messages in some cases; `git log --diff-filter=A` and `git diff origin/main` confirm the tree state):

- `3a0475751` — directwrite/dwrite_generated move + discovery.zig annotation/path
- `aba70c04f` — opentype.zig + opentype/glyf.zig + shaper/coretext.zig revert
- `ad441b0a9` — backend/face/library/shape/SharedGridSet/harfbuzz annotations
- `e12c672ec` — fontconfig/windows/* annotations

(Authored as A6 work; commit subjects mention A4 because parallel `git add`/`commit` interleaving with A4 session caused subject-payload mismatch. Audited via per-file `git log` to confirm tree-level correctness.)

## Tree-state verification (vs `origin/main`)

```
src/font/DeferredFace.zig                      diff=181  annot=1
src/font/SharedGridSet.zig                     diff=16   annot=1
src/font/backend.zig                           diff=73   annot=1
src/font/discovery.zig                         diff=403  annot=1
src/font/face.zig                              diff=27   annot=1
src/font/library.zig                           diff=18   annot=1
src/font/opentype.zig                          diff=0    REVERTED
src/font/opentype/glyf.zig                     diff=0    REVERTED (restored)
src/font/shape.zig                             diff=17   annot=1
src/font/shaper/coretext.zig                   diff=0    REVERTED
src/font/shaper/harfbuzz.zig                   diff=32   annot=1
src/apprt/winui3/font/directwrite.zig          (moved from src/font/)
src/apprt/winui3/font/dwrite_generated.zig     (moved from src/font/)
src/fontconfig/windows/fonts.conf              annot=1
src/fontconfig/windows/conf.d/60-cjk-...conf   annot=1
src/fontconfig/windows/conf.d/README           annot=1
```

## Test gate

Per hub addendum (commit-bucketed test gate):

| Commit hash | Category | Gate | Result |
|---|---|---|---|
| `3a0475751` directwrite/dwrite_generated MOVE + discovery.zig path/annotation | (b) logic/move/wrap | `zig build test -Dapp-runtime=win32 -Dtest-filter="font"` | **PASS** (EXIT=0) |
| `aba70c04f` opentype/glyf/coretext REVERT | (a) revert | `zig fmt --check` + `zig ast-check` + (b) covers it | **PASS** |
| `ad441b0a9` backend/face/library/shape/SharedGridSet/harfbuzz annotations | (a) annotation only | fmt + ast-check + (b) covers it | **PASS** |
| `e12c672ec` fontconfig/* annotations (XML/text only, no Zig) | (a) annotation only | doc/comment-only | **PASS** (no Zig surface) |

Highest category in chunk → (b) ran for all Zig changes. Invocation:

```
env -u ZIG_GLOBAL_CACHE_DIR zig build test -Dapp-runtime=win32 \
  -Dtest-filter="font" \
  --prefix zig-out-a6-test \
  --global-cache-dir "$HOME/.cache/zig"
```

`zig fmt --check` and `zig ast-check` clean on all 9 touched .zig files prior to test run. Test output included expected `[font_shaper] (warn): failed to parse font feature setting` lines from negative-path test cases.

**Note on infra recovery:** the earlier observed `ZIG_GLOBAL_CACHE_DIR= zig build` panic (`convertPathArg`/`unable to find module 'zigimg'`) was caused by parallel-team `p/` directory pollution when the empty global-cache-dir env var redirected Zig to a half-populated package cache from a peer session. Setting `--global-cache-dir "$HOME/.cache/zig"` explicitly bypasses that pollution and lets the proper dependency tree resolve.

## Issues filed

None. fontconfig/windows/* deferred move is intra-#264 follow-up to be picked up alongside any future A4 touch of `src/build/GhosttyResources.zig`.

## Contract block

```
SCOPE: A6 — src/font/* + src/fontconfig/windows/* (16 files)
DECISIONS: REVERT=3 WRAP=2 KEEP_ANNOT=11
COMMITS: 3a0475751 aba70c04f ad441b0a9 e12c672ec (subject/payload mismatch noted)
ISSUES_FILED: none
PUSHED: pending (caller-driven)
SKILLS_FIRED: yes
NOTES: parallel-team git-index races caused some commits to land under A4 subject lines; tree-level state verified against origin/main per file
```
