#!/bin/bash
# Promote Ghostty staging build to retail.
# Handles locked files via Atomic Rename (renaming .exe/.dll to .old).
#
# Usage:
#   bash scripts/promote-staging.sh

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GHOSTTY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

STAGING="$GHOSTTY_ROOT/zig-out-winui3-staging"
RETAIL="$GHOSTTY_ROOT/zig-out-winui3"

if [ ! -d "$STAGING" ]; then
    echo "[promote] staging directory not found: $STAGING" >&2
    exit 1
fi

# Ensure retail directory exists
mkdir -p "$RETAIL"

echo "[promote] promoting $STAGING -> $RETAIL"

# Use rsync or cp --recursive to copy everything from staging to retail
# But first, we must handle locked files in retail/bin/
if [ -d "$RETAIL/bin" ]; then
    for f in "$RETAIL/bin"/*.exe "$RETAIL/bin"/*.dll; do
        [ -f "$f" ] || continue
        # Rename locked file to .old (allowed on Windows)
        # Skip if already .old
        [[ "$f" == *.old ]] && continue
        
        old_f="${f}.old"
        rm -f "$old_f" 2>/dev/null || true
        mv -f "$f" "$old_f" 2>/dev/null || true
    done
fi

# Copy staging to retail
# Use cp -rf for simplicity (rsync is better but might not be available)
cp -rf "$STAGING"/* "$RETAIL/"

# Cleanup: attempt to remove .old files (will fail if still running, which is fine)
if [ -d "$RETAIL/bin" ]; then
    rm -f "$RETAIL/bin"/*.old 2>/dev/null || true
fi

echo "[promote] finished. retail is now updated."
exit 0
