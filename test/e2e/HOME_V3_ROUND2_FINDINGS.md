# QA round 2 — Home v3

Reviewed `hv-qa`, product baseline `e56a744`, on 2026-10-07 against
`PRD-home-v3.md`, `PRD-2-gameplay.md` §3.33, `CLAUDE.md`, `SPEC.md`, and
`.worktrees/briefs3/{common,wpF,wpG,wpH,wpI}.md` in the workspace root.
Product code is unchanged. This commit adds the independent round-2 suite
and this report only. No generated images, external tablet outputs, or
signing files are included.

`flutter pub get` passed. Baseline `flutter analyze` was clean; baseline
`flutter test --reporter expanded` passed **645 tests**, including every
round-1 defect regression. The final suite passes **657 tests**, with
**five explicitly skipped reproductions for four new open findings**.
Final `flutter analyze --no-pub` is clean. Enabling the reproductions fails
all five at their intended contract assertions; the 12 new normal journeys
pass in that run too.

Severity: major = broken celebration/economy flow; minor = accessibility
or avoidable allocation. These IDs continue after the round-1 IDs
S1-30 and S2-30–33.

| ID | Severity | File:line | What's wrong / reproduction | Expected / PRD |
|---|---|---|---|---|
| S1-31 | Major (feedback; no lost or duplicated saved coins) | `lib/components/ui/coin_reward.dart:340`; `lib/game/flappy_game.dart:1240` | Start with coins 1,250, unclaimed best 10. Tap No ads with fake billing delayed two seconds. Let EGG catch-up open; deliver success, which queues the No-ads celebration. Claim EGG and leave the No-ads card open four seconds. The pill counts to **2,300**, including the unclaimed No-ads bonus, instead of **1,300**. The later No-ads CLAIM has no remaining +1,000 to count. Each reward targets the entire live wallet and releases the same pill hold. | Each celebration counts its own reward at its CLAIM: EGG +50, then No ads +1,000. PRD §4.3, §5, §7 CLAIM; WP-I §3 explicitly requires correct bonus presentation. Queue serialization alone does not serialize the count-ups. |
| S1-32 | Major (conditional receipt redelivery/economy) | `lib/game/purchases.dart:178`; `lib/services/iap_service.dart:510` | Reinstall-style prefs: coins 1,250 and no local No-ads ownership. Without initiating a buy, use the real `StoreIapService` with `FakeStore` to replay an **old** No-ads `PurchaseDetails` with status `purchased`, an existing purchase ID and an old transaction date. Ownership becomes true, but the app also opens the fresh-purchase celebration and credits another 1,000. The adapter discards receipt identity/date and the grant checks only the local ownership bool. | Recover owned state without celebration or a fresh bonus for a previously completed receipt. PRD §7, common decision, WP-I §3: fresh purchase only, never restore/redelivery. This is proven for **old receipts delivered as `purchased`**; explicit `restored` events and redelivery with the local owned flag intact pass. Real Play delivery of this fixture was not exercised. |
| S2-34 | Minor (accessibility) | `lib/components/noads_celebration.dart:83`; `:177`; `:270` | Buy No ads with motion enabled. At 0.2 seconds into the celebration, enable the game's reduce-motion override and advance 0.05 seconds. The card remains at scale **1.0515**, angle **0.015 rad**, and the icon is still wobbling at scale **1.0754**, angle **−0.0974 rad**. The card returns early without resetting its pose, while the header keeps the motion flag captured at construction, so its rays/sparkles also continue. | Changing the accessibility setting must settle the card and stop header motion, as the live home/LEVELS emblems already do. PRD §3.2 / carried-over PRD-menu-v2 §8.4; §7 reduce-motion behavior. Tested through the override, not an actual OS setting change. |
| S2-35 | Minor (performance contract; no measured jank) | `lib/components/levels/emblem_view.dart:104`; `lib/levels/emblem_painter.dart:143` | Paint warmed unranked frames at t=0.2 and t=0.3. A new native octagon Path is drawn on the second frame. Also render an unranked `EmblemView` at those phases: it reports uncached painting because the ranked sweep interval is treated as active even though the unranked painter has no sweep. This repeats during the first 28% of every 6.4-second idle cycle. | Reuse the static unranked geometry/picture; no imaginary sweep should force it to repaint. PRD §11 (cached paths, no per-frame allocations), WP-G performance and WP-H §2 static-picture requirements. Two failing checks pin the allocation and the view's cache bypass. |

Run the normal suite with:

```bash
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH" \
  ANDROID_HOME="$HOME/Android/Sdk" JAVA_HOME="$(ls -d $HOME/opt/jdk-17* | head -1)"
flutter test test/e2e/home_v3_round2_e2e_test.dart --reporter expanded
```

Enable the open findings explicitly (this command intentionally fails):

