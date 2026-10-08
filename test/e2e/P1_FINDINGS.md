# QA round P1 — Flappy Spikes 2.1

Independent review on 2026-10-08 of `g6-qa`, baseline `19f9843`, against
`PRD-2-gameplay.md`, `docs/gameplay-v2/ARCH.md` (including §§11–15),
`docs/gameplay-v2/REQ-MATRIX.md`, `SOUNDS.md`, and the workspace rules.
Only QA tests and this report were changed. No product fixes, production
Firebase writes, Pixel 8 use, or iOS changes.

**Result: nine confirmed defects, including the already known Big Hoops colour
issue. Five major, four minor, no blockers.** The other eight findings extend
the existing coverage. Every finding has a regression named `S6-xx`, disabled
with `skip: 'S6-xx open'` in `p1_gameplay_e2e_test.dart`. FlameTester requires a
boolean skip argument, so its cases use the enclosing test group's string skip
reason instead. S6-08 also has an emulator test in
`functions/test/p1_qa.test.ts`, pending unless `S6_QA_OPEN=1`.

## Gates

| Check | Result |
|---|---|
| `flutter pub get` | Passed; tracked dependency files unchanged. |
| `flutter analyze` | Clean after adding the QA tests. |
| Baseline `flutter test -j 4 --reporter expanded` | 1,157 passed; four failures, all the known Big Hoops colour assertions at 568 / 711 pt. |
| Final `flutter test -j 4 --no-pub --reporter expanded` | 1,161 passed; nine QA regressions skipped; four known Big Hoops failures plus one existing menu test with a random-powerup dependency, explained below. |
| `npm --prefix functions test` | 77 passed; one new QA regression pending. Firestore, Auth and Functions demo emulators. Installed the locked dependencies with `npm --prefix functions ci` first. |
| `npm --prefix functions run lint` | Passed. |
| New P1 E2E file, normal run | Five passed; nine open regressions skipped. |
| New P1 E2E file, `--run-skipped` | All nine defect cases failed on their expected behavior assertions, including the S6-08 emulator assertion. |
| Screenshot tests | Ran with the full suite, including the five `test/run/shots/` generators; screenshot tests passed. PNG comparisons described below. |

The full Flutter gate remains red. S6-01 is the four failures disclosed in the
round's brief, not four additional defects. The added open regressions are
skipped in the normal gate.

The final suite also failed
`test/e2e/menu_v4_round1_schedule_e2e_test.dart:338` (“completed free-coins and
slot videos count”). It passed in the baseline full run, then failed in both
the final suite and a focused rerun. This older test accepts the random home
powerup, calls `killRun` once, and assumes the run has ended. With Shield,
that mistake is correctly saved, `goHome()` is ignored while still playing,
and the expected menu popup never appears. Controlled copies of the test
confirmed **forced Shield fails / forced Big Hoops passes** using persisted
three-repeat slot histories. The copies were removed. This is an existing
test-harness assumption exposed by the now-live Shield, not another PRD-2
product behavior defect; the original test/helper was left unchanged.

## Findings

Product file locations refer to baseline `19f9843`.

