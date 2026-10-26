#!/usr/bin/env bash
# vfy.sh <wp> <round> — full verify of the WP worktree as a detached worker <wp>-v<round> (heavy slot inside verify.sh).
. "$(dirname "$0")/env.sh"
wp=$1; n=$2; wt=$WS/.worktrees/p26-$wp
exec "$(dirname "$0")/spawn.sh" "$wp-v$n" 40 "$wt" -- python3 "$REPO/scripts/orch/bench.py" test --task "$wp" --scope full \
  --where task-worktree --wave "${WAVE:-W1}" -- bash scripts/verify.sh
