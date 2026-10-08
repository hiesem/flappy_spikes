# QA round P2 — Flappy Spikes 2.1

Independent review, 2026-10-08, baseline `d062f77`, worktree `g6-qa2`.
Sources: workspace `PRD-2-gameplay.md` and `CLAUDE.md`, local `AGENTS.md`,
`docs/gameplay-v2/ARCH.md` including as-built §§11–17,
`REQ-MATRIX.md`, `SOUNDS.md`, and `test/e2e/P1_FINDINGS.md` fix decisions.

**Five confirmed defects: one major, four minor; no blockers.** Only this
report and `p2_gameplay_e2e_test.dart` were added. No product fixes, Pixel 8
use, iOS edits, Firebase production access, or publication actions.

The brief names `g6-qa` in its commit instruction, but explicitly assigns
this worktree on `g6-qa2`; the QA commit stays on this worktree's branch.
The separate existing `g6-qa` checkout was not altered.

## Findings

Locations refer to baseline `d062f77`.

| id | severity | file:line | what's wrong | repro | expected (PRD §) |
|---|---|---|---|---|---|
| S6-20 | minor | `lib/run/screens/phoenix_rise.dart:81` | Phoenix's safe-line search uses the superseded centre-plane test. It skips an unresolved tilted ring whose right-hand extent is still ahead, although the spawner correctly identifies it as the next ring. | First ring at 45°, centre y=200; put its centre 20 pt behind flight x70. `nextHoopAhead()` returns it and its rightmost extent is ahead of the bird; `reviveSafeLine()` returns 355.5 instead of 200. | Rise to the vertical centre of the next ring still ahead, respecting tilted geometry (§3.14 Safe line; §3.0.4 miss line; ARCH §13b next-hoop contract). |
| S6-21 | minor | `lib/run/screens/revive_screen.dart:450` | Both heartbeat formulas double their configured scale amplitudes. Idle peaks at 1.07 and urgency at approximately 1.1194. | Offer a revive after six passes; sample `screen.beat` at 60 Hz through five seconds. | Idle peak 1.035, urgency peak 1.06 (§5.9 Urgency / idle beat). |
| S6-22 | major | `lib/levels/level_progress.dart:92`; `lib/run/screens/results_screen.dart:120` | Claim persists `claimedLevels` before crediting coins. A kill between those writes leaves the reward marked claimed but unpaid. Startup recovery recomputes the reward from claimed levels, pays zero and clears `unclaimedLevelReward`, permanently losing the coins. This also affects interruption of automatic startup recovery. | Execute the real claim with a preferences platform that stops before the coin write, retaining earlier writes. Restart from that actual disk snapshot: best=12, claimed=[1], pending=50, coins=100. Startup leaves coins=100 instead of 150 and clears pending. | A level reward is never lost; claim and restart recovery must preserve exactly one credit (§3.14 reward guarantee, §5.10, §7 `unclaimedLevelReward`). |
| S6-23 | minor | `lib/run/config/results_config.dart:35`; `lib/run/screens/results_screen.dart:266` | Whole-page scaling changes NEXT's bottom offset and reduces its width/height on short screens. At 568 pt, NEXT ends 54 pt above the screen bottom rather than the reference 65 pt. | Render results at 568; transform `nextButton` through `page.content`: bottom≈514, height≈39.93, x≈43.4, width≈233.2. Reference: bottom646 at711, height50, x14, width292. | Bottom buttons keep the same bottom distance across 568–730 pt (§3.0.1 Screen heights); NEXT has the §5.10 layout. ARCH §17 documents the scaling choice, but the stated precedence is PRD > ARCH. |
| S6-24 | minor | `lib/run/screens/results_screen.dart:1083` | CLAIM applies a plum `srcIn` recolour to the shared coin sprite. Its pale inner ring disappears and the coin becomes a solid plum dot. | Reach EGG and wait for CLAIM; inspect `results_claim_568.png` / `711.png`. The regression rasterizes the real CLAIM icon and compares it with the unmodified same sprite; pixels differ. | Every coin retains `coin.png`'s gold disc and thick pale inner ring; the plum results coin is explicitly superseded (§3.0.6, §3.0.9 master #14). |

S6-22 is an actual persistence-boundary reproduction, not merely a manually
invented restart state. The producer test runs `LevelProgress.claim()` and
records the platform store just before its coin write. The second test boots
the full game from that recorded store. An existing test deliberately treats
this same combination of claimed-level / pending keys as a completed claim
with a stale flag; the persisted keys cannot distinguish that case from an
interrupted unpaid claim. The ordinary **kill before CLAIM** case passes.

Each defect is in a group with `skip: 'S6-xx open'` (FlameTester accepts only a
boolean skip argument). S6-22 has a producer plus its failing restart case.
When enabled, the file finishes with six passes and **five expected assertion
failures**, one per defect; no setup/compilation failures.

## Gates

