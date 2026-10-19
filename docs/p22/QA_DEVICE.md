# PRD-2.2 final Pixel 8 QA

> Note: the raw device captures under `docs/p22/device/` (recordings, screenshots, UI/state dumps, logcat and console logs, interactions.jsonl) were removed 2026-10-20 (run 17), see git history. File names below refer to that history.

2026-10-12. Tester branch: g7-qadev. Production code under test: a92835f.
Pixel 8 <PIXEL8_SERIAL>, Android 17, USB hub, gesture navigation (mode 2).
No production, iOS, store, backend deployment or push changes.

**Release gates: e2e PASS; analyze / unit / backend PASS; §33 soak FAIL;
§8 native back FAIL.** Existing QA P3 findings S7-14–16 remain in this
checkout: its head is the P3 merge, not a later P3 fix merge.

## Gate results

| Gate | Result | Evidence |
| --- | --- | --- |
| Device e2e (mode, FREE FLY, live VERSUS, journey, elements, six rides, reminders, upload/delete) | PASS, **8/8**, final full run | e2e.txt (removed 2026-10-20 (run 17), see git history), 85-shot manifest (removed 2026-10-20 (run 17), see git history), PNG folder (removed 2026-10-20 (run 17), see git history) |
| flutter analyze | PASS, no issues | analyze.txt (removed 2026-10-20 (run 17), see git history) |
| Full flutter test --concurrency=4 | PASS, **2465 passed /6 skipped** | full_test.txt (removed 2026-10-20 (run 17), see git history) |
| Focused music /rumble /revive /moving physics | PASS, 19 | focused.txt (removed 2026-10-20 (run 17), see git history) |
| Focused captureShot visual suites (mode /portal /fire /post-run) | PASS, 45 | focused_visual.txt (removed 2026-10-20 (run 17), see git history) |
| npm --prefix functions test | PASS, **121**; build completed first | functions_test.txt (removed 2026-10-20 (run 17), see git history), setup (removed 2026-10-20 (run 17), see git history) |
| §33 final soak | **FAIL**, 20 games, 3/5 criteria fail | [PERF.md §2d](PERF.md), [CSV](device/soak/soak.csv), console (removed 2026-10-20 (run 17), see git history) |
| Native Android back | **FAIL**, S7-20 | gesture results (removed 2026-10-20 (run 17), see git history), finish log (removed 2026-10-20 (run 17), see git history), before/after PNGs (removed 2026-10-20 (run 17), see git history) |
| Final debug install /settings restoration | PASS: normal lib/main.dart debug APK, data retained, brightness 1 /3, stay-awake 7; copied keys deleted | build (removed 2026-10-20 (run 17), see git history), install (removed 2026-10-20 (run 17), see git history), restoration (removed 2026-10-20 (run 17), see git history), final Home (removed 2026-10-20 (run 17), see git history) |

The six skips include the three P3 finding regressions in
`test/p22/s12_s18_s20_s21_qa_p3_test.dart`. Green automated gates
do not certify S7-14–16 as fixed. No existing test assertion was removed. The only suite changes are in the
device e2e fixture; the manual native entry point is new. No production code
was changed or fixed.

## Device pass/fail matrix

Paths below are inside device/. Every setup operation, adb tap/swipe, snapshot
and close-button tap is logged in interactions.jsonl (removed 2026-10-20 (run 17), see git history).
[commands.md](device/commands.md) records build/test commands and correction history.
Native render/audio/rumble/focus/Google test ads use
[integration_test/p22_final_device_main.dart](../../integration_test/p22_final_device_main.dart).
Its in-memory prefs and fake IAP avoid touching saved game state or purchases.
Its counters were not used for the profile soak.

