import 'dart:math' show max, min;

import 'package:flame/extensions.dart';

/// All gameplay constants from SPEC.md, in logical points on the original
/// 320x568 iPhone canvas (1 point = 1 Forge2D world unit).
class Config {
  Config._();

  // Virtual resolution. The playfield is always 320 pt wide; its height is
  // the screen aspect's height, clamped to [minViewHeight, maxViewHeight]
  // (568 = the original design height; 730 ~ a bit beyond 20:9 phones).
  static const double worldWidth = 320;
  static const double worldHeight = 568; // design/default height
  static const double minViewHeight = 568;
  static const double maxViewHeight = 730;

  // Physics (Flappy Bird feel; an intentional, user-requested deviation from
  // the 2014 original's 1350/525 — see SPEC.md): a modest flap pop whose rise
  // is about half the final pipe gap, plus a terminal fall speed so dives
  // stay recoverable.
  static const double gravity = 1250; // pt/s^2 downward
  static const double flapVelocity = 370; // pt/s upward delta-v:
  // rise = v^2 / (2 * g) = 370^2 / 2500 ~= 55 pt (continuous, 60 fps alike)
  static const double maxFallSpeed = 500; // pt/s terminal velocity (downward)
  static const double scrollSpeed = 200; // pt/s leftward

  /// Longest simulation step in one frame. [FlappySpikesGame.update] clamps
  /// the frame's dt ONCE, so physics, the pipe spawner, fades, the colour
  /// crossfade and every component update share one clock: a stalled frame
  /// (app resumed from the background, debugger pause, the rewarded-ad
  /// wait) neither teleports the bird through pipes or into the spikes nor
  /// spawns overlapping pipe pairs — the whole game slows instead. 1/30 s
  /// still covers 30 fps devices without slowing them down.
  static const double maxFrameStep = 1 / 30;

  // Collision categories (mirror the original bitmasks).
  static const int categoryBird = 0x1;
  static const int categoryWorld = 0x2;
  static const int categoryPipe = 0x4;
  static const int categoryScore = 0x8;

  // Bird.
  static const double birdX = 80; // width / 4
  static const double birdY = 284; // vertical center
  static final Vector2 birdSize = Vector2(46.5, 29.5);
  static const double birdRadius = 14.75; // sprite height / 2
  static const double idleFrameTime = 0.5;
  static const double flapFrameTime = 0.2;

  /// Points per art unit for the 2.0 look art ([LookPainter]'s 44 x 36 art
  /// box): the 30-unit art body square matches the 1.0 bird height
  /// (2 * [birdRadius] = 29.5), so the hitbox and physics stay untouched.
  static const double lookScale = 2 * birdRadius / 30; // 29.5 / 30
  static const double deathSpin = 5 * 3.141592653589793; // 5pi rad over 1 s
  static const double deathRestitution = 0.1;
  static final Vector2 deathVelocity = Vector2(120, -360);

  // Spike strips.
  static const double spikeHeight = 72;
  static const double spikeTileWidth = 384;

  // Pipes.
  static const double pipeWidth = 88;
  static const double pipeHeight = 513.5;
  static const double pipeGapStart = 145; // gap at score 0 (easy onboarding)
  static const double pipeGap = 105; // final/min gap once fully ramped
  static const int difficultyRampScore = 25; // score where the gap bottoms out
  // Random gap bonus: 50 pt at score 0 tapering to 20 pt once ramped (raised
  // from 25/10 on user request 2026-07-22 — "at least 2x, more dynamic").
  static const double gapVarianceStart = 50; // random gap bonus at score 0
  static const double gapVarianceEnd = 20; // bonus once fully ramped
  static const double pipeSpawnInterval = 1.5;
  static const double pipeSpawnX = worldWidth + pipeWidth / 2; // 320 + 44
  static const double gapBottomMin = 202; // 72 + 130: every draw leaves a
  // >= 130 pt flyable window below the ceiling spikes — and from gap 130
  // down the gap can never tuck under the ceiling at all (the original's
  // 112 could leave a nearly unflyable 40 pt window)
  static const double gapBottomMax = 371; // 568 - 72 - 105 - 20 (final gap)
  static const double maxGapJump = 140; // max vertical jump of the gap
  // between consecutive pipes — keeps every transition flyable
  static const double sensorOffsetX = 111; // right of pipe center

  /// Minimum visible length of each pipe stub (top and bottom) for any
  /// spawned gap: 20 pt still clearly shows the pipe and its cap rim, so "a
  /// pipe is always visible" holds while leaving room for the 2x variance.
  /// (Was 40 pt before the 2026-07-22 variance increase.)
  static const double minPipeStub = 20;

  /// Pipe gap for a given score: [pipeGapStart] at 0, shrinking linearly to
  /// [pipeGap] once the score reaches [difficultyRampScore].
  static double gapForScore(int score) {
    final t = score.clamp(0, difficultyRampScore) / difficultyRampScore;
    return pipeGapStart + (pipeGap - pipeGapStart) * t;
  }

  /// Random gap variance for a given score: [gapVarianceStart] at 0,
  /// tapering linearly to [gapVarianceEnd] once the score reaches
  /// [difficultyRampScore] (the same ramp schedule as [gapForScore]).
  static double gapVarianceForScore(int score) {
    final t = score.clamp(0, difficultyRampScore) / difficultyRampScore;
    return gapVarianceStart + (gapVarianceEnd - gapVarianceStart) * t;
  }

  /// Gap for one spawned pipe: [gapForScore] plus a random bonus of up to
  /// [gapVarianceForScore] on top ([rng01] in [0, 1]) — the curve value
  /// stays the MINIMUM gap — capped at [maxGapFor] so both pipe stubs stay
  /// >= [minPipeStub].
  static double gapForPipe(
    int score,
    double rng01, [
    double viewHeight = worldHeight,
  ]) {
    final gap =
        gapForScore(score) + rng01.clamp(0.0, 1.0) * gapVarianceForScore(score);
    return min(gap, maxGapFor(viewHeight));
  }

  /// Largest gap where both pipe stubs can still be >= [minPipeStub] at a
  /// given playfield height (192 at 568, 273 at 730).
  static double maxGapFor(double viewHeight) =>
      (viewHeight - 2 * (spikeHeight + minPipeStub)) / 2;

  /// Lowest allowed gap-bottom y (top edge of the bottom pipe) for a given
  /// gap: [gapBottomMin], or gap + spikeHeight + [minPipeStub] when that is
  /// higher. Guarantees the TOP pipe stub is always >= [minPipeStub] — a
  /// pipe is always visible, never fully hidden behind the ceiling spikes.
  static double gapBottomMinFor(double gap) =>
      max(gapBottomMin, gap + spikeHeight + minPipeStub);

