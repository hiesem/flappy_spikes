#!/usr/bin/env bash
# Versus backend tests (ARCH §7.2): build, then run mocha inside the Firebase
# Emulator Suite (auth, firestore, functions) under a demo project, so nothing
# touches the real flappy-spikes-a2b55. Inside an already running
# `firebase emulators:exec` (FIRESTORE_EMULATOR_HOST set) it runs mocha directly.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
npm run --silent build
npx tsc --noEmit -p tsconfig.test.json
if [[ -n "${FIRESTORE_EMULATOR_HOST:-}" ]]; then
  exec npx mocha "$@"
fi
cd "$here/.."
# df4 runs several lanes at once and the emulators use fixed ports (firebase.json): take the shared lock in the
# jail's npm cache so only one emulator suite runs at a time ("Could not start emulator hub, port taken").
if [[ -n "${npm_config_cache:-}" && -d "$npm_config_cache" ]] && command -v flock >/dev/null; then
  exec 9>"$npm_config_cache/.df4-emulators.lock"
  flock -w 2700 9 || echo "test.sh: emulator lock not acquired after 45 min, trying anyway" >&2
fi
exec firebase emulators:exec --project demo-flappy-spikes --only auth,firestore,functions,storage \
  "npm --prefix functions run --silent test:emulated -- $*"
