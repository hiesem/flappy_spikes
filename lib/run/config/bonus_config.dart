import 'dart:ui';

/// Balloon bonus screen knobs (PRD-2 §3.15, §5.14; mock engine
/// `design/menu_v2/bonus.js` with `BONUS_OPT = {final: true, label: 'POP THE
/// JACKPOT!'}`). Geometry in the 320 × 711 reference; times in seconds.
abstract final class BonusConfig {
  /// §3.15 / Q35 The nine prizes (coins), shuffled per screen.
  static const List<int> prizes = [25, 25, 50, 50, 75, 75, 100, 150, 250];

  /// §3.15 The jackpot prize.
  static const int jackpot = 250;

  /// §3.15 Feathers per round of pops, and the ad's extra feathers (once).
  static const int feathers = 3;

  // ----------------------------------------------------------- layout
  /// §5.14 Reference screen.
  static const double referenceHeight = 711;

  /// §3.0.1 / §5.14 (S6-63) Top of the bottom-button band in the
  /// reference: the feather row, the ad button, NO THANKS and NEXT (y ≥
  /// 552) keep their reference size and bottom distance on every screen
  /// height; only the column above (pill, hero, grid, prompt) scales.
  static const double bandTop = 552;

  /// §5.14 Coin total pill: white, x 204 → 306, y 52, 38 tall.
  static const Rect pill = Rect.fromLTWH(204, 52, 102, 38);

  /// §5.14 Where the flying coins land (the pill's coin).
  static const Offset pillCoin = Offset(288, 71);

  /// §5.14 Pill number plum 24 pt (right edge 18 pt right of the pill
  /// centre), coin 22 pt.
  static const double pillFont = 24;
  static const double pillCoinSize = 22;

  /// §5.14 Pill punch ×1.12 over 0.25 s when a coin lands.
  static const double pillPunch = .12;
  static const double pillPunchLength = .25;

  /// §5.14 Hero: white circle r 42 at (160, 146), gold 4 pt rim, 8 gold
  /// rays (30 %) rotating 0.5 rad/s, 10-coin heap.
  static const Offset hero = Offset(160, 146);
  static const double heroRadius = 42;
  static const double heroRim = 4;
  static const double heroRayOmega = .5;

  /// §5.14 Feather wings: three per side, flapping at 0.8 Hz.
  static const double wingHz = .8;

  /// §5.14 Banner: gold band centred at y 200 (top 188), 24 tall, width =
  /// text + 32 (min 164), folded ends `#D48A00`; plum 16 pt, 1.6 spacing;
  /// pulses ±3.5 % at 1.1 Hz.
  static const String bannerText = 'POP THE JACKPOT!';
  static const double bannerTop = 188;
  static const double bannerHeight = 24;
  static const double bannerFont = 16;
  static const double bannerSpacing = 1.6;
  static const double bannerMinHalf = 82;
  static const double bannerPulse = .035;
  static const double bannerHz = 1.1;

  /// §5.14 Grid panel x 14 → 306, y 222 → 522 (`fg` 14 %); nine 88 pt
  /// tiles (`fg` 24 %), 6 pt gaps, starting at (22, 230).
  static const Rect panel = Rect.fromLTWH(14, 222, 292, 300);
  static const double panelMix = .14;
  static const double tileMix = .24;
  static const double tile = 88;
  static const double tileStep = 94;
  static const Offset gridOrigin = Offset(22, 230);

  /// §5.14 Prompt: plum 20 pt, 2 px spacing, centred at y 541.
  static const double promptY = 541;
  static const double promptFont = 20;
  static const double promptSpacing = 2;
  static const String promptPick = 'POP A BALLOON!';
  static const String promptMore = 'MORE FEATHERS?';

  /// §5.14 Feather row: x 112 / 160 / 208, y 588, scale 1.25, turned 0.45.
  static const double rowX = 112;
  static const double rowStep = 48;
  static const double rowY = 588;
  static const double rowScale = 1.25;
  static const double rowTilt = .45;

  /// §5.14 Used feather = silhouette in `fg` 30 %.
  static const double ghostMix = .3;

