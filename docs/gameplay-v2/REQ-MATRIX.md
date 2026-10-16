# PRD-2 requirement matrix (sign-off checklist)

One row per requirement of `PRD-2-gameplay.md`. Owners follow [ARCH.md §9](ARCH.md#9-wp-boundaries-and-file-ownership).
Each WP fills **Test ID(s)** (`test file::test name`, or `integration_test/... ::name`, or `shot: <png>` for visual
checks) and sets **Status** (`todo` → `done` / `n/a` + reason) for its rows in the same commit as the work.

WPs: 0b scaffolding · 0c shared parts (recommended, ARCH §9.3) · 1a hoops · 1b layout+director wiring · 2a lives /
shield / Big Hoops · 2b streak · 2c rumble · 2d HUD+pause+revive · 2e results · 3a comet · 3b portal · 3c bullseye /
train / spring / spin / FEVER · 3d saw / switch / pairs · 3e star trail / egg / piggy / jar · 3f hourglass / mini /
frenzy · 3g squeeze · 3h sound pack · 4a feathers / balloon / puzzle · 4b reminders · 4c persistence + delete my data ·
5a versus backend · 5b versus client · 6 final e2e + release.

## 3.0.1 Core tuning

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.0.1-1 | Cruise scroll 150 pt/s, rising +3.5 % per minute of `runClock` | 3.0.1 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.0.1 … reaches the bird ≈ 2.1 s later; test/run/physics/s3_0_4_rim_test.dart::§3.0.4 4 … recovers toward cruise; test/scrolling_test.dart::PRD-2 §3.0.1 the world scrolls … at the cruise speed | done |
| R-3.0.1-2 | Hoop spacing constant 310 pt (never shortened for difficulty) | 3.0.1 | 1a | test/run/flow/s3_0_1_hoop_spawner_test.dart::§3.0.1 / §3.0.2 spawned hoops: one spacing apart …; test/run/flow/s3_0_1_hoop_spawner_test.dart::stalled frames keep hoops one spacing apart | done |
| R-3.0.1-3 | First hoop spawns 60 pt past the right edge at the first tap, at exact vertical centre, scrolls in, reaches the bird ≈ 2.1 s after the tap; nothing pops into view | 3.0.1, 3.1 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.0.1 the first hoop spawns 60 pt past the right edge …; test/run/flow/s3_0_1_hoop_spawner_test.dart::… scrolled in from ≥ 60 pt past the edge | done |
| R-3.0.1-4 | Gravity 1250 pt/s²; flap sets vy to −370 (rise ≈ 55 pt) | 3.0.1 | 1a | test/flap_physics_test.dart (45–65 pt rise band, unchanged); test/config_test.dart | done |
| R-3.0.1-5 | Max fall speed 650 pt/s | 3.0.1 | 1a | test/flap_physics_test.dart::terminal velocity; test/config_test.dart::§3.0.1 terminal velocity caps the fall speed at 650 pt/s | done |
| R-3.0.1-6 | Bird screen x 70, collider circle r 14.75 (Mini × 0.52) | 3.0.1 | 1a | test/config_test.dart::§3.0.1 bird sits at x = 70; test/bird_look_test.dart (radius 14.75) | done (Mini × 0.52 via RunState.birdScale: 3f) |
| R-3.0.1-7 | Opening 118 pt at hoop 0, −0.32 % per hoop, floor 92 pt (78 %), by hoop index | 3.0.1 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.1-8 | Rim ends: two circles r 7, restitution 0.85 | 3.0.1, 3.0.4 | 1a | test/run/physics/s3_0_4_rim_test.dart::§3.0.4 1 two rim ends r 7 …; test/run/physics/s3_0_4_rim_test.dart::§3.0.4 2 head-on … restitution 0.85 | done |
| R-3.0.1-9 | Forward recovery 2000 pt/s² back to cruise after a knock-back | 3.0.1 | 1a | test/run/physics/s3_0_4_rim_test.dart::§3.0.4 4 after a knock-back the forward speed recovers …; test/run/flow/s3_1_hoop_flow_test.dart::§3.0.4 a rim touch bounces, the world jolts back … | done |
| R-3.0.1-10 | Hoops spawned during comet / portal rides are the curve size of their index (PRD-2.4 §2), upright, still | 3.0.1, 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.1-11 | **PRD-2.2 §13:** score = points: 1 per non-perfect pass, max(2, streak) per perfect pass, coin bonuses in points, ×2 with the chick, +5 from a pair SCORE gift (test/p22/s13_points_test.dart) | 3.0.1 | 1a | test/collision_test.dart::§3.1 crossing the plane inside the opening scores exactly once; test/run/hoops/s3_21_pair_test.dart::§3.21 the score gift does what it says | done |
| R-3.0.1-12 | Colour stage = floor(hoopsPassed / 10) mod 11 over the existing 11 palettes (gold last); replaces `stageOf(score)` | 3.0.1 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.0.1 the colour stage changes every 10 hoops passed …; test/color_state_test.dart | done |
| R-3.0.1-13 | Hoop index = slots spawned (train / pair = 1 slot), not reset by a revive; ramps use the index of the slot being spawned | 3.0.1 | 0b | test/run/flow/s3_0_run_core_flow_test.dart | done |
| R-3.0.1-14 | `runClock` runs in play and rides, stops in pause / revive offer / phoenix, slows with Hourglass; used by scroll ramp, squeeze, versus timeline, Big Hoops | 3.0.1 | 0b | test/run/flow/s3_0_run_core_flow_test.dart | done |
| R-3.0.1-15 | Screen heights 568–730: HUD row + score circle top-anchored, bottom buttons bottom-anchored, centred blocks keep their offset from centre (y − 355.5 at 711) | 3.0.1 | 0b (geometry), 2d / 2e / 4a / 5b (screens) | lib/run/run_geometry.dart (RunGeometry) | done (0b geometry); 2d HUD row top-anchored, revive / pause centred offsets; 4a bonus screen fits 568–730 (BonusRules.layoutFor); 2e / 5b screens pending |
| R-3.0.1-16 | Normal bird position (70, viewHeight / 2) wherever the PRD returns the bird "to its normal position" | 3.0.1 | 0b | test/run/flow/s3_0_run_core_flow_test.dart | done |
| R-3.0.1-17 | Every number of §3.0 is a `Config` knob with its PRD section; nothing hard-coded in components | 3.0 | all | | todo |

## 3.0.2 Hoop layout ramp

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.0.2-1 | Heights are fractions of the band between the tooth lines (623 pt at 711, 480 at 568) | 3.0.2 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.2-2 | Band table by hoop index (centre range, \|Δy\| median / p90 / max, tilt %, tilt weights, moving %) for 0–2, 3–9, 10–19, 20–34, 35–44, 45+ | 3.0.2 | 0b | test/run/director/s3_0_2_layout_ramp_test.dart | done |
| R-3.0.2-3 | Hoop 0 at exactly 0.50 | 3.0.2 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.2-4 | \|Δy\| sampling by linear quantile pieces (u < 0.5 / < 0.9 / else) × band | 3.0.2 | 0b | test/run/director/s3_0_3_director_test.dart; test/run/director/s3_0_2_layout_ramp_test.dart | done |
| R-3.0.2-5 | Direction flips vs the previous step with p 0.65; flip if outside the range; then clamp | 3.0.2 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.2-6 | Band rule: centre ≥ opening / 2 + 7 + 18 pt from each tooth line (saw: wider opening; pair: full height); squeezed band during a squeeze | 3.0.2 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.2-7 | The band's max replaces the old 140 pt max jump everywhere | 3.0.2 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.2-8 | Tilt and movement only on normal hoops; specials and the comet hoop upright and still | 3.0.2 | 0b / 1b | test/run/director/s3_0_3_director_test.dart; test/run/director/s3_0_2_layout_ramp_test.dart | done |
| R-3.0.2-9 | Tilt steps capped at 45° (60° folded into 45°) | 3.0.2 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.2-10 | Moving types: 20–44 rail 80 / swing 20; 45+ rail 50 / swing 15 / horizontal 10 / diagonal 10 / orbit 8 / rock 7 | 3.0.2 | 0b / 1b | test/run/director/s3_0_3_director_test.dart; test/run/director/s3_0_2_layout_ramp_test.dart | done |
| R-3.0.2-11 | No moving rings during a squeeze (tilted rings fine) | 3.0.2, 3.17 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.2-12 | Tables mirror `spawn_tables.json` (mirror test), with the PRD overrides | 3.0, 7 | 0b | test/run/config/tables_mirror_test.dart; test/run/director/s3_0_3_director_test.dart | done |

## 3.0.3 Run director

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.0.3-1 | Director decides each slot's kind and each gap's item when the slot spawns (just off-screen right) | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-2 | One seeded `layout` stream per run + separate `cosmetic` stream (visuals never change spawns); per-run seed | 3.0.3, 7 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-3 | Same seed → same slot / gap sequence (unit test) | 7 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-4 | Slot order 1: ride active → normal, the curve size of its index (PRD-2.4 §2), upright, still, no special, no gap item | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-5 | Slot order 2: first hoop after a revive is normal | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-6 | Slot order 3: portal at `portalAt` (first 25–50, then +40–60) when no squeeze is coming and the last comet hoop ≥ 10 back; waits otherwise | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-7 | Slot order 4: cooldown — next slot normal after a special (2 after train / spring / pair, 3 after portal) | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-8 | Slot order 5: special roll with the budget chance, weighted among eligible types (unlocked, min distance, allowed now) | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-9 | Slot order 6: comet hoop at `cometAt` (first 10–30, then +45–60) if still normal, no timed powerup, no squeeze window, portal ≥ 10 hoops away both ways | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-10 | Slot order 7: tilt and movement modifiers from 3.0.2 | 3.0.3 | 0b / 1b | test/run/director/s3_0_3_director_test.dart; test/run/director/s3_0_2_layout_ramp_test.dart; test/run/hoops/s3_11_moving_rings_test.dart | done |
| R-3.0.3-11 | Gap order 1: running piggy places 4 coins per gap (4 + 4 × 4 = 20); running jar places a swarm of 7; either fills the gap | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-12 | Gap order 2: fixed schedules heart (3, then +17–27; skipped while extra life active, schedule moves on), feather (once, 3–12), piece (once, 14–25); taken gap → next free gap | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-13 | Gap order 3: a switch ring's switch takes the gap before it; if taken, the switch ring becomes normal | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-14 | Gap order 4: optional item roll with the gap budget, weighted among eligible types | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-15 | Budget table (special / gap chance) for 0–4, 5–7, 8–19, 20–34, 35–49, 50+ | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-16 | Measured share check: specials 0 % at 0–7, ≈ 15 % at 8–19, ≈ 20 % at 20–49, ≈ 25 % from 50; ≈ 1 gap in 3 holds something (tolerance test over many seeds) | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-17 | Special-hoop table (from, weight, min since same, cooldown, not-allowed) for bullseye, train, spring, switch, pair, FEVER, Lucky Spin, saw (18 → 26 from 45), portal, comet | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-18 | Squeeze window (3 s before warning → walls open): only bullseye, FEVER and saw specials; no comet hoop (waits) | 3.0.3, 3.17 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-19 | Optional gap-item table (from, weight, min gaps, limits, placement) for Star Trail, capsule (35 / 35 / 30), egg, piggy, jar, shield (max 1, not while shielded) | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-20 | Placements: heart mid-gap (first on line, later 50 % on / 50 % off by 0.1–0.4 band); feather / piece 0.65 × spacing after the hoop, 64–200 pt above; switch 1.0 s × scroll (≥ 150 pt) before its ring, 70–100 pt above/below; capsule / egg / piggy / jar mid-gap on the line; shield 0.1–0.4 band off the line; star trail arc 40 pt after → 40 pt before, bulging 40 pt | 3.0.3 | 0b (plans) / element WPs (components) | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-21 | Exclusivity: one timed powerup (comet, Hourglass, Mini, Frenzy); no capsule / comet hoop while one runs; no COMET gift while one runs | 3.0.3 | 0b / 3f / 3d | test/run/director/s3_0_3_director_test.dart; test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 / §6 a capsule starts its powerup at once …; test/run/items/s3_30_s3_32_capsules_test.dart::§6 / WP-3a the comet uses the slot … | done |
| R-3.0.3-22 | Exclusivity: piggy or jar (never both); one egg/chick; star trail combines | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-23 | Rides: no specials, no gap items, no squeeze start (waits until 2 s after) | 3.0.3 | 0b / 3g | test/run/director/s3_0_3_director_test.dart; test/run/items/s3_17_squeeze_test.dart::§3.17 a squeeze never starts during a ride | done |
| R-3.0.3-24 | Portal ride pauses a running Hourglass / Mini / Frenzy and resumes it after landing | 3.0.3, 3.12 | 3f / 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.12 / §3.0.3 a running Hourglass…; test/run/items/s3_30_s3_32_capsules_test.dart::§3.0.3 a portal ride pauses the powerup … | done |
| R-3.0.3-25 | Portal ride start: all hoops/items ahead fade 0.2 s and are removed; uncaught piggy coins / fireflies not counted missed; piggy / jar placement continues after landing; ride rings crack the egg | 3.0.3 | 3b / 3e | test/run/rides/s3_12_ride_rules_test.dart::§3.12 entering… (cleared; spawner.clearAhead never judges) | 3b done; 3e pending (egg / piggy / jar) |
| R-3.0.3-26 | Comet flies through what is spawned: rims ignored (saw too), closed switch rings open, nearest pair ring + its gift, springs don't launch, tilt/motion kept, pickups only if touched | 3.0.3, 3.8 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 / §3.0.3 the comet flies through what is spawned…; test/run/items/s3_8_comet_test.dart::§3.8 the comet steers to the ring nearest its line… | done (3a part: rims / mistakes / closed-switch verdict ignored, nearest pair ring, pickups by touch); switch opening look 3d, spring no-launch 3c |
| R-3.0.3-27 | Only hoops spawned before a ride can be angled or moving | 3.0.3 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.0.3-28 | Pickup hit test: distance(bird, pickup) − bird r (× 0.52 Mini) ≤ radius; radii heart 16, shield 18, feather 18, piece 22, switch 18, comet 18, egg 16, piggy 18, jar 18, capsule 18, piggy coin 10, star 10, firefly 16 | 3.0.3 | 0b (base) | test/run/s7_run_parts_test.dart::§3.0.3 pickup hit radii; test/run/flow/s3_0_run_core_flow_test.dart::§3.0.3 pickups* | done |
| R-3.0.3-29 | Per-run order players meet things matches the table (typical run; flow test over seeds) | 3.0.3 | 0b | test/run/director/s3_0_8_first_meet_test.dart::§3.0.8 every element is met… | done |
| R-3.0.3-30 | Typical run 30–110 hoops in 1–3 min with the bot; ≈ 3–4 hearts, 1–2 comets, ≈ 1 portal, ≈ 1 squeeze per 2.5 min (soak test, informational) | 3.0.3 | 6 | | todo |

## 3.0.4 Rim bounce and miss rule

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.0.4-1 | Rim-end circles at local (0, ±(opening/2 + 7)), rotated with tilt, moved with motion; rest of the ring has no collider | 3.0.4 | 1a | test/run/physics/s3_0_4_rim_test.dart::§3.0.4 1 two rim ends r 7 at local (0, ±(opening/2 + 7)), rotated with the tilt; test/run/physics/s3_0_4_rim_test.dart::§3.0.4 2 relative to the rim's own velocity (moving rings) | done |
| R-3.0.4-2 | On overlap push out along the normal; reflect velocity into the rim (relative to rim velocity) with restitution 0.85, tangential unchanged | 3.0.4 | 1a | test/run/physics/s3_0_4_rim_test.dart::§3.0.4 2 head-on …; test/run/physics/s3_0_4_rim_test.dart::§3.0.4 2 moving away …; test/run/physics/s3_0_4_rim_test.dart::§3.0.4 2 relative to the rim's own velocity | done |
| R-3.0.4-3 | Rim touch marks the hoop touched (no perfect; PRD-2.2 §11 also needs the perfect zone, §10 knocks at the touch), rim "tonk", white sparks at contact, 360° spin over 0.35 s (direction from vy) | 3.0.4 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.0.4 a rim touch bounces …; test/run/physics/s3_0_4_rim_test.dart::§3.0.4 3 the spin is one turn over 0.35 s | part (touched, sparks, spin done; the rim "tonk" sound file does not exist yet: 3h) |
| R-3.0.4-4 | Forward speed is a real velocity; recovers at 2000 pt/s²; camera follows → the world jolts back | 3.0.4 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.0.4 a rim touch bounces, the world jolts back … | done |
| R-3.0.4-5 | Pass: centre crosses the plane forward between the rim-end centres (\|local y − ring offset\| ≤ opening/2 + 7); pressed against the inside counts as through | 3.0.4 | 1a | test/run/physics/s3_0_4_pass_test.dart::§3.0.4 inside the opening scores …; test/run/physics/s3_0_4_pass_test.dart::§3.0.4 the segment ends at the rim-end centres; test/run/physics/s3_0_4_pass_test.dart::§3.0.4 a bird pressed against the inside of a rim end passes (upright and every tilt step, both ends); test/run/flow/s3_1_hoop_flow_test.dart::§3.0.4 a bird pressed against the inside of the bottom rim end passes | done |
| R-3.0.4-6 | Crossings of the plane's extension beside the ring decide nothing | 3.0.4 | 1a | test/run/physics/s3_0_4_pass_test.dart::§3.0.4 crossings of the plane beside the ring decide nothing | done |
| R-3.0.4-7 | Miss only when fully past: bird x − r > centre x + \|sin tilt\| × (largest offset + opening/2 + 7) + 7 | 3.0.4 | 1a | test/run/physics/s3_0_4_pass_test.dart::§3.0.4 miss only when fully past …; test/run/physics/s3_0_4_pass_test.dart::§3.0.4 rightmost point of a tilted ring …; test/run/physics/s3_0_4_pass_test.dart::§3.0.4 a tilted ring is never missed early (every tilt step) | done |
| R-3.0.4-8 | Knocked back across the plane → not judged; each hoop resolves once | 3.0.4 | 1a | test/run/physics/s3_0_4_pass_test.dart::§3.0.4 a bird knocked back across the plane is not judged; test/collision_test.dart::§3.1 crossing the plane … scores exactly once | done |
| R-3.0.4-9 | Inside half of a rim end pushes into the opening (save); outside half pushes away | 3.0.4 | 1a | test/run/physics/s3_0_4_rim_test.dart::§3.0.4 6 the inside half pushes the bird into the opening, the outside half away from it | done |
| R-3.0.4-10 | Exceptions: saw rim = mistake, no bounce; closed switch reached = mistake; rides ignore rims | 3.0.4 | 1a (hooks) / 3d / 3a / 3b | lib/run/run_controller.dart hooks (RimMode.deadly → saw mistake, PlaneVerdict.mistake → closed switch, RimMode.ignored in rides); test/run/rides/s3_12_ride_rules_test.dart::§3.12 entering… (ride rings: rims ignored); test/run/rides/s3_12_portal_ride_test.dart; test/run/hoops/s3_18_saw_test.dart::§3.18 the rim is deadly …; test/run/hoops/s3_20_switch_test.dart::§3.20 reaching the ring while it is still closed… | part (3d, 3b done; 3a pending) |
| R-3.0.4-11 | Upward passes count like any forward pass | 10 (R16) | 1a | test/run/physics/s3_0_4_pass_test.dart::§3.0.4 inside the opening scores … (any forward crossing, vy free) | done |

## 3.0.5 Death physics

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.0.5-1 | At death camera and scroll ease to a stop over 0.4 s (ease-out); hoops, teeth, pickups stop with it | 3.0.5 | 1a | test/run/physics/s3_0_5_tumble_test.dart::§3.0.5 the world eases to a stop over 0.4 s; test/run/flow/s3_1_hoop_flow_test.dart::§3.0.5 the world eases to a stop over 0.4 s … | done |
| R-3.0.5-2 | Bird keeps its velocity (forward + vertical) | 3.0.5 | 1a | test/run/physics/s3_0_5_tumble_test.dart::§3.0.5 momentum + 180 pt/s knock along the contact normal | done |
| R-3.0.5-3 | Knock +180 pt/s along the contact normal (rim/saw from rim end, strip away from strip, closed switch −x); plain miss pops vy −140 | 3.0.5 | 1a | test/run/physics/s3_0_5_tumble_test.dart::§3.0.5 momentum + 180 pt/s knock …; test/run/physics/s3_0_5_tumble_test.dart::§3.0.5 a plain miss pops the bird up (vy − 140) | done |
| R-3.0.5-4 | Spin ω = clamp(forward / 25 + impact ±3–4, −12, 12) rad/s; dead X eyes | 3.0.5 | 1a | test/run/physics/s3_0_5_tumble_test.dart::§3.0.5 spin = clamp(forward / 25 + impact, ±12) rad/s; test/run/flow/s3_1_hoop_flow_test.dart::§3.2 / §5.1 … the dead bird rests on the floor spikes | done |
| R-3.0.5-5 | Then gravity 1250 and air drag −40 %/s on forward speed; top strip bounces down (restitution 0.3) | 3.0.5 | 1a | test/run/physics/s3_0_5_tumble_test.dart::§3.0.5 a top-strip hit bounces the bird back down (0.3) | done |
| R-3.0.5-6 | No collisions while tumbling (hoops, rims, pickups) | 3.0.5 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.0.5 the world eases to a stop over 0.4 s; the dead bird passes through hoops | done |
| R-3.0.5-7 | Floor bounce at tooth tips − r + 2 with restitution 0.3 (forward × 0.6, spin × −0.6, dust/feather puff) while landing > 140 pt/s; usually 1–2 bounces | 3.0.5 | 1a | test/run/physics/s3_0_5_tumble_test.dart::§3.0.5 bounces 1–2 times, then rests on the floor tooth line … | done |
| R-3.0.5-8 | Rest: slides to a stop (−600 %/s), spin settles flat (belly or back, nearer), stays behind the tooth tips through revive and until results | 3.0.5 | 1a | test/run/physics/s3_0_5_tumble_test.dart::§3.0.5 bounces 1–2 times …; test/run/flow/s3_1_hoop_flow_test.dart::§3.2 / §5.1 … the dead bird rests on the floor spikes | done |
| R-3.0.5-9 | Screen edges: bounce back at 24 pt from left / 30 pt from right (forward × −0.3); never leaves the screen | 3.0.5 | 1a | test/run/physics/s3_0_5_tumble_test.dart::§3.0.5 never leaves the screen sideways (24 pt / 30 pt edges) | done |
| R-3.0.5-10 | During a squeeze the resting line is the squeezed floor | 3.0.5 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 the moving walls are the spikes | done |
| R-3.0.5-11 | Themed deaths: signature moment first, then the same tumble (Frost: ice block shatters, frozen bird lies there); Black Hole swallows (no tumble, no body, only the shock ring) | 3.0.5 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 / §3.0.5 touching the <design> rim kills…; test/run/hoops/s3_18_saw_test.dart::§3.14 / §3.0.5 a revive after a Black Hole death… | done |
| R-3.0.5-12 | Revive offer 1.5 s after the hit (or when resting, if sooner); themed: moment + ≤ 1.5 s, max 2.2 s | 3.0.5 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.0.5-13 | ≤ 5 hoops: same tumble, then bonus / results after 1.5 s (2.2 s max) | 3.0.5 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.0.5-14 | Extra life / shield saves: no tumble, keep flying; spike save bounces off the tooth line during the 2 s (top: down at 30 %; floor: vy −222) | 3.0.5 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 / §3.0.5 a spike save bounces off the tooth line and the bird stays on screen through the 2 s | done |
| R-3.0.5-15 | SPEC.md DEVIATION note: death tumble replaces the 1.0 death | 3.0.5 | 1a | SPEC.md "PRD-2 hoops replace pipes (WP-1a)" | done |

## 3.0.6 Coin icon

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.0.6-1 | Every coin in a run and its screens uses `assets/images/menu/coin.png` (popups, flying coins, pills, prices, hearts); never a code-drawn thin ring; no recolour on gold backgrounds | 3.0.6 | 0c (+ every visual WP) | shot: build/parts_shots/08_coin_popup_timeline.png (CoinIcon) | part (0c: CoinIcon + popup; screens later) |

## 3.0.8 Every element, first meet, debug menu

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.0.8-1 | Every catalogue element has spawn rule, visuals + sounds, analytics event and a test (rows R-3.0.8-E*) | 3.0.8 | all | | todo |
| R-3.0.8-2 | `metElements` stored per install; met = spawned on screen in a run | 3.0.8 | 0b | test/run/director/s3_0_8_first_meet_test.dart | done |
| R-3.0.8-3 | Never-met element forced within 5 slots / 5 gaps after its first-possible hoop, when its rules allow | 3.0.8 | 0b | test/run/director/s3_0_8_first_meet_test.dart | done |
| R-3.0.8-4 | One forced element at a time, oldest unlock first; counts against the budget | 3.0.8 | 0b | test/run/director/s3_0_8_first_meet_test.dart | done |
| R-3.0.8-5 | Squeeze met at its normal time; feather / piece need no forcing | 3.0.8 | 0b | test/run/director/s3_0_8_first_meet_test.dart | done |
| R-3.0.8-6 | After met, normal weights and schedules only | 3.0.8 | 0b | test/run/director/s3_0_8_first_meet_test.dart | done |
| R-3.0.8-7 | Debug force menu (debug builds only): every element → next slot/gap ignoring unlock + cooldown, keeping exclusivity | 3.0.8 | 0b | test/run/debug/s3_0_8_force_menu_test.dart; test/run/director/s3_0_3_director_test.dart::§3.0.8 debug force* | done |
| R-3.0.8-8 | Debug: "start at hoop N" (= `startHoopIndex`), "reset met elements", "force portal ride: cannon / space / volcano / sea / pinball / storm" | 3.0.8 | 0b (3b for rides) | test/run/debug/s3_0_8_force_menu_test.dart; test/run/director/s3_0_3_director_test.dart::§3.0.8 debug force* | done |
| R-3.0.8-9 | Debug menu never compiled into release builds | 3.0.8 | 0b | test/run/debug/s3_0_8_force_menu_test.dart; test/run/director/s3_0_3_director_test.dart::§3.0.8 debug force* | done |
| R-3.0.8-E1 | Element: normal hoop | 3.0.7 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.0.1 … normal kind …; test/autopilot_test.dart | done |
| R-3.0.8-E2 | Element: angled ring | 3.0.7 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.10 an angled hoop is rotated around its centre… | done |
| R-3.0.8-E3 | Element: moving ring | 3.0.7 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.11 a moving hoop gets its motion and its guide… | done |
| R-3.0.8-E4 | Element: Bullseye Ring | 3.0.7 | 3c | test/run/flow/s3_19_s3_22_s3_25_autopilot_test.dart | done (WP-3c) |
| R-3.0.8-E5 | Element: Ring Train | 3.0.7 | 3c | test/run/flow/s3_19_s3_22_s3_25_autopilot_test.dart | done (WP-3c) |
| R-3.0.8-E6 | Element: Spring Ring | 3.0.7 | 3c | test/run/flow/s3_19_s3_22_s3_25_autopilot_test.dart | done (WP-3c) |
| R-3.0.8-E7 | Element: switch ring (5 designs) | 3.0.7 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 <design>: … (met on screen); test/run/flow/s3_18_s3_20_s3_21_autopilot_test.dart | done |
| R-3.0.8-E8 | Element: pair of powerup rings | 3.0.7 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 flying through the … ring … (met); test/run/flow/s3_18_s3_20_s3_21_autopilot_test.dart | done |
| R-3.0.8-E9 | Element: glowing ring (FEVER) | 3.0.7 | 3c | test/run/flow/s3_19_s3_22_s3_25_autopilot_test.dart | done (WP-3c) |
| R-3.0.8-E10 | Element: Lucky Spin | 3.0.7 | 3c | test/run/flow/s3_19_s3_22_s3_25_autopilot_test.dart | done (WP-3c) |
| R-3.0.8-E11 | Element: saw ring (3 designs) | 3.0.7 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 a clean pass … (met); test/run/flow/s3_18_s3_20_s3_21_autopilot_test.dart | done |
| R-3.0.8-E12 | Element: portal roller-coaster | 3.0.7 | 3b | test/run/rides/s3_12_portal_ride_test.dart; test/run/rides/s3_12_portal_autopilot_test.dart | done |
| R-3.0.8-E13 | Element: comet boost | 3.0.7 | 3a | test/run/items/s3_8_comet_test.dart; test/run/items/s3_8_comet_autopilot_test.dart; test/run/shots/comet_shots_test.dart | done |
| R-3.0.8-E14 | Element: heart → extra life | 3.0.7 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 three hearts give one extra life …; test/run/items/s3_3_s3_7_lives_test.dart::§3.3 a heart pickup on the bird is collected by touch … | done |
| R-3.0.8-E15 | Element: shield | 3.0.7 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.7 the shield pickup arms the shield … | done |
| R-3.0.8-E16 | Element: Star Trail | 3.0.7 | 3e | test/run/items/s3_26_star_trail_test.dart; test/run/items/s3_26_29_collect_autopilot_test.dart; shot: build/shots/run/collect/collect_trail_711.png | done (WP-3e) |
| R-3.0.8-E17 | Element: powerup capsule (Hourglass / Mini Bird / Coin Frenzy) | 3.0.7 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.0.8 / §3.30 a forced … capsule … counts as met on screen; test/run/items/s3_30_capsule_autopilot_test.dart | done |
| R-3.0.8-E18 | Element: Egg → chick ×2 | 3.0.7 | 3e | test/run/items/s3_27_egg_test.dart; test/run/items/s3_26_29_collect_autopilot_test.dart; shot: build/shots/run/collect/collect_egg_711.png | done (WP-3e) |
| R-3.0.8-E19 | Element: Piggy Bank | 3.0.7 | 3e | test/run/items/s3_28_piggy_test.dart; test/run/items/s3_26_29_collect_autopilot_test.dart; shot: build/shots/run/collect/collect_piggy_711.png | done (WP-3e) |
| R-3.0.8-E20 | Element: Firefly Jar | 3.0.7 | 3e | test/run/items/s3_29_jar_test.dart; test/run/items/s3_26_29_collect_autopilot_test.dart; shot: build/shots/run/collect/collect_jar_711.png | done (WP-3e) |
| R-3.0.8-E21 | Element: golden feather | 3.0.7 | 4a | test/run/items/s3_15_feathers_test.dart; test/run/items/s3_15_s3_16_collect_autopilot_test.dart | done (4a) |
| R-3.0.8-E22 | Element: puzzle piece | 3.0.7 | 4a | test/run/items/s3_16_puzzle_test.dart; test/run/items/s3_15_s3_16_collect_autopilot_test.dart | done (4a) |
| R-3.0.8-E23 | Element: spike squeeze | 3.0.7 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.0.8 the squeeze is forceable; test/run/items/s3_17_squeeze_autopilot_test.dart | done |
| R-3.0.8-E24 | Element: Big Hoops | 3.0.7 | 2a | test/run/items/s3_6_big_hoops_test.dart::§3.6 the home-slot Big Hoops is consumed at the start … | done |
| R-3.0.8-E25 | Element: perfect streak + ring tier looks | 3.0.7 | 2b | test/run/items/s3_4_streak_test.dart::§3.4 perfect passes build the streak; test/run/items/s3_4_streak_test.dart::§3.5 the whole ring field shows the tier | done |
| R-3.0.8-E26 | Element: coins (per pass + bonuses) | 3.0.7 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.2 / §5.1 a perfect pass pays 2 coins at once …; test/home_flow_test.dart::PRD-2 §3.2 coins are credited per hoop … | done (bonus sources: their WPs) |
| R-3.0.8-E27 | Element: rumble | 3.0.7 | 2c | test/run/items/s3_33_rumble_test.dart::§3.33 mapping; test/run/items/s3_33_rumble_test.dart::§3.33 throttle | done |
| R-3.0.8-E28 | Element: revive, results, versus | 3.0.7 | 2d / 2e / 5b | test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent…; test/versus/s3_13_versus_run_test.dart::§3.13 / §5.10 WIN… | done (versus: 5b) |

## 3.0.9 Shared parts (one master each)

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.0.9-1 | Spike strips 44 pt (band 26 + teeth 18, period 40), stage fg, 40 × 44 repeating tile, scrollable teeth; replaces 72 pt sprite; `spikeHeight` → 44 | 3.0.9 #1 | 0c / 1a | test/run/effects/s3_0_9_parts_test.dart::§3.0.9 #1 44 pt = band 26 + teeth 18, period 40, tips at 20 + 40k; test/run/shots/parts_shots_test.dart::§3.0.9 #1 menu with the 44 pt teeth art | done (0c art; 1a: spikeHeight 44 + SpikeArt.teeth default, test/config_test.dart::§3.0.9 #1 strips are 44 pt tall) |
| R-3.0.9-2 | Score circle = current game's 183 pt disc at (160, centre + 35), LVDC digits, behind hoops and bird | 3.0.9 #2 | existing / 0c check | shot: build/parts_shots/01_hoops_m0.png (existing ScoreHud) | done |
| R-3.0.9-3 | Hoop ring master: 24 pt wide, stroke 7, front `#EC008C` over bird, back `#B0006B` behind; height = opening + 2 × 7; specials change colours/decorations only | 3.0.9 #3 | 0c | test/run/effects/s3_0_9_parts_test.dart::§3.0.9 #3 24 pt wide, stroke 7, half height = opening / 2 + 7; shot: 01_hoops_m0.png, 03_ring_variants.png | done |
| R-3.0.9-4 | Bird = `LookPainter` (classic + equipped skin), ×0.983, flap, blink, themed death tint (no stage blend since PRD-2.2 §20); every screen draws the equipped skin | 3.0.9 #4 | 0c (check) | shot: build/parts_shots/05_birds.png (existing LookPainter) | done |
| R-3.0.9-5 | Gold bird (tier 2+): body `#FFB529`, tail + wing `#E08A00`, beak `#FFB529`, eye white; everywhere incl. rides and comet | 3.0.9 #5 | 0c / 2b | test/run/effects/s3_0_9_bird_test.dart::§3.0.9 #5 gold bird: body #FFB529, shade #E08A00, beak gold; test/run/items/s3_4_streak_test.dart::§3.5 the whole ring field shows the tier (goldTier at tier 2+); test/run/effects/s3_0_9_gold_glow_perf_test.dart::§3.0.9 #5 the gold glow layer is bounded: same pixels | done |
| R-3.0.9-6 | Dead X-eyes: white X 6 × 6, line 2, replacing the eye | 3.0.9 #6 | 0c | test/run/effects/s3_0_9_bird_test.dart::§3.0.9 #6 dead X: white 6 × 6, line 2, replacing the eye | done |
| R-3.0.9-7 | Streak banner master (y 190, pad 6, fixed font per tier [28,32,34,30,32,34,34,32,34,30], 0.1 em, white Opificio, scale-in ≈ 0.1 s, hold 1–1.9 s, scale-out; 10 names, cap IMMORTAL ×10) for every perfect pass incl. rides | 3.0.9 #7 | 0c | test/run/effects/s3_0_9_parts_test.dart::§3.0.9 #7 ten names, fixed sizes, colours, capped at IMMORTAL ×10; shot: 07_banners.png; test/run/items/s3_4_streak_test.dart::§3.4 perfect passes build the streak; shot: build/shots/run/streak/tier{1,2,3,5,10}_{711,568}.png (test/run/shots/streak_shots_test.dart) | done |
| R-3.0.9-8 | Pass coin popup: gold "+2" 28 pt + coin.png 24 pt from (x − 10, y − 70), scale 0.7 → 1.1 → 1, rises 40 pt, fades, 1.1 s; "+1" the same | 3.0.9 #8 | 0c | test/run/effects/s3_0_9_parts_test.dart::§3.0.9 #8 1.1 s, scale 0.7 → 1.1 → 1, rises 40 pt, fades; shot: 07_perfect_tier*.png; shot: build/shots/run/streak/tier{1,2,3,5,10}_{711,568}.png (test/run/shots/streak_shots_test.dart) (wired by ScoringFeature, WP-1a) | done |
| R-3.0.9-9 | Perfect burst: 8 + 3 × min(tier,3) squares, 5–8 pt, pink/gold/soft pink, 25–55 pt, 350–600 ms, no rotation, no shockwave | 3.0.9 #9 | 0c | test/run/effects/s3_0_9_parts_test.dart::§3.0.9 #9 5–8 pt, 25–55 pt, 350–600 ms, no rotation, 3 colours; test/run/items/s3_4_streak_test.dart::§3.0.9 #9 perfect burst at the bird | done |
| R-3.0.9-10 | Block trail tier 3+: 8–13 pt squares every ≈ 33 ms, 50/50 `#FFB529`/`#EC008C`, 0.9 → 0 in 450 ms, 26 pt behind along flight direction ± 8, drifting 70 pt opposite | 3.0.9 #10 | 0c | test/run/effects/s3_0_9_parts_test.dart::§3.0.9 #10 spawned 26 pt behind along the flight direction, drifts 70 pt opposite; shot: 10_trail_direction.png; test/run/items/s3_4_streak_test.dart::§3.5 the whole ring field shows the tier (trail active at tier 3+); shot: tier3_blocks_*.png | done |
| R-3.0.9-11 | Ring tier looks: pink → gold (`#FFB529`/`#D48A00`) → bright gold (`#FFD54A`/`#E0A800`); stars 9–15 / 10–17 / 12–24 pt at 7 / 16 / 38 per s per ring, 0.5–0.9 s; tier 3+ glow sprite + flame flicks | 3.0.9 #11 | 0c | test/run/effects/s3_0_9_parts_test.dart::§5.3 sparkles at 7 / 16 / 38 per second, sizes per tier; shot: 04_ringtier_*.png; test/run/items/s3_4_streak_test.dart::§3.5 the whole ring field shows the tier | done |
| R-3.0.9-12 | Speed lines kept separate: comet (2 pt, 30–110, 0.7, ≈ 34 ms, −460 pt in 260 ms); cannon (70 × 2, 0.7, −420 in 380 ms; vertical 2 × 60 in ride); themed (2 pt, 60 pt, 0.55, ≈ 500 pt over 0.38 s along flight) | 3.0.9 #12 | 3a / 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.0.9 #12 cannon / sea…; test/run/items/s3_8_comet_test.dart::§5.6 / §3.0.9 #12 comet speed streaks… | done |
| R-3.0.9-13 | No full-screen flash on perfect passes at any tier | 3.0.9 #13 | 2b | test/run/items/s3_4_streak_test.dart::§3.0.9 #13 no screen flash | done |
| R-3.0.9-14 | Coin icon = coin.png everywhere | 3.0.9 #14 | 0c | lib/run/effects/coin_icon.dart (CoinIcon); shot: 08_coin_popup_timeline.png | part (master 0c) |
| R-3.0.9-15 | Dust / feather puff: 12–22 particles 4–9 pt in the surface colour, ±140 / −90…−10 pt/s, slow down, fade 0.6–1 s (tumble bounce, landings) | 3.0.9 | 0c | test/run/effects/s3_0_9_parts_test.dart::§3.0.9 dust: 12–22 round particles 4–9 pt, up 10–90 pt/s, 0.6–1 s | part (master 0c; wiring 1a) |
| R-3.0.9-16 | No element draws its own version of a master (code review checklist item at each WP) | 3.0.9 | all | | todo |

## 3.1 Hoops replace pipes

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.1-1 | Pipes removed; bird flies through hoops; spike strips stay lethal | 3.1 | 1a | test/collision_test.dart; test/autopilot_test.dart | done |
| R-3.1-2 | Pass inside the opening: +1, `point.mp3` (non-perfect), HUD update, colour-stage check, pass feedback | 3.1 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.1 a non-perfect pass plays point.mp3 and the §5.1 pulse; test/run/flow/s3_1_hoop_flow_test.dart::§3.0.1 the colour stage … | done |
| R-3.1-3 | Missing a hoop ends the run (or uses extra life / shield), plays the miss flash | 3.1 | 1a | test/collision_test.dart::§3.1 missing a hoop ends the run exactly once; test/run/flow/s3_1_hoop_flow_test.dart::§5.13 a miss plays the shock-ring miss flash … | done (extra life / shield: test/run/items/s3_3_s3_7_lives_test.dart::§3.3 the extra life forgives one mistake …) |
| R-3.1-4 | Rim touch doesn't end the run: bounce; if through, +1 and 1 coin, not perfect, streak resets | 3.1 | 1a / 2b | test/run/flow/s3_1_hoop_flow_test.dart::§3.0.4 a rim touch bounces … +1 with 1 coin and is not perfect | done (streak reset: 2b) |
| R-3.1-5 | Floor/ceiling spikes: contact = mistake | 3.1 | 1a | test/collision_test.dart::§3.1 bird-spike contact ends the run exactly once; test/run/flow/s3_1_hoop_flow_test.dart::§3.0.5 a spike save (invulnerable) bounces off the floor tooth line | done |
| R-3.1-6 | Score fires at the plane crossing (replaces the 111 pt sensor) | 3.1 | 1a | test/run/physics/s3_0_4_pass_test.dart; test/collision_test.dart::§3.1 crossing the plane inside the opening scores exactly once | done |
| R-3.1-7 | Hoop art ~22–24 pt deep, opening + 2 × 7 tall, scales with the opening; two layers (back half behind, front half in front) | 3.1 | 1a / 0c | shot: build/shots/run/hoops/run_711.png (test/run/shots/hoops_shots_test.dart::§5.1 run frame with M0 hoops at 711) | done |
| R-3.1-8 | Every hoop spawns ≥ 60 pt past the right edge (glow and decorations out of view) | 3.1 | 1a | test/run/flow/s3_0_1_hoop_spawner_test.dart::… scrolled in from ≥ 60 pt past the edge | done |
| R-3.1-9 | Colours fixed (not stage-tinted); Big Hoops gold `#FFB529`/`#D48A00`; contrast checked on stage 45 | 3.1 | 1a / 2a | test/color_state_test.dart (hoops keep the skin colours, not the tint) | done (Big Hoops gold: test/run/items/s3_6_big_hoops_test.dart::§3.6 every hoop spawned is sized by the multiplier …) |
| R-3.1-10 | `pipe_pair` → `Hoop`; pipe Config constants → hoop constants; min/max centre bands use the same margin | 3.1 | 1a | pipe_pair.dart deleted; test/config_test.dart::PRD-2 hoop course …; test/run/flow/s3_0_1_hoop_spawner_test.dart | done |
| R-3.1-11 | Fredoka SemiBold added (assets + pubspec) | 3.1, 5.7 | 0b | pubspec.yaml font family Fredoka (assets/fonts/Fredoka-SemiBold.ttf, OFL) | done |
| R-3.1-12 | Tint registry no longer applies to obstacles; pipe sprites dropped | 3.1 | 1a | test/color_state_test.dart (hoops are not Tintable) | done |
| R-3.1-13 | SPEC.md DEVIATION: obstacle, score trigger, miss rule, 2.0 physics | 3.1, 7 | 1a | SPEC.md "PRD-2 hoops replace pipes (WP-1a)" | done |
| R-3.1-14 | Tests updated: autopilot, gap-variance, layout, collision; plane-crossing suite (see R-7-T1) | 3.1 | 1a | test/autopilot_test.dart; test/collision_test.dart; test/run/flow/s3_0_1_hoop_spawner_test.dart (replaces pipe_spawner / gap_variance); test/layout_test.dart; test/run/physics/s3_0_4_pass_test.dart | done |
| R-3.1-15 | Home/store copy "Don't touch the spikes" unchanged (superseded by PRD-2.3 §12: the home subtitle is FLAP FAST, FLY FAR) | 3.1 | 1a | lib/components/home/home_screen.dart | done |

## 3.2 Coin earning

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.2-1 | 1 coin per hoop passed; floating "+1" with coin icon at the hoop | 3.2 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.0.4 a rim touch bounces … 1 coin; lib/run/items/scoring.dart (CoinPopup, master #8) | done |
| R-3.2-2 | Perfect pass +2 instead of 1 | 3.2 | 1a / 2b | test/run/flow/s3_1_hoop_flow_test.dart::§3.2 / §5.1 a perfect pass pays 2 coins at once … | done |
| R-3.2-3 | Coins credited to the wallet at the moment of the pass (kept if the run ends right after); interim "1 coin per point at game over" removed | 3.2 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.2 / §5.1 … no coins at game over …; test/home_flow_test.dart::PRD-2 §3.2 coins are credited per hoop at the pass …; test/e2e/menu_e2e_test.dart::QA play score is credited once … | done |
| R-3.2-4 | A hoop saved by an extra life / shield gives no coin | 3.2 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 the extra life forgives one mistake … (no pass → no point / coin) | done |
| R-3.2-5 | No coin total in the in-game HUD | 3.2 | 2d | test/run/screens/s5_7_hud_pause_test.dart | done |
| R-3.2-6 | Versus win +10 (draw +5) | 3.2, 3.13 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 / §5.10 WIN: 5 vs 3 → +10…; …DRAW: 3 vs 3 → +5… | done |

## 3.3 Hearts and extra life

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.3-1 | Heart pickups collected by touch | 3.3 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 a heart pickup on the bird is collected by touch (the spawner hit test) and counts | done |
| R-3.3-2 | HUD single heart: empty dashed, 1/3, 2/3 (clipped from bottom), full + pulse = extra life | 3.3, 5.7 | 2d | test/run/screens/s5_7_hud_pause_test.dart | done |
| R-3.3-3 | 3rd heart → extra life; heart badge floats above the bird (bobbing) | 3.3, 5.5 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 three hearts give one extra life …; shot: build/shots/run/lives/big_heart_badge_*.png | done |
| R-3.3-4 | Mistake list (missed hoop incl. pair, spikes, saw rim, closed switch) forgiven once by the extra life | 3.3 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.7 / §3.3 save order … (spikes, saw, closed switch, missed hoop) | done |
| R-3.3-5 | On use: badge pops (heart particles), indicator → 0/3, bird flashes + 2 s invulnerability, keep playing; missed hoop not counted | 3.3 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 the extra life forgives one mistake …; shot: build/shots/run/lives/extra_life_pop_*.png | done |
| R-3.3-6 | Doesn't stack; no heart spawns while active (schedule moves on) | 3.3 | 2a / 0b | test/run/director/s3_0_3_director_test.dart | done (0b schedule; 2a: test/run/items/s3_3_s3_7_lives_test.dart::§3.3 three hearts … a 4th heart does not stack) |
| R-3.3-7 | Separate from the shield; both can be active | 3.3 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.7 / §3.3 save order: the shield (order 10) absorbs first, then the extra life (order 20) … | done |
| R-3.3-8 | Hearts reset at game over (run-only) | 3.3 | 2a | RunState is per run (new run → hearts 0); test/run/items/s3_6_big_hoops_test.dart::§3.6 … no run without it is boosted (second run starts fresh) | done |
| R-3.3-9 | Spawn: first after hoop 3, then every 17–27, mid-gap; first on line, later 50/50 off by 0.1–0.4 band; never in a hoop or strip; max one on screen | 3.3 | 0b / 2a | test/run/director/s3_0_3_director_test.dart; test/run/hoops/s3_11_moving_rings_test.dart::§3.3 heart placement… | done (0b schedule; 1b placement; 2a real pickup: test/run/items/s3_3_s3_7_lives_test.dart::§3.3 a heart pickup on the bird is collected by touch …) |
| R-3.3-10 | Big Hoops and hearts independent | 3.3 | 2a | independent features (BigHoopsFeature / ExtraLifeFeature); shot: build/shots/run/lives/big_heart_badge_*.png | done |

## 3.4 Perfect-pass streak

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.4-1 | Perfect = no rim contact **and inside the perfect zone (PRD-2.2 §11: ±min(24, 0.2 × opening), test/p22/s11_perfect_zone_test.dart)**; non-perfect pass (graze or clean off-centre) or mistake resets the streak to 0 | 3.4 | 2b | test/run/items/s3_4_streak_test.dart::§3.4 / §5.3 a graze resets the streak; test/run/items/s3_4_streak_test.dart::§3.4 a save or a death breaks the streak | done |
| R-3.4-2 | Every perfect pass +2 coins (flat at all tiers) | 3.4 | 2b | test/run/flow/s3_1_hoop_flow_test.dart (ScoringFeature: +2 perfect at every tier) | done |
| R-3.4-3 | 10 tiers (effects); banner names and colours per PRD-2.2 §29 (50 names, FLAPPY GOD ×n from ×51, 10 rotating colours; test/p22/s29_streak_names_test.dart) | 3.4 | 2b | test/run/items/s3_4_streak_test.dart::§3.4 perfect passes build the streak | done |
| R-3.4-4 | Tier effects: 1 small burst; 2 bigger burst + gold bird; 3+ biggest burst + block trail; tier 4+ reuse tier 3 | 3.4 | 2b | test/run/items/s3_4_streak_test.dart::§3.0.9 #9 perfect burst at the bird; test/run/items/s3_4_streak_test.dart::§3.5 the whole ring field shows the tier | done |
| R-3.4-5 | Sounds: `perfect_1` (streak 1), `perfect_2` (2), `perfect_3` (3+); replace `point.mp3` on perfect; `point.mp3` still on a graze | 3.4 | 2b | test/run/items/s3_4_streak_test.dart::§3.4 perfect passes build the streak; test/run/items/s3_4_streak_test.dart::§3.4 / §5.3 a graze resets the streak | done |
| R-3.4-6 | Streak sounds respect SFX mute; peak ≈ −1.4 dBFS, checked against flap loudness | 3.4 | 2b / 3h | test/run/items/s3_4_streak_test.dart::§3.4 perfect passes build the streak (through SoundService.play: the SFX mute applies); loudness: WP-3h files | done |

## 3.5 Ring reactions to the streak

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.5-1 | Whole ring field (passed, ahead, newly spawned) shows the current tier's look | 3.5 | 2b | test/run/items/s3_4_streak_test.dart::§3.5 the whole ring field shows the tier | done |
| R-3.5-2 | Tier 0 pink, tier 1 light gold sparkles, tier 2 gold rings + gold bird, tier 3+ heavier sparkles + flame flicks + glow + bright gold + block trail | 3.5 | 2b | test/run/items/s3_4_streak_test.dart::§3.5 the whole ring field shows the tier | done |
| R-3.5-3 | Streak break: all rings instantly return to pink, effects stop | 3.5 | 2b | test/run/items/s3_4_streak_test.dart::§3.5 the whole ring field shows the tier; test/run/items/s3_4_streak_test.dart::§3.4 a save or a death breaks the streak | done |
| R-3.5-4 | Banner, +2 popup, small burst and tier sound still fire per pass; tier 4+ confetti + full-screen flash removed | 3.5 | 2b | test/run/items/s3_4_streak_test.dart::§3.4 perfect passes build the streak; test/run/items/s3_4_streak_test.dart::§3.0.9 #9 perfect burst at the bird; test/run/items/s3_4_streak_test.dart::§3.0.9 #13 no screen flash | done |
| R-3.5-5 | Comet: hoops count as perfect, build streak, same banners/sounds; streak carries on after | 3.5 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 during the boost …; test/run/items/s3_8_comet_test.dart::§3.8 / §3.9 the end … the streak carries on | done |
| R-3.5-6 | Performance: sparkles children of each ring, pooled, capped (≈ 38/s per ring, ≤ 3 rings); one glow sprite per ring | 3.5 | 0c / 2b | test/run/effects/s3_0_9_parts_test.dart::§3.5 a streak break clears every effect at once; test/run/items/s3_4_streak_test.dart::§3.5 the whole ring field shows the tier (one RingTierFx per ring, painted with the ring) | done |

## 3.6 Big Hoops (run side)

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.6-1 | Read and consume `armedPowerup` at run start; next run only; no stacking | 3.6 | 2a | test/run/items/s3_6_big_hoops_test.dart::§3.6 the home-slot Big Hoops is consumed at the start and rolls D in 30–40 s … | done |
| R-3.6-2 | D random 30–40 s of runClock; hoops spawned until D − 8 s are 1.5× (capped to fit the band) and gold | 3.6 | 2a | test/run/items/s3_6_big_hoops_test.dart::§3.6 D over many seeds …; test/run/items/s3_6_big_hoops_test.dart::§3.6 every hoop spawned is sized by the multiplier at its spawn time … | done |
| R-3.6-3 | Last 8 s: multiplier eases 1.5 → 1.0 per newly spawned hoop; a hoop never changes size on screen; normal after D | 3.6 | 2a | test/run/items/s3_6_big_hoops_test.dart::§3.6 BigHoopsState §3.6 ×1.5 until D − 8 s, easing …; test/run/items/s3_6_big_hoops_test.dart::§3.6 every hoop spawned … a hoop never changes size on screen | done |
| R-3.6-4 | Every hoop kind grows; specials keep their look (no gold); tier look on top | 3.6 | 2a | director scales every kind (0b); gold only for normal hoops: test/run/items/s3_6_big_hoops_test.dart::§3.6 every hoop spawned … | done (special kinds land in P3; BigHoopsFeature.isGold for 2b) |
| R-3.6-5 | Autopilot playability test passes with Big Hoops on | 3.6 | 2a | test/autopilot_test.dart::AUTOPILOT (568 / 711) seed 7, 21, 1234 Big Hoops | done |
| R-3.6-6 | Boosted runs count for best, levels, versus pools, leaderboard (not flagged) | 3.6 | 2a / 5b | no flag on boosted runs (RunSummary unchanged) | done (versus pools: 5b) |
| R-3.6-7 | No in-game indicator | 3.6 | 2a | no indicator component | done |
| R-3.6-8 | Knobs `bigHoopsMult 1.5`, `bigHoopsMin 30`, `bigHoopsMax 40`, `bigHoopsEase 8` | 3.6 | 2a | test/run/items/s3_6_big_hoops_test.dart::§3.6 knobs (bigHoopsMult 1.5, bigHoopsMin 30, bigHoopsMax 40, bigHoopsEase 8) | done |

## 3.7 Shield (run side)

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.7-1 | Absorbs exactly one mistake (full mistake list), no timer; shatters; flash + 2 s invulnerability; spike save stays on screen | 3.7 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.7 / §3.3 save order …; test/run/items/s3_3_s3_7_lives_test.dart::§3.3 / §3.0.5 a spike save bounces … | done |
| R-3.7-2 | Active look: translucent circle, gold ring, rotating dashed inner ring, gentle pulse, no badge | 3.7, 5.5 | 2a | shot: build/shots/run/lives/shield_circle_*.png; test/run/items/s3_3_s3_7_lives_test.dart::§3.7 the shield pickup arms the shield … circle forms | done |
| R-3.7-3 | Obtained by field pickup (from hoop 12, max 1 per run, off the line), SHIELD pair gift, home slot (active from start) | 3.7 | 2a / 3d | test/run/items/s3_3_s3_7_lives_test.dart::§3.7 the shield pickup arms the shield …; test/run/items/s3_3_s3_7_lives_test.dart::§3.7 the home-slot shield is consumed at the start …; test/run/hoops/s3_21_pair_test.dart::§3.21 the shield gift does what it says | done |
| R-3.7-4 | Icon: pink fill, gold border, gold star (same asset as the home slot) | 3.7 | 2a | shot: build/shots/run/lives/shield_circle_*.png (LifeIcons.paintShield) | done |
| R-3.7-5 | Stacks with all powerups; visuals layer | 3.7 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.7 / §3.3 save order … (shield + extra life together) | done |

## 3.8 Comet boost

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.8-1 | Pickup: gold 4-point star with pink/gold tail hanging 20 pt past the plane of a normal (upright, still) hoop; collected by flying through | 3.8 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 / §3.0.3 the comet hoop …; test/run/items/s3_8_comet_autopilot_test.dart; shots: build/shots/run/comet/comet_{pickup,active,tier,landing}_711.png, comet_active_568.png (test/run/shots/comet_shots_test.dart) | done |
| R-3.8-2 | Spawn first 10–30, then +45–60; also the COMET pair gift | 3.8 | 0b / 3a | test/run/director/s3_0_3_director_test.dart; test/run/items/s3_8_comet_test.dart::§3.21 a pair COMET gift …; test/run/items/s3_8_comet_test.dart::§3.0.8 first meet … | done (the pair gift fires through `PickupCollected(comet, null)`, emitted by 3d) |
| R-3.8-3 | On collection: pop (white flash, squares, gold ring); bird inside the fireball | 3.8 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 the pop …; shots: build/shots/run/comet/comet_{pickup,active,tier,landing}_711.png, comet_active_568.png (test/run/shots/comet_shots_test.dart) | done |
| R-3.8-4 | 10 s; scroll eases to 1.7 × cruise (0.45 s); hoops spawned during are the curve size (PRD-2.4 §2), upright still; existing hoops keep motion; comet flies through as 3.0.3 | 3.8 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 10 s at 1.7 × cruise …; test/run/items/s3_8_comet_test.dart::§3.8 during the boost … | done |
| R-3.8-5 | Bird flies itself; taps ignored; white speed streaks; gold countdown ring with seconds left | 3.8 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 / §3.9 / §6 collecting the star … taps are ignored; test/run/items/s3_8_comet_test.dart::§5.6 / §3.0.9 #12 comet speed streaks …; shots: build/shots/run/comet/comet_{pickup,active,tier,landing}_711.png, comet_active_568.png (test/run/shots/comet_shots_test.dart) | done |
| R-3.8-6 | Hoops score + coins and count as perfect (banner, burst, +2, tier sounds, ring field) | 3.8 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 during the boost … | done |
| R-3.8-7 | Last 0.9 s eases speed down; bird pops back; control returns; no extra invulnerability | 3.8 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 / §3.9 the end … | done |
| R-3.8-8 | Combines with extra life and shield (shield circle around the comet) | 3.8 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 combines with the shield and the extra life … | done |

## 3.9 Powerup sounds

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.9-1 | `pu_heart_1` on 1st/2nd heart; `pu_heart_2` on the 3rd (badge appears at once); `pu_heart_use` when the extra life absorbs | 3.9 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 three hearts give one extra life …; test/run/items/s3_3_s3_7_lives_test.dart::§3.3 the extra life forgives one mistake … | done |
| R-3.9-2 | `pu_shield_get` on collection; `pu_shield_hit` on absorb | 3.9 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.7 the shield pickup arms the shield …; test/run/items/s3_3_s3_7_lives_test.dart::§3.7 / §3.3 save order … | done |
| R-3.9-3 | `pu_comet_get` on collection; `pu_comet_loop` from ≈ 1.2 s until the end (fade ≈ 0.3 s, ≈ 30 % volume, BGM-style looping player); `pu_comet_end` at the end | 3.9 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 / §3.9 the end …; test/run/items/s3_8_comet_test.dart::§3.9 a paused run silences the comet loop … | done |
| R-3.9-4 | `pu_portal`, `pu_cannon_aim`, `pu_cannon_shot`, `pu_land` at their moments | 3.9 | 3b | test/run/rides/s3_12_portal_ride_test.dart (pu_portal, pu_cannon_aim, pu_cannon_shot, pu_land) | done |
| R-3.9-5 | All through low-latency AudioPool (loops via the looping player); peak ≈ −1.4 dBFS | 3.9 | 0b (API) | test/run/director/s3_0_3_director_test.dart | done |

## 3.10 Angled rings

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.10-1 | Fixed steps −20, −10, +15, +30, +45 (positive = top leans right), weights by hoop index; none before 10; 45° from 35 | 3.10 | 0b / 1b | test/run/director/s3_0_3_director_test.dart; test/run/director/s3_0_2_layout_ramp_test.dart::§3.10 tilt share and step weights per row… | done |
| R-3.10-2 | Effective opening = opening × cos(angle); pass inside the tilted segment | 3.10 | 1b | — (pass test in the hoop frame is WP-1a; 1b poses position / angle) | 1b part done; 1a pending |
| R-3.10-3 | Same opening as upright before tilt; band max jump kept; autopilot passes with angled rings | 3.10 | 1b | test/run/director/s3_0_2_layout_ramp_test.dart; test/run/flow/s3_10_s3_11_autopilot_test.dart (skipped until WP-1a) | 1b part done; autopilot runs after the WP-1a merge |
| R-3.10-4 | Art: the ring rotated around its centre, layers and streak effects as normal; no angle label | 3.10 | 1b | test/run/hoops/s3_11_moving_rings_test.dart; shot: build/shots/run/rings/5_11_*.png | done |
| R-3.10-5 | Other powerups don't change tilting | 3.10 | 1b | test/run/director/s3_0_2_layout_ramp_test.dart (tilt is rolled from the hoop index only) | done |

## 3.11 Moving rings

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.11-1 | Dashed guide with arrowheads scrolls with the ring; visible before the ring is reachable (spawn together) | 3.11, 5.12 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.11 a moving hoop gets its motion and its guide…; shot: build/shots/run/rings/5_12_*.png | done |
| R-3.11-2 | Rail slide: up to ±25° off vertical, ±40–60 pt, constant 30–39 pt/s, turns at the ends | 3.11 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.11 rail slide…; test/run/director/s3_0_2_layout_ramp_test.dart::§3.11 slides… | done |
| R-3.11-3 | Swing: hangs from a rope above the top spikes, ±15°, period 1.8 s, ring in line with the rope | 3.11 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.11 swing…; test/run/director/s3_0_2_layout_ramp_test.dart | done |
| R-3.11-4 | Horizontal slide (45+): toward/away from the bird ±40–60 pt at 30–39 pt/s | 3.11 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.11 horizontal slide…; test/run/director/s3_0_2_layout_ramp_test.dart | done |
| R-3.11-5 | Diagonal slide (45+): ±38° diagonal, ±40–60 pt at 30–39 pt/s | 3.11 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.11 horizontal slide… (diagonals); test/run/director/s3_0_2_layout_ramp_test.dart | done |
| R-3.11-6 | Orbit (45+): ellipse ≈ 50 × 62, path speed ≤ 39 pt/s, angle ±22° along the path | 3.11 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.11 orbit…; test/run/director/s3_0_2_layout_ramp_test.dart | done |
| R-3.11-7 | Rock (45+): stays, rocks ±15°, period 3 s | 3.11 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.11 rock…; test/run/director/s3_0_2_layout_ramp_test.dart | done |
| R-3.11-8 | Pass judged at the ring's actual position and angle at the crossing | 3.11 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.11 / §3.10 a moving ring is posed at home + offset… | 1b part done (pose at runClock); 1a pass test pending |
| R-3.11-9 | Amplitudes capped to stay in the band and within the max jump; autopilot passes with moving rings | 3.11 | 1b | test/run/director/s3_0_2_layout_ramp_test.dart::§3.11 fairness…; test/run/flow/s3_10_s3_11_autopilot_test.dart (skipped until WP-1a) | 1b part done; autopilot runs after the WP-1a merge |
| R-3.11-10 | Moving rings may also be tilted and react to the streak | 3.11 | 1b | test/run/hoops/s3_11_moving_rings_test.dart::§3.11 / §3.10 a moving ring is posed… (tilt + motion) | done |

## 3.12 Portal roller-coaster

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.12-1 | Portal ring: normal size, purple `#7C4DFF` / `#4B2BB8`, cyan `#22E6FF` inner rim, ≈ 66 pt beam, cyan sparkles | 3.12, 5.12b | 3b | lib/run/hoops/kinds/portal.dart; test/run/rides/s3_12_ride_rules_test.dart::§3.12 chain…; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-3.12-2 | Chain: next ring visible, the rest hidden until the ride; then only rings ≤ 1 500 pt ahead | 3.12 | 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.12 chain: the first curve ring is visible ahead… | done |
| R-3.12-3 | Entering counts as a pass (banner, +2, tier sound, portal sound); camera starts at the live scroll speed; bird accelerates to 480 pt/s over ≈ 2.2 s | 3.12 | 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.12 entering…; test/run/rides/s3_12_portal_ride_test.dart | done |
| R-3.12-4 | Clear the way: hoops/items ahead fade 0.2 s and are removed; timed powerups paused | 3.12 | 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.12 entering… (cleared); test/run/rides/s3_12_ride_rules_test.dart::§3.12 / §3.0.3 a running Hourglass… | done |
| R-3.12-5 | Cannon ride path: curve up r 180, climb ≈ 1 600, loop r 220, dive ≈ 2 000; rings every 380 pt (first 190; PRD-2.3.1 §7: 5 rings every 950 pt), facing the path; no track line | 3.12 | 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.12 the cannon path… | done |
| R-3.12-6 | Input ignored; run can't end; background tints purple/cyan; strips fade out; vertical speed lines | 3.12 | 3b | test/run/rides/s3_12_portal_ride_test.dart (input ignored, strips fade, run cannot end); test/run/rides/s3_12_ride_rules_test.dart::§3.0.9 #12 cannon…; test/run/rides/s3_12_ride_rules_test.dart::§3.12 never the same ride… (no death in a ride) | done |
| R-3.12-7 | Every ride ring is a perfect pass (banner, +2, burst, tier sound, tier looks; trail follows direction); no flames on the bird | 3.12 | 3b | test/run/rides/s3_12_portal_ride_test.dart (11 perfect ride passes, shakes); test/run/rides/s3_12_ride_rules_test.dart::§3.12 the bird is hidden in the barrel…; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-3.12-8 | Cannon: ground rises, blocky spiked cannon; bird into the muzzle; barrel tilts right ≈ 38° with shake; fires | 3.12 | 3b | lib/run/rides/themes/cannon.dart; test/run/rides/s3_12_portal_ride_test.dart::§3.12 cannon…; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-3.12-9 | Shot: flash, smoke, confetti; ballistic arc 560 / −640 pt/s, g 520; camera follows; cannon recoils and stays | 3.12 | 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.12 the shot…; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-3.12-10 | Return ≈ 2.5 s: tint fades, strips fade in with teeth scrolling ≈ 1 300 pt/s easing to stop; glide to (70, viewHeight/2) with squash + wobble; normal rings ≈ 1 s after landing; piggy/jar resume | 3.12 | 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.12 the shot… (glide home, teeth scroll); test/run/rides/s3_12_portal_ride_test.dart (hoops ≈ 1 s after the landing) | done (piggy / jar resume: 3e) |
| R-3.12-11 | Points by the streak (PRD-2.2 §13.1), +2 coins per ride ring; no extra ride bonus | 3.12 | 3b | test/run/rides/s3_12_portal_ride_test.dart (ride points max(2, streak), +2 coins per ride ring) | done |
| R-3.12-12 | Timing: pass 0 → ride ≈ 9.6 s → entry 0.2 → aim ≈ 1 → flight 1.7 → return 2.5 (≈ 15 s) | 3.12 | 3b | test/run/rides/s3_12_portal_ride_test.dart (ride 8–10.6 s, flight 1.65, glide + settle 3.1) | done |
| R-3.12-13 | Each portal picks one of 6 rides with equal chance, never the same twice in a row (also across runs, `lastPortalRide`) | 3.12 | 0b / 3b | test/run/director/s3_0_3_director_test.dart; test/run/rides/s3_12_ride_rules_test.dart::§3.12 never the same ride twice…; test/run/rides/s3_12_portal_autopilot_test.dart | done |
| R-3.12-14 | All rides: same portal ring, 11 golden rings + portal = 12 passes (+12 score, +24 coins); PRD-2.3.1 §7: 5 rings + portal = 6 passes (+12 coins), ≈ 9.6 s ride, exit, launch flight, glide | 3.12 | 3b | test/run/rides/s3_12_portal_ride_test.dart (all six rides) | done |
| R-3.12-15 | Engine: one `PortalRide` (path from segments/curve, 11 rings (PRD-2.3.1 §7: 5) at equal arc length, ride camera, exit → launch → glide) + pluggable `RideTheme` | 7 | 3b | lib/run/rides/portal_ride.dart, ride_theme.dart, ride_path.dart; test/run/rides/s3_12_ride_rules_test.dart::§3.12 / §7 <id>: 11 rings at equal arc length… | done |

## 3.13 Versus

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.13-1 | Every run is a duel vs a real recorded run when available, else solo; no generated opponents | 3.13 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 solo start…; test/versus/s3_13_service_test.dart::§3.13 matching from the prefetched pool… | done |
| R-3.13-2 | Anonymous Firebase Auth account on first start (no UI) | 3.13 | 5b | test/versus/s3_13_service_test.dart::§3.13 initialize: a nickname once per install, anonymous auth…; lib/services/firebase_versus_backend.dart (start: signInAnonymously) | done (plugin call: device / e2e) |
| R-3.13-3 | Play Games players show PGS name + avatar; anonymous show generated nickname + default avatar | 3.13 | 5b | test/versus/s3_13_service_test.dart::§3.13 a Play Games player links the account and shows their name | done (avatar image: Fix P45 R1 S6-64, ARCH §30; test/versus/s6_64_65_identity_test.dart) |
| R-3.13-4 | Play Games sign-in later links the same Firebase account (runs carry over, name switches) | 3.13 | 5b | test/versus/s3_13_service_test.dart::§3.13 a Play Games player links the account…; lib/services/identity.dart (GameAuth.getAuthCode → PlayGamesAuthProvider) | done (live link: device) |
| R-3.13-5 | Nickname: Adjective + Bird + 3 digits; ≤ 14 chars before digits; the 20 + 20 word lists; once per install; no free text | 3.13 | 5b | test/versus/s3_13_matching_nickname_test.dart::§3.13 nicknames (3 tests) | done |
| R-3.13-6 | Stored per run: score, best, ts, name, avatar, look (5 ids), `tl` (cs deltas uint16 base64 on runClock), `end`, `fl` timeline v2 (PRD-2.2 §13.5: flags + values; test/p22/s13_versus_timeline_test.dart, functions/test/timeline.test.ts), platform | 3.13 | 5b | test/versus/s3_13_upload_entry_test.dart::§3.13 an entry carries score, best, name, look, platform and the timeline…; test/versus/s3_13_emulator_test.dart (opt-in, tool/versus_emulator_test.sh) | done |
| R-3.13-7 | Pair +5 gifts appear as a step of 5 in the timeline | 3.13 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 the timeline records every point on runClock… | done |
| R-3.13-8 | Kept: best run + last 5; best always uploaded; others ≤ 3 a day; score < 3 never; local queue with retry | 3.13 | 5b | test/versus/s3_13_upload_entry_test.dart::§3.13 upload queue (4 tests); test/versus/s3_13_upload_entry_test.dart::§3.13 player doc — one new run per write (2 tests); test/versus/s3_13_service_test.dart::§3.13 submitRun… | done |
| R-3.13-9 | Matching from a prefetched pool before START: same level & below my best → any → solo; never own runs; no repeat in a session | 3.13 | 5b | test/versus/s3_13_matching_nickname_test.dart::§3.13 matching — test/fixtures/versus_matching.json (all cases); test/versus/s3_13_service_test.dart::§3.13 matching from the prefetched pool… | done |
| R-3.13-10 | VS intro only if an opponent is prefetched at tap time; otherwise straight to a solo run | 3.13, 5.8 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 solo start…; test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent… | done |
| R-3.13-11 | Opponent score replays their timeline on my runClock (stops in pause, revive offer, phoenix; slows with Hourglass); out (dimmed) at the end of their timeline | 3.13 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 timeline replay on runClock…; test/versus/s3_13_versus_run_test.dart::§3.13 the replay holds through the revive offer and the phoenix… | done |
| R-3.13-12 | Result WIN / LOSE / DRAW on final scores; +10 win, +5 draw (`win_bonus`), in YOUR REWARD | 3.13 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 / §5.10 WIN / LOSE / DRAW (3 tests) | done |
| R-3.13-13 | Powerups, revives, rides part of both runs | 3.13 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 the timeline records every point… (ride / train / gift flags) | done |
| R-3.13-14 | Firestore `players/{uid}` written only by its owner (rules: auth uid, field + size validation) | 3.13 | 5a | functions/test/rules.test.ts::§3.13 a player can create, read, update and delete their own doc; functions/test/rules.test.ts::§3.13 a player cannot read or write another player doc; functions/test/rules.test.ts::§3.13 rejects a player doc with … (19 cases) | done |
| R-3.13-15 | `pools/{level}_{shard}`: server-only writes, ≤ 150 entries, level 0–10 × 4 shards, newest first; clients read only | 3.13 | 5a | functions/test/rules.test.ts::§3.13 signed-in clients can read a pool but never write one; functions/test/pools.test.ts::§3.13 a shard is trimmed to 150 entries, newest first; functions/test/matching.test.ts::§3.13 runs land in a shard of the uploader level; all 4 shards are used; no self-match | done |
| R-3.13-16 | Function `onPlayerRunWrite` (2nd gen, europe-west1): validate, append to a random shard of the level, trim to 150, remove the player's older entries | 3.13 | 5a | functions/test/functions.test.ts::§3.13 a client upload of a new best lands in the pool of its level; functions/test/pools.test.ts::§3.13 a new best run goes to a shard of the server-recomputed level, newest first; functions/test/pools.test.ts::§3.13 the player older entries are removed from the shard (dedupe per uid) | done |
| R-3.13-17 | Client reads one pool doc at app start (own level, random shard; miss → random other level) and when candidates run out | 3.13 | 5b | test/versus/s3_13_service_test.dart::§3.13 initialize… (own level, random shard; on a miss another level); test/versus/s3_13_matching_nickname_test.dart::§3.13 pool read plan… | done |
| R-3.13-18 | Cheat filter: timeline length ≠ score (minus gifts), points < 0.9 s apart (not for ride/train), best < score, upload rate exceeded → reject | 3.13 | 5a | functions/test/pools.test.ts::§3.13 rejects: … (5 cases); functions/test/pools.test.ts::§3.13 the 4th non-best run of a UTC day is rejected; a new best still goes; the next day resets; functions/test/timeline.test.ts::§3.13 ride / train / gift points are exempt from the 0.9 s gap; functions/test/functions.test.ts::§3.13 a cheated timeline (points 0.5 s apart) is rejected and never reaches a pool | done |
| R-3.13-19 | App Check with Play Integrity on Firestore and the function | 3.13 | 5a / 5b | functions/test/functions.test.ts::§3.13 refuses a call without an App Check token (callable); Firestore enforcement = console step, docs/gameplay-v2/VERSUS-BACKEND.md §5; lib/services/firebase_versus_backend.dart (activateAppCheck); test/versus/s3_13_emulator_test.dart (opt-in, tool/versus_emulator_test.sh)::…deleteMyData needs App Check | done (client sends tokens; console enforcement = deploy step) |
| R-3.13-20 | TTL: pool entries and recent runs older than 60 days deleted; best runs stay while the player is active | 3.13 | 5a | functions/test/pools.test.ts::§3.13 entries older than 60 days are dropped on write; functions/test/pools.test.ts::§3.13 sweepPools trims > 60-day entries in every shard; functions/test/pools.test.ts::§3.13 recent runs older than 60 days are trimmed from the player doc; TTL on players.expireAt: firestore.indexes.json + functions/scripts/set_ttl.sh | done (TTL policy applied at deploy) |
| R-3.13-21 | Budget alert $5/month; Blaze plan (already set up) | 3.13 | 5a (verify) | docs/gameplay-v2/VERSUS-BACKEND.md §7 (Blaze + €5 budget recorded 2026-10-08; maxInstances 10) | done (from the setup record; no gcloud here to re-read the budget) |
| R-3.13-22 | Data-safety form lists user IDs, name, game progress shared with other players | 3.13 | 4c | SUBMISSION.md §6 "Data safety — what versus stores online" (fields, 60-day TTL, anonymous / Play Games id, App Check) | done |
| R-3.13-23 | "Delete my data" in Settings deletes players doc, pool entries (function), Firebase account, resets the Analytics ID; local progress untouched | 3.13 | 4c / 5a / 5b | functions/test/functions.test.ts::§3.13 deletes the player doc, their pool entries and the Auth user; idempotent; functions/test/pools.test.ts::§3.13 removes the player doc, the rate doc and the entries in every shard; idempotent; test/versus/s3_13_service_test.dart::§3.13 Delete my data…; test/versus/s3_13_delete_data_test.dart (row at 568 + 711, confirm, CANCEL / ✕ / Esc, DELETE reaches the service, failure text, `resetVersusData`); test/run/persistence_test.dart::§3.13 … resets the versus keys only; shot: build/menu_shots/settings_{568,711}*.png | done |
| R-3.13-24 | Every Firebase call wrapped: failure = solo, never a crash or blocked START | 3.13 | 5b | test/versus/s3_13_service_test.dart::§3.13 offline / any failure: solo, never a crash or a blocked START | done |
| R-3.13-25 | One shared pool for Android and iOS; never filtered by platform; `platform` stored for analytics only | 3.13 | 5a / 5b | functions/test/matching.test.ts::§3.13 platform is never used for matching (an iOS run matches an Android player); functions/test/functions.test.ts::§3.13 a client upload of a new best lands in the pool of its level; lib/versus/matcher.dart (never filters by platform) | done |
| R-3.13-26 | Identity: Play Games link on Android; Game Center (iOS) behind the same interface (stub until iOS reopens) | 3.13 | 5b | lib/services/identity.dart (PlayGamesIdentity, GameCenterIdentity stub) | done |
| R-3.13-27 | App Check providers: Play Integrity (Android), App Attest + DeviceCheck fallback (iOS, later); debug provider only in debug / FS_E2E | 3.13 | 5b | lib/services/firebase_versus_backend.dart (activateAppCheck) | done |
| R-3.13-28 | Looks: same catalogue ids on both platforms; unknown item → default look | 3.13 | 5b | test/versus/s3_13_upload_entry_test.dart::§3.13 cross-platform looks: unknown item ids fall back… | done |
| R-3.13-29 | iOS setup steps documented for when iOS reopens (no `ios/` changes now) | 3.13 | 5b | docs/gameplay-v2/ARCH.md §24 (iOS setup note) | done |
| R-3.13-30 | Before launch: cross-platform match test (iPhone ↔ Android) — deferred until iOS reopens | 3.13 | 6 | | todo |

## 3.14 Revive and results

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.14-1 | On a run-ending mistake: tumble, freeze with the dead bird on the floor under a dim overlay, offer for 5 s | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart; test/run/shots/revive_hud_shots_test.dart | done |
| R-3.14-2 | Offer only with ≥ 6 hoops passed (gifts don't count, ride hoops do); ≤ 5 → tumble then bonus/results after 1.5 s, no ladder step used (`reviveMinHoops = 6`) | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.14-3 | Price ladder per game: ad → 250 → 500 → 1 000 → doubling, no cap; resets each new game | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.14-4 | No ad available or no-ads owner on the 1st revive: "NO AD AVAILABLE" + gold heart 250, ladder continues 500, 1 000 … | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.14-5 | The whole heart is the button; ad heart: revive only after a fully watched ad; closed early / failed → offer returns with the remaining time | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.14-6 | Coin heart: `wallet.spend(price)`, coins fly from the pill into the heart, balance counts down, then revive | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.14-7 | Not enough coins: grey locked heart "🔒 REVIVE ● 250" + "need N more"; tap shakes (nope thud) | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.14-8 | GET COINS › opens the Shop as a GameWidget overlay on the paused game; countdown paused; music × 0.5; returns with remaining time; gold heart if enough coins now | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done (Flame overlay of the menus' ShopScreen over the paused game, not a Flutter widget overlay — call) |
| R-3.14-9 | Balance pill top-right on the revive screen | 3.14 | 2d | test/run/shots/revive_hud_shots_test.dart | done |
| R-3.14-10 | No thanks → bonus or results | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.14-11 | Countdown 5 s, urgency in the last 2 s, empty heart stays 1 s, then moves on | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.14-12 | Phoenix ≈ 1.65 s: flames around the dead bird, rise to the safe line in a flame column turning upright with flame wings, burst out | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart; test/run/shots/revive_hud_shots_test.dart | done |
| R-3.14-13 | Black Hole death: phoenix re-forms from the shock ring at the last position | 3.14 | 2d / 3d | test/run/screens/s3_14_revive_test.dart; test/run/hoops/s3_18_saw_test.dart::§3.14 / §3.0.5 a revive after a Black Hole death… | done (3d supplies the Black Hole death) |
| R-3.14-14 | Safe line = centre of the next hoop ahead (clamped to band), else band centre; drift back to x 70 while rising | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.14-15 | Straight back in at 1.65 s: no countdown, no slow motion; small upward flap; 2 s invulnerability | 3.14 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-3.14-16 | Kept: score, coins, hearts, feather/piece progress. Lost: running egg/chick, piggy, jar. Reset: streak + fire. Ended: timed powerups | 3.14 | 2d (+ 3e / 3f / 3c hooks) | test/run/screens/s3_14_revive_test.dart | done (state cleared generically; 3e / 3f / 3c add their visuals) |
| R-3.14-17 | Running squeeze resets to open during the phoenix (0.5 s); next 60–120 s later | 3.14 | 3g | test/run/screens/s3_14_revive_test.dart; test/run/items/s3_17_squeeze_test.dart::§3.17 / §3.14 a revived death during a squeeze | done |
| R-3.14-18 | First hoop after a revive is normal | 3.14 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.14-19 | Versus: opponent recording pauses during offer and phoenix | 3.14 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 the replay holds through the revive offer and the phoenix… | done |
| R-3.14-20 | Results page content: WIN/LOSE header, versus card (scores, WINNER), NEW BEST, level (emblem + bird, rank, progress), YOUR REWARD, NEXT → `goHome()` (new arrival) | 3.14 | 2e / 5b | test/run/screens/s3_14_s5_10_results_test.dart::§3.14 solo…; test/run/shots/results_shots_test.dart (versus parts: 5b); test/versus/s3_13_versus_run_test.dart::§3.13 / §5.10 WIN…; shot: build/shots/run/versus/results_* | done |
| R-3.14-21 | YOUR REWARD = run coins + puzzle coins + win/draw bonus, excluding balloon coins; one total, no breakdown | 3.14 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§3.14 YOUR REWARD includes puzzle coins… | done |
| R-3.14-22 | Solo: same page without versus card / header | 3.14 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§3.14 solo… | done |
| R-3.14-23 | Results replaces the 1.0 game-over panel; league strip and 2× coins ad removed; no ad on results | 3.14 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§3.14 solo…; test/services/ads_service_test.dart | done |
| R-3.14-24 | Levels = the 10 ranks of PRD-home-v3 §4.1 from best score; page shows the level after this run | 3.14 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§5.10 level bar…; §3.14 the model reads the level… | done |
| R-3.14-25 | Level up on the results page: celebration for the highest new level, rewards summed, CLAIM credits `wallet.add(level)` at the claim; replaces the home LEVEL UP popup | 3.14 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§3.14 level up (one level)…; §3.14 several levels… | done |
| R-3.14-26 | NEXT while CLAIM showing auto-claims with the same animation, then home | 3.14 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§3.14 NEXT while CLAIM shows…; §3.14 NEXT before CLAIM… | done |
| R-3.14-27 | App closed before claiming: `unclaimedLevelReward` credited at next start without animation | 3.14, 7 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§7 an unclaimed level reward is credited at the next app start… | done |

## 3.15 Golden feathers and the balloon bonus

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.15-1 | One feather per run max (revive = same run) | 3.15 | 4a | test/run/items/s3_15_feathers_test.dart::§3.15 / §3.0.3 one feather per run (gap 3–12, also across a revive)… | done (4a) |
| R-3.15-2 | Floats between hoops, collected by touch; missed = none that run | 3.15 | 4a | test/run/items/s3_15_feathers_test.dart::§3.15 a touched feather is banked at once… | done (4a) |
| R-3.15-3 | Spawn once in the gap after a random hoop 3–12 (pushed to the next free gap), only while < 3 held, never during rides; placement 0.65 × spacing after, 64–200 pt above | 3.15 | 0b / 4a | test/run/director/s3_0_3_director_test.dart; test/run/items/s3_15_feathers_test.dart::§3.15 / §3.0.3 one feather per run…; test/run/items/s3_15_feathers_test.dart::§3.15 no feather spawns while 3 are held | done (4a) |
| R-3.15-4 | Fetch animation into the feather tray (3 slots, y ≈ 206–254), tray fades out | 3.15 | 4a | test/run/items/s3_15_feathers_test.dart::§3.15 a touched feather is banked at once…; test/run/shots/collect_shots_test.dart | done (4a) |
| R-3.15-5 | 3rd feather: set-complete celebration + "BONUS UNLOCKED!" sticker | 3.15 | 4a | test/run/items/s3_15_feathers_test.dart::§3.15 the 3rd feather: set complete, BONUS UNLOCKED!… | done (4a) |
| R-3.15-6 | `feathers` 0–3 persistent; reset to 0 when the bonus screen opens | 3.15 | 4a | test/run/items/s3_15_feathers_test.dart::§3.15 a death keeps the banked feather…; test/run/screens/s3_15_bonus_screen_test.dart::§3.15 opens after the run with 3 feathers… | done (4a) |
| R-3.15-7 | Feathers don't affect score, coins, streak, duel | 3.15 | 4a | test/run/items/s3_15_feathers_test.dart::§3.15 feathers do not touch score, coins, streak | done (4a) |
| R-3.15-8 | Bonus screen after the run (offer declined/timed out) with 3 feathers, between revive and results | 3.15 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 opens after the run with 3 feathers…; test/run/screens/s3_15_bonus_screen_test.dart::§3.15 fewer than 3 feathers… | done (4a) |
| R-3.15-9 | 9 balloons; a tap uses a feather: feather flies in, stretch, pop, prize card + confetti, coins into the total pill | 3.15 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 opens after the run…; test/run/shots/collect_shots_test.dart | done (4a) |
| R-3.15-10 | Prizes coins only: 25, 25, 50, 50, 75, 75, 100, 150, 250 jackpot, shuffled per screen | 3.15 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 / Q35 prizes… | done (4a) |
| R-3.15-11 | Jackpot: gold card, gold screen flash, bigger confetti, big fanfare | 3.15 | 4a | test/run/shots/collect_shots_test.dart (balloon_next: jackpot card) | done (4a) |
| R-3.15-12 | Coins credited at each pop | 3.15 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 opens after the run… (wallet at the tap) | done (4a) |
| R-3.15-13 | Hero: "POP THE JACKPOT!" banner under a coin-heap circle with feather wings; no title | 3.15 | 4a | test/run/shots/collect_shots_test.dart (balloon_start) | done (4a) |
| R-3.15-14 | Out of feathers: "MORE FEATHERS?" + gold ad button ▶ feather ×3 alone for 3 s, then NO THANKS fades in | 3.15 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 out of feathers: ad offer alone, NO THANKS after 3 s… | done (4a) |
| R-3.15-15 | Ad → 3 feathers fly back → 3 more pops; ad once per bonus screen; after 6 pops only NEXT | 3.15 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 the ad gives 3 more feathers once; after 6 pops only NEXT | done (4a) |
| R-3.15-16 | No thanks / NEXT → results; unpopped balloons never revealed | 3.15 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 out of feathers… unpopped balloons never revealed… | done (4a) |
| R-3.15-17 | No ad available → skip offer, show NEXT; no-ads owners get 3 extra feathers without an ad (no video icon, once) | 3.15 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 no rewarded ad available…; test/run/screens/s3_15_bonus_screen_test.dart::§3.15 no-ads owners… | done (4a) |
| R-3.15-18 | Taps ignored while a balloon opens (≈ 1.1 s) | 3.15 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 opens after the run… taps ignored while a balloon opens | done (4a) |
| R-3.15-19 | Results YOUR REWARD excludes bonus coins | 3.15 | 2e / 4a | test/run/screens/s3_14_s5_10_results_test.dart::§3.14 YOUR REWARD includes puzzle coins… (balloon excluded); test/run/screens/s3_15_bonus_screen_test.dart::§3.15 out of feathers… YOUR REWARD excludes the bonus | done (4a) |
| R-3.15-20 | App killed on the bonus screen: remaining pops lost (Q39) | 10 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 opens after the run with 3 feathers; feathers back to 0… | done (4a) |
| R-3.15-21 | Tray waits until a banner has gone (Q37, same queue as Q42) | 10 | 4a / 0c | test/run/items/s3_15_feathers_test.dart::§3.15 / §3.16 the collect slot clears the banner band… (call: no overlap → no wait) | done (4a) |

## 3.16 Puzzle pieces

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.16-1 | One piece per run max (revive = same run); independent of feathers | 3.16 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 / §3.0.3 one piece per run… | done (4a) |
| R-3.16-2 | Bigger pickup (≈ 50 pt + tabs, rays, glow), collected by touch | 3.16 | 4a | test/run/items/s3_16_puzzle_test.dart::§5.15 knobs; test/run/shots/collect_shots_test.dart | done (4a) |
| R-3.16-3 | Only missing pieces spawn, in any order; the pill shows where it goes | 3.16 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 only a missing piece spawns… | done (4a) |
| R-3.16-4 | Spawn every run once in the gap after a random hoop 14–25, only while the round is incomplete; not in rides; placement as the feather | 3.16 | 0b / 4a | test/run/director/s3_0_3_director_test.dart; test/run/items/s3_16_puzzle_test.dart::§3.16 / §3.0.3 one piece per run… | done (4a) |
| R-3.16-5 | Fetch into the puzzle pill (y ≈ 206–254): colour pieces, grey silhouettes, "n/4"; fades out | 3.16 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 the slot sound follows the count held…; test/run/shots/collect_shots_test.dart | done (4a) |
| R-3.16-6 | 4/4: picture flashes + bounces, PICTURE COMPLETE sticker, coin badge counts up | 3.16 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 4/4: random 50–250…; test/run/shots/collect_shots_test.dart | done (4a) |
| R-3.16-7 | Reward uniform 50–250 in steps of 5, credited (`puzzle`) at the 4/4 moment in the run | 3.16 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 4/4: random 50–250 step 5 credited exactly once… | done (4a) |
| R-3.16-8 | YOUR REWARD includes puzzle coins (no separate line) | 3.16 | 2e / 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 4/4… YOUR REWARD includes it | done (4a) |
| R-3.16-9 | Rounds have their own colours; next round new colours; pill resets to grey | 3.16 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 4/4… (next round Pink, 1/4) | done (4a) |
| R-3.16-10 | 8 colours in order Pink, Sky, Gold, Ocean, Cocoa, Mint, Grape, Tangerine, then loop (themes as data) | 3.16, 5.15 | 4a | test/run/items/s3_16_puzzle_test.dart::§5.15 the 8 rounds in order… | done (4a) |
| R-3.16-11 | `puzzlePieces` (mask) and `puzzleRound` persistent; 4/4 sets mask 0 and round + 1 at once | 3.16, 7 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 4/4… mask 0 + round + 1 at once | done (4a) |
| R-3.16-12 | Tray/pill clash: second waits for the first to fade | 3.16 | 4a / 0c | test/run/effects/s3_0_9_parts_test.dart::Q37 / Q42 collect slot: one at a time… | done (4a) |
| R-3.16-13 | Slot sound by count held (1st collected plays slot1 whatever its position) | 3.16 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 the slot sound follows the count held, not the position | done (4a) |

## 3.17 Spike squeeze

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.17-1 | First squeeze at random 60–120 s runClock; next 60–120 s after fully open; any number per run | 3.17 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 a squeeze from start to open | done |
| R-3.17-2 | Never starts during a ride / comet / revive; waits until it ends + 2 s | 3.17 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 a squeeze never starts during a ride; ::§3.17 / §3.14 a revived death during a squeeze | done |
| R-3.17-3 | Open space between tooth tips: 50 / 45 / 40 / 35 % of screen height for squeeze 1 / 2 / 3 / 4+, never < 230 pt; both walls move (band − open)/2 | 3.17 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 each wall moves …; ::§3.17 open space … | done |
| R-3.17-4 | Phases: warning 1.5 s (shake 0 → 2.6, teeth flash red, falling bits, no text); closing 3 s ease-in-out (shake 2.2); lock (punch 6 pt, 0.35 s, dust); hold random 10–20 s, no indicator, last 3 s ticks + tremble; opening 3 s (shake 1.4, 0.8 s) | 3.17 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 a squeeze from start to open; ::§3.17 phases …; ::§3.17 shake … | done |
| R-3.17-5 | Moving walls are spike strips (mistake on touch; saves as 3.3 / 3.7) | 3.17 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 the moving walls are the spikes; ::§3.17 a save on a squeezed wall | done |
| R-3.17-6 | From 3 s before the warning until open, new hoops and pickups spawn only within the squeezed band (normal spacing, max jump clamped) | 3.17 | 0b / 3g | test/run/director/s3_0_3_director_test.dart; test/run/items/s3_17_squeeze_test.dart::§3.17 the window; test/run/items/s3_17_squeeze_autopilot_test.dart | done |
| R-3.17-7 | Hoop size, scroll, scoring unchanged; no extra reward | 3.17 | 3g | test/run/items/s3_17_squeeze_autopilot_test.dart (scoring / scroll untouched by the feature) | done |
| R-3.17-8 | HUD above the walls; score circle turns white while covered | 3.17 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 the score circle turns white; test/run/shots/squeeze_shots_test.dart | done |
| R-3.17-9 | Revived death during a squeeze: walls slide out over 0.5 s; next 60–120 s later | 3.17 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 / §3.14 a revived death during a squeeze | done |
| R-3.17-10 | Director during the window: specials only saw / FEVER / bullseye; gap items only scheduled hearts + star trails; no moving rings | 3.17 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.17-11 | Each player has their own squeeze moments in versus | 3.17 | 3g | (own `RunController` per run: own director timing stream) | done (by construction) |

## 3.18 Saw rings

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.18-1 | Touching any part of the rim = mistake (death or extra life/shield); no bounce | 3.18 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 / §3.0.5 touching the <design> rim kills…; test/run/hoops/s3_18_saw_test.dart::§3.18 the rim is deadly (no bounce)… | done |
| R-3.18-2 | Each spawn picks Live Wire / Frost Ring / Black Hole at random (equal), never the same twice in a row per run | 3.18 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 designs: each spawn picks one at random… | done |
| R-3.18-3 | Mandatory hoop: +1, coins, streak; a clean pass is always perfect | 3.18 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 a clean pass is an ordinary, always-perfect hoop… | done |
| R-3.18-4 | Collider: two circles at the ring ends, r 5 (Live Wire / Frost) or 6 (Black Hole) | 3.18 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 rim-end collider r = half the rim… | done |
| R-3.18-5 | On contact: design death moment, then tumble, then revive offer; with a save the ring is treated as passed (no score) | 3.18 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 / §3.0.5 touching the <design> rim kills…; test/run/hoops/s3_18_saw_test.dart::§3.18 with an armed shield the touch is saved… | done |
| R-3.18-6 | Visual effects never kill; only the rim | 3.18 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 Black Hole pull… (the opening centre is clear); the collider is the rim ends only | done |
| R-3.18-7 | Opening +28 pt vs a normal hoop at the same index; autopilot passes with saw rings | 3.18 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 a clean pass … +28 pt…; test/run/flow/s3_18_s3_20_s3_21_autopilot_test.dart | done |
| R-3.18-8 | Black Hole pull: within 34 pt of the rim 260 pt/s² toward the rim; inhale 0.9 s every 3.4 s at 570 pt/s² | 3.18 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 Black Hole pull…; test/run/hoops/s3_18_saw_test.dart::§3.18 the Black Hole pulls a bird near its rim toward it | done |
| R-3.18-9 | Spawn from 20, weight 18 (26 from 45), ≥ 3 apart; never the first hoop after a revive; upright and still | 3.18 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.18-10 | Band rule with the wider opening (also in a squeeze) | 3.18 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.18-11 | Comet / portal fly through saw rings; Big Hoops grows them but keeps the design | 3.18 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 the rim is deadly (no bounce); rides … fly through it (Big Hoops: the director scales the opening; the saw art ignores the gold) | done |
| R-3.18-12 | Saw rings keep their own look (no tier look) | 3.18 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 a clean pass … (no tier fx, no gold) | done |

## 3.19 Glowing ring (FEVER)

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.19-1 | Perfect pass sets streak to max(5, streak + 1); ≥ ×5 already → normal +1 (cap ×10) | 3.19 | 3c | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-3.19-2 | Bird catches fire until the streak breaks (graze or save); smoke puff + sizzle; visual only; tier look stays, fire on top | 3.19 | 3c | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-3.19-3 | Feedback: FEVER! banner (≈ 1.6 s, above the tier banner) + tier banner, +2, `perfect_3` + FEVER sound, ring pass effect | 3.19 | 3c | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-3.19-4 | Rim touch on the FEVER ring: normal hoop behaviour, no FEVER, no fire | 3.19 | 3c | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-3.19-5 | Points by the new streak (PRD-2.2 §13.1: ≥ 5), +2 coins; no extra FEVER bonus | 3.19 | 3c | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-3.19-6 | ~~Only the FEVER ring (and FEVER gift) lights the fire~~ superseded by PRD-2.2 §21: the 3rd perfect pass in a row lights the fire (one fire master, sizes ×3 / ×5 / ×7, flame-trail colours, 2× trail, crackle loop 25 % / FEVER volume); FEVER shows the same fire at ≥ ×5 size | 3.19 / 2.2 §21 | V2 | test/p22/s21_fire_test.dart; test/run/items/s3_19_fever_test.dart | done (P22-V2) |
| R-3.19-7 | Replaces a normal hoop; same opening, rim bounce, spacing, max jump | 3.19 | 3c | test/run/flow/s3_19_s3_22_s3_25_autopilot_test.dart | done (WP-3c) |
| R-3.19-8 | Spawn from 15, weight 6, ≥ 20 apart; not next to a saw ring or the portal (± 3); not while on fire; never tilted/moving | 3.19 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.19-9 | Not spawned during rides; a burning fire keeps burning through a ride | 3.19 | 3c | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-3.19-10 | Can spawn during a squeeze (inside the band) | 3.19 | 0b | test/run/director/s3_0_3_director_test.dart | done |

## 3.20 Switch rings

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.20-1 | Spawns closed; switch pickup floats in front; touch opens; reaching it closed = mistake | 3.20 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 <design>: spawns closed …; test/run/hoops/s3_20_switch_test.dart::§3.20 reaching the ring while it is still closed is a mistake… | done |
| R-3.20-2 | Five designs (Lockdown, Laser Gate, Power Iris, Snoozer, Gift Wrap) at random, never twice in a row per run; mixed in a run | 3.20 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 five designs at random… | done |
| R-3.20-3 | Mandatory hoop: same opening, spacing, max jump; once open it's a normal hoop (+1, coins, streak, bounce) | 3.20 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 <design>: … then a normal pass | done |
| R-3.20-4 | Switch 1.0 s × scroll before the ring (≥ 150 pt), gap otherwise empty, 70–100 pt above/below, ≤ 110 pt vertical from the previous hoop centre, never in a strip | 3.20 | 0b / 3d | test/run/director/s3_0_3_director_test.dart; test/run/hoops/s3_20_switch_test.dart::§3.20 <design>: spawns closed with its switch in the gap before… | done |
| R-3.20-5 | Touch: ring opens at once in logic (open animation ≤ 0.8 s); +1 coin with "+1 ●"; streak unchanged | 3.20 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 <design>: … +1 coin (switch), the ring opens at once (animation ≤ 0.8 s), the streak is unchanged…; test/run/hoops/s3_20_switch_test.dart::§3.20 / §5.19 every design opens within 0.8 s… | done |
| R-3.20-6 | Closed ring reached: crash animation + mistake; with a save the ring counts as passed (no score); streak resets | 3.20 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 reaching the ring while it is still closed…; test/run/hoops/s3_20_switch_test.dart::§3.20 with a shield the closed ring is saved… | done |
| R-3.20-7 | Always readable as closed; switch matches its ring (Iris draws a cable); no text tutorial | 3.20 | 3d | test/run/shots/hazard_rings_shots_test.dart (switchring_*_off: closed look, Iris cable) | done (visual) |
| R-3.20-8 | Spawn from 12, weight 14, ≥ 8 apart; not near the portal; never first after revive; upright still; not in rides or squeeze | 3.20 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.20-9 | Comet opens a closed switch ring already on screen | 3.20 | 3a / 3d | test/run/items/s3_8_comet_test.dart::§3.8 / §3.0.3 the comet flies through what is spawned… | part (3a: no closed-switch verdict in a ride); the opening look is 3d |
| R-3.20-10 | Big Hoops grows the ring (own design), switch stays the same size | 3.20 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 rules (pure) (the switch size / radius are fixed) | done |
| R-3.20-11 | Own look (no tier look); counts for the streak once open | 3.20 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 a closed ring at the plane is a mistake; open, a pass (no tier look) | done |
| R-3.20-12 | One `SwitchRing` kind with pluggable designs (barrier, decorations, switch sprite, open timeline, crash); autopilot steers to the switch first | 7 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 <design>: … the autopilot takes the switch first …; test/run/flow/s3_18_s3_20_s3_21_autopilot_test.dart | done |

## 3.21 Pairs of powerup rings

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.21-1 | A pair is one hoop: through one ring → its gift + normal scoring; perfect = no contact on the chosen ring | 3.21 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 flying through the top / bottom ring takes its gift… | done |
| R-3.21-2 | Through neither (between, above, below) = miss (mistake) | 3.21 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 flying through neither ring (between them) is a miss… | done |
| R-3.21-3 | Resolves once at the plane; the other ring + box shrink and fade (≈ 0.45 s) | 3.21 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 flying through the … ring … resolves once… | done |
| R-3.21-4 | Offset 230 × viewHeight / 711 (230 at 711, ≈ 184 at 568); both rings + tags fit between the HUD bottom (≈ 114) and the floor; one ring within max jump; else normal hoop | 3.21 | 0b / 3d | test/run/director/s3_0_3_director_test.dart; test/run/hoops/s3_21_pair_test.dart::§3.21 geometry at 711 / 568 pt… | done |
| R-3.21-5 | Two different rewards, weights Shield 25, Comet 20, Coins 25, Score 15, FEVER 15 | 3.21 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.21-6 | Effects: SHIELD arms; COMET starts the boost; +10 COINS (`pair`); +5 SCORE; FEVER (any pass) | 3.21 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 the <reward> gift does what it says; test/run/hoops/s3_21_pair_test.dart::§3.21 FEVER gift keeps a higher streak | done (COMET emits the WP-3a pair contract event) |
| R-3.21-7 | No useless reward: no shield if armed, no FEVER if on fire, no comet within 10 of a portal or while a timed powerup runs | 3.21 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.21-8 | Spawn from 12, weight 10, ≥ 15 apart, 2 normal hoops after; never in rides / squeeze; upright still; gifts on top of per-run limits | 3.21 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.21-9 | +5 SCORE counts in the duel | 3.21 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 the timeline records every point… | done |
| R-3.21-10 | Autopilot targets the nearer ring | 7 | 0b / 3d | lib/run/debug/autopilot.dart (nearest ring); test/run/flow/s3_18_s3_20_s3_21_autopilot_test.dart | done |

## 3.22 – 3.32 Smaller elements

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.22-1 | Ring Train: three rings 56 pt apart, ±16 pt steps in one direction, dotted track; one slot (next hoop at normal spacing after the 3rd) | 3.22 | 3c | test/run/hoops/s3_22_train_test.dart | done (WP-3c) |
| R-3.22-2 | Train rings are normal hoops (score, coins, streak, bounce); missing any is a miss | 3.22 | 3c | test/run/hoops/s3_22_train_test.dart | done (WP-3c) |
| R-3.22-3 | Combo dots fill gold; all three → +3 coins (`train`) + TRAIN ×3 banner + rising finish; a miss saved by a life → no combo; a rim touch still counts | 3.22 | 3c | test/run/hoops/s3_22_train_test.dart | done (WP-3c) |
| R-3.22-4 | Spawn from 8, weight 14, ≥ 10 apart, 2 normal after; not in rides / squeeze | 3.22 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.23-1 | Spring: pass sets vy −770 (up) or +420 (down) per its arrows; flap ignored 0.45 s / 0.28 s | 3.23 | 3c | test/run/hoops/s3_23_spring_test.dart | done (WP-3c) |
| R-3.23-2 | Next hoop placed 240 pt above/below (out of normal reach); normal in every other way | 3.23 | 0b / 3c | test/run/hoops/s3_23_spring_test.dart | done (WP-3c) |
| R-3.23-3 | Wobble on pass, "BOING ↑/↓" pop, boing sound | 3.23 | 3c | test/run/hoops/s3_23_spring_test.dart | done (WP-3c) |
| R-3.23-4 | Spawn from 10, weight 12, ≥ 10 apart, 2 normal after; up/down 50/50 with room; not in squeeze | 3.23 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.24-1 | Bullseye: normal hoop + target + dashed lines at ±12 pt (fixed as openings shrink) | 3.24 | 3c | test/run/hoops/s3_24_bullseye_test.dart | done (WP-3c) |
| R-3.24-2 | Centre inside the band = BULLSEYE +3 coins (`bullseye`), banner, flash, thunk + chord | 3.24 | 3c | test/run/hoops/s3_24_bullseye_test.dart | done (WP-3c) |
| R-3.24-3 | Spawn from 6, weight 20, ≥ 6 apart; upright still; allowed in squeeze | 3.24 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.25-1 | Lucky Spin: wheel on a post above the ring, spins freely, stops ≈ 0.9 s after the pass; slice paid as coins (`lucky_spin`) + banner | 3.25 | 3c | test/run/hoops/s3_25_lucky_spin_test.dart | done (WP-3c) |
| R-3.25-2 | Slices +2, +5, +10, +3, +20, +5 equal chance; prize pre-rolled at spawn from the `layout` stream; wheel animated to stop on it | 3.25 | 0b / 3c | test/run/hoops/s3_25_lucky_spin_test.dart | done (WP-3c) |
| R-3.25-3 | Spawn from 15, weight 8, ≥ 18 apart; upright still | 3.25 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.26-1 | Star Trail: 8 stars on an arc 40 pt after → 40 pt before the next hoop, bulging 40 pt up, dotted line; touch collects, rising scale notes | 3.26 | 3e | test/run/items/s3_26_star_trail_test.dart::§3.26 8 stars at u = (i+1)/9 …; ::§3.26 the arc: the stars sit on a 40 pt bulge …; test/run/items/s3_26_29_collect_autopilot_test.dart; shot: build/shots/run/collect/collect_trail_711.png | done (WP-3e) |
| R-3.26-2 | All 8 → PERFECT LINE +5 coins (`star_trail`); fewer → "n / 8", nothing; single stars pay nothing | 3.26 | 3e | test/run/items/s3_26_star_trail_test.dart::§3.26 all 8 stars: PERFECT LINE …; ::§3.26 fewer than 8: the "n / 8" pop, no coins … | done (WP-3e) |
| R-3.26-3 | Spawn from gap 5, weight 30, ≥ 8 gaps apart, empty gap only; allowed in squeeze | 3.26 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.27-1 | Egg pickup mid-gap puts the egg on the bird's back ("EGG! hatches in 5 rings") | 3.27 | 3e | test/run/items/s3_27_egg_test.dart::§3.27 the pickup goes on the bird's back …; test/run/items/s3_26_29_collect_autopilot_test.dart; shot: build/shots/run/collect/collect_egg_711.png | done (WP-3e) |
| R-3.27-2 | Every ring passed cracks it (countdown 4…1; PRD-2.2 §23: ride rings no longer count); after 5 it hatches into a chick ("HATCHED!") | 3.27 | 3e | test/run/items/s3_27_egg_test.dart::§3.27 every ring cracks it (a ride ring counts): countdown 4…1 … | done (WP-3e) |
| R-2.2-15 | PRD-2.2 §15: plan one slot ahead; every hoop / pickup created off-screen; feature follow-ups created inside pop in | 2.2 §15 | G2 | test/p22/s15_scroll_in_test.dart | done (P22-G2) |
| R-2.2-19 | PRD-2.2 §19: heart first at 5–27; early pool 4–9; feather / piece ≈ 60 % at 3–40, not neighbouring; single pickups 30–70 % / ±50 pt | 2.2 §19 | G2 | test/p22/s19_random_opening_test.dart | done (P22-G2) |
| R-2.2-27 | PRD-2.2 §27: one bonus at a time — activities, rewards ahead fade, 2-hoop cool-down, owed feather / piece, reward rings lose their gifts | 2.2 §27 | G2 | test/p22/s27_one_bonus_test.dart; test/p22/s27_one_bonus_director_test.dart | done (P22-G2) |
| R-2.2-23 | PRD-2.2 §23: a rim touch while still an egg breaks it quietly (shell + yolk pieces, `egg_crack`, no banner, `egg_broken {rim, cracks}`); the touched hoop doesn't crack; ride rings neither crack nor break | 2.2 §23 | G2 | test/p22/s23_egg_rim_test.dart | done (P22-G2) |
| R-3.27-3 | Chick: every coin earned counts double (ring coins and every bonus); gold ×2 badge under the score; pops read "+2 ×2" | 3.27 | 3e / 0b (earn) | test/run/items/s3_27_egg_test.dart::§3.27 the chick doubles every coin earned …; test/run/items/s3_28_piggy_test.dart::§3.28 the chick's ×2 stacks on the pay-out …; test/run/director/s3_0_3_director_test.dart | done (WP-3e / WP-0b earn) |
| R-3.27-4 | Any rim touch scares the chick ("bye!", "×2 LOST"); crash before hatching breaks the egg; a save also loses egg/chick; revive-offer death loses it | 3.27 | 3e | test/run/items/s3_27_egg_test.dart::§3.27 a rim touch scares the chick away …; ::§3.27 a crash before hatching breaks the egg …; ::§3.27 Q66 an extra life / shield save loses the chick too … | done (WP-3e) |
| R-3.27-5 | No extra coin pickups; spawn from gap 10, weight 12, ≥ 15 apart; one egg/chick at a time | 3.27 | 0b / 3e | test/run/director/s3_0_3_director_test.dart; test/run/items/s3_27_egg_test.dart::§3.27 5 rings, gap 10, weight 12, ≥ 15 apart, one egg / chick …; test/run/items/s3_26_29_collect_autopilot_test.dart | done (WP-3e / WP-0b) |
| R-3.28-1 | Piggy: grab → "PIGGY BANK"; exactly 20 coins: 4 in its gap then 4 per gap × 4 | 3.28 | 3e | test/run/items/s3_28_piggy_test.dart::§3.28 grabbing the piggy starts the bank …; ::§3.28 exactly 20 coins, 4 in the own gap … | done (WP-3e) |
| R-3.28-2 | Caught coins go into the bank; uncaught = missed | 3.28 | 3e | test/run/items/s3_28_piggy_test.dart::§3.28 caught coins go into the bank (not the wallet) and all 20 resolve … | done (WP-3e) |
| R-3.28-3 | When all 20 resolved: smash, pays ×2 of caught (`piggy`); HUD piggy, "n / 20", bar, "n missed" | 3.28 | 3e | test/run/items/s3_28_piggy_test.dart::§3.28 exactly 20 coins, 4 in the own gap, pays ×2 …; ::§3.28 caught coins go into the bank …; shot: build/shots/run/collect/collect_piggy_711.png | done (WP-3e) |
| R-3.28-4 | Crash before pay-out loses the bank (also with revive); a save keeps it; egg ×2 doubles the pay-out; portal removes on-screen coins without counting them missed | 3.28 | 3e | test/run/items/s3_28_piggy_test.dart::§3.28 Q66 a shield save keeps the bank …; ::§3.28 the chick's ×2 stacks on the pay-out …; ::§3.0.3 a portal ride clears the on-screen coins without counting them … | done (WP-3e) |
| R-3.28-5 | Spawn from gap 12, weight 10, ≥ 30 apart; never with a jar; its coins fill the next gaps | 3.28 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.29-1 | Jar: animated pickup; grab → "FIREFLY JAR"; fireflies only after the grab | 3.29 | 3e | test/run/items/s3_29_jar_test.dart::§3.29 grabbing the animated jar starts it …; ::§3.29 fireflies only appear after the jar is grabbed …; test/run/items/s3_26_29_collect_autopilot_test.dart; shot: build/shots/run/collect/collect_jar_711.png | done (WP-3e) |
| R-3.29-2 | Each following gap: swarm of 7 weaving ±45 pt around the line; catch radius 16 | 3.29 | 3e | test/run/items/s3_29_jar_test.dart::§3.29 a swarm of 7 weaves inside ±45 pt of the line; ::§5.28 look: the weaving swarm stays inside the ±45 pt band … | done (WP-3e) |
| R-3.29-3 | Uncaught firefly escapes; 3 ✕ marks; 20 caught = JAR FULL +25 (`jar`); 3 escaped = JAR BROKE, nothing; remaining fly away | 3.29 | 3e | test/run/items/s3_29_jar_test.dart::§3.29 20 caught = JAR FULL: +25 coins (jar) …; ::§3.29 3 escapes = JAR BROKE: no reward …; ::§3.29 20 caught fills the jar (+25), 3 escapes break it … | done (WP-3e) |
| R-3.29-4 | Crash loses it (also with revive); save keeps it; portal removes swarms without counting escapes | 3.29 | 3e | test/run/items/s3_29_jar_test.dart::§3.29 Q68 an extra life / shield save keeps the jar …; ::§3.0.3 a portal ride clears the swarms on screen without counting … | done (WP-3e) |
| R-3.29-5 | Spawn from gap 15, weight 10, ≥ 30 apart; never with a piggy | 3.29 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-3.30-1 | Capsule mid-gap on the line; flying into it starts the powerup at once (banner name + one line, start sound) | 3.30 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.0.8 / §3.30 a forced … capsule floats mid-gap on the line …; test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 / §6 a capsule starts its powerup at once … | done |
| R-3.30-2 | Timer pill near the top (y ≈ 206): icon + draining bar + seconds left | 3.30 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 the HUD stays real time; the timer pill …; shot: build/shots/run/capsules/capsule_hourglass_711.png | done (call: pill top y 156, above the y-190 banner band — ARCH §23) |
| R-3.30-3 | One timed powerup at a time (incl. comet); no capsule while one runs, nor in rides / squeeze; spawn from gap 10, weight 20, ≥ 20 apart; Hourglass 35 / Mini 35 / Frenzy 30 | 3.30 | 0b / 3f | test/run/director/s3_0_3_director_test.dart; test/run/items/s3_30_s3_32_capsules_test.dart::§3.0.3 / §3.30 spawn …; test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 a capsule collected while a ride runs starts nothing … | done |
| R-3.30-4 | Hourglass: whole world incl. bird at 45 % (scroll, gravity, flap, spawns, motion, animations), 0.2 s ease in/out; rules unchanged | 3.30 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 the world runs at 45 % (eased over 0.2 s) … | done |
| R-3.30-5 | Hourglass duration random 10–20 s real time, rolled at pickup | 3.30 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 the world runs at 45 % … the timer counts real time … | done |
| R-3.30-6 | Hourglass feedback: blue tint + vignette, ghost trail, clock ring with turning hand, tick every 0.6 s, music ≈ 72 % | 3.30 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 the world runs at 45 % … ticks every 0.6 s; music 72 % …; shot: build/shots/run/capsules/capsule_hourglass_711.png | done |
| R-3.30-7 | runClock timers (squeeze, comet, Big Hoops, versus) slow with it | 3.30 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 the world runs at 45 % … runClock slows with it … | done |
| R-3.31-1 | Mini Bird: shrink to 52 % (0.15 s ease) for 8 s; hitbox shrinks (rims, strips, pickups); physics unchanged | 3.31 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.31 the bird shrinks to 52 % over 0.15 s …; test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 a capsule collected while a ride runs … (touch radius × 0.52) | done |
| R-3.31-2 | Pops back at the end; rim bounce applies if touching while growing | 3.31 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.31 the bird shrinks to 52 % … then pops back … | done |
| R-3.31-3 | Feedback: purple sparkles in, bubbles trail, pop + burst at the end | 3.31 | 3f | shot: build/shots/run/capsules/capsule_mini_711.png | done |
| R-3.32-1 | Coin Frenzy: 6 s, every ring not yet passed is a coin ring paying +5 on top (`frenzy`); coin shower, cash sound, pulsing gold border | 3.32 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.32 every ring passed pays +5 on top …; shot: build/shots/run/capsules/capsule_frenzy_711.png | done |

## 3.33 Rumble

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.33-1 | Knock (15 ms, amp ≈ 90) on non-perfect pass and on every pickup (coins, stars, fireflies, hearts, shield, comet, feather, piece, switch, egg, piggy, jar, capsules) | 3.33 | 2c | test/run/items/s3_33_rumble_test.dart::§3.33 mapping | done |
| R-3.33-2 | Shake (45 ms, 255) on every perfect pass incl. pair, train, FEVER, comet and portal hoops; never grows | 3.33 | 2c | test/run/items/s3_33_rumble_test.dart::§3.33 mapping | done |
| R-3.33-3 | Nothing else rumbles (death, saves, rewards, squeeze, menus); vibration only, no screen shake added | 3.33 | 2c | test/run/items/s3_33_rumble_test.dart::§3.33 no rumble while paused | done |
| R-3.33-4 | Throttle one knock per 90 ms; a shake is never skipped; same window → only the shake | 3.33 | 2c (service exists) | test/run/items/s3_33_rumble_test.dart::§3.33 throttle; test/run/items/s3_33_rumble_test.dart::§3.33 a perfect pass that also collects | done |
| R-3.33-5 | Pass rumbles at the plane decision; pickup knocks at touch | 3.33 | 2c | test/run/items/s3_33_rumble_test.dart::§3.33 a perfect pass that also collects (flushed at the end of the frame of the decision / touch) | done |
| R-3.33-6 | Ignores SFX mute and music volume; own switch | 3.33 | 2c | test/run/items/s3_33_rumble_test.dart::§3.33 the RUMBLE switch | done |
| R-3.33-7 | No rumble on paused, revive, bonus, results screens; Hourglass doesn't change pulses | 3.33 | 2c | test/run/items/s3_33_rumble_test.dart::§3.33 no rumble while paused; test/run/items/s3_33_rumble_test.dart::§3.33 Hourglass | done |
| R-3.33-8 | Settings: RUMBLE row under MUSIC, toggle style as SOUND, phone icon, on by default, `rumble` stored, applies immediately (also to a paused run); row shown without a vibrator | 3.33 | existing (verify 2c) | test/rumble_test.dart (settings row, existing); test/run/items/s3_33_rumble_test.dart::§3.33 the RUMBLE switch | done |
| R-3.33-9 | Vibration plugin with amplitude (fallback plain pulse); VIBRATE permission; one `Rumble` service; no-op recorder in tests | 3.33 | existing (verify 2c) | test/rumble_test.dart (Rumble service, existing) | done |

## 3.34 Reminder notifications

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-3.34-1 | Local notifications only, no server / FCM | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 service reschedule lays out 14 filled reminders and persists the plan | done (local only; `ReminderPlatform` seam — no FCM/server) |
| R-3.34-2 | 20 English messages with `{best}` / `{coins}` filled at scheduling | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 messages 20 English messages, numbered 1-20; ::§3.34 messages {best} and {coins} are filled in | done |
| R-3.34-3 | New-player fallback (best 0) for #1 and #2 | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 messages new-player fallback for #1 and #2 (best 0) | done |
| R-3.34-4 | Two a day: midday random 11:30–13:30, evening random 18:30–20:30, local time | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 when two slots a day inside their windows | done |
| R-3.34-5 | Never 22:00–09:00, also across time-zone / DST changes | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 when nothing between 22:00 and 09:00, across DST and time-zone changes | done |
| R-3.34-6 | Skip a slot within 2 h after play | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 when a slot within 2 h after play is skipped | done |
| R-3.34-7 | Shuffled order, reshuffle after 20; no message twice within 10 days | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 order the rotation never repeats a message within 10 days; ::§3.34 order a long absence does not break the rotation | done (10 seeds + a 40-day absence) |
| R-3.34-8 | Android 13+: ask POST_NOTIFICATIONS once at first app start (before the first game); never again if declined; no prompt on ≤ 12 | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 service permission is asked once and the result is logged; ::§3.34 service a decline is final and logged; ::§3.34 service no prompt on an OS without one (Android <= 12) | done |
| R-3.34-9 | No in-game on/off switch; system channel "Reminders" | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 service reschedule lays out 14 filled reminders and persists the plan | done (no settings switch; channel "Reminders") |
| R-3.34-10 | Channel: default importance, custom sound `notif_chime` (from `notif_b.ogg`) set at creation (`reminders` id; change = new id), keep.xml for the raw file | 3.34 | 4b | integration_test/reminders_e2e_test.dart::WP-4b reminders: permission + the pending 7-day window; android/app/src/main/res/raw/keep.xml; `flutter build apk --debug` | done (channel `reminders`, `RawResourceAndroidNotificationSound(notif_chime)`) |
| R-3.34-11 | On every background / close: cancel all and schedule 7 days (at most 14 slots, a fixed 7-day horizon; dropped slots are not refilled), drop slots within 2 h, fill text, next messages in order; also at app start | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 lifecycle app start asks once and lays out the plan; leaving reschedules; ::§3.34 service a delivered slot advances the rotation, pending ones stay | done |
| R-3.34-12 | Inexact scheduling (`inexactAllowWhileIdle`), reboot rescheduling via the plugin | 3.34 | 4b | integration_test/reminders_e2e_test.dart::WP-4b reminders: permission + the pending 7-day window | done (`AndroidScheduleMode.inexactAllowWhileIdle`; no exact-alarm permission; boot receiver per plugin docs) |
| R-3.34-13 | Small icon white monochrome bird; large icon app icon | 3.34 | 4b | shot: android/app/src/main/res/drawable-*/ic_notif_bird.png (visual check) | done |
| R-3.34-14 | Tap opens the app on home (no deep links); `notif_opened` sent | 3.34 | 4b | test/services/s3_34_reminders_test.dart::§3.34 service tapping a reminder logs notif_opened | done (tap -> home, no deep links) |
| R-3.34-15 | Persisted: order, position, last-sent dates, permission-asked | 3.34 | 4b (keys 0b) | test/run/persistence_test.dart; test/services/s3_34_reminders_test.dart::§3.34 service reschedule lays out 14 filled reminders and persists the plan | done (0b keys; 4b reads/writes them) |
| R-3.34-16 | iOS later: same schedule (`UNCalendarNotificationTrigger`), `notif_chime.caf` — documented only | 3.34 | 4b | — | n/a: iOS paused; the schedule + `notif_chime.caf` are behind `ReminderPlatform` (Darwin settings present), no `ios/` edits |

## 4. Run flow

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-4-1 | Home START → [VS intro if opponent prefetched] → run | 4 | 0b / 5b | test/run/flow/s3_0_run_core_flow_test.dart; test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent… | done |
| R-4-2 | Mistake without save → tumble ≈ 1.5 s → revive offer (≥ 6 hoops) → ad / coins → phoenix → run | 4 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-4-3 | No thanks / timeout → [balloon bonus with 3 feathers] → results → NEXT → home (new slot roll) | 4 | 2d / 4a / 2e | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 out of feathers… → results; test/run/screens/s3_14_revive_then_results_test.dart | done (4a part) |
| R-4-4 | Pause any time in the run → RESUME → straight back in (no countdown) | 4, 5.7 | 2d | test/run/screens/s5_7_hud_pause_test.dart | done |
| R-4-5 | Puzzle needs no screen (paid in the run) | 4 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 4/4… (paid in the run) | done (4a) |

## 5.x Screens and visual specs

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-5.1-1 | In-game hoop M0: pink stroke 7, no posts / inner spikes, two layers; matches `hoops_m0.png` | 5.1 | 1a | shot: build/shots/run/hoops/run_568.png, run_711.png vs design/menu_v2/hoops_m0.png (test/run/shots/hoops_shots_test.dart) | done |
| R-5.1-2 | Non-perfect pass feedback: ring outline pulses 0.8 → 1.9 in ≈ 0.55 s, gold "+1" floats up; `point.mp3`; HUD increments | 5.1 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§3.1 a non-perfect pass plays point.mp3 and the §5.1 pulse | done |
| R-5.1-3 | Big Hoops look 1.5× and gold; matches `hoops_m0_big.png` | 5.1 | 2a | shot: build/shots/run/lives/big_heart_badge_*.png vs hoops_m0_big.png | done |
| R-5.2-1 | Heart pickup 32 pt `#FF3B5C`, 1.8 pt white outline, pulse 1.0 ↔ 1.14 (1 s), no glow | 5.2 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§5.2 the heart pickup pulses 1.0 ↔ 1.14 over 1 s; hit radius 16; shot: build/shots/run/lives/big_heart_badge_*.png | done |
| R-5.2-2 | "+1 coin" gold text with icon rising ≈ 30 pt, fading 1.6 s at the hoop (superseded by master #8 for passes) | 5.2 | 0c | | todo |
| R-5.2-3 | Saved: shards burst, "SAVED!" rises in pink, bird shakes briefly, hearts reset | 5.2 | 2a | test/run/screens/s5_7_hud_pause_test.dart | done (SAVED! shows in the RunHud banner band) |
| R-5.3-1 | Sparkle spec (colours, sizes per tier, twinkle 0.5–0.9 s, 45° → 90° spin, emission 7/16/38 per s) | 5.3 | 0c / 2b | test/run/effects/s3_0_9_parts_test.dart::§5.3 sparkles at 7 / 16 / 38 per second, sizes per tier | part (master 0c) |
| R-5.3-2 | Flame flicks tier 3+ (7–12 pt wide, 1.6–2.4× tall, rise 20–45 pt, 0.4–0.7 s) | 5.3 | 0c | test/run/effects/s3_0_9_parts_test.dart::§5.3 flame flicks and glow only from tier 3; glow fades in 0.25 s | part (master 0c) |
| R-5.3-3 | Glow tier 3+: radial gold ≈ 96 × 152 pt behind each ring (fade in 0.25 s) | 5.3 | 0c | test/run/effects/s3_0_9_parts_test.dart::§5.3 flame flicks and glow only from tier 3; glow fades in 0.25 s | part (master 0c) |
| R-5.3-4 | Graze: everything resets at once. The "GRAZE · streak lost" text is removed (PRD-2.3.1 §8, DEVIATION) | 5.3 | 2b | test/run/items/s3_4_streak_test.dart::§3.4 / §5.3 a graze resets the streak; test/p231/s8_graze_text_test.dart | done |
| R-5.4-1 | Perfect effects match `perfect_tier{1,2,3,5,10}.png` within the master rules (no shockwave rings, no flash, no confetti) | 5.4 | 2b | shot: build/shots/run/streak/tier{1,2,3,5,10}_{711,568}.png (test/run/shots/streak_shots_test.dart) — big rotating burst / shock rings / flash / confetti not copied (§3.0.9) | done |
| R-5.4-2 | Effects cosmetic, above hoops, below HUD, pooled ≤ 130 particles | 5.4 | 0c | test/run/effects/s3_0_9_parts_test.dart::§5.4 the pool caps particles at 130 and recycles them | part (pool 0c) |
| R-5.5-1 | Extra-life badge 34 pt above the bird ≈ 40 pt, bob ±4 pt ≈ 0.6 Hz, pops in 0.35 s after the heart flies to the indicator | 5.5 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 three hearts give one extra life … the badge pops in over the bird | done |
| R-5.5-2 | On a mistake: badge pops into hearts, indicator resets, bird flashes 2 s (25 % ↔ 100 % every 0.1 s) | 5.5 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 the extra life forgives one mistake …; shot: build/shots/run/lives/extra_life_pop_*.png | done |
| R-5.5-3 | Shield icon (pink fill, gold border, gold star white outline) for pickup and HUD | 5.5 | 2a | shot: build/shots/run/lives/shield_circle_*.png | done |
| R-5.5-4 | Shield circle 84 pt, gold 3.5 pt ring, 28 % soft-pink fill, dashed white inner ring 90°/s, pulse ±5 %, forms with a gold ring burst, hit: white flash + 12 shards | 5.5 | 2a | shot: build/shots/run/lives/shield_circle_*.png, shield_hit_*.png; test/run/items/s3_3_s3_7_lives_test.dart::§3.7 / §3.3 save order … (12 triangles) | done |
| R-5.6-1 | Comet pickup 46 pt star, white 2 pt outline, inner white star, pink + gold tail; wobble ±14°, pulse ±8 % | 5.6 | 3a | test/run/items/s3_8_comet_test.dart::§5.6 the pickup …; shots: build/shots/run/comet/comet_{pickup,active,tier,landing}_711.png, comet_active_568.png (test/run/shots/comet_shots_test.dart) | done |
| R-5.6-2 | Bird inside the fireball (bird 90 %, pink/gold shell, triangle tail), pixel-block shower | 5.6 | 3a | test/run/items/s3_8_comet_test.dart::§5.6 the fireball and countdown …; shots: build/shots/run/comet/comet_{pickup,active,tier,landing}_711.png, comet_active_568.png (test/run/shots/comet_shots_test.dart) | done (the pixel shower is the master #10 trail) |
| R-5.6-3 | Countdown ring r 34, gold 6 pt, drains 10 s inside the graphic; "10s → 1s" gold 18 pt 50 pt below | 5.6 | 3a | test/run/items/s3_8_comet_test.dart::§5.6 the fireball and countdown …; shots: build/shots/run/comet/comet_{pickup,active,tier,landing}_711.png, comet_active_568.png (test/run/shots/comet_shots_test.dart) | done |
| R-5.6-4 | Banners replace each other (never stack) during the boost; HUD unchanged | 5.6 | 3a / 0c | test/run/effects/s3_0_9_parts_test.dart::§5.6 banners replace each other, never stack; shots: build/shots/run/comet/comet_{pickup,active,tier,landing}_711.png, comet_active_568.png (test/run/shots/comet_shots_test.dart) | done |
| R-5.7-1 | HUD row y 52, 38 tall: heart indicator x 14 (38 × 38; PRD-2.3.1 §9 DEVIATION: no panel, the heart floats on the game) | 5.7 | 2d | test/run/screens/s5_7_hud_pause_test.dart; test/run/shots/revive_hud_shots_test.dart | done |
| R-5.7-2 | Versus bar x 60 → 260: two 90 × 38 boxes (you pink + dark-pink avatar outside; opponent stage grey), VS between, scores 26 pt; gold 3 pt outline flash when the opponent scores | 5.7 | 2d / 5b | test/run/screens/s5_7_hud_pause_test.dart; test/run/shots/revive_hud_shots_test.dart; test/versus/s3_13_versus_run_test.dart::§3.13 timeline replay on runClock… (out state); shot: build/shots/run/versus/hud_versus_* | done (avatars: neutral glyph, ARCH §24) |
| R-5.7-3 | Name chips 90 × 22 at y 92, white, plum Fredoka SemiBold 15 pt, ellipsis; VS same font | 5.7 | 2d | test/run/shots/revive_hud_shots_test.dart | done |
| R-5.7-4 | Pause button right edge 306 (38 × 38, pink, two bars) | 5.7 | 2d | test/run/screens/s5_7_hud_pause_test.dart | done |
| R-5.7-5 | Score circle only (no small HUD circle); no coin total in the HUD | 5.7 | 2d | test/run/screens/s5_7_hud_pause_test.dart | done |
| R-5.7-6 | Solo HUD: no versus bar; heart and pause in place | 5.7 | 2d | test/run/screens/s5_7_hud_pause_test.dart | done |
| R-5.7-7 | Pause screen: dark overlay, bg card, "PAUSED" pink 34 pt 0.14 em, gold RESUME (56 tall), sound + settings pink buttons; no Quit | 5.7 | 2d | test/run/screens/s5_7_hud_pause_test.dart; test/run/shots/revive_hud_shots_test.dart | done |
| R-5.7-8 | RESUME straight back in; opponent's run paused with the player | 5.7 | 2d / 5b | test/run/screens/s5_7_hud_pause_test.dart; test/versus/s3_13_versus_run_test.dart::§3.13 timeline replay on runClock… | done |
| R-5.8-1 | VS layout: top stage panel (fg 26 %) with opponent, bottom soft-pink panel with you, zigzag seam (22 pt teeth, period 32), spike strips above panels | 5.8 | 5b | shot: test/run/shots/versus_shots_test.dart (vs_*) | done |
| R-5.8-2 | Plates: opponent x 44 y 80 (232 × 52), you x 44 y 584, avatar + name + level emblem at 0.32× in the 52 pt slot (overhanging, animated) | 5.8 | 5b | shot: test/run/shots/versus_shots_test.dart; test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent… | done |
| R-5.8-3 | Levels: yours from your best, opponent's from their stored best | 5.8 | 5b | test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent…; test/versus/s3_13_upload_entry_test.dart::§3.13 JSON round trip… (level from their best) | done |
| R-5.8-4 | Birds 2.2× in equipped skins (opponent mirrored), always alive (bob, flap, tail, blink, accessories), one-off reactions | 5.8 | 5b | shot: test/run/shots/versus_shots_test.dart | done (no separate tail wiggle: the LookPainter has no tail part, ARCH §24) |
| R-5.8-5 | VS square pink 100 × 56 at (110, 316), soft-pink 42 pt | 5.8 | 5b | shot: test/run/shots/versus_shots_test.dart | done |
| R-5.8-6 | Stripes background: top 45° fg 9 % drifting left 39.6 pt / 3.2 s; bottom −45° pink 7 % drifting right; floating squares; shake shows fg grey | 5.8 | 5b | shot: test/run/shots/versus_shots_test.dart | done |
| R-5.8-7 | Timeline ≈ 6.3 s (tap squash, panels slide 0.42 s, your bird flies in, emblem pop, opponent plate drops, FINDING RIVAL…, name reel 20 names easing 40 + 330·p^2.4 ms, lock flash + emblem + MATCH FOUND! + confetti 80 + 3 fireworks, opponent flies in, VS punch + shake + lunge, taunts, 0.3 s white fade) | 5.8 | 5b | test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent… | done (≈ 7.3 s from the mock timings, ARCH §24) |
| R-5.8-8 | Reel always lands on the real prefetched opponent; filler names random display names | 5.8 | 5b | test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent… | done |
| R-5.8-9 | Avatars from cache; neutral avatar while missing | 5.8 | 5b | lib/run/screens/versus_intro.dart (neutral avatar) | part (neutral avatar always; image loading not built, ARCH §24) |
| R-5.8-10 | Music keeps playing; flaps use flap.mp3; intro SFX as files through pools | 5.8 | 5b / 3h | test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent… | done |
| R-5.8-11 | Not skippable; taps ignored | 5.8 | 5b | test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent… (taps do nothing) | done |
| R-5.9-1 | Offer background: frozen game, miss ghost, dead bird on the floor, 62 % overlay, strips remain | 5.9 | 2d | test/run/shots/revive_hud_shots_test.dart | done |
| R-5.9-2 | Heart 226 pt at x 47 y ≈ 222, drains from the top over 5 s; ad / coins / locked styles exactly as specified | 5.9 | 2d | test/run/screens/s3_14_revive_test.dart; test/run/shots/revive_hud_shots_test.dart | done |
| R-5.9-3 | NO AD AVAILABLE 34 pt above; GET COINS › 22 pt under (locked only); No thanks 86 pt under; balance pill (x → 306, y 58) | 5.9 | 2d | test/run/shots/revive_hud_shots_test.dart | done |
| R-5.9-4 | Urgency as V1 (shake from 3 s, heartbeat 1.2 → 3 Hz to 1.06, red edge glow, ease-out 4.6–5.5 s; idle beat 1.25 Hz 1.035) | 5.9 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-5.9-5 | Tap → pay: ad (pop, fade 0.25 s, ad); coins (10 coins fly 0.5 s each 0.05 apart + ticks, balance counts down 0.7 s, pill squeezes, heart flashes); locked (shake ±9 pt, GET COINS bumps) | 5.9 | 2d | test/run/screens/s3_14_revive_test.dart; test/run/shots/revive_hud_shots_test.dart | done |
| R-5.9-6 | Phoenix timeline 0–0.5 / 0.5–1.0 / 1.0 burst / 1.0–1.65 / 1.65 exactly as the table (flames, rise, wings, 34 feathers, 46 embers, shockwave 20 → 170) | 5.9 | 2d | test/run/screens/s3_14_revive_test.dart; test/run/shots/revive_hud_shots_test.dart | done |
| R-5.9-7 | Sounds `rv_pay`, `rv_ignite`, `rv_burst`, `rv_locked`, `bn_coin` per coin, `flap.mp3` on resume | 5.9 | 2d | test/run/screens/s3_14_revive_test.dart | done |
| R-5.10-1 | Layout: header y 70 (pink YOU WIN! / grey YOU LOSE), versus card y 124, NEW BEST sticker y ≈ 238, level stage y 262 (emblem 0.62 at (160, 346) + bird), rank line y 414, bar y 444, YOUR REWARD y 494 + pill y 512, NEXT y 596 | 5.10 | 2e / 5b | test/run/shots/results_shots_test.dart | done |
| R-5.10-2 | Draw: "DRAW" grey, both scores plum, no WINNER tag, +5 in reward | 5.10 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 / §5.10 DRAW…; shot: build/shots/run/versus/results_draw_* | done |
| R-5.10-3 | Sequence: level before → count-ups 0.45 s → NEW BEST 1.2 s → bar fill 1.65 s → LEVEL UP (flash, shake, pop, rays, banner, rank bounce, confetti 60/100/150 + 3 fireworks; lv 9–10 second wave) → CLAIM button +0.9 s pulsing → claim (12 coins, count-up, pill bump, confetti) → bar refills | 5.10 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§5.10 new best…; §3.14 level up…; §5.10 lv 9-10…; test/run/shots/results_shots_test.dart | done |
| R-5.10-4 | Sounds `perfect_1` (NEW BEST), `lv_bar`, `lv_up` / `lv_up_big`, `lv_claim`, `bn_coin` | 5.10 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§5.10 new best…; §3.14 level up…; §5.10 lv 9-10… | done |
| R-5.10-5 | Solo: no header, card shows only you centred | 5.10 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§3.14 solo…; test/run/shots/results_shots_test.dart | done |
| R-5.11-1 | Angled rings match `rings_angled.png` (no labels) | 5.11 | 1b | shot: build/shots/run/rings/5_11_angled_{711,568}.png vs rings_angled.png | done |
| R-5.12-1 | Guides: dashed fg 2.5 pt 6/6, 75 %, arrowheads 13 × 12, 16 pt end caps, behind the ring, attached to the home position | 5.12 | 1b | shot: build/shots/run/rings/5_12_*.png vs moving_1..4.png; test/run/hoops/s3_11_moving_rings_test.dart::§5.12 guide painter… | done |
| R-5.12b-1 | Portal ring ellipse 64 × 150, front `#7C4DFF` 9 pt + cyan 3 pt inner rim, back `#4B2BB8`, 13 % cyan fill, beam 66 × 126 pulsing 75–100 % | 5.12b | 3b | lib/run/hoops/kinds/portal.dart (PortalConfig); shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.12b-2 | Ride rings: the standard ring rotated to the heading with tier looks | 5.12b | 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.12 chain…; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.12b-3 | Cannon art (120 × 150, barrel, muzzle, spikes, bands, base, square wheels) and violet ground with cyan line | 5.12b | 3b | lib/run/rides/themes/cannon.dart; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.12b-4 | Strips as a repeating 40 × 44 tooth mask so teeth scroll (same approach in the game) | 5.12b | 0c | lib/run/effects/spike_teeth.dart (offset scroll); shot: 01_strip_72_reach.png | part (0c) |
| R-5.12b-5 | Z-order back halves 5 < bird 10 < cannon 11 < front halves 12; bird raised to 12 after the shot | 5.12b | 3b | lib/run/config/portal_config.dart (worldPriority, frontPriority 11, birdAfterShot 12); shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.12b-6 | Themed rides share portal, rings, bird, trail, banners, popup, burst, speed lines, HUD, score circle; no track line; ride position offset 66, 40 pt over 1.6 s; speed to 480 over 2.2 s; strips fade 0.8 s | 5.12b | 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.12 entering…; test/run/rides/s3_12_portal_ride_test.dart; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.12b-7 | Way back for every ride: launch flight 1.7 s (camera eases 110→140, 330→310, theme wash tint per ride), glide 2.5 s + 0.6 s settle, strips fade in 0.3 s with scrolling teeth, speed lines thin out 1.4 s, hoops ≈ 1 s after landing | 5.12b | 3b | test/run/rides/s3_12_ride_rules_test.dart::§3.12 the shot…; test/run/rides/s3_12_portal_ride_test.dart; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.12b-8 | Space trip (path, world, Mars landing, rocket launch, nose pop) + sounds `rd_space_land/rocket/pop` | 5.12b | 3b | lib/run/rides/themes/space.dart; test/run/rides/s3_12_portal_ride_test.dart::§3.12 space…; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.12b-9 | Volcano eruption (path, world, outside view, eruption shot) + `rd_volc_rumble/erupt` | 5.12b | 3b | lib/run/rides/themes/volcano.dart; test/run/rides/s3_12_portal_ride_test.dart::§3.12 volcano…; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.12b-10 | Deep sea dive (path, world, whale spout) + `rd_sea_splash/bubble/whale`, `rd_space_land`, `rd_sea_spout` | 5.12b | 3b | lib/run/rides/themes/sea.dart; test/run/rides/s3_12_portal_ride_test.dart::§3.12 sea…; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.12b-11 | Pinball (lanes, bumpers +500, spinning ball bird, flipper → jackpot loop → plunger) + `rd_pin_bumper/flipper/jackpot/plunger` | 5.12b | 3b | lib/run/rides/themes/pinball.dart; test/run/rides/s3_12_portal_ride_test.dart::§3.12 pinball…; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.12b-12 | Storm & tornado (corkscrew 4.2 turns r 150 → 70, depth scale ±12 %, debris, lightning, spit-out, pink umbrella) + `rd_storm_thunder/wind/umbrella` | 5.12b | 3b | lib/run/rides/themes/storm.dart; test/run/rides/s3_12_ride_rules_test.dart::§5.12b storm: a 4.2-turn corkscrew…; shots: build/shots/run/rides/ride_<id>_{1,2,3}_{711,568}.png (test/run/shots/rides_shots_test.dart) | done |
| R-5.13-1 | Miss flash on every miss (normal + all special kinds; both rings of a pair), also when saved; not for saw / closed switch / spikes | 5.13 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§5.13 a miss plays the shock-ring miss flash … | done (one shockwave per ring offset; special kinds: their WPs) |
| R-5.13-2 | Sequence: white flash 0–0.12 (stroke 8, glow 24); red `#FF1F3D` shockwave 1 → 2.6× 0–0.55; red edge glow 0–0.7 (180 → 430 pt radii, 0 → 0.55 → 0); drain to grey + dashed 0.12–0.52; grey dashed ghost stays and scrolls | 5.13 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§5.13 …; shot: build/shots/run/hoops/miss_(flash, wave, ghost)_(568, 711).png vs miss_c_*.png | done |
| R-5.13-3 | World keeps easing to a stop; tier look cleared on the missed hoop; `miss_shock` sound; no rumble | 5.13 | 1a | test/run/flow/s3_1_hoop_flow_test.dart::§5.13 … (missShock); test/run/flow/s3_1_hoop_flow_test.dart::§3.0.5 the world eases to a stop | done (tier look: Hoop.look.missed for 2b) |
| R-5.14-1 | Feather art (vane `#FFB529`/`#F09A0A`, notches, pink quill, white outline, ≈ 20 × 44, 20° tilt, flat) and idle (bob, pulse, sway, drift, twinkles every 0.28 s) | 5.14 | 4a | test/run/items/s3_15_feathers_test.dart::§5.14 feather art, idle and tray numbers; test/run/shots/collect_shots_test.dart | done (4a) |
| R-5.14-2 | Touch fx + swell ×1.4 + 0.62 s curved flight into the tray shrinking to 0.82, turning 26°, block trail | 5.14 | 4a | test/run/items/s3_15_feathers_test.dart::§5.14 fetch: swell ×1.4 from the pickup…; test/run/shots/collect_shots_test.dart | done (4a) |
| R-5.14-3 | Tray: centre (160, 230), 132 × 48, three 36 pt slots at −42 / 0 / +42; fades in sliding 10 pt; landing punch ×1.38, gold ring, 6 sparkles; fades ≈ 2.15 s after touch | 5.14 | 4a | test/run/items/s3_15_feathers_test.dart::§5.14 feather art, idle and tray numbers; test/run/shots/collect_shots_test.dart | done (4a) |
| R-5.14-4 | 3rd feather: gold flash, bounces, 26 confetti, ring 20 → 90, sticker "BONUS UNLOCKED!"; holds ≈ 3.4 s | 5.14 | 4a | test/run/items/s3_15_feathers_test.dart::§3.15 the 3rd feather…; test/run/shots/collect_shots_test.dart | done (4a) |
| R-5.14-5 | Bonus screen: total pill (x 204 → 306, y 52), hero r 42 at (160, 146) with rays + coin heap + feather wings, banner y 188, grid panel x 14 → 306 y 222 → 522 with nine 88 pt tiles, balloons, prompt y 541, feather row y 588, ad button y 562, NO THANKS y ≈ 641, NEXT y 562 | 5.14 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§5.14 geometry knobs; test/run/screens/s3_15_bonus_screen_test.dart::§5.14 layout…; test/run/shots/collect_shots_test.dart | done (4a) |
| R-5.14-6 | Pop timeline (feather 0.42 s, stretch 0–0.32, pop at 0.32 with scraps, card at 0.6 overshoot, ring + confetti, 3–8 coins 0.5 s each 0.07 apart); prize card + jackpot variant | 5.14 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§5.14 geometry knobs; test/run/screens/s3_15_bonus_screen_test.dart::§5.14 3–8 coins fly per prize…; test/run/shots/collect_shots_test.dart | done (4a) |
| R-5.14-7 | After the ad: three feathers fly back (0.5 s each, 0.22 apart) with slot chimes; NEXT fades in ≈ 0.3 s after the last coin | 5.14 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 the ad gives 3 more feathers once… | done (4a) |
| R-5.15-1 | Picture 48 × 48 in the round's colours, 2 × 2 jigsaw (24 pt cells, pinwheel tabs), white 4 pt outline + 1.1 pt edge line | 5.15 | 4a | test/run/items/s3_16_puzzle_test.dart::§5.15 2 × 2 cut, 24 pt cells, pinwheel tabs…; test/run/shots/collect_shots_test.dart | done (4a) |
| R-5.15-2 | Field piece ×2.1 with radial glow + 8 rotating rays; idle bob/pulse/rock; twinkles every 0.22 s; touch fx (r 10 → 40, ring 10 → 52, 16 squares) + 0.62 s flight + trail | 5.15 | 4a | test/run/items/s3_16_puzzle_test.dart::§5.15 knobs; test/run/shots/collect_shots_test.dart | done (4a) |
| R-5.15-3 | Pill centre (160, 230) 140 × 64; board at x −32, silhouettes fg 40 %, "n/4" Opificio 24 at +34; landing punch; fades ≈ 2.15 s | 5.15 | 4a | test/run/items/s3_16_puzzle_test.dart::§5.15 knobs; test/run/shots/collect_shots_test.dart | done (4a) |
| R-5.15-4 | 4/4: flash, bounces 0.08 apart, board pop ×1.15 + gold frame, 22 confetti, ring 20 → 100, "n/4" plum, sticker PICTURE COMPLETE; coin badge 0.55 s later (7 coins, `col4_coins`, count-up 0.8 s, bump); hold until ≈ 4.6 s | 5.15 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 4/4…; test/run/shots/collect_shots_test.dart | done (4a) |
| R-5.15-5 | The 8 round colour hexes (card, body, wing + tail, beak, sparkles) as data | 5.15 | 4a | test/run/items/s3_16_puzzle_test.dart::§5.15 the 8 rounds in order, hexes as data, looped | done (4a) |
| R-5.16-1 | Walls: the normal strip moves as one piece (solid part grows, teeth ride on it), one flat stage-fg grey | 5.16 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 a squeeze from start to open; test/run/shots/squeeze_shots_test.dart | done |
| R-5.16-2 | Warning flash: teeth blend to `#FF3B5C` pulsing every 0.5 s through the warning and the first 0.4 s of closing | 5.16 | 3g | test/run/items/s3_17_squeeze_test.dart::§5.16 warning flash; test/run/shots/squeeze_shots_test.dart | done |
| R-5.16-3 | Falling bits 2–5 pt ≈ 28/s (warning, closing, opening), fade 0.7 s; lock dust 40 squares 3–7 pt | 5.16 | 3g | test/run/items/s3_17_squeeze_test.dart::§5.16 bits …; ::§3.17 a squeeze from start to open | done |
| R-5.16-4 | Shake: whole view; exposed edges show the wall grey | 5.16 | 3g | test/run/items/s3_17_squeeze_test.dart::§5.16 / §5.18 / §5.17 the squeeze shake composes | done |
| R-5.16-5 | Sounds `sq_warn`, `sq_close`, `sq_lock`, `sq_hold` (loop, wav/ogg), `sq_tick` × 3, `sq_open`; music keeps playing; hold loop stops when opening starts | 5.16 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 a squeeze from start to open; ::§5.16 the hold loop stops in pause | done |
| R-5.17-1 | Saw rings not stage-tinted; two render layers; danger hum per design fading with closeness² | 5.17 | 3d | test/run/hoops/s3_18_saw_test.dart::§5.17 the danger hum fades in…; test/run/shots/hazard_rings_shots_test.dart | done |
| R-5.17-2 | Live Wire look (navy core, cyan glow, filament, 3–4 forked arcs redrawn 18×/s, big strike ≈ 9 %, near-miss bolt within 46 pt) | 5.17 | 3d | test/run/shots/hazard_rings_shots_test.dart (sawring_electric_fly) | done (visual) |
| R-5.17-3 | Live Wire death (0.6 s held: jitter, spikes, lightning, X-ray alternation; then charred tumble, smoke, twitches) + sounds | 5.17 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 / §3.0.5 touching the liveWire rim kills…; test/run/shots/hazard_rings_shots_test.dart (sawring_electric_death) | done |
| R-5.17-4 | Frost Ring look (rim colours, frost zig-zag, icicles, shard clusters at 46 points, fog, snow) | 5.17 | 3d | test/run/shots/hazard_rings_shots_test.dart (sawring_ice_fly) | done (visual) |
| R-5.17-5 | Frost death (blue, ice block 0.3 s, cracks 0.38 s, tumble, shatter on the spikes, frozen bird stays) + sounds | 5.17 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 / §3.0.5 touching the frostRing rim kills… (shatters); test/run/shots/hazard_rings_shots_test.dart (sawring_ice_death) | done |
| R-5.17-6 | Black Hole look (black torus 16 pt, photon ring, plasma, void ≈ 36 pt, spiralling stars, ripples, strips bend toward it within ≈ 170 pt; inhale every 3.4 s for 0.9 s) | 5.17 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 Black Hole pull… (inhale 0.9 s / 3.4 s); test/run/hoops/s3_18_saw_test.dart::§3.18 the Black Hole pulls… (strips bend); test/run/shots/hazard_rings_shots_test.dart (sawring_hole_fly) | done |
| R-5.17-7 | Black Hole death (pulled, stretched, spun, shrunk 0.8 s, rumble + darkening, boom + white shock ring, nothing left) + sounds | 5.17 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 / §3.0.5 touching the blackHole rim kills… (swallowed, no body); test/run/shots/hazard_rings_shots_test.dart (sawring_hole_death) | done |
| R-5.18-1 | FEVER ring look: red rim + dark-red outline + orange glow, 30 boiling beads 12×/s, inner gold ring, 3 plasma loops, golden beam ≈ 125 pt with 8 streaks, warm halo, sparkles, embers | 5.18 | 3c | test/run/items/s3_19_fever_test.dart + test/run/shots/special_hoops_shots_test.dart | done (WP-3c) |
| R-5.18-2 | FEVER pass effect: three light rings 0.09 s apart, ≈ 26 plasma flames, beam/halo flare, warm screen flash ≈ 0.3 s, small shake 6 pt | 5.18 | 3c | test/run/items/s3_19_fever_test.dart + test/run/shots/special_hoops_shots_test.dart | done (WP-3c) |
| R-5.18-3 | Bird on fire: ≈ 115 teardrop flames/s, warm halo, behind the bird; out: smoke + sizzle | 5.18 | 3c | test/run/items/s3_19_fever_test.dart + test/run/shots/special_hoops_shots_test.dart | done (WP-3c) |
| R-5.18-4 | FEVER! banner: Opificio 44 pt gradient `#FFF59D` → `#FF9800` → `#E64A19`, plum 7 pt outline, pop 0.6 → 1.1 → 1, tilt + jitter, ≈ 1.6 s above the tier banner | 5.18 | 3c | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-5.18-5 | Sounds: FEVER pass (whoosh + boom + chord on top of `perfect_3`), burning crackle loop, fire-out sizzle | 5.18 | 3c / 3h | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-5.19-1 | Switch rings not stage-tinted; barrier + back half behind the bird, front decorations in front | 5.19 | 3d | test/run/shots/hazard_rings_shots_test.dart (switchring_*) | done (visual) |
| R-5.19-2 | Switch pickups 40–46 pt, bob, halo, twinkles; touch fx + "+1 ●"; Laser button / Iris lever stay to show ON then fade | 5.19 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 / §5.19 every design opens within 0.8 s… (stay 0.3 / 1.1 s); test/run/shots/hazard_rings_shots_test.dart | done |
| R-5.19-3 | Open words: POWER OFF (green), POWER ON (gold), WAKE UP! (purple), SNIP! (pink); Lockdown uses CLEAR! sign | 5.19 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 / §5.19 … the open words…; test/run/shots/hazard_rings_shots_test.dart (switchring_*_open) | done |
| R-5.19-4 | Crash: tumble (+180 straight back), design crash effect + sound, red banner LOCKED! / ZAPPED! / SHUT! / HMPF! / WRAPPED!, then normal death flow | 5.19 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 reaching the ring while it is still closed… (knock −x, red banner word); test/run/shots/hazard_rings_shots_test.dart (switchring_*_fail) | done |
| R-5.19-5 | Lockdown look + key + 0–0.5 s open timeline (key arc, turn, links fly, padlock drops, siren green ✓, CLEAR!) + crash | 5.19 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 lockdown: …; test/run/shots/hazard_rings_shots_test.dart (switchring_lock_*) | done |
| R-5.19-6 | Laser Gate look + button + timeline (press, 0.12 s power-down, beams retract 0.4 s) + crash | 5.19 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 laserGate: …; test/run/shots/hazard_rings_shots_test.dart (switchring_laser_*) | done |
| R-5.19-7 | Power Iris look + cable + lever + timeline (flip, spark along cable, bulbs, iris open 0.5–0.8 s) + crash | 5.19 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 powerIris: …; test/run/shots/hazard_rings_shots_test.dart (switchring_iris_*) | done |
| R-5.19-8 | Snoozer look + alarm clock + timeline (ring, eyes open 0.2, yawn 0.38–0.73, fill fades 0.78) + crash (spit back) | 5.19 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 snoozer: …; test/run/shots/hazard_rings_shots_test.dart (switchring_sleepy_*) | done |
| R-5.19-9 | Gift Wrap look + scissors + timeline (fly, snips, cut at 0.5, paper tears, confetti 34) + crash (drum bounce) | 5.19 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 giftWrap: …; test/run/shots/hazard_rings_shots_test.dart (switchring_gift_*) | done |
| R-5.19-10 | Sounds per design (switch touched, opening, crash) + shared "clear" chord; pass plays `perfect_1/2/3` | 5.19 | 3d / 3h | test/run/hoops/s3_20_switch_test.dart::§3.20 <design>: … (touch + opening sounds); test/run/hoops/s3_20_switch_test.dart::§3.20 reaching the ring … (crash sound) | done |
| R-5.20-1 | Reward colours and icons (Shield, Comet, +10 Coins, +5 Score, FEVER) | 5.20 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 gifts: … §5.20 reward colours and words… | done |
| R-5.20-2 | Ring 7 pt in the main colour, dark back half, 1.6 pt white inner line on the front | 5.20 | 3d | test/run/shots/hazard_rings_shots_test.dart (giftpair_approach) | done (visual) |
| R-5.20-3 | Gift box ≈ 44 pt (body, dark right half, lid, white ribbon + bow), bob ±3, tilt ±5° | 5.20 | 3d | test/run/shots/hazard_rings_shots_test.dart (giftpair_approach) | done (visual) |
| R-5.20-4 | Gift tag (luggage tag, 2 pt outline, icon + word Opificio 14) on a string ≈ 30 pt out from the top/bottom ring; never in the gap or opening | 5.20 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 geometry … (tags outside the pair); test/run/hoops/s3_21_pair_test.dart::§5.20 the gift tag…; test/run/shots/hazard_rings_shots_test.dart | done |
| R-5.20-5 | Pick feedback: lid flies, icon jumps out, ≈ 22 confetti, colour ring pulse, reward word pops; skipped ring/box/tag shrink to 60 % and fade 0.45 s with a grey puff | 5.20 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 flying through the … ring … the other ring shrinks and fades; test/run/shots/hazard_rings_shots_test.dart (giftpair_pick) | done |
| R-5.20-6 | Sounds: box opens, per reward (5), ring skipped | 5.20 | 3d / 3h | test/run/hoops/s3_21_pair_test.dart::§3.21 the <reward> gift does what it says (reward sounds); pair_kind.dart (box pop, skipped blip) | done |
| R-5.21-1 | Train look: pink rings turn gold when passed; dotted track fg 50 % 2.5 pt 6/6 moving toward the bird, 34 pt before → after; progress dots 6.5 pt 20 pt above; banner TRAIN ×3 | 5.21 | 3c | test/run/hoops/s3_22_train_test.dart + test/run/shots/special_hoops_shots_test.dart | done (WP-3c) |
| R-5.21-2 | Train sounds C5 / E5 / G5 per ring; finish high C + chord + rising whistle | 5.21 | 3c / 3h | test/run/hoops/s3_22_train_test.dart | done (WP-3c) |
| R-5.22-1 | Spring look: green `#2EBD6B` / `#1E8A4C`, coils above and below, three chevrons moving in the launch direction; wobble ±7 pt 0.5 s, green burst, "BOING ↑/↓" | 5.22 | 3c | test/run/hoops/s3_23_spring_test.dart + test/run/shots/special_hoops_shots_test.dart | done (WP-3c) |
| R-5.22-2 | Spring sound: sine sweep 160 → 720 Hz (up) / 480 → 140 (down) + triangle overtone | 5.22 | 3c / 3h | test/run/hoops/s3_23_spring_test.dart | done (WP-3c) |
| R-5.23-1 | Bullseye target (white / red rings at 15 / 11 / 7 / 3.5 pt, 62 % width), band lines from 46 pt before; hit: flash, burst, banner "BULLSEYE!" "+3 coins" | 5.23 | 3c | test/run/hoops/s3_24_bullseye_test.dart + test/run/shots/special_hoops_shots_test.dart | done (WP-3c) |
| R-5.23-2 | Bullseye sound: dart thunk + bright chord | 5.23 | 3c / 3h | test/run/hoops/s3_24_bullseye_test.dart | done (WP-3c) |
| R-5.24-1 | Lucky Spin: 3 pt post, wheel r 24 36 pt above, pointer, six coloured slices with labels, spins 7 rad/s with ticks, slows 8 rad/s² after the pass, banner in slice colour, burst | 5.24 | 3c | test/run/hoops/s3_25_lucky_spin_test.dart + test/run/shots/special_hoops_shots_test.dart | done (WP-3c) |
| R-5.24-2 | Lucky Spin sounds: ticks, whoosh on pass, 4-note win chord | 5.24 | 3c / 3h | test/run/hoops/s3_25_lucky_spin_test.dart | done (WP-3c) |
| R-5.25-1 | Star Trail look: 8 four-point stars gold with pale core, 8–10 pt, halo, dotted gold line 2/6; collect sparkle; banner PERFECT LINE "8 / 8 stars · +5 coins" or "n / 8" | 5.25 | 3e | test/run/items/s3_26_star_trail_test.dart::§5.25 look: 8 pt gold stars …; ::§3.26 all 8 stars: PERFECT LINE …; shot: build/shots/run/collect/collect_trail_711.png | done (WP-3e) |
| R-5.25-2 | Star Trail sounds: C major C5 → C6 per star, bright chord on all 8 | 5.25 | 3e / 3h | test/run/items/s3_26_star_trail_test.dart::§5.25 the collected star plays the next note of C major …; ::§3.26 all 8 stars: … the 8 notes and the chord … | done (WP-3e; sounds WP-3h) |
| R-5.26-1 | Egg look (cream oval 8 × 10, ×1.3 pickup, speckles, halo; on the back ≈ 22 pt above; cracks + wobble); hatch burst + banner | 5.26 | 3e | test/run/items/s3_27_egg_test.dart::§5.26 look: cream 8 × 10 oval at 1.3× …; ::§3.27 every ring cracks it …; shot: build/shots/run/collect/collect_egg_711.png | done (WP-3e) |
| R-5.26-2 | Chick = `golden` bird skin at 48 %, ≈ 36 pt behind, 10 pt below, soft lag, fast flaps, peeps; HUD gold pill 64 × 24 "×2"; lost: flies away "bye!", banner "×2 LOST" | 5.26 | 3e | test/run/items/s3_27_egg_test.dart::§5.26 look: … the chick …; ::§3.27 the pickup goes on the bird's back …; ::§3.27 a rim touch scares the chick away …; shot: build/shots/run/collect/collect_egg_711.png | done (WP-3e) |
| R-5.26-3 | Egg sounds: pickup chime, crack, hatch peeps + chord, peeps, rim tonk, 3-note goodbye | 5.26 | 3e / 3h | test/run/items/s3_27_egg_test.dart::§3.27 the pickup goes on the bird's back … (eggPickup); ::§3.27 every ring cracks it … (eggCrack/eggHatch); ::§3.27 a rim touch scares the chick away … (eggBye) | done (WP-3e; sounds WP-3h) |
| R-5.27-1 | Piggy look (pink body, snout, legs, slot, curly tail, ≈ 32 pt with halo, 1.4× in HUD); coins = our coin spinning; caught fly into the HUD piggy | 5.27 | 3e | test/run/items/s3_28_piggy_test.dart::§5.27 look: pig art, 1.25× pickup / 1.4× HUD …; shot: build/shots/run/collect/collect_piggy_711.png | done (WP-3e) |
| R-5.27-2 | Piggy HUD under the score: piggy, "n / 20" `#E05A99`, 90 pt bar, "n missed"; pay-out smash + banner "+N" | 5.27 | 3e | test/run/items/s3_28_piggy_test.dart::§5.27 look: … HUD …; ::§3.28 caught coins go into the bank …; shot: build/shots/run/collect/collect_piggy_711.png | done (WP-3e) |
| R-5.27-3 | Piggy sounds: oink, clinks, missed blip, smash + cascade + chord | 5.27 | 3e / 3h | test/run/items/s3_28_piggy_test.dart::§3.28 grabbing the piggy starts the bank … (piggyOink); ::§3.28 caught coins go into the bank … (piggyCoin/piggyMiss/piggySmash) | done (WP-3e; sounds WP-3h) |
| R-5.28-1 | Jar pickup animated (glass, lid, glowing liquid, bob ±5, sway ±7°, lime glow pulse, 10 rays, 4 fireflies inside, sparks) | 5.28 | 3e | test/run/items/s3_29_jar_test.dart::§5.28 look: the weaving swarm stays inside the ±45 pt band; jar …; shot: build/shots/run/collect/collect_jar_711.png | done (WP-3e) |
| R-5.28-2 | Fireflies 2.6 pt pale-yellow with lime halo, weaving; HUD jar filling, "n / 20" `#7CB518`, 3 ✕ turning red; JAR FULL! / JAR BROKE banners | 5.28 | 3e | test/run/items/s3_29_jar_test.dart::§5.28 look: … swarm …; ::§3.29 20 caught = JAR FULL …; ::§3.29 3 escapes = JAR BROKE … | done (WP-3e) |
| R-5.28-3 | Jar sounds: pickup chime, twinkle per firefly, blip per escape, crack, bright chord | 5.28 | 3e / 3h | test/run/items/s3_29_jar_test.dart::§3.29 grabbing the animated jar starts it … (jarPickup); ::§3.29 20 caught = JAR FULL … (jarTwinkle/jarFull); ::§3.29 3 escapes = JAR BROKE … (jarEscape/jarBreak) | done (WP-3e; sounds WP-3h) |
| R-5.29-1 | Capsule (all timed powerups): 34 pt rounded square (r 8) in the powerup colour, darker lower band, white icon, bob ±3 in a pulsing 25 pt ring, burst on pickup | 5.29 | 3f | shot: build/shots/run/capsules/capsule_capsule_711.png, capsule_mini_capsule_711.png; test/run/items/s3_30_s3_32_capsules_test.dart::§5.29 capsule 34 pt … | done |
| R-5.29-2 | Timer pill 120 × 22 at y ≈ 206 (icon disc 26 pt + draining bar); seconds left next to it | 5.29 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 the HUD stays real time; the timer pill …; shot: capsule_hourglass_568.png | done (call: y 156, ARCH §23) |
| R-5.29-3 | Hourglass `#2F80FF`, white hourglass icon; blue tint 10 % + dark-blue vignette, ghost birds, thin blue clock ring with hand | 5.29 | 3f | shot: build/shots/run/capsules/capsule_hourglass_711.png | done |
| R-5.29-4 | Hourglass sounds: slowdown sweep 700 → 110 Hz, tick-tock 0.6 s, speed-up sweep; music ≈ 72 % | 5.29 | 3f / 3h | test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 the world runs at 45 % … (hourglassStart / Tick / End, music 0.72) | done |
| R-5.30-1 | Mini Bird `#2EBD6B`, shrink-potion icon (flask, cork, purple liquid, bubbles, pink bird label); purple sparkles in, bubbles, green/purple/white burst at the end | 5.30 | 3f | shot: build/shots/run/capsules/capsule_mini_711.png | done |
| R-5.30-2 | Mini sounds: bubble blips + falling whistle 1400 → 300 Hz; rising whistle + pop at the end | 5.30 | 3f / 3h | test/run/items/s3_30_s3_32_capsules_test.dart::§3.31 … sounds and bubbles | done |
| R-5.31-1 | Coin Frenzy `#FFB529`, three-coins icon; rings not yet passed gold `#FFD54A`/`#D48A00` 8 pt with 10 orbiting coins; each pass "+5" + 5 coins up; pulsing 10 pt gold border; sparkles | 5.31 | 3f | shot: build/shots/run/capsules/capsule_frenzy_711.png; test/run/items/s3_30_s3_32_capsules_test.dart::§3.32 … | done |
| R-5.31-2 | Frenzy sounds: 5-note jackpot run + chord, coin cascade per ring, short falling tone at the end | 5.31 | 3f / 3h | test/run/items/s3_30_s3_32_capsules_test.dart::§3.32 every ring passed pays +5 … (frenzyStart / Ring / End) | done |

## 6. Analytics (Firebase)

| ID | Event (params) | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-6-1 | `coins_earned` (source: hoop / perfect / win_bonus / level / bonus / puzzle / switch / pair / train / bullseye / lucky_spin / star_trail / piggy / jar / frenzy; flag `egg_x2`) | 6 | 0b (router) + source WPs | test/run/flow/s3_0_run_core_flow_test.dart::§3.0.1 START builds a RunController…; test/run/s7_run_parts_test.dart::§6* | done |
| R-6-2 | `big_hoops_used` | 6 | existing / 2a verify | test/run/items/s3_3_s3_7_lives_test.dart::§3.7 the home-slot shield …; test/run/items/s3_6_big_hoops_test.dart::§3.6 the home-slot Big Hoops … (big_hoops_used) | done |
| R-6-3 | `heart_collected` | 6 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 three hearts give one extra life … | done |
| R-6-4 | `extra_life_used` (cause: missed_hoop / spikes) | 6 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.3 the extra life forgives one mistake … | done |
| R-6-5 | `comet_collected` | 6 | 3a | test/run/items/s3_8_comet_test.dart::§3.8 / §3.9 / §6 collecting the star … (comet_collected {source}) | done |
| R-6-6 | `shield_collected` | 6 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.7 the shield pickup arms the shield … | done |
| R-6-7 | `shield_used` | 6 | 2a | test/run/items/s3_3_s3_7_lives_test.dart::§3.7 / §3.3 save order … | done |
| R-6-8 | `portal_entered` (ride: cannon / space / volcano / sea / pinball / storm) | 6 | 3b | test/run/rides/s3_12_portal_ride_test.dart (portal_entered {ride}) | done |
| R-6-9 | `perfect_pass` (tier) | 6 | 2b | test/run/items/s3_4_streak_test.dart::§3.4 perfect passes build the streak | done |
| R-6-10 | `streak_broken` (length) | 6 | 2b | test/run/items/s3_4_streak_test.dart::§3.4 / §5.3 a graze resets the streak; test/run/items/s3_4_streak_test.dart::§3.4 a save or a death breaks the streak (+ cause param: graze / save / death) | done |
| R-6-11 | `revive_offered` | 6 | 2d | | todo |
| R-6-12 | `revive_ad_started` | 6 | 2d | | todo |
| R-6-13 | `revive_ad_completed` | 6 | 2d | | todo |
| R-6-14 | `revive_coins` (price, revive_index) | 6 | 2d | | todo |
| R-6-15 | `revive_locked_tap` | 6 | 2d | | todo |
| R-6-16 | `revive_get_coins` | 6 | 2d | | todo |
| R-6-17 | `revive_declined` | 6 | 2d | | todo |
| R-6-18 | `revive_timeout` | 6 | 2d | | todo |
| R-6-19 | `level_up` (from, to, reward, claim: tap / auto_next / app_start) | 6 | 2e | | todo |
| R-6-20 | `versus_matched` | 6 | 5b | test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent… | done |
| R-6-21 | `versus_skipped` (reason: no_opponent) | 6 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 solo start… | done |
| R-6-22 | `versus_result` (win/lose/draw, score, opp_score) | 6 | 5b | test/versus/s3_13_versus_run_test.dart::§3.13 / §5.10 WIN / LOSE / DRAW | done |
| R-6-23 | `feather_collected` (count 1–3) | 6 | 4a | test/run/items/s3_15_feathers_test.dart::§3.15 a touched feather is banked at once… | done (4a) |
| R-6-24 | `bonus_shown` | 6 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 opens after the run… | done (4a) |
| R-6-25 | `bonus_pop` (prize, pop 1–6) | 6 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 opens after the run… | done (4a) |
| R-6-26 | `bonus_ad_offered` | 6 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 out of feathers… | done (4a) |
| R-6-27 | `bonus_ad_completed` | 6 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 the ad gives 3 more feathers once… | done (4a) |
| R-6-28 | `bonus_declined` (pops used) | 6 | 4a | test/run/screens/s3_15_bonus_screen_test.dart::§3.15 out of feathers… | done (4a) |
| R-6-29 | `puzzle_piece_collected` (piece 1–4, count 1–4, round) | 6 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 only a missing piece spawns… | done (4a) |
| R-6-30 | `puzzle_completed` (round, coins) | 6 | 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 4/4… | done (4a) |
| R-6-31 | `squeeze_started` (index, open_pct, hold_s) | 6 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 a squeeze from start to open | done |
| R-6-32 | `squeeze_survived` (index) | 6 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 a squeeze from start to open | done |
| R-6-33 | `squeeze_death` (index, phase) | 6 | 3g | test/run/items/s3_17_squeeze_test.dart::§3.17 the moving walls are the spikes | done |
| R-6-34 | `sawring_spawned` (design) | 6 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 a clean pass … sawring_spawned / sawring_passed | done |
| R-6-35 | `sawring_passed` (design) | 6 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 a clean pass … sawring_passed | done |
| R-6-36 | `sawring_death` (design, used: none / extra_life / shield) | 6 | 3d | test/run/hoops/s3_18_saw_test.dart::§3.18 / §3.0.5 touching the <design> rim kills … (used: none); test/run/hoops/s3_18_saw_test.dart::§3.18 with an armed shield … (used: shield) | done |
| R-6-37 | `fever_ring_spawned` (hoop_index) | 6 | 3c | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-6-38 | `fever_ring_passed` (perfect, streak_before, streak_after) | 6 | 3c | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-6-39 | `fever_fire_out` (streak, hoops_burned, cause: graze / extra_life / shield / death) | 6 | 3c | test/run/items/s3_19_fever_test.dart | done (WP-3c) |
| R-6-40 | `pair_spawned` (reward_top, reward_bottom) | 6 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 geometry … (pair_spawned) | done |
| R-6-41 | `pair_picked` (reward, skipped_reward, top/bottom, perfect) | 6 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 flying through the … ring … pair_picked | done |
| R-6-42 | `pair_missed` | 6 | 3d | test/run/hoops/s3_21_pair_test.dart::§3.21 flying through neither ring … pair_missed | done |
| R-6-43 | `train_completed` | 6 | 3c | test/run/hoops/s3_22_train_test.dart | done (WP-3c) |
| R-6-44 | `spring_used` (up/down) | 6 | 3c | test/run/hoops/s3_23_spring_test.dart | done (WP-3c) |
| R-6-45 | `bullseye_hit` | 6 | 3c | test/run/hoops/s3_24_bullseye_test.dart | done (WP-3c) |
| R-6-46 | `lucky_spin` (prize) | 6 | 3c | test/run/hoops/s3_25_lucky_spin_test.dart | done (WP-3c) |
| R-6-47 | `star_trail` (stars) | 6 | 3e | | todo |
| R-6-48 | `egg_collected` | 6 | 3e | | todo |
| R-6-49 | `egg_hatched` | 6 | 3e | | todo |
| R-6-50 | `chick_lost` (cause: rim / crash, coins_doubled) | 6 | 3e | | todo |
| R-6-51 | `piggy_collected` | 6 | 3e | | todo |
| R-6-52 | `piggy_paid` (caught, payout) | 6 | 3e | | todo |
| R-6-53 | `jar_collected` | 6 | 3e | | todo |
| R-6-54 | `jar_result` (full / broken, caught) | 6 | 3e | | todo |
| R-6-55 | `powerup_started` (hourglass / mini / frenzy, duration) | 6 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 / §6 a capsule starts its powerup at once …; test/run/items/s3_30_s3_32_capsules_test.dart::§6 / WP-3a the comet … | done |
| R-6-56 | `powerup_ended` (type) | 6 | 3f | test/run/items/s3_30_s3_32_capsules_test.dart::§3.30 / §6 …; test/run/items/s3_30_s3_32_capsules_test.dart::§3.14 a death ends the timed powerup … | done |
| R-6-57 | `setting_changed` (setting: rumble, value) | 6 | 2c (existing `rumble_toggle` → rename or send both; call in 2c) | test/run/items/s3_33_rumble_test.dart::§3.33 the RUMBLE switch — call: both `rumble_toggle` and `setting_changed` are sent | done |
| R-6-58 | `notif_permission` (granted / denied) | 6 | 4b | test/services/s3_34_reminders_test.dart::§3.34 service permission is asked once and the result is logged; ::§3.34 service a decline is final and logged | done |
| R-6-59 | `notif_opened` (message 1–20, slot midday / evening) | 6 | 4b | test/services/s3_34_reminders_test.dart::§3.34 service tapping a reminder logs notif_opened | done |
| R-6-60 | `switchring_spawned` (design) | 6 | 3d | lib/run/hoops/kinds/switch/switch_kind.dart (onSpawn) | done |
| R-6-61 | `switchring_switch_taken` (design) | 6 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 <design>: … switchring_switch_taken | done |
| R-6-62 | `switchring_passed` (design) | 6 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 <design>: … switchring_passed | done |
| R-6-63 | `switchring_closed_hit` (design, used: none / extra_life / shield) | 6 | 3d | test/run/hoops/s3_20_switch_test.dart::§3.20 reaching the ring … (used: none); test/run/hoops/s3_20_switch_test.dart::§3.20 with a shield … (used: shield) | done |
| R-6-64 | `run_end` (cause: missed_hoop / spikes / saw / closed_switch / pair_missed, hoop_index, hoop_kind, run_s, hoops, coins, saves) | 6 | 0b | test/run/flow/s3_0_run_core_flow_test.dart::§3.0.1 START builds a RunController…; test/run/s7_run_parts_test.dart::§6* | done |
| R-6-65 | `run_director_hoops` (one int per hoop kind and modifier + rim_touches + perfect_pct; ≤ 25 params) with `run_end` | 6 | 0b | test/run/flow/s3_0_run_core_flow_test.dart::§3.0.1 START builds a RunController…; test/run/s7_run_parts_test.dart::§6* | done |
| R-6-66 | `run_director_items` (one int per gap item type; ≤ 25 params) with `run_end` | 6 | 0b | test/run/flow/s3_0_run_core_flow_test.dart::§3.0.1 START builds a RunController…; test/run/s7_run_parts_test.dart::§6* | done |
| R-6-67 | `ad_rewarded_shown` placements `revive` / `bonus_feathers` (2× coins placement removed) | 6 | 0b (enum) / 2d / 4a | test/run/flow/s3_0_run_core_flow_test.dart::§3.0.1 START builds a RunController…; test/run/s7_run_parts_test.dart::§6* | done |
| R-6-68 | Store data declarations updated for the new events / data | 6 | 4c | | todo |

## 7. Technical notes and test list

| ID | Requirement | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-7-1 | Run state (hearts, extra life, shield, streak, ride) lives in the game, not storage; coins via the wallet at the moment earned | 7 | 0b | test/run/flow/s3_0_run_core_flow_test.dart | done |
| R-7-2 | New components for pickups, pooled effects, moving paths + guides, portal + cannon, HUD row, pause, revive, results | 7 | per WP | | todo |
| R-7-3 | `RunDirector` owned by the game; tables as `Config` data mirroring `spawn_tables.json` / prototype `BANDS` / `BUDGET` / `SPECIAL` / `GAPITEM` | 7 | 0b | test/run/config/tables_mirror_test.dart; test/run/director/s3_0_3_director_test.dart | done |
| R-7-4 | One `Hoop` component with a `kind` (normal, saw, switch, pair, fever, train, spring, bullseye, spin, portal) and ring offsets; strategy objects; tilt/move modifiers | 7 | 0b / 1a | test/run/flow/s3_0_run_core_flow_test.dart; test/run/flow/s3_1_hoop_flow_test.dart | done (kinds per WP) |
| R-7-5 | Bird at fixed screen x; world moves at the bird's forward speed; rim ends checked in plain math; `maxTranslation = 10000` kept | 7 | 1a | test/run/flow/s3_1_hoop_flow_test.dart; test/run/physics/s3_0_4_rim_test.dart; lib/game/flappy_game.dart maxTranslation = 10000 kept | done |
| R-7-6 | Death: free ballistic body, world eases to 0 over 0.4 s | 7 | 1a | test/run/physics/s3_0_5_tumble_test.dart; test/run/flow/s3_1_hoop_flow_test.dart::§3.0.5 the world eases to a stop over 0.4 s | done |
| R-7-7 | Results reads the level from `bestScore` before/after; `unclaimedLevelReward` until CLAIM/NEXT; emblem painter shared with home | 7 | 2e | test/run/screens/s3_14_s5_10_results_test.dart::§3.14 level up…; §7 an unclaimed level reward… | done |
| R-7-8 | `PortalRide` engine + `RideTheme` per ride; `rides84.js` timings | 7 | 3b | | todo |
| R-7-9 | Sounds through `AudioPool` only; comet loop via the BGM-style player | 7 | 0b / all | test/run/s7_run_parts_test.dart::§3.9 loops… | done (0b part); all pending |
| R-7-10 | Versus backend in repo: `functions/` (TS, 2nd gen), `firestore.rules`, `firestore.indexes.json`, TTL policy; Emulator Suite tests; `VersusService` no-op by default | 7 | 5a / 5b | functions/, firestore.rules, firestore.indexes.json, functions/scripts/set_ttl.sh; `npm --prefix functions test`; test/versus/s3_13_service_test.dart; test/versus/s3_13_emulator_test.dart (opt-in, tool/versus_emulator_test.sh) | done |
| R-7-11 | Feathers: persistent count, at most one pickup, bonus screen between revive and results, wallet per pop, ad placement `bonus_feathers`; timings from `bonus.js` / `collect.js` | 7 | 4a | test/run/items/s3_15_feathers_test.dart; test/run/screens/s3_15_bonus_screen_test.dart | done (4a) |
| R-7-12 | Puzzle: mask + round, one missing piece per run, 4/4 credit + reset + round + 1 atomically, colour themes as data (`PZT`) | 7 | 4a | test/run/items/s3_16_puzzle_test.dart | done (4a) |
| R-7-13 | Switch ring: one kind, pluggable design, shared rules; spawner places ring + switch; seeded design pick | 7 | 3d | test/run/hoops/s3_20_switch_test.dart; lib/run/hoops/kinds/switch/switch_kind.dart | done |
| R-7-T1 | Plane-crossing tests: inside scores; outside ends; rim bounces + scores +1 without perfect; pressed against the inside passes (upright and every tilt step); tilted ring never missed early; saw rim kills; exactly-once game over | 3.1, 7 | 1a (saw: 3d) | test/run/physics/s3_0_4_pass_test.dart; test/run/physics/s3_0_4_rim_test.dart; test/collision_test.dart; test/run/flow/s3_1_hoop_flow_test.dart; test/run/hoops/s3_18_saw_test.dart::§3.18 / §3.0.5 touching the <design> rim kills (saw rim) | done |
| R-7-T2 | Run-director tests (3.0.3), incl. same seed → same sequence | 3.1, 7 | 0b | test/run/director/s3_0_3_director_test.dart | done |
| R-7-T3 | Death-physics tests (3.0.5) | 3.1, 7 | 1a | test/run/physics/s3_0_5_tumble_test.dart; test/run/flow/s3_1_hoop_flow_test.dart | done |
| R-7-T4 | `flutter test` green incl. autopilot at 568 and 711, with and without Big Hoops, director on (all elements), each special forced on every allowed slot | 7 | 1a / 1b / 2a / P3 | test/autopilot_test.dart::AUTOPILOT (568 / 711) seed 7, 21, 1234: §7 the hoop-aware bot passes >= 12 hoops | part (plain gate 1a; Big Hoops 2a: test/autopilot_test.dart::AUTOPILOT (568 / 711) seed 7, 21, 1234 Big Hoops; elements: P3) |
| R-7-T5 | `startHoopIndex` override; gate ≥ 12 hoops after each type unlocks at both heights; plain run ≥ 12 | 7 | 0b / P3 | test/run/director/s3_0_3_director_test.dart | done (0b part); P3 pending |
| R-7-T6 | Autopilot targets the switch before a closed switch ring and the nearer ring of a pair | 7 | 0b / 3d | lib/run/debug/autopilot.dart (nearest ring); switch pre-target via HoopKind.autopilotTarget (3d); test/run/hoops/s3_20_switch_test.dart::§3.20 <design>: … the autopilot takes the switch first; test/run/flow/s3_18_s3_20_s3_21_autopilot_test.dart | done |
| R-7-T7 | Revive tests: ladder (ad → 250 → 500 → 1 000 → doubling, reset per game, no-ad start 250); phoenix (safe line, drift to 70, scroll at 1.65 s, 2 s invuln, Black Hole re-form); ≥ 6 rule (≤ 5 → no offer, no ladder step); collectables lost and timed powerups ended at death; squeeze reset | 7 | 2d (+ 3d / 3e / 3f / 3g cases) | | todo |
| R-7-T8 | Results tests: level-up one / several, CLAIM, auto-claim on NEXT, `unclaimedLevelReward` at next start; YOUR REWARD incl. puzzle + win/draw, excl. balloon | 7 | 2e (+ 4a / 5b cases) | test/run/screens/s3_14_s5_10_results_test.dart (4a / 5b cases: their WPs) | done |
| R-7-T9 | Versus tests: timeline replay on runClock (pause, revive offer, phoenix, Hourglass); opponent out at timeline end; WIN / LOSE / DRAW + bonus; solo start without prefetch | 7 | 5b (+ 3f case) | test/versus/s3_13_versus_run_test.dart (Hourglass via RunState.timeScale; 3f adds the capsule case) | done |
| R-7-T10 | Rumble tests: recorder per event; 90 ms throttle; shake never skipped | 7 | 2c | | todo |
| R-7-T11 | Notification tests with a fake clock: windows, quiet hours incl. TZ / DST, skip-after-play, 7 d / 14 slots, rotation no repeat in 10 d, fill-in + fallback | 7 | 4b | | todo |
| R-7-T12 | Persistence: every key round-trips with its default | 7 | 0b / 4c | test/run/persistence_test.dart | done (0b part); 4c pending |
| R-7-T13 | Emulator tests: rules, function, matching | 7 | 5a | functions/test/*.test.ts (77 tests: rules, trigger, callable, matching fixture test/fixtures/versus_matching.json, level parity) | done |
| R-7-T14 | Pixel 8 `integration_test` with `FS_E2E` (fixed seed, fake ads, debug App Check, force hooks) per phase; final release e2e | ARCH | 0b / 6 | integration_test/run_core_e2e_test.dart; integration_test/release_e2e_test.dart::P6 §7 journey …, ::P6 §3.0.8 element sweep …, ::P6 §3.12 rides …, ::P6 §3.34 reminders …, ::P6 §3.13 versus live round trip … | done on Linux (WP-6a; reminders / versus live skip there); Pixel 8 run by the orchestrator |
| R-7-T15 | Screenshot checks vs the approved PNG for every drawn element (`captureShot` pattern) | common | all visual WPs | | todo |

## 7. Persistence keys

| ID | Key (type, default) | PRD § | WP | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-7-P1 | `bestScore` (int, 0) — existing | 7 | 0b (test) | test/run/persistence_test.dart | done |
| R-7-P2 | `gamesPlayed` (int, 0) — existing | 7 | 0b (test) | test/run/persistence_test.dart | done |
| R-7-P3 | `muteSound` (bool, false) — existing | 7 | 0b (test) | test/run/persistence_test.dart | done |
| R-7-P4 | `musicVolume` (double 0–1, 0.6) — existing | 7 | 0b (test) | test/run/persistence_test.dart | done |
| R-7-P5 | `rumble` (bool, true) | 3.33 | existing / 0b (test) | test/run/persistence_test.dart | done |
| R-7-P6 | `feathers` (int 0–3, 0) | 3.15 | 0b | test/run/persistence_test.dart | done |
| R-7-P7 | `puzzlePieces` (int 4-bit mask, 0) | 3.16 | 0b | test/run/persistence_test.dart | done |
| R-7-P8 | `puzzleRound` (int, 0) | 3.16 | 0b | test/run/persistence_test.dart | done |
| R-7-P9 | `lastPortalRide` (string ride id or null) | 3.12 | 0b | test/run/persistence_test.dart | done |
| R-7-P10 | `unclaimedLevelReward` (int coins, 0) | 3.14, 5.10 | 0b | test/run/persistence_test.dart | done |
| R-7-P11 | `metElements` (set of element ids, empty) | 3.0.8 | 0b | test/run/persistence_test.dart | done |
| R-7-P12 | `levelRewardsClaimed` (highest level claimed) — mapped onto the existing `claimedLevels` set (ARCH §5 call) | 3.14 | 0b | test/run/persistence_test.dart | done |
| R-7-P13 | `versusNickname` (string, generated once at first start) | 3.13 | 0b (key) / 5b (generation) | test/run/persistence_test.dart; test/versus/s3_13_service_test.dart::§3.13 initialize: a nickname once per install… | done |
| R-7-P14 | `uploadQueue` (list of run entries JSON, empty) | 3.13 | 0b | test/run/persistence_test.dart | done |
| R-7-P15 | `uploadsToday` + `uploadsDay` (int + date string, 0 + '') | 3.13 | 0b | test/run/persistence_test.dart | done |
| R-7-P16 | `notifOrder` (list of int, shuffled at first schedule) | 3.34 | 0b | test/run/persistence_test.dart | done |
| R-7-P17 | `notifPosition` (int, 0) | 3.34 | 0b | test/run/persistence_test.dart | done |
| R-7-P18 | `notifLastSent` (map message → date, empty) | 3.34 | 0b | test/run/persistence_test.dart | done |
| R-7-P19 | `notifPermissionAsked` (bool, false) | 3.34 | 0b | test/run/persistence_test.dart | done |
| R-7-P20 | Menu keys of PRD-1 unchanged; Firebase uid not in storage; saw / switch design history not stored | 7 | 0b | test/run/persistence_test.dart | done |

## 8. Sounds (approved files to ship + deliverables still to make)

Approved files exist in `design/menu_v2/sfx/` and are copied to `assets/audio/` by WP-0b; deliverables are generated by
WP-3h with the `gen_sfx*` scripts (same family, mp3 + wav, peak ≈ −1.4 dBFS). All play through `AudioPool` (loops via
the looping player).

| ID | Sound | PRD § | WP (ship / make) | Test ID(s) | Status |
|---|---|---|---|---|---|
| R-S-1 | `perfect_1`, `perfect_2`, `perfect_3` | 3.4 | 0b ship / 2b use | test/run/s7_run_parts_test.dart::§3.9 every approved PRD-2 run sound is bundled | shipped (0b); use pending |
| R-S-2 | `pu_heart_1`, `pu_heart_2`, `pu_heart_use` | 3.9 | 0b / 2a | test/run/s7_run_parts_test.dart::§3.9 every approved PRD-2 run sound is bundled | done |
| R-S-3 | `pu_shield_get`, `pu_shield_hit` | 3.9 | 0b / 2a | test/run/s7_run_parts_test.dart::§3.9 every approved PRD-2 run sound is bundled | done |
| R-S-4 | `pu_comet_get`, `pu_comet_loop` (loop), `pu_comet_end` | 3.9 | 0b / 3a | test/run/s7_run_parts_test.dart::§3.9 every approved PRD-2 run sound is bundled; test/run/items/s3_8_comet_test.dart::§3.8 / §3.9 the end … | done |
| R-S-5 | `pu_portal`, `pu_cannon_aim`, `pu_cannon_shot`, `pu_land` | 3.9 | 0b / 3b | test/run/s7_run_parts_test.dart::§3.9 every approved PRD-2 run sound is bundled | done (0b part); 3b pending |
| R-S-6 | `miss_shock` | 5.13 | 0b / 1a | test/run/s7_run_parts_test.dart::§3.9 every approved PRD-2 run sound is bundled | done (0b part); 1a pending |
| R-S-7 | `rv_pay`, `rv_ignite`, `rv_burst`, `rv_locked` | 5.9 | 0b / 2d | test/run/s7_run_parts_test.dart::§3.9 every approved PRD-2 run sound is bundled | done (0b part); 2d pending |
| R-S-8 | `lv_bar`, `lv_up`, `lv_up_big`, `lv_claim` | 5.10 | 0b / 2e | test/run/s7_run_parts_test.dart::§3.9 every approved PRD-2 run sound is bundled | done (0b part); 2e pending |
| R-S-9 | `col_feather_get`, `col_feather_slot1/2/3` | 3.15 | 0b / 4a | test/run/items/s3_15_feathers_test.dart::§3.15 a touched feather is banked at once…; test/run/items/s3_15_feathers_test.dart::§3.15 the 3rd feather… | done (4a) |
| R-S-10 | `bn_balloon_open`, `bn_prize_s/m/big`, `bn_coin` (exists), `bn_adbtn` (exists) | 3.15 | 0b / 4a | test/run/screens/s3_15_bonus_screen_test.dart (sounds through SoundService.play) | done (4a) |
| R-S-11 | `col4_puzzle_get`, `col4_puzzle_slot1..4`, `col4_coins` | 3.16 | 0b / 4a | test/run/items/s3_16_puzzle_test.dart::§3.16 only a missing piece spawns…; test/run/items/s3_16_puzzle_test.dart::§3.16 4/4… | done (4a) |
| R-S-12 | `sq_warn`, `sq_close`, `sq_lock`, `sq_hold` (seamless loop: ship `.ogg`/`.wav`, not mp3), `sq_tick`, `sq_open` | 5.16 | 0b / 3g | test/run/s7_run_parts_test.dart; test/run/items/s3_17_squeeze_test.dart::§3.17 a squeeze from start to open | done |
| R-S-13 | Ride sounds `rd_space_*`, `rd_volc_*`, `rd_sea_*`, `rd_pin_*`, `rd_storm_*` (16 files) | 5.12b | 0b / 3b |test/run/s7_run_parts_test.dart::§3.9 every approved PRD-2 run sound is bundled; test/run/rides/s3_12_portal_ride_test.dart (ride cues per theme) | done |
| R-S-14 | `notif_b.ogg` → `android/app/src/main/res/raw/notif_chime.ogg` | 3.34 | 4b | integration_test/reminders_e2e_test.dart::WP-4b reminders: permission + the pending 7-day window; `flutter build apk --debug` -> res/raw/notif_chime.ogg | done (19246 B, byte-identical to design/menu_v2/sfx/notif_b.ogg) |
| R-S-15 | Deliverable: versus intro set (whoosh, ticks, chime, rocket, pop / crackle, thud, boing) | 5.8, 7 | 3h make / 5b use | test/run/sound_pack_test.dart::§7 every cue maps to one existing, non-empty mp3; test/versus/s3_13_versus_run_test.dart::§5.8 / §3.13 a prefetched opponent… (vs_* sounds) | done |
| R-S-16 | Deliverable: saw-ring hums (3 loops) and deaths (Live Wire zap + thunder + crackles; Frost crunch + hiss, crack, shatter; Black Hole roar + sub drop, boom, inhale) | 5.17, 7 | 3h / 3d | test/run/sound_pack_test.dart::§7 the 4 new loops are SfxLoop entries with a .wav file | done (3h: 3 `SfxLoop` hums + 12 one-shots); 3d use pending |
| R-S-17 | Deliverable: FEVER pass, burning crackle loop, fire out sizzle | 5.18, 7 | 3h / 3c | test/run/sound_pack_test.dart::§7 the 4 new loops start, keep volume and stop | done (3h: `fever_*`); 3c uses them (WP-3c) |
| R-S-18 | Deliverable: switch rings × 5 designs (touched, opening, crash) + shared "clear" chord | 5.19, 7 | 3h / 3d | test/run/sound_pack_test.dart::§7 every PRD-2 §7 deliverable is a registered Sfx | done (3h: `sw_*`, 16 files); 3d use pending |
| R-S-19 | Deliverable: pair gifts (box opens, shield, comet, coins, score, FEVER, ring skipped) | 5.20, 7 | 3h / 3d | test/run/sound_pack_test.dart::§7 every PRD-2 §7 deliverable is a registered Sfx | done (3h: `pair_*`, 7 files); 3d use pending |
| R-S-20 | Deliverable: Ring Train notes + finish; Spring boing up/down; Bullseye thunk + chord; Lucky Spin ticks / whoosh / win chord; Star Trail scale notes + chord | 5.21–5.25, 7 | 3h / 3c / 3e | test/run/sound_pack_test.dart::§7 every PRD-2 §7 deliverable is a registered Sfx; test/run/items/s3_26_star_trail_test.dart::§5.25 the collected star plays the next note of C major … | done (3h: `train_*`, `spring_*`, `bull_*`, `lucky_*`, `trail_*`, 21 files); 3c uses its (WP-3c), 3e its (WP-3e) |
| R-S-21 | Deliverable: Egg (chime, crack, hatch, peeps, goodbye), Piggy (oink, clink, blip, smash cascade), Jar (chime, twinkle, blip, crack, chord) | 5.26–5.28, 7 | 3h / 3e | test/run/sound_pack_test.dart::§7 every PRD-2 §7 deliverable is a registered Sfx; test/run/items/s3_27_egg_test.dart; test/run/items/s3_28_piggy_test.dart; test/run/items/s3_29_jar_test.dart (pickup / crack / escape / reward sounds asserted) | done (3h: `egg_*`, `piggy_*`, `jar_*`, 14 files); 3e uses its (WP-3e) |
| R-S-22 | Deliverable: Hourglass (slowdown, tick-tock, speed-up), Mini Bird (start, end), Coin Frenzy (start run, cascade, end tone) | 5.29–5.31, 7 | 3h / 3f | test/run/sound_pack_test.dart::§7 every PRD-2 §7 deliverable is a registered Sfx | done (3h: `hourglass_*`, `mini_*`, `frenzy_*`, 8 files); 3f use pending |
| R-S-23 | Deliverable: rim "tonk" | 3.0.4, 7 | 3h / 1a (placeholder: `sk_tap` until 3h lands) | test/run/sound_pack_test.dart::§7 every PRD-2 §7 deliverable is a registered Sfx | done (3h: `rim_tonk`); 1a wiring pending |
| R-S-24 | Deliverable: squeeze tick-last-3-s tremble uses `sq_tick`; graze sound = `point.mp3` (no new file) | 3.17, 3.4 | 3g / 2b | test/run/items/s3_17_squeeze_test.dart::§3.17 a squeeze from start to open (3 × sq_tick + tremble) | done (3g part) |
