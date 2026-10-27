#!/usr/bin/env bash
# slot.sh <name> <n> -- <cmd...> — run <cmd> while holding one of <n> lock files $ORCH/locks/<name>-<i> (waits for a free one).
. "$(dirname "$0")/env.sh"
name=$1 n=$2; shift 2; [ "$1" = "--" ] && shift
while :; do
  for i in $(seq 0 $((n-1))); do
    # slots beyond the first two only open while memory is plentiful (MemAvailable >= 8 GB)
    if [ "$i" -ge 2 ] && [ "$(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo)" -lt 8 ]; then continue; fi
    exec 9>"$ORCH/locks/$name-$i"
    if flock -n 9; then exec "$@"; fi
    exec 9>&-
  done
  sleep 15
done
