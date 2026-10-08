import 'dart:ui';

/// Tuning and layout of the results page (PRD-2 §3.14 / §5.10, mock
/// `design/menu_v2/screen_results_levels.html`). WP-2e. Every member's doc
/// starts with its PRD section.
///
/// Geometry is in *reference* points: the 320 × 711 page of the mock. The
/// page is drawn at [scaleFor] about the top centre so the whole column fits
/// between the strips on every screen (568 … 730 pt).
abstract final class ResultsConfig {
  // ------------------------------------------------------------ fitting
  /// §5.10 Height the layout table was measured at (pt).
  static const double referenceHeight = 711;

  /// §5.10 Top of the content column (the header) at 711 (pt).
  static const double contentTop = 70;

  /// §5.10 Bottom of the content column (NEXT's bottom edge) at 711 (pt).
  static const double contentBottom = 646;

  /// §5.10 (call) Smallest gap between a strip's tooth tips and the column
  /// on the shortest screen (568): the column then scales down uniformly.
  static const double minEdgeGap = 10;

  /// 0 at 568, 1 at 711 and above.
  static double _t(double h) => ((h - 568) / (referenceHeight - 568)).clamp(0.0, 1.0);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// §5.10 Where the column's top lands on screen at [h] (70 at 711).
  static double topFor(double h) =>
      _lerp(44 + minEdgeGap, contentTop, _t(h));

  /// §5.10 Where the column's bottom may reach at [h] (646 at 711).
  static double bottomFor(double h) =>
      h - _lerp(44 + minEdgeGap, referenceHeight - contentBottom, _t(h));

  /// §5.10 (call) Uniform page scale at [h]: 1 from 711 up, ≈ 0.8 at 568.
  static double scaleFor(double h) =>
      ((bottomFor(h) - topFor(h)) / (contentBottom - contentTop)).clamp(0.0, 1.0);

  // ------------------------------------------------------------ layout
  /// §5.10 Header "YOU WIN!" / "YOU LOSE" / "DRAW" (versus only, WP-5b).
  static const Rect header = Rect.fromLTWH(14, 70, 292, 48);
  static const double headerFontSize = 28;
  static const double headerLetterSpacing = .12;

  /// §5.10 Versus card: soft panel (`fg` 14 % over bg), padding 16 / 8 / 8.
  static const Rect card = Rect.fromLTWH(14, 124, 292, 124);
  static const double cardTint = .14;
  static const double cardPadTop = 16;
  static const double cardPadSide = 8;

  /// §5.10 Player column: avatar 40, name Fredoka 15, score 42 pt (36 from
  /// four digits); avatar top = card top + 16 + 4.
  static const double avatarSize = 40;
  static const double avatarGlyph = 26;
  static const double avatarTop = 144;
  static const double nameTop = 188;
  static const double nameFontSize = 15;
  static const double scoreTop = 205;
  static const double scoreFontSize = 42;
  static const double scoreFontSizeLong = 36;

  /// §5.10 Column centres: solo centred (160); versus you / opponent.
  static const double soloColumnX = 160;
  static const double youColumnX = 84;
  static const double opponentColumnX = 236;

  /// §5.10 WINNER tag (gold, 11 pt, 0.1 em, padding 2 × 8) 12 pt above the
  /// column top.
  static const double winnerTagFontSize = 11;

  // region WP-5b — versus parts
  /// §5.10 WINNER tag: top (12 pt above the column's 4 pt padding) and its
  /// padding 2 × 8.
  static const double winnerTagTop = 128;
  static const double winnerTagPadX = 8;
  static const double winnerTagPadY = 2;

  /// §5.10 "VS" (Fredoka 15 plum) centred between the columns, on their
  /// vertical middle.
  static const double vsCentreY = 194;
  // endregion WP-5b

  /// §5.10 NEW BEST sticker top (overlapping the card's bottom edge).
  static const double newBestTop = 238;

