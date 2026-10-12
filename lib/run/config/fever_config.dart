import 'dart:ui';

import '../run_layers.dart';
import 'parts_config.dart';

/// FEVER — the glowing ring "Gate Nova" and the bird on fire (PRD-2 §3.19,
/// §5.18; mock `screen_fever_gatenova_A.html`, preset `full` of
/// `build63_themes.js`). Every member's doc starts with its PRD section.
abstract final class FeverConfig {
  // ------------------------------------------------------------ the ring
  /// §5.18 Rim front colour (red).
  static const Color rimFront = Color(0xFFE8141C);

  /// §5.18 Rim back colour.
  static const Color rimBack = Color(0xFFA50E14);

  /// §5.18 Dark-red outline under the rim.
  static const Color outline = Color(0xFF5E000A);

  /// §5.18 Rim stroke (pt).
  static const double rimWidth = 10;

  /// §5.18 Outline stroke (pt) = rim + 4.
  static const double outlineWidth = 14;

  /// §5.18 Orange glow colour and blur (pt) of the outline.
  static const Color glowColor = Color(0xFFFF6D00);

  /// §5.18 Orange glow blur (pt).
  static const double glowBlur = 16;

  /// §5.18 Boiling plasma: beads riding the rim (whole ring).
  static const int beads = 30;

  /// §5.18 Bead radius base (pt): r = base × (0.55 … 1.15) ≈ 2.5–5.3 pt.
  static const double beadRadius = 4.6;

  /// §5.18 Beads are re-rolled this many times per second.
  static const double beadRerollPerSecond = 12;

  /// §5.18 Bead colours (cycled).
  static const List<Color> beadColors = [
    Color(0xFFFFF3B0),
    Color(0xFFFFD54A),
    Color(0xFFFF9100),
    Color(0xFFFFFFFF),
  ];

  /// §5.18 Inner gold ring colour.
  static const Color innerRing = Color(0xFFFFE57F);

  /// §5.18 Inner gold ring stroke (pt).
  static const double innerWidth = 2.4;

  /// §5.18 Inner ring glow blur range (pt): 6 + 12 × pulse (0.2 … 1).
  static const double innerGlowMin = 6;

  /// §5.18 Inner ring glow pulse amplitude (pt).
  static const double innerGlowPulse = 12;

  /// §5.18 Plasma loops (prominences) on the rim.
  static const int loops = 3;

  /// §5.18 Loop cycle speed (cycles/s; ≈ 3 s per loop).
  static const double loopSpeed = .35;

  /// §5.18 Loop rise (pt) over the 10 pt base: up to ≈ 54 pt off the rim.
  static const double loopHeight = 44;

  /// §5.18 Loop stroke (pt).
  static const double loopWidth = 6;

  /// §5.18 Loop colour (orange) and core (pale).
  static const Color loopColor = Color(0xFFFF6E00);

  /// §5.18 Loop core colour.
  static const Color loopCore = Color(0xFFFFF0B4);

  /// §5.18 Light beam length toward the bird (pt).
  static const double beamLength = 125;

  /// §5.18 Beam spread past the ring top / bottom at its far end (pt).
  static const double beamSpread = 14;

  /// §5.18 Beam opacity at the ring.
  static const double beamAlpha = .6;

  /// §5.18 White light streaks drifting through the beam.
  static const int beamStreaks = 8;

  /// PRD-2.2 §25 The halo, beam, loops, sparkles and embers were designed
  /// at the full-size opening 118 pt; every decoration size / offset is
  /// multiplied by `ry / ryDesign` (`FeverRingPainter.decorScaleFor`). The
  /// rim, outline, beads and inner gold ring are not scaled.
  static const double decorDesignOpening = 118;

  /// PRD-2.2 §25 The half height the decorations were designed at
  /// (`RingPainter.ryFor(118)` = 118 / 2 + 7).
  static const double ryDesign = decorDesignOpening / 2 + PartsConfig.rimRadius;

  /// §5.18 Warm halo radius beyond the ring half height (pt).
  static const double haloExtra = 44;

