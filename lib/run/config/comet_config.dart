import 'dart:ui';

import '../effects/pickup_touch_fx.dart';
import 'parts_config.dart';

/// Comet boost (PRD-2 §3.8, §3.9, §5.6; `screen_comet2.html`). Every
/// member's doc starts with its PRD section (ARCH §4). The pickup hit radius
/// (18) is `PickupRadii.comet`, the hang (20 pt past the plane) is
/// `RunConfig.cometHang` and the schedule lives in `DirectorTables.prd2`.
abstract final class CometConfig {
  // --- §3.8 the boost -------------------------------------------------------

  /// §3.8 Boost length (s of game time; owner decision 2026-10-07).
  static const double duration = 10;

  /// §3.8 World scroll during the boost (× cruise ≈ 255 pt/s at the start).
  static const double speedMult = 1.7;

  /// §3.8 Ease-in to [speedMult] (s, smoothstep).
  static const double easeIn = .45;

  /// §3.8 The last this-many seconds ease the speed back to cruise (s,
  /// smoothstep: the smooth landing).
  static const double easeOut = .9;

  /// §5.6 Auto-pilot steering: the comet closes this fraction of its
  /// vertical distance to the target per second (`screen_comet2.html`
  /// `rate = 16`; y += (target − y) · min(1, dt · rate)).
  static const double steerRate = 16;

  /// §5.6 Auto-pilot vertical speed cap (pt/s). Call: the mock's rate alone
  /// jumps up to ≈ 4 800 pt/s when the target switches to the next hoop;
  /// 900 pt/s still reaches any next hoop (≤ 0.52 band) in < 0.4 s of the
  /// ≈ 1.2 s between boost hoops.
  static const double maxSteerSpeed = 900;

  /// §5.6 The comet tilts with its vertical motion: (target − y) × this
  /// (degrees per pt), capped at ±[maxTiltDeg].
  static const double tiltPerPt = .3;

  /// §5.6 Tilt cap (degrees).
  static const double maxTiltDeg = 25;

  // --- §3.9 sounds ----------------------------------------------------------

  /// §3.9 `pu_comet_loop` starts this long after the collection (s).
  static const double loopDelay = 1.2;

  /// §3.9 The comet loop plays at ≈ 30 % volume under other sounds.
  static const double loopVolume = .3;

  /// §3.9 The loop fades out over this long when the boost ends (s).
  static const double loopFade = .3;

  // --- §5.6 the fireball (80 × 60 graphic, centre (40, 30)) ------------------

  /// §5.6 The bird rides inside the fireball at 90 %.
  static const double birdScale = .9;

  /// §5.6 Shell: gold disc r 28 with a pink 3.5 pt rim, inner glow r 22.
  static const double shellR = 28;
  static const double shellStroke = 3.5;
  static const double shellInnerR = 22;
  static const Color shellInner = Color(0xFFFFD98A);

  /// §5.6 Tail triangles behind the shell (offsets from the comet centre,
  /// pt): gold 45 % (−4, ±22) → (−104, 0); pink 55 % (−4, ±15) → (−74, 0).
  static const double tailGoldBaseX = -4;
  static const double tailGoldHalf = 22;
  static const double tailGoldTipX = -104;
  static const double tailGoldAlpha = .45;
  static const double tailPinkBaseX = -4;
  static const double tailPinkHalf = 15;
  static const double tailPinkTipX = -74;
  static const double tailPinkAlpha = .55;

  /// §5.6 Countdown ring: r 34, gold 6 pt, round caps, drains clockwise
  /// from the top over the boost; soft white track (#ffffff55 at 0.6).
  static const double ringR = 34;
  static const double ringStroke = 6;
  static const Color ringTrack = Color(0x55FFFFFF);
  static const double ringTrackOpacity = .6;

  /// §5.6 "10s → 1s" label: gold 18 pt, centred 50 pt below the comet.
  static const double labelBelow = 50;
  static const double labelSize = 18;

  // --- §3.8 / §5.6 the pop (collection and landing) --------------------------

  /// §5.6 The comet graphic pops 0.4 → 1.3 → 1 over this long (s).
  static const double popLength = .38;
  static const double popFrom = .4;
  static const double popPeak = 1.3;

  /// §3.8 The pop's white flash over the screen: 0.7 → 0 over [popLength].
  static const double flashAlpha = .7;

  /// §3.8 / §5.6 The pop's squares and gold ring ([PickupTouchFx]): 10
  /// squares of 9 pt, pink / gold, 70 pt out in 0.5 s (no spin); a gold
  /// ring 10 → 56 pt.
  static const PickupTouchSpec pop = PickupTouchSpec(
    ringFrom: 10,
    ringTo: 56,
    ringStroke: 4,
    ringLength: .5,
    ringEase: false,
    squares: 10,
    squareMin: 9,
    squareMax: 9,
    speedMin: 140,
    speedMax: 140,
    damp: 0,
    spin: 0,
    lifeMin: .5,
    lifeMax: .5,
    colors: [PartsConfig.pink, PartsConfig.gold],
  );

  // --- §5.6 speed streaks (master #12, kept separate) ------------------------

  /// §5.6 / §3.0.9 #12 One streak every ≈ 34 ms.
  static const double lineEvery = .034;

  /// §5.6 Streak length range (pt), 2 pt thick, white at 0.7.
  static const double lineMin = 30;
  static const double lineMax = 110;
  static const double lineThickness = 2;
  static const double lineAlpha = .7;

  /// §5.6 A streak starts at x 340 and slides 460 pt left in 260 ms.
  static const double lineStartX = 340;
  static const double lineTravel = 460;
  static const double lineLife = .26;

  /// §5.6 Streak rows: from 120 pt below the top to 91 pt above the bottom
  /// (the mock's 120–620 at 711).
  static const double lineTop = 120;
  static const double lineBottomInset = 91;

  // --- §5.6 the pickup -------------------------------------------------------

  /// §5.6 Pickup star: 46 pt 4-point star, gold with a white 2 pt outline
  /// and an inner white star (0.9), tail to the right.
  static const double starSize = 46;
  static const double starOutline = 2;

  /// §5.6 The star wobbles ±14° (sin 3t) and pulses ±8 % (sin 6t).
  static const double starWobbleDeg = 14;
  static const double starWobbleOmega = 3;
  static const double starPulse = .08;
  static const double starPulseOmega = 6;

  /// §5.6 The pickup bobs ±4 pt (sin 4t).
  static const double starBob = 4;
  static const double starBobOmega = 4;
}
