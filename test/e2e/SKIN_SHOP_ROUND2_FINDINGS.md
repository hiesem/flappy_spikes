QA round 2 — skin shop and live Home/Shop, 2026-10-07.

**Fix round 2 (branch `ss-fix2`, 2026-10-07):** all three findings are fixed
and their pinning tests now run by default (the `skip:` markers and the
`QA_VERIFY_OPEN_DEFECTS` switch are gone). The report below is the original QA
text, kept verbatim for the record; the fixes are:

- S2-10 `LookComponent` keeps the pose/frame clock (wing frames, still reset by
  `playFlap`) apart from a continuous art clock that is passed to
  `LookPainter` as `t` and only freezes on death or `paused`; the wind-up key
  therefore turns straight through a gameplay flap.
- S2-11 `SoundService._initPools` publishes a pool and its stop duration
  together, so a pool without metadata is not ready and `play` keeps dropping
  the sound instead of dereferencing a missing duration.
- S2-12 `SoundService._playPool` contains both the pool start and the deferred
  stop futures (caught and ignored) — audio failures never reach the zone.

Reviewed `ss-qa` at `6d177b8`, against workspace PRD-menu-v2.md, CLAUDE.md,
SPEC.md, and the common/WP-A/B1/B2/C/D/E briefs. Product code is unchanged.
IDs start at S2-10 because older PRD-1/AdMob tests already use S2-01/02.

`flutter pub get` succeeded. Baseline `flutter analyze` was clean and
`flutter test --reporter expanded` passed 498 tests. After adding this QA
suite, analysis is clean and the full suite passes **507 tests, with three
explicitly skipped open defects**. The new suite contributes nine passing
tests and three reproductions. Enabling the reproductions produces three
failures at their intended assertions, with no setup failures.

| ID | Severity | File:line | Problem and reproduction | Expected / basis |
|---|---|---|---|---|
| S2-10 | minor | `lib/components/look_component.dart:106` (also `:123`) | Gameplay flaps reset the same clock that animates the whole outfit. Equip Robin + Wind-up key + Cowboy, START, wait about 0.48 s, then flap: the key snaps back to its initial phase. Returning from flap to idle resets it again. The pixel test holds the wing constant and proves the gear changes without elapsed time. | PRD §5.2 explicitly requires Wind-up key's clockwork animation to be idle-only, with no gameplay reactions; §3.8 shows gear in runs. Keep its animation phase continuous across wing-pose changes. |
| S2-11 | major | `lib/game/sound.dart:163` and `:133` | Warm-up publishes a pool before awaiting its duration. Request an enabled SFX to start warm-up; hold `getDuration()` pending after pool creation; request the same SFX again. Playback starts, then `_durations[sfx]!` throws a null-check error. No stop timer is scheduled, so the borrowed player is not returned by this code path. | PRD §4.4 / CLAUDE.md low-latency pool invariant, and SPEC's "SFX before warm-up are dropped" decision: a partially initialized pool must remain silent until its stop metadata is ready. |
| S2-12 | major | `lib/game/sound.dart:130` | Ready-pool playback failures escape through an unhandled Future. Warm up a pool, make `start()` fail (the reproduction injects a native SoundPool-style failure), then play an SFX. The error reaches the uncaught error handler because the `then` chain has no error handler. | PRD §4.4's pooled SFX path and SoundService's stated audio-failure invariant (`sound.dart:168`): contain playback failures, as initialization/music failures are contained. The requirement to contain errors is an implementation invariant; the PRD does not explicitly specify native-error handling. |

The audio tests confirm uncaught Dart errors through the injected pool seam;
they do not establish a native process crash or measure device audio latency.
There are no blockers found in this pass.

All three findings are pinned in `skin_shop_round2_e2e_test.dart`, skipped by
default with `S2-xx open`. The FlameTester case uses a skipped group because
its skip argument accepts a bool. Reproduce all open findings with:

```bash
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH" \
  ANDROID_HOME="$HOME/Android/Sdk" JAVA_HOME="$(ls -d $HOME/opt/jdk-17* | head -1)"
flutter test test/e2e/skin_shop_round2_e2e_test.dart \
  --dart-define=QA_VERIFY_OPEN_DEFECTS=true --name S2- --reporter expanded
```

The nine passing tests cover these journeys and contracts:

- Fresh install → Home → Skins → actual scroll/tap on locked Galaxy →
  try-on without equipping → insufficient-coins feedback/analytics → six
  actual debug +1000 presses → legendary BUY/celebration/countdown/persistence
  → buy Wind-up key and Cap → equipped Home bird → START → stage 5 → spike
  death with frozen attached gear/hat → REPLAY back Home. Checks the original
  circular hitbox and 35% stage blend.
- Equip NONE gear and hat, cancel a locked try-on by switching tabs, persist
  the changes, verify equip analytics and unchanged collection counts.
- All five tabs at both 568 and 730 logical points: exact preview/tab/grid
  geometry, a purchase per tab, counters/wallet, and reachable bottom tiles.
  Capture each bottom grid; retain preview-only hoop/trail equipment on Home.
