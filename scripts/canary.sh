#!/bin/bash
# Run a new Ghostty build ("canary") next to the one in use, to try it and
# smoke-test it before it replaces the current build.
#
# The canary is the working tree built with ./build-winui3.sh and copied to
# its own folder (~/.ghostty-win/canary), so the exe in use is never locked or
# replaced. Canary windows run with:
#   GHOSTTY_INSTANCE_ID=canary   own single-instance IPC pipe (ghostty-canary),
#                                so "+new-window" never reaches the other build
#   GHOSTTY_SESSION_NAME=ghostty-canary-<time>
#                                deckpilot lists them as ghostty-canary-...
#                                (the window title shows the same name)
#   GHOSTTY_CONTROL_PLANE=1      reachable from deckpilot
# Config, themes and debug logs (per PID) are shared as usual.
#
# Usage:
#   bash scripts/canary.sh build            Build the working tree and install it as the canary
#   bash scripts/canary.sh launch           Open a canary window (prints its deckpilot session)
#   bash scripts/canary.sh smoke [-Only a,b] Run the same UIA tests on the current build and on
#                                           the canary, side by side (default: CP tests that do
#                                           not move the mouse; -All for the full suite)
#   bash scripts/canary.sh status           Canary build info and running canary windows
#   bash scripts/canary.sh stop             Close canary windows (only processes from the canary folder)
#
# Env: GHOSTTY_STABLE_EXE  the current build to compare with (default: ghostty.exe on PATH)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CANARY_ROOT="$HOME/.ghostty-win/canary"
CANARY_EXE="$CANARY_ROOT/bin/ghostty.exe"
INFO_FILE="$CANARY_ROOT/canary-build.txt"
DEFAULT_SMOKE="phase2-session-detect,phase2-send-show-roundtrip,phase3-ascii-input,phase3-input-tab-routing"

winpath() { cygpath -w "$1" 2>/dev/null || echo "$1"; }

stable_exe() {
    if [ -n "${GHOSTTY_STABLE_EXE:-}" ]; then echo "$GHOSTTY_STABLE_EXE"; return; fi
    command -v ghostty.exe 2>/dev/null || command -v ghostty 2>/dev/null || true
}

# canary_pids: PIDs of ghostty processes started from the canary folder.
canary_pids() {
    pwsh -NoProfile -Command "\$root = [IO.Path]::GetFullPath('$(winpath "$CANARY_ROOT")'); Get-Process ghostty -ErrorAction SilentlyContinue | Where-Object { \$_.Path -and \$_.Path.StartsWith(\$root, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { \$_.Id }" 2>/dev/null | tr -d '\r'
}

