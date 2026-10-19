import 'dart:ui';

/// Tuning of the shared parts (PRD-2 §3.0.9 masters and the extra shared
/// parts of ARCH §3). WP-0c. Every member's doc starts with its PRD section.
///
/// Units: seconds, points, pt/s, degrees; ratios as fractions.
abstract final class PartsConfig {
  // ---------------------------------------------------------------- palette
  /// §3.4 Pink `#EC008C` (ring front, banner tier 1/8, burst, trail).
  static const Color pink = Color(0xFFEC008C);

  /// §3.4 Light pink `#FF4FB7` (banner tiers 2/7).
  static const Color lightPink = Color(0xFFFF4FB7);

  /// §3.4 Gold `#FFB529` (coin, gold ring, gold bird, banner tiers 3/6).
  static const Color gold = Color(0xFFFFB529);

  /// §3.4 Plum `#7A0044` (banner tiers 5/10, sticker text).
  static const Color plum = Color(0xFF7A0044);

  /// §5.4 Soft pink `#FCD9EE` (third burst colour).
  static const Color softPink = Color(0xFFFCD9EE);

  // ------------------------------------------------------- #1 spike strips
  /// §3.0.9 #1 Strip height: solid band + teeth (pt).
  static const double spikeStripHeight = 44;

  /// §3.0.9 #1 Solid band of the strip (pt).
  static const double spikeBand = 26;

  /// §3.0.9 #1 Tooth depth (pt).
  static const double spikeToothDepth = 18;

  /// §3.0.9 #1 Tooth period = tile width (pt); tips at x = 20 + 40 k.
  static const double spikeToothPeriod = 40;

  // ------------------------------------------------------------ #3 ring
  /// §3.0.9 #3 Ring width (pt): the ellipse's horizontal diameter.
  static const double ringWidth = 24;

  /// §3.0.9 #3 Ring stroke (pt).
  static const double ringStroke = 7;

  /// §3.0.1 Rim-end circle radius (pt); ring half height = opening / 2 + this.
  static const double rimRadius = 7;

  // -------------------------------------------------- #7 streak banner
  /// §3.0.9 #7 Banner top (pt from the screen top).
  static const double bannerTop = 190;

  /// §3.0.9 #7 Banner vertical padding (pt, above and below the text).
  static const double bannerPadding = 6;

  /// §3.0.9 #7 Letter spacing (em).
  static const double bannerLetterSpacing = .1;

  /// §3.0.9 #7 Scale-in share of the banner duration (0.12 ≈ 0.1 s).
  static const double bannerInShare = .12;

  /// §3.0.9 #7 Hold-until share of the banner duration (scale-out after).
  static const double bannerHoldShare = .75;

  /// §3.0.9 #7 Duration = base + per-tier × min(tier, cap) (s): 1.06–1.86 s.
  static const double bannerBase = .9;

  /// §3.0.9 #7 Extra duration per tier (s).
  static const double bannerPerTier = .16;

  /// §3.0.9 #7 Tier where the duration stops growing.
  static const int bannerTierCap = 6;

  // ---------------------------------------------------- #8 coin popup
  /// §3.0.9 #8 Popup text size (pt).
  static const double popupFontSize = 28;

  /// §3.0.9 #8 Popup coin icon size (pt).
  static const double popupCoinSize = 24;

  /// §3.0.9 #8 Gap between the text and the coin (pt).
  static const double popupGap = 3;

  /// §3.0.9 #8 Start offset from the pass point (top-left of the popup).
  static const Offset popupOffset = Offset(-10, -70);

  /// §3.0.9 #8 Rise distance (pt).
  static const double popupRise = 40;

  /// §3.0.9 #8 Duration (s).
  static const double popupDuration = 1.1;

  // --------------------------------------------------- #9 perfect burst
  /// §3.0.9 #9 Base square count; + [burstPerTier] × min(tier, 3).
  static const int burstBase = 8;

  /// §3.0.9 #9 Extra squares per tier (tiers 1–3).
  static const int burstPerTier = 3;

  /// §3.0.9 #9 Square size range (pt).
  static const double burstSizeMin = 5, burstSizeMax = 8;

  /// §3.0.9 #9 Flight distance range (pt).
  static const double burstDistMin = 25, burstDistMax = 55;

  /// §3.0.9 #9 Life range (s).
  static const double burstLifeMin = .35, burstLifeMax = .6;