| PRD /item | Result and practical limit | Evidence |
| --- | --- | --- |
| §8 Home | PASS for later real edge swipes: stays foreground; early launch swipe exited once | shots/back_home_before.png, back_home_after.png; initial home_back_after.png |
| §8 Settings, Shop, Skins, Levels | **FAIL:** edge swipe leaves screen open | states/back_{settings,shop,skins,levels}_{before,after}.json / corresponding shots |
| §8 Home popups: NO ADS, LEVEL UP, purchase cancelled/failed, celebration | **FAIL:** popup remains open | shots/back_{no_ads,level_up,purchase_cancelled,purchase_failed,celebration}_{before,after}.png |
| §8 Debug | **FAIL:** panel remains open | shots/back_debug_before.png /after.png |
| §8 nested Shop → Skins and Settings → Delete confirmation | **FAIL:** top screen/popup remains open | shots/back_nested_before.png /after.png; back_delete_confirm_before.png /after.png |
| §8 playing, pause, run settings, revive, bonus, results | PASS for edge swipes: no state change /no app exit | gesture_results.json; gesture_finish.txt; shots/back_{playing,paused,run_settings,revive,bonus,results}_*.png |
| §8 KEYCODE_BACK on Settings | **FAIL:** sends activity to launcher | shots/key_back_settings_before.png /after.png; states/key_back_settings_after_activity.txt |
| §9 fresh-default music | PASS: no musicVolume key, storage/applied **0.25** | native_initial_state.json, native.txt ready line, shots/settings_music_25.png |
| §28 music returns at run start while flapping | PASS with skipped-music setup followed by the real native media check and repeated adb taps: skipped=false /music=true | states/music_skipped_setup.json, music_return_while_flapping.json; recordings/flapping_music_return.mp4 |
| §10 rim knock /perfect shake | PASS by motor log (not a claimed human tactile opinion): **15 ms /0.35**, **80 ms /1.00**; HAL finish durations about 89–93 /160 ms | rumble_knock.txt, rumble_shake.txt; shots/egg_after_real_rim.png /perfect_native_rumble.png |
| §30 moving rings | PASS: all six rail /swing /horizontal /diagonal /orbit /rock clean passes counted by real physics; forced at hoop 60, bot /god setup | moving_types.json; moving_clean_pass_evidence.json; moving_late_console.txt; shots/moving_*; recordings/moving_*.mp4 |
| §2 mode button /approved mock | PASS: right aligned, side swap, VERSUS tag /FREE FLY colours; e2e retains choice /solo flow | shots/home_versus.png, home_free_fly.png; refs/screen_mode_toggle3.png; e2e p22_* PNGs |
| §7.5 test banner at Pixel height | PASS: **661.33 pt visible**, **681.33 logical**, **24 pt bottom inset**, 18 pt teeth +6 pt base | states/run_banner_661.json, shots/run_banner_661.png; bonus_palette.json; approved run_banner/play_663.png |
| §7.6 interstitial after NEXT /guards | PASS: physical NEXT shows TEST interstitial; close × returns full-height Home, music recovers. Native firstRuns /noAds /notLoaded /background /rewardedThisRun /cooldown guards observed; cooldown NEXT skips | interstitial_console.txt; states/interstitial_*.json; recordings/interstitial_after_next.mp4; soak_ad_watch.txt; states/bonus_ad_suspended.json |
| §7.8 bonus feather ×3 after revive ad | PASS: real TEST revive ad →3 pops →offer →real TEST ad →3 refilled →3 more pops →results | rewarded_bonus_console.txt, bonus_refill_console.txt; shots/bonus_feather_x3_offer.png /bonus_refilled_three.png /bonus_six_pops.png; recordings/bonus_rewarded.mp4 |
| §7.15 /§24 revive waits /buttons only | PASS: **205+ s** offer remains; real empty-space taps inert; heart opens rewarded /No thanks declines. No tap reaches a flap while offering | states/revive_recovery_over_30s.json, revive_empty_taps_correct_grid.json; shots/revive_*; recordings/revive_heart_test_ad.mp4 |
| §13.2 big scores | PASS: **99,999 /999,999 /9,999,999** fit the 183 pt circle. Injected render stress, not forged cloud runs | shots/score_99999.png /score_999999.png /score_9999999.png; corresponding state JSON |
| §14 count-up ticks | PASS: native sk_tick starts/stops during actual results/CLAIM/bonus counts; one-stream exact count covered locally | native.txt, profile soak logcat; s14_results_ticks_test.dart in full suite |
| §29 streak banners | PASS for native ×3 /×5 /×7 /×11 captures, rotating name/colour; all 50 /beyond-50 /text-fit covered locally | shots/fire_*.png, refs/screen_streak_names.png, full suite |
| §12 banners behind gameplay | Main band PASS visually behind bird/hoops; existing **S7-14–16 remain FAIL** | shots/banner_behind_bird.png; puzzle_sticker_after_death.png; QA_P3.md |
| §16 /§17 comet zigzag /landing | PASS: native zigzag, automatic return flap, landing scale **0.5 →1.0**; easing capture is 0.821 (its filename says half-speed) | shots/comet_*.png; states/comet_auto_flap.json /comet_landing_full_speed.json; recordings/comet_zigzag_landing.mp4; rides_console.txt |
| §18 all six rides | PASS: all six native scenes /way-back /automatic flap; first ring about **1.96–2.01 s**; all theme cues reach native playback | recordings/ride_*.mp4, shots/ride_*; ride_native_cues.json; ride_native_audio_starts.json; native.txt; e2e sweep_ride_* PNGs |
| §19 opening variety /§27 exclusivity | PASS in 500-seed local statistical/contract tests; native different-seed sequences /single piggy activity observed | full_test.txt; native.txt; physics_console.txt; shots/piggy_coins_16pt.png |
| §20 bird colours | PASS visually classic bird on grey /cyan; gold remains an effect. Accessory-stage pixel checks pass locally | shots/bird_colours_stage0.png /bird_colours_cyan.png; full suite |
| §21 fire ×3 /×5 /×7 | PASS native renderer: fire/trail grow, body remains in front, no outline; tiers use existing debugPass setup | shots/fire_3.png /fire_5.png /fire_7.png; refs/screen_fire_choice2.png |
| §22 long cues | PASS native timing: soak perfect_3 12× **2400–2411 ms**, perfect_2 20×1500–1506, perfect_1 59×1000–1017. No 0.6 s stop | PERF.md §2d; native.txt perfect_3 native-stop /sfx-stop; recordings/flapping_music_return.mp4 |
| §23 egg breaks on rim | PASS: real physics RimTouched after placement setup, egg gone /shell fall /egg_crack; no injected rim event used | physics_console.txt; shots/egg_before_rim.png /egg_after_real_rim.png; recordings/egg_rim_break.mp4 |
| §25 special sizes | PASS observed shrinking saw/FEVER at hoop 70; exact size /decor transforms /portal exception covered locally | shots/saw_hoop70.png /fever_hoop70.png; full suite |
| §26 piggy coins | PASS native large coins /fly-in; **16 pt /14 pt catch** constants and bounds verified locally | shots/piggy_coins_16pt.png; recordings/piggy_coins.mp4; full suite |
| §31 grey post-run /rays | PASS grey native pages/base **#F1F1F1 /#828282**, content above strips; extended rays verified in e2e CLAIM /captureShot suites. The extra forced native results frame has no pending level-up and does not prove rays | bonus_palette.json; shots/bonus_*.png /results_grey_rays.png; e2e_release/journey_09_claim.png; full suite |
| §28 full-screen audio | PASS functional: suspended=true /music=false under real TEST ads; resumes music=true /suspended=false after close; no game one-shot native starts during the ad hold | rewarded_suspended_state.json, states/bonus_ad_suspended.json /bonus_refilled_three.json; native.txt |

