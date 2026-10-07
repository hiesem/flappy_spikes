import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show Color, Paint, PlatformDispatcher, Rect;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, KeyEventResult;
import 'package:url_launcher/url_launcher.dart';

import '../components/bird.dart';
import '../components/debug_panel.dart';
import '../components/fake_ad_overlay.dart';
import '../components/gameover_panel.dart';
import '../components/home/home_screen.dart';
import '../components/home/menu_primitives.dart' show MenuButton;
import '../components/levels/level_up_popup.dart';
import '../components/levels/levels_screen.dart';
import '../components/menu_drag_dispatcher.dart';
import '../components/menu_screen_chrome.dart' show MenuScreen;
import '../components/noads_celebration.dart';
import '../components/noads_popup.dart';
import '../components/pipe_pair.dart';
import '../components/purchase_result_popup.dart';
import '../components/score_hud.dart';
import '../components/settings_panel.dart';
import '../components/shop/shop_screen.dart';
import '../components/skins/celebration.dart' show ScreenFlash, ScreenShake;
import '../components/skins/skin_shop_screen.dart';
import '../components/spike_strip.dart';
import '../components/tap_catcher.dart';
import '../components/ui/coin_fly.dart';
import '../components/ui/coin_reward.dart';
import '../components/ui/confetti.dart';
import '../components/ui/service_message.dart';
import '../menu/free_coins_policy.dart';
import '../menu/menu_state.dart';
import '../menu/powerup_slot.dart';
import '../menu/wallet.dart';
import '../services/ads_service.dart';
import '../services/game_services.dart';
import '../services/iap_service.dart';
import '../services/monetization.dart';
import '../skins/catalog.dart';
import '../skins/item_store.dart';
import '../skins/look.dart';
import 'config.dart';
import 'fade.dart';
import 'palettes.dart';
import 'purchases.dart';
import 'rumble.dart';
import 'sound.dart';
import 'storage.dart';
import 'tintable.dart';

/// Game states from SPEC.md. `replay` is a transition that returns to
/// [GameState.start] after a full reset with a 0.3 s white fade.
enum GameState { start, playing, gameOver }

/// Which menu screen is up while in [GameState.start] (meaningless in the
/// other states).
enum MenuScene { home, settings, shop, skins, levels }

