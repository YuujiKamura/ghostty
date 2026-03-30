#!/bin/bash
# Usage: tsf-inject.sh <session> <utf8-text>
# Sends ESC[TSF:<text> to the given CP session via agent-deck or direct pipe.
SESSION="$1"
TEXT="$2"
if [ -z "$SESSION" ] || [ -z "$TEXT" ]; then
    echo "Usage: tsf-inject.sh <session> <utf8-text>" >&2
    exit 1
fi
AGENT_DECK="$HOME/agent-deck/agent-deck.exe"
PAYLOAD=$(printf '\033[TSF:%s' "$TEXT")

# Try agent-deck send first (top-level)
if "$AGENT_DECK" send "$SESSION" "$PAYLOAD" --no-wait 2>/dev/null; then
    exit 0
fi

# Fallback: agent-deck session send
if "$AGENT_DECK" session send "$SESSION" "$PAYLOAD" --no-wait 2>/dev/null; then
    exit 0
fi

# Fallback: direct Named Pipe via INPUT protocol
# Extract PID from session name (ghostty-<PID>)
PID_NUM=$(echo "$SESSION" | grep -oP '\d+$')
if [ -n "$PID_NUM" ]; then
    PIPE_PATH="//./pipe/ghostty-winui3-ghostty-${PID_NUM}-${PID_NUM}"
    # Base64 encode the payload
    B64=$(printf '%s' "$PAYLOAD" | base64 -w0)
    REQUEST="INPUT|tsf-inject|${B64}"
    # Write to pipe (timeout 3s)
    if echo "$REQUEST" > "$PIPE_PATH" 2>/dev/null; then
        exit 0
    fi
fi

echo "WARN: All send methods failed for session '$SESSION'" >&2
exit 1
