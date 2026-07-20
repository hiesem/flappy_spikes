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
  static const double pipeSpawnInterval = 1.5;
  static const double pipeSpawnX = worldWidth + pipeWidth / 2; // 320 + 44
  static const double gapBottomMin = 202; // 72 + 130: every draw leaves a
  // >= 130 pt flyable window below the ceiling spikes — and from gap 130
  // down the gap can never tuck under the ceiling at all (the original's
  // 112 could leave a nearly unflyable 40 pt window)
  static const double gapBottomMax = 351; // 568 - 72 - 105 - 40 (final gap)
  static const double maxGapJump = 140; // max vertical jump of the gap
  // between consecutive pipes — keeps every transition flyable
  static const double sensorOffsetX = 111; // right of pipe center

  /// Pipe gap for a given score: [pipeGapStart] at 0, shrinking linearly to
  /// [pipeGap] once the score reaches [difficultyRampScore].
  static double gapForScore(int score) {
    final t = score.clamp(0, difficultyRampScore) / difficultyRampScore;
    return pipeGapStart + (pipeGap - pipeGapStart) * t;
  }

  /// Lowest allowed gap-bottom y (top edge of the bottom pipe) for a given
  /// gap and playfield height: keeps 40 pt clearance between the bottom pipe
  /// and the ground spikes.
  static double gapBottomMaxFor(double gap, [double viewHeight = worldHeight]) =>
      viewHeight - spikeHeight - gap - 40;

  // UI sizes.
  static final Vector2 titleSize = Vector2(274.5, 147.5);
  static final Vector2 pointsfieldSize = Vector2(241.5, 82);
  static final Vector2 buttonSize = Vector2(241.5, 38.5);
  static final Vector2 soundButtonSize = Vector2(30, 30);
  static final Vector2 gameCenterButtonSize = Vector2(30, 30);
  static final Vector2 gameCenterGameoverButtonSize = Vector2(60, 60);
  static final Vector2 scoreCircleSize = Vector2(183, 183);

  // Privacy policy, hosted on GitHub Pages (docs/index.html; see
  // SUBMISSION.md). Linked from the start scene and both store listings.
  static const String privacyPolicyUrl =
      'https://hiesem.github.io/flappy_spikes/';

  // UI positions. The helpers take the playfield center Y (viewHeight / 2)
  // and reproduce the original 320x568 layout exactly at centerY = 284
  // (SpriteKit y-up coordinates from SPEC converted to Flame's y-down).
  static Vector2 titlePositionFor(double centerY) =>
      Vector2(160, centerY - 147.5 / 2 - 35); // 175.25 at 284
  static Vector2 bestLabelPositionFor(double centerY) =>
      Vector2(160, centerY + 120); // 404 at 284
  static Vector2 gamesLabelPositionFor(double centerY) =>
      Vector2(160, centerY + 150); // 434 at 284
  static Vector2 soundButtonPositionFor(double centerY) =>
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

  // Fixed positions at the design height (kept for tests and defaults).
  static final Vector2 titlePosition = titlePositionFor(284);
  static final Vector2 bestLabelPosition = bestLabelPositionFor(284);
  static final Vector2 gamesLabelPosition = gamesLabelPositionFor(284);
  static final Vector2 soundButtonPosition = soundButtonPositionFor(284);
  static final Vector2 scoreHudPosition = scoreHudPositionFor(284);
  static final Vector2 pointsfieldPosition = pointsfieldPositionFor(284);
  static final Vector2 replayButtonPosition = replayButtonPositionFor(284);
  static final Vector2 shareButtonPosition = shareButtonPositionFor(284);
  static final Vector2 gameCenterButtonPosition =
      gameCenterButtonPositionFor(284);
  static final Vector2 gameCenterGameoverButtonPosition =
      gameCenterGameoverButtonPositionFor(284);
  static final Vector2 privacyLinkPosition = privacyLinkPositionFor(284);

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
  static const double staggerDuration = 0.2;

  // Score HUD watermark: the circle is tinted this fraction of the way from
  // the foreground toward the background color, so pipes (full foreground
  // tint) stay visibly darker than the circle behind them.
  static const double hudCircleLighten = 0.45;
}
