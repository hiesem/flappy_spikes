# PRD-2.2 QA P3

Date: 2026-10-12. Branch: `g7-qa3`. Reviewed implementation: `f83548ee`
(all sections plus P1/P2 fixes). Scope: §12, §20, §31, P2 findings
S7-07…13, and the integration/coverage audit of §1 items 1–30.

**Three findings: 3 minor, 0 major, 0 blockers.** All three new finding
regressions were run unskipped and failed on the stated contract assertions.
The default suite skips them by `S7-14`, `S7-15`, `S7-16`; green gates do not
certify these defects as fixed. Production code is unchanged.

## Findings

### S7-14 — minor — the world banner does not fade with the HUD row

- **PRD:** §12.2 explicitly requires the moved layer to fade with HUD row
  opacity; §12.1 keeps banner timings and appearance unchanged.
- **Location:** `lib/run/hud/banner_layer.dart:55` / `:65`,
  `lib/run/hud/run_hud.dart:124`. The world render uses visibility flags but
  never applies `hud.rowOpacity`. The scene-render path in
  `lib/run/rides/portal_ride.dart:446` also applies only ride opacity.
- **Repro:** show a settled streak-12 band; paint its actual world branch
  over black first with row opacity 1, then 0.25, sampling x290/y206.
- **Expected:** the band sample is its colour composited at 25% in the
  second frame, following the row's fade.
- **Actual:** the sample is the full-strength band colour in both frames
  (red-channel difference from expected: 0.75). Banners have their own
  timeline fades but ignore this additional HUD fade.
- **Regression:** `test/p22/s12_s18_s20_s21_qa_p3_test.dart`, S7-14.
- **Integration:** preserve §18's 50% scene opacity and avoid drawing the
  same host twice when adding the row fade. Preserve real-time updates,
  pause freezing and camera-shake compensation.

### S7-15 — minor — puzzle CollectText labels still draw above gameplay

- **PRD:** §12.1 and §12.2 explicitly move collect labels (`CollectText`)
  to the banner layer, while the pill/tray and fetch effects stay in the HUD.
- **Location:** `lib/run/items/puzzle.dart:372` / `:377` (n/4), `:434`
  (+N badge), `lib/run/hud/collect_slot.dart:103` (paints the whole item
  through the HUD slot).
- **Repro:** collect one puzzle piece, settle its pill for 0.9s, and paint
  only the actual HUD branch. Inspect the count area, separate from the
  puzzle board and its panel fill.
- **Expected:** no count-text pixels in the HUD branch; the label's text
  should be drawn behind the bird/hoops/pickups by the banner layer.
- **Actual:** 53 solid foreground-coloured count glyph pixels remain in
  the HUD branch. The badge uses the same foreground HUD paint path
  (source-audited). Only the completion sticker moved.
- **Regression:** `test/p22/s12_s18_s20_s21_qa_p3_test.dart`, S7-15.
- **Call disposition:** the builder's opaque-pill justification contradicts
  the explicit labels requirement. Moving the label alone behind an opaque
  panel would hide it, so the fix must coordinate panel compositing and
  background text without moving the kept board/fetch effects wholesale.

### S7-16 — minor — a completion sticker survives the collect layer's death

- **PRD:** §12.2 / §12.4: death clears the banner layer, revive rebuilds its
  contents, replay leaves no stale host or collect content.
- **Location:** `lib/run/hud/run_hud.dart:115` / `:118` clears the host and
  removes CollectLayer; `lib/run/hud/collect_layer.dart:214` adds stickers
  to the world layer, and `:224` only removes them from `onGone`;
  `lib/run/hud/collect_slot.dart:90` calls `onGone` on timed expiry, with
  no equivalent removal hook.
- **Repro:** eight passes; store puzzle mask 7; collect the fourth piece;
  advance 1.5s until PICTURE COMPLETE is mounted; die and wait until revive
  is shown. Inspect the surviving banner-layer descendants.
