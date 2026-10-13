import 'dart:ui';

import 'hud_config.dart';
import 'tuning_values.dart';

/// Firefly Jar (PRD-2 §3.29, §5.28; `design/menu_v2/lab2_collect.js`
/// `IDEAS.flies` / `flies2` + `lab3_collect.js` `IDEAS.flies3`). The spawn
/// rules (gap 15, weight 10, ≥ 30 gaps apart, 7 fireflies / gap) live in
/// `DirectorTables.prd2` / `RunConfig`; this file holds the art, HUD and
/// sound numbers. Every member's doc starts with its PRD section.
abstract final class JarConfig {
  // --- §3.29 the jar --------------------------------------------------------

  /// §3.29 20 fireflies fill the jar; 3 escapes break it.
  static const int total = 20;
  static const int maxEscapes = 3;

  /// §3.29 JAR FULL pays coins. PRD-2.3 §14.2: +8 (`coin_jar`; was +25).
  static int get reward => TuningValues.current.i('coin_jar');

  // --- §5.28 the animated jar pickup ---------------------------------------

  /// §5.28 The jar bobs ±5 pt at 2.6 rad/s and sways ±0.12 rad at 2 rad/s.
  static const double bobAmp = 5;
  static const double bobOmega = 2.6;
  static const double swayAmp = .12;
  static const double swayOmega = 2;

  /// §5.28 Ten soft light rays turn at 0.6 rad/s; length 36 + 8 sin(3t + i).
  static const int rays = 10;
  static const double rayOmega = .6;
  static const double rayLength = 36;
  static const double rayPulse = 8;
  static const double rayPulseOmega = 3;
  static const double raySpread = .1;
  static const Color rayColor = Color(0xFFC8F03C);
  static const Color rayColorEnd = Color(0xFFE6FF78);

  /// §5.28 The halo pulses r 34 + 6·pul (pul = 0.5 + 0.5 sin 4t), α 0.45 +
  /// 0.3·pul; the glass fill fades 0.25 → 0.35 with the pulse.
  static const Color haloColor = Color(0xFFD6FF50);
  static const double haloR = 34;
  static const double haloPulse = 6;
  static const double haloPulseOmega = 4;
  static const double haloAlpha = .45;
  static const double haloAlphaPulse = .3;

  /// §5.28 The jar graphic at 1.05× as a pickup.
  static const double pickupScale = 1.05;

  /// §5.28 Four fireflies blink and drift up inside the glass.
  static const int innerFlies = 4;

  /// §5.28 Inside-firefly blink / drift (mock `sin(1.7t + 1.9k)` × 6,
  /// `6 − ((t·.35 + k·.27) % 1)·22`, blink `sin(9t + 2k)`).
  static const double innerSway = 6;
  static const double innerSwayOmega = 1.7;
  static const double innerSwayPhase = 1.9;
  static const double innerRiseRate = .35;
  static const double innerRiseStep = .27;
  static const double innerRiseSpan = 22;
  static const double innerRiseTop = 6;
  static const double innerBlinkOmega = 9;
  static const double innerBlinkPhase = 2;
  static const double innerHaloR = 6;
  static const Color innerDot = Color(0xFFFDFFD0);
  static const double innerDotR = 1.4;

  /// §5.28 Tiny sparks float off the jar (mock `Math.random() < dtR·10`).
  static const double sparkRate = 10;
  static const double sparkSpread = 30;
  static const double sparkSizeMin = 1.6;
  static const double sparkSizeMax = 3;
  static const double sparkLife = .9;

  /// §5.28 "FIREFLY JAR", "JAR FULL!" and "JAR BROKE" banners.
  static const String bannerText = 'FIREFLY JAR';
  static const String bannerSub = 'catch 20 · let 3 escape and it breaks';
  static const String fullText = 'JAR FULL!';
  static String get fullSub => '20 fireflies · +$reward coins';
  static const String brokeText = 'JAR BROKE';
  static const String brokeSub = '3 fireflies got away';

