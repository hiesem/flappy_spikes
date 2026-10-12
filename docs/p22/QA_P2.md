# PRD-2.2 QA P2

Date: 2026-10-12. Branch: `g7-qa2`. Implementation reviewed: `a7841e6`.
Scope: §7, §15–19, §21–28, §33 and P1 fixes S7-01…06. §12, §20 and §31
are not merged in this worktree and are excluded.

Seven findings: **2 major, 5 minor, no blockers**. Production code is unchanged.
All nine finding regressions were executed without skips and failed before
being committed with `skip: 'S7-xx'`. The green gates do not mean the reported
defects are fixed. FlameTester widget regressions use a containing group's
string skip, since its test helper only accepts a boolean skip.

## Findings

### S7-07 — minor — FEVER ends after five perfect passes despite an unbroken streak

- **PRD:** §21.1, “FEVER unchanged”, including its sounds; §21.3. The new
  ordinary fire must not shorten the existing FEVER phase. Before §21, FEVER's
  loud loop continued until the streak broke.
- **Location:** `lib/run/items/fever.dart:117` (decrements the new countdown),
  `lib/run/items/fever.dart:153` (starts it),
  `lib/run/items/fever.dart:191` (changes the loop volume),
  `lib/run/config/fever_config.dart:255` (`feverHoops = 5`).
- **Repro:** start a run, emit a pair FEVER gift, let its loop start, pass six
  normal hoops perfectly, then allow the volume ramp to settle. No rim touch,
  off-centre pass, save or death occurs.
- **Expected:** FEVER remains active and the one loop remains at the existing
  FEVER volume, 0.35, until the streak breaks.
- **Actual:** `feverLeft` reaches zero; the loop ramps to 0.25 even though the
  bird still burns and the streak is intact. This is the builder's five-pass
  Call, not a requirement in the approved PRD. The instruction to ramp down
  when FEVER ends does not authorize a new condition for ending FEVER.
- **Regression:** `test/p22/s16_s21_qa_p2_contract_test.dart`, skipped S7-07.

### S7-08 — major — ordinary ×3 fire blocks FEVER rings and pair FEVER gifts

- **PRD:** §21.1 / §21.3, FEVER unchanged; §27.1, fire and FEVER are passive
  states which never block rewards.
- **Location:** `lib/run/director/run_director.dart:731` (FEVER ring filter),
  `lib/run/director/run_director.dart:772` (pair gift filter).
- **Repro:** create an all-enabled/all-met director at hoop 20, force a FEVER
  ring, and pass an otherwise open context with `onFire: true` and no activity.
  This now describes any ordinary three-perfect streak, before FEVER begins.
- **Expected:** ordinary streak fire leaves FEVER eligible. Preserve the
  existing FEVER-specific exclusions without broadening them to all fire.
- **Actual:** the forced FEVER slot becomes a normal hoop. The pair filter
  likewise removes FEVER whenever `onFire` is true. Successful streak players
  therefore lose access to this reward simply by reaching ×3.
- **Regression:** `test/p22/s16_s21_qa_p2_contract_test.dart`, skipped S7-08.
  The test proves the ring path; the identical gift predicate is source-audited.

### S7-09 — major — already-playing one-shots remain audible under ads and interruptions

- **PRD:** §28.2, everything suspended during full-screen ads; §28.3, sound
  effects muted during calls / alarms / assistant interruptions. §28.1 permits
  one-shots to finish at death, not to remain audible under an ad or call.
- **Location:** `lib/game/sound.dart:862` (`suspend`),
  `lib/game/sound.dart:891` (`setInterrupted`); neither reaches live SfxPool voices.
- **Repro:** preload `perfect_3`, play four copies to fill its three voices and
  steal the oldest, then either suspend for an ad or signal an interruption.
  Inspect actual fake voice playback state, not only the `onAudible` callback.
- **Expected:** zero audible one-shot voices while held. Ordinary §22 full
  lengths and oldest-copy stealing still apply outside the hold.
