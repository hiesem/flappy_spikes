import 'dart:ui';

import '../../game/sound.dart';
import '../run_layers.dart';
import 'tuning_values.dart';

/// Perfect-pass streak, ring tier reactions and the graze notice (PRD-2
/// §3.4, §3.5, §3.19 FEVER hook, §5.3, §5.4). The look of every effect is a
/// §3.0.9 master (`PartsConfig`); these are the streak's own rules. Every
/// member's doc starts with its PRD section (ARCH §4).
abstract final class StreakConfig {
  /// §3.4 The streak tiers (effects) are capped here; further perfect
  /// passes keep the top tier's effects. PRD-2.2 §29: it no longer caps the
  /// banner name ([names], [nameFor]).
  static const int tierCap = 10;

  /// PRD-2.2 §29.3 The 50 streak names (×1 … ×50); from ×51 the last one
  /// ([names].last, FLAPPY GOD) with the real number. Owner-approved
  /// 2026-10-11 (PHOENIX / LEGEND are level names, not used here).
  static const List<String> names = [
    'PERFECT', 'GREAT', 'ON FIRE', 'AMAZING', 'SOARING', //
    'SKY HIGH', 'HIGH FLYER', 'FEATHERLIGHT', 'EAGLE EYE', 'FREE BIRD', //
    'TAILWIND', 'SKYLARK', 'TOP BIRD', 'WINGMASTER', 'RINGMASTER', //
    'SPIKE-PROOF', 'BLAZING', 'FIREBIRD', 'PEREGRINE', 'STORMRIDER', //
    'THUNDERBIRD', 'HURRICANE', 'SKYDRAGON', 'GRIFFIN', 'MIGHTY ROC', //
    'PEGASUS', 'STARLING', 'COMET', 'METEOR', 'SUPERNOVA', //
    'COSMIC', 'GALACTIC', 'ASTRAL', 'BLACK HOLE', 'WARP SPEED', //
    'CELESTIAL', 'DIVINE', 'MYTHIC', 'GODLIKE', 'IMMORTAL', //
    'UNSTOPPABLE', 'UNTOUCHABLE', 'LIMITLESS', 'ETERNAL', 'INFINITE', //
    'FLAWLESS', 'SKY KING', 'KING OF BIRDS', 'ASCENDED', 'FLAPPY GOD', //
  ];

  /// PRD-2.2 §29.2 The 10 banner colours (white text), rotating: streak n
  /// uses colour ((n − 1) mod 10) + 1.
  static const List<Color> colours = [
    Color(0xFFEC008C), // 1 pink
    Color(0xFFFF4FB7), // 2 light pink
    Color(0xFFFFB529), // 3 gold
    Color(0xFFFF7A1A), // 4 tangerine
    Color(0xFFE8141C), // 5 fever red
    Color(0xFFC2185B), // 6 deep pink
    Color(0xFF9B30D9), // 7 epic purple
    Color(0xFF1E9BE0), // 8 sky blue
    Color(0xFF00897B), // 9 teal
    Color(0xFF7A0044), // 10 plum
  ];

  /// PRD-2.2 §29.1 The banner text for perfect streak [n] (≥ 1): ×1 is just
  /// PERFECT, every other streak NAME ×n; from ×51 FLAPPY GOD ×n.
  static String nameFor(int n) {
    final k = n < 1 ? 1 : n;
    if (k == 1) return names.first;
    final name = names[(k > names.length ? names.length : k) - 1];
    return '$name ×$k';
  }

  /// PRD-2.2 §29.2 The banner colour for perfect streak [n] (≥ 1).
  static Color colourFor(int n) => colours[((n < 1 ? 1 : n) - 1) % 10];

  /// §3.4 / §5.3 Tiers above this reuse its effects (tier 3+ look).
  static const int topEffectTier = 3;

  /// §3.5 / §5.3 The bird turns gold from this tier.
  static const int goldBirdTier = 2;

