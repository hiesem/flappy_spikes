import 'dart:ui';

import '../../game/sound.dart';
import '../run_layers.dart';

/// Perfect-pass streak, ring tier reactions and the graze notice (PRD-2
/// §3.4, §3.5, §3.19 FEVER hook, §5.3, §5.4). The look of every effect is a
/// §3.0.9 master (`PartsConfig`); these are the streak's own rules. Every
/// member's doc starts with its PRD section (ARCH §4).
abstract final class StreakConfig {
  /// §3.4 The streak tiers are capped here (IMMORTAL ×10); further perfect
  /// passes keep the top tier.
  static const int tierCap = 10;

  /// §3.4 / §5.3 Tiers above this reuse its effects (tier 3+ look).
  static const int topEffectTier = 3;

  /// §3.5 / §5.3 The bird turns gold from this tier.
  static const int goldBirdTier = 2;

  /// §3.5 / §5.3 The bird leaves its trail from this tier.
  static const int trailTier = 3;

  /// §3.19 A perfect FEVER pass sets the streak to max(this, streak + 1).
  static const int feverMinStreak = 5;

  /// §3.4 Tier sounds: streak 1, 2 and 3+ (index = min(streak, 3) − 1).
  static const List<Sfx> tierSounds = [Sfx.perfect1, Sfx.perfect2, Sfx.perfect3];

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
  /// z 9 under the bird's 10).
  static const int trailPriority = RunLayer.bird - 1;

  /// §3.0.9 #7 / §5.4 The banner band: over every run effect, under the
  /// HUD pills (19 / 21).
  static const int bannerPriority = 18;

  /// §5.3 The graze notice: same band as the banners.
  static const int grazePriority = 18;

  /// §5.3 Graze notice colour fallback (the stage foreground is used).
  static const Color grazeFallback = Color(0xFF828282);
}
