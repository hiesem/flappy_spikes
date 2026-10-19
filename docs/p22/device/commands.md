# Final device QA commands

> Note: the raw device captures under `docs/p22/device/` (recordings, screenshots, UI/state dumps, logcat and console logs, interactions.jsonl) were removed 2026-10-20 (run 17), see git history. File names below refer to that history.

All shell sessions use PATH / ANDROID_HOME / JAVA_HOME from AGENTS.md.
Device commands always target Pixel 8 `38300DLJH004SD`.

Initial revision: `a92835f` (branch `g7-qadev`). `flutter pub get` passed.
Initial `pm list packages flappy` was empty; dumpsys reported app absent.
Copied the two gitignored signing files from the active project as instructed.
Original stay-awake = 7; original brightness/mode are in `original_*.txt`.
Set `settings put global stay_on_while_plugged_in 7` during QA.

```bash
flutter test integration_test/release_e2e_test.dart -d 38300DLJH004SD \
  --dart-define=FS_E2E=true --dart-define=FS_LIVE_VERSUS=true \
  --dart-define=FS_APPCHECK_DEBUG_TOKEN=<registered debug token> \
  --reporter expanded > docs/p22/device/e2e.txt 2>&1
npm --prefix functions ci
npm --prefix functions run build
```

The final e2e upload/delete probe uses named Firebase app `qa-device-round-trip`,
following the already adopted `seed` app pattern. The production app and live
match test still use the normal startup path. See the test-only diff.

Further commands and every tap/swipe/capture are appended here or recorded by
`drive.py` in `interactions.jsonl` with timestamp, argv and command outcome.

First e2e: 6 passed, 2 failed (tier-3 probe and VS intro). This Flutter defaults
`flutter test -d …` to `--uninstall` on exit. The first run therefore removed its
test install; no app existed before this run. All following integration-test
commands explicitly add `--no-uninstall` to honor the owner's data constraint.
The raw first log was sanitized with `redact.py` before saving as `e2e_first.txt`.
The reminder permission prompt was accepted by `input tap 540 1370` during e2e.

Rerun is the command above plus `--no-uninstall`. Its effects-only tier-3 frame
probe maintains the forced tier during capture because §11 clean passes now
reset it. No pass/miss, scoring, bot, or production code is changed.

Second full e2e: 6 passed, 2 failed. All six portal rides passed. The live-match
capture `live_home_second.png` proves a pending LEVEL UP modal blocked START
(the synthetic best=60 causes it); the test now settles Home after prefetch.
The isolated round-trip's first transaction was refused. Its named Auth/App
Check token handshake is now explicitly awaited. The focused live retry passed
both tests, replayed 13 v2 pool runs, and deleted only its anonymous QA account.

```bash
flutter test integration_test/release_e2e_test.dart -d 38300DLJH004SD \
  --no-uninstall --dart-define=FS_E2E=true --dart-define=FS_LIVE_VERSUS=true \
  --dart-define=FS_APPCHECK_DEBUG_TOKEN=<registered debug token> \
  --plain-name live --reporter expanded
```
The final full rerun uses the same flags without `--plain-name`.

Final full e2e: **8 passed**. Its 85 screenshot calls and hashes are recorded in
`e2e_manifest.json`; generated PNGs were pulled from `code_cache/e2e_release`
(the legacy printed hint says `cache`, which is wrong on this phone).

```bash
python3 -I tool/soak.py --label final-qa > docs/p22/device/soak_console.txt 2>&1
```
The script itself builds the upload-key-signed profile APK with `FS_SOAK=true`,
installs with `adb -s 38300DLJH004SD install -r`, fixes brightness at 128, and
restores the saved brightness/mode. `device/soak` links to `../perf/final-qa`.
Trace data remains local under the existing gitignore rule.

Soak completed 20 games / 1,215.4 s of driver time. Script restored brightness
mode 1 and value 3. The merged §7 path shows Google test interstitials; the
read-only-window watcher closes only accessible × / Close ad buttons. It does
not touch consent, billing, sign-in or ad content. Seven close-button taps
were recorded (end cards can need another close). See `soak_ad_watch.txt`,
`interactions.jsonl` and `shots/soak_test_ad_*.png`.

```bash
flutter build apk --debug -t integration_test/p22_final_device_main.dart \
  --dart-define=FS_APPCHECK_DEBUG_TOKEN=<registered debug token>
```
This harness uses the actual game, back observer, native sound/rumble/focus and
Google test ad loaders; mock game prefs, FakeIapService, no cloud or reminders.
Its setup commands identify injected debug passes/scores vs real physics events.
Its counters are not used for the profile soak gate.

The native passes, rides, real-rim egg contact, gesture matrix and test-ad
follow-up use `gameplay.py`, `gestures.py`, `physics.py`, `rides.py`,
`moving_late.py` and `interstitial.py`; each command/input is timestamped in
`interactions.jsonl`. Failed setup attempts remain beside successful logs.
`mock_refs.cjs` captures the named approved mocks in headless Chromium; it
does not use the owner's browser profile.

```bash
flutter analyze --no-pub
flutter test --no-pub --concurrency=4 --reporter expanded
npm --prefix functions test
flutter build apk --debug \
  --dart-define=FS_APPCHECK_DEBUG_TOKEN=<registered debug token>
adb -s 38300DLJH004SD install -r build/app/outputs/flutter-apk/app-debug.apk
```

The final build uses the default `lib/main.dart`, without FS_E2E /FS_SOAK or
the QA entry point. APK SHA256 is `final_apk.sha256`; package flags confirm
DEBUGGABLE in `final_debug_package.txt`. The normal-entry confirmation uses
the exact physical left-edge swipe, then KEYCODE_BACK, on Settings. The edge
does not close Settings; KEYCODE_BACK resumes NexusLauncher. No back-handler
registration workaround was added. Reopened normal app on Home afterwards.

Restored all three original settings through explicit named-device adb
commands: stay-awake 7, brightness mode 1, brightness value 3. Navigation
remains gesture mode 2. See `restoration.txt` and final Home screenshot.
Removed only QA control files from code_cache; no app data clear or explicit
uninstall. Deleted the two copied signing files at the end. Stopped the host
native logcat reader and redacted/scanned text evidence for OAuth secrets.
No credentials or regenerated store screenshots are staged.
