# QA round P3 — PRD-2 gameplay

Independent review of `g6-qa3` at `ba52ed5`, 2026-10-08. Product code was
not changed. Reviewed the workspace PRD-2, SPEC/CLAUDE contracts, ARCH
§§11–25, REQ-MATRIX, SOUNDS, and P1/P2 findings. Scope is the 18 newly built
elements, including all six portal rides, three saw designs and five switch
designs. Unbuilt WP-4a, WP-5b and Delete my data are excluded.

**Eight open defects: two major, six minor; no blockers.** Ten failing
regressions are committed with `skip: 'S6-xx open'`. Normal execution passes;
`--run-skipped --plain-name S6-` produces ten expected assertion failures and
two passing full-size switch controls, with no setup/compilation failures.

## Findings

Paths below are relative to the Flutter project root.

| ID | Severity | File:line | What is wrong | Reproduction | Expected / PRD |
|---|---|---|---|---|---|
| S6-40 | minor | `lib/run/items/fever.dart:51` | FEVER remains lit on a physical rim graze until a non-perfect hoop **pass** resolves. There is no `RimTouched` subscription; a later death can report fire-out as death instead of graze. | Ignite via the real pair FEVER gift. Put an unresolved normal rim 10 pt ahead and the bird at its upper end; step one frame. `touched=true`, `resolved=false`, `onFire=true`. | Rim touch/graze extinguishes fire with smoke/sizzle (§3.19; fire-out cause in §6). |
| S6-41 | major | `lib/run/items/piggy.dart:99`, `:141` | Portal clearing treats unresolved bank coins as `voided` toward the 20-coin completion threshold. Clearing the last field pays and ends the bank, removing the remaining catch opportunities. | Reachable bank state: 16 caught, final four actual bank coins ahead. Call the portal's real `clearAhead()`. It credits **32** and drops the bank immediately. | All 20 must be caught or missed before payout; portal-cleared coins are not misses and placement continues after landing (§§3.0.3, 3.12, 3.28). **ARCH §25 / SPEC explicitly document the voided implementation; this finding is the conflict with the PRD requirement.** |
| S6-42 | minor | `lib/run/items/star_trail_feature.dart:69` | The partial-trail `n / 8` pop never requests `trailPop`; that sound has no product call site. | Spawn a real Star Trail already behind the bird with six caught stars; let the spawner resolve its escape. The `6 / 8` pop occurs without `trailPop` in the SoundService recorder. | Play the partial-count pop cue (SOUNDS Star Trail row; §§3.26 / 5.25). Rising per-star notes and the complete-trail chord are wired. |
| S6-43 | minor | `lib/run/hoops/kinds/pair/pair_kind.dart:167` | The +10 COINS gift sprays solid gold circle particles rather than the shared coin sprite; every inner pale ring is missing. | Apply the real coins gift to a cleared particle pool and rasterize the ten particles. Gold pixels exist; pale-ring pixels are **0**. | All coins use `coin.png`'s gold disc and thick pale inner ring (§3.0.6, §3.0.9 master #14, §5.20). |
| S6-44 | minor | `lib/run/debug/autopilot.dart:107`, `:140` | The debug autopilot's switch approach is not reliable with Mini Bird's smaller pickup hitbox. This is a test/debug bot defect, not a demonstrated manual-play collision defect. | Seed 5, start index 20, force switch, activate Mini Bird; run the hoop-aware bot at **568 and 711**. Both die at the first closed switch with **0 passes**. Identical full-size controls pass three hoops. | The bot targets the switch and passes ≥12 hoops after unlock with combined elements (§7; shrinking pickup hitbox §3.31). Pair/saw Mini Bird controls pass. |
| S6-45 | minor | `lib/run/director/run_director.dart:647` | Clamping the switch to ±110 pt from the previous hoop can push it outside the required 70–100 pt offset from its own ring. | Unforced director, seed 3, all registered elements enabled/met, 711 pt, scroll 180: slot 42 ringY=193.52, switchY=297.25186, offset=**103.73186**. | Keep both reachability constraints; switch offset 70–100 pt (§3.20 / §3.0.3). The existing placement test checks a weaker ≥60 bound without a maximum. |
| S6-46 | major | `lib/run/director/run_director.dart:691` | Running Piggy Bank / Firefly Jar fields bypass squeeze eligibility. New coin fields and firefly swarms still spawn during the squeeze window. | Real director, start index 50, seed 7, 711 pt, `squeezeWindow=true`, inset 177.75. With `piggyRunning` the gap contains `piggyCoins`; with `jarRunning` it contains `fireflySwarm`. Two regressions. | From three seconds before warning until reopening, only scheduled hearts and Star Trails may occupy gaps; defer these fields (§3.17 / §3.0.3). |
| S6-47 | minor | `lib/run/run_spawner.dart:203`, `:216` | Portal clear's `fade=.2` is a removal delay, with no opacity change. Objects remain opaque, then disappear. | Clear a mounted real normal hoop; advance the spawner 0.1 s and rasterize both halves. Alpha sum remains **488645**, identical to before clearing. | Hoops/items ahead fade out over 0.2 s, then are removed (§3.0.3 / §3.12). |

