import 'tuning_values.dart';

/// PRD-2 core tuning (§3.0.1) and the director's placement constants
/// (§3.0.2 / §3.0.3 / §3.0.8). Every member's doc starts with its PRD
/// section (ARCH §4). Pure Dart.
abstract final class RunConfig {
  // --- §3.0.1 core tuning --------------------------------------------------

  /// §3.0.1 Playfield width (pt); unchanged from 1.0.
  static const double worldWidth = 320;

  /// §3.0.1 Screen height the PRD specifies layouts at (pt).
  static const double designHeight = 711;

  /// §3.0.1 Cruise (scroll) speed at hoop 0 (pt/s). PRD-2.3 §14.4: the
  /// run's speed is the `curve_speed` keyframe table by hoop index ([cruise];
  /// 150 → 172.5 at hoop 50 → 187.5 from hoop 150), replacing the 2.2
  /// +3.5 %-per-minute ramp. This is the design reference value only.
  static const double cruiseSpeed = 150;

  /// §3.0.1 Hoop spacing, plane to plane (pt). Constant.
  static const double spacing = 310;

  /// §3.0.1 The first hoop spawns this far past the right edge (pt) at the
  /// first tap and scrolls in (json "1.3 s" is overridden by the PRD).
  static const double firstHoopOffscreen = 60;

  /// PRD-2.3 §10.2 Hoop 0's plane x (pt, of the 320 pt playfield): it
  /// stands on screen while the bird waits for the first tap (replaces
  /// [firstHoopOffscreen] for hoop 0 only). Hoop 1 follows at [spacing]
  /// (x 600). Not tunable.
  static const double hoop0X = 290;

  /// PRD-2.3 §10.2 Hoop 0's centre is this far below the playfield's middle
  /// (pt): `viewHeight / 2 + 16`. Not tunable.
  static const double hoop0DropY = 16;

  /// §3.0.1 Gravity (pt/s²).
  static const double gravity = 1250;

  /// §3.0.1 A flap SETS vy to this (pt/s).
  static const double flapVelocity = -370;

  /// §3.0.1 Max fall speed (pt/s).
  static const double maxFallSpeed = 650;

  /// §3.0.1 Bird screen x in flight (pt).
  static const double birdX = 70;

  /// §3.0.1 Bird collider radius (pt).
  static const double birdRadius = 14.75;

  /// §3.0.1 / §3.31 Mini Bird scale.
  static const double miniBirdScale = 0.52;

  /// §3.0.1 Opening at hoop 0 (pt). PRD-2.3 §14.4 / §0 item 3 / §10.2:
  /// hoop 0 always stays 118 (also with Big Hoops' cap). PRD-2.4 §2: ride
  /// hoops are no longer 118; they take the curve size of their index
  /// ([openingFor]). Not tunable.
  static const double opening0 = 118;

  /// §3.0.1 / §3.0.4 Rim-end circle radius (pt).
  static const double rimRadius = 7;

  /// §3.0.1 / §3.0.4 Rim restitution.
  static const double rimRestitution = 0.85;

  /// Owner 2026-10-13 soft rim bump: a rim hit from inside the gap (top
  /// rim while rising, bottom rim while falling) ends with this speed away
  /// from the rim along the ring (pt/s; top: down, bottom: up) instead of
  /// the [rimRestitution] reflection. Forward speed is kept. Remote
  /// (`curve_rim_soft_bump`, default 20; was 60 in 2.3.0 (13)).
  static double get rimSoftBump =>
      TuningValues.current.d('curve_rim_soft_bump');

  /// Owner 2026-10-13 (2.3.0 (15)): after a soft rim bump the bird hangs
  /// for this long (s) with gravity scaled by [rimHangGravity], then
  /// gravity eases back to full over [rimHangEase]; a flap ends it.
  /// Remote (`curve_rim_hang_s`, default 0.25).
  static double get rimHangSeconds =>
      TuningValues.current.d('curve_rim_hang_s');

  /// Owner 2026-10-13: the gravity scale of the rim hang (0 = none, 1 =
  /// full). Remote (`curve_rim_hang_gravity`, default 0.25).
  static double get rimHangGravity =>
      TuningValues.current.d('curve_rim_hang_gravity');

  /// Owner 2026-10-13: gravity eases from [rimHangGravity] back to full
  /// over this time (s) after the hang.
  static const double rimHangEase = 0.1;

