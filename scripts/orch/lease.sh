#!/usr/bin/env bash
# lease.sh take <owner> | show | age-min — who orchestrates now (session / headless-<pid>) and since when.
. "$(dirname "$0")/env.sh"
f=$ORCH/lease
case "${1:-show}" in
  take) echo "${2:-session} $(date +%s)" > "$f.tmp" && mv "$f.tmp" "$f" ;;
  show) [ -f "$f" ] && { read -r o t < "$f"; echo "$o $(( ($(date +%s)-t)/60 ))m ago"; } || echo "none" ;;
  age-min) [ -f "$f" ] && { read -r o t < "$f"; echo $(( ($(date +%s)-t)/60 )); } || echo 0 ;;   # no lease yet = nobody to take over from
esac