```bash
flutter test test/e2e/home_v3_round2_e2e_test.dart \
  --dart-define=QA_VERIFY_OPEN_DEFECTS=true --name 'S[12]-' --reporter expanded
```

The string `skip: 'Sx-xx open'` is on enclosing groups because FlameTester's
test method accepts only a boolean skip.

The new normal journeys cover:

- Fresh install at **640 and 730** → actual START tap → real Forge2D flight
  and scoring to 12+ → natural death → replay tap → stage-0 home → LEVEL UP
  → CLAIM → EGG current/reached on LEVELS → return without a second popup.
  Round 1 supplies the same complete journeys at 568 and 711.
- Existing LEGEND catch-up pays the complete **10,350** once, including a
  rapid second action on the fading card; LEVELS shows MAX LEVEL, all rows
  reached and the current row scrolled into view; persisted wallet verified.
- A fake 5,000 pack purchase counting while the player moves through
  Shop → home → LEVELS → home: correct persisted balance, 12 landing sounds,
  released pill, no stranded confetti. Round 1 verifies all four exact
  pack presets, monotone count-up and payoff sounds.
- Delayed cancellation/failure/pending while navigating from Shop to
  Settings: result on the current menu, dim dismissals, unchanged saved
  wallet, failure analytics retained, no popup for pending.
- No-ads ✕ claims exactly once, survives repeated dismissal, persists
  ownership and bonus, and shows the owned tile/slot. Delayed fresh success
  during a run queues until home, celebrates once and completes the claim.
  Round 1 covers all three purchase sources, Shop/GET owned states,
  restore and same-install redelivery silence.
- Real Settings RUMBLE presses: off silent, one knock on enable, persisted
  setting after reopening, no pulses throughout an actual 12+ scored run
  and its death. The START menu press itself may knock. Round 1 also checks
  menus with stored rumble off; focused tests verify throttle and shake.
- Changing reduce motion on a live LEGEND home freezes the emblem, then
  opening LEVELS keeps both header/current-row emblems static. Round 1
  verifies reduced-motion coin/No-ads rewards still finish correctly.
- A fresh Settings screenshot after a Shop round trip verifies the visible
  shared back box as well as its geometry, mounting and opacity.

The full gates ran the screenshot generators, including
`home_v3_screenshot_test.dart`, `purchase_feedback_screenshot_test.dart`,
`coin_reward_screenshot_test.dart`, and `levels/emblem_generator_test.dart`.
Inspected the generated PNGs against all supplied `home_v3*.png`,
`levels_*.png`, `coinbuy_*.png`, `purchase_*.png`, `noads_*.png`,
`settings_v3.png` and `shop_v3.png` references. Comparison sheets are
`build/qa-r2-visual-{1..6}.png`, with four-height home layout in
`build/qa-r2-heights.png`; original captures remain in
`build/menu_shots/` and `build/emblem_check/`.

No additional static visual defect was confirmed. Home centre/side
alignment, large-number shrink, emblem silhouettes/colours, LEVELS states,
purchase cards, owned states, Settings and Shop match the intended layout.
Reference/generated seeds differ for best/last scores, wallet, featured
skin and powerup. Reduced-motion captures suppress glow/confetti; differing
purchase phases change the count and floating reward label. The later
`coinbuy_end2.png` confirms the payoff label/confetti missing from the early
WP-I end capture. The WP-I Settings screenshot omits the corner box after
its sequence of capture/resizes; the independent fresh-size capture
`build/menu_shots/r2_settings_back_probe.png` confirms that it is visible.
Settings' labels at x130 follow the approved mock and Config; the prose
x115 in PRD §8 conflicts with that reference and is not a product finding.

The level table and rewards match §4.1/4.2 (10,350 total). Required analytics
are exercised by the combined E2E suites: levels_open, level_up,
level_reward_claimed, purchase_result_popup, rumble_toggle,
noads_celebration_shown and noads_bonus_claimed. Menus return to stage 0
after real runs. SFX still use preloaded low-latency AudioPools; the new
No-ads jingles are registered, and no bare FlameAudio.play or MediaPlayer
SFX path was introduced. Shop has no RESTORE; Settings retains RESTORE
and Privacy Policy. No iOS changes were made.

Confetti is finite and expires (at most 90 burst + 90 rain for No ads;
150 at a pack payoff). No unbounded particle emitter was found. Static
LEVELS row Pictures are cached/disposed, but grey pictures still replay
their recorded saveLayer: picture caching does not eliminate the raster
compositing cost. Animated flag/flame geometry, opacity-transition layers,
and the production Rumble.fired list's app-lifetime growth remain profiling
observations, not demonstrated frame-time defects. S2-35 separately proves
avoidable allocation in an entirely static emblem.

This was a headless Linux/fake-billing pass. Hardware pulse amplitude,
real Play callback timing, physical-device frame times and OS accessibility
propagation remain unverified. The tablet generator's files outside qa3
were ignored and are not part of this commit.