| Check | Result |
|---|---|
| `flutter pub get` | Passed; tracked dependency files unchanged. |
| Baseline `flutter analyze` | Clean. |
| Baseline `flutter test -j 3` | **1,232 passed, one skipped**, all green. |
| `npm --prefix functions ci` | Installed locked test dependencies; tracked files unchanged. Initial backend attempt lacked `tsc`. |
| `npm --prefix functions test` | **78 passed**, including S6-08; builds and type-checks, then runs Auth / Firestore / Functions **demo** emulators. |
| Final `flutter analyze` | Clean. |
| Final `flutter test -j 3 --no-pub --reporter expanded` | **1,237 passed, seven skipped**, all green. Six skips are the new open-case tests; the existing skip is the optional Flutter wrapper for S6-08, already exercised in the backend gate. |
| P2 file, normal execution | Five journeys passed; six open-case tests skipped. |
| P2 file, `--run-skipped` | Six passed, five expected failures (S6-20 through S6-24). |
| Screenshot generators | Passed in both full-suite runs; generated PNGs under `build/` inspected as described below. |

Logs: `/tmp/p2-{pub,analyze,tests,functions-ci,functions,e2e,repros,analyze-final,tests-final}.log`.
These are local evidence, not committed artifacts. Screenshot writes outside
this worktree (`../flappy_spikes/store/...`, `../shots`) were ignored and not
staged.

Reproduce with the SDK / JDK environment in AGENTS.md:

```bash
flutter test -j 3 --no-pub test/e2e/p2_gameplay_e2e_test.dart
flutter test -j 3 --no-pub --run-skipped test/e2e/p2_gameplay_e2e_test.dart
flutter test -j 3 --no-pub --run-skipped test/e2e/p2_gameplay_e2e_test.dart --plain-name S6-22
npm --prefix functions test
```

Run both S6-22 tests together (the name filter above includes the producer).
The before-CLAIM kill/restart journey likewise comprises two ordered cases
in this file.

## New E2E coverage

At **568 and 711 pt**, the actual Home Big Hoops slot button completes the
fake ad, consumes the starter, and starts a run with forced angled / moving
rings and heart. The seeded autopilot passes at least 12 hoops. The journey
then verifies world, bird and runClock freeze on pause, immediate resume,
backgrounding to pause without automatic resume, and four deaths with
**ad → 250 → 500 → 1,000** revives. Offers and phoenixes stop runClock;
resumption returns to x70 with two-second invulnerability. Egg / Piggy / Jar
state is lost at each death; coins and earned run reward stay intact. Games
played increments once on the final decline. Results pays EGG's reward on
CLAIM, animates YOUR REWARD, goes Home on NEXT, and a new run offers the ad
step again. The next offer before decline is correctly 2,000.

A real results-page preference snapshot is taken **before CLAIM**, then a
fresh full game starts from it: the pending reward is credited once with no
popup, and a second claim pays nothing.

A **25-day** reminder journey recreates storage/service each day, uses pending
payloads as simulated deliveries, spans Amsterdam's **spring DST** transition,
and checks both local windows, ≤14 pending slots, all 20 messages, a ten-day
repeat exclusion and one permission request. The existing P1 **35-day autumn
DST** journey also passes. Notification delivery is simulated; no phone
notification or physical haptic/audio session was performed.

## P1 fix re-verification

| ID | Result / evidence |
|---|---|
| S6-01 | Passes now, including the active Home Big Hoops gold assertion; integrated Big Hoops PNG is gold. |
| S6-02 | Active regression passes: separating rim overlap marks a graze, preventing perfect score/coin/streak feedback. |
| S6-03 | Active regression passes: first-meet only consumes the guarantee when the ring artwork enters the screen. |
| S6-04 | Active regression passes: death hoop index and kind come from the captured same hoop. |
| S6-05 | Active regression passes: a same-instance Amsterdam → Denver zone change reschedules in the current zone. |
| S6-06 | Active regression passes across 30 seeds: skipped slots do not extend the seven-calendar-day horizon. |
| S6-07 | Active regression passes: scheduling failure consumes no rotation or unseen-message history. |
| S6-08 | Backend emulator regression passes: delayed writes after deletion recreate neither pool membership nor rate state. |
| S6-09 | Active regression passes: RockMotion rim reflection includes endpoint angular velocity. |

The older menu test's shield-save assumption was repaired in the baseline
helper, as recorded in P1_FINDINGS; it passes in both full runs.

## PRD review coverage

