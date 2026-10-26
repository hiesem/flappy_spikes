# Flappy Spikes 2.1 — gameplay v2 architecture (PRD-2)

Status: WP-0a design stage, 2026-10-08. Source of truth for behaviour: `PRD-2-gameplay.md` (workspace root).
This document is the module map and the contract set every later WP builds against. If a WP must change a
contract, it updates this file in the same commit and says so in its report.

Precedence: PRD-2 > this document > `design/menu_v2/proto_gameplay.html` > mocks. `CLAUDE.md` invariants always hold
(`maxTranslation = 10000`, low-latency pool-only SFX (`SfxPool`, PRD-2.2 §33), never `GameAuth.signIn()` at launch, never `GameAuth.isSignedIn`,
`Config.uiAccent` on game-over text, no `ios/` edits).

Companion: [REQ-MATRIX.md](REQ-MATRIX.md) — one row per requirement, owning WP, test IDs, status.

---

## 0. The shape of a 2.0 run (read first)

```
FlappySpikesGame (Forge2DGame, owns GameState, menus, persistence, services)
 ├─ world: RunScaledWorld (Forge2DWorld; updateTree(dt × timeScale) — Hourglass slows everything in it)
 │   ├─ backdrop, ScoreHud (score circle master #2, RunLayer.scoreCircle −100), SpikeStrip ×2 (master #1)
 │   ├─ RunBannerLayer (RunLayer.banners −60, PRD-2.2 §12): the run's banner host (every banner), the collect stickers and the puzzle's collect text (`CollectLabels`, §12.1); real time, frozen by pause, screen-anchored, fades with `RunHud.rowOpacity`
 │   ├─ Bird (Forge2D body: vertical physics only; x pinned to 70 in flight)
 │   └─ RunController (Component, one per run; null on the home screen)
 │        ├─ RunTrack.back   (priority RunLayer.hoopBack)  ← hoop back halves, guides, ghosts, switch barriers
 │        ├─ RunTrack.items  (priority RunLayer.items)     ← pickups, coins, stars, fireflies
 │        ├─ RunTrack.front  (priority RunLayer.hoopFront) ← hoop front halves, front decorations
 │        └─ RunTrack.fx     (priority RunLayer.fx)        ← pooled particles, popups, shock rings
 └─ camera.viewport (screen space, REAL time — not slowed, not shaken)
     └─ RunHud (top row: heart, pause, versus bar; collect slot / tray / pill and fetch flights; timer pill; graze notice) + run screens (pause, revive, bonus, results, VS intro)
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
| `run/run_controller.dart` | Owns one run: state, clock, director, spawner, physics step, features, layers, mistake pipeline, end of run | `class RunController extends Component with HasGameReference<FlappySpikesGame>` — `RunController({required RunSetup setup})`; `RunState get state`; `RunContext get ctx`; `RunEvents get events`; `void open()` (PRD-2.3 §10.1/§10.2: the run opens waiting — features attach, hoop 0 placed at x 290, mid + 16; the game calls it right after adding the controller); `void beginWaiting()` (PRD-2.3 §10.3b: the bird is floating and tappable, the tap-reminder count `waitClock` starts; solo at START, versus after the VS intro, wired next to `onVersusIntroFinished`); `bool get waiting` / `waitingBegun` / `double get waitClock`; `void start()` (the first tap, PRD-2.3 §10.1: clock on, `RunStarted`; the game flaps first); `void onTap()`; `void pause()`; `void resume()`; `bool get isScrolling`; `void mistake(Mistake m)`; `void revive(ReviveKind k)`; `RunSummary summarize()`; `void disposeRun()` | run/*, services/*, menu/wallet | the spawner block in `FlappySpikesGame.update`, `onScoreSensor`, `onBirdHit` body |
| `run/run_setup.dart` | Inputs to a run | `class RunSetup { int seed; Powerup starter; OpponentRun? opponent; int startHoopIndex = 0; List<ElementId> forced = const []; RideId? forcedRide; double viewHeight; }` | — | — |
| `run/run_state.dart` | All mutable run data (pure data, no logic). Complete from WP-0b; feature WPs fill behaviour, not fields | see §2.1 | run/elements | — |
| `run/run_clock.dart` | runClock + timeScale | `class RunClock { double t; bool running; double timeScale; void tick(double dt); }` | — | — |
| `run/run_events.dart` | Typed synchronous event bus + the event catalogue | `class RunEvents { void on<T extends RunEvent>(void Function(T) h); void off<T>(…); void emit(RunEvent e); }` + `sealed class RunEvent` (§2.4) | run/elements | — |
| `run/run_context.dart` | Facade handed to kinds/features: sinks + read access | `class RunContext { RunState get s; RunEvents get events; RunDirector get director; Random get cosmetic; void sfx(Sfx s); LoopHandle loop(SfxLoop l, {double volume}); void knock(); void shake(); void track(String event, [Map<String,Object>? p]); void earn(int coins, CoinSource src); void addScore(int n, {PointFlags flags}); void mistake(Mistake m); void emit(RunEvent e); RunLayers get layers; RunGeometry get geo; double get viewHeight; }` | game, wallet, sound, rumble, services | — |
| `run/run_layers.dart` | Track layers + z constants | `class RunLayers { RunTrack back, items, front, fx; }`, `abstract final class RunLayer { static const backdrop=-1000, scoreCircle=-100, banners=-60 (PRD-2.2 §12), guides=-20, hoopBack=-10, items=-6, strips=-5, deadBird=-7, bird=10, hoopFront=12, fx=15, rideCannon=11; }` | — | `SpikeStrip.basePriority` stays −5 |
| `run/run_geometry.dart` | Band / tooth lines / safe line math (§3.0.1 screen heights, §3.0.2 band rule) | `class RunGeometry { double get topTooth; double get floorTooth; double get band; double fraction(double f); double clampCentre(double y, double opening, {double extra}); double safeLine(); Vector2 toTrack(Vector2 screen); }` | run_state | `Config.gapBottomMinFor/MaxFor` (pipe bands; the "same stub" invariant becomes "same margin 7 + 18 pt both sides") |
| `run/elements.dart` | Every catalogue element id (§3.0.7) incl. storage ids | `enum ElementId { normalHoop, angledRing, movingRing, bullseye, train, spring, switchRing, pair, fever, luckySpin, saw, portal, comet, heart, shield, starTrail, capsule, hourglass, miniBird, coinFrenzy, egg, piggy, jar, feather, puzzlePiece, squeeze, bigHoops, … }` with `String get storageId` (snake_case, stable) and `ElementKind kind` (slot / modifier / gap / schedule / event / starter) | — | — |
| `run/features.dart` | Registry of run features (append-only regions) | `List<RunFeature> buildRunFeatures()` | all features | — |
| `run/run_feature.dart` | Feature interface | §2.6 | — | — |
| `run/mistakes.dart` | The one mistake pipeline (§3.3 list) | `class Mistake { MistakeCause cause; Vector2? normal; ThemedDeath? themed; Hoop? hoop; }`, `enum MistakeCause { missedHoop, spikes, saw, closedSwitch, pairMissed }`, `abstract class MistakeInterceptor { int get order; bool tryAbsorb(Mistake m, RunContext ctx); }` | run_state | `onBirdHit` |
| `run/run_summary.dart` | Immutable result handed to post-run screens and versus upload | `class RunSummary { int score, hoopsPassed, coins, bestBefore, bestAfter, saves, revives; double runSeconds; MistakeCause cause; HoopKindId? hoopKind; int hoopIndex; RunTimeline timeline; OpponentRun? opponent; DuelResult? duel; }` | versus/timeline | `GameOverPanel` args |
| `run/run_spawner.dart` | Turns director plans into components; keeps one spacing ahead of the screen; removes off-screen parts. **PRD-2.2 §15**: plans one slot ahead (`plannedAhead`: planned when the hoop before it spawns; its line items before it and its attached items exist off-screen; its hoop spawns 60 pt past the edge as before); feature follow-ups created inside the screen pop in (`spawnItem`). **PRD-2.2 §27**: keeps `RunState.activity` in sync (`syncActivity`, `ActivityStarted` / `ActivityEnded`) and clears the rewards ahead when one starts (`clearRewardsAhead`). **PRD-2.3 §17** (P23-17): `bigBonusOpen` / `openBigCount` feed `DirectorContext.bigBonusOpen` (one open big bonus, §17.2/§17.3); each slot's hoop is created at its own edge `creationEdge(plan)` = max(60, visual reach + 8) so halos / beams scroll in (§17.4; reach in each element's config, `slotReach` / `itemReach` / `visualLeftX` / `hoopVisualLeftX`); `clearRewardsAhead` clears only what is not visible yet (`isVisible` / `hoopVisible`) — no fade for anything on screen (§17.5) | `class RunSpawner { void update(double dt); void clearAhead({double fade = 0.2}); void clearRewardsAhead({double fade = 0.2}); void syncActivity(); SlotPlan? get plannedAhead; Pickup? spawnItem(GapItemPlan p); Hoop? nextHoopAhead(); Iterable<Hoop> get hoops; Iterable<Pickup> get pickups; bool get bigBonusOpen; int get openBigCount; static double creationEdge(SlotPlan p); bool isVisible(Pickup p); bool hoopVisible(Hoop h); }` | director, hoops, pickups | the 1.5 s pipe timer |

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
| `tuning_types.dart`, `tuning_values.dart`, `tuning_defaults.dart` | P23-15, audit 17 | The gameplay value table (PRD-2.3 §14). Every §14 value is a `TuningDef` key in `tuning_defaults.dart` (a const table); config getters read `TuningValues.current`, which is always `TuningValues.defaults()` in the app (tests assign overrides). The Remote Config read, `tuning_codegen.dart` and `tool/tuning_sync.dart` were removed in audit 17 (DEVIATION from PRD-2.3 §15) |
| `gates_config.dart` | P23-14 | **2.3:** lifetime unlock gates (PRD-2.3 §14.6, `gate_*` keys) |

### 1.4 `lib/run/physics/` (WP-1a; squeeze walls API used by WP-3g)

| File | Responsibility | API |
|---|---|---|
| `bird_motion.dart` | forward speed + recovery 2000 pt/s², cruise ramp (+3.5 %/min of runClock), max fall, flap lock (spring), Mini scale | `class BirdMotion { double cruise(double runClock); void step(RunState s, Bird b, double dt); void knock(Vector2 normal, double restitution); }` |
| `rim_collision.dart` | §3.0.4 1–3, 6: rim-end circles, push-out, restitution 0.85 against the rim end's own velocity (`HoopFrame.velocityAt`: centre motion + rotation), every contact marks a graze, spin 360°/0.35 s; owner 2026-10-13: a hit from inside the gap is the soft rim bump instead of the reflection (`RunConfig.rimSoftBump` 60 pt/s away from the rim along the ring, local x kept) | `RimContact? collideRims(HoopFrame f, BirdCircle b, Vector2 vel)` pure; PRD-2.2 §30: `collideRimsSwept(prevFrame, f, prev, now, vel)` (current pose first, then the sub-step poses of a fast ring: no tunnelling); `void applyBounce(...)` |
| `pass_test.dart` | §3.0.4 5: local-frame plane crossing between rim-end centres; "fully past" miss; one resolution per hoop | `PlaneEvent? testPlane(HoopFrame f, BirdCircle prev, BirdCircle now, {HoopFrame? prevFrame})` (PRD-2.2 §30: `prev` in the previous step's pose, `now` in the current one, local y interpolated, 4 sub-steps for a ring moving > 2 pt per step; `PlaneEvent.offset` = crossing offset from the ring centre in the moving frame, kept as `Hoop.passOffset`), `bool isFullyPast(HoopFrame f, BirdCircle b)` — `enum PlaneEventKind { pass, missPast, closedReached }` |
| `spike_walls.dart` | Current top/floor tooth lines (squeeze-aware), spike contact + save bounce (top ×0.3 down, floor vy −222) | `class SpikeWalls { double top, floor; double squeezeInset; bool touches(BirdCircle b); void saveBounce(Bird b, bool top); }` |
| `death_tumble.dart` | §3.0.5 momentum tumble, ease-out world stop 0.4 s, floor bounces/rest, edge bounces, settle flat | `class DeathTumble { DeathTumble(Mistake m, Vector2 v); bool get resting; void step(double dt); Vector2 position; double angle; }` |
| `hoop_frame.dart` | A hoop's world transform at time t (centre, tilt, ring offsets, velocity, angular velocity) | `class HoopFrame { Vector2 centre; double tilt; List<double> rings; double opening; double rimR; Vector2 velocity; double angularVelocity /* rad/s */; Vector2 velocityAt(Vector2 p); Vector2 toLocal(Vector2 p); double rightmostX; }` |

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
| `heart_pickup.dart`, `shield_pickup.dart` | 2a | `HeartPickupKind` / `ShieldPickupKind` (§14) |
| `comet_star.dart` | 3a | hangs 20 pt past the plane |
| `star_trail.dart`, `egg_pickup.dart`, `piggy_pickup.dart`, `piggy_coin.dart`, `jar_pickup.dart`, `firefly_swarm.dart` | 3e | |
| `capsule.dart` | 3f | one capsule, `CapsuleType` param |
| `feather_pickup.dart`, `puzzle_piece_pickup.dart` | 4a | |
| switch pickups | 3d | live in `hoops/kinds/switch/` (design-owned), registered as pickups |

### 1.7 `lib/run/items/` — what elements do (run features)

| File | Owner | Feature |
|---|---|---|
| `scoring.dart` | 1a | points per pass (PRD-2.2 §13: 1, perfect max(2, streak); attached **after** `StreakFeature` so it reads the new streak), coin per pass (1 / 2 perfect), colour stage per 10 hoops, `point.mp3` on non-perfect |
| `extra_life.dart`, `shield.dart`, `invulnerability.dart` | 2a | `MistakeInterceptor`s (shield order 10, extra life order 20), 2 s invulnerability, flash (`InvulnerabilityFeature`, §14) |
| `big_hoops.dart` | 2a | D = 30–40 s (`timing` stream), mult 1.5 eased over last 8 s, gold look, cap to band |
| `streak.dart` | 2b | streak/tier, banners, pass sounds, FEVER hook (`streak = max(5, streak+1)`), break on graze/save/clean. Perfect is decided in `RunController._pass` via `PerfectBandConfig.isPerfect` (`config/streak_config.dart`): no rim touch, plus — when the remote `point_perfect_band` curve is > 0 at the hoop index (owner 2026-10-13) — the crossing offset within ±band; rides always perfect |
| `rumble_router.dart` | 2b (2c folded in) | events → `Rumble.knock/shake` |
| `comet.dart` | 3a | 10 s × 1.7, auto-pilot, rims ignored, timed-powerup slot |
| `fever.dart` | 3c, P22-V2 | FEVER + the one fire master (`FireMaster`, PRD-2.2 §21): lit by a ×3 streak (`StreakChanged`) or FEVER, size by streak, flame-trail colours, one `fever_loop` player (25 % / FEVER volume with a 0.3 s ramp) |
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
| `portal_ride.dart` | 3b | `class PortalRide implements Ride` — path (arc/line segments or sampled curve), 5 rings at equal arc length over 190 … L − 260 (+ portal = 6 passes; PRD-2.3.1 §7, was 11 / 12), ride camera from live scroll speed, 480 pt/s over 2.2 s, strips fade out 0.8 s, clear ahead (0.2 s), exit → launch flight (560/−640, g 520, 1.7 s) → glide 2.5 s + 0.6 s settle → control returns with a flap; the first ring 2 s later (PRD-2.2 §18) |
| `ride_theme.dart` | 3b | `abstract class RideTheme { RideId id; RidePath buildPath(); void paintWorld(Canvas c, RideCamera cam, double t); ExitChoreography exit; Offset launchPoint; (Color,Color) washTint; Map<RideCue,Sfx> sounds; }` |
| `themes/cannon.dart`, `space.dart`, `volcano.dart`, `sea.dart`, `pinball.dart`, `storm.dart` | 3b | one per ride |
| `ride_path.dart` | 3b | `class RidePath { double length; Vector2 at(double s); double headingAt(double s); }` |
| `speed_lines.dart` | 3a/3b | **three separate classes on purpose** (master #12): `CometSpeedLines` (3a), `CannonSpeedLines`, `RideSpeedLines` (3b) |
| `comet_ride.dart` | 3a | `class CometRide implements Ride` |

### 1.9 `lib/run/effects/` — shared parts (masters, §3) — WP-0c

`particle_pool.dart`, `perfect_burst.dart`, `coin_popup.dart`, `block_trail.dart`, `tier_trail.dart`,
`ring_tier_fx.dart`, `dust_puff.dart`, `shock_ring.dart`, `pickup_touch_fx.dart`, `fetch_flight.dart`, `twinkle.dart`,
`miss_flash.dart` (1a), `gold_sticker.dart`, `invuln_flash.dart`, `spike_teeth.dart`, `dashed_path.dart`,
`screen_edge_glow.dart`, `run_shake.dart`. WP-3e adds `text_pop.dart` (the rising-text pop, moved out of the spring
kind, §21), `collect_art.dart`, `collect_fx.dart` and `hud_fetch.dart` (the shared collectable art / burst / "fly into
the HUD" ease). Details and owners in §3 and §21.

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
| `lib/versus/opponent.dart` | 0b | `class OpponentRun { String uid, name; Look look; int score, best, level; RunTimeline timeline; String platform; }`, `abstract class OpponentFeed { int scoreAt(double runClock); bool outAt(double runClock); }` | — |
| `lib/versus/matcher.dart` | 5b | `OpponentRun? pick(List<PoolEntry> pool, {required int myLevel, required int myBest, required String myUid, required Set<String> seen, required Random r})` | — |
| `lib/versus/nickname.dart` | 5b | `String generateNickname(Random r)` (20 × 20 words, ≤ 14 chars + 3 digits) | — |
| `lib/versus/upload_queue.dart` | 5b | queue + 3/day + score ≥ 3 + best always | — |
| `lib/versus/run_entry.dart` | 5b | Firestore entry (de)serialisation, mirrors `functions/src/schema.ts` | — |
| `lib/services/versus_service.dart` | interface + `NoopVersusService` 0b; Firebase impl 5b | §6.3 | pattern of `GameServices` |
| `lib/services/versus_auth.dart` | P231-B | PRD-2.3.1 §2: `VersusAuth` port (uid, isAnonymous, linkedToPlayGames, sign-in anonymous / with credential, link, sign-out, reload, refreshToken) + `FirebaseVersusAuth`; `FirebaseVersusBackend(auth:, appCheck:, analytics:)` runs the link / switch and the start-up self-healing over it. `PlatformIdentity.firebaseCredential({bool fresh})` (fresh = `forceRefreshToken`). Link outcomes log `versus: link <outcome> <code>` in release + event `versus_link {outcome, code}` | `FirebaseAuth` |
| `lib/achievements/` | P231-E | PRD-2.3.1 §12: `achievement_catalog.dart` (`enum AchievementId`, 48: key, title, descriptions, points, hidden, `androidId` from Play Console, `iosId` = `fs_ach_<key>`; the single source of the store kits), `achievements.dart` (`AchievementTracker` = `game.achievements`: idempotent `unlock`, the run's rules staged as `AchOp`s until `finishRun` and journaled on disk for `recoverJournal` at launch (QA P2-03), the counters (`achRides`, `achItemCounts`, `achVersusWins`, daily streak), the toast queue; **PRD-2.3.1 §19** the run rules only *earn* into the FIFO `achPending` queue (a hoop goal is staged when its threshold is crossed; run-end earnings — versus win, ranks, daily — form one batch sorted by catalog index) and a counting run's `finishRun` unlocks at most one (`releaseOne`, the oldest; all state in the one `achState` key, one write per transition; the shop, the jackpot and the debug unlock call `unlock` at once), the item achievements are lifetime catch goals (`kItemGoals`; a Star Trail counts once, `AchievementsFeature.catchFor`) and MAGPIE is earned once all 11 are unlocked; `syncAll()` over `GameServices.unlockAchievement`), `achievements_feature.dart` (the run rules, a `RunFeature`; only while `RunController.countsForAchievements`: never a forced / `startHoopIndex` / `ignoreGates` / god / bot / `debugPass` / force-menu / e2e / soak run), `achievement_toast.dart` (the results-page / shop pill, one at a time, "+N more"). Ranks and daily run in `FlappySpikesGame.endRun`, GOLDEN EGG in `BonusScreen.tapTile` (`achievements.lastRunCounted`), the shop in `buyTriedOnItem` | — |
| `lib/services/identity.dart` | 5b | `PlatformIdentity` (§6.4) | uses `games_services` |
| `lib/services/reminders.dart` | 4b | `Reminders` service + pure `ReminderScheduler` (§3.34) | — |
| `lib/services/e2e.dart` | 0b | `const bool kE2E = bool.fromEnvironment('FS_E2E'); const int kE2ESeed = int.fromEnvironment('FS_E2E_SEED', defaultValue: 7); const String kAppCheckDebugToken = String.fromEnvironment('FS_APPCHECK_DEBUG_TOKEN');` + `E2EHooks` | — |
| `lib/components/spike_strip.dart` | 0c (art), 1a (44 pt switch), 3g (squeeze), P22-7 (`PlayfieldResizable`) | master #1 | 72 pt sprite tiles |
| `lib/game/playfield.dart`, `lib/game/playfield_viewport.dart` | P22-7 | PRD-2.2 §7.5.2: `PlayfieldResizable { onPlayfieldResize(h) }` registry (`game.registerResizable`), `BannerState`, `InterstitialSkip`; `PlayfieldViewport` = FixedResolutionViewport with `setResolution`. `game.setPlayfieldHeight(visible, {stripDrop})` is the ONLY resize entry point; `viewHeight` = visible + stripDrop, `visibleHeight`, `bottomStripInset` (24 / 44) | `CameraComponent.withFixedResolution` |
| `lib/services/ads_service.dart`, `ads_consent.dart`, `lib/components/banner_slot.dart` | P22-7 | §7.10: `AdsConsent` (once, shared), `RewardedAds` (+`ensureLoaded`), `InterstitialAds`, `BannerAds` — Noop / Fake / AdMob each; `Monetization.{ads, interstitial, banner, consent}`; `BannerSlot` under the `GameWidget` | — |
| `lib/components/score_hud.dart` | 3g adds white-when-covered | master #2 | — |
| `lib/share/share_card.dart`, `share_content.dart`, `share_flow.dart`, `lib/services/share_sheet.dart` | P23-4 | PRD-2.3 §2/§4: `ShareCardPainter` (pure `dart:ui`, 1080², one master per card part: rays, sticker, banner, name tag, spike strips, logo bar; emblem = `EmblemPainter`, birds = `LookPainter`), `ShareCardData`, `ShareContent` (random picks, injectable `Random`), `ShareFlow` (PNG + text, text-only fallback) behind `ShareSheet`. `game.onShareScore` / `game.onInvite` take a `ShareCardData` (was `int score` / no args); the game makes the versus nickname first (`shareName()`) | `SharePlus` |
| `lib/components/bird.dart` | 1a | flight + kinematic tumble mode; `Bird.scale` (Mini), `Bird.goldTier`, `Bird.onFire` flags read by painters | 1.0 death impulse/spin |
| `lib/components/look_component.dart`, `lib/skins/art/look_painter.dart` | 0c | gold tier (#5), white X-eyes (#6) | — |
| `lib/components/gameover_panel.dart` | deleted by 2e | — | — |
| `lib/components/pipe_pair.dart` | deleted by 1a | — | — |
| `functions/`, `firestore.rules`, `firestore.indexes.json`, `firebase.json` (emulators/functions/firestore keys) | 5a | §6 | — |
| `integration_test/` | 0b harness, every WP may add a file, 6 final | §7.4 | — |
| `android/app/src/main/res/raw/notif_chime.ogg` + `keep.xml`, `res/drawable-*/ic_notif_bird.png` (white bird small icon; no large icon), manifest permissions/receivers | 4b | §3.34 | — |

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
  bool onFire = false;      // the bird burns (×3 streak or FEVER, PRD-2.2 §21)
  int feverLeft = 0;        // FEVER: perfect passes left (loud loop, ≥ ×5 fire)
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
  double openingFor(int hoopIndex);  // hoop 0 = 118, then curve_opening (PRD-2.4 §1); rides follow it (§2)
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
  PRD-2.3.1 §17: at most `ride_portal_max` (2; 0 = no limit) portals per run (`portalCount`, monotonic: every placed
  portal counts, also one later turned plain / owed by `plainSlot` / `oweSlot`; a revive does not reset it); at the cap
  the portal step is skipped, the schedule stops, nothing is owed or waits, and a debug-forced portal is discarded.
- PRD-2.3.1 §16 comet layout: `RunSpawner.startCometLayout` (called by `CometRide.start`) finds the last hoop that
  stays (visible / behind the bird), calls `RunDirector.onCometStart(anchorX:)`, which locks `cometStations` (k =
  max(1, round(stretch / ride_comet_hoop_gap)) equal steps up to predicted end − `ride_comet_tail`) and
  `cometAfterMin` (end + `ride_comet_after_gap`, follows `updateCometEnd`); the spawner then re-places every hoop
  group not yet visible and the planned-ahead slot through `RunDirector.cometReplan` (plain ride hoop at the next
  station, zigzag height) and drops every pickup planned in the moved hoops' gaps (everything past the last hoop
  that stays, visible ones included — they fade — plus the waiting line items); pickups in unaffected gaps stay. `nextSlot` takes the remaining stations, then the
  safe first hoop after the comet (normal height).
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
enum GameState { start, playing, results /* the 1.0 gameOver, renamed by WP-2e */, versusIntro, paused, dying, reviving, bonus }
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
| `_startGame` | builds `RunSetup` (seed, starter, `versus.takeOpponent()`, debug forced queue) and adds `RunController`; PRD-2.3 §10.1: START opens the run waiting (`open()`, bird `startHover()`, `beginWaiting()`, the `FirstRunHint`); the first playfield tap (`_firstTap`) does banner / `logGameStart` / `run_start` / `versus.onRunStart` / gravity + flap / `run.start()` | 0b, P23-10 |
| `onScreenTap` / `onPlayfieldTap` | `playing` → `run.onTap()` (ignored in rides / flap lock / tumble) | 0b |
| `onScoreSensor` | deleted (pass test lives in `run/physics/pass_test.dart`) | 1a |
| `onBirdHit` | replaced by `endRun(RunSummary)`: persistence (`incrementGamesPlayed`, `saveLastScore`, best), `noAdsPopup.recordRun`, `logGameOver`, `logNewBest`, `submitBestScore`, versus upload, then `PostRunFlow`; no coins here any more (wallet per pass) | 0b (plumbing) / 1a (removal of interim coin rule) |
| `pause()` / `resume()` | new; Esc and `AppLifecycleState.paused` pause a running run (call: backgrounding pauses) | 2d |
| `goHome()` | accepted from `gameOver`(results); unchanged otherwise | — |
| `replay()` | `_run?.disposeRun()` instead of the `PipePair` query; resets strips (44 pt, squeeze 0) | 0b |
| `update()` | spawner block removed (in `RunController.update`) | 0b |
| `onScoreSensor` colour stage | `stageForHoops(hoopsPassed)` in `palettes.dart` replaces `stageOf(score)` in runs (`stageOf` stays for legacy tests until 1a updates them) | 1a |
| `showRewardedAd` | unchanged; new placements `revive` (exists) and `bonusFeathers` | 0b adds enum |
| `beforeRunStart` | kept as the generic hook; WP-5b does **not** use it — `_runFromHome` takes the opponent at tap time and plays the VS intro itself (§24) | 5b |
| `lifecycleStateChange` | + reminders reschedule on paused/detached (4b), + run auto-pause (2d) | 2d / 4b |
| keyboard | Esc while playing → pause; D (debug) also during pause | 2d / 0b |
| system back | `handleSystemBack()` (PRD-2.2 §8): the Android back closes the menus only (topmost, one close per gesture, `back_gesture` analytics), never a run, the post-run pages or a video ad; `SystemBackObserver` (main.dart) reports every back as handled. Esc unchanged | 2.2 |

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
| `EggHatched` / `JarFilled` / `StarTrailPerfect` / `PuzzleCompleted` | — | egg / jar / star trail / puzzle features, next to their `track(...)` (PRD-2.3.1 §12.2, P231-E) |
| `FeverStarted` | — | `FeverFeature._light(fever: true)`: every real FEVER (the ring's perfect pass, the pair gift), also when already burning; never the streak fire (PRD-2.3.1 §12.2) |

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
- **Audio pool rules (PRD-2.2 §22, §33.4; `lib/game/sfx_pool.dart`, `lib/game/sound.dart`).** Every one-shot `Sfx`
  plays through our own `SfxPool` (not audioplayers' `AudioPool`, which grows without a cap and only `release()`s):
  - **Fixed voice set, hard cap.** `SoundService.voicesFor`: 2 players, 3 for files > 1 s, 4 for the 1.0 sounds
    (flap / point / gameover / click), 6 for the bursts (`bn_coin`, `sk_tick`, `piggy_coin`). The pool is published
    with its first voice; the rest are created right after, one by one per file (SoundPool load race). `play` never
    creates a player: when every voice is busy the **oldest copy is stopped and restarted**.
  - **Full length.** Each play is stopped after `kSoundDurations[file]` (+ 100 ms), the table generated by
    `python3 -I tool/gen_sound_durations.py` into `lib/game/sound_durations.g.dart`; never `getDuration()` (null on
    Android SoundPool). Re-run the generator whenever a sound changes (`test/p22/s22_full_length_sounds_test.dart`
    fails on a stale table).
  - **Dispose, never release.** Voices are disposed only when their pool is evicted or on `SoundService.dispose()`.
  - **No position polling.** `positionUpdater = null` on every SFX voice, loop player and the music player.
  - **One global audio context** (`AudioPlayer.global`, mixWithOthers), set before the first player; no per-player
    context (each one rewrote AudioManager mode on Android).
  - **Bounded lazy pools.** `prewarmed` (core run set) is created at start and never evicted; other pools are created
    on first `play` / `preload` and disposed after `Config.sfxPoolIdleDisposeMs` without a play, or LRU-first above
    `Config.sfxMaxLivePools` (a pool still ringing is kept; "ringing" = really played within its length + margin,
    `SfxPool.lastPlayedMs`, never a preload touch). `preload(Iterable<Sfx>)` warms cues ahead (§18.4): the latest
    batch is reserved (the cap never evicts it), and a preload never goes over the cap — pools alive, being created and
    the core set count; it evicts an idle LRU pool for room, else leaves the rest of the batch to its first `play`.
  - **Session set and run-scoped pools (§33.6, S7-19).** The game calls `warmSession()` once at load: it pins
    `sessionWarm` (post-run count-up / coins / ticks, balloon bonus, LEVEL UP / CLAIM, feather slots, star trail) next
    to `prewarmed` and creates those pools one by one after the core; pinned pools are never evicted. Every other pool
    is run-scoped: `replay()` (Home arrival) calls `endRun()`, which disposes them at once, or via `maintain()` (called
    every game frame, no work when nothing is pending) as soon as their last copy has finished. A pool played or
    preloaded again first stays. So Home always holds exactly the session set (flat live players game after game);
    `Config.sfxMaxLivePools` (56) = the 33 pinned pools + room for one run.
  - **Teardown is final for in-flight work.** `dispose()` bumps a generation: creations still loading publish nothing
    and dispose the voices they made; the core warm-up stops. The service can be used again afterwards.
  - Test seam: `voiceFactory` (fake voices, `test/p22/fake_audio.dart`, which also has a fake audioplayers platform for
    the real `PlayerVoice`).
- **Audio around ads, death and other apps (PRD-2.2 §28).** `SoundService.suspend()` / `resume()` (ref-counted;
  `clearSuspend()` on app resume / scene change when no ad is up) pause the music at its position, stop every loop and
  drop every `play` (a loop asked for while suspended is born stopped); one-shots already ringing are stopped
  (`SfxPool.stopAll`, queued after any pending start, so nothing bursts out after the hold), as on `setInterrupted(true)`. `FlappySpikesGame.showRewardedAd`, the
  interstitial and the fake overlay suspend when the ad is displayed and resume when it ends. `setInterrupted(bool)`
  (from `AudioFocus.interruptions`, `lib/services/audio_focus.dart`) pauses the music and mutes SFX + loops;
  `setOtherMusicActive` skips the game music while the player's own music plays (cleared only at a scene change; the
  check is `FlappySpikesGame._otherMusicNow`: `AudioFocus.isOtherMusicActive`, confirmed by `isOtherMediaListed`
  while `SoundService.ownSoundRecent`, so the game's own flaps never count as other music);
  `setBackground` replaces Bgm's lifecycle observer (the game owns the music lifecycle). The global audio context is
  mixWithOthers with Android usage `USAGE_GAME` (`SoundService.gameAudioContext`), so `MainActivity.kt`'s
  `AudioWatch` can tell the game's players from other apps'. `RunController._die` stops all loops at the moment of
  death; features restart their own loops after a revive. Test seams: `onAudible` (passed every gate), `onMusic`
  (`start` / `pause` / `resume`), `droppedPlays`, `stopAllLoopsCalls`.
- **Music guard and backend (PRD-2.3 §13, §16).** `lib/game/music_guard.dart` (`FlappySpikesGame.musicGuard`,
  stepped from `update`) owns every re-check: it listens to `AudioFocus.changes` (an `AudioWatchState`: interrupted /
  notification / media / `isMusicActive` / the raw playback list), polls `AudioFocus.snapshot()` every 0.5 s while
  the music is held for an interruption or a notification, confirms "own music" with two answers 1 s apart
  (`confirmOwnMusic`: launch, 1 s after a foreground return), re-checks skipped music every 2 s on a menu, clears a
  stale ad suspend after 5 s, runs the 5 s music watchdog (`SoundService.restartMusic`, `player_dead`) and sends
  `music_held` once per Home visit. `SoundService.setOtherSound` is the notification hold (music only).
  `SoundService.musicLog` (`lib/game/music_log.dart`) is the 50-entry diagnostic log (logcat `FS-Music`, debug
  panel MUSIC LOG). The plugin calls go through `MusicBackend` (`lib/game/music_backend.dart`): `JustAudioMusic` on
  Android (ExoPlayer `LoopMode.one`, `USAGE_GAME`, no focus, no position stream), `AudioplayersMusic`
  (`FlameAudio.bgm`) on Linux / iOS. Test seams: `musicBackend`, `musicStateProbe`, `FakeAudioFocus.push`.
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
| 4 | Bird (equipped look, ×0.983, wing flap, blink, themed death tint; no stage blend since PRD-2.2 §20) | `LookComponent` / `LookPainter` | `lib/components/look_component.dart`, `lib/skins/art/look_painter.dart` | look, scale, pose, mirror (VS), opacity | existing |
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
| Fireworks (rocket 0.5 s rise → 34 streaks) | `Fireworks` | `lib/run/effects/fireworks.dart` | results level up, VS intro | 2e |

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
  `ScreenEdgeGlow.miss / reviveUrgency / hourglass / coinFrenzy`; `RunShake` (kick + sustain + the vertical thump (2.5.1 squeeze lock), squeeze helpers);
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
| `puzzlePayout` | int 0 | `puzzlePayout` | `beginPuzzleCompletion(payout)` / `endPuzzlePayout()` | 4a recovery (Fix P45 R1, S6-62): the balance a 4/4 bonus must reach, written with the mask reset + round advance before the coin write, cleared after it; settled at start by `PuzzleFeature.settlePayout` (before the level-reward recovery); **not** a PRD-2 key |
| `uploadsSent` + `uploadsSentDay` | int 0 + String '' | `uploadsSent`, `uploadsSentDay` | `saveUploadsSent(String day, int count)` | 5b pacing (Fix P45 R1, S6-60): non-best runs *written* on a UTC day (the server's rate day); cleared with the versus reset; **not** a PRD-2 key |
| `levelRewardPayout` | int 0 | `levelRewardPayout` | `beginLevelRewardClaim` / `endLevelRewardClaim` + `saveLevelRewardPayout(int)` | 2e recovery (Fix P2 R1, S6-22): bookkeeping for a level-reward credit in flight — the balance the credit must reach, written before it and cleared right after; **not** a PRD-2 key, so it is not in the §7 round-trip list |
| `metElements` | Set\<String\> (storageIds) empty | `metElements` | `saveMetElements(Set<String>)`, `markElementMet(String)` | 0b |
| `levelRewardsClaimed` | — | **reuses existing `claimedLevels`** (Set\<int\>; highest = max) | `saveClaimedLevels` (exists) | 2e (call: no second key) |
| `playerLevel` | int 0 (0–10) | `playerLevel` | `savePlayerLevel(int)` | **WP-L (owner 2026-10-17)**: the stored player level (no longer derived from the best); steps up one per run (`LevelProgress.recordRun` / `levelAfterRun`); reset by "Delete my data" and `resetMenuState`; **not** a PRD-2 key |
| `versusNickname` | String? (generated once) | `versusNickname` | `saveVersusNickname(String)` | 5b |
| `versusCustomName` | String '' | `versusCustomName` | `saveVersusCustomName(String, {syncedUid})` | **WP-NAME (2.4)**: the custom versus name from the Settings PLAYER card (3–14, A–Z/a–z/0–9; '' = none: the player sees "You", opponents the nickname); reset by "Delete my data"; **not** a PRD-2 key |
| `versusCustomNameSync` | String '' (`uid\nname`) | `versusCustomNameSync` | `saveVersusCustomNameSync(uid, name)` | WP-NAME: what `setVersusName` last confirmed for which uid; a differing name (offline edit, new uid) is sent by `FirebaseVersusService.syncCustomName` |
| `versusCustomNameError` | String '' | `versusCustomNameError` | `saveVersusCustomNameError(String)` | WP-NAME: the reason (`length` / `chars` / `blocked` / WP-N2 `taken`) a name saved offline was refused later; shown once in the card |
| `versusCustomNameRead` | String '' (`uid\nYYYY-MM-DD`) | `versusCustomNameRead` | `saveVersusCustomNameRead(uid, day)` | WP-N2: when `getVersusName` last read the server's name back for which uid (UTC day): at once for a new uid / after a link, else at most once a day (the activity ping that keeps a guest's name); reset by "Delete my data" |
| `uploadQueue` | List\<String\> (JSON entries) empty | `uploadQueue` | `saveUploadQueue(List<String>)` | 5b |
| `versusAvatar` | — (WP-AV: removed; the stale key is deleted at load and by the versus reset) | `versusAvatar` | — | was PRD-2.3 §21.3: the last uploaded versus picture (the Firebase uid it belongs to, the SHA-256 of the Play Games icon it was made from, its download URL = the run's `avatar`); re-upload when uid or hash differ, or (S8-06) when `at` is missing or older than `VersusConfig.avatarRefresh` (30 d: the server deletes the picture with the player doc); cleared with the versus reset and the anonymous-account clean-up; **not** a PRD-2 key |
| `uploadsToday` + `uploadsDay` | int 0 + String '' | `uploadsToday`, `uploadsDay` | `saveUploadsToday(String day, int count)` | 5b |
| `notifOrder` | List\<int\> (shuffled at first schedule) | `notifOrder` | `saveNotifOrder(List<int>)` | 4b |
| `notifPosition` | int 0 | `notifPosition` | `saveNotifPosition(int)` | 4b |
| `notifLastSent` | Map\<int,String\> (JSON string) empty | `notifLastSent` | `saveNotifLastSent(Map<int,String>)` | 4b |
| `notifPermissionAsked` | bool false | `notifPermissionAsked` | `saveNotifPermissionAsked(bool)` | 4b |
| `lastFeatherRun` | int −1 | `lastFeatherRun` | `saveLastFeatherRun(int)` | **PRD-2.3 §14.2** (P23-14): the `gamesPlayed` of the run that last showed a golden feather (written in `FlappySpikesGame.endRun` before the increment); never a feather in two runs in a row (`GatesConfig.shownLastRun`) |
| `lastPieceRun` | int −1 | `lastPieceRun` | `saveLastPieceRun(int)` | **PRD-2.3 §14.2**: the same for the puzzle piece |
| `firstRunHintSeen` | bool false (true when the key is missing and `gamesPlayed > 0`) | `firstRunHintSeen` | `saveFirstRunHintSeen(bool)` | **PRD-2.3 §10.3** (P23-10): the first-run instructions were shown. **PRD-2.3.1 §10:** the full instructions write `false` when they show, and `RunController` saves `true` on the run's first pass of hoop 0 (a graze counts; once per run); the first tap saves nothing. Kept by "Delete my data" |
| `gamesPlayed` (2.3) | — | — | `saveGamesPlayed(int)` | **PRD-2.3 §14.6**: the RUN DEBUG "Runs: N (+5 / 0)" row; drives the lifetime gates |
| `playtimeSeconds` | int 0 | `playtimeSeconds` | `savePlaytimeSeconds(int)` | **PRD-2.3 §18.3**: foreground seconds since install (resumed, outside full-screen ads) until the new-player grace ends; written every 10 s, on going to the background and at run end; kept by "Delete my data" |
| `firstInterstitialShown` | bool false | `firstInterstitialShown` | `saveFirstInterstitialShown()` | **PRD-2.3 §18.4**: the one-time `first_interstitial` event went out |
| `lastRatingRequestAt` | int 0 (seconds since the epoch) | `lastRatingRequestAt` | `saveLastRatingRequestAt(int)` | **PRD-2.3 §23.2**: the last request of the store's rating sheet (30-day cooldown); kept by "Delete my data" |
| `achState` | JSON string (`AchState`) | `ach` (+ the read-only `ach*` getters below) | `saveAchState(AchState)` | **PRD-2.3.1 §19, QA P19-01..05 (2.3.1 (21)):** the tracker's WHOLE state (unlocked, reported + player, rides, items, itemCounts, pending, versus wins, day streak, journal + excluded) in ONE key, written by ONE awaited setter per transition (`AchievementTracker._tx`: stage op, run end commit + release, recovery, shop / jackpot unlock, reported mark); analytics, toasts and platform calls run only after that write. A kill keeps the state before or after a transition, never half. The separate `ach*` keys below are the 2.3.1 (20) layout: read once to migrate when `achState` is missing, never written again (`resetAchievements` removes them) |
| `achUnlocked` / `achReported` | Set\<String\> empty | `achUnlocked`, `achReported` | `saveAchUnlocked`, `saveAchReported` | **PRD-2.3.1 §12.3** (P231-E): unlocked achievement keys (local truth) / keys the platform confirmed for `achReportedPlayer`. Kept by "Delete my data"; cleared by `resetMenuState` and the debug "Achievements: reset local" (`resetAchievements()`) |
| `achReportedPlayer` | String '' | `achReportedPlayer` | `saveAchReportedPlayer(String)` | **PRD-2.3.1 §12.4**: the platform player id `achReported` belongs to; a different player clears `achReported` (everything is reported again) |
| `achRides` / `achItems` | Set\<String\> empty | `achRides`, `achItems` | `saveAchRides`, `saveAchItems` | **PRD-2.3.1 §12.2**: portal rides finished (`RideId.storageId`) / item achievement keys caught (FREQUENT FLYER; `achItems` is no longer written since §19, kept for old installs) |
| `achItemCounts` | Map\<String,int\> (string list `key=n`) empty | `achItemCounts` | `saveAchItemCounts(Map<String,int>)` | **PRD-2.3.1 §19.1**: lifetime catches per item achievement key (a Star Trail counts once); the goal is `kItemGoals`. Kept by "Delete my data"; cleared by `resetAchievements()` |
| `achPending` | List\<String\> empty | `achPending` | `saveAchPending(List<String>)` | **PRD-2.3.1 §19.2**: earned achievements waiting for a counting run end (FIFO, oldest first; one unlocks per counting run; recovered journals land here). Never reported or toasted while pending. Kept by "Delete my data"; cleared by `resetAchievements()` |
| `achVersusWins` | int 0 | `achVersusWins` | `saveAchVersusWins(int)` | **PRD-2.3.1 §12.2**: versus wins since 2.3.1 |
| `achDayStreak` + `achLastPlayDay` | int 0 + int −1 | `achDayStreak`, `achLastPlayDay` | `saveAchDays(int streak, int day)` | **PRD-2.3.1 §12.2**: consecutive local days (`storage.today`) with a counted run |
| `achJournal` + `achJournalExcluded` | List\<String\> empty + bool false | `achJournal`, `achJournalExcluded` | `saveAchJournal(List<String>, excluded:)` | **PRD-2.3.1 §12.2 / §12.3** (QA P2-03): the open run's staged rule ops (`AchOp`: `u:`/`ride:`/`item:`/`hoops:`/`vwin:`), written per staged event (hoops only at a threshold) and on backgrounding; a debug assist marks it excluded first. The next launch commits a clean journal (no toast; the platform via `syncAll`) and drops an excluded one; `beginRun`/`finishRun` clear it |
| `armedPowerupDebug` | bool false | `armedPowerupDebug` | `saveArmedPowerup(String, debug:)` | **PRD-2.3.1 §12.2** (QA P2-02): the armed slot powerup came from a debug "Slot: force …" roll; written, restored and cleared together with `armedPowerup` |

The Firebase uid lives in Firebase Auth. Saw/switch "never twice in a row" is per run (`RunState`), not stored.
"Delete my data" (WP-4c) clears `versusNickname` (regenerated), `uploadQueue`, `uploadsToday/Day`; it does not touch
coins, skins, levels, feathers, puzzle or met elements (Q22).

---

## 6. Versus (§3.13)

### 6.1 Firestore schema (project `flappy-spikes-a2b55`, location eur3)

```
players/{uid}
  name: string (≤ 32)            avatar: '' (WP-AV legacy key)     platform: 'android' | 'ios'
  look: { bird, gear, hat, hoop, trail }: string ids
  best: int  level: int (0–10, the stored player level client-side (WP-L); the pool level is recomputed from best server-side)
  bestRun: RunEntry | null       recent: RunEntry[] (≤ 5, newest first)
  uploads: { day: 'YYYY-MM-DD', count: int }
  updatedAt: timestamp (server)  expireAt: timestamp (client now + 60 d, rules accept ±1 d; TTL policy on players)

