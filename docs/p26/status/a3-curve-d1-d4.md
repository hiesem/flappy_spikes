# a3-curve-d1-d4 — WP-D D1–D4 (+ C3 spawn rows) and Appendix tuning keys

Auditor: a3-curve-d1-d4 · tree feat/2.6 @ a57a7fb · 2026-10-26

## 1. Summary

- D1/D2 data is in place and matches the PRD: opening, perfect band, tilt and moving curves, `tilt_rows`, the six Δy rows in points (dyRef = min(band, 540)), the motion rows, the align/45° keys, `dy_hard_factor`, the early pool, the switch/saw/moving/portal first hoops, the saw weight curve and saw-in-squeeze from 100. Tests cover them, and the D2 tests I ran pass.
- D3 hazard budget (`hazard_budget.dart`) and D4 calm (`calm_schedule.dart`) are built and wired into `run_director.dart`. The 200-seed ceiling oracle in `curve_ceiling_test.dart` checks them, and it passes per the orchestrator's run.
- **Owner decision 2 (squeeze surcharge) is followed** in code (`hazard_budget.dart:270-283`), in the test oracle (`curve_ceiling_test.dart` ~l.225) and in a SPEC DEVIATION (`SPEC.md:1931`).
- **Owner decision 3 (R2) is NOT followed as worded.** The decision says the drawn Δy is identical at 711/730 *and centre rows use the full band*. The code instead caps the centre course at a "portable" 623 pt band anchored to the top tooth (`layout_config.dart:82`, `layout_sampler.dart:52-104,124,135`). On a 730 pt screen the course does not use the bottom 19 pt and sits about 9.5 pt above centre. The full-band `limits()` is effectively dead in production. `same_rules_test` asserts the stricter final-centre identity. SPEC.md:1912-1916 records the portable band, not the #118 note. #118 never ran. The owner needs to accept one of the two.
- **Main regression (new finding):** #127 added `unsafeLanding = _calm.dueAt(hoop+1) || _hazard.budgetAt(hoop+1) < 4` (`run_director.dart:1130-1131`). It drops every non-forced spring before hoop ~49 in every run, not only in squeezes. Measured with 200 seeds, hoops 0–149:
  - springs before hoop 50: 2.6 has **5 (568) / 7 (711)**, 2.5 (d0a72c2) had **167 / 329**;
  - total springs in hoops 0–149: 503 / 729 against 692 / 1189.
  - This is the cause of the red `s3_23_spring_test` (3 springs found, needs > 5). It also breaks the PRD rule "other specials keep 2.5 tuning".
