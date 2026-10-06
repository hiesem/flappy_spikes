import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show Color, Paint, PlatformDispatcher;

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
import '../components/noads_popup.dart';
import '../components/pipe_pair.dart';
import '../components/score_hud.dart';
import '../components/settings_panel.dart';
import '../components/shop/shop_screen.dart';
import '../components/skins/skin_shop_screen.dart';
import '../components/spike_strip.dart';
import '../components/tap_catcher.dart';
import '../components/ui/service_message.dart';
import '../menu/free_coins_policy.dart';
import '../menu/menu_state.dart';
import '../menu/powerup_slot.dart';
import '../menu/skin_catalog.dart';
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
import 'sound.dart';
import 'storage.dart';
import 'tintable.dart';

/// Game states from SPEC.md. `replay` is a transition that returns to
/// [GameState.start] after a full reset with a 0.3 s white fade.
enum GameState { start, playing, gameOver }

/// Which menu screen is up while in [GameState.start] (meaningless in the
/// other states).
enum MenuScene { home, settings, shop, skins }

class FlappySpikesGame extends Forge2DGame with KeyboardEvents {
  FlappySpikesGame({
    double? worldHeight,
    GameServices? services,
    Monetization? monetization,
    DateTime Function()? clock,
    this.soundEnabled = true,
  }) : services = services ?? GameServices(),
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
  late final CoinPill _coinPill;
  late final MenuCornerBox _cornerBox;

  /// Every home / Shop / Skins screen still on screen (the current one and
  /// any fading out): the shared chrome's opacity follows them.
  final List<PositionComponent> _chromeHosts = [];

  /// Set by a screen-to-screen hop between two screens that both show the
  /// chrome; it then stays fully opaque until the old screen is gone.
  bool _chromeHold = false;
  GameOverPanel? _gameOverPanel;
  SettingsPanel? _settingsPanel;
  ShopScreen? _shop;
  SkinShopScreen? _skinShop;
  bool _itemPurchaseRunning = false;
  NoAdsPopup? _noAdsPopup;
  /// The popup's only context since 2026-10-05 (analytics payload).
  static const String _launchTrigger = 'launch';
  bool _freeCoinsBusy = false;
  DebugPanel? _debugPanel;
  FakeAdOverlay? _fakeAd;
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

  /// Test / debug override of [reduceMotion] (null = follow the OS).
  bool? reduceMotionOverride;

  /// The OS "reduce motion" / remove-animations setting (PRD-menu-v2 §8.4):
  /// no flash, shake, rays or pulsing; bob and flap stay.
  bool get reduceMotion =>
      reduceMotionOverride ??
      PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  /// The No-ads popup while it is up (null otherwise).
  NoAdsPopup? get noAdsPopup => _noAdsPopup;

  /// True while a free-coins rewarded ad is playing.
  bool get freeCoinsBusy => _freeCoinsBusy;