S6-40, S6-41 and S6-43 use real feature code with controlled reachable
starting states. S6-45/46 exercise the director's production planning API;
they do not depend on a debug force overriding normal rules. No persisted
coins are claimed lost in S6-41: the defect reduces the remaining bank catch
opportunities. S6-47 verifies actual rendered opacity, not just a config value.

## Gates and reproduction

| Check | Result |
|---|---|
| `flutter pub get` | Passed; tracked dependency files unchanged. |
| Baseline `flutter analyze` | Clean. |
| Baseline `flutter test -j 3 --no-pub --reporter expanded` | **1,652 passed, one skipped**, all green. |
| New P3 files, normal execution | **70 passed, ten skipped**, all green. |
| Open regressions, `--run-skipped --plain-name S6-` | **Two passed, ten expected failures**, covering S6-40–47. |
| Final `flutter analyze` | Clean after QA lint cleanup. |
| Final full Flutter suite | **1,722 passed, 11 skipped**, all green. |
| Screenshot generators | All passed in both full-suite runs; output inspected under `build/shots/run/`. |

Use the SDK/JDK environment from AGENTS.md, then:

```bash
flutter test -j 3 --no-pub test/e2e/p3_gameplay_e2e_test.dart test/e2e/p3_interactions_e2e_test.dart
flutter test -j 3 --no-pub --run-skipped test/e2e/p3_interactions_e2e_test.dart --plain-name S6-
flutter test -j 3 --no-pub --run-skipped test/e2e/p3_interactions_e2e_test.dart --plain-name S6-46
```

Evidence logs: `/tmp/p3-pubget.log`, `/tmp/p3-analyze.log`, `/tmp/p3-tests.log`,
`/tmp/p3-e2e-final.log`, `/tmp/p3-repros-final.log`,
`/tmp/p3-analyze-final.log`, `/tmp/p3-tests-final.log`, `/tmp/p3-p2-fixes.log`. Logs and generated
PNGs are local artifacts, not committed. Screenshot writes outside this
worktree (`../flappy_spikes/store/...`, `../shots`) were ignored/not staged.
Pixel 8 was not used. No native audio/haptics, device heap profile, backend
emulator or production Firebase telemetry delivery was exercised this round.

## P2 fix re-verification

The active S6-20–24 regressions passed in both full gates and a focused
re-verification (six tests):

| ID | Reverified behavior |
|---|---|
| S6-20 | Phoenix safe line follows the next tilted hoop whose extent remains ahead. |
| S6-21 | Idle/urgent heartbeat peaks match 1.035 / 1.06. |
| S6-22 | Interrupted claim/startup recovery credits the recorded reward exactly once. |
| S6-23 | NEXT keeps its 65 pt bottom gap and button size at 568 pt. |
| S6-24 | CLAIM renders the unmodified shared coin and its pale inner ring. |

## New end-to-end coverage

All new integration journeys run at **568 and 711 pt**.