RunEntry
  runId: string (client uuid)    score: int   best: int   ts: timestamp
  name, avatar, look, platform   (denormalised so a pool entry is self-contained)
  tl: string  (base64 of uint16 LE centisecond deltas, one per timeline entry; ≤ 16 384 chars)
  end: int (cs from the last entry to death, 0–65535)
  fl: string (timeline format v2, PRD-2.2 §13.5: base64 of the version byte 2, then per entry the flag byte
              ride 1 | train 2 | gift 4 | bonus 8 | puzzle 16 (with bonus 8, the puzzle completion) and the entry's value as uint16 LE; ≤ 8 192 chars ≈ 2 047 entries.
              The values sum to `score`. v1 — one flag byte per point — is rejected by the server and skipped by
              the client; the 2.1 pool runs were converted once by `functions/scripts/convert_pools_v2.ts`, removed in audit 17)

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
- `runId` ≤ 64 chars; `name` 1–32; `avatar` ≤ 512 (WP-AV: the app writes '', pools always store ''); `look` five ids `^[a-z0-9_]{1,40}$` (WP-AV, rules + function); `platform` `android | ios`.

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
| `onPlayerRunWrite` | `onDocumentWritten('players/{uid}')` | Detect the new run (new `recent[0].runId` or new `bestRun.runId`). Validate (cheat filter, timeline v2 PRD-2.2 §13.5): `fl` is v2 (else `version`); sum of the entry values == `score`; plausibility per entry (a pass ≤ 2 × (pass entries so far + 5), a bonus ≤ 80, a puzzle completion bonus (flag 16) ≤ 500, a gift ≤ 10; else `count`); every entry without the ride/train/gift/bonus flag ≥ 0.9 s after the previous entry that is not a bonus (a bonus never restarts the interval, P22-FIX1 S7-02); the Dart mirror is `RunTimeline.check()`; `best >= score`; score ≥ 3; display fields re-checked; upload rate ≤ 3 non-best runs per UTC day per uid (+ best always). On accept: in a transaction on `pools/{level}_{random shard}` (+ `versusRate/{uid}`) remove this uid's entries, prepend the entry (+ uid, level, server ts), drop entries > 60 d, trim to 150 / 900 KB. On reject: log + `versusRate/{uid}.last`, no pool write. Also trims `recent` entries > 60 d in the player doc (the follow-up trigger finds nothing new and stops). WP-AV: the pool entry gets `avatar: ''` and `versusName(name, uid)` (`functions/src/nickname.ts`: a generated name is kept, any other becomes a generated name derived from the uid); a delete of the player doc does nothing (no Storage). Level is recomputed from `best` with `functions/src/levels.ts` (thresholds must equal `lib/levels/levels.dart`; `functions/test/levels.test.ts` parses the Dart file and compares). |
| `deleteMyData` | callable (`enforceAppCheck: true`, `consumeAppCheckToken: false`) | Deletes `players/{uid}` and `versusRate/{uid}`, removes the caller's entries from all 44 pool shards, deletes the Auth user (Admin SDK). Idempotent. Returns `{ ok: true, removed }`. Client: `FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('deleteMyData')`. |
| `sweepPools` | `onSchedule('every 24 hours', UTC)` | Trims > 60 d entries in every shard (WP-AV: no picture sweep any more). |

