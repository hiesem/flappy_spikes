import 'dart:ui';

/// Run HUD row and pause screen knobs (PRD-2 §5.7; mock
/// `design/menu_v2/screen_game_versus.html` G1–G3, 320 × 711). The row is
/// top-anchored (§3.0.1 R-3.0.1-15); the pause card keeps its offset from
/// the screen centre.
abstract final class HudConfig {
  /// §5.7 The row's top (pt).
  static const double rowTop = 52;

  /// §5.7 Row height = button size (pt).
  static const double rowHeight = 38;

  /// §5.7 Heart indicator left (pt), 38 × 38.
  static const double heartLeft = 14;

  /// §5.7 The heart icon inside the indicator (pt, the 24-unit box).
  static const double heartIcon = 28;

  /// §5.7 Empty heart: dashed outline, stroke (box units) and dash (pt).
  static const double heartOutline = 2;
  static const List<double> heartDash = [3, 2.5];

  /// §5.7 Extra life ready: pulse 1.0 ↔ 1.14 over 0.9 s.
  static const double heartPulse = 1.14;
  static const double heartPulsePeriod = .9;

  /// §5.7 Versus bar: you box at x 60, opponent box at x 170, 90 × 38.
  static const double youLeft = 60;
  static const double themLeft = 170;
  static const double boxWidth = 90;

  /// §5.7 Avatar squares (38 × 38) on the outside of each box.
  static const Color youBox = Color(0xFFEC008C);
  static const Color youAvatar = Color(0xFFC40073);

  /// §5.7 Opponent avatar: the stage foreground darkened (70 % over black).
  static const double themAvatarMix = .7;

  /// §5.7 Scores 26 pt (soft pink on yours, stage background on theirs).
  static const double scoreSize = 26;
  static const Color soft = Color(0xFFFCD9EE);

  /// §5.7 The opponent box's 3 pt gold outline flash when they score (s).
  static const double flashStroke = 3;
  static const double flashLength = .45;
  static const Color gold = Color(0xFFFFB529);

  /// §5.7 Name chips: y 92, 90 × 22, white, plum Fredoka SemiBold 15 pt.
  static const double chipTop = 92;
  static const double chipHeight = 22;
  static const double chipFont = 15;

  /// PRD-2.3 §21.2 a name tag shrinks to fit its room down to 70 % of its
  /// normal size, then it is cut with "…" (`fitName`).
  static const double nameMinScale = .7;

  /// PRD-2.3 §21.2 the padding on each side of a name chip's text (pt).
  /// S8-08: 2 (was 4), so with [chipNameSize] every generated nickname
  /// (the longest: 14 letters + 3 digits) fits at 70 % with its digits.
  static const double chipPad = 2;

  /// PRD-2.3 §21.2 (S8-08) a name chip's normal name size (pt) and letter
  /// spacing (em): 14 / 0 (§5.7 was 15 / .02, which cut the digits of the
  /// longest generated nicknames even at 70 %). The VS label keeps
  /// [chipFont].
  static const double chipNameSize = 14;
  static const double chipNameSpacing = 0;
  static const Color plum = Color(0xFF7A0044);
  static const String nameFont = 'Fredoka';

  /// §5.26–§5.28 / §3.0.9 #7 (S6-F03 call): the collectables' HUD badges
  /// (egg ×2 pill, piggy, jar) are drawn this far ABOVE the mock's spot
  /// (mock y ≈ 195–242), whose band is the banner band (y 190 → ≈ 249 with
  /// a subtitle) that shows on every perfect pass and with each badge's own
  /// announcement ("PIGGY BANK", "FIREFLY JAR", "HATCHED!"). Lifted, they
  /// keep the approved art and layout in the free strip between the name
  /// chips (end y 114) and the §5.29 timer pill (top y 156) — the same
  /// "move it clear of the band" call as the timer pill (y 156) and the
  /// collect tray (y 288, ARCH §27).
  static const double collectLift = 86;

  /// §5.7 VS label between the boxes (x 150 → 170), same font and size.
  static const double vsLeft = 150;
  static const double vsWidth = 20;

  /// §5.7 Pause button: right edge 306, 38 × 38, pink, two soft bars.
  static const double pauseRight = 306;
  static const Color pink = Color(0xFFEC008C);

  /// §5.7 The two-bar icon (20 pt box of the 24-unit glyph).
  static const double pauseIcon = 20;

  /// §5.7 Tap targets are at least this big (pt).
  static const double minTarget = 48;

  /// §5.7 The row fades in / out with the run (s).
  static const double rowFade = .2;

  // ----------------------------------------------------------- pause card
  /// §5.7 Pause overlay: rgba(20, 20, 30, .62).
  static const Color pauseDim = Color(0x9E14141E);

  /// §5.7 Card: left / right 34, padding 16 / 16 / 18, bg-coloured.
  static const double cardInset = 34;
  static const double cardPad = 16;
  static const double cardPadBottom = 18;

  /// §5.7 Card top's offset from viewHeight / 2 (mock: top 210 at 711).
  static const double cardTopOffset = -145.5;

  /// §5.7 "PAUSED": pink 34 pt, 0.14 em; 14 pt gap below.
  static const double pausedSize = 34;
  static const double pausedSpacing = .14;
  static const double pausedGap = 14;
  static const String pausedText = 'PAUSED';

  /// §5.7 RESUME: gold, 56 tall, plum 28 pt, 0.1 em.
  static const double resumeHeight = 56;
  static const double resumeSize = 28;
  static const double resumeSpacing = .1;
  static const String resumeText = 'RESUME';

  /// §5.7 Sound / settings row: 10 pt below RESUME, 46 tall, gap 8.
  static const double rowGap = 10;
  static const double smallHeight = 46;
  static const double smallGap = 8;

  /// §5.7 Icons on the small buttons (pt).
  static const double smallIcon = 24;

  /// §5.7 The pause card fades in (s).
  static const double cardFade = .15;
}
