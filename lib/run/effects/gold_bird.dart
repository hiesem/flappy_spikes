import 'dart:ui';

import '../../skins/art/bird_art.dart';

/// Master #5 colours — the gold bird of streak tier 2+ (PRD §3.0.9 #5,
/// §5.3 / §5.4): body `#FFB529`, tail + wing `#E08A00`, beak `#FFB529` (it
/// merges with the body), eye white. Drawn by `LookPainter.paint(gold: true)`
/// / `LookComponent.goldTier`.
///
/// On the classic bird the look is recoloured with [classic]; every other
/// bird skin keeps its art and gets a gold glow outline instead (ARCH §3
/// "Skin interplay").
abstract final class GoldBird {
  static const Color body = Color(0xFFFFB529);
  static const Color shade = Color(0xFFE08A00);
  static const Color beak = Color(0xFFFFB529);

  /// Glow outline colour on non-classic skins.
  static const Color glow = Color(0xFFFFB529);

  /// Blur sigma of the glow outline (art units).
  static const double glowSigma = 2.2;

  /// The bird skin that is recoloured (all others get the glow outline).
  static const String classicId = 'classic';

  /// The classic bird in gold.
  static final BirdSpec classic = BirdSpec(
    classicId,
    'sq',
    c: body,
    d: shade,
    bk: beak,
  );
}
