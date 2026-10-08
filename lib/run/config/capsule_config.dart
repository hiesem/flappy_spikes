import 'dart:ui';

/// Powerup capsules and the timed powerups they start: Hourglass, Mini
/// Bird, Coin Frenzy (PRD-2 §3.30–§3.32, §5.29–§5.31; idea lab round 3
/// `screen_lab3_powerups.html`, `lab_power.js` / `lab2_power.js`). Every
/// member's doc starts with its PRD section (ARCH §4). The capsule hit
/// radius (18) is `PickupRadii.capsule`, the spawn rules and type weights
/// live in `DirectorTables.prd2`, the Hourglass duration range is
/// `RunConfig.hourglassMin` / `hourglassMax` and the Mini Bird scale is
/// `RunConfig.miniBirdScale`.
abstract final class CapsuleConfig {
  // --- §5.29 the capsule (all timed powerups) ------------------------------

  /// §5.29 Capsule body: a rounded square this many pt wide.
  static const double size = 34;

  /// §5.29 Capsule corner radius (pt).
  static const double radius = 8;

  /// §5.29 The darker lower band: rgba(0,0,0,.14), 12 pt tall from y +5
  /// (capsule-local, centre origin), corner radius 6.
  static const Color band = Color(0x24000000);

  /// §5.29 Lower band top (pt below the capsule centre).
  static const double bandTop = 5;

  /// §5.29 Lower band height (pt).
  static const double bandHeight = 12;

  /// §5.29 The capsule bobs ±3 pt (`sin(t · 3)`).
  static const double bob = 3;

  /// §5.29 Bob angular speed (rad/s).
  static const double bobOmega = 3;

  /// §5.29 The pulsing ring round the capsule: radius 25 pt, stroke 3 pt.
  static const double ringRadius = 25;

  /// §5.29 Pulsing ring stroke (pt).
  static const double ringStroke = 3;

  /// §5.29 Ring opacity 0.35 + 0.25 · sin(5 t).
  static const double ringAlpha = .35;

  /// §5.29 Ring opacity swing.
  static const double ringAlphaSwing = .25;

  /// §5.29 The capsule (and ring) scale 1 + 0.06 · sin(5 t).
  static const double pulseScale = .06;

  /// §5.29 Pulse angular speed (rad/s).
  static const double pulseOmega = 5;

  // --- §5.29 the timer pill ------------------------------------------------

  /// §5.29 Timer pill left edge (pt, screen).
  static const double pillX = 100;

  /// §3.30 / §5.29 Timer pill top (pt from the screen top; top-anchored
  /// like the HUD row). Call: the mock's y ≈ 206 lies inside the master
  /// banner band (#7: y 190, ≈ 53 pt tall), which shows on every perfect
  /// pass and would hide the pill most of the time; the pill keeps its
  /// fixed spot just above that band, in the free space under the HUD row
  /// (name chips end at 114), so banners, the collect slot (206–254) and
  /// the pill never overlap.
  static const double pillY = 156;

  /// §5.29 Timer pill size 120 × 22 pt.
  static const double pillWidth = 120;

  /// §5.29 Timer pill height (pt).
  static const double pillHeight = 22;

  /// §5.29 Pill track colour rgba(0,0,0,.12).
  static const Color pillTrack = Color(0x1F000000);

  /// §5.29 The draining bar starts this far right of the pill's left edge.
  static const double barInset = 24;

  /// §5.29 Bar inset from the top (pt).
  static const double barTop = 5;

  /// §5.29 Bar height (pt); its full length is pill width − 30.
  static const double barHeight = 12;

  /// §5.29 Bar full length = pill width − this.
  static const double barShort = 30;

  /// §5.29 The icon disc: 26 pt (r 13) centred 11 pt in from the left.
  static const double discRadius = 13;

  /// §5.29 Icon scale inside the disc (the capsule icon × 0.62).
  static const double discIconScale = .62;

  /// §5.29 Seconds-left label ("14 s"): 13 pt Opificio at x 226, centred
  /// on the pill's middle line.
  static const double labelX = 226;

