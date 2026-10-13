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

  /// PRD-2.3 §17.2 visual reach of the FEVER ring beyond [beamLength]
  /// (decor scale 1): the streaks start 6 pt in front of the ring and are
  /// up to 20 pt long. The reach (`FeverRingPainter.visualReach`) is
  /// `(beamLength + beamReachExtra) · decorScale`, at least the halo.
  static const double beamReachExtra = 26;

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
  // PRD-2.2 §21 (supersedes PRD-2 §3.19 Q51): the one fire master, lit by a
  // perfect streak of ×3 or by FEVER; approved mock
  // `design/menu_v2/screen_fire_choice2.html`, right phone.

  /// PRD-2.2 §21.1 The perfect streak that sets the bird on fire.
  static const int fireStreak = 3;

  /// PRD-2.2 §21.1 Size levels: streak ×3–×4 → level 1, ×5–×6 → 2, ×7+ → 3.
  static const List<int> fireLevelStreaks = [3, 5, 7];

  /// PRD-2.2 §21.1 Flames per second per level (1, 2, 3).
  static const List<double> fireRates = [55, 95, 150];

  /// PRD-2.2 §21.1 Flame size factor per level (70 %, 85 %, 100 %).
  static const List<double> fireScales = [.7, .85, 1];

  /// PRD-2.2 §21.1 Teardrop size at 100 % (pt): 9 … 16 (≈ 6–11 at 70 %).
  static const double fireSizeMin = 9;

  /// PRD-2.2 §21.1 Largest teardrop at 100 % (pt).
  static const double fireSizeMax = 16;

  /// PRD-2.2 §21.1 Master teardrop width per pt of flame size: the mock's
  /// drop of size s is ≈ 0.5 s wide and 1.2 s tall; the master teardrop
  /// (w wide, ≈ 1.6 w tall) covers the same area at w ≈ 0.6 s.
  static const double fireDropWidth = .6;

  /// PRD-2.2 §21.1 Flame life (s): 0.3 … 0.55, × (0.8 + 0.2 × size factor)
  /// as in the mock.
  static const double fireLifeMin = .3;

  /// PRD-2.2 §21.1 Longest flame life at 100 % (s).
  static const double fireLifeMax = .55;

  /// PRD-2.2 §21.1 Flame velocity (pt/s): vx −130 … −60, vy −80 … −20.
  static const double fireVxMin = -130, fireVxMax = -60;

  /// PRD-2.2 §21.1 Vertical flame velocity range (pt/s).
  static const double fireVyMin = -80, fireVyMax = -20;

  /// PRD-2.2 §21.1 The bottom edge gives half the lift.
  static const double fireBottomLift = .5;

  /// PRD-2.2 §21.1 Share of flames from the back edge (40 %) and the top
  /// edge (35 %); the rest (25 %) rises from the bottom edge (mock).
  static const double fireBackShare = .4, fireTopShare = .35;

  /// PRD-2.2 §21.1 Back edge: x = bird − 22 + (−2 … 4), y = ± 14 (pt).
  static const double fireBackX = -22, fireBackSpread = 14;

  /// PRD-2.2 §21.1 Top / bottom edges: y = ∓ 15 pt, x = bird − 20 … + 16
  /// (top) / + 10 (bottom).
  static const double fireEdgeY = 15;

  /// PRD-2.2 §21.1 Flame colours over the life (classic orange fire, used
  /// with every non-flame trail): white → #FFF3B0 → #FF9100 → #D50000.
  static const List<Color> firePalette = [
    Color(0xFFFFFFFF),
    Color(0xFFFFF3B0),
    Color(0xFFFF9100),
    Color(0xFFD50000),
  ];

  /// PRD-2.2 §21.1 Warm halo behind the bird per level: radius (pt).
  static const List<double> fireHaloRadii = [34, 42, 52];

  /// PRD-2.2 §21.1 Halo opacity per level.
  static const List<double> fireHaloAlphas = [.22, .30, .38];

  /// PRD-2.2 §21.1 The halo's solid core radius (pt) and its centre offset
  /// from the bird (−4, −2), as in the mock.
  static const double fireHaloCore = 6;

  /// PRD-2.2 §21.1 Halo centre x offset (pt).
  static const double fireHaloDx = -4;

  /// PRD-2.2 §21.1 Halo centre y offset (pt).
  static const double fireHaloDy = -2;

  /// §5.18 Fire out: grey smoke puffs.
  static const int smokePuffs = 16;

  /// §5.18 Smoke colour.
  static const Color smoke = Color(0x80787878);

  /// PRD-2.2 §21.1 The quiet crackle loop (`fever_loop`) while the bird
  /// burns outside FEVER (≈ 25 %).
  static const double crackleVolume = .25;

  /// §5.18 / PRD-2.2 §21.1 The same loop at today's FEVER volume while
  /// FEVER runs.
  static const double loopVolume = .35;

  /// PRD-2.2 §21.1 Volume ramp between the two (s).
  static const double loopRamp = .3;

  /// PRD-2.2 §21.1 Volume updates per second during the ramp (no per-frame
  /// platform traffic, §33).
  static const double loopRampSteps = 20;

  /// PRD-2.2 §21.1 FEVER shows the fire at least at the ×5 size.
  static const int feverSizeStreak = 5;

  /// §5.18 / PRD-2.2 §21.1 The fire draws behind the bird (never over the
  /// body) and over the trail (mock order trail → halo → flames → bird).
  static const int firePriority = RunLayer.bird - 1;

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
