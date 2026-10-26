# a2-showcase — PRD 2.6 WP-B Showcase audit (feat/2.6 @ a57a7fb)

## 1. Summary

- **The showcase never runs in the shipped game.** All WP-B parts exist (plan model, scripts, director overlay,
  starters, grabs, FREE revive, force-menu row, tests), but production still uses the inert M1 skeleton:
  `FlappySpikesGame` defaults to `const InertShowcasePlan()` / `InertShowcaseProgress()`
  (`lib/game/flappy_game.dart:169-170`), and `lib/main.dart:161-167` passes neither. `ShowcaseShow(` is built
  only in `test/p26/showcase/plan_state_test.dart`. Every other showcase test injects a `FixedShowcase`/`_ShowcasePlan`
  stub. The #60 builder said so ("the default planner is still inert"), and no later issue fixed it.
- The pure parts match the PRD: the B3 tables (`lib/run/config/showcase_config.dart`) match the PRD cell by cell. The
  B1 state machine (`lib/run/showcase/showcase_plan.dart`) does steps and bits, A at START, done via all/cap/fast,
  tester adoption and Delete my data. The FREE revive ladder and the eligibility fix from #36/#92 are correct.
- These are built but wrong or incomplete:
  - `showcase_end` gets only default score/cause/shield/revive values from the game (`flappy_game.dart:4197-4200`).
  - The `showcase_done` ftue step is never emitted.
  - Once wired, `highlight_seen` would be sent twice.
  - The director flattens every hoop within ±7 of a highlight to a plain still, untilted hoop. That goes beyond
    R6 (normal mix) and D6 (headline items only), and the 200-seed parity test simply excludes that window.
  - The re-seeded portal theme is a uniform random pick that ignores the no-repeat rule.
  - The portal-grab tests call `grab()` directly.
- **#60 (merged without a tester verdict):** its claims hold in the code (scripted slots and gaps, first-meet off,
  portal re-seed, force-menu row, bot and invisibility tests). Two exceptions:
  - Its own tester's major "debug runs never upload" is still open: `countsForUpload` is never read, and
    `versus.submitRun` at `flappy_game.dart:4270` is unguarded. That is WP-E E1 scope.
  - Its parity is window-excluded, as described above.
- **#123/#126** are about formations, spring and tilt (not WP-B). They kept the showcase suites green.
- **Test-run blocker for every auditor:** `.dart_tool/package_config.json` points at
  `~/.local/state/df4/flappy-spikes/cache/{flutter,pub-cache}`, which no longer exists (df4 was removed today).
  Every `flutter test --no-pub` now fails at load (compile errors in `mystery_box.dart` and others; I tried
  `test/p26/showcase/*`). I could not re-run tests. Test statuses below rely on the orchestrator's full-suite run
  (only 3 reds, none of them showcase tests), so all `test/p26/showcase/*` were green then. A `flutter pub get` with
  the `~/flutter` SDK is needed before any further test run (an orchestrator decision; I am forbidden to run it).

## 2. Requirement table