| id | severity | file:line | what's wrong | repro | expected (PRD §) |
|---|---|---|---|---|---|
| S6-01 | major | `lib/run/items/streak.dart:233` | **Known:** tier-zero streak processing clears Big Hoops gold, leaving enlarged rings pink. | Arm Big Hoops on Home, START: first opening is 177 pt but `look.colors == null`. Integrated `big_heart_badge_568.png` / `711.png` are pink. | Boosted normal rings are gold; preserve Big Hoops colours alongside streak tiers (§3.6, §3.5, §5.1). |
| S6-02 | major | `lib/run/run_controller.dart:352` | An overlapping rim contact moving away from the rim is pushed out but never marked touched. The ensuing pass is incorrectly perfect, pays two coins, advances the streak and shakes. | Overlap the first ring's inside top rim, 1 pt before its plane, with `vy=80`; update 0 then 1/60 s. Contact exists with `bounced=false`; controller emits `perfect=true`. | Every rim touch marks a graze: no death on the inside, +1 score / +1 coin, no perfect celebration, streak reset and knock (§3.0.4 points 2–3, §3.1, §3.4, §3.33). |
| S6-03 | minor | `lib/run/run_spawner.dart:120` | First-meet persistence uses half the opening as horizontal visibility, marking a ring met while its artwork is still offscreen. A death now permanently consumes the guarantee without the player seeing it. | Force an angled first ring; update 0.02 s. Even its generously expanded left artwork bound is beyond x=320, but `metElements` already contains `angled_ring`. | An element becomes met when spawned **on screen** (§3.0.8). |
| S6-04 | minor | `lib/run/run_controller.dart:539` | `run_end.hoop_index` reports the next director spawn index instead of the missed/death ring; the kind and index can describe different rings. | Hold the bird above the first opening until it fully misses slot 0; finish tumble. Analytics reports `cause=missed_hoop, hoop_index=2`. | Report the slot associated with the run-ending cause (§6, `run_end`). |
| S6-05 | major | `lib/services/reminders.dart:939` | The local zone is resolved only at initialize. Rescheduling on the same app instance after a device zone change keeps the old zone, violating local windows and potentially quiet hours. | Initialize in Amsterdam; change the mocked device zone to Denver; advance to the next day and reschedule. An evening reminder converts to Denver 12:19 in the recorded repro; Amsterdam midday slots convert to Denver 03:30–05:29. | Recalculate in the **current** local zone; midday 11:30–13:30, evening 18:30–20:30, never 22:00–09:00 across zone/DST changes (§3.34, When). |
| S6-06 | minor | `lib/services/reminders.dart:509` | The scheduler refills to 14 notifications after dropping elapsed / recent-play slots, extending the plan into an eighth calendar date and beyond seven days. | Schedule Amsterdam 2026-10-08 12:00, seed 1, just played. The final reminder is 2026-10-15 13:21, after the seven-day deadline of 12:00. | Schedule the next seven days and **drop** slots within two hours; a player who never returns gets seven days then nothing (§3.34, Scheduling). |
| S6-07 | minor | `lib/services/reminders.dart:991` | A notification scheduling failure still persists the entire rotation as scheduled/sent. Unseen messages are consumed and enter the ten-day exclusion history. | Make `FakeReminderPlatform.schedule` throw; reschedule. No notification is pending, but position advances to 14 and `notifLastSent` records 14 future dates. | Rotation and last-sent history represent messages actually scheduled/delivered; an unsuccessful schedule must remain retryable without consuming them (§3.34, Order / Scheduling / persisted last-sent dates). |
| S6-08 | major | `functions/src/pools.ts:116` | A delayed pre-deletion player-write event recreates the deleted user's pool entry and rate document. Processing trusts the event snapshot without checking current deletion state. | Finish `deletePlayerData(uid)`; replay a queued valid player-write snapshot for the same uid. `players/uid` stays absent while `pools/3_0` receives the uid again. Transaction also recreates its rate document. | Delete my data leaves **everything stored online** for that player deleted, including pool entries (§3.13, Privacy / data safety). |
| S6-09 | major | `lib/run/physics/rim_collision.dart:85` | Rim reflection subtracts only the moving centre velocity. Rock / swing / orbit angular motion is excluded from the rim end's velocity, so rotating contacts receive the wrong bounce. | Actual hoop with RockMotion, amplitude 15°, period 3 s, phase 0: stationary bird overlaps the right of the top rim. That rim moves right at 36.19 pt/s; returned bird vx is 0 instead of 66.95 pt/s. | Reflect relative to the **rim's own velocity**, restitution 0.85, including motion of the rotated rim endpoint (§3.0.4 point 2, §3.11). |