Reference implementations for the 5b client live in `functions/src/` (`matching.ts`: candidates + pool read plan;
`timeline.ts`: codec, `scoreAt`, cheat filter). The Dart matcher test must pass `test/fixtures/versus_matching.json`.
PRD-2.2 §3: `poolReadPlan` became `poolSearchOrder` + `searchPools` in both (the fixture's `search` cases);
§4: `FirebaseVersusBackend` wraps plugin failures in `VersusFailure(reason)` (`lib/versus/diagnostics.dart`).

### 6.4 Client interfaces

```dart
abstract class VersusService {                       // lib/services/versus_service.dart
  Future<void> initialize();                         // anon auth, App Check, profile, first prefetch; never throws
  bool get ready;
  OpponentRun? takeOpponent();                       // sync at START: a prefetched match or null (→ solo, no intro)
  Future<void> prefetch();                           // PRD-2.2 §3 search: own level's shards, then nearest levels; ≤ 44 reads, 6 s, once per Home visit
  void onRunStart();                                 // PRD-2.2 §3 every run start (both modes): the next prefetch searches again
  VersusSearchInfo get lastSearch;                   // PRD-2.2 §4 state / reason / reads / level / opponent uid (debug panel)
  VersusSoloReason get soloReason;                   // PRD-2.2 §4 why a VERSUS START without an opponent is solo now
  Future<void> submitRun(RunSummary s, Look look);   // queue + rules (best always, ≤ 3/day, score ≥ 3), retry online
  Future<bool> deleteMyData();                       // callable + local reset + FirebaseAnalytics.resetAnalyticsData();
                                                     // false = offline / refused, nothing deleted (WP-4c)
  VersusProfile get me;                              // name (the nickname), level
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
repeat within a session. Linking: anonymous user `linkWithCredential`; on `credential-already-in-use` sign in with a
fresh credential (the account that already owns the Play Games id wins; call; PRD-2.3.1 §2, see "PRD-2.3 WP-VS contract changes").

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

**Start-up order (Fix P6 R1, S6-F01 / S6-F02).** `GameServices.ensureFirebase()` owns the ONE shared
`Firebase.initializeApp` future (a failure is retried on the next call). `FirebaseVersusService(startAfter: …)` makes
every start attempt — `main.dart`, Home's prefetch, an early app resume, a flush — first await that future and
`game.loaded` (storage), so App Check / Auth / Firestore never run before Firebase and the nickname is never generated
against unloaded storage. `activateAppCheck` sets its process-wide guard only AFTER `activate` succeeded and shares an
in-flight attempt; a failure (e.g. `[core/no-app]`) rethrows and the next start tries again. On success it logs
`versus: App Check activated (…)`. `GameStorage.ensureVersusNickname` reads the saved value from disk before generating,
so a saved nickname is never overwritten.

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

- `flutter test integration_test/<file>.dart -d <PIXEL8_SERIAL> --dart-define=FS_E2E=true [--dart-define=FS_E2E_SEED=7] [--dart-define=FS_APPCHECK_DEBUG_TOKEN=…]`
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
| notifications: fake clock, windows, quiet hours + TZ/DST, skip-after-play, 7 d horizon (≤ 14 slots, skipped slots are not refilled), current zone each reschedule, failed schedule consumes nothing, rotation no repeat in 10 d, fill-in + fallback | `test/services/s3_34_reminders_test.dart` | 4b |
| persistence: every key round-trips with its default | `test/run/persistence_test.dart` | 0b; 4c audits + adds `levelRewardPayout` (recovery, not a §7 key) and the versus reset |

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

**Note (WP-3e, 2026-10-08):** `TextPop` was moved from `hoops/kinds/spring.dart` (WP-3c) to
`effects/text_pop.dart` so the collectables reuse it; `spring.dart` now `export`s it, so the spring and
`s3_23_spring_test` are unchanged. WP-3e also moved `run_spawner.dart`'s private `_spawnItem` behind a public
`spawnItem(GapItemPlan)` (its own region) and added `PickupCleared` / `StarTrailFinished` / `PiggyState.voided` (removed in Fix P3 R1, S6-41) in
its regions — all append-only, nothing reordered.

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
| **4c** persistence table + Delete my data | settings row + confirm dialog, `VersusService.deleteMyData` call site, data-safety notes in `SUBMISSION.md` | settings_panel.dart, `components/delete_data_popup.dart`, storage.dart (reset helper), versus_service.dart (signature) | 0b; real delete needs 5b |
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

## 12. WP-1b contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| `lib/run/config/layout_config.dart` | `LayoutConfig` owns the §3.0.2 rows (`bands`, `bandFor`), the moving-type weights (`movingTypes20/45`, `allMotionTypesFrom` 45), the slide / swing tables (`rail`, `swing`), the |Δy| quantile cut-offs and the zig-zag flip chance, `orbitTiltDeg` 22, and the §5.12 guide knobs. `DirectorTables.prd2` points at these consts (the mirror test still checks them against `spawn_tables.json`) | one source for the ramp |
| `HoopMotion` (`hoops/motion/hoop_motion.dart`) | `abstract class HoopMotion implements HoopMotionDriver` — `HoopMotion.fromSpec(MotionSpec)` → `RailMotion` (rail / horizontal / diagonal), `SwingMotion`, `OrbitMotion`, `RockMotion`; `poseAt(t)` sets `offset`, `angleOffset` (rad), `velocity` (pt/s), `angularVelocity` (°/s); `update(hoop, runClock)` poses the hoop: `position = basePosition + offset`, `angle = tilt + angleOffset`, front half synced; `offsetAt(t)` look-ahead without side effects; `extent` | the pose is a pure function of `runClock` (pause / revive / tumble hold it, Hourglass slows it, rides keep it); WP-1a's `Hoop.frame()` can read `hoop.position/angle` and `motion.velocity` |
| Motion wiring | `MovingRingsFeature` (`hoops/motion/moving_rings_feature.dart`, registered in `features.dart` region WP-1b): on `HoopSpawned` with `plan.motion` it sets `hoop.motion` and adds a `MotionGuide` (priority −1 in `layers.back`, at the home position, under the ring); every frame it poses each moving hoop at `runClock`; a guide leaves with its hoop. No edits to `hoop.dart` / `run_spawner.dart` | stays out of WP-1a's files |
| Tilt | the `Hoop` is already built rotated by `SlotPlan.tiltDeg` (WP-0b); WP-1b only registers `angledRing` / `movingRing` in `_hoopElements` | — |
| Guides | `MotionGuidePainter.paint(canvas, spec, opening:, color:, ring:, opacity:)` — rail/diagonal/horizontal: line + 16 pt caps + 13 × 12 arrowheads 4 pt past the ends; swing: solid rope pivot → ring + dashed arc; orbit: dashed ellipse + clockwise arrows; rock: curved arrow (radius = ring half height + 20, ±28°) + dotted centre line. Colour = `game.foregroundColor` | §5.12 |
| Sampler (calls) | a slide's travel cap uses the band-rule room (`limits(useTable: false)`), not the row's centre range; with < `railMinHalfTravel` (10 pt) left it becomes a rock; `RunConfig.orbitOmega` 1.4 → 1.25 (≤ 39 pt/s on 31 pt) | §3.11 fairness / speed |
| Autopilot | region WP-1b in `debug/autopilot.dart`: for a `HoopMotion` hoop it aims at the ring's y at the predicted crossing time (distance / forward speed) | §3.11 |
| Heart placement | `pickups/placeholder_heart.dart` (`PlaceholderHeartKind`, registered in `pickups/registry.dart` region WP-1b): the director's heart `GapItemPlan` becomes a pickup at the planned spot (hit radius 16), no effect on collect. **WP-2a deletes the file and the WP-1b region line** when it registers the real heart | §3.3 placement without the heart component |
---

## 13. WP-1a contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Physics files | `lib/run/physics/{hoop_frame,rim_collision,pass_test,spike_walls,death_tumble,bird_motion}.dart`, all pure Dart (Vector2 only). `BirdCircle(c, r)`; `collideRims(f, b, vel)` → `RimResult { position, velocity, contacts }` (ends processed in order, prototype `hoopStep`); `rimSpinVelocity(vy)`; `testPlane(f, prev, now, prevFrame:)` / `isFullyPast(f, b)` (PRD-2.2 §30: `RunController` keeps each hoop's previous-step `HoopFrame`; the autopilot rollout does the same); `SpikeWalls(geo)` reads the squeeze inset through `RunGeometry` (`touches` → `SpikeSide?`, `saveBounce`); `DeathTumble(position, velocity, normal, camX, camSpeed, top, floor)` owns the camera ease (`camX`, `camSpeed`), `onLand` callback (dust); `BirdMotion` is static (`cruise`, `recover`, `step(state, dt)`) | the world is the camera; one integrator for bird + world on death |
| Knobs | `lib/run/config/physics_config.dart` (`PhysicsConfig`: rim spin/sparks, spike contact inset 0, save bounce, every §3.0.5 tumble number, results delay 1.5 / themed 2.2) and `lib/run/config/miss_flash_config.dart` (`MissFlashConfig`); `config.dart` only got the core value changes (bird x 70, max fall 650, spike height 44, menu inset 0, tooth depth 18; pipe / scroll / death constants removed) | ARCH §4 |
| `Hoop` (region WP-1a) | `look` (`HoopLook`: colours / stroke / dash / glow / opacity / `missed` — master #3 parameters that kinds' painters read and the miss flash / tier look write), `paintBack` (back half in hoop-local coords), `tiltRad`, `frame()` (base + motion offset / angle / velocity, the kind's rim radius), `syncMotion(t)` (calls `HoopMotionDriver.update`, moves both halves) | WP-1b's motion only implements the driver; the controller syncs every hoop each physics step |
| `RunController` (region WP-1a) | physics step after the spawner: per hoop → `syncMotion(runClock)`, rims (`RimMode`; none while invulnerable), plane (`kind.onPlane` → closed switch), fully past (rides: pass); then spikes. `mistake()` now **returns `MistakeOutcome`** (god mode → ignored). A death builds the `DeathTumble`, calls `game.beginDying()` (state `dying`, `gameover` sfx, bird dead pose, kinematic, `RunLayer.deadBird`) and hands over to `game.endRun(endRun())` after 1.5 s or once resting; the tumble keeps running (and the bird lying) after that. `particles` (`ParticlePool` in `layers.fx`) is the run's shared pool. `debugPass({perfect})` is the test seam for a hoop-less pass (replaces `onScoreSensor(PipePair)`). `legacyPipes` / `legacyPoint` removed | §3.0.5 |
| Generic pass / miss | controller: pass → `hoopsPassed`, `passes`, `perfectPasses` (perfect = no rim touch, rides always), `taken[element]`, `HoopPassed`, `kind.onPass`; miss → `HoopMissed`, `kind.onMiss`, `MissFlash.play`, `missShock`, `mistake(missedHoop | pairMissed)` | ARCH §2.5 |
| Scoring | `items/scoring.dart` `ScoringFeature` (features region WP-1a): on `HoopPassed` → `addScore(perfect ? max(2, streak) : 1)` (PRD-2.2 §13; `RunContext.earn` adds coin bonuses as points with `PointFlags.bonus`, `addScore` doubles with the chick), `earn(1, hoop)` / `earn(2, perfect)`, `CoinPopup` at the ring centre, non-perfect: `point` + `ShockRing.passPulse`, then `game.applyRunStage(state.stage)` | §3.1 / §3.2 |
| Game (region WP-1a) | `runBird`, `stageKey`, `applyRunStage(index)` (`paletteKeyForStageIndex`, `stageForHoops` in `palettes.dart`), `beginDying()`; `endRun` accepts `dying`, no longer fades the bird, no `CoinSource.play` credit; `onScoreSensor`, `pipeRandom`, the pipe spawner and `legacyPipeTargetY` are gone; `onBirdHit(cause)` stays as the test / debug seam (now: tumble first) | §3.0.5, §3.2 |
| Bird | no Forge2D collisions (mask 0); `setFlight(y, vy)`, `startRimSpin(ω)` (one turn), `placeTumble(screen, angle)`, `die()` (kinematic + dead pose, priority `RunLayer.deadBird`); x velocity pinned to 0 | plain-math contacts |
| Spike strips | `SpikeStrip.defaultArt = SpikeArt.teeth`; the teeth (and the legacy tiles) follow `-run.state.camX` (stop with the world on a death, jolt with a knock-back) | §3.0.9 #1 |
| Miss flash | `MissFlash.play(hoop, fx:, glowParent:, glowPriority:, screen:)` — the edge glow goes into the **world under the strips** (`RunLayer.items`), as the mock paints it, not the viewport | §5.13 mock order |
| Calls | spike contact = the bird circle reaching the tooth tips (prototype used tips + 8); no rim bounce while invulnerable (prototype); perfect passes are silent until WP-2b's perfect sounds (ARCH: `point.mp3` on non-perfect only); the rim "tonk" plays `Sfx.rimTonk` looked up by name (WP-3h adds it) | |
| Tests | `killRun(game[, cause])` helper (onBirdHit + step through the tumble) replaces the 1.0 instant game over in the menu / e2e tests | |

## 13b. WP-P1int contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| `RunSpawner.nextHoopAhead()` | the first unresolved hoop the bird is not fully past (`birdX − r ≤ frame().rightmostX`, the §3.0.4 5 miss line), instead of `planeX > birdX − 4` | a tilted ring's plane centre is behind the bird while it still crosses the upper / lower half: the bot (and `RunSummary.hoopKind`) jumped to the next hoop mid-crossing and flew into the rim |
| `Autopilot` | plain rings: a planner rolls the real physics (`BirdMotion.recover`, `collideRims`, `testPlane`, `isFullyPast`, spike lines, moving poses via `HoopMotion.poseAt`) for a family of controllers (bang-bang to ring centre + aim offset; from τ s before the plane glide or flap once) and follows the cheapest passing one (rim clearance < 4 pt counts as a touch); re-checked every 4 frames. Switch pre-targets / closed switches / no pass found → the prototype `botStep` rule | the prototype's bang-bang bot also fails most forced 35°+ / moving rings (node harness: 6/20 at 35°, 5/20 at moving 45); a θ-tilted ring leaves only `reach·cosθ − (r + rimR)` of a level path |
| `SoundService` | lazy pools: `prewarmed` (flap, point, gameover, click, rimTonk, perfect1–3) warm at start; every other `Sfx` creates its low-latency `AudioPool` on first `play`, which is played once ready if that took ≤ `firstPlayLateLimit` (250 ms), else dropped; one creation per sound (`poolRequested` test seam) | 168 pools at start-up (WP-3h warning) |
## 14. WP-2a contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `pickups/{heart,shield}_pickup.dart` (`HeartPickupKind` / `ShieldPickupKind`, registered in `pickups/registry.dart` region WP-2a; `placeholder_heart.dart` and the WP-1b registry line deleted); `items/{extra_life,shield,big_hoops,invulnerability}.dart` (features region WP-2a); `config/lives_config.dart` (`LivesConfig`). **No `big_hoops_config.dart`**: the four §3.6 knobs already live in `RunConfig` (`bigHoopsMult/Min/Max/Ease`, used by the director and `BigHoopsState`) | one source per knob |
| Pickups vs features | a pickup only draws itself and plays its touch fx (`PickupTouchFx.heart` / `.shield`) on collect; what it *does* is the feature reacting to `PickupCollected` (so a pair gift or a test can emit the same event) | features read events |
| Saves | `ShieldFeature` (order 10) and `ExtraLifeFeature` (order 20) implement `MistakeInterceptor` and add themselves to `RunController.pipeline` on attach. A save sets `state.invulnerable = 2` (the controller counts it down while scrolling), plays `puShieldHit` / `puHeartUse`, sends `shield_used` / `extra_life_used` (`cause`), and pops the visual | §3.3, §3.7, Q27 |
| Invulnerability look | `InvulnerabilityFeature` owns the one `InvulnFlash`: whenever `state.invulnerable` *rises* it starts the 2 s blink on `Bird.setSpriteOpacity`. **Anyone granting invulnerability (WP-2d phoenix) only sets `state.invulnerable`** — the flash follows | one flash, no per-feature copies |
| SAVED! | on `MistakeSaved`, `InvulnerabilityFeature` shows `ElementBanner('SAVED!')` in the run's `BannerHost` (`RunHud.of(run).banners`, in the banner layer since PRD-2.2 §12; none before the run's `RunHud`). Until then nothing shows | master #7, banners never stack |
| Heart HUD | the heart indicator is WP-2d's (`hud/heart_indicator.dart`; no grey panel since PRD-2.3.1 §9); it reads `state.hearts` (0..2) and `state.extraLife`. A collected heart flies (shared `FetchFlight`, `FetchSpec.heart`) to `LivesConfig.indicatorCentre` (33, 71), drawn in the world at `RunLayer.fx + 1` | §5.2 / §5.7 |
| Badge / circle | `HeartBadge` (in `ExtraLifeFeature`) and `ShieldCircle` (in `ShieldFeature`) are world components at `RunLayer.bird + 1` (over the bird, under the hoop fronts) following `game.runBird`. Both **observe the state** (`extraLife` / `shield`): any source (pair SHIELD gift of WP-3d, home slot, tests) shows them; a cleared flag hides them. PRD-2.3.1 §13: `ShieldCircle` draws with the bird art's current opacity and scale (`Bird.drawnOpacity` / `drawnScale`, the one visibility source: a ride's `placeRide(hidden:)`, the fades, the invulnerability flash), so it vanishes while a ride hides the bird | sources stay decoupled |
| Bird attachments (audit HIDE, 2026-10-17) | **One rule:** everything worn on or following the run bird is drawn only while the bird art is (`Bird.presented` = drawn opacity > 0, read via `FlappySpikesGame.runBirdPresented`). Every attachment mixes in `BirdAttachment` (`lib/run/effects/bird_attachment.dart`): wholly worn ones (`HeartBadge`, `ShieldCircle`) skip their render tree while the bird is hidden; ones with free parts (`EggView` — departing chick; `FireMaster` — shed flames; the streak trail; `HourglassTrail` — ghosts) set `hidesWholly = false` and gate their worn parts and any emission at the bird with `birdPresented` (also Mini Bird bubbles, Hourglass ghosts). Covers every source of a hidden bird (cannon / volcano / space exit + projectile, Black Hole swallow, phoenix no-body start). Only visibility follows; state and timers run on. Hats / gear / gold glow are inside `LookComponent` and hide with it. Tests: `test/audit/hide_attachments_test.dart` | new attachments mix in `BirdAttachment` |
| Shared parts added | `effects/life_icons.dart` (`LifeIcons.paintHeart` — the mock `HEARTP` — and `paintShield`: the one heart and shield drawing for pickups, badge, shards, flying heart and the WP-2d indicator); `effects/save_burst.dart` (`SaveBurst.emit`: white flash + 12 hearts / triangles); `ParticlePool` gained `ParticleShape.heart` | §3.0.9: no second heart / burst drawing |
| Big Hoops | `BigHoopsFeature.attach` (before the first slot is planned) sets `state.bigHoops = BigHoopsState(D = director.rollBigHoopsDuration(), start: runClock)` when `setup.starter == Powerup.bigHoops`; the director already scales and caps every opening by `bigHoopsMult` at spawn. On `HoopSpawned` a **normal** hoop spawned with mult > 1 gets `look.colors = RingColors.gold` (also during the ease — "after D … normal size and colour"); `BigHoopsFeature.isGold(hoop)` tells WP-2b's tier look to fall back to gold. The state is cleared once D is over | §3.6 |
| Home slot | `_runFromHome` → `RunSetup.starter`: shield → `state.shield` in `RunController.start` (0b), Big Hoops → `BigHoopsFeature`. Analytics `big_hoops_used` / `shield_armed` stay in the game | §3.6 / §3.7 |
| Rumble | no new events: pickups already raise `PickupCollected` (knock, WP-2c); saves raise `MistakeSaved` (no rumble by §3.33) | §3.33 |
## 15. WP-2b contract notes (as built, 2026-10-08; WP-2c folded in)

| Area | As built | Why |
|---|---|---|
| `items/streak.dart` | `StreakFeature` (features region WP-2b): `HoopPassed` perfect → `streak + 1` (FEVER kind: `max(5, streak + 1)`, cause `fever`); non-perfect → 0 (`graze`, no text since PRD-2.3.1 §8; PRD-2.2 §11 a clean off-centre pass: `clean`); `MistakeSaved` → 0 (`save`); `RunDied` → 0 (`death`). Emits `StreakChanged` on every change and `TierChanged` when `RunState.tier` changes; keeps `bestStreak`. Per perfect pass: `BannerHost.showStreak(streak)` (PRD-2.2 §29 names / colours), `perfect_1/2/3` (min(streak, 3)), `PerfectBurst` at the bird in **screen space** (world coordinates, own `ParticlePool` at `RunLayer.fx`, like the §5.3 mock's `pop`), `perfect_pass {tier}`. `streak_broken {length, cause}` when a running streak breaks. The "+2 coin" popup and coins stay in `ScoringFeature` (WP-1a), as does `point` + the pulse on a graze | single owner per effect |
| Ring field | on `HoopSpawned` every hoop whose kind `usesTierLook` gets one `RingTierFx` per ring; the streak **wraps** the hoop's `paintBack` (glow, behind the ring) and `front.paintFront` (sparkles / flames, over it) closures, so kinds must set those in `buildVisual` (before `HoopSpawned`) and not replace them later. `Hoop.look.colors` gets `RingPainter.colorsForTier(tier)` — **only while it still holds the value the streak wrote last** (another owner such as Big Hoops gold or the miss flash keeps its colours; Big Hoops should write its gold every frame or on spawn). `look.missed` hoops drop out (fx cleared, no tint) | §3.5 / §5.13 |
| Bird / trail | `LookComponent.goldTier = tier >= 2` every frame (reset on detach and on death). `TierTrail` (equipped trail; blocks item → `BlockTrail`) in a screen-space component at `RunLayer.bird − 1`, active at tier 3+ **or while `RunState.ride != null`** (comet / portal, §3.0.9 #10). Heading: 0 in normal flight (call: matches the §5.3 mock — the camera follows the bird forward, flaps do not tilt the trail); during a ride the bird's motion relative to the world (screen Δ + camera Δ) | §3.0.9 #10 |
| Banners | one `BannerHost` per run, inside the run's `RunBannerLayer` (world, `RunLayer.banners` −60; PRD-2.2 §12): shared by streak, FEVER (3c), element and switch banners; a new banner replaces the one showing. `clear()` (death, run end) keeps a banner with `survivesDeath` (the switch crash word) | master #7 host |
| Graze notice | **Removed by PRD-2.3.1 §8 (a DEVIATION from §5.3):** no text on a graze that breaks a streak. Was §5.3 "GRAZE · streak lost" (stage foreground, 22 pt Opificio, 0.1 em, centred at x 160, top 250, rises 26 pt and fades in 1.1 s) on a graze that breaks a running streak (call: the mock's demo text is shown in the game) | R-5.3-4 |
| `items/rumble_router.dart` | `RumbleRouter` (features region WP-2b): perfect pass → shake; non-perfect pass → knock; `PickupCollected` → knock; nothing else. Only while `RunController.isScrolling`. Requests are **coalesced per frame** and flushed in `update` (and on death): a shake wins over any knock in that frame; `Rumble` keeps the 90 ms knock throttle and "shake never skipped" across frames | §3.33 "same window → only the shake" |
| Analytics | `GameServices.logRumbleToggle` sends `rumble_toggle {on}` **and** `setting_changed {setting: rumble, value: 0/1}` (call) | R-6-57 |
| Gold glow perf | `LookPainter` bounds the gold-glow `saveLayer` to `goldGlowBounds` (art box + blur reach). Measured (CPU raster, 960 × 2133): unbounded ≈ 15 ms/frame vs bounded ≈ 2 ms (incl. ≈ 2 ms readback); same pixels | WP-0c perf warning |
| Config | `lib/run/config/streak_config.dart` (`StreakConfig`) | ARCH §4 |

## 16. WP-2d contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `hud/{run_hud,heart_indicator,versus_bar,name_chip,pause_button}.dart`; `screens/{pause_screen,revive_screen,revive_ladder,revive_rules,phoenix_rise,shop_overlay}.dart`; `config/{hud_config,revive_config}.dart` (`HudConfig`, `ReviveConfig`) | ARCH §9.2 2d row (+ `revive_rules.dart`, `hud_config.dart`) |
| `RunHud` | `RunHud.ensureFor(run)` creates the run's HUD in `camera.viewport` and its `RunBannerLayer` in the world (any feature may call it at attach; the game calls it after `run.start()`); `RunHud.of(run)`; `game.runHud`. Children: `heart`, `versus` (only with `setup.opponent`), `pauseButton`; PRD-2.3 §10.3 the waiting run's `FirstRunHint` (`run/hud/first_run_hint.dart`, priority −1, below the pause button; mode `firstRun` = veil (`FirstRunVeil`, world priority −80) + AVOID THE SPIKES bands (held `RunBanner`s) + flap path + TAP TO FLAP! + hand, or `reminder` = hand + banner only after `Config.tapReminderDelay` of `run.waitClock`; `game.firstRunHint`; `dismiss()` on the first tap; the hand and the banner are its static `paintHand` / `paintTapBanner` masters). `bannerLayer` (PRD-2.2 §12) holds `banners` (the one `BannerHost`, priority `StreakConfig.bannerPriority`); `RunHud.banners` returns it. `rowOpacity` fades the row in while playing / paused, out on a death; a death also clears the banners (not the ones that survive a death) and HUD texts. Hidden entirely (`hidden`) while a menu overlay sits over the run; the banner layer is hidden with it. Removes itself, and its banner layer, when `game.run` changes | ARCH §0 viewport, real time |
| Banners | `StreakFeature` takes `RunHud.ensureFor(c.run).banners` (no world host any more); no graze notice any more (PRD-2.3.1 §8). `InvulnerabilityFeature`'s viewport lookup now finds the HUD host, so SAVED! shows | §5.2 / §5.3 |
| Extra-life badge | stays in the world (over the bird) and divides its dt by `RunState.timeScale` | §5.5, ignores the Hourglass |
| Pause | `game.pause()` / `game.resume()` (region WP-2d); state `paused`; `RunScaledWorld.frozenSource` → the whole world gets dt 0, except `RunScaledWorld.realTime` children (an in-run menu overlay); `PauseScreen` in the viewport; back stack: Esc on the card resumes (or closes the settings first). Esc while playing and `AppLifecycleState.paused/hidden/inactive` call `pause()` | §5.7, ARCH §2.3 |
| In-run menu overlay | `RunMenuBackdrop` (world priority 18, stage background) + the menus' own `SettingsPanel` / `ShopScreen` and chrome on top; strips raised over the sheet. `game.openRunSettings()` / `closeRunSettings()` (from the pause card), `game.openReviveShop(onClose:)` (GET COINS; `sound.duckMusic(0.5)`, back → `closeShop()` → `onClose`). `_sceneOnTop`, `buyProduct`, `buyNoAds`, `restorePurchases` accept the overlay; the featured skin row does nothing over a run | §3.14 "Shop as an overlay on the paused game" (a Flame overlay, not a Flutter route) |
| Revive hand-off | `RunController._stepDeath` calls `game.runDeathSettled(run)` instead of `endRun`: ≥ `ReviveConfig.minHoops` hoops and `PostRunScreens.revive` set (`ReviveFlow`, registered in `onLoad`) → state `reviving`, `ReviveFlow.show` → declined → `endRun(run.endRun())`; else `endRun` at once. `PostRunFlow.run` no longer offers the revive (bonus → results only). `endRun` accepts `reviving` | persistence / versus upload once per game |
| Ladder | `ReviveLadder.offer(state, adReady:)` / `record` / `coinPrice` / `eligible`; `RunState.coinRevives` (region WP-2d) + the existing `adStepAvailableThisGame` (false once used or skipped) | §3.14 |
| Revive screen | `ReviveScreen` (viewport, priority 20): phases offer / ad / paying / shop / phoenix / closing / done; `tapHeart`, `tapGetCoins`, `tapNoThanks` (test seams = the tap targets); the dim overlay is `ReviveDim` in the **world** (priority `RunLayer.fx + 2`) so the phoenix (`+1`, bird `+2`) rises above it as in the mock. Coins: `wallet.spend(price, 'revive')` + the `CoinFly` master | §5.9 |
| Phoenix | `PhoenixRise` (world): drives the kinematic bird (`Bird.placeTumble`, `phoenixAlive`, `phoenixFlap`); `reviveSafeLine(run)`; `RunController.beginRevive(kind, price)` (tumble off, `revive()`, `RevivePhoenixStarted`) and `finishRevive(...)` (via `game.finishRevive`: state `playing`, `Bird.reviveFlight(y)` + flap, runClock on, `invulnerable = 2`, `Revived`). Black Hole (`ThemedDeath.noBody`): a shock ring at the last position, the bird fades in while rising | §3.14 / §5.9 |
| Death rules | `ReviveRulesFeature` (features region WP-2d, last): `onDeath` clears egg / piggy / jar, ends `timed` (`PowerupEnded`), time scale / bird scale 1, fire out; `onRevive` resets a running squeeze (phase idle, inset → 0 over 0.5 s, `nextAt = rollSqueezeAt(runClock)`). 3e / 3f / 3g keep their own visuals in their `onDeath` / `onRevive` | §3.14 |
| Big Hoops gold | `StreakFeature._applyHoop` keeps `RingColors.gold` on `BigHoopsFeature.isGold` hoops at every tier; `BigHoopsFeature.update` re-applies it every frame (only the miss flash wins) | WP-2b warning (shared gold) |
| Analytics | `revive_offered {offer, price, revive_index}`, `revive_ad_started`, `revive_ad_completed`, `revive_coins {price, revive_index}`, `revive_locked_tap {price}`, `revive_get_coins {price}`, `revive_declined`, `revive_timeout`; `shop_open {source: revive}`; ads keep `ad_rewarded_shown {placement: revive}` | §6 |
## 17. WP-2e contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `lib/run/screens/results_screen.dart` (`ResultsPage` factory, `ResultsScreen` component, pure `ResultsModel` / `LevelBar` / `rankText`, `claimLevelRewards`), `lib/run/config/results_config.dart` (`ResultsConfig`), `lib/run/effects/fireworks.dart` (`Fireworks`, new shared part). `gameover_panel.dart`, `LegacyGameOverResults` and `game.showLegacyGameOver` deleted; `PostRunScreens.results` defaults to `ResultsPage` | §5.10 |
| State | `GameState.gameOver` → `results` (lib + tests + integration_test) | ARCH §2.3 |
| Game (region WP-2e) | `showResults(RunSummary)` (adds the page to the **world** at priority 20 and lifts both strips to 21; the menus also live in the world), `resultsScreen` getter, `_removeResults()` in `replay()`; `endRun` stores `unclaimedLevelReward` when the run reached a new level; `onLoad` credits it (`claimLevelRewards(this, 'app_start')`) right after the menu state is built. A run-less `endRun` builds a bare `RunSummary` | the page needs the strips over it |
| YOUR REWARD | `RunSummary.coins` (= `RunState.coinsThisRun`): every `ctx.earn` in the run — hoop / perfect / elements / **puzzle** / **winBonus** (WP-5b must credit the win / draw bonus through `ctx.earn(…, CoinSource.winBonus)` before `RunController.endRun` builds the summary). The balloon bonus (WP-4a) pays with `wallet.add` after the run and is therefore not in it | §3.14 Q36 |
| Level reward | `claimLevelRewards(game, how)` = `menu.levels.claim()` (marks claimed first, then `wallet.add(level_reward)`) + `unclaimedLevelReward = 0` + `level_up {from, to, reward, claim: tap / auto_next / app_start}`. The page shows CLAIM when the run's level after > level before and a reward is owed; NEXT while CLAIM shows plays the claim animation (≈ 1.4 s) + 0.25 s, then `goHome()`; NEXT before CLAIM is up pays at once and goes home. The home `LevelUpPopup` stays for the catch-up / debug case only (pending rewards without a results-page level up) | §3.14 |
| Versus parts | region WP-5b in `ResultsScreen.onLoad` (card build): header WIN / LOSE / DRAW at `ResultsConfig.header`, the opponent `ResultsPlayerColumn(mine: false, lower:, winner:)` at `opponentColumnX` and yours moved to `youColumnX`, VS between. Solo = your column alone at x 160 | brief |
| Layout | the 320 × 711 mock in `content` coordinates, scaled by `ResultsConfig.scaleFor(h)` (1 from 711, ≈ 0.8 at 568) about the top centre; the fx layer (`ResultsFx`: confetti, fireworks, `CoinFly` claim coins, white flash) is a world sibling at priority 30 with the same transform | §5.10 at 568 |
| Kept buttons (call) | leaderboard (trophy) and share (invite glyph) as 40 pt pink boxes flanking the reward pill; gated on the 0.3 s fade-in also when pressed directly | PRD-1 §3.7 "kept" |

## 18. WP-3b contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `hoops/kinds/portal.dart` (`PortalHoopKind`, `RideRingKind`; both registered in `kinds/registry.dart` region WP-3b), `rides/{portal_ride,ride_theme,ride_path,speed_lines}.dart`, `rides/themes/{cannon,space,volcano,sea,pinball,storm,themes}.dart`, `config/portal_config.dart` (`PortalConfig`) | ARCH §9.2 3b row |
| Feature | `PortalRideFeature` (features region WP-3b, before 2d's revive rules): on a portal's `HoopSpawned` it builds the chain (theme from `SlotPlan.extra`, path, stations) and shows ring #1 ahead (a `rideRing` hoop owned by the feature, not the spawner); on the portal's `HoopPassed` it plays `pu_portal` and starts one `PortalRide` (same frame, after the physics loop) | §3.12 chain |
| `PortalRide` | implements `Ride`; phases `RidePhase.ride → exit → fly → glide → done` (`RideState.phase` = the name). Camera: path coordinates from the portal centre; `camX/camY` = portal + ride camera (screen anchor eases 66 / 40 pt over 1.6 s), the run's `forwardSpeed` mirrors the camera speed (trail drift). Rings are real `Hoop`s (`HoopKindId.rideRing`) in the track layers, added (+ `HoopSpawned` → tier look) when ≤ 1 500 pt ahead, passed by arc length through `RunController.ridePass` (`HoopPassed(duringRide: true, perfect: true)`), removed at the exit. Exit / flight scenes are screen space; the flight offset makes them fall away. At the glide start `camY = 0`, the old course is cleared (`spawner.clearAll`), `director.resumeAt(birdX + cruise × (2.5 + 1))` and the spawner is released (glide-time slots follow the ride rule: normal, upright, at their index's curve size, PRD-2.4 §2); the ring size is `PortalRide.rideRingOpening` (curve of the portal's index × Big Hoops, fixed when the portal spawns, PRD-2.4 §2.3); `director.onRideEnd` / `RideEnded` / control back after the settle | §3.12 / §5.12b |
| `RideTheme` | `buildPath`, `ringStations` (cannon `everyStep` 190 + 950k (PRD-2.3.1 §7, was 380k), themed `equalStations` 190 … L − 260), `washTint`, `sounds` (`RideCue → Sfx`), `exitDuration`, `launchPoint`, `paintWorld` (path camera), `paintWorldFront` (cannon over the bird), `paintExit` / `paintExitFront` (scene at −off), `exitPose`, `onLaunch`, `projectileActive` / `paintProjectile` (space rocket), `tick`, `paintExtra`; flags `exitFill`, `spin`, `depth`, `umbrella`. `RideView` carries the clocks, cameras, the theme's particle pools (`ParticlePool` screen + scene) and `RideBlob`s (bubbles, lava, bombs, "+500": shapes the pool cannot draw) | §7 pluggable theme |
| Layers | four screen-space `_RideLayer`s in the world: world `scoreCircle − 50` (under the score circle and the hoops), under the bird 9 (umbrella), front `rideCannon` 11 (cannon, rocket), fx `fx + 1` (themed speed lines, ride particles, flash). The bird is raised to `hoopFront` 12 in the flight | §5.12b z-order |
| Shared-file regions | `run_controller.dart`: `rideHold` (skips `BirdMotion.step` + `_stepPhysics`), `ridePass`, `endRideHold`; `run_spawner.dart`: `hold`, `clearAll`; `director/run_director.dart`: `resumeAt`; `run_state.dart`: `RideState.birdHidden`; `items/streak.dart`: no trail while `birdHidden`; `items/scoring.dart`: `PointFlags.ride` on ride points, portal-ride popups at the bird in screen space (the ride camera races along the path); `components/bird.dart`: `beginRide` / `placeRide` / `endRide`, `flap` ignored in a ride; `components/spike_strip.dart`: `rideShift` (teeth scroll on the way back) | the ride drives bird + camera itself |
| Speed lines | `rides/speed_lines.dart`: `CannonSpeedLines` (vertical 2 × 60 in the ride) and `RideSpeedLines` (along the heading) — both add the horizontal 70 × 2 launch lines in the flight / glide; WP-3a adds `CometSpeedLines` to the same file | master #12 |
| Calls | the bird joins the path from where it crossed the portal plane over 0.5 s; the space rocket sound plays once (ignition), not again at the launch; storm launch has no sound (the mock's synth only); ride screen positions of exit scenes are bottom-anchored (`fromBottom`) except pinball's loop / launch and the storm spit (top-anchored) | mock at 711 only |

## 19. WP-3c contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `hoops/kinds/{bullseye,train,spring,lucky_spin,fever}.dart` (registered in `kinds/registry.dart` region WP-3c), `items/fever.dart` (`FeverFeature`, features region WP-3c — **attached before `StreakFeature`** so it reads the streak before a pass / save changes it), `hud/fever_banner.dart` (`FeverBanner extends RunBanner`), `config/fever_config.dart` (`FeverConfig`), `config/special_hoops_config.dart` (`BullseyeConfig`, `TrainConfig`, `SpringConfig`, `LuckySpinConfig` — one file for the four small kinds) | ARCH §9.2 3c row |
| `HoopKind.extraHoops(SlotPlan)` (region WP-3c in `hoop_kind.dart`) + spawner region | a slot may spawn further hoops right after its own (each a full `Hoop`, its own `HoopSpawned`); the Ring Train's rings 2 / 3 carry `TrainRing(spec, k)` in `SlotPlan.extra` (ring 0 keeps the director's `TrainSpec`); `TrainGroup.forSpec` ties the three | the pass test, rims and miss stay per ring; the slot still counts once |
| Kinds' per-hoop state | cached kinds are stateless; state lives in a child `Component` of the hoop (world time: pause freezes it, the Hourglass slows it) looked up through an `Expando` | kinds are singletons in the registry |
| Spring flap lock | `RunState.flapLock` counts down in `BirdMotion.step` (region WP-3c); `RunController.flapLocked`; the game drops taps while it runs (`onScreenTap` / `onPlayfieldTap`, regions WP-3c in `flappy_game.dart`) | §3.23 |
| Director (call) | the spring's room check and the forced next centre use the band rule (`limits(useTable: false)`), not the row's centre range (< 240 pt on 568 pt screens until hoop 50) | §3.23 "with room inside the band" |
| Lucky Spin | the wheel's approach angle is a function of the bird's remaining distance to the plane, phased so the post-pass slow-down (≈ 8 rad/s², ≈ 0.9 s) ends on the pre-rolled slice; coins, banner, burst and `lucky_spin` at the stop (still paid if the hoop is culled first) | §3.25 pre-rolled prize, animated to stop on it |
| FEVER | `FeverFeature` owns `RunState.onFire` / `hoopsBurned`, the crackle loop (stops in pause / on death), the fire (own screen-space `ParticlePool`, priority bird − 2) and smoke, the FEVER! banner; the kind owns the ring's pass effect (3 `ShockRing`s, flame burst in the run pool, `FeverFlash`, `FeverShake` = `RunShake.feverPass` applied as a camera delta). New events (run_events region WP-3c): `FeverIgnite(source)` — the pair FEVER gift (3d) emits it to light the fire (3d still owns the gift's streak part); `FeverFireChanged(lit, cause)` | §3.19 / §5.18; pair gift Q59 |
| Masters extended (§3.0.9) | `BannerHost`: a **FEVER slot** (`showFever`, `fever`; `show()` routes `BannerLane.fever` there) so FEVER! shows with the tier banner; `RunBanner.subtitle` / `ElementBanner(subtitle:)` (second 13 pt line: "+3 coins", "all three rings · +3 coins", "lucky spin · coins"); `ParticleShape.flame` + `Particle.ramp` (colour over the life) + `ParticlePool.rampColor` / `paintFlame`; `ShockRing.grow` (pt added to both radii) + `glowBlur` | no second banner / pool / ring class |
| Scoring | train ring points carry `PointFlags.train` (`scoring.dart` region WP-3c) | §3.13 cheat filter |
| Autopilot | a spring's crossing height does not count toward the next hoop in the planner's cost (region WP-3c) | §3.23 |
## 20. WP-3a contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `items/comet.dart` (`CometFeature`, features region WP-3a), `rides/comet_ride.dart` (`CometRide implements Ride`), `pickups/comet_star.dart` (`CometStarKind` / `CometStar`, pickups registry region WP-3a), `CometSpeedLines` in `rides/speed_lines.dart` (region WP-3a), `config/comet_config.dart` (`CometConfig`) | ARCH §9.2 3a row |
| Start | `CometFeature` reacts to `PickupCollected(ElementId.comet, pickup)`: **a pair's COMET gift (WP-3d) emits `PickupCollected(ElementId.comet, null)`** (source `pair`), the star emits it with itself (source `hoop`). `comet_collected {source}`. A second comet while a ride / timed powerup runs is ignored | same contract as WP-2a pickups (the event, not a call) |
| Speed | `RunState.cruiseMult` (region WP-3a) — `BirdMotion.step` recovers toward `cruise × cruiseMult` (region WP-3a). The ride sets it from `CometRide.cruiseMultAt(t)` (smoothstep 0.45 s up, last 0.9 s down) and resets it to 1 at the end | the camera, spawner and pass tests stay the controller's; no `rideHold` |
| Ride state | `RunState.ride = RideState(comet, phase: boost / landing)` and `RunState.timed = TimedPowerupState(comet, 10)` (the timed-powerup slot; WP-3f's `TimedPowerupSlot` should adopt it), `director.onRideStart/End(comet)`, `PowerupStarted/Ended(comet)`, `RideStarted/Ended(comet)`. **WP-3f: do not send `powerup_started` / `powerup_ended` analytics for `TimedPowerup.comet`** (§6 lists hourglass / mini / frenzy only) | §3.0.3 exclusivity through the existing state |
| Bird | kinematic for the boost (`Bird.beginRide` / `placeRide(… scale 0.9 × pop)` / `endRide(y)`), so taps are ignored; `y += (target − y) · min(1, 16 dt)` capped at 900 pt/s, target = `HoopKind.autopilotTarget(h, s, y).y` of `spawner.nextHoopAhead()` (moving rings: offset at the crossing time), clamped inside the tooth lines; tilt = clamp((target − y) × 0.3°, ±25°) | §5.6 mock |
| What the ride means elsewhere | Already generic: `HoopKind.rimMode` → ignored while `s.ride != null`; the controller skips `onPlane` verdicts (closed switches) and counts "fully past" as a pass in a ride; every ride pass is perfect (`HoopPassed(duringRide: true)`); `MistakePipeline` ignores mistakes in a ride. **Kinds that override `rimMode` (saw, WP-3d) must keep `ignored` while `s.ride != null`; the switch ring (3d) opens visually on `RideStarted(comet)`; the spring (3c) must not launch on `duringRide` passes** (§3.0.3 "Rides and what is already spawned") | one ride flag |
| Visuals | screen-space world components: `_CometBack` (tail + shell, priority `bird − 1`, after the trail), `_CometFront` (countdown ring + "Ns" label, `bird + 1`, the shield circle r ≥ 38 stays around it), `_CometLines` (`CometSpeedLines`, priority `guides`: over the score circle, under the hoops), the pop (`_CometFlash` full-screen 0.7 → 0 at `fx + 1`, `PickupTouchFx` with `CometConfig.pop` + an own screen-space `ParticlePool` at `fx`). The trail is master #10 (`TierTrail` is already on in every ride) — the mock's separate pixel shower is not drawn twice | §3.0.9 #10 / #12 |
| Sound | `pu_comet_get` on start, `SfxLoop.cometLoop` at 0.3 from 1.2 s (silenced while the run is paused), faded over 0.3 s and stopped after the end, `pu_comet_end` at the end | §3.9 |
| Autopilot | region WP-3a in `_cost`: a comet hoop's plan pays for crossing the plane outside the star's reach (18 + r − 6) | the bot collects the star |

## 21. WP-3d contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `hoops/kinds/saw/{saw_kind,live_wire,frost_ring,black_hole,saw_death}.dart`, `hoops/kinds/switch/{switch_kind,lockdown,laser_gate,power_iris,snoozer,gift_wrap}.dart`, `hoops/kinds/pair/{pair_kind,gift_box,gift_tag}.dart`, `hoops/kinds/ring_arcs.dart` (the mocks' canvas helpers: half arcs, glow shells, halos, `Mulberry`, `Lightning`), `config/{saw,switch,pair}_config.dart`, `effects/rising_word.dart`. Registered in `kinds/registry.dart`, `pickups/registry.dart` (`ElementId.switchRing` → `SwitchPickupKind`) and `features.dart` (`SawFeature`, `SwitchRingFeature`), regions WP-3d | ARCH §9.2 3d row |
| Designs | one kind per element with a pluggable design strategy picked from `SlotPlan.extra` (`SawDesignArt.of`, `SwitchDesignArt.of`); per-hoop state is a child component (`SawRingState`, `SwitchRingState`, `PairState`) found through an `Expando`, as WP-3c does | §7 "one `SwitchRing` type with a pluggable design" |
| `HoopKind.themedDeath(Hoop)` (region WP-3d in `hoop_kind.dart`) | the controller puts it on the saw / closed-switch `Mistake` (`themed:`). Saw: `ThemedDeath('saw_live_wire', hold 0.6)`, `('saw_frost_ring', 0.4)`, `('saw_black_hole', 0.8, noBody)`; switch: `('switch_<design>')` with no hold | §3.0.5 |
| Themed death in `RunController` (regions WP-3d) | `_stepDeath`: while `themed.holdSeconds` runs (or forever for `noBody`) only the camera eases (`DeathTumble.stepCamera`, region WP-3d) and the bird is placed at the hit point + `themedPose` (`ThemedDeathPose`: offset / angle written by `SawDeath`); then the normal tumble. Hand-over to the revive offer / results: `min(hold + 1.5, 2.2)` or once resting; Black Hole: `hold + SawConfig.holeAfter` (0.6 s). `beginRevive` clears `themedPose` | §3.0.5 "the design's moment first, then the same tumble"; Black Hole swallows |
| Bird tint | `Bird.deathTint` / `deathTintAmount` (region WP-3d) are the only blend of the look while set (the stage blend is gone, PRD-2.2 §20) (Live Wire X-ray / charred, Frost blue, Laser Gate crash flash); `SawFeature` clears it (and the Black Hole's look scale) on attach / revive / detach | one look, no second bird drawing |
| Master #1 (§3.0.9) | `SpikeTeethPainter.paint(warp:)` (strip space in / out; the band edge and teeth bend, the outer edge stays) and `SpikeStrip.lens` (screen point → screen point) — the PRD's "lensing bend (Black Hole)" parameter. `SawFeature` sets `lens` on every `SpikeStrip` in the world each frame while a Black Hole is within 170 pt of the screen | §5.17 lensing, visual only |
| Black Hole pull | `SawHoopKind.pullAt(frame, bird, birdR, runClock, seed)`: toward the nearest rim end whose centre is within 34 pt of the bird's edge (`d < 34 + r`, the mock), 260 + (570 − 260) × hunger; hunger = the 0.9 s sine bump every 3.4 s on `runClock + seed × 0.07`. `SawRingState` adds it to the live bird's vy (world time); the autopilot rollout adds it too (region WP-3d) | §3.18 |
| Hums | `SawFeature`: one `SfxLoop` per design, volume = closeness² × 0.8 (closeness = 1 − (planeX − birdX) / (320 − 70 + 40)); started / re-volumed (Δ > 0.02) while playing, stopped on a death (`onDeath`), pause and detach | §5.17 |
| Switch pickup | `SwitchPickup` (items layer) linked both ways with its ring (`SwitchRingState.pickup`); a touch: shared `PickupTouchFx.switchTouch`, `CoinPopup` "+1", `earn(1, switchRing)`, touch sound, `switchring_switch_taken`, `SwitchRingState.open()` (ring open in the logic at once). Laser / Iris switches stay 0.3 / 1.1 s then fade 0.35 s ×1.4; the key / scissors fly to the ring (drawn by the ring). Iris cable drawn by the pickup (`paintUnder`) | §3.20 / §5.19 |
| Closed ring | `SwitchRingKind.onPlane` → `PlaneVerdict.mistake` (crash fx + sound in the kind's state); `SwitchRingFeature` shows the red crash word in the run's `BannerHost` (the banner layer, PRD-2.2 §12; `survivesDeath` so the death's clear keeps it) on `RunDied` and sends `switchring_closed_hit` {design, used}. A comet ride (`RideState.kind == comet`) opens a closed ring by itself (no coin) | §5.19 crash; §3.0.3 comet |
| Autopilot | `SwitchRingKind.autopilotTarget` returns the switch as `preTarget` while it is untouched and ahead (the bot's bang-bang path), then the ring (the planner); pairs keep the default nearest ring | §7 |
| Pair gifts | `PairHoopKind.applyGift`: SHIELD sets `RunState.shield` (the circle observes it); COMET emits `PickupCollected(ElementId.comet, null)` (WP-3a's pair contract); +10 COINS `earn(10, pair)` + coin spray; +5 SCORE `addScore(5, flags: PointFlags.gift)`; FEVER emits the new **`StreakAtLeast(5)`** (run_events region WP-3d; `StreakFeature` raises the streak, region WP-3d in `streak.dart`) then `FeverIgnite('pair')`. During a ride the gift is the ring nearest the bird | §3.21 Q59; WP-3c note "3d owns the gift's streak part" |
| Shared part added | `RisingWord` (`effects/rising_word.dart`): outlined Opificio word, solid or gradient fill, pop-in 0.6 → 1.1 → 1, rises and fades — the switch open words and the pair reward words | §3.0.9: no per-element text drawing |
| Calls | the reward word sits next to the bird (x 180, bird y − 34) in screen space; the pair's "perfect" is the hoop's `touched` (a graze on the skipped ring also counts); the frozen / charred bird is the themed-death tint of the look (no second bird drawing); a saw / closed-switch save shows SAVED! (no crash word) | |

## 22. WP-3g contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `items/squeeze.dart` (`SqueezeFeature`, features region WP-3g — **before** WP-2d's `ReviveRulesFeature`, so its `onRevive` sees the running squeeze), `config/squeeze_config.dart` (`SqueezeConfig`: the §3.17 table as `openFor` / `insetFor`, phases, shake, flash, bits, cover ramp, hold volume). The schedule knobs stay in `RunConfig` (0b) | ARCH §9.2 3g row |
| State | the feature is the only writer of `RunState.squeeze` while flying (phase, `index` = the 0-based number of the coming / running squeeze, `nextAt`, `holdS`, `inset`); 2d's revive rules reset it on a revive. `SqueezePhaseChanged(phase, index)` on every phase change | one owner |
| Schedule | `nextAt = director.rollSqueezeAt(runClock)` at attach and after each fully open squeeze; it starts when `runClock ≥ nextAt`, no ride, not in a portal `rideHold`, the run scrolling, and `runClock ≥` (last `RideEnded` / `Revived`) + 2 s | §3.17 waits |
| Window | `RunController.directorContext` (region WP-3g): while `squeezeWindow` the squeezed tooth lines are the coming squeeze's full depth (`SqueezeConfig.insetFor(index)`), not the walls' current inset (0 until the closing) | §3.17 "hoops already on screen when the warning starts were spawned under this rule" |
| Force (§3.0.8) | `DebugForced(squeeze)` / a queued `setup.forced` squeeze → `SqueezeFeature.force()`: `nextAt = runClock + 3 + lead + 0.05` with `lead` = the farthest spawned hoop ahead / cruise, so every hoop already on screen is crossed before the window starts | nothing is caught by a closing wall |
| Master #1 (§3.0.9) | `SpikeStrip.squeezeInset` (follows `run.state.squeeze.inset` in `update`, 0 without a run) → `SpikeTeethPainter.paint(reach: 44 + inset)` (the solid band grows, the teeth ride on it); `SpikeStrip.toothFlash` → `paint(toothColor:)` overdraws only the teeth (also through the WP-3d `warp`) | lens + squeeze + flash compose |
| Master #2 (§3.0.9) | `ScoreHud.setSqueezeCover(cover, textColor)` (circle tint → white, score turns the wall grey past 0.5), `ScoreHud.coverFor(...)` (0 until a tooth line reaches the circle, 1 after 30 pt), `ScoreCoverOverlay` (world priority `strips + 1`) repaints the circle + score clipped to the walls so the circle stays over them | §3.17 "HUD on top of the walls" |
| Shake | one `RunShake` in the feature, applied to `camera.viewfinder` as a delta (like WP-3c's `FeverShake`), so both compose; reverted on death / revive / detach | §5.16 |
| Bits / dust | own `ParticlePool` (120) in `layers.fx`, in track coordinates (the bits leave the scrolling teeth); also during the revive's 0.5 s slide out | §5.16 |
| Sound | `sqWarn`, `sqClose`, `sqLock`, `sqTick` × 3, `sqOpen`; `SfxLoop.sqHold` at 0.6 only while holding and `GameState.playing` (stops in pause, on a death, at the opening) | §5.16 |
| Analytics | `squeeze_started {index (1-based), open_pct, hold_s}`, `squeeze_survived {index}`, `squeeze_death {index, phase}` (a death in any non-idle phase) | §6 |
| Calls | the warning flash pulses `|sin|` every 0.5 s (the mock's `max(0, sin)` is dark every other half second and in the first 0.4 s of closing); a squeeze interrupted by a revive counts (the next is tighter); the score-circle cover uses the master circle (183 pt at centre + 35) — at 711 only the 4th squeeze touches it | |
## 23. QA round P2 fix notes (`Fix P2 R1`, as built 2026-10-08)

Fixes for the five findings in `test/e2e/P2_FINDINGS.md`; each has a live
regression in `test/e2e/p2_gameplay_e2e_test.dart` (S6-20 … S6-24).

| Area | As built | Why |
|---|---|---|
| Phoenix safe line (S6-20) | `reviveSafeLine()` uses `RunSpawner.nextHoopAhead()` — the §3.0.4 5 "fully past" miss-line predicate (`birdX − r ≤ frame().rightmostX`) — replacing the centre-plane test `planeX > birdX − 4` | a tilted ring's plane centre can sit behind the bird while it still crosses the upper / lower half, so the old predicate skipped the ring the spawner calls next and the phoenix rose to the wrong line (ARCH §13b, one predicate) |
| Revive beat (S6-21) | `ReviveConfig.idleBeatScale` (.035) and `beatAmplitude` (.06) are the **peak amplitudes themselves**: idle is `scale · sin²`, urgent is `amplitude · urgency · (1 − cos)/2`. The old code doubled both (peak 1.07 / ≈1.12) | §5.9 peaks are 1.035 idle / 1.06 urgent; the configured knob is the peak, never a half-wave |
| Level reward claim (S6-22) | `LevelProgress.claim()` is recoverable and idempotent: `beginLevelRewardClaim(payout, claimed)` writes the payout record (`levelRewardPayout` = target wallet balance) and the claimed set in one scope, then `wallet.add`, then `endLevelRewardClaim()` (record, then flag). A re-entrant call pays nothing (`_claimInFlight`); a start with a leftover record pays the rest and settles. `claimLevelRewards` no longer writes `unclaimedLevelReward = 0` (that is `endLevelRewardClaim`); `_creditUnclaimedLevelReward` runs for a pending reward **or** a record | a kill between the claim write and the credit must neither lose nor double the coins; the two persisted keys alone cannot tell an interrupted claim from a completed one, so the payout record makes the intent explicit (§3.14 reward guarantee, §5.10, §7) |
| `GameStorage` handle | `load()` caches the resolved `SharedPreferences` in `_prefs`; `begin`/`endLevelRewardClaim` use it (`_prefs ?? getInstance()`) and issue their writes in order (record before mark; record before flag) | the claim must win against a concurrent `load()` whose own `getInstance()` may resolve first and clobber the in-memory caches (results `next()` fires the claim unawaited, then the 1.0 home → replay path runs `load()`); a fast `getInstance()` still lands the memory update before the first await |
| Next button (S6-23) | at 568 … 730 NEXT is laid out in inverse scale: `ResultsConfig.bottomGap` (= 711 − 646 = 65) and `nextTopFor(h)` anchor its top edge; its box and label font are pre-divided by the page scale, so the rendered button is the §5.10 292 × 50 at the reference bottom gap while the column above scales | §3.0.1 bottom buttons keep the same bottom distance on every screen height; PRD outranks the ARCH §17 uniform-scale note |
| Claim coin (S6-24) | the CLAIM icon is the unmodified shared `coin.png` `MenuIcon` (no `recolor`) | §3.0.6 / §3.0.9 #14: every coin keeps the gold disc and thick pale inner ring; the plum recolour was a forbidden variant |

## 24. WP-3f contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `pickups/capsule.dart` (`CapsulePickupKind` / `CapsulePickup`, `CapsuleArt`: capsule + the three icons, shared with the pill), `items/timed_powerup.dart` (`TimedPowerupSlot`, `TimedPowerupEffect` base, `TimedPowerupInfo` extension), `items/{hourglass,mini_bird,coin_frenzy}.dart`, `hud/timer_pill.dart` (`TimerPill`, a `RunHud` child), `config/capsule_config.dart` (`CapsuleConfig`). Registered in `pickups/registry.dart` (`ElementId.capsule` → `CapsulePickupKind`; `hourglass` / `miniBird` / `coinFrenzy` in `_pickupElements`) and `features.dart` (region WP-3f, after WP-3g and before WP-2d's revive rules) | ARCH §9.2 3f row |
| Slot | `TimedPowerupSlot` starts a powerup on `PickupCollected(capsule)` (type = `GapItemPlan.extra`), only when `RunState.timed == null` and no ride: `RunState.timed = TimedPowerupState(type, d)` (Hourglass `director.rollHourglassDuration()`, Mini 8, Frenzy 6), `taken[type]++`, `PowerupStarted`, banner (`ElementBanner` name + one line, powerup colour, 1.6 s), pill. It ticks `remaining` with **real** dt for capsule types only (the comet ride keeps its own clock), not while `paused`; at 0 → `timed = null`, `PowerupEnded`. Analytics `powerup_started {type, duration (s, rounded)}` / `powerup_ended {type}` from the events, **skipped for `TimedPowerup.comet`**. The comet (WP-3a) keeps writing `RunState.timed` itself — the slot is the shared state, not a call | §3.30 one at a time; WP-3a note |
| Effects | `TimedPowerupEffect` features follow `PowerupStarted / Ended / Paused / Resumed` for their type: `onStart`, `onEnd(death:)` (death = `run.dying`: everything back at once, no end sound), `onPause` / `onResume` (portal ride: effect suspended), `step(gameDt, realDt)`, `reset()` (also from `onDeath` and `detach`) | features never call each other |
| Hourglass | owns `RunState.timeScale` + `RunClock.timeScale` while active or easing: 1 → 0.45 over 0.2 s real (cubic in-out) and back at the end; a ride pause sets 1 **at once** (no slow-motion rides) and music 1, resume eases in again. `SoundService.setMusicRate(0.72 / 1)`. Vignette = `ScreenEdgeGlow.hourglass` in the world (priority −30: over the score circle, under hoops and strips), `intensity` = slowness; ghost trail + clock ring = `HourglassTrail` in `RunTrack.back` (ghosts in track coordinates, drawn with `LookPainter` at 25 % → 0 over 0.5 s, 16/s real) | §3.30 / §5.29 |
| Mini Bird | owns `RunState.birdScale` (every plain-math contact already reads `birdRadius × birdScale`) and `Bird.lookComponent.scale` while active / growing back; it does not touch the look scale while a ride drives the bird (`s.ride != null` / `bird.inRide`); a ride pause sets the collider to full size, resume shrinks again. Sparkles / bubbles / burst in the shared run `ParticlePool` | §3.31 / §5.30 |
| Coin Frenzy | marks the unresolved hoops at start and every `HoopSpawned` while on (not the portal) and wraps their `paintBack` / `front.paintFront` once (an `Expando`): while live it swaps `HoopLook.colors` / `strokeWidth` to `#FFD54A` / `#D48A00` / 8 pt **only during the paint call** (tier-look kinds; specials keep their colours) and draws 10 orbiting `coin.png` coins — the streak / Big Hoops states underneath are never overwritten. `HoopPassed` (not `duringRide`) while on → `earn(5, frenzy)`, `frenzyRing`, a master #8 `CoinPopup` "+5" (shifted 44 pt right, 0.12 s later than the pass popup), `FrenzyCoinShower` (5 coins up). Border = `ScreenEdgeGlow.coinFrenzy` (world, priority −30); sparkles = pool twinkles | §3.32 / §5.31 |
| Pill | `TimerPill` at (100, `CapsuleConfig.pillY` = 156), 120 × 22: track rgba(0,0,0,.12), bar (w − 30) × remaining / duration from x 24, 26 pt icon disc, Hourglass "N s" at x 226 (13 pt Opificio, `#2F80FF`); fades 0.2 s; recreated by the slot after a death cleared the HUD children. **Call:** the mock's y 204 lies in the master banner band (y 190, ≈ 53 pt, shown on every perfect pass), so the pill sits just above it | §5.29 |
| Autopilot | unchanged: the PRD's bot does not aim at capsules (they float on its line; ≈ 50 % are flown through when forced on every gap) | §7 bot rule |
| Tests changed | `test/run/items/s3_6_big_hoops_test.dart`, `test/e2e/p1_gameplay_e2e_test.dart` (Big Hoops expiry): they flew `D + 6` s of **real** time and expected `runClock > D`; with capsules registered an Hourglass on the way slows `runClock` (§3.30), so they now fly until `runClock > D + 2` | PRD-2 behaviour change |
## 25. WP-3e contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `items/{star_trail_feature,egg,piggy,jar}.dart` (features region WP-3e); `pickups/{star_trail,egg_pickup,piggy_pickup,piggy_coin,jar_pickup,firefly_swarm}.dart`; `hud/run_badges.dart` (`EggBadge` / `PiggyBadge` / `JarBadge`); `config/{star_trail,egg,piggy,jar}_config.dart`; `effects/{text_pop,collect_art,collect_fx,hud_fetch}.dart` | ARCH §9.2 3e row |
| Registration | pickups registry (region WP-3e): `starTrail → StarTrailKind`, `egg → EggPickupKind`, `piggy → PiggyPickupKind`, `piggyCoins → PiggyCoinKind`, `jar → JarPickupKind`, `fireflySwarm → FireflySwarmKind`. Features region WP-3e adds `StarTrailFeature, EggFeature, PiggyFeature, JarFeature` **before** WP-2d's `ReviveRulesFeature` (that one stays last). Each element is forceable from the debug menu (0b) since its `ElementId` and unlock index already exist | one region per WP, §3.0.8 |
| Star Trail | `StarTrail` (pickup, track coords) draws the 8 stars + the 2/6 dotted line; `StarTrailConfig.starAt(i)` = u = (i+1)/9, y = lerp(y0, y1, u) − sin(πu)·40 (the 40 pt bulge 40 pt after → 40 pt before the next hoop). Each star collects by touch (`PickupRadii.star = 10`, §3.0.3) → sparkle + `trailNote1..8`, and stores `caughtCount` in `RunState.trails.caught[trailId]`; when the last star is behind the bird it emits `StarTrailFinished(trail)`. `StarTrailFeature` then shows PERFECT LINE ("8 / 8 stars · +5 coins"), pays +5 (`CoinSource.starTrail`) and plays `trailChord` when all 8, else the "n / 8" `TextPop` and nothing; analytics `star_trail {stars}`. Single stars pay nothing (Q65) | §3.26 / §5.25 |
| Egg | `EggPickup` → `PickupCollected(egg)`; `EggFeature` sets `RunState.egg = EggState(stage: egg)` and the `_EggView` (world component, `RunLayer.bird + 1`) rides on the bird's back with the "EGG! hatches in 5 rings" pop. Every `HoopPassed` — ride rings too — cracks it: countdown 4…1 + wobble + `eggCrack`; after `EggConfig.rings` (5) it becomes `EggStage.chick` (HATCHED! banner, hatch burst, `eggHatch` + chord). The chick is a `LookComponent` in `golden` at 48 %, ≈ 36 pt behind / 10 pt below with soft lag, fast flaps and `eggPeep` | §3.27 / §5.26 |
| Egg ×2 (where the doubling lives) | `RunContext.earn` (WP-0b) already applies the doubling: while `state.egg?.stage == EggStage.chick` it adds the same amount again, tracked as `EggFeature.doubledCoins` (`coins_doubled`). **No WP-3e feature doubles coins itself** — ring coins, piggy pay-out and every other bonus all go through `earn`, so they all double (and the piggy pay-out doubles too) | §3.27-3, one owner |
| Egg loss | `RimTouched` scares the chick away (`eggBye` + "bye!" pop + "×2 LOST" banner + `chick_lost`); a crash before hatching breaks the egg (`egg_cracked`, no `chick_lost`); `MistakeSaved` (shield / extra life) loses the egg or chick silently (`egg_lost`); WP-2d's `ReviveRulesFeature` clears `state.egg` on the death that raises the revive offer, so a revive-offer death loses it even if the player revives (Q66) | §3.27-4 |
| Piggy | `PiggyFeature` on `PickupCollected(piggy)`: "PIGGY BANK" + `PiggyBadge`; 4 `PiggyCoin`s in the gap that spawned the piggy (emitted by the feature with `RunSpawner.spawnItem`), the director fills the next 4 gaps ×4 while `DirectorContext.piggyRunning` = exactly 20. A `PiggyCoin` bulges 18 pt off the line; caught → into the bank (`piggyCoin` + `HudFetch` into the HUD piggy), missed → `piggyMiss`. At `caught + missed == 20` the piggy smashes (portal-cleared coins are re-placed, S6-41) (burst at the HUD piggy + a 4 pt `RunShake` kick) and pays **caught × `PiggyConfig.payoutMult` (2)** into the wallet (`CoinSource.piggy`, so the chick's ×2 stacks through `earn`), then shows "+N". `PiggyBadge` = pig, "n / 20" `#E05A99`, 90 pt bar, "n missed". **Call (Fix P6 R1, S6-F03):** the egg / piggy / jar badges are drawn `HudConfig.collectLift` (86 pt) above the mock spot, between the name chips (y 114) and the timer pill (y 156), clear of the banner band (y 190) | §3.28 / §5.27 |
| Piggy pay-out fix | The 2026-10-08 build paid `caught` coins; PRD §3.28/"pays ×2 of what you caught" means `caught × 2`. Fixed in WP-3e (`PiggyFeature._check` → `c.earn(payout, …)` with `payout = caught * PiggyConfig.payoutMult`) | §3.28-3 |
| Jar | `JarPickup` (animated: bob ±5, sway ±7°, lime glow pulse, 10 rays, 4 fireflies inside, sparks) → "FIREFLY JAR" + `JarBadge`; the director places a `FireflySwarm` of 7 in each following gap while `state.jar` is set. The swarm weaves ±32 × ±22 pt (inside `JarConfig.weaveBand` ±45) and each firefly catches at r 16 (`jarTwinkle` + `HudFetch` into the HUD jar) or escapes (`jarEscape` + a ✕ that turns red). 20 caught = JAR FULL +25 (`CoinSource.jar`, `jarFull`, bright chord); 3 escaped = JAR BROKE, no reward (`jarBreak`); either way the jar and its fireflies are gone. `JarBadge` = the jar filling, "n / 20" `#7CB518`, 3 ✕ | §3.29 / §5.28 |
| Losing / keeping them | Piggy and jar: a crash before the pay-out loses the bank / jar (also with a revive); a `MistakeSaved` (shield / extra life) keeps them (Q67 / Q68). The egg follows the table above | §3.27-4 / §3.28-4 / §3.29-4 |
| Ride interaction (§3.0.3) | New `PickupCleared(element, pickup)` event: a portal ride's `clearAhead` marks every pickup it removes `escaped` (never judged) **and** emits `PickupCleared`. `PiggyFeature` refunds the vanished coins to the director (`RunDirector.refundPiggyCoins`; `clearAhead` refunds still-pending planned bank fields itself), which places them again in the gaps after the landing, so the bank still resolves only at `caught + missed == 20` (**Fix P3 R1, S6-41** — replaces the as-built `PiggyState.voided`, which paid out early, against PRD §3.28 / §3.0.3); `JarFeature` does **not** count a cleared swarm as an escape (a lost catch, not an escape) and the ✕s stay, so a jar whose swarms were all cleared resolves at 3 escapes only. Placement resumes after the landing (WP-3b). `RunSpawner.spawnItem(GapItemPlan)` (WP-3e region) lets a feature emit an item right away (the piggy's own gap, the jar's first swarm); the director's follow-gap fields come through the normal slot path | §3.0.3 / §3.28-4 / §3.29-4 |
| Autopilot | region WP-3e in `_cost` / `_chase`: the bot steers at the nearest-ahead collectable while it is nearer than the next hoop's plane, then hands back to the ring plan 0.85 s before the plane (the mock bot rule). Star → the star's y; egg / jar → the pickup's y; piggy → the piggy, then its nearest-ahead uncaught coin; swarm → the nearest-ahead firefly. A hoop's own crossing height does not pay for the collectable | §3.26–§3.29 bot |
| Helpers (§3.0.9) | `effects/text_pop.dart` = the spring's `TextPop` moved out of `hoops/kinds/spring.dart` (which now re-exports it) so the collectables reuse one rising-text pop (`life` 1 s, `rise` 28 pt/s, **centred** — the mocks left-align); `effects/collect_art.dart` (`CollectArt.halo` / `star4` / `triangle` / `roundRect`, the mocks' `halo`/`star4`/`fpoly`/`rr`); `effects/collect_fx.dart` (`CollectBursts` — one shared burst pool + the pickup pop); `effects/hud_fetch.dart` (`HudFetch` — the "caught coins fly into the HUD" ease of §5.27/§5.28, `x += (tx − x) · min(1, 7 dt)`). No second star / pig / jar / firefly drawing | §3.0.9 |
| HUD placement | The badges are **left-aligned** at x 46–172, y ≈ 216 (below the score), while WP-2d's `ScoreHud` circle is centred (≈ x 68–252). At 711 the piggy / jar badges clear the circle; the egg ×2 pill sits just above it. The mock `lab_egg3` puts the pill just under the circle — see the SPEC deviation | §5.26 / §5.27 / §5.28 |
| Sounds | `trailNote1..8`, `trailChord`, `eggPickup/eggCrack/eggHatch/eggPeep/eggBye`, `piggyOink/piggyCoin/piggyMiss/piggySmash`, `jarPickup/jarTwinkle/jarEscape/jarBreak/jarFull` (WP-3h) fired through `AudioPool`; no new `Sfx` entries added | R-S-20 / R-S-21 |
| Tests | `test/run/items/s3_26_star_trail_test.dart` (7), `s3_27_egg_test.dart` (8), `s3_28_piggy_test.dart` (7), `s3_29_jar_test.dart` (9), `s3_26_29_collect_autopilot_test.dart` (24: 4 elements × 2 heights × 3 seeds, ≥ 12 hoops), `test/run/shots/collect_shots_test.dart` (6 shots, §5.25–§5.28) | ARCH §7.1/§7.4 |
## 26. WP-5b contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `lib/versus/{matcher,nickname,upload_queue,run_entry}.dart`, `lib/services/{identity,firebase_versus_backend}.dart`, the Firebase impl in `lib/services/versus_service.dart` (region WP-5b), `lib/run/items/versus_recorder.dart`, `lib/run/screens/versus_intro.dart`, `lib/run/config/versus_config.dart` (`VersusConfig`), `tool/versus_emulator_test.sh` | ARCH §9.2 5b row (+ backend split, config) |
| Service split | `FirebaseVersusService` (matching, held opponent, queue, profile, delete; pure Dart) over a `VersusBackend` interface; `FirebaseVersusBackend` holds every FlutterFire call (App Check, anonymous auth, Play Games link, pool read, transaction write, callable, analytics reset). Tests drive the service with a fake backend (`test/versus/s3_13_service_test.dart`) | plugins need a device; the logic is unit-tested |
| Wiring | `main.dart` region WP-5b: Android only → `FirebaseVersusService(storageOf: () => game.storage)`; every start waits for the `startAfter` gate = `services.ensureFirebase()` (the shared Firebase.initializeApp) + `game.loaded` (Fix P6 R1, S6-F01/F02). Tests / Linux / iOS keep `NoopVersusService` | §6.4, iOS paused |
| START (call) | `beforeRunStart` is **not** used: `_runFromHome` (region WP-5b) takes the opponent at tap time (`versus_matched` / `versus_skipped {reason: no_opponent}`), plays the intro (state `versusIntro`) only when there is one, and `_startRun` uses that opponent (no second `takeOpponent()`). A plain START without an opponent stays synchronous | the 1.0-era tests and journeys rely on a synchronous START |
| VS intro | `VersusIntro` (world priority 20, strips lifted to 21, the coin pill lowered under it); one clock drives the §5.8 timeline from the mock (`play()` of `screen_versus_levels.html`): reel ends at ≈ 3.97 s, VS at ≈ 5.0 s, white fade 6.04–7.34 s. `done` completes under the white; the game starts the run and fades the white out (0.3 s). The home screen is dropped when the panels cover it (0.54 s). `E2EHooks.skipVersusIntroWait` plays it to the end at once; `debugFreeze(t)` / `unfreeze()` for shots. Shared parts: `EmblemView` (0.32 ×), `LookComponent` (2.2 ×, mirrored), `ConfettiBurst`, `Fireworks`, `ParticlePool` (feather trails, seam sparks), `Ease.bezier` (new public wrapper on the easing master) | §5.8, §3.0.9 |
| Intro layout (call) | every mock y maps through `yFor(y) = 44 + (y − 44)·(h − 88)/623` (the band between the strips scales), so 568 pt screens keep birds, plates and VS apart | §3.0.1 R-3.0.1-15 |
| Recorder | `VersusRecorder` (features region WP-5b, before the revive rules): one timeline point per `ScoreChanged` point with the event's flags (a pair "+5" = the pass + 4 gift points at the same time); on the new `RunEnding` event (emitted by `RunController.endRun` right before `summarize()`) it settles `RunState.duel` / `duelBonus`, credits the bonus with `ctx.earn(…, CoinSource.winBonus)` and sends `versus_result {result, score, opp_score}`. `RunSummary.duel` is filled | single timeline writer; YOUR REWARD |
| HUD | `VersusBar.out` (region WP-5b): once `opponent.outAt(runClock)` the opponent box, avatar, score and name chip draw at `VersusConfig.outOpacity` (0.4) | §3.13 "dimmed" (no mock: call) |
| Results | region WP-5b in `ResultsScreen.onLoad`: `ResultsHeader` (pink YOU WIN! / fg YOU LOSE / fg DRAW), opponent `ResultsPlayerColumn`, Fredoka VS at (160, 194); both scores count up; the WINNER tag is `ResultsWinnerTag` (gold, plum 11 pt, 2 × 8 — the mock; the generic `MenuTag` is white-on-gold) | §5.10 |
| Upload | `UploadQueue` over `uploadQueue` / `uploadsToday` / `uploadsDay`: score < 3 never, a new best always, others ≤ 3 per **UTC** day (counted at enqueue), cap 12 (oldest non-best dropped), FIFO flush one run per write; `UploadWrite.retry` keeps the head (offline / timeout), `drop` removes it (rules refusal) | §3.13, WP-5a write contract |
| Player doc | `nextPlayerDoc(old, run, newBest, …)` builds the whole doc: `recent = [run, ...old.recent].take(5)` (old entries passed through unchanged so `in old` holds), `bestRun` = the same run object only for a new best above the stored best, `best = max(old.best, run.best)`, `level` = the stored player level (WP-L, `PlayerFields.level`; `levelFor(best)` when absent), `uploads {day, count}`; the backend adds `updatedAt` (server timestamp) and `expireAt` (now + 60 d) and writes it in a transaction | ARCH §6.1 |
| Identity | `PlatformIdentity` / `PlayGamesIdentity` (`GameAuth.player` stream, `GameAuth.getAuthCode(VersusConfig.playGamesWebClientId)` → `PlayGamesAuthProvider.credential`, games_services 5.1.0 has it) / `GameCenterIdentity` stub. The service links when a player appears; `credential-already-in-use` signs in with that account (a fresh code if the error carries none) | §6.4; never `signIn()` at launch, never `isSignedIn` |
| App Check | `FirebaseVersusBackend.activateAppCheck()`: `AndroidDebugProvider` in `kDebugMode || kE2E` (the native SDK logs the debug secret to logcat; `FS_APPCHECK_DEBUG_TOKEN` passes a registered one), `AndroidPlayIntegrityProvider` in release; Apple: debug / App Attest + DeviceCheck fallback | §6.5 |
| Avatars (call / not done) | the plates, HUD and results draw the neutral person glyph; `avatar` is stored (Firebase `photoURL` after a Play Games link, else '') but no image is loaded yet. Display names are the Play Games name when signed in, else the nickname | §5.8 "neutral avatar while missing" |
| Intro bird (call) | the "tail wiggle" has no counterpart (`LookPainter` draws the tail with the body); everything else of "always alive" is built (bob, tilt, flaps, blinks, landing squash, hop, lunge, flip) | shared bird master |
| Intro length (call) | the mock's timings give ≈ 7.3 s (the PRD's "≈ 6.3 s" is approximate; the timing table is followed) | §5.8 table |
| Live check | `tool/versus_emulator_test.sh` → `firebase emulators:exec --project demo-flappy-spikes` + `FS_EMULATOR_TESTS=1 flutter test test/versus/s3_13_emulator_test.dart`: client-built docs pass the real rules, `onPlayerRunWrite` pools them, a second player matches and replays; one run per write; a foreign token is refused; `deleteMyData` needs App Check. Skipped in the normal suite | ARCH §7.2 |
| ProGuard | `android/app/proguard-rules.pro` region WP-5b (gRPC, protobuf-lite, Firestore / App Check / Functions / Auth, Play Games, Play Integrity); `flutter build apk --release` builds | build gate |
| iOS setup (when reopened) | register the iOS app (`flutterfire configure` → `GoogleService-Info.plist`), enable Game Center sign-in in Firebase Auth and implement `GameCenterIdentity` (`GameCenterAuthProvider.credential()`), register App Attest in App Check, wire `FirebaseVersusService` for iOS in `main.dart` (`identity: GameCenterIdentity()`), add the App Store privacy labels (same data as the Play data-safety form). Rules, pools and functions need no change | §3.13 cross-platform |

