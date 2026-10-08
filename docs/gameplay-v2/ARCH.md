# Flappy Spikes 2.1 — gameplay v2 architecture (PRD-2)

Status: WP-0a design stage, 2026-10-08. Source of truth for behaviour: `PRD-2-gameplay.md` (workspace root).
This document is the module map and the contract set every later WP builds against. If a WP must change a
contract, it updates this file in the same commit and says so in its report.

Precedence: PRD-2 > this document > `design/menu_v2/proto_gameplay.html` > mocks. `CLAUDE.md` invariants always hold
(`maxTranslation = 10000`, AudioPool-only SFX, never `GameAuth.signIn()` at launch, never `GameAuth.isSignedIn`,
`Config.uiAccent` on game-over text, no `ios/` edits).

Companion: [REQ-MATRIX.md](REQ-MATRIX.md) — one row per requirement, owning WP, test IDs, status.

---

## 0. The shape of a 2.0 run (read first)

```
FlappySpikesGame (Forge2DGame, owns GameState, menus, persistence, services)
 ├─ world: RunScaledWorld (Forge2DWorld; updateTree(dt × timeScale) — Hourglass slows everything in it)
 │   ├─ backdrop, ScoreHud (score circle master #2), SpikeStrip ×2 (master #1)
 │   ├─ Bird (Forge2D body: vertical physics only; x pinned to 70 in flight)
 │   └─ RunController (Component, one per run; null on the home screen)
 │        ├─ RunTrack.back   (priority RunLayer.hoopBack)  ← hoop back halves, guides, ghosts, switch barriers
 │        ├─ RunTrack.items  (priority RunLayer.items)     ← pickups, coins, stars, fireflies
 │        ├─ RunTrack.front  (priority RunLayer.hoopFront) ← hoop front halves, front decorations
 │        └─ RunTrack.fx     (priority RunLayer.fx)        ← pooled particles, popups, shock rings
 └─ camera.viewport (screen space, REAL time — not slowed, not shaken)
     └─ RunHud (HUD row, banners, trays/pills, timer pill) + run screens (pause, revive, bonus, results, VS intro)
```

- **Track coordinates.** Everything that scrolls (hoops, pickups, guides, ghosts, ride rings) lives in a `RunTrack`
  layer in *track coordinates*: x grows to the right along the course, y is screen y. Each `RunTrack` layer's position
  is `(-camX, -camY)`; `camX` advances by `RunState.forwardSpeed × dt` (the bird's forward velocity, PRD §7 "move the
  world at the bird's forward speed"). The bird's track x is `camX + bird.screenX`. Normal flight pins the bird at
  screen x `RunConfig.birdX = 70`; the camera *is* the bird's forward motion, so a rim knock-back (negative forward
  speed) visibly jolts the world back (§3.0.4.4). `camY` is 0 except in portal rides.
- **Time.** `FlappySpikesGame.update` keeps the single clamped `dt` (Config.maxFrameStep). The run world runs on
  `gameDt = dt × RunState.timeScale` (1.0, Hourglass 0.45 with 0.2 s eases). `RunClock` adds `gameDt` while it runs
  (§3.0.1 runClock: runs in play and rides, stops in pause / revive offer / phoenix). HUD and screens use real `dt`.
- **Physics.** Forge2D only integrates the bird's vertical motion (gravity 1250, flap sets vy −370, max fall 650) and
  keeps `flap_physics_test` meaningful. Every gameplay contact — rim ends, pass plane, miss, spike tooth lines, saw
  rims, closed switches, pickups — is **plain math** in `lib/run/physics/` against the bird circle (r 14.75 × scale),
  per PRD §7. No Forge2D fixtures for hoops, sensors or strips. The death tumble is a plain-math ballistic integrator
  that drives the bird body kinematically.
- **Decisions are data.** `RunDirector` (pure Dart, no Flame) returns `SlotPlan` / `GapPlan` values; `RunSpawner` turns
  them into components through the `HoopKind` and `PickupKind` registries. A kind that is not registered yet is never
  offered, so the director can be complete from P0 and elements switch on as their WPs land.
- **Features don't call each other.** A feature (streak, egg, squeeze…) reads `RunState`, reacts to `RunEvent`s on
  `RunEvents`, and produces side effects only through the `RunContext` sinks (sound, rumble, analytics, wallet/score,
  emit). Cross-feature effects go through events (e.g. `MistakeSaved` → streak breaks, egg lost, fire out).

---

## 1. Module map

Legend: **API** = public surface other modules may use. **Deps** = what it may import. **Replaces / reuses** = existing
code. Paths are relative to `flappy_spikes/`.

### 1.1 `lib/run/` — core (WP-0b unless noted)