S6-06 interprets “next seven days” as a fixed time horizon, following the explicit
“drop” and “seven days and then nothing” wording. Current implementation/tests
instead aim to fill 14 future slots. It is a small scheduling discrepancy, not a
quiet-hours defect.

## Reproductions

Use the workspace Flutter / Android SDK / JDK 17 environment from AGENTS.md.

```bash
flutter test -j 4 --no-pub test/e2e/p1_gameplay_e2e_test.dart
flutter test -j 4 --no-pub --run-skipped test/e2e/p1_gameplay_e2e_test.dart
```

To isolate a Flutter finding, add `--plain-name S6-02` (or the corresponding
ID) to the second command. The backend defect can be run independently:

```bash
S6_QA_OPEN=1 npm --prefix functions test -- --grep S6-08
```

The TS case deterministically replays a stale write snapshot after deletion; it
does not depend on winning a live timing race. The default functions test command
keeps it pending. All backend repros use the repository's demo emulators.

Local command logs were written to `/tmp/g6-qa-p1-{tests,tests-final,tests-slot-final,
functions,functions-final,repros,e2e,e2e-final,analyze-final}.log`. These are working-session evidence,
not committed artifacts. The repro log records all nine expected failures; it
was taken before adding the two extra Big Hoops journey cases.

## E2E and review coverage

The five new passing journeys exercise:

- At **both 568 and 711 pt**: the actual Home slot action, completed fake rewarded
  ad and Shield consumption, debug-forced angled ring,
  moving ring and heart, seeded autopilot through at least 12 hoops, immediate
  wallet credit, shield before extra life on successive mistakes, two-second
  invulnerability, death through the current GameOverPanel, bird settling flat
  on the **44 pt** floor teeth, no duplicate coin payout, and return Home.
- At **both heights**: the actual Home slot action, completed fake rewarded ad
  and Big Hoops consumption, duration in **30–40 s**,
  **1.5×** opening, linear last-eight-seconds easing, per-spawn sizing, expiry,
  and no resizing of any visible ring. The nonzero-start clock case is checked.
- **35 days** of reminders with recreated storage/service, persisted pending
  payloads and simulated delivery, Amsterdam autumn DST, both local windows,
  one permission prompt, all 20 messages encountered, and at least ten calendar
  days between repeats. This passing same-zone DST case does not cover or
  contradict S6-05's device-zone-change failure.

Source review and the existing suites additionally covered:

