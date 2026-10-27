#!/usr/bin/env bash
# watch.sh [minutes=10] — the in-session heartbeat. Refreshes the lease ("session") every 30 s and exits when a worker
# finishes, dies, stalls or passes its cap, or after <minutes> (the regular status update). Prints why + status.sh.
. "$(dirname "$0")/env.sh"
max=${1:-10}; end=$(( $(date +%s) + max*60 ))
snap() { "$(dirname "$0")/status.sh" | awk '{print $1, $2}' | sed 's/(exit [0-9]*)//' | sort; }
before=$(snap)
while :; do
  "$(dirname "$0")/lease.sh" take session
  now=$(snap)
  # wake only for workers that newly finished / died / stalled (new RUNNING workers are not events)
  ch=$(comm -13 <(echo "$before" | sort) <(echo "$now" | sort) | grep -v ' RUNNING$')
  if [ -n "$ch" ]; then echo "EVENT: worker state changed"; echo "$ch"; break; fi
  echo "$now" | grep -qE ' (STALLED|OVERCAP|DEAD)$' && { echo "EVENT: stalled/overcap/dead worker"; break; }
  [ $(date +%s) -ge $end ] && { echo "HEARTBEAT ${max}m"; break; }
  sleep 30
done
"$(dirname "$0")/status.sh"