| File | Responsibility | API (Dart) | Deps | Replaces / reuses |
|---|---|---|---|---|
| `run/run_controller.dart` | Owns one run: state, clock, director, spawner, physics step, features, layers, mistake pipeline, end of run | `class RunController extends Component with HasGameReference<FlappySpikesGame>` — `RunController({required RunSetup setup})`; `RunState get state`; `RunContext get ctx`; `RunEvents get events`; `void start()` (first tap: flap + first hoop scheduled 60 pt off-screen, §3.0.1); `void onTap()`; `void pause()`; `void resume()`; `bool get isScrolling`; `void mistake(Mistake m)`; `void revive(ReviveKind k)`; `RunSummary summarize()`; `void disposeRun()` | run/*, services/*, menu/wallet | the spawner block in `FlappySpikesGame.update`, `onScoreSensor`, `onBirdHit` body |
| `run/run_setup.dart` | Inputs to a run | `class RunSetup { int seed; Powerup starter; OpponentRun? opponent; int startHoopIndex = 0; List<ElementId> forced = const []; RideId? forcedRide; double viewHeight; }` | — | — |
| `run/run_state.dart` | All mutable run data (pure data, no logic). Complete from WP-0b; feature WPs fill behaviour, not fields | see §2.1 | run/elements | — |
| `run/run_clock.dart` | runClock + timeScale | `class RunClock { double t; bool running; double timeScale; void tick(double dt); }` | — | — |
| `run/run_events.dart` | Typed synchronous event bus + the event catalogue | `class RunEvents { void on<T extends RunEvent>(void Function(T) h); void off<T>(…); void emit(RunEvent e); }` + `sealed class RunEvent` (§2.4) | run/elements | — |
| `run/run_context.dart` | Facade handed to kinds/features: sinks + read access | `class RunContext { RunState get s; RunEvents get events; RunDirector get director; Random get cosmetic; void sfx(Sfx s); LoopHandle loop(SfxLoop l, {double volume}); void knock(); void shake(); void track(String event, [Map<String,Object>? p]); void earn(int coins, CoinSource src); void addScore(int n, {PointFlags flags}); void mistake(Mistake m); void emit(RunEvent e); RunLayers get layers; RunGeometry get geo; double get viewHeight; }` | game, wallet, sound, rumble, services | — |
| `run/run_layers.dart` | Track layers + z constants | `class RunLayers { RunTrack back, items, front, fx; }`, `abstract final class RunLayer { static const backdrop=-1000, scoreCircle=-100, guides=-20, hoopBack=-10, items=-6, strips=-5, deadBird=-7, bird=10, hoopFront=12, fx=15, rideCannon=11; }` | — | `SpikeStrip.basePriority` stays −5 |
| `run/run_geometry.dart` | Band / tooth lines / safe line math (§3.0.1 screen heights, §3.0.2 band rule) | `class RunGeometry { double get topTooth; double get floorTooth; double get band; double fraction(double f); double clampCentre(double y, double opening, {double extra}); double safeLine(); Vector2 toTrack(Vector2 screen); }` | run_state | `Config.gapBottomMinFor/MaxFor` (pipe bands; the "same stub" invariant becomes "same margin 7 + 18 pt both sides") |
| `run/elements.dart` | Every catalogue element id (§3.0.7) incl. storage ids | `enum ElementId { normalHoop, angledRing, movingRing, bullseye, train, spring, switchRing, pair, fever, luckySpin, saw, portal, comet, heart, shield, starTrail, capsule, hourglass, miniBird, coinFrenzy, egg, piggy, jar, feather, puzzlePiece, squeeze, bigHoops, … }` with `String get storageId` (snake_case, stable) and `ElementKind kind` (slot / modifier / gap / schedule / event / starter) | — | — |
| `run/features.dart` | Registry of run features (append-only regions) | `List<RunFeature> buildRunFeatures()` | all features | — |
| `run/run_feature.dart` | Feature interface | §2.6 | — | — |
| `run/mistakes.dart` | The one mistake pipeline (§3.3 list) | `class Mistake { MistakeCause cause; Vector2? normal; ThemedDeath? themed; Hoop? hoop; }`, `enum MistakeCause { missedHoop, spikes, saw, closedSwitch, pairMissed }`, `abstract class MistakeInterceptor { int get order; bool tryAbsorb(Mistake m, RunContext ctx); }` | run_state | `onBirdHit` |
| `run/run_summary.dart` | Immutable result handed to post-run screens and versus upload | `class RunSummary { int score, hoopsPassed, coins, bestBefore, bestAfter, saves, revives; double runSeconds; MistakeCause cause; HoopKindId? hoopKind; int hoopIndex; RunTimeline timeline; OpponentRun? opponent; DuelResult? duel; }` | versus/timeline | `GameOverPanel` args |
| `run/run_spawner.dart` | Turns director plans into components; keeps one spacing ahead of the screen; removes off-screen parts | `class RunSpawner { void update(double dt); void clearAhead({double fade = 0.2}); Hoop? nextHoopAhead(); Iterable<Hoop> get hoops; Iterable<Pickup> get pickups; }` | director, hoops, pickups | the 1.5 s pipe timer |

### 1.2 `lib/run/director/` (WP-0b, pure Dart, unit-tested without Flame)

| File | Responsibility | API |
|---|---|---|
| `run_director.dart` | §3.0.3 decision order for every slot and gap, schedules, cooldowns, budget, first-meet guarantee (§3.0.8), debug force, `startHoopIndex` | see §2.2 |
| `director_context.dart` | Read-only snapshot the game passes in per decision | `class DirectorContext` (§2.2) |
| `plans.dart` | Decision data | `SlotPlan`, `GapPlan`, `GapItemPlan`, `MotionSpec`, `PairRewards`, `SpringDir`, `SawDesign`, `SwitchDesign`, `RideId`, `CapsuleType` |
| `layout_sampler.dart` | §3.0.2 |Δy| quantile sampling, zig-zag direction, clamp, tilt and motion picks | `class LayoutSampler { double nextCentre(int i, Band b, double opening, {double extra}); double? tilt(int i); MotionSpec? motion(int i, double centre, Band b); }` |
| `first_meet.dart` | `metElements` bookkeeping + the one-at-a-time forced queue | `class FirstMeet { FirstMeet(Set<ElementId> met); ElementId? dueSlot(int i); ElementId? dueGap(int i); void markMet(ElementId e); }` |
| `rng.dart` | Seeded streams | `class RunRandom { RunRandom(int seed); final Random layout, timing, cosmetic; double range(Random r, double a, double b); int rangeInt(…); T pickWeighted<T>(Random r, Map<T,num> w); }` |

### 1.3 `lib/run/config/` — tuning as data (§4)

| File | Owner | Content |
|---|---|---|
| `run_config.dart` | 0b | §3.0.1 core tuning (`RunConfig`) |
| `director_tables.dart` | 0b | §3.0.2 / §3.0.3 tables (`DirectorTables.prd2`) mirroring `spawn_tables.json` |
| `<feature>_config.dart` | feature WP | one file per feature (e.g. `squeeze_config.dart`, `comet_config.dart`, `revive_config.dart`) |

### 1.4 `lib/run/physics/` (WP-1a; squeeze walls API used by WP-3g)

| File | Responsibility | API |
|---|---|---|
| `bird_motion.dart` | forward speed + recovery 2000 pt/s², cruise ramp (+3.5 %/min of runClock), max fall, flap lock (spring), Mini scale | `class BirdMotion { double cruise(double runClock); void step(RunState s, Bird b, double dt); void knock(Vector2 normal, double restitution); }` |
| `rim_collision.dart` | §3.0.4 1–3, 6: rim-end circles, push-out, restitution 0.85 against the rim's own velocity, spin 360°/0.35 s | `RimContact? collideRims(HoopFrame f, BirdCircle b, Vector2 vel)` pure; `void applyBounce(...)` |
| `pass_test.dart` | §3.0.4 5: local-frame plane crossing between rim-end centres; "fully past" miss; one resolution per hoop | `PlaneEvent? testPlane(HoopFrame f, BirdCircle prev, BirdCircle now)`, `bool isFullyPast(HoopFrame f, BirdCircle b)` — `enum PlaneEventKind { pass, missPast, closedReached }` |
| `spike_walls.dart` | Current top/floor tooth lines (squeeze-aware), spike contact + save bounce (top ×0.3 down, floor vy −222) | `class SpikeWalls { double top, floor; double squeezeInset; bool touches(BirdCircle b); void saveBounce(Bird b, bool top); }` |
| `death_tumble.dart` | §3.0.5 momentum tumble, ease-out world stop 0.4 s, floor bounces/rest, edge bounces, settle flat | `class DeathTumble { DeathTumble(Mistake m, Vector2 v); bool get resting; void step(double dt); Vector2 position; double angle; }` |
| `hoop_frame.dart` | A hoop's world transform at time t (centre, tilt, ring offsets, velocity) | `class HoopFrame { Vector2 centre; double tilt; List<double> rings; double opening; double rimR; Vector2 velocity; Vector2 toLocal(Vector2 p); double rightmostX; }` |

### 1.5 `lib/run/hoops/`

| File | Owner | Responsibility / API |
|---|---|---|
| `hoop.dart` | 0b skeleton, 1a fills | `class Hoop extends PositionComponent` in track coords: `SlotPlan plan; HoopKind kind; double opening; double tilt; List<double> rings; HoopMotion? motion; bool touched; bool resolved; bool open = true; int? takenRing; HoopFrame frame(); void resolvePass(int ring); void resolveMiss(); void ghost();` Children: `HoopBackLayer` (in `layers.back`), `HoopFrontLayer` (in `layers.front`). |
| `hoop_kind.dart` | 0b | `abstract class HoopKind` (§2.5), `enum HoopKindId { normal, bullseye, train, spring, switchRing, pair, fever, luckySpin, saw, portal, rideRing }` |
| `kinds/registry.dart` | 0b (regions per WP) | `HoopKind? hoopKindFor(HoopKindId id)`; `Set<ElementId> registeredElements()` |
| `kinds/normal.dart` | 1a | normal hoop (+ tier look) |
| `ring_painter.dart` | 0c | **master #3** (see §3) |
| `motion/hoop_motion.dart` | 1b | `abstract class HoopMotion { void update(Hoop h, double t); Vector2 offset; double angleOffset; Vector2 velocity; }`; `RailMotion`, `SwingMotion`, `OrbitMotion`, `RockMotion` (horizontal/diagonal = rail with axis) |
| `motion/motion_guide.dart` | 1b | dashed guides (§5.12), uses `DashedPathPainter` (master) |
| `kinds/bullseye.dart`, `train.dart`, `spring.dart`, `lucky_spin.dart`, `fever.dart` | 3c | |
| `kinds/saw/` (`saw_kind.dart`, `live_wire.dart`, `frost_ring.dart`, `black_hole.dart`, `saw_death.dart`) | 3d | one `SawKind` + `SawDesign` strategy |
| `kinds/switch/` (`switch_kind.dart`, `lockdown.dart`, `laser_gate.dart`, `power_iris.dart`, `snoozer.dart`, `gift_wrap.dart`) | 3d | one `SwitchRingKind` + `SwitchDesign` strategy (barrier, decorations, switch sprite, open timeline ≤ 0.8 s, crash effect, sounds) |
| `kinds/pair/` (`pair_kind.dart`, `gift_box.dart`, `gift_tag.dart`) | 3d | |
| `kinds/portal.dart` | 3b | portal ring (beam, sparkles) |

### 1.6 `lib/run/pickups/`

| File | Owner | API |
|---|---|---|
| `pickup.dart` | 0b | `abstract class Pickup extends PositionComponent` (track coords): `PickupKindId id; double hitRadius; bool collected; void onCollect(RunContext c); void onPassedUncaught(RunContext c);` — hit test §3.0.3 (distance − bird r ≤ radius), one shared `PickupTouchFx` |
| `pickup_kind.dart` / `registry.dart` | 0b | `abstract class PickupKind { ElementId get element; Pickup build(GapItemPlan p, RunContext c); }`; `PickupKind? pickupKindFor(ElementId e)` |
| `heart_pickup.dart`, `shield_pickup.dart` | 2a | |
| `comet_star.dart` | 3a | hangs 20 pt past the plane |
| `star_trail.dart`, `egg_pickup.dart`, `piggy_pickup.dart`, `piggy_coin.dart`, `jar_pickup.dart`, `firefly_swarm.dart` | 3e | |
| `capsule.dart` | 3f | one capsule, `CapsuleType` param |
| `feather_pickup.dart`, `puzzle_piece_pickup.dart` | 4a | |
| switch pickups | 3d | live in `hoops/kinds/switch/` (design-owned), registered as pickups |

### 1.7 `lib/run/items/` — what elements do (run features)

| File | Owner | Feature |
|---|---|---|
| `scoring.dart` | 1a | +1 per pass, coin per pass (1 / 2 perfect), colour stage per 10 hoops, `point.mp3` on non-perfect |
| `extra_life.dart`, `shield.dart` | 2a | `MistakeInterceptor`s (shield order 10, extra life order 20), 2 s invulnerability, flash |
| `big_hoops.dart` | 2a | D = 30–40 s (`timing` stream), mult 1.5 eased over last 8 s, gold look, cap to band |
| `streak.dart` | 2b | streak/tier, banners, pass sounds, FEVER hook (`streak = max(5, streak+1)`), break on graze/save |
| `rumble_router.dart` | 2c | events → `Rumble.knock/shake` |
| `comet.dart` | 3a | 10 s × 1.7, auto-pilot, rims ignored, timed-powerup slot |
| `fever.dart` | 3c | fire on/off, crackle loop |
| `egg.dart`, `piggy.dart`, `jar.dart`, `star_trail_feature.dart` | 3e | |
| `hourglass.dart`, `mini_bird.dart`, `coin_frenzy.dart`, `timed_powerup.dart` | 3f | one `TimedPowerupSlot` (also used by comet) |
| `squeeze.dart` | 3g | §3.17 scheduler + phases; drives `SpikeWalls.squeezeInset` |
| `feathers.dart`, `puzzle.dart` | 4a | |
| `versus_recorder.dart` | 5b | timeline from `ScoreChanged` on runClock |
| `analytics_router.dart` | 0b (regions) | `run_end`, `run_director_hoops`, `run_director_items`, aggregated `coins_earned` |
| `met_elements.dart` | 0b | `ElementSpawned` (on screen) → `storage.markElementMet` |

### 1.8 `lib/run/rides/`

| File | Owner | API |
|---|---|---|
| `ride.dart` | 0b | `abstract class Ride { RideKind kind; void start(RunContext c); void update(double dt); bool get done; }`; `enum RideKind { comet, portal }`; `enum RideId { cannon, space, volcano, sea, pinball, storm }` |
| `portal_ride.dart` | 3b | `class PortalRide implements Ride` — path (arc/line segments or sampled curve), 11 rings at equal arc length (+ portal = 12 passes), ride camera from live scroll speed, 480 pt/s over 2.2 s, strips fade out 0.8 s, clear ahead (0.2 s), exit → launch flight (560/−640, g 520, 1.7 s) → glide 2.5 s + 0.6 s settle → resume ≈ 1 s later |
| `ride_theme.dart` | 3b | `abstract class RideTheme { RideId id; RidePath buildPath(); void paintWorld(Canvas c, RideCamera cam, double t); ExitChoreography exit; Offset launchPoint; (Color,Color) washTint; Map<RideCue,Sfx> sounds; }` |
| `themes/cannon.dart`, `space.dart`, `volcano.dart`, `sea.dart`, `pinball.dart`, `storm.dart` | 3b | one per ride |
| `ride_path.dart` | 3b | `class RidePath { double length; Vector2 at(double s); double headingAt(double s); }` |
| `speed_lines.dart` | 3a/3b | **three separate classes on purpose** (master #12): `CometSpeedLines` (3a), `CannonSpeedLines`, `RideSpeedLines` (3b) |
| `comet_ride.dart` | 3a | `class CometRide implements Ride` |

### 1.9 `lib/run/effects/` — shared parts (masters, §3) — WP-0c

`particle_pool.dart`, `perfect_burst.dart`, `coin_popup.dart`, `block_trail.dart`, `tier_trail.dart`,
`ring_tier_fx.dart`, `dust_puff.dart`, `shock_ring.dart`, `pickup_touch_fx.dart`, `fetch_flight.dart`, `twinkle.dart`,
`miss_flash.dart` (1a), `gold_sticker.dart`, `invuln_flash.dart`, `spike_teeth.dart`, `dashed_path.dart`,
`screen_edge_glow.dart`, `run_shake.dart`. Details and owners in §3.

### 1.10 `lib/run/hud/` (viewport, real time)

| File | Owner | API |
|---|---|---|
| `run_hud.dart` | 0b skeleton, 2d | `class RunHud extends PositionComponent` — top-anchored row container; slots: `heart`, `versus`, `pause`, `belowScore` badges (egg ×2 pill, piggy, jar), `collectSlot`, `timerPill`, `banners` |
| `heart_indicator.dart`, `versus_bar.dart`, `pause_button.dart`, `name_chip.dart` | 2d | §5.7 |
| `banners.dart` | 0c | **master #7**: `BannerHost` with lanes `streak` (StreakBanner), `fever` (FeverBanner, 3c draws), `element` (ElementBanner: TRAIN ×3, BULLSEYE!, LUCKY SPIN, PERFECT LINE, HATCHED!, ×2 LOST, PIGGY BANK, JAR FULL!, powerup names, SAVED!, LOCKED! …) — replace, never stack |
| `collect_slot.dart` | 0c | the y ≈ 206–254 slot queue shared by feather tray, puzzle pill (Q37/Q42: second waits for the first to fade; also waits for a banner) |
| `timer_pill.dart` | 3f | 120 × 22 pill, icon disc, draining bar, seconds label |
| `run_badges.dart` | 3e | egg ×2 pill, piggy HUD, jar HUD under the score |

### 1.11 `lib/run/screens/` (viewport)

| File | Owner | API |
|---|---|---|
| `post_run_flow.dart` | 0b (slots), 2d/2e/4a fill | `class PostRunFlow { Future<void> run(RunSummary s); }` — order: dying (tumble, ≤ 1.5 s / 2.2 s themed) → revive offer if `hoopsPassed ≥ 6` → phoenix → back to play, or → bonus (if `storage.feathers == 3`) → results → `game.goHome()` |
| `post_run_screens.dart` | 0b | `abstract class ReviveScreenFactory`, `BonusScreenFactory`, `ResultsScreenFactory`; registered in regions; 0b default = legacy `GameOverPanel` adapter for results, no revive, no bonus |
| `pause_screen.dart` | 2d | §5.7 pause card (RESUME, sound, settings; no Quit) |
| `revive_screen.dart`, `revive_ladder.dart`, `phoenix_rise.dart` | 2d | §3.14 / §5.9 |
| `shop_overlay.dart` | 2d | GET COINS: Shop as a `GameWidget` overlay on the paused game (countdown paused, music × 0.5) — reuses `ShopScreen` |
| `results_screen.dart` | 2e | §5.10, replaces `GameOverPanel` |
| `bonus_screen.dart` | 4a | §3.15 / §5.14 |
| `versus_intro.dart` | 5b | §5.8; plugged in as `game.beforeRunStart` |

### 1.12 `lib/run/debug/` (WP-0b; debug builds and Linux only, never referenced from release paths)

| File | API |
|---|---|
| `force_menu.dart` | page of `DebugPanel`: every `ElementId` → `RunController.debugForce(e)` (next slot/gap, ignores unlock + cooldown, keeps exclusivity); "start at hoop N"; "reset met elements"; "force portal ride: cannon / space / volcano / sea / pinball / storm"; "bot on/off"; "god mode". From home: queued into the next `RunSetup.forced`; in a run: from the pause screen (debug builds only). |
| `autopilot.dart` | `class Autopilot { Autopilot(RunController r, {double margin = 10}); bool shouldFlap(); }` — hoop-aware bang-bang bot: targets the next unresolved hoop through `HoopKind.autopilotTarget` (switch first, nearer pair ring, spring launch line, saw centre), pickups only when on the way. Used by the debug bot, `test/helpers.dart` and `integration_test/`. |
| `debug_overlay.dart` | rim circles, pass planes, hoop index / kind / angle (prototype debug view) |

### 1.13 Outside `lib/run/`

| Path | Owner | Responsibility / API | Replaces / reuses |
|---|---|---|---|
| `lib/versus/timeline.dart` | 5b (codec in 0b for the recorder contract) | `class RunTimeline { List<int> cs; List<int> flags; int endCs; String encodeTl(); String encodeFlags(); static RunTimeline decode(...); int scoreAt(double runClock); }` — uint16 centisecond deltas, base64; flags byte per point: `ride=1, train=2, gift=4` | — |
| `lib/versus/opponent.dart` | 0b | `class OpponentRun { String uid, name, avatarUrl; Look look; int score, best, level; RunTimeline timeline; String platform; }`, `abstract class OpponentFeed { int scoreAt(double runClock); bool outAt(double runClock); }` | — |
| `lib/versus/matcher.dart` | 5b | `OpponentRun? pick(List<PoolEntry> pool, {required int myLevel, required int myBest, required String myUid, required Set<String> seen, required Random r})` | — |
| `lib/versus/nickname.dart` | 5b | `String generateNickname(Random r)` (20 × 20 words, ≤ 14 chars + 3 digits) | — |
| `lib/versus/upload_queue.dart` | 5b | queue + 3/day + score ≥ 3 + best always | — |
| `lib/versus/run_entry.dart` | 5b | Firestore entry (de)serialisation, mirrors `functions/src/schema.ts` | — |
| `lib/services/versus_service.dart` | interface + `NoopVersusService` 0b; Firebase impl 5b | §6.3 | pattern of `GameServices` |
| `lib/services/identity.dart` | 5b | `PlatformIdentity` (§6.4) | uses `games_services` |
| `lib/services/reminders.dart` | 4b | `Reminders` service + pure `ReminderScheduler` (§3.34) | — |
| `lib/services/e2e.dart` | 0b | `const bool kE2E = bool.fromEnvironment('FS_E2E'); const int kE2ESeed = int.fromEnvironment('FS_E2E_SEED', defaultValue: 7); const String kAppCheckDebugToken = String.fromEnvironment('FS_APPCHECK_DEBUG_TOKEN');` + `E2EHooks` | — |
| `lib/components/spike_strip.dart` | 0c (art), 1a (44 pt switch), 3g (squeeze) | master #1 | 72 pt sprite tiles |
| `lib/components/score_hud.dart` | 3g adds white-when-covered | master #2 | — |
| `lib/components/bird.dart` | 1a | flight + kinematic tumble mode; `Bird.scale` (Mini), `Bird.goldTier`, `Bird.onFire` flags read by painters | 1.0 death impulse/spin |
| `lib/components/look_component.dart`, `lib/skins/art/look_painter.dart` | 0c | gold tier (#5), white X-eyes (#6) | — |
| `lib/components/gameover_panel.dart` | deleted by 2e | — | — |
| `lib/components/pipe_pair.dart` | deleted by 1a | — | — |
| `functions/`, `firestore.rules`, `firestore.indexes.json`, `firebase.json` (emulators/functions/firestore keys) | 5a | §6 | — |
| `integration_test/` | 0b harness, every WP may add a file, 6 final | §7.4 | — |
| `android/app/src/main/res/raw/notif_chime.ogg`, `res/raw/keep.xml`, `res/drawable/ic_notif_bird.xml`, manifest permissions | 4b | §3.34 | — |

---

## 2. Core contracts

### 2.1 `RunState` (lib/run/run_state.dart)

Pure data; the controller and features mutate it; screens and HUD read it. All fields exist from WP-0b.

```dart
class RunState {
  RunState({required this.seed, required this.viewHeight});
  final int seed;
  final double viewHeight;

  // progress
  int score = 0;            // shown score; includes pair "+5 score" gifts
  int hoopsPassed = 0;      // hoops passed (rides included, gifts not): revive minimum, colour stage
  int hoopIndex = 0;        // slots spawned (train / pair = 1 slot); NOT reset by a revive
  int gapIndex = 0;         // == index of the slot the gap follows
  double runClock = 0;      // mirrors RunClock.t (s)
  int coinsThisRun = 0;     // YOUR REWARD: run coins + puzzle + win/draw bonus; NOT balloon coins
  int stage = 0;            // floor(hoopsPassed / 10) % 11

  // motion
  double camX = 0, camY = 0;
  double forwardSpeed = 0;  // pt/s, the bird's forward velocity (can be < 0 after a knock-back)
  double timeScale = 1;     // Hourglass
  double birdScale = 1;     // Mini Bird 0.52 (eased)
  double flapLock = 0;      // s; spring launch (0.45 up / 0.28 down), rides

  // life
  int hearts = 0;           // 0..2; the 3rd converts to extraLife
  bool extraLife = false;
  bool shield = false;      // armed (pickup, pair gift or home slot)
  double invulnerable = 0;  // s left (2 s after a save / phoenix)
  int saves = 0;

  // streak
  int streak = 0;           // perfect passes in a row
  int bestStreak = 0;
  int get tier => streak.clamp(0, 10);
  bool onFire = false;      // FEVER
  int hoopsBurned = 0;

  // powerups
  TimedPowerupState? timed;     // hourglass | mini | frenzy | comet: remaining, paused (portal), duration
  BigHoopsState? bigHoops;      // D, start runClock; mult(runClock)
  RideState? ride;              // comet | portal(rideId, phase)
  bool rideOrSqueezeBlocksSpawns() => ...;

  // collectables (lost on a death that brings up the revive offer, §3.14)
  EggState? egg;            // stage egg|chick, cracks 0..5
  PiggyState? piggy;        // placed, caught, missed
  JarState? jar;            // caught, escaped
  StarTrailState trails;    // per-trail caught counts
  bool featherSpawned = false, pieceSpawned = false;   // once per run, also across a revive

  // squeeze
  SqueezeState squeeze;     // phase idle|warning|closing|hold|opening, index n, nextAt, holdS, inset

  // revive
  int revivesThisGame = 0;
  bool adStepAvailableThisGame = true;   // false after the ad step is used or skipped (no fill / no-ads)
  bool firstSlotAfterRevive = false;

  // bookkeeping for analytics and tests
  final Map<String, int> spawned = {};   // run_director_hoops / _items
  final Map<String, int> taken = {};
  int passes = 0, perfectPasses = 0, rimTouches = 0;
  final Set<ElementId> metThisRun = {};
  final Set<ElementId> metElements;      // install-wide copy loaded from storage at run start
  RunTimeline timeline = RunTimeline.empty();
}
```

Sub-state classes (`TimedPowerupState`, `BigHoopsState`, `RideState`, `EggState`, `PiggyState`, `JarState`,
`StarTrailState`, `SqueezeState`) live in the same file, as plain data with no behaviour.

### 2.2 `RunDirector`

```dart
class RunDirector {
  RunDirector({
    required int seed,
    DirectorTables tables = DirectorTables.prd2,
    required Set<ElementId> enabled,        // registered kinds (registries); unregistered kinds are never offered
    required Set<ElementId> met,            // storage.metElements (first-meet guarantee)
    int startHoopIndex = 0,                 // test/debug override (§7): sets hoop index + opening ramp
    RideId? lastPortalRide,                 // storage.lastPortalRide (no same ride twice, also across runs)
    List<ElementId> forced = const [],      // debug force queue
    RideId? forcedRide,
  });

  final RunRandom rng;                      // layout / timing / cosmetic streams
  int get hoopIndex;                        // next slot index
  SlotPlan nextSlot(DirectorContext ctx);   // §3.0.3 "order of decisions for a hoop slot"
  GapPlan nextGap(DirectorContext ctx, SlotPlan slot);   // §3.0.3 "order of decisions for the gap"
  double openingFor(int hoopIndex, {required bool ride});  // 118 → −0.32 %/hoop → floor 92; ride = 118
  double rollSqueezeAt(double now);         // timing stream: now + 60..120 s
  double rollSqueezeHold();                 // timing stream: 10..20 s
  double rollBigHoopsDuration();            // timing stream: 30..40 s
  int rollPuzzleBonus();                    // timing stream: 50..250 step 5
  void onRevive();                          // next slot normal
  void onRideStart(RideKind k);
  void onRideEnd(RideKind k);
  void debugForce(ElementId e);             // next slot/gap; ignores unlock + cooldown; keeps exclusivity
  void debugForceRide(RideId id);
  void markMet(ElementId e);
  Map<String, int> get spawnedCounts;       // for run_director_hoops / _items
}

class DirectorContext {               // snapshot built by RunController for each decision
  final double viewHeight, topTooth, floorTooth;          // current tooth lines
  final double squeezeTopTooth, squeezeFloorTooth;        // squeezed lines when the squeeze window is on
  final bool squeezeWindow;          // 3 s before the warning .. walls fully open
  final bool rideActive; final RideKind? ride;
  final bool timedPowerupRunning, onFire, shieldArmed, extraLifeActive;
  final bool eggOrChick, piggyRunning, jarRunning;
  final int shieldPickupsThisRun;
  final double scrollSpeed;           // current cruise (switch lead = 1.0 s × this, ≥ 150 pt)
  final double runClock, bigHoopsMult;
  final double prevCentreY;           // previous hoop centre (switch reach ≤ 110 pt, pair reach)
  final double hudBottom;             // y ≈ 114 (pair fit)
}

class SlotPlan {
  final int index; final HoopKindId kind; final ElementId element;
  final double trackX;                // plane x of the (first) ring
  final double centreY, opening;      // opening incl. saw +28 and Big Hoops mult (capped to the band)
  final double tiltDeg;               // 0 for specials / rides
  final MotionSpec? motion;           // normal hoops only
  final bool cometHang;               // comet star 20 pt past the plane
  final List<double> ringOffsets;     // [0] or pair [−o/2, +o/2], o = 230 × viewHeight / 711
  final double advance;               // spacing to the next slot (train: 2 × 56 + 310)
  final Object? extra;                // PairRewards | SpringDir | int spinPrize | SawDesign | SwitchDesign | TrainDir | RideId
  final bool forced;                  // first-meet or debug
}

class GapPlan { final int index; final List<GapItemPlan> items; }
class GapItemPlan {
  final ElementId kind;               // heart, feather, puzzlePiece, switchRing (its switch), starTrail, capsule, egg, piggy, jar, shield, piggyCoins, fireflySwarm
  final double trackX; final double? y;   // y == null → on the straight line between the hoops, resolved by the spawner
  final Object? extra;                // CapsuleType | int puzzleSlot | SwitchDesign | count
}
```

Rules the director must implement (all from §3.0.3; tested in WP-0b):
- Slot order: ride → normal full-size upright; first after revive → normal; portal schedule (25–50, then +40–60;
  waits for ride/squeeze/comet < 10 back); cooldown (1, or 2 after train/spring/pair, 3 after portal); special roll
  with the budget table and per-type min distance / not-allowed rules; comet hang schedule (10–30, then +45–60; waits);
  tilt / motion for normal hoops (not in squeeze window for motion).
- Gap order: running piggy (4 per gap, 4 + 4×4 = 20) or jar (swarm of 7); fixed schedules heart (3, +17–27, skipped
  while extra life, schedule still moves) / feather (once, 3–12, only while `feathers < 3`) / piece (once, 14–25, only
  while the round is open) moving to the next free gap; the switch of a switch ring in the next slot (gap taken → the
  switch ring becomes normal); optional roll with the gap budget.
- Exclusivity, squeeze-window and ride rules; pair reward filter (no shield if armed, no FEVER if on fire, no COMET
  within 10 of a portal or while a timed powerup runs); spring room for 240 pt; pair fit (else normal); saw and switch
  design never the same twice in a row per run; ride never the same as `lastPortalRide`.
- First-meet: once an element's first-possible hoop is reached and it is not in `met`, force it within 5 slots/gaps as
  soon as its rules allow; one forced element at a time, oldest unlock first; counts against the budget.
- Determinism: same seed + same `DirectorContext` sequence → identical `SlotPlan`/`GapPlan` sequence. **Streams**:
  `layout` (heights, kinds, items, pair rewards, spin prize, designs), `timing` (squeeze moments and holds, Big Hoops D,
  capsule durations, puzzle bonus, balloon prizes — rolls that happen on the clock, so the slot sequence never depends
  on when they happen), `cosmetic` (visual variety only). Seeds derive as `layout = seed`,
  `timing = seed ^ 0x5bd1e995`, `cosmetic = seed ^ 0x9e3779b9`.

Prototype differences that the PRD overrides (do not copy): pair offset is 230 × viewHeight / 711 (proto: fixed ±115);
spring's next ring is 240 pt away (proto: 175); first hoop spawns 60 pt past the right edge (json: "1.3 s"); the
switch is placed at 1.0 s × scroll speed ≥ 150 pt (proto: fixed 150); piggy places 4 per gap (proto: 5).

### 2.3 Game state machine and `flappy_game.dart`

```dart
enum GameState { start, versusIntro, playing, paused, dying, reviving, bonus, gameOver /* = results; renamed `results` by WP-2e */ }
```

- `playing` covers normal play and rides. `paused` = pause screen (runClock stopped). `dying` = tumble until the
  revive offer / bonus / results. `reviving` = revive offer, GET COINS shop overlay and phoenix (`RunState` keeps the
  sub-phase). `bonus` = balloon screen. `gameOver` = results page (kept so the 1.0 tests keep compiling; WP-2e renames
  it to `results` with a mechanical lib+test rename).
- `isScrolling` → `run?.isScrolling ?? false` (true while playing and the world moves).

`flappy_game.dart` changes (WP-0b does the plumbing; later WPs only touch their marked regions):

| Member | Change | WP |
|---|---|---|
| constructor | `world: RunScaledWorld(gravity: …)` (time scale); keep `maxTranslation = 10000` | 0b |
| fields | `RunController? _run; RunController? get run;` remove `_spawnTimer`, `_lastGapBottomY`, `pipeRandom` → `runSeed` (tests set it; e2e uses `kE2ESeed`; production: `Random().nextInt`) | 0b |
| `_runFromHome` | passes the consumed `Powerup` into `_startGame(starter)`; analytics `big_hoops_used` / `shield_armed` stay | 0b |
| `_startGame` | builds `RunSetup` (seed, starter, `versus.takeOpponent()`, debug forced queue) and adds `RunController`; first tap = flap + first hoop | 0b |
| `onScreenTap` / `onPlayfieldTap` | `playing` → `run.onTap()` (ignored in rides / flap lock / tumble) | 0b |
| `onScoreSensor` | deleted (pass test lives in `run/physics/pass_test.dart`) | 1a |
| `onBirdHit` | replaced by `endRun(RunSummary)`: persistence (`incrementGamesPlayed`, `saveLastScore`, best), `noAdsPopup.recordRun`, `logGameOver`, `logNewBest`, `submitBestScore`, versus upload, then `PostRunFlow`; no coins here any more (wallet per pass) | 0b (plumbing) / 1a (removal of interim coin rule) |
| `pause()` / `resume()` | new; Esc and `AppLifecycleState.paused` pause a running run (call: backgrounding pauses) | 2d |
| `goHome()` | accepted from `gameOver`(results); unchanged otherwise | — |
| `replay()` | `_run?.disposeRun()` instead of the `PipePair` query; resets strips (44 pt, squeeze 0) | 0b |
| `update()` | spawner block removed (in `RunController.update`) | 0b |
| `onScoreSensor` colour stage | `stageForHoops(hoopsPassed)` in `palettes.dart` replaces `stageOf(score)` in runs (`stageOf` stays for legacy tests until 1a updates them) | 1a |
| `showRewardedAd` | unchanged; new placements `revive` (exists) and `bonusFeathers` | 0b adds enum |
| `beforeRunStart` | versus intro hook (set by 5b when an opponent is prefetched) | 5b |
| `lifecycleStateChange` | + reminders reschedule on paused/detached (4b), + run auto-pause (2d) | 2d / 4b |
| keyboard | Esc while playing → pause; D (debug) also during pause | 2d / 0b |

### 2.4 Events (`RunEvents`)

Synchronous, in-order, emitted from the update loop. Handlers must not throw (the bus try/catches and debug-prints).
Catalogue (WP-0b defines all of these; a WP that needs a new event appends it in its region):

| Event | Payload | Emitted by |
|---|---|---|
| `RunStarted` | setup | controller |
| `HoopSpawned` | hoop, plan | spawner |
| `ElementSpawned` | `ElementId`, onScreen (for met) | spawner / features |
| `HoopPassed` | hoop, ring, `perfect`, `rimTouched`, `bullseye`, `duringRide`, `trainK` | pass test |
| `RimTouched` | hoop, contact point, normal | rim collision |
| `HoopMissed` | hoop (miss flash) | pass test |
| `ClosedSwitchReached` | hoop | pass test |
| `PickupCollected` | `ElementId`, pickup | pickup |
| `PickupEscaped` | `ElementId` (piggy coin missed, firefly escaped) | pickup |
| `ScoreChanged` | old, new, `PointFlags` (ride/train/gift) | ctx.addScore |
| `CoinsEarned` | amount (after ×2), source, eggX2 | ctx.earn |
| `StreakChanged` | old, new, cause (pass/graze/save/death/fever/ride) | streak |
| `TierChanged` | old, new | streak |
| `MistakeSaved` | mistake, by (shield/extraLife) | mistake pipeline |
| `RunDied` | mistake | mistake pipeline |
| `PowerupStarted` / `PowerupEnded` / `PowerupPaused` / `PowerupResumed` | type, duration | timed slot |
| `RideStarted` / `RideEnded` | kind, rideId | rides |
| `SqueezePhase` | phase, index | squeeze |
| `RevivePhoenixStarted` / `Revived` | kind (ad/coins), price | revive |
| `RunEnded` | summary | controller |

### 2.5 `HoopKind`

```dart
enum RimMode { bounce, deadly, ignored }