| Area | Checks / conclusion |
|---|---|
| Numbers and timing | Core 150 pt/s +3.5%/minute, 310 pt spacing, first ring 60 pt offscreen, gravity 1250, flap −370, max fall 650, bird x70 / r14.75, opening 118 × max(0.78, 1 − 0.0032 × index), rim r7 / restitution 0.85, forward recovery 2000, colour stage every ten passes, 44 pt strips. Layout rows, motion type weights, travel/speed bounds, life/save and miss/tumble configs checked against PRD and as-built calls. No additional numeric mismatch confirmed. |
| Director | Special/gap weights and cooldowns, budget and exclusion rules, one oldest-unlock first-meet queue, within-five eligibility tests, debug force/start-index/reset hooks, and the documented stuck-head behavior. Mirror/director tests pass. S6-03 concerns the live spawner's visibility bookkeeping. Unbuilt element visuals/effects were not treated as defects. |
| Physics | Existing inside-rim nonfatal, fully-past miss, tilted-extension/no-premature-miss, knock-back recovery, one resolution and tumble tests pass; new journeys confirm floor rest. S6-02 and S6-09 are additional contact edge cases. |
| Hearts / shield | Three hearts per extra life, no heart while armed, home starter paths, shield-first interception, two-second invulnerability, shared badge / shield / shard / blink parts. Existing tests and new journeys pass. |
| Streak and banners | Tiers capped at ten; PERFECT, GREAT, AMAZING, INCREDIBLE, LEGENDARY, UNREAL, GODLIKE, MYTHIC, COSMIC, IMMORTAL; sizes 28/32/34/30/32/34/34/32/34/30, fixed top190, duration 0.9 + 0.16 × min(tier,6); burst 11/14/17 squares, tier-two gold bird, tier-three trail, resets on graze/miss. Shared-master and streak suites pass except known gold ownership S6-01. |
| Rumble | Perfect shake 45 ms/full; graze and pickup knock 15 ms/~90; knock throttle 90 ms; shake wins a frame and is never suppressed by that throttle; run-state gating and setting/toggle analytics. Recorder/service tests pass. Actual motor feel was not tested. Existing menu knocks remain the settled home-v3 behavior. S6-02 misclassifies the pass upstream of this router. |
| Reminders | Message text/fallbacks, placeholder fill-in, permission once, channel sound/raw keep file, inexact scheduling, windows/quiet hours, pending-message restoration, rotation and DST tests reviewed. Three new scheduling issues: S6-05/06/07. |
| Persistence / analytics | Built-scope keys and write paths checked against §7 and ARCH §5. `levelRewardsClaimed` deliberately aliases existing `claimedLevels`. Versus-client queue/profile keys are outside this build. Built pass/miss/touch/save/pickup/coin/director/reminder/toggle routes checked against §6; S6-04 is the confirmed run-end payload defect. |
| Shared parts (§3.0.9) | Live paths use RingPainter, spike teeth, score disc, LifeIcons, ElementBanner/BannerHost, CoinPopup, PerfectBurst/ParticlePool, FetchFlight, InvulnFlash and shared trail/tier painters. No second built gameplay variant confirmed. Superseded mock details were not reported. |
| Sound / lazy audio | Registry/files versus SOUNDS.md, sound routing and loop interfaces, eight prewarmed cues, one lazy request per other cue, ≤250 ms late first-play allowance and contained pool errors reviewed. Sound suites pass. No physical device playback/listening check. |
| Versus backend | Emulator coverage passes timeline/flags and cheat rejection, rate/new-best rules, pool level/shard/150-entry cap and replacement, 60-day pruning/retention, security rules/callable authorization and deletion. S6-08 adds the delayed-write deletion case. Versus client/matching/replay UI and production App Check/TTL/console state were not tested in this scope. |

## Visual comparison

Generated `build/shots/run/{hoops,rings,lives,streak}` and `build/parts_shots`
PNGs were inspected against the approved PRD references in `design/menu_v2/`:
`hoops_m0.png`, `hoops_m0_big.png`, `ringtier_2.png`, `ringtier_3.png`,
`perfect_1.png`, `perfect_10.png`, `miss_c_wave.png`, `hearts_2.png`,
`hearts_3.png`, `moving_3.png`, and `moving_4.png`.

The clear integration mismatch is **S6-01**: the enlarged ring is pink in
`build/shots/run/lives/big_heart_badge_568.png` and
`build/shots/run/lives/big_heart_badge_711.png`, whereas
`design/menu_v2/hoops_m0_big.png` is gold. The isolated shared-master screenshot
`build/parts_shots/01_hoops_m0_big.png` is correctly gold, confirming that the
problem is integration rather than the ring painter.

Other inspected built art was consistent with the current masters at the tested
snapshots. These were visual reviews of generated snapshots, not pixel-golden
assertions or physical-device animation checks. Deliberate §3.0.9 / ARCH
differences were excluded: the current 183 pt score disc, 44 pt strips, equipped
bird/trail look, fixed banner position and shared small burst rather than older
full-screen celebration effects. The compact HUD and new post-run screens are
WP-2d/2e work in progress; absent HUD indicators and the old results screen are
not P1 defects. SAVED banner hosting is explicitly deferred by ARCH §14.

Tablet screenshot writes outside this worktree were ignored and were not staged.

## Excluded scope

HUD row, pause, revive and new results page; comet, rides, special-hoop effects,
unbuilt gap items, capsules, squeeze, feathers, puzzle, versus client. Their
absence was not reported. Existing director data for these elements was still
reviewed as part of the shared director contract.
