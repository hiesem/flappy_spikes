import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show Color, Paint;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:url_launcher/url_launcher.dart';

import '../components/bird.dart';
import '../components/debug_panel.dart';
import '../components/gameover_panel.dart';
import '../components/home/home_screen.dart';
import '../components/pipe_pair.dart';
import '../components/score_hud.dart';
import '../components/settings_panel.dart';
import '../components/spike_strip.dart';
import '../components/tap_catcher.dart';
import '../components/ui/service_message.dart';
import '../menu/menu_state.dart';
import '../menu/powerup_slot.dart';
import '../menu/skin_catalog.dart';
import '../menu/wallet.dart';
import '../services/ads_service.dart';
import '../services/game_services.dart';
import '../services/monetization.dart';
import 'config.dart';
import 'fade.dart';
import 'palettes.dart';
import 'sound.dart';
import 'storage.dart';
import 'tintable.dart';

/// Game states from SPEC.md. `replay` is a transition that returns to
/// [GameState.start] after a full reset with a 0.3 s white fade.
enum GameState { start, playing, gameOver }

/// Which menu screen is up while in [GameState.start] (meaningless in the
/// other states). Shop / Skins are opened by later work packages.
enum MenuScene { home, settings, shop, skins }

class FlappySpikesGame extends Forge2DGame with KeyboardEvents {
  FlappySpikesGame({
    double? worldHeight,
    GameServices? services,
    Monetization? monetization,
    this.soundEnabled = true,
  }) : services = services ?? GameServices(),
       monetization = monetization ?? Monetization(),
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

  /// Passed to the [SoundService] created in [onLoad]. Headless tests
  /// construct with `soundEnabled: false` so no audioplayers platform-channel
  /// call ever happens (the per-test `sound.enabled = false` lines predate
  /// this and only run after [onLoad]).
  final bool soundEnabled;

  /// Analytics + leaderboards. No-op unless main() initialized it.
  final GameServices services;

  /// Rewarded ads + in-app purchases. In-memory fakes unless main() passes
  /// `Monetization.forPlatform()`.
  final Monetization monetization;

  /// Coins, skins, powerup slot and popup policies; built in [onLoad] right
  /// after the storage is loaded.
  late final MenuState menu;

  /// Called when the share button is pressed (wired up by the app shell).
  void Function(int score)? onShareScore;

  /// Called by the home Invite tile (wired up by the app shell to the share
  /// sheet with the store link).
  void Function()? onInvite;

  /// Awaited between the START press and the run (PRD-1 §9: part 2 inserts
  /// the versus intro here). Null = the run starts synchronously.
  Future<void> Function()? beforeRunStart;

  /// Debug panel availability: debug builds and the Linux desktop target.
  static bool get debugAvailable =>
      kDebugMode || (!kIsWeb && Platform.isLinux);

  GameState state = GameState.start;
  MenuScene menuScene = MenuScene.home;
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
  _BirdOpacityAdapter? _birdAdapter;
  late ScoreHud _hud;
  late final RectangleComponent _backdrop;
  late final SpikeStrip _ceiling;
  late final SpikeStrip _ground;
  late final _SpikeInsetAdapter _spikeInset;
  HomeScreen? _home;
  GameOverPanel? _gameOverPanel;
  SettingsPanel? _settingsPanel;
  DebugPanel? _debugPanel;
  ServiceMessage? _message;
  bool _runStarting = false;

  // Skin tint blend (see Config.skinStageBlend): follows the colour
  // crossfade from _skinBlendFrom to _skinBlendTo.
  double _skinBlend = 0;
  double _skinBlendFrom = 0;
  double _skinBlendTo = 0;

  /// Back handlers, topmost last (settings, debug panel; later the Shop,
  /// Skins and popups). Esc pops the topmost. Each returns true when it
  /// handled the back press.
  final List<bool Function()> _backHandlers = [];

  Color get foregroundColor => _fgColor;
  Color get stageBackground => _bgColor;
  bool get isScrolling => state == GameState.playing;

  /// The home screen while it is up (null in runs / settings).
  HomeScreen? get homeScreen => _home;

  /// Current skin blend toward the stage foreground (0 in menus).
  double get skinBlend => _skinBlend;