- **Actual:** all three voices keep playing in both cases. Music and loops are
  handled, and future plays are gated, but the existing one-shots are untouched.
  A long perfect / reward sound can therefore overlap the ad or interruption.
- **Regression:** two tests in `test/p22/s22_s28_s33_qa_p2_audio_test.dart`,
  both skipped S7-09. Each observed 3 ringing voices rather than 0.
- **Integration:** quiet or stop existing voices and consider starts already
  queued on per-voice operation chains; avoid a delayed burst on resume.

### S7-10 — minor — pending pool creation survives SoundService disposal

- **PRD:** §33.4 / §33.7, disposal releases players and bounds the live set.
- **Location:** `lib/game/sound.dart:786` (`dispose`),
  `lib/game/sound.dart:703` (`_createPool` publishes after asynchronous load),
  `lib/game/sound.dart:676` (core warm-up continues).
- **Repro:** gate first-voice creation for the core flap and lazy `lv_up` pool,
  request the preload, await `dispose`, then release both gates.
- **Expected:** zero pools and zero live players after teardown, including
  completions that arrive later.
- **Actual:** nine pools are published after disposal and their players remain
  live. Clearing `_creating` neither cancels nor invalidates its futures;
  `_initPools` also continues warming the remaining core pools.
- **Regression:** `test/p22/s22_s28_s33_qa_p2_audio_test.dart`, skipped S7-10.
  A second cleanup disposal is necessary in the probe.
- **Scope:** this is a teardown/soak/service-replacement race. Ordinary replays
  currently share the service and do not call this disposal API; this finding
  does not establish a player leak on each ordinary replay.

### S7-11 — minor — unplayed preloads exceed the live-pool cap

- **PRD:** §33.4 item 3, a cap on live sound pools, retaining the core set.
- **Location:** `lib/game/sound.dart:754` (`evictable`),
  `lib/game/sound.dart:767` (cap trimming),
  `lib/game/config.dart:1236` (`sfxMaxLivePools = 40`).
- **Repro:** at one fixed monotonic time, preload 41 different non-core cues
  and allow initialization to finish. Never play any sound.
- **Expected:** at most 40 pools. A never-played pool is safe to evict or its
  admission can be deferred; no genuinely ringing copy needs to be cut short.
- **Actual:** 49 pools (41 rare + 8 core), with zero voice starts. Creation
  initializes `lastUsedMs`, and eviction treats that preload touch as a recent
  play, so every new unused pool is temporarily protected from cap trimming.
- **Regression:** `test/p22/s22_s28_s33_qa_p2_audio_test.dart`, skipped S7-11.
  Existing churn coverage ages the clock between requests and misses this case.

### S7-12 — minor — comet entry clears modifiers from the already-planned hoop

- **PRD:** §16.1, hoops already planned or on screen when the comet begins
  retain their height, tilt and motion; the zigzag affects newly planned hoops.
- **Location:** `lib/run/run_spawner.dart:153` (late ride conversion),
  `lib/run/director/run_director.dart:917` (`plainSlot`),
  `lib/run/director/run_director.dart:947` (zero tilt / clear motion).
- **Repro:** all elements met, seed 5, hoop index 20; force an angled or moving
  ring and wait until it is `plannedAhead`. Start a comet before that plane
  reaches the spawn edge, then inspect the actual spawned Hoop plan.
- **Expected:** that pre-existing plan keeps its tilt or MotionSpec. Reward
  removal under §27 must not erase ordinary obstacle modifiers under §16.
- **Actual:** `_spawnAhead` calls `plainSlot` because the ride started after
  planning. Tilt changes from −10° to 0°, or a rail MotionSpec becomes null.
  The original object remains in `slotLog`, so inspecting only that log gives
  a false pass. The regression checks the actual spawned component.
- **Regression:** two tests in `test/p22/s16_s21_qa_p2_contract_test.dart`,
  skipped S7-12. Both modifiers failed independently.
- **Integration:** coordinate §15's planned-ahead conversion, §16's frozen
  pre-existing geometry and §27's removal of rewards.

