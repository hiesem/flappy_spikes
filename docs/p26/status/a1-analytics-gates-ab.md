# a1 — WP-A analytics, WP-C gates / popup budget / reminders, WP-H A/B, §5 events

Auditor a1-analytics-gates-ab · tree `feat/2.6` @ a57a7fb · 2026-10-26

## 1. Summary

- **WP-A analytics is mostly built and wired in production**: `run_fail` (22 params), `run_end` (25), `run_extra`, the
  hb/gb buckets, no per-pass `perfect_pass`, `PersistedFtueTracker` (default in the game constructor), durable
  `first_meet`, `highlight_seen`, and the 5 user properties are all there. Open: `run_extra.downgraded` is hard-coded 0
  (the director already counts downgrades); the `ftue_step` names `showcase_done`, `level_1/5/10` are never emitted;
  `level` / `lvl_pts_before` / `beat_best_hoop` / `fs_level` are placeholders until WP-J/K; `fs_best_hb` still counts
  debug runs (#90 minor); the names test only covers a hand list of six router events.
- **WP-B is not live in production, so the showcase events never fire**: `FlappySpikesGame` defaults to
  `InertShowcasePlan` / `InertShowcaseProgress` (`lib/game/flappy_game.dart:169-170`) and nothing (main.dart included)
  injects `ShowcaseShow`. So `showcase_start/end/done` never fire, `showcase` is always 0 in `run_fail`/`run_end` and
  `fs_showcase` stays '0'. There are also two latent bugs that only show once it is wired: `highlight_seen` gets sent
  twice, and `showcase_end` sends default score/cause/shield/revive. (This is mainly WP-B's area. It is flagged here
  because it empties the WP-A funnel.)
- **WP-C1 gates are DONE**: saw 3, squeeze 5, all the others 0, squeeze is in `GatesConfig.keys`, the squeeze trigger
  is filtered, there is no forced first meet for saw, and the debug Runs row and `ignoreGates` still work. One weak
  test: the "pure filter" test compares two directors that never run a squeeze.
- **WP-C2 popup budget is partly built.** The `HomeMomentBudget` policy (C2 order, oldest gift first, Star Road once a
  day / never before game 3) is instance-owned and wired for the after-run Home arrival with LEVEL UP / No-Ads /
  rating. The gaps:
  - the **launch Home visit is not budgeted** (No-Ads session offer + catch-up LEVEL UP can both show);
  - the Star Road day is memory-only;
  - STREAK LOST / streak reward / GO TO COLLECT / missions chest / Star Road have no sources yet. That is wave 3/4
    (TODO, depends on G1/G2/G6/WP-LB).
- **WP-C3 is DONE except one rating nit**: reminders #11/#13/#16/#19 are gated on metElements, the 4 bodies match
  texts.html, and the #93 rotation fix is in. The portal `firstPossible` is 12. The rating minimum is `max(5,
  doneAt+2)`, but it is hard-coded to 5, so the `rate_min_runs` tuning key is dead.
- **WP-H is not built** (TODO): no `abArm_v1`, no `Random.secure` draw, no `profiles_test`; `fs_arm` is the constant
  '0'.
- **Tests could NOT be run by me**: `.dart_tool/package_config.json` points every package at
  `~/.local/state/df4/flappy-spikes/cache/…`, which no longer exists (removed with df4). Every `flutter test` fails to
  compile ("Error when reading …/flutter_test.dart"). Statuses below are from code reading plus the issue tester
  verdicts. The orchestrator must run `flutter pub get` before anyone can run tests (I am not allowed to).

## 2. Requirement table

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| A1 | No per-pass `perfect_pass`; counts per run in `run_extra` | DONE | no `perfect_pass` track in lib (`lib/run/items/streak.dart:44` comment); tests `test/run/items/s3_4_streak_test.dart:101`, `test/p26/analytics/run_events_test.dart:238` | — |
| A2-hb/gb | Hoop buckets (12) and games buckets (8) as listed | DONE | `lib/services/analytics_buckets.dart:8-63`; `test/p26/analytics/analytics_buckets_test.dart` | — |
| A2-run_fail | One event per mistake, 22 params, outcome end/revive_ad/revive_coins/revive_free/shield/life | DONE (level param placeholder) | `analytics_router.dart:456-518, 587-604, 608-613`; keys `:80-103`; #29 tester PASS | `level` is hard 0 (`:513`) → wire to the WP-J level (WP-J dep) |
| A2-run_fail emitted from mistakes | via the pipeline's `onResolved` | DONE | `analytics_router.dart:160` | — |
| A2-run_end | Extended fields, ≤ 25 params | DONE (3 placeholders) | `analytics_router.dart:632-665` (25 keys) | `level`, `lvl_pts_before`, `beat_best_hoop` are hard 0/0/−1 (`:662-664`) → WP-J/WP-K |
| A2-run_extra | perfect by tier, ride_hoops, squeezes, max_speed, coins_bonus, formations, downgraded | FIX | `analytics_router.dart:667-676`: `'downgraded': 0` hard-coded, but `RunDirector.downgrades` exists (`run_director.dart:282`); `ride_hoops` counts only *perfect* ride passes (`:346-351`, increment after the `!e.perfect` return) | Send `c.director.downgrades`; count every pass with `e.duringRide`; add asserts in `run_events_test` |
| A2-ftue_step | 14 step names, once per install, `s_since_install` | FIX | bitmask + wall-clock install time `ftue_tracker.dart:96-112`, `storage.dart:479-491`. Emitted: first_tap `flappy_game.dart:1499`, run4_start `:1585`, run1/2/3/20_end `:4201-4210`, run1_highlight / first_saw / first_squeeze / versus_first_end in the router. **Never emitted:** `showcase_done` (no `FtueStep.showcaseDone` caller), `level_1`, `level_5`, `level_10` | Emit `showcase_done` from the showcase done transition (WP-B wiring); emit `level_1/5/10` when WP-J's level-up commits (WP-J dep) |
| A2-showcase_start/end | Params step, attempt / + hoops, score, highlight, cause, shield_used, revive_used | FIX (inert in prod) | Built in `showcase_plan.dart:447, 500-509`, but production uses `InertShowcaseProgress` (`flappy_game.dart:170`). The call site `flappy_game.dart:4197-4200` passes only gamesPlayed + hoopsPassed, so score=0, cause='missed_hoop', shield_used=0, revive_used=0 always | Wire `ShowcaseShow` in production (WP-B); pass the real score, cause, shield and revive use from the run summary/state |
| A2-showcase_done | Once; runs, s_since_install, via | FIX | `showcase_plan.dart:536-542`; `s_since_install` falls back to `storage.playtimeSeconds` when `secondsSinceInstall` is not injected (it is not in production) | Use the install-time clock (`storage.installAtMs`), as `PersistedFtueTracker` does |
| A2-highlight_seen | id, scripted, run_no, hoop when a ride/comet/FEVER starts | FIX | Router sends it for every `HighlightStarted` (`analytics_router.dart:436-452` → `ftue_tracker.dart:115-125`); `ShowcaseShow.onHighlight` sends it **again** in showcase runs (`showcase_plan.dart:476-481`). Latent today (showcase inert) | Remove the copy in `showcase_plan.dart`; keep the router as the only sender; add a test that one highlight = one event in a showcase run |
| A2-first_meet | element, hoop, games, forced, survived; durable across restart | DONE | `analytics_router.dart:198-239, 343-375, 415-429`; `ftue_tracker.dart:127-209`; Opus tester PASS on #90 (49 tests) | — (see §3 for the forced-provenance note) |
| A2-level_up / level_reward_claimed / best_beaten | WP-J / WP-K | TODO (other WPs) | not in lib | Built with WP-J (J10) / WP-K |
| A3 | `setUserProperty` try/caught on GameServices, no-op default | DONE | `game_services.dart:701-706` | — |
| A3-fs_gb / fs_showcase | at run end | DONE (fs_showcase stuck at 0 while WP-B is inert) | `analytics_router.dart:706-717` | — |
| A3-fs_best_hb | lifetime best hoops bucket | FIX (minor) | `analytics_router.dart:701`: `max(storage.bestHoops, s.hoopsPassed)` for **every** run, including non-counting debug/god runs. The save is guarded (`:702`); the property is not. Existing installs start at `bestHoops` 0 (no migration) | Use `s.hoopsPassed` only when `c.run.countsForAchievements`; add a test with a debug run above the best |
| A3-fs_level | plain level number (WP-J) | FIX (dep) | `analytics_router.dart:705` reads the old 10-rank `storage.playerLevel` | Switch to the WP-J `lvlIndex` (WP-J) |
| A3-fs_arm | the arm | TODO | constant `'0'` at `analytics_router.dart:718` | WP-H: read `abArm_v1` |
| A-storage | `ftueSteps` bitmask, appended obf key | DONE | `tool/gen_obf_strings.dart:142`, `anchor_strings.txt:32`; extra keys `installAtMs`, `bestHoops`, `pendingFirstMeets` appended `:149-151` | Add `installAtMs` / `pendingFirstMeets` to the PRD Appendix key table (WP-I) |
| A-test names | every event name snake_case ≤ 40, ≤ 25 params | FIX | `test/p26/analytics/analytics_names_test.dart:39-58` checks only a hard list of 6 router names | Scan every `track('…'` / `_track('…'` literal in `lib/` (as the p23 analytics audit tests do) and check name rules + param count per call site |
| A-test run_fail / ftue / perfect | listed tests | DONE | `run_events_test.dart`, `ftue_tracker_test.dart`, `first_meet_regressions_test.dart` (#29, #90 PASS) | — |
| A4 | GA4 dimensions/metrics, BigQuery EU export, 14 months, signals off, $5 alert (O10, O43) | OWNER | console; `RESUME-2026-10-26.md` "GA4 custom definitions" pending | Orchestrator does it in the console with the owner signed in; add `fs_*` user-property registration |
| C1-gates | gate table: egg/pair/feather/puzzle/piggy/jar/fever/lucky_spin/spring/switch 0, saw 3, squeeze 5 | DONE | `tuning_defaults.dart:336-374`; `gates_config.dart:38` (squeeze key) | — |
| C1-ungated | tilt / moving / Δy ungated, by hoop | DONE | not in `GatesConfig.keys`; `unlocks_test.dart:129-150` | — |
| C1-squeeze pure filter | draws still made, only the trigger is skipped | DONE (code) / FIX (test) | `squeeze.dart:172-184, 251`: first roll always made, start skipped while closed. Test `unlocks_test.dart:151-165` compares two `RunDirector` courses that never run a squeeze (the directors are identical by construction), so it proves nothing about the live run | Replace it with a live-run test: same seed at gamesPlayed 4 vs 5, layout-stream slot plans equal up to the first squeeze warning; later differences only from squeeze/calm/headline |
| C1-no forced first meet saw/squeeze | | DONE | `elements.dart:49` (saw forced=false), `squeeze` event kind; `unlocks_test.dart:60-83` | — |
| C1-debug | Runs: N row + ignoreGates | DONE | `force_menu.dart:39-48, 110`; `flappy_game.dart:1560` | — |
| C1-tests | 200 seeds × 60 hoops; gamesPlayed 0 D1 starts; no UI at gate open; autopilot gamesPlayed 0/10 × 568/711 | DONE (UNVERIFIED run) | `test/p26/gates/unlocks_test.dart:85-127, 129-150, 256-283, 287-318` | Rerun after pub get |
| C2-policy | one big popup per Home visit, priority order, gifts oldest first, Star Road ≤ 1/day, never in runs 1–3 | DONE (policy) | `lib/game/home_moments.dart:96-181` (instance state, #91 fix) | — |
| C2-after-run visit | budget reset on each Home arrival after a run; live LEVEL UP / No-Ads / rating | DONE (UNVERIFIED run, #91 never reviewed) | `flappy_game.dart:1037-1056, 4626-4650`; `2779`, `2902`, `2933`, `3012` | Rerun `test/p26/home/home_moments_test.dart` |
| C2-launch visit | the first Home visit (launch / resume) is a Home visit too | FIX | `_homeVisitBudgeted` is false until the first post-run arrival (`flappy_game.dart:1014-1018, 1034`), so at launch `_visitActive` is false and `tryShow` opens everything (`home_moments.dart:121-125`): the No-Ads session offer and the catch-up LEVEL UP can both show. Wave-3 STREAK LOST "first Home visit of each day" mostly *is* the launch visit | Begin a budgeted visit at launch / session start with all live candidates (keep the 2.5 order inside the one slot); test: launch with an owed LEVEL UP + No-Ads due → one popup |
| C2-LEVEL UP catch-up | | FIX (minor) | `levelUpCatchUp` is true only for a level gained *this run* (`flappy_game.dart:1046-1047`). A LEVEL UP owed from earlier loses to No-Ads (`_select` picks noAds, `tryShow(levelUp)` is refused) | Request it whenever `pendingLevelUp != null` (WP-J rewrites this anyway) |
| C2-Star Road once a day | | FIX (wave 3) | `_starRoadShownDay` is memory-only (`home_moments.dart:103, 135`), so it resets on app restart | Persist the last shown day (new key) when the Star Road source lands |
| C2-wave-3 sources | STREAK LOST, streak reward, GO TO COLLECT (+gift opening), missions chest, Star Road | TODO (wave 3/4) | `HomeVisitRequests` fields exist, but `_beginHomeVisit` fills none of them (`flappy_game.dart:1042-1055`) | **Depends on G2 (streak + restore), G1 (missions chest), WP-LB client (gifts), G6 (Star Road).** Also: STREAK LOST pending offer takes the first visit of each day (O49), never in runs 1–3 (policy only guards Star Road by `gamesPlayed >= 3`), chest opens on the next Home visit (O32) |
| C2-exempt | achievement toast, mission ticks, system sheets, results climb | DONE | not routed through `homeMoments` | — |
| C2-test home_moments_test | one popup per visit, order, chest/Star Road never together, Star Road ≤ 1/day | DONE (policy level) / TODO (wave-3 live cases) | `test/p26/home/home_moments_test.dart` | Extend in wave 3 with real sources |
| C3-portal | `firstPossible` 40 → 12 | DONE | `elements.dart:50-51` | — |
| C3-reminders gated | #11/#13/#16/#19 skipped while not in metElements | DONE | `reminders.dart:432-436, 556-561`; #93 rotation fix, Opus PASS | — |
| C3-bodies O42 | #2, #13, #16, #17 bodies | DONE | `reminders.dart:107-171` = `texts.html` ROUND 21 rows | — |
| C3-rating | `rate_min_runs` → max(5, showcaseDoneAt+2) | FIX (minor) | `config.dart:1125-1126` hard-codes 5; `Config.ratingMinRuns` (`rate_min_runs`) is now unused in lib. While the showcase is unfinished (`doneAt` null) the minimum is 5, even though the showcase can run until game 6 | `max(Config.ratingMinRuns, (doneAt ?? …) + 2)`; decide: hold the rating while the showcase is still active (doneAt null and gamesPlayed < showcase_max_games) |
| C-analytics | `first_meet` silent | DONE | see A2-first_meet | — |
| H1 | `abArm_v1` drawn with `Random.secure` at first launch, stored (obf key appended) | TODO | no `abArm` anywhere in lib/tool | Build (wave 2) |
| H2 | arm reported as `fs_arm` | TODO | constant '0' | read the stored arm |
| H3 | arms may differ only on showcase_*, gate_saw/squeeze, ads_grace_*, ads_interstitial_*, rate_min_runs, ui_unlock_*, mission targets; never curve_/point_/spawn_/squeeze_/ride_/coin_/revive_/hazard_/calm_/level_ | TODO | — | Arm table (one arm = defaults) + override layer on `TuningValues` limited to the allow-list |
| H4 | `profiles_test` checks both lists | TODO | — | New test |
| H5 | single arm in 2.6, no remote switch (O11) | TODO (trivially satisfied by not building a switch) | no remote config path | assert arm table length 1 in test |
| §5 FTUE funnel / run_fail table / survival / retention by fs_level, fs_gb | dashboards | OWNER (data) + depends on the A fixes | — | GA4/BigQuery setup (A4) |
| §5 economy earned/spent/bought | lifetime coin keys | TODO (WP-F, other auditor) | — | — |
| §5 levels / fallback share | `level_reward_claimed.fallback` | TODO (WP-J) | — | — |
| §5 leaderboard opens / climbs / gifts lost to ghosts | | TODO (WP-LB client/UI) | server `lbSettle` side done in M0 (other auditor) | — |
| §5 streak restore restored / ad-fail share; missions done; weekly course share; beat-best per run | | TODO (G1/G2/G5/WP-K) | — | Each WP must add its event; add them to the names test |
| O2 | ad timing unchanged; popup budget stays | DONE | grace/gap keys unchanged `tuning_defaults.dart:378-382` | — |
| O3 | system sheets at launch, outside the budget | DONE | not routed through `homeMoments` | — |
| O10 / O43 | GA4/BigQuery console settings | OWNER | — | console |
| O11 / D7 | no remote switch; lifetime-only arms | TODO (WP-H) | — | — |
| O15 / O16e | only saw/squeeze gated; silent | DONE | see C1; `unlocks_test.dart:256-283` | — |
| O42 | false reminders #2/#13/#16/#17 fixed | DONE | see C3 | (N7 keep / N8 drop are G3, not audited here) |
| O47 / O49 / O54 / O68 / O75 / O32 | STREAK LOST top + daily, GO TO COLLECT after streak popups / one per visit / oldest first, Star Road first visit after claimable, chest next visit | TODO (wave 3/4; policy ready) | `home_moments.dart:147-167` | see C2-wave-3 sources |

## 3. Open findings from the issues, re-checked

- **#31 / #90**:
  - The tracker is wired: `flappy_game.dart:202-204` creates `PersistedFtueTracker`. Fixed.
  - The `fs_best_hb` lifetime best is fixed, but it still counts debug runs (**still present**,
    `analytics_router.dart:701`).
  - `first_meet.survived` per encounter: fixed (`:364-375, 415-429`).
  - Real install time: fixed (`storage.dart:479-491`, with a local-midnight migration).
  - Durable pending first meets: fixed (`ftue_tracker.dart:127-209`, flushed at `flappy_game.dart:779`).
  - Forced provenance: builder3 said it was not done, but the Opus test3 PASS says forced-flag tests exist. In code,
    `forced` = `setup.forced ∨ plan.forced` (`:205-206`). A pickup forced by first-meet has `hoop == null`, so it falls
    back to `setup.forced` only. **Possibly still present for naturally-placed vs first-meet-forced gap pickups:
    UNVERIFIED.**
- **#90 minors (brief)**:
  - (a) Delete-my-data check for the 5 original keys: **still present**. `test/p26/m1/skeleton_test.dart:66-75` checks
    the in-memory fields but asserts `prefs.containsKey(...) == false` only for `pendingFirstMeets`. Production
    `resetVersusData` does remove all 5 (`storage.dart:1142-1146`).
  - (b) Real `s_since_install` restart assertion: **still present**. `ftue_tracker_test.dart:92-96` sends the restarted
    tracker's event to a throwaway `AnalyticsSpy()` and never checks its value.
  - (c) `fs_best_hb` only from counting runs: **still present** (above). The restart test for `fs_best_hb` itself is
    now real (`user_props_test.dart:84-134`).
- **#38 / #91**:
  - The budget is now instance-owned and called on after-run arrivals. The #38 majors are fixed.
  - #91 was merged on a red verify and was **never reviewed** (#116 not started).
  - New finding: the launch/resume visit is unbudgeted (C2-launch visit).
  - New finding: the LEVEL UP catch-up loses to No-Ads when the level was not gained this run.
  - New finding: the Star Road day is memory-only.
  - New finding: `_visitActive` never resets, so outside Home `show()` is refused after a shown moment until the next
    arrival. Today this only hits the debug "force No-Ads" path; it matters if wave 3 opens popups from other screens.
- **#40 / #93**: the rotation fix is in, and Opus PASS says 11 regressions fail before / pass after. **No open
  finding.**
- **#56 / #85**: #56 was merged with a red verify and no tester. #85 fixed the fallout. The gate values and code
  match the PRD now. The open item is the weak pure-filter test (C1). The squeeze/Firefly autopilot reds are not on
  the current known-red list; per the brief they now pass, UNVERIFIED by me.
- **#23**: the skeleton wiring is fine. `Config.ratingMinRunsFor` ignores the `rate_min_runs` key (new finding).

## 4. Proposed work packages (one Sol builder each)

1. **A-FIX1 — analytics correctness (≈2 h)**. PRD A2/A3. Paths: `lib/run/items/analytics_router.dart`,
   `test/p26/analytics/*`, `test/p26/m1/skeleton_test.dart`.
   - `run_extra.downgraded = c.director.downgrades`.
   - `ride_hoops` counts every ride pass.
   - `fs_best_hb` uses the current run only if it counts.
   - Fix the #90 test minors: prefs-key removal for the 5 keys; the restarted tracker's `s_since_install` = elapsed
     seconds since the original install.
   - Accept: new tests fail on HEAD and pass after.
2. **A-FIX2 — analytics names/limits audit test (≈1–2 h)**. PRD A2 tests. Path: `test/p26/analytics/analytics_names_test.dart`.
   - Parse every `track('name', {...})` / `_track(` / `logEvent` literal in `lib/`.
   - Assert snake_case, ≤ 40 characters, ≤ 25 keys per call site, and user-property names ≤ 24 characters.
   - Allow-list dynamic calls explicitly.
   - Accept: it catches a planted 26-param map.
3. **B-WIRE-AN — showcase analytics once WP-B is live (≈1–2 h; depends on the WP-B production wiring, another
   auditor's WP)**. Paths: `lib/run/showcase/showcase_plan.dart`, the `flappy_game.dart` run-end call (~:4197).
   - Remove the duplicate `highlight_seen`.
   - Pass score / cause / shield_used / revive_used to `onRunEnd`.
   - `showcase_done.s_since_install` from `installAtMs`.
   - Emit `ftue_step showcase_done`.
   - Accept: a showcase run 1 with a portal sends exactly one `highlight_seen`; `showcase_end` carries the run's real
     score and cause; a done transition sends `showcase_done` + `ftue_step{name: showcase_done}`.
4. **C2-LAUNCH — budget the launch / resume Home visit (≈2–3 h)**. PRD C2, O3. Paths: `lib/game/flappy_game.dart`
   (`_startSession`, `_beginHomeVisit`, `openLevelUpPopup`), `lib/game/home_moments.dart`,
   `test/p26/home/home_moments_test.dart`.
   - Start a budgeted visit at launch and resume, with the owed LEVEL UP (any pending) and the No-Ads candidates.
   - Keep system sheets outside the budget.
   - Accept: launch with an owed level + No-Ads due → exactly one popup, LEVEL UP first; the next visit shows No-Ads.
   - Do this before wave 3.
5. **C3-RATE — rating minimum from tuning (≈0.5–1 h)**. Path: `lib/game/config.dart`, `test/p26/m1/skeleton_test.dart`,
   `test/p23/s23_rating_prompt_test.dart`.
   - `max(ratingMinRuns, doneAt + 2)`.
   - While the showcase is unfinished, require `gamesPlayed ≥ max(ratingMinRuns, showcase_max_games + 1)`. That
     needs a small editor call: "PRD silent; it follows the C3 intent".
6. **C1-TEST — real squeeze-gate determinism test (≈1–2 h)**. Path: `test/p26/gates/unlocks_test.dart` only.
   - Live run, same seed, gamesPlayed 4 vs 5, forced early squeeze time.
   - Assert the slot plans are identical up to the warning hoop, and later differences only within squeeze, calm or
     headline-attributable slots. Keep the director-level check.
7. **H-ARMS — WP-H baked arm plumbing (≈3–4 h; wave 2)**. PRD WP-H, A3, T14. Paths:
   - new `lib/run/config/ab_arms.dart`;
   - `lib/game/storage.dart` (`abArm_v1`, appended to `tool/gen_obf_strings.dart` + regenerate + `anchor_strings.txt`);
   - `lib/run/config/tuning_values.dart` (arm overlay);
   - `analytics_router.dart` (`fs_arm`);
   - new `test/p26/ab/profiles_test.dart`.

   Requirements:
   - Draw with `Random.secure` at first launch; one arm (0) in 2.6.
   - The overlay may only touch allow-listed prefixes.
   - Delete my data keeps the arm. This is an editor call; the PRD does not say.

   Acceptance:
   - `profiles_test` fails if any arm sets a forbidden key or a key outside the allow-list;
   - the arm survives a restart;
   - `fs_arm` = the stored arm.
8. **C2-WAVE3 — extend the popup budget with the wave-3/4 sources (≈3–4 h; depends on G2 streak + restore, G1
   missions chest, the WP-LB client gift list, G6 Star Road; and on C2-LAUNCH)**. Paths: `flappy_game.dart`
   `_beginHomeVisit`, `home_moments.dart`, `home_moments_test.dart`. Requirements:
   - STREAK LOST first on the first Home visit of each day while an offer is pending (O47, O49, O73), never in runs 1–3;
   - streak reward;
   - GO TO COLLECT, one box per visit, oldest first, after the streak popups (O54, O68);
   - missions chest on the next Home visit (O32);
   - Star Road on the first visit after a tier becomes claimable, ≤ 1/day, persisted day key, never with the chest
     (O37, O75).

   Accept: the PRD `home_moments_test` items with real sources and normal Home transitions.
9. **Dependent, built in their own WPs** (list for the plan, not separate packages):
   - `fs_level`, `run_fail.level`, `run_end.level/lvl_pts_before`, `ftue_step level_1/5/10` → WP-J;
   - `beat_best_hoop`, `best_beaten` → WP-K;
   - §5 events for missions / streak restore / board opens / climbs / weekly course → G1 / G2 / WP-LB / G5.

   Each must add its events to the A-FIX2 names test.

Owner/console (not code):
- A4 / O10 / O43 GA4 dimensions + `fs_*` user properties, BigQuery EU export, 14-month retention, signals off, $5
  alert.

## 5. Risks / conflicts

- **The test environment is broken.** `.dart_tool/package_config.json` references the deleted df4 cache
  (`~/.local/state/df4/flappy-spikes/cache/...`). Until `flutter pub get` runs, no auditor or builder can run
  `flutter test`, and every "DONE (tests)" above is from code plus the issue verdicts.
- **`flappy_game.dart` is a hotspot.** C2-LAUNCH, C2-WAVE3, B-WIRE-AN, the WP-B production wiring and WP-J's level-up
  all edit `_beginHomeVisit` / the run-end block (~:1000-1060, ~:4180-4260). Run them sequentially or give them narrow
  disjoint regions.
- **Delete my data and analytics.** `resetVersusData` clears `ftueSteps` and the showcase keys
  (`storage.dart:1125-1146`). After a Delete, the FTUE funnel steps fire again with a large `s_since_install`, which
  pollutes dashboard 1. The PRD Appendix says Delete clears all 2.6 keys except the streak, which agrees with the code.
  That needs either a dashboard filter or an editor note. It also does not clear `bestHoops` / `installAtMs`, which
  looks consistent with "local progress" but is unstated.
- **The showcase is inert in production** (WP-B). Until it is wired, the showcase KPIs in §5 (highlight 1 seen in run
  1, showcase done ≥ 70 %) cannot be measured. The C3 rating rule also degenerates to 5.
- **The squeeze gate and the timing stream.** While gated, the squeeze hold/gap rolls on `rng.timing` are never made,
  so later timing rolls (Big Hoops / hourglass durations, puzzle bonus; `run_director.dart:334-362`) differ between
  gamesPlayed 4 and 5. Slot plans (layout stream) are unaffected, which fits the PRD's "random streams stay put" only
  for the layout stream. That is acceptable, but the C1-TEST should spell it out.
