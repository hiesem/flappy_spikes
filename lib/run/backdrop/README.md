# `lib/run/backdrop/` — the lively run background (PRD-2.4 §3)

A 1:1 port of the canvas drawing in `docs/p24/endless_vertical.html` (the spec).
Only the background: the bird, hoops, spikes, HUD and rides are untouched.

## Files

| File | What |
|---|---|
| `backdrop_math.dart` | constants (`kHoopsPerScene` 20, `kE` 6 000, `kNST` 10, `kVWIN` 1 500, `kLinger` 1 750, `kANCH` 160, 320 × 568 design), `hash`, `Rng` (`rng`), `smooth`, `smoother`, `modD`, `jsRound` |
| `backdrop_ctx.dart` | `Ctx`: a canvas-2D facade (`fillStyle`, `save/restore`, `beginPath`, `arc`, `ellipse`, `roundRect`, `fill/stroke/clip`, gradients, dashes) + the world state (`cam`, `t`, `env`, `xl/xr`, `yTop`, `vert`, `fold`, `cut`) + `strip()` picture cache |
| `backdrop_helpers.dart` | the prototype's shared helpers: `each`, `wraps`, `ridgeY/ridgePath/ridge/ridgeAt`, `gfillSink/gfillCut`, `flatCloud`, `pill`, `vgrad`, `mark`, `early`, `presence` (≡ 1: no side-by-side seams) |
| `backdrop_scene.dart` | `Band` (sky, far, mid, near, front) and `BackdropScene` |
| `scenes/sNN_*.dart` | one painter per scene (all 10 ported) |
| `seams/seam.dart` | `FloorSeam` (seams 1–6: `dir`, `yF`, `thickness`, `hang`, `travel`, `slab`, `piece`, `fold`), `OlderSeam` (7–10: `move`), `SeamFrame` (`S`: `u`, `q`, `sT`, `sB`, `oA`, `oB`, `hx`) |
| `seams/seamNN_*.dart` | one file per seam (all 10 ported) |
| `seams/water.dart` | `ek`/`LAG`, `lift`, `wave`, `waterline`, `sea`, `rays`, `paperBoat` |
| `backdrop_tables.dart` | `kScenes`, `kSeams` — already list every file; do not edit to fill a scene |
| `backdrop_world.dart` | `BackdropWorld` (`world()`, `drawGroup()`, `vmove()`, first-loop rule) and `BackdropPainter` (base fill, tall anchoring, colour filter, ride clip) |
| `backdrop_palette.dart` | `palMatrix(bg, fg)` |
| `world_distance.dart` | camera → world distance mapping |
| `ride_hook.dart` | `BackdropRideHook` for WP-R |
| `run_backdrop.dart` | the Flame component (`RunLayer.runBackdrop` −999), one per run |

## Contract for scene / seam builders (WP-W2, WP-W3)

- Fill **only your own files**: `scenes/s04…s10_*.dart`, `seams/seam03…10_*.dart`. The tables already reference them.
- A scene's `draw(c, band)` paints one band in design coordinates (320 × 568). Port the JS literally:
  `c.fillStyle = const Color(0xFF…)`, `c.beginPath()…c.fill()`, `c.circ(x, y, r)` for `circ(c, …)`,
  `each(c, off, spacing, seed, (x, r, k) {…})` (call `r()` in the same order as the JS), `wraps(c, …, (x) {…})`,
  `mark(c, dx)`, `early(c, x, f, span)`. `F(f)` / `pa()` / `presence()` are 1 and can be dropped.
- The screen top is `c.yTop` (0 at 568, negative on taller views; the sky grows above). Use it where the JS means
  "the top of the screen" (`0`, `-20`, `-400` in visibility tests and clips); keep `kVH` (568) for the bottom.
- Taller views: floor moves get `travel + c.ext`, older moves `lift(c)` / `liftNest(c)` (already done).
- Static bands (no `t`) may use `c.strip(key, off, (off) {…})` (unique key per scene band, e.g. 401, 402…).
- Seam 6's `fold` is applied to the arriving scene as `c.fold` (Origami reads it as `G.fold`).
- Tests: add your scene/seam numbers to `portedScenes` / `portedSeams` in `test/p24/s3_3_smoke_test.dart` and to
  `seams` in `test/p24/s3_3_no_jump_test.dart` (helpers: `test/p24/backdrop_harness.dart`, `expectNoJump`,
  `seamEdges()`, `renderBackdrop`, `saveEvidence`).