abstract class HoopKind {
  HoopKindId get id;
  ElementId get element;
  bool get usesTierLook;                 // normal, bullseye, luckySpin, train, rideRing: yes; saw, switch, fever, pair, spring, portal: no (call)
  double extraOpening(SlotPlan p) => 0;  // saw +28
  RimMode rimMode(Hoop h, RunState s);   // rides → ignored; saw → deadly; else bounce
  double rimRadius(Hoop h) => 7;         // saw: 5 (Live Wire / Frost) or 6 (Black Hole)
  void onSpawn(Hoop h, RunContext c) {}
  void buildVisual(Hoop h, RunContext c);            // adds back/front children via RingPainter / design painters
  PlaneVerdict onPlane(Hoop h, int ring, RunContext c) => PlaneVerdict.pass;   // closed switch → mistake
  void onPass(Hoop h, PassInfo p, RunContext c) {}   // bullseye +3, spin prize, spring launch, pair gift, train combo, FEVER, portal start
  void onMiss(Hoop h, RunContext c) {}               // miss flash is generic; kinds may add
  void onRim(Hoop h, RimContact rc, RunContext c) {}
  void update(Hoop h, double dt, RunContext c) {}
  AutopilotTarget autopilotTarget(Hoop h, RunState s);   // y to aim at + optional pre-target (switch, nearer pair ring)
}
```

Generic pass/miss/rim handling is in `RunController` (not in kinds): +1 score, coin, `HoopPassed`, streak via the
event, miss → `HoopMissed` + `mistake(missedHoop)`. Kinds only add their specifics.

### 2.6 `RunFeature`

```dart
abstract class RunFeature {
  void attach(RunContext c);               // subscribe to events; create HUD parts
  void update(double gameDt, double realDt) {}
  void onDeath(Mistake m) {}               // e.g. lose egg / piggy / jar; end timed powerups
  void onRevive() {}                       // e.g. squeeze opens in 0.5 s
  void detach() {}
}
```

Mistake pipeline (`run/mistakes.dart`, 0b skeleton, 1a death, 2a saves): ignore while `invulnerable > 0` or during a
ride; ask `MistakeInterceptor`s in `order` (shield 10, extra life 20 — call: shield absorbs first, matching the
prototype); a save emits `MistakeSaved` (streak break, fire out, egg/chick lost, piggy/jar kept, 2 s invulnerability,
spike save bounce); otherwise `RunDied` → tumble → `PostRunFlow`.

### 2.7 Sinks: sound, rumble, analytics, wallet

- **Sound.** `SoundService` gains (0b): `Sfx` entries for every approved file that exists today (§8 sound list),
  `LoopHandle loop(SfxLoop l, {double volume})` (looping `AudioPlayer` in low-latency mode, BGM-style, owned by the
  service; `comet_loop` at 0.3, `sq_hold`, saw hums, fever crackle), `setMusicRate(double)` (Hourglass 0.72),
  `duckMusic(double)` (GET COINS 0.5). Still never `FlameAudio.play`. Tests: `onPlay` / a new `onLoop` recorder.
  **WP-3h** generates the rest of the §7 deliverable list (`design/menu_v2/gen_sfx15.py`) and registers it: 88 one-shot
  `Sfx` + 4 `SfxLoop` (`sawWireHum`, `sawFrostHum`, `sawHoleHum`, `feverLoop`) in the `// region WP-3h` blocks of
  `lib/game/sound.dart`; each has its file, use, length and generator in `docs/gameplay-v2/SOUNDS.md`. The 58 files 0b
  shipped are unchanged; 3c/3d/3e/3f/3g/5b reference these names (never invent a new one — §3.0.9).