| Journey | Result / limits |
|---|---|
| Natural all-elements course, 180 s, seeds 7 / 21 / 1234 | 568: **109 / 107 / 109** hoops; 711: **107 / 105 / 106**. No natural deaths; no god mode. All registered elements allowed, not forced. Aggregate courses meet every newly built element; individual random runs need not collect every pickup. |
| 390 s fixed-frame soak, seed 1234 | God mode used only to guarantee duration. Game clocks **381.84 s / 390 s**, passes **246 / 242**. Recursive mounted count initially 103, then **56–87**, ending 63 / 72; no upward trend. Hoops/pickups each remain below 12. This checks mounted component growth, not native heap leakage. |
| Portal + Hourglass | All six themes, both heights: actual portal entry suspends effect/timer, restores timeScale 1; pause freezes ride/exit/flight/glide; landing resumes 0.45× and real-time countdown. |
| Comet + squeeze | Actual 10 s boost; scheduled squeeze waits until its end+2 s. Pause freezes boost and warning/closing/hold/opening. |
| FEVER + streak + Big Hoops + Coin Frenzy | Real FEVER ignition, streak≥5, frenzy earnings/expiration. Back/front painting restores Big Hoops gold and 7 pt stroke after temporary frenzy colors; fire survives effect end. Pause passes. S6-40 tests real rim contact separately. |
| Black Hole + squeeze + FEVER shake | Real Black Hole, squeeze warning seam and FEVER shake component. Spike-strip lensing nonzero; pause freezes state; reopening clears inset/flash and camera returns. |
| Mini Bird + switch/pair/saw | Pair/saw pass repeated forced courses with Mini active. Switch fails at both heights (S6-44); full-size controls pass. |
| Death/revive after each element | 36 journeys: force actual element, observe collection/pass/start, pause, reach ≥6 passes, exhaust saves and die, actual heart-button revive, phoenix, then two more hoops. Timed effects/fire end, bank/jar/egg state is lost, earned coins/score remain, offer/phoenix freeze runClock, squeeze resets, x returns 70 with ≈2 s protection. God mode only while reaching target effects; absent collectable state is populated via a test seam to verify shared cleanup. |
| Director | 6000 unforced slots, 30 seeds, all registered/met: unlocks, same-kind distances and cooldowns pass. All six ride contexts produce plain upright/still hoops and empty gaps. Squeeze permits only normal/saw/FEVER/bullseye and heart/trail when no bank/jar is running; running bank/jar violates this (S6-46). |
| Debug force menu | Every one of the 18 new element IDs is present, including SQUEEZE; all six ride IDs covered. |
| Analytics | Long journeys terminate through actual death/decline flow and assert one run summary, integer director counts with ≤25 params, spawn-event counts for FEVER/saw/switch/pair, and earnings amount/source/egg_x2. Existing per-element analytics tests pass; source review finds all built §6 events wired. S6-40 affects graze fire-out timing/cause. |

## PRD number/rule review

Source/config comparison was checked alongside the existing numeric,
director, physics, feature, autopilot, sound and screenshot suites. Passing
unit tests alone are not treated as proof of interaction correctness.

