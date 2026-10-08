# P6 — real Pixel 8 playtest, final PRD-2 merge

Independent device test on **2026-10-08**, branch `g6-qa5`, product baseline
`0f96074`. Device **Pixel 8**, Android **17**, serial `38300DLJH004SD`,
1080 × 2400 px (320 pt game width). This is the requested Flappy Spikes 2.1 /
PRD-2 feature build; its embedded package version remains **2.0.0+7**.

**Verdict: not shippable to internal testing as the completed PRD-2 build.**
One major and two minor findings remain open. S6-F01 prevents live matching on
this phone, and successful online deletion could not be verified. Offline solo
play remains usable. No product code was changed and nothing was deployed.

## Build and method

- Built and installed the requested debug APK with `FS_E2E=true` and the supplied
  registered App Check debug token. APK SHA-256:
  `16441651d7e159be5c2a0fbca1083ebf38a60ac6f0b741129a37dfe80edd082b`.
- Cleared the authorized test-install data at the start. Runs, menus, ad revive,
  coin revive, bonus, pause and Settings were driven through **ADB taps on the
  real app**. The debug panel (`D` key → RUN DEBUG) forced elements/rides;
  bot/god mode assisted long runs. Debug +1000 coins funded the revive ladder.
- Collected the last two feathers using timed hand flaps, and completed the
  puzzle by playing successive forced-piece runs. No feather/puzzle preferences
  were seeded, and no synthetic opponent was injected.
- `FS_E2E` deliberately uses `NoopReminders`, so it cannot show notification
  permission. Installed a second debug APK with **FS_E2E omitted**, retaining
  test progress and passing the same App Check token. SHA-256:
  `231ee9d27cea8ab5329ce03a7f0e519f14d01166ef7a6959beac43b4e3a16ca1`.
  The Android permission sheet appeared before playing; Allow and the test-ad
  consent refusal were tapped. It did not reappear on the next cold start.
  The requested FS_E2E APK was restored afterward.
- Read PRD-2, SPEC, ARCH and earlier P1/P2/P3/P45 findings. Device captures were
  visually compared with the approved PNGs named by the corresponding §5
  sections. Differences in score, stage, opponent absence, equipped trail and
  animation phase were considered. This was visual inspection, not a pixel
  golden comparison.
- Retained **99 unmodified 1080 × 2400 screenshots** in
  [playtest_shots/](playtest_shots/). `capture_manifest.json` maps each renamed
  image to its original capture. Contact sheets were review aids only.

## Findings

| ID | Severity | Screen / flow | What's wrong | Reproduction steps | Expected (PRD §) | Screenshot / evidence |
|---|---|---|---|---|---|---|
| **S6-F01** | **major** | Cold start → Home → live versus; online actions | Home/resume starts versus before Firebase initialization completes. `activateAppCheck` sets its process-wide success guard **before** activation; `[core/no-app]` leaves it latched. Recovery then bypasses activation. Pool reads return `permission-denied`, Home has no opponent and START goes solo. Reproduced in both APK variants. | 1. Cold-launch online with the registered token. 2. Wait on Home. 3. START: no VS intro. 4. Resume / return Home: pool remains unavailable. 5. Read Flutter logs: `initialize failed: [core/no-app]`, followed by Firestore permission denied, with no successful App Check activation message. Repeat cold start. | Initialize Firebase before dependent startup; activate App Check successfully; use a real prefetched opponent when available, and recover transient startup failure (§3.13, §5.8; ARCH §6.5). Solo fallback itself is correct. | [Home](playtest_shots/S6-F01_F02_home_after_restart.png), [app logs](playtest_shots/app-log-excerpts.txt), [deletion failure](playtest_shots/delete_failed.png). Source: `firebase_versus_backend.dart:35`, `flappy_game.dart:718,746`, `main.dart:108`. |
| **S6-F02** | **minor** | Persistent anonymous player identity | Generated nickname changes on cold starts without deleting data. Early resume initializes versus against unloaded storage and overwrites the saved nickname. | 1. Read the test install's saved nickname. 2. Force-stop and launch without clearing data. 3. Read again. Two consecutive starts produced **SparklyEagle285 → CleverFinch671**. 4. The FlameTester case invokes the real resumed lifecycle before storage load: saved `SwiftKiwi482` is replaced. | Anonymous nickname is created **once per install** and retained across launches; only Delete my data starts a fresh identity (§3.13 Who plays; §7 `versusNickname`). | [First Home](playtest_shots/S6-F02_home_before_restart.png), [second Home](playtest_shots/S6-F01_F02_home_after_restart.png), [nickname readback](playtest_shots/nickname-proof.json). Home does not display the nickname; JSON supplies the identity evidence. Source: `flappy_game.dart:718`, `versus_service.dart:347,367`, `storage.dart:433`. |
| **S6-F03** | **minor** | Piggy Bank / Firefly Jar pickup → HUD announcement | The persistent collection counter is painted through the announcement banner. Piggy art, `3 / 20`, bar and `1 missed` overlap `PIGGY BANK` and its explanation. Jar's HUD likewise overlaps `FIREFLY JAR`. This clears when the banner fades; payouts still completed. | 1. Home → debug → RUN DEBUG → Bot + God → force Piggy Bank. 2. START. 3. Observe collection around 3–4 s. 4. Repeat with Jar. 5. Subsequent streak banners can occupy the same HUD band. | The progress HUD and announcement must remain readable (§3.28/§5.27, §3.29/§5.28, shared banner §3.0.9). Preserve the approved art while arranging or suppressing colliding content. | [Piggy overlap](playtest_shots/S6-F03_piggy_banner_overlap.png), [Jar overlap](playtest_shots/S6-F03_jar_banner_overlap.png). Source: `run/hud/run_badges.dart:76,148`, `run/hud/banners.dart:20`; piggy counter y209 and bar y220 intersect the banner starting y190. |

