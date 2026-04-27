# Windows 10 Implementation Lessons — Architectural Review

Companion to issue #194. Captures architectural inconsistencies surfaced during
Windows 10 first-deploy verification on a Celeron 3865U / Win10 Home 22H2 box,
organized by theme rather than by individual bug. The point of this document is
not to re-litigate any single fix; the point is to record the patterns where
individual fixes were each correct in isolation but combined incoherently, so
the same shape of failure does not recur.

Scope is fork-internal. None of the recommendations here propose changes to
upstream `ghostty-org/ghostty` or to Microsoft's Windows App SDK. We adapt to
what they ship.

## Context

### Verification environment

- Hardware: Intel Celeron 3865U (Kaby Lake, no AVX2), 4 GB RAM
- OS: Windows 10 Home 22H2 (build 19045)
- State: clean install — no Visual Studio, no MSIX runtime packages, no Windows
  Terminal preinstalled
- Artifact under test: `ghostty-windows-winui3` from Fork Stable CI run #31, then
  rebuilt locally as iterations landed

### Why this matters

The dev machines used during the WinUI3 port (Phase 7 onward) had a permissive
environment: Windows 11, Visual Studio installed, Windows App SDK runtime
already deployed via Windows Terminal or other apps, AVX2-capable CPU, developer
mode on. Each of those preconditions silently masked a different defect. The
Win10 box was the first environment that did not have any of them.

The cluster of issues #179 through #193 enumerates the individual defects that
fell out. This document is about the *shape* of the failures: where the
architecture was internally inconsistent rather than just buggy.

### Issue cluster index

One-liner per cited issue. State as of 2026-04-27.

| Issue | State | Topic |
|-------|-------|-------|
| #179 | closed | CI emits AVX2 instructions; crashes on older x86_64 (`-Dcpu=baseline`) |
| #180 | closed | Bootstrap requested SDK v1.4 while bundled DLLs were v1.6 (or vice versa) |
| #181 | closed | `bootstrap.zig` searched only `../../xaml/prebuilt/runtime/x64/`; CI artifacts flatten DLLs into `bin/` |
| #182 | closed | CI artifact omitted `share/` (fontconfig, terminfo, shell-integration) |
| #183 | closed | `setlocale(LC_ALL, "en_US.UTF-8")` is POSIX-form; MSVC runtime rejects it |
| #184 | closed | Design issue: framework-dependent vs self-contained mismatch (parent of #186) |
| #185 | closed | Documentation: Windows 10 compatibility landmines |
| #186 | open   | UndockedRegFreeWinRT activation for self-contained deployment |
| #187 | closed | `setlocale` fallback chain for Win10 1809+ (parent: #185 item 4) |
| #188 | closed | CI Windows 10 runner / emulation (parent: #185 item 1) |
| #189 | closed | Embed DPI awareness, long path, UTF-8 code page in app manifest |
| #190 | closed | Windows App SDK runtime installer in `setup-dev.ps1` (framework-dependent path) |
| #191 | closed | Zig 0.15 `subsystem = .Windows` requires `WinMain` trampoline |
| #192 | closed | Centralize Windows App SDK version as single source of truth |
| #193 | closed | CJK fallback broken after upstream switched font backend `fontconfig_freetype` → `freetype` |
| #194 | this   | Architectural lessons-learned (this document closes it) |

## Lesson 1: framework-dependent vs self-contained must be ONE choice, not mixed

Related: #184, #186, #180, #181, #192.

Windows App SDK supports two unpackaged-deployment shapes:

| Mode | Runtime DLLs in app dir? | `MddBootstrapInitialize` | MSIX packages required |
|------|--------------------------|--------------------------|------------------------|
| framework-dependent unpackaged | No  | Yes | Yes (Framework + Main + Singleton + DDLM) |
| self-contained unpackaged      | Yes | No  | No |

`build-winui3.sh` produces a self-contained shape: WinUI3 runtime DLLs are
flat-copied into the same directory as `ghostty.exe`. This is the layout that
ships from the Fork Stable CI artifact and the layout that a user actually gets
when they download a release.

`src/apprt/winui3/bootstrap.zig`, however, does framework-dependent setup work:
it loads `Microsoft.WindowsAppRuntime.Bootstrap.dll` and calls
`MddBootstrapInitialize`. `MddBootstrapInitialize` does not look at the app
directory at all. It searches the MSIX package store for registered DDLM/Main/
Singleton packages and fails (HRESULT `0x80670016`,
`MDD_E_BOOTSTRAP_INITIALIZE_FAILED`) when they are absent.

