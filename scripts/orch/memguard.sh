#!/usr/bin/env bash
# memguard.sh — run by the systemd user service orch-memguard (Restart=always). Keeps memory above MEMGUARD_MIN_MB so
# Claude Code never has to reap the orchestrator's watcher: below the floor it stops ONE orchestration worker session
# (a tester `claude -p` first, then a codex builder; newest first, so the least work is lost) with everything it
# started (stop.sh kills its process group), marks it `memkilled`, logs it, and waits before the next check.
# Never touches interactive Claude sessions, verifies, merges or automerge: those are re-run by the orchestrator.
. "$(dirname "$0")/env.sh"
MIN=${MEMGUARD_MIN_MB:-3072}; PAUSE=${MEMGUARD_PAUSE_S:-90}
avail() { awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo; }
victim() {  # prints the worker id to stop, testers before builders, newest first
  for kind in t b; do
    for d in $(ls -td "$W"/*-"$kind"[0-9]* 2>/dev/null); do
      [ -f "$d/exit" ] && continue
      pid=$(cat "$d/pid" 2>/dev/null) && kill -0 "$pid" 2>/dev/null || continue
      grep -qE '(^|/)(claude|codex|tester\.sh)' "$d/cmd" 2>/dev/null || continue
      basename "$d"; return
    done
  done
}
while :; do
  m=$(avail)
  if [ "$m" -lt "$MIN" ]; then
    id=$(victim)
    if [ -n "$id" ]; then
      "$(dirname "$0")/stop.sh" "$id" >/dev/null
      touch "$W/$id/memkilled"
      echo "$(date '+%F %T') [memguard] MemAvailable ${m} MB < ${MIN} MB -> stopped $id (re-run it when memory recovers)" >> "$ORCH/RUNLOG.md"
      sleep "$PAUSE"; continue
    fi
  fi
  sleep 10
done
