# Notes for every builder and tester (Flappy Spikes 2.6)

**Toolchain:** see the workspace CLAUDE.md (`flutter` / `dart` / `node` / `npm` / `firebase` on PATH). Dependencies are installed: use
`flutter pub get --offline` only if you must, never add a package without the issue saying so. Run
`bash scripts/verify.sh` before you stop (it runs `flutter analyze`, the functions build, the whole `flutter test`
and, when `functions/` changed, `npm --prefix functions test` in the Firebase emulators under a demo project).
Run the functions tests ONLY as `npm --prefix functions test [-- test/<file>.test.ts]`: never start
`firebase emulators:exec` / `emulators:start` yourself (parallel builders share the fixed emulator ports; the npm script
waits for its turn, a hand-started suite breaks their runs).
Memory is shared by parallel builders (22 GB): run `flutter test` with `-j 4` at most, and prefer single files while you work.

**Never:** `adb`, devices or emulators, `firebase deploy`, gcloud, Play Console / App Store Connect, real Firebase
project calls, publishing anything. Never touch `android/upload-keystore.jks`, `android/app/key.properties` or any
secret file. Don't edit `docs/p26/` (PRD + approved designs; the one exception is `docs/p26/SHARED_ELEMENTS.md`, kept
current by the issues that add or change a master) — report a conflict instead.

**Spec:** `docs/p26/PRD-2.6-fun-progression.md` (binding) with the approved designs in `docs/p26/design/` (see
`docs/p26/README.md` for the path map). Gameplay changes follow `SPEC.md` or add a DEVIATION note there.
Module map: `docs/gameplay-v2/ARCH.md`.

**Reuse, don't remake (owner, PRD O97–O100 — binding):** when a 2.6 design shows an element the game already has
(rays, boxes, confetti, coin fly / counter, popup frame, buttons, tags, banners, stickers, sparkles, emblems, avatars,
card painters …), use the existing in-game element and its code; the design page only gives layout, size, colour and
timing. A new look is only a parameter of the same master, never a second drawing. Rays: reuse one of the 4 existing
ray versions as it is (O98). Boxes: everything draws from the one box master (O99). The list of masters is
`docs/p26/SHARED_ELEMENTS.md` (written by the first M0 issue): check it before drawing anything. **Testers: fail any
second drawing of a listed element** (blocker), and any new shared-looking element that is not added to the list.

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

**Known-red tests (temporary, M1F):** M1 merged with 55 failing tests. They are listed in
`scripts/known_red_tests.txt`; `scripts/verify.sh` runs the whole Flutter suite and stays green while every failure is
on that list, red on any other failure. Never edit that list (protected). When your work makes listed tests pass,
name them in your summary. A test's expectation may only change when PRD 2.6 changed the rule it checks (cite the
PRD section in the test); otherwise fix the code.
