# Notes for every builder and tester (Flappy Spikes 2.6, df4)

**Toolchain in the jail:** `flutter` / `dart` are on PATH (a writable copy of Flutter 3.47.6), `PUB_CACHE` is set and
already filled; `node` / `npm` / `firebase` are on PATH. Dependencies are installed before your turn: use
`flutter pub get --offline` only if you must, never add a package without the issue saying so. Run
`bash scripts/verify.sh` before you stop (it runs `flutter analyze`, the functions build, the scoped `flutter test`
and, when `functions/` changed, `npm --prefix functions test` in the Firebase emulators under a demo project).

**Never:** `adb`, devices or emulators, `firebase deploy`, gcloud, Play Console / App Store Connect, real Firebase
project calls, publishing anything. Never touch `android/upload-keystore.jks`, `android/app/key.properties` or any
secret file. Don't edit `docs/p26/` (PRD + approved designs) — report a conflict instead.

**Spec:** `docs/p26/PRD-2.6-fun-progression.md` (binding) with the approved designs in `docs/p26/design/` (see
`docs/p26/README.md` for the path map). Gameplay changes follow `SPEC.md` or add a DEVIATION note there.
Module map: `docs/gameplay-v2/ARCH.md`.

**Invariants that break things silently (from the workspace CLAUDE.md):**
- `maxTranslation = 10000` in the `FlappySpikesGame` constructor — never remove it.
- Shared parts have one master each (ring, burst, banner, coin popup, trail): reuse, never draw a second variant.
- Never call `GameAuth.signIn()` at launch on Android; never use `GameAuth.isSignedIn` (use the `GameAuth.player`
  subscription).
- SFX only through the preloaded low-latency `AudioPool`s (`Sfx` / `SfxLoop`); never bare `FlameAudio.play`. New or
  changed audio → `python3 -I tool/gen_sound_durations.py`.
- Results-page title/labels use `Config.uiAccent` (#FF4FB7), not the stage tint. `music_note.png` stays #EC008C on
  #FCD9EE.
- UI geometry lives in `lib/game/config.dart` (`*PositionFor(centerY)` helpers); runtime layout reads
  `game.viewHeight`, never `Config.worldHeight`. New run elements go through `world.addRun(...)` (tablets).
- Every `GameServices` / plugin call is try/caught; the default services instance is a no-op in tests.
- New storage keys: append at the END of `kObfStrings` in `tool/gen_obf_strings.dart`, regenerate
  `obf_strings.g.dart`, add them to `tool/anchor_strings.txt` (PRD WP-J notes).
- Both platforms (PRD O27): every feature compiles and works on Android and iOS; store-compliance rules in PRD §7.5.

**Tests:** use `test/helpers.dart` (`createRunTestGame`, `startRun`, `flyRun`, `flushAndMount`; always
`soundEnabled: false`). Add the tests the PRD names for your work package. `test/autopilot_test.dart` is the
playability gate and must stay green.
