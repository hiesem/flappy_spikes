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
exec firebase emulators:exec --project demo-flappy-spikes --only auth,firestore,functions,storage \
  "npm --prefix functions run --silent test:emulated -- $*"
