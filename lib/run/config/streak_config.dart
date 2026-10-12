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

/// PRD-2.2 §11 The perfect zone: a pass is perfect only when no rim was
/// touched **and** the bird's centre crosses the plane within ±[halfWidth]
/// of the passed ring's centre (measured in the ring's own moving frame,
/// `PlaneEvent.offset` / `Hoop.passOffset`). Ride rings stay always perfect.
abstract final class PerfectConfig {
  /// PRD-2.2 §11.1 Zone half-width = [zoneFactor] × the ring's opening …
  static const double zoneFactor = 0.2;

  /// PRD-2.2 §11.1 … capped at this many pt (Big Hoops and saw openings
  /// make passing easier, not perfects).
  static const double zoneMax = 24;

  /// PRD-2.2 §11.1 The zone half-width (pt) for a ring of [opening] pt:
  /// ±23.6 at 118, ±18.4 at 92, ±24 from 120 up.
  static double halfWidth(double opening) {
    final w = zoneFactor * opening;
    return w < zoneMax ? w : zoneMax;
  }

  /// PRD-2.2 §11.1 Whether a crossing [offset] pt from the ring centre is
  /// inside the zone of a ring of [opening] pt (the edge counts as inside).
  static bool inZone(double offset, double opening) =>
      offset.abs() <= halfWidth(opening) + 1e-9;
}