- **Rumble.** `Rumble` exists (throttle, setting). Only `rumble_router.dart` (2c) calls `knock()/shake()` for run
  events; no rumble outside `playing` (paused/revive/bonus/results never rumble).
- **Analytics.** `ctx.track(name, params)` → `GameServices.track`. Element events are sent by the owning feature at the
  moment in §6. `analytics_router.dart` (0b) sends `run_end`, `run_director_hoops`, `run_director_items` (≤ 25 int
  params each) from `RunEnded`, and **aggregates in-run `coins_earned`** per (source, egg_x2) into one event per
  source at run end (call: avoids ~100 events per run; out-of-run sources — level, bonus, win_bonus — are sent at once).
- **Wallet / coins.** `ctx.earn(n, source)` is the only in-run coin path: applies the chick ×2 (egg), credits
  `menu.wallet.add` at once (kept if the run ends), adds to `coinsThisRun`, emits `CoinsEarned`. `CoinSource` gains (0b):
  `hoop, perfect, winBonus, bonus, puzzle, switchRing, pair, train, bullseye, luckySpin, starTrail, piggy, jar, frenzy`
  with analytics names from §6; `levelReward` keeps its home-v3 name `level_reward` (call; PRD §6 lists `level`).
  `CoinSource.play` and the "1 coin per point at game over" rule are removed by 1a.
- **Score.** `ctx.addScore(n, flags)` updates `score`, the `ScoreHud`, the versus timeline (via `ScoreChanged`).

---

## 3. Shared-parts registry (§3.0.9) — one class each, no variants

A WP that needs one of these **must** use the class below and only change the listed parameters. If the master lacks a
needed parameter, add the parameter to the master (and note it here), never a copy.

| # | Part | Class | File | Parameters allowed | Owner |
|---|---|---|---|---|---|
| 1 | Spike strips (44 pt: band 26 + teeth 18, period 40, 40 × 44 tile, scrolling teeth) | `SpikeStrip` drawing `SpikeTeethPainter` | `lib/components/spike_strip.dart`, `lib/run/effects/spike_teeth.dart` | colour (stage fg), tooth scroll offset/speed, squeeze inset, warning flash blend, opacity (ride fade), lensing bend (Black Hole), falling bits on/off | 0c art, 1a switch to 44 pt, 3g squeeze |
| 2 | Score circle (183 × 183 at (160, centre + 35), LVDC digits, behind play) | `ScoreHud` | `lib/components/score_hud.dart` | score, tint, white-when-covered (squeeze) | existing; 3g |
| 3 | Hoop ring (24 pt wide, stroke 7, front over / back under the bird, height = opening + 2 × 7) | `RingPainter` (normal hoops delegate to `HoopPainter` for the equipped hoop skin) | `lib/run/hoops/ring_painter.dart` | opening, colours (front/back), stroke, tilt, dash (miss ghost), glow, skin id | 0c |
| 4 | Bird (equipped look, ×0.983, wing flap, blink, stage blend) | `LookComponent` / `LookPainter` | `lib/components/look_component.dart`, `lib/skins/art/look_painter.dart` | look, scale, pose, mirror (VS), opacity | existing |
| 5 | Gold bird (tier 2+: body `#FFB529`, tail+wing `#E08A00`, beak `#FFB529`, eye white) | `LookComponent.goldTier` → `LookPainter(gold: true)` | same files + `lib/run/effects/gold_bird.dart` (colours) | on/off | 0c |
| 6 | Dead X-eyes (white 6 × 6, line 2) | `LookPainter(dead: true)` | `lib/skins/art/look_painter.dart` | — | 0c |
| 7 | Streak banner (y 190, padding 6, font sizes [28,32,34,30,32,34,34,32,34,30], 0.1 em, white Opificio, scale-in 0.1 s, hold 1–1.9 s, 10 names, cap IMMORTAL ×10) | `StreakBanner` in `BannerHost` | `lib/run/hud/banners.dart` | tier | 0c |
| 8 | Pass coin popup ("+N" gold 28 pt + coin.png 24 pt at (x − 10, y − 70), 0.7 → 1.1 → 1, rises 40 pt, 1.1 s) | `CoinPopup` | `lib/run/effects/coin_popup.dart` | amount, "×2" suffix (egg), position | 0c |
| 9 | Perfect-pass burst (8 + 3 × min(tier,3) squares, 5–8 pt, pink/gold/soft pink, 25–55 pt, 350–600 ms, no rotation, no shockwave) | `PerfectBurst` | `lib/run/effects/perfect_burst.dart` | tier, position | 0c |
| 10 | Block trail (8–13 pt squares, 30/s, 50/50 gold/pink, 0.9 → 0 in 450 ms, 26 pt behind along flight direction ± 8, drifts 70 pt opposite) | `BlockTrail` (+ `TierTrail` chooser) | `lib/run/effects/block_trail.dart`, `tier_trail.dart` | direction, density fixed | 0c |
| 11 | Ring tier looks (tints pink → gold → bright gold; stars 9–15 / 10–17 / 12–24 at 7 / 16 / 38 per s; tier 3+ glow sprite 96 × 152 + flame flicks) | `RingTierFx` | `lib/run/effects/ring_tier_fx.dart` | tier, ring frame | 0c |
| 12 | Speed lines — **kept separate on purpose** | `CometSpeedLines`, `CannonSpeedLines`, `RideSpeedLines` | `lib/run/rides/speed_lines.dart` | as specified per animation | 3a / 3b |
| 13 | Perfect-pass screen flash | **none** — no class; `ScreenFlash` (skins/celebration.dart) is never used for a perfect pass | — | — | — |
| 14 | Coin icon | sprite `menu/coin.png` via `CoinIcon` helper | `lib/run/effects/coin_icon.dart` | size | 0c |
| — | Dust / feather puff (12–22 particles 4–9 pt, ±140 / −90…−10 pt/s, fade 0.6–1 s) | `DustPuff` | `lib/run/effects/dust_puff.dart` | colour, count, position | 0c |

