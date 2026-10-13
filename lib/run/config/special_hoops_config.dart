import 'dart:ui';

import 'tuning_values.dart';

/// Bullseye Ring (PRD-2 §3.24, §5.23). Every member's doc starts with its
/// PRD section.
abstract final class BullseyeConfig {
  /// §3.24 Bullseye band: ± this many pt around the ring centre (fixed as
  /// openings shrink, Q63).
  static const double band = 12;

  /// §3.24 Coins for a bullseye. PRD-2.3 §14.2: 1 (`coin_bullseye`; was
  /// 3).
  static int get coins => TuningValues.current.i('coin_bullseye');

  /// §5.23 Target rings (radius pt, colour), outside in.
  static const List<(double, Color)> target = [
    (15, Color(0xFFFFFFFF)),
    (11, Color(0xFFFF3B5C)),
    (7, Color(0xFFFFFFFF)),
    (3.5, Color(0xFFFF3B5C)),
  ];

  /// §5.23 Target squashed to this share of its width.
  static const double targetSquash = .62;

  /// §5.23 Band guide lines start this far before the ring (pt).
  static const double guideFrom = 46;

  /// §5.23 Band guide lines end this far before the ring centre (pt).
  static const double guideTo = 8;

  /// §5.23 Guide line opacity (stage foreground).
  static const double guideAlpha = .45;

  /// §5.23 Guide line width (pt) and dash.
  static const double guideWidth = 1.5;

  /// §5.23 Guide dash on / off (pt).
  static const List<double> guideDash = [3, 4];

  /// §5.23 Hit: the target "flashes bigger" — it grows by this share and
  /// shrinks back at 1 /s (0.5 s).
  static const double flashGrow = .5;

  /// §5.23 Burst / banner colour.
  static const Color red = Color(0xFFFF3B5C);

  /// §5.23 Burst particles.
  static const int burst = 16;

  /// §5.23 Burst speed (pt/s).
  static const double burstSpeed = 170;
}

/// Ring Train (PRD-2 §3.22, §5.21). Layout knobs (56 pt, ±16 pt) live in
/// `RunConfig.trainDx` / `trainDy` (the director places the train).
abstract final class TrainConfig {
  /// §3.22 Rings in a train.
  static const int rings = 3;

  /// §3.22 Combo coins for all three rings. PRD-2.3 §14.2: 1
  /// (`coin_train`; was 3).
  static int get comboCoins => TuningValues.current.i('coin_train');

  /// §5.21 Track: from this far before the first ring to this far after
  /// the last (pt).
  static const double trackOverhang = 34;

  /// §5.21 Track opacity (stage foreground).
  static const double trackAlpha = .5;

  /// §5.21 Track dash phase speed (pt/s, toward the bird).
  static const double trackSpeed = 40;

  /// §5.21 Progress dot diameter (pt).
  static const double dotSize = 6.5;

  /// §5.21 Dots sit this far above the highest ring's top (pt).
  static const double dotAbove = 20;

  /// §5.21 Unfilled dot colour (grey 40 %).
  static const Color dotEmpty = Color(0x66828282);

  /// §5.21 Passed ring / filled dot gold.
  static const Color gold = Color(0xFFFFB529);

  /// §5.21 Banner title.
  static const String bannerText = 'TRAIN ×3';

  /// §5.21 Banner subtitle.
  static String get bannerSub =>
      'all three rings · +$comboCoins ${comboCoins == 1 ? 'coin' : 'coins'}';
}

/// Spring Ring (PRD-2 §3.23, §5.22). The 240 pt jump lives in
/// `RunConfig.springJump` (the director places the next ring).
abstract final class SpringConfig {
  /// §3.23 Launch vy up (pt/s).
  static const double launchUp = -770;

  /// §3.23 Launch vy down (pt/s).
  static const double launchDown = 420;

  /// §3.23 Flap lock after an up launch (s).
  static const double lockUp = .45;

  /// §3.23 Flap lock after a down launch (s).
  static const double lockDown = .28;

  /// §5.22 Ring front colour.
  static const Color front = Color(0xFF2EBD6B);

  /// §5.22 Ring back colour (also the coils).
  static const Color back = Color(0xFF1E8A4C);

  /// §5.22 Coil turns above / below the rim ends.
  static const int coilTurns = 6;

  /// §5.22 Coil stroke (pt).
  static const double coilWidth = 2.6;

  /// §5.22 Coil half width (pt) and step per turn (pt).
  static const double coilHalfWidth = 6;

  /// §5.22 Coil step per turn (pt).
  static const double coilStep = 3.2;

  /// §5.22 Chevron cycles per second.
  static const double chevronSpeed = 1.6;

  /// §5.22 Chevron travel (pt, centred on the ring).
  static const double chevronTravel = 52;

  /// §5.22 Wobble amplitude (pt) and length (s).
  static const double wobble = 7;

  /// §5.22 Wobble length (s).
  static const double wobbleSeconds = .5;

  /// §5.22 Wobble frequency (rad per unit of the decaying wobble).
  static const double wobbleFreq = 30;

  /// §5.22 Burst particles and speed (pt/s).
  static const int burst = 12;

  /// §5.22 Burst speed (pt/s).
  static const double burstSpeed = 150;

  /// §5.22 Pop text.
  static const String popUp = 'BOING ↑';

  /// §5.22 Pop text (down).
  static const String popDown = 'BOING ↓';
}

/// Lucky Spin (PRD-2 §3.25, §5.24). The slices' coins live in
/// `RunConfig.luckySpinSlices` (the director pre-rolls the prize).
abstract final class LuckySpinConfig {
  /// §5.24 Slice colours (same order as the prizes).
  static const List<Color> sliceColors = [
    Color(0xFFEC008C),
    Color(0xFFFFB529),
    Color(0xFF2F80FF),
    Color(0xFF8E5CFF),
    Color(0xFFFF7A1A),
    Color(0xFF2EBD6B),
  ];

  /// §5.24 Wheel radius (pt).
  static const double radius = 24;

  /// §5.24 Wheel centre above the top rim (pt).
  static const double above = 36;

  /// PRD-2.3 §17.2 visual reach of the Lucky Spin ring (measured from the
  /// painter): the wheel ([radius]) and its rim stroke, centred on the
  /// ring's plane; the ring itself is narrower.
  static const double visualReach = radius + 4;

  /// §5.24 Post width (pt).
  static const double postWidth = 3;

  /// §5.24 Free spin (rad/s).
  static const double spin = 7;

  /// §5.24 Slow-down after the pass (rad/s²) — the stop lands on the
  /// pre-rolled slice, so the real rate is within a slice of this.
  static const double decel = 8;

  /// §5.24 Label size (pt).
  static const double labelSize = 10;

  /// §5.24 Burst particles at the wheel.
  static const int burst = 18;

  /// §5.24 Burst speed (pt/s).
  static const double burstSpeed = 180;

  /// §5.24 Ticks play only while the wheel is on screen (+30 pt).
  static const double tickMargin = 30;

  /// §5.24 Banner subtitle.
  static const String bannerSub = 'lucky spin · coins';
}
