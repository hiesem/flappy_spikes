#!/usr/bin/env bash
# build.sh <wp> <round> [fix-prompt-file] — start the builder for <wp> (round 1: the brief; later rounds: resume the WP's
# codex session with the fix prompt). Worker id <wp>-b<round>, cap 90 min.
# Builder: DeepSeek V4.1 Flash (`deepseek-flash`, effort max) through codex with DeepSeek's own API as the provider
# (owner 2026-10-28; was GPT-6.1 Terra medium). BUILDER_MODEL=gpt-6.1-terra (or -sol) switches back to OpenAI.
set -euo pipefail
. "$(dirname "$0")/env.sh"
wp=$1; n=$2; fix=${3:-}
wt=$WS/.worktrees/p26-$wp
model=${BUILDER_MODEL:-deepseek-flash}
if [[ "$model" == deepseek-* ]]; then
  effort=${BUILDER_EFFORT:-max}
  # the key lives outside the repo; it is exported into the builder's environment only, never printed
  set -a; . "$HOME/.config/duofoundry/deepseek.env"; set +a
  provider=(-c model_provider=deepseek
    -c 'model_providers.deepseek={name="DeepSeek",base_url="https://api.deepseek.com/v1",env_key="DEEPSEEK_API_KEY",wire_api="responses"}'
    -c model_context_window=1048576)   # codex has no metadata for deepseek-flash; without this it falls back to defaults
else
  effort=${BUILDER_EFFORT:-medium}; provider=()
fi
flags=(-m "$model" "${provider[@]}" -c model_reasoning_effort="$effort" -c sandbox_mode="danger-full-access" --json -o "$ORCH/$wp.b$n.last.txt")
[ "$n" -gt 1 ] && { [ -n "$fix" ] && [ -s "$fix" ] || { echo "build.sh: round $n needs a non-empty fix prompt file" >&2; exit 2; }; }
if [ -z "$fix" ]; then
  exec "$(dirname "$0")/spawn.sh" "$wp-b$n" 90 "$wt" -- codex exec "${flags[@]}" "$(cat "$ORCH/$wp.md")"
fi
b1=$W/$wp-b1; [ -d "$b1" ] || b1=$ORCH/killed/$wp-b1
sid=$(grep -h -m1 -o '"thread_id":"[^"]*"' "$b1/log" 2>/dev/null | head -1 | cut -d'"' -f4 || true)
# a session started on another model (e.g. a Terra thread) cannot be resumed on this one: start fresh with brief + fix
if [ -z "$sid" ] || ! grep -q -- "-m $model " "$b1/cmd" 2>/dev/null; then
  exec "$(dirname "$0")/spawn.sh" "$wp-b$n" 90 "$wt" -- codex exec "${flags[@]}" \
    "$(cat "$ORCH/$wp.md")

## This round (orchestrator) — earlier rounds were built by another builder; your worktree keeps their commits
$(cat "$fix")"
fi
exec "$(dirname "$0")/spawn.sh" "$wp-b$n" 90 "$wt" -- codex exec resume "$sid" "${flags[@]}" "$(cat "$fix")"