Additional shared parts (not in the PRD table, introduced here so elements do not each draw their own):

| Part | Class | File | Used by | Owner |
|---|---|---|---|---|
| Particle pool (flat squares/strips/triangles, max ≈ 130 alive, §5.4) | `ParticlePool` | `lib/run/effects/particle_pool.dart` | bursts, confetti in run, shards, sparks | 0c |
| Expanding ring outline (non-perfect pass pulse 0.8 → 1.9 in 0.55 s, gold rings on pickups, coloured pulses) | `ShockRing` | `lib/run/effects/shock_ring.dart` | pass feedback, pickups, pair pick, phoenix shockwave, FEVER pass | 0c |
| Pickup touch fx (white flash r a→b, gold ring, n squares) | `PickupTouchFx` | `lib/run/effects/pickup_touch_fx.dart` | feather, piece, switch, heart, shield, capsule | 0c |
| Fetch flight (pickup flies on a curve into a HUD slot, block trail behind) | `FetchFlight` | `lib/run/effects/fetch_flight.dart` | feather, piece, heart → indicator | 0c |
| Four-point twinkle star | `Twinkle` | `lib/run/effects/twinkle.dart` | feather, piece, switches, tier stars | 0c |
| Gold sticker (NEW BEST style, −3/−4° tilt, plum text) | `GoldSticker` | `lib/run/effects/gold_sticker.dart` | BONUS UNLOCKED!, PICTURE COMPLETE, NEW BEST (results) | 0c |
| Invulnerability flash (opacity 25 % ↔ 100 % every 0.1 s, 2 s) | `InvulnFlash` | `lib/run/effects/invuln_flash.dart` | extra life, shield, phoenix | 0c |
| Miss flash "C · Shock ring" (§5.13) | `MissFlash` | `lib/run/effects/miss_flash.dart` | every miss incl. pairs | 1a |
| Dashed path (2.5 pt, 6/6) | `DashedPathPainter` (wraps `ArtPaint.dashed`) | `lib/run/effects/dashed_path.dart` | moving guides, train track, bullseye lines, Iris cable, star trail line | 0c |
| Screen edge glow (radial, colour, sine pulse) | `ScreenEdgeGlow` | `lib/run/effects/screen_edge_glow.dart` | miss (red), revive urgency (red), Hourglass vignette (blue), Coin Frenzy border | 0c |
| World shake (offset per frame; exposed edges show the strip grey) | `RunShake` | `lib/run/effects/run_shake.dart` | squeeze, FEVER pass, Black Hole death, piggy smash | 0c |
| Collect slot queue (y ≈ 206–254, one at a time, waits for banners) | `CollectSlot` | `lib/run/hud/collect_slot.dart` | feather tray, puzzle pill | 0c |
| Confetti (results / bonus / VS) | `ConfettiBurst` | `lib/components/ui/confetti.dart` (existing) | screens | existing |
| Coin fly (balance pill ↔ targets) | `CoinFly` | `lib/components/ui/coin_fly.dart` (existing) | revive pay, CLAIM, bonus coins | existing |
| Level emblem | `EmblemPainter` | `lib/levels/emblem_painter.dart` (existing) | results, VS plates | existing |

**WP-0c as built (2026-10-08) — parameters added to masters / contract notes:**
- Knobs of every shared part: `lib/run/config/parts_config.dart` (`PartsConfig`), each with its PRD section.
- #1: `SpikeStrip.defaultArt` (`SpikeArt.sprite` → WP-1a sets `SpikeArt.teeth` with `Config.spikeHeight` 44 — the
  whole switch). Per strip: `art`, `toothOffset`, `teethOpacity`, `toothReach` (= `spikeHeight − visualInset`).
  `SpikeTeethPainter.paint(canvas, width, color, reach, offset, opacity)` draws in strip space (y 0 = screen edge).
- #3: `RingPainter.paintHalf(centre, opening, front, skinId, colors, strokeWidth, tilt, dash, dashPhase, glow,
  glowBlur, opacity, t)`; `RingColors.{pink,gold,brightGold,ghost,white}`; `colorsForTier(tier)`; `ryFor(opening)`
  = opening / 2 + 7. `HoopPainter.paintHalf` gained an optional `rx` (gameplay keeps rx 12).
- #5/#6: `LookPainter.paint(gold:)`, `LookComponent.goldTier`; dead pose draws `paintDeadX` (white 6 × 6, 2 pt;
  dark on light bodies). Colours in `GoldBird`.
- #7: `BannerHost.show(RunBanner)` / `showStreak(tier)`, `busy`; `RunBanner` is the base class for `FeverBanner` (3c).
- #8: `CoinPopup` (`play(at, amount, doubled:)`) + `CoinIcon` (#14). #9 `PerfectBurst.emit(pool, at, tier, rnd)`.
  #10 `BlockTrail.update(pool, dt, bird, heading)` and `TierTrail` (equipped trail vs blocks; the equipped
  `TrailEmitter` only drifts horizontally). #11 `RingTierFx` (one per ring; `tier`, `update`, `paintBack` glow,
  `paintFront` sparkles/flames, `ringColors`). Dust: `DustPuff.emit(pool, at, color, rnd, count:)`.
- Pooling: `ParticlePool` (Component; capacity 130; `spawn(...)` with gravity / drag / damp / fadePow / spin /
  delay; shapes rect, circle, triangle, twinkle) and `EffectPool<T extends PooledEffect>` (`CoinPopup.newPool()`,
  `ShockRing.newPool()`, `PickupTouchFx.newPool()`).
- `ShockRing.passPulse / missWave / goldRing / play`; `PickupTouchFx` + `PickupTouchSpec.{feather, puzzlePiece,
  switchTouch, heart, shield, capsule}`; `FetchFlight` + `FetchSpec.{feather, puzzlePiece, heart}`; `Twinkle`
  (`waist`: ring 0.354 / pickups 0.28); `GoldSticker.newBest / collect`; `InvulnFlash`; `DashedPathPainter`;
  `ScreenEdgeGlow.miss / reviveUrgency / hourglass / coinFrenzy`; `RunShake` (kick + sustain, squeeze helpers);
  `CollectSlot.request(CollectSlotItem)`; shared easings in `lib/run/effects/easing.dart` (`Ease`).

**Skin interplay (call, from PRD-menu-v2 §3.8/§6 and Q-S2…Q-S4 proposals):** normal hoops draw the **equipped hoop
skin** at tier 0–1 (default `pink` = the M0 colours of master #3); gameplay gold states (tier 2+, Big Hoops, Coin Frenzy,
passed train rings) override the skin while active. Tier 2+ uses master #5 on the classic bird; on other bird skins
`goldTier` draws a gold glow outline instead of recolouring. Tier 3+, comet and portal rides show the **equipped trail**
(`TrailEmitter`) using the flight-direction rule of master #10; `BlockTrail` is used when the equipped trail is
`blocks` and for non-bird fetch trails. One switch `TierTrail.useEquippedTrail` (default true) flips this if the owner
decides otherwise.

---

## 4. Config: PRD tables as data

- **Where.** Existing `Config` (lib/game/config.dart) keeps menu/layout knobs and gets only the changed core values
  (1a: `scrollSpeed` → removed for runs, `birdX 70`, `maxFallSpeed 650`, `spikeHeight 44`, pipe constants removed).
  All new run knobs live in `lib/run/config/`, one file per feature, each a `abstract final class XxxConfig` with
  `static const` members. This keeps `config.dart` out of the parallel-conflict set.
- **Naming.** Class `<Feature>Config` (`RunConfig`, `LayoutConfig`, `SqueezeConfig`, `CometConfig`, `ReviveConfig`,
  `BigHoopsConfig`, `StreakConfig`, `SawConfig`, …). Members: lowerCamelCase named after the PRD knob
  (`bigHoopsMult`, `reviveMinHoops`, `rimRestitution`). Units: seconds, points, pt/s, pt/s², degrees — stated in the
  doc comment; ratios as fractions (0.45, not 45). **Every member's doc comment starts with its PRD section**, e.g.
  `/// §3.17 Hold duration range (s).`
- **Tables.** `DirectorTables.prd2` is a `const` object:

```dart
class LayoutBand { const LayoutBand({required this.from, required this.centre, required this.dy, required this.tilt,
  required this.tiltWeights, required this.moving}); final int from; final (double, double) centre;
  final (double median, double p90, double max) dy; final double tilt; final Map<int, int> tiltWeights; final double moving; }
class BudgetRow { const BudgetRow(this.from, this.special, this.gap); ... }
class SpecialRule { const SpecialRule({required this.from, required this.weight, this.weightFrom45, required this.minSince,
  required this.cooldown, this.allowedInSqueeze = false, this.blockedNearPortal = 0}); ... }
class GapItemRule { const GapItemRule({required this.from, required this.weight, required this.minSince, this.maxPerRun,
  this.allowedInSqueeze = false}); ... }
class Schedule { const Schedule({required this.first, required this.then}); final (int, int) first, then; }
class DirectorTables { const DirectorTables({...}); final List<LayoutBand> bands; final List<BudgetRow> budget;
  final Map<HoopKindId, SpecialRule> specials; final Map<ElementId, GapItemRule> gapItems;
  final Schedule portal, comet, heart; final (int, int) featherWindow, pieceWindow;
  final Map<PairReward, int> pairWeights; final Map<CapsuleType, int> capsuleWeights;
  final Map<String, int> movingTypes20, movingTypes45; static const prd2 = DirectorTables(...); }
```

- **Mirror test.** WP-0b copies `design/reference/data/spawn_tables.json` into
  `test/fixtures/spawn_tables.json` (the workspace `design/` is outside the repo) and `test/run/config/tables_mirror_test.dart`
  asserts `DirectorTables.prd2` equals it, with the PRD overrides listed in §2.2 asserted explicitly.

---

## 5. Persistence (PRD §7 table → `lib/game/storage.dart`)

Pattern stays: public field loaded in `load()` + `Future<void> saveX(value)`. **WP-0b adds every key below in one
`// region PRD-2 keys` block** with the round-trip test `test/run/persistence_test.dart` (each key round-trips with its
default). Later WPs only read/write them.

