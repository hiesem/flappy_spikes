#!/usr/bin/env bash
# vfy.sh <wp> <round> — full verify of the WP worktree as a detached worker <wp>-v<round> (heavy slot inside verify.sh).
D=$(cd "$(dirname "$0")" && pwd)   # absolute: spawn.sh runs the command inside the worktree
. "$D/env.sh"
wp=$1; n=$2; wt=$WS/.worktrees/p26-$wp
exec "$D/spawn.sh" "$wp-v$n" 60 "$wt" -- "$D/slot.sh" verify 2 -- env VERIFY_SKIP_HEAVY=1 python3 "$REPO/scripts/orch/bench.py" test --task "$wp" --scope full \
  --where task-worktree --wave "${WAVE:-W1}" -- bash scripts/verify.sh