| Area | Evidence and conclusion |
|---|---|
| Tuning and layout | Source comparison of Config / RunConfig / PhysicsConfig / LayoutConfig against §§3.0.1–3.0.5: cruise150 +3.5%/minute, spacing310, first ring +60 offscreen, gravity1250, flap−370, max fall650, x70 / r14.75, opening118 shrinking0.32%/slot to78%, rim7 / restitution0.85, recovery2000, colour every10, 44pt strips. Layout quantiles, tilt weights and motion table values match. Full numeric, mirror, physics and layout suites pass. New discrepancies: S6-21 and S6-23. |
| Director / first-meet | Budget bands, special and optional-gap tables, cooldowns, exclusion/schedule order, within-five first-meet tests, registered-element gating and debug force/start-index/reset hooks reviewed. Determinism and director suites pass. Unbuilt elements were reviewed as table data only. |
| Physics | Active inside-rim, fully-past miss, every tilt step, rotating endpoint, one-resolution and death-tumble suites pass; P1 journeys confirm rest on the 44pt floor teeth. S6-20 is the revive helper's inconsistent ahead predicate, not a pass/miss regression. |
| Save order / Big Hoops | Shield order10 before extra life20; two-second protection; three hearts per life. Big Hoops D30–40 run seconds, ×1.5, last8 seconds easing, per-spawn sizing, no visible resizing. Both existing P1 home journeys and new P2 starter journey pass; gold ownership is fixed. |
| Streak / shared parts | Names PERFECT / GREAT / AMAZING / INCREDIBLE / LEGENDARY / UNREAL / GODLIKE / MYTHIC / COSMIC / IMMORTAL; sizes28/32/34/30/32/34/34/32/34/30, top190, cap10, gold bird from2 and trail from3; bursts11/14/17. Shared RingPainter, strips, LifeIcons, banner host, CoinPopup, PerfectBurst and life/shield parts remain used. S6-24 is a forbidden shared-coin colour variant. |
| Rumble | Recorder/service tests pass: knock15ms at90, shake45ms at255, 90ms knock throttle, per-frame shake precedence, shake never throttled, run-state gating. Settled menu knocks remain as authorized by AGENTS.md. |
| Reminders | Source and passing fake-clock tests cover windows, quiet hours, current zone, spring/autumn DST, rotation, skipped slots, seven-day horizon, one-time permission, fallback text, notification-open analytics and failed-plan rollback. S6-05/06/07 remain fixed. |
| Persistence / analytics | Built-scope §7 keys/defaults and round-trips pass. Claimed-level alias to `claimedLevels` and `level_reward` analytics source are documented ARCH calls. Revive events, ladder indexes/prices, run-end payload, per-source earnings, level-up claim modes and reminder events have live call paths and passing tests. S6-22 exposes the gap between claimed-level and wallet persistence. Client versus queue/nickname behavior remains excluded. |
| Sound / lazy pools | SOUNDS.md registry and bundled-file tests pass; generated one-shots and seamless WAV loops are registered. Eight cues prewarm, others request one lazy low-latency pool, first play drops beyond250ms, pool errors are contained. No bare FlameAudio.play SFX path. Hardware listening was not performed. |
| Versus backend | Reviewed schema/rules/trigger/callable/timeline against §3.13 and ARCH §6. Emulator gate passes all78 tests: ownership/size validation, timeline/flags/0.9s filter, low-score and best rejection, rate/new-best exemptions, pool level/shard/cap/size, retention, matching fixtures and deletion. Production App Check enforcement, deployed TTL and cross-device matching were not exercised. Versus client remains out of scope. |
| HUD / pause / post-run | HUD row geometry, solo omission of versus placeholders, heart state/pulse, viewport timing, pause tap/keyboard/settings/back/backgrounding, ≥6-hoop eligibility, ad failure/locked-shop behavior, ladder reset, phoenix timing/squeeze-reset/collectable/timed-powerup rules, results CLAIM/NEXT/early-NEXT and no results ad are covered by active suites. New independent journeys connect them through actual runs. |

## Visual comparison

The full suite ran every generator in `test/run/shots/`, including
`revive_hud_shots_test.dart` and `results_shots_test.dart`, at 568 and 711.
Inspected built PNGs against PRD-approved mocks:

- HUD and pause: `game_versus_g1.png`, `game_versus_g2.png`,
  `game_versus_pause.png`; solo is intentionally missing the versus boxes.
- Revive: `revive_v2_ad.png`, `revive_v2_lock.png`, `revive_v2_burst.png`,
  with coin/ignite/Shop states generated by the same suite.
- Results: `results_lv_claim.png` against `results_claim_711.png` and
  `results_claim_568.png`; the solid plum CLAIM dot is **S6-24**. The narrow,
  shorter NEXT on 568 is **S6-23**.
- Core art: `hoops_m0.png`, `hoops_m0_big.png`, `ringtier_3.png`,
  `miss_c_wave.png`, `moving_3.png`, `hearts_3.png`; the formerly pink
  integrated Big Hoops ring is now gold.

This is snapshot inspection, not a pixel-golden gate. Differing course,
score, animation sampling, and solo/versus content are not visual defects.
The larger score disc, 44pt strips, equipped bird, fixed banner band and
shared burst intentionally supersede old mock variants (§3.0.9); older
mock differences were not filed. S6-21's pulse error is established by the
60Hz trace rather than a single PNG. No other clear mismatch was confirmed
in the inspected states.

Comet, rides, special-hoop behavior, unbuilt gap items, capsules, squeeze,
feathers, puzzle and versus client were not reported as missing. Their
baseline data/contract seams were checked only where this round builds or
uses them.