| Key | Type / default | Field | Setter(s) | Used by |
|---|---|---|---|---|
| `bestScore` | int 0 | `bestScore` | `saveBestScore` (exists) | results, levels, versus |
| `gamesPlayed` | int 0 | `gamesPlayed` | `incrementGamesPlayed` (exists) | — |
| `muteSound` | bool false | `muteSound` | `saveMuteSound` (exists) | pause sound button |
| `musicVolume` | double 0.6 | `musicVolume` | `saveMusicVolume` (exists) | — |
| `rumble` | bool true | `rumble` | `saveRumble` (exists) | 2c |
| `feathers` | int 0–3, 0 | `feathers` | `saveFeathers(int)` | 4a |
| `puzzlePieces` | int 4-bit mask, 0 | `puzzlePieces` | `savePuzzlePieces(int)`, `completePuzzleRound()` (mask 0 + round + 1 in one write) | 4a |
| `puzzleRound` | int 0 | `puzzleRound` | `savePuzzleRound(int)` | 4a |
| `lastPortalRide` | String? null | `lastPortalRide` | `saveLastPortalRide(String)` | 3b |
| `unclaimedLevelReward` | int 0 | `unclaimedLevelReward` | `saveUnclaimedLevelReward(int)` | 2e (credited at app start if > 0) |
| `metElements` | Set\<String\> (storageIds) empty | `metElements` | `saveMetElements(Set<String>)`, `markElementMet(String)` | 0b |
| `levelRewardsClaimed` | — | **reuses existing `claimedLevels`** (Set\<int\>; highest = max) | `saveClaimedLevels` (exists) | 2e (call: no second key) |
| `versusNickname` | String? (generated once) | `versusNickname` | `saveVersusNickname(String)` | 5b |
| `uploadQueue` | List\<String\> (JSON entries) empty | `uploadQueue` | `saveUploadQueue(List<String>)` | 5b |
| `uploadsToday` + `uploadsDay` | int 0 + String '' | `uploadsToday`, `uploadsDay` | `saveUploadsToday(String day, int count)` | 5b |
| `notifOrder` | List\<int\> (shuffled at first schedule) | `notifOrder` | `saveNotifOrder(List<int>)` | 4b |
| `notifPosition` | int 0 | `notifPosition` | `saveNotifPosition(int)` | 4b |
| `notifLastSent` | Map\<int,String\> (JSON string) empty | `notifLastSent` | `saveNotifLastSent(Map<int,String>)` | 4b |
| `notifPermissionAsked` | bool false | `notifPermissionAsked` | `saveNotifPermissionAsked(bool)` | 4b |

The Firebase uid lives in Firebase Auth. Saw/switch "never twice in a row" is per run (`RunState`), not stored.
"Delete my data" (WP-4c) clears `versusNickname` (regenerated), `uploadQueue`, `uploadsToday/Day`; it does not touch
coins, skins, levels, feathers, puzzle or met elements (Q22).

---

## 6. Versus (§3.13)

### 6.1 Firestore schema (project `flappy-spikes-a2b55`, location eur3)

```
players/{uid}
  name: string (≤ 32)            avatar: string (URL or '')        platform: 'android' | 'ios'
  look: { bird, gear, hat, hoop, trail }: string ids
  best: int  level: int (0–10, derived from best client-side; server recomputes)
  bestRun: RunEntry | null       recent: RunEntry[] (≤ 5, newest first)
  uploads: { day: 'YYYY-MM-DD', count: int }
  updatedAt: timestamp (server)  expireAt: timestamp (client now + 60 d, rules accept ±1 d; TTL policy on players)

RunEntry
  runId: string (client uuid)    score: int   best: int   ts: timestamp
  name, avatar, look, platform   (denormalised so a pool entry is self-contained)
  tl: string  (base64 of uint16 LE centisecond deltas, one per point; ≤ 16 384 chars)
  end: int (cs from the last point to death, 0–65535)
  fl: string (base64, one byte per point: ride 1 | train 2 | gift 4; ≤ 8 192 chars)

pools/{level}_{shard}            level 0–10, shard 0–3   (server-written only)
  level: int  shard: int  updatedAt: timestamp
  entries: (RunEntry + uid + level)[]   newest first, ≤ 150 and ≤ 900 KB total (1 MiB doc cap with long timelines);
                                        ts = server accept time; level = server-recomputed from the player's best

versusRate/{uid}                 server-only (rules deny all clients): { day 'YYYY-MM-DD' UTC, count, seen: runId[≤20],
                                 last: { runId, status, reason?, pool? } }  — upload rate + idempotent retries
```

**Write contract (WP-5a, binding for the 5b client):**
- **One new run per write.** A run is added as `recent[0]` (the rest shift down; `recent` ≤ 5). A new best run is the
  same object in `bestRun` and `recent[0]`; otherwise `bestRun` is unchanged or null. A create holds at most one run.
  (Rules allow at most 1 000 evaluated expressions per request; validating more than one new run per write exceeds it.)
  The upload queue therefore flushes one run per write.
- **Point count == score.** A pair "+5" gift is five points (pass point + gift points, or five gift points, any
  delta — usually 0) flagged `gift` (4); flagged points (ride / train / gift) are exempt from the 0.9 s gap check.
- `best` never decreases (rules); a run counts as a "new best" for the rate only if `bestRun.runId == runId`,
  `score == best` and `score >` the previous stored `best`.
- `runId` ≤ 64 chars; `name` 1–32; `avatar` ≤ 512; `look` five string ids ≤ 40; `platform` `android | ios`.

### 6.2 Security-rule intent (`firestore.rules`, WP-5a) and App Check

- `players/{uid}`: read / create / update / delete only when `request.auth.uid == uid`; field whitelist; `name` 1–32
  chars; `recent.size() <= 5`; `tl` ≤ 16 KB and `fl` ≤ 8 KB (WP-5a: 8 KB of base64 `tl` holds only ≈ 3 000 points, short
  of the LEGEND threshold 5 000); `best >= run.best >= run.score`; `best` never decreases; `updatedAt == request.time`;
  `expireAt` within now + 59–61 d; one new run per write (above).
- `pools/{doc}`: `read: if request.auth != null`; `write: if false` (Admin SDK in the function only).
- Everything else: denied.
- App Check **enforced** on Firestore and on the callable function (console setting; user-only step if Playwright cannot
  do it). Rules cannot rate-limit; the function enforces the upload rate.
- TTL: Firestore TTL deletes whole documents only, so (call) the TTL policy is on `players.expireAt` (inactive players
  vanish after 60 d, "best runs stay while the player is active"); pool entries and `recent` entries older than 60 d
  are trimmed by the function on every write plus a daily scheduled sweep.

### 6.3 Cloud Functions (`functions/`, TypeScript, 2nd gen, region `europe-west1`, Node 22)

| Function | Trigger | Contract |
|---|---|---|
| `onPlayerRunWrite` | `onDocumentWritten('players/{uid}')` | Detect the new run (new `recent[0].runId` or new `bestRun.runId`). Validate (cheat filter): decoded point count == `score`; every gap between consecutive points without the ride/train/gift flag ≥ 0.9 s; `best >= score`; score ≥ 3; display fields re-checked; upload rate ≤ 3 non-best runs per UTC day per uid (+ best always). On accept: in a transaction on `pools/{level}_{random shard}` (+ `versusRate/{uid}`) remove this uid's entries, prepend the entry (+ uid, level, server ts), drop entries > 60 d, trim to 150 / 900 KB. On reject: log + `versusRate/{uid}.last`, no pool write. Also trims `recent` entries > 60 d in the player doc (the follow-up trigger finds nothing new and stops). Level is recomputed from `best` with `functions/src/levels.ts` (thresholds must equal `lib/levels/levels.dart`; `functions/test/levels.test.ts` parses the Dart file and compares). |
| `deleteMyData` | callable (`enforceAppCheck: true`, `consumeAppCheckToken: false`) | Deletes `players/{uid}` and `versusRate/{uid}`, removes the caller's entries from all 44 pool shards, deletes the Auth user (Admin SDK). Idempotent. Returns `{ ok: true, removed }`. Client: `FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('deleteMyData')`. |
| `sweepPools` | `onSchedule('every 24 hours', UTC)` | Trims > 60 d entries in every shard. |

Reference implementations for the 5b client live in `functions/src/` (`matching.ts`: candidates + pool read plan;
`timeline.ts`: codec, `scoreAt`, cheat filter). The Dart matcher test must pass `test/fixtures/versus_matching.json`.

### 6.4 Client interfaces

```dart
abstract class VersusService {                       // lib/services/versus_service.dart
  Future<void> initialize();                         // anon auth, App Check, profile, first prefetch; never throws
  bool get ready;
  OpponentRun? takeOpponent();                       // sync at START: a prefetched match or null (→ solo, no intro)
  Future<void> prefetch();                           // own level + random shard, else a random other level
  Future<void> submitRun(RunSummary s, Look look);   // queue + rules (best always, ≤ 3/day, score ≥ 3), retry online
  Future<void> deleteMyData();                       // callable + local reset + FirebaseAnalytics.resetAnalyticsData()
  VersusProfile get me;                              // name, avatarUrl, level
  Future<void> onPlatformSignIn();                   // links PlatformIdentity credential to the Firebase user
}
class NoopVersusService implements VersusService {}  // default; tests and unconfigured builds (like GameServices)
class FakeVersusService implements VersusService {}  // tests / FS_E2E: scripted pool, records submissions
class FirebaseVersusService implements VersusService {} // 5b; every call try/caught + timeout; failure = solo

abstract class PlatformIdentity {                    // lib/services/identity.dart
  String get platform;                               // 'android' | 'ios'
  Stream<PlatformPlayer?> get player;                // Play Games: GameAuth.player subscription (never isSignedIn)
  Future<AuthCredential?> firebaseCredential();      // PlayGamesAuthProvider.credential(serverAuthCode: GameAuth.getAuthCode(serverClientId)) — only when player != null; never signIn()
}
class PlayGamesIdentity implements PlatformIdentity {}
class GameCenterIdentity implements PlatformIdentity {}  // stub returning null until iOS reopens (GameCenterAuthProvider later)
```

Matching (pure, `lib/versus/matcher.dart`): own level & score < my best → else any → else null; never own uid; no
repeat within a session. Linking: anonymous user `linkWithCredential`; on `credential-already-in-use` sign in with that
credential (the account that already owns the Play Games id wins; call).

### 6.5 App Check flow

```dart
// main.dart, after Firebase.initializeApp (region WP-5b)
await FirebaseAppCheck.instance.activate(
  providerAndroid: (kDebugMode || kE2E)
      ? AndroidDebugProvider(debugToken: kAppCheckDebugToken.isEmpty ? null : kAppCheckDebugToken)
      : const AndroidPlayIntegrityProvider(),
  providerApple: kDebugMode ? const AppleDebugProvider() : const AppleAppAttestWithDeviceCheckFallbackProvider(),
);
```

The debug token for the Pixel 8 / e2e runs is registered in the Firebase console (App Check → Apps → Manage debug
tokens) and passed with `--dart-define=FS_APPCHECK_DEBUG_TOKEN=…`. Release builds never use the debug provider.

---

## 7. Test strategy

### 7.1 Unit / flow tests (`flutter test`, `FlameTester` + `test/helpers.dart`)

- Pure-Dart units (no Flame): director, layout sampler, first-meet, rim collision, pass test, death tumble integrator,
  revive ladder, streak, timeline codec, matcher, nickname, upload queue, reminder scheduler, palettes stage index.
- Flow tests: run a `FlappySpikesGame` headless with `createTestGame`, a fixed `runSeed`, `stepGame`, and the hoop
  autopilot. WP-0b extends `test/helpers.dart` (append-only):

```dart
FlappySpikesGame createTestGame([prefs, worldHeight, services, monetization, {int seed = 7, VersusService? versus}]);
RunController startRun(FlappySpikesGame g, {Powerup starter = Powerup.none, int startHoopIndex = 0,
    List<ElementId> force = const [], RideId? ride});            // start → playing, first tap done, flushAndMount
RunFlight flyRun(FlappySpikesGame g, {double maxSeconds = 120, int? untilHoops, bool autopilot = true,
    double dt = 1 / 60, void Function(RunController r)? onFrame}); // fixed steps, microtask flush every 10 frames
class RunFlight { int hoops, score, coins; double seconds; MistakeCause? cause; List<String> trace; }
void forceNext(RunController r, ElementId e);                    // debugForce shortcut
Iterable<Hoop> hoopsOf(FlappySpikesGame g);  Iterable<Pickup> pickupsOf(FlappySpikesGame g);
List<String> sfxLog(FlappySpikesGame g);  List<RumbleKind> rumbleLog(FlappySpikesGame g);
List<(String, Map<String,Object>?)> analyticsLog(SpyGameServices s);
```

- **Playability gate** (`test/autopilot_test.dart`, rewritten by 1a/1b, extended by every element WP): the autopilot
  reaches ≥ 12 hoops at 568 and 711, with and without Big Hoops, director on with every registered element; and for
  each special type, `startHoopIndex` = its unlock index with the type forced on every allowed slot: ≥ 12 hoops after
  the unlock.
- **Naming.** `test/run/<area>/s<section>_<topic>_test.dart`, test names start with the PRD section,
  e.g. `test('§3.0.4 bird pressed against the inside of a rim end passes (+30°)', …)`. Test IDs in REQ-MATRIX are
  `file::name`.
- **Screenshots.** Same pattern as `captureShot` in `test/menu_screenshot_test.dart` (resize right before capture).
  Each visual WP adds `test/run/shots/<area>_shots_test.dart` writing PNGs to `build/shots/run/<area>/` (never commit
  them, never write to `store/`), at 711 and 568, and compares by eye with the approved PNG named in the PRD section.
  Use `RunController.debugFreeze(t)` (0b) to freeze animations at a time like the mocks' `?at=` parameter.

### 7.2 Firebase Emulator Suite (WP-5a)