### S7-13 — minor — game flaps can prevent music returning at run start

- **PRD:** §28.3, after the player's own music stops, game music starts at the
  next scene change (Home / run start).
- **Location:** `android/app/src/main/kotlin/com/flappyspikes/flappy_spikes/MainActivity.kt:177`
  (`media || isMusicActive`), `lib/game/flappy_game.dart:2603` (scene recheck).
  The builder documents this behavior in `docs/p22/ADS.md:167`.
- **Repro:** launch while external music is playing, stop it before START,
  then flap every 0.1 s through the 0.6 s delayed recheck. Model the Android
  fallback's music-stream activity, which also includes the game's own SFX.
- **Expected:** only external media keeps the game's music skipped; it returns
  at this run start even if the player keeps flapping.
- **Actual:** the delayed query sees the game's own flap, retains
  `ownMusicSkipped`, and does not retry within this run. Music can remain off
  until a later Home arrival. Waiting 0.6 s is not sufficient while flaps repeat.
- **Regression:** `test/p22/s22_s28_s33_qa_p2_audio_test.dart`, skipped S7-13.
  It runs the actual scene-change code with a faithful stream-fallback fake;
  it proves the documented Call's failure without claiming a native device test.

## Calls reviewed

| Builder Call | QA disposition |
| --- | --- |
| §21 FEVER lasts five perfect passes | Contradicts unchanged FEVER; S7-07. |
| §21 no FEVER ring while any fire burns | Broadens the old restriction to ordinary ×3 fire; S7-08. |
| §7.5 logical height = visible + 20, cropping camera | Accepted as the lowered-strip implementation: comparisons at 663/596/524 show the required 24 pt visible bottom teeth and usable controls; all ride phases and versus revives pass at these heights. Keep visible and logical heights distinct when integrating later screens. |
| §28 observe playback/mode without requesting focus | A small platform observer is within §28.4's allowed implementation choice and preserves mixing. Native focus coverage is not certified in this no-device round; the existing ringing-SFX hold fails independently (S7-09). |
| §28 music can stay off through a flapping run start | Contradicts the next-scene-change requirement; S7-13. |
| §15 freeze Big Hoops size one gap early, decide gold at spawn | Accepted: planning geometry early follows §15; the gameplay gold state remains a spawn-time decision. A planned large hoop can survive the power-up expiring before it spawns. |
| §18 banner opacity = 1 − 0.5 × scene mix; preload at portal spawn | Matches 50% in the ride and continuous recovery to normal; portal cue checks pass after the test harness correction. |
| §25 portal fixed at 118 pt | Literal PRD exception; accepted. |
| §26 piggy spacing 45 pt | Literal PRD spacing; accepted. |

QA made no production behavior changes and no new gameplay contract Calls.

## Coverage and visual review

- §7: existing tests cover banner/no-fill/consent/NO ADS resize, pause, bonus,
  revive and results; all six interstitial guards, preload and failed show;
  rewarded-video counting including interstitials; bonus offer wait, timeout
  and availability; privacy options; NO ADS/free revive ladder; indefinite
  revive offers. §24 tap filtering and locked-heart behavior pass.
- New integration coverage: all six rides at visible 663/596/524, banner and
  circle retained throughout ride/exit/fly/glide, automatic return flap, first
  post-ride hoop ≈2 s later, then two breather hoop planes before a forced
  deferred heart. A one-update activity synchronization boundary is allowed.
- New versus coverage: both normal ad and NO ADS free phoenix revives after a
  30 s offer wait; frozen clock/score, same opponent, one phoenix, consumed ad
  step, no coin charge, correct banner height.
- §15/19/23/25/26/27: element spawn gates, opening statistics, placement bounds,
  egg/chick rim cases, special-ring geometry/decorations, piggy dimensions,
  activity clearing/owed items/cooldowns and seeded activity statistics pass.
  §16/17/18 autopilot, landing and ride tests pass except the new S7-12 probes.
