/// PRD-2 core tuning (§3.0.1) and the director's placement constants
/// (§3.0.2 / §3.0.3 / §3.0.8). Every member's doc starts with its PRD
/// section (ARCH §4). Pure Dart.
abstract final class RunConfig {
  // --- §3.0.1 core tuning --------------------------------------------------

  /// §3.0.1 Playfield width (pt); unchanged from 1.0.
  static const double worldWidth = 320;

  /// §3.0.1 Screen height the PRD specifies layouts at (pt).
  static const double designHeight = 711;

  /// §3.0.1 Cruise (scroll) speed at runClock 0 (pt/s).
  static const double cruiseSpeed = 150;

  /// §3.0.1 Cruise rise per minute of runClock (fraction: 0.035 = +3.5 %).
  static const double cruiseRampPerMinute = 0.035;

  /// §3.0.1 Hoop spacing, plane to plane (pt). Constant.
  static const double spacing = 310;

  /// §3.0.1 The first hoop spawns this far past the right edge (pt) at the
  /// first tap and scrolls in (json "1.3 s" is overridden by the PRD).
  static const double firstHoopOffscreen = 60;

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

  /// §3.0.1 Opening at hoop 0 (pt).
  static const double opening0 = 118;

  /// §3.0.1 Opening shrink per hoop index (fraction of [opening0]).
  static const double openingShrinkPerHoop = 0.0032;

  /// §3.0.1 Opening floor (fraction of [opening0]: 78 % = 92 pt).
  static const double openingFloor = 0.78;

  /// §3.0.1 / §3.0.4 Rim-end circle radius (pt).
  static const double rimRadius = 7;

  /// §3.0.1 / §3.0.4 Rim restitution.
  static const double rimRestitution = 0.85;

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

  /// §3.18 Saw rings: extra opening (pt).
  static const double sawExtraOpening = 28;

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

  /// §3.25 Lucky Spin slices (coins), equal chance.
  static const List<int> luckySpinSlices = [2, 5, 10, 3, 20, 5];

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

  /// §3.17 First squeeze at runClock 60–120 s; again 60–120 s after it opens.
  static const double squeezeGapMin = 60;

  /// §3.17 First squeeze at runClock 60–120 s; again 60–120 s after it opens.
  static const double squeezeGapMax = 120;

  /// §3.17 Squeeze hold duration range (s).
  static const double squeezeHoldMin = 10;

  /// §3.17 Squeeze hold duration range (s).
  static const double squeezeHoldMax = 20;

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

  /// §3.16 Puzzle completion bonus range (coins) and step.
  static const int puzzleBonusMin = 50;

  /// §3.16 Puzzle completion bonus range (coins) and step.
  static const int puzzleBonusMax = 250;

  /// §3.16 Puzzle completion bonus range (coins) and step.
  static const int puzzleBonusStep = 5;

  /// §3.30 Hourglass duration range (s).
  static const double hourglassMin = 10;

  /// §3.30 Hourglass duration range (s).
  static const double hourglassMax = 20;

  // --- helpers ---------------------------------------------------------------

  /// §3.0.1 Cruise at [runClock] seconds: 150 pt/s, +3.5 % per minute.
  static double cruise(double runClock) =>
      cruiseSpeed * (1 + cruiseRampPerMinute * runClock / 60);

  /// §3.0.1 Opening at [hoopIndex] (rides: full size).
  static double openingFor(int hoopIndex, {bool ride = false}) {
    if (ride) return opening0;
    final shrunk = opening0 * (1 - openingShrinkPerHoop * hoopIndex);
    final floor = opening0 * openingFloor;
    return shrunk < floor ? floor : shrunk;
  }

  /// §3.0.1 Colour stage for [hoopsPassed].
  static int stageForHoops(int hoopsPassed) =>
      (hoopsPassed ~/ stageEveryHoops) % stageCount;
}
