import 'dart:ui';

import '../effects/pickup_touch_fx.dart';
import 'parts_config.dart';

/// Comet boost (PRD-2 §3.8, §3.9, §5.6; `screen_comet2.html`). Every
/// member's doc starts with its PRD section (ARCH §4). The pickup hit radius
/// (18) is `PickupRadii.comet`, the hang (20 pt past the plane) is
/// `RunConfig.cometHang` and the schedule lives in `DirectorTables.prd2`.
///
/// 2.3.1 (PRD-2.3.1 §16): the comet hoop layout is locked at comet start —
/// the hoops not yet visible move into it, the comet hoops are spread
/// evenly up to the predicted end − `RunConfig.cometTail`, and the first
/// normal hoop after the ride is ≥ the end + `RunConfig.cometAfterGap`.
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

  /// PRD-2.2 §16.1 Hoops the director plans during a comet ride sit
  /// alternately this far above and below the playfield middle
  /// (`viewHeight / 2`), the first opposite to the star hoop (pt; fixed on
  /// every run height).
  static const double zigzagAmp = 70;

  /// PRD-2.2 §16.1 The comet tilts along its flight direction
  /// (`atan2(vy, forward speed)`), capped at ±this (degrees; was ±25° from
  /// the vertical speed in PRD-2 §5.6).
  static const double maxTiltDeg = 35;

  /// PRD-2.2 §16.1 The tilt follows the flight direction but turns at
  /// most this fast (degrees per second), so it never snaps (a moving
  /// ring's crossing point can move; the curve itself turns ≤ ≈ 110°/s).
  static const double maxTiltRateDeg = 240;

  /// PRD-2.2 §16.1 A hoop whose plane is less than this far ahead when a
  /// new curve starts (the star is caught up to ≈ 30 pt before its hoop's
  /// plane) is flown through as it is: the curve starts at the bird's
  /// height and leads to the hoop after it (pt).
  static const double minCurveSpan = 40;

  // --- PRD-2.2 §17 the landing ------------------------------------------------

  /// PRD-2.2 §17.1 At control return the run world runs at this time scale
  /// (the Hourglass's `RunState.timeScale`; quiet: no vignette, no sounds,
  /// music at its normal pitch)…
  static const double landingScale = .5;

  /// PRD-2.2 §17.1 …for this long (s of real time)…
  static const double landingHold = .8;

  /// PRD-2.2 §17.1 …then eases back to 1 over this long (s of real time,
  /// smoothstep): ≈ 1.5 s in all.
  static const double landingEase = .7;

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

  /// PRD-2.3 §17.2 visual reach of the comet star (measured from the
  /// painter): the gold tail's tip [tailGoldTipX] plus the star pulse.
  static const double visualReach = -tailGoldTipX + 4;
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
