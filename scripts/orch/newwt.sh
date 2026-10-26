#!/usr/bin/env bash
# newwt.sh <wp> [base] — worktree .worktrees/p26-<wp> on branch p26/<wp> from the last green feat/2.6 head (or base),
# with pub deps and functions/node_modules (symlinked from the main checkout).
set -euo pipefail
. "$(dirname "$0")/env.sh"
wp=$1; base=${2:-$(cat "$ORCH/integ_green_sha" 2>/dev/null || git -C "$REPO" rev-parse feat/2.6)}
wt=$WS/.worktrees/p26-$wp
if [ ! -d "$wt" ]; then
  git -C "$REPO" worktree add -q -b "p26/$wp" "$wt" "$base"
fi
cd "$wt"
[ -e functions/node_modules ] || ln -s "$REPO/functions/node_modules" functions/node_modules
flutter pub get --offline >/dev/null 2>&1 || flutter pub get >/dev/null
echo "$base" > "$ORCH/base-$wp"
echo "worktree $wt on p26/$wp from $(git rev-parse --short "$base")"