  /// Owner 2026-10-14 (2.3.0 (19)): hoop spacing during a comet ride (pt,
  /// plane to plane; at least [spacing]). Remote (`ride_comet_hoop_gap`,
  /// default 560: about 5–6 hoops per 10 s comet instead of 8–10).
  ///
  /// PRD-2.3.1 §16 (2.3.1): the **target** spacing. At comet start the
  /// director spreads the comet hoops evenly from the last hoop that stays
  /// to the predicted end − [cometTail], in `max(1, round(stretch / gap))`
  /// equal steps (`RunDirector.onCometStart`).
  static double get cometHoopGap =>
      TuningValues.current.d('ride_comet_hoop_gap');

  /// PRD-2.3.1 §16.2 the last comet hoop sits this far before the comet's
  /// predicted end (pt). Remote (`ride_comet_tail`, default 100).
  static double get cometTail => TuningValues.current.d('ride_comet_tail');

  /// PRD-2.3.1 §16.2 the first normal hoop after a comet is at least this
  /// far after its predicted end (pt). Remote (`ride_comet_after_gap`,
  /// default 310).
  static double get cometAfterGap =>
      TuningValues.current.d('ride_comet_after_gap');

  /// §3.0.1 Forward recovery toward cruise after a knock-back (pt/s²).
  static const double forwardRecovery = 2000;

  /// §3.0.1 Colour stage changes every this many hoops passed.
  static const int stageEveryHoops = 10;

  /// §3.0.1 Number of colour stages (existing palettes).
  static const int stageCount = 11;

  /// §3.0.9 #1 Spike strip height: band 26 + teeth 18 (pt).
  static const double stripHeight = 44;

  /// §3.0.2 Band rule extra margin beyond opening/2 + rim radius (pt).
  static const double bandMargin = 18;

  /// §3.0.2 Tilt steps are capped at this many degrees.
  static const double maxTiltDeg = 45;

  // --- §3.0.3 placements ---------------------------------------------------

  /// §3.18 Saw rings: extra opening (pt). PRD-2.2 §25: 0 (was 28) — saw
  /// rings have exactly the normal opening at that point in the run.
  static const double sawExtraOpening = 0;

  /// §3.21 Pair ring offset at a 711 pt screen (pt between ring centres;
  /// scales with viewHeight / 711).
  static const double pairOffsetAt711 = 230;

  /// §3.21 HUD bottom: a pair's upper ring and tag stay below this (pt).
  static const double hudBottom = 114;

  /// §3.23 Spring: the next ring is this far above / below (pt).
  static const double springJump = 240;

  /// §3.22 Ring Train: ring spacing along x (pt).
  static const double trainDx = 56;

  /// §3.22 Ring Train: vertical step per ring (pt).
  static const double trainDy = 16;

  /// §3.20 Switch lead before its ring (s × current scroll speed).
  static const double switchLeadSeconds = 1.0;

  /// §3.20 Switch lead minimum (pt).
  static const double switchLeadMin = 150;

  /// §3.20 Switch vertical offset from the ring centre (pt).
  static const double switchOffsetMin = 70;

  /// §3.20 Switch vertical offset from the ring centre (pt).
  static const double switchOffsetMax = 100;

  /// §3.20 Switch at most this far (vertically) from the previous hoop
  /// centre (pt).
  static const double switchMaxFromPrev = 110;

  /// §3.0.3 Items stay this far inside the tooth lines (pt).
  static const double itemEdgeMargin = 40;

  /// §3.0.3 Feather / piece: fraction of the spacing after the hoop.
  static const double detourAfter = 0.65;

  /// §3.0.3 Feather / piece: height above the hoop centre (pt).
  static const double detourAboveMin = 64;

  /// §3.0.3 Feather / piece: height above the hoop centre (pt).
  static const double detourAboveMax = 200;

  /// §3.0.3 Heart / shield off the line by this fraction of the band.
  static const double offLineMin = 0.1;

  /// §3.0.3 Heart / shield off the line by this fraction of the band.
  static const double offLineMax = 0.4;

  /// §3.0.3 Heart: later hearts sit on the line with this chance.
  static const double heartOnLineChance = 0.5;

  /// PRD-2.2 §25.1 The portal ring is a fixed 118 pt at every hoop (it does
  /// not shrink). PRD-2.4 §2.3 keeps it unchanged: Big Hoops multiplies it,
  /// as in 2.3.1.
  static const double portalOpening = 118;

  /// PRD-2.2 §19.4 Single pickups (heart, shield, capsule, egg, jar,
  /// piggy, feather, puzzle piece) sit at a random point this far along the
  /// gap (fraction of the spacing; supersedes mid-gap / the detour).
  static const double singleAlongMin = 0.3;