  /// §3.5 / §5.3 The bird leaves its trail from this tier.
  static const int trailTier = 3;

  /// §3.19 A perfect FEVER pass sets the streak to max(this, streak + 1)
  /// (PRD-2.3 §14.3 unchanged; tunable `point_fever_streak`).
  static int get feverMinStreak =>
      TuningValues.current.i('point_fever_streak');

  /// §3.4 Tier sounds: streak 1, 2 and 3+ (index = min(streak, 3) − 1).
  static const List<Sfx> tierSounds = [
    Sfx.perfect1,
    Sfx.perfect2,
    Sfx.perfect3,
  ];

  /// §5.3 Graze notice text ("GRAZE · streak lost").
  static const String grazeText = 'GRAZE · streak lost';

  /// §5.3 Graze notice: font size (pt), letter-spacing (em).
  static const double grazeFontSize = 22;
  static const double grazeLetterSpacing = .1;

  /// §5.3 Graze notice: centre x and top y (pt; mock left 60, top 250 —
  /// top-anchored like the HUD, §3.0.1 screen heights).
  static const double grazeCentreX = 160;
  static const double grazeTop = 250;

  /// §5.3 Graze notice: rises this far (pt) while fading out over
  /// [grazeDuration] (s).
  static const double grazeRise = 26;
  static const double grazeDuration = 1.1;

  /// §5.4 Effects sit above the hoops and below the HUD: the perfect burst
  /// (screen space, at the bird, like the §5.3 mock's `pop`).
  static const int burstPriority = RunLayer.fx;

  /// §5.3 The block / equipped trail is drawn right behind the bird (mock
  /// z 9 under the bird's 10). PRD-2.2 §21: one step lower, so the bird's
  /// fire (`FeverConfig.firePriority`, bird − 1) draws over the trail as in
  /// `screen_fire_choice2.html` (trail → halo → flames → bird).
  static const int trailPriority = RunLayer.bird - 2;

  /// §3.0.9 #7 / §5.4 The banner band's priority inside the run's banner
  /// layer (PRD-2.2 §12.2: the layer itself is in the world at
  /// `RunLayer.banners`, behind the gameplay; the stickers sit under it).
  static const int bannerPriority = 18;

  /// §5.3 The graze notice: same band as the banners.
  static const int grazePriority = 18;

  /// §5.3 Graze notice colour fallback (the stage foreground is used).
  static const Color grazeFallback = Color(0xFF828282);
}

// PRD-2.3 §14.3 the PRD-2.2 §11 perfect zone (`PerfectConfig`: ±0.2 × the
// opening, max 24 pt) is retired: a perfect is any pass with no rim touch.
// The Bullseye keeps its own band (`BullseyeConfig.band`, remote
// `point_bullseye_band`, owner 2026-10-13).

/// Owner 2026-10-13 (PRD-2.3 §14.3 + §15): the optional remote perfect band.
abstract final class PerfectBandConfig {
  /// Owner 2026-10-13: the perfect band (± pt around the gap centre) at
  /// [hoopIndex], from the `point_perfect_band` keyframe curve (default
  /// `[[0, 0]]`). A value ≤ 0 means no band (the §14.3 rule).
  static double bandAt(int hoopIndex) =>
      TuningValues.current.curve('point_perfect_band').at(hoopIndex);

  /// Owner 2026-10-13: whether a non-ride pass is perfect. A rim touch is
  /// never perfect. With a band v > 0 the bird centre's crossing [offset]
  /// (ring-local, `Hoop.passOffset`, measured like the Bullseye) must also
  /// be within ±v pt; a null [offset] (no crossing recorded) skips the band.
  static bool isPerfect({
    required bool touched,
    required int hoopIndex,
    double? offset,
  }) {
    if (touched) return false;
    final v = bandAt(hoopIndex);
    if (v <= 0 || offset == null) return true;
    return offset.abs() <= v;
  }
}