  /// Highest allowed gap-bottom y (top edge of the bottom pipe) for a given
  /// gap and playfield height: keeps [minPipeStub] clearance between the
  /// bottom pipe and the ground spikes.
  static double gapBottomMaxFor(
    double gap, [
    double viewHeight = worldHeight,
  ]) => viewHeight - spikeHeight - gap - minPipeStub;

  // UI sizes.
  static final Vector2 titleSize = Vector2(274.5, 147.5);
  static final Vector2 pointsfieldSize = Vector2(241.5, 82);
  static final Vector2 buttonSize = Vector2(241.5, 38.5);
  static final Vector2 settingsButtonSize = Vector2(30, 30);
  static final Vector2 gameCenterButtonSize = Vector2(30, 30);
  static final Vector2 gameCenterGameoverButtonSize = Vector2(60, 60);
  static final Vector2 scoreCircleSize = Vector2(183, 183);

  // Privacy policy, hosted on GitHub Pages (docs/index.html; see
  // SUBMISSION.md). Linked from the start scene and both store listings.
  static const String privacyPolicyUrl =
      'https://hiesem.github.io/flappy_spikes/';

  // Store listing shared by the home Invite tile (PRD-1 §3.4).
  static const String storeListingUrl =
      'https://play.google.com/store/apps/details?id=com.flappyspikes.flappy_spikes';

  // UI positions. The helpers take the playfield center Y (viewHeight / 2)
  // and reproduce the original 320x568 layout exactly at centerY = 284
  // (SpriteKit y-up coordinates from SPEC converted to Flame's y-down).
  static Vector2 titlePositionFor(double centerY) =>
      Vector2(160, centerY - 147.5 / 2 - 35); // 175.25 at 284
  static Vector2 bestLabelPositionFor(double centerY) =>
      Vector2(160, centerY + 120); // 404 at 284
  static Vector2 gamesLabelPositionFor(double centerY) =>
      Vector2(160, centerY + 150); // 434 at 284
  static Vector2 settingsButtonPositionFor(double centerY) =>
      Vector2(160, centerY); // screen center
  static Vector2 scoreHudPositionFor(double centerY) =>
      Vector2(160, centerY + 35); // 319 at 284
  static Vector2 pointsfieldPositionFor(double centerY) =>
      Vector2(160, centerY - 41); // 243 at 284
  static Vector2 replayButtonPositionFor(double centerY) =>
      Vector2(160, centerY + 19.25 + 6); // 309.25 at 284
  static Vector2 shareButtonPositionFor(double centerY) =>
      Vector2(160, centerY + 3 * 19.25 + 12); // 353.75 at 284
  // Leaderboard buttons (positions from the 2014 original,
  // FlappySpikes/Flappy Spikes/GameScene.m): on the start scene at 3/4 width,
  // screen middle; on the game-over scene at the right side of the points
  // field, vertically centered on it.
  static Vector2 gameCenterButtonPositionFor(double centerY) =>
      Vector2(240, centerY); // (240, 284) at 284
  static Vector2 gameCenterGameoverButtonPositionFor(double centerY) =>
      Vector2(240.5, centerY - 41); // (240.5, 243) at 284
  // Privacy-policy link at the bottom of the start scene, just above the
  // ground spikes.
  static Vector2 privacyLinkPositionFor(double centerY) =>
      Vector2(160, 2 * centerY - spikeHeight - 20); // 476 at 284
  // Transient service-failure message (ServiceMessage): bottom-center, the
  // same free band the privacy link used before it moved into settings —
  // visible on both the start and game-over scenes.
  static Vector2 serviceMessagePositionFor(double centerY) =>
      Vector2(160, 2 * centerY - spikeHeight - 20); // 476 at 284

  // Game-over coin line ("+N" + coin, PRD-1 §4.2): below the games label,
  // in the free band above the ground spikes (466 at 284).
  static Vector2 coinsEarnedPositionFor(double centerY) =>
      Vector2(160, centerY + 182);
  static const double coinsEarnedFontSize = 22;
  static const double coinsEarnedIconSize = 18;

  // Fixed positions at the design height (kept for tests and defaults).
  static final Vector2 titlePosition = titlePositionFor(284);
  static final Vector2 bestLabelPosition = bestLabelPositionFor(284);
  static final Vector2 gamesLabelPosition = gamesLabelPositionFor(284);
  static final Vector2 settingsButtonPosition = settingsButtonPositionFor(284);
  static final Vector2 scoreHudPosition = scoreHudPositionFor(284);
  static final Vector2 pointsfieldPosition = pointsfieldPositionFor(284);
  static final Vector2 replayButtonPosition = replayButtonPositionFor(284);
  static final Vector2 shareButtonPosition = shareButtonPositionFor(284);
  static final Vector2 gameCenterButtonPosition = gameCenterButtonPositionFor(
    284,
  );
  static final Vector2 gameCenterGameoverButtonPosition =
      gameCenterGameoverButtonPositionFor(284);
  static final Vector2 privacyLinkPosition = privacyLinkPositionFor(284);
  static final Vector2 serviceMessagePosition = serviceMessagePositionFor(284);

  // --- Home screen v3 (PRD-home-v3 §3.1, design/menu_v2/
  // screen_home_final_v2.html = build78 / build77) ---------------------------
  //
  // Rects are in world points at a given playfield height. The §3.1 table is
  // measured at 711 pt and reproduced exactly there. Vertical rule: the top
  // part (top row, title, subtitle, emblem stage) is pinned to the top; the
  // tile row keeps its 711 distance to the bottom edge (compressing a little
  // toward 568); the START + slot block is centred in the band between the
  // emblem's ribbon and the tile row. When that band gets too small (short
  // screens) the emblem stage scales down about its top edge, to at least
  // emblem 0.78 / bird 1.1 (Q-H3), and then the gaps shrink evenly.

  /// Fixed menu chrome colours (not stage-tinted).
  static const Color menuPink = Color(0xFFEC008C);
  static const Color menuPinkDark = Color(0xFFC40073);
  static const Color menuSoft = Color(0xFFFCD9EE);
  static const Color menuGold = Color(0xFFFFB529);
  static const Color menuPlum = Color(0xFF7A0044);

  /// Height at which the PRD table was measured.
  static const double homeReferenceHeight = 711;
  // 2.0 DEVIATION (product owner, 2026-10-04): gear / back button top-left,
  // coin pill top-right. Gear = BEST = Shop tile left edge (14); pill right
  // edge = LAST = No-ads tile right edge (306).
  static const double homeMargin = 14; // gear / BEST / shop tile left edge
  static const double homeRightEdge = worldWidth - homeMargin; // 306 (pill)
  static const double homeTopRowY = 58; // gear + trophy + pill band 58..96
  static const double homeTopRowHeight = 38;