  /// The fake rewarded-ad overlay while it is up (null otherwise).
  FakeAdOverlay? get fakeAdOverlay => _fakeAd;

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
    )..start();
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

    // No-ads upsell on launch: from the day after install, max once a day,
    // until three dismissals, never to owners (NoAdsPopupPolicy).
    if (menu.noAdsPopup.shouldShowOnLaunch()) {
      openNoAdsPopup();
      unawaited(menu.noAdsPopup.markShown());
    }
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
    if (state == AppLifecycleState.resumed) {
      unawaited(monetization.iap.refresh());
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
    final home = HomeScreen(
      bestScore: storage.bestScore,
      gamesPlayed: storage.gamesPlayed,
    );
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
    sound.play(Sfx.click);
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
    sound.play(Sfx.click);
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
      _ => false,
    };
  }

  /// Shop tile / coin pill: fades the home screen (or the Skins screen)
  /// out and the Shop in. The pill ([scrollToCoins]) opens it at the coin
  /// packs; pressed while already in the Shop it just scrolls there.
  /// [source] defaults to "pill" / "tile" (`shop_open` analytics).
  void openShop({bool scrollToCoins = false, String? source}) {
    if (_sceneOnTop(MenuScene.shop)) {
      if (scrollToCoins) {
        sound.play(Sfx.click);
        _shop?.scrollToCoins();
      }
      return;
    }
    if (_shop != null) return;
    final fromSkins = _sceneOnTop(MenuScene.skins);
    if (!_homeInteractive && !fromSkins) return;
    sound.play(Sfx.click);
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
    sound.play(Sfx.click);
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
      await menu.wallet.add(FreeCoinsPolicy.reward, CoinSource.rewarded);
    } finally {
      _freeCoinsBusy = false;
    }
    showToast('+${FreeCoinsPolicy.reward} coins');
  }

  /// A coin pack (Shop) or No ads (popup price button): starts the store
  /// purchase; [Purchases] grants it when the store confirms.
  Future<void> buyProduct(IapProduct product) async {
    if (state != GameState.start) return;
    sound.play(Sfx.click);
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
    await buyProduct(IapProduct.noAds);
  }

  /// "RESTORE PURCHASES" (Shop / Settings).
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
    sound.play(Sfx.click);
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
  /// tried on (on [layer]'s tab — the open one for grid taps).
  void tapItem(SkinLayer layer, String id) {
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
    if (screen.tryOnId == id) return;
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
  Future<void> buyTriedOnItem() async {
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
    final before = menu.wallet.balance;
    _itemPurchaseRunning = true;
    final ItemPurchaseResult result;
    try {
      result = await items.purchase(item.layer, item.id);
    } finally {
      _itemPurchaseRunning = false;
    }
    if (result != ItemPurchaseResult.purchased) return;
    services.logItemPurchase(item.layer, item.id, item.rarity, item.price);
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

  // --- No-ads popup (PRD-1 §5.1) ------------------------------------------

  /// The automatic launch upsell (PO change 2026-10-05: the popup's only
  /// path — home-tile / Shop-banner taps buy directly now). No-op during a
  /// run, over another popup / the debug panel / a fake ad, or while the
  /// menus are transitioning; owners get a toast instead.
  void openNoAdsPopup() {
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
    services.track('noads_popup_shown', {'trigger': _launchTrigger});
    final popup = NoAdsPopup(
      onDismiss: () => closeNoAdsPopup(),
      onBuy: () => buyProduct(IapProduct.noAds),
    );
    _noAdsPopup = popup;
    world.add(popup);
    fadeOpacity(popup, from: 0, to: 1, duration: Config.popupFadeDuration);
    pushBack(_noAdsPopupBack);
  }

  /// Closes the popup. [dismissed] (×, dim, Esc) logs
  /// `noads_popup_dismissed` and counts toward the policy's dismissal cap
  /// (the BRIEF stops automatic upsells after three manual dismissals
  /// too); a purchase closes it with `dismissed: false`.
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
  }

  bool _noAdsPopupBack() {
    closeNoAdsPopup();
    return true;
  }

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
    fadeOpacity(_hud, from: 1, to: 0, duration: Config.gameplayFadeDuration);
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
      onRestorePurchases: restorePurchases,
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
    // A home action: like the tiles, the row is blocked while a run is
    // starting or a rewarded ad is in flight. The game-over panel's
    // trophy is not on the home screen and stays available.
    if (state == GameState.start && !_homeInteractive) return;
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
  void _updateMenuChrome() {
    final current = _home ?? _shop ?? _skinShop;
    _chromeHosts.removeWhere(
      (host) =>
          !identical(host, current) &&
          (host.isRemoving ||
              host.isRemoved ||
              (host as OpacityProvider).opacity <= 0),
    );
    if (current == null || _chromeHosts.length <= 1) _chromeHold = false;
    var homeShare = 0.0;
    var total = 0.0;
    for (final host in _chromeHosts) {
      final opacity = (host as OpacityProvider).opacity;
      total += opacity;
      if (host is HomeScreen) homeShare += opacity;
    }
    final opacity = _chromeHold ? 1.0 : total.clamp(0.0, 1.0);
    _coinPill
      ..opacity = opacity
      ..balance = menu.wallet.balance;
    _cornerBox
      ..opacity = opacity
      ..gearMix = total > 0 ? homeShare / total : 1;
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
    super.update(dt);
    _purchases?.update(dt);

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
