import 'dart:ui';

import 'tuning_values.dart';

/// Revive offer, price ladder and phoenix rise knobs (PRD-2 §3.14, §5.9;
/// mock `design/menu_v2/screen_revive4.html`, 320 × 711). Positions are
/// screen points; "centre offset" values are relative to viewHeight / 2
/// (§3.0.1 R-3.0.1-15: centred blocks keep their offset from the centre).
abstract final class ReviveConfig {
  // ------------------------------------------------------------- the rule
  /// §3.14 The offer needs at least this many hoops passed (gifts don't
  /// count, ride hoops do); ≤ 5 → no offer and no ladder step
  /// (`revive_min_hoops`).
  static int get minHoops => TuningValues.current.i('revive_min_hoops');

  // ----------------------------------------------------------- the ladder
  /// §3.14 The coin steps after the ad step. PRD-2.3 §14.2: 250, 500,
  /// 1000, 2000, 4000, 8000 (`revive_ladder`); after the last one there is
  /// no more revive that run (7 at most with the ad one; was: doubling, no
  /// cap).
  static List<int> get coinLadder => TuningValues.current.ints('revive_ladder');

  /// §3.14 The first coin step (2nd revive, or the 1st without an ad).
  static int get firstCoinPrice => coinLadder.first;

  // ------------------------------------------------------------ countdown
  /// §3.14 / §5.9 The heart drains from the top over this many seconds.
  static const double offerSeconds = 5;

  /// §3.14 The empty heart's hold (2.1). PRD-2.2 §7.15: the offer never
  /// times out any more; kept only as a reference span for tests.
  static const double emptyHold = 1;

  /// §5.9 Urgency (shake, faster beat, red edge glow) starts here (s).
  static const double urgencyStart = 3;

  /// §5.9 Urgency rise length (smoothstep, s).
  static const double urgencyRise = 1.4;

  /// §5.9 Urgency eases out between 4.6 s and 5.5 s.
  static const double urgencyOutStart = 4.6;

  /// §5.9 Urgency ease-out length (s).
  static const double urgencyOutLength = .9;

  /// §5.9 Urgency shake amplitude (±pt).
  static const double shakeAmplitude = 5;

  /// §5.9 Urgency shake frequency (Hz).
  static const double shakeHz = 9;

  /// §5.9 Heartbeat rate at the start of the urgency (Hz).
  static const double beatHzFrom = 1.2;

  /// §5.9 Heartbeat rate at the peak of the urgency (Hz).
  static const double beatHzTo = 3;

  /// §5.9 Heartbeat rate rise length (s).
  static const double beatRise = 1.6;

  /// §5.9 Urgent heartbeat: the peak scale above 1 (1.06).
  static const double beatAmplitude = .06;

  /// §5.9 Idle beat rate (Hz) before the urgency.
  static const double idleBeatHz = 1.25;

  /// §5.9 Idle beat scale: the peak scale above 1 (1.035).
  static const double idleBeatScale = .035;

  /// §5.9 Red edge glow fade-in length after [urgencyStart] (s).
  static const double glowIn = .6;

  /// §5.9 Red edge glow fade-out start (s).
  static const double glowOutStart = 4.8;

  /// §5.9 Red edge glow fade-out length (s).
  static const double glowOutLength = .8;

  /// PRD-2.2 §7.15 the red edge glow's steady level while the empty heart
  /// waits (fraction of the peak; the offer never times out).
  static const double waitGlow = .35;

  // ---------------------------------------------------------------- layout
  /// §5.9 Dark overlay over the frozen game.
  static const double dim = .62;

  /// §5.9 Overlay colour (black).
  static const Color dimColor = Color(0xFF000000);

  /// §5.9 Heart box left (pt).
  static const double heartLeft = 47;

  /// §5.9 Heart box width (pt).
  static const double heartWidth = 226;

  /// §5.9 Heart box height (pt).
  static const double heartHeight = 207;

  /// §5.9 Heart box centre's offset from viewHeight / 2 (mock: top 222 at
  /// 711 → centre 325.5 = 355.5 − 30).
  static const double heartCentreOffset = -30;