  /// §5.29 Seconds-left label size (pt).
  static const double labelSize = 13;

  /// §5.29 The pill fades in / out over this long (s, real time; call).
  static const double pillFade = .2;

  // --- §3.30 / §5.29 Hourglass ---------------------------------------------

  /// §5.29 Hourglass colour.
  static const Color hourglass = Color(0xFF2F80FF);

  /// §3.30 The world runs at 45 % speed.
  static const double hourglassScale = .45;

  /// §3.30 The slow-down eases in (and back out at the end) over ≈ 0.2 s
  /// (real time).
  static const double hourglassEase = .2;

  /// §3.30 / §5.29 Music playback rate while slowed (≈ 72 %).
  static const double hourglassMusicRate = .72;

  /// §3.30 / §5.29 Tick-tock every 0.6 s (real time).
  static const double hourglassTick = .6;

  /// §5.29 Ghost trail: fading birds spawned 16 per second (real time).
  static const double ghostRate = 16;

  /// §5.29 A ghost fades out over 0.5 s.
  static const double ghostLife = .5;

  /// §5.29 A ghost starts at 25 % opacity.
  static const double ghostAlpha = .25;

  /// §5.29 Clock ring round the bird: radius 26 pt, 2 pt, rgba(47,128,255,.7).
  static const double clockRadius = 26;

  /// §5.29 Clock ring stroke (pt).
  static const double clockStroke = 2;

  /// §5.29 Clock ring colour.
  static const Color clockColor = Color(0xB32F80FF);

  /// §5.29 The clock hand: 22 pt from the bird centre, one turn over the
  /// whole duration (starts pointing up).
  static const double clockHand = 22;

  // --- §3.31 / §5.30 Mini Bird ---------------------------------------------

  /// §5.30 Mini Bird colour.
  static const Color mini = Color(0xFF2EBD6B);

  /// §3.31 Mini Bird lasts 8 s.
  static const double miniDuration = 8;

  /// §3.31 The shrink eases in over ≈ 0.15 s (real time).
  static const double miniShrink = .15;

  /// §3.31 The pop back to full size at the end (s; call: the mock's
  /// `sc += (1 − sc) · dt · 10` reaches 80 % in ≈ 0.16 s).
  static const double miniGrow = .15;

  /// §5.30 Potion liquid / start sparkles: magic purple.
  static const Color potionPurple = Color(0xFFC9A6FF);

  /// §5.30 Start: 12 purple sparkles pull into the bird from 30 pt away.
  static const int miniSparkles = 12;

  /// §5.30 Start sparkle distance (pt).
  static const double miniSparkleFrom = 30;

  /// §5.30 Start sparkle life (s) and diameter (pt).
  static const double miniSparkleLife = .35;

  /// §5.30 Start sparkle diameter (pt).
  static const double miniSparkleSize = 5;

  /// §5.30 While small: little bubbles trail from the bird, 8 per second.
  static const double bubbleRate = 8;

  /// §5.30 Bubble colour (pale green).
  static const Color bubble = Color(0xFFB9F6CA);

  /// §5.30 Bubble life (s).
  static const double bubbleLife = .5;

  /// §5.30 Bubble drift (pt/s, relative to the bird): back and up.
  static const double bubbleVx = -50;

  /// §5.30 Bubble rise (pt/s).
  static const double bubbleVy = -40;

  /// §5.30 End: a burst of 12 green / purple / white squares.
  static const int miniBurst = 12;

  /// §5.30 End burst speed (pt/s, × 0.4–1.2).
  static const double miniBurstSpeed = 130;

  /// §5.30 End burst colours.
  static const List<Color> miniBurstColors = [
    mini,
    potionPurple,
    Color(0xFFFFFFFF),
  ];

  // --- §3.32 / §5.31 Coin Frenzy -------------------------------------------

  /// §5.31 Coin Frenzy colour.
  static const Color frenzy = Color(0xFFFFB529);

