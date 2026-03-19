#!/bin/bash
# Usage: tsf-inject.sh <session> <utf8-text>
# Sends ESC[TSF:<text> to the given CP session via agent-ctl send.
SESSION="$1"
TEXT="$2"
if [ -z "$SESSION" ] || [ -z "$TEXT" ]; then
    echo "Usage: tsf-inject.sh <session> <utf8-text>" >&2
    exit 1
fi
AGENT_CTL="$HOME/agent-relay/target/debug/agent-ctl.exe"
PAYLOAD=$(printf '\033[TSF:%s' "$TEXT")
exec "$AGENT_CTL" send "$SESSION" "$PAYLOAD"