S6-F01's App Check failure is a **confirmed client defect**, independently
reproduced without the network. It explains the missing client activation;
Firestore's live permission error alone would not prove the state of server
rules or the seeded pool. No rules, tokens or live pool contents were changed.
The deletion callable returned `firebase_functions/unauthenticated`; that is
consistent with the failed authenticated/App Check path, but this pass did not
independently inspect the callable's server rejection reason.

## Player-flow results

| Check | Device observation | Key captures |
|---|---|---|
| First start / Home | Fresh FS_E2E install showed the No-ads launch popup, then Home. Normal debug showed the native notification request; Allow persisted. | `home_fresh.png`, `notification_permission.png` |
| START / real hoops | Actual scrolling hoops and perfect passes; PERFECT, GREAT, AMAZING and higher tier banners, gold bird, trails, coin pops and stage changes. Initial ordinary bot run reached 45 and died. | `element_angled_ring.png`, `element_train.png`, `element_comet.png` |
| Death / floor rest | Bird tumbled and rested on floor teeth; ≥6-hoop revive overlay appeared. | `death_floor_rest.png`, `revive_ad_offer.png` |
| Ad revive / phoenix | Tapped real revive heart, saw visible TEST AD / REVIVE countdown, then ignition, rise, wings, burst and return to scrolling. Score retained. | `revive_fake_ad.png`, `phoenix_ignite/rise/wings/resume.png` |
| Coin ladder / decline | Second death offered 250; paying reduced wallet. Next death offered 500. Later six-hoop run's **No thanks** was tapped at about (540,1770), opening earned balloon bonus. | `revive_coins250.png`, `revive_coin_payment.png`, `revive_coins500.png`, `bonus_revive_no_thanks.png`, `balloon_start.png` |
| Results / level up | First 45-hoop run showed LEVEL UP / EGG LV1, CLAIM +50, reward 128 →178, then NEXT returned Home with best/last45. | `results_levelup_claim.png`, `results_levelup_claimed.png`, `results_next_home.png` |
| Pause / background | Pause button froze the run; Resume returned to play. Home key followed by reopening returned to PAUSED; manual Resume worked. | `pause.png`, `background_paused.png`, `resume.png` |
| Feather / balloon | Third feather flew into tray, bounced with confetti and BONUS UNLOCKED. Nine-balloon bonus accepted three pops; ad offer initially lacked No thanks, which appeared after 3s. Fake bonus ad refilled three feathers; six total pops → NEXT → results. Bonus total425; results reward12 excluded those already credited coins. | `feather_fetch.png`, `feather_complete.png`, `balloon_pop_animation.png`, `balloon_offer_before_no_thanks.png`, `balloon_offer_after3s.png`, `balloon_fake_ad.png`, `balloon_refill.png`, `balloon_after6_next.png`, `balloon_results.png` |
| Puzzle 4/4 | Across forced-piece runs, persistent 2/4 →3/4 →4/4; picture celebration and +130 coin badge. A following run displayed a Sky-round piece, confirming round advancement. | `puzzle_3of4.png`, `puzzle_4of4_reward130.png` |
| Settings | RUMBLE on→off, SFX on→muted and MUSIC slider moved; all remained changed after force-stop/relaunch. Haptic feel was not tested. | `settings_before.png`, `settings_changed.png`, `settings_persisted.png` |
| Delete my data | Confirm and DELETE worked; result **COULDN'T DELETE**, callable unauthenticated. Progress remained on phone. Successful online deletion is **not verified**. | `delete_confirm.png`, `delete_failed.png` |
| Versus | Home stayed without an opponent; START correctly fell back to solo. **Live VS intro, bar and duel results could not be exercised**, blocked by S6-F01. Earlier harness coverage is not counted as phone coverage. | `S6-F01_F02_home_after_restart.png`, `app-log-excerpts.txt` |