  /// §5.9 Heart border width in heart-path units (the 22 × 20.5 box).
  static const double heartStroke = 1.5;

  /// §5.9 Empty heart fill: 20 % soft pink.
  static const Color emptyFill = Color(0x33FCD9EE);

  /// §5.9 Empty heart border.
  static const Color emptyBorder = Color(0xFFFCD9EE);

  /// §5.9 Ad heart fill / border.
  static const Color adFill = Color(0xFFEC008C);
  static const Color adBorder = Color(0xFFFCD9EE);

  /// §5.9 Coin heart fill / border.
  static const Color coinFill = Color(0xFFFFB529);
  static const Color coinBorder = Color(0xFFFFE7A3);

  /// §5.9 Locked heart fill / border.
  static const Color lockFill = Color(0xFF8A8A8A);
  static const Color lockBorder = Color(0xFFC9C9C9);

  /// §5.9 Plum (coin heart text, balance pill, GET COINS text).
  static const Color plum = Color(0xFF7A0044);

  /// §5.9 Soft pink (balance number).
  static const Color soft = Color(0xFFFCD9EE);

  /// §5.9 Gold (GET COINS button).
  static const Color gold = Color(0xFFFFB529);

  /// §5.9 Ad heart: video icon size (pt) and its top above the centre.
  static const double videoIconSize = 30;
  static const double videoIconTop = -47;

  /// §5.9 Ad heart "REVIVE" size (pt) and letter spacing (em).
  static const double adReviveSize = 36;
  static const double adReviveSpacing = .08;

  /// §5.9 Coin heart "REVIVE" size, spacing, top offset from the centre.
  static const double coinReviveSize = 24;
  static const double coinReviveSpacing = .1;
  static const double coinReviveTop = -52;

  /// §5.9 Coin heart price size (pt), coin icon size (pt), row top offset.
  static const double priceSize = 40;
  static const double priceCoinSize = 34;
  static const double priceTop = -18;

  /// §5.9 Locked: "🔒 REVIVE" 22 pt, price 36 pt + 30 pt coin, "need N
  /// more" 13 pt (90 %); top offsets from the centre.
  static const double lockReviveSize = 22;
  static const double lockPriceSize = 36;
  static const double lockCoinSize = 30;
  static const double lockPriceTop = -20;
  static const double needSize = 13;
  static const double needTop = 24;

  /// §5.9 "NO AD AVAILABLE": 13 pt, 0.1 em, white 80 %, 34 pt above the
  /// heart.
  static const double noAdSize = 13;
  static const double noAdGap = 34;
  static const String noAdText = 'NO AD AVAILABLE';

  /// §5.9 GET COINS ›: 16 pt plum on gold, 0.1 em, padding 7 × 16, 22 pt
  /// under the heart.
  static const double getCoinsSize = 16;
  static const double getCoinsGap = 22;
  static const double getCoinsPadX = 16;
  static const double getCoinsPadY = 7;
  static const String getCoinsText = 'GET COINS ›';

  /// §5.9 No thanks: white 75 %, 18 pt, 0.06 em, 86 pt under the heart.
  static const double noThanksSize = 18;
  static const double noThanksGap = 86;
  static const String noThanksText = 'No thanks';

  /// §5.9 Balance pill: right edge 306, top 58, 38 tall, padding 10, 22 pt
  /// number + 24 pt coin, gap 8.
  static const double pillRight = 306;
  static const double pillTop = 58;
  static const double pillHeight = 38;
  static const double pillPad = 10;
  static const double pillFont = 22;
  static const double pillCoin = 24;

  /// §5.9 The heart is one tap target, at least 48 pt around it.
  static const double minTarget = 48;

  // ------------------------------------------------------------- tap → pay
  /// §5.9 Heart pop 1 → 1.12 → 0.92 (s).
  static const double popLength = .26;

  /// §5.9 The offer fades out over this (s).
  static const double fadeOut = .25;

  /// §5.9 Ad: the offer starts fading this long after the tap (s).
  static const double adHideDelay = .22;