| ID | Requirement (short) | Status | Evidence | What to do |
|---|---|---|---|---|
| B-goal / O16c | Runs 1–3 get an invisible early highlight in the real game | **FIX** | `flappy_game.dart:169-170` inert default; `main.dart:161-167` no showcase args; `git log -S "ShowcaseShow("` shows only #33 | Wire `ShowcaseShow(storage: game.storage, tracker: services.track)` in production only (factory/late setter), keep the inert default for tests |
| B1.1 | New pure model `lib/run/showcase/showcase_plan.dart` + `lib/run/config/showcase_config.dart` | DONE | both files exist | — |
| B1.2 | Step S = first unset bit; bits 0 portal, 1 comet, 2 FEVER | DONE | `showcase_plan.dart:343-350`, `showcase_config.dart:11` | — |
| B1.3 | Done: all bits OR gamesPlayed ≥ 6 OR a showcase run passes 40 | DONE | `showcase_plan.dart:428-437, 510-521`; tuning `showcase_max_games` 6 / `showcase_fast_hoops` 40 `tuning_defaults.dart:479-482`; `plan_state_test` "done via all/cap/fast" | — |
| B1.4 | A incremented + saved at START; plan frozen in `RunSetup.showcase` | DONE (in model) | `showcase_plan.dart:439-447`; `flappy_game.dart:1540-1566`; `plan_state_test` "A increments at START" | Only live after wiring |
| B1.5 | Never built on `setup.forced`; never touches `_cleanStart`; separate planner step 0 | DONE | `RunSetup.showcase` separate field; `atStart(forced:)` returns null `showcase_plan.dart:406-409`; `_cleanStart` unchanged `run_controller.dart:118-128`; overlay at `run_director.dart:1387-1410` | Note: implemented as a post-overlay on the finished normal slot, not literally "before debug force" (equivalent, because a forced run has no showcase) |
| B1.6 | Highlight bit written the moment the highlight starts | DONE | `showcase_plan.dart:452-465` (sync storage + queued prefs write); emitters `portal_ride.dart:146`, `comet.dart:80`, `fever.dart:162` | — |
| B2.1 | Mode/ads/dialogs as today; VERSUS with VS intro + upload | DONE (test) | `upload_rules_test.dart` (VERSUS upload of a showcase run) | Re-check on device after wiring |
| B2.2 | Counts for everything; `countsForAchievements` true | DONE | `invisible_components_test.dart` expects `countsForAchievements` true; `run_controller.dart:142-152` | — |
| B2.3 | Normal mix by hoop index + lifetime gates (no saw < game 4, no squeeze < game 6) | **FIX** | Gates: `run_controller.dart:75-84` applies `GatesConfig.filter` in showcase runs too (OK). Mix: `_showcaseHeadline` (`run_director.dart:1404-1421`) turns every hoop with \|hoop−highlight\| < 8 into `_showcasePlain` (tilt 0, no motion, normal kind, no attached). Step 1 A1: hoops 0–14 all plain; step 3 A1: hoops 0–22 plain (tilt from 10 / switch from 15 removed). | Limit the window to D6 headline items (rides, big bonus, squeeze warning, introductions, first meets). Keep tilt/motion/switch by hoop index. Or record a DEVIATION in SPEC.md + PRD if the owner wants calm |
| B2.4 | Layout/opening = normal curve (R6: no Δy row, no floor 110) | DONE | no showcase Δy row/floor in `run_director.dart`; scripted slots clamp the normal centreY `run_director.dart:1056-1062` | — |
| B2.5 | First-meet pulls off in showcase runs | DONE | `run_director.dart:57` `pullsEnabled: showcase == null`; `first_meet.dart:31`; `director_script_test` `firstMeet.due(100)` null | — |
| B2.6 | Big Hoops + shield armed at START, no label/FREE offer; the other one added if the home slot armed one | DONE | `flappy_game.dart:1593-1601`; `big_hoops.dart:36-44`; `starters_test.dart` | — |
| B2.7 | Big Hoops D = 60 s in step 1 (still drawing once), normal roll in steps 2–3 | DONE | `big_hoops.dart:83-90`; `starters_test.dart:95-100` timing-stream determinism (the #35 major, fixed by #92) | — |
| B2.8 | One FREE revive from the first death after hoop 0; ignores `revive_min_hoops`; then the 2.5 ladder (ad, coins, also versus) | DONE | `revive_ladder.dart:98-102, 126-130`; `flappy_game.dart:2074-2078`; `free_revive_test.dart` ("FREE below six hoops, then ad, then coins; no ad for FREE", "six-hoop exemption ends") | — |
| B2.9 | Revive screen labels it FREE (golden) | DONE | `revive_screen.dart:177, 293, 748`; `free_revive_goldens_test.dart` | #36 minor (heart size) appears compensated (`revive_screen.dart:682-687` scale); visual UNVERIFIED |
| B3 step 1 | Portal Cannon 7/5/3; star trail 2,5 / 2 / 2; feather 4/3/2; hearts 10,13,16 | DONE (plan) | `showcase_config.dart:39-125`; `plan_tables_test`; `director_script_test` (568/711/730, 50 seeds) | Add a run-level spawn test (see WP-B-4) |
| B3 step 2 | Frenzy 3/3/2; comet 9/6/4; star trail 6/5/–; bullseye 14; hearts 12,15,18 | DONE (plan) | same; bullseye-through-comet fix (#60 build3) sets `duringRide: true` on scripted slots `run_director.dart:1072`, read by `run_spawner.dart:174` | Same |
| B3 step 3 | FEVER 5/4/3; puzzle 8/6/5; Space portal 15/13/11; hourglass 11/11/9 | DONE (plan) | `showcase_config.dart:50-53, 69-73, 105-109` | Same |
| B3 re-seed | Portal schedule re-seeded after a scripted portal (+25..40) | DONE / minor FIX | `run_director.dart:1054, 1394-1403`; test "next portal actually resumes" | The re-seeded theme `RideId.values[_showcaseRandom…]` ignores the `_lastRide` no-repeat rule (`run_director.dart:2093`), so it can repeat Cannon right after the scripted Cannon. The scripted portal does not update `_lastRide` either. Use the normal theme pick |
| B4 portal | Any live crossing of the portal plane starts the ride (showcase only) | DONE / test FIX | `run_controller.dart:512-519`, `portal_ride.dart:113-123` | `grabs_test.dart:116-160` still calls `feature.grab()` directly (#35 minor open). Add a flown crossing-outside-ring test vs a normal miss |
| B4 comet | Radius 18→60, drift ≤ 90 pt/s, via the `cometMode=2` path | DONE | `comet_star.dart:33-62`, `comet.dart:19-20`; `grabs_test` radius/drift tests | `HighlightStarted.hoop` for the comet is `s.hoopIndex - 1` (the spawn index, not the star's hoop) `comet.dart:84`: #35 minor still open |
| B4 FEVER | `!h.touched` treated as true in showcase | DONE | `run_controller.dart:628-631`; `grabs_test` FEVER pair | — |
| B5 | Home unchanged; no showcase/graduation moment | DONE | `invisible_components_test.dart` (runtime-type scan at 568/711/730, steps 1–3, plus Home) | The scan is name-based only (weak, acceptable) |
| Edge: dies at hoop 2 | Normal results; next START step 1 A = 2 | DONE (model) | `plan_state_test` | — |
| Edge: before hoop 0 | Normal death, no FREE | DONE | `free_revive_test` "death before hoop 0", `invisible_components_test` | — |
| Edge: kill after highlight | Next run = next step, A = 1 | DONE | `showcase_plan.dart:466-472`; `plan_state_test:73` | — |
| Edge: Delete my data | Resets every showcase key | DONE (keys) / DEFER? | `storage.dart:1128-1146`; `plan_state_test:292, 323` | After a real restart with gamesPlayed ≥ 3, the install is treated as legacy (done), and at ≥ 6 the cap ends it. #33 test2 major, still present by design; the test encodes "follows the WP-B legacy rule". Accept, or persist an explicit reset marker. Low value; suggest accepting and noting it in the PRD |
| Edge: testers | gamesPlayed ≥ 3 and no key → done | DONE | `showcase_plan.dart:352-387, 410-421`; `plan_state_test:244, 266` | — |
| Edge: No-Ads | Same script | DONE | `free_revive_test:57` | — |
| Edge: tablets | Scripted items via the director / `world.addRun` | DONE | `invisible_components_test` checks pickups parented to `run.layers.items` (run column) | — |
| Files: force_menu | Showcase row step / attempt / done | DONE | `force_menu.dart:46-56`; `s3_0_8_force_menu_test.dart:100-103` | — |
| Storage | `showcaseSeen` (bit 7 done), `showcaseAttempt`, `showcaseRuns`, `showcaseDoneAt` | DONE | `storage.dart:70-73, 287-293, 522-525`; Obf keys `Obf.prefShowcase*` | UNVERIFIED: whether they are appended at the END of `kObfStrings` and in `anchor_strings.txt` (§1.4); the a-storage auditor should confirm |
| Tests: plan per step × attempt at 568/711/730 | | DONE | `director_script_test.dart:8-70` | — |
| Tests: 200-seed parity except scripted slots/gaps; gates | | **FIX** | `director_script_test.dart:101-152` also excludes the ±7 headline window and every portal slot, so it does not prove R6 | Tighten after fixing B2.3 |
| Tests: bits persist / A at START | | DONE | `plan_state_test` | — |
| Tests: invisible | | DONE | see B5 | — |
| Tests: starters armed, normal HUD, no FREE on slot | | DONE | `starters_test.dart` | — |
| Tests: portal grab vs miss | | FIX (weak) | see B4 portal | — |
| Tests: FREE once, no `revive_ad`, then ladder incl. versus coins | | DONE | `free_revive_test.dart:94-160` | — |
| Tests: `countsForAchievements` + VERSUS upload | | DONE | `upload_rules_test.dart`, `invisible_components_test` | — |
| Tests: testers done | | DONE | `plan_state_test:244` | — |
| Tests: human-noise bot ≥ 85 % at A=1, 100 % at A=3; perfect bot 100 % of 50 seeds per step | | DONE | `bot_highlights_test.dart:25-31, 90-94` (711 only); green in the orchestrator's suite run | Optional: add 568 |
| Tests: golden FREE heart | | DONE | `free_revive_goldens_test.dart` | — |
| Tests: a production-wiring test | (implied by B1) | **TODO** | `wiring_test.dart` only checks injected seams | Add a test that the production factory builds `ShowcaseShow`, and that a fresh install gets step 1 at START |
| Analytics `showcase_start` | step, attempt | DONE (model) | `showcase_plan.dart:447` | Live only after wiring |
| Analytics `showcase_end` | + hoops, score, highlight, cause, shield_used, revive_used | **FIX** | The model accepts them (`showcase_plan.dart:486-509`), but the `ShowcaseProgress` interface has only `gamesPlayed, hoopsPassed` (`:233-239`), and the game passes only those (`flappy_game.dart:4197-4200`). In production: score 0, cause "missed_hoop", shield/revive 0 | Extend the interface; pass the summary's score, cause, `shieldUsed`, `revivesThisGame > 0` |
| Analytics `showcase_done` | runs, s_since_install, via | DONE (model) | `showcase_plan.dart:537-543` | — |
| Analytics `highlight_seen` | Any ride/comet/FEVER start: id, scripted, run_no, hoop | DONE / FIX on wiring | `analytics_router.dart:436-451` sends it for every run; `ShowcaseShow` also sends it (`showcase_plan.dart:476-481`), so it is sent twice after wiring | Drop the ShowcaseShow copy. `scripted` = "run is a showcase run", not "the item was scripted" (`portal_ride.dart:148` etc.): use the plan's slot match |
| Analytics `ftue_step` showcase_done / run1_highlight | | FIX / DONE | `FtueStep.showcaseDone` (`ftue_tracker.dart:14`) has no caller; `run1_highlight` emitted `analytics_router.dart:446-450` | Call `ftueTracker.step(showcaseDone)` from `_markDone` |
| run_end `showcase` 0–3; `run_fail outcome revive_free`; `fs_showcase` | | DONE | `analytics_router.dart:515, 567, 571-574, 595, 715-716` | — |
| C3 (touches WP-B) | `rate_min_runs` = max(5, showcaseDoneAt + 2) | DONE | `config.dart:1125-1126`, `flappy_game.dart:4243` | — |
| R2 / §1.4 | Showcase is the only lifetime exception; normal runs identical across lifetime inputs | DONE (normal side) | `same_rules_test` uses non-showcase setups (orchestrator run: green) | — |
| §1.4 maxTranslation / addRun / one master | | DONE | the FREE heart reuses `LifeIcons.paintHeart`; scripted pickups in the run column | — |
| §2 run 1 | VERSUS run, Big Hoops 60 s + shield, star trails 2/5, feather 4, portal 7 Cannon, hearts 10/13/16, FREE revive | **FIX** | All correct in the plan, but not live (wiring) | WP-B-1 |
| §2 runs 2/3 | comet 9 + magnet, frenzy 3, bullseye 14; FEVER 5, piece, Space 15 | **FIX** | same | WP-B-1 |
| §2 run 4 / run 6 | Saw from game 4, squeeze from game 6, silent | Out of scope (WP-C) | gates applied in showcase runs too (`run_controller.dart:75-84`) | — |
| O16b | No practice loop | DONE | no loop; the death-before-hoop-0 test | — |
| E1 (raised in #60) | Debug runs never upload | **FIX** (cross-area, WP-E) | `countsForUpload` (`run_controller.dart:149`) has no reader; `flappy_game.dart:4268-4271` submits every run | Guard `versus.submitRun` (and the WP-LB board submit) with `run.countsForUpload`; extend `upload_rules_test` to a finished debug run |

## 3. Open findings from issues (checked in code)

| Issue | Finding | Still present? |
|---|---|---|
| #60 test2 major 1 | Real scripts change unscripted plans beyond the headline windows | Partly: outside ±7 the parity holds (test `director_script_test:101`). Inside ±7 everything is flattened, which is a design deviation (B2.3) |
| #60 test2 major 2 | Bullseye 14 lost during the comet ride | Fixed (`duringRide: true`, `run_director.dart:1072`; spawner `run_spawner.dart:174`). No flown run-level assertion found (UNVERIFIED) |
| #60 test2 major 3 | Debug runs still upload | **Yes**: `countsForUpload` unused |
| #60 test2 major 4 | Out-of-scope test edits | Reverted in build3, per its summary |
| #60 builder1 | "Default planner is still inert" | **Yes** (main finding) |
| #33 test1/test2 | Delete my data after a real restart → legacy done | Yes, by design now (`plan_state_test:323` encodes it). Decide or accept |
| #33 test1 | Queued writes can restore keys after reset | Mitigated: each queued write re-checks the in-memory value (`showcase_plan.dart:555-581`) plus the epoch. OK |
| #33 test1 | Organic highlights not recorded | Fixed (`showcase_plan.dart:452-465`; `plan_state_test:106, 130`); only during showcase runs, which is fine |
| #33 test1 | `showcase_end` missing fields | Model fixed; **the game still passes nothing** (B-analytics FIX) |
| #35 major | Big Hoops determinism test missing | Fixed (#92; `starters_test.dart:95-100`) |
| #35 minor | Portal grab tests call `grab()` directly | **Yes** |
| #35 minor | Comet highlight hoop = spawn index | **Yes** (`comet.dart:84`) |
| #36 major | Six-hoop exemption persists after FREE | Fixed (`revive_ladder.dart:126-130`; test) |
| #36 major | `flappy_game.dart` out of paths | Moot |
| #36 minor | Heart size changed | Compensated (`revive_screen.dart:682-687`); visual UNVERIFIED |
| #42 major | Bot σ not on emitted flaps | Re-done in #94/#117 (a-curve scope); `bot_highlights` green in the orchestrator's run |
| misc | `HighlightStarted` doc says "no component emits it yet" (`run_events.dart:382-383`) | Stale comment; trivial |

## 4. Proposed work packages (in order)

**WP-B-1 Wire the showcase into production** (~2–3 h). PRD B1, B5, O16c, §2 runs 1–3.
- Paths: `lib/game/flappy_game.dart` (constructor: add `ShowcaseShow Function(GameStorage)? showcaseFactory`, or
  build it in `onLoad` after `storage.load()`), `lib/main.dart`, `lib/run/showcase/showcase_plan.dart` (interface),
  `test/p26/showcase/production_wiring_test.dart` (new).
- How:
  - Production builds one `ShowcaseShow(storage, tracker: services.track, secondsSinceInstall: …)` and uses it as
    both plan and progress, only after `storage` has loaded (its constructor reads state).
  - The test harness (`createRunTestGame`) keeps the inert default, so the 4900 existing tests stay unchanged.
  - Decide for FS_E2E/FS_SOAK builds: they must not get a showcase (pass inert when `kE2E || kSoak`), otherwise
    `integration_test/release_e2e_test.dart` flies with shield and Big Hoops.
- Acceptance:
  - A fresh install (`gamesPlayed` 0) gets step 1 A1 at START with Big Hoops 60 s + shield.
  - An install with gamesPlayed ≥ 3 and no keys starts with no plan and `showcaseDoneAt` set.
  - FS_E2E starts have no plan.
  - `flutter analyze` is clean; the existing showcase suites are green.

**WP-B-2 Showcase analytics completion** (~1–2 h). PRD §A table, B analytics. Depends on WP-B-1.
- Paths: `lib/run/showcase/showcase_plan.dart`, `lib/game/flappy_game.dart` (the endRun call only),
  `test/p26/showcase/plan_state_test.dart`, `test/p26/analytics/*`.
- Do:
  - Extend `ShowcaseProgress.onRunEnd` with score, cause, shieldUsed and reviveUsed, and pass them from the run
    summary.
  - Remove the duplicate `highlight_seen` from `ShowcaseShow` (the router owns it).
  - Emit `ftue_step showcase_done` from `_markDone` (inject `FtueTracker`).
  - Make `HighlightStarted.scripted` true only for plan slots, and give the comet its source hoop index.
- Acceptance: a recorded game-level run emits exactly one `highlight_seen` per highlight and a `showcase_end`
  with the real score/cause/shield/revive. `ftue_step showcase_done` is sent once, via all/cap/fast.

**WP-B-3 Showcase course = normal mix (R6/D6)** (~2–4 h). PRD B2 (element set, headline window), R6, D6. Can run in
parallel with WP-B-2; it conflicts with WP-D work in `run_director.dart`.
- Paths: `lib/run/director/run_director.dart` (showcase overlay region ~1020–1090, 1387–1450, the `nextGap`
  showcase part), `test/p26/showcase/director_script_test.dart`.
- Do:
  - Replace the ±7 `_showcasePlain` flattening. Around a highlight, suppress only D6 headline items (other ride
    starts/portals, big bonuses, squeeze warnings, introductions); keep tilt/motion/switch/specials by hoop index.
  - Re-seeded portal theme: use the director's normal theme pick (no repeat of `_lastRide`). Update `_lastRide`
    for scripted portals.
- Acceptance: the 200-seed parity test compares every non-scripted slot (drop the `headline` exclusion; keep only
  scripted slots/gaps, headline-item replacements and re-seeded portal slots). No two consecutive portal rides share
  a theme. Bot tests stay green (≥ 85 % / 100 %).
- If the owner prefers the calm window: record a SPEC.md DEVIATION + PRD note instead (owner decision, not blocking).

**WP-B-4 Run-level showcase tests** (~2 h). PRD B tests. Depends on WP-B-1 (or uses `FixedShowcase`).
- Paths: `test/p26/showcase/grabs_test.dart`, `test/p26/showcase/spawn_flight_test.dart` (new).
- Do:
  - Fly a physical crossing outside the portal ring: the showcase starts the ride; the normal run follows the miss
    rule.
  - Fly steps 1–3 A1 with the autopilot at 568/711 and assert `HoopSpawned`/`PickupSpawned` for every scripted
    slot and gap item, including hearts/star trails after the Cannon ride and the bullseye at 14 during the comet
    ride.
- Acceptance: the tests exist and are green. A scripted item lost to a ride clear fails them.

**WP-B-5 (cross-area, belongs to WP-E E1) Debug runs never upload** (~1 h).
- Paths: `lib/game/flappy_game.dart` (submit block ~4268), `test/p26/showcase/upload_rules_test.dart`.
- Guard `versus.submitRun` (and the WP-LB board submit when it exists) with `run.countsForUpload`.
- Acceptance: a finished debug-forced / god / bot run does not reach `submitRun` or the queue; showcase, Free Fly
  and revive runs do.

Owner decision (not blocking): Delete my data on an install with gamesPlayed ≥ 3 after a restart counts as
legacy-done (current behaviour). Recommend accepting it and noting it in the PRD edge cases.

## 5. Risks / conflicts

- **Test toolchain is broken right now:** `.dart_tool/package_config.json` points at the deleted df4 cache. Nobody
  can run `flutter test --no-pub` until a `flutter pub get` (with `~/flutter`, 3.47.6) is run in the worktree.
- **Wiring blast radius:**
  - If WP-B-1 makes `ShowcaseShow` the constructor default, every test at gamesPlayed 0 changes (shield, Big Hoops,
    scripted items, FREE revive), including `autopilot_test`, goldens and screenshots. Keep the default inert and
    wire only in `main.dart`/`onLoad`.
  - Store screenshot generators and device e2e must stay showcase-free.
- `run_director.dart` is the hotspot shared with WP-D (formations, hazard, calm, D6). WP-B-3 must be sequenced with
  any WP-D director package. The D6 headline window in WP-D and the showcase window should share one
  implementation.
- `flappy_game.dart` endRun (~4185–4275) is touched by WP-B-2, WP-B-5, WP-J levels and WP-LB submits; expect merge
  conflicts.
- The human-noise median gate (`autopilot_test`, red) belongs to the curve, not the showcase. The showcase bot test
  uses the same bot and is green; council D-01 recalibration must not change `flyHumanNoiseBotToDeath` without
  re-running `bot_highlights_test`.
- R2: showcase runs go into versus pools with a shield, Big Hoops and a FREE revive (accepted by the owner, §6).
  Once wired, the first real ghosts from new installs will include them.
