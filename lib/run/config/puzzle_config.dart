import 'dart:ui';

/// One round's colours (PRD-2 §5.15 table; `PZT` in
/// `design/menu_v2/collect4.js`). Data, so more rounds need no code.
class PuzzleTheme {
  const PuzzleTheme({
    required this.name,
    required this.card,
    required this.body,
    required this.wing,
    required this.beak,
    required this.sparkle,
  });

  final String name;

  /// Card (picture background).
  final Color card;

  /// Bird body.
  final Color body;

  /// Wing + tail; also the piece edge line (§5.15).
  final Color wing;
  final Color beak;
  final Color sparkle;

  Color get edge => wing;
}

/// Puzzle piece + puzzle pill knobs (PRD-2 §3.16, §5.15; mock engine
/// `design/menu_v2/collect4.js`, design `puzzle`).
abstract final class PuzzleConfig {
  static const Color _gold = Color(0xFFFFB529);
  static const Color _white = Color(0xFFFFFFFF);

  /// §5.15 The 8 rounds, played in this order and then looped
  /// (colour = round % 8).
  static const List<PuzzleTheme> themes = [
    PuzzleTheme(
      name: 'Pink',
      card: Color(0xFFFCD9EE),
      body: Color(0xFFEC008C),
      wing: Color(0xFFC2185B),
      beak: _gold,
      sparkle: _gold,
    ),
    PuzzleTheme(
      name: 'Sky',
      card: Color(0xFFD3F5FF),
      body: Color(0xFF0CD9FF),
      wing: Color(0xFF0890AD),
      beak: _gold,
      sparkle: _white,
    ),
    PuzzleTheme(
      name: 'Gold',
      card: Color(0xFFFFF0C7),
      body: Color(0xFFFFB529),
      wing: Color(0xFFD48A00),
      beak: Color(0xFFEC008C),
      sparkle: _white,
    ),
    PuzzleTheme(
      name: 'Ocean',
      card: Color(0xFFDCE6FF),
      body: Color(0xFF0067FF),
      wing: Color(0xFF001D89),
      beak: _gold,
      sparkle: _gold,
    ),
    PuzzleTheme(
      name: 'Cocoa',
      card: Color(0xFFF3E3D3),
      body: Color(0xFF8B5A2B),
      wing: Color(0xFF5A3818),
      beak: _gold,
      sparkle: _gold,
    ),
    PuzzleTheme(
      name: 'Mint',
      card: Color(0xFFD9F7E4),
      body: Color(0xFF21C46B),
      wing: Color(0xFF137A42),
      beak: _gold,
      sparkle: _white,
    ),
    PuzzleTheme(
      name: 'Grape',
      card: Color(0xFFECDFFF),
      body: Color(0xFF8E44FF),
      wing: Color(0xFF5420B0),
      beak: _gold,
      sparkle: _gold,
    ),
    PuzzleTheme(
      name: 'Tangerine',
      card: Color(0xFFFFE4CC),
      body: Color(0xFFFF7A1A),
      wing: Color(0xFFB84A00),
      beak: Color(0xFFFFD54A),
      sparkle: _white,
    ),
  ];

  /// §3.16 The theme of 0-based [round].
  static PuzzleTheme themeFor(int round) =>
      themes[round % themes.length];

  /// §3.16 Pieces per picture (2 × 2).
  static const int pieces = 4;

  // ------------------------------------------------------------- picture
  /// §5.15 Picture 48 × 48 pt, 24 pt cells.
  static const double cell = 24;

  /// §5.15 Tab bulb ≈ 15 % of the edge, 2.3 × deep.
  static const double tabBulb = .15;
  static const double tabDepth = 2.3;

  /// §5.15 White 4 pt outline; 1.1 pt edge line in the wing colour at 45 %.
  static const double outline = 4;
  static const double edgeLine = 1.1;
  static const double edgeAlpha = .45;

  // ------------------------------------------------------------- field
  /// §5.15 Field scale ×2.1 (≈ 50 pt plus the tabs).
  static const double pickupScale = 2.1;

  /// §5.15 Glow: white → gold `#FFD54A` 35 % → clear, r 46 pt; 8 gold rays
  /// (22 %) rotating 0.6 rad/s.
  static const double glowRadius = 46;
  static const double rayOmega = .6;

  /// §5.15 Idle: bob ±4 pt at 0.6 Hz, pulse ±6 % at 1 Hz, rock ±11°
  /// (0.2 rad) at 0.5 Hz.
  static const double bob = 4;
  static const double bobHz = .6;
  static const double pulse = .06;
  static const double pulseHz = 1;
  static const double rock = .2;
  static const double rockHz = .5;

  /// §5.15 A twinkle every 0.22 s on a 36 pt radius (4–8 pt, 0.6 s).
  static const double twinkleEvery = .22;
  static const double twinkleRadius = 36;
  static const double twinkleMin = 4;
  static const double twinkleMax = 8;

  // ------------------------------------------------------------- pill
  /// §5.15 Pill 140 × 64 (`fg` 18 % over bg); board (48 pt) at x −32.
  static const double pillWidth = 140;
  static const double pillHeight = 64;
  static const double panelMix = .18;
  static const double boardX = -32;

  /// §5.15 Missing pieces: `fg` 40 % silhouettes with `fg` 20 % seams
  /// (1.4 pt).
  static const double ghostMix = .40;
  static const double seamMix = .20;
  static const double seam = 1.4;

  /// §5.15 "n/4" Opificio 24 pt at x +34.
  static const double countX = 34;
  static const double countSize = 24;

  /// §5.15 The flight lands 0.14 + 0.62 s after the touch.
  static const double landAt = .14 + .62;

  /// §5.15 Landing punch ×1.38 (0.35 s), ring 6 → 30 pt, 6 sparkles.
  static const double punch = .38;
  static const double punchLength = .35;
  static const double landRingFrom = 6;
  static const double landRingTo = 30;

  /// §5.15 The pill fades out ≈ 2.15 s after the touch; 4.6 s with the
  /// 4th piece.
  static const double fadeAt = 2.15;
  static const double fadeAtComplete = 4.6;

  /// §5.15 4/4 (0.24 s after landing): flash, pieces bounce 0.08 s apart,
  /// board pop ×1.15 + white flash + gold 2.5 pt frame, 22 confetti, gold
  /// ring 20 → 100 pt.
  static const double completeDelay = .24;
  static const double bounceGap = .08;
  static const double boardPop = .15;
  static const double frame = 2.5;
  static const int confetti = 22;
  static const double completeRingFrom = 20;
  static const double completeRingTo = 100;

  /// §5.15 Sticker copy, 0.15 s after the flash, 24 pt under the pill.
  static const String stickerText = 'PICTURE COMPLETE';
  static const double stickerDelay = .15;
  static const double stickerGap = 24;

  /// §5.15 Coin badge 0.55 s after 4/4: centre 62 pt under the pill's
  /// bottom edge, width = text + 50, 34 tall, coin r 11, "+N" plum 24 pt;
  /// pops in 0.3 s; 7 coins arc in; the number counts up from 0.35 s over
  /// 0.8 s, then bumps ×1.2 (0.3 s).
  static const double badgeDelay = .55;
  static const double badgeGap = 62;
  static const double badgeHeight = 34;
  static const double badgePad = 50;
  static const double badgeCoin = 22;
  static const double badgePop = .3;
  static const int badgeCoins = 7;
  static const double countStart = .35;
  static const double countLength = .8;
  static const double bump = .2;
  static const double bumpLength = .3;
}