- Smaller gaps:
  - the `calm_every` / `calm_after` keys are declared but never read (CalmSchedule hard-codes the values);
  - `run_extra.downgraded` is hard-coded to 0;
  - after a revive the player gets 1 plain slot plus 3 calm slots (4 in total, not 3 replacing the plain one);
  - a strong tilt clamped to 15° still takes the approach sign (#50 minor, still present);
  - the `spawn_tables.json` fixture still has the 2.5 band, tilt and motion rows;
  - stale LayoutBand tilt/moving fields and the `movingTypes20/45` / `allMotionTypesFrom` aliases are still there;
  - D1 "80 slide speed step" contradicts the D2 motion table (PRD conflict).
- Appendix: every D, C1 and B1 key exists with the PRD value. All wave-2+ keys (J, G, F6, WP-LB, Star Road) are missing (TODO, outside wave 1).

Tests I ran (via flock): s3_23_spring, layout_d2, hazard_budget, calm_schedule, spawn_tables_d2, same_rules, wp_d_wire, tables_mirror: 73 pass, 1 fail (s3_23 spring, "Expected > 5, Actual 3 at 568"). The probe that compares 2.6 and 2.5 ran on a scratch copy of the tree (`scratchpad/a3/repo`, `scratchpad/a3/r25`). I did not re-run curve_ceiling (5 min per variant); its status is the orchestrator's.

## 2. Requirement table

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| D.goal | One curve for every run, showcase included (R2/R6) | DONE | same_rules_test 'R2 same seed has the same rules…' passes (games 6/500, best, level 0/31/36, mode, noAds) | — |
| D1.1 | Height variation from hoop 3 | DONE | `layout_config.dart:27-34` row 3; tables_mirror_test | — |
| D1.2 | Tilt ≤15° from hoop 10 | DONE | `curve_tilt` [9,0],[10,.30]; `tilt_rows` 10_* (`tuning_defaults.dart:175-182,398-400`); curve_ceiling asserts tilt≥10 | — |
| D1.3 | Switch from 15 | DONE | `spawn_switch.from` 15 (`tuning_defaults.dart:245`), `elements.dart` switchRing 15; spawn_tables_d2_test | — |
| D1.4 | Δy steps at 20 / 40 / 65 / 100 | DONE | `layout_config.dart:35-66` | — |
| D1.5 | Moving (slow rails) from 25 | DONE | `curve_moving` [24,0],[25,.15]; motion row 25 rail 100, 22–28 pt/s (`layout_config.dart:129-134`) | — |
| D1.6 | Saw from 30 (gamesPlayed ≥ 3) | DONE | `spawn_saw.from` 30, `elements.dart` saw 30, `gate_saw` 3; unlocks_test | — |
| D1.7 | Squeeze #1 at 25–40, headline wait | see D5/D6 auditor | — | — |
| D1.8 | 20–30° aligned tilts from 50 | DONE | `tilt_rows` 50_*; `alignedTilt` (`layout_sampler.dart:287-296`); curve_ceiling asserts ≥20° ⇒ i≥50, aligned, \|Δy\|≥40 | — |
| D1.9 | 45° from 60 | DONE | `tilt_rows` 60_45; curve_ceiling asserts i≥60 | — |
| D1.10 | Horizontal/diagonal slides from 70 | DONE | motion row 70 (`layout_config.dart:141-151`); cramped slide <90 → no motion (`layout_sampler.dart:346-348`) | — |
| D1.11 | **Slide speed step at 80** | DEFER? | The D2 motion table has no step at 80 (70–89 and 90+ are both 30–39; the speed step is at 120). Code follows D2 | Owner/PRD editor: delete the D1 row "80" or add an 80 row to D2 |
| D1.12 | Orbit and rock from 90 | DONE | motion row 90; curve_ceiling asserts orbit/rock i≥90 | — |
| D1.13 | 100: Δy row, bigger 45° share, saw in squeeze | DONE | row 100; `tilt_rows` 100_45 25; `_specialInSqueezeFrom` saw 100 (`director_tables.dart:~398`); tables_mirror_test | — |
| D1.14 | 150: moving + 30° tilt | DONE | `tiltCap` 30 from 150 (`layout_sampler.dart:235-245`); curve_ceiling asserts the rendered angle ≤15/30 | (formations: D7 auditor) |
| D1.15 | Intros ≥5 hoops apart / one dimension at a time | DONE (data) | row starts 3/10/15/20/25/30/40/50/60/65/70/90/100 | — |
| D2.speed | `curve_speed` unchanged | DONE | `tuning_defaults.dart:135-139` | — |
| D2.open | `curve_opening` new keyframes | DONE | `tuning_defaults.dart:141-157` match PRD exactly | — |
| D2.band | `point_perfect_band` 0–40 unchanged + [50,11.8]…[150,10]; Big Hoops ×1.5 | DONE | `tuning_defaults.dart:59-75` | — |
| D2.tilt | `curve_tilt` [[9,0],[10,.30],[49,.35],[50,.50],[100,.60],[150,.65]] | DONE | `tuning_defaults.dart:175-182` | — |
| D2.rows | `tilt_rows` magnitudes | DONE | `tuning_defaults.dart:398-415`, read at `layout_sampler.dart:269`; layout_d2_test 'tilt magnitudes follow the row weights' | Remove the duplicate `LayoutConfig.tiltRows` and the stale `LayoutBand.tiltWeights/tilt/moving` values (`layout_config.dart:19-75`); they are not used for decisions and only cause confusion |
| D2.sign1 | ≤15°: random sign from its own draw | DONE | `layout_sampler.dart:281` | — |
| D2.sign2 | ≥20°: sign follows the approach (higher → negative) | DONE | `alignedTilt` `dy.sign*mag`, approachDy = y − prev (`run_director.dart:1942,2152`) | — |
| D2.sign3 | \|Δy\| < 40 → clamp to 15° | FIX (minor) | `layout_sampler.dart:292-294`: a strong tilt clamped to 15° still takes `dy.sign` when dy≠0 (#50 minor finding, still present). The test covers only dy = 0 (`layout_d2_test.dart:183`) | After the clamp, keep the tilt's own random sign when the final magnitude is ≤15°; test with 0 < \|dy\| < 40 |
| D2.45 | `tilt45_extra_opening` +6 on 45° rings | DONE | `run_director.dart:1279-1282,2155-2158`; curve_ceiling asserts the opening | — |
| D2.mov | `curve_moving` new keyframes | DONE | `tuning_defaults.dart:159-167` | — |
| D2.movtilt | Moving ring ≤15° before 150, ≤30° aligned from 150 | DONE | `maxBaseTilt` includes the motion's own angle; curve_ceiling asserts tilt + swing ≤ 15/30 | — |
| D2.dy | Δy rows × min(band,540), centre × band; max 270 (711) / 240 (568) | FIX | Δy correct (`layout_sampler.dart:162-186`, rows `layout_config.dart:18-67`). **Centre uses `min(band,623)` anchored at the top tooth**, not the full band (`layout_sampler.dart:76-83,124`). See R2 | Owner choice (see §5): either implement decision 3 (full-band centres; assert the *drawn* Δy identity and that the edge clamp only moves out-of-band centres) or approve the portable-band DEVIATION and record it |
| D2.dyhard | `dy_hard_factor` 0.85 × max after moving / ≥30° tilt | DONE | `layout_sampler.dart:160-167,185,205-207`; layout_d2 'hard follow-up clamps only draws above 0.85' | — |
| D2.pool | Early pool starTrail/bullseye/nothing 1:1:1 | DONE | `director_tables.dart:~420`; tables_mirror_test; spawn_tables_d2 'never a tilted ring at hoops 4–9' | — |
| D2.switch | `spawn_switch.from` 15, firstPossible 15 | DONE | above | — |
| D2.saw | saw from 30, firstPossible 30, `spawn_saw_weight` [[30,14],[60,20],[100,26]], `weight_from_45` retired | DONE | `tuning_defaults.dart:274-279,427-431`; `director_tables.dart:308`; no `weight_from_45` left in lib/test | (The object still carries `'weight': 14`, unused by the saw; harmless) |
| D2.moving | `movingRing.firstPossible` 25 | DONE | `elements.dart:41` | — |
| D2.sawsq | Saw during a squeeze only from 100 | DONE | `director_tables.dart` `_specialInSqueezeFrom`; spawn_tables_d2 test | — |
| D2.special | `spawn_special_chance` unchanged | DONE | `tuning_defaults.dart:208-215` | — |
| D2.motion | Motion rows 25/35/70/90 (+120 speed cap 34–42) | DONE | `layout_config.dart:128-178`; layout_d2 'motion rows own their type, travel, and speed ranges'; swing speed from the row (#50 major fixed) | Remove the dead aliases `movingTypes20/45`, `allMotionTypesFrom` (`layout_config.dart:180-192`, `director_tables.dart:175-176,260-263,384-385`), which the PRD says are *replaced* |
| D2.ceil | Ceiling numbers at 150: 187.5, opening 70, band ±10, tilt 65 % (45° = 25 %), moving 58 % ≤42 pt/s, Δy ≤270, hazard 5.5 | DONE | the keyframes above; `LayoutConfig.motionSpeedCap` 42 | — |
| D2.phys | Every element ≤4.5 taps/s with a clean window ≥20 pt on the natural path | UNVERIFIED | curve_ceiling checks a geometric window ≥15 level / ≥35 at slope ±0.5, not taps/s or the 20 pt natural-path window | Optional: add a taps/s check to the autopilot ceiling test (D7 auditor area) |
| C3.portal | `portal.firstPossible` 12 | DONE | `elements.dart:52`; tables_mirror_test | — |
| C3.json | `test/fixtures/spawn_tables.json` updated with the tables | FIX (minor) | the fixture still holds the 2.5 bands (from 10, signed tilt weights, moving chances); the mirror test asserts constants instead | Update the fixture's bands / tilt_rows / motion rows to D2 and make tables_mirror_test read them from the json |
| C.spring (R2 "other specials keep 2.5") | Spring keeps 2.5 tuning (from 6) | **FIX (major, regression)** | `run_director.dart:1130-1131` `unsafeLanding … || _hazard.budgetAt(hoop + 1) < 4` drops every non-forced spring before hoop ~49 in every run. Probe: springs <50 = 5/7 in 200 runs against 167/329 in 2.5; `s3_23_spring_test` red ("Expected > 5, Actual 3 at 568") | Restrict the guard to the case it was written for (a landing that falls in a squeezed slot while budget < 4, or a due calm) and make s3_23 green; keep curve_ceiling squeeze=true green |
| D3.cost | Cost table (saw 2, switch 1.5, spring/pair/train .5, tilt ≤20 .25 / 30 1 / 45 1.5, rail/swing 1, other motion 1.25, Δy>p90 +1, squeeze +1, rewards/rides 0) | DONE | `hazard_budget.dart:19-76` reads `hazard_costs`; hazard_budget_test 'cost table covers every element…'; independent oracle in curve_ceiling | — |
| D3.budget | `hazard_budget` curve over the last 4 slots incl. the current one | DONE | `hazard_budget.dart:17,273-288` (#44 major on the five-slot window fixed); tests 'ledger sums only the last four…', 'oldest cost expires…' | — |
| D3.down | Downgrade order motion → tilt ≤15 → Δy p90 → normal | DONE | `hazard_budget.dart:134-223` and director completion `run_director.dart:1180-1233`; downgrade tests | Small code smell: `run_director.dart:1228-1229` falls back to `normal.copyWith(centreY: planned.centreY)` (restores the un-downgraded Δy) when even a normal does not fit; check that this is unreachable, or clamp instead |
| D3.forced | Forced slots exempt but counted | DONE | `allows`/`downgrade` return early on forced; `add` always records; test 'forced slots are never changed but their cost enters the ledger', wp_d_wire 'forced slots are counted but exempt' | — |
| D3.sq | Owner decision 2: squeeze +1 counts like a forced slot; other costs downgraded; own cost 0 while budget <4 | DONE | `hazard_budget.dart:270-283`; oracle `curve_ceiling_test.dart` (costs − surcharges ≤ budget; cost ≤ 1 when budget < 4); SPEC.md:1931-1945 DEVIATION | — |
| D3.field | `SlotPlan.hazardCost` | DONE | `plans.dart:327,376,418` | — |
| D4.slot | Calm slot = normal, no motion, tilt ≤10°, Δy ≤ median, opening on the curve | DONE | `_calmSlot` `run_director.dart:1862-1902` (tilt 0); curve_ceiling calm asserts | — |
| D4.items | Gap items / fun pickups preferred in calm gaps | DONE (untested) | `run_director.dart:3014` weight ×3 for non-big items on calm slots | Add a test (calm gaps have a higher item share) |
| D4.revive | After a revive: 3 slots, *replacing* the single plain slot | FIX (minor) | `onRevive` starts calm at `_i` (`run_director.dart:368-375`), but the spawner still turns the planned-ahead slot plain (`run_spawner.dart:173-182` → `plainSlot`), so the player gets 1 plain + 3 calm. Only the pure director is tested (wp_d_wire) | Make the planned-ahead revive slot calm slot 1 (built with `_calmSlot`, calm flag) and give 2 more; or document it as a DEVIATION. Add a game-level test |
| D4.sq | After a squeeze ends: 2 | DONE | `squeeze.dart:345` → `onSqueezeEnded` (`run_director.dart:405`) | — |
| D4.ride | After a ride ends: 2 | DONE | `portal_ride.dart:881`, `comet_ride.dart:406,423` → `onRideEnd` → `_calm.onRideEnded` | — |
| D4.periodic | 3 slots, first at 30–34, ×1.2, cap 55 (≈32, 68, 111, 163, 218) | DONE | `calm_schedule.dart:8-35,90-96`; calm_schedule_test; curve_ceiling schedule ±4 | — |
| D4.gap | ≥12 apart; a revive calm always happens | DONE | `calm_schedule.dart:72-88` (revive force); test 'a revive always calms…' | — |
| D4.reset | Any calm or ride resets the periodic timer | DONE | `_resetPeriodicAfter` in `_start` and `onRideStart`; test 'a calm or ride resets the periodic timer' | — |
| D4.sqwarn | No squeeze warning starts inside a calm | DONE | `allowsSqueezeWarning` (`run_director.dart:395-399`, `squeeze.dart:183`); test | — |
| D4.det | Calm deterministic (#46 major) | DONE | seeded default `_defaultTimingSeed` (`calm_schedule.dart:7`); test 'no-argument schedule is deterministic' | — |
| D4.keys | `calm_every` / `calm_after` tuning objects drive the schedule | FIX (minor) | keys declared (`tuning_defaults.dart:459-472`) but never read; `calm_schedule.dart:8-15` hard-codes the same numbers | Read them through `TuningValues` (as HazardBudget does); add a tuning test |
| D.tests1 | curve_ceiling_test (200 seeds × 568/711/730 × 400 slots, ± squeeze; all listed checks) | DONE (per orchestrator) | test exists and covers Δy ≤270, alignment, 45° allowance, moving tilt, budget, calm schedule, intro hoops, clean window, determinism; the 3 squeeze=true entries pass (BRIEF) | Prune them from `scripts/known_red_tests.txt` |
| D.tests2 | same_rules_test fairness incl. R2 at 711/730 | DONE with caveat | passes (ran). Arm: WP-H not wired, so only arm 0 (comment in the test). The R2 test asserts the final-centre identity, which needs the portable band (see D2.dy) | Re-shape it according to the owner's R2 choice |
| D.tests3 | Update s1_hoop_curve, s14_perfect_band, s3_0_2_layout_ramp, tables_mirror, s3_17_squeeze, baked_tuning, s0_live_tuning_defaults | DONE | each was touched in 2.6 (git log: 1/1/2/3/1/4/4 commits); green per orchestrator | — |
| D.tests4 | `leaderboard_max_test` passes unedited | DONE | `test/protection/leaderboard_max_test.dart` has 0 commits since d0a72c2 | — |
| D.analytics | `run_fail` fields (tilt, motion, Δy, hazard, calm, formation) | DONE | `analytics_router.dart:80-96,485-510` | — |
| D.analytics2 | `run_extra.downgraded` | FIX | hard-coded `'downgraded': 0` (`analytics_router.dart:675`); the director has a `downgrades` counter (`run_director.dart:280`) | Report the run's real downgrade count |
| D.docs | SPEC/ARCH DEVIATION notes | DONE except R2 | SPEC.md:1898-1983 | Fix the R2 note to match the owner's choice; also document the spring guard once it is fixed |
| App.D | Appendix D keys (`curve_*`, `point_perfect_band`, `tilt_rows`, `tilt_align_*`, `tilt45_extra_opening`, Δy/motion rows, `dy_ref_band`, `dy_hard_factor`, early pool, `spawn_switch.from`, `spawn_saw`, `spawn_saw_weight`, firstPossible, `hazard_budget`, `hazard_costs`, `calm_every`, `calm_after`, `headline_window/wait`, `formation_every`) | DONE (values) | all present with PRD values in `tuning_defaults.dart:134-478`; `calm_*` not read (see D4.keys); `dy_ref_band` / `dy_hard_factor` read via `run_config.dart:367,370`, but `LayoutConfig.dyRefBand/hardHoopDyFactor` duplicates exist (`layout_config.dart:78,85`) | Remove the LayoutConfig duplicates or assert they are equal |
| App.C1 | `gate_*` values (egg/pair/feather/puzzle/piggy/jar/fever/spin/spring 0, saw 3, squeeze 5) | DONE | `tuning_defaults.dart:336-374` | — |
| App.B1 | `showcase_max_games` 6, `showcase_fast_hoops` 40 | DONE | `tuning_defaults.dart:480-482` | — |
| App.rate | `rate_min_runs` 5 applied as max(5, showcaseDoneAt+2) | DONE (minor) | `config.dart:1125-1126` hard-codes 5 instead of reading `rate_min_runs` | Use `ratingMinRuns` in the max |
| App.ads | `ads_*` unchanged | DONE | `tuning_defaults.dart:378-382` | — |
| App.F6 | `ui_unlock_games` 3 | TODO | not in lib | wave F |
| App.J | `level_points`, `level_coins`, `level_items`, `level_eternal_*`; retire `level_rewards` | TODO | none present; `level_rewards` still at `tuning_defaults.dart:116` | wave J |
| App.E4 | `kBestBrackets` (+ ts mirror) | DONE | `lib/versus/brackets.dart:6`, `functions/src/brackets.ts` | — |
| App.G | `mission_rewards`, `mission_chest_coins`, `streak_rewards`, `weekly_rewards`, `streak_restore_coins`, `starroad_*`; `streak_freeze_max` removed | TODO | none present (`streak_freeze_max` correctly absent) | waves G |
| App.LB | `lb_results_min_games` 3 / `lb_results_wait_ms` 4000 / `lb_queue_cap` 30 | TODO / UNVERIFIED | not found in lib or `functions/src/schema.ts` (the client `VersusConfig.queueCap` is 12, a different queue) | WP-LB auditor to confirm |
| App.mirror | Tuning mirror tests (baked_tuning, s0_live_tuning_defaults, tables_mirror) | DONE | updated in 2.6, green | Extend them when the TODO keys land |

## 3. Open findings from the issues (still present)

- #50 minor: a strong tilt clamped to 15° takes the approach sign (`layout_sampler.dart:294`). **Present.**
- #50 major "centre ranges use the full band": fixed in `limits()`, but production uses `portableLimits()` (623 pt cap), so at 730 centres still do not use the full band. **Present in a different form** (R2 conflict). The layout_d2 test 'centre limits use the full band above the design height' exercises the unused `limits()` path, so it is false comfort.
- #118 (R2 drawn-Δy test + SPEC note + screenshot paths): **never built** (no builder comments). R2 is solved differently (portable band). For the screenshot generator paths, see the other auditor or check `test/screenshot_generator_test.dart`.
- #127 tester: "spring landing before squeeze entry" — builder2 "fixed" it with the global `budgetAt(hoop+1) < 4` guard, which removed natural springs before hoop 50 → **new regression, s3_23 red**.
- #44 majors (five-slot window, zero-cost rewards): fixed. #46 majors (headline clear, calm determinism): calm fixed; headline is the D6 auditor's.
- #113 / #114 (reviews of #86 / #95 / #96): never run. I checked the D3/D4 parts of #95 (window, zero-cost, calm determinism): they hold, with tests. #86's target tests are green per the orchestrator except s3_23.

## 4. Proposed work packages (in order)

**WP-a3-1 Spring regression (must, ~2 h)**
- PRD: R2 "other specials keep 2.5", §3.23, D3 × O18 (decision 2).
- Paths: `lib/run/director/run_director.dart` (~1120-1150, spring reservation), `test/run/hoops/s3_23_spring_test.dart` (no loosening), a new `test/p26/curve/spring_rate_test.dart`.
- Change: drop `|| _hazard.budgetAt(hoop + 1) < 4` as a global condition. Downgrade a spring only when (a) its landing slot is a due calm, (b) the landing slot will be inside a squeeze window (or a pending warning) while budget < 4, or (c) `allowsFollowing` fails.
- Acceptance:
  - s3_23 green;
  - springs before hoop 50 over 200 seeds at 711 ≥ 50 % of the 2.5 baseline (329), at 568 ≥ 50 % of 167;
  - curve_ceiling (all 6 variants), formations_wire_*, wp_d_wire, same_rules green;
  - SPEC D3 × O18 paragraph updated.

**WP-a3-2 R2 owner choice + tests (must, 1–3 h; needs the owner's pick, see §5)**
- Option A (decision 3 literal):
  - centre limits use the full band (`limits`) in `nextCentre`, `_calmSlot`, `plainSlot`, spring and formation placement;
  - `same_rules_test` R2 asserts the *drawn* Δy (expose `LayoutSampler.lastDrawnDy` or a debug hook) for 200 seeds × 200+ hoops;
  - a new test shows the edge clamp moves a centre only when it would leave the band;
  - SPEC note "R2 holds for the drawn Δy; centres use the full band" (#97/#118).
- Option B: keep the portable 623 pt band, write a SPEC DEVIATION that names decision 3 and why, and fix the misleading layout_d2 test so it checks `portableLimits`.
- Paths: `layout_sampler.dart`, `run_director.dart` (placement helpers), `layout_config.dart`, `test/p26/curve/same_rules_test.dart`, `test/p26/curve/layout_d2_test.dart`, SPEC.md.
- Acceptance: curve_ceiling + formations tests green at 730.

**WP-a3-3 D4/D3 polish (should, ~2 h)**
- Paths: `calm_schedule.dart`, `run_director.dart` (onRevive / revive plain slot), `run_spawner.dart:173-182`, `analytics_router.dart:675`, `layout_sampler.dart:287-296`, tests in `test/p26/curve/`.
- Items:
  - (a) CalmSchedule reads `calm_every` / `calm_after`;
  - (b) the revive gives exactly 3 calm slots, with the planned-ahead plain slot as calm slot 1 (game-level test with `FlameTester`: revive → next 3 hoops `calm`, the 4th not forced calm);
  - (c) `run_extra.downgraded` = the director's downgrade count for the run (test in `test/p26/analytics/run_events_test.dart`);
  - (d) ≤15° after the clamp keeps the random sign (test with 0 < |dy| < 40);
  - (e) calm-gap item preference test.
- Acceptance: the named tests, plus curve_ceiling / wp_d_wire / same_rules green (determinism: (d) changes plans, so re-check curve_ceiling).

**WP-a3-4 Table hygiene (could, ~1–2 h)**
- Remove the stale `LayoutBand.tilt/tiltWeights/moving` values (or set them to the D2 values), `LayoutConfig.tiltRows`, `dyRefBand`, `hardHoopDyFactor` duplicates, and the `movingTypes20/45` / `allMotionTypesFrom` aliases.
- Update `test/fixtures/spawn_tables.json` bands / tilt_rows / motion rows to D2, and make tables_mirror_test compare the json against code.
- `ratingMinRunsFor` uses `rate_min_runs`.
- Paths: `layout_config.dart`, `director_tables.dart`, `game/config.dart:1125`, `test/fixtures/spawn_tables.json`, `test/run/config/tables_mirror_test.dart`.
- Acceptance: analyze clean, mirror / baked / live-tuning tests green, no plan changes (same_rules / curve_ceiling identical).

**Housekeeping (orchestrator):** prune the 3 `curve_ceiling … squeeze=true` lines from `scripts/known_red_tests.txt`.

## 5. Risks / conflicts

- **R2 decision 3 vs the code (owner):** the code meets "Δy identical at 711/730" by *not* using the full band at 730 (the portable 623 pt band, anchored at the top). That contradicts "centre rows use the full band". Option A changes plans at 730 only, but it touches many placement helpers (calm, plainSlot, spring, formations all use `portableLimits` / `courseRefBand`), so there is a risk to the curve_ceiling and formation gates. Option B is cheap but needs an explicit owner DEVIATION.
- **PRD internal conflict:** D1 "80 Slide speed step" vs the D2 motion rows (no change at 80). Needs a PRD edit.
- WP-a3-1 and WP-a3-2 both edit `run_director.dart` placement and reservation code; run them in sequence (1 then 2). WP-a3-3(b) touches `run_spawner.dart`, which the showcase/revive (WP-B) auditor may also touch (free revive).
- Changing the spring guard can move the human-noise median and the squeeze=true ceiling sweep; run both after WP-a3-1.
- Test environment: at about 09:40 the repo's `.dart_tool/package_config.json` pointed at the deleted df4 pub cache. The orchestrator has fixed it since; my later runs used the fixed tree.