  /// The trophy box (moved from the bottom row into the top row; opens the
  /// Play Games leaderboard) and its 24 pt glyph.
  static const double homeTrophyLeft = 60;
  static const double homeTrophyIconSize = 24;

  static const double homeTitleTop = 104;
  static const double homeTitleFontSize = 34;
  static const double homeSubtitleTop = 142;
  static const double homeSubtitleFontSize = 13;
  static const double homeSubtitleLetterSpacing = 0.14; // em

  /// Emblem + bird stage: 264 x 204 at (28, 148), the plate centre at 52 %
  /// of its height (160, 254); emblem art scale 0.936, bird 1.32 (points
  /// per art unit). Scaled down to [homeStageMinScale] on short screens.
  static const double homeStageTop = 148;
  static const double homeStageWidth = 264;
  static const double homeStageHeight = 204;
  static const double homePlateYFraction = 0.52;
  static const double homeEmblemScale = 0.936;
  static const double homeBirdScale = 1.32;

  /// Smallest stage scale: emblem 0.78 / bird 1.1 (the build76 variation).
  static const double homeStageMinScale = 0.78 / homeEmblemScale;

  /// How far the emblem's ribbon reaches below the plate centre (art units).
  static const double homeEmblemReach = 70;

  /// Smallest gap above / below the START + slot block before the emblem
  /// starts scaling down.
  static const double homeStartMinGap = 24;

  /// BEST / LAST flank columns: 70 wide, label 12 pt (0.18 em, 13 pt line
  /// + 2) over the number 30 pt (0.02 em, 33 pt line), centred on the
  /// plate; BEST gold, LAST stage fg.
  static const double homeFlankWidth = 70;
  static const double homeFlankLabelFontSize = 12;
  static const double homeFlankLabelLetterSpacing = 0.18;
  static const double homeFlankLabelLine = 13;
  static const double homeFlankLabelGap = 2;
  static const double homeFlankNumberFontSize = 30;
  static const double homeFlankNumberLetterSpacing = 0.02;
  static const double homeFlankNumberLine = 33;
  /// A 4+ digit number shrinks to this width: the 70 pt column less the
  /// tips of LEGEND's wings (they reach x 80 / 240).
  static const double homeFlankNumberMaxWidth = 62;
  static const double homeFlankHeight =
      homeFlankLabelLine + homeFlankLabelGap + homeFlankNumberLine; // 48

  /// START 216 x 67 (label 34 pt, play glyph 28, gap 10) and the powerup
  /// slot 216 x 31 4 pt below it (label 17 pt).
  static const double homeStartWidth = 216;
  static const double homeStartHeight = 67;
  static const double homeStartFontSize = 34;
  static const double homeStartIconSize = 28;
  static const double homeSlotHeight = 31;
  static const double homeSlotFontSize = 17;
  static const double homeSlotGap = 4; // START bottom -> slot top
  static const double homeSlotOutline = 3; // bg-coloured outline
  static const double homeStartBlockHeight =
      homeStartHeight + homeSlotGap + homeSlotHeight; // 102
  static const double homeStartLeft = (worldWidth - homeStartWidth) / 2; // 52

  static const int homeTileCount = 4;
  static const double homeTileWidth = 70;
  static const double homeTileHeight = 92;
  static const double homeTileGap = 4;
  static const double homeTileIconSize = 38;
  // Owned No-ads tile: the check glyph (24-unit viewBox, ink ~16 x 12.5)
  // drawn in the icon slot in the same 38 pt box as the crossed-AD icon.
  static const double homeTileCheckSize = homeTileIconSize;

