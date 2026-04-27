#!/usr/bin/env bash
LOG=$(dirname "$0")/monitor-events.log
SRC=/c/Users/yuuji/AppData/Local/Temp/deckpilot-daemon.log
START_FILE=$(dirname "$0")/daemon-baseline-offset.txt
offset=$(cat "$START_FILE" 2>/dev/null || stat -c '%s' "$SRC")
echo "[$(date +%H:%M:%S.%3N)] monitor-start offset=$offset" > "$LOG"
counter=0
while true; do
  counter=$((counter+1))
  list=$(deckpilot list 2>/dev/null)
  if ! echo "$list" | grep -q "ghostty-35640"; then
    echo "[$(date +%H:%M:%S.%3N)] sess gone from list" >> "$LOG"
    break
  fi
  status=$(echo "$list" | awk '$1=="ghostty-35640"{print $NF}')
  if [ "$status" = "dead" ]; then
    echo "[$(date +%H:%M:%S.%3N)] dead detected status=$status" >> "$LOG"
    # Capture daemon log slice up to now
    current=$(stat -c '%s' "$SRC")
    tail -c +$((offset+1)) "$SRC" 2>/dev/null > $(dirname "$0")/daemon-slice-final.log
    echo "[$(date +%H:%M:%S.%3N)] daemon slice captured ($((current-offset)) bytes)" >> "$LOG"
    break
  fi
  current=$(stat -c '%s' "$SRC" 2>/dev/null)
  if [ "$current" -gt "$offset" ]; then
    new_events=$(tail -c +$((offset+1)) "$SRC" 2>/dev/null \
      | grep "35640" \
      | grep -E "BUSY|renderer_locked|pipe.Tail|recovered|dead|added")
    if [ -n "$new_events" ]; then
      echo "$new_events" | sed "s/^/[$(date +%H:%M:%S.%3N) match] /" >> "$LOG"
    fi
    offset=$current
  fi
  [ $((counter % 30)) -eq 0 ] && echo "[$(date +%H:%M:%S.%3N)] tick counter=$counter status=$status" >> "$LOG"
  sleep 0.5
done
echo "[$(date +%H:%M:%S.%3N)] monitor-exit counter=$counter" >> "$LOG"
