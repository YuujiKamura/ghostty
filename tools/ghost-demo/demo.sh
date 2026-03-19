#!/bin/bash
# Ghost demo: launch Ghostty ReleaseFast → send 60fps animation via CP
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GHOSTTY="$SCRIPT_DIR/../../zig-out-winui3/bin/ghostty.exe"
AGENT_CTL="$HOME/agent-relay/target/debug/agent-ctl.exe"
PLAY_CMD="python $SCRIPT_DIR/play.py --fps 60"

if [ ! -f "$GHOSTTY" ]; then
    echo "[demo] ghostty.exe not found. Run: ./build-winui3.sh -Doptimize=ReleaseFast"
    exit 1
fi

echo "[demo] Killing old instances..."
taskkill //F //IM ghostty.exe 2>/dev/null || true
sleep 1

echo "[demo] Starting Ghostty (ReleaseFast)..."
"$GHOSTTY" &
sleep 8

echo "[demo] Cleaning dead sessions..."
"$AGENT_CTL" clean 2>/dev/null || true

echo "[demo] Finding live session..."
SESSION=""
SESSION_DIR="$HOME/AppData/Local/WindowsTerminal/control-plane/winui3/sessions"
for f in "$SESSION_DIR"/*ghostty*.session; do
    [ -f "$f" ] || continue
    s=$(basename "$f" .session)
    if "$AGENT_CTL" ping "$s" 2>/dev/null | grep -q PONG; then
        SESSION="$s"
        break
    fi
done

if [ -z "$SESSION" ]; then
    echo "[demo] ERROR: No live Ghostty session found"
    exit 1
fi

echo "[demo] Session: $SESSION"
echo "[demo] Sending ghost demo (60fps)..."
"$AGENT_CTL" send "$SESSION" "$PLAY_CMD" --enter
echo "[demo] Running. Ctrl+C in Ghostty to stop."