  /// §5.28 The full burst: 20 lime / white dots at 180 pt/s; the fly-away
  /// glow drifts up-right (mock vx 40–100, vy −120…−200).
  static const int fullPieces = 20;
  static const double fullSpeed = 180;
  static const List<Color> fullColors = [
    Color(0xFFE6FF6B),
    Color(0xFFFFFFFF),
  ];
  static const double awayVxMin = 40;
  static const double awayVxMax = 100;
  static const double awayVyMin = 120;
  static const double awayVyMax = 200;
  static const double awaySize = 3;
  static const Color awayColor = Color(0xFFD6FF50);

  // --- §5.28 the glass jar (mock `jarIcon`) ---------------------------------

  /// §5.28 Pale blue glass `rgba(200,240,255,.45)`, grey outline
  /// `rgba(120,140,150,.95)` 2 pt, brown lid `#8D6E3F`, lime glow fill.
  static const Color glass = Color(0x73C8F0FF);
  static const Color glassStroke = Color(0xF2788C96);
  static const double glassStrokeWidth = 2;
  static const Color lid = Color(0xFF8D6E3F);
  static const Color glow = Color(0x99D6FF50);

  /// §5.28 The glass body: x ±12, top −14, bottom 17, rounded corners 4.
  static const double glassHalfW = 12;
  static const double glassTop = -14;
  static const double glassBottom = 17;
  static const double glassCorner = 4;
  static const double lidW = 28;
  static const double lidH = 6;
  static const double lidY = -20;

  // --- §5.28 fireflies ------------------------------------------------------

  /// §5.28 2.6 pt `#F4FF9A` dots with a pulsing lime halo r 14 (α 0.7·bl,
  /// bl = 0.55 + 0.45 sin(7t + 3·ph)), a small dark body above.
  static const Color dot = Color(0xFFF4FF9A);
  static const double dotR = 2.6;
  static const Color flyHalo = Color(0xFFD6FF50);
  static const double flyHaloR = 14;
  static const double flyHaloAlpha = .7;
  static const double flyBlinkOmega = 7;
  static const Color flyBody = Color(0x9950503C);

  /// §5.28 The weave around the swarm centre (mock `flies.itemStep`):
  /// t = 1.3·p.t + ph; x = cx + cos t·24 + sin(1.7t)·8; y = cy + sin(1.2t)·22.
  static const double weaveRate = 1.3;
  static const double weaveAx = 24;
  static const double weaveBx = 8;
  static const double weaveBk = 1.7;
  static const double weaveAy = 22;
  static const double weaveKy = 1.2;

  /// §3.29 / Q68 Catch radius 16 pt.
  static const double catchRadius = 16;

  /// §3.29 PRD §3.0.3 "swarms weave ±45 pt around the line": the mock's
  /// exact offsets (±32 × ±22 from [weaveAx] / [weaveBx] / [weaveAy]) stay
  /// inside that band.
  static const double weaveBand = 45;

  // --- §5.28 the HUD (under the score, left) --------------------------------

  /// §5.28 Jar at (46,218,·95); "n / 20" `#7CB518` 14 pt at (66,210); three ✕
  /// at (72 + 16i, 228), red `#FF3B5C` per escape, else grey.
  static const double hudJarX = 46;
  static const double hudJarY = 218 - HudConfig.collectLift;
  static const double hudJarScale = .95;
  static const Color hudText = Color(0xFF7CB518);
  static const double hudTextX = 66;
  static const double hudTextY = 210 - HudConfig.collectLift;
  static const double hudTextSize = 14;
  static const double markX = 72;
  static const double markY = 228 - HudConfig.collectLift;
  static const double markStep = 16;
  static const double markSize = 4;
  static const double markWidth = 2.4;
  static const Color markRed = Color(0xFFFF3B5C);
  static const Color markGrey = Color(0x80828282);

  // --- §5.28 colours --------------------------------------------------------

  /// §5.28 FIREFLY JAR and JAR FULL! banners are lime `#7CB518`; JAR BROKE is
  /// grey `#9E9E9E`; the full burst is `#E6FF6B` / white.
  static const Color bannerColor = Color(0xFF7CB518);
  static const Color brokeGrey = Color(0xFF9E9E9E);
  static const Color burstLime = Color(0xFFE6FF6B);
}
