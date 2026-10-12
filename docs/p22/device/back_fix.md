# S7-20 fix: Android system back on the Pixel 8 (PRD-2.2 §8)

Branch `g7-fin-back`, 2026-10-12. Pixel 8 `38300DLJH004SD`, Android 17, gesture
navigation (mode 2), targetSdk 36. Debug builds signed with the upload key,
`adb install -r` only (never uninstalled; saved wallet / best kept).

## Cause (two parts)

1. **Predictive back.** With targetSdk 36 the system delivers back to the app
   only through `OnBackInvokedDispatcher`. Flutter's `FlutterActivity`
   registers its callback only after the framework sends
   `SystemNavigator.setFrameworkHandlesBack(true)`, which `WidgetsApp` /
   `Navigator` normally do. The game's root is a bare `GameWidget`, so nothing
   claimed back: KEYCODE_BACK and swipes finished the activity (to
   NexusLauncher) and `SystemBackObserver.didPopRoute` was never reached.
2. **Sticky immersive.** The game hides both system bars
   (`SystemUiMode.manual, overlays: []` = IMMERSIVE_STICKY). In that mode
   Android spends the **first** edge swipe on revealing the transient bars;
   only a second swipe is a back gesture. Measured with fix 1 alone: Settings
   stayed open after one `input swipe 2 1200 400 1200 150` (status bar
   appeared) and closed on the second.

## Fix

- `AndroidManifest.xml`: `android:enableOnBackInvokedCallback="true"` (PRD §8.2
  fallback branch: "set the flag to true and keep the framework registered as
  the back handler all the time").
- `MainActivity.onCreate`: `setFrameworkHandlesBack(true)` before Dart runs
  (covers the early-launch swipe that exited once in QA).
- `SystemBackObserver.install()` (main.dart): adds the observer, claims back
  again from Dart and on every `resumed`. The predictive commit with no
  animating observer goes `commitBackGesture → handlePopRoute → didPopRoute →
  game.handleSystemBack()`; it always returns true. No peek animation (§8.1).
- `FlappySpikesGame.systemBackWanted` / `onSystemBackWanted`: true while a menu
  screen or popup is open over Home (the same gate as `handleSystemBack`).
  While true main.dart shows the navigation bar (transparent, gesture handle
  only, layout unchanged: edge-to-edge) so ONE swipe closes the screen. Home
  and runs stay fully immersive (there back does nothing anyway; an edge
  swipe only reveals the bars, as before).

## Results: harness build (`integration_test/p22_final_device_main.dart`)

Driver `backfix.py` (uses `docs/p22/device/drive.py`; every adb call in
`back_fix/interactions.jsonl`). Each case starts from a fresh launch, does ONE
`input swipe 2 1200 400 1200 150` or ONE `input keyevent KEYCODE_BACK`, then
checks the game state and `dumpsys activity activities` (topResumedActivity =
MainActivity). Raw data: [results.json](back_fix/results.json); states in
`back_fix/states/`, before/after screenshots in `back_fix/shots/`
(`<swipe|key>_<case>_{before,after}.png`).

| Case | Edge swipe | KEYCODE_BACK |
| --- | --- | --- |
| Settings | PASS: closes to Home | PASS |
| Shop | PASS | PASS |
| Skins | PASS | PASS |
| Levels | PASS | PASS |
| Debug panel | PASS | PASS |
| Home popups: NO ADS, LEVEL UP, purchase cancelled, purchase failed, celebration | PASS (each closes) | PASS |
| Nested Shop → Skins | PASS: back to Shop | PASS |
| Settings → Delete confirm | PASS: confirm closes, Settings stays | PASS |
| Home | PASS: nothing, app resumed | PASS |
| Playing | PASS: still playing | PASS |
| Paused | PASS: still paused | PASS |
| Pause → run settings | PASS: unchanged | PASS |
| Results | PASS: unchanged | PASS |

**34 / 34 pass**; MainActivity stayed the top resumed activity in every case.
(The first `results` attempt hit a driver timeout because the run skipped the
revive offer; the driver now accepts either and the rerun passed.)

## Results: normal `lib/main.dart` debug build (left installed)

[normal_main.txt](back_fix/normal_main.txt):

- swipe 0.3 s after `am start -W` (cold launch): app stays resumed;
- Home: two edge swipes + KEYCODE_BACK: nothing happens, app resumed
  (`normal_home_start.png`, `normal_home_after_2swipes_key.png`);
- Settings → one edge swipe → Home (`normal_settings_open.png`,
  `normal_settings_after_edge_swipe.png`; the gesture handle is visible over
  the bottom spike strip while Settings is open);
- Settings → KEYCODE_BACK → Home (`normal_settings_after_keycode_back.png`).

Not re-run here: 3-button navigation (the owner's phone uses gestures; the
3-button back goes through the same `OnBackInvokedCallback`).