| Element / PRD | Numbers and rules checked | Conclusion |
|---|---|---|
| Comet §3.8 |10 s, 1.7×, 0.45 s acceleration/ 0.9 s landing; 10–30 first/+45–60; 20 pt past upright normal plane; forced-perfect coins/streak, ignores input, existing hoop handling | Match; combined squeeze journey passes. |
| Portal §3.12 / §5.12b |25–50 first/+40–60, comet distance10; six themes/no immediate repeat; 480 pt/s/ 2.2 s; 11 path rings+portal; cannon380 pt spacing/ 190 first, 180/ 220 radii, 1600 climb; 560/ −640/g520 launch, 1.7 s flight/ 2.5 s glide; tint/strip/teeth return and paused capsules | Feature/path tests and all theme journeys pass; S6-41/ 47 clearing discrepancies. |
| Squeeze §3.17 |60–120 run seconds, 1.5 warning/ 3 close/random10–20 hold/ 3 open; 50/ 45/ 40/ 35% viewport opening with230 pt floor; 3 s lookahead, rides/revive wait+2 s, reopen0.5 s on revive | Timing/floor/pause/reset pass; S6-46 gap exclusivity. |
| Saw §3.18 | Three equal/nonrepeating designs; rims5/ 5/ 6 pt,+28 opening; pull260/ 570 within34 pt, 0.9 s inhale every3.4 s; from20, weights18→26 at45, min3; save consumes once; keep themed art | Numeric, collision/save, death, forced autopilot and combined lensing tests pass. |
| FEVER §3.19 | max(5,streak+1), cap10; unchanged coins/score; from15 weight6/min20; no adjacency saw/portal, not when already lit; rides keep existing fire | Match except S6-40 immediate graze/fire-out. |
| Switch §3.20 | Five equal/nonrepeating designs;≥150 pt or1 s lead, 70–100 offset,≤110 from previous; touch pays+1, opening≤0.8 s, pass/save/closed death; from12 weight16/min8 | S6-45 placement bound; S6-44 debug Mini combination. |
| Pair §3.21 |230×height/ 711 separation, different weighted gifts; SHIELD/COMET/+10 coins/+5 score/FEVER, one pick; skip fade0.45 s to0.6; from12 weight10/min15 | Rules/payments pass; S6-43 coin art. |
| Train §3.22 | Three rings56 pt apart/±16 pt; each scores, all three +3; graze still qualifies, saved miss cancels; from8 weight14/min10/cooldown2 | Match. |
| Spring §3.23 |−770/+420 velocity, 0.45/ 0.28 lock, next ring240 pt away; both directions need band room; from10 weight12/min10/cooldown2; no squeeze | Match. |
| Bullseye §3.24 | Fixed±12 pt center band, +3; from6 weight20/min6; unchanged normal pass outside target | Match. |
| Lucky Spin §3.25 | Equal slices2/ 5/ 10/ 3/ 20/ 5, preroll layout seed,≈0.9 s stop; from15 weight8/min18 | Match. |
| Star Trail §3.26 | Eight stars, 40 pt insets/upward bulge; only8 pays+5; from5 weight30/min8; empty gap | Match except S6-42 partial pop sound. |
| Egg §3.27 | Five passes incl. ride rings; chick doubles all in-run earn sources; rim/save/death loss; from10 weight12/min15, at most one | Numeric/earn/loss/ride tests pass. |
| Piggy §3.28 | Exactly20, four immediately+four in each next four gaps; caught coins withheld until ×2 payout; saves retain/death loses; from12 weight10/min30, excludes jar | Match ordinary flow; S6-41 portal completion and S6-46 squeeze. |
| Jar §3.29 | Seven per swarm, catch20→+25, escape3→no reward, 16 pt radius; saves retain/death loses; from15 weight10/min30, excludes bank | Match ordinary/portal flow; S6-46 squeeze. |
| Hourglass §3.30 | One capsule slot, type weights35/ 35/ 30; from10 weight20/min20; 10–20 real seconds, 0.45× game, 0.2 easing, music0.72, tick0.6 s; ride suspends | Match; six-theme integration passes. |
| Mini §3.31 |0.52 scale/hitbox for8 s, 0.15 s easing, unchanged physics/growth rim bounce | Feature tests pass; debug bot interaction S6-44. |
| Frenzy §3.32 |6 s, every unresolved hoop gets coin painter/+5 in addition to ordinary pay, chick stacks; pooled sprite shower, restores original painters | Match; FEVER/Big Hoops combined test passes. |

The mirrored budget rows are special/optional-gap probabilities
**0/ 0, 0/ 0.25, 0.25/ 0.25, 0.35/ 0.33, 0.45/ 0.33, 0.60/ 0.33** at
indices 0/ 5/ 8/ 20/ 35/ 50. These are roll probabilities, not realized shares:
cooldowns, empty eligible pools and fixed schedules change observations.
Existing 300-seed prototype-share tests pass (including attached switches in
occupied-gap counts). The new 6000-slot sample observes table-special shares
0/ 0/ 17.78/ 22.00/ 25.78/ 31.47% in these six bands, and 1628 occupied gap
plans/ 6000; that last figure excludes switches attached before their rings.
The pure sample has no simulated ride collection/squeeze and is informational.

The all-elements first-meet queue tests pass across 30 seeds; isolated
within-five guarantees pass across 25 seeds per catalogue element. The
render-entry persistence regression S6-03 also passes. Natural courses
exercise the registered queue; no unbuilt element is reported missing.
ARCH's oldest-unlock queue and patience deferral remain documented calls.

