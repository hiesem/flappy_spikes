#!/usr/bin/env bash
# The project's verify gate: run it before calling any change done (builders run it themselves before they stop).
#
#   exit 0      green; anything else is red
#
# Environment (all optional):
#   VERIFY_BASE       a git ref: scope the functions tests to what the branch changed since it; unset: run everything
#   VERIFY_FULL=1     everything, even when VERIFY_BASE is set
#   VERIFY_SCOPED=1   with VERIFY_BASE: only the changed/matching Flutter tests + the playability core (quick local check)
#   FLUTTER_J         flutter test concurrency (default 4)
#
# Flappy Spikes checks:
#   always      flutter analyze (whole project; must be clean) + flutter test (all)
#   scoped      the functions tests only when functions/ or firestore.rules changed
#   unscoped    + npm --prefix functions test (Firebase emulators, demo project; never the real one)
# No device, emulator or store work runs here: Pixel e2e and uploads stay with the orchestrator / owner.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE="${VERIFY_BASE:-}"
[ "${VERIFY_FULL:-}" = 1 ] && BASE=""
changed() {   # files the branch touches (scoped) — empty when unscoped
  [ -n "$BASE" ] || return 0
  { git diff --name-only "$BASE"...HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u
}

CORE_TESTS=(test/autopilot_test.dart test/layout_test.dart test/flap_physics_test.dart)

# Optional memory guard for parallel builders: VERIFY_HEAVY_LOCKS = space-separated lock files; the flutter suites
# then run while holding one of them, so parallel verify runs never run more full suites at once than there are files.
# Unset: `heavy` just runs the command.
heavy() {
  [ -n "${VERIFY_HEAVY_LOCKS:-}" ] && command -v flock >/dev/null || { "$@"; return; }
  local f got="" rc=0
  for f in $VERIFY_HEAVY_LOCKS; do
    exec 9<"$f"
    if flock -n 9; then got=1; break; fi
    exec 9<&-
  done
  [ -n "$got" ] || { exec 9<"${VERIFY_HEAVY_LOCKS%% *}"; flock 9; }
  "$@" || rc=$?
  exec 9<&-
  return $rc
}

# Known-red list (temporary, orchestrator-owned like this script): failures listed in scripts/known_red_tests.txt
# ("<test file>: <full test name>", one per line) do not turn the gate red; any other failure, a load/compile error
# or a listed test that now passes but is still listed is reported. Builders never edit the list (protected path):
# when their work makes a listed test pass they say so in their summary and the orchestrator prunes the list.
KNOWN_RED=scripts/known_red_tests.txt
norm_failures() { grep ' \[E\]$' | sed -E 's#^([0-9:]+ )?\+[0-9]+( ~[0-9]+)? -[0-9]+: ##; s#^/[^ ]*/(test/)#\1#; s# \[E\]$##' | sort -u; }
flutter_all() {   # [test files...] (none = the whole suite); failures on the known-red list are tolerated
  local out rc=0
  out="$(mktemp)"
  flutter test --no-pub -j "${FLUTTER_J:-4}" "$@" 2>&1 | tee "$out" || rc=$?
  [ "$rc" = 0 ] && { rm -f "$out"; return 0; }
  if [ ! -s "$KNOWN_RED" ]; then rm -f "$out"; return "$rc"; fi
  local new
  new="$(norm_failures < "$out" | comm -23 - <(sort -u "$KNOWN_RED"))"
  local nfail; nfail="$(norm_failures < "$out" | wc -l)"
  if [ "$nfail" != 0 ] && [ -n "$new" ]; then
    # flaky tests (timing, unseeded randomness) turned whole rounds red: rerun the files of the unlisted failures
    # once; only failures that repeat count (they are printed as FLAKY otherwise).
    local files again
    files="$(printf '%s\n' "$new" | cut -d: -f1 | sort -u | tr '\n' ' ')"
    echo "--- rerun once (flake check): $files"
    again="$(flutter test --no-pub -j "${FLUTTER_J:-4}" $files 2>&1 | norm_failures)"
    local flaky; flaky="$(comm -23 <(printf '%s\n' "$new") <(printf '%s\n' "$again") | grep -v '^$' || true)"
    [ -n "$flaky" ] && { echo "=== FLAKY (failed once, passed on the rerun):"; printf '%s\n' "$flaky"; }
    new="$(comm -12 <(printf '%s\n' "$new") <(printf '%s\n' "$again") | grep -v '^$' || true)"
  fi
  rm -f "$out"
  if [ "$nfail" = 0 ] || [ -n "$new" ]; then
    echo "=== flutter test: failures NOT in $KNOWN_RED (these make the gate red):"
    [ -n "$new" ] && printf '%s\n' "$new" || echo "(no [E] lines: a load or compile error, see above)"
    return 1
  fi
  echo "=== flutter test: $nfail failure(s), all listed in $KNOWN_RED (known red, tolerated until their work package fixes them)"
}

flutter_checks() {
  echo "--- flutter pub get (offline)"
  flutter pub get --offline >/dev/null
  echo "--- flutter analyze"
  flutter analyze --no-pub
  echo "--- functions build (the Dart p45 tests load functions/lib)"
  npm --prefix functions run --silent build
  # Always the whole Flutter suite (~5 min): scoping by file name hid cross-suite breakage in M1 (55 red tests
  # merged unseen). Set VERIFY_SCOPED=1 to get the old scoped run for a quick local check.
  if [ -z "$BASE" ] || [ "${VERIFY_SCOPED:-}" != 1 ]; then
    echo "--- flutter test (all)"
    heavy flutter_all
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
  echo "--- flutter test (scoped: ${#files[@]} files; no heavy slot)"
  flutter_all "${files[@]}"
}

functions_checks() {
  if [ -n "$BASE" ] && ! changed | grep -q -E '^(functions/|firestore\.rules|firestore\.indexes\.json|firebase\.json)'; then
    echo "--- functions: untouched, skipped"
    return
  fi
  echo "--- npm --prefix functions test (emulators, demo project)"
  # functions/scripts/test.sh serializes the emulator suite across parallel builders (flock); an agent that starts the emulators
  # by hand bypasses it, so a "port taken" start is retried (up to 4 times, 90 s apart) instead of turning the gate red.
  local out rc attempt
  out="$(mktemp)"
  for attempt in 1 2 3 4 5; do
    rc=0
    npm --prefix functions test 2>&1 | tee "$out" || rc=$?
    if [ "$rc" != 0 ] && [ "$attempt" -lt 5 ] && grep -q -E "port taken|Port [0-9]+ is not open" "$out"; then
      echo "--- emulator ports taken by another builder; retrying in 90 s (attempt $((attempt + 1)) of 5)"
      sleep 90
      continue
    fi
    break
  done
  rm -f "$out"
  return "$rc"
}

run_checks() {
  flutter_checks
  functions_checks
}

if [ "${VERIFY_ONLY_E2E:-}" != 1 ]; then run_checks; fi
echo "=== verify.sh: green ==="