  /// §5.10 Level stage (y 262, 148 tall); plate centre (160, 346).
  static const Rect stage = Rect.fromLTWH(0, 262, 320, 148);
  static const Offset plateCentre = Offset(160, 346);

  /// §5.10 Emblem art scale and bird scale in emblem units.
  static const double emblemScale = .62;
  static const double birdOnEmblem = 1.4;

  /// §5.10 The bird flaps "now and then": the wing is down for the first
  /// [birdFlapShare] of every 1 / [birdFlapRate] s.
  static const double birdFlapRate = 1.2;
  static const double birdFlapShare = .25;

  /// §5.10 Rank line "HAWK · LV 7" (Fredoka 18 plum) top.
  static const double rankTop = 414;
  static const double rankFontSize = 18;

  /// §5.10 Progress bar x 50 → 270, y 444, 14 tall; label 11 pt 0.12 em
  /// 18 pt under the bar's top.
  static const Rect bar = Rect.fromLTWH(50, 444, 220, 14);
  static const double barLabelTop = 462;
  static const double barLabelFontSize = 11;
  static const double barLabelLetterSpacing = .12;

  /// §5.10 CLAIM button 210 × 38 at the bar's spot, 20 pt, gold-dark edge.
  static const Rect claim = Rect.fromLTWH(55, 438, 210, 38);
  static const double claimFontSize = 20;
  static const double claimCoinSize = 20;
  static const double claimEdge = 3;

  /// §5.10 YOUR REWARD label (12 pt, 0.2 em) and the white pill.
  static const double rewardLabelTop = 494;
  static const double rewardLabelFontSize = 12;
  static const double rewardLabelLetterSpacing = .2;
  static const Rect rewardPill = Rect.fromLTWH(60, 512, 200, 46);
  static const double rewardFontSize = 32;
  static const double rewardCoinSize = 28;
  static const double rewardGap = 10;

  /// §5.10 NEXT button (28 pt, 0.14 em).
  static const Rect next = Rect.fromLTWH(14, 596, 292, 50);
  static const double nextFontSize = 28;
  static const double nextLetterSpacing = .14;

  /// §3.0.1 Bottom buttons keep the same distance to the bottom edge on
  /// every screen height 568 … 730 (the reference: 711 − 646 = 65 pt).
  static const double bottomGap = referenceHeight - contentBottom;

  /// §3.0.1 Screen y of NEXT's top edge at [h] (bottom-anchored).
  static double nextTopFor(double h) => h - bottomGap - next.height;

  /// §3.14 / PRD-1 §3.7 (call) The kept leaderboard and share buttons: two
  /// 40 pt pink boxes flanking the reward pill, 24 pt glyphs.
  static const Rect leaderboardButton = Rect.fromLTWH(14, 515, 40, 40);
  static const Rect shareButton = Rect.fromLTWH(266, 515, 40, 40);
  static const double sideIconSize = 24;

  /// §5.10 LEVEL UP! banner (Fredoka 22 plum on gold, padding 4 × 16,
  /// 0.08 em, 3 pt gold-dark drop edge) top.
  static const double levelUpTop = 247;
  static const double levelUpFontSize = 22;

  // ------------------------------------------------------------ colours
  /// §5.10 Fixed colours of the page.
  static const Color pink = Color(0xFFEC008C);
  static const Color soft = Color(0xFFFCD9EE);
  static const Color plum = Color(0xFF7A0044);
  static const Color gold = Color(0xFFFFB529);
  static const Color goldDark = Color(0xFFC98A00);
  static const Color goldLight = Color(0xFFFFE082);

  // ------------------------------------------------------------ sequence
  /// §5.10 (call) The page fades in over this long; buttons take taps after.
  static const double pageFadeIn = .3;

  /// §5.10 Scores and YOUR REWARD count up from 0.45 s for 0.7 s (ease-out).
  static const double countStart = .45;
  static const double countDuration = .7;

