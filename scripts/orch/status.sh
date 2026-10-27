#!/usr/bin/env bash
# status.sh — one line per worker: RUNNING / STALLED / OVERCAP / DONE(exit) / DEAD, idle and run minutes.
. "$(dirname "$0")/env.sh"
# only codex builders stream output, so only they can be STALLED on idle
now=$(date +%s); n=0
for d in "$W"/*/; do
  [ -d "$d" ] || continue; id=$(basename "$d"); [ -f "$d/processed" ] && [ -z "${ALL:-}" ] && continue; n=$((n+1))
  pid=$(cat "$d/pid" 2>/dev/null || echo 0); st=$(cat "$d/started" 2>/dev/null || echo $now); cap=$(cat "$d/cap" 2>/dev/null || echo 90)
  run=$(( (now-st)/60 )); lm=$(stat -c %Y "$d/log" 2>/dev/null || echo $st); idle=$(( (now-lm)/60 ))
  if [ -f "$d/exit" ]; then s="DONE(exit $(cat "$d/exit"))"
  elif kill -0 "$pid" 2>/dev/null; then
    if [ $run -ge $cap ]; then s=OVERCAP; elif [ $idle -ge $IDLE_MIN ] && grep -q "codex" "$d/cmd" 2>/dev/null; then s=STALLED; else s=RUNNING; fi
  else s=DEAD; fi
  printf '%-34s %-14s run %4sm idle %3sm cap %3sm pid %s\n' "$id" "$s" "$run" "$idle" "$cap" "$pid"
done
[ $n = 0 ] && echo "no workers"
true
