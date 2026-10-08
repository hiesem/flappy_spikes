import 'dart:ui';

import '../../game/sound.dart';

/// Star Trail (PRD-2 §3.26, §5.25; `design/menu_v2/lab_collect.js` `IDEAS.trail`).
/// The spawn rules (gap 5, weight 30, ≥ 8 gaps apart, inset 40, bulge 40,
/// 8 stars) live in `DirectorTables.prd2` / `RunConfig`; this file holds the
/// art and sound numbers. Every member's doc starts with its PRD section.
abstract final class StarTrailConfig {
  // --- §3.26 the trail ------------------------------------------------------

  /// §3.26 Stars per trail (mock `for i<8`).
  static const int stars = 8;

  /// §3.26 Star i sits at u = (i + 1) / 9 along the arc.
  static double u(int i) => (i + 1) / (stars + 1);

  /// §3.26 Collecting all 8 pays +5 coins (PERFECT LINE).
  static const int reward = 5;

  // --- §5.25 the stars ------------------------------------------------------

  /// §5.25 4-point star base size (pt) and the twinkle ±(pt) at 6 rad/s
  /// (mock `8 + 1.6 sin(6t + i)`).
  static const double starBase = 8;
  static const double starPulse = 1.6;
  static const double starPulseOmega = 6;

  /// §5.25 Gold `#FFB529` with a pale core `#FFF8E1` at 0.5×.
  static const Color gold = Color(0xFFFFB529);
  static const Color core = Color(0xFFFFF8E1);
  static const double coreScale = .5;

  /// §5.25 Soft gold halo (r 16, `rgba(255,213,74,·)` at α 0.45).
  static const Color halo = Color(0xFFFFD54A);
  static const double haloR = 16;
  static const double haloAlpha = .45;

  /// §5.25 Dotted gold line (2 pt, 2 on / 6 off, `rgba(255,181,41,·)` 0.45).
  static const double lineWidth = 2;
  static const List<double> lineDashes = [2, 6];
  static const double lineAlpha = .45;

  /// §5.25 A collected star sparkles: a 12 pt `#FFF59D` twinkle rising at
  /// 30 pt/s for 0.4 s (mock `parts.push({kind:'star', s:12, col:'#FFF59D'})`).
  static const double sparkleSize = 12;
  static const Color sparkleColor = Color(0xFFFFF59D);
  static const double sparkleRise = 30;
  static const double sparkleLife = .4;

  /// §5.25 Otherwise a pop "n / 8" in `#B87F00` (mock `pop(got + ' / 8',
  /// BX + 40, bird.y − 36)`; `pop()`'s default size 20).
  static const Color popColor = Color(0xFFB87F00);
  static const double popDx = 40;
  static const double popDy = -36;
  static const double popSize = 20;

  /// §5.25 PERFECT LINE banner colour.
  static const Color bannerColor = Color(0xFFFFB529);

  /// §5.25 The PERFECT LINE banner and its one-line explanation (mock
  /// `banner('PERFECT LINE', '#FFB529', '8 / 8 stars · +5 coins')`).
  static const String bannerText = 'PERFECT LINE';
  static const String bannerSub = '8 / 8 stars · +5 coins';

  /// §5.25 Each star plays the next note of C major (C5 → C6); all 8 a chord.
  static const List<Sfx> notes = [
    Sfx.trailNote1,
    Sfx.trailNote2,
    Sfx.trailNote3,
    Sfx.trailNote4,
    Sfx.trailNote5,
    Sfx.trailNote6,
    Sfx.trailNote7,
    Sfx.trailNote8,
  ];
}