---

## 27. WP-4c contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Service signature | `VersusService.deleteMyData()` is **`Future<bool>`** (was `Future<void>`): `true` = the callable confirmed and the local state was reset; `false` = offline / refused, nothing was deleted and the local state (nickname, queue, counter, account) is kept for a retry. `NoopVersusService` → `true`; `FakeVersusService` → `deleteSucceeds` (scriptable) + `deleteCalls` | the Settings row must tell "failed" from "done" (PRD-2 §3.13 offline/failure) |
| Local reset | `GameStorage.resetVersusData()` (region WP-4c): clears `versusNickname` (removed, so it is regenerated), `uploadQueue`, `uploadsToday` / `uploadsDay`. Coins, skins, levels, feathers, puzzle, met elements and the sound / rumble settings are untouched | ARCH §5 / Q22 |
| Firebase order | `FirebaseVersusService.deleteMyData()`: callable first (`backend.deleteMyData()`), then `resetAnalytics()`, then `resetVersusData()`, then the session's pool / held opponent / `_seen` are dropped, `_ready = false` and `initialize()` runs again (a fresh anonymous account so versus keeps working) | a false callable must not wipe local state; the same account is needed for the retry |
| UI | `SettingsPanel.onDeleteMyData` (the home panel and `openRunSettings`); the row is `DeleteDataIcon` + "DELETE MY DATA", placed at `deleteRowPositionFor(centerY) = privacyLinkPositionFor(centerY).y − 60` (**565 @ 711, 425 @ 568**) so it never collides with the 44 pt bottom spike strip (starts at 524 @ 568) | PRD §3.13 "in Settings"; §5.1 spike strips |
| Dialog | `DeleteDataPopup extends P1Popup` (`lib/components/delete_data_popup.dart`): confirm face = soft trash glyph + CANCEL (soft) / DELETE (pink); result faces = gold OK, "DATA DELETED" (`Sfx.skProgress`) or "COULDN'T DELETE" (`Sfx.skNoCoins`). Wording is a call (PRD Q22 fixes what it deletes, not the copy) | P1 popup style (`purchase_result_popup.dart`) |
| Modal rules | `_deleteDataPopup` joins `modalPopupOpen` and `liveMotionPaused`; `openDeleteDataConfirm()` / `confirmDeleteMyData()` / `closeDeleteDataPopup()` / `_deleteDataBack()` in the game (region WP-4c). CANCEL, the ✕, Esc and the dim dismiss without a call | one popup queue, never two at once (§3.0.9) |
| Tests | `test/versus/s3_13_delete_data_test.dart` (row at 568 + 711 + safe band, confirm wording, CANCEL / ✕ / Esc, DELETE → `deleteCalls` + "DATA DELETED", failure text, `resetVersusData`), the two new `persistence_test.dart` cases (§3.14 payout record, §3.13 reset) and `settingsShot` in `test/menu_screenshot_test.dart` (row + confirm / deleted / failed at 568 + 711) | PRD §7 test list, WP-4c sheet |