Visual comparisons use the exact named approved HTMLs /PNGs. Their captures
are under refs/; production captureShot files remain under build/. Random
particles, animation phases, scores and mock annotations are not pixel-identical
targets. Media volume was not changed. Native timing/volume/start/stop evidence
does not claim an independent auditory recording of every cue. Calls, Spotify,
3-button navigation and a Play-installed release are not performed in this WP.

## Findings (new numbering continues after S7-17)

### S7-18 — minor — debug link failures expose an OAuth access token

- PRD: §4 diagnostics; the preserved optional Play Games ↔Firebase link.
- Repro: run the registered-token device e2e; automatic existing-player link
  fails and FirebaseAuthException's message contains a redirect query token.
- Expected: a safe diagnostic, with credentials stripped.
- Actual: lib/services/versus_service.dart:359 prints the full exception:
  versus: link failed: [firebase_auth/unknown]
  http://localhost?access_token=&lt;REDACTED&gt;&providerId=playgames.google.com.
- Evidence: device/e2e_first.txt, e2e_second.txt, e2e.txt. **All saved token
  values are redacted** with device/redact.py. The print is kDebugMode-gated,
  so this finding does not claim release builds print it.
- Automatic linking itself was refused; anonymous live matching/upload worked.
  No interactive sign-in or account configuration change was attempted.

### S7-19 — major — merged-build §33.6 release soak fails three criteria

- PRD: §33.6, release gate.
- Repro: the recorded repeat command, 20 profile FS_SOAK games on the same
  hub/phone/brightness as the baseline, including bonuses /CLAIM /NEXT.
- Expected: PSS ≤110% of game 2; flat native players from game 2; final p90 /
  slow% unchanged from game 1 and no worse than 2.1.
- Actual: **445,974 →509,180 KB (+14.17%)**, over **490,571 KB** limit;
  **76 →82 →94 →96** live players; p90 **12.79 →14.73 ms (+15.17%)**,
  versus baseline game 20 **13.72 ms (+7.36%)**; slow% **11.7 →20.0%**.
- CPU /thermal pass: 56.5% vs baseline 84.4%, 0 polls and thermal 0.
- Evidence: PERF.md §2d and all five rows /raw dumps /game-10 trace.
- The voice difference tracks owned lazy pools, with 44 pool evictions /
  123 native disposals. **No old unowned-player leak is observed**. Do not
  equate bounded pool warming with flat aggregate count.
