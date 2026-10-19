import 'dart:ui';

import '../director/plans.dart' show SawDesign;
import 'parts_config.dart';

/// Saw rings — Live Wire, Frost Ring, Black Hole (PRD-2 §3.18, §5.17; mock
/// `screen_hazard_hoops4.html`, builder `build60.py` + `build60_themes.js`).
/// Every member's doc starts with its PRD section (ARCH §4). The extra
/// opening lives in `RunConfig.sawExtraOpening` (the director applies it;
/// PRD-2.2 §25: 0, saw rings have the normal opening).
abstract final class SawConfig {
  // ------------------------------------------------------------- the rim
  /// §3.18 Rim-end collider radius (pt) = half the design's rim thickness:
  /// 5 (Live Wire / Frost Ring, 10 pt rim) or 6 (Black Hole, 12 pt rim).
  static double rimRadius(SawDesign d) => switch (d) {
    SawDesign.liveWire || SawDesign.frostRing => 5,
    SawDesign.blackHole => 6,
  };

  // ------------------------------------------------- decoration scale
  /// PRD-2.2 §25 The saw decorations (glow, swirl, ripples, sparks,
  /// crystals, stars / debris) were designed at this opening (pt): the
  /// PRD-2 normal 118 + 28. Every decoration size / offset is multiplied by
  /// `ry / ryDesign` (`SawHoopKind.decorScaleFor`); the rim thickness, the
  /// rim-end colliders and [pullRange] are not scaled.
  static const double decorDesignOpening = 146;

  /// PRD-2.2 §25 The half height the decorations were designed at
  /// (`RingPainter.ryFor(146)` = 146 / 2 + 7).
  static const double ryDesign = decorDesignOpening / 2 + PartsConfig.rimRadius;

  // --------------------------------------------------- Black Hole pull
  /// §3.18 The pull acts within this distance (pt) of a rim end, measured
  /// from the rim-end centre to the bird's edge (the mock's `34 + BR`).
  static const double pullRange = 34;

  /// §3.18 Pull toward the rim (pt/s²) outside the inhale.
  static const double pull = 260;

  /// §3.18 Pull during the inhale peak (pt/s²).
  static const double inhalePull = 570;

  /// §3.18 / §5.17 The Black Hole inhales every this many seconds.
  static const double inhalePeriod = 3.4;

  /// §3.18 / §5.17 Inhale length (s).
  static const double inhaleLength = .9;

  /// §5.17 Each hole's inhale clock is phased by `seed × 0.07` s (mock).
  static const double inhalePhasePerSeed = .07;

  // ---------------------------------------------------------- deaths
  /// §5.17 / §3.0.5 Live Wire: the bird is held (s) before the tumble.
  static const double wireHold = .6;

  /// §5.17 Live Wire X-ray / over-bright alternation (s): X-ray part.
  static const double wireXray = .19;

  /// §5.17 Live Wire X-ray / over-bright alternation (s): bright part.
  static const double wireBright = .09;

  /// §5.17 Live Wire held jitter (pt / rad).
  static const double wireJitter = 3;

  /// §5.17 Live Wire held jitter angle (rad).
  static const double wireJitterAngle = .25;

  /// §5.17 Live Wire charred twitches per second.
  static const double wireTwitchRate = 3;

  /// §5.17 / §3.0.5 Frost Ring: the ice block forms (s) — the held moment.
  static const double frostHold = .4;

  /// §5.17 Frost Ring: the block crunches shut over this time (s).
  static const double frostForm = .3;

  /// §5.17 Frost Ring: the cracks spread at this time (s).
  static const double frostCrack = .38;

  /// §5.17 Frost Ring: ice block size (pt).
  static const double frostBlockW = 56, frostBlockH = 48;

  /// §5.17 Frost Ring: shards when the block shatters on the floor spikes.
  static const int frostShards = 36;

  /// §5.17 Black Hole: the bird is pulled to the contact point while it
  /// stretches, spins and shrinks (s).
  static const double holeHold = .8;

  /// §3.0.5 Black Hole: nothing is left — the revive offer / results come
  /// this long after the boom (s; within the 2.2 s themed maximum).
  static const double holeAfter = .6;

  /// §5.17 Black Hole: the screen darkens within this radius (pt).
  static const double holeDarkRadius = 140;

  // ------------------------------------------------------ approach hum
  /// §5.17 Hum volume = closeness² × this (mock gain `k² × 0.8`).
  static const double humGain = .8;

  /// §5.17 The hum starts when the ring is this far right of the screen
  /// edge (pt) and is gone once the ring is this far behind the bird.
  static const double humAhead = 40, humBehind = 60;

  // ------------------------------------------------------------ looks
  /// §5.17 Live Wire: redraws of the crawling arcs per second.
  static const double wireRedraw = 18;

  /// §5.17 Live Wire: chance of a big forked strike per redraw.
  static const double wireStrike = .09;

  /// §5.17 Live Wire: near-miss bolt reach (pt from a rim end to the bird
  /// edge).
  static const double wireNear = 46;

  /// §5.17 Live Wire colours: navy core, glowing cyan, bolt body.
  static const Color wireCore = Color(0xFF1E2B55);
  static const Color wireCoreBack = Color(0xFF121A38);
  static const Color wireCyan = Color(0xFF5CF2FF);
  static const Color wireCyanBack = Color(0xFF0E93AD);
  static const Color wireGlow = Color(0xFF22E6FF);

  /// §5.17 Frost Ring colours: rim, inner rim, shards.
  static const Color frostRim = Color(0xFF2F7FB0);
  static const Color frostRimBack = Color(0xFF1F5E86);
  static const Color frostInner = Color(0xFF9BE3FF);
  static const Color frostInnerBack = Color(0xFF5AAED6);
  static const Color frostTint = Color(0xFF6EC8FF);

  /// §5.17 Frost Ring: shard cluster points round the ring.
  static const int frostPoints = 46;

  /// §5.17 Black Hole: torus width (pt), photon ring, plasma colours.
  static const double holeTorus = 16;
  static const Color holePhoton = Color(0xFFFFE7B0);
  static const Color holePhotonGlow = Color(0xFFFFB04D);
  static const Color holeHunger = Color(0xFFFF3D6E);
  static const List<Color> holePlasma = [
    Color(0xFFFFF3D0),
    Color(0xFFFFB04D),
    Color(0xFFFF5E2B),
    Color(0xFFB388FF),
  ];

  /// §5.17 Black Hole: the void reaches this far out of the rim (pt);
  /// it grows by [holeVoidHunger] (≈ +60 %) during the inhale.
  static const double holeVoid = 36, holeVoidHunger = .6;

  /// §5.17 Black Hole lensing: the spike strips bend toward it, strongest
  /// within ≈ 170 pt (`exp(−d / 170)`); strength 0.24 (+0.2 hungry).
  static const double lensRange = 170, lensStrength = .24, lensHunger = .2;

  /// §5.17 Black Hole: stars spiralling in.
  static const int holeStars = 70;
}