  /// §5.18 Halo opacity.
  static const double haloAlpha = .32;

  /// §5.18 Ambient sparkles per second drifting out along the beam.
  static const double sparksPerSecond = 12;

  /// §5.18 Embers per second flying off the rim.
  static const double embersPerSecond = 12;

  // ----------------------------------------------------- the pass effect
  /// §5.18 Pass: light rings (gold, white, orange) 0.09 s apart.
  static const List<Color> passRingColors = [
    Color(0xFFFFE57F),
    Color(0xFFFFFFFF),
    Color(0xFFFF9100),
  ];

  /// §5.18 Delay between the pass rings (s).
  static const double passRingGap = .09;

  /// §5.18 Pass ring life (s).
  static const double passRingLife = .7;

  /// §5.18 Pass ring growth (pt added to both radii over its life).
  static const double passRingGrow = 160;

  /// §5.18 Plasma flames bursting from the rim on the pass.
  static const int passBurst = 26;

  /// §5.18 Burst speed (pt/s, × 0.6 … 1.3).
  static const double passBurstSpeed = 240;

  /// §5.18 Warm screen flash start opacity factor (decays 3 /s ≈ 0.3 s).
  static const double passFlash = .6;

  /// §5.18 Screen flash decay (1/s).
  static const double passFlashDecay = 3;

  /// §5.18 Screen flash colour (alpha = flash × 0.55).
  static const Color flashColor = Color(0xFFFFFADC);

  /// §5.18 Small shake (pt) on the pass.
  static const double passShake = 6;

  /// §5.18 Ring flare (beam / halo) decay (1/s).
  static const double flareDecay = 2;

  // ------------------------------------------------------- bird on fire
  /// §5.18 Flame particles per second.
  static const double fireRate = 115;

  /// §5.18 Flame teardrop size (pt): 10 … 18.
  static const double fireSize = 10;

  /// §5.18 Flame life (s): 0.35 … 0.65.
  static const double fireLifeMin = .35;

  /// §5.18 Flame life range (s).
  static const double fireLifeRange = .3;

  /// §5.18 Flame colours over the life: white → #FFF3B0 → #FF9100 → #D50000.
  static const List<Color> firePalette = [
    Color(0xFFFFFFFF),
    Color(0xFFFFF3B0),
    Color(0xFFFF9100),
    Color(0xFFD50000),
  ];

  /// §5.18 Warm halo around the burning bird (radius pt, opacity).
  static const double fireHalo = 44;

  /// §5.18 Fire halo opacity.
  static const double fireHaloAlpha = .45;

  /// §5.18 Fire out: grey smoke puffs.
  static const int smokePuffs = 16;

  /// §5.18 Smoke colour.
  static const Color smoke = Color(0x80787878);

  /// §5.18 Burning crackle loop volume.
  static const double loopVolume = .35;

  /// §5.18 Fire particles draw behind the bird (gold bird and trail stay
  /// visible).
  static const int firePriority = RunLayer.bird - 2;

  // ------------------------------------------------------- FEVER! banner
  /// §5.18 FEVER! text.
  static const String bannerText = 'FEVER!';

  /// §5.18 Banner font size (pt).
  static const double bannerFontSize = 44;

  /// §5.18 Banner gradient (top → middle → bottom).
  static const List<Color> bannerGradient = [
    Color(0xFFFFF59D),
    Color(0xFFFF9800),
    Color(0xFFE64A19),
  ];

  /// §5.18 Banner outline (plum) and width (pt).
  static const Color bannerOutline = Color(0xFF7A0044);

  /// §5.18 Banner outline width (pt).
  static const double bannerOutlineWidth = 7;

  /// §5.18 Banner time on screen (s).
  static const double bannerDuration = 1.6;

  /// §5.18 Banner centre y (pt): above the tier banner band (top 190).
  static const double bannerCentreY = 160;

  /// §5.18 Banner tilt (rad) and jitter amplitude (rad, 30 rad/s).
  static const double bannerTilt = -.06;

  /// §5.18 Banner jitter amplitude (rad).
  static const double bannerJitter = .02;
}
