import 'dart:ui';

import 'hud_config.dart';
import 'tuning_values.dart';

/// Piggy Bank (PRD-2 §3.28, §5.27; `design/menu_v2/lab2_collect.js`
/// `IDEAS.piggy` / `piggy2` + `lab3_collect.js` `IDEAS.piggy3`). The spawn
/// rules (gap 12, weight 10, ≥ 30 gaps apart, 4 coins / gap, 4 follow gaps)
/// live in `DirectorTables.prd2` / `RunConfig`; this file holds the art,
/// HUD and sound numbers. Every member's doc starts with its PRD section.
abstract final class PiggyConfig {
  // --- §3.28 the bank -------------------------------------------------------

  /// §3.28 Exactly 20 coins appear. PRD-2.3 §14.2: every 2 caught pay 1
  /// (rounded down; max 10), was ×2 of what you caught.
  static const int total = 20;

  /// §3.28 One coin field is placed in the piggy's own gap (2.0.0 G6: the
  /// director's follow-gaps carry the other 16).
  static const int ownGapCoins = 4;

  /// §3.28 The own-gap field runs from 20 pt after the piggy to 40 pt before
  /// the next hoop (mock `coinGap(it.x + 20, nh.x - 40)`).
  static const double ownGapStart = 20;
  static const double ownGapEnd = 40;

  /// §3.28 Fallback span when no hoop is ahead: 115 pt of flat field.
  static const double ownGapFallback = 115;

  /// §3.28 Coins follow the line with a 18 pt upward bulge (mock `-sin(u·π)·18`).
  static const double coinBulge = 18;

  /// §5.27 Coins spin at 4 rad/s (mock `coin(..., cos(t·4 + x·.05))`).
  static const double coinSpinRate = 4;
  static const double coinSpinPhase = .05;

  /// PRD-2.3 §14.2 The smash pays 1 coin for every this many caught,
  /// rounded down (`coin_piggy_per`, 2: 20 caught = 10; was ×2 of caught).
  static int get coinsPer => TuningValues.current.i('coin_piggy_per');

  /// PRD-2.3 §14.2 The smash pay-out for [caught] coins caught.
  static int payoutFor(int caught) {
    final per = coinsPer;
    return per <= 0 ? 0 : caught ~/ per;
  }

  // --- §5.27 the pig (mock `pig()`, ~32 pt as a pickup) ---------------------

  /// §5.27 The pickup / HUD unit is the pig art drawn at this scale.
  static const double pickupScale = 1.25;
  static const double hudScale = 1.4;

  /// §5.27 Flat pink `#FF8AC4` body ellipse (rx 13, ry 10); snout
  /// `#FF6FB0`; legs `#E05A99`; nostril `#B0306E`; eye `#3E1028`.
  static const Color body = Color(0xFFFF8AC4);
  static const Color snout = Color(0xFFFF6FB0);
  static const Color legs = Color(0xFFE05A99);
  static const Color nostril = Color(0xFFB0306E);
  static const Color eye = Color(0xFF3E1028);
  static const double bodyRx = 13;
  static const double bodyRy = 10;

  /// §5.27 The pickup bobs ±3 pt at 3 rad/s; halo r 26 `rgba(255,138,196,·)`
  /// at α 0.5.
  static const double bobAmp = 3;
  static const double bobOmega = 3;
  static const Color haloColor = Color(0xFFFF8AC4);
  static const double haloR = 26;

  /// PRD-2.3 §17.2 visual reach of the Piggy Bank: its halo r 26.
  static const double visualReach = haloR;
  static const double haloAlpha = .5;

  // --- §5.27 the coins ------------------------------------------------------

  /// §5.27 Coins are our coin icon; caught coins fly into the HUD piggy
  /// (mock `parts.push({kind:'coin', tx:46, ty:216, m:.35, s:6})`).
  /// PRD-2.2 §26: 16 pt (was 8; mock `screen_piggy_coins2x.html` phone B).
  static const double coinSize = 16;
  static const double fetchSeconds = .35;

  /// PRD-2.2 §26 The caught coin leaves at [coinSize] and shrinks by this
  /// fraction over the flight into the HUD piggy (mock `COIN_PT·(1 − .6u)`).
  static const double fetchShrink = .6;

  /// §3.28 "PIGGY BANK" banner and its one-line explanation.
  static const String bannerText = 'PIGGY BANK';
  /// PRD-2.3 §14.2 (call) the texts say the new rate (was "… for the full
  /// ×2" / "pays ×2").
  static String get bannerSub =>
      '20 coins appear · every $coinsPer caught pay 1';

  /// §3.28 The pay-out banner: title "+N", subtitle "n / 20 coins · 2 per
  /// coin".
  static String get payoutSub => ' / 20 coins · $coinsPer per coin';

  /// §5.27 The smash burst: 22 pink / gold / white pieces at 200 pt/s.
  static const List<Color> smashColors = [
    Color(0xFFFF8AC4),
    Color(0xFFFFB529),
    Color(0xFFFFFFFF),
  ];

  // --- §5.27 the HUD (under the score, left) --------------------------------

  static const double hudPigX = 46;
  static const double hudPigY = 216 - HudConfig.collectLift;

  /// §5.27 "n / 20" in `#E05A99` 16 pt at (68, 209).
  static const Color hudText = Color(0xFFE05A99);
  static const double hudTextX = 68;
  static const double hudTextY = 209 - HudConfig.collectLift;
  static const double hudTextSize = 16;

  /// §5.27 A 90 pt bar at (68, 220), h 8, r 4: caught `#FF6FB0`, missed grey
  /// `rgba(158,158,158,.8)`, track `rgba(130,130,130,.25)`.
  static const double hudBarX = 68;
  static const double hudBarY = 220 - HudConfig.collectLift;
  static const double hudBarW = 90;
  static const double hudBarH = 8;
  static const double hudBarRadius = 4;
  static const Color hudBarTrack = Color(0x40828282);
  static const Color hudBarCaught = Color(0xFFFF6FB0);
  static const Color hudBarMissed = Color(0xCC9E9E9E);

  /// §5.27 "n missed" 11 pt `#9E9E9E` at (68, 236).
  static const Color hudMissed = Color(0xFF9E9E9E);
  static const double hudMissedY = 236 - HudConfig.collectLift;
  static const double hudMissedSize = 11;

  // --- §5.27 the smash ------------------------------------------------------

  /// §5.27 Pay-out burst at the HUD piggy (46,216): 22 pieces, pink / gold /
  /// white, 200 pt/s, with a 4 pt camera shake ([RunShake.piggySmash]).
  static const int smashPieces = 22;
  static const double smashSpeed = 200;

  /// §5.27 The pay-out banner is gold `#FFB529`; the PIGGY BANK banner pink
  /// `#FF6FB0`.
  static const Color bannerColor = Color(0xFFFF6FB0);
  static const Color payoutColor = Color(0xFFFFB529);
}