- Final merged ads are included; closing test interstitials is recorded.
  No causal diagnosis or statistical significance is invented from one run.
- **Fix round R1-b (`g7-fin-soak`, PERF.md §2e):** session sound set pinned,
  run-scoped pools disposed at the Home arrival. Re-soak `final-fix`: players
  **93 at every hold** (PASS), PSS 454.9 → 499.9 MB **+9.9 %** (PASS, narrow),
  Home CPU 49–55 % / 0 polls and thermal 0 (PASS); run p90 12.81 → 14.74 ms,
  slow 11.7 → 25.9 % (**FAIL**). Cause: the §7.5 banner platform view redraws
  on the main (= Dart UI) thread, ≈ 7 ms per redraw in 0.6 s bursts every 5 s;
  a 10-game soak without the banner is flat (p90 11.4–13.3 ms, slow 3.5–13.6 %).
  Open for the owner (banner decision).

### S7-20 — major — Android system back bypasses the menu close path

- PRD: §8.1 /§8.2 /§8.4.
- Repro: real left-edge adb swipe 2 1200 400 1200 150 on each menu/popup;
  KEYCODE_BACK on Settings. Gesture navigation mode 2, Android 17.
- Expected: topmost menu/popup closes; Home/runs remain foreground; never
  finish the activity.
- Actual: most menu/popup edge swipes leave them open. KEYCODE_BACK sends
  Settings to NexusLauncher; an early startup swipe also exited. Later Home
  and in-run swipes stay foreground, so inert run cases are not misreported
  as menu-close passes.
- Evidence: gesture_results.json, gesture_finish.txt, states/*_activity.txt,
  shots/back_* /key_back_settings_*, recordings/back_home.mp4 /back_shop.mp4.
- The QA entry uses the production SystemBackObserver and matching shell.
  Confirmed again in the **normal lib/main.dart debug build**: Settings remains
  after the exact edge swipe; KEYCODE_BACK exits to NexusLauncher. Evidence:
  normal_back_console.txt, normal_main_settings_{edge,key}_activity.txt,
  shots/normal_main_settings_*.png, recordings/normal_main_back.mp4.
  No registration workaround is installed.

## Test-only changes /Calls

- release_e2e_test.dart: §11 clean passes can reset the old forced tier-3
  frame probe, so the effects-only capture keeps its requested tier active.
  This changes the fixture in `P6 §3.12 rides`; physical pass assertions are
  retained elsewhere.
- Live-match setup now dismisses the synthetic best=60 LEVEL UP popup after
  asynchronous prefetch, before START; the failed screenshot proves it was
  an input precondition, not a matcher failure (`P22 §2–§4 live VERSUS match`).
- The destructive upload/delete probe uses a separate named Firebase app,
  checks it is unlinked and awaits that app's Auth /App Check tokens. It never
  deletes the default identity (`P6 §3.13 versus live round trip`). First two full runs and focused retries are
  preserved; final full run is 8/8.
- --no-uninstall is required by this Flutter for device tests. The exact
  supplied command's first run auto-uninstalled its test app on exit; I missed
  that default initially. The app was **absent before QA**, so no pre-existing
  local game data was available/lost. Every subsequent device test kept the
  install; every explicit install used -r. Never pm clear.
- Native manual checks use in-memory game prefs /fake IAP /no cloud, real
  test ad loaders with scripted consent (no owner UMP choice change). Forced
  render stress is distinguished from real physics /motor events.
- Literal §33 criteria are reported as measured, with no invented tolerance.
- SPEC /ARCH unchanged: no product behavior or module contract changed.
  No Config knob or sound asset added. Store screenshot outputs not committed.

## Handoff /remaining limits

S7-18–20 and prior S7-14–16 need the integration/fix owner. This tester
does not fix production code or publish anything. Version is still 2.1.0+8;
release work must set 2.2.0+9. The normal lib/main.dart debug build is left
installed on Home with the registered App Check token, without FS_E2E /FS_SOAK.
Its saved wallet /look /best remain visible after reinstall. Brightness mode 1,
value 3 and stay-awake 7 match the originals; gesture navigation remains 2.
Both copied signing files were deleted. See device/restoration.txt and the
final Home screenshot. Perfetto trace stays local under the existing ignore
rule; all other recorded evidence is committed.

The native harness initially read an obsolete ride stub and inferred dynamic
for an empty ring list. These QA-only logging errors were corrected before
the final ride/motion sweeps; raw failed attempts remain in the evidence.
The first interstitial background probe also needed explicit game RESUME
after returning from Home; the successful retry is interstitial_console.txt.
