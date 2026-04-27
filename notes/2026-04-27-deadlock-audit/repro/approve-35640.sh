#!/usr/bin/env bash
sess="ghostty-35640"
LOG=$(dirname "$0")/approver-events.log
echo "[$(date +%H:%M:%S.%3N)] approver-start sess=$sess" > "$LOG"
i=0
while true; do
  i=$((i+1))
  ts=$(date +%H:%M:%S.%3N)
  list=$(deckpilot list 2>/dev/null)
  if ! echo "$list" | grep -q "$sess"; then
    echo "[$ts] sess gone from list" >> "$LOG"
    break
  fi
  status=$(echo "$list" | awk -v s="$sess" '$1==s{print $NF}')
  if [ "$status" = "dead" ]; then
    echo "[$ts] dead detected" >> "$LOG"
    break
  fi
  out=$(deckpilot show "$sess" --tail 25 2>/dev/null)
  if echo "$out" | grep -qE "Allow execution|Apply this change"; then
    deckpilot send "$sess" "2" >/dev/null 2>&1
    echo "[$(date +%H:%M:%S.%3N)] APPROVED status=$status" >> "$LOG"
  else
    [ $((i % 10)) -eq 0 ] && echo "[$ts] poll=$i status=$status no-prompt" >> "$LOG"
  fi
  sleep 1
done
echo "[$(date +%H:%M:%S.%3N)] approver-exit total_polls=$i" >> "$LOG"
