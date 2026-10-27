#!/usr/bin/env bash
# automerge.sh — background worker: every 60 s, merge each WP whose LATEST round n has <wp>-v<n> exit 0 AND <wp>-t<n>
# verdict PASS (merge queue, one at a time). Marks $ORCH/merged/<wp>; a conflict/red fast check is logged for the orchestrator.
. "$(dirname "$0")/env.sh"
mkdir -p "$ORCH/merged" "$ORCH/mergefail"
verdict() { python3 -c "
import json,sys
s=open(sys.argv[1]).read()
try: r=json.loads(s[s.index('{'):]).get('result','')
except Exception: r=''
v=r[r.rfind('VERDICT'):].split('\n')[0] if 'VERDICT' in r else ''
print('PASS' if 'PASS' in v else 'FAIL')" "$1"; }
while [ ! -f "$ORCH/ORCH_STOP" ]; do
  # a builder round that finished cleanly gets its full verify + tester at once (the orchestrator reads the verdicts)
  for b in "$W"/*-b[0-9]*/; do
    id=$(basename "$b"); wp=${id%-b*}; n=${id##*-b}
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    [ "$(cat "$b/exit" 2>/dev/null)" = 0 ] || continue
    [ -d "$WS/.worktrees/p26-$wp" ] || continue     # only real work packages (not integ/merge/chain workers)
    if [ -n "$(git -C "$WS/.worktrees/p26-$wp" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      touch "$b/noauto"; echo "$(date '+%F %T') [automerge] $wp r$n ended with UNCOMMITTED changes -> orchestrator" >> "$ORCH/RUNLOG.md"; continue; fi
    [ -e "$W/$wp-v$n" ] || [ -e "$W/$wp-t$n" ] || [ -e "$b/noauto" ] && continue
    "$(dirname "$0")/vfy.sh" "$wp" "$n" > /dev/null 2>&1; "$(dirname "$0")/tester.sh" "$wp" "$n" > /dev/null 2>&1
    echo "$(date '+%F %T') [automerge] $wp r$n built -> verify + tester started" >> "$ORCH/RUNLOG.md"
  done
  for v in "$W"/*-v[0-9]*/; do
    id=$(basename "$v"); wp=${id%-v*}; n=${id##*-v}
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    [ -d "$WS/.worktrees/p26-$wp" ] || continue
    [ -e "$ORCH/merged/$wp" ] || [ -e "$ORCH/mergefail/$wp-$n" ] && continue
    ls -d "$W/$wp"-[vb]* 2>/dev/null | grep -qE -- "-[vb]$((n+1))$" && continue      # a newer round exists
    [ "$(cat "$v/exit" 2>/dev/null)" = 0 ] || continue
    t="$W/$wp-t$n"; [ -e "$t/exit" ] || continue
    [ "$(verdict "$t/log")" = PASS ] || continue
    git -C "$REPO" branch --list "p26/$wp" | grep -q . || continue
    if out=$("$(dirname "$0")/merge.sh" "$wp" 2>&1); then
      touch "$ORCH/merged/$wp"; echo "$(date '+%F %T') [automerge] $(echo "$out" | tail -1)" >> "$ORCH/RUNLOG.md"
      break    # one merge per pass, so finished builders get their verify + tester promptly
    else
      touch "$ORCH/mergefail/$wp-$n"; echo "$(date '+%F %T') [automerge] $wp r$n NOT merged: $(echo "$out" | tail -1)" >> "$ORCH/RUNLOG.md"
    fi
  done
  sleep 60
done