Each individual decision was defensible in isolation:
- "ship the DLLs alongside the exe so users do not need a separate runtime
  installer" — defensible for a self-contained shape
- "call `MddBootstrapInitialize` because that is what unpackaged WinUI3 apps do"
  — defensible for a framework-dependent shape

The combination contradicts itself. `MddBootstrapInitialize` returns an error
on a clean Win10 box even though every DLL it would conceivably need is already
sitting one inode away.

### The version-churn symptom

`#180` and `#192` are downstream of the same confusion. The question "what SDK
version do we target?" only matters if `MddBootstrapInitialize` actually
participates in DLL resolution, and it does not. The bootstrap version constant
controlled which MSIX *package* `MddBootstrapInitialize` would look for, and the
DLLs in `xaml/prebuilt/runtime/x64/` controlled what was loaded by the linker
and `LoadLibraryW`. These are unrelated channels that were being treated as if
they had to agree.

History (from `git log -- src/apprt/winui3/bootstrap.zig`):
- `5deca8186` (#180): bootstrap version 1.4 → 1.6, "align with bundled DLLs"
- `0a1c1bf5e` (#192): bootstrap version 1.6 → 1.4, "DDLM 4000 is widely
  installed"
- Win10 verification: DDLM 4000 is *not* installed by default
- `b0ba7a34d` (#184, #186): branch added for "self-contained mode" — log
  warnings instead of failing when bootstrap DLL is absent

The current `bootstrap.zig` head still tries `MddBootstrapInitialize` when the
bootstrap DLL is present. It only degrades to "self-contained" silently when
the DLL is missing. The fork has not yet picked one shape and committed to it
end-to-end. WinRT class activation under the self-contained branch is the
remaining unknown that #186 is owned by another agent to address.

### What we conclude (fork-internal)

- The deployed shape (DLLs flat-copied next to `ghostty.exe`) is the contract.
  It is what users actually see. The bootstrap path should match that contract,
  not the other one.
- The choice of contract is downstream of "what do we ship?", not "what does
  the SDK example code do?". Microsoft's reference samples are mostly
  framework-dependent because that is what their installer flow optimizes for;
  copying their bootstrap call without copying their deployment shape is the
  proximate cause of this whole class of bug.
- A second mode is not free. Even an honest two-mode design (probe, then pick)
  doubles the matrix of states the binary can launch into and we still have to
  test both. We are not staffed to keep both paths working.
- The version constant is only meaningful in framework-dependent mode. If we
  commit to self-contained, the constant becomes "what version did we ship in
  `xaml/prebuilt/runtime/x64/`?" — a single-writer fact, no synchronization
  needed.

## Lesson 2: SDK-version churn comes from assumption-based decisions, not evidence-based

Related: #180, #192.

The 1.4 → 1.6 → 1.4 → 1.6 oscillation traced in Lesson 1 is a process problem,
not just a version-pin problem. Each rollback was internally rational at the
time it was made:

- 1.4 → 1.6 (#180, commit `5deca8186`): "bundled DLLs are 1.6, so the bootstrap
  call should request 1.6 to match." Assumed: DDLM 6000 is installed somewhere.
- 1.6 → 1.4 (#192, commit `0a1c1bf5e`): "DDLM 4000 is widely deployed via
  Windows Terminal." Assumed: WT installs DDLM 4000.
- 1.4 → 1.6 (Win10 verification): DDLM 4000 was not on the test box. WT does
  not install DDLM at all.

None of those assumptions was checked against a clean machine before being
committed. The decision-time rationale was not written down in the commit
message in a way that survived to the next reviewer, so when the next person
rolled it back, they were not refuting evidence — they were refuting nothing,
because there was no evidence on file.

### What we conclude (fork-internal)

- Decisions about runtime preconditions need to be backed by an explicit
  observation on a clean machine, recorded at decision time. "Widely
  installed" without a reproducible probe is not evidence.
- The cure is not more discussion. The cure is a probe script in the
  repository that says "before you change this constant, run this on a Win10
  box and paste the output into the commit message". `notes/` is the right
  place for the probe and its expected output.
- Centralizing the version (#192) is a real improvement orthogonal to the
  oscillation: it makes the constant grep-able. But centralization without an
  evidence-recording habit just gives the next reviewer a more obvious place to
  flip the wrong bit.

## Lesson 3: Build-output layout and runtime path assumptions drift apart

Related: #181, #182.

Two related concrete failures:

1. `bootstrap.zig`'s `SetDllDirectory` originally pointed at
   `../../xaml/prebuilt/runtime/x64/`, a path that exists in the source tree
   but not in any artifact. CI produces `bin/ghostty.exe` next to the DLLs;
   there is no `xaml/prebuilt/...` two levels up. (#181)
2. Fork Stable CI uploaded `bin/` only, dropping `share/`. That broke font
   discovery, terminfo, and shell-integration. (#182)

Both are the same shape of mistake: the script that writes the layout
(`build-winui3.sh`, the CI workflow) and the code that reads the layout
(`bootstrap.zig`, locale init, fontconfig discovery) were authored in different
sessions with different mental models of "where things end up". There was no
written contract for the artifact layout that both sides referenced.

In #181 the failure was masked for a long time because the dev tree happened to
contain `xaml/prebuilt/runtime/x64/`, so dev runs found the DLLs even though
artifact runs would not have. The bug only appeared when someone tried to run
the CI artifact standalone.

### What we conclude (fork-internal)

- The artifact layout is a contract between `build-winui3.sh`, `.github/
  workflows/fork-stable-ci.yml`, and every runtime path that resolves files
  relative to the exe. There is no place in the repo where that contract is
  written down. It should be — even a five-line `notes/artifact-layout.md`
  would have caught both #181 and #182 by code review.
- "Run from the dev tree" and "run from the unpacked artifact" are different
  test modes. The dev-tree mode masks layout drift indefinitely. A smoke test
  that unpacks the artifact in a clean directory and launches it once would
  have caught both.

## Lesson 4: upstream sync silently changed a backend our config files target

Related: #193.

Upstream sync `14b6fd640` (`merge: sync with upstream ghostty-org/ghostty`)
changed the default font backend on Windows from `fontconfig_freetype` to
`freetype`. The fork carries its own
`src/fontconfig/windows/conf.d/60-cjk-prefer-japanese.conf` to bias CJK
unification glyph selection toward Japanese forms. The new backend does not
consume fontconfig at all, so the config file is dead weight and CJK glyphs
render with Chinese forms by default in Japanese locales.

The data file did not move. The code that reads the data file went away.
Nothing in the fork referenced the file in a way that would have produced a
build error or even a warning when the consumer was removed upstream.

This is structurally similar to Lesson 3: two artifacts (a config file in the
repo, a backend choice in upstream code) that have to agree, with no enforced
link between them.

### What we conclude (fork-internal)

- Fork-owned data files that depend on a specific upstream code path need a
  marker that surfaces during merge. A README in `src/fontconfig/windows/`
  saying "this directory is only consumed when font_backend ==
  fontconfig_freetype; if upstream changes the default, audit this file" would
  have raised the question at merge time.
- The proximate workaround (config-time `font-family = BIZ UDGothic`) is fine
  for the user-facing problem but does not address the structural issue: we
  still carry a fontconfig configuration directory whose consumer is gone.
  Either the directory should be removed, or the freetype backend in the fork
  should grow a CJK fallback that does what the conf file used to do. We have
  not picked one.
- We do not know how to fix this in the freetype backend without touching code
  that is upstream-shared territory. Per heavy-fork-stewardship, that means
  the realistic fork-internal options are (a) delete the conf directory and
  document that the user must set `font-family` explicitly on Win10 Japanese
  locales, or (b) accept the upstream-shared edit and mark it
  `UPSTREAM-SHARED-OK: CJK fallback fork-specific`. Neither has been chosen.

## Lesson 5: CI environment and target environment diverge along multiple axes at once

Related: #179, #183, #185, #188, #189.

The Fork Stable CI runs on `windows-2022` (Windows Server 2022). The verification
environment was Windows 10 Home 22H2. The two differ along axes that all matter
for an unpackaged WinUI3 app:

| Axis | CI (Server 2022) | Win10 22H2 target | Caught what |
|------|------------------|-------------------|-------------|
| OS kernel | Win11 | Win10 | bootstrap DDLM/AppExtension code path divergence (#185 item 1) |
| CPU | Modern, AVX2+ | Celeron Kaby Lake, no AVX2 | `-Dcpu=baseline` regression (#179) |
| MSIX runtime | Always-latest | None | `MddBootstrapInitialize` failure (#180, #184) |
| Locale handling | Server defaults | Consumer defaults | `setlocale` POSIX-string rejection (#183, #187) |
| Developer mode | Admin runner, on | User box, off | Zig symlink unpacking failure |
| Preinstalled WinUI3 deps | Often present | Absent | DDLM/Main/Singleton absence (#185 item 2) |

Each of these can be addressed individually (#179 closed by adding
`-Dcpu=baseline`, #189 closed by embedding the manifest, #188 closed by adding
a Win10 runner job), and most have been. The pattern is that the gap between CI
and target is multi-dimensional. A single-axis fix (a Win10 runner that has
DDLM preinstalled) gets one axis but not the others. Users do not run on Server
2022 with a clean profile; they run on Home or Pro with whatever they happened
to install before.

### What we conclude (fork-internal)

- "CI passes" is necessary but not sufficient for a release gate. There needs
  to be at least one validation pass on a profile that approximates a clean
  consumer install: Win10 Home, no developer mode, no MSIX runtime, no Visual
  Studio. The cheapest version is a manual run on a VM snapshot, taken once per
  release, with the result pasted into the release notes.
- Adding a Win10 CI runner (#188) helps with kernel-path divergence but does
  not by itself replicate the missing-MSIX-runtime axis. The runner would need
  to be a fresh image on every run, and it would need to *not* have anything
  preinstalled that papers over Lesson 1.
- Some of these axes are orthogonal in nature and need orthogonal coverage:
  CPU baseline is a build flag (#179), MSIX runtime presence is a deployment
  test, locale string acceptance is a unit test against the MSVC runtime, and
  developer mode is a documentation / build prerequisite. Folding them into one
  "Win10 runner" pass undersells the actual coverage gap.

## Lesson 6: AI-implements-step-without-coherence-check is the cross-cutting failure mode

Related: most of the cluster, but most clearly #180 + #181 + #184.

Each individual fix was implemented by an agent (often me) from the issue text
without an enforced step that asked "given the rest of the system, does this
make the system more coherent or less?" The bootstrap version flip in #180 is
the clearest example: the local change made the constant match the bundled
DLLs, which was true and correct as stated. It did not address whether the
constant was meaningful at all in our deployment shape, because the issue did
not ask that.

This is not a critique of the issue authoring — issues are scoped by design.
The gap is between issue scope and architectural scope. There is no agent in
the loop whose job is "this fix landed; does the combination of fixes that
landed in the last 30 days still tell a coherent story?"

### What we conclude (fork-internal)

- A periodic coherence pass is worth the cost. The shape that worked tonight
  was: dispatch one agent to write *this* document while two other agents work
  on actual code (`#209` TSF IME, `#186` UndockedRegFreeWinRT). The doc agent
  is not blocked by the code agents and vice versa. Doing a coherence write-up
  of the last sprint as a matter of course (once per Win10-class issue cluster)
  is cheap relative to the cost of re-litigating the same constant.
- "Verify on the target environment" is the single highest-leverage step.
  Most of the bugs in this cluster were reproducible the first time the binary
  was launched on Win10 Home. If that launch had been a routine step before
  closing the parent issue (#194 itself), the cluster would have been smaller.
- Issue text should call out what other issues a fix interacts with. #180's
  body did not mention #184, even though #184 (still being filed at the time)
  invalidates the framing of #180. A standing convention of "list adjacent
  issues that this fix is locally consistent with but globally inconsistent
  with" would have made the inconsistency visible at PR time.

## Cross-cutting failure modes (summary)

These are the recurring patterns from the lessons above, restated as patterns
rather than as instances:

- **Local-correct, global-incoherent fixes.** Each agent implements its issue
  faithfully. Nobody verifies the combination. (Lessons 1, 6.)
- **Decision rationale not captured at decision time.** The next reviewer
  cannot tell whether a constant flip is refuting prior evidence or refuting
  nothing. (Lesson 2.)
- **Implicit contracts between scripts and code.** Artifact layout, fontconfig
  consumer presence, and similar agreements are not written down anywhere they
  would be read during code review. (Lessons 3, 4.)
- **Dev environment masks deployment failure modes.** The dev box had MSIX
  runtimes, the dev tree had `xaml/prebuilt/runtime/x64/`, the dev CPU had
  AVX2. Each of those silently absorbed a defect that became visible on a
  clean target. (Lesson 5.)
- **Single-axis CI coverage for multi-axis gaps.** Adding one Win10 runner
  does not by itself cover the locale-string axis or the missing-MSIX-runtime
  axis. The dimensions need to be enumerated explicitly. (Lesson 5.)

## Recommendations going forward

These are fork-internal habits, not upstream proposals. None of them require
contract changes from `ghostty-org/ghostty` or Microsoft.

1. **Pick one deployment mode and document the contract.** Self-contained is
   the shape we already produce; commit to it. Track #186 to closure so the
   bootstrap branch under "self-contained mode" actually performs WinRT
   activation rather than logging a warning and proceeding. Once self-contained
   is the only path, delete the framework-dependent code rather than leaving
   it as a fallback.
2. **Add a `notes/artifact-layout.md` contract.** One page: what files end up
   where, who writes them (`build-winui3.sh` step N, CI workflow step M), who
   reads them (`bootstrap.zig` line range, locale init, fontconfig discovery).
   When the contract changes, both sides update the same file.
3. **Add a clean-VM smoke step to the release process.** A Win10 Home VM
   snapshot, no developer mode, no MSIX runtime, no Visual Studio. Boot snapshot,
   download artifact, double-click `ghostty.exe`, type a command, screenshot.
   Pasted into release notes. Manual is fine; the point is that the step exists
   and is documented.
4. **Codify SDK-version decisions.** Keep #192's centralization. In addition,
   require the commit message that flips the version constant to include the
   output of a documented probe (e.g., `Get-AppxPackage *WindowsAppRuntime*` on
   a clean Win10 box). Without the probe output, do not flip.
5. **Add a fontconfig-consumer marker.** A `src/fontconfig/windows/README.md`
   that says "consumed only when font backend is fontconfig_freetype; audit on
   upstream sync that changes font backend default". Resolves Lesson 4 without
   any code change.
6. **Track issue interactions.** When filing a bug fix that touches the same
   subsystem as a recent design issue, link both ways. PR template can prompt
   for this with a single "interacts with" field.
7. **Periodic coherence pass.** After each Win10-class issue cluster (more than
   ~5 related issues filed within a week), write a short retrospective note in
   `notes/YYYY-MM-DD_<topic>_lessons.md`. This document is the first instance.

## What we will NOT do

Per `~/.agents/skills/heavy-fork-stewardship/SKILL.md`:

- Will NOT propose architectural changes to upstream `ghostty-org/ghostty`.
  The font-backend switch (#193) and apprt boundary in general are upstream's
  domain. We adapt to whatever they ship.
- Will NOT file issues, PRs, or discussion threads against
  `microsoft/WindowsAppSDK` about the bootstrap design, the
  framework-dependent / self-contained split, or the DDLM lookup behavior.
  These are working as Microsoft intends; the fact that they are confusing in
  combination is not grounds for an AI agent to engage upstream.
- Will NOT redesign the WindowsAppRuntime bootstrap surface. We use what is
  there; if it does not fit our deployment shape, we use a different entry
  point (UndockedRegFreeWinRT, RoActivateInstance) that the SDK already
  provides.
- Will NOT touch other apprts (`gtk/`, `embedded/`, `none/`). Cross-apprt
  edits are the upstream maintainer's call, not ours, even when an apparent
  parallel bug exists.
- Will NOT propose a new abstraction layer in `src/apprt/winui3/` that would
  generalize self-contained vs framework-dependent into a "deployment strategy"
  trait or similar. Per Lesson 1, the goal is to commit to one shape, not to
  abstract over both.

## Honest unknowns

Things this document does not claim to have solved:

- We do not yet know whether UndockedRegFreeWinRT (#186) will fully replace
  `MddBootstrapInitialize` for our use of WinUI3. The activation manifest
  approach has known sharp edges around proxy/stub registration that we have
  not exercised. The work is in flight on a parallel agent.
- We do not have a chosen path for the CJK-fallback regression (#193) that is
  consistent with heavy-fork-stewardship. Both options (delete the dead
  fontconfig directory, or accept an upstream-shared edit to the freetype
  backend with a justification marker) have costs that have not been weighed.
- We do not have a clean-VM smoke-test infrastructure. The recommendation
  above is to add one; it does not exist yet.
- The "periodic coherence pass" recommendation is itself untested as a habit.
  This document is the first instance and will only be load-bearing if the
  habit holds for the next cluster.

## References

- Issue #194 — meta issue this document closes
- Issues #179, #180, #181, #182, #183, #184, #185, #186, #187, #188, #189,
  #190, #191, #192, #193 — the Win10 verification cluster
- `notes/2026-04-27_fork_isolation_audit.md` — apprt contract context for
  WinUI3-specific work that should not bleed into upstream-shared paths
- `notes/2026-04-27_font_backend_interface_design.md` — adjacent discussion of
  how to enforce font backend boundaries structurally
- `notes/2026-04-27_mailbox_interface_design.md` — adjacent discussion of
  type-level enforcement at apprt boundaries
- `~/.agents/skills/heavy-fork-stewardship/SKILL.md` — fork stewardship rules
  cited throughout
- Microsoft, "Windows App SDK deployment overview":
  https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/deploy-overview
- Microsoft, "Self-contained deployment for Windows App SDK":
  https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps
