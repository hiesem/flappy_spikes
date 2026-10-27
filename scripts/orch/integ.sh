#!/usr/bin/env bash
# integ.sh — rolling integration verify (ORCHESTRATION.md §5.2): the full unscoped verify on the newest feat/2.6 head in
# .worktrees/p26-integ; green → $ORCH/integ_green_sha. Run as a spawn.sh worker (one at a time).
set -uo pipefail
. "$(dirname "$0")/env.sh"
exec 7>"$ORCH/integ.lock"; flock 7   # one integration verify at a time (shared p26-integ worktree)
wt=$WS/.worktrees/p26-integ
[ -d "$wt" ] || { git -C "$REPO" worktree add -q --detach "$wt" feat/2.6; ln -s "$REPO/functions/node_modules" "$wt/functions/node_modules"; }
cd "$wt" && git checkout -q --detach "$(git -C "$REPO" rev-parse feat/2.6)"
head=$(git rev-parse HEAD); echo "integration verify on $head"
flutter pub get --offline > /dev/null 2>&1
python3 "$REPO/scripts/orch/bench.py" test --task null --scope full --where integration -- bash scripts/verify.sh > "$ORCH/integ-${head:0:8}.log" 2>&1
rc=$?
if [ $rc = 0 ]; then echo "$head" > "$ORCH/integ_green_sha"; echo "INTEG GREEN ${head:0:8}"; else echo "$head" > "$ORCH/integ_red_sha"; echo "INTEG RED ${head:0:8} (log $ORCH/integ-${head:0:8}.log)"; fi
echo "$(date '+%F %T') integration ${head:0:8}: $([ $rc = 0 ] && echo green || echo RED)" >> "$ORCH/RUNLOG.md"
exit $rc
