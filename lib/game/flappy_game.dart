import 'dart:math';
import 'dart:ui' show Color, Paint;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/bird.dart';
import '../components/gameover_panel.dart';
import '../components/pipe_pair.dart';
import '../components/score_hud.dart';
import '../components/spike_strip.dart';
import '../components/start_panel.dart';
import '../components/tap_catcher.dart';
import '../services/game_services.dart';
import 'config.dart';
import 'fade.dart';
import 'palettes.dart';
import 'sound.dart';
import 'storage.dart';
import 'tintable.dart';

/// Game states from SPEC.md. `replay` is a transition that returns to
/// [GameState.start] after a full reset with a 0.3 s white fade.
enum GameState { start, playing, gameOver }

class FlappySpikesGame extends Forge2DGame {
  FlappySpikesGame({double? worldHeight, GameServices? services})
      : services = services ?? GameServices(),
        viewHeight = _clampViewHeight(worldHeight ?? Config.worldHeight),
        super(
          gravity: Vector2(0, Config.gravity),
          camera: CameraComponent.withFixedResolution(
            width: Config.worldWidth,
            height: _clampViewHeight(worldHeight ?? Config.worldHeight),
          ),
          zoom: 1,
        ) {
    // The game uses 1 Forge2D world unit = 1 logical point (SPEC.md). The
    // engine's default per-step translation clamp (2.0 units, tuned for
    // meter-scale worlds) would otherwise cap every body at ~120 pt/s at
    // 60 fps, breaking flap physics and the 200 pt/s scroll. Raise it well
    // beyond anything reachable (bird speeds stay in the low hundreds).
    maxTranslation = 10000;
    maxTranslationSquared = maxTranslation * maxTranslation;
  }

  static double _clampViewHeight(double height) =>
      height.clamp(Config.minViewHeight, Config.maxViewHeight);

  /// Playfield height in points: 320/aspect on the device, clamped to
  /// [Config.minViewHeight]..[Config.maxViewHeight]. The spike strips are
  /// pinned to the top/bottom edges, so there are no letterbox bars.
  final double viewHeight;

  final GameStorage storage = GameStorage();
  late final SoundService sound;

  /// Analytics + leaderboards. No-op unless main() initialized it.
  final GameServices services;

  /// Called when the share button is pressed (wired up by the app shell).
  void Function(int score)? onShareScore;

  GameState state = GameState.start;
  int score = 0;
  int _stage = 0;

  // Color stage system. Initialized to the stage-0 palette up front because
  // GameWidget reads backgroundColor() on its first build, before onLoad.
  Color _bgColor = kPalettes[0]!.background;
  Color _fgColor = kPalettes[0]!.foreground;
  late Color _fadeFromBg;
  late Color _fadeFromFg;
  late Color _targetBg;
  late Color _targetFg;
  double _colorFadeT = 1;

  final Set<Tintable> _tintables = {};
  final List<Fade> _fades = [];
  final Random _random = Random();
  double _spawnTimer = 0;
  double? _lastGapBottomY;

  Bird? _bird;
  late ScoreHud _hud;
  late final RectangleComponent _backdrop;
  StartPanel? _startPanel;
  GameOverPanel? _gameOverPanel;

  Color get foregroundColor => _fgColor;
  bool get isScrolling => state == GameState.playing;

  // Any letterbox slivers (only on screens beyond the viewHeight clamp, e.g.
  // tablets) are painted with the FOREGROUND tint so they read as an
  // extension of the spike strips. The world's own background is drawn by an
  // in-world backdrop rectangle (see onLoad).
  @override
  Color backgroundColor() => _fgColor;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewfinder.anchor = Anchor.topLeft;

    await storage.load();
    sound = SoundService(muted: storage.muteSound);

    final palette = paletteForStage(0);
    _bgColor = palette.background;
    _fgColor = palette.foreground;
    _targetBg = _fadeFromBg = _bgColor;
    _targetFg = _fadeFromFg = _fgColor;

    // In-world background: a flat rect painted with the background color,
    // behind everything (backgroundColor() itself is now the bar color).
    _backdrop = RectangleComponent(
      position: Vector2.zero(),
      size: Vector2(Config.worldWidth, viewHeight),
      priority: -1000,
      paint: Paint()..color = _bgColor,
    );
    world.add(_backdrop);

    world.add(SpikeStrip(isCeiling: false));
    world.add(SpikeStrip(isCeiling: true));
    _hud = ScoreHud(position: Config.scoreHudPositionFor(viewHeight / 2));
    _hud.opacity = 0;
    world.add(_hud);
    registerTintable(_hud);
    world.add(TapCatcher());