  /// §5.14 Ad button: gold, x 50 → 270, y 562, 50 tall; pops in (0.35 s,
  /// overshoot), pulses ±3 % at 1.2 Hz, a white shine every 1.6 s.
  static const Rect adButton = Rect.fromLTWH(50, 562, 220, 50);
  static const double adPop = .35;
  static const double adPulse = .03;
  static const double adHz = 1.2;
  static const double shineEvery = 1.6;

  /// PRD-2.2 §7.8 while the offer waits for an ad (up to
  /// `Config.bonusAdWait`): the button at this opacity with a spinner in
  /// place of the video icon, no taps.
  static const double adWaitAlpha = .6;

  /// PRD-2.2 §7.8 no ad within the wait: the offer fades out over this long
  /// (s), then NEXT fades in.
  static const double adWaitFadeOut = .3;

  /// §5.14 NO THANKS: `fg` 80 %, 20 pt, 2 px spacing, y 641, fades in
  /// (0.45 s) after 3 s; tap band y 622 → 660.
  static const double noThanksDelay = 3;
  static const double noThanksFade = .45;
  static const double noThanksY = 641;
  static const double noThanksAlpha = .8;
  static const String noThanksText = 'NO THANKS';

  /// §5.14 NEXT: pink, x 14 → 306, y 562, 50 tall, soft-pink 28 pt with
  /// 4 px spacing; fades in ≈ 0.3 s after the last coin lands.
  static const Rect nextButton = Rect.fromLTWH(14, 562, 292, 50);
  static const double nextFont = 28;
  static const double nextSpacing = 4;
  static const double nextFadeIn = .3;
  static const double nextDelay = .8;

  // ----------------------------------------------------------- pop timeline
  /// §5.14 The rightmost feather flies to the balloon (0.42 s).
  static const double featherFly = .42;

  /// §3.15 Taps are ignored while a balloon opens (≈ 1.1 s from the tap).
  static const double busy = .42 + .7;

  /// §5.14 Stretch ×1 → ×1.2 with a jitter until the pop at 0.32 s.
  static const double popAt = .32;
  static const double stretch = .2;

  /// §5.14 The string drops and fades in 0.3 s.
  static const double stringFade = .3;

  /// §5.14 The pop: 11 pink / dark-pink scraps.
  static const int scraps = 11;

  /// §5.14 The prize card fades in at 0.6 s with an overshoot pop (0.3 s).
  static const double cardAt = .6;
  static const double cardFade = .12;
  static const double cardPop = .3;

  /// §5.14 The balloon is hidden from 0.75 s; the tile is settled at 1.2 s.
  static const double balloonGone = .75;
  static const double settled = 1.2;

  /// §5.14 3–8 coins (by amount) fly into the pill, 0.5 s each, 0.07 s
  /// apart, from 0.25 s after the card.
  static const double coinDelay = .25;
  static const double coinFly = .5;
  static const double coinGap = .07;

  /// §3.15 Coin landing sound at most every 60 ms.
  static const double coinSoundGap = .06;

  /// §5.14 Prize ring / confetti; the jackpot: ring 20 → 120, 36 confetti,
  /// a 0.5 s gold screen flash at 45 %.
  static const int confetti = 12;
  static const int jackpotConfetti = 36;
  static const double flashAlpha = .45;
  static const double flashLength = .5;

  /// §5.14 After the ad: three feathers fly back (0.5 s each, 0.22 s
  /// apart). The fake ad of the mock lasts 2.2 s; the real ad is awaited.
  static const double refillFly = .5;
  static const double refillGap = .22;

  // ----------------------------------------------------------- colours
  static const Color pink = Color(0xFFEC008C);
  static const Color darkPink = Color(0xFFB0006B);
  static const Color lightPink = Color(0xFFFF4FB7);
  static const Color soft = Color(0xFFFCD9EE);
  static const Color plum = Color(0xFF7A0044);
  static const Color gold = Color(0xFFFFB529);
  static const Color goldDark = Color(0xFFD48A00);
  static const Color paleGold = Color(0xFFFFD54A);
}