## World distance (pacing, PRD §3.3)

The prototype's `cam` is 300 pt per hoop; seam k sits at `cam = 6 000·k` (see "Scene length" below). The game's hoop spacing is not fixed
(310, trains 422, comets, rides), so `WorldDistance` integrates the camera instead of scaling it:

- each frame the screen centre `c = camX + 160` moves by `dc` and the world by `r·dc`,
  `r = (W* − w) / (X* − c)`: W* = 300·n* for the next seam hoop n* (a multiple of 20), X* its plane (real once
  planned, else the director's next slot + 310 per slot, never nearer than the right screen edge);
- `r` is clamped to [0.1, 2.5]: continuous and monotonic; between seams r ≈ 300/310 (the prototype parallax);
- when hoop n*'s plane reaches the screen centre, `w = W*` exactly (seam k centred on hoop 20·k);
- while n* is not planned (a portal ride holds the spawner), the world never comes nearer than
  `300·(slots to plan) + 100` to W*: it holds still under the ride and plays the seam on its hoop afterwards;
- the run starts with `w = 300·i₀ − (x₀ − c)·300/310` (first hoop i₀ at x₀); a knock-back moves it back a little.
- First loop: `w < 3 000` draws pure Nest Canopy (no Homecoming, no leftovers); from hoop 200 the loop plays.

## Scene length (owner 2026-10-19, 2.4.0+38)

A scene lasts `kHoopsPerScene` = 20 hoops (the prototype: 40), at the 1× scroll and clock of 2.4.0 (36). Everything
measured in the stage is scaled with it, so a scene is the prototype's composition in half the hoops:
`kE = 20 · kPerHoop` = 6 000, the seam window `kVWIN = kE / 4` = 1 500 (5 hoops), `kLinger = kE · 3 500 / 12 000`
= 1 750. A seam (window + linger, ±2 500) ends 1 000 (≈ 3 hoops) before the next one starts; seam k is centred on
hoop 20·k; the loop of 10 scenes is 200 hoops. Set pieces run on the window's progress `u` (cuckoo, gumballs,
book, crane), so they play complete in the shorter window. A landmark (`mark`) sweeps 480 pt per stage as in the
prototype (0.08× instead of 0.04×), so it still enters and leaves inside its scene. The layers' own parallax and
the ambient clock are unchanged. Colour stages stay at 10 hoops (`stageForHoops`, not tied to the scene).
Tests: `test/p24/scene_length_test.dart`.

## Ride hook (WP-R, PRD §3.5)

`RunBackdrop.of(game)?.rideHook = myHook` during the ride, `null` after (`PortalRide` does this with
`lib/run/rides/portal_handover.dart`). `BackdropRideHook` has no-op defaults: `bandOffset(band)` (dx, dy per band,
also applied to slabs and pieces; dy < −1 also stretches the band's row at design y 608 down to the screen
bottom, so a lifted ground never ends), `sideReach(band)` (constant sideways travel: the band is drawn that much
wider), `scroll(dc)` (override the world advance; after an override `WorldDistance` re-syncs to the hoop schedule
at ≥ 0.6× with the unplanned-hoop cap off, until it is back on schedule), `cover(path, viewHeight)` (the screen area
the ride scene still covers; the background is not drawn there) and `hidden` (the ride scene covers everything: the
background is not drawn). `WorldDistance.resync(w)` sets the world while it is not seen (never across the next seam
hoop or back into the last seam). The ride phase is `RunBackdrop.ridePhase` (`RunState.ride?.phase`).

## Colour and frame

One `saveLayer` per frame with `ColorFilter.matrix(palMatrix(stageBackground, foregroundColor))` (the game's own
crossfaded stage colours) and the fade opacity; skipped at stage 0 when fully shown.

## Scenes 8–10, seams 7–10 (WP-W3)

- `scenes/s08_sea.dart` also holds the shared bubbles (`kBubbles`, `bubbles()`; Dreamland draws the sea's last ones).
- `seams/water.dart` `sea()` holds its middle colour over the view's extra height above y 0, so on taller views the
  dive ends and the emerge starts exactly on the Underwater sky's gradient; the Underwater rays start at y 0 (as at 568).
- Seam 7 start fix (PRD §3.3 known issue): the sea, its rays, waterline and boats fade in over the first 5 % of the
  move's ease (`DiveSeam.fadeIn`), instead of appearing at once over the paper river.
- Static bands use strip keys 801–803, 901–902, 1001–1002.