- Reduce motion on Home, Shop, legendary try-on and purchase: no idle
  pulses/streaks/glints/wobbles/random actions, static try-on alpha, no purchase
  flash/shake/rays or collection-bar pop.
- Actual GET tap → mocked rewarded completion → six staggered coin flights
  → navigate Home mid-flight → +40 displayed once → cooldown and no repeated
  reward. Pins 112×32 GET, 0.65 s flight, 0.07 s stagger and sound/event order.
- Reset legacy keys without grants/refunds while preserving the new wardrobe
  and coin balance.
- Home look/idle clocks pause under no-ads popup and debug; Shop clocks,
  featured art and cascading streak phases pause under fake ads, resume on
  cancellation, and grant no coins. Pins cascade delays 0 / 0.7 / 1.14 /
  1.58 / 2.02 / 2.5 s.
- A ready pooled SFX starts and returns its borrowed player after the known
  duration plus the 100 ms padding.

The wider implementation review found these contracts satisfied outside the
reported findings:

- Catalogue ids, grid order, names, rarities and prices match the approved
  JS catalogue and PRD tables: 30 birds; 15 entries in each other layer;
  90 entries including two NONE choices; 88 collectibles. Layer costs are
  40,850 / 16,000 / 19,000 / 25,000 / 20,750, total 121,600. Fresh progress is
  3/88; tab counts are 1/30, 0/14, 0/14, 1/15, 1/15.
- ItemStore owns free defaults, rejects unknown/already-owned/insufficient
  purchases, spends once in the guarded UI flow, auto-equips and persists.
  Unknown or unowned saved equipment is sanitized; new data survives legacy
  cleanup. Existing focused tests exercise these model rules.
- `item_try_on`, `item_purchase`, `item_equip`, `item_no_coins` and
  `skin_shop_tab` carry layer/id data; shortfall and reward events are covered.
  Tile locked/owned/equipped/try-on/NEW states, rarity purchase feedback,
  collection updates and preview timing have existing regression coverage.
- Preview hoop cadence, split front/back drawing, trail windows, permanent
  Trails-tab emission and Afterimage's injected look renderer are connected.
  Hoop/trail rendering remains preview-only per common.md. Menus stay at
  stage 0; runs blend the complete bird/gear/hat stack; dead gear/hat remain
  attached and the key freezes.
- Approved JS timing deviations are respected: half-strength try-on hop,
  first Home action at 4.4 s then 6–12 s, and legendary progress sound at
  1.6 s versus 0.5 s for other purchases. GET and the live Home/Shop motion
  schedulers agree with the source and existing timing tests.
- SFX use low-latency pools with no bare one-shot fallback. Physics,
  `maxTranslation=10000`, pipe stub bounds, result UI accent, no-auth launch
  and no-op service routes retain the CLAUDE.md contracts. No iOS changes.
  The six round-1 skin-shop regressions run and pass in the full suite.

The visual pass ran the screenshot producers as part of the complete suite
and inspected the generated `build/menu_shots`, `build/look_shots` and
`build/art_check` PNGs against `design/menu_v2/skinshop_*.png`, `live_*.png`
and `skin_catalog.png`. This included locked/try-on/BUY layouts, Hoops and
Trails previews, live Home/Shop/GET, combined gear/hats, stage-5/dead looks,
short/tall bottom grids and the new coin-flight capture. No additional static
visual defect was found. Back-left/pill-right chrome is the settled SPEC
layout; the older reference uses the opposite arrangement. Featured-item
selection and animation phase differ legitimately between captures.
Screenshots remain generated artifacts; tablet outputs outside the worktree
are ignored and excluded from this commit.

Performance inspection found bounded trail particle/history storage, finite
catalogue caches with disposal, hoop culling, expiring celebrations and
offscreen tile animation clipping. Allocation hotspots remain in animated
hoop paths/paints (`lib/skins/art/hoop_painter.dart`), ribbon/echo rendering
(`lib/skins/art/trail.dart`) and stage-blend matrix/filter construction
(`lib/components/look_component.dart:137`). These are profiling candidates,
not measured frame-rate defects in this headless pass.

The round-1 static locked-tile fix needs a GPU profiling check:
`lib/components/skins/item_art.dart:118` records `saveLayer` inside a
`ui.Picture`, replayed by `item_tile.dart:236`. This avoids repeated Dart
recording, but caching a display list does not itself prove the GPU avoids
offscreen compositing. The existing outer-Canvas saveLayer counter cannot
observe commands inside `drawPicture`. Raster-cache/renderer behavior was
not measured, so this is a retained performance hazard rather than a newly
confirmed GPU regression. Visible animated locked tiles also retain a
per-frame alpha `saveLayer` (`item_tile.dart:210`); the fixed viewport bounds
their number, but its device compositing cost still needs profiling. No native
frame-time benchmark, real store/ad transaction or audible device playback
was performed.