  /// 0 at 568, 1 at 711 (and above).
  static double _homeT(double viewHeight) =>
      ((viewHeight - minViewHeight) / (homeReferenceHeight - minViewHeight))
          .clamp(0.0, 1.0);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Top of the tile row: 149 pt above the bottom edge at 711 (y 562, 13 pt
  /// above the menu spike tips), 146 at 568 (10 pt above them).
  static double homeTileRowTopFor(double viewHeight) =>
      viewHeight - _lerp(146, 149, _homeT(viewHeight));

  /// Emblem stage scale (1 = the §3.1 size): shrinks when the START block
  /// would get less than [homeStartMinGap] above / below it, down to
  /// [homeStageMinScale].
  static double homeStageScaleFor(double viewHeight) {
    const reach =
        homeStageHeight * homePlateYFraction + homeEmblemReach * homeEmblemScale;
    final room =
        homeTileRowTopFor(viewHeight) -
        2 * homeStartMinGap -
        homeStartBlockHeight -
        homeStageTop;
    return (room / reach).clamp(homeStageMinScale, 1.0);
  }

  /// The emblem + bird stage (tap area) at [viewHeight], centred on x 160.
  static Rect homeStageRectFor(double viewHeight) {
    final k = homeStageScaleFor(viewHeight);
    return Rect.fromLTWH(
      (worldWidth - homeStageWidth * k) / 2,
      homeStageTop,
      homeStageWidth * k,
      homeStageHeight * k,
    );
  }

  /// The emblem plate centre (160, 254 at 711).
  static Offset homePlateCentreFor(double viewHeight) {
    final stage = homeStageRectFor(viewHeight);
    return Offset(
      worldWidth / 2,
      stage.top + stage.height * homePlateYFraction,
    );
  }

  /// Emblem art scale (0.936 at full size, 0.78 at the minimum).
  static double homeEmblemScaleFor(double viewHeight) =>
      homeEmblemScale * homeStageScaleFor(viewHeight);

  /// Bird art scale (1.32 at full size, 1.1 at the minimum).
  static double homeBirdScaleFor(double viewHeight) =>
      homeBirdScale * homeStageScaleFor(viewHeight);

  /// Bottom of the emblem's ribbon (≈ 320 at 711).
  static double homeEmblemBottomFor(double viewHeight) =>
      homePlateCentreFor(viewHeight).dy +
      homeEmblemReach * homeEmblemScaleFor(viewHeight);

  /// Top of the START button: the START + slot block centred between the
  /// emblem bottom and the tile row, on whole points (390 at 711).
  static double homeStartTopFor(double viewHeight) =>
      ((homeEmblemBottomFor(viewHeight) + homeTileRowTopFor(viewHeight)) / 2 -
              homeStartBlockHeight / 2)
          .roundToDouble();

  /// TOP-RIGHT corner of the coin pill: the pill grows leftwards with the
  /// balance, its right edge pinned to [homeRightEdge].
  static Vector2 homeCoinPillPositionFor(double viewHeight) =>
      Vector2(homeRightEdge, homeTopRowY);
  static Rect homeGearRectFor(double viewHeight) => Rect.fromLTWH(
    homeMargin,
    homeTopRowY,
    homeTopRowHeight,
    homeTopRowHeight,
  );
  static Rect homeTrophyRectFor(double viewHeight) => Rect.fromLTWH(
    homeTrophyLeft,
    homeTopRowY,
    homeTopRowHeight,
    homeTopRowHeight,
  );
  // Title / subtitle positions are the TOP-CENTRE of their line boxes.
  static Vector2 homeTitlePositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, homeTitleTop);
  static Vector2 homeSubtitlePositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, homeSubtitleTop);

  /// BEST (left, x 14) / LAST ([right], right edge 306) column, centred
  /// vertically on the plate.
  static Rect homeFlankRectFor(double viewHeight, {required bool right}) =>
      Rect.fromLTWH(
        right ? homeRightEdge - homeFlankWidth : homeMargin,
        homePlateCentreFor(viewHeight).dy - homeFlankHeight / 2,
        homeFlankWidth,
        homeFlankHeight,
      );

  static Rect homeStartRectFor(double viewHeight) => Rect.fromLTWH(
    homeStartLeft,
    homeStartTopFor(viewHeight),
    homeStartWidth,
    homeStartHeight,
  );
  static Rect homeSlotRectFor(double viewHeight) => Rect.fromLTWH(
    homeStartLeft,
    homeStartTopFor(viewHeight) + homeStartHeight + homeSlotGap,
    homeStartWidth,
    homeSlotHeight,
  );

  /// Tile [index] of the row: 0 Shop, 1 Skins, 2 Invite, 3 No ads.
  static Rect homeTileRectFor(double viewHeight, int index) => Rect.fromLTWH(
    homeMargin + index * (homeTileWidth + homeTileGap),
    homeTileRowTopFor(viewHeight),
    homeTileWidth,
    homeTileHeight,
  );

  /// Short-lived toasts on the home screen: centred in the gap between the
  /// powerup slot and the tile row.
  static Vector2 homeToastPositionFor(double viewHeight) {
    final slot = homeSlotRectFor(viewHeight);
    return Vector2(
      worldWidth / 2,
      (slot.bottom + homeTileRowTopFor(viewHeight)) / 2,
    );
  }

  /// Tap on the emblem stage -> LEVELS opens this much later (§3.3), with
  /// a fade + 14 pt rise over [levelsEnterDuration].
  static const double homeEmblemTapDelay = 0.17;
  static const double levelsEnterDuration = 0.22;
  static const double levelsEnterRise = 14;

  /// The home emblem's upgrade pop after a LEVEL UP claim (§4.3): 0.6 ->
  /// 1.15 -> 1 over 0.7 s.
  static const double homeEmblemPopDuration = 0.7;

  /// LEVEL UP trigger (Q-H1 interim): the popup opens once home has been
  /// up, with nothing over it, for this long.
  static const double levelUpSettleDelay = 0.35;

  // --- LEVELS screen (PRD-home-v3 §4.4, build74 `.lvh` / `.lvl`) -----------
  static const double levelsTitleTop = 106;
  static const Rect levelsHeaderRect = Rect.fromLTWH(14, 150, 292, 84);
  static const double levelsHeaderEmblemBox = 84;
  static const double levelsHeaderEmblemScale = 0.34;
  static const double levelsHeaderEmblemY = 44; // plate centre in the box
  static const double levelsHeaderNameFontSize = 20;
  static const double levelsHeaderStatsFontSize = 11;
  static const double levelsBarWidth = 186;
  static const double levelsBarHeight = 16;
  static const double levelsBarFontSize = 10;
  static const double levelsHeaderMix = 0.15; // card: fg 15 % over bg
  static const double levelsListTop = 242;
  static const double levelsListPadTop = 4;
  static const double levelsListPadBottom = 26;
  static const double levelsRowHeight = 72;
  static const double levelsRowGap = 6;
  static const double levelsRowMix = 0.09; // row: fg 9 % over bg
  static const double levelsRowEmblemWidth = 84;
  static const double levelsRowEmblemScale = 0.29;
  static const double levelsRowEmblemY = 37;
  static const double levelsRowNameFontSize = 17;
  static const double levelsRowReachFontSize = 11;
  static const double levelsChipHeight = 28;
  static const double levelsChipTop = 22;
  static const double levelsChipRight = 8;
  static const double levelsChipPad = 9;
  static const double levelsChipFontSize = 15;
  static const double levelsChipCoinSize = 15;
  static const double levelsCurrentOutline = 3;

  /// Bird on an emblem in the LEVELS header / rows / popup: 1.4 x the
  /// emblem's art scale (build74 `paintEmb`).
  static const double levelsBirdOnEmblem = 1.4;

  /// World y of row [index] (0 = EGG) at scroll 0.
  static double levelsRowTop(int index) =>
      levelsListTop + levelsListPadTop + index * (levelsRowHeight + levelsRowGap);

  // --- LEVEL UP popup (PRD-home-v3 §4.3, build74 `.pcard`) ------------------
  static const double levelUpCardWidth = 280;
  static const double levelUpHeaderHeight = 178;
  static const double levelUpTitleHeight = 45;
  static const double levelUpTitleFontSize = 22;
  static const double levelUpBodyPadTop = 14;
  static const double levelUpBodyPad = 16;
  static const double levelUpSmallFontSize = 12;
  static const double levelUpNameFontSize = 30;
  static const double levelUpButtonHeight = 50;
  static const double levelUpButtonGap = 14;
  static const double levelUpButtonFontSize = 22;
  static const double levelUpCoinSize = 22;
  static const double levelUpEmblemScale = 0.72;
  static const double levelUpEmblemY = 96; // in the header
  static const double levelUpPopDuration = 0.45;
  static const double levelUpCardPopDuration = 0.26;
  static const double levelUpConfettiDelay = 0.18;
  static const double levelUpCardHeight =
      levelUpHeaderHeight +
      levelUpTitleHeight +
      levelUpBodyPadTop +
      levelUpSmallFontSize * 1.284 +
      2 +
      levelUpNameFontSize * 1.284 +
      4 +
      levelUpSmallFontSize * 1.284 +
      levelUpButtonGap +
      levelUpButtonHeight +
      levelUpBodyPad; // ≈ 392

  /// The card, centred on the screen (x 20 -> 300).
  static Rect levelUpCardRectFor(double viewHeight) => Rect.fromLTWH(
    (worldWidth - levelUpCardWidth) / 2,
    (viewHeight - levelUpCardHeight) / 2,
    levelUpCardWidth,
    levelUpCardHeight,
  );

  /// Menus show the spike strips 28 pt shorter (44 pt, as in the approved
  /// mocks); they slide to their full 72 pt when a run starts. Visual only:
  /// the strips' physics bodies never move.
  static const double menuSpikeInset = 28;

  /// Skin tint during runs at stages >= 5: lerp(mockColor, stageFg, this).
  /// 0 in menus and at stage 0 (identity colours, as mocked).
  static const double skinStageBlend = 0.35;

  /// Height of the menus' short spike strips (spike tips 44 pt from the
  /// edge).
  static const double menuSpikeHeight = spikeHeight - menuSpikeInset; // 44

  // --- Shared menu-screen chrome (Shop, Skins; PRD-1 §5) --------------------
  //
  // Back button top-left in the gear's place, coin pill top-right (as on
  // home; [menuScreenPillPositionFor] is its top-right corner), title
  // centred at the top; the content scrolls in the band between the title
  // and the bottom spike tips. Everything is pinned to the top.

  static Vector2 menuScreenPillPositionFor(double viewHeight) =>
      homeCoinPillPositionFor(viewHeight);
  static Rect menuScreenBackRectFor(double viewHeight) =>
      homeGearRectFor(viewHeight);
  static const double menuScreenTitleTop = 104;
  static const double menuScreenTitleFontSize = 30;
  static const double menuScreenTitleLetterSpacing = 0.06; // em
  // Top-centre of the title's line box.
  static Vector2 menuScreenTitlePositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, menuScreenTitleTop);

  /// Scrolling content viewport: from just below the title's line box
  /// (104 + 30 x 1.284) to the bottom spike tips.
  static double menuScreenContentTopFor(double viewHeight) => 143;
  static double menuScreenContentBottomFor(double viewHeight) =>
      viewHeight - menuSpikeHeight;

  /// Toasts over a menu screen (Shop, Skins, Settings): a chip centred in
  /// the band just above the bottom spike tips (643 at 711).
  static Vector2 menuScreenToastPositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, viewHeight - menuSpikeHeight - 24);

  /// Card behind content blocks (packs, featured row): the stage foreground
  /// at this opacity over the background (mock `color-mix(fg 14%, bg)`).
  static const double menuCardMix = 0.14;

  // --- Menu list momentum scrolling (product decision 2026-10-07) ----------
  //
  // Every menu scroll list (skin shop grid, Shop, LEVELS, any
  // [MenuScrollArea]) flings after a release, rubber-bands past its edges and
  // springs back. Physics lives here so the feel is tunable in one place.

  /// Fraction of the release velocity kept per second while flinging
  /// (`v(t) = v0 * pow(menuScrollFlingDecay, t)`). A quick ~2000 pt/s flick
  /// travels ~1.3 viewports before it stops.
  static const double menuScrollFlingDecay = 0.07;

  /// A release slower than this (pt/s) does not fling.
  static const double menuScrollMinFlingVelocity = 40;

  /// Flings are capped at this initial speed (pt/s).
  static const double menuScrollMaxFlingVelocity = 4000;

  /// The glide stops below this speed (pt/s).
  static const double menuScrollRestVelocity = 6;

  /// Drag slop (world pt): a press that travels further than this is a
  /// scroll, never a tap: the drag wins the gesture arena, so every pressed
  /// tile / button cancels (QA S1-50). Flutter's default (18 logical px) is
  /// replaced by this, converted to logical px at the current camera scale,
  /// while a [MenuScrollArea] is mounted.
  static const double menuScrollSlop = 6;

  /// Release velocity = average of the drag samples of the last this many
  /// seconds (older samples are stale and ignored).
  static const double menuScrollVelocityWindow = 0.07;

  /// Rubber band: the displayed overshoot asymptotes at this share of the
  /// viewport height, so dragging further gets ever more resistance.
  static const double menuScrollRubber = 0.18;

  /// Critically damped spring back to an edge (~0.35 s to settle).
  static const double menuScrollSpringOmega = 19;
  static const double menuScrollSpringRestDistance = 1; // pt
  static const double menuScrollSpringRestVelocity = 20; // pt/s
  static const double menuScrollSpringMaxDuration = 1.0; // s

  // --- Shop (PRD-1 §5.2, design S1-B; content coordinates = world
  // coordinates before scrolling, measured at 711 and top-pinned) ---------

  static const double shopRowWidth = homeRightEdge - homeMargin; // 292
  static Rect shopBannerRectFor(double viewHeight) =>
      const Rect.fromLTWH(homeMargin, 146, shopRowWidth, 52);
  static Rect shopFreeCoinsRectFor(double viewHeight) =>
      const Rect.fromLTWH(homeMargin, 206, shopRowWidth, 44);

  static const double shopPackWidth = 142;
  static const double shopPackHeight = 150;
  static const double shopPackGap = 8; // 14 + 142 + 8 = 164
  static const double shopPackRowTop = 266;
  static const double shopPackRowStep = 160; // 266 -> 426

  /// Coin pack card [index] (0 = 500, 1 = 1,800, 2 = 5,000, 3 = 12,000), in
  /// a 2 x 2 grid.
  static Rect shopPackRectFor(double viewHeight, int index) => Rect.fromLTWH(
    homeMargin + (index % 2) * (shopPackWidth + shopPackGap),
    shopPackRowTop + (index ~/ 2) * shopPackRowStep,
    shopPackWidth,
    shopPackHeight,
  );

  /// Inside a pack card: the coin stack's bottom edge, the amount's line
  /// box top and the price button height (mock flex column, 26 pt top
  /// padding, 56 pt art box, space-between).
  static const double shopPackArtBottom = 78;
  static const double shopPackAmountTop = 82.875;
  static const double shopPackPriceHeight = 38;
  // Gold flap tag centred on the card's top edge.
  static const double shopPackTagHeight = 24;
  static const double shopPackTagPadX = 10;

  static Rect shopFeaturedRectFor(double viewHeight) =>
      const Rect.fromLTWH(homeMargin, 588, shopRowWidth, 56);

  /// Bottom of the scrollable content (22 pt below the featured row, where
  /// the restore link ended before PRD-home-v3 §9 moved it to Settings):
  /// fits the 667 pt viewport at 711 without scrolling.
  static double shopContentBottomFor(double viewHeight) => 666;

  /// Content y the "+" of the coin pill scrolls to the top of the viewport:
  /// just above the first row of packs' flap tags.
  static double shopCoinsAnchorFor(double viewHeight) =>
      shopPackRowTop - shopPackTagHeight / 2 - 8;

  /// How long a restore may stay silent before "Nothing to restore".
  static const double restoreTimeout = 4;

  // --- Skin shop (PRD-menu-v2 §4.1, layout A; world coordinates measured at
  // 711 and top-pinned — only the grid's bottom follows the view height) ----

  /// Collection bar ("owned / 88") under the coin pill.
  static const Rect skinShopBarRect = Rect.fromLTWH(70, 100, 180, 18);
  static const double skinShopBarFontSize = 12;
  static const double skinShopBarLetterSpacing = 0.08; // em
  static const double skinShopBarPopScale = 1.12;
  static const double skinShopBarPopDelay = 0.5;
  static const double skinShopBarPopDuration = 0.4;
  static const double skinShopBarFillDelay = 0.4;
  static const double skinShopBarFillDuration = 0.6;

  /// Live preview stage: background = fg at [skinShopStageMix] over bg.
  static const Rect skinShopStageRect = Rect.fromLTWH(14, 126, 292, 138);
  static const double skinShopStageMix = 0.09;
  static const double skinShopBirdScale = 1.9;
  static const double skinShopBirdX = 0.42; // share of the stage width
  static const double skinShopBobAmplitude = 3;
  static const double skinShopBobSpeed = 3.2; // rad/s
  static const double skinShopHopKick = 150; // pt/s upwards
  static const double skinShopHopGravity = 900; // pt/s²
  static const double skinShopHoopInterval = 2.3;
  static const double skinShopHoopFirst = 0.8;
  static const double skinShopHoopSpeed = 120; // pt/s
  static const double skinShopHoopRy = 26; // art units (x bird scale)
  static const double skinShopFireAfterPass = 1.7;
  static const double skinShopTrailScroll = -150; // emitter vx

  /// Name row (inside the stage, 8 / 7 from its top-left) and the action
  /// button (8 / 8 from its bottom-right).
  static const double skinShopNameLeft = 8;
  static const double skinShopNameTop = 7;
  static const double skinShopNameFontSize = 14;
  static const double skinShopChipFontSize = 9;
  static const double skinShopActionInset = 8;
  static const double skinShopActionHeight = 30;
  static const double skinShopActionFontSize = 13;
  static const double skinShopActionPulse = 1.06;
  static const Color skinShopPoorGrey = Color(0xFFA0A0A0);

  /// Tab bar: 5 equal tabs, 3 pt underline sliding 0.3 s with overshoot.
  static const Rect skinShopTabBarRect = Rect.fromLTWH(14, 270, 292, 52);
  static const double skinShopTabIconWidth = 30;
  static const double skinShopTabIconHeight = 24;
  static const double skinShopTabFontSize = 9;
  static const double skinShopTabUnderline = 3;
  static const double skinShopTabSlideDuration = 0.3;
  static const double skinShopTabIconActiveScale = 1.18;

  /// Item grid: 3 columns of 92 x 92 tiles, 8 pt gaps, 6 pt top / 30 pt
  /// bottom padding, from y 326 down to 44 pt above the bottom edge (667
  /// at 711).
  static const int skinShopColumns = 3;
  static const double skinShopGridLeft = homeMargin;
  static const double skinShopGridTop = 326;
  static const double skinShopGridWidth = 292;
  static const double skinShopTile = 92;
  static const double skinShopTileGap = 8;
  static const double skinShopGridPadTop = 6;
  static const double skinShopGridPadBottom = 30;
  static double skinShopGridBottomFor(double viewHeight) =>
      viewHeight - menuSpikeHeight;

  /// The scrolling grid viewport.
  static Rect skinShopGridRectFor(double viewHeight) => Rect.fromLTRB(
    skinShopGridLeft,
    skinShopGridTop,
    skinShopGridLeft + skinShopGridWidth,
    skinShopGridBottomFor(viewHeight),
  );

  /// Tile [index] of a tab's grid (content coordinates at scroll 0).
  static Rect skinShopTileRectFor(double viewHeight, int index) =>
      Rect.fromLTWH(
        skinShopGridLeft +
            (index % skinShopColumns) * (skinShopTile + skinShopTileGap),
        skinShopGridTop +
            skinShopGridPadTop +
            (index ~/ skinShopColumns) * (skinShopTile + skinShopTileGap),
        skinShopTile,
        skinShopTile,
      );

  /// Bottom of a grid of [count] tiles, including the bottom padding.
  static double skinShopContentBottomFor(double viewHeight, int count) =>
      skinShopTileRectFor(viewHeight, count - 1).bottom +
      skinShopGridPadBottom;

  // Inside a tile: art in an 84 x 68 box centred on the tile; card = fg at
  // [skinShopTileMix] over bg; locked art at 42 %; lock 13 pt at (6, 5);
  // price pill 8 pt above the bottom; 3 pt equipped / try-on outline; 22 pt
  // check badge; NEW tag 5 pt past the right edge, 6 pt above the top.
  static const double skinShopTileMix = 0.15;
  static const double skinShopArtWidth = 84;
  static const double skinShopArtHeight = 68;
  static const double skinShopLockedOpacity = 0.42;
  static const double skinShopLockSize = 13;
  static const double skinShopLockLeft = 6;
  static const double skinShopLockTop = 5;
  static const double skinShopPriceBottom = 8;
  static const double skinShopPriceFontSize = 12;
  static const double skinShopPriceCoin = 13;
  static const double skinShopOutline = 3;
  static const double skinShopCheckBadge = 22;
  static const double skinShopRarityBar = 4;
  static const double skinShopTagOverhangX = 5;
  static const double skinShopTagOverhangY = 6;
  static const double skinShopTagFontSize = 10;
  static const double skinShopPressScale = 0.93;
  static const double skinShopTryPulse = 0.9; // s per half cycle
  static const double skinShopNewWobble = 1.2;
  static const double skinShopShineLoop = 1.6;

  /// Tab-switch entrance: tiles rise 16 pt and fade in over 240 ms,
  /// staggered 30 ms per column and 40 ms per row.
  static const double skinShopEnterRise = 16;
  static const double skinShopEnterDuration = 0.24;
  static const double skinShopEnterColumnDelay = 0.03;
  static const double skinShopEnterRowDelay = 0.04;

  // --- Live home & Shop (PRD-menu-v2 §8) --------------------------------
  // Effect timings live in components/ui/live_effects.dart (LiveCurves).

  /// Free-coins reward: the pill counts +40 in 0.4 s once the coins have
  /// landed, then `sk_progress` 0.18 s later.
  static const double coinRewardCountDuration = 0.4;
  static const double coinRewardProgressDelay = 0.18;

  /// Coin pill coin pop on a reward (135 % and back in 0.3 s).
  static const double coinPopScale = 1.35;
  static const double coinPopDuration = 0.3;

  // --- Coin reward celebration (PRD-home-v3 §5, build73 / 74 / 79) -------
  /// Each landing pops the pill coin to 125 % (0.18 s).
  static const double coinRewardLandPopScale = 1.25;
  static const double coinRewardLandPopDuration = 0.18;

  /// End of the count: the pill pops 114 % (0.38 s, ease-out) and its coin
  /// spins and pops 150 % / -20° (0.42 s).
  static const double coinRewardPillPopScale = 1.14;
  static const double coinRewardPillPopDuration = 0.38;
  static const double coinRewardSpinPopScale = 1.5;
  static const double coinRewardSpinPopDuration = 0.42;
  static const double coinRewardSpinPopDegrees = -20;

  /// Pill gold glow fade (CSS `transition: box-shadow .25s`).
  static const double coinRewardGlowFade = 0.25;

  /// "+amount" under the pill: gold 26 pt, right edge 8 pt inside the
  /// pill's, top 8 pt below it (mock right 22 / top 104), 1.5 s.
  static const double coinRewardLabelFontSize = 26;
  static const double coinRewardLabelInset = 8;
  static const double coinRewardLabelGap = 8;
  static const double coinRewardLabelDuration = 1.5;

  /// The 12 000 pack's white flash: 75 % -> 0 in 0.5 s.
  static const double coinRewardFlashOpacity = 0.75;
  static const double coinRewardFlashDuration = 0.5;

  /// The Shop's GET button (was WATCH): 112 x 32, camera 20 + "GET" 20 pt
  /// bold (0.9 pt stroke), 0.12 em, gap 9; pulse 1 -> 1.05 with a pink glow
  /// (12 pt blur, #EC008C 45 %).
  static const double shopGetWidth = 112;
  static const double shopGetHeight = 32;
  static const double shopGetFontSize = 20;
  static const double shopGetLetterSpacing = 0.12;
  static const double shopGetStroke = 0.9;
  static const double shopGetIconSize = 20;
  static const double shopGetGap = 9;
  static const double shopGetPulse = 0.05;
  static const Color shopGetGlow = Color.fromRGBO(236, 0, 140, .45);
  static const double shopGetGlowBlur = 12;

  /// Home powerup slot pulse: 1 -> 1.035, gold glow (14 pt blur, #FFB529
  /// 55 %).
  static const double homeSlotPulse = 0.035;
  static const Color homeSlotGlow = Color.fromRGBO(255, 181, 41, .55);
  static const double homeSlotGlowBlur = 14;

  /// Shop price-button light-streak cascade (s): Remove ads, the four
  /// packs in reading order, the featured item.
  static const double shopStreakDelayNoAds = 0;
  static const List<double> shopStreakDelayPacks = [0.7, 1.14, 1.58, 2.02];
  static const double shopStreakDelayFeatured = 2.5;

  /// Purchase feedback: pill count-down, UNLOCKED! banner (top 150,
  /// centred), legendary flash + shake, NOT ENOUGH COINS toast (top 318).
  static const double skinShopCountDuration = 0.6;
  static const double skinShopBannerTop = 150;
  static const double skinShopBannerDuration = 1.9;
  static const double skinShopBannerDurationLegendary = 2.6;
  static const double skinShopFlashDuration = 0.6;
  static const double skinShopShakeDuration = 0.38;
  static const double skinShopToastTop = 318;
  static const double skinShopToastDuration = 1.5;
  static const double skinShopProgressSoundDelay = 0.52;
  static const double skinShopProgressSoundDelayLegendary = 1.3;

  // --- No-ads popup (PRD-1 §5.1, design P1) --------------------------------

  /// Card x 20 -> 300, top 190 at 711; the card stays centred on the same
  /// band at other heights.
  static Rect noAdsCardRectFor(double viewHeight) => Rect.fromLTWH(
    20,
    190 + (viewHeight - homeReferenceHeight) / 2,
    worldWidth - 40,
    noAdsCardHeight,
  );
  static const double noAdsHeaderHeight = 120;
  static const double noAdsCloseSize = 38;
  static const double noAdsTitleFontSize = 22;
  static const double noAdsTitlePad = 8;
  // 22 pt line box + 2 x 8 pt padding; the browser's line box measures
  // 29 pt on popup_p1.png (22 x 1.284 = 28.25 rounded up).
  static const double noAdsTitleHeight = 29 + 2 * noAdsTitlePad; // 45
  static const double noAdsPad = 16;
  static const double noAdsBenefitSize = 44;
  static const double noAdsBenefitGap = 12;
  static const double noAdsPriceGap = 18;
  static const double noAdsPriceHeight = 54;
  static const double noAdsCardHeight =
      noAdsHeaderHeight +
      noAdsTitleHeight +
      noAdsPad +
      2 * noAdsBenefitSize +
      noAdsBenefitGap +
      noAdsPriceGap +
      noAdsPriceHeight +
      noAdsPad; // 369

  /// Toasts while the popup is up: centred below the card.
  static Vector2 noAdsToastPositionFor(double viewHeight) => Vector2(
    worldWidth / 2,
    noAdsCardRectFor(viewHeight).bottom + 32,
  );

  // --- Fake rewarded ad overlay (Linux / desktop debug only) ----------------

  /// Centred card, x 20 -> 300 like the popups.
  static Rect fakeAdCardRectFor(double viewHeight) => Rect.fromLTWH(
    20,
    (viewHeight - fakeAdCardHeight) / 2,
    worldWidth - 40,
    fakeAdCardHeight,
  );
  static const double fakeAdCardHeight = 260;
  static const double fakeAdHeaderHeight = 64;
  static const double fakeAdTitleFontSize = 30;
  static const double fakeAdPlacementFontSize = 13;
  static const double fakeAdCountFontSize = 64;
  static const double fakeAdMessageFontSize = 20;
  static const double fakeAdHintFontSize = 11;

  // --- Settings -------------------------------------------------------------

  /// "RESTORE PURCHASES" link below the privacy link (centre; 510 at 568),
  /// clear of the 44 pt menu spike strip.
  static Vector2 settingsRestoreLinkPositionFor(double centerY) =>
      Vector2(160, 2 * centerY - 58);

  // Debug panel (debug builds / Linux): a column of text buttons centred on
  // the playfield.
  static const double debugRowHeight = 30;
  static Vector2 debugPanelTopFor(double viewHeight) =>
      Vector2(worldWidth / 2, Config.spikeHeight + 16);

  // UI accent: the native pink of the button/points-field artwork. Used for
  // the game-over title and labels so they never share the pipe tint (the
  // stage foreground made them unreadable behind frozen pipes).
  static const Color uiAccent = Color(0xFFFF4FB7);

  // Vertical offset of the score number inside the points field from the
  // field's center (the "POINTS" caption lives in the field's lower half).
  static const double scoreLabelNudgeY = -18;

  // Fonts.
  static const String scoreFont = 'LVDC Common2';
  static const String uiFont = 'Opificio Neue';

  // Durations.
  // Menu transitions (home <-> settings / Shop / Skins, the home UI fading
  // out on START, toasts): 3x+ faster than 1.0's 0.5 s after product-owner
  // feedback (2.0 menu deviation, SPEC.md).
  static const double uiFadeDuration = 0.15;
  static const double colorFadeDuration = 0.5;
  static const double replayFadeDuration = 0.3;
  // Popups and dialogs (No-ads popup, skin unlock dialog, fake-ad overlay)
  // fade in / out.
  static const double popupFadeDuration = 0.07;
  // The run's bird fading in at its spawn point after START (the home
  // screen's bird fades out with the home screen).
  static const double runBirdFadeDuration = 0.25;
  // Stagger step for staggered menu elements.
  static const double staggerDuration = 0.07;
  // Gameplay fades keep the 1.0 timing: the score HUD in / out, the spike
  // strips sliding out on START, the bird fading on death, and the
  // game-over panel's staggered fade-in chain.
  static const double gameplayFadeDuration = 0.5;
  static const double gameOverStaggerDuration = 0.2;
  // How long a ServiceMessage stays fully visible between its fade-in and
  // fade-out (total lifetime: uiFadeDuration + this + uiFadeDuration).
  static const double serviceMessageHoldDuration = 2.0;
  // Fake rewarded ad overlay (Linux / desktop debug only): countdown
  // length, then how long "REWARD GRANTED" / "Ad failed to load" stay up.
  static const double fakeAdCountdown = 3.0;
  static const double fakeAdResultHold = 0.8;
  static const double fakeAdFailHold = 1.5;

  // Score HUD watermark: the circle is tinted this fraction of the way from
  // the foreground toward the background color, so pipes (full foreground
  // tint) stay visibly darker than the circle behind them.
  static const double hudCircleLighten = 0.45;

  // --- PRD-home-v3 §6 / §7: P1 popups after a purchase ----------------------

  /// The P1 popups' dim (`rgba(40,40,48,.72)`) and card width (x 20 -> 300).
  static const Color p1PopupDim = Color(0xB8282830);
  static const double p1PopupWidth = 280;
  static const double p1PopupCloseSize = 38;
  static const double p1PopupPad = 16;

  /// Grey body line (`#9a4d78`).
  static const Color p1PopupSmallText = Color(0xFF9A4D78);

  /// Purchase cancelled / failed (§6, build73 `.pcard`): 120 pt header,
  /// 45 pt title band (20 pt at 0.08 em), 20 pt body top padding, message
  /// 18 pt (line-height 1.3), small line 13 pt 8 pt below, OK 50 pt
  /// (24 pt at 0.12 em) 18 pt below.
  static const double purchasePopupHeaderHeight = 120;
  static const double purchasePopupTitleHeight = 45;
  static const double purchasePopupTitleFontSize = 20;
  static const double purchasePopupBodyTop = 20;
  static const double purchasePopupMessageFontSize = 18;
  static const double purchasePopupSmallFontSize = 13;
  static const double purchasePopupSmallGap = 8;
  static const double purchasePopupOkGap = 18;
  static const double purchasePopupOkHeight = 50;
  static const double purchasePopupOkFontSize = 24;

  /// §6 timings: dim in 0.15 s, card pop .82 -> 1.04 -> 1 in 0.24 s, the
  /// gold ✕ badge spins in over 0.38 s after 0.12 s, close fade 0.12 s.
  static const double purchasePopupFadeIn = 0.15;
  static const double purchasePopupPopDuration = 0.24;
  static const double purchasePopupBadgeDelay = 0.12;
  static const double purchasePopupBadgeDuration = 0.38;
  static const double purchasePopupFadeOut = 0.12;

  /// No-ads celebration (§7, build79): 170 pt header, 48 pt title band
  /// (22 pt at 0.1 em), body 16 pt padding, chip 15 pt, CLAIM 52 pt (22 pt
  /// at 0.1 em); 92 pt AD icon, 62 pt gold stamp at (154, 88) in the
  /// header with a 5 pt pink ring.
  static const double noAdsCelebrationHeaderHeight = 170;
  static const double noAdsCelebrationTitleHeight = 48;
  static const double noAdsCelebrationTitleFontSize = 22;
  static const double noAdsCelebrationIconSize = 92;
  static const double noAdsCelebrationStampSize = 62;
  static const Offset noAdsCelebrationStampTopLeft = Offset(154, 88);
  static const double noAdsCelebrationClaimHeight = 52;

  /// §7 timings (s).
  static const double noAdsCelebrationFlash = 0.6;
  static const double noAdsCelebrationShakeDelay = 0.2;
  static const double noAdsCelebrationShake = 0.38;
  static const double noAdsCelebrationSwing = 0.36;
  static const double noAdsCelebrationWobbleDelay = 0.12;
  static const double noAdsCelebrationWobble = 0.42;
  static const double noAdsCelebrationStampDelay = 0.33;
  static const double noAdsCelebrationStampDuration = 0.34;
  static const double noAdsCelebrationConfettiAt = 0.43;
  static const int noAdsCelebrationConfetti = 90;
  static const double noAdsCelebrationFadeOut = 0.15;

  /// Owned flips after the bonus count-up: 0.25 s after it, the Shop
  /// banner (rotateX); 0.7 s later the home tile (rotateY) and the video
  /// icons shrinking away. Flip: 0.18 s out + 0.28 s in.
  static const double noAdsFlipDelay = 0.25;
  static const double noAdsFlipHomeDelay = 0.7;
  static const double flipOutDuration = 0.18;
  static const double flipInDuration = 0.28;
  static const double videoIconShrinkDuration = 0.3;

  /// Owned No-ads tile / banner fill: pink 55 % over the menu background.
  static final Color noAdsOwnedFill = Color.lerp(
    const Color(0xFFF1F1F1),
    menuPink,
    .55,
  )!;

  // --- Settings v3 (PRD-home-v3 §8) -----------------------------------------

  /// Rows relative to the playfield centre, from the mock at 711 (centre
  /// 355.5): title line box top 140 (centre 158), SOUND EFFECTS 235, MUSIC
  /// 295, RUMBLE 355, credit top 405 (centre 414.6).
  static const double settingsTitleDy = -197.5;
  static const double settingsSfxRowDy = -120.5;
  static const double settingsMusicRowDy = -60.5;
  static const double settingsRumbleRowDy = -0.5;
  static const double settingsCreditDy = 59.1;

  /// 30 pt icon squares centred at x 85; labels / slider from x 130 (mock
  /// `.srow` left 70 + 30 pt icon + 30 pt margin).
  static const double settingsIconX = 85;
  static const double settingsContentX = 130;

  /// The RUMBLE icon's buzz when switched on (s).
  static const double settingsRumbleBuzz = 0.32;
}
