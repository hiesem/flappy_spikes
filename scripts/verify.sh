#!/usr/bin/env bash
# The verify contract (DuoFoundry v4). df4 runs this script as the GATE after every build round, inside the same
# bubblewrap jail as the builders (so "green for the builder" == "green for the gate"), and once per milestone
# unscoped on the merged base (the milestone gate). Builders run it themselves before they stop.
#
#   exit 0      green; anything else is red (the tester is not called; the tail goes to the next builder)
#   jail        $HOME is an empty tmpfs (only the toolchain is visible), no docker/podman socket, .git read-only
#
# Environment set by df4:
#   DF4_VERIFY_BASE   set: scope to what the branch changed; unset: run everything (the milestone gate)
#   DF4_E2E_FULL=1    (verify:full repair issues and the gate) everything
#
# Flappy Spikes checks:
#   always      flutter analyze (whole project; must be clean)
#   scoped      the changed/added test files + every test under a test/ folder whose name matches a changed lib/
#               file or folder + the playability core (autopilot, layout, flap physics); the functions tests only
#               when functions/ or firestore.rules changed
#   unscoped    flutter test (all) + npm --prefix functions test (Firebase emulators, demo project; never the real one)
# No device, emulator or store work runs here: Pixel e2e and uploads stay with the orchestrator / owner.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE="${DF4_VERIFY_BASE:-}"
[ "${DF4_E2E_FULL:-}" = 1 ] && BASE=""
changed() {   # files the branch touches (scoped) — empty when unscoped
  [ -n "$BASE" ] || return 0
  { git diff --name-only "$BASE"...HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u
}

CORE_TESTS=(test/autopilot_test.dart test/layout_test.dart test/flap_physics_test.dart)

flutter_checks() {
  echo "--- flutter pub get (offline)"
  flutter pub get --offline >/dev/null
  echo "--- flutter analyze"
  flutter analyze --no-pub
  echo "--- functions build (the Dart p45 tests load functions/lib)"
  npm --prefix functions run --silent build
  if [ -z "$BASE" ]; then
    echo "--- flutter test (all)"
    flutter test --no-pub
    return
  fi
  local files=() f stem
  while IFS= read -r f; do
    case "$f" in
      test/*_test.dart) [ -f "$f" ] && files+=("$f") ;;
      lib/*.dart)
        stem="$(basename "$f" .dart)"
        while IFS= read -r t; do files+=("$t"); done < <(find test -name "${stem}*_test.dart" 2>/dev/null)
        ;;
    esac
  done < <(changed)
  files+=("${CORE_TESTS[@]}")
  mapfile -t files < <(printf '%s\n' "${files[@]}" | sort -u)
  echo "--- flutter test (scoped: ${#files[@]} files)"
  flutter test --no-pub "${files[@]}"
}

functions_checks() {
  if [ -n "$BASE" ] && ! changed | grep -q -E '^(functions/|firestore\.rules|firestore\.indexes\.json|firebase\.json)'; then
    echo "--- functions: untouched, skipped"
    return
  fi
  echo "--- npm --prefix functions test (emulators, demo project)"
  npm --prefix functions test
}

run_checks() {
  flutter_checks
  functions_checks
}

if [ "${DF4_VERIFY_ONLY_E2E:-}" != 1 ]; then run_checks; fi
echo "=== verify.sh: green ==="