  // ----------------------------------------------------- #10 block trail
  /// §3.0.9 #10 Blocks per second.
  static const double trailRate = 30;

  /// §3.0.9 #10 Block size range (pt).
  static const double trailSizeMin = 8, trailSizeMax = 13;

  /// §3.0.9 #10 Spawn distance behind the bird along the flight direction.
  static const double trailBack = 26;

  /// §3.0.9 #10 Sideways jitter (± pt).
  static const double trailSide = 8;

  /// §3.0.9 #10 Drift opposite to the flight direction over the life (pt).
  static const double trailDrift = 70;

  /// §3.0.9 #10 Block life (s).
  static const double trailLife = .45;

  /// §3.0.9 #10 Start opacity (fades to 0).
  static const double trailAlpha = .9;

  // ------------------------------------------------- #11 ring tier looks
  /// §5.3 Sparkle emission per visible ring per second, tiers 0..3+.
  static const List<double> sparkleRate = [0, 7, 16, 38];

  /// §5.3 Sparkle size range per tier 1..3+ (pt).
  static const List<(double, double)> sparkleSize = [
    (9, 15), (10, 17), (12, 24), //
  ];

  /// §5.3 Sparkle twinkle life range (s).
  static const double sparkleLifeMin = .5, sparkleLifeMax = .9;

  /// §5.3 Share of tier-3 sparkles that also launch a flame flick.
  static const double flameChance = .5;

  /// §5.3 Flame flick width range (pt).
  static const double flameWidthMin = 7, flameWidthMax = 12;

  /// §5.3 Flame flick height factor range (× width).
  static const double flameTallMin = 1.6, flameTallMax = 2.4;

  /// §5.3 Flame flick rise range (pt).
  static const double flameRiseMin = 20, flameRiseMax = 45;

  /// §5.3 Flame flick life range (s).
  static const double flameLifeMin = .4, flameLifeMax = .7;

  /// §5.3 Glow sprite width (pt).
  static const double glowWidth = 96;

  /// §5.3 Glow sprite height at the mock's 92 pt ring (pt); grows with the
  /// ring (height = ring height + 60).
  static const double glowHeight = 152;

  /// §5.3 Glow fade-in (s).
  static const double glowFadeIn = .25;

  // ---------------------------------------------------------- dust puff
  /// §3.0.9 Dust puff default count (12–22).
  static const int dustCount = 22;

  /// §3.0.9 Dust radius range (pt).
  static const double dustSizeMin = 4, dustSizeMax = 9;

  /// §3.0.9 Dust horizontal speed (± pt/s).
  static const double dustVx = 140;

  /// §3.0.9 Dust vertical speed range (pt/s, up is negative).
  static const double dustVyMin = -90, dustVyMax = -10;

  /// §3.0.9 Dust life range (s).
  static const double dustLifeMin = .6, dustLifeMax = 1;

  /// §3.0.9 Dust gravity (pt/s², rides84 `dust`).
  static const double dustGravity = 60;

  /// §3.0.9 Dust horizontal slow-down (1/s).
  static const double dustDrag = 2;

  /// §3.0.9 Dust peak opacity.
  static const double dustAlpha = .8;

  // ----------------------------------------------------- particle pool
  /// §5.4 Max particles alive in the shared run pool.
  static const int maxParticles = 130;

  // --------------------------------------------------- non-perfect pulse
  /// §5.1 Pass pulse scale start.
  static const double pulseScaleFrom = .8;

  /// §5.1 Pass pulse scale end.
  static const double pulseScaleTo = 1.9;

  /// §5.1 Pass pulse duration (s).
  static const double pulseDuration = .55;

  /// §5.1 Pass pulse border (pt).
  static const double pulseStroke = 4;

  /// §5.1 Pass pulse start opacity.
  static const double pulseAlpha = .9;

  // ------------------------------------------------- invulnerability
  /// §5.5 Invulnerability flash half period (s): 25 % ↔ 100 %.
  static const double invulnStep = .1;

  /// §5.5 Invulnerability low opacity.
  static const double invulnLow = .25;

  /// §3.3 Invulnerability duration (s).
  static const double invulnDuration = 2;

  // ------------------------------------------------------- dashed path
  /// §5.12 Dashed guide stroke (pt).
  static const double dashWidth = 2.5;

  /// §5.12 Dash / gap (pt).
  static const double dashOn = 6, dashOff = 6;
}
