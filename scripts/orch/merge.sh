#!/usr/bin/env bash
# merge.sh <wp> — the merge queue step (ORCHESTRATION.md §5.2): rebase p26/<wp> on feat/2.6, fast check, fast-forward
# feat/2.6, push, bench event. Exit 3 = rebase conflict (back to the builder), 4 = fast check red.
set -uo pipefail
. "$(dirname "$0")/env.sh"
wp=$1; wt=$WS/.worktrees/p26-$wp; t0=$(date +%s)
exec 8>"$ORCH/merge.lock"; flock 8
cd "$wt" || exit 2
old_base=$(git merge-base HEAD feat/2.6)
if ! git rebase -q feat/2.6; then
  git rebase --abort; echo "MERGE CONFLICT $wp"
  python3 "$REPO/scripts/orch/bench.py" ev merge task_id="$wp" ts_start="$(date -d @$t0 -Iseconds)" ts_end="$(date -Iseconds)" conflict:=true resolved_by=pending result=conflict
  exit 3
fi
# fast check: analyze + the WP's own changed/matching tests + core tests, on the rebased tree (scope = the WP's diff
# against the new feat/2.6; cross-package interactions are the rolling integration verify's job)
if ! python3 "$REPO/scripts/orch/bench.py" test --task "$wp" --scope targeted --where task-worktree -- \
     env VERIFY_BASE=feat/2.6 VERIFY_SCOPED=1 VERIFY_SKIP_HEAVY=1 bash scripts/verify.sh > "$ORCH/merge-$wp.log" 2>&1; then
  echo "FAST CHECK RED $wp (see $ORCH/merge-$wp.log)"; exit 4
fi
# feat/2.6 may have moved during the check: rebase again; recheck only if product code (not scripts/orch, docs, bench) moved
for try in 1 2 3; do
  checked=$(git merge-base HEAD feat/2.6)
  [ "$checked" = "$(git rev-parse feat/2.6)" ] && break
  git rebase -q feat/2.6 || { git rebase --abort; echo "MERGE CONFLICT $wp (late)"; exit 3; }
  if git diff --name-only "$checked" feat/2.6 | grep -qvE '^(scripts/orch/|docs/|bench/)'; then
    python3 "$REPO/scripts/orch/bench.py" test --task "$wp" --scope targeted --where task-worktree -- \
      env VERIFY_BASE=feat/2.6 VERIFY_SCOPED=1 VERIFY_SKIP_HEAVY=1 bash scripts/verify.sh >> "$ORCH/merge-$wp.log" 2>&1 || { echo "FAST CHECK RED $wp (late)"; exit 4; }
  fi
done
stat=$(git diff --shortstat feat/2.6...HEAD)
cd "$REPO" && git merge -q --ff-only "p26/$wp" || { echo "FF FAILED $wp"; exit 5; }
sha=$(git rev-parse --short HEAD)
f=$(echo "$stat" | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo 0)
a=$(echo "$stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
r=$(echo "$stat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)
python3 "$REPO/scripts/orch/bench.py" ev merge task_id="$wp" sha="$sha" ts_start="$(date -d @$t0 -Iseconds)" ts_end="$(date -Iseconds)" conflict:=false resolved_by=none files_changed:=${f:-0} lines_added:=${a:-0} lines_removed:=${r:-0} > /dev/null
git add bench && git commit -q -m "bench: merge $wp" || true
git push -q origin feat/2.6 && echo "MERGED $wp -> $sha"
echo "$(date '+%F %T') merged $wp -> $sha ($stat)" >> "$ORCH/RUNLOG.md"
