# a4-curve-d5-d7 — WP-D D5 / D6 / D7, the human-noise bot, the 3 red tests

Auditor: Opus (read-only). Tree: feat/2.6 @ a57a7fb. Tests were run in a **scratch copy** of the worktree
(`scratchpad/a4/p26`, `flutter pub get --offline`), because the worktree's `.dart_tool/package_config.json`
pointed into the deleted df4 cache when I started (the orchestrator fixed it later). The 2.5 measurements
used a second scratch copy built from `git archive d0a72c2` (`scratchpad/a4/p25`). Nothing in the repo was touched.

## 1. Summary

- **D5 squeeze schedule: done.** The timing keys are unchanged from 2.5. A revive keeps the squeeze index, and the
  test for that is real. There is no motion and no tilt above 15° before hoop 150 in a squeeze. Two small test gaps remain.
- **D6 headline window: built and wired** for ride, squeeze, big bonus and first-meet. The "introduction" claim covers
  only the saw. A released item may fire inside the 8-hoop window after its 5-hoop wait (this is a reading of the PRD; SPEC records it).
- **D7: all 6 formations and the mix chapters are built and wired, and their tests pass.** Two reading problems remain.
  The slalom alternates ±110–130 pt around a centre, which is a 220–260 pt Δy per step. "Sync rails" share one absolute
  phase, so "one line passes all" is not guaranteed when the bird arrives.
- **Red test 1+2, the human-noise median: the bot is still defective. This is not only the course.** At σ = 0 the
  shipped `HumanNoiseBot` dies on hoops 4–7 on seeds where the plain autopilot survives, so its forecasts go stale.
  I prototyped a closed-loop fix that reproduces the autopilot exactly at σ = 0 (data in §6). With that fixed bot,
  σ 90 ms gives a median of about 6–13 on **both** 2.5 and 2.6 (31 seeds, 120 s). That is the council's "2.5 also far
  below 40" branch, so we need a calibrated σ: about 50 ms gives about 40 on 2.5, and 2.6 then scores ≥ 2.5 (57/55 at
  45 ms, 40/39 at 60 ms).
- **Red test 3, s3_23 spring: the root cause is found.** #127 (14b6765) added a blanket
  `_hazard.budgetAt(hoop + 1) < 4` to `unsafeLanding` at `run_director.dart:1130-1131`. It removes every
  non-forced spring before hoop 50: 3 springs in 40 seeds × 60 slots at 568, where the test needs more than 5.
  Removing the clause turns the spring test green, but `curve_ceiling squeeze=true` then fails at 711 and 730.
  A proper fix needs a squeeze look-ahead (WP D-SPRING below).
- **Test-list "Update" items:** all 7 named files were edited in 2.6. `leaderboard_max_test.dart`
  (`test/protection/`) is unedited (0 commits since d0a72c2).

