# apprt contract

This document defines the rule that governs where fork-driven changes belong
in the ghostty-win source tree. It is referenced by `AGENTS.md` Operating
Rule on the apprt contract and enforced mechanically by
`tools/lint-fork-isolation.sh` (see `lefthook.yml` pre-push).

## The contract

`src/apprt/<platform>/` is upstream's explicit extension point. Upstream
ships several platform implementations side by side (`apprt/macos/`,
`apprt/gtk/`, `apprt/embedded/`) and accepts new ones (we contribute
`apprt/winui3/` and `apprt/win32/`) precisely so the per-platform code stays
contained.

Fork-driven changes belong inside `src/apprt/winui3/` (or `src/apprt/win32/`).
Changes to upstream-shared code outside that boundary are a contract
violation and require explicit justification.

## Why it matters

Every upstream-shared edit becomes our maintenance burden FOREVER:

- Upstream cannot know about it, so each upstream change to that file is a
  potential conflict we resolve manually on the next merge.
- The wider the sprawl, the higher the merge cost, the slower we can ride
  upstream improvements, the more we drift.
- The cost is on us. Framing it as "merge debt" misattributes
  responsibility — upstream did not impose this; we self-imposed it by
  skipping the wrapper layer.

A wrapper inside `src/apprt/winui3/` has the same behavioural effect with
zero merge cost. The contract is not about purity; it is about cheap
maintenance.

## Fork-owned paths

These are the paths the lint script (`tools/lint-fork-isolation.sh`) treats
as fork-owned. Edits here need no justification. Edits anywhere else do.

```
src/apprt/winui3/         — primary fork extension point
src/apprt/win32/          — secondary fork extension point
src/apprt/win32_replacement/
vendor/zig-control-plane/ — submodule, fork-controlled
xaml/                     — XAML resources (winui3-only)
tests/winui3/             — winui3 test suite
scripts/                  — fork tooling
docs/                     — fork docs
tools/                    — fork tooling (this script lives here)
notes/                    — fork investigation notes
.github/                  — CI / PR templates (fork-owned)
.dispatch/                — agent dispatch briefs
.kiro/                    — fork spec management
.githooks/                — git hooks (fork-owned)
.config/                  — fork-only config (windows.dsc.yaml etc.)
lefthook.yml              — pre-commit / pre-push gates
AGENTS.md                 — fork agent operating rules
CLAUDE.md                 — fork project rules
NON-NEGOTIABLES.md        — fork hard rules
AI_POLICY.md              — fork AI usage policy
APPRT_INTERFACE.md        — fork-side interface notes
PLAN.md                   — fork roadmap
CODEOWNERS, OWNERS.md     — fork ownership
build-winui3.sh           — fork build wrapper
```

Top-level scratch files (`*.md`, `*.ps1`, `*.zon`, `*.toml`, etc.) at the
repo root are also treated as fork-owned because this fork uses them
heavily for investigation logs.

## Maintainer self-check

Before any upstream-shared edit, ask:

> If the upstream maintainer received this commit as a PR, would they merge it?

The answer is almost always no. Common no-shapes:

- modifying a stdlib type in `src/datastruct/` to add Win32-specific shutdown
  semantics (it is not their type to specialise);
- editing `src/apprt/embedded.zig` or `src/apprt/gtk/class/application.zig`
  to keep the build green for an apprt we do not use (it is a maintenance
  burden on them for nothing);
- changing `src/Surface.zig` policy to fit Win32 PTY behaviour without an
  RFC (policy changes need design discussion).

If the answer is no, the change does not belong in upstream-shared code.
Refactor it as a wrapper inside `src/apprt/winui3/`. If wrapping is
genuinely impossible, write the maintainer self-check answer in the commit
body explaining WHY wrapping is impossible and add the
`UPSTREAM-SHARED-OK: <reason>` marker.

The lint catches the mechanical absence of justification. The judgment of
"is wrapping really impossible?" is human. The lint exists to force the
conversation, not to make the decision.

## Wrapper patterns

### 1. Type wrapping

