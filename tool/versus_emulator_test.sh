#!/usr/bin/env bash
# WP-5b opt-in live check (PRD-2 §3.13, ARCH §7.2): the Dart client's data
# contract against the Firebase Emulator Suite (auth, firestore, functions)
# on the demo-flappy-spikes project — nothing touches flappy-spikes-a2b55.
# Needs functions/node_modules (`npm --prefix functions ci`), Java ≥ 11 and
# flutter on PATH. Usage: tool/versus_emulator_test.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
npm --prefix functions run --silent build
exec firebase emulators:exec --project demo-flappy-spikes --only auth,firestore,functions \
  "FS_EMULATOR_TESTS=1 flutter test test/versus/s3_13_emulator_test.dart"