## 2. Requirement table

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| D5.1 | `squeeze_first` [25,40] unchanged | DONE | `tuning_defaults.dart:184` = 2.5 `:101` | — |
| D5.2 | `squeeze_hold` [5,10] unchanged | DONE | `tuning_defaults.dart:186` | — |
| D5.3 | `squeeze_gap` [25,45] unchanged | DONE | `tuning_defaults.dart:188` | — |
| D5.4 | Tilt in a squeeze ≤ 15° before hoop 150 | DONE | `layout_sampler.dart:235-245` `tiltCap(squeeze:)`; `layout_d2_test.dart:224` "D2 tilt is limited in motion and early squeeze slots" | Optional: add this to the curve_ceiling oracle as well (it does not check squeeze tilt today) |
| D5.5 | Depth unchanged (50/45/40/35 %, ≥ 230 pt open) | DONE | `squeeze_config.dart` has no diff vs d0a72c2 | — |
| D5.6 | No motion inside a squeeze | DONE | `layout_sampler.dart:307`; forced moving blocked at `run_director.dart:758`; chapter motion skips it at `:1847` | Optional oracle assert |
| D5.7 | A revive keeps the squeeze index | DONE | `squeeze.dart:526-529` no longer does `index++`; `s3_17_squeeze_test.dart` ~:570 `expect(s.squeeze.index, 0)` | `wp_d_wire_test.dart:163` "WP-D5 a revive keeps the squeeze index" is **vacuous** (`rollSqueezeAt` ignores `index`). Delete it or rewrite it against `SqueezeFeature` |
| D5.8 | Index passed in squeeze.dart:111/213/331 and revive_rules.dart:69 | DONE (inert) | `squeeze.dart:115,221,343`, `revive_rules.dart:69-73`; `rollSqueezeAt`/`rollSqueezeHold` never read `index` (`run_director.dart:325-345`) | Fine, since timing is unchanged (O18). Mark the param "reserved" in a doc comment |
| D6.1 | ≤ 1 of {ride start, squeeze warning, big bonus, first meet, in-run intro step} per 8 hoops | FIX (minor) | `headline_window.dart`; claims at `run_director.dart:1343-1358` and squeeze `:395-402`; `wp_d_wire_test.dart:185` covers ride/squeeze/bonus only | The "introduction" claim covers **only the saw** (`:1355`). Moving (25), switch (15) and the tilt/Δy steps claim only as first-meet when a first meet happens. Decide whether the D1 rows (switch 15, moving 25, saw 30) count as "introduction steps" and claim them. Add first-meet and introduction to the D6 test |
| D6.2 | A due item waits up to 5 hoops | DONE (interpretation) | `headline_window.dart:11-24`, `_headlineDue` `run_director.dart:2487-2498`. After 5 hoops it fires even inside the window (`_forcedHeadlineAt`). SPEC.md:1953 records this | Orchestrator: accept the reading (a forced item resets the window) |
| D7.1 | Formations from hoop 150, every 12–20 hoops | DONE | `formation_every` [12,20] at `tuning_defaults.dart:478`; `run_director.dart:1510-1566`; `formations_wire_schedule_test.dart:53` | — |
| D7.2 | "never one of the last 2" | DONE (interpretation: no repeat of the previous two shapes) | `formations.dart:62-70` | — |
| D7.3 | All within the hazard budget | DONE | tilt wave pre-check via `allowsSequence` (`:1528-1546`); other shapes go through `_recordSlot` downgrade; `formations_wire_schedule_test.dart:136` | Downgrades can strip a shape (e.g. a stair's tilt). Acceptable |
| D7.4 | ≥ 310 pt between hoop planes | DONE | `RunConfig.spacing` 310; templates use `offset * spacing`; `formations_test.dart:144` | — |
| D7.5 | Stairs: 4 hoops, +70–90 each, aligned 15° | DONE | `formations.dart:182-198`; flipped to face the band `run_director.dart:~1660` | Template `hazardCost: 1.25` is hard-coded; check the director recomputes it (`_withCost`) — the curve_ceiling oracle checks plan.hazardCost, so it does |
| D7.6 | Slalom: 4 upright, alternating ±110–130 pt | FIX? (reading) | `formations.dart:200-212`: offsets ±step **around a centre**, so Δy per step = 2·step = 220–260 pt, then scaled to the row max Δy (`run_director.dart` `_placeFormation` slalom branch) | Orchestrator decides. The natural reading is "each step ±110–130 pt". If so, use the centre ±step/2 (Δy 110–130). The 220–260 version runs at the Δy ceiling every step and probably feeds the human-bot deaths after 150 |
| D7.7 | Tilt wave −30/−15/0/+15/+30, aligned | DONE | `formations.dart:214-238` path 0,−1,−2,−1,0 × `tilt_align_min_dy`; #48/#58 majors fixed (`formations_test.dart:80-102`) | — |
| D7.8 | Sync rails: 3–4 rails in phase, "one line passes all" | FIX | `formations.dart:240-258`: same `MotionSpec.phase` for all; `RailMotion._tri` poses on absolute `runClock` (`hoop_motion.dart:114`, `moving_rings_feature.dart:41`). Rings 310 pt apart are reached ~1.5 s apart, the period is 4·halfTravel/speed ≈ 2.9–5.3 s, so at arrival they sit at different offsets. halfTravel 30–45 > the safe slack (~opening/2 − r − rim) | Offset each ring's phase by its arrival delay: `phase_k = phase − k·spacing/(cruise(start)·period)`. Test: with the bird at cruise, ring k's offset at its plane-crossing time is equal for all k (±2 pt) |
| D7.9 | Saw gate: saw between two upright hoops, clean line through the middle | DONE | `formations.dart:260-276` | — |
| D7.10 | Switch chain: 3 switches alternating sides | DONE | `formations.dart:278-318`, `_withoutRepeatingSwitch` | — |
| D7.11 | Mix chapters every 50 past 150, saw → switch → moving, equal budget | DONE | `Formations.chapterAt/mixWeightsAt` (`formations.dart:126-168`), wired in `run_director.dart:1795-1860`; `formations_test.dart:176` | — |
| D7.12 | Shapes 4–6 tuned with the human-noise bot | TODO | The bot is broken (see §3), so no tuning has happened | After WP D-BOT: run the bot from hoop 150 and record the per-formation death share |
| D7.T1 | `curve_ceiling_test` (200 seeds × 568/711/730 × 400, ±squeeze), all 9 bullets | DONE (passes) / FIX (gaps) | `test/p26/curve/curve_ceiling_test.dart`; 6/6 sweeps pass (see §6 test run) | Gaps: no squeeze-tilt ≤ 15° assert; no "no motion in squeeze" assert. "Calm on schedule ±4" uses `inInclusiveRange(12,59)` plus ±4 — OK. The harness never calls `onSqueezeWarning`, so D4 "warning not inside calm" and D6 are not exercised here |
| D7.T2 | `same_rules_test` R2 matrix (gamesPlayed 6/500, best, level 0/31/36, mode, No-Ads, arm, metElements) | DONE except arm | `same_rules_test.dart:25-92`; passes | Arm is not an input yet (WP-H). Add it when WP-H lands. Note: `playerLevel` is set but the level-31/36 **runtime level** (WP-J) is not wired, so re-check after WP-J |
| D7.T3 | R2 Δy identical at 711/730 | DONE | `same_rules_test.dart:95-111` (asserts the final centre Δy, stricter than decision 3); passes | — |
| D7.T4 | autopilot ceiling gate: start 150/250 × 568/711 × 3 seeds ≥ 40 hoops | DONE | `autopilot_test.dart:59-88`; green in the orchestrator's full run | — |
| D7.T5 | Human-noise bot median ≥ 40 from hoop 0 at gamesPlayed 10 | FIX (red) | `autopilot_test.dart:92-139`; medians 7/6 | WP D-BOT + D-CAL (§4) |
| D7.T6 | Update the 7 named tests | DONE | p24/s1_hoop_curve, p23/s14_perfect_band, s3_0_2_layout_ramp, tables_mirror, s3_17_squeeze, audit17/baked_tuning, p231/s0_live_tuning_defaults: all changed since d0a72c2 (`git log d0a72c2..HEAD`) | Content not re-audited line by line (a different auditor owns D2) |
| D7.T7 | `leaderboard_max_test.dart` passes unedited | DONE | `test/protection/leaderboard_max_test.dart`: 0 commits since d0a72c2 | — |
| D7.F | Files: `formations.dart` new, `plans.dart` `.calm/.hazardCost/.formation`, SPEC/ARCH notes | DONE | files exist; SPEC.md:1925-1977 | SPEC.md:1938-1945 documents the spring "budget 4" blanket and the 568 pre-calm squeeze-band hack. Rewrite after D-SPRING |
| §0.3.4 | Shared human-noise bot σ 90 ms, 10 % extra | FIX | `lib/run/debug/human_bot.dart` | Defective scheduler (§3.1). Rewrite: WP D-BOT |
| Dec.1 | Calibrate against 2.5 (council D-01) | TODO | not done; my measurement is in §6 | WP D-CAL |
| Dec.2 | Squeeze +1 counts like forced; other costs downgraded | DONE | `hazard_budget.dart` `_fitsCost`/`_surcharges` (#127); oracle `curve_ceiling_test.dart:196-217`; SPEC.md:1931 | — |
| Dec.3 | R2 on the drawn Δy; centres use the full band | DONE | see D7.T3 | — |

## 3. Root causes of the 3 red tests

### 3.1 Human-noise median (2 tests): the bot is broken, *and* σ 90 ms is too harsh for either course

- **Defect (verified).** `HumanNoiseBot.shouldFlap` (`human_bot.dart:~176-205`) plans one base flap at
  `now + nextFlapDelay()` + jitter. It then **does not re-forecast while that base is pending**: `rebasePendingBase`
  runs only after an *extra* flap. So the bot fires on a forecast that goes stale as the controller and state change.
  Proof with jitter σ = 0 and extra = 0, 21 seeds, gamesPlayed 10, 60 s cap:
  - shipped bot: 568 dies at 6/4/7 hoops (seeds 5, 8, 18, missedHoop); 711 dies at 4.
  - plain `flyRun` autopilot: same seeds, **no deaths** (all time out at 27–35 hoops).
- The simple fix "rebase every frame" is worse. A positive jitter is re-added to a moving target, so the flap never
  fires (median 0–1 at σ 30 ms, all spikes).
- **Working model (prototyped in the scratch copy):** draw jitter `j` once per base decision, then re-ask the autopilot
  every frame from the real state.
  - If `j ≥ 0`: tap when the autopilot has wanted to flap (`nextFlapDelay() == 0`) for ≥ `j` s.
  - If `j < 0`: tap as soon as the fresh `nextFlapDelay() ≤ −j`.
  - An extra flap fires `extraFlapGap` (80 ms) after a base with 10 % chance.
  - Every emitted tap calls `autopilot.replanAfterFlap()` and clears `j`.

  At σ = 0 this reproduces the autopilot **exactly** (identical score vectors, §6). Core code (about 30 lines;
  `drawJitter()`/`drawExtra()` are `_gaussian()*jitterSigma` and `_random.nextDouble() < extraFlapChance` on the scheduler):
  ```dart
  final delay = autopilot.nextFlapDelay();
  if (delay == null) { _wantSince = null; return false; }
  _jitter ??= scheduler.drawJitter();
  final j = _jitter!;
  var fire = false;
  if (delay == 0) { _wantSince ??= now; fire = now - _wantSince! >= j; }
  else { _wantSince = null; fire = j < 0 && delay <= -j; }
  if (!fire) return false;
  // record offset j, maybe schedule extra at now+0.08, clear _jitter/_wantSince, replanAfterFlap()
  ```
- **With the fixed bot, σ 90 ms gives a median of 6 (568) / 10 (711) on 2.6 and 13 / 9 on 2.5** (31 seeds, 120 s cap).
  So 2.5 is also far below 40. Per council D-01, keep σ 90 as a **baseline comparison** and add a 40-hoop gate for a
  calibrated σ. Calibration on 2.5 (31 seeds, 120 s cap, the test's own cap): see §6.

### 3.2 `s3_23_spring_test` "room for its 240 pt jump" (Expected > 5, Actual 3 at 568)

- **Cause:** #127 (commit 14b6765, builder2 round 2) changed the spring commit check in `_recordSlot`. In
  `run_director.dart:1130-1131` it is now:
  ```dart
  final unsafeLanding =
      _calm.dueAt(hoop + 1) || _hazard.budgetAt(hoop + 1) < 4;
  ```
  `hazard_budget` reaches 4 only at hoop 50 ([25,3],[50,4]), so every non-forced spring before hoop 50 is turned into a
  normal hoop. The test only looks at 60 slots, so springs almost vanish.
- **Why it was added:** a spring at slot k whose 240 pt landing (Δy > p90 → +1) falls on the first **squeezed** slot
  breaks Decision 2's rule "below budget 4 a squeezed slot carries no cost beyond its surcharge". The director can't
  know that slot k+1 will be squeezed, so builder2 banned springs below budget 4 altogether.
- **Verified:** with only the `budgetAt < 4` clause removed (scratch copy), `s3_23_spring_test` passes. But
  `curve_ceiling squeeze=true` fails at 711 and 730: seed 52 slot 35 (the first squeezed slot) has
  `cost 2.0 > 1` at `curve_ceiling_test.dart:215`. 568 still passes.
- **Fix (WP D-SPRING):** give the director a one-slot squeeze look-ahead and downgrade the spring only when its
  landing will be squeezed **and** `budgetAt(hoop+1) < 4`.
  - `run_controller.dart:319-341` already computes the window from `sq.nextAt − squeezeWindowLead − lead`.
    Add `DirectorContext.squeezeNextSlot` (true when the window opens within the next slot's lead, i.e. one
    `RunConfig.spacing / cruise` seconds later).
  - The curve_ceiling harness then sets it at `i % 40 == 29` (and `i == 34`).
  - Alternative with no runtime plumbing (weaker): treat a committed spring landing like a forced slot, exempt but
    counted. That contradicts Decision 2's wording and needs an orchestrator/owner OK.
  - Keep `_calm.dueAt(hoop + 1)` (that clause is legitimate: a calm slot needs Δy ≤ median).

## 4. Proposed work packages (in order)

**D-SPRING — restore springs before hoop 50** (≈ 2 h)
- PRD refs: §3.23, D3 × O18 (Dec. 2).
- Paths: `lib/run/director/run_director.dart` (spring block ~1118-1150), `lib/run/director/director_context.dart`,
  `lib/run/run_controller.dart:~319-345`, `test/p26/curve/curve_ceiling_test.dart` (harness flag only), SPEC.md:1938-1945.
- Work:
  - Add `squeezeNextSlot` to `DirectorContext` (default false; `.open(..., squeezeNextSlot:)`) and compute it in
    `RunController`.
  - Replace `_hazard.budgetAt(hoop + 1) < 4` with
    `(ctx.squeezeNextSlot || ctx.squeezeWindow) && _hazard.budgetAt(hoop + 1) < 4`.
  - Rewrite the SPEC paragraph.
- Accept:
  - `s3_23_spring_test.dart` all green.
  - `curve_ceiling_test.dart` 6/6 green at unchanged thresholds.
  - `formations_wire_recovery_test.dart` and `same_rules_test.dart` green.
  - New test: a spring planned with `squeezeNextSlot` and budget < 4 is downgraded; without it, springs appear from hoop 10.

**D-BOT — make HumanNoiseBot a real closed-loop bot** (≈ 2–3 h)
- PRD refs: §0.3.4, D7 tests, B (showcase bot test at 506).
- Paths: `lib/run/debug/human_bot.dart`, `test/p26/bot/human_bot_test.dart`.
- Work: implement the §3.1 model and keep the public API (`flapTimes`, `baseFlapOffsets`, `extraFlaps`,
  `flyHumanNoiseBotToDeath`). Make σ and the extra chance constructor parameters, with defaults of 0.09 / 0.1.
- Accept:
  - New test "σ 0 / extra 0 reproduces `flyRun`": same hoops for seeds 0–20 at 568/711 (60 s).
  - The emitted base offsets over ≥ 500 flaps have mean ≈ 0 ± 10 ms and sd 90 ± 10 ms.
  - The extra rate is 10 ± 3 %.
  - The showcase bot tests that use the bot stay green (`test/p26/showcase/bot_highlights_test.dart`; re-check the
    ≥ 85 % / 100 % numbers at line 506 of the PRD).
- Risk: this changes what the showcase bot test measures (owned by another area).

**D-CAL — calibrate against 2.5 and rewrite the median gate** (≈ 3 h; depends on D-BOT; needs owner sign-off on the DEVIATION)
- Measure 2.5 **out of tree** (the 2.5 course cannot be rebuilt in-tree: director +1548 lines, LayoutConfig rows in code):
  1. `git archive d0a72c2 | tar -x -C $SCRATCH/p25`, then `flutter pub get --offline` there (same pubspec.lock).
  2. Copy HEAD's `lib/run/debug/autopilot.dart` (only additive: `replanAfterFlap`, `nextFlapDelay`, train preview;
     it compiles on 2.5) and the D-BOT `human_bot.dart` into it. Remove the `HighlightStarted` case
     (`run_events.dart` has no such event in 2.5).
  3. Run a test file like `autopilot_test.dart:92-139`: same seeds 0–N, `prefs {'gamesPlayed': 10}`,
     `flyHumanNoiseBotToDeath(maxSeconds: 120)`, sweeping σ.
  4. Use ≥ 41 seeds per height for the medians (variance is large; see §6), and use separate seeds to validate.
- Then in-tree (`test/autopilot_test.dart`):
  - (a) Keep the σ 90 / 10 % test, but assert `median(2.6) ≥ baseline25_σ90 − tolerance`, with the baseline numbers
    from step 3 as constants and a comment naming the d0a72c2 measurement.
  - (b) Add the "after 10 games ≈ 40" gate with the calibrated σ (≈ 50 ms; the exact value is the one where 2.5's
    median is ≈ 40 at both heights): `median(2.6) ≥ 40`.
  - (c) Add a SPEC.md DEVIATION (§0.3.4 / D7 tests, council D-01) and list it for the owner.
- Accept: both tests green at 568 and 711. The numbers are recorded in SPEC. The command sequence for re-measuring is
  in a comment or in `docs/p26/BUILD_NOTES.md`.
- Owner: the DEVIATION (σ for the 40-gate) needs confirmation (council D-01 already says so).
- Note: if the calibrated σ fails on 2.6 but passes on 2.5, the 2.6 course is harder than 2.5 in hoops 0–40. The
  PRD says hoops 0–40 must be no harder, so that goes back to the D2 owner, not the gate.

**D-SYNC — sync rails passable on one line** (≈ 1–2 h)
- Paths: `lib/run/director/formations.dart` (`_syncRails`), `test/p26/curve/formations_test.dart`.
- Work: offset each ring's phase by its arrival time (see D7.8).
- Accept: in a FlameTester run from `startHoopIndex` at a forced syncRails, each ring's offset at the moment the bird
  crosses its plane differs by ≤ 4 pt. The autopilot from 150/250 stays green.

**D-SLALOM — confirm the slalom step size** (≈ 1 h; orchestrator decision first)
- If the PRD means Δy 110–130: `centreY: y + (even ? -step/2 : step/2)` and update `formations_test.dart:62-78`.
- Accept: the formations tests and the D7 autopilot stay green.

**D-TESTS — small test gaps** (≈ 1–2 h; after D-SPRING)
- Add to the curve_ceiling oracle: squeeze slots have `motion == null` and |tilt| ≤ 15 before 150.
- Add first-meet / introduction headlines to the D6 wire test (`wp_d_wire_test.dart:185`).
- Replace the vacuous `wp_d_wire_test.dart:163`.
- Fix `Formations.fourSlotHazardCost` for shapes with fewer than 4 slots (it returns 0, #48 minor still present at
  `formations.dart:~172-184`): pad, or use partial windows.
- Decide on D6.1 introduction claims (claim `'introduction'` at the D1 rows: switch 15, moving 25, saw 30).

**D-SHAPES — tune shapes 4–6 with the bot** (≈ 2 h; after D-BOT and D-CAL)
- Run the calibrated bot from hoops 150/200/250 (≥ 30 seeds) and record the deaths per formation id. Shapes whose
  death share is far above their slot share get softer parameters within the budget.
- Report-only acceptance plus a test asserting no formation's bot-death share exceeds 2× its slot share (soft).

Also remove the `_prepareForNextCalm` hack if D-SPRING makes it unnecessary (`run_director.dart:948-1018`, #127). At
568 it moves every pre-calm slot into the deepest-squeeze band (inset index 3) **even when no squeeze is coming**,
which changes the 568 course for a test artefact. Check whether `curve_ceiling 568 squeeze=true` still passes without
it once the spring is fixed. If it does not, limit it to `ctx.squeezeWindow || ctx.squeezeNextSlot`.

## 5. Risks / conflicts

- `run_director.dart` is a shared hotspot (2 400+ lines). D-SPRING, D-TESTS and other areas' WPs (D1–D4, showcase B)
  all touch it, so run them one after another.
- The bot rewrite (D-BOT) changes the showcase bot test (PRD :506, area B). Coordinate.
- SPEC.md:1938-1945 currently **documents** the spring ban and the 568 squeeze-band hack as intended. Leaving it would
  contradict §3.23 ("spring from hoop 10" test) and D4. Rewrite it with D-SPRING.
- The human-noise test runs 21 seeds × up to 120 s per height (≈ 3–5 min each). The medians are noisy (with 21 seeds,
  medians swing by ±10 between σ steps). Use ≥ 41 seeds for calibration and keep the gate tolerance explicit.
- R2: `same_rules_test` must gain the arm (WP-H) and the runtime level (WP-J) when they land.

## 6. Measurements (scratch copies; gamesPlayed 10, showcase off, gates on)

Fixed closed-loop bot (my prototype). 21 seeds, 60 s cap (≈ 27–35 hoops max), medians:

| σ (ms) | 2.6 @568 | 2.6 @711 | 2.5 @568 | 2.5 @711 |
|---|---|---|---|---|
| 0 (=autopilot) | 28 | 29 | 29 | 29 |
| 30 | 28 | 28 | 29 | 29 |
| 45 | 27 | 27 | 27 | 29 |
| 60 | 27 | 27 | 26 | 27 |
| 90 | **4** | **5** | **7** | **9** |

Shipped bot on 2.6 at σ 0: 568 deaths at 6/4/7 hoops; 711 at 4. Plain autopilot: 0 deaths in 21 seeds at both heights.

120 s cap (the gate's own cap), 31 seeds, medians:

| σ (ms) | 2.5 @568 | 2.5 @711 | 2.6 @568 | 2.6 @711 |
|---|---|---|---|---|
| 45 | 51 | 51 | 57 | 55 |
| 60 | 23 | 30 | 40 | 39 |
| 75 | 14 | 10 | 28 | 15 |
| 90 | 13 | 9 | 6 | 10 |

How to read the 120 s table:
- 2.5 crosses about 40 hoops between σ 45 and 60 ms (by interpolation about 50 ms). At that σ, 2.6 is well above 40
  (57/55 at 45 ms, about 40 at 60 ms). So with a calibrated bot the 2.6 early course is **not harder** than 2.5. It looks
  slightly easier at σ 45–75.
- At σ 90 both courses are about 10 and the difference is noise.
- The tail is very noisy, so use ≥ 41 seeds for the final constants.
- The seed lists are not paired courses: a given seed builds a different course in 2.5 and 2.6.

Test run in the worktree (after the orchestrator fixed package_config), via flock:
`flutter test test/p26/curve/ test/run/director/wp_d_wire_test.dart test/run/hoops/s3_23_spring_test.dart test/p26/bot/`
gives **105 pass, 1 fail** (s3_23 "room for its 240 pt jump"). All 6 `curve_ceiling` sweeps, `same_rules` (both tests),
every formations test, the hazard / calm / headline tests and the human-bot unit tests pass.

Spring evidence (scratch copy, `budgetAt < 4` clause removed): s3_23 passes. `curve_ceiling squeeze=true` fails at
h=711 and h=730 (`seed=52 slot=35 … Expected ≤ 1, Actual 2.0`, `curve_ceiling_test.dart:215`). 568 still passes.