- **Expected:** the active collect sticker disappears when death clears
  its collect layer.
- **Actual:** one live GoldSticker remains at (160,344). Removing its HUD
  owner prevents the timed slot cleanup; the sticker remains behind the
  revive heart. The unskipped probe captures this frame at
  `build/menu_shots/p22/qa3/stale_puzzle_sticker_revive.png`.
- **Regression:** `test/p22/s12_s18_s20_s21_qa_p3_test.dart`, S7-16.
- **Integration:** tear down both active and queued collect timelines when
  their slot/layer is removed. Apply the same ownership cleanup to feather
  stickers, without destroying the host used by a switch crash banner.

## P2 fixes reverified

All original P2 regressions are unskipped on this branch. The 39-test focused
run (P2 originals, FIX2 additions, §12/20/31 builders) passed without skips.

| Finding | Evidence and result |
| --- | --- |
| S7-07 | `s16_s21_qa_p2_contract_test.dart`: FEVER remains at 0.35 past six perfect passes. Fixed. |
| S7-08 | Same file: ordinary fire leaves FEVER eligible; `fix2_s16_s21_s28_s33_test.dart` tests the ring and pair-gift exclusions independently. Fixed. |
| S7-09 | `s22_s28_s33_qa_p2_audio_test.dart`: live voices stop for ads and interruptions; FIX2 covers a queued start and no delayed burst on resume. Fixed. |
| S7-10 | Same audio file: releasing delayed core/lazy voice creation after disposal creates no orphan pools; FIX2 covers a fresh service generation. Fixed. |
| S7-11 | Same audio file: simultaneous never-played preloads stay within the cap; FIX2 preserves the latest ride reservations while evicting older unused pools. Fixed. |
| S7-12 | Original angled and rail planned-ahead regressions inspect actual spawned components; FIX2 tests stripping a reward while preserving its height. Fixed. |
| S7-13 | Original fallback-model run-start test resumes music while flapping; FIX2 retains suppression for positively identified external media. Fixed in the model/source path; native detection needs the later device round. |

Files in this table are under `test/p22/`. No P2 finding is reopened.

## Builder Calls and visual review

| Call | QA disposition |
| --- | --- |
| CollectText count/badge stays in HUD because the pill is opaque | Rejected against literal §12; S7-15. |
| Banner band does not fade with rowOpacity | Rejected against literal §12.2; S7-14. |
| Existing run strips use page mode for grey/normal reach | Accepted. Real cyan squeeze → revive → bonus → results → CLAIM journeys pass at 711/568/524 visible points, including normal tooth bounds and #828282 pixels. No separate strip instance is required by §31. |

Compared captures with `flow_postrun.html` (its linked bonus/results mocks),
`screen_levelup_rays_new.html` and its `shots_postrun/seq/` frames,
`shots_postrun/bonus_711.png`, and `screen_portal_rides3.html` / ride PNGs.
The grey bonus/results match the approved palette and arrangement; the rays
extend beyond the old rectangle, soften toward their tips, and stay behind
card/buttons/text. The three lowered-height results outcomes and solo result
fit above the visible teeth. Random confetti, scores and timeline phases
are deliberately not compared as identical pixels.

New screenshots explicitly load Fredoka as well as the two UI fonts. Their
711/568 captures use `captureShot`; the 524-point captures use its same
PictureRecorder pattern with **visible** height, avoiding stage-coloured
letterbox artifacts from feeding a logical 544-point field to the cropped
camera. This is a test-harness adjustment, not a product finding. Generated
PNGs and comparisons stay under `build/` and are not committed.

§12 × §18: all six rides have one host in the new world banner layer,
suppressed in its own paint pass, painted by the scene branch below objects,
and restored after exit. §20 × §21: a robin/wind-up/cowboy look with identical
gold effect retains identical painted colours when cyan stage and fire are
active. Existing classic/accessory stage sweeps and themed-death tests pass.

