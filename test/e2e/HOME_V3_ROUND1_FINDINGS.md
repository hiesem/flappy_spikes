# QA round 1 — Home v3

Reviewed branch `hv-qa`, product baseline `26c6feb`, on 2026-10-07 against
workspace `PRD-home-v3.md`, `PRD-2-gameplay.md` §3.33, `CLAUDE.md`,
`SPEC.md`, and `.worktrees/briefs3/{common,wpF,wpG,wpH,wpI}.md`.
Product code is unchanged. Only this report and the independent regression
suite are committed. No screenshot files, external tablet outputs, or
signing files are included.

`flutter pub get` succeeded. Baseline `flutter analyze` was clean and the
full baseline suite passed **609 tests**. The QA suite adds **25 passing
checks/journeys and six skipped reproductions for five open findings**.
Final `flutter analyze` is clean and `flutter test --reporter expanded`
passes **634 tests, with six explicitly skipped open-defect cases**.
Running the six reproductions unskipped fails each at its intended contract
assertion, with no setup/compilation/teardown failures.

## Findings

Severity: major = broken user flow; minor = presentation, accessibility or
allocation-contract mismatch. IDs are new, starting at 30 to avoid older QA IDs.

| ID | Severity | File:line | What's wrong and reproduction | Expected / basis |
|---|---|---|---|---|
| S1-30 | Major | `lib/game/flappy_game.dart:1340` and `:1355` | No-ads success ignores an existing LEVEL UP popup. Start with an unclaimed EGG best (10), buy No ads before the 0.35 s home-settle delay, leave billing pending while catch-up opens, then deliver success. Both `levelUpPopup` and `noAdsCelebration` are live, both cards render, and both are registered on the back stack. The reproduction captures the overlapping cards in `build/menu_shots/qa3_S1-30_two_popups.png`. | Serialize the popups; retain the fresh-purchase celebration until the current card has closed. Common brief's LEVEL UP trigger decision and WP-H §6: **never two popups**; PRD §4.3/§7. The test does not assert lost coins. |
| S2-30 | Minor (accessibility) | `lib/components/levels/level_up_popup.dart:276` | Under reduce motion, LEVEL UP disables the sweep but still advances `emblem.t = _t + 1` each frame. With best 5,000 and levels 1–9 claimed, enable reduce motion, leave the LEGEND popup open, and advance one second: emblem phase increases by one second. Flags, galaxy stars, rainbow ring and emblem rays continue animating. | Freeze the emblem's clock as on home and LEVELS. PRD §3.2 reduce motion: **no emblem animation**; WP-H §2 and §6 tests. Tested with the game's reduce-motion override; the physical OS setting is not tested headlessly. |
| S2-31 | Minor (animation order) | `lib/game/flappy_game.dart:1193` | The home emblem upgrade pop starts immediately after the wallet claim, before the first reward coin lands. Claim EGG; at +0.1 s the pill still shows the old balance, while `homeScreen.popping` is already true. Its 0.7 s animation finishes while the coin count-up is still running. | Run the reward flight/count-up, **then** the 0.7 s home upgrade pop. PRD §4.3 CLAIM sequence and WP-H §5. |
| S2-32 | Major | `lib/game/flappy_game.dart:1293` | A late canceled or failed purchase is discarded during a run. Start a delayed No-ads purchase, press START while billing is pending, deliver cancellation/failure during play, die and return home. `purchase_result_popup` is logged, but no popup appears either during play or after returning home. Both outcomes have failing reproductions. | Show the result for every cancellation/failure (§6 and common decision); if gameplay blocks presentation, retain it for home. Pending alone still produces no result popup. The test does not require an interruption of the run. |
| S2-33 | Minor (performance contract) | `lib/levels/emblem_painter.dart:217` | The otherwise static FALCON light sweep builds a new coordinate list and native `Path` every visible-sweep frame. Draw warmed FALCON frames at t=0.2 and t=0.3 using the Canvas recorder: the second draw contains one new Path identity; all other drawn Paths are reused. | Cache the sweep geometry and translate it at draw time. PRD §11: cached paths, no per-frame allocations; WP-G performance requirement. This demonstrates allocation, **not measured device jank**. |

## Reproduce open findings

From the QA worktree:

```bash
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH" \
  ANDROID_HOME="$HOME/Android/Sdk" JAVA_HOME="$(ls -d $HOME/opt/jdk-17* | head -1)"
flutter test test/e2e/home_v3_round1_e2e_test.dart \
  --dart-define=QA_VERIFY_OPEN_DEFECTS=true --name 'S[12]-' --reporter expanded
```

Default runs use `skip: 'Sx-xx open'` on enclosing groups because
FlameTester's own skip argument only accepts a bool. The override above
enables all six reproductions.

