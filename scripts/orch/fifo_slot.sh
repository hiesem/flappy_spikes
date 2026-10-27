#!/usr/bin/env bash
# fifo_slot.sh <name> <n> -- <cmd...> — like slot.sh but first come, first served: a waiter takes a slot only when it holds
# the oldest ticket in $ORCH/queue/<name>/ (ticket time = $TICKET_TS or now). Slots beyond 2 need MemAvailable >= 9 GB.
. "$(dirname "$0")/env.sh"
name=$1 n=$2; shift 2; [ "$1" = "--" ] && shift
q="$ORCH/queue/$name"; mkdir -p "$q"
ticket="$q/$(printf '%012d' "${TICKET_TS:-$(date +%s)}")-$$"; : > "$ticket"
trap 'rm -f "$ticket"' EXIT
while :; do
  for t in "$q"/*; do p=${t##*-}; kill -0 "$p" 2>/dev/null || rm -f "$t"; done   # drop dead waiters
  if [ "$(ls "$q" | sort | head -1)" = "$(basename "$ticket")" ]; then
    for i in $(seq 0 $((n-1))); do
      if [ "$i" -ge 2 ] && [ "$(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo)" -lt 9 ]; then continue; fi
      exec 9>"$ORCH/locks/$name-$i"
      if flock -n 9; then rm -f "$ticket"; trap - EXIT; exec "$@"; fi
      exec 9>&-
    done
  fi
  sleep 10
done
