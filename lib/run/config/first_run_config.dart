import 'dart:ui';

/// PRD-2.3 §10.3 / §10.3b the first-run instructions and the tap reminder
/// (approved design D: `design/onboarding_v23/first_run_src.html`). Every
/// position is at the 568 pt design height; vertical positions are offsets
/// from the playfield's middle (`mid`) or from the spike strips, so they hold
/// on taller screens. Timings and fades live in `Config` (§10 region).
abstract final class FirstRunConfig {
  // --- veil (§10.3) ----------------------------------------------------------
  /// §10.3 the score circle is dimmed by this veil …
  static const Color veilColor = Color(0xFFF1F1F1);

  /// §10.3 … at 72 % (× the fade).
  static const double veilAlpha = .72;

  // --- AVOID THE SPIKES bands (§10.3) ----------------------------------------
  /// §10.3 the band text.
  static const String warningText = 'AVOID THE SPIKES';

  /// §10.3 the band colour.
  static const Color warningColor = Color(0xFFE8141C);

  /// §10.3 white Opificio 22 pt (the master #7 band; letter-spacing .1 em).
  static const double warningFontSize = 22;

  /// §10.3 the top band's top edge sits this far under the top strip, the
  /// bottom band's bottom edge this far above the bottom strip (pt).
  static const double warningGap = 6;

  /// PRD-2.3 §10.3 / §10.1 (S8-07 call): the design has no HUD row, but in
  /// the game the heart and pause controls (y 52–90) and, in versus, the
  /// versus bar and its name chips (to y 114) sit right under the top
  /// strip. The top band moves down to keep this gap under the lowest of
  /// them, so the full text and both chevrons stay readable and the pause
  /// button stays usable (never painted over).
  static const double warningHudGap = 6;

  /// §10.3 the chevrons' centre x (pt) at each end of a band.
  static const List<double> chevronX = [30, 290];

  /// §10.3 chevron scale (the design's polygon is ±22 × −12..16).
  static const double chevronScale = .6;

  /// §10.3 the chevrons pulse this far towards the spikes (pt) …
  static const double chevronPulse = 4;

  /// §10.3 … at this rate (rad/s; `(sin(t × 6) + 1) / 2`).
  static const double chevronPulseOmega = 6;

  // --- flap path (§10.3) -----------------------------------------------------
  /// §10.3 the path's start: the bird's front (x 84, mid).
  static const Offset pathStart = Offset(84, 0);

  /// §10.3 the two FLAP points (x, y below mid).
  static const Offset flap1 = Offset(152, 12);
  static const Offset flap2 = Offset(220, 18);

  /// §10.3 the three arcs' peaks (pt) and point counts (the design's
  /// `seg(…, peak, n)`).
  static const List<double> arcPeaks = [66, 60, 44];
  static const List<int> arcPoints = [30, 30, 34];

  /// §10.3 the path runs on past hoop 0's centre: 4 steps of 3.4 pt
  /// (≈ 14 pt).
  static const int tailSteps = 4;
  static const double tailStep = 3.4;

  /// §10.3 the stage foreground at 80 %, 3 pt, dashes 8 / 7.
  static const double pathAlpha = .8;
  static const double pathWidth = 3;
  static const List<double> pathDash = [8, 7];

  /// §10.3 one loop (s); the path draws itself over the first 62 % (≈ 2 s)
  /// and fades out over the last 12 %.
  static const double loop = 3.2;
  static const double drawShare = .62;
  static const double outFrom = .88;

  /// §10.3 the arrowhead: a triangle 14 pt long, 16 pt wide, tip forward.
  static const double arrowLength = 14;
  static const double arrowHalfWidth = 8;

  /// §10.3 FLAP labels: Opificio 15, letter-spacing 2, 18 pt below the point.
  static const String flapText = 'FLAP';
  static const double flapFontSize = 15;
  static const double flapLetterSpacing = 2;
  static const double flapLabelDy = 18;

  // --- TAP TO FLAP! (§10.3) --------------------------------------------------
  static const String ctaText = 'TAP TO FLAP!';

  /// §10.3 the banner's centre: (160, mid + 80).
  static const Offset ctaCentre = Offset(160, 80);

  /// §10.3 rotated −0.05 rad, a ±4 % pulse at 5 rad/s.
  static const double ctaRotation = -.05;
  static const double ctaPulse = .04;
  static const double ctaPulseOmega = 5;

  /// §10.3 the pink box (220 × 50 at −110, −27) and its hard plum shadow
  /// 6 / 6.
  static const Rect ctaBox = Rect.fromLTWH(-110, -27, 220, 50);
  static const Offset ctaShadow = Offset(6, 6);
  static const Color pink = Color(0xFFEC008C);
  static const Color plum = Color(0xFF7A0044);

  /// §10.3 Fredoka SemiBold 28 white, letter-spacing 1, centred at (0, −1).
  static const double ctaFontSize = 28;
  static const double ctaLetterSpacing = 1;
  static const double ctaTextDy = -1;

  // --- the hand (§10.3, design D) --------------------------------------------
  /// §10.3 the hand's anchor: (154, mid + 150).
  static const Offset handAnchor = Offset(154, 150);

  /// §10.3 tilt (rad) and scale.
  static const double handRotation = -.26;
  static const double handScale = .86;

  /// §10.3 the fingertip is (0, −34) in hand units.
  static const double handTipLength = 34;

  /// §10.3 white fill, plum outline 3.2 pt (round joins), hard plum shadow
  /// offset (5, 6).
  static const Color handFill = Color(0xFFFFFFFF);
  static const double handOutline = 3.2;
  static const Offset handShadow = Offset(5, 6);

  /// §10.3 each "tap" presses the hand down 6 pt.
  static const double pressDepth = 6;

  /// §10.3 a press lasts 8 % of the draw, the strokes' flash 14 %.
  static const double pressShare = .08;
  static const double burstShare = .14;

  /// §10.3 the five strokes around the fingertip (degrees), 3.4 pt, round
  /// caps: inner radius 13 (+ 4 as they fade), 9 pt long.
  static const List<double> burstAngles = [-150, -115, -90, -65, -30];
  static const double burstWidth = 3.4;
  static const double burstInner = 13;
  static const double burstSpread = 4;
  static const double burstLength = 9;

  /// §10.3 the pink ripple: from r 10, growing 90 pt/s, fading 1.8 /s,
  /// stroke 4.
  static const double rippleStart = 10;
  static const double rippleGrowth = 90;
  static const double rippleFade = 1.8;
  static const double rippleWidth = 4;
}
