#!/usr/bin/env bash
# Pre-commit gate for tests/winui3/test-cp-session-file-appears.ps1.
# Only fires when staged files touch the CP orchestration glue.
# Bypass: SKIP_UIA_SMOKE=1 or LEFTHOOK_EXCLUDE=cp-session-smoke.
set -u

if [ "${SKIP_UIA_SMOKE:-0}" = "1" ]; then
  echo "[cp-session-smoke] SKIP_UIA_SMOKE=1, skipping"
  exit 0
fi

# NOTE: vendor/zig-control-plane is a git submodule. When only the
# submodule pointer (gitlink) bumps, `git diff --cached --name-only` reports
# the bare path `vendor/zig-control-plane` with NO trailing slash, so the
# `(/|$)` group is required to catch pointer-only bumps as well as nested
# files. See ~/.agents/scratch/ghostty-win/lefthook-submodule-regex-fix-2026-05-05.md.
if ! git diff --cached --name-only --diff-filter=ACMR | \
     grep -qE '^(src/apprt/winui3/|vendor/zig-control-plane(/|$)|xaml/)|^(build\.zig|build\.zig\.zon)$'; then
  echo "[cp-session-smoke] no relevant paths staged, skipping"
  exit 0
fi

exec pwsh.exe -NoProfile -File tests/winui3/test-cp-session-file-appears.ps1