  /// PRD-2.2 §19.4 See [singleAlongMin].
  static const double singleAlongMax = 0.7;

  /// PRD-2.2 §19.4 Single pickups sit up to this far off the straight line
  /// between the hoops (pt; supersedes [offLineMin] / [offLineMax] and the
  /// detour heights). The spawner keeps them [itemEdgeMargin] inside.
  static const double singleOffLine = 50;

  /// §3.28 / PRD-2.2 §26 Piggy coins sit this far apart (pt) in a field.
  static const double piggyCoinSpacing = 45;

  /// §3.29 A firefly swarm spans ± this much around its centre (pt).
  static const double fireflyHalfSpan = 110;

  /// PRD-2.2 §19.4 Patterns (piggy coins, firefly swarms) keep their shape;
  /// their start moves randomly inside the gap, keeping this far from the
  /// rings (pt).
  static const double patternInset = 40;

  /// PRD-2.2 §27.2 Cool-down after an activity ends: hoops before the next
  /// reward item may appear.
  static const int activityCooldownHoops = 2;

  /// PRD-2.2 §27.3 Reward items ahead fade out over this long (s) when an
  /// activity starts.
  static const double rewardClearFade = 0.2;

  /// PRD-2.3 §17.3 one big bonus on screen: while a big bonus is open the
  /// planner plans no other; a blocked one waits (rule 4). Tests turn it
  /// off (`RunSetup.oneBigBonus`) only for the §17.6 count baseline.
  static const bool oneBigBonus = true;

  /// PRD-2.3 §17.4 a big bonus (its hoop included) is created when its left
  /// visual edge is at least this far beyond the right screen edge (pt).
  static const double bigBonusEdgeMargin = 8;

  /// PRD-2.2 §15.1 Pop-in of a feature follow-up created inside the
  /// screen: scale 0 → [popInOvershoot] → 1 over this long (s).
  static const double popInTime = 0.25;

  /// PRD-2.2 §15.1 See [popInTime].
  static const double popInOvershoot = 1.15;

  /// PRD-2.2 §15.1 The pop-in's small sparkle (pieces of the pickup
  /// sparkle master, `CollectBursts`).
  static const int popInSparkle = 6;

  /// §3.26 Star Trail: stars per trail.
  static const int starTrailStars = 8;

  /// §3.26 Star Trail: the trail starts / ends this far from the hoops (pt).
  static const double starTrailInset = 40;

  /// §3.26 Star Trail: arc bulge upward (pt).
  static const double starTrailBulge = 40;

  /// §3.28 Piggy Bank: coins placed per gap.
  static const int piggyCoinsPerGap = 4;

  /// §3.28 Piggy Bank: follow-up gaps after the piggy's own gap.
  static const int piggyFollowGaps = 4;

  /// §3.29 Firefly Jar: fireflies per swarm.
  static const int fireflySwarm = 7;

  /// §3.8 The comet star hangs this far past its hoop's plane (pt).
  static const double cometHang = 20;

  /// §3.0.3 Portal / comet keep this many hoops apart (both directions).
  static const int cometPortalDistance = 10;

  /// §3.0.3 Saw / FEVER / switch not within this many hoops of the portal.
  static const int nearPortal = 3;

  /// §3.0.3 Cooldown after a portal (normal slots).
  static const int portalCooldown = 3;

  /// §3.0.8 First-meet: force within this many slots / gaps.
  static const int firstMeetWithin = 5;

  /// §3.25 Lucky Spin slices (coins), equal chance. PRD-2.3 §14.2:
  /// [1, 2, 3, 5, 1, 2] (`coin_spin_slices`; was [2, 5, 10, 3, 20, 5]).
  static List<int> get luckySpinSlices =>
      TuningValues.current.ints('coin_spin_slices');

  // --- §3.11 motion parameters the director rolls ----------------------------

  /// §3.11 Horizontal slide axis (deg from vertical).
  static const double horizontalAxisDeg = 90;

  /// §3.11 Diagonal slide: ±38° from horizontal = ±52° from vertical.
  static const double diagonalAxisDeg = 52;

  /// §3.11 Rail amplitude never below this (pt).
  static const double railMinHalfTravel = 10;

  /// §3.11 Swing rope at least this long (pt), else top tooth − y + 40.
  static const double swingMinRope = 120;

  /// §3.11 Swing pivot sits this far above the top tooth line (pt).
  static const double swingPivotAbove = 40;