- §22/33: duration table freshness/full lengths, per-cue caps/steal, normal
  eviction/churn, no position polling for SFX/loops/music, avatar decode bounds
  and LRU, idle 30 fps/wake behavior, background engine pause/resume and small
  resource disposals pass. A lazy sound requested before an ad never starts
  late after preload finishes (new passing regression). The cap and teardown
  edge cases are S7-10/11.
- P1 S7-01…06 remain fixed: all unskipped P1 Dart regressions and the backend
  checks pass (wide score bounds, bonus gap exemption, chick puzzle doubling,
  Bullseye crossing offset, 80-point generic bonus/puzzle exception, stale Home
  search generations). No P1 finding is reopened.

Reviewed generated PNGs beside approved mock artifacts:

- `build/p22_banner_shots/{play,revive,bonus,results}_{663,596,524}.png` and
  lowered-strip captures versus `design/menu_v2/run_banner/`. Controls fit above
  the visible bottom teeth. Also reviewed NO ADS/free/wait revive, bonus
  waiting/active and privacy captures under `build/menu_shots/`.
- `build/menu_shots/p22/s18/` ride/exit/fly/glide captures for every theme;
  sea/volcano also at 568, versus approved `ride_*_1/2/3.png` and
  `screen_portal_rides3.html`. New `build/qa_p2/sea_{663,596,524}.png` captures
  exercise the banner heights. Scene colors/circle/banner transitions agree
  with §18; frames are compared for layout, not identical random object states.
- §15 pop-in/iris/cable and §23 egg carried/break/fall captures; §27 pair,
  Lucky Spin and FEVER before/fading/plain captures; §25 shrink comparison.
  Reviewed approved comet/piggy HTML mocks and the fire mock held at ×3/×5/×7
  alongside `build/shots/p22/s21_fire_*.png`.
- Some existing screenshot tests omit the UI font loader and render block
  glyphs; this is an artifact limitation, not evidence of broken device fonts.
  Theme differences in bonus/results belong to the absent §31. Banner layering
  belongs to absent §12; neither is counted as a P2 finding.

PNG comparisons and local headless Chromium mock captures are under
`build/qa_p2/` and are not committed. No store screenshots are committed.

## Changes and validation

- Added `test/p22/s16_s21_qa_p2_contract_test.dart` (4 finding regressions).
- Added `test/p22/s22_s28_s33_qa_p2_audio_test.dart` (5 finding regressions +
  1 passing preload/suspend regression).
- Added `test/p22/s7_s17_s18_s27_qa_p2_flow_test.dart` (18 ride/height cases +
  2 versus revive cases, all passing).
- Changed only the audio harness in
  `test/p22/s18_portal_rides_polish_test.dart`: fake the loop platform/cache as
  well as SFX, and run the three audio verifications with `tester.runAsync`.
  Their expectations are unchanged. Previously cleanup awaited audio futures
  across the widget fake clock and stalled the run. No existing behavioral
  assertions were changed.

Validation:

- `flutter pub get`: passed.
- `flutter analyze`: **clean**.
- `flutter test --concurrency=4 test/p22`: **487 passed, 9 skipped**.
- `flutter test --concurrency=4`: **2403 passed, 12 skipped** (9 P2 finding regressions + 3 existing skips).
- `npm --prefix functions ci`, `npm --prefix functions run build`: passed.
- `npm --prefix functions test`: **121 passing**, emulator suite shut down cleanly.
- Finding-only probe without skips: **1 passed, 9 failed as reported**.
- `git diff --check`: clean.

## Remaining work and integration risks

The seven findings require builder fixes. No fixes, device work, emulator
launch, deployment, signing-key copies, account actions, iOS edits or pushes
were performed. The Functions test command runs its required backend emulator
suite; no Android emulator was used.

30-fps frame pacing, native Android audio interruption/player detection and
long-session device thermals are not certified by headless tests or still
PNGs. This round intentionally has no device work. The tests verify timing and
state continuity, not subjective smoothness. Integrators should keep §12/20/31
outside this report's verdict and coordinate the shared director/audio fixes
identified above before treating the green suite as release approval.