## 28. WP-4a contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Files | `pickups/feather_pickup.dart` (`FeatherPickupKind`, `FeatherPickup`, `FeatherArt` — the one feather drawing for pickup, flight, tray and bonus screen), `pickups/puzzle_piece_pickup.dart` (`PuzzlePieceKind`, `PuzzlePiecePickup`, `PuzzleArt` — the four clip paths, picture, glow / rays), `items/{feathers,puzzle}.dart` (`FeathersFeature` + `FeatherTrayItem`, `PuzzleFeature` + `PuzzlePillItem`; features region WP-4a, before 2d's revive rules), `hud/collect_layer.dart` (`CollectLayer`, `CollectTimeline`, `CollectText`), `screens/bonus_screen.dart` (`BonusPage`, `BonusScreen`, pure `BonusRules`), `config/{feather,puzzle,bonus}_config.dart` (`FeatherConfig` + `CollectConfig`, `PuzzleConfig` + `PuzzleTheme` data, `BonusConfig`). Registered in `pickups/registry.dart` (region WP-4a) | ARCH §9.2 4a row |
| Banked at the touch | a feather / piece is written to storage in the `PickupCollected` handler (`saveFeathers`, `savePuzzlePieces` / `completePuzzleRound`), so a death or a kill a second later keeps it (§3.14 "kept: feather / piece progress"). `RunState.featherSpawned` / `pieceSpawned` are set when the pickup is built (the controller's `featherWanted` reads it) | §3.15 / §3.16 |
| Puzzle 4/4 | at the 4th piece's touch: `director.rollPuzzleBonus()` → `RunState.coinsThisRun`, `wallet.add(…, CoinSource.puzzle)`, `CoinsEarned(puzzle)` — not through `ctx.earn` (recoverable payout record), but doubled by the chick in coins and points like `earn` (PRD-2.2 §13.1, P22-FIX1 S7-03; the badge shows the paid amount; points entry flagged `bonus | puzzle`) — then `completePuzzleRound()`. A piece the player already holds (only a debug force can plan two in one run) fills the first missing place | §3.16 |
| Collect slot | `CollectLayer.ensureFor(run)` puts one layer in the `RunHud` (priority 17): the shared `CollectSlot` (master, **no banner wait** — `banners: null`), a screen-space `ParticlePool` (trails, sparkles, confetti), `ShockRing`s. The `GoldSticker`s ("BONUS UNLOCKED!", "PICTURE COMPLETE") are added to the run's banner layer instead (PRD-2.2 §12.2, `CollectLayer.bannerLayer`), behind the gameplay. The puzzle's `CollectText` ("n/4", the badge's "+N") is drawn there too by `CollectLabels` (a part of the layer, priority 2, on the slot's clock and fade, §12.1); the pill's panel and the badge keep a 1 pt window over each text, and the banner layer paints the backing under it. The layer removes `CollectLabels` with itself, and a removed `CollectSlot` calls `onDiscard` on its active and queued items so their stickers go too (§12.4). **Call:** the slot centre is `CollectConfig.slotY` = 288, not the PRD's 230: the banner band (y 190 → ≈ 252 with a subtitle) shows on every perfect pass, so Q37's "wait for the banner" would hold the tray for most of a streak; under the band the two never overlap (also clear of the 3f timer pill at y 156). A death clears the layer with the HUD; the next `ensureFor` builds a new one | brief: no overlap with the banner band / timer pill |
| Items | `CollectTimeline` (a `CollectSlotItem` with cues on the slot clock: landing sound / punch / ring / sparkles at 0.76 s, the complete celebration at + 0.24 s, the sticker at + 0.15 s, the puzzle coin badge at + 0.55 s). The `FetchFlight` (master) lands in the slot at the same 0.76 s | §5.14 / §5.15 timelines |
| Master fixed | `FetchSpec.feather` / `.puzzlePiece` `scaleFrom` = the pickup scale (1.05 / 2.1): the swell runs ×1 → ×1.4 / ×1.3 from the pickup as in `collect.js itemTf` (it started at the swollen size and grew again) | §5.14 / §5.15 |
| Page grey and rays (PRD-2.2 §31) | `kPostRunPalette` (`palettes.dart`, = stage 0: `#F1F1F1` / `#828282`) is the only palette of the balloon bonus and results pages. `FlappySpikesGame.postRunPageUp` (set by `showBonus` / `showResults`, cleared by `_removeResults` / `_removeBonus` in `replay()`) puts both run strips in page mode (`SpikeStrip.onPage`: normal reach, approved grey, no squeeze inset, no flash) and the banner strip (`_syncBannerStripColor`) in the page grey. `ResultsScreen.render` paints the background and then the 12 level-up rays (radius `ResultsConfig.rayRadius` 280 × the page scale, unclipped, `ResultsScreen.rayFade`: 35 % → 19 % at 45 % → 0); `ResultsLevelStage` no longer draws rays | §31 |
| Bonus flow | `PostRunScreens.bonus = BonusPage()` (game `onLoad`, region WP-4a). `game.showBonus(s)` (region WP-4a): state `bonus`, `saveFeathers(0)`, `bonus_shown`, prizes shuffled on the run's `timing` stream, the screen in the world at priority 20 with the strips lifted to 21; it completes on NO THANKS / NEXT (state back to `results`, the results page comes up over it, the screen removes itself 0.6 s later); `replay()` drops a screen still up | §3.15, ARCH §1.11 |
| Bonus screen | one component painting the 320 × 711 mock through `BonusRules.layoutFor(h)` (between the strips: scale `(h − 88) / 623` ≤ 1, centred above 711); test seams `tapTile`, `tapOffer`, `tapNoThanks`, `tapNext` (= the tap targets). Each pick credits `wallet.add(prize, bonus)` at the tap and sends `bonus_pop {prize, pop}`; out of feathers + settled → `BonusRules.offerFor` (ad / free for no-ads / none); ad → `showRewardedAd(bonusFeathers)` → completed: 3 feathers fly back, `bonus_ad_completed`; not completed: NEXT (call). Coins drawn with the coin sprite (master #14), never code-drawn; rings `ShockRing`, pop flash `PickupTouchFx` | §3.15 / §5.14 |
| Analytics | `feather_collected {count}`, `bonus_shown`, `bonus_pop {prize, pop}`, `bonus_ad_offered` (real ad only), `bonus_ad_completed`, `bonus_declined {pops}`, `puzzle_piece_collected {piece 1–4, count 1–4, round 1-based}`, `puzzle_completed {round 1-based, coins}`; `coins_earned` for `bonus` / `puzzle` through the wallet hook (not aggregated) | §6 |
| Autopilot | the prototype bot does not chase the detour pickups (not taught). Region WP-4a in `targetY`: with a small bird (Mini Bird) the switch pre-target aim moves down by up to 12 pt so the ≈ 55 pt bang-bang arc is centred on the switch (its reach is 18 + 7.7 pt): the feather / piece rolls shifted a seeded switch-ring course into a Mini Bird + high switch case the bot missed | §7 bot rule |
| Tests changed | `test/run/shots/hazard_rings_shots_test.dart`: the §5.19 switch shots use seed 6 (the director's feather / piece rolls changed the seed-4 course at 568 pt, which showed no Lockdown switch before the bot's run ended) | seeded course shift, not a behaviour change of 3d |
## 29. QA round P3 fix notes (`Fix P3 R1`, as built 2026-10-08)

| Finding | As built | PRD |
|---|---|---|
| S6-40 | `FeverFeature` subscribes to `RimTouched` and puts the fire out (`fever_fire_out` cause `graze`, smoke, sizzle) at the contact; ignored while a ride runs | §3.19 |
| S6-41 | Director owes bank coins (`_piggyOwed`, 16 at activation, ≤ 4 per gap); `refundPiggyCoins(n)` re-owes coins a portal cleared (from `PickupCleared` in `PiggyFeature`, and pending planned fields in `RunSpawner.clearAhead`). `PiggyState.voided` removed | §3.28 / §3.0.3 |
| S6-42 | `StarTrailFeature` plays `Sfx.trailPop` with the "n / 8" pop | §3.26, SOUNDS |
| S6-43 | `ParticleShape.coin` draws master #14 (`CoinIcon.paint`, `ParticlePool.coinImage`); the pair's +10 COINS spray uses it | §3.0.9 #14, §5.20 |
| S6-44 | `Autopilot` plans the closed-switch approach (rollout of the ring planner's controller family toward the switch point, reach = 18 + bird r × scale − 3) before the hoop planner | §7, §3.31 |
| S6-45 | `RunDirector._switchItem` picks the switch from the intersection of 70–100 pt off the ring, ≤ 110 pt from the previous centre and the item margins; if empty the ring moves (1 pt steps, band limits, ≤ max jump) to the nearest height that has one, else the slot is a normal hoop. `RunConfig.switchMinFromRing` removed | §3.20 |
| S6-46 | `nextGap`: running bank / jar fields are not placed inside the squeeze window (the bank keeps what it owes) | §3.17 |
| S6-47 | `ClearFade` mixin (`effects/clear_fade.dart`) on `Hoop`, `HoopFrontLayer`, `Pickup`: `clearAlpha` drawn through one translucent layer; `RunSpawner` sets it to remaining / fade each frame of the 0.2 s clear | §3.12 / §3.0.3 |
---

## 30. WP-6a contract notes (as built, 2026-10-08)

| Area | As built | Why |
|---|---|---|
| Release e2e | `integration_test/release_e2e_test.dart`: journey (ad revive → coin revive → No thanks → level-up results → CLAIM → NEXT → home), element sweep (every `ForceMenu.forceable` element the build registers + Big Hoops via the armed home slot + the squeeze; a catalogue element that is neither swept nor listed in `_coveredElsewhere` fails the test), the six rides, reminders (Android), versus live (`FS_LIVE_VERSUS`, Android) and a FrameTiming log (tier 3, comet, space ride) | ARCH §7.3 P6 |
| Persistence in e2e | every launch uses `SharedPreferences.setMockInitialValues` (in-memory, also on the phone): a fresh best 0 / 0 coins / `firstSessionDone`, the sweep with every element met (no first-meet forcing in the way) | deterministic journeys; the phone's real data is untouched |
| Screenshots (call) | `RenderRepaintBoundary.toImage` of the boundary above the `GameWidget` (not `takeScreenshot` / `convertFlutterSurfaceToImage`): one path on Linux and Android. Linux: `build/e2e/release/`; Android: `<cache>/e2e_release` (pull with `adb exec-out run-as … tar`) | `takeScreenshot` has no desktop implementation |
| Frame log (call) | own `addTimingsCallback` summary (build / raster / total ms: avg, p50, p90, p99, max, frames over 16.7 ms) into `binding.reportData['frame_timings']`, `frame_timings.json` and a `FRAMES` log line; not `watchPerformance` / `traceAction` | those wait on the VM-service timeline and can hang without frames; the log is not a gate |
| RunEvents errors | the test traps `RunEvents: … threw` debug prints (the bus swallows handler errors) and fails on them | "no exceptions" must include swallowed handler errors |
| App Check | `FirebaseVersusBackend.activateAppCheck({String? debugToken})`: the live versus test passes `FS_APPCHECK_DEBUG_TOKEN` or a fresh UUID v4 and prints it in a banner for registration | the orchestrator needs a printable token |
| iOS | `PORT-IOS.md` (repo root): the port checklist + every Android-only path with file:line | P6 prep |

## 31. QA round P4/P5 fix notes (`Fix P45 R1`, as built 2026-10-08)

| Finding | As built | PRD |
|---|---|---|
| S6-60 | `UploadQueue.flush` paces non-best writes by the UTC **upload** day (`uploadsSent` / `uploadsSentDay`, `sentToday`): at most `dailyUploads` (3) a day; over that a non-best run is skipped and stays queued (a later best still goes out). The enqueue rule (≤ 3 a play day) and the cap of 12 (oldest non-best evicted) are unchanged. There is still no acknowledgement read (rules deny `versusRate`), so pacing is what keeps runs from being rate-rejected | §3.13 upload / offline rules |
| S6-61 | `deletePlayerData` is one Firestore transaction: reads the player, rate and 44 shards, then deletes / rewrites (≤ 46 writes) — a failure deletes nothing, a retry starts over; serializable with `processPlayerWrite`. `deleteMyData` first checks Auth (`getUser`, `unavailable` if it does not answer), then the transaction, then `deleteUser`; an Auth-delete failure after the data delete is completed by the client's retry (idempotent) | §3.13 / Q22 privacy |
| S6-62 | `PuzzleFeature._complete`: `beginPuzzleCompletion(payout = balance + bonus)` (record, mask 0, round + 1 — issued before the coin write), `wallet.add`, then `endPuzzlePayout()`. `PuzzleFeature.settlePayout` pays `puzzlePayout − balance` at start (game `onLoad`, before `_creditUnclaimedLevelReward`) and clears the record — same pattern as S6-22 | §3.16, §7 |
| S6-63 | `BonusRules.layoutFor` scales only the column above `BonusConfig.bandTop` (552) into `h − 159 − 44`; the band (feather row, ad button, NO THANKS, NEXT) is drawn unscaled with `bandShiftFor(h) = h − 711` (bottom-anchored). Taps hit-test grid in column space, buttons in band space; feather flights convert band points (`_bandToContent`) and keep the row's size at the band end | §3.0.1, §5.14 |
| S6-64 | (superseded by WP-AV: `StickerAvatars`) `lib/services/avatars.dart`: `AvatarImages` (game `avatars`) — `lookup(key)` returns the cached image (Flame `Images`, keyed by URL or a `data:` URI) or starts one load and returns null (glyph). `AvatarSource`: `NoAvatarSource` (default, tests/desktop), `HttpAvatarSource` (https, 8 s, 512 KB; wired in `main.dart` on mobile). `PlatformPlayer.iconImage` (games_services 5.1.0 `PlayerData.iconImage`, base64) → `VersusProfile.avatarImage`; the intro plates, `VersusBar` and `ResultsPlayerColumn` paint the image when cached | §3.13 Who plays, §5.8 |
| S6-65 | `FlappySpikesGame.myVersusName`: `versus.me.name` (WP-AV: always the nickname), else the stored nickname, else "You"; used by the VS intro, the HUD chip and both results columns | §3.13, §5.8, §5.10 |
| S6-66 | `FirebaseVersusService`: a shared start future; a failed start schedules background retries (`retryBase` 5 s doubling to `retryMax` 2 min; `main.dart` passes `VersusConfig.authRetryBase`, tests leave it null) and is retried at once by `prefetch`, `flush` (so `submitRun` too) and the new `VersusService.onResume()` (game `lifecycleStateChange(resumed)`). `flush` passes are shared. No connectivity plugin (call): the backoff timer is the connectivity probe | §3.13 offline rules; R-3.13-2, -8 |


---

## PRD-2.2 WP-G2 contract changes (2026-10-12)

| Contract | Change | PRD-2.2 |
|---|---|---|
| Spawner timing | One slot planned ahead (`RunSpawner.plannedAhead`): `RunDirector.nextSlot` / `nextGap` run one gap before the slot's hoop spawns, so `RunState.hoopIndex` (slots spawned) is `director.hoopIndex − 1`. Attached items (switch, comet star) are created at plan time; `HoopKind.linkAttached(h, pickup, c)` hands them to the hoop when it spawns (the switch ring takes its switch; `SwitchPickup.ringPlan` places the Power Iris cable until then). A revive or a ride started since the plan turns the planned-ahead slot plain (`RunDirector.takeRevivePending`, `RunDirector.plainSlot`). `clearAhead` / `clearAll` / `hold` include the planned-ahead slot | §15 |
| Pop-in | `RunSpawner.spawnItem` (feature follow-ups) pops an item in when its left edge is inside the screen: `ClearFade.popScale` 0 → 1.15 → 1 over 0.25 s + a `CollectBursts` sparkle in `layers.fx` | §15.1 |
| Events | `PickupSpawned(pickup)` for every pickup created; `ActivityStarted` / `ActivityEnded(activity)` | §15 / §27 |
| Director tables | `heart.first = (5, 27)`, `featherWindow = pieceWindow = (3, 40)`, `featherChance = pieceChance = 0.6` (rolled on the timing stream), `earlyPool` (indices 4–9: Star Trail / Bullseye / angled / nothing, equal weight; `RunDirector.earlyPicks`); single pickups 30–70 % along the gap, ±50 pt off the line; patterns' start moves | §19 |
| Activity | `RunState.activity` (`RunActivity.of(state)`: portal / comet ride, piggy, jar, capsule), `activityStart`, `activityEndedAtSlot`; `DirectorContext.activity` / `activityEndedAtSlot`; the director skips every reward ring / item (`RunDirector.rewardKinds`, `isRewardItem`, `isRewardSlot`) during an activity and its 2-hoop cool-down (slots from n + 1, gaps from n, n = the next slot to plan when it ended); `oweFeather` / `owePiece`; `activityItemsFor` refills the planned gap with a new piggy / jar run's own items | §27 |
| Reward rings | `Hoop.plan` is mutable; `Hoop.stripReward()` (pair / Lucky Spin / FEVER on screen when an activity starts) makes its plan kind normal, fades the reward parts (`rewardAlpha`, `NormalHoopKind.paintStripped`) and the kinds skip their reward on pass | §27.3 |
| Egg | A rim touch while still an egg breaks it (`EggFeature._break`, `egg_broken {cause, cracks}`); ride rings don't crack it; `CollectBursts.burst(gravity:)` | §23 |
| Portal ring | Fixed 118 pt (`RunConfig.portalOpening`) × the Big Hoops multiplier (unchanged from 2.3.1) | §25.1, PRD-2.4 §2.3 |
## 32. WP-33c contract notes (PRD-2.2 §33.4 items 4–6, as built 2026-10-12)

| Area | As built | PRD |
|---|---|---|
| Idle menus | `lib/game/idle_frames.dart` `IdleFrameLimiter` (game `idleFrames`, enabled by `main.dart` outside FS_E2E; off in tests unless a test turns it on). At the end of each `update` the game reports `_menuIdle` (state start, a menu scene on top with nothing over it, no fade / colour fade / popup queue / ad, Home built and fully shown, `CoinPill.busy` false, no `Effect`, `CoinFly`, `CoinRewardAnimation`, `ConfettiBurst`, `ServiceMessage`, `ScreenFlash`, `ScreenShake` or gliding `MenuScrollArea` in the tree) for `Config.idleMenuDelay` (2 s). Then Flame's loop is stopped after the frame and a timer restarts it `1/Config.idleMenuFps` later (30 fps); the restart frame's dt is the real vsync-to-vsync time (Flame's restart gives 0). A global pointer route, keys and the system back wake it at once. Home's idle motion (bob, pulse, streak, wiggles, glint) keeps its timing, only fewer frames | §33.4 item 5 |
| Background | Flame's `pauseWhenBackgrounded` (kept explicit in the constructor) stops the engine on paused / hidden / detached and resumes on inactive / resumed; the limiter drops its timer on background | §33.4 item 5, §33.7 |
| Avatars | (superseded by WP-AV) `AvatarImages` decodes with `instantiateImageCodecWithSize`: short side ≤ `Config.avatarDecodePoints` (52 pt, the VS plate) × physical px per world pt, never upscaled; an LRU of `Config.avatarCacheMax` (6) keys, refreshed on every `lookup` hit, evicts with `Images.clear` (disposes); an evicted key loads again when drawn | §33.4 item 4 |
| Small ones | `lib/game/paints.dart` `layerPaint(alpha)` / `fillPaint(color)`: shared scratch paints for per-frame `saveLayer` fades and plain fills (banners, pair / switch kinds, bonus screen, stickers, feathers, puzzle, rides, menus); `PulseEffect` makes a new blur only when its sigma changes; `Rumble.fired` records only without hardware or in debug builds, capped at `Rumble.firedCap`; the share capture image is disposed after encoding; `CollectText.clearCache` disposes its `TextPainter`s | §33.4 item 6 |

## PRD-2.2 WP-G3 contract changes (2026-10-12)

| Contract | Change | PRD-2.2 |
|---|---|---|
| Comet zigzag | `RunDirector.onCometStart({fromY, endTrackX, viewHeight, amplitude})` / `updateCometEnd(x)` / `cometEndTrackX`: during a comet ride, ride slots whose plane is ≤ the predicted end sit at `viewHeight / 2 ± CometConfig.zigzagAmp`, alternating, the first opposite `fromY` (the star hoop's centre; the bird's y for the pair gift); later ride slots get the normal layout centre (the normal draw is always made). `onRideEnd(comet)` clears it | §16 |
| Comet path | `CometRide(c, source:, starY:)`; `CometRide.predictEndTrackX()`, `nextPlaneAhead({minAhead})`, `slope`, `flightAngle`: the comet flies an ease-in-out curve over track x between hoop planes; tilt = flight direction, ±35°, ≤ 240°/s (`CometConfig.maxTiltDeg`, `maxTiltRateDeg`, `minCurveSpan`; `steerRate` / `maxSteerSpeed` / `tiltPerPt` are gone) | §16 |
| Landing | `rides/landing_slow_mo.dart` `LandingSlowMo` (owned by `CometFeature.landing`, stepped with real dt): `RunState.landingScale` / `hourglassScale` / `cometLanding`; `RunState.timeScale` = min(landing, Hourglass) — `HourglassFeature._write` and the landing both write it; `RunActivity.of` counts `cometLanding` as the comet activity. `CometRide._finish` flaps the bird (`Bird.flap()`) | §17 |
| Ride scene layers | `RideTheme.paintBackdrop` / `paintWorld` (objects) and `paintExitBackdrop` / `paintExit` (objects); `RideTheme.circleColor` / `circleDigits`. `PortalRide` adds a backdrop layer (`PortalConfig.backdropPriority` −150), a scene banner layer (`sceneBannerPriority` −99) and the objects layer (`worldPriority` −60); in the flight / glide the circle and the banner layer move over the wash (`circleOverWashPriority` / `bannerOverWashPriority`) | §18.1 / §18.5 |
| Score circle | `game.scoreHud`; `ScoreHud.setSceneLook({circle, digits, mix, alpha})` / `clearSceneLook()` / `sceneMix` / `visibleOpacity`: the one circle draws the normal look at 1 − mix and the scene look at mix · alpha; the ride sets its priority and restores it at the end | §18.1 |
| Banners | `BannerHost.drawnByScene` (its own render pass draws nothing) + `renderInScene(canvas, opacity)`: a portal ride's scene banner layer draws the host at 1 − 0.5 · mix. Since PRD-2.2 §12 the host lives in the run's `RunBannerLayer` (world, −60); both members are kept and the ride layer keeps drawing it into the scene | §18.1 |
| Portal end | `PortalRide._finish` flaps the bird; `resumeAt` = glide start + `PortalRide.cruiseDistance(runClock, glide + settle + PortalConfig.firstRingAfterControl)` (`resumeAfterLanding` is gone) | §18.2 / §18.3 |
| Sound preload | `items/sound_preload.dart` `SoundPreloadFeature` (features region WP-G3): `HoopSpawned(portal)` → `SoundService.preload(portalCues(theme))` (`pu_portal`, `pu_land`, `flap`, the theme's cues); `PickupSpawned` comet star → `pu_comet_get/end`; capsule → its power-up's cues. `requests` (tests) | §18.4 |

## PRD-2.3 WP-SET contract changes (Settings §20, gift codes §22; 2026-10-13)

| Contract | Change | PRD-2.3 |
|---|---|---|
| Settings screen | `SettingsPanel` rebuilt in place (`lib/components/settings_panel.dart`): `SettingsTile` ×3 (SOUND / MUSIC / RUMBLE; `on`, `tag`), `VolumeBars` (8 levels, tap / drag, `levelAt(x)`, `barRect(i)`), `SettingsCard` + `SettingsRow` (GAME: Support, Restore purchases (spinner while `game.purchasesRestoring`), Redeem code; PRIVACY & DATA: Privacy policy, Privacy options (only when `privacyOptionsShown`), Delete my data), footer (`creditText`, `versionText`). Callbacks unchanged plus `onSupport`, `onRedeemCode`. Geometry: `SettingsLayout.fit(viewHeight, gameRows, privacyRows)` from the `Config.settings*` knobs (the page at 711; shrink order at 568: card gaps → rows 34 → tiles 88 → then, a call, top band / rows 30 / tiles 64 / paddings / bottom inset). Removed: `DeleteDataIcon`, `VolumeSlider`, `RestoreLink`, the old `settings*Dy` row layout use. `RumbleToggle(interactive: false)` sits inside the RUMBLE tile | §20.2, §20.4 |
| Volume | Shown as `SettingsPanel.levelFor(volume)` (nearest of 0–8); a change stores `level / 8` through the unchanged `onMusicVolume` → `game.setMusicVolume`. The MUSIC tile remembers the last level for the app session (`SettingsPanel._lastMusicLevel`; from 0 with none: `Config.settingsMusicRestoreLevel` = 5) | §20.2 |
| Links | `game.urlOpener(uri, mode)` (default `launchUrl`; tests record) behind `openPrivacyPolicy`, `openSupport` (`Config.supportUrl`) and `openMusicCredit` (`Config.musicCreditUrl`, the footer's name): the in-app browser (`LaunchMode.inAppBrowserView`: Custom Tab / SFSafariViewController; owner 2026-10-19, WP-SET). `openRedeemCode` (`Config.redeemCodeUrl`, logs `redeem_code_opened`) stays `externalApplication` (the Play app). `Config.deleteDataUrl` is plain text in the Delete dialog's confirm face (`DeleteDataPopup.webText`), not a link | §20.3, §22.2 |
| Version | `lib/services/app_info.dart`: `AppInfo` (`NoAppInfo` default, `FixedAppInfo` tests, `PluginAppInfo` = `package_info_plus`, try/caught, wired in `main.dart` and read at launch; only a success is cached, WP-SET) → `game.appInfo`. The panel sets the footer text whenever the read lands (no mounted check: a cached read lands before the first frame mounts the panel) | §20.2, §20.4 |
| Gift products | `IapProduct.giftCoins10000` (`gift_coins_10000`, consumable, 10 000) and `giftNoAdsCoins10000` (`gift_noads_coins_10000`, one-time, No Ads + 10 000); `isGift`, `grantsNoAds`; `kShopProducts` = everything sold / price-queried (gifts excluded; `StoreIapService` queries only these) | §22.1, §22.2 item 5 |
| Sync | `IapService.syncPurchases()` (Store: `restorePurchases` = Play `queryPurchases`; a call before `initialize` runs right after it). `Purchases.sync()` throttles to `Config.iapSyncInterval` (5 s) on the game clock; the game calls it after creating `Purchases` (launch) and on every `resumed` | §22.2 item 2 |
| Store layer | `IapEvent.acknowledged` (Play `Purchase.isAcknowledged`, null elsewhere). A Play purchase whose `purchaseState` is pending is never granted or completed (the plugin labels it `restored`). A granted consumable that is a gift, or a consumable brought back `restored`, is consumed with `IapStore.consumePurchase` (`InAppPurchaseAndroidPlatformAddition.consumePurchase`; false off Play → `completePurchase`) | §22.2 item 3 |
| Granting | `Purchases._grantGift`: a gift product, or a `no_ads` not started this session with `acknowledged == false` and not yet granted (a promo code), is granted once per persisted purchase id (`GameStorage.grantedPurchases`, no new key); an already granted or store-acknowledged one-time gift only restores No Ads (never coins). Coins `CoinSource.gift` (promo `no_ads`: its 1 000 as `noadsBonus`); `gift_redeemed {product, source: promo}`; `onGift(GiftGrant)`. A restored consumable with ids is granted like a purchase. A `restored` No Ads toasts "Purchases restored" only while the player's own restore runs (the sync is silent) | §22.2 items 3, 6 |
| Gift popup | `game._onGiftGranted`: holds the pill (`reserve(coins)`), holds the No Ads looks, queues `openNoAdsCelebration(gift:)` (`NoAdsCelebration.gift`: "A GIFT FOR YOU!", the item, the gift's coins; CLAIM flies them in via `CoinRewardAnimation.noAdsBonus(amount:)`) for `_menusUp` (any menu, never mid-run / results), one per code. `pendingGiftPopups` (tests) | §22.2 item 4 |
| Popup order hook | **`game.giftThisHomeVisit`**: true from a gift grant until the next run starts. Gift popups queue first; LEVEL UP waits for an empty popup queue; every No-Ads popup trigger must skip while it is true — the session-start offer (`_startSession`) reads it; PRD-2.3 §24's after-run check must read it too | PRD-2.3 §0 item 2 |

## 33. PRD-2.3 §14 / §15 contract notes (P23-14 / P23-15, as built 2026-10-13)

The 2.2 numbers above (cruise +3.5 %/min, opening 118 → 92, comet / portal schedules, coin amounts,
the chick's ×2, the perfect zone) are superseded by PRD-2.3 §14; `SPEC.md` has the DEVIATION list.

| Contract | As built | PRD-2.3 |
|---|---|---|
| Tuning layer | `TuningValues.current` (pure Dart, `run/config/tuning_values.dart`) is what every tunable getter reads: `tuning.i/d/b/ints/range/curve/obj('<key>')`. DEVIATION (audit 17, 2026-10-19): the Remote Config read (`services/tuning.dart`, `FirebaseTuningBackend`, `kTuning` / `FS_TUNING`, `beginRun`) is removed; the baked values equal the live RC values of 2026-10-19. `TuningValues.resolve` is a test-only override | §15.2 |
| Adding a key | One `TuningDef(key, type, value, section, doc)` line in `tuning_defaults.dart` + a config getter | §15.3 |
| Keyframes | `Keyframes([[hoop, value], …]).at(x)`: linear between keys, flat outside | §15.3 |
| `DirectorTables.prd2` | Now a getter: `DirectorTables.fromTuning(TuningValues.current)` (spawn rows `spawn_*`, heart, feather / piece windows and chances, `CometRule comet` {chance, from, spacing} replacing the comet `Schedule`, portal `Schedule` 40–60 / 60–80, pair / capsule weights, `tiltCurve` / `movingCurve` → `tiltChance(i)` / `movingChance(i)`). `RunDirector({DirectorTables? tables})` defaults to it. Budget rows and the early pool stay const | §14.4, §14.5, §15.3 |
| Speed / opening | `RunConfig.cruise(int hoopIndex)` (`curve_speed`; callers pass `RunState.hoopIndex`, so a revive keeps the speed); `RunConfig.openingFor(i)` = 118 at hoop 0 (also with Big Hoops: `RunDirector._bigMult`), then `curve_opening` (PRD-2.4 §1: 118 at hoops 1–2, 66 from hoop 100; rides and comets use it too, §2); `RunConfig.secondsForHoops(from, n)` turns hoop counts into runClock | §14.4, §0 item 3 |
| Squeeze | `RunDirector.rollSqueezeAt(now, {hoop, first})` / `rollSqueezeHold({hoop})`: hoop counts (`squeeze_first` / `_hold` / `_gap`) at the cruise of those hoops | §14.4 |
| Comet | `_cometAllowed` mode 0: from `ride_comet_from`, ≥ `ride_comet_spacing` after the last comet, then a `ride_comet_chance` roll on the layout stream (only for an otherwise eligible normal hoop); a planned comet turned plain is owed (no roll); `cometAt` = the first hoop it may come | §14.5 |
| Feather / piece | `RunDirector(featherAllowed:, pieceAllowed:)` (the controller: `!GatesConfig.shownLastRun(storage.last…Run, gamesPlayed)`, or forced); both roll → the feather wins | §14.2 |
| Gates | `RunController` filters `enabled` through `GatesConfig.filter(all, gamesPlayed, keep: forced)` unless `RunSetup.ignoreGates` (`RunDebugState.ignoreGates`: the test harness; FS_E2E and FS_SOAK builds) | §14.6 |
| Scoring | Perfect = no rim touch (`RunController._pass`; `PerfectConfig` removed). `RunContext.earn` / `addScore` no longer double anything; `ScoringFeature.chickBonus(state)` (+`point_chick`) is added to the pass's points; `EggFeature.pointsAdded` → `chick_lost {points_added}` | §14.3 |
| Revive | `ReviveConfig.coinLadder` (`revive_ladder`); `ReviveLadder.eligible` is false once `coinRevives ≥ ladder.length` | §14.2 |
| Analytics | `run_end` + `coins_per_hoop`, `perfect_rate`, `opening_end`, `speed_end`, `games_played`; `Wallet(onSpent:)` → `coins_spent {amount, reason}` (`Wallet.spendReason`: `item:*` → `skin`) | §14.8 |
| Portal rides | `RunDirector.portalDropped(ride)`: a portal planned / spawned ahead and cleared by a ride (`RunSpawner.clearAhead` / `clearAll`) does not count as the last ride | §3.12 (kept) |
| Debug | The **TUNING >** page is removed (audit 17); its two run-stats rows are on the debug panel main page. RUN DEBUG **Runs: N (+5 / 0)**; `FlappySpikesGame.debugAvailable` includes `kTester` (`--dart-define=FS_TESTER=true`, `services/tester.dart`) | §15.4, §14.6 |
| Autopilot | `_farFromPlane` hands a chase back earlier: + abs(bird y − hoop y) ÷ 300 pt/s, and a moving ring's sideways reach (`_reachX`) | gate, §14.4 |


## PRD-2.3 WP-SKINS contract changes (§19, 2026-10-13)

- **Catalogue:** every layer has 30 entries (`kCollectibleTotal` 148); the 60
  new items are mixed into the grid by rarity; `kNewInUpdate` is the 2.3 list
  (60 keys, the showpieces Sunburst, Disco ball, Aurora, Supernova first; the
  Shop's `featuredItemFor` reads it). No new storage key.
- **Art:** the new painters are 1:1 ports of `design/skins_v23/parts/*.js`
  in `lib/skins/art/{hat,gear,hoop}_art_v23.dart` and `trail_v23.dart`,
  dispatched from the existing masters (`paintHat`, `paintGearBack/Front`,
  `HoopPainter.paintHalf`, `TrailEmitter`) so every surface (tiles, preview,
  Home, run, results, share card, versus) still has one master per layer.
  They draw through `Ctx2D` (`ctx2d.dart`), a Canvas2D-shaped facade with a
  pooled path set, one reused `Paint` and a keyed gradient cache.
  `Ctx2D.glowLayer` draws many same-blur canvas shadows as one blurred
  layer (Aurora hoop: 22 segment glows per half → 1 blur; Pixel frame budget).
- `TrailEmitter.paint` takes an optional `head` (the Supernova core glow;
  defaults to the last emit point while emitting). `TrailEmitter.ids` /
  `HoopPainter.ids` / `HatArt.ids` / `GearArt.ids` are the full grid order.
- `LookPainter.extentOf` knows the new hats (`hatRise`), the gear that floats
  above the head (`gearRise`, new) and below the body (`gearDrop`).
- `BirdShape.hasBl` (JS `s.bl != null`) anchors stern gear on the duck.
- Port check: `tool/skins_port/render_js.mjs` + `test/skins/p23_skins_port_test.dart`
  → `docs/p23/SKINS_PORT.png` (page left, Flutter right, H1…T15).
## PRD-2.3 WP-VS contract changes (§25 then §21, 2026-10-13)

**§25 Versus: never a silent solo.**
- `matcher.dart` (mirrored in `functions/src/matching.ts`, shared fixture
  `test/fixtures/versus_matching.json`): "already met" is a preference. The
  service keeps an ordered met list (`_met`, oldest first, cap
  `VersusConfig.metCap` = 100; filled at `takeOpponent`). `matchCandidates`
  prefers unmet runs (tiers `level`, `any`), else the run met longest ago
  (tier `rematch`), else `solo` (only own runs). `hasUsableOpponent` counts
  met runs; `hasFreshOpponent` is the unmet test. `searchPools` reads in
  rounds of `VersusConfig.shards` documents in parallel, stops after the first
  round holding an unmet run, else returns the document of the run met longest
  ago; `onRead` reports every read as it is issued (a `timeout` has its real
  count). Per-read time box `VersusConfig.readTimeout` (4 s).
- `VersusService`: `onRunStart()` starts the search for the next opponent
  (the Home prefetch stays as a backup). New members: `holdsOpponent`,
  `loadingIntro` (false for `NoopVersusService` and, by default,
  `FakeVersusService`: the 2.2 solo START without intro), and
  `searchForStart()` (waits for the running search or starts one; completes
  false at once when this Home visit's search already ended `no_rival`).
- `FlappySpikesGame._startRun`: in VERSUS with nothing held and
  `loadingIntro`, the VS intro is the loading screen: `VersusIntro(opponent:
  null)` cycles fillers at the base interval while `searchForStart` runs, up
  to `VersusConfig.introWait` (3 s) after START; `VersusIntro.resolve(o)`
  lands smoothly on the found opponent, or (null / 3 s) on the NO RIVAL FOUND
  plate (grey person icon, no emblem) followed by the banner master's FLY SOLO
  (`VersusConfig.noRivalText` / `flySoloText`). A late result stays held for
  the next START. Analytics: `versus_solo {reason, reads, level, waited_ms}`
  and `versus_intro_wait {waited_ms, found}` whenever the reel waited.
- **Hook for §10 (waiting start):** `FlappySpikesGame.onVersusIntroFinished`
  (`void Function({required bool versus})?`) is called once the VS intro's
  white fade covers the screen, right before the run starts; `versus` is
  false when the intro landed on NO RIVAL FOUND (a solo run). WP-WAIT (P23-10)
  hooks its waiting state here: right after that call the game runs
  `_versusIntroFinishedForWaiting()`, which clears `_introPending` and calls
  `RunController.beginWaiting()` on a run that already exists; while the
  intro plays (`_introPending`) `_startGame` never starts the §10.3b
  reminder count itself. Today the run is built just after the intro, so its
  count starts in `_startGame`, after the VS screen either way.

**§21 Versus: names, pictures and looks.**
- One name rule: `lib/run/hud/fit_name.dart` `fitName(name, maxWidth, size,
  measure)` (shrink to `HudConfig.nameMinScale` = 70 %, then cut with "…");
  `HudText.name(...)` wraps it. Used by the intro plates (room ends before the
  emblem: `VersusIntroPlate.nameRoom`), the HUD `NameChip`, the results
  columns (`ResultsConfig.nameRoomVersus/Solo`) and the share card's name tag.
- (Superseded by WP-AV, see the end of this file: no pictures, sticker avatars.)
  Avatar squares: `lib/components/versus_avatar.dart` `VersusAvatar.paintBird`
  is the single fallback painter (the `LookPainter` art): the opponent's bird
  in their look on their tint while the picture loads / fails / is missing;
  your own bird on `VersusAvatar.ownBackdrop` when you have no Play Games
  picture. The grey person icon only on the NO RIVAL FOUND plate.
- Pictures: `VersusBackend.uploadAvatar(jpeg)` → Firebase Storage
  `avatars/{uid}.jpg` (`storage.rules`: public read, owner-only write/delete,
  `image/*` ≤ 30 KB); `encodeVersusAvatar` (`lib/services/avatar_upload.dart`,
  package `image`) makes the 96 × 96 JPEG; the service uploads once per
  (uid, picture hash) and puts the URL in `VersusProfile.avatarUrl` → the
  run's `avatar`. `deleteMyData` also deletes `avatars/{uid}.jpg`
  (`functions/src/avatars.ts`, bucket from `FIREBASE_CONFIG.storageBucket`,
  else `<project>.firebasestorage.app`).
- Self-match guard: runs carry `pg` (12th `RunEntry` key; SHA-256 hex of the
  Play Games id + the app salt, '' without Play Games). The salt comes from
  Remote Config parameter `versus_pg_salt` (`PgSaltSource`,
  `RemoteConfigPgSalt`; tests use `FixedPgSalt`), never from the repo.
  `isOtherPlayer` skips my uid and, when I have a pg, any run with my pg.
  `firestore.rules` accept a 12th key `pg` ('' or 64 lowercase hex);
  `timeline.ts` `validPg` re-checks it; `pools.ts` copies it.
- Account switch: `VersusBackend.link(identity, beforeSwitch:)` runs
  `beforeSwitch` on `credential-already-in-use` while still signed in as the
  old anonymous uid; the service passes `deleteOnline()` (the `deleteMyData`
  callable without sign-out) and clears `versusAvatar`. A failure is logged and
  the switch goes on.
- PRD-2.3.1 §2 (P231-B): the switch uses a FRESH server auth code
  (`firebaseCredential(fresh: true)` → `forceRefreshToken`), never the code the
  link used up; `beforeSwitch` runs only once that fresh credential is in hand
  (none → nothing deleted, the guest stays, `switch_failed no_fresh_code`). A
  failed `signInWithCredential` signs in a new anonymous user at once
  (`fallback_anon`): `link()` never ends on the deleted guest. A link that
  meets `invalid-credential` (a cached, used code on an in-process retry) is
  tried once more with a fresh code. `start()` reloads a persisted user and
  replaces one the server no longer knows (`deadUserCodes`) by a new guest;
  `classify(e, liveUser:)` maps a `permission-denied` without a live user to
  `auth`, and `prefetch` then re-authenticates (`backend.start()`) and searches
  once more. A failed switch is retried on the next launch and on resume.

## 27. PRD-2.3 WP-ADS contract notes (as built, 2026-10-13)

- **Ad grace (§18):** `lib/menu/ad_grace.dart`. `AdGrace.active({runs, playtimeSeconds})`
  is the one rule (`runs < ads_grace_runs && playtime < ads_grace_seconds`); `interstitialSkipReason()`
  returns `InterstitialSkip.newPlayer` while it holds, and `_onFirstFlight` preloads only when it does not
  hold for the run that starts. `PlaytimeCounter` (same file) is driven from `FlappySpikesGame.update` with the
  real frame time (≤ 1 s) only while resumed and no full-screen ad is up; it flushes on background and at run end,
  and writes every 10 s on the menus only (`mayWrite`; SPEC DEVIATION §18.3).
- **Rating prompt (§23):** `lib/services/rating_prompt.dart`. `RatingPrompt` (no backend = never available,
  every call try/caught) is injected through `FlappySpikesGame(rating:)`; `main.dart` builds it with
  `InAppReviewBackend` on the mobile products and calls `prepare()` after `runApp`. The game decides with
  `RatingRules.trigger` at `endRun`, asks in `_checkRatingPrompt(dt)` (the results page's `settled` getter,
  no modal, no debug panel, no ad) and writes `lastRatingRequestAt` before `request()`. The interstitial reads
  `_ratingRequestedThisRun` (skip reason `rating`) and the Home arrival skips the No-Ads check on it.
- **No-Ads after a run (§24):** `_arriveHome()` queues the offer through `_queueNoAdsOffer(check:, stale:)`
  (shared with the session start) **after the arrival's storage reload** (`_homeReload`): `GameStorage.load()`
  reverts in-memory state with what the preferences hold, so a reload that lands after a show was recorded
  would undo it. The popup's `noads_popup_shown` carries `check: session | after_run`.
- **Shop / Skins lock (§26):** `MenuScreen(lock: [line1, line2])` (null = open). A locked screen's
  `isActive()` is false, so every content control (buttons, tiles, tabs, scroll) stops hit-testing, and
  `MenuLockOverlay` (`lib/components/menu_lock_overlay.dart`) sits above the content and swallows taps; the back
  button keeps `isBackActive()` and a higher priority. `MenuState.locked` (`bestScore < Config.menuUnlockBest`)
  is the one check; the revive shop opens with `allowLock: false`. The Home tiles show `MenuTile.locked`
  (a gold lock badge in the NEW tag's corner) and no NEW tag while locked.
- **Tuning:** `ads_*`, `rate_*`, `noads_*` and `ui_unlock_best` are read through the `Config` getters
  (`interstitialMinGap`, `adsGraceRuns`, `adsGraceSeconds`, `ratingMinRuns`, `ratingCooldown`,
  `ratingDelaySeconds`, `noAdsPopupMinGap`, `noAdsPopupMaxPerDay`, `noAdsPopupFallback`, `menuUnlockBest`).


## PRD-2.4 §3 WP-W1 contract notes — `lib/run/backdrop/` (as built, 2026-10-16)

| File | Responsibility | API |
|---|---|---|
| `run/backdrop/run_backdrop.dart` | The run background component, one per run, world priority `RunLayer.runBackdrop` (−999, over the flat `RunLayer.backdrop` rect). Added by `FlappySpikesGame._startRun`; removes itself when `game.run` is another run; fades in 0.3 s at run open, out under `postRunPageUp` | `RunBackdrop(run)`; `static RunBackdrop? of(game)`; `double get worldDistance`; `double opacity`; `BackdropRideHook? rideHook`; `String? get ridePhase` |
| `run/backdrop/backdrop_world.dart` | `world()` / `drawGroup()` / `vmove()` of the prototype; first-loop rule (no Homecoming below w 6 000); `BackdropPainter` (base fill, tall-screen anchoring: the 568 design on the screen bottom, one colour-filter `saveLayer`, ride cover clip) | `BackdropWorld.sceneAt(w)`, `seamAt(w)`, `paint(Ctx)`, `group(c, env, bands, dy)`; `BackdropPainter.paint(canvas, cam:, t:, viewHeight:, bg:, fg:, opacity:)` |
| `run/backdrop/world_distance.dart` | camera → world distance (300 per hoop; seam k landed on hoop 40·k; continuous, monotonic; holds while the seam hoop is unplanned) | `WorldDistance.start/advance`, `HoopAnchors` |
| `run/backdrop/backdrop_tables.dart` | `kScenes` (10), `kSeams` (10), one file each under `scenes/` and `seams/` | — |
| `run/backdrop/ride_hook.dart` | WP-R's hook (§3.5) | `BackdropRideHook.bandOffset(band)`, `scroll(dc)`, `cover(path, viewHeight)`, `hidden` (scene covers all: not drawn), `sideReach(band)` (draw wider) |
| `run/rides/portal_handover.dart` | WP-R: the hook a `PortalRide` installs (start) / removes (finish, abort); `step()` each frame, `onLaunch()` re-syncs the world while a themed scene covers it | `PortalHandover(ride)`, `offsetOf(band)`, `progress`, `tau`, `static softY(y)`, `rate` |
| `run/rides/ride_reveal.dart` | WP-R: `REVEAL` table, `sceneClip` and `sceneEdge` of `ride_landings.html` (shared by the ride's clip and the background's cover) | `RideReveal.of(id)`, `progress(τ)`, `remaining(band, τ)`, `sceneClip(path, id, p, t, w, h)`, `paintEdge(canvas, id, p, t, w, h)` |
| `run/config/handover_config.dart` | WP-R knobs (§3.5) | `HandoverConfig` |
| `run/backdrop/backdrop_ctx.dart`, `backdrop_helpers.dart`, `backdrop_math.dart`, `backdrop_palette.dart`, `seams/water.dart` | canvas-2D facade, the prototype's helpers, `palMatrix` | see `lib/run/backdrop/README.md` |

Scenes 4–10 and seams 3–6 are stubs (W2: 4–7 + 3–6; W3: 8–10 + 7–10 + the loop); each builder edits only its own
scene / seam files. Contract and the pacing math: `lib/run/backdrop/README.md`.

## WP-AV sticker avatars (2026-10-17)

- **One master:** `lib/components/sticker_avatar.dart` `StickerAvatars` (game `avatars`, built with the
  physical px per world point) is the only painter of a player picture: `paint(canvas, rect, look, mirror:,
  opacity:)` blits `image(look, side)`, rendered once per (bird, gear, hat, px) by `render` /
  `paintSticker` (design C of `avatar_design/src.html`: star blob, 16° tilt, white edge from 20 stamps of
  the look through a `srcIn` white layer, blurred black shadow) with `LookPainter.paint(t: .6)`; LRU of 16
  images (`dispose` on eviction). `normalise` = the per-layer catalogue fallback; `tintOf` = `palette()`.
  Callers: `VersusIntroPlate.render` (your plate and the opponent's once landed; the person glyph during
  filler ticks and on NO RIVAL FOUND), `VersusBar.render`, `ResultsPlayerColumn.render` (also solo).
  Removed: `VersusAvatar`, `AvatarImages` / `AvatarSource` / `HttpAvatarSource`, `avatar_upload.dart`,
  `VersusBackend.uploadAvatar` / `photoUrl`, `VersusAuth.photoUrl`, `PlatformPlayer.displayName` /
  `iconImage`, `VersusProfile.avatarUrl` / `avatarImage`, `OpponentRun.avatarUrl`, `RunEntry.avatar`,
  `PlayerFields.avatar`, `Config.avatarDecodePoints` / `avatarCacheMax`, the `VersusConfig.avatar*`
  knobs, the `firebase_storage` and `image` packages.
- **Names:** `VersusProfile.name` is always `storage.versusNickname` (the platform player only drives the
  link and `pg`).
- **Backend:** `functions/src/avatars.ts`, `sweepStaleAvatars` and the Storage deletes are gone;
  `storage.rules` deny all. `schema.ts` `validLook` / `LOOK_ID_RE` (used by `timeline.ts` `validDisplay`);
  `firestore.rules` `isId`. One-off `functions/scripts/backfill_avatars.ts` (`--dry-run` / `--run`,
  pure parts in `backfill_lib.ts`; both removed in audit 17 after the run, see git history): random bird / gear / hat (40 % none) + generated name for every player
  doc and pool entry (one identity per uid), `avatar: ''`, platform-name fields dropped, every object under
  `avatars/` deleted.


## WP-TAB contract notes — tablets widen the world (as built, 2026-10-17)

The playfield is `game.viewWidth` × `game.viewHeight`: 320 × (320 / aspect, clamped [568, 730]) on phones, 568 ×
(568 × aspect, ≤ 426) on wider screens (`Config.viewWidthFor`, `Config.maxViewWidth`). `game.extraWidth` = width − 320
(0 on phones: every path below is then the old one, bit for bit).

| Piece | Contract |
|---|---|
| Camera | `PlayfieldViewport` resolution `(viewWidth, visible)`; the viewfinder rests at `game.cameraBase` = (−extra / 2, 0), so world x 0..320 (menus) is centred. Shakes move the viewfinder relative to it; code that cancels a shake uses `game.cameraShake` (viewfinder − base), never the raw position. |
| Run column | `RunScaledWorld.columnShift` = extra / 2: world children marked as run content (`RunScaledWorld.inRunColumn(c)` / `world.addRun(c)`; every `RunTrack` automatically) are drawn that much further right. Run coordinates are unchanged (bird x 70, right edge 320): the look-ahead is the phone's; the screen's left edge in run x is `RunState.viewLeft` = −extra. **Any new run component added straight to the world must use `addRun`**, else it draws extra / 2 too far left on tablets. Hit testing is unaffected (run content takes no taps). |
| Full-screen fills | `game.bleedRect(h)` / `bleedRectFor(component, h)` (x −extra .. 320 + extra: covers the screen from the centred column, the run column and the HUD); `game.runScreenRect(h)` (−extra .. 320) for run-column effects that need the true screen edges (edge glows, flashes). Spike strips paint `left: −extra` with the tooth phase kept. |
| Bands / centred overlays | `RunBanner` bands span −extra .. 320 + extra (every banner: run banners, FEVER, the VS intro's FLY SOLO / MATCH FOUND!, the first-run warning bands). The run's `BannerHost` sits at x −extra / 2 in its layer and the first-run hint draws its message (TAP TO FLAP! banner, hand, ripples, warning bands) `centreShift` = −extra / 2 left, so both are centred on the screen; the hint's flap path stays on the run column (bird → hoop 0). |
| HUD / screens | `RunHud` at viewport x = extra (on the run column); `PauseScreen`, `ReviveScreen` at viewport x = extra / 2 (centred); world pages (results, bonus, VS intro, settings, popups) are centred by the camera. |
| Culling | `RunSpawner._cull`, the saw / FEVER / Lucky Spin on-screen tests, the Black Hole lens and `DeathTumble.viewLeft` use the real left edge. Spawning and planning (right edge) are unchanged. |
| Backdrop / rides | `BackdropPainter.paint(left: −extra)` draws `xl` from the left edge; `RideView.left` / `full` / `wrapX`, `RideReveal.sceneClip` / `paintEdge(left:)`, the theme culls and fills, `CometSpeedLines.extraLeft`. |
| Banner strip | `bannerStripHeight` uses the screen's full width in game points (`dp × screenWidthPoints / widthDp`); `screenHeight` is at least 568. |

Tests: `test/p24/tab_wide_world_test.dart` (sizes, geometry per shape, autopilot at 3:4, every ride + comet edge
watch, backdrop gap check at every seam), `test/p24/tab_screens_evidence_test.dart` (PNG evidence).

## 2.6 wave 1 module map (WP-A–D)

| Module | Owner and contract | Binding tests |
|---|---|---|
| `lib/run/run_events.dart`, `lib/run/items/analytics_router.dart`, `lib/services/analytics_buckets.dart` | WP-A typed run events, one analytics router, stable hoop/game buckets; no identity in payloads | `test/p26/analytics/run_events_test.dart`, `analytics_names_test.dart`, `analytics_buckets_test.dart`, `user_props_test.dart` |
| `lib/services/ftue_tracker.dart` | WP-A durable once-only FTUE steps and flush | `test/p26/analytics/ftue_tracker_test.dart` |
| `lib/game/home_moments.dart` | WP-A Home moment arbitration and priority | `test/p26/home/home_moments_test.dart` |
| `lib/run/showcase/`, `lib/run/config/showcase_config.dart` | WP-B frozen START script, progress/attempt persistence, safety net and pass-driven completion; director step 0 overlays after normal draws | `test/p26/showcase/plan_tables_test.dart`, `plan_state_test.dart`, `director_script_test.dart`, `director_spawn_test.dart`, `starters_test.dart`, `free_revive_test.dart`, `upload_rules_test.dart`, `bot_highlights_test.dart` |
| `lib/run/config/gates_config.dart` | WP-C lifetime saw/squeeze filters; other introductions follow hoop index | `test/p26/gates/unlocks_test.dart` |
| `lib/run/config/layout_config.dart`, `lib/run/director/layout_sampler.dart` | WP-D centre/Δy, tilt magnitude/sign, motion rows and rendered-angle caps; all layout draws seeded | `test/p26/curve/layout_d2_test.dart`, `spawn_tables_d2_test.dart`, `curve_ceiling_test.dart`, `same_rules_test.dart` |
| `lib/run/director/hazard_budget.dart` | WP-D four-slot ledger, forced accounting, deterministic downgrade; director records the final plan and reserves spring landings | `test/p26/curve/hazard_budget_test.dart`, `curve_ceiling_test.dart` |
| `lib/run/director/calm_schedule.dart` | WP-D periodic/event recovery, spacing and warning exclusion; director produces calm geometry | `test/p26/curve/calm_schedule_test.dart`, `curve_ceiling_test.dart` |
| `lib/run/director/headline_window.dart` | WP-D shared eight-hoop headline arbitration and bounded waits | `test/p26/curve/headline_window_test.dart` |
| `lib/run/director/formations.dart` | WP-D six seeded formation templates; director wires cadence, interruptions, final budget and mix chapters | `test/p26/curve/formations_test.dart`, `formations_wire_schedule_test.dart`, `formations_wire_recovery_test.dart`, `formations_wire_autopilot_test.dart` |
| `lib/run/debug/human_bot.dart`, `lib/run/debug/autopilot.dart` | Test/debug flight drivers; no release tuning dependency | `test/autopilot_test.dart` (12-hoop baseline, 150/250 ceiling, ordinary human-noise median) |

The integration sweep includes normal gap draws and final hazard downgrades,
200 seeds × 568/711/730 × 400 slots, both open and squeeze contexts. Fairness
uses ordinary `RunSetup` → `RunController` construction with gates enabled,
equal met-elements and no showcase or debug assistance. Currently only baked
arm 0 exists; an arm selector must extend the fairness matrix when introduced.
The height equality, squeeze-budget and human-noise gates remain unresolved;
see the WP-D validation note in SPEC.md. Timeline encoding and maximum-score
protection retain their existing tests without edits.