**Rim-bounce coverage:** a final timed hand-flap attempt captured lower-rim
white sparks and the rotating bird in [rim_contact_spin.png](playtest_shots/rim_contact_spin.png)
(bot off, god on). Other attempts produced perfect passes and miss flashes.
This confirms contact/spin art on the phone, but an inside-rim bounce followed
by a credited +1 pass, the full 360° sequence and recoil recovery were not
conclusively isolated. Those parts are not marked passed on-device. The green
automated baseline does not replace that remaining phone observation.

## Forced elements and approved-art review

Every force-menu element category was seen on the phone. Bot/god mode provides
visual reachability, not proof of normal difficulty or deadly-rim behavior.
All five named rides **plus Cannon** were captured through return to normal
play. No additional clear broken animation or incorrect element copy was found.

| Element / state seen | Approved comparison | Phone evidence in `playtest_shots/` |
|---|---|---|
| Normal, angled, moving hoops; bullseye; train; spring | §5.1, §5.11–12, `lab_bull/train/spring.png` | `element_angled_ring.png`, `element_moving_ring.png`, `element_bullseye.png`, `element_train.png`, `element_spring.png` |
| Switch ring (Sleepy), gift pair, FEVER, Lucky Spin, saw (black hole; Ice also seen later) | `switchring_sleep_off.png`, `giftpair_*.png`, `fever_*.png`, `lab_lucky.png`, `sawring_hole/ice_fly.png` | `element_switch_ring.png`, `element_pair.png`, `element_fever.png`, `element_lucky_spin.png`, `element_saw.png` |
| Big Hoops starter; Comet and expiry; heart; Shield pickup, gift-pair activation and SAVED | §5.2, §5.5–6 | `element_comet.png`, `comet_expired.png`, `element_heart.png`, `element_shield.png`, `shield_from_gift_pair.png`, `shield_saved.png`, `big_hoops_starter.png` |
| Star Trail; Hourglass; Mini Bird; Coin Frenzy capsules | `lab_trail/slow2/mini2/frenzy.png` | `element_star_trail.png`, `element_hourglass.png`, `element_mini_bird.png`, `element_coin_frenzy.png` |
| Egg → hatch/chick ×2; Piggy → +26 payout; Jar → JAR FULL +25 | `lab_egg3/piggy3/flies3.png` | `element_egg.png`, `egg_hatched.png`, `egg_chick_x2.png`, `element_piggy.png`, `piggy_payout26.png`, `element_jar.png`, `jar_full_reward25.png` |
| Feathers, puzzle, squeeze warning/close/hold | `feather_*.png`, `puzzle_*.png`, `squeeze_*.png` | `element_feather.png`, `element_puzzle_piece.png`, `feather_complete.png`, `puzzle_4of4_reward130.png`, `element_squeeze_warning/closed/hold.png` |
| Space / rocket | `ride_space_*.png`, portal landing mocks (§5.12b) | `ride_space_1..4.png` |
| Volcano / eruption | `ride_volcano_*.png` | `ride_volcano_1..4.png` |
| Deep Sea / whale spout | `ride_sea_*.png` | `ride_sea_1..4.png` |
| Pinball / bumpers, flippers and jackpot loop | `ride_pinball_*.png` | `ride_pinball_1..4.png` |
| Storm / funnel, cow, lightning, umbrella | `ride_storm_*.png` | `ride_storm_1..4.png` |
| Cannon / aim, launch, glide | `portal4_*.png`, cannon launch specification | `ride_cannon_1..4.png` |

