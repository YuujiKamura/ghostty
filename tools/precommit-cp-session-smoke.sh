#!/usr/bin/env bash
# Pre-commit gate for tests/winui3/test-cp-session-file-appears.ps1.
# Only fires when staged files touch the CP orchestration glue.
# Bypass: SKIP_UIA_SMOKE=1 or LEFTHOOK_EXCLUDE=cp-session-smoke.
set -u

if [ "${SKIP_UIA_SMOKE:-0}" = "1" ]; then
  echo "[cp-session-smoke] SKIP_UIA_SMOKE=1, skipping"
  exit 0
fi

if ! git diff --cached --name-only --diff-filter=ACMR | \
     grep -qE '^(src/apprt/winui3/|vendor/zig-control-plane/|xaml/)|^(build\.zig|build\.zig\.zon)$'; then
  echo "[cp-session-smoke] no relevant paths staged, skipping"
  exit 0
fi

exec pwsh.exe -NoProfile -File tests/winui3/test-cp-session-file-appears.ps1