`functions/test/` (mocha + tsx) with `@firebase/rules-unit-testing`, the Admin SDK and the real functions emulator
(`firebase-functions-test` is not used: it does not support firebase-admin 14). `npm --prefix functions test` builds,
type-checks and wraps mocha in `firebase emulators:exec --project demo-flappy-spikes --only auth,firestore,functions`
(a demo project: nothing touches the real one). Covers: rules (own doc only, pools read-only, size limits, one new run
per write), `onPlayerRunWrite` (logic called directly with a fixed clock/shard: accept, each cheat-filter reject, rate,
retries, shard trim to 150 / 900 KB, dedupe per uid, 60-day trim, level recompute; plus end to end through the emulated
trigger), `deleteMyData` (over HTTP: App Check missing → 401, delete + idempotent), `sweepPools`, and the matching
fixtures shared with the Dart matcher test (`test/fixtures/versus_matching.json`). The Firestore emulator needs Java ≥ 11
(system Java is fine; JDK 17 also works).

### 7.3 `integration_test/` on the Pixel 8 (`FS_E2E`)

- `flutter test integration_test/<file>.dart -d 38300DLJH004SD --dart-define=FS_E2E=true [--dart-define=FS_E2E_SEED=7] [--dart-define=FS_APPCHECK_DEBUG_TOKEN=…]`
- `kE2E` switches: fixed seed (`kE2ESeed`), `FakeRewardedAds` with the overlay (succeed), App Check debug provider,
  `E2EHooks` (force element, start hoop index, force ride, fake clock offset for reminders, skip VS intro wait),
  the autopilot as the player.
- Files: `integration_test/run_core_e2e_test.dart` (0b harness smoke; 1a/1b extend), `…_elements_e2e_test.dart` (each
  P3 WP adds its element forced once and passed), `revive_results_e2e_test.dart` (2d/2e), `bonus_puzzle_e2e_test.dart`
  (4a), `reminders_e2e_test.dart` (4b: permission + pending requests), `versus_e2e_test.dart` (5b: real Firebase with
  debug App Check: upload, pool read, match, delete my data), `release_e2e_test.dart` (P6).

### 7.4 Where the §7 test-list items go

| PRD §7 / §3.1 item | Test location | WP |
|---|---|---|
| plane crossing: inside scores, outside ends, rim bounces +1 no perfect, pressed against the inside passes (upright + every tilt step), tilted ring never missed early, saw rim kills, exactly-once game over | `test/run/physics/s3_0_4_pass_test.dart`, `s3_0_4_rim_test.dart` (pure) + `test/run/flow/s3_1_hoop_flow_test.dart` | 1a (saw case 3d) |
| run director (same seed → same sequence; tables; schedules; first-meet; force) | `test/run/director/s3_0_3_director_test.dart`, `s3_0_8_first_meet_test.dart`, `s3_0_2_layout_test.dart` | 0b / 1b |
| death physics | `test/run/physics/s3_0_5_tumble_test.dart` | 1a |
| autopilot / gap-variance / layout / collision updates | `test/autopilot_test.dart`, `test/layout_test.dart`, `test/collision_test.dart`, `test/gap_variance_test.dart` → rewritten | 1a / 1b |
| revive: ladder, phoenix (safe line, drift to 70, scroll at 1.65 s, 2 s invuln, Black Hole re-form), ≥ 6 hoops rule, collectables lost, timed powerups ended, squeeze reset | `test/run/screens/s3_14_revive_test.dart`, `s5_9_phoenix_test.dart` | 2d (Black Hole: 3d; squeeze: 3g; collectables: 3e/3f add cases) |
| results: level-up one / several, CLAIM, auto-claim on NEXT, unclaimed at next start, YOUR REWARD incl. puzzle + win/draw, excl. balloon | `test/run/screens/s5_10_results_test.dart` | 2e (puzzle: 4a, win/draw: 5b add cases) |
| versus: timeline on runClock (pause, revive, phoenix, Hourglass), opponent out, WIN/LOSE/DRAW + bonus, solo start | `test/versus/s3_13_*_test.dart` | 5b (Hourglass case 3f) |
| rumble: recorder per event, 90 ms throttle, shake never skipped | `test/run/items/s3_33_rumble_test.dart` | 2c |
| notifications: fake clock, windows, quiet hours + TZ/DST, skip-after-play, 7 d / 14 slots, rotation no repeat in 10 d, fill-in + fallback | `test/services/s3_34_reminders_test.dart` | 4b |
| persistence: every key round-trips with its default | `test/run/persistence_test.dart` | 0b (4c re-checks) |

---

## 8. iOS-readiness and packages

Rules: only plugins that support Android **and** iOS; platform code behind small interfaces in `lib/services/`
(`PlatformIdentity`, `Reminders`, `Rumble`, `VersusService`, `RewardedAds`); nothing in `ios/` (iOS paused); no
`Platform.isAndroid` branches outside `lib/services/` except the existing ones; iOS assets that will be needed later
(`notif_chime.caf`, `GoogleService-Info.plist`) are listed in the iOS setup note, not added.

New packages (resolved with `flutter pub add --dry-run` on Flutter 3.47.6 / Dart 3.13.5, 2026-10-08 — all resolve
with the current lockfile; `firebase_core` moves 4.12.1 → 4.15.0). **This WP does not change `pubspec.yaml`.**

| Package | Version | Added by | Purpose | iOS |
|---|---|---|---|---|
| `integration_test` (sdk) | sdk | 0b (dev) | Pixel 8 e2e | yes |
| `firebase_auth` | ^6.7.0 | 5b | anonymous + Play Games link (`PlayGamesAuthProvider`) | yes (Game Center provider) |
| `cloud_firestore` | ^6.10.0 | 5b | players / pools | yes |
| `firebase_app_check` | ^0.4.8 | 5b | Play Integrity / debug provider (`providerAndroid`, `AndroidPlayIntegrityProvider`, `AndroidDebugProvider`) | yes (App Attest + DeviceCheck fallback) |
| `cloud_functions` | ^6.5.0 | 5b | `deleteMyData` callable | yes |
| `flutter_local_notifications` | ^22.3.1 | 4b | reminders (`AndroidScheduleMode.inexactAllowWhileIdle`; needs core-library desugaring in `android/app/build.gradle.kts`) | yes |
| `timezone` | ^0.11.1 | 4b | `TZDateTime` | yes |
| `flutter_timezone` | ^5.1.1 | 4b | local zone name | yes |
| existing `vibration` ^3.2.1, `games_services` ^5.1.0 (has `GameAuth.getAuthCode`), `google_mobile_ads`, `firebase_analytics` | — | — | — | yes |

Fonts/assets: Fredoka SemiBold (SIL OFL, Google Fonts) → `assets/fonts/Fredoka-SemiBold.ttf` + pubspec font family
`Fredoka` (0b). Approved sounds already in `design/menu_v2/sfx/` are copied to `assets/audio/` by 0b; missing ones
are generated by 3h (§8 of REQ-MATRIX lists all).

Functions toolchain: Node 22 runtime target for 2nd-gen functions (local Node 26 runs the emulator), TypeScript,
`firebase-functions` v6+, `firebase-admin` v13+; `npm --prefix functions test`.

---

## 9. WP boundaries and file ownership

### 9.1 Shared files and the region rule

Shared files may be edited by several WPs, but only **inside a marked block** that the WP appends:

```dart
// region WP-2a — hearts / extra life / shield / Big Hoops (PRD-2 §3.3, §3.6, §3.7)
...
// endregion WP-2a
```

Rules: append new regions at the end of the relevant section (enum values: at the end of the enum, each value with a
`// WP-x` comment); never reorder, reformat or edit another WP's region; WP-0b creates the anchors
(`// region anchors — append below`) in each shared file. Merge conflicts in a shared file are resolved by keeping both
regions.

| Shared file | Who touches it, how |
|---|---|
| `lib/game/flappy_game.dart` | 0b plumbing (§2.3); after that only small regions: 1a (stage/coin removal), 2d (pause, lifecycle), 2e (`gameOver`→`results` rename), 4b (lifecycle reschedule), 5b (`beforeRunStart`, versus init) |
| `lib/game/config.dart` | 1a only (core value changes, pipe constants removed). New knobs go to `lib/run/config/<feature>_config.dart` |
| `lib/game/storage.dart` | 0b adds all PRD-2 keys (§5); later WPs read/write only. 4c adds the delete-reset helper in its region |
| `lib/game/sound.dart` | 0b: loop API + entries for existing approved sounds; 3h: entries for generated sounds. Element WPs never add entries — they request them from 3h (or add in their own region only if 3h has landed and the sound is truly new) |
| `lib/game/palettes.dart` | 1a (`stageForHoops`) |
| `lib/run/features.dart`, `lib/run/hoops/kinds/registry.dart`, `lib/run/pickups/registry.dart`, `lib/run/screens/post_run_screens.dart`, `lib/run/run_events.dart`, `lib/run/items/analytics_router.dart` | one region per WP (registration lines) |
| `lib/menu/wallet.dart` (`CoinSource`) | 0b adds all sources |
| `lib/services/ads_service.dart` (`AdPlacement`) | 0b adds `bonusFeathers`; 2e removes `doubleCoins` |
| `lib/services/game_services.dart` | regions per WP only if a typed helper is needed (prefer `track`) |
| `lib/components/settings_panel.dart` | 4c (Delete my data row) |
| `lib/components/debug_panel.dart` | 0b (force menu page) |
| `lib/main.dart` | 4b (reminders init), 5b (Firebase auth/App Check/versus) |
| `test/helpers.dart` | 0b API; later WPs append helpers in regions |
| `pubspec.yaml` | 0b (integration_test, Fredoka, audio already covered by `assets/audio/`), 4b, 5b (one region each) |
| `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts` | 4b (notifications, desugaring) |
| `SPEC.md` | DEVIATION notes, one section per WP |
| `docs/gameplay-v2/REQ-MATRIX.md` | every WP fills its rows' test IDs and status |

### 9.2 Ownership per WP