    _setupStartScene();
    _applyTints();
  }

  // --- scene setup -------------------------------------------------------

  void _setupStartScene() {
    state = GameState.start;
    final bird = Bird();
    _bird = bird;
    world.add(bird);
    final panel = StartPanel(
      muted: storage.muteSound,
      onToggleSound: toggleSound,
      onLeaderboard: showLeaderboard,
      onPrivacyPolicy: openPrivacyPolicy,
      bestScore: storage.bestScore,
      gamesPlayed: storage.gamesPlayed,
    );
    _startPanel = panel;
    world.add(panel);
    registerTintable(panel);
  }

  // --- input -------------------------------------------------------------

  void onScreenTap() {
    switch (state) {
      case GameState.start:
        _startGame();
      case GameState.playing:
        _bird?.flap();
      case GameState.gameOver:
        break;
    }
  }

  void _startGame() {
    state = GameState.playing;
    services.logGameStart();
    final panel = _startPanel;
    _startPanel = null;
    if (panel != null) {
      unregisterTintable(panel);
      fadeOpacity(panel, from: 1, to: 0, removeOnDone: true);
    }
    _bird!
      ..enableGravity()
      ..flap();
    fadeOpacity(_hud, from: 0, to: 1);
    _spawnTimer = Config.pipeSpawnInterval; // spawn the first pair now
  }

  // --- scoring & contacts ------------------------------------------------

  void onScoreSensor(Object other) {
    if (state != GameState.playing || other is! PipePair || other.scored) {
      return;
    }
    other.scored = true;
    score++;
    sound.play(Sfx.point);
    _hud.setScore(score);
    final newStage = stageOf(score);
    if (newStage != _stage) {
      _stage = newStage;
      _startColorFade(paletteForStage(newStage));
    }
  }

  void onBirdHit() {
    if (state != GameState.playing) {
      return;
    }
    state = GameState.gameOver;
    sound.play(Sfx.gameover);
    _bird?.die();
    fadeOpacity(_bird == null ? null : _BirdOpacityAdapter(_bird!), from: 1, to: 0);

    final previousBest = storage.bestScore;
    storage.incrementGamesPlayed();
    if (score > storage.bestScore) {
      storage.saveBestScore(score);
    }
    services.logGameOver(score: score, bestScore: storage.bestScore);
    if (score > previousBest) {
      services.logNewBest(score);
      services.submitBestScore(score);
    }

    final panel = GameOverPanel(
      score: score,
      bestScore: storage.bestScore,
      gamesPlayed: storage.gamesPlayed,
      onReplay: replay,
      onShare: shareScore,
      onLeaderboard: showLeaderboard,
    );
    _gameOverPanel = panel;
    world.add(panel);
    fadeOpacity(_hud, from: 1, to: 0);
  }

  // --- buttons -----------------------------------------------------------

  void toggleSound() {
    sound.muted = !sound.muted;
    storage.saveMuteSound(sound.muted);
    _startPanel?.setMuted(sound.muted);
    sound.play(Sfx.click); // only audible when unmuting
  }

  void replay() {
    sound.play(Sfx.click);

    // Full scene reset.
    _bird?.removeFromParent();
    _bird = null;
    for (final pipe in world.children.query<PipePair>()) {
      pipe.removeFromParent();
    }
    final oldPanel = _gameOverPanel;
    _gameOverPanel = null;
    if (oldPanel != null) {
      oldPanel.removeFromParent();
    }
    score = 0;
    _stage = 0;
    _lastGapBottomY = null;
    _hud.setScore(0);
    _fades.removeWhere((fade) => identical(fade.target, _hud));
    _hud.opacity = 0;

    // Colors snap back to the default palette (covered by the white fade).
    final palette = paletteForStage(0);
    _bgColor = _targetBg = _fadeFromBg = palette.background;
    _fgColor = _targetFg = _fadeFromFg = palette.foreground;
    _colorFadeT = 1;
    _applyTints();

    // Best/games/mute reloaded from persistence.
    storage.load().then((_) {
      sound.muted = storage.muteSound;
      _startPanel?.setStats(
        bestScore: storage.bestScore,
        gamesPlayed: storage.gamesPlayed,
      );
    });

    _setupStartScene();

    // 0.3 s white fade.
    final overlay = RectangleComponent(
      position: Vector2.zero(),
      size: Vector2(Config.worldWidth, viewHeight),
      paint: Paint()..color = const Color(0xFFFFFFFF),
      priority: 1000,
    );
    world.add(overlay);
    fadeOpacity(overlay, from: 1, to: 0, duration: Config.replayFadeDuration, removeOnDone: true);
  }

  void shareScore() {
    sound.play(Sfx.click);
    services.logShareScore(score);
    onShareScore?.call(score);
  }

  /// Leaderboard button (start + game-over scenes): opens the platform's
  /// native leaderboard UI (Google Play Games / Game Center).
  void showLeaderboard() {
    sound.play(Sfx.click);
    services.showLeaderboards();
  }

  /// Privacy-policy link on the start scene: opens the policy in the browser.
  Future<void> openPrivacyPolicy() async {
    sound.play(Sfx.click);
    try {
      await launchUrl(
        Uri.parse(Config.privacyPolicyUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // No usable browser (or plugin unavailable in tests): ignore.
    }
  }

  // --- color stages --------------------------------------------------------

  void _startColorFade(Palette palette) {
    _fadeFromBg = _bgColor;
    _fadeFromFg = _fgColor;
    _targetBg = palette.background;
    _targetFg = palette.foreground;
    _colorFadeT = 0;
  }

  void _applyTints() {
    for (final tintable in _tintables) {
      tintable.setTint(_fgColor);
    }
    _backdrop.paint.color = _bgColor;
    _hud.setScoreColor(_bgColor);
    // The watermark circle stays a lighter shade than the pipes so pipe
    // outlines remain clearly visible against it (it was set to the raw
    // foreground tint by the loop above via its Tintable registration).
    _hud.setTint(Color.lerp(_fgColor, _bgColor, Config.hudCircleLighten)!);
  }

  void registerTintable(Tintable tintable) {
    _tintables.add(tintable);
    tintable.setTint(_fgColor);
  }

  void unregisterTintable(Tintable tintable) {
    _tintables.remove(tintable);
  }

  // --- fades ---------------------------------------------------------------

  void fadeOpacity(
    OpacityProvider? target, {
    required double from,
    required double to,
    double duration = Config.uiFadeDuration,
    bool removeOnDone = false,
  }) {
    if (target == null) {
      return;
    }
    target.opacity = from;
    Component? component = target is Component ? target as Component : null;
    _fades.removeWhere((fade) => identical(fade.target, target));
    _fades.add(
      Fade(
        duration: duration,
        target: target,
        onUpdate: (value) => target.opacity = from + (to - from) * value,
        onComplete: () {
          target.opacity = to;
          if (removeOnDone) {
            component?.removeFromParent();
          }
        },
      ),
    );
  }

  // --- update --------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);

    if (_colorFadeT < 1) {
      _colorFadeT = (_colorFadeT + dt / Config.colorFadeDuration).clamp(0.0, 1.0);
      _bgColor = Color.lerp(_fadeFromBg, _targetBg, _colorFadeT)!;
      _fgColor = Color.lerp(_fadeFromFg, _targetFg, _colorFadeT)!;
      _applyTints();
    }

    for (final fade in List.of(_fades)) {
      fade.update(dt);
      if (fade.done) {
        _fades.remove(fade);
      }
    }

    if (state == GameState.playing) {
      _spawnTimer += dt;
      if (_spawnTimer >= Config.pipeSpawnInterval) {
        _spawnTimer = 0;
        // Difficulty ramp: the gap shrinks as the score climbs.
        final gap = Config.gapForScore(score);
        const minY = Config.gapBottomMin;
        final maxY = Config.gapBottomMaxFor(gap, viewHeight);
        var gapBottomY = minY + _random.nextDouble() * (maxY - minY);
        // Keep consecutive gaps within a flyable jump of each other.
        final last = _lastGapBottomY;
        if (last != null) {
          gapBottomY = gapBottomY
              .clamp(last - Config.maxGapJump, last + Config.maxGapJump)
              .clamp(minY, maxY);
        }
        _lastGapBottomY = gapBottomY;
        world.add(PipePair(gapBottomY: gapBottomY, gap: gap));
      }
    }
  }
}

/// Adapts [Bird]'s opacity setter to the [OpacityProvider] interface so the
/// shared fade helper can fade the bird sprite out on game over.
class _BirdOpacityAdapter implements OpacityProvider {
  _BirdOpacityAdapter(this._bird);

  final Bird _bird;
  double _opacity = 1;

  @override
  double get opacity => _opacity;

  @override
  set opacity(double value) {
    _opacity = value;
    _bird.setSpriteOpacity(value);
  }
}
