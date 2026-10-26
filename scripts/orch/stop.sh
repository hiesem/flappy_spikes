#!/usr/bin/env bash
# stop.sh <worker-id> — stop a worker and everything it started (its own process group; never pkill -f).
. "$(dirname "$0")/env.sh"
d=$W/$1; pid=$(cat "$d/pid" 2>/dev/null) || { echo "no worker $1"; exit 1; }
kill -TERM -- "-$pid" 2>/dev/null; sleep 5; kill -KILL -- "-$pid" 2>/dev/null
[ -f "$d/exit" ] || echo "killed" > "$d/exit"
echo "stopped $1 (pgid $pid)"