| WP | Owns (creates / exclusively edits) | Shared-file regions | Depends on |
|---|---|---|---|
| **0a** | `docs/gameplay-v2/ARCH.md`, `REQ-MATRIX.md` | — | — |
| **0b** scaffolding | `lib/run/{run_controller,run_setup,run_state,run_clock,run_events,run_context,run_layers,run_geometry,elements,features,run_feature,mistakes,run_summary,run_spawner}.dart`; `lib/run/director/**`; `lib/run/config/{run_config,director_tables}.dart`; `lib/run/hoops/{hoop,hoop_kind}.dart` skeleton + `kinds/registry.dart`; `lib/run/pickups/{pickup,pickup_kind,registry}.dart`; `lib/run/rides/ride.dart`; `lib/run/screens/{post_run_flow,post_run_screens}.dart`; `lib/run/debug/**`; `lib/run/items/{analytics_router,met_elements}.dart`; `lib/versus/{opponent,timeline}.dart`; `lib/services/{versus_service (interface+noop+fake),e2e}.dart`; `integration_test/run_core_e2e_test.dart`; `test/fixtures/spawn_tables.json`; `test/run/director/**`, `test/run/persistence_test.dart`; Fredoka font; approved sounds copied | flappy_game.dart (plumbing), storage.dart (all keys), sound.dart (loop + existing), wallet.dart, ads_service.dart, debug_panel.dart, helpers.dart, pubspec.yaml | 0a |
| **0c** shared parts (recommended new WP, parallel with 0b) | `lib/run/effects/**` (except `miss_flash.dart`), `lib/run/hoops/ring_painter.dart`, `lib/run/hud/{banners,collect_slot}.dart`, gold/dead-eye params in `look_component.dart` / `look_painter.dart`, `SpikeTeethPainter` + 44 pt art in `spike_strip.dart`; `test/run/shots/parts_shots_test.dart` | — | 0a |
| **1a** hoops replace pipes | `lib/run/physics/**`, `lib/run/hoops/kinds/normal.dart`, `lib/run/items/scoring.dart`, `lib/run/effects/miss_flash.dart`; delete `pipe_pair.dart`; Bird tumble mode | config.dart, flappy_game.dart (regions), palettes.dart, SPEC.md; rewrites pipe tests | 0b, 0c |
| **1b** layout + director wiring | `lib/run/hoops/motion/**`, `lib/run/config/layout_config.dart`, heart *placement* wiring (no heart component), `test/run/director/s3_0_2_*`, layout/autopilot tilt+moving cases | registries | 0b (parallel with 1a) |
| **2a** hearts / extra life / shield / Big Hoops | `pickups/{heart,shield}_pickup.dart`, `items/{extra_life,shield,big_hoops}.dart`, `config/{lives,big_hoops}_config.dart`, HUD heart-badge over bird | registries, features | P1 |
| **2b** streak / tiers / banners / pass sounds | `items/streak.dart`, `config/streak_config.dart`, tier wiring of `RingTierFx`/gold bird/trail | features | P1, 0c |
| **2c** rumble wiring | `items/rumble_router.dart`, rumble tests | features | P1 |
| **2d** HUD + pause + revive v2 | `hud/{run_hud,heart_indicator,versus_bar,pause_button,name_chip}.dart`, `screens/{pause_screen,revive_screen,revive_ladder,phoenix_rise,shop_overlay}.dart`, `config/revive_config.dart` | flappy_game.dart (pause/lifecycle), post_run_screens | P1 |
| **2e** results page | `screens/results_screen.dart`, `config/results_config.dart`; deletes `gameover_panel.dart`; renames `gameOver`→`results` | flappy_game.dart, post_run_screens, ads_service (drop doubleCoins) | P1 |
| **3a** comet | `items/comet.dart`, `rides/comet_ride.dart`, `pickups/comet_star.dart`, `CometSpeedLines`, `config/comet_config.dart` | registries | P2 |
| **3b** portal rides | `hoops/kinds/portal.dart`, `rides/{portal_ride,ride_theme,ride_path}.dart`, `rides/themes/**`, `CannonSpeedLines`, `RideSpeedLines`, `config/portal_config.dart` | registries | P2 |
| **3c** Bullseye / Train / Spring / Lucky Spin / FEVER | `hoops/kinds/{bullseye,train,spring,lucky_spin,fever}.dart`, `items/fever.dart`, `FeverBanner` drawing, configs | registries | P2 |
| **3d** saw / switch / pairs | `hoops/kinds/{saw,switch,pair}/**`, configs | registries | P2 |
| **3e** Star Trail / Egg / Piggy / Firefly | `pickups/{star_trail,egg_pickup,piggy_pickup,piggy_coin,jar_pickup,firefly_swarm}.dart`, `items/{egg,piggy,jar,star_trail_feature}.dart`, `hud/run_badges.dart`, configs | registries | P2 |
| **3f** Hourglass / Mini Bird / Coin Frenzy | `pickups/capsule.dart`, `items/{timed_powerup,hourglass,mini_bird,coin_frenzy}.dart`, `hud/timer_pill.dart`, configs | registries, sound (music rate already in 0b) | P2 |
| **3g** spike squeeze | `items/squeeze.dart`, `config/squeeze_config.dart`, squeeze parts of `spike_strip.dart` / `spike_walls.dart` / `score_hud.dart` | features | P2 |
| **3h** sound pack | done: `design/menu_v2/gen_sfx15.py` outputs (88 one-shot mp3 + 4 loop wav) → `assets/audio/*`, all new `Sfx`/`SfxLoop` entries + `docs/gameplay-v2/SOUNDS.md` | sound.dart | — (done) |
| **4a** feathers + balloon bonus + puzzle | `pickups/{feather_pickup,puzzle_piece_pickup}.dart`, `items/{feathers,puzzle}.dart`, `screens/bonus_screen.dart`, configs | registries, post_run_screens | P3 |
| **4b** reminders | `lib/services/reminders.dart`, android res/raw + keep.xml + icon, permission prompt | main.dart, flappy_game.dart lifecycle, pubspec, manifest, gradle | 0b (independent of gameplay) |
| **4c** persistence table + Delete my data | settings row + confirm dialog, `VersusService.deleteMyData` call site, data-safety notes in `SUBMISSION.md` | settings_panel.dart, storage.dart (reset helper) | 0b; real delete needs 5b |
| **5a** versus backend | `functions/**`, `firestore.rules`, `firestore.indexes.json`, firebase.json keys, emulator tests | — | 0a |
| **5b** versus client + VS intro + results versus parts | `lib/versus/{matcher,nickname,upload_queue,run_entry}.dart`, `lib/services/{versus_service (Firebase impl),identity}.dart`, `items/versus_recorder.dart`, `screens/versus_intro.dart`, versus parts of results (region in `results_screen.dart`) | main.dart, flappy_game.dart, pubspec, results_screen (region) | 5a, 2d, 2e |
| **6** final e2e + release | `integration_test/release_e2e_test.dart`, version bump, store notes | — | all |

### 9.3 Recommended split changes (phases kept)

1. **Put the whole director in WP-0b** (pure Dart, every table and rule, first-meet, force, determinism test), and let
   element WPs only register a `HoopKind`/`PickupKind`. Otherwise every P3 WP edits `run_director.dart` at once.
   WP-1b keeps layout geometry (tilt, motion paths, guides) and the heart placement wiring.
2. **Add WP-0c "shared parts"** in parallel with 0b: all §3.0.9 masters + the extra shared parts of §3, with screenshot
   tests. 0b is already large, and every P2/P3 WP needs the masters on day one.
3. **Move WP-3h (sound pack) into P2** (parallel), and let 0b copy the already-approved sounds. P3 WPs then reference
   finished `Sfx` names and never edit `sound.dart`.
4. **All storage keys in WP-0b** (§5). WP-4c keeps "Delete my data" + the data-safety/store declarations + a final
   persistence audit; it no longer gates other WPs.
5. **WP-2c is small** (the `Rumble` service and the settings row already exist): it can be folded into 2b. Kept as a
   separate WP here only to respect the plan.
6. **WP-4c's real deletion needs 5a/5b**; build the UI and call `VersusService.deleteMyData()` (no-op until 5b).

---

## 10. Calls made in this document

| Call | Where |
|---|---|
| Physics: Forge2D only for the bird's vertical motion; all contacts in plain math; tumble kinematic | §0 |
| HUD and run screens in `camera.viewport` (real time, not slowed, not shaken); Hourglass scales the world via `RunScaledWorld.updateTree` | §0, §2.3 |
| Third seeded stream `timing` (beside `layout`/`cosmetic`) so clock-driven rolls never shift the slot sequence | §2.2 |
| `GameState.gameOver` kept as the results state until 2e renames it to `results` | §2.3 |
| Backgrounding the app pauses a running run | §2.3 |
| Shield absorbs before the extra life when both are active | §2.6 |
| Tier look applies to normal, bullseye, Lucky Spin, train and ride rings; not saw, switch, FEVER, pair, spring, portal | §2.5 |
| In-run `coins_earned` aggregated per source at run end | §2.7 |
| `CoinSource.levelReward` keeps analytics name `level_reward` | §2.7 |
| Equipped hoop skin / trail used in runs; gameplay gold wins while active; non-classic birds get a gold outline at tier 2+ | §3 |
| `levelRewardsClaimed` = existing `claimedLevels` | §5 |
| Firestore TTL on `players.expireAt`; pool / recent entries trimmed by the function + daily sweep | §6.2 |
| Pool shard cap also 900 KB (1 MiB doc limit with long timelines) | §6.1 |
| Timeline: one entry per point; a +5 gift = 5 entries at the same time with the `gift` flag; the 0.9 s check skips flagged points | §6.1, §6.3 |
| Play Games link conflict: the account that already owns the Play Games id wins | §6.4 |
| Debug force menu reachable from home (queued for the next run) and from the pause screen (debug builds) | §1.12 |
| Delete my data regenerates the nickname and clears the upload queue | §5 |
| WP-5a: one new run per player-doc write (rules expression limit); `bestRun` new only as `recent[0]` | §6.1 |
| WP-5a: `tl` ≤ 16 KB / `fl` ≤ 8 KB (8 KB `tl` cannot hold a LEGEND-level run) | §6.1, §6.2 |
| WP-5a: server-only `versusRate/{uid}` holds the UTC-day upload count, seen runIds (idempotent retries) and the last verdict | §6.1, §6.3 |
| WP-5a: pool entry `ts` = server accept time (client clocks cannot keep an entry alive); entry carries `level` | §6.1 |
| WP-5a: `expireAt` set by the client to now + 60 d, rules accept ±1 d | §6.1, §6.2 |

---

## 11. WP-0b contract notes (as built, 2026-10-08)

Changes to the contracts above, made while building WP-0b. Later WPs build against these.

| Area | As built | Why |
|---|---|---|
| `HoopKindId`, `RideId`, `RideKind`, `PairReward`, `CapsuleType`, `SawDesign`, `SwitchDesign`, `MotionType`, `SpringDir` | live in `lib/run/director/plans.dart`; `hoops/hoop_kind.dart` and `rides/ride.dart` re-export them | the director stays pure Dart (§1.2) |
| `SlotPlan` | + `attached` (the switch of a switch ring — it sits in the gap *before* the ring — and the comet star), + `duringRide`, `lastRingX`; `extra` uses `TrainSpec`, `SpinPrize` (slice + coins) | the switch is decided with its ring, after the gap before was planned (prototype order) |
| `GapItemPlan` | `y == null` items carry `lineOffset` (heart / shield off the line), runs carry `toTrackX`; the spawner fills `y`/`toY` via `resolved()` once the next slot is planned | the line needs the next hoop's centre |
| `DirectorContext` | + `featherWanted` (`feathers < 3`), `puzzleMask`; `DirectorContext.open(vh, …)` for pure tests | feather / piece rules |
| Director calls | first slot after a revive is plain (upright, still, no comet); Big Hoops mult also scales ride hoops (capped to the band); a forced spring with no room moves to the edge of its range that leaves room (within the row's max jump), a rolled one becomes normal; feather / piece wait during the squeeze window (R-3.17-10); `startHoopIndex` shifts a comet / portal schedule that lies before the start by the start and pulls the heart / feather / piece to the start | §3.0.3 ambiguities |
| First-meet | one queue over slots and gaps, oldest unlock first; a head that waited > 10 indices without its rules allowing it (e.g. shield while the home-slot shield stays armed) goes behind the others for the rest of the run; capsule types are met separately (`hourglass`, `miniBird`, `coinFrenzy`; `capsule` follows any) | one stuck element must not block all others |
| Registries | `hoops/kinds/registry.dart`: `_kinds` (HoopKindId → factory) + `_hoopElements` (modifiers / scheduled elements: angled, moving, comet, portal register here); `pickups/registry.dart`: `_kinds` (ElementId → PickupKind) + `_pickupElements`; `testHoopKinds` / `testPickupKinds` seams. The spawner is **live only once `HoopKindId.normal` is registered** (WP-1a); until then the 1.0 pipes run and the controller is in "legacy pipes" mode | |
| Layers | the four `RunTrack`s are direct children of the world (added by the controller on mount) | z-order against the bird / strips |
| Events | the squeeze event is `SqueezePhaseChanged` (the name `SqueezePhase` is the enum); + `DebugForced(element)` for elements the director does not place (squeeze) | name clash; §3.0.8 |
| `Hoop` | skeleton: `front` (`HoopFrontLayer` in `layers.front`), `HoopMotionDriver` interface (1b's `HoopMotion` implements it), `announced`; `frame()` is WP-1a's | |
| `HoopKind` | `onRim(Hoop, RimTouch, ctx)`; `autopilotTarget(Hoop, RunState, double birdY)` (default: nearest ring) | |
| `Pickup` | `id` is an `ElementId`; `PickupRadii` (§3.0.3); hit test + `isPast` in the base; the spawner runs collect / escape | |
| `RunController` | `RunController({setup, game})`; `legacyPoint(score)` and `endRun()`; death → `game.endRun(summary)` → persistence → `PostRunFlow` (`PostRunScreens.revive/bonus/results` statics; results default = `LegacyGameOverResults`); `game.onBirdHit([MistakeCause])` routes into `run.mistake` | |
| `RunClock` | `tick(gameDt)`: `RunScaledWorld` (lib/run/run_scaled_world.dart) already scales the world by `RunState.timeScale` | |
| `RunContext.addScore` | does not write the timeline; WP-5b's recorder does from `ScoreChanged` | single writer |
| Sound | `SfxLoop { cometLoop, sqHold, sawWireHum, sawFrostHum, sawHoleHum, feverLoop }` ship as `.wav` (seamless, iOS-playable); `SoundService.loop/stopAllLoops/setMusicRate/duckMusic`, `onLoop` seam | |
| Analytics | `CoinSource.aggregatedInRun`; the game's wallet hook skips those sources, the router sends them per (source, egg_x2) at `RunEnded` | |
| Test harness | `createRunTestGame({prefs, worldHeight, services, monetization, seed, versus})` (Dart cannot mix positional and named optionals); `createTestGame` sets `runSeed = 7`; the spy is `AnalyticsSpy` (`SpyGameServices` exists in leaderboard_test) | |
| Debug | `RunDebugState` on the game (`runDebug`): start hoop, force queue, forced ride, bot, god, overlay; the debug panel's `RUN DEBUG >` page (paged) | |
| e2e | `FS_E2E` builds use `Monetization()` (fake ads + fake store) with the visible fake-ad overlay | |