  /// §3.11 Orbit ellipse ≈ 50 × 62 pt: x radius (pt).
  static const double orbitRx = 25;

  /// §3.11 Orbit ellipse ≈ 50 × 62 pt: max y radius (pt).
  static const double orbitRy = 31;

  /// §3.11 Orbit angular speed (rad/s): path speed ≤ 39 pt/s on the
  /// 31 pt radius (WP-1b call; the prototype's 1.4 reached 43 pt/s).
  static const double orbitOmega = 1.25;

  /// §3.11 Rock amplitude (deg).
  static const double rockAmplitudeDeg = 15;

  /// §3.11 Rock period (s).
  static const double rockPeriod = 3;

  // --- §3.17 / §3.6 / §3.16 timing-stream rolls ----------------------------

  // PRD-2.3 §14.4 the squeeze schedule is counted in hoops now
  // (`squeeze_first` 25–40, `squeeze_hold` 5–10, `squeeze_gap` 25–45 hoops;
  // `RunDirector.rollSqueezeAt` / `rollSqueezeHold`), replacing the 2.2
  // runClock knobs (60–120 s, hold 10–20 s).

  /// §3.17 Squeeze window starts this long before the warning (s).
  static const double squeezeWindowLead = 3;

  /// §3.6 Big Hoops duration D range (s of runClock).
  static const double bigHoopsMin = 30;

  /// §3.6 Big Hoops duration D range (s of runClock).
  static const double bigHoopsMax = 40;

  /// §3.6 Big Hoops eases back over the last this many seconds.
  static const double bigHoopsEase = 8;

  /// §3.6 Big Hoops opening multiplier.
  static const double bigHoopsMult = 1.5;

  /// §3.16 Puzzle completion bonus range (coins) and step. PRD-2.3 §14.2:
  /// 50–150 in steps of 5 (`puzzle_reward` = [min, max, step]; was 50–250).
  static int get puzzleBonusMin =>
      TuningValues.current.ints('puzzle_reward')[0];

  /// §3.16 / PRD-2.3 §14.2 See [puzzleBonusMin].
  static int get puzzleBonusMax =>
      TuningValues.current.ints('puzzle_reward')[1];

  /// §3.16 / PRD-2.3 §14.2 See [puzzleBonusMin].
  static int get puzzleBonusStep =>
      TuningValues.current.ints('puzzle_reward')[2];

  /// §3.30 Hourglass duration range (s).
  static const double hourglassMin = 10;

  /// §3.30 Hourglass duration range (s).
  static const double hourglassMax = 20;

  // --- helpers ---------------------------------------------------------------

  /// PRD-2.3 §14.4 Cruise at [hoopIndex] (pt/s): the `curve_speed`
  /// keyframe table (150 at hoop 0, 172.5 at 50, 187.5 from 150). A revive
  /// keeps the current speed (the hoop index is not reset).
  static double cruise(int hoopIndex) =>
      TuningValues.current.curve('curve_speed').at(hoopIndex);

  /// PRD-2.3 §14.4 the runClock seconds [hoops] hoops take from
  /// [fromHoop] at the cruise of each hoop (spacing / cruise per hoop): the
  /// squeeze schedule counted in hoops.
  static double secondsForHoops(int fromHoop, int hoops) {
    var t = 0.0;
    for (var k = 0; k < hoops; k++) {
      t += spacing / cruise(fromHoop + k);
    }
    return t;
  }

  /// §3.0.1 / PRD-2.3 §14.4 / PRD-2.4 §2 Opening at [hoopIndex] (before the
  /// Big Hoops multiplier): hoop 0 is 118 (the fixed easy first hoop,
  /// §10.2); from hoop 1 the `curve_opening` keyframe table, 118 at hoops
  /// 1–2, 110.5 at 10, 98 at 25, 87.5 at 40, 72 at 75, 66 from hoop 100
  /// (PRD-2.4 §1.2). Rides, comets and re-plans during a ride follow the
  /// same curve (PRD-2.4 §2); only the portal stays 118 ([portalOpening]).
  /// Replaces the 2.2 118 − 0.32 %/hoop → 92.
  static double openingFor(int hoopIndex) {
    if (hoopIndex <= 0) return opening0;
    return TuningValues.current.curve('curve_opening').at(hoopIndex);
  }

  /// §3.0.1 Colour stage for [hoopsPassed].
  static int stageForHoops(int hoopsPassed) =>
      (hoopsPassed ~/ stageEveryHoops) % stageCount;
}
