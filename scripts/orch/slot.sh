#!/usr/bin/env bash
# slot.sh <name> <n> -- <cmd...> — run <cmd> while holding one of <n> lock files $ORCH/locks/<name>-<i> (waits for a free one).
. "$(dirname "$0")/env.sh"
name=$1 n=$2; shift 2; [ "$1" = "--" ] && shift
while :; do
  for i in $(seq 0 $((n-1))); do
    exec 9>"$ORCH/locks/$name-$i"
    if flock -n 9; then exec "$@"; fi
    exec 9>&-
  done
  sleep 15
done
