QA round 1 — skin shop and live home/Shop, 2026-10-07.

**Fix round 1 (branch `ss-fix1`, 2026-10-07):** all six findings are fixed and
their pinning tests now run by default (the `skip:` markers and the
`QA_VERIFY_OPEN_DEFECTS` switch are gone). The table below is the original QA
report, kept verbatim for the record; the fixes are:

- S1-10 `SoundService.play` drops the sound (warming the pools) instead of a
  one-shot `FlameAudio.play`; a `poolFactory` test seam covers the path.
- S1-11 `LookComponent.paused` freezes the look's clock; `HomeBird` drives it
  from `liveMotionPaused`.
- S1-12 `ItemArtCache.lockedPictureFor` records the 42 % dim once and settled
  locked static tiles replay it (no per-frame `saveLayer`).
- S1-13 the shop's initial featured try-on clears the item's NEW tag and calls
  `markSeen` like a grid tap.
- S1-14 `ItemStore.resetAll` clears the persisted menu state and notifies;
  the debug panel uses it, so the home bird shows the defaults at once.
- S1-15 `FeaturedSkinRow` pauses its artwork clock (`isPaused`) under the
  Shop's overlays.

Reviewed branch `ss-qa` at `255763eeb2f56ca3d0e15f5f18810bb035a1589e`, against
the workspace PRD-menu-v2.md, CLAUDE.md, SPEC.md, and common/WP-A/B1/B2/C/D/E
briefs. Product code was left unchanged. IDs start at S1-10 because the existing
PRD-1 QA tests already use S1-01 through S1-09.

`flutter pub get` succeeded. Baseline analysis was clean and the baseline suite
passed 481 tests. Final analysis is clean; the final suite passes 488 tests with
six explicitly skipped open findings. The new suite contributes seven passing
journeys and six reproductions. Enabling the open reproductions gives six
failures at their intended assertions; none fails through a setup error.

| ID | Severity | File:line | Issue and reproduction | Expected / basis |
|---|---|---|---|---|
| S1-10 | major | `lib/game/sound.dart:115` | `SoundService.play` calls bare `FlameAudio.play` whenever its pool is missing. Request an enabled SFX before warmup completes, or after a pool fails to initialize. This creates the one-shot player path the project explicitly bans. The regression test pins the forbidden call; native latency was not measured in this pass. | PRD §4.4, CLAUDE.md audio invariant, WP-A: use preloaded low-latency pools only, including fallback paths. |
| S1-11 | minor | `lib/components/look_component.dart:116`; `lib/components/home/home_screen.dart:758` | Equip Wind-up key, then leave a no-ads popup or debug panel over Home. The parent idle scheduler pauses, but the child's animation clock advances (0 → 0.5 s during the pinned popup test), so the key keeps turning beneath the overlay. | PRD §8.4 / WP-E: idle animations pause under dialogs, popups, ads, fake ads, and debug panels. |
| S1-12 | minor, performance hazard | `lib/components/skins/item_tile.dart:192` | Open Skins on a fresh install and leave the grid settled. Every visible locked static tile still issues one full-tile `saveLayer` per render to dim its cached picture. The test warms Sky's picture and counts one layer. This establishes repeated compositing work, not a measured frame-rate regression. | PRD §4.3 / WP-C static-art caching and the requested performance audit: cache the static dimmed result so settled locked thumbnails avoid repeated offscreen compositing. |
| S1-13 | minor | `lib/components/skins/skin_shop_screen.dart:157`; `lib/game/flappy_game.dart:848` | Fresh install → Shop → tap featured Lemonade. Skins opens with Lemonade tried on, but its NEW tag remains and `seenItems` omits `bird:lemon`. Initial try-on bypasses the grid tap's `clearNew` / `markSeen` path. | PRD §3.3 / WP-C: tapping an item clears its NEW tag and persists that it was seen; featured is also an item tap. |
| S1-14 | minor | `lib/components/debug_panel.dart:99`; `lib/components/home/home_screen.dart:772` | Equip Robin + Wind-up key + Cowboy, return Home, open debug → Reset menu state → close debug. ItemStore now returns the defaults, but the existing home bird still displays the deleted outfit until Home is recreated. | WP-A reset requirement and PRD §3.8: the rendered Home look agrees with the current equipped state immediately. |
| S1-15 | minor | `lib/components/shop/shop_screen.dart:807` | Own Lemonade, Toucan, and Ghost so Magic carpet becomes featured. Open Shop → debug panel → wait. The row's idle clock pauses, but `_t` continues advancing and the carpet still waves. Isolated row renders differ after 0.25 s under the overlay. | PRD §8.4 / WP-E: the featured artwork pauses with the other Shop idle animations. |

All six findings are pinned in `skin_shop_round1_e2e_test.dart`. Each is skipped
with the explicit reason `S1-xx open`; the FlameTester cases use a skipped group
because its own skip parameter accepts only a bool. Reproduce them with:

```bash
flutter test test/e2e/skin_shop_round1_e2e_test.dart \
  --dart-define=QA_VERIFY_OPEN_DEFECTS=true --name S1- --reporter expanded
```

The seven enabled journeys exercise actual taps and drags where practical:

- Fresh install → Skins → locked Galaxy → NOT ENOUGH COINS → six debug +1000
  presses → legendary BUY → buy Shades and Cap → Home → START → stage 5 → spike
  death → REPLAY → Home. Checks wallet, persisted ownership/equipment, purchase
  and shortfall analytics, collection/tab counts, outfit continuity, frozen
  dead pose, 35% stage blend, and the unchanged 14.75-point circular hitbox.
- Equip NONE gear and hat; cancel a locked try-on by switching tabs; verify
  persisted equipment, Home rendering, equip events, and unchanged counters.
- GET → mocked rewarded completion → six coin sprites → delayed count-up to
  +40 → cooldown, with the required sounds in order and no second grant.
- Reduce motion across Home, Shop, try-on, and a legendary purchase: no idle
  pulses/streaks/glints/wiggles/random actions, static try-on alpha, no flash,
  shake, rays, or collection-bar pop.
- Five tabs at 568 points and five tabs at 730 points (two journeys): exact
  stage/tab rectangles, height-dependent grid bottom, reachable last tile,
  input selection, and screenshots after visible trail emitters have warmed.
- Magic carpet's full featured name stays clear of its price. The suspected
  overlap did not reproduce and is covered as an enabled passing regression.

The broader review found the following contracts satisfied outside the findings:

- Catalogue ids/order/names/rarities/prices match the approved art and PRD
  tables: 30 birds and 15 entries in each other layer; 90 entries including the
  two NONE choices; 88 collectibles. Layer costs are 40,850 / 16,000 / 19,000 /
  25,000 / 20,750, totalling 121,600. Fresh progress is 3/88, with tab counts
  1/30, 0/14, 0/14, 1/15, 1/15.
- Legacy skin keys are deleted without grants or refunds, per common.md;
  persisted new items survive this cleanup. Unknown/unowned equipped ids fall
  back to defaults. ItemStore rejects unknown/insufficient/already-owned buys,
  owns free defaults, spends once, auto-equips, and persists immediately.
- `item_try_on`, `item_purchase`, `item_equip`, `item_no_coins`, and
  `skin_shop_tab` are wired with the expected parameters. New journeys verify
  purchase, shortfall, equip, and reward payloads. Existing flow tests cover
  the other rarity paths, analytics, tile states, and preview timing.
- Preview hoop spawning, split front/back rendering, trail windows, permanent
  Trails-tab emission, and injected Afterimage look drawing are connected.
  Hoop/trail equipment remains preview-only in this pipes-game phase, as
  explicitly settled in common.md.
- Stage-0 menu colours, stage blending, original bird geometry/physics,
  maxTranslation=10000, matching pipe-stub bounds, UI accent on results,
  deferred sign-in, and no-op services in tests remain intact. No iOS edits.
- Live curves and their attached effects follow the approved periods,
  keyframes, cascade delays, GET dimensions, coin flight, and reduced-motion
  rules tested by `live_home_shop_test.dart`, except the independent artwork
  clocks identified above.

The screenshot-producing tests ran in both complete suite runs. Inspected the
five `build/menu_shots/skinshop_*.png` captures beside their skinshop references,
the live Home/Shop/GET captures beside `live_*.png`, the catalogue/gear/hat/hoop/
trail art checks beside `skin_catalog.png`, and the Home/run look captures.
The new `skin_qa_568_*_bottom.png` and `skin_qa_730_*_bottom.png` captures confirm
the grid fits at both bounds. `skin_qa_get_in_flight.png` shows the coin flight;
`build/look_shots/qa_dead_galaxy_shades_cap.png` isolates the actual dead
component at full opacity after the gameplay results fade.

The larger back button at top-left and wallet at top-right are the settled
SPEC.md chrome, so their difference from the older skinshop references is not
a defect. The new featured price follows the new catalogue. Approved JS
behaviour governs the initial 4.4-second Home action, smaller try-on hop, and
legendary collection-sound delay where the written PRD differs.

Other performance observations: trail particles/history are bounded (512
particles and at most 120 history points per emitter), offscreen tile art
stops advancing, finite screen caches are disposed, and preview hoops are
culled. Rendering still allocates Paint/Path objects in trail/hoop drawing
(e.g. `lib/skins/art/trail.dart:336` and `:348`) and builds the stage colour
matrix per blended draw. These are profiling candidates; no unbounded list or
confirmed frame-rate regression was found. GPU frame timing, native SFX, Play
Billing, and AdMob were not exercised by this headless pass; service outcomes
in the new journeys use fakes.

Only the QA test and this report are committed. Generated PNGs, tablet outputs
outside this worktree, and Android signing files are excluded.
