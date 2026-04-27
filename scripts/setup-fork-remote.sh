#!/usr/bin/env bash
# scripts/setup-fork-remote.sh
# Configures git defaults so push targets the personal fork, not upstream.
# See issue #237.
set -euo pipefail

if ! git remote get-url fork &>/dev/null; then
  echo "ERROR: 'fork' remote not configured. Run:" >&2
  echo "  git remote add fork https://github.com/YuujiKamura/ghostty.git" >&2
  exit 1
fi

git config remote.pushDefault fork
git config push.default current
echo "OK: pushDefault=fork, push.default=current"
git config --local --get remote.pushDefault
git config --local --get push.default
