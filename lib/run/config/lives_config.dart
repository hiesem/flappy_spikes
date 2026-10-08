import 'dart:ui';

/// Hearts / extra life / shield / saves (PRD-2 §3.3, §3.7, §5.2, §5.5).
/// Values from the approved mocks `screen_hearts_v2.html` (heart pickup 1b)
/// and `screen_shield3.html` (extra-life badge, shield circle, hit).
abstract final class LivesConfig {
  // ------------------------------------------------------------- hearts

  /// §3.3 Hearts needed for one extra life (owner 2026-10-07; was 2).
  static const int heartsPerLife = 3;

  /// §5.2 Heart red `#FF3B5C` (pickup, badge, shards, indicator).
  static const Color heartRed = Color(0xFFFF3B5C);

  /// §5.2 Heart pickup size (pt; the 24-unit heart drawn in a 32 pt box).
  static const double heartPickupSize = 32;

  /// §5.2 Heart pickup white outline (viewBox units of the 24-unit heart;
  /// the mock's `stroke-width 1.8`).
  static const double heartOutline = 1.8;

  /// §5.2 Heart pickup pulse: scale 1.0 ↔ this, one loop per
  /// [heartPulsePeriod] s; no glow.
  static const double heartPulseScale = 1.14;

  /// §5.2 Heart pickup pulse period (s).
  static const double heartPulsePeriod = 1;

  /// §5.7 / §5.5 Where a collected heart flies to: the centre of the HUD
  /// heart indicator (x 14, y 52, 38 × 38 → (33, 71)), top-anchored.
  static const Offset indicatorCentre = Offset(33, 71);

  // ------------------------------------------------- extra-life badge

  /// §5.5 Extra-life badge size (pt).
  static const double badgeSize = 34;

  /// §5.5 Badge centre this far above the bird centre (pt; mock: y − 58 +
  /// 17 → 41, "≈ 40 pt").
  static const double badgeLift = 41;

  /// §5.5 Badge bob amplitude (pt, ±).
  static const double badgeBob = 4;

  /// §5.5 Badge bob angular speed (rad/s; ≈ 0.64 Hz, "≈ 0.6 Hz").
  static const double badgeBobOmega = 4;

  /// §5.5 Badge breathing scale (± fraction) and its angular speed (rad/s).
  static const double badgePulse = .08;

  /// §5.5 Badge breathing angular speed (rad/s).
  static const double badgePulseOmega = 6;

  /// §5.5 Badge / shield circle pop-in time (s, smoothstep).
  static const double popIn = .35;

  /// §5.5 The badge / circle start forming this long after the pickup
  /// touch (the heart first flies to the HUD indicator; mock 1.0 → 1.3 s).
  static const double formDelay = .3;

  // ------------------------------------------------------- shield circle

  /// §5.5 Shield circle outer radius (pt; 84 pt circle → r 38 + stroke).
  static const double shieldRadius = 38;

  /// §5.5 Shield gold ring stroke (pt).
  static const double shieldStroke = 3.5;

  /// §5.5 Shield fill: soft pink at this opacity.
  static const double shieldFillAlpha = .28;

  /// §5.5 Dashed inner ring radius (pt), stroke, dash / gap, opacity.
  static const double shieldInnerRadius = 31;

  /// §5.5 Dashed inner ring stroke (pt).
  static const double shieldInnerStroke = 2.5;

  /// §5.5 Dashed inner ring dash and gap (pt).
  static const List<double> shieldInnerDash = [7, 9];

  /// §5.5 Dashed inner ring opacity.
  static const double shieldInnerAlpha = .8;

  /// §5.5 Dashed inner ring rotation (°/s).
  static const double shieldSpin = 90;

  /// §5.5 Idle pulse (± fraction) and its angular speed (rad/s).
  static const double shieldPulse = .05;

  /// §5.5 Idle pulse angular speed (rad/s).
  static const double shieldPulseOmega = 5;

  /// §5.5 Pop-in overshoot: scale × (1 + this × (1 − born)) while forming.
  static const double shieldOvershoot = .15;

  /// §5.5 Shield pickup icon width (pt; the mock's 38 × 41 icon).
  static const double shieldPickupWidth = 38;

  /// §5.5 Shield pickup vertical wobble (pt, ±) and angular speed (rad/s).
  static const double shieldPickupBob = 3;

  /// §5.5 Shield pickup wobble angular speed (rad/s).
  static const double shieldPickupBobOmega = 6;

  // ---------------------------------------------------------------- hit

  /// §5.5 Hit: white flash disc (80 pt) scale 0.5 → 1.6, opacity 0.8 → 0.
  static const double hitFlashRadius = 40;

  /// §5.5 Hit flash length (s).
  static const double hitFlashLength = .26;

  /// §5.5 Hit: shards (12 triangles for the shield, 12 small hearts for
  /// the extra-life badge).
  static const int shards = 12;

  /// §5.5 Shard size (pt).
  static const double shardSize = 16;

  /// §5.5 Shard travel range (pt) and the extra rise (pt).
  static const double shardDistMin = 60;

  /// §5.5 Shard travel range (pt).
  static const double shardDistMax = 110;

  /// §5.5 Shards drift this much upwards over their life (pt).
  static const double shardRise = 20;

  /// §5.5 Shard life (s).
  static const double shardLife = .62;

  // -------------------------------------------------------------- saved

  /// §5.2 "SAVED!" element banner text (shown in the shared banner band
  /// when a `BannerHost` is mounted).
  static const String savedText = 'SAVED!';

  /// §3.3 / §3.7 Invulnerability after a save (s; Q27: same for both).
  static const double invulnerable = 2;
}