## Enabled regression coverage

- The exact ten ranks, threshold boundaries and rewards (10,350 total).
- Fresh install at 568 and 711 → actual START tap → real Forge2D flight and
  pipe scoring to at least 12 → natural collision → actual replay tap →
  home at stage 0 → LEVEL UP → actual CLAIM tap → persisted +50 and claimed
  EGG → actual emblem tap → LEVELS reached/current/locked states → back home
  without a second popup. No best/score/wallet injection in these runs.
- Existing best 640 → launch upsell first → one FALCON catch-up card paying
  1,550 → ✕ claims → wallet/claimed-level persistence reload → LEVELS opens
  scrolled to FALCON → back home without another award. A second claim pays 0.
- Home side/centre alignment, plate-centred BEST/LAST, non-overlapping and
  approximately even START gaps, and large-number shrink at 568/640/711/730.
  Fresh-install journeys also verify unranked and LAST's pre-run em dash.
- All four coin packs through fake billing and real Shop pack taps: exact
  flight/count/confetti presets, intermediate monotone balances, exact final
  saved balances, landing/tick/jingle/progress sound order, IAP/earn analytics,
  and complete confetti expiry.
- Cancel, fail and pending for both coin packs and No ads: exact popup titles,
  result/error analytics, unchanged balances, OK dismissals, and no result popup
  or celebration on pending. Existing focused tests cover ✕/dim/Esc as well.
- Fresh No ads from tile, Shop banner and launch popup → grant once → held
  balance → CLAIM count-up → owned tile/banner/GET/slot → persistence reload
  → no celebration or bonus on restore/redelivery. A separate reinstall-style
  journey restores a store-owned purchase through Settings with no celebration
  or bonus, then verifies the home owned state.
- Real Settings rumble presses: off silent, enable knocks once and buzzes,
  persisted on/off values, stored-off menu silence, and no pulses on gameplay
  taps, score sensors or death. The START menu press itself still knocks.
- Reduce motion: static home emblem and no random bird actions; coin/No-ads
  grants still count correctly, with no confetti, No-ads flash or screen shake.
  S2-30 pins the popup's remaining failure separately.

## Visual and invariant audit

The full suite ran `home_v3_screenshot_test.dart`,
`purchase_feedback_screenshot_test.dart`, `coin_reward_screenshot_test.dart`
and `levels/emblem_generator_test.dart`. PNGs are in `build/menu_shots/` and
`build/emblem_check/`; none are committed. Inspected comparisons against all
`home_v3*.png`, `levels_list.png`, `levels_levelup.png`, `levels_emblems.png`,
`coinbuy_*.png`, `purchase_*.png`, `noads_*.png`, `settings_v3.png`, and
`shop_v3.png` references. Generated comparison sheets are
`build/qa3-visual-{1..5}.png`, `build/qa3-heights.png`, and
`build/qa3-emblems.png`.

Home layout at all four heights, emblem silhouettes/colours, LEVELS list and
popup geometry, purchase-result cards, No-ads card/owned states, Settings and
Shop chrome closely match the approved static references. Different seeded
balances/featured skins, frozen motion in the home generator, and purchase
animation capture times explain the corresponding screenshot differences;
they are not classified as visual defects. Shop has no RESTORE; Settings
retains RESTORE and Privacy Policy. No additional static visual defect was
confirmed in this pass.

The SFX path still uses preloaded `AudioPool.create(...,
playerMode: PlayerMode.lowLatency)`; no bare `FlameAudio.play` or
MediaPlayer SFX path was introduced. New jingles are registered and pooled.
Menu stage-0 restoration is checked after the actual scored runs, and menu
screens continue reading those stage colours. No iOS changes were made.

Static non-current LEVELS row emblems are recorded once as Pictures and
disposed on removal; live views cache when frozen. An allocation mismatch
is recorded as S2-33. Other dynamic flag/flame shapes also rebuild geometry,
and grey locked-row Pictures record `saveLayer(null, _greyPaint)`
(`emblem_painter.dart:119`), so picture replay still includes compositing.
These are device-profiling concerns; caching a Picture alone does not prove
there are no raster-layer costs. No frame-time/jank claim is made without
physical-device profiling. Confetti counts are finite (largest No-ads burst
90 + rain 90), have fixed lifetimes, and the pack journey confirms removal.
The Rumble recorder also appends to `fired` in production; this is an
app-lifetime growth risk to watch, rather than an observed failure in this pass.

This pass uses channel-free Linux/headless tests and generated captures.
Real Play billing, hardware pulse amplitude, physical-device frame timings,
and the OS accessibility-setting propagation remain unverified.
