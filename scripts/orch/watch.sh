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
  if [ "$now" != "$before" ]; then echo "EVENT: worker state changed"; diff <(echo "$before") <(echo "$now") | grep '^>' ; break; fi
  echo "$now" | grep -qE ' (STALLED|OVERCAP|DEAD)$' && { echo "EVENT: stalled/overcap/dead worker"; break; }
  [ $(date +%s) -ge $end ] && { echo "HEARTBEAT ${max}m"; break; }
  sleep 30
done
"$(dirname "$0")/status.sh"