  /// §3.32 Coin Frenzy lasts 6 s.
  static const double frenzyDuration = 6;

  /// §3.32 Each ring passed pays +5 coins on top of the normal ring coins.
  static const int frenzyCoins = 5;

  /// §5.31 Coin ring front colour.
  static const Color frenzyRingFront = Color(0xFFFFD54A);

  /// §5.31 Coin ring back colour.
  static const Color frenzyRingBack = Color(0xFFD48A00);

  /// §5.31 Coin ring stroke (pt).
  static const double frenzyRingStroke = 8;

  /// §5.31 10 coins orbit each ring's rim.
  static const int orbitCoins = 10;

  /// §5.31 Orbit speed (turns per second; the mock's 0.3 half-turns/s).
  static const double orbitSpeed = .15;

  /// §5.31 Orbiting coin size (pt; the mock's r 5).
  static const double orbitCoinSize = 10;

  /// §5.31 Each pass: 5 coins burst up from the ring.
  static const int showerCoins = 5;

  /// §5.31 Shower coin speed (pt/s): 180 + random 120.
  static const double showerSpeed = 180;

  /// §5.31 Shower coin extra random speed (pt/s).
  static const double showerSpeedRandom = 120;

  /// §5.31 Shower spread round straight up (rad, ± half).
  static const double showerSpread = 1.4;

  /// §5.31 Shower gravity (pt/s²).
  static const double showerGravity = 600;

  /// §5.31 Shower coin life (s).
  static const double showerLife = .9;

  /// §5.31 Shower coin size (pt; the mock's r 7).
  static const double showerCoinSize = 14;

  /// §5.31 The "+5" popup sits this far right of the ring's "+N" pass
  /// popup and starts this much later (call: master #8 with amount 5, so
  /// the two popups don't overlap).
  static const Offset frenzyPopupShift = Offset(44, 0);

  /// §5.31 "+5" popup delay (s; call).
  static const double frenzyPopupDelay = .12;

  /// §5.31 The pulsing gold border round the screen (pt).
  static const double frenzyBorder = 10;

  /// §5.31 Gold sparkles drift across the screen, 18 per second.
  static const double sparkleRate = 18;

  /// §5.31 Sparkle colour.
  static const Color sparkle = Color(0xFFFFD54A);

  /// §5.31 Sparkle size (pt).
  static const double sparkleSize = 10;

  /// §5.31 Sparkle life (s).
  static const double sparkleLife = .6;

  /// §5.31 Sparkles appear between y 220 and 640 of the 711 pt mock (as
  /// fractions of the screen height).
  static const double sparkleTop = 220 / 711;

  /// §5.31 Sparkle band bottom (fraction of the screen height).
  static const double sparkleBottom = 640 / 711;

  /// §5.31 Sparkle drift (pt/s on screen): left and down.
  static const double sparkleVx = -40;

  /// §5.31 Sparkle fall (pt/s).
  static const double sparkleVy = 30;

  // --- §3.30–3.32 banners --------------------------------------------------

  /// §3.30 The start banner shows the name and a one-line explanation.
  static String bannerTitle(String type) => switch (type) {
    'hourglass' => 'HOURGLASS',
    'mini' => 'MINI BIRD',
    _ => 'COIN FRENZY',
  };

  /// §3.30–3.32 The banner's one-line explanation ([seconds] = this
  /// pickup's duration).
  static String bannerLine(String type, double seconds) {
    final s = seconds.round();
    return switch (type) {
      'hourglass' => 'the world slows down · $s s',
      'mini' => 'half size · roomier rings · $s s',
      _ => 'every ring pays +$frenzyCoins coins · $s s',
    };
  }

  /// §3.30 The start banner stays on screen this long (s; call: the lab's
  /// 1.6 s).
  static const double bannerDuration = 1.6;

  /// Run-world priority of the Hourglass vignette and the Coin Frenzy
  /// border (§5.29 / §5.31 "drawBg": over the score circle, under the
  /// hoops and the spike strips).
  static const int glowPriority = -30;
}