Need a stdlib type to gain a Win32-specific behaviour? Wrap, do not modify.

```zig
// src/apprt/winui3/safe_mailbox.zig
const std = @import("std");
const blocking_queue = @import("../../datastruct/blocking_queue.zig");

pub fn SafeMailbox(comptime T: type, comptime cap: usize) type {
    return struct {
        inner: blocking_queue.BlockingQueue(T, cap),
        // winui3-local additions: shutdown flag, timeout enforcement, etc.
    };
}
```

Upstream's `BlockingQueue` stays untouched. Only winui3 callers use the
wrapper. Surface.zig and other consumers continue using upstream's type
unchanged (Surface.zig may receive a wrapper via dependency injection if
needed — see pattern 4).

### 2. Function wrapping

`src/Command.zig` needs Win32-specific timeout/termination? Wrap in a
fork-owned helper:

```zig
// src/apprt/win32/spawn.zig
const std = @import("std");
const Command = @import("../../Command.zig");

pub fn waitWithTimeout(cmd: *Command, ms: u32) !std.process.Child.Term {
    // bounded WaitForSingleObject / GetExitCodeProcess / TerminateProcess
}
```

Callers in `src/apprt/winui3/` use `waitWithTimeout`; upstream
`Command.wait()` semantics are not touched.

### 3. Submodule isolation (existing success)

`vendor/zig-control-plane/` already demonstrates the pattern: an entire
subsystem (CP server logic) is fork-owned, lives outside the upstream tree
in a vendored submodule, and is consumed by `src/apprt/winui3/`. New
fork-only subsystems should follow this pattern when they are large enough
to warrant a separate module.

### 4. Build-time policy injection (last resort)

When wrapping is genuinely impossible because an upstream-shared site
makes a policy decision the fork needs to override, the contract-aware
move is to extend the upstream interface with a generic / comptime
parameter on our fork only.

Example (hypothetical): if `src/Surface.zig` hard-codes `.forever = {}`
push semantics that winui3 needs to override, the fork-local refactor is
to add a `mailbox_policy` comptime parameter to Surface and let
`src/apprt/winui3/` inject `.{ .ns = N }`. The upstream-shared file still
becomes more general (no behaviour change for other apprts), and the
policy decision moves into fork-owned code.

This is contract extension, not contract violation. We carry it as
fork-local maintenance and we do NOT propose it to upstream.

## What we do NOT do

- **Propose architectural changes to upstream.** Issues describing a pain
  point are fine. PRs proposing the fix are not — we do not have the
  standing to dictate upstream's architecture, and our needs are
  Windows-specific in ways their other apprts do not share.
- **Modify other apprts.** `src/apprt/embedded.zig`, `src/apprt/gtk/`,
  `src/apprt/macos/` are not ours to maintain. If a build-error force
  pushes us to modify them, the right fix is in our `apprt/winui3/`
  consumer, not in their files.
- **Modify stdlib types in `src/datastruct/` or `src/os/`.** Wrap them
  instead. Their upstream maintainer is not us.
- **Frame self-imposed sprawl as "merge debt".** The cost is fork-local
  commitment; calling it debt externalises responsibility.

## Honest disclaimer

The lint catches the mechanical violation. It does not judge whether a
particular edit is genuinely impossible to wrap. That judgment is yours.

Some adaptations may be irreducible — Win32 PTY/text/font behaviour
diverges from Unix in ways the upstream interface does not capture, and
some core touches may be the only practical option. Those become our
fork-local maintenance commitment, recorded with the
`UPSTREAM-SHARED-OK:` marker plus a self-check answer in the commit body.

The audit at `notes/2026-04-27_fork_isolation_audit.md` distinguishes
"should have been wrapped" from "genuinely needed core touch". Use it as
the input to the refactor backlog.

## See also

- `AGENTS.md` Operating Rule on the apprt contract
- `tools/lint-fork-isolation.sh` (mechanical enforcement)
- `notes/2026-04-27_fork_isolation_audit.md` (current divergence audit)
- `docs/deadlock-discipline.md` (sibling discipline doc, same shape)
