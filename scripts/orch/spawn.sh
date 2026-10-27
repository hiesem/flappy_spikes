#!/usr/bin/env bash
# spawn.sh <worker-id> <cap-minutes> <workdir> -- <command...>
# Starts a builder/tester DETACHED (survives the Claude session): $W/<id>/{pid,cmd,cwd,started,cap,log,exit}.
set -euo pipefail
. "$(dirname "$0")/env.sh"
id=$1 cap=$2 cwd=$3; shift 3; [ "${1:-}" = "--" ] && shift
d=$W/$id
if [ -f "$d/pid" ] && [ ! -f "$d/exit" ] && kill -0 "$(cat "$d/pid")" 2>/dev/null; then
  echo "spawn: $id is still running (pid $(cat "$d/pid"))" >&2; exit 2
fi
[[ "$cap" =~ ^[0-9]+$ ]] || { echo "spawn: cap must be minutes" >&2; exit 2; }
rm -rf "$d"; mkdir -p "$d"
printf '%q ' "$@" > "$d/cmd"; echo "$cwd" > "$d/cwd"; echo "$cap" > "$d/cap"; date +%s > "$d/started"
[[ "$cap" =~ ^[0-9]+$ ]] || { echo "spawn: cap must be minutes" >&2; exit 2; }
[ -d "$cwd" ] || { echo "spawn: no dir $cwd" >&2; exit 2; }
# Under a systemd unit (the headless tick) the unit's cgroup is killed when the pass ends (KillMode=control-group):
# run the worker in its own transient scope so it survives the pass (incident 2026-10-27 01:36, 8 workers lost).
scope=(); if [ -n "${INVOCATION_ID:-}" ] && command -v systemd-run >/dev/null; then
  scope=(systemd-run --user --scope --quiet --collect --expand-environment=no --unit="orchw-${id//[^A-Za-z0-9_-]/_}-$(date +%s)" --)
fi
( cd "$cwd" && exec "${scope[@]}" setsid nohup bash -c 'echo $$ > "$0/pid"; "$@" > "$0/log" 2>&1 < /dev/null; echo $? > "$0/exit"' "$d" "$@" ) &
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$d/pid" ] && break; sleep 0.2; done
echo "spawned $id pid $(cat "$d/pid" 2>/dev/null || echo ?) cap ${cap}m in $cwd"