  /// §5.9 Coins: 10 coins fly from the pill into the heart, 0.5 s each,
  /// 0.05 s apart.
  static const int payCoins = 10;
  static const double payCoinLength = .5;
  static const double payCoinStagger = .05;

  /// §5.9 Coins: the balance counts down over this (s).
  static const double countDown = .7;

  /// §5.9 Coins: the pill squeezes to this scale (0.3 s).
  static const double pillSqueeze = .9;

  /// §5.9 Coins: the heart flashes brighter at this moment for 0.3 s.
  static const double payFlashAt = .75;
  static const double payFlashLength = .3;

  /// §5.9 Coins: the offer fades out at this moment after the tap (s).
  static const double payHideAt = 1.01;

  /// §5.9 The phoenix starts this long after the offer has gone (s).
  static const double phoenixDelay = .2;

  /// §5.9 Locked: the heart shakes ±9 pt over 0.32 s; GET COINS bumps 1.15.
  static const double lockShake = 9;
  static const double lockShakeLength = .32;
  static const double getCoinsBump = 1.15;
  static const double getCoinsBumpLength = .4;

  /// §3.14 GET COINS: the music plays at × 0.5 while the Shop is open.
  static const double shopMusicDuck = .5;

  // ---------------------------------------------------------- phoenix rise
  /// §5.9 The whole phoenix (s): the world scrolls again here.
  static const double phoenixLength = 1.65;

  /// §5.9 Ignite phase end (flames, tremble) (s).
  static const double igniteEnd = .5;

  /// §5.9 Rise end = burst moment (s).
  static const double burstAt = 1.0;

  /// §5.9 Overlay 62 % → 35 % over 0.6 s from the start.
  static const double phoenixDim = .35;
  static const double phoenixDimFade = .6;

  /// §5.9 At 1.65 s the overlay fades 35 % → 0 over 0.3 s.
  static const double endDimFade = .3;

  /// §5.9 Bird tremble while the flames catch (±pt).
  static const double tremble = 1.5;

  /// §5.9 Flame particles: radius 11–19 pt, rising 100–190 pt/s, life
  /// 0.4–0.7 s, ±16 pt spread, ±14 pt/s sideways.
  static const double flameRMin = 11, flameRMax = 19;
  static const double flameVMin = 100, flameVMax = 190;
  static const double flameLifeMin = .4, flameLifeMax = .7;
  static const double flameSpread = 16;

  /// §5.9 Flame colours as they fade: white-yellow → orange → red.
  static const Color flameHot = Color(0xFFFFF0AA);
  static const Color flameMid = Color(0xFFFF9628);
  static const Color flameCool = Color(0xFFE63C14);

  /// §5.9 Flame wings: 6 orange-gold blades per side, up to ≈ 107 pt.
  static const int wingBlades = 6;
  static const double wingBase = 62;
  static const double wingStep = 9;

  /// §5.9 The bird's gold glow while rising (blur, pt).
  static const double glowFrom = 20;
  static const double glowTo = 40;
  static const Color glowColor = Color(0xFFFFB529);

  /// §5.9 Burst: warm flash `#FFF3C4` 0.9 → 0 in 0.42 s.
  static const Color flashColor = Color(0xFFFFF3C4);
  static const double flashAlpha = .9;
  static const double flashLength = .42;

  /// §5.9 Burst: gold shockwave ring radius 20 → 170 pt in 0.45 s.
  static const double shockFrom = 20;
  static const double shockTo = 170;
  static const double shockLength = .45;
  static const Color shockColor = Color(0xFFFFDC78);

  /// §5.9 Burst: 34 gold feathers and 46 embers.
  static const int feathers = 34;
  static const int embers = 46;

  /// §5.9 Hover after the burst: ±4 pt bob, a wing flap every 0.2 s.
  static const double hoverBob = 4;
  static const double hoverFlapPeriod = .2;

  /// §3.14 The bird is invulnerable this long after the phoenix (s).
  static const double invulnerable = 2;

  /// §3.14 Safe line: kept this far inside the tooth lines (pt, beyond the
  /// bird radius).
  static const double safeMargin = 10;

  /// §3.14 / §3.17 A running squeeze slides open over this (s).
  static const double squeezeOpen = .5;
}