## §1 coverage: all 30 summary items

Paths below are relative to `test/p22/` unless qualified. “Pass” means local
automated evidence; device/service limitations are explicit. Existing tests
were reviewed and executed, not merely counted by filename.

| Item / section | Tests proving the behavior | Verdict / coverage gap |
| --- | --- | --- |
| 1 — Home mode / §2 | `s2_mode_button_test.dart`, `s2_mode_button_screenshot_test.dart`, `s2_s8_qa_p1_flow_test.dart`; `test/versus/s3_13_versus_run_test.dart` | Pass: storage/reset, switch/sound/analytics, START gating, tag/layout, solo FREE FLY with upload retained. |
| 2 — Sparse matching / §3 | `s3_matcher_search_test.dart`, `s4_versus_diagnostics_test.dart`, `s3_qa_p1_search_test.dart`; `functions/test/matching.test.ts` | Pass: own four shards, nearest levels, first hit/own uid, 44 reads, timeout, stale-generation protection and shared fixtures. |
| 3 — Diagnostics / §4 | `s4_versus_diagnostics_test.dart`, `s2_mode_button_test.dart` | Pass: fake-backend reasons, params, log/debug lines, no player-facing error. Live Play Integrity outside this round. |
| 4 — Ads / §7 | `s7_ads_test.dart`, `s7_banner_layout_test.dart`, `s7_7_noads_test.dart`, `s7_9_privacy_options_test.dart`, `s7_s17_s18_s27_qa_p2_flow_test.dart`; new `s7_s31_qa_p3_postrun_test.dart` | Pass in fakes: banner lifecycle/no-fill/consent/resize, interstitial guards, NO ADS ladder, bonus loading/offer, privacy, post-run strip. Mediation fill and real SDK/lifecycle remain device/service coverage. |
| 5 — Back / §8 | `test/back_gesture_test.dart`, `s2_s8_qa_p1_flow_test.dart` | Pass: observer routing, menu/popup close, run/inert behavior, app exit handled. Physical gesture delivery not rechecked here. |
| 6 — Music default / §9 | `s9_music_volume_test.dart` | Pass: 0.25, persisted values including zero, delete reset and slider/game application. |
| 7 — Rumble / §10 | `s10_hoop_rumble_test.dart` | Pass: contact timing, 80ms/255 perfect shake, light knock and throttle. Motor strength/feel is device-only; no new feel claim. |
| 8 — Perfect zone / §11 | `s11_perfect_zone_test.dart`, `s13_qa_p1_adversarial_test.dart` | Pass: boundaries/cap, off-centre reset and +1 coin, all hoop kinds, Bullseye crossing offset. |
| 9 — Background banners / §12 | `s12_banner_layer_test.dart`; feather/puzzle and switch suites under `test/run/`; new `s12_s18_s20_s21_qa_p3_test.dart` | Main layer/order/clock/shake and ride handoff pass. New coverage exposes S7-14…16, intentionally skipped in the green gate. |
| 10 — Points / §13 | `s13_points_test.dart`, `s13_versus_timeline_test.dart`, `s13_qa_p1_adversarial_test.dart`, `s13_fix1_timeline_check_test.dart`; `functions/test/{timeline,p22_qa_p1,convert}.test.ts` | Pass: points vs coins, uncapped streak, all bonus/chick/puzzle values, HUD fit, record/server validation and old-run conversion. |
| 11 — Results ticks / §14 | `s14_results_ticks_test.dart` | Pass: zero counts silent, one concurrent tick stream, count/CLAIM timing and cancellation. |
| 12 — Scroll in / §15 | `s15_scroll_in_test.dart`, `s15_s23_s27_screenshot_test.dart` | Pass: catalogue spawn-edge gate, attached switch/comet plans, follow-up pop-in, clearing/hold and revive. |
| 13 — Comet zigzag / §16 | `s16_comet_zigzag_test.dart`, `s16_s21_qa_p2_contract_test.dart`, FIX2 | Pass: alternating ±70 at both heights, start side, curve/tilt, end prediction, already-planned tilt/motion retained. |
| 14 — Comet landing / §17 | `s17_comet_landing_test.dart`, `s7_s17_s18_s27_qa_p2_flow_test.dart` | Pass: one flap, 0.8s at half speed + 0.7s return, quiet landing, Hourglass composition and blocking. |
| 15 — Portal polish / §18 | `s18_portal_rides_polish_test.dart`, `s18_portal_rides_shots_test.dart`, P2 flows; new P3 scene-paint tests | Pass for all six themes: real banner paint handoff, circle colour/opacity/continuous return, auto flap, two-second first plane, cue preload. Actual cue audibility not certified headlessly. |
| 16 — Opening variety / §19 | `s19_random_opening_test.dart` | Pass: heart histogram, equal early pool, 55–65% feather/piece across seeded runs, window/placement bounds, determinism. |
| 17 — Bird colours / §20 | `s20_bird_colours_test.dart`, `test/look_visual_test.dart`; new P3 fire/accessory pixels | Pass: classic/accessory stage 0/1/5/10 pixels, gold preserved, themed tint preserved, cyan+fire interaction. |
| 18 — Fire / §21 | `s21_fire_test.dart`, `s21_fire_screenshot_test.dart`, P2 contract/FIX2; new P3 accessory pixels | Pass: threshold/reset, size/halo/emission/palettes, thick trail, one loop, FEVER unchanged, rides/comet. |
| 19 — Full sound lengths / §22 | `s22_full_length_sounds_test.dart`, P2 audio and FIX2 | Pass: duration-table file freshness, full-length fake voices, overlap/steal caps. Native SoundPool audibility is a later device check. |
| 20 — Egg / §23 | `s23_egg_rim_test.dart`, `s15_s23_s27_screenshot_test.dart` | Pass: each rim type, quiet break, chick immunity, ride-ring exclusion and fall art. |
| 21 — Revive taps / §24 | `s24_revive_taps_test.dart`, `s7_7_noads_test.dart`, P2 versus revive flows | Pass: real empty-space taps inert, buttons only, locked heart, indefinite wait, ad/free phoenix ladder. |
| 22 — Special-ring sizes / §25 | `s25_ring_sizes_test.dart`, `s25_ring_sizes_screenshot_test.dart`; special-hoop/autopilot suites | Pass: normal-size saw openings, shrinking decoration transforms, portal 118 exception, playability. |
| 23 — Piggy / §26 | `s26_piggy_coins_test.dart` | Pass: 16-point coin, 14-point catch/miss radius, spacing and collection. |
| 24 — One bonus / §27 | `s27_one_bonus_test.dart`, `s27_one_bonus_director_test.dart`, P2 flow/FIX2 | Pass: reward gating, fading/stripping ahead, owed pickups, two breather planes, passive states, 500-seed statistics. |
| 25 — Audio / §28 | `s28_audio_test.dart`, `s22_s28_s33_qa_p2_audio_test.dart`, FIX2 | Pass: death loops, ad and interruption holds including ringing/queued one-shots, own/external music models. Android native observer and calls/alarms/other apps are weak coverage until device QA. |
| 26 — Streak names / §29 | `s29_streak_names_test.dart` | Pass: all 50 names, modulo colours, beyond 50 real count, white text and text fit. |
| 27 — Moving passes / §30 | `test/run/physics/p22_s30_moving_pass_test.dart`, `p22_s30_moving_pass_game_test.dart`; moving-hoop/autopilot suites | Pass: every motion across 200 phases, clean/miss boundary, previous/current pose, interpolation, fast rim sweep, once-only resolution. |
| 28 — Grey pages/rays / §31 | `s31_postrun_grey_test.dart`, `s31_postrun_shots_test.dart`; new `s7_s31_qa_p3_postrun_test.dart` | Pass. Former weak bonus/versus/CLAIM assertions filled with 12 complete cyan-squeeze journeys, grey pixels, actual ray/UI paint comparison and shortened-viewport bounds. |
| 29 — Prices / §32 | New `s32_placeholder_prices_test.dart`; `test/localized_price_fit_test.dart`, `test/services/store_iap_service_test.dart`; workspace `tools/pricing/test_pricing.py` and `PLAY_VERIFY_2026-10-12.md` | Missing explicit build-price gate filled: all five offline/default USD values pass. Store prices have recorded 174/174 evidence per product; no live console re-verification/account action in P3. |
| 30 — Performance / §33 | `s33_audio_pool_test.dart` (20-run overlap/churn), `s33_avatar_cache_test.dart`, `s33_idle_lifecycle_test.dart`, `s33_small_leaks_test.dart`, `s33_soak_test.dart`; P2 audio/FIX2 | Local bounds/disposal/polling/cache/lifecycle pass. **Weak physical release coverage:** merged-build PSS/native-player/CPU/thermal/frame soak still requires the device round. `docs/p22/PERF.md` records the earlier after-idle soak and calls game-20 frame drift borderline; these headless results do not close §33.6. |