  /// Tint for [skin]'s body layer right now.
  Color skinTintFor(SkinDef skin) => skin.tintFor(_fgColor, _skinBlend);

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
    menu = MenuState(
      storage,
      onEarned: (amount, source) => services.track('coins_earned', {
        'amount': amount,
        'source': source.analyticsName,
      }),
    );
    sound = SoundService(muted: storage.muteSound, enabled: soundEnabled);
    // Background music: persisted volume, then start the loop (everywhere —
    // menus and gameplay). Guarded/unawaited: no-ops in headless tests.
    unawaited(sound.setMusicVolume(storage.musicVolume));
    unawaited(sound.startMusic());

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

    _ground = SpikeStrip(isCeiling: false);
    _ceiling = SpikeStrip(isCeiling: true);
    _spikeInset = _SpikeInsetAdapter([_ground, _ceiling]);
    world.add(_ground);
    world.add(_ceiling);
    _hud = ScoreHud(position: Config.scoreHudPositionFor(viewHeight / 2));
    _hud.opacity = 0;
    world.add(_hud);
    registerTintable(_hud);
    world.add(TapCatcher());

    // First home arrival (app launch): PowerupSlot already rolled in its
    // constructor, so no extra roll here.
    _setupStartScene();
    _logSlotShown();
    _applyTints();
  }

  // --- scene setup -------------------------------------------------------

  void _setupStartScene() {
    state = GameState.start;
    menuScene = MenuScene.home;
    final bird = Bird();
    _bird = bird;
    // The home screen draws its own bird in the start block; the physics
    // bird waits invisibly at its spawn point and fades in on START.
    _birdAdapter = _BirdOpacityAdapter(bird)..opacity = 0;
    world.add(bird);
    // Menus show the short (44 pt) spike strips of the mocks.
    _fades.removeWhere((fade) => identical(fade.target, _spikeInset));
    _spikeInset.opacity = 1;
    _addHome();
  }

  void _addHome() {
    final home = HomeScreen(
      bestScore: storage.bestScore,
      gamesPlayed: storage.gamesPlayed,
    );
    _home = home;
    world.add(home);
    registerTintable(home);
  }

  /// Fades the home screen out and drops it; its buttons stop hit-testing
  /// at once.
  void _leaveHome() {
    final home = _home;
    _home = null;
    if (home != null) {
      home.active = false;
      unregisterTintable(home);
      fadeOpacity(home, from: home.opacity, to: 0, removeOnDone: true);
    }
  }

  /// Re-reads the menu state into the home screen now (after a purchase,
  /// a debug reset, ...); it also re-syncs itself every frame.
  void refreshHome() => _home?.refresh();

  // --- input -------------------------------------------------------------

  /// Primary action, for tests and the keyboard (Space / Enter): START on
  /// the home screen (no modal open), flap while playing.
  void onScreenTap() {
    switch (state) {
      case GameState.start:
        if (menuScene == MenuScene.home && _backHandlers.isEmpty) {
          startRun();
        }
      case GameState.playing:
        _bird?.flap();
      case GameState.gameOver:
        break;
    }
  }

  /// A real tap that no button consumed (TapCatcher): flaps while playing.
  /// Menus never start a run on a stray tap — only the START button does
  /// (PRD-1 §4.2).
  void onPlayfieldTap() {
    if (state == GameState.playing) {
      _bird?.flap();
    }
  }

  /// The START button. Consumes the armed powerup (the 1.0 run ignores its
  /// effect; part 2 reads it), awaits [beforeRunStart] if set, then starts
  /// the run. Synchronous when [beforeRunStart] is null.
  Future<void> startRun() async {
    if (state != GameState.start ||
        menuScene != MenuScene.home ||
        _backHandlers.isNotEmpty ||
        _runStarting) {
      return;
    }
    sound.play(Sfx.click);
    final hook = beforeRunStart;
    if (hook != null) {
      _runStarting = true;
      try {
        await hook();
      } finally {
        _runStarting = false;
      }
      if (state != GameState.start) return;
    }
    switch (menu.slot.consume()) {
      case Powerup.bigHoops:
        services.track('big_hoops_used');
      case Powerup.shield:
        services.track('shield_armed');
      case Powerup.none:
        break;
    }
    _startGame();
  }

  void _startGame() {
    state = GameState.playing;
    services.logGameStart();
    _leaveHome();
    final adapter = _birdAdapter;
    if (adapter != null) {
      fadeOpacity(
        adapter,
        from: adapter.opacity,
        to: 1,
        duration: Config.runBirdFadeDuration,
      );
    }
    // The strips slide out to their full 72 pt.
    fadeOpacity(_spikeInset, from: _spikeInset.opacity, to: 0);
    _bird!
      ..enableGravity()
      ..flap();
    fadeOpacity(_hud, from: 0, to: 1);
    _spawnTimer = Config.pipeSpawnInterval; // spawn the first pair now
  }

  /// Gold home slot: arm the offered powerup — free for No-ads owners,
  /// otherwise after a completed rewarded ad (PRD-1 §3.6).
  Future<void> tapPowerupSlot() async {
    if (!_homeInteractive || menu.slot.armed != Powerup.none) return;
    sound.play(Sfx.click);
    if (menu.noAds) {
      await menu.slot.armOffered();
      refreshHome();
      return;
    }
    final ads = monetization.ads;
    if (!ads.isAvailable) {
      showToast('No video available right now');
      return;
    }
    final result = await ads.show(AdPlacement.homeSlot);
    if (result == AdResult.completed) {
      await menu.slot.armOffered();
      services.track('ad_rewarded_shown', {
        'placement': AdPlacement.homeSlot.analyticsName,
      });
      refreshHome();
    } else {
      showToast('No video available right now');
    }
  }

  /// True while the home screen is up with nothing over it.
  bool get _homeInteractive =>
      state == GameState.start &&
      menuScene == MenuScene.home &&
      _backHandlers.isEmpty &&
      !_runStarting;

  void _logSlotShown() {
    services.track('home_slot_shown', {
      'item': switch (menu.slot.offered) {
        Powerup.bigHoops => 'big_hoops',
        Powerup.shield => 'shield',
        Powerup.none => 'none',
      },
    });
  }

  // --- later work packages (minimal stubs) ---------------------------------

  /// Shop (coin pill "+" scrolls to the coin packs). Stub until WP5.
  void openShop({bool scrollToCoins = false}) {
    if (!_homeInteractive) return;
    sound.play(Sfx.click);
    services.track('shop_open', {'source': scrollToCoins ? 'pill' : 'tile'});
    showToast('Coming soon');
  }

  /// Skins screen. Stub until WP6.
  void openSkins() {
    if (!_homeInteractive) return;
    sound.play(Sfx.click);
    services.track('skins_open');
    showToast('Coming soon');
  }

  /// No-ads popup ([trigger]: launch / home_tile / shop_banner). Stub until
  /// WP5.
  void openNoAdsPopup(String trigger) {
    if (!_homeInteractive) return;
    sound.play(Sfx.click);
    if (menu.noAds) {
      showToast('Already ad-free');
      return;
    }
    services.track('noads_popup_shown', {'trigger': trigger});
    showToast('Coming soon');
  }

  /// Invite tile: system share sheet with the store link (PRD-1 §3.4, no
  /// reward).
  void invite() {
    if (!_homeInteractive) return;
    sound.play(Sfx.click);
    services.track('invite_tap');
    final share = onInvite;
    if (share == null) {
      showToast('Coming soon');
    } else {
      share();
    }
  }

  // --- back stack & keyboard -------------------------------------------------

  /// Registers a back handler (topmost wins). Pair with [popBack].
  void pushBack(bool Function() handler) => _backHandlers.add(handler);

  /// Removes [handler] wherever it is in the stack.
  void popBack(bool Function() handler) => _backHandlers.remove(handler);

  /// Back (Esc): runs the topmost handler. False when nothing handled it.
  bool handleBack() =>
      _backHandlers.isNotEmpty && _backHandlers.last.call();

  // Stable identities for push/popBack.
  bool _settingsBack() {
    closeSettings();
    return true;
  }

  bool _debugBack() {
    closeDebugPanel();
    return true;
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (state == GameState.gameOver) {
        // The game-over panel's action, once it has faded in.
        if (_gameOverPanel?.canContinue ?? false) {
          goHome();
        }
      } else {
        onScreenTap();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      return handleBack() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.keyD && debugAvailable) {
      if (_debugPanel != null) {
        closeDebugPanel();
      } else {
        openDebugPanel();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- debug panel -----------------------------------------------------------

  /// Opens the developer panel over the menus (debug builds / Linux only).
  void openDebugPanel() {
    if (!debugAvailable || state != GameState.start || _debugPanel != null) {
      return;
    }
    final panel = DebugPanel(onClose: closeDebugPanel);
    _debugPanel = panel;
    world.add(panel);
    pushBack(_debugBack);
  }

  void closeDebugPanel() {
    final panel = _debugPanel;
    if (panel == null) return;
    _debugPanel = null;
    popBack(_debugBack);
    panel.removeFromParent();
    refreshHome();
  }

  /// The debug panel while open (tests).
  DebugPanel? get debugPanel => _debugPanel;

  /// Short-lived message ([ServiceMessage] style): on the home screen in
  /// the gap above the tiles, elsewhere bottom-centre.
  void showToast(String text) => _showServiceMessage(text);

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
      _startColorFade(paletteForStage(newStage), stage: newStage);
    }
  }

  void onBirdHit() {
    if (state != GameState.playing) {
      return;
    }
    state = GameState.gameOver;
    sound.play(Sfx.gameover);
    _bird?.die();
    // Same adapter as the START fade-in, so a very early death replaces
    // that fade instead of fighting it.
    final adapter = _birdAdapter;
    if (adapter != null) {
      fadeOpacity(adapter, from: adapter.opacity, to: 0);
    }

    // Interim coin rule (PRD-1 §3.1): 1 coin per point, credited at game
    // over.
    final coins = score;
    if (coins > 0) {
      unawaited(menu.wallet.add(coins, CoinSource.play));
    }

    final previousBest = storage.bestScore;
    storage.incrementGamesPlayed();
    if (score > storage.bestScore) {
      storage.saveBestScore(score);
    }
    services.logGameOver(score: score, bestScore: storage.bestScore);
    if (score > previousBest) {
      services.logNewBest(score);
    }
    // Submit the local best after EVERY game, not just on a new best: Play
    // Games keeps each player's highest score server-side (one entry), and
    // this also backfills a best set before sign-in was available.
    services.submitBestScore(storage.bestScore);

    final panel = GameOverPanel(
      score: score,
      bestScore: storage.bestScore,
      gamesPlayed: storage.gamesPlayed,
      coinsEarned: coins,
      onReplay: goHome,
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
    _settingsPanel?.setMuted(sound.muted);
    sound.play(Sfx.click); // only audible when unmuting
  }

  /// Music slider on the settings panel: applies the volume live and
  /// persists it. Fire-and-forget (no-op-safe in headless tests).
  void setMusicVolume(double volume) {
    unawaited(sound.setMusicVolume(volume));
    unawaited(storage.saveMusicVolume(volume));
    _settingsPanel?.setMusicVolume(sound.musicVolume);
  }

  /// Gear button on the home screen: fades the home screen out and the
  /// settings panel in. Only reachable from the home screen.
  void openSettings() {
    if (!_homeInteractive || _settingsPanel != null) {
      return;
    }
    sound.play(Sfx.click);
    menuScene = MenuScene.settings;
    _leaveHome();
    final settings = SettingsPanel(
      muted: sound.muted,
      musicVolume: sound.musicVolume,
      onToggleSound: toggleSound,
      onMusicVolume: setMusicVolume,
      onBack: closeSettings,
      onPrivacyPolicy: openPrivacyPolicy,
    );
    _settingsPanel = settings;
    world.add(settings);
    registerTintable(settings);
    fadeOpacity(settings, from: 0, to: 1);
    pushBack(_settingsBack);
  }

  /// Back button / Esc on the settings panel: fades the settings panel out
  /// and a fresh home screen back in (not a new arrival: no slot roll).
  void closeSettings() {
    final settings = _settingsPanel;
    if (state != GameState.start || settings == null) {
      return;
    }
    sound.play(Sfx.click);
    _settingsPanel = null;
    popBack(_settingsBack);
    menuScene = MenuScene.home;
    unregisterTintable(settings);
    fadeOpacity(settings, from: settings.opacity, to: 0, removeOnDone: true);
    _addHome();
    fadeOpacity(_home, from: 0, to: 1);
  }

  /// The game-over panel's action (and part 2's results NEXT): back to the
  /// home screen as a NEW arrival — the powerup slot re-rolls (PRD-1 §3.6).
  void goHome() {
    if (state != GameState.gameOver) {
      return;
    }
    menu.slot.rollForArrival();
    replay();
    _logSlotShown();
  }

  /// Full scene reset with a 0.3 s white fade, ending on the home screen at
  /// colour stage 0. [goHome] wraps it with the new-arrival bookkeeping.
  void replay() {
    sound.play(Sfx.click);

    // Full scene reset.
    _bird?.removeFromParent();
    _bird = null;
    _birdAdapter = null;
    for (final pipe in world.children.query<PipePair>()) {
      pipe.removeFromParent();
    }
    final oldPanel = _gameOverPanel;
    _gameOverPanel = null;
    if (oldPanel != null) {
      oldPanel.removeFromParent();
    }
    final oldHome = _home;
    _home = null;
    if (oldHome != null) {
      unregisterTintable(oldHome);
      oldHome.removeFromParent();
    }
    score = 0;
    _stage = 0;
    _skinBlend = _skinBlendFrom = _skinBlendTo = 0;
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
      _home?.setStats(
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
    fadeOpacity(
      overlay,
      from: 1,
      to: 0,
      duration: Config.replayFadeDuration,
      removeOnDone: true,
    );
  }

  void shareScore() {
    sound.play(Sfx.click);
    services.logShareScore(score);
    onShareScore?.call(score);
  }

  /// Leaderboard button (start + game-over scenes): opens the platform's
  /// native leaderboard UI (Google Play Games / Game Center). On failure a
  /// short-lived [ServiceMessage] tells the player what happened — a failed
  /// tap must not be indistinguishable from no tap.
  Future<void> showLeaderboard() async {
    sound.play(Sfx.click);
    switch (await services.showLeaderboards()) {
      case ShowLeaderboardResult.signInFailed:
        _showServiceMessage('Play Games sign-in unavailable');
      case ShowLeaderboardResult.leaderboardFailed:
        _showServiceMessage('Leaderboard unavailable — try again');
      case ShowLeaderboardResult.opened:
      case ShowLeaderboardResult.unavailable:
      case ShowLeaderboardResult.busy:
        break; // nothing to report
    }
  }

  void _showServiceMessage(String text) {
    // One message at a time: a new one replaces any still on screen.
    final old = _message;
    if (old != null && old.parent != null) {
      old.removeFromParent();
    }
    final message = ServiceMessage(
      message: text,
      position: state == GameState.start
          ? Config.homeToastPositionFor(viewHeight)
          : Config.serviceMessagePositionFor(viewHeight / 2),
    );
    _message = message;
    world.add(message);
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

  void _startColorFade(Palette palette, {required int stage}) {
    _skinBlendFrom = _skinBlend;
    _skinBlendTo = stage == 0 ? 0 : Config.skinStageBlend;
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
      _colorFadeT = (_colorFadeT + dt / Config.colorFadeDuration).clamp(
        0.0,
        1.0,
      );
      _bgColor = Color.lerp(_fadeFromBg, _targetBg, _colorFadeT)!;
      _fgColor = Color.lerp(_fadeFromFg, _targetFg, _colorFadeT)!;
      _skinBlend =
          _skinBlendFrom + (_skinBlendTo - _skinBlendFrom) * _colorFadeT;
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
        // Difficulty ramp: the gap shrinks as the score climbs, plus a
        // bounded random variance on top (the curve value is the MINIMUM
        // gap; the draw is capped so both pipe stubs can stay >= 40 pt).
        final gap = Config.gapForPipe(score, _random.nextDouble(), viewHeight);
        // The spawn band keeps both pipe stubs >= 40 pt: the top stub can
        // never hide fully behind the ceiling spikes (a pipe is always
        // visible), the bottom stub never sinks into the ground spikes.
        final minY = Config.gapBottomMinFor(gap);
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

/// Drives the strips' menu inset through the shared fade helper: opacity 1
/// = the menu's short strips ([Config.menuSpikeInset]), 0 = full strips.
class _SpikeInsetAdapter implements OpacityProvider {
  _SpikeInsetAdapter(this._strips);

  final List<SpikeStrip> _strips;
  double _value = 0;

  @override
  double get opacity => _value;

  @override
  set opacity(double value) {
    _value = value;
    for (final strip in _strips) {
      strip.visualInset = Config.menuSpikeInset * value;
    }
  }
}
