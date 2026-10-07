QA round 1 — skin shop v2 tweaks (WP-J1/J2), 2026-10-07.

Reviewed `s2-qa` against briefs4/common.md, wpJ1.md, wpJ2.md, workspace
CLAUDE.md / AGENTS.md and the skin-shop / Home v3 sections of SPEC.md.
Product code is unchanged. IDs start at S1-50 / S2-50 as requested.

`flutter pub get` succeeded. Baseline `flutter analyze` was clean and the
full `flutter test --reporter expanded` passed **689 tests**. With this QA
suite, analysis remains clean and the full suite passes **701 tests, with
three explicitly skipped open defect reproductions**. The new suite has
12 passing journeys and three reproductions. Each reproduction was run
unskipped and failed at its intended product assertion.

| ID | Severity | File:line | What's wrong | Reproduction | Expected / basis |
|---|---|---|---|---|---|
| S1-50 | High | `lib/components/menu_screen_chrome.dart:459`; `lib/components/skins/item_tile.dart:165` | Drag slop is inherited from Flutter's default touch recognizer, rather than the specified ~6 world points. A 10-point drag never becomes a scroll, so tile tap-up still triggers a purchase. | At 320 × 568, start with 1,000 coins. Home → Skins → tap Sky once. Press Sky, move upward 10 points, hold 80 ms, release. Sky becomes owned/equipped, balance becomes 850 and `item_purchase(source: tile)` fires. | WP-J1: travel beyond ~6 pt cancels the child press and scrolls; WP-J2: only a real second tap buys. This gesture must leave the balance and ownership unchanged. |
| S1-51 | Medium | `lib/components/menu_screen_chrome.dart:146`; `lib/game/flappy_game.dart:466` | The stop-tap gate is a child of the priority-20 menu screen. The shared priority-21 coin pill receives touches first and bypasses it. | Home → Skins → flick upward 60 points over 60 ms. While `isGliding` is true, tap the shared top-right coin pill. The app opens Shop and logs `shop_open` instead of merely stopping the list. | common.md decision 1 / WP-J1: a touch during a fling or spring stops motion and presses nothing under the finger, including fixed controls. Stay in Skins without a Shop action. |
| S2-50 | Low | `lib/components/menu_screen_chrome.dart:389` | Fling velocity decays exponentially, but displacement uses forward Euler (`v0 * dt`). Distance therefore changes with frame interval. | At 320 × 568, reset Birds to offset 0, flick upward 60 points over 60 ms, then advance exactly 1 second at 30, 60 and 120 fps. Post-release distances are **365.45 / 357.53 / 353.61 pt**. No bounds are reached. | WP-J1's frame-rate independence: identical input and elapsed time should have the same trajectory within negligible numerical error. 30 fps adds 11.84 pt (3.35%) over 120 fps. The reproduction allows 1 pt. |
| S2-51 | Low, visual only | `lib/components/skins/preview_stage.dart:284`; `lib/skins/art/bird_art.dart:198` | Rubber duck's high head anchor places the Wizard cone above the preview's clipping rectangle. Its pointed tip is cut flat at the stage's top edge even after the equip hop settles. | Equip Rubber duck and Wizard, open Hats and wait for the hop to finish. See **build/menu_shots/s2_qa1_rubber_duck_hat_wizard.png**. The stage begins at world y=126; the cone tip is about 10–16 pt above that edge over the idle bob. | WP-J2's requirement to check fitting with every hat: the complete attached Wizard hat should be visible in the idle live preview. The captured journey records this visual-only defect; it has no pixel assertion. |

Reproduce the three automated findings (this command intentionally fails):

```bash
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH" \
  ANDROID_HOME="$HOME/Android/Sdk" JAVA_HOME="$(ls -d $HOME/opt/jdk-17* | head -1)"
flutter test --no-pub --run-skipped --name 'S[12]-5' \
  test/e2e/skin_shop_v2_round1_e2e_test.dart --reporter expanded
```

The `skip: 'Sx-xx open'` reasons live on groups because FlameTester's own
skip argument accepts only a bool.

