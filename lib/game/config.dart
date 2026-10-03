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
  static const double uiFadeDuration = 0.5;
  static const double colorFadeDuration = 0.5;
  static const double replayFadeDuration = 0.3;
  // The run's bird fading in at its spawn point after START (the home
  // screen's bird fades out with the home screen).
  static const double runBirdFadeDuration = 0.25;
  static const double staggerDuration = 0.2;
  // How long a ServiceMessage stays fully visible between its fade-in and
  // fade-out (total lifetime: uiFadeDuration + this + uiFadeDuration).
  static const double serviceMessageHoldDuration = 2.0;

  // Score HUD watermark: the circle is tinted this fraction of the way from
  // the foreground toward the background color, so pipes (full foreground
  // tint) stay visibly darker than the circle behind them.
  static const double hudCircleLighten = 0.45;
}
