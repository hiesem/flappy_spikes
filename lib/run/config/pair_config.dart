import 'dart:ui';

import '../../game/sound.dart';
import '../director/plans.dart' show PairReward;

/// One reward's colours, tag word and pick word (§5.20 table).
class PairRewardStyle {
  const PairRewardStyle({
    required this.main,
    required this.dark,
    required this.light,
    required this.tag,
    required this.word,
    required this.sound,
  });
  final Color main, dark, light;

  /// The gift tag's word.
  final String tag;

  /// The word that pops up next to the bird.
  final String word;
  final Sfx sound;
}

/// Pairs of two powerup rings, design "Gift Box" (PRD-2 §3.21, §5.20; mock
/// `screen_ring_pairs_giftbox.html`, builder `build68.py` → `build66_themes
/// .js`). The pair offset (230 × viewHeight / 711) and the HUD bottom live
/// in `RunConfig` (the director places the pair); the reward weights in
/// `DirectorTables.prd2`. Every member's doc starts with its PRD section.
abstract final class PairConfig {
  /// §3.21 +10 COINS gift.
  static const int coins = 10;

  /// §3.21 +5 SCORE gift (five points flagged `gift`, ARCH §6.1).
  static const int score = 5;

  /// §3.21 FEVER gift: the streak is set to at least this (×5).
  static const int feverStreak = 5;

  /// §3.21 / §5.20 The skipped ring, box and tag shrink to 60 % and fade
  /// out over 0.45 s.
  static const double skipFade = .45, skipScale = .6;

  /// §5.20 Ring stroke (pt) and the white inner line on the front half.
  static const double ringStroke = 7, innerLine = 1.6;

  /// §5.20 Gift box half size before the ×1.45 scale (mock `s = 15`;
  /// ≈ 44 pt box).
  static const double boxHalf = 15, boxScale = 1.45;

  /// §5.20 Box bob (pt) and tilt (rad ≈ ±5°).
  static const double boxBob = 3, boxTilt = .08;

  /// §5.20 The tag hangs ≈ 30 pt out from the top of the top ring / the
  /// bottom of the bottom ring, tilted −3° and swaying ±3°.
  static const double tagOut = 30, tagTilt = -.06, tagSway = .06;

  /// §5.20 Tag text size (Opificio) and outline (pt).
  static const double tagFont = 14, tagOutline = 2;

  /// §5.20 Pick: confetti squares and strips.
  static const int confetti = 22;

  /// §5.20 Pick: the reward word (Opificio 24–30 pt) floats up for this
  /// long (s).
  static const double wordLife = 1.4;

  /// §5.20 / §5.4 The reward word moves below the bird when it would sit in
  /// the streak banner band (y 190 ± its height) of the same pass (pt).
  static const double bannerBandTop = 170, bannerBandBottom = 262;

  /// §5.20 Grey puff of the skipped ring.
  static const Color puff = Color(0x73A0A0A0);

  /// §5.20 Reward colours, icons' words and sounds.
  static PairRewardStyle style(PairReward r) => switch (r) {
    PairReward.shield => const PairRewardStyle(
      main: Color(0xFF2F80FF),
      dark: Color(0xFF1646A8),
      light: Color(0xFFA9D0FF),
      tag: 'SHIELD',
      word: 'SHIELD!',
      sound: Sfx.pairShield,
    ),
    PairReward.comet => const PairRewardStyle(
      main: Color(0xFFFF7A1A),
      dark: Color(0xFFB84A00),
      light: Color(0xFFFFD0A8),
      tag: 'COMET',
      word: 'COMET!',
      sound: Sfx.pairComet,
    ),
    PairReward.coins => const PairRewardStyle(
      main: Color(0xFFFFB529),
      dark: Color(0xFFB87F00),
      light: Color(0xFFFFE6A8),
      tag: '+10 COINS',
      word: '+10 COINS',
      sound: Sfx.pairCoins,
    ),
    PairReward.score => const PairRewardStyle(
      main: Color(0xFF8E5CFF),
      dark: Color(0xFF4B2BB8),
      light: Color(0xFFD7C6FF),
      tag: '+5 SCORE',
      word: '+5 SCORE',
      sound: Sfx.pairScore,
    ),
    PairReward.fever => const PairRewardStyle(
      main: Color(0xFFFF3B3B),
      dark: Color(0xFFA50E14),
      light: Color(0xFFFFC2C2),
      tag: 'FEVER',
      word: 'FEVER!',
      sound: Sfx.pairFever,
    ),
  };
}
