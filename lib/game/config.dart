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

  // --- Home screen (PRD-1 §4, design/menu_v2/screen_home_centered.html) ---
  //
  // Rects are in world points at a given playfield height. The table in
  // PRD-1 §4.1 is measured at 711 pt and reproduced exactly there. Vertical
  // rule (§4.2): the coin pill / gear / title / subtitle are pinned to the
  // top; the tile row and leaderboard row keep their 711 distance to the
  // bottom edge (compressing toward 568, where the free space runs out); the
  // start block is centred in the band between the subtitle and the tile
  // row, so the title->start gap is what shrinks first.

  /// Fixed menu chrome colours (not stage-tinted).
  static const Color menuPink = Color(0xFFEC008C);
  static const Color menuPinkDark = Color(0xFFC40073);
  static const Color menuSoft = Color(0xFFFCD9EE);
  static const Color menuGold = Color(0xFFFFB529);
  static const Color menuPlum = Color(0xFF7A0044);

  /// Height at which the PRD table was measured.
  static const double homeReferenceHeight = 711;
  static const double homeMargin = 14; // pill / shop tile / trophy left edge
  static const double homeRightEdge = worldWidth - homeMargin; // 306
  static const double homeTopRowY = 58; // pill + gear band 58..96
  static const double homeTopRowHeight = 38;
  static const double homeTitleTop = 128;
  static const double homeTitleFontSize = 42;
  static const double homeSubtitleTop = 178;
  static const double homeSubtitleFontSize = 19;
  static const double homeSubtitleLineHeight = 0.9;
  // Top of the band the start block is centred in: the subtitle's ink
  // bottom (~210) less 10 at 711 (the PRD's "equal gaps"); at 568 it moves
  // down 6 pt so the squeezed gaps above / below the block stay balanced.
  static double homeStartBandTopFor(double viewHeight) =>
      _lerp(206, 200, _homeT(viewHeight));

  static const double homeStartWidth = 186;
  static const double homeStartHeight = 68;
  static const double homeSlotHeight = 32;
  static const double homeSlotGap = 2; // START bottom -> slot top
  static const double homeSlotOutline = 3; // bg-coloured outline
  static const double homeStartBlockHeight =
      homeStartHeight + homeSlotGap + homeSlotHeight; // 102
  static const double homeStartLeft = 96;
  static final Vector2 homeBirdSize = Vector2(44, 36);
  static const double homeBirdLeft = 38;

  static const int homeTileCount = 4;
  static const double homeTileWidth = 70;
  static const double homeTileHeight = 92;
  static const double homeTileGap = 4;
  static const double homeTileIconSize = 38;
  static const double homeLeaderboardSize = 70;
  static const double homeTrophySize = 44;
  static const double homeStatsGap = 14; // trophy tile -> stats text

  /// 0 at 568, 1 at 711 (and above): how much of the 711 spacing the
  /// bottom-pinned rows keep.
  static double _homeT(double viewHeight) =>
      ((viewHeight - minViewHeight) / (homeReferenceHeight - minViewHeight))
          .clamp(0.0, 1.0);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Top of the leaderboard row: 67 pt above the bottom edge at 711 (23 pt
  /// above the menu spike tips), 54 at 568.
  static double homeLeaderboardTopFor(double viewHeight) =>
      viewHeight - _lerp(54, 67, _homeT(viewHeight)) - homeLeaderboardSize;

  /// Top of the tile row: 26 pt above the leaderboard row at 711, 12 at 568.
  static double homeTileRowTopFor(double viewHeight) =>
      homeLeaderboardTopFor(viewHeight) -
      _lerp(12, 26, _homeT(viewHeight)) -
      homeTileHeight;

  /// Top of the START button: the start block centred between
  /// [homeStartBandTopFor] and the tile row (277 at 711).
  static double homeStartTopFor(double viewHeight) =>
      (homeStartBandTopFor(viewHeight) + homeTileRowTopFor(viewHeight)) / 2 -
      homeStartBlockHeight / 2;

  static Vector2 homeCoinPillPositionFor(double viewHeight) =>
      Vector2(homeMargin, homeTopRowY);
  static Rect homeGearRectFor(double viewHeight) => Rect.fromLTWH(
    homeRightEdge - homeTopRowHeight,
    homeTopRowY,
    homeTopRowHeight,
    homeTopRowHeight,
  );
  // Title / subtitle positions are the TOP-CENTRE of their line boxes.
  static Vector2 homeTitlePositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, homeTitleTop);
  static Vector2 homeSubtitlePositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, homeSubtitleTop);
  static Rect homeBirdRectFor(double viewHeight) => Rect.fromLTWH(
    homeBirdLeft,
    homeStartTopFor(viewHeight) + (homeStartHeight - homeBirdSize.y) / 2,
    homeBirdSize.x,
    homeBirdSize.y,
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
  static Rect homeLeaderboardRectFor(double viewHeight) => Rect.fromLTWH(
    homeMargin,
    homeLeaderboardTopFor(viewHeight),
    homeRightEdge - homeMargin,
    homeLeaderboardSize,
  );
  static Rect homeTrophyRectFor(double viewHeight) => Rect.fromLTWH(
    homeMargin,
    homeLeaderboardTopFor(viewHeight),
    homeLeaderboardSize,
    homeLeaderboardSize,
  );

  /// Short-lived toasts on the home screen: centred in the gap between the
  /// powerup slot and the tile row (417.5 at 711).
  static Vector2 homeToastPositionFor(double viewHeight) {
    final slot = homeSlotRectFor(viewHeight);
    return Vector2(
      worldWidth / 2,
      (slot.bottom + homeTileRowTopFor(viewHeight)) / 2,
    );
  }

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
  // Coin pill top-left (as on home), back button in the gear's place, title
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

  /// "RESTORE PURCHASES" link: top of its text line, centred.
  static const double shopRestoreTop = 650;
  static Vector2 shopRestorePositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, shopRestoreTop);

  /// Bottom of the scrollable content (just below the restore link): fits
  /// the 667 pt viewport at 711 without scrolling.
  static double shopContentBottomFor(double viewHeight) => 666;

  /// Content y the "+" of the coin pill scrolls to the top of the viewport:
  /// just above the first row of packs' flap tags.
  static double shopCoinsAnchorFor(double viewHeight) =>
      shopPackRowTop - shopPackTagHeight / 2 - 8;

  /// How long a restore may stay silent before "Nothing to restore".
  static const double restoreTimeout = 4;

  // --- Skins (PRD-1 §5.3, design K1; content coordinates = world
  // coordinates before scrolling, measured at 711 and top-pinned) ---------

  static const int skinGridColumns = 3;
  static const double skinTileWidth = 92;
  static const double skinTileHeight = 106;
  static const double skinTileGap = 8; // 14 + 92 + 8 = 114
  static const double skinGridTop = 150;

  /// Skin tile [index] (catalogue display order), 3 per row.
  static Rect skinTileRectFor(double viewHeight, int index) => Rect.fromLTWH(
    homeMargin + (index % skinGridColumns) * (skinTileWidth + skinTileGap),
    skinGridTop + (index ~/ skinGridColumns) * (skinTileHeight + skinTileGap),
    skinTileWidth,
    skinTileHeight,
  );

  /// Bottom of the scrollable grid of [count] tiles (one gap below the last
  /// row): 606 for 12 skins, inside the 667 pt viewport at 711.
  static double skinsContentBottomFor(double viewHeight, int count) =>
      skinTileRectFor(viewHeight, count - 1).bottom + skinTileGap;

  // Inside a tile (mock `.sk`, measured on skins_k1.png): the 48 x 52
  // preview centred at y 54 (its 6 pt top margin minus the inline svg's
  // baseline gap); price pill 6 pt above the bottom; the lock icon at
  // (6, 8) (6 pt box, inline svg 2 pt down); NEW tag 4 pt past the right
  // edge and 6 pt above the top.
  static const double skinPreviewWidth = 48;
  static const double skinPreviewHeight = 52;
  static const double skinPreviewCenterY = 54;
  static const double skinTileInset = 6;
  static const double skinLockTop = 8;
  static const double skinLockSize = 14;
  static const double skinOutlineWidth = 3;
  static const double skinCheckBadgeSize = 22;
  static const double skinCheckIconSize = 14;
  static const double skinPriceFontSize = 13;
  static const double skinPriceCoinSize = 14;
  static const double skinPricePadX = 6;
  static const double skinPricePadY = 2;
  // The browser's line box of the 13 pt text (13 x 1.284 rounded down).
  static const double skinPriceLineHeight = 16;
  static const double skinPriceGap = 4;
  static const double skinTagOverhangX = 4;
  static const double skinTagOverhangY = 6;
  static const double skinTagFontSize = 10;
  static const double skinTagLetterSpacing = 0.05; // em

  // --- Skin unlock dialog (no-ads popup visual language) -----------------

  static const double skinDialogHeaderHeight = 120;
  static const double skinDialogPlateSize = 96; // soft square behind it
  static const double skinDialogPreviewScale = 1.6; // 77 x 83 bird
  static const double skinDialogCoinSize = 20;
  static const double skinDialogMessageFontSize = 16;
  static const double skinDialogMessageGap = 10;
  static const double skinDialogCancelHeight = 44;
  static const double skinDialogCancelFontSize = 13;

  /// Card of [cardHeight] (it depends on the dialog state), x 20 -> 300,
  /// centred on the same band as the No-ads card.
  static Rect skinDialogRectFor(double viewHeight, double cardHeight) {
    final noAds = noAdsCardRectFor(viewHeight);
    return Rect.fromLTWH(
      noAds.left,
      noAds.center.dy - cardHeight / 2,
      noAds.width,
      cardHeight,
    );
  }

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
}