The review accepts the current large score disc (§3.0.9 / §5.7), 44pt menu
strips, equipped default Flame trail (ARCH skin interplay), and collect tray at
centre y288 (ARCH §27's documented call). Older mock small score discs, block
trails, y230 tray and balloon jackpot500 are not newly filed defects; PRD's
current jackpot is250. All five switch designs, all three saw designs, every
ride random branch and the balloon jackpot outcome were **not** exhaustively
sampled. S6-F03 is an actual counter/banner collision, independent of these
accepted layout differences.

## Audio, performance and logs

- Available mid-pass and final logcat buffers contained **0** FATAL EXCEPTION,
  fatal signal, E/flutter, unhandled exception, RunEvents listener failure,
  AudioPlayerError or MediaPlayer error matches. Firebase failures were caught
  and logged; the deletion stack was caught, not an uncaught Flutter exception.
- `dumpsys media.audio_flinger` during Pinball/continued play showed **two active
  tracks** for the app process (PID28856, UID10545). SoundPools were present.
  The device's route was muted; this confirms playback activity and absence of
  logged audio failures, not an audible judgement of mixing or clip quality.
- Normal non-E2E debug logged **AdMobRewardedAds load failed: Unable to obtain a
  JavascriptEngine**. It also found all five IAP products. Production ad delivery
  was not established; the requested revive/bonus journeys used fake ads.
- Requested Android `gfxinfo` observations (debug APK, ADB capture overhead):

| Sample | Rendered frames | Janky frames | Percentage | p50 / p90 / p95 / p99 |
|---|---:|---:|---:|---|
| Tier-3+ stretch / pause |43|6|**13.95%**|5 /57 /81 /300ms|
| Pinball / return to play |18|5|**27.78%**|6 /129 /300 /300ms|

Raw summaries are `gfx-first.txt` and `gfx-pinball.txt`. These are small Android
view-renderer samples; Flutter renders via Impeller/Vulkan, so they are **not**
a representative Flutter raster-frame benchmark. Performance is not a gate.

## Reproduction tests and verification

Added [p6_playtest_e2e_test.dart](p6_playtest_e2e_test.dart). Each finding has its
own group with the requested `skip: 'S6-Fxx open'` reason (FlameTester's case
argument accepts only a boolean, so the descriptive skip is on the group).

| Check | Result |
|---|---|
| Requested FS_E2E APK build/install | Passed |
| Normal debug APK build/install, then restore FS_E2E | Passed |
| `flutter analyze` | Clean |
| `flutter test -j 3 --reporter expanded` | **1,871 passed, 6 skipped**, all green |
| `flutter test test/e2e/p6_playtest_e2e_test.dart --run-skipped --reporter expanded` | **Three expected assertion failures**, one per finding; no compile/setup failure |
| `git diff --check` | Clean |

S6-F01 exercises real Home prefetch and the real static App Check activation
guard, isolating Auth/network plugins; the first missing-Firebase activation
fails, but a retry incorrectly reports completion (expected0, actual1).
S6-F02 exercises the real resumed lifecycle before storage load and finds the
persisted nickname overwritten. S6-F03 collects a real Piggy pickup in the
Flame game, mounts its actual HUD/banner and proves the counter lies inside the
visible announcement band.

The first full-suite attempt lacked the Functions npm dependencies; installing
the locked dependencies with `npm --prefix functions ci` and building Functions
resolved the environment-only failures. The final complete suite above passed.
No tracked dependency or product files changed. This is a QA-only commit: report,
open reproductions and real-device evidence.

## Fix round R1 decisions (Fix P6 R1)

- **S6-F01:** fixed — `GameServices.ensureFirebase()` owns one shared `Firebase.initializeApp` future and every versus start waits for it plus the storage load (`FirebaseVersusService.startAfter`); `activateAppCheck` latches only after a successful activation and retries after a failure.
- **S6-F02:** fixed — versus waits for the storage load, and `GameStorage.ensureVersusNickname` reads the saved name from disk before generating one once per install; a saved nickname is never overwritten.
- **S6-F03:** fixed by moving, not hiding — the egg / piggy / jar HUD badges keep their approved art and layout but sit `HudConfig.collectLift` = 86 pt higher (between the name chips at y 114 and the timer pill at y 156), clear of the y-190 banner band, like the timer pill and the y-288 tray calls.
- **Device re-check (Pixel 8, debug APK with the registered token):** across 10+ cold starts logcat shows `versus: App Check activated (debug provider)` with no `[core/no-app]` or `permission-denied`. The nickname stayed `CleverDove701` on every start. Pool reads succeed, and when a shard holds a foreign run, Home holds an opponent and START plays the VS intro. `release_e2e_test.dart --plain-name "versus live"` passes, including `deleteMyData ok`. Side fix: `notif_permission {granted: bool}` tripped a Firebase Analytics assertion. `GameServices.logEvent` now sends bools as 1 / 0.