cmd_build() {
    cd "$REPO_ROOT" || exit 1
    if [ -n "$(canary_pids)" ]; then
        echo "[canary] canary windows are open (PID $(canary_pids | tr '\n' ' ')); close them or run: bash scripts/canary.sh stop" >&2
        exit 1
    fi
    ./build-winui3.sh "$@" || exit 1
    # build-winui3.sh picks zig-out-winui3 / -staging / -build depending on
    # which exe is locked; take the exe it just wrote (the newest).
    local newest prefix
    newest="$(ls -t zig-out-winui3*/bin/ghostty.exe 2>/dev/null | head -1)"
    if [ -z "$newest" ]; then
        echo "[canary] no built ghostty.exe found under zig-out-winui3*" >&2
        exit 1
    fi
    prefix="${newest%/bin/ghostty.exe}"
    local tmp="$CANARY_ROOT.new"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    cp -r "$prefix/." "$tmp/" || { echo "[canary] copy failed" >&2; exit 1; }
    rm -rf "$CANARY_ROOT.old"
    if [ -d "$CANARY_ROOT" ]; then mv "$CANARY_ROOT" "$CANARY_ROOT.old" || exit 1; fi
    mv "$tmp" "$CANARY_ROOT" || exit 1
    rm -rf "$CANARY_ROOT.old"
    {
        echo "commit=$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . ':!xaml/prebuilt' 2>/dev/null || echo -dirty)"
        echo "branch=$(git rev-parse --abbrev-ref HEAD)"
        echo "source=$(winpath "$REPO_ROOT")"
        echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$INFO_FILE"
    echo "[canary] installed $(sed -n 's/^commit=//p' "$INFO_FILE") from $prefix -> $CANARY_ROOT"
    echo "[canary] open a window: bash scripts/canary.sh launch"
}

cmd_launch() {
    if [ ! -f "$CANARY_EXE" ]; then
        echo "[canary] not built yet: bash scripts/canary.sh build" >&2
        exit 1
    fi
    local session="ghostty-canary-$(date +%H%M%S)"
    GHOSTTY_INSTANCE_ID=canary GHOSTTY_SESSION_NAME="$session" GHOSTTY_CONTROL_PLANE=1 \
        pwsh -NoProfile -Command "Start-Process -FilePath '$(winpath "$CANARY_EXE")'" || exit 1
    echo "[canary] launched $(sed -n 's/^commit=//p' "$INFO_FILE"); deckpilot session: $session"
    echo "[canary] e.g.  deckpilot show $session --tabs"
}

# smoke: run the UIA suite against an exe and print "<status> <name>" lines.
run_suite() {
    local exe="$1" instance="$2"; shift 2
    local results="$REPO_ROOT/tests/winui3/.last-results.json"
    rm -f "$results"
    # The test windows get their own single-instance pipe so they never talk
    # to the windows in use.
    GHOSTTY_INSTANCE_ID="$instance" pwsh -NoProfile -File "$REPO_ROOT/tests/winui3/run-all-tests.ps1" \
        -ExePath "$(winpath "$exe")" "$@" > "$CANARY_ROOT.$instance.log" 2>&1
    if [ -f "$results" ]; then
        pwsh -NoProfile -Command "(Get-Content '$(winpath "$results")' -Raw | ConvertFrom-Json) | ForEach-Object { '{0} {1}' -f \$_.Status, \$_.Name }" | tr -d '\r'
    fi
}

cmd_smoke() {
    if [ ! -f "$CANARY_EXE" ]; then
        echo "[canary] not built yet: bash scripts/canary.sh build" >&2
        exit 1
    fi
    local stable; stable="$(stable_exe)"
    if [ -z "$stable" ] || [ ! -f "$stable" ]; then
        echo "[canary] current build not found; set GHOSTTY_STABLE_EXE" >&2
        exit 1
    fi
    local args=(-Only "$DEFAULT_SMOKE")
    if [ "${1:-}" = "-All" ]; then args=(); shift; fi
    if [ "${1:-}" = "-Only" ] && [ -n "${2:-}" ]; then args=(-Only "$2"); fi

    echo "[smoke] current: $stable"
    echo "[smoke] canary:  $CANARY_EXE ($(sed -n 's/^commit=//p' "$INFO_FILE"))"
    echo "[smoke] tests:   ${args[*]:-full suite}"
    local s c
    s="$(run_suite "$stable" smoke-current "${args[@]}")"
    c="$(run_suite "$CANARY_EXE" smoke-canary "${args[@]}")"
    printf '%-34s %-8s %-8s\n' TEST CURRENT CANARY
    local diff=0
    for name in $( (echo "$s"; echo "$c") | awk 'NF==2 {print $2}' | sort -u); do
        local a b
        a="$(echo "$s" | awk -v n="$name" '$2==n {print $1}')"; a="${a:--}"
        b="$(echo "$c" | awk -v n="$name" '$2==n {print $1}')"; b="${b:--}"
        local mark=""
        if [ "$a" != "$b" ]; then mark="  <- differs"; diff=$((diff + 1)); fi
        printf '%-34s %-8s %-8s%s\n' "$name" "$a" "$b" "$mark"
    done
    echo "[smoke] $diff test(s) differ. A test the canary adds or fixes is expected to differ;"
    echo "        a PASS on current that FAILs on canary is a regression. Logs: $CANARY_ROOT.smoke-*.log"
    if echo "$c" | grep -q '^FAIL'; then return 1; fi
}

cmd_status() {
    if [ -f "$INFO_FILE" ]; then
        echo "[canary] build:"; sed 's/^/  /' "$INFO_FILE"
    else
        echo "[canary] not built"
    fi
    local pids; pids="$(canary_pids)"
    echo "[canary] running windows: ${pids:-none}" | tr '\n' ' '; echo
}

cmd_stop() {
    local pids; pids="$(canary_pids)"
    if [ -z "$pids" ]; then echo "[canary] no canary windows"; return 0; fi
    for p in $pids; do
        pwsh -NoProfile -Command "Stop-Process -Id $p -ErrorAction SilentlyContinue" && echo "[canary] closed PID $p"
    done
}

case "${1:-}" in
    build) shift; cmd_build "$@" ;;
    launch) cmd_launch ;;
    smoke) shift; cmd_smoke "$@" ;;
    status) cmd_status ;;
    stop) cmd_stop ;;
    *) sed -n '2,29p' "$0"; exit 2 ;;
esac
