#!/usr/bin/env bash
# build.sh <wp> <round> [fix-prompt-file] — start the Sol builder for <wp> (round 1: the brief; later rounds: resume
# the WP's codex session with the fix prompt). Worker id <wp>-b<round>, cap 90 min.
set -euo pipefail
. "$(dirname "$0")/env.sh"
wp=$1; n=$2; fix=${3:-}
wt=$WS/.worktrees/p26-$wp
flags=(-m gpt-6.1-sol -c model_reasoning_effort="medium" -c sandbox_mode="danger-full-access" --json -o "$ORCH/$wp.b$n.last.txt")
if [ -z "$fix" ]; then
  exec "$(dirname "$0")/spawn.sh" "$wp-b$n" 90 "$wt" -- codex exec "${flags[@]}" "$(cat "$ORCH/$wp.md")"
fi
sid=$(grep -h -m1 -o '"thread_id":"[^"]*"' "$W/$wp-b1/log" | cut -d'"' -f4)
[ -n "$sid" ] || { echo "no codex session id for $wp"; exit 2; }
exec "$(dirname "$0")/spawn.sh" "$wp-b$n" 90 "$wt" -- codex exec resume "$sid" "${flags[@]}" "$(cat "$fix")"
