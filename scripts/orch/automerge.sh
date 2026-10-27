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
  for v in "$W"/*-v[0-9]*/; do
    id=$(basename "$v"); wp=${id%-v*}; n=${id##*-v}
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    [ -e "$ORCH/merged/$wp" ] || [ -e "$ORCH/mergefail/$wp-$n" ] && continue
    ls -d "$W/$wp"-v* 2>/dev/null | grep -qE -- "-v$((n+1))$" && continue      # a newer round exists
    [ "$(cat "$v/exit" 2>/dev/null)" = 0 ] || continue
    t="$W/$wp-t$n"; [ -e "$t/exit" ] || continue
    [ "$(verdict "$t/log")" = PASS ] || continue
    git -C "$REPO" branch --list "p26/$wp" | grep -q . || continue
    if out=$("$(dirname "$0")/merge.sh" "$wp" 2>&1); then
      touch "$ORCH/merged/$wp"; echo "$(date '+%F %T') [automerge] $(echo "$out" | tail -1)" >> "$ORCH/RUNLOG.md"
    else
      touch "$ORCH/mergefail/$wp-$n"; echo "$(date '+%F %T') [automerge] $wp r$n NOT merged: $(echo "$out" | tail -1)" >> "$ORCH/RUNLOG.md"
    fi
  done
  sleep 60
done