## Visual and sound audit

Every screenshot generator ran, producing both 568/ 711 variants where
specified. Compared the following approved PNG families in
`design/menu_v2/` with actual `build/shots/run/**` output using side-by-side
contact sheets (not pixel-identical goldens):

| PRD section | Approved references compared | Actual family |
|---|---|---|
| §5.6 | `boost_active`, `boost_tier` | `comet/` |
| §5.12 / §5.12b | `portal_4`, `portal_6`; every `ride_{space,volcano,sea,pinball,storm}_{1, 2, 3}` | `rides/` all themes/phases |
| §5.16 | `squeeze_hold1`, `squeeze_hold4` | `squeeze/` |
| §5.17 | `sawring_{electric,ice,hole}_{fly,death}` | `hazard/` |
| §5.18 | `fever_pass`, `fever_burning` | `special/` |
| §5.19 | Every `switchring_{lock,laser,iris,sleepy,gift}_{off,open,fail}` | `rings/` |
| §5.20 | `giftpair_pick` | `rings/` pair |
| §§5.21–24 | `lab_train`, `lab_spring`, `lab_bull`, `lab_lucky` | `special/` |
| §§5.25–28 | `lab_trail`, `lab_egg3`, `lab_piggy3`, `lab_flies3` | `collect/` |
| §§5.29–31 | `lab_slow2`, `lab_mini2`, `lab_frenzy` | `capsules/` |

Clear new visual defects are the pair's solid coin discs (S6-43) and the
portal removal transition (S6-47, raster reproduction). No other clear new
element-art mismatch was confirmed in the inspected pairs. Reference
timestamps, course positions, skins and scores differ; these are not golden
pixel comparisons. Shared giant score circle, master top 190 banners and
pass coin popups supersede older mock variants. Solo omits versus boxes;
the equipped trail can differ from the mock's block trail. The timer pill's
y 156 and collectable badges above the centered score circle are explicit
ARCH/SPEC layout calls, and were not filed as accidental rendering bugs.

SOUNDS registry/assets/pool tests pass. Source audit and existing feature
recorders cover the built elements' cue/loop requests. Partial Star Trail's
`trailPop` is unwired (S6-42). **`swClear` is intentionally not requested
separately:** SOUNDS' implementation notes explicitly mix that chord into
each switch `*_open` clip; the independent opening cue is already played.
Versus-only cues are outside scope. Verification observes SoundService
requests and asset loading; audible playback on Android was not tested.

## Fix round P3-R1 decisions (2026-10-08)

All eight regressions are active (skips removed, assertions unchanged).

- **S6-40:** `FeverFeature` listens to `RimTouched` and puts the fire out (cause `graze`) at the contact; rim contacts during a ride are ignored (rides keep the fire).
- **S6-41:** PRD wins: `PiggyState.voided` is gone; portal-cleared (and pending planned) bank coins are refunded to the director (`refundPiggyCoins`) and placed again after the landing; payout only at caught + missed = 20. ARCH §25 / SPEC updated; `s3_28_piggy_test` portal case rewritten to the PRD rule.
- **S6-42:** the partial "n / 8" pop plays `Sfx.trailPop`.
- **S6-43:** new `ParticleShape.coin` draws master #14 (`CoinIcon.paint` from `menu/coin.png`); the +10 COINS spray uses it.
- **S6-44:** the autopilot plans the closed-switch approach with a physics rollout (same controller family as the ring planner, reach = 18 + bird r × birdScale − 3) instead of the bang-bang hover.
- **S6-45:** the switch is chosen inside 70–100 pt of its ring ∩ ≤ 110 pt of the previous centre ∩ item margins; with no such spot the ring moves to the nearest band height that has one (else the slot becomes a normal hoop). `switchMinFromRing` removed.
- **S6-46:** running bank / jar fields are not placed in the squeeze window; the bank keeps its owed coins for after the reopening.
- **S6-47:** a `ClearFade` mixin on hoop halves and pickups fades `clearAlpha` 1 → 0 over the clear's 0.2 s (one translucent layer), then the spawner removes them.