Missing headless assertions discovered in the coverage audit were written
(§32 placeholders, §31 bonus/versus/CLAIM/short-height paint, §12 lifecycle
and opacity, §12×18 scene paint, §20×21 pixels). No summary item lacks a
local test suite now. Native-only gaps cannot be certified by adding fake
assertions; the existing device integration/soak harnesses are retained for
the next authorized device round.

## Changes and validation

- Added `test/p22/s12_s18_s20_s21_qa_p3_test.dart`: 7 passing integrations
  and 3 failing finding regressions, skipped by ID by default.
- Added `test/p22/s7_s31_qa_p3_postrun_test.dart`: 12 passing post-run
  integrations and visual captures with correctly loaded fonts.
- Added `test/p22/s32_placeholder_prices_test.dart`: 5 passing price cases.
- Added this report. Existing tests and all production contracts unchanged;
  no SPEC/ARCH amendment is required for QA-only tests.

- `flutter pub get`: passed.
- Focused P2/FIX2 + §12/20/31 builder tests: **39 passed, 0 skipped**.
- New QA P3 suites: **24 passed, 3 skipped**; the full gate below also
  includes their final visible-height capture adjustment.
- Finding probe: `flutter test --concurrency=4
  test/p22/s12_s18_s20_s21_qa_p3_test.dart
  --dart-define=QA3_FINDINGS=true --reporter expanded`: **7 passed,
  3 failed**, exactly S7-14…16; no harness/precondition failures.
- `flutter analyze --no-pub`: **clean**.
- `flutter test --no-pub --concurrency=4 --reporter expanded`:
  **2465 passed, 6 skipped** (3 existing skips + 3 new finding regressions).
- `npm --prefix functions ci`, `npm --prefix functions run build`: passed.
- `npm --prefix functions test`: **121 passing**; backend emulator suite
  shut down cleanly.
- `git diff --check`: clean.

No existing tests were changed. The 24 passing tests and three documented
skips are additions, so the count increase reflects additional coverage,
not removed behavioral checks.

## Remaining work and integration risks

S7-14…16 require builder fixes. Coordinate the banner opacity/scene handoff,
collect-panel/text compositing, and collect timeline teardown. Physical
rumble/audio/gestures, live mediation/versus and the final 20-game soak are
outside this **no-device** round. No device installs, Android emulator,
deployments, signing-key copies, account changes, iOS edits, store screenshots
in the commit, or pushes were performed. The Functions command ran its
required backend emulator suite only.

QA made no new gameplay Calls. Test-only Calls: compare colours with the
same gold effect and frozen accessory clocks; render the actual cropped
visible viewport for banner-height PNGs; compare animation layout/palette
without requiring random particles or demonstration scores to match.