class FlappySpikesGame extends Forge2DGame with KeyboardEvents {
  FlappySpikesGame({
    double? worldHeight,
    GameServices? services,
    Monetization? monetization,
    DateTime Function()? clock,
    this.soundEnabled = true,
    bool? rumbleEnabled,
  }) : services = services ?? GameServices(),
       rumble = Rumble(hardware: rumbleEnabled ?? soundEnabled),
       monetization = monetization ?? Monetization(),
       storage = GameStorage(clock: clock),
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
    // The knock throttle runs on game time (tests step it).
    rumble.clock = () => _clock;
  }

  static double _clampViewHeight(double height) =>
      height.clamp(Config.minViewHeight, Config.maxViewHeight);

  /// Playfield height in points: 320/aspect on the device, clamped to
  /// [Config.minViewHeight]..[Config.maxViewHeight]. The spike strips are
  /// pinned to the top/bottom edges, so there are no letterbox bars.
  final double viewHeight;

  /// Persistence; its clock (wall time unless the constructor's `clock`
  /// overrides it, e.g. in tests) also drives the daily menu policies.
  final GameStorage storage;
  late final SoundService sound;

  /// Passed to the [SoundService] created in [onLoad]. Headless tests
  /// construct with `soundEnabled: false` so no audioplayers platform-channel
  /// call ever happens (the per-test `sound.enabled = false` lines predate
  /// this and only run after [onLoad]).
  final bool soundEnabled;

  /// Phone vibration (PRD-2 §3.33; menu knocks PRD-home-v3 §10). Its
  /// `hardware` follows `rumbleEnabled` (default: [soundEnabled]), so
  /// headless tests get a recorder; `on` follows `GameStorage.rumble`.
  final Rumble rumble;

  /// Seconds of game time (clamped frame steps): the rumble throttle clock.
  double _clock = 0;

  /// Analytics + leaderboards. No-op unless main() initialized it.
  final GameServices services;

  /// Rewarded ads + in-app purchases. In-memory fakes unless main() passes
  /// `Monetization.forPlatform()`.
  final Monetization monetization;

  /// Coins, skins, powerup slot and popup policies; built in [onLoad] right
  /// after the storage is loaded.
  late final MenuState menu;

  /// Store purchase flow: grants coins / No ads from the IAP event stream
  /// (subscribed in [onLoad], cancelled in [onRemove]).
  Purchases get purchases => _purchases!;
  Purchases? _purchases;

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

  /// Seeds the pipe spawn layout (tests); null = unseeded. Tests inject a
  /// seeded [Random] so journeys that fly a fixed line meet the same pipes
  /// every run.
  Random? pipeRandom;
  final Random _random = Random();

  /// The pipe spawn RNG: the injected [pipeRandom] when set, else [_random].
  Random get _pipeRandom => pipeRandom ?? _random;

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
  late final CoinPill _coinPill;
  late final MenuCornerBox _cornerBox;

  /// Every home / Shop / Skins screen still on screen (the current one and
  /// any fading out): the shared chrome's opacity follows them.
  final List<PositionComponent> _chromeHosts = [];

  /// Set by a screen-to-screen hop between two screens that both show the
  /// chrome; it then stays fully opaque until the old screen is gone.
  bool _chromeHold = false;

  /// Like [_chromeHold] for the corner box only (home <-> settings: the
  /// box stays, the pill fades with home).
  bool _cornerHold = false;
  GameOverPanel? _gameOverPanel;
  SettingsPanel? _settingsPanel;
  ShopScreen? _shop;
  SkinShopScreen? _skinShop;
  LevelsScreen? _levels;
  LevelUpPopup? _levelUpPopup;

  /// Seconds until a tapped home emblem opens LEVELS (null = none due).
  double? _levelsOpenIn;

  /// How long home has been settled with a LEVEL UP owed (Q-H1 trigger).
  double _levelUpSettle = 0;
  bool _itemPurchaseRunning = false;
  NoAdsPopup? _noAdsPopup;
  PurchaseResultPopup? _purchasePopup;
  NoAdsCelebration? _noAdsCelebration;

  /// Modal popups waiting for the one on screen to close (or for the
  /// menus to come back), oldest first: never two popups at once.
  final List<_PopupRequest> _popupQueue = [];

  /// Where the last No-ads purchase started (tile / shop_banner / popup).
  String _noAdsSource = 'popup';

  /// PRD-home-v3 §7: from a fresh No-ads purchase until the owned flips,
  /// the No-ads tile / banner keep their old face ([_noAdsRevealHeld]) and
  /// the powerup slot / GET keep their video icon ([_noAdsVideoHeld]).
  bool _noAdsRevealHeld = false;
  bool _noAdsVideoHeld = false;
  bool _noAdsBonusReserved = false;

  /// The popup's only context since 2026-10-05 (analytics payload).
  static const String _launchTrigger = 'launch';
  bool _freeCoinsBusy = false;
  DebugPanel? _debugPanel;
  FakeAdOverlay? _fakeAd;
  ServiceMessage? _message;

  /// The "Purchase pending…" toast and its product, while it may be up.
  (IapProduct, ServiceMessage)? _pendingToast;
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

  /// Menu screens (Shop / Skins) below the one on top, bottom first: their
  /// back button returns to the last one (re-created), or home when empty.
  /// Re-opening a screen already in the trail goes back to it, so the
  /// Shop <-> Skins hops never pile up.
  final List<MenuScene> _menuTrail = [];

  Color get foregroundColor => _fgColor;
  Color get stageBackground => _bgColor;
  bool get isScrolling => state == GameState.playing;

  /// The home screen while it is up (null in runs / settings).
  HomeScreen? get homeScreen => _home;

  /// The coin pill shared by home, Shop and Skins (see [_updateMenuChrome]).
  CoinPill get coinPill => _coinPill;

  /// The top-left box behind home's gear and the screens' back button.
  MenuCornerBox get cornerBox => _cornerBox;

  /// The Shop while it is open (null otherwise).
  ShopScreen? get shopScreen => _shop;

  /// The skin shop while it is open (null otherwise).
  SkinShopScreen? get skinShop => _skinShop;

  /// The LEVELS screen while it is open (null otherwise).
  LevelsScreen? get levelsScreen => _levels;

  /// The LEVEL UP popup while it is up (null otherwise).
  LevelUpPopup? get levelUpPopup => _levelUpPopup;

  /// Test / debug override of [reduceMotion] (null = follow the OS).
  bool? reduceMotionOverride;

  /// The OS "reduce motion" / remove-animations setting (PRD-menu-v2 §8.4):
  /// no flash, shake, rays or pulsing; bob and flap stay.
  bool get reduceMotion =>
      reduceMotionOverride ??
      PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  /// The No-ads popup while it is up (null otherwise).
  NoAdsPopup? get noAdsPopup => _noAdsPopup;

  /// The purchase cancelled / failed popup while it is up (PRD-home-v3 §6).
  PurchaseResultPopup? get purchaseResultPopup => _purchasePopup;

  /// The No-ads celebration while it is up (PRD-home-v3 §7).
  NoAdsCelebration? get noAdsCelebration => _noAdsCelebration;

  /// Whether one of the modal popups (launch No-ads upsell, LEVEL UP,
  /// purchase result, No-ads celebration) is up.
  bool get modalPopupOpen =>
      _noAdsPopup != null ||
      _levelUpPopup != null ||
      _purchasePopup != null ||
      _noAdsCelebration != null;

  /// How many modal popups wait for their turn (tests).
  int get queuedPopups => _popupQueue.length;

  /// Queues a modal popup: [open] runs as soon as no other modal popup is
  /// up, every popup queued earlier has opened, and [canOpen] holds
  /// (checked again each frame). Right away when all that holds now.
  void _queuePopup(bool Function() canOpen, void Function() open) {
    _popupQueue.add(_PopupRequest(canOpen, open));
    _drainPopups();
  }

  /// Opens the oldest queued popup when its turn has come (see
  /// [_queuePopup]); called each frame and whenever a popup closes.
  void _drainPopups() {
    while (_popupQueue.isNotEmpty && !modalPopupOpen) {
      final next = _popupQueue.first;
      if (!next.canOpen()) return;
      _popupQueue.removeAt(0);
      next.open();
    }
  }

  /// Menus up and no run starting: where queued results / celebrations
  /// may show (a late store callback during a run waits for home).
  bool get _menusUp => state == GameState.start && !_runStarting;

  /// Whether the No-ads owned looks show (tile / banner AD-FREE): the
  /// owned flag, except between a fresh purchase and its flips.
  bool get noAdsShown => menu.noAds && !_noAdsRevealHeld;

  /// Whether the powerup slot / GET chip drop their video icon (as
  /// [noAdsShown], released with the icons' shrink).
  bool get noAdsVideoGone => menu.noAds && !_noAdsVideoHeld;

  /// Rewarded ads on screen right now (real or fake).
  int _adsShowing = 0;

  /// PRD-menu-v2 §8.4: the idle animations of the live home / Shop pause
  /// while a dialog, popup, ad, fake ad or the debug panel is on top.
  bool get liveMotionPaused =>
      _noAdsPopup != null ||
      _levelUpPopup != null ||
      _purchasePopup != null ||
      _noAdsCelebration != null ||
      _debugPanel != null ||
      _fakeAd != null ||
      _adsShowing > 0;

  /// True while a free-coins rewarded ad is playing.
  bool get freeCoinsBusy => _freeCoinsBusy;

  /// The fake rewarded-ad overlay while it is up (null otherwise).
  FakeAdOverlay? get fakeAdOverlay => _fakeAd;

  /// Current skin blend toward the stage foreground (0 in menus).
  double get skinBlend => _skinBlend;


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
    // Before any DragCallbacks component mounts, so Flame uses this one: the
    // menu lists' drag slop is Config.menuScrollSlop world points (S1-50).
    final drags = MenuDragDispatcher(
      pointsToPixels: () => canvasSize.x <= 0 || canvasSize.y <= 0
          ? 1
          : min(
              canvasSize.x / Config.worldWidth,
              canvasSize.y / viewHeight,
            ),
    );
    // Flame's own DragCallbacks registers its default dispatcher this way.
    // ignore: invalid_use_of_internal_member
    registerKey(const MultiDragDispatcherKey(), drags);
    add(drags);

    await storage.load();
    menu = MenuState(
      storage,
      onEarned: (amount, source) => services.track('coins_earned', {
        'amount': amount,
        'source': source.analyticsName,
      }),
    );
    // The slot arms a powerup only right before it starts the run, which
    // consumes it: anything still armed here is stale (an app killed
    // mid-start, or a pre-WP10 arm-then-START build) and must not ride
    // along on a plain START.
    if (menu.slot.armed != Powerup.none) menu.slot.consume();
    _purchases = Purchases(
      iap: monetization.iap,
      menu: menu,
      services: services,
      toast: showToast,
      onNoAdsGranted: () {
        closeNoAdsPopup(dismissed: false);
        refreshHome();
      },
      onPackPurchased: _onPackPurchased,
      onNoAdsPurchased: _onNoAdsPurchased,
      onPurchaseProblem: openPurchaseResultPopup,
      pendingToast: (product, text) {
        showToast(text);
        _pendingToast = (product, _message!);
      },
      onResolved: _dismissPendingToast,
    )..start();
    sound = SoundService(muted: storage.muteSound, enabled: soundEnabled);
    rumble.on = storage.rumble;
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

    // Shared menu chrome: one coin pill above the screens (it takes its own
    // taps) and one top-left box below them (their gear / back buttons are
    // transparent tap targets on top). Both outlive the screens, so a
    // crossfade between two screens that show them never dims them.
    _coinPill = CoinPill(
      initialBalance: menu.wallet.balance,
      topRight: Config.homeCoinPillPositionFor(viewHeight),
      onPressed: () => openShop(scrollToCoins: true),
      isActive: () =>
          _homeInteractive ||
          _sceneOnTop(MenuScene.shop) ||
          _sceneOnTop(MenuScene.skins),
      priority: 21,
    )..opacity = 0;
    _cornerBox = MenuCornerBox(
      rect: Config.homeGearRectFor(viewHeight),
      priority: 19,
    )..opacity = 0;
    world.add(_cornerBox);
    world.add(_coinPill);

    // First home arrival (app launch): PowerupSlot already rolled in its
    // constructor, so no extra roll here.
    _setupStartScene();
    _logSlotShown();
    _applyTints();

    // App launch = a session start: the No-ads upsell may show on this
    // home arrival (PRD-menu-v4 §8, NoAdsPopupPolicy).
    await _startSession();
  }

  /// When the app went to the background (null while in the foreground).
  DateTime? _backgroundSince;

  /// Runs started since the current session began: the session-start
  /// upsell is dropped once one started (never between runs).
  int _runsThisSession = 0;

  /// A No-ads offer waits in [_popupQueue] (never more than one).
  bool _noAdsOfferQueued = false;

  /// A session starts (launch, or back after >= [Config.sessionGap]): the
  /// home arrival may show the No-ads upsell, through the popup queue
  /// (after / before LEVEL UP, purchase results, celebrations). Only when
  /// home is up — a return into a run, game over or another menu screen
  /// is no home arrival.
  ///
  /// At most one offer at a time (QA S1-70): no new request while one is
  /// queued or the popup is up, and the full §8 window is re-checked the
  /// moment the queued request would show — dropped if it closed since.
  Future<void> _startSession() async {
    await menu.noAdsPopup.startSession();
    _runsThisSession = 0;
    if (state != GameState.start || menuScene != MenuScene.home) return;
    if (_noAdsOfferQueued || _noAdsPopup != null) return;
    if (menu.noAdsPopup.evaluate() == null) return;
    bool stale() =>
        _runsThisSession > 0 ||
        menu.noAds ||
        state != GameState.start ||
        menuScene != MenuScene.home;
    _noAdsOfferQueued = true;
    _queuePopup(
      () => stale() || (_homeInteractive && _fakeAd == null),
      () {
        _noAdsOfferQueued = false;
        if (stale() || _noAdsPopup != null) return;
        final reason = menu.noAdsPopup.evaluate();
        if (reason == null) return;
        openNoAdsPopup(reason: reason.name);
        if (_noAdsPopup != null) unawaited(menu.noAdsPopup.markShown());
      },
    );
  }

  @override
  void onRemove() {
    _purchases?.dispose();
    super.onRemove();
  }

  /// Back from the background (e.g. after the Play payment sheet or a
  /// settings detour): re-query store products that were still missing.
  @override
  void lifecycleStateChange(AppLifecycleState state) {
    super.lifecycleStateChange(state);
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _backgroundSince ??= storage.now();
      case AppLifecycleState.resumed:
        unawaited(monetization.iap.refresh());
        final since = _backgroundSince;
        _backgroundSince = null;
        if (since != null &&
            storage.now().difference(since) >= Config.sessionGap) {
          unawaited(_startSession());
        }
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  // --- scene setup -------------------------------------------------------

  void _setupStartScene() {
    state = GameState.start;
    menuScene = MenuScene.home;
    _menuTrail.clear();
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
    final home = HomeScreen();
    _home = home;
    _chromeHosts.add(home);
    world.add(home);
    registerTintable(home);
    _updateMenuChrome();
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

  /// The START button: a plain run, never with a powerup (only the slot
  /// arms one, right before it starts the run itself). Awaits
  /// [beforeRunStart] if set; synchronous when it is null.
  Future<void> startRun() async {
    if (!_homeInteractive) return;
    // §8.2: the home bird hops with flap.mp3 as the run starts. The run's
    // first flap plays flap.mp3 in this same frame, so it is only played
    // here when [beforeRunStart] delays the run.
    if (beforeRunStart != null) sound.play(Sfx.flap);
    _home?.bird.hop(HomeBird.startHop);
    await _runFromHome();
  }

  /// Gold home slot (2.0 DEVIATION from PRD-1 §3.6, see SPEC.md): "watch
  /// an ad -> play with the powerup". A completed rewarded ad arms the
  /// offered powerup and starts the run at once (START's path, which
  /// consumes it); a failed / unavailable ad leaves the player home with a
  /// toast and nothing armed. No-ads owners skip the ad (PRD-1 Q2). The
  /// home screen takes no input while the ad plays.
  Future<void> tapPowerupSlot() async {
    if (!_homeInteractive) return;
    sound.play(Sfx.bnAdBtn);
    if (!menu.noAds) {
      final ads = monetization.ads;
      if (!ads.isAvailable) {
        showToast('No video available right now');
        return;
      }
      // Blocks every home action (START, Space / Enter, tiles, a second
      // slot tap) until the ad is over.
      _runStarting = true;
      final AdResult result;
      try {
        result = await showRewardedAd(AdPlacement.homeSlot);
      } finally {
        _runStarting = false;
      }
      if (result != AdResult.completed) {
        showToast('No video available right now');
        return;
      }
      if (state != GameState.start || menuScene != MenuScene.home) return;
    }
    await _runFromHome(withPowerup: true);
  }

  /// Shared tail of START and the powerup slot: arms the offered powerup
  /// ([withPowerup], slot only), awaits [beforeRunStart], then consumes the
  /// armed powerup (the 1.0 run ignores its effect; part 2 reads it) and
  /// starts the run. Synchronous for a plain START without a hook.
  Future<void> _runFromHome({bool withPowerup = false}) async {
    final hook = beforeRunStart;
    if (withPowerup || hook != null) {
      _runStarting = true;
      try {
        if (withPowerup) await menu.slot.armOffered();
        if (hook != null) await hook();
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
    _runsThisSession++;
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
    // The strips slide out to their full 72 pt (gameplay timing).
    fadeOpacity(
      _spikeInset,
      from: _spikeInset.opacity,
      to: 0,
      duration: Config.gameplayFadeDuration,
    );
    _bird!
      ..enableGravity()
      ..flap();
    fadeOpacity(_hud, from: 0, to: 1, duration: Config.gameplayFadeDuration);
    _spawnTimer = Config.pipeSpawnInterval; // spawn the first pair now
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

  // --- Shop (PRD-1 §5.2) ---------------------------------------------------

  /// True while [scene] is the menu screen up, with no popup / debug panel
  /// over it and no run starting.
  bool _sceneOnTop(MenuScene scene) {
    if (state != GameState.start || menuScene != scene || _runStarting) {
      return false;
    }
    return switch (scene) {
      MenuScene.home => _backHandlers.isEmpty,
      MenuScene.shop =>
        _backHandlers.isNotEmpty && _backHandlers.last == _shopBack,
      MenuScene.skins =>
        _backHandlers.isNotEmpty && _backHandlers.last == _skinsBack,
      MenuScene.levels =>
        _backHandlers.isNotEmpty && _backHandlers.last == _levelsBack,
      _ => false,
    };
  }

  /// Shop tile / coin pill: fades the home screen (or the Skins screen)
  /// out and the Shop in. The pill ([scrollToCoins]) opens it at the coin
  /// packs; pressed while already in the Shop it just scrolls there.
  /// [source] defaults to "pill" / "tile" (`shop_open` analytics).
  /// [sfx]: the button's sound (§8.2: `sk_tap` for the tile).
  void openShop({
    bool scrollToCoins = false,
    String? source,
    Sfx sfx = Sfx.click,
  }) {
    if (_sceneOnTop(MenuScene.shop)) {
      if (scrollToCoins) {
        sound.play(sfx);
        _shop?.scrollToCoins();
      }
      return;
    }
    if (_shop != null) return;
    final fromSkins = _sceneOnTop(MenuScene.skins);
    if (!_homeInteractive && !fromSkins) return;
    sound.play(sfx);
    services.track('shop_open', {
      'source': source ?? (scrollToCoins ? 'pill' : 'tile'),
    });
    // Real prices for anything the launch query missed (cheap when none).
    unawaited(monetization.iap.refresh());
    if (fromSkins) {
      _dismissSkins();
      _advanceTrail(from: MenuScene.skins, to: MenuScene.shop);
    } else {
      _menuTrail.clear();
      _leaveHome();
    }
    _showShop(scrollToCoins: scrollToCoins);
  }

  void _showShop({bool scrollToCoins = false}) {
    menuScene = MenuScene.shop;
    final shop = ShopScreen(onBack: closeShop);
    _shop = shop;
    _chromeHosts.add(shop);
    _chromeHold = true; // always replaces home / Skins
    world.add(shop);
    registerTintable(shop);
    fadeOpacity(shop, from: 0, to: 1);
    pushBack(_shopBack);
    if (scrollToCoins) {
      shop.loaded.then((_) {
        if (identical(_shop, shop)) shop.scrollToCoins(animate: false);
      });
    }
  }

  /// Fades the Shop out and drops it; its buttons stop hit-testing at once.
  void _dismissShop() {
    final shop = _shop;
    if (shop == null) return;
    _shop = null;
    popBack(_shopBack);
    shop.active = false;
    unregisterTintable(shop);
    fadeOpacity(shop, from: shop.opacity, to: 0, removeOnDone: true);
  }

  /// Back button / Esc in the Shop: back to the screen it was opened from
  /// (Skins) or the home screen (not a new arrival: no slot roll).
  void closeShop() {
    if (state != GameState.start || _shop == null) return;
    sound.play(Sfx.click);
    _dismissShop();
    _returnFromMenuScreen();
  }

  /// [from] is being replaced by [to]: remember [from] for back, unless
  /// [to] is already below (then this is a way back to it).
  void _advanceTrail({required MenuScene from, required MenuScene to}) {
    final index = _menuTrail.indexOf(to);
    if (index >= 0) {
      _menuTrail.removeRange(index, _menuTrail.length);
    } else {
      _menuTrail.add(from);
    }
  }

  /// After a menu screen closed: the previous screen of the trail, or a
  /// fresh home screen.
  void _returnFromMenuScreen() {
    final previous = _menuTrail.isEmpty ? null : _menuTrail.removeLast();
    switch (previous) {
      case MenuScene.shop:
        _showShop();
      case MenuScene.skins:
        _showSkins();
      default:
        menuScene = MenuScene.home;
        _chromeHold = true; // from the Shop / Skins
        _addHome();
        fadeOpacity(_home, from: 0, to: 1);
    }
  }

  bool _shopBack() {
    closeShop();
    return true;
  }

  /// Shop free-coins row: a rewarded ad for +[FreeCoinsPolicy.reward]
  /// coins, within the policy's cooldown / daily cap. No-ads owners never
  /// see an ad (PRD-1 §3.5 / §9): they CLAIM the same +40 directly, under
  /// the same cap and cooldown, and no `ad_rewarded_shown` is logged.
  Future<void> claimFreeCoins() async {
    if (!_sceneOnTop(MenuScene.shop) || _freeCoinsBusy) return;
    final policy = menu.freeCoins;
    if (!policy.canClaim) return;
    sound.play(Sfx.bnAdBtn);
    _freeCoinsBusy = true;
    try {
      if (!menu.noAds) {
        final ads = monetization.ads;
        if (!ads.isAvailable) {
          showToast('No video available right now');
          return;
        }
        final result = await showRewardedAd(AdPlacement.shopFreeCoins);
        if (result != AdResult.completed) {
          showToast('No video available right now');
          return;
        }
      }
      await policy.recordClaim();
      // The pill keeps the old number until the coins land (§8.3).
      _coinPill.hold();
      await menu.wallet.add(FreeCoinsPolicy.reward, CoinSource.rewarded);
    } finally {
      _freeCoinsBusy = false;
    }
    showToast('+${FreeCoinsPolicy.reward} coins');
    final chip = _shop?.freeCoins.chipRect;
    if (chip != null) {
      playCoinReward(CoinRewardAnimation.freeCoins(from: chip));
    } else {
      _coinPill.releaseHold();
    }
  }

  /// The standard "coins added" feedback (PRD-home-v3 §5, Q-S9): starts
  /// [reward] (a [CoinRewardAnimation] preset) into the shared coin pill,
  /// which it holds until the coins land — credit the wallet before or
  /// after this call, the number waits either way. Returns [reward].
  CoinRewardAnimation playCoinReward(CoinRewardAnimation reward) {
    reward.random ??= coinFlyRandom;
    reward.prepare(
      pill: _coinPill,
      coin: Sprite(images.fromCache('menu/coin.png')),
    );
    _coinReward = reward;
    world.add(reward);
    return reward;
  }

  /// The coin reward while it runs (tests; null once it finished).
  CoinRewardAnimation? get coinReward =>
      _coinReward != null && !_coinReward!.finished ? _coinReward : null;
  CoinRewardAnimation? _coinReward;

  /// The coin-fly animation while it runs (tests).
  CoinFly? get coinFly {
    final fly = _coinReward?.fly;
    return fly != null && !fly.done ? fly : null;
  }

  /// Seeds the coin-fly drift (tests); null = random.
  Random? coinFlyRandom;

  /// A coin pack (Shop) or No ads (popup price button): starts the store
  /// purchase; [Purchases] grants it when the store confirms.
  Future<void> buyProduct(IapProduct product, {Sfx sfx = Sfx.click}) async {
    if (state != GameState.start) return;
    sound.play(sfx);
    await purchases.buy(product);
  }

  /// Home NO ADS tile / Shop REMOVE ADS banner (PO change 2026-10-05):
  /// starts the `no_ads` store purchase straight away instead of opening
  /// the popup — the popup is now the automatic launch upsell only.
  /// [source] (home_tile / shop_banner) is logged as `noads_purchase_tapped`
  /// when the tap actually starts a purchase. Owners keep the unchanged
  /// "Already ad-free" toast; the buttons are not tappable while a
  /// No-ads purchase is pending.
  Future<void> buyNoAds(String source) async {
    if (state != GameState.start) return;
    if (menu.noAds) {
      sound.play(Sfx.click);
      showToast('Already ad-free');
      return;
    }
    if (purchases.isPending(IapProduct.noAds) ||
        (!_homeInteractive && !_sceneOnTop(MenuScene.shop))) {
      return;
    }
    services.track('noads_purchase_tapped', {'source': source});
    _noAdsSource = source == 'home_tile' ? 'tile' : source;
    // §8.2 / §8.3: `sk_tap` for the home tile, `sk_dialog` for the Shop's
    // Remove-ads banner.
    await buyProduct(
      IapProduct.noAds,
      sfx: source == 'shop_banner' ? Sfx.skDialog : Sfx.skTap,
    );
  }

  /// "RESTORE PURCHASES" (Settings; PRD-home-v3 §9 took it off the Shop).
  Future<void> restorePurchases() async {
    if (state != GameState.start) return;
    sound.play(Sfx.click);
    await purchases.restore();
  }

  /// Shop featured-item row: the skin shop on [item]'s tab with it tried
  /// on.
  void openFeaturedItem(SkinItem item) => openSkins(
    layer: item.layer,
    tryOnId: item.id,
    source: 'shop_featured',
  );

  // --- Skin shop (PRD-menu-v2 §3–4) ------------------------------------------

  /// Skins tile (home) / featured row (Shop): fades the current screen out
  /// and the skin shop in, on [layer]'s tab (default Birds) with the locked
  /// item [tryOnId] tried on (scrolled into view). Already open: switches to
  /// that tab / try-on. [source] defaults to "tile" / "shop" (`skins_open`
  /// analytics).
  void openSkins({SkinLayer? layer, String? tryOnId, String? source}) {
    final open = _skinShop;
    if (_sceneOnTop(MenuScene.skins) && open != null) {
      if (layer != null) selectSkinTab(layer);
      if (tryOnId != null) tapItem(open.tab, tryOnId);
      return;
    }
    if (open != null) return;
    final fromShop = _sceneOnTop(MenuScene.shop);
    if (!_homeInteractive && !fromShop) return;
    sound.play(Sfx.skTap); // §8.2 tile / §8.3 featured row
    services.track('skins_open', {
      'source': source ?? (fromShop ? 'shop' : 'tile'),
    });
    if (fromShop) {
      _dismissShop();
      _advanceTrail(from: MenuScene.shop, to: MenuScene.skins);
    } else {
      _menuTrail.clear();
      _leaveHome();
    }
    _showSkins(layer: layer, tryOnId: tryOnId);
  }

  void _showSkins({SkinLayer? layer, String? tryOnId}) {
    menuScene = MenuScene.skins;
    final tryOn = layer != null && tryOnId != null && !menu.items.isOwned(layer, tryOnId)
        ? tryOnId
        : null;
    final screen = SkinShopScreen(
      onBack: closeSkins,
      initialTab: layer ?? SkinLayer.bird,
      initialTryOn: tryOn,
    );
    _skinShop = screen;
    _chromeHosts.add(screen);
    _chromeHold = true; // always replaces home / the Shop
    world.add(screen);
    registerTintable(screen);
    fadeOpacity(screen, from: 0, to: 1);
    pushBack(_skinsBack);
    if (layer != null && tryOn != null) {
      final item = itemById(layer, tryOn);
      if (item != null) services.logItemTryOn(layer, item.id, item.rarity);
    }
  }

  /// Fades the skin shop out and drops it.
  void _dismissSkins() {
    final screen = _skinShop;
    if (screen == null) return;
    _skinShop = null;
    popBack(_skinsBack);
    screen.active = false;
    unregisterTintable(screen);
    fadeOpacity(screen, from: screen.opacity, to: 0, removeOnDone: true);
  }

  /// Back button / Esc in the skin shop: back to the Shop when it was
  /// opened from there, else home (not a new arrival: no slot roll).
  void closeSkins() {
    if (state != GameState.start || _skinShop == null) return;
    sound.play(Sfx.click);
    _dismissSkins();
    _returnFromMenuScreen();
  }

  bool _skinsBack() {
    closeSkins();
    return true;
  }

  /// A tab of the skin shop: clears the try-on (one at a time), `sk_tab`,
  /// `skin_shop_tab`, and the grid refills with its entrance animation.
  void selectSkinTab(SkinLayer layer) {
    final screen = _skinShop;
    if (screen == null || !_sceneOnTop(MenuScene.skins)) return;
    if (screen.tab == layer) return;
    screen.selectTab(layer);
    sound.play(Sfx.skTab);
    services.logSkinShopTab(layer);
  }

  /// A grid tile (PRD-menu-v2 §3.3–3.5): clears its NEW tag; an owned item
  /// is equipped at once (or `sk_tap` when it already is); a locked one is
  /// tried on (on [layer]'s tab — the open one for grid taps). [fromTile]:
  /// a real tap on that grid tile — a second tap on the tile already being
  /// tried on buys it (WP-J2, same path as the preview's BUY).
  void tapItem(SkinLayer layer, String id, {bool fromTile = false}) {
    final screen = _skinShop;
    if (screen == null || !_sceneOnTop(MenuScene.skins)) return;
    final item = itemById(layer, id);
    if (item == null) return;
    if (layer != screen.tab) selectSkinTab(layer);
    final items = menu.items;
    if (screen.isNewTag(item)) {
      screen.clearNew(item);
      unawaited(items.markSeen(layer, id));
    }
    if (items.isOwned(layer, id)) {
      final wasEquipped =
          items.isEquipped(layer, id) && screen.tryOnId == null;
      screen.clearTryOn();
      if (wasEquipped) {
        sound.play(Sfx.skTap);
      } else {
        unawaited(equipItem(layer, id));
      }
      return;
    }
    if (screen.tryOnId == id) {
      if (fromTile) unawaited(buyTriedOnItem(source: 'tile'));
      return;
    }
    screen.setTryOn(id);
    sound.play(Sfx.skTap);
    screen.hop(.5);
    services.logItemTryOn(layer, id, item.rarity);
  }

  /// Equips an owned item (saved at once; the home bird and the run bird
  /// follow the store): `sk_equip`, the preview bird hops with `flap.mp3`.
  Future<void> equipItem(SkinLayer layer, String id) async {
    if (!menu.items.isOwned(layer, id)) return;
    _skinShop?.clearTryOn();
    sound.play(Sfx.skEquip);
    _skinShop?.hop();
    services.logItemEquip(layer, id);
    await menu.items.equip(layer, id);
  }

  /// The preview's BUY button (§3.6): with enough coins the tried-on item
  /// is bought (coins spent, owned + equipped), the celebration plays and
  /// the coin pill counts down; otherwise `sk_nocoins`, the NOT ENOUGH
  /// COINS toast and the pill shakes with its "+" flashing gold (the "+"
  /// opens the Shop). No confirmation: the try-on is the confirmation.
  /// [source]: `button` (preview BUY) or `tile` (second tap on the tile).
  Future<void> buyTriedOnItem({String source = 'button'}) async {
    final screen = _skinShop;
    if (screen == null || !_sceneOnTop(MenuScene.skins)) return;
    final item = screen.tryOnItem;
    if (item == null || _itemPurchaseRunning) return;
    final items = menu.items;
    if (menu.wallet.balance < item.price) {
      sound.play(Sfx.skNoCoins);
      screen.showNoCoins();
      _coinPill.nudge(shake: !reduceMotion);
      services.logItemNoCoins(
        item.layer,
        item.id,
        items.shortfall(item.layer, item.id),
      );
      return;
    }
    // Rewards still waiting to count in stay out of the count-down.
    final before = menu.wallet.balance - _coinPill.reserved;
    _itemPurchaseRunning = true;
    final ItemPurchaseResult result;
    try {
      result = await items.purchase(item.layer, item.id);
    } finally {
      _itemPurchaseRunning = false;
    }
    if (result != ItemPurchaseResult.purchased) return;
    services.logItemPurchase(
      item.layer,
      item.id,
      item.rarity,
      item.price,
      source: source,
    );
    // The purchase auto-equips (ItemStore.purchase): mirror the explicit
    // equip's analytics so both paths log the same events.
    services.logItemEquip(item.layer, item.id);
    _coinPill
      ..balance = menu.wallet.balance
      ..countFrom(before);
    if (identical(_skinShop, screen)) {
      screen
        ..clearTryOn()
        ..celebrate(item);
    }
  }

  // --- LEVELS + LEVEL UP (PRD-home-v3 §3.3, §4.3, §4.4) ---------------------

  /// A tap on the home emblem stage (§3.3): the bird already hopped; LEVELS
  /// opens [Config.homeEmblemTapDelay] later.
  void tapHomeEmblem() {
    if (!_homeInteractive || _levelsOpenIn != null) return;
    _levelsOpenIn = Config.homeEmblemTapDelay;
  }

  /// Fades home out and the LEVELS screen in (fade + 14 pt rise, 0.22 s).
  /// [source] is logged as `levels_open`.
  void openLevels({String source = 'home_emblem'}) {
    _levelsOpenIn = null;
    if (!_homeInteractive || _levels != null) return;
    services.logLevelsOpen(source);
    _menuTrail.clear();
    _leaveHome();
    menuScene = MenuScene.levels;
    final screen = LevelsScreen(onBack: closeLevels);
    _levels = screen;
    _chromeHosts.add(screen);
    _chromeHold = true; // replaces home: the corner box stays
    world.add(screen);
    registerTintable(screen);
    fadeOpacity(
      screen,
      from: 0,
      to: 1,
      duration: Config.levelsEnterDuration,
    );
    pushBack(_levelsBack);
  }

  /// Back button / Esc on LEVELS: back home (not a new arrival).
  void closeLevels() {
    final screen = _levels;
    if (state != GameState.start || screen == null) return;
    sound.play(Sfx.click);
    _levels = null;
    popBack(_levelsBack);
    screen.active = false;
    unregisterTintable(screen);
    fadeOpacity(screen, from: screen.opacity, to: 0, removeOnDone: true);
    _returnFromMenuScreen();
  }

  bool _levelsBack() {
    closeLevels();
    return true;
  }

  /// Q-H1 interim trigger: once home has been up with nothing over it for
  /// [Config.levelUpSettleDelay] and a LEVEL UP is owed (a run reached a
  /// new level, or the catch-up after the update), the popup opens. The
  /// no-ads launch popup goes first (it blocks home until closed).
  void _checkLevelUp(double dt) {
    final home = _home;
    final ready =
        _levelUpPopup == null &&
        _popupQueue.isEmpty &&
        _levelsOpenIn == null &&
        home != null &&
        home.built &&
        home.opacity >= 1 &&
        _homeInteractive &&
        _fakeAd == null &&
        _adsShowing == 0 &&
        menu.levels.pendingLevelUp != null;
    if (!ready) {
      _levelUpSettle = 0;
      return;
    }
    _levelUpSettle += dt;
    if (_levelUpSettle >= Config.levelUpSettleDelay) {
      _levelUpSettle = 0;
      openLevelUpPopup();
    }
  }

  /// Shows the owed LEVEL UP popup over home (§4.3): `sk_buy_rare` /
  /// `epic` / `legendary` for lv 1-4 / 5-8 / 9-10 and `level_up`. No-op
  /// when nothing is owed or home is not up with nothing over it.
  void openLevelUpPopup() {
    final pending = menu.levels.pendingLevelUp;
    if (pending == null || _levelUpPopup != null || !_homeInteractive) return;
    final level = pending.toLevel;
    sound.play(
      level >= 9
          ? Sfx.skBuyLegendary
          : level >= 5
          ? Sfx.skBuyEpic
          : Sfx.skBuyRare,
    );
    services.logLevelUp(level, storage.bestScore);
    final popup = LevelUpPopup(
      pending: pending,
      look: menu.items.look,
      onClaim: (from) => unawaited(claimLevelUp(from: from)),
    );
    _levelUpPopup = popup;
    world.add(popup);
    fadeOpacity(popup, from: 0, to: 1, duration: Config.popupFadeDuration);
    pushBack(_levelUpBack);
  }

  /// CLAIM ([from] = the button's rect) or ✕ / Esc ([from] null): the
  /// popup closes, every owed reward is paid (`menu.levels.claim()`), the
  /// coins fly into the pill and count up, and the home emblem upgrades
  /// with a pop. ✕ claims too — the reward is never lost.
  Future<void> claimLevelUp({Rect? from}) async {
    final popup = _levelUpPopup;
    if (popup == null) return;
    _levelUpPopup = null;
    popBack(_levelUpBack);
    popup.active = false;
    sound.play(from == null ? Sfx.skClose : Sfx.skTap);
    fadeOpacity(
      popup,
      from: popup.opacity,
      to: 0,
      duration: Config.popupFadeDuration * 2,
      removeOnDone: true,
    );
    final level = popup.pending.toLevel;
    _home?.holdLevel(popup.pending.fromLevel);
    // The pill keeps its number until the coins land; the home emblem's
    // upgrade pop follows the finished count-up (§4.3).
    final reward = CoinRewardAnimation.levelReward(
      popup.pending.reward,
      level,
      from: from,
      onDone: () {
        if (state == GameState.start) _home?.playUpgradePop();
      },
    );
    playCoinReward(reward);
    _drainPopups();
    final paid = await menu.levels.claim();
    if (paid > 0) services.logLevelRewardClaimed(level, paid);
  }

  bool _levelUpBack() {
    unawaited(claimLevelUp());
    return true;
  }

  // --- No-ads popup (PRD-1 §5.1) ------------------------------------------

  /// The automatic session-start upsell (PO change 2026-10-05: the
  /// popup's only path — home-tile / Shop-banner taps buy directly now;
  /// the schedule is [_startSession] + NoAdsPopupPolicy). [reason] is the
  /// `noads_popup_shown` reason (videos / best / level / fallback; the
  /// debug force passes `forced`). No-op during a run, over another
  /// popup / the debug panel / a fake ad, or while the menus are
  /// transitioning; owners get a toast instead.
  void openNoAdsPopup({String? reason}) {
    if (_noAdsPopup == null && modalPopupOpen) {
      // Another popup is up: the upsell takes its turn after it (only one
      // offer ever waits).
      if (_noAdsOfferQueued) return;
      _noAdsOfferQueued = true;
      _queuePopup(() => true, () {
        _noAdsOfferQueued = false;
        openNoAdsPopup(reason: reason);
      });
      return;
    }
    if (_noAdsPopup != null ||
        _debugPanel != null ||
        _fakeAd != null ||
        state != GameState.start ||
        (!_homeInteractive && !_sceneOnTop(MenuScene.shop))) {
      return;
    }
    if (menu.noAds) {
      showToast('Already ad-free');
      return;
    }
    services.track('noads_popup_shown', {
      'trigger': _launchTrigger,
      'reason': ?reason,
    });
    final popup = NoAdsPopup(
      onDismiss: () => closeNoAdsPopup(),
      onBuy: () {
        _noAdsSource = 'popup';
        buyProduct(IapProduct.noAds);
      },
    );
    _noAdsPopup = popup;
    world.add(popup);
    fadeOpacity(popup, from: 0, to: 1, duration: Config.popupFadeDuration);
    pushBack(_noAdsPopupBack);
  }

  /// Closes the popup. [dismissed] (×, dim, Esc) logs
  /// `noads_popup_dismissed` and counts the dismissal (analytics only — no
  /// limit since PRD-menu-v4 §8; closing restarts the 4 h gap); a
  /// purchase closes it with `dismissed: false`.
  void closeNoAdsPopup({bool dismissed = true}) {
    final popup = _noAdsPopup;
    if (popup == null) return;
    _noAdsPopup = null;
    popBack(_noAdsPopupBack);
    popup.active = false;
    if (dismissed) {
      sound.play(Sfx.click);
      services.track('noads_popup_dismissed', {'trigger': _launchTrigger});
      unawaited(menu.noAdsPopup.markDismissed());
    }
    fadeOpacity(
      popup,
      from: popup.opacity,
      to: 0,
      duration: Config.popupFadeDuration,
      removeOnDone: true,
    );
    _drainPopups();
  }

  bool _noAdsPopupBack() {
    closeNoAdsPopup();
    return true;
  }

  // --- purchase feedback (PRD-home-v3 §5–7) -------------------------------

  /// §5: a coin pack was bought; called right before the coins are
  /// credited. In the menus the pack's coins burst from its coin stack in
  /// the Shop (the screen centre when the Shop is not on top, e.g. a late
  /// store callback) into the pill and count up; during a run the pill is
  /// hidden and simply shows the new balance later.
  void _onPackPurchased(IapProduct product) {
    if (state != GameState.start) return;
    final shop = _sceneOnTop(MenuScene.shop) && (_shop?.built ?? false)
        ? _shop
        : null;
    final from =
        shop?.packFor(product)?.stackRect ??
        Rect.fromLTWH(Config.worldWidth / 2, viewHeight / 2, 0, 0);
    playCoinReward(CoinRewardAnimation.pack(product, from: from));
  }

  /// §6: CANCELLED (always) / FAILED (any reason) over whatever is on
  /// screen; `sk_nocoins` on open. The analytics event is logged on
  /// arrival; the card itself waits its turn behind another popup, and a
  /// result arriving during a run waits until the menus are back.
  void openPurchaseResultPopup(
    IapProduct product,
    PurchaseProblem problem,
    String? code,
  ) {
    services.logPurchaseResultPopup(
      product.storeId,
      problem.analyticsName,
      code,
    );
    _queuePopup(() => _menusUp, () => _showPurchaseResult(problem));
  }

  void _showPurchaseResult(PurchaseProblem problem) {
    sound.play(Sfx.skNoCoins);
    final popup = PurchaseResultPopup(
      problem: problem,
      onDismiss: closePurchaseResultPopup,
    );
    _purchasePopup = popup;
    world.add(popup);
    fadeOpacity(popup, from: 0, to: 1, duration: Config.purchasePopupFadeIn);
    pushBack(_purchasePopupBack);
  }

  /// ✕ / OK / dim / Esc: `sk_close` and a 0.12 s fade. Balance and buttons
  /// are untouched.
  void closePurchaseResultPopup() {
    final popup = _purchasePopup;
    if (popup == null) return;
    _purchasePopup = null;
    popBack(_purchasePopupBack);
    popup.active = false;
    sound.play(Sfx.skClose);
    fadeOpacity(
      popup,
      from: popup.opacity,
      to: 0,
      duration: Config.purchasePopupFadeOut,
      removeOnDone: true,
    );
    _drainPopups();
  }

  bool _purchasePopupBack() {
    closePurchaseResultPopup();
    return true;
  }

  /// §7: a FRESH No-ads purchase (never a restore or re-delivery), right
  /// before the flag and the bonus are granted: the owned looks and the
  /// pill's number wait for the celebration, which opens as soon as the
  /// menus are up and no other popup is (popups queue in arrival order).
  void _onNoAdsPurchased() {
    _noAdsRevealHeld = true;
    _noAdsVideoHeld = true;
    // The +1 000 is credited now but counts in only at the celebration's
    // CLAIM: any other reward before it counts just its own coins.
    _coinPill
      ..hold()
      ..reserve(kNoAdsBonusCoins);
    _noAdsBonusReserved = true;
    _queuePopup(() => _menusUp, openNoAdsCelebration);
  }

  /// The celebration itself (also the debug panel's preview): `noads_unlock`,
  /// a white flash and a short shake (not under reduce motion), the popup,
  /// and at 0.43 s a confetti burst from the card plus a rain over the
  /// screen.
  void openNoAdsCelebration() {
    if (_noAdsCelebration != null) return;
    services.logNoAdsCelebrationShown(_noAdsSource);
    sound.play(Sfx.noadsUnlock);
    final motion = !reduceMotion;
    final popup = NoAdsCelebration(
      onClaim: () => _claimNoAdsBonus(claimed: true),
      onDismiss: () => _claimNoAdsBonus(claimed: false),
    );
    _noAdsCelebration = popup;
    world.add(popup);
    fadeOpacity(popup, from: 0, to: 1, duration: 0.16);
    pushBack(_noAdsCelebrationBack);
    if (motion) {
      world.add(ScreenFlash(size: Vector2(Config.worldWidth, viewHeight)));
      world.add(
        ScreenShake(
          camera.viewfinder,
          keysX: _celebrationShakeX,
          keysY: _celebrationShakeY,
          duration: Config.noAdsCelebrationShake,
          delay: Config.noAdsCelebrationShakeDelay,
        ),
      );
      _after(Config.noAdsCelebrationConfettiAt, () {
        if (!identical(_noAdsCelebration, popup) || !popup.isLoaded) return;
        world
          ..add(
            ConfettiBurst.burst(
              origin: popup.confettiOrigin,
              count: Config.noAdsCelebrationConfetti,
              speed: 340,
              up: 200,
              driftX: 0,
              stars: true,
              random: coinFlyRandom,
              priority: 27,
            ),
          )
          ..add(
            ConfettiBurst.rain(
              count: Config.noAdsCelebrationConfetti,
              random: coinFlyRandom,
              priority: 27,
            ),
          );
      });
    }
  }

  static const List<(double, double)> _celebrationShakeX = [
    (0, 0),
    (.2, -5),
    (.4, 4),
    (.6, -3),
    (.8, 2),
    (1, 0),
  ];
  static const List<(double, double)> _celebrationShakeY = [
    (0, 0),
    (.2, 3),
    (.4, -3),
    (.6, 2),
    (.8, -1),
    (1, 0),
  ];

  bool _noAdsCelebrationBack() {
    _claimNoAdsBonus(claimed: false);
    return true;
  }

  /// CLAIM or ✕ / dim / Esc (the bonus is never lost): the popup fades out
  /// and the +1 000 (already credited at purchase, the pill held its old
  /// number) flies from the CLAIM button into the pill and counts up; 0.25 s
  /// later the owned looks flip.
  void _claimNoAdsBonus({required bool claimed}) {
    final popup = _noAdsCelebration;
    if (popup == null) return;
    _noAdsCelebration = null;
    popBack(_noAdsCelebrationBack);
    popup.active = false;
    sound.play(claimed ? Sfx.skTap : Sfx.skClose);
    services.logNoAdsBonusClaimed();
    final from = popup.isLoaded
        ? popup.claimRect
        : Rect.fromLTWH(Config.worldWidth / 2, viewHeight / 2, 0, 0);
    fadeOpacity(
      popup,
      from: popup.opacity,
      to: 0,
      duration: Config.noAdsCelebrationFadeOut,
      removeOnDone: true,
    );
    final reservation = _noAdsBonusReserved ? kNoAdsBonusCoins : 0;
    _noAdsBonusReserved = false;
    playCoinReward(
      CoinRewardAnimation.noAdsBonus(
        from: from,
        reservation: reservation,
        onDone: () => _after(Config.noAdsFlipDelay, _flipNoAdsOwned),
      ),
    );
    _drainPopups();
  }

  /// §7 owned states, `noads_stamp`: the Shop banner flips to AD-FREE ·
  /// THANK YOU and, 0.7 s later, GET loses its video icon; on home the
  /// No-ads tile flips to ✓ AD-FREE and the slot's video icon shrinks
  /// away. Screens opened later simply show the owned state.
  void _flipNoAdsOwned() {
    if (!_noAdsRevealHeld && !_noAdsVideoHeld) return;
    _noAdsRevealHeld = false;
    final shop = _sceneOnTop(MenuScene.shop) ? _shop : null;
    final home = _home;
    if (shop != null || home != null) sound.play(Sfx.noadsStamp);
    shop?.banner.flipToOwned();
    if (home != null && home.isLoaded) {
      home.noAdsTile.flipToOwned();
      home.slotButton.shrinkVideo();
    }
    void dropVideo() {
      _noAdsVideoHeld = false;
      final current = _sceneOnTop(MenuScene.shop) ? _shop : null;
      if (current != null && current.built) current.freeCoins.shrinkVideo();
    }

    if (shop != null) {
      _after(Config.noAdsFlipHomeDelay, dropVideo);
    } else {
      dropVideo();
    }
  }

  /// Runs [action] after [seconds] of game time.
  void _after(double seconds, void Function() action) => world.add(
    TimerComponent(period: seconds, removeOnFinish: true, onTick: action),
  );

  // --- rewarded ads -----------------------------------------------------------

  /// Plays a rewarded ad for [placement]. With the in-memory fakes and
  /// [Monetization.showFakeAdOverlay] on (the Linux / desktop app shell),
  /// a visible [FakeAdOverlay] stands in for the ad; otherwise (tests,
  /// AdMob) this is just `ads.show`. Callers check `isAvailable` first.
  ///
  /// Analytics (PRD-1 §6/§8): `ad_rewarded_shown` fires as soon as the ad
  /// is DISPLAYED — overlay mounted, or the `onShown` hook of
  /// [RewardedAds.show] (AdMob `onAdShowedFullScreenContent`) — including
  /// an ad closed before the reward (the show rate must not depend on the
  /// outcome); `ad_reward_earned` fires when the reward is actually earned.
  Future<AdResult> showRewardedAd(AdPlacement placement) async {
    _adsShowing++;
    try {
      final result = await _showRewardedAd(placement);
      // PRD-menu-v4 §8: completed rewarded videos feed the upsell trigger.
      if (result == AdResult.completed && isLoaded) {
        unawaited(menu.noAdsPopup.recordRewardedVideo());
      }
      return result;
    } finally {
      _adsShowing--;
    }
  }

  Future<AdResult> _showRewardedAd(AdPlacement placement) async {
    final ads = monetization.ads;
    // Exactly one impression per displayed ad, logged at display time.
    var shownLogged = false;
    void logShown() {
      if (shownLogged) return;
      shownLogged = true;
      services.track('ad_rewarded_shown', {
        'placement': placement.analyticsName,
      });
    }

    if (!monetization.showFakeAdOverlay ||
        !monetization.isFake ||
        _fakeAd != null) {
      final result = await ads.show(placement, onShown: logShown);
      // Safety net for an implementation that never reports display: a
      // completed or dismissed ad was displayed, so it still counts (once).
      if (result == AdResult.completed || result == AdResult.dismissed) {
        logShown();
      }
      if (result == AdResult.completed) {
        services.track('ad_reward_earned', {
          'placement': placement.analyticsName,
        });
      }
      return result;
    }
    // The fake's scripted outcome (it also counts the ad); unavailable
    // shows no overlay at all. The overlay below is the display, so the
    // fake's own onShown is not used here.
    final scripted = await ads.show(placement);
    if (scripted == AdResult.unavailable) return scripted;
    final overlay = FakeAdOverlay(
      placement: placement,
      fails: scripted != AdResult.completed,
    );
    _fakeAd = overlay;
    world.add(overlay);
    fadeOpacity(overlay, from: 0, to: 1, duration: Config.popupFadeDuration);
    pushBack(_fakeAdBack);
    // Succeed mode puts a playable test ad on screen; the fail variant
    // only shows a load error, so it is not a displayed ad.
    if (scripted == AdResult.completed) {
      logShown();
    }
    final result = await overlay.result;
    _fakeAd = null;
    popBack(_fakeAdBack);
    fadeOpacity(
      overlay,
      from: overlay.opacity,
      to: 0,
      duration: Config.popupFadeDuration,
      removeOnDone: true,
    );
    if (result == AdResult.completed) {
      services.track('ad_reward_earned', {
        'placement': placement.analyticsName,
      });
    }
    return result;
  }

  /// Esc on the fake ad: closes it early (no reward unless already
  /// granted).
  bool _fakeAdBack() {
    _fakeAd?.close();
    return true;
  }

  /// Invite tile: system share sheet with the store link (PRD-1 §3.4, no
  /// reward).
  void invite() {
    if (!_homeInteractive) return;
    sound.play(Sfx.skTap);
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
      if (state == GameState.gameOver) {
        // Back from a finished run is the panel's replay: a fresh home
        // arrival (PRD-1 §3.6), once the panel accepts input.
        if (_gameOverPanel?.canContinue ?? false) {
          goHome();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
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
    if (!debugAvailable ||
        state != GameState.start ||
        _debugPanel != null ||
        _fakeAd != null ||
        _runStarting) {
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

  /// The toast on screen (tests; null once it has gone).
  ServiceMessage? get toastMessage {
    final message = _message;
    if (message == null ||
        message.parent == null ||
        message.isRemoving ||
        message.isRemoved) {
      return null;
    }
    return message;
  }

  /// [product]'s purchase resolved: its "Purchase pending…" toast goes at
  /// once, so it never sits under the celebration or the result popup.
  void _dismissPendingToast(IapProduct product) {
    final pending = _pendingToast;
    if (pending == null || pending.$1 != product) return;
    _pendingToast = null;
    final message = pending.$2;
    if (message.parent != null) message.removeFromParent();
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
      fadeOpacity(
        adapter,
        from: adapter.opacity,
        to: 0,
        duration: Config.gameplayFadeDuration,
      );
    }

    // Interim coin rule (PRD-1 §3.1): 1 coin per point, credited at game
    // over.
    final coins = score;
    if (coins > 0) {
      unawaited(menu.wallet.add(coins, CoinSource.play));
    }

    final previousBest = storage.bestScore;
    final previousLevel = menu.levels.level;
    storage.incrementGamesPlayed();
    unawaited(storage.saveLastScore(score));
    if (score > storage.bestScore) {
      storage.saveBestScore(score);
    }
    unawaited(
      menu.noAdsPopup.recordRun(
        newBest: score > previousBest,
        newLevel: menu.levels.level > previousLevel,
      ),
    );
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
    fadeOpacity(_hud, from: 1, to: 0, duration: Config.gameplayFadeDuration);
  }

  // --- buttons -----------------------------------------------------------

  void toggleSound() {
    sound.muted = !sound.muted;
    storage.saveMuteSound(sound.muted);
    _settingsPanel?.setMuted(sound.muted);
    sound.play(Sfx.click); // only audible when unmuting
  }

  /// The RUMBLE switch (PRD-2 §3.33, PRD-home-v3 §8): applies at once and
  /// persists; switching it on gives one knock, off is silent.
  void setRumble(bool on) {
    if (rumble.on == on) return;
    rumble.on = on;
    unawaited(storage.saveRumble(on));
    services.logRumbleToggle(on);
    _settingsPanel?.setRumble(on);
    if (on) rumble.knock();
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
    sound.play(Sfx.skTab); // §8.2 gear
    menuScene = MenuScene.settings;
    _leaveHome();
    final settings = SettingsPanel(
      muted: sound.muted,
      musicVolume: sound.musicVolume,
      onToggleSound: toggleSound,
      onMusicVolume: setMusicVolume,
      onBack: closeSettings,
      onPrivacyPolicy: openPrivacyPolicy,
      onRestorePurchases: restorePurchases,
      rumble: rumble.on,
      onToggleRumble: () => setRumble(!rumble.on),
    );
    _settingsPanel = settings;
    // PRD-home-v3 §8: the settings back button is the shared corner box
    // (the gear turns into the chevron); the coin pill fades with home.
    _chromeHosts.add(settings);
    _cornerHold = true;
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
    _cornerHold = true;
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
      _chromeHosts.remove(oldHome);
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
    // (Home polls best / last / level from the storage.)
    storage.load().then((_) {
      sound.muted = storage.muteSound;
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
  Future<void> showLeaderboard({Sfx sfx = Sfx.click}) async {
    // A home action: like the tiles, the row is blocked while a run is
    // starting or a rewarded ad is in flight. The game-over panel's
    // trophy is not on the home screen and stays available.
    if (state == GameState.start && !_homeInteractive) return;
    sound.play(sfx);
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
    // Home: bare text in the gap above the tiles (as before). Over the
    // No-ads popup: below its card; on the other menu screens (Shop,
    // Settings) a chip above the bottom spikes; runs / game over: the 1.0
    // bottom-centre spot.
    final popup = _noAdsPopup != null;
    final menuScreen =
        state == GameState.start && menuScene != MenuScene.home;
    final message = ServiceMessage(
      message: text,
      chip: popup || menuScreen,
      position: popup
          ? Config.noAdsToastPositionFor(viewHeight)
          : menuScreen
          ? Config.menuScreenToastPositionFor(viewHeight)
          : state == GameState.start
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

  // --- shared menu chrome ----------------------------------------------------

  /// Drives the shared coin pill / corner box from the screens that show
  /// them ([_chromeHosts]). On a hop between two such screens (home <->
  /// Shop <-> Skins, in any order and however fast: [_chromeHold]) the
  /// chrome stays fully opaque; otherwise it follows the hosts' summed
  /// opacity, i.e. fades with a screen that is entered from / left for a
  /// scene without it (settings, START, replay). The corner glyph is the
  /// hosts' opacity-weighted gear / back mix.
  /// The transparent tap target over [_cornerBox] on the current screen.
  MenuButton? get _cornerButton {
    final home = _home;
    if (home != null) return home.isLoaded ? home.gearButton : null;
    final settings = _settingsPanel;
    if (settings != null) return settings.isLoaded ? settings.backButton : null;
    final MenuScreen? screen = _shop ?? _skinShop ?? _levels;
    return screen != null && screen.built ? screen.backButton : null;
  }

  void _updateMenuChrome() {
    final current = _home ?? _shop ?? _skinShop ?? _levels ?? _settingsPanel;
    _chromeHosts.removeWhere(
      (host) =>
          !identical(host, current) &&
          (host.isRemoving ||
              host.isRemoved ||
              (host as OpacityProvider).opacity <= 0),
    );
    if (current == null || _chromeHosts.length <= 1) {
      _chromeHold = false;
      _cornerHold = false;
    }
    var homeShare = 0.0;
    var total = 0.0;
    var pillTotal = 0.0; // settings has the corner box but no pill
    for (final host in _chromeHosts) {
      final opacity = (host as OpacityProvider).opacity;
      total += opacity;
      // Settings and LEVELS have no coin pill (PRD-home-v3 §4.4): the pill
      // fades with the screens around them that show one.
      if (host is! SettingsPanel && host is! LevelsScreen) {
        pillTotal += opacity;
      }
      if (host is HomeScreen) homeShare += opacity;
    }
    _coinPill
      ..opacity = _chromeHold ? 1.0 : pillTotal.clamp(0.0, 1.0)
      ..balance = menu.wallet.balance;
    _cornerBox
      ..opacity = _chromeHold || _cornerHold ? 1.0 : total.clamp(0.0, 1.0)
      ..gearMix = total > 0 ? homeShare / total : 1
      ..pressScale = _cornerButton?.pressScale ?? 1;
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
    // One clamped clock for the whole simulation (Config.maxFrameStep):
    // super.update runs the component tree (Forge2D world step, bird,
    // pipes, camera) with this same dt, and everything below uses it too,
    // so a stalled frame slows the game uniformly instead of letting the
    // spawner or fades run ahead of the bodies.
    dt = min(dt, Config.maxFrameStep);
    _clock += dt;
    super.update(dt);
    _purchases?.update(dt);
    _drainPopups();

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
    _updateMenuChrome();
    final levelsIn = _levelsOpenIn;
    if (levelsIn != null) {
      _levelsOpenIn = levelsIn - dt;
      if (_levelsOpenIn! <= 0) openLevels();
    }
    if (state == GameState.start) _checkLevelUp(dt);

    if (state == GameState.playing) {
      _spawnTimer += dt;
      if (_spawnTimer >= Config.pipeSpawnInterval) {
        _spawnTimer = 0;
        // Difficulty ramp: the gap shrinks as the score climbs, plus a
        // bounded random variance on top (the curve value is the MINIMUM
        // gap; the draw is capped so both pipe stubs can stay >= 40 pt).
        final gap = Config.gapForPipe(score, _pipeRandom.nextDouble(), viewHeight);
        // The spawn band keeps both pipe stubs >= 40 pt: the top stub can
        // never hide fully behind the ceiling spikes (a pipe is always
        // visible), the bottom stub never sinks into the ground spikes.
        final minY = Config.gapBottomMinFor(gap);
        final maxY = Config.gapBottomMaxFor(gap, viewHeight);
        var gapBottomY = minY + _pipeRandom.nextDouble() * (maxY - minY);
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

/// A modal popup waiting for its turn (see FlappySpikesGame._queuePopup).
class _PopupRequest {
  _PopupRequest(this.canOpen, this.open);

  final bool Function() canOpen;
  final void Function() open;
}