  /// §5.10 NEW BEST pops in at 1.2 s (0.38 s).
  static const double newBestAt = 1.2;

  /// §5.10 The bar fills from 1.65 s: 1.2 s within a level, 0.9 s to 100 %
  /// when a level is reached.
  static const double barAt = 1.65;
  static const double barFill = 1.2;
  static const double barToLevel = .9;

  /// §5.10 The label bumps (1.25 → 1, 0.3 s) after a fill within a level.
  static const double barLabelBump = .3;

  /// §5.10 LEVEL UP: bar flash 0.35 s, old emblem shake 0.26 s, then the
  /// white screen flash (0.85 → 0, 0.45 s) and the new emblem pop (0.5 s).
  static const double barFlash = .35;
  static const double shake = .26;
  static const double screenFlash = .45;
  static const double screenFlashAlpha = .85;
  static const double emblemPop = .5;

  /// §5.10 Rotating gold rays: 12 wedges, radius 150, 35 %, 0.6 rad/s.
  static const int rays = 12;
  static const double rayRadius = 150;
  static const double rayAlpha = .35;
  static const double raySpeed = .6;

  /// §5.10 Rank bounce / LEVEL UP! drop-in / NEW BEST pop-out.
  static const double rankBounce = .52;
  static const double levelUpDrop = .52;
  static const double newBestOut = .2;

  /// §5.10 Confetti pieces from the emblem: lv 1–4 / 5–8 / 9–10.
  static int confettiFor(int level) => level >= 9
      ? 150
      : level >= 5
      ? 100
      : 60;

  /// §5.10 Second wave for lv 9–10 after this long (2 confetti + 2 rockets).
  static const double secondWave = .9;

  /// §5.10 Second-wave confetti bursts (pieces each).
  static const int secondWaveConfetti = 60;

  /// §5.10 Fireworks: (x, burst y, colour, delay) of the three rockets and
  /// of the lv 9–10 second-wave pair.
  static const List<(double, double, Color, double)> rockets = [
    (70, 170, Color(0xFFFFB529), 0),
    (250, 150, Color(0xFF29B6F6), .22),
    (170, 200, Color(0xFFFF4FB7), .44),
  ];
  static const List<(double, double, Color, double)> secondWaveRockets = [
    (110, 140, Color(0xFFAB47BC), 0),
    (220, 120, Color(0xFF66BB6A), 0),
  ];

  /// §5.10 The bar becomes CLAIM 0.9 s after the level up (pop 0.38 s; the
  /// bar fades 0.2 s); the button then pulses 1 ↔ 1.06 every 0.52 s.
  static const double claimAfter = .9;
  static const double claimPop = .38;
  static const double barFadeOut = .2;
  static const double claimPulse = .52;
  static const double claimPulseScale = 1.06;

  /// §5.10 CLAIM: 12 coins fly from the button (x ± 60) into the pill
  /// (x ± 30), 0.55 s each, 0.05 s apart, arcing 60 pt up; the button
  /// fades out (0.25 s).
  static const int claimCoins = 12;
  static const double coinFlight = .55;
  static const double coinStagger = .05;
  static const double coinArc = 60;
  static const double claimFadeOut = .25;

  /// §5.10 The reward counts up 0.45 s after CLAIM for 0.9 s; the pill
  /// bumps (1.12, 0.5 s) 0.85 s into the count; small confetti (30) and the
  /// rays end 0.95 s into it; then the bar comes back (0.25 s) and fills to
  /// the progress in the new level (0.7 s).
  static const double claimCountDelay = .45;
  static const double claimCount = .9;
  static const double pillBumpAt = .85;
  static const double pillBump = .5;
  static const double pillBumpScale = 1.12;
  static const double claimConfettiAt = .95;
  static const int claimConfetti = 30;
  static const double barBackFade = .25;
  static const double barBackFill = .7;

  /// §5.10 NEXT while CLAIM shows: the claim animation, this pause, home.
  static const double nextAfterClaim = .25;
}