Passing coverage uses real GameWidget pointer events and real game,
wallet and persistence flows, with plugin-free analytics/ad/IAP services:

- First tap → BUY pill and a 1.06 pulse → moving try-on between tiles →
  second tap in a tile corner → one purchase/celebration → saved wallet and
  equipped Home look, at both 568 and 730 pt heights.
- Unaffordable second tap → grey still BUY pill → no-coins toast, flashing
  coin pill and analytics → tab switch clears try-on → a first tap after
  returning to Birds only tries on → the top-right BUY still buys.
- Try-on → fling → stop-tap on that same BUY tile cannot become a purchase
  → the following real tap buys. Fixed preview BUY and Back also stop
  motion without acting on the stop touch.
- Reduce motion freezes both BUY pulses and purchase rays while momentum
  still continues after release.
- Home → each of Skins / Shop / LEVELS → release momentum and deceleration
  → stop touch → new drag → animated scrollTo cancels the fling → bottom
  rubber band → spring-stop hold/release → exact bound → top rubber band
  → take over a spring with a drag → settle in range → Back to Home.
- A 4 pt drag still taps; a long drag cancels the tile press and cannot buy.
- Release velocity follows the final 60 ms of a slow-then-fast gesture
  (1,000 pt/s). A stationary sample after a pause prevents stale momentum.
- Buy Rubber duck → equip all 14 gear and all 14 hats through their tiles
  → retain duck and selected items in the preview, storage and Home.
- Buy Rubber duck → buy Shades / Cap through tile and button paths →
  attached Home outfit → START and flap → real physics collision / dead
  pose → Home with the outfit retained.

Visual review used the generated **build/art_check/rubber_duck.png** sheet
(duck versus Chick, idle/flap/dead/blink, all 14 hats and all 14 gear) and
the actual-game **build/menu_shots/s2_qa1_*.png** captures. The duck has a
distinct boat body and upturned tail, yellow body, blue head band, white
gloss highlight and large red-orange bill. Standalone accessories attach
correctly; the Wizard preview clipping is recorded above. The duck keeps
the catalogue identity `duck`, name “Rubber duck”, Rare, 750.

Physics feel was evaluated through deterministic pointer/frame journeys
and rendering; this pass does not claim hands-on phone testing. Additional
builder tests cover velocity-dependent distance, growing edge resistance,
instant scrollTo cancellation and spring rest. Tablet store screenshots
written outside this worktree were ignored. Only QA tests and this report
are committed; generated images and logs remain under ignored paths.

## Fix round 1 (branch `s2-fix1`, 2026-10-07)

All four findings are fixed; the reproductions run unskipped and pass
(full suite 707 green, analysis clean).

- **S1-50 fixed.** The game registers its own drag dispatcher
  (`lib/components/menu_drag_dispatcher.dart`) whose recognizer slop is
  `Config.menuScrollSlop` = 6 world pt (converted at the camera scale) while
  a `MenuScrollArea` is mounted. Past 6 pt the drag wins the gesture arena,
  so the pressed tile / button gets a tap cancel: no try-on, select or buy.
- **S1-51 — ORCHESTRATOR DECISION (native mobile behaviour), behaviour
  changed instead of the original expectation.** The stop-the-glide gate
  covers only the list viewport. A tap INSIDE the gliding / springing list
  only stops it (nothing selected); a tap OUTSIDE it (coin pill, back, tabs,
  preview BUY) stops the list AND performs its normal action. The pinning
  test now asserts that a coin-pill tap during a fling stops the list and
  opens the Shop; the journeys that expected back / preview BUY to only stop
  were updated to the decision.
- **S2-50 fixed.** The fling integrates the exponential decay in closed form
  (`x += v0 (d^dt - 1) / ln d`), so 30 / 60 / 120 fps travel the same distance.
- **S2-51 fixed.** `LookPainter.extentOf` gives each look's vertical extent
  (hat rise, crests, gear drop; `test/skins/preview_fit_test.dart` checks it
  against the rendered art for every bird x hat / gear). The preview rests a
  tall look lower so it fits through the bob and a hop, the bigger
  celebration hop stops at the stage top, and hoops stay inside the stage.
