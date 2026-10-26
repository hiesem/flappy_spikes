#!/usr/bin/env bash
# tick.sh — run by the systemd user timer (every 30 min). If the orchestrator lease is older than LEASE_STALE_MIN
# (the chat session is dead or silent) and no headless orchestrator runs, start ONE headless Opus orchestrator pass.
. "$(dirname "$0")/env.sh"
[ -f "$ORCH/ORCH_STOP" ] && exit 0            # owner/orchestrator stopped the build
[ -f "$ORCH/ORCH_ACTIVE" ] || exit 0          # build not started (or finished)
age=$("$(dirname "$0")/lease.sh" age-min)
[ "$age" -lt "$LEASE_STALE_MIN" ] && exit 0
exec 9>"$ORCH/headless.lock"; flock -n 9 || exit 0
"$(dirname "$0")/lease.sh" take "headless-$$"
log=$ORCH/headless/$(date +%Y%m%d-%H%M).log; mkdir -p "$ORCH/headless"
cd "$REPO" && timeout 75m claude -p --model claude-opus-5-5 --effort medium --permission-mode bypassPermissions \
  "$(cat "$REPO/scripts/orch/headless_prompt.md")" > "$log" 2>&1
echo "headless pass exit $? ($(date '+%F %T'))" >> "$ORCH/RUNLOG.md"
