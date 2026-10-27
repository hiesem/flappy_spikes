import 'dart:async';
// region P26-G2c
import '../components/progression/streak_lost_popup.dart';
// endregion
// region P26-G2b
import 'dart:math' as math;
import '../components/progression/streak_strip.dart';
import '../components/home/menu_primitives.dart' show MenuTag;
import '../progression/day_streak.dart';
import '../run/effects/fetch_flight.dart';
// endregion
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show Color, Paint, PlatformDispatcher, Rect;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        visibleForTesting,
        ValueListenable,
        ValueNotifier,
        debugPrint,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, KeyEventResult;
import 'package:url_launcher/url_launcher.dart';

import '../achievements/achievement_toast.dart'; // P231-E
import '../achievements/achievements.dart'; // P231-E
import '../components/bird.dart';
import '../components/debug_panel.dart';
import '../components/delete_data_popup.dart';
import '../components/fake_ad_overlay.dart';
import '../components/home/home_screen.dart';
import '../components/home/menu_primitives.dart' show MenuButton;
import '../components/levels/level_up_popup.dart';
import '../components/levels/levels_screen.dart';
import '../components/menu_drag_dispatcher.dart';
import '../components/menu_screen_chrome.dart' show MenuScreen, MenuScrollArea;
import '../components/noads_celebration.dart';
import '../components/noads_popup.dart';
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
import '../menu/ad_grace.dart'; // PRD-2.3 §18
import '../menu/free_coins_policy.dart';
import '../menu/home_mode.dart';
import '../menu/menu_state.dart';
import '../menu/powerup_slot.dart';
import '../menu/wallet.dart';
import '../run/backdrop/run_backdrop.dart';
import '../run/debug/autopilot.dart';
import '../run/debug/debug_overlay.dart';
import '../run/debug/force_menu.dart';
import '../services/rating_prompt.dart'; // PRD-2.3 §23
import '../services/soak.dart';
import '../services/redact.dart';
import 'idle_frames.dart';
import '../run/director/plans.dart';
import '../run/elements.dart';
import '../run/items/puzzle.dart';
import '../run/mistakes.dart';
import '../run/run_controller.dart';
import '../run/run_scaled_world.dart';
import '../run/run_setup.dart';
import '../run/run_state.dart' show BigHoopsState;
import '../run/run_summary.dart';
import '../run/showcase/showcase_plan.dart';
import '../run/screens/post_run_flow.dart';
import '../run/config/revive_config.dart';
import '../run/debug/run_stats.dart';
import '../run/hud/first_run_hint.dart';
import '../run/hud/run_hud.dart';
import '../levels/level_progress.dart' show PendingLevelUp;
import '../run/run_events.dart' show HighlightStarted, ReviveKind;
import '../run/screens/pause_screen.dart';
import '../run/screens/phoenix_rise.dart' show ReviveDim;
import '../run/screens/post_run_screens.dart';
import '../run/screens/revive_ladder.dart';
import '../run/screens/revive_screen.dart';
import '../run/screens/shop_overlay.dart';
import '../run/screens/results_screen.dart';
import '../run/screens/versus_intro.dart'; // WP-5b
import '../run/config/versus_config.dart'; // WP-5b
import '../versus/opponent.dart'; // WP-5b
// region P26-E2
import '../versus/duel.dart';
// endregion
import '../versus/diagnostics.dart'; // P22-2
import '../run/screens/bonus_screen.dart'; // WP-4a
import '../services/e2e.dart';
import '../services/ftue_tracker.dart';
import '../versus/timeline.dart';
import '../components/sticker_avatar.dart'; // WP-AV
import '../services/versus_service.dart';
// region P26-LB1
import '../leaderboard/lb_service.dart';
// endregion
// region P26-LB2
import '../leaderboard/lb_models.dart';
import '../leaderboard/lb_queue.dart';
import '../leaderboard/lb_submit_hook.dart';
// endregion
import '../services/ads_service.dart';
import '../services/audio_focus.dart';
import '../services/game_services.dart';
import '../services/iap_service.dart';
import '../services/monetization.dart';
import '../services/reminders.dart';
import '../services/tester.dart';
import '../skins/catalog.dart';
import '../skins/item_store.dart';
import '../skins/look.dart';
import 'config.dart';
import 'diag.dart';
import 'fade.dart';
import 'home_moments.dart';
import 'palettes.dart';
import 'playfield.dart';
import 'playfield_viewport.dart';
import 'purchases.dart';
import '../services/app_info.dart';
import '../share/share_card.dart' show ShareCardData; // PRD-2.3 §2
import '../share/share_content.dart'; // PRD-2.3 §2
import '../versus/nickname.dart' show generateNickname; // PRD-2.3 §2.2
import '../versus/custom_name.dart'; // WP-NAME
import 'rumble.dart';
import 'music_guard.dart';
import 'sound.dart';
import 'storage.dart';
import 'tintable.dart';

/// Game states from SPEC.md. `replay` is a transition that returns to
/// [GameState.start] after a full reset with a 0.3 s white fade.
///
/// PRD-2 (ARCH §2.3): `versusIntro`, `paused`, `dying`, `reviving` and
/// `bonus` are entered by later WPs; `results` is the results page (WP-2e,
/// PRD-2 §5.10; the 1.0 `gameOver`).
enum GameState {
  start,
  playing,
  results,
  versusIntro,
  paused,
  dying,
  reviving,
  bonus,
}

/// Which menu screen is up while in [GameState.start] (meaningless in the
/// other states).
enum MenuScene { home, settings, shop, skins, levels }

class FlappySpikesGame extends Forge2DGame with KeyboardEvents {
  FlappySpikesGame({
    double? worldHeight,
    GameServices? services,
    Monetization? monetization,
    Reminders? reminders,
    DateTime Function()? clock,
    this.soundEnabled = true,
    bool? rumbleEnabled,
    VersusService? versus,
    // region P26-LB1
    this.leaderboard = const NoopLeaderboardService(),
    // endregion
    RatingPrompt? rating,
    ShowcasePlan? showcasePlan,
    ShowcaseProgress? showcaseProgress,
    // region P26-B1
    this.showcaseFactory,
    // endregion
    FtueTracker? ftueTracker,
    HomeMoments? homeMoments,
  }) : services = services ?? GameServices(),
       versus = versus ?? NoopVersusService(),
       rating = rating ?? RatingPrompt(),
       reminders = reminders ?? const NoopReminders(),
       rumble = Rumble(hardware: rumbleEnabled ?? soundEnabled),
       monetization = monetization ?? Monetization(),
       // region P26-B1
       _showcasePlan = showcasePlan ?? const InertShowcasePlan(),
       _showcaseProgress = showcaseProgress ?? const InertShowcaseProgress(),
       // endregion
       homeMoments = homeMoments ?? HomeMomentBudget(),
       storage = GameStorage(clock: clock),
       // WP-TAB: a wide screen (tablet) is 568 pt high in game points.
       screenHeight = max(
         worldHeight ?? Config.worldHeight,
         Config.minViewHeight,
       ),
       viewWidth = Config.viewWidthFor(worldHeight ?? Config.worldHeight),
       _screenWidthPoints =
           (worldHeight ?? Config.worldHeight) >= Config.minViewHeight
           ? Config.worldWidth
           : Config.worldWidth *
                 Config.minViewHeight /
                 (worldHeight ?? Config.worldHeight),
       _viewHeight = _clampViewHeight(worldHeight ?? Config.worldHeight),
       super(
         world: RunScaledWorld(gravity: Vector2(0, Config.gravity)),
         gravity: Vector2(0, Config.gravity),
         // PRD-2.2 §7.5.2: a fixed 320 pt wide window whose height follows
         // setPlayfieldHeight (FixedResolutionViewport with a settable
         // resolution).
         camera: CameraComponent(
           viewport: PlayfieldViewport(
             resolution: Vector2(
               Config.viewWidthFor(worldHeight ?? Config.worldHeight),
               _clampViewHeight(worldHeight ?? Config.worldHeight),
             ),
           ),
         ),
         zoom: 1,
       ) {
    _ftueTracker =
        ftueTracker ??
        PersistedFtueTracker(services: this.services, storage: storage);
    // The game uses 1 Forge2D world unit = 1 logical point (SPEC.md). The
    // engine's default per-step translation clamp (2.0 units, tuned for
    // meter-scale worlds) would otherwise cap every body at ~120 pt/s at
    // 60 fps, breaking flap physics and the 200 pt/s scroll. Raise it well
    // beyond anything reachable (bird speeds stay in the low hundreds).
    maxTranslation = 10000;
    maxTranslationSquared = maxTranslation * maxTranslation;
    (world as RunScaledWorld).coveredBelowSource = _worldCoveredBelow;
    // The knock throttle runs on game time (tests step it).
    rumble.clock = () => _clock;
    // PRD-2.2 §33.4 item 5: the engine stops in the background and resumes
    // on return (Flame's default, kept explicit: see lifecycleStateChange).
    pauseWhenBackgrounded = true;
    achievements = AchievementTracker(
      storage: storage,
      services: this.services,
    );
  }

  /// PRD-2.3.1 §12.3 the achievement tracker (local truth + platform sync).
  late final AchievementTracker achievements;

  /// PRD-2.6 M1 seams; their default implementations are inert.
  // region P26-B1
  /// Production opts in after storage loads; tests and capture tools stay inert.
  final ShowcaseShow Function(GameStorage)? showcaseFactory;
  ShowcasePlan _showcasePlan;
  ShowcaseProgress _showcaseProgress;
  ShowcasePlan get showcasePlan => _showcasePlan;
  ShowcaseProgress get showcaseProgress => _showcaseProgress;
  // endregion
  late final FtueTracker _ftueTracker;

  /// PRD-2.6 WP-A: production always uses the persisted tracker. Tests can
  /// inject an inert or recording implementation.
  FtueTracker get ftueTracker => _ftueTracker;
  final HomeMoments homeMoments;

  static double _clampViewHeight(double height) =>
      height.clamp(Config.minViewHeight, Config.maxViewHeight);

  /// PRD-2.2 §7.5.5: the visible run height with a banner is clamped to
  /// [Config.minRunViewHeight]..[Config.maxViewHeight].
  static double clampRunViewHeight(double height) =>
      height.clamp(Config.minRunViewHeight, Config.maxViewHeight);

  /// Playfield (layout) height in points: 320/aspect on the device, clamped
  /// to [Config.minViewHeight]..[Config.maxViewHeight]. The spike strips are
  /// pinned to the top/bottom edges, so there are no letterbox bars.
  ///
  /// PRD-2.2 §7.5.2: settable through [setPlayfieldHeight] only (START with
  /// a banner, the Home arrival). In a run with a banner it is the visible
  /// height + [stripDrop]: the bottom [stripDrop] points (the lowered spike
  /// strip's base, §7.5.4) lie under the bottom edge of the game view, so
  /// every run layout keeps its 44 pt bottom strip while only 24 pt of it
  /// show ([bottomStripInset]).
  double get viewHeight => _viewHeight;
  double _viewHeight;

  /// The full screen height (320 / aspect, unclamped) from the app shell.
  /// WP-TAB: at least 568 (a wide screen is 568 pt high in game points).
  final double screenHeight;

  // region WP-TAB — tablets widen the world
  /// WP-TAB: the playfield width (pt): 320 on phones, `568 × aspect` on
  /// wider screens, up to [Config.maxViewWidth] (3:4).
  final double viewWidth;

  /// WP-TAB: the screen's full width in game points (beyond 3:4 it is
  /// wider than [viewWidth]: side bars).
  final double _screenWidthPoints;

  /// WP-TAB: the extra width over the phone's 320 pt (0 on phones).
  double get extraWidth => viewWidth - Config.worldWidth;

  /// WP-TAB: the camera's resting position: the 320 pt menu column is
  /// centred on the screen (x −extra / 2). Shakes move the viewfinder
  /// relative to it.
  Vector2 get cameraBase => Vector2(-extraWidth / 2, 0);

  /// WP-TAB: the camera's current shake offset (viewfinder − [cameraBase]).
  Vector2 get cameraShake => camera.viewfinder.position - cameraBase;

  /// WP-TAB: a rect [height] high that covers the whole screen from any
  /// 320 pt column (centred menus, the run column, the viewport HUD):
  /// x from −extra to 320 + extra. Full-screen fills (backgrounds, dims,
  /// flashes) use it; the view clips the rest.
  Rect bleedRect(double height, {double top = 0}) => Rect.fromLTWH(
    -extraWidth,
    top,
    Config.worldWidth + 2 * extraWidth,
    height,
  );

  /// WP-TAB: the visible screen in run coordinates (the run column: run
  /// world content and the run HUD): x from −extra to 320.
  Rect runScreenRect(double height) =>
      Rect.fromLTWH(-extraWidth, 0, viewWidth, height);
  // endregion WP-TAB

  /// PRD-2.2 §7.5.4: how far the bottom spike strip is lowered under the
  /// view's bottom edge ([Config.bannerStripDrop] in a run with a banner,
  /// else 0).
  double get stripDrop => _stripDrop;
  double _stripDrop = 0;

  /// PRD-2.2 §7.5.2: the height the game view shows (the camera's
  /// resolution): [viewHeight] − [stripDrop].
  double get visibleHeight => _viewHeight - _stripDrop;

  /// PRD-2.2 §7.5.4: from the visible bottom edge to the deadly tooth line:
  /// 24 in a run with a banner, 44 otherwise.
  double get bottomStripInset => Config.spikeHeight - _stripDrop;

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

  /// Versus backend (PRD-2 §3.13). No-op unless main() passes one (WP-5b).
  final VersusService versus;
  // region P26-LB1
  final LeaderboardService leaderboard;
  // endregion
  // region P26-LB2
  late final leaderboardQueue = LbQueue(
    storage: storage,
    service: leaderboard,
    analytics: services.track,
    request: (runs) {
      final look = menu.items.look;
      final card = sanitiseCard(look.card);
      return LbSubmitRunRequest(
        runs: runs,
        name: versus.me.name.isEmpty ? null : versus.me.name,
        look: look,
        card: card.isEmpty ? null : card,
        platform: defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        t: LbSubmitHook.testerBuild ? 1 : 0,
      );
    },
  );
  late final leaderboardSubmit = LbSubmitHook(leaderboardQueue, storage);
  // endregion

  /// PRD-2.3 §23.4 the store's rating sheet (no-op unless main() passes a
  /// backend: the default never requests).
  final RatingPrompt rating;

  /// PRD-2.3 §18.3 the foreground playtime counter (kept by the storage).
  late final PlaytimeCounter playtime = PlaytimeCounter(storage);

  /// Whether the app is resumed (PRD-2.3 §18.3: only resumed time counts).
  bool _resumed = true;

  /// WP-AV the sticker avatars (design C) shared by the VS intro, the
  /// versus HUD bar and the results card: every player picture is the
  /// player's own bird / gear / hat, rendered once per size at the
  /// screen's pixels per world point and cached (no photo is ever read).
  late final StickerAvatars avatars = StickerAvatars(
    pixelsPerPoint: _pixelsPerPoint,
  );

  /// Physical pixels per world point (the playfield is 320 pt wide).
  static double _pixelsPerPoint() {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return 0;
    return views.first.physicalSize.width / Config.worldWidth;
  }

  /// §3.13 / §5.8 / §5.10 the own name on the plates, the HUD chip and the
  /// results card. WP-NAME: the custom name chosen in Settings, else "You"
  /// (opponents see the custom name, else the generated nickname; WP-AV:
  /// never a Play Games / Game Center name).
  String get myVersusName {
    final c = validCustomName(storage.versusCustomName);
    return c.isNotEmpty ? c : kDefaultOwnName;
  }

  /// WP-NAME saves the custom versus name from the Settings card ('' =
  /// none: "You"). The format rule first; then the server (word filter):
  /// refused = nothing changes; offline = kept on the phone and sent later
  /// (FirebaseVersusService.syncCustomName). Never throws.
  Future<CustomNameSave> saveCustomName(String name) async {
    final n = name.trim();
    if (n.isNotEmpty) {
      final f = checkCustomNameLocal(n);
      if (f != null) return CustomNameRefused(f);
    }
    if (n == storage.versusCustomName) return const CustomNameAccepted('');
    CustomNameSave r;
    try {
      r = await versus
          .sendCustomName(n)
          .timeout(
            VersusConfig.callTimeout + const Duration(seconds: 2),
            onTimeout: () => const CustomNameOffline(),
          );
    } catch (_) {
      r = const CustomNameOffline();
    }
    try {
      switch (r) {
        case CustomNameAccepted(:final uid):
          await storage.saveVersusCustomName(
            n,
            syncedUid: uid.isEmpty ? null : uid,
          );
        case CustomNameOffline():
          await storage.saveVersusCustomName(n);
        case CustomNameRefused():
          return r;
      }
      await storage.saveVersusCustomNameError('');
    } catch (_) {}
    return r;
  }

  /// Reminder notifications (PRD-2 §3.34). No-op unless the app shell swaps
  /// in the real service (`main.dart`, mobile only); [onLoad] asks for the
  /// permission once and lays out the first 7-day plan.
  Reminders reminders;

  /// PRD-2.2 §28.3 other apps' audio (calls, alarms, the player's music).
  /// No-op by default (tests, Linux); `main.dart` sets the Android one.
  AudioFocus audioFocus = const NoopAudioFocus();

  /// PRD-2.3 §13.4: the music never stays silent without a reason (built
  /// in [onLoad] with [sound]).
  late final MusicGuard musicGuard;
  bool _musicReady = false;

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

  /// PRD-2.3 §2.0: called when the results-page share button is pressed,
  /// with the Spotlight card data and the picked text (wired up by the app
  /// shell to the card painter and the share sheet).
  FutureOr<void> Function(ShareCardData data)? onShareScore;

  /// PRD-2.3 §2.2: called by the home Invite tile with its card (the
  /// Spotlight card of the last run, or a new-player card).
  FutureOr<void> Function(ShareCardData data)? onInvite;

  /// PRD-2.3 §2 the random share picks (injectable for tests).
  ShareContent shareContent = ShareContent();

  /// Awaited between the START press and the run (PRD-1 §9: part 2 inserts
  /// the versus intro here). Null = the run starts synchronously.
  Future<void> Function()? beforeRunStart;

  /// Debug panel availability: debug builds and the Linux desktop target.
  /// P22-33 (§33.3): also in an FS_SOAK profile build (never release).
  /// Audit 17: also in FS_TESTER tester builds (god mode, autopilot bot,
  /// RUN DEBUG); never in the production build (the flag defaults to false).
  static bool get debugAvailable =>
      kDebugMode || kSoak || kTester || (!kIsWeb && Platform.isLinux);

  /// P22-33 (§33.3) the FS_SOAK driver (null in every normal build).
  SoakDriver? soak;

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

  // region WP-0b — run plumbing (ARCH §2.3)
  RunController? _run;

  /// The current run (null on the home screen).
  RunController? get run => _run;

  /// Seed of the next run: tests set it, e2e builds use [kE2ESeed],
  /// production rolls one per run (each player flies their own course).
  int? runSeed;

  /// §3.0.8 debug choices for the next run (debug panel force page).
  final RunDebugState runDebug = RunDebugState();
  Autopilot? _debugBot;
  // endregion WP-0b

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
  ResultsScreen? _results;
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
  // region WP-4c — Delete my data (PRD-2 §3.13 / Q22)
  DeleteDataPopup? _deleteDataPopup;
  // endregion WP-4c
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

  /// Back handlers, topmost last (settings, debug panel; later the Shop,
  /// Skins and popups). Esc pops the topmost. Each returns true when it
  /// handled the back press.
  final List<bool Function()> _backHandlers = [];

  /// PRD-2.2 §8.1 "one close per gesture": game-time seconds left in which a
  /// system back is ignored, after it closed a menu screen or popup.
  double _systemBackLock = 0;

  /// Menu screens (Shop / Skins) below the one on top, bottom first: their
  /// back button returns to the last one (re-created), or home when empty.
  /// Re-opening a screen already in the trail goes back to it, so the
  /// Shop <-> Skins hops never pile up.
  final List<MenuScene> _menuTrail = [];

  Color get foregroundColor => _fgColor;
  Color get stageBackground => _bgColor;
  bool get isScrolling => _run?.isScrolling ?? state == GameState.playing;

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

  // region WP-4c — Delete my data (PRD-2 §3.13 / Q22)
  /// The "Delete my data" dialog while it is up (null otherwise).
  DeleteDataPopup? get deleteDataPopup => _deleteDataPopup;
  // endregion WP-4c

  /// The No-ads celebration while it is up (PRD-home-v3 §7).
  NoAdsCelebration? get noAdsCelebration => _noAdsCelebration;

  /// Whether one of the modal popups (launch No-ads upsell, LEVEL UP,
  /// purchase result, No-ads celebration) is up.
  bool get modalPopupOpen =>
      // region P26-G2c
      _streakLostPopup != null ||
      // endregion
      // region P26-G2b
      _streakCard != null ||
      // endregion
      _noAdsPopup != null ||
      _levelUpPopup != null ||
      _purchasePopup != null ||
      // region WP-4c — Delete my data (PRD-2 §3.13 / Q22)
      _deleteDataPopup != null ||
      // endregion WP-4c
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

  /// PRD-2.2 §33.4 item 5: idle menus draw at [Config.idleMenuFps]. Off
  /// unless `main.dart` enables it (tests drive frames themselves).
  late final IdleFrameLimiter idleFrames = IdleFrameLimiter(this)
    ..onInput = _onUserInput;

  /// Seconds the current menu has been settled and untouched
  /// ([_menuIdle]); the idle frame rate starts at [Config.idleMenuDelay].
  double _idleQuiet = 0;

  /// A touch, key or system back: the display rate comes back at once and
  /// the idle delay starts over.
  void _onUserInput() => _idleQuiet = 0;

  /// Wakes the idle frame limiter (touch, key, system back).
  void wakeFrames() {
    _onUserInput();
    idleFrames.wake();
  }

  /// PRD-2.2 §33.4 item 5: a menu screen (Home, Shop, Skins, Levels) is up
  /// with nothing over it, nothing fading, flying, counting or gliding.
  /// Its own idle motion (bob, pulse, streak, wiggles, glint) still runs —
  /// only at the idle frame rate.
  bool get _menuIdle {
    if (state != GameState.start || !_sceneOnTop(menuScene)) return false;
    // Owner 2026-10-17: the Shop and Skins (the bird + trail preview moves
    // fast and looked choppy at the idle rate) always draw at the display
    // rate; Home and LEVELS keep the idle saving.
    if (menuScene == MenuScene.shop || menuScene == MenuScene.skins) {
      return false;
    }
    if (_fades.isNotEmpty || _colorFadeT < 1) return false;
    if (_popupQueue.isNotEmpty || _levelsOpenIn != null) return false;
    if (_fakeAd != null || _adsShowing > 0 || liveMotionPaused) return false;
    final home = _home;
    if (menuScene == MenuScene.home &&
        (home == null || !home.built || home.opacity < 1)) {
      return false;
    }
    if (coinPill.busy) return false;
    for (final c in descendants()) {
      if (c is Effect ||
          c is CoinFly ||
          c is CoinRewardAnimation ||
          c is ConfettiBurst ||
          c is ServiceMessage ||
          c is ScreenFlash ||
          c is ScreenShake ||
          (c is MenuScrollArea && c.isBusy)) {
        return false;
      }
    }
    return true;
  }

  /// PRD-menu-v2 §8.4: the idle animations of the live home / Shop pause
  /// while a dialog, popup, ad, fake ad or the debug panel is on top.
  bool get liveMotionPaused =>
      // region P26-G2c
      _streakLostPopup != null ||
      // endregion
      _noAdsPopup != null ||
      _levelUpPopup != null ||
      _purchasePopup != null ||
      // region WP-4c — Delete my data (PRD-2 §3.13 / Q22)
      _deleteDataPopup != null ||
      // endregion WP-4c
      _noAdsCelebration != null ||
      _debugPanel != null ||
      _fakeAd != null ||
      _adsShowing > 0;

  /// True while a free-coins rewarded ad is playing.
  bool get freeCoinsBusy => _freeCoinsBusy;

  /// The fake rewarded-ad overlay while it is up (null otherwise).
  FakeAdOverlay? get fakeAdOverlay => _fakeAd;

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
    // WP-TAB: the menu column is centred; the run column sits on the right.
    camera.viewfinder.position = cameraBase;
    (world as RunScaledWorld).columnShift = extraWidth / 2;
    // Before any DragCallbacks component mounts, so Flame uses this one: the
    // menu lists' drag slop is Config.menuScrollSlop world points (S1-50).
    final drags = MenuDragDispatcher(
      pointsToPixels: () => canvasSize.x <= 0 || canvasSize.y <= 0
          ? 1
          : min(canvasSize.x / viewWidth, canvasSize.y / viewHeight),
    );
    // Flame's own DragCallbacks registers its default dispatcher this way.
    // ignore: invalid_use_of_internal_member
    registerKey(const MultiDragDispatcherKey(), drags);
    add(drags);

    await storage.load();
    // region P26-B1
    final show = showcaseFactory?.call(storage);
    if (show != null) {
      _showcasePlan = show;
      _showcaseProgress = show;
      // region P26-B2
      show.ftueTracker = ftueTracker;
      // endregion
      show.adoptLegacyDone();
    }
    // endregion
    await ftueTracker.flushPendingFirstMeets();
    // QA P2-03 (PRD-2.3.1 §12.3): commit (clean) or drop (excluded) the
    // journal of a run the app died in, before the sync below reports it.
    await achievements.recoverJournal();
    // PRD-2.3.1 §12.4 report what an earlier session left unreported (a
    // no-op while signed out; the player stream triggers it again).
    unawaited(achievements.syncAll());
    menu = MenuState(
      storage,
      onEarned: (amount, source) {
        // In-run sources are aggregated by the run's analytics router and
        // sent once at run end (ARCH §2.7).
        if (source.aggregatedInRun) return;
        services.track('coins_earned', {
          'amount': amount,
          'source': source.analyticsName,
        });
      },
      // PRD-2.3 §14.8 every spend: `coins_spent {amount, reason}`.
      onSpent: (amount, reason) =>
          services.track('coins_spent', {'amount': amount, 'reason': reason}),
    );
    // The slot arms a powerup only right before it starts the run, which
    // consumes it: anything still armed here is stale (an app killed
    // mid-start, or a pre-WP10 arm-then-START build) and must not ride
    // along on a plain START.
    // region P26-G2b
    // Only a tagged streak start survives launch; legacy / debug arms keep
    // their stale-start cleanup. The existing armedPowerup key holds the tag.
    if (!streakFreeStart && menu.slot.armed != Powerup.none) {
      menu.slot.consume();
    }
    // endregion
    // Audit A3-6: the banner service's own preloads (consent, retry) skip
    // NO ADS owners, like the game's ([bannerWanted]).
    monetization.banner.preloadWanted = () => !menu.noAds;
    // §3.16 (S6-62) a 4/4 puzzle bonus a kill interrupted is paid first
    // (it happened before any level-reward claim of that session).
    try {
      await PuzzleFeature.settlePayout(storage, menu.wallet);
    } catch (_) {}
    // region WP-2e — results page (PRD-2 §3.14)
    await _creditUnclaimedLevelReward();
    // endregion WP-2e
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
      onGift: _onGiftGranted,
      clock: storage.now,
    )..start();
    // PRD-2.3 §22.2: gift codes redeemed outside the game arrive on launch.
    _purchases!.sync();
    // PRD-2.3 §24.3 (S8-13): until the launch sync has settled, the first
    // START waits for it (bounded), so launch ownership reaches the first
    // run's banner decision.
    _purchases!.launchSync?.whenComplete(() => _launchSyncSettled = true);
    sound = SoundService(muted: storage.muteSound, enabled: soundEnabled);
    _soundReady = true;
    if (kSoak && soundEnabled) {
      // P22-33 §33.3 (+ the §22 stop-timing log)
      final d = soak = SoakDriver(this);
      sound.debugOnStop = d.onSfxStop;
    }
    rumble.on = storage.rumble;
    // Background music: persisted volume, then start the loop (everywhere —
    // menus and gameplay). Guarded/unawaited: no-ops in headless tests.
    unawaited(sound.setMusicVolume(storage.musicVolume));
    // PRD-2.2 §28.3: the player's own music already playing at launch →
    // the game skips its own (SFX stay on); calls / alarms hold the audio.
    // PRD-2.3 §13: the music guard turns the playback changes into holds
    // and re-checks them; the diagnostic log goes to logcat (FS-Music).
    sound.musicLog.sink = audioFocus.log;
    musicGuard = MusicGuard(
      sound: sound,
      focus: audioFocus,
      onMenu: () => state == GameState.start || state == GameState.results,
      adShowing: () => _adsShowing > 0,
      adJustEnded: () => _adJustEnded,
      otherMusicNow: _otherMusicNow,
      track: services.track,
    )..attach();
    _musicReady = true;
    unawaited(_startMusicChecked());
    // PRD-2.2 §33.6 (S7-19): the session sound set is created once on
    // Home and kept, so the live players stay flat game after game.
    unawaited(sound.warmSession());

    final palette = paletteForStage(0);
    _bgColor = palette.background;
    _fgColor = palette.foreground;
    _targetBg = _fadeFromBg = _bgColor;
    _targetFg = _fadeFromFg = _fgColor;

    // In-world background: a flat rect painted with the background color,
    // behind everything (backgroundColor() itself is now the bar color).
    _backdrop = RectangleComponent(
      position: Vector2(-extraWidth, 0), // WP-TAB: full width
      size: Vector2(Config.worldWidth + 2 * extraWidth, viewHeight),
      priority: -1000,
      paint: Paint()..color = _bgColor,
    );
    world.add(_backdrop);
    // PRD-2.2 §7.5.2: the backdrop and the score HUD follow the playfield.
    registerResizable(
      PlayfieldResizeCallback((h) {
        _backdrop.size = Vector2(Config.worldWidth + 2 * extraWidth, h);
        _hud.position = Config.scoreHudPositionFor(h / 2);
      }),
    );

    _ground = SpikeStrip(isCeiling: false);
    _ceiling = SpikeStrip(isCeiling: true);
    _spikeInset = _SpikeInsetAdapter([_ground, _ceiling]);
    // WP-TAB: the strips and the score circle are run content.
    world.add(RunScaledWorld.inRunColumn(_ground));
    world.add(RunScaledWorld.inRunColumn(_ceiling));
    _hud = ScoreHud(position: Config.scoreHudPositionFor(viewHeight / 2));
    _hud.opacity = 0;
    world.add(RunScaledWorld.inRunColumn(_hud));
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
    // PRD-2.2 §7.5.1: preload the banner on Home as soon as ads may be
    // requested (and again whenever consent changes).
    monetization.consent.canRequestAds.addListener(_preloadBanner);
    _preloadBanner();
    _logSlotShown();
    _applyTints();

    // App launch = a session start: the No-ads upsell may show on this
    // home arrival (PRD-menu-v4 §8, NoAdsPopupPolicy).
    await _startSession();

    // region WP-2d — revive v2 (PRD-2 §3.14): the revive slot of the flow
    PostRunScreens.revive ??= const ReviveFlow();
    // endregion WP-2d

    // region WP-4a — balloon bonus (PRD-2 §3.15): the bonus slot of the flow
    PostRunScreens.bonus ??= const BonusPage();
    // endregion WP-4a

    // region WP-4b — reminder notifications (PRD-2 §3.34)
    // §3.34 "Permission": asked once, at the first app start, before the
    // first game. §3.34 "Scheduling": the same plan is laid out at app start
    // (covers reboots and app updates); storage is loaded by now, so the
    // `{best}` / `{coins}` fill-in has the real values.
    //
    // 2.4.0 (26): the launch dialogs come one at a time. The notification
    // question waits for the ads consent form ([awaitLaunchConsent]), and
    // the platform sign-in (Play Games' "Welcome back" banner, Game
    // Center's) waits for both ([launchDialogsDone]): on a first launch
    // they all landed at once and the banner showed behind the dialogs.
    unawaited(() async {
      try {
        await reminders.initialize();
        final consent = awaitLaunchConsent;
        if (consent != null) {
          await consent().timeout(launchConsentWait, onTimeout: () {});
        }
        await reminders.requestPermissionIfNeeded();
      } finally {
        if (!_launchDialogs.isCompleted) _launchDialogs.complete();
      }
      await reminders.reschedule();
    }());
    // endregion WP-4b
  }

  /// 2.4.0 (26): main() sets this to the launch ads consent flow (UMP
  /// form); null in tests (nothing to wait for).
  Future<void> Function()? awaitLaunchConsent;

  /// The longest the notification question waits for the consent form.
  static const Duration launchConsentWait = Duration(minutes: 3);

  final Completer<void> _launchDialogs = Completer<void>();

  /// Completes once the launch dialogs (consent form, notification
  /// question) are done; the platform sign-in waits for it.
  Future<void> get launchDialogsDone => _launchDialogs.future;

  /// When the app went to the background (null while in the foreground).
  DateTime? _backgroundSince;

  /// Runs started since the current session began: the session-start
  /// upsell is dropped once one started (never between runs).
  int _runsThisSession = 0;

  /// A No-ads offer waits in [_popupQueue] (never more than one).
  bool _noAdsOfferQueued = false;

  // region P26-C2L
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
    // Launch and a resumed Home session both get one C2 popup slot. Gather
    // the owed LEVEL UP before the session offer can try to use that slot.
    _beginHomeVisit();
    _queueNoAdsOffer(
      check: 'session',
      stale: () =>
          _runsThisSession > 0 ||
          giftThisHomeVisit ||
          menu.noAds ||
          state != GameState.start ||
          menuScene != MenuScene.home,
    );
  }

  /// C2: launch, a resumed Home session and the Home arrival after a run
  /// each start a fresh popup budget. Rejected requests stay pending with
  /// their sources for a later visit. Returns from Shop / Skins / Levels /
  /// Settings are not arrivals. System sheets remain outside this budget.
  void _beginHomeVisit() {
    if (state != GameState.start || menuScene != MenuScene.home) return;
    // region P26-G2c
    _streakLostVisit++;
    // endregion
    // region P26-LB2
    unawaited(leaderboardQueue.flush());
    // endregion
    homeMoments.beginVisit(
      HomeVisit(
        day: storage.now(),
        gamesPlayed: storage.gamesPlayed,
        requests: HomeVisitRequests(
          // region P26-G2c
          streakLost: streakLostPending,
          // endregion
          levelUpCatchUp: menu.levels.pendingLevelUp != null,
          // region P26-G2b
          streakReward: streakRewardPending,
          // endregion
          noAds:
              !giftThisHomeVisit &&
              !_ratingRequestedThisRun &&
              menu.noAdsPopup.evaluate() != null,
          rating: _deferredRatingTrigger != null,
        ),
      ),
    );
  }

  // endregion

  /// Queues the No-ads offer through the popup queue (at most one at a
  /// time, QA S1-70): the window is re-checked the moment it would show, and
  /// the offer is dropped when [stale] by then.
  void _queueNoAdsOffer({
    required String check,
    required bool Function() stale,
  }) {
    if (_noAdsOfferQueued || _noAdsPopup != null) return;
    if (menu.noAdsPopup.evaluate() == null) return;
    _noAdsOfferQueued = true;
    _queuePopup(
      () =>
          stale() || (_homeInteractive && _fakeAd == null && _adsShowing == 0),
      () {
        _noAdsOfferQueued = false;
        if (stale() || _noAdsPopup != null) return;
        final reason = menu.noAdsPopup.evaluate();
        if (reason == null) return;
        openNoAdsPopup(reason: reason.name, check: check);
        if (_noAdsPopup != null) unawaited(menu.noAdsPopup.markShown());
      },
    );
  }

  @override
  void onRemove() {
    if (_musicReady) unawaited(musicGuard.dispose());
    monetization.consent.canRequestAds.removeListener(_preloadBanner);
    idleFrames.detach();
    _purchases?.dispose();
    super.onRemove();
  }

  /// Back from the background (e.g. after the Play payment sheet or a
  /// settings detour): re-query store products that were still missing.
  @override
  void lifecycleStateChange(AppLifecycleState state) {
    // PRD-2.2 §33.4 item 5: FlameGame.lifecycleStateChange pauses the
    // engine (no update, no frames) on paused / hidden / detached and
    // resumes it on inactive / resumed ([pauseWhenBackgrounded]); the idle
    // frame limiter lets go of a stopped loop so the resume restarts it.
    super.lifecycleStateChange(state);
    switch (state) {
      case AppLifecycleState.paused ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
        idleFrames.cancel();
      case AppLifecycleState.resumed || AppLifecycleState.inactive:
        wakeFrames();
    }
    // region WP-4b — reminder notifications (PRD-2 §3.34)
    // §3.34 "Scheduling": leaving the app (background or close) cancels the
    // pending plan and schedules the next 7 days, so the reminders always
    // reflect the last time the player was in the game.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(reminders.reschedule());
    }
    // endregion WP-4b
    // region WP-2d — backgrounding pauses a running run (PRD-2 §5.7, ARCH
    // §2.3 call)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      pause();
      // QA P2-03: the open run's achievement journal reaches disk.
      final run = _run;
      if (run != null && !run.ended) {
        achievements.saveJournal(counts: run.countsForAchievements);
      }
    }
    // endregion WP-2d
    // 2.4.0 (24): a player signed in to Play Games meanwhile (or whose
    // automatic sign-in landed late) is picked up on the return.
    if (state == AppLifecycleState.resumed) {
      unawaited(services.recheckSignIn('resume'));
      // region P26-LB2
      if (isLoaded) unawaited(leaderboardQueue.flush());
      // endregion
    }
    // region PRD-2.2 §28 — the game owns the music lifecycle
    _audioLifecycle(state);
    // endregion PRD-2.2 §28
    // region PRD-2.2 §7.6 guard 6 — no interstitial while in the background
    _inBackground =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    // PRD-2.3 §18.3: only resumed time counts, and the counter is saved when
    // the app leaves the foreground.
    _resumed = state == AppLifecycleState.resumed;
    if (!_resumed) unawaited(playtime.flush());
    // endregion PRD-2.2 §7.6
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _backgroundSince ??= storage.now();
      case AppLifecycleState.resumed:
        unawaited(monetization.iap.refresh());
        // PRD-2.3 §22.2: ... and on every return (≤ once per 5 s).
        _purchases?.sync();
        // §3.13 (S6-66) a failed versus start recovers; the queue retries.
        unawaited(versus.onResume());
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
    _audioSceneChange(); // PRD-2.2 §28
    if (_soundReady) musicGuard.onHomeArrival(); // PRD-2.3 §13.3
    state = GameState.start;
    menuScene = MenuScene.home;
    _menuTrail.clear();
    final bird = Bird();
    _bird = bird;
    // The home screen draws its own bird in the start block; the physics
    // bird waits invisibly at its spawn point and fades in on START.
    _birdAdapter = _BirdOpacityAdapter(bird)..opacity = 0;
    world.add(RunScaledWorld.inRunColumn(bird)); // WP-TAB
    // Menus show the short (44 pt) spike strips of the mocks.
    _fades.removeWhere((fade) => identical(fade.target, _spikeInset));
    _spikeInset.opacity = 1;
    _addHome();
    // region WP-5b — §3.13 an opponent is prefetched at home
    unawaited(versus.prefetch());
    // endregion WP-5b
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
        // PRD-2.3 §10.1 the first tap starts the waiting run.
        if (_run?.waiting ?? false) {
          _firstTap();
          break;
        }
        // region WP-3c — §3.23 flap input is ignored during a spring launch
        if (_run?.flapLocked ?? false) break;
        // endregion WP-3c
        _run?.onTap();
        _bird?.flap();
      case GameState.results:
      case GameState.versusIntro:
      case GameState.paused:
      case GameState.dying:
      case GameState.reviving:
      case GameState.bonus:
        break;
    }
  }

  /// S8-14 (PRD-2.3 §10.1): the run is open and waits for its first tap.
  /// The [TapCatcher] then starts it on tap-up, so a pointer the OS cancels
  /// (the Android back edge swipe) cannot start it.
  bool get runWaitingForFirstTap =>
      state == GameState.playing && (_run?.waiting ?? false);

  /// A real tap that no button consumed (TapCatcher): flaps while playing.
  /// Menus never start a run on a stray tap — only the START button does
  /// (PRD-1 §4.2).
  void onPlayfieldTap() {
    if (state == GameState.playing) {
      // PRD-2.3 §10.1 the first playfield tap starts the waiting run (a tap
      // on the pause button never gets here).
      if (_run?.waiting ?? false) {
        _firstTap();
        return;
      }
      // region WP-3c — §3.23 flap input is ignored during a spring launch
      if (_run?.flapLocked ?? false) return;
      // endregion WP-3c
      _run?.onTap();
      _bird?.flap();
    }
  }

  /// The START button: a plain run, never with a powerup (only the slot
  /// arms one, right before it starts the run itself). Awaits
  /// [beforeRunStart] if set; synchronous when it is null.
  Future<void> startRun() async {
    if (!_homeInteractive) return;
    // §8.2: the home bird hops with flap.mp3 as the run starts. PRD-2.3
    // §10.1: START no longer flaps the run's bird (the run waits for the
    // first tap), so the hop always plays it here.
    sound.play(Sfx.flap);
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
    // region P26-G2b
    if (streakFreeStart) {
      await _runFromHome();
      return;
    }
    // endregion
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
    // PRD-2.3 §24.3 (S8-13): a restore / redeem at launch applies before the
    // first run: the session's first START waits (at most
    // [Config.launchOwnershipStartWait]) for the launch sync still running.
    if (_runsThisSession == 0 &&
        !_launchSyncSettled &&
        _purchases?.launchSync != null) {
      _runStarting = true;
      try {
        await _awaitLaunchOwnership();
      } finally {
        _runStarting = false;
      }
      if (state != GameState.start || menuScene != MenuScene.home) return;
    }
    // PRD-2.2 §7.5.2: the playfield shrinks at START, before the VS intro
    // and the run scene are built.
    _reserveRunBanner();
    final hook = beforeRunStart;
    // region WP-5b — §3.13 / §5.8 the opponent is taken at tap time.
    // PRD-2.3 §25.3: in VERSUS every START shows the VS intro, also when
    // nothing is held yet (the intro is the loading screen: it waits up to
    // 3 s for the search, then lands on the opponent or on NO RIVAL FOUND).
    // A service without a backend ([VersusService.loadingIntro] false)
    // keeps the 2.2 solo START without an intro.
    // PRD-2.2 §2.2: FREE FLY never takes the opponent (no intro, no bar,
    // no versus result); the held one stays ready for a later VERSUS.
    final versusStart = homeMode == HomeMode.versus;
    final waitIntro = versusStart && !_hasHeldOpponent() && _versusLoadingIntro;
    final opponent = versusStart && !waitIntro ? _takeRunOpponent() : null;
    if (!versusStart || waitIntro) _runOpponent = null;
    // endregion WP-5b
    if (withPowerup || hook != null || opponent != null || waitIntro) {
      _runStarting = true;
      try {
        if (withPowerup) await menu.slot.armOffered();
        if (hook != null) await hook();
        // region WP-5b
        if (opponent != null || waitIntro) await _playVersusIntro(opponent);
        // endregion WP-5b
      } finally {
        _runStarting = false;
      }
      if (state != GameState.start) return;
    }
    // region P26-G2b
    if (streakFreeStart) {
      await storage.saveArmedPowerup(streakStarter.name);
    }
    // endregion
    final starter = menu.slot.consume();
    switch (starter) {
      case Powerup.bigHoops:
        services.track('big_hoops_used');
      case Powerup.shield:
        services.track('shield_armed');
      case Powerup.none:
        break;
    }
    _startGame(starter);
  }

  // region PRD-2.3 §24.3 (S8-13) — launch ownership before the first run
  /// The launch purchase sync has settled (its grants are applied).
  bool _launchSyncSettled = false;

  /// The first START waiting for the launch sync, and its game-time budget.
  Completer<void>? _launchOwnershipWait;
  double _launchOwnershipLeft = 0;

  Future<void> _awaitLaunchOwnership() {
    final c = Completer<void>();
    _launchOwnershipWait = c;
    _launchOwnershipLeft = Config.launchOwnershipStartWait;
    _purchases?.launchSync?.whenComplete(() {
      if (!c.isCompleted) c.complete();
    });
    return c.future.whenComplete(() => _launchOwnershipWait = null);
  }

  void _tickLaunchOwnershipWait(double dt) {
    final c = _launchOwnershipWait;
    if (c == null || c.isCompleted) return;
    _launchOwnershipLeft -= dt;
    if (_launchOwnershipLeft <= 0) c.complete();
  }
  // endregion

  void _startGame([Powerup starter = Powerup.none]) {
    state = GameState.playing;
    _runsThisSession++;
    _giftThisHomeVisit = false; // PRD-2.3 §0 item 2: a new Home visit next
    // PRD-2.3 §10.1: START only opens the run, waiting for the first tap;
    // the banner, logGameStart, run_start and versus.onRunStart move to
    // [_firstTap] (the opponent is decided now, so remember it).
    _runHadOpponent = _runOpponent != null;
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
    // PRD-2.3 §10.1 the bird floats at its spawn point (gravity off).
    _bird!.startHover();
    fadeOpacity(_hud, from: 0, to: 1, duration: Config.gameplayFadeDuration);
    _startRun(starter);
    // PRD-2.3 §10.3b the bird is floating and tappable now: the reminder
    // count starts — solo at START, in versus once the VS intro (the §25.3
    // loading screen) has finished ([_versusIntroFinishedForWaiting], next
    // to `onVersusIntroFinished`).
    if (!_introPending) _run?.beginWaiting();
    _introPending = false;
  }

  /// PRD-2.3 §10.3b / §25.3 a VS intro is playing: the waiting run's
  /// reminder count must not start before it has finished.
  bool _introPending = false;

  /// PRD-2.3 §10.3b the VS intro handed over (called right where
  /// `onVersusIntroFinished` fires): the bird will float and be tappable,
  /// so the reminder count may start.
  void _versusIntroFinishedForWaiting() {
    _introPending = false;
    _run?.beginWaiting();
  }

  // region P23-10 — the waiting start (PRD-2.3 §10)
  /// The run being opened had a versus opponent (`run_start.opponent`).
  bool _runHadOpponent = false;

  /// PRD-2.3 §10.3 / §10.3b the first-run instructions / tap reminder of
  /// the waiting run (null once dismissed and gone).
  FirstRunHint? get firstRunHint {
    final h = _firstRunHint;
    return h == null || h.isRemoved ? null : h;
  }

  FirstRunHint? _firstRunHint;

  /// Owner 2026-10-14 (2.3.0 (18)): the current / last run's counts for
  /// the debug TUNING page.
  RunStats? runStats;

  /// PRD-2.3 §10.1 the first playfield tap of a waiting run: everything
  /// START used to do at once — the banner (PRD-2.2 §7.4; since PRD-2.3.1 §11
  /// it is up already on the waiting screen), logGameStart,
  /// `run_start`, versus.onRunStart, gravity and the first flap, then
  /// `RunController.start()` (the clock runs, `RunStarted`). The hint
  /// fades out. PRD-2.3.1 §10: the tap no longer saves `firstRunHintSeen`;
  /// the first pass of hoop 0 does (`RunController`).
  void _firstTap() {
    final run = _run;
    if (run == null || !run.waiting) return;
    final hint = _firstRunHint;
    _firstRunHint = null;
    hint?.dismiss();
    // PRD-2.2 §7.4: the bird starts flying — banner in, interstitial load.
    _onFirstFlight();
    services.logGameStart();
    // PRD-2.2 §2.3 run_start {mode, opponent (VERSUS only)}; §3 the next
    // Home visit searches again.
    final mode = homeMode;
    services.track('run_start', {
      'mode': mode.analytics,
      if (mode == HomeMode.versus) 'opponent': _runHadOpponent ? 1 : 0,
    });
    try {
      versus.onRunStart();
    } catch (_) {}
    ftueTracker.step(FtueStep.firstTap, gamesPlayed: storage.gamesPlayed);
    _bird!
      ..stopHover()
      ..enableGravity()
      ..flap();
    run.start();
  }

  /// PRD-2.3 §10.3 / §10.3b adds the waiting run's hint: the full
  /// instructions until `firstRunHintSeen` is saved (PRD-2.3.1 §10: the first
  /// pass of hoop 0, so every run before that), else the tap reminder.
  void _addFirstRunHint(RunController run, RunHud hud) {
    final full = !storage.firstRunHintSeen;
    // PRD-2.3.1 §10.2: the full instructions write the key as `false`, so a
    // new player whose first run fails is not counted as seen by the
    // `gamesPlayed > 0` fallback. The fallback only covers installs from
    // before 2.3.
    if (full) unawaited(storage.saveFirstRunHintSeen(false));
    final hint = FirstRunHint(
      run: run,
      mode: full ? FirstRunHintMode.firstRun : FirstRunHintMode.reminder,
    );
    _firstRunHint = hint;
    hud.add(hint);
  }
  // endregion P23-10

  // region WP-0b — run plumbing (ARCH §2.3)
  /// Builds the [RunSetup] (seed, starter, versus opponent, debug / e2e
  /// force queue) and starts the [RunController] with the first tap.
  void _startRun(Powerup starter) {
    _run?.disposeRun();
    // 2.4.0 (24): before the run's achievements, a late Play Games sign-in
    // is picked up (Android; no-op when signed in, on iOS and in tests).
    unawaited(services.recheckSignIn('run start'));
    _audioSceneChange(); // PRD-2.2 §28
    if (_soundReady) musicGuard.onRunStart(); // PRD-2.3 §13.3
    final d = runDebug;
    final e2e =
        kE2E || E2EHooks.force.isNotEmpty || E2EHooks.startHoopIndex > 0;
    final forced = [...d.force, if (e2e) ...E2EHooks.force];
    final showcase = showcasePlan.atStart(
      gamesPlayed: storage.gamesPlayed,
      seen: storage.showcaseSeen,
      attempt: storage.showcaseAttempt,
      forced: forced.isNotEmpty,
    );
    final setup = RunSetup(
      seed: runSeed ?? (kE2E ? kE2ESeed : _random.nextInt(1 << 31)),
      starter: starter,
      // region WP-5b — the opponent taken at START (null = solo)
      opponent: _consumeRunOpponent(),
      // endregion WP-5b
      startHoopIndex: e2e && E2EHooks.startHoopIndex > 0
          ? E2EHooks.startHoopIndex
          : d.startHoopIndex,
      forced: forced,
      forcedRide: d.forcedRide ?? (e2e ? E2EHooks.forcedRide : null),
      viewHeight: viewHeight,
      // PRD-2.3 §14.6 the gates hold in every real run; the test harness,
      // FS_E2E and FS_SOAK builds fly with every element.
      ignoreGates: d.ignoreGates || kE2E || kSoak,
      // PRD-2.3 §17.6 only the test baseline turns the rule off.
      oneBigBonus: d.oneBigBonus,
      // PRD-2.3.1 §12.2 a debug-forced slot starter is a debug start.
      debugStarter: menu.slot.takeConsumedDebug() && starter != Powerup.none,
      showcase: showcase,
      extraStarters: showcase?.extraStarters ?? const [],
    );
    d.force.clear();
    d.forcedRide = null;
    final run = RunController(setup: setup, game: this);
    // PRD-2.3.1 §12.2 / §12.5: no pill over the run. iOS round 2 §6: the
    // unshown toasts stay queued for the next results page / Home.
    _hideAchievementToast();
    achievements.beginRun(counts: run.countsForAchievements);
    runStats = RunStats(run); // 2.3.0 (18) debug panel run rows
    _run = run;
    run.events.on<HighlightStarted>(
      (event) => showcaseProgress.onHighlight(
        event.id,
        scripted: event.scripted,
        hoop: event.hoop,
      ),
    );
    if (storage.gamesPlayed == 3) {
      ftueTracker.step(FtueStep.run4Start, gamesPlayed: storage.gamesPlayed);
    }
    (world as RunScaledWorld).timeScaleSource = () => run.state.timeScale;
    world.add(run);
    // PRD-2.4 §3 the lively run background (leaves with its run).
    world.add(RunScaledWorld.inRunColumn(RunBackdrop(run)));
    // PRD-2.3 §10.1 / §10.2 the run opens waiting for the first tap, hoop 0
    // already at its spot.
    // PRD-2.6 WP-B: arm showcase extras before features attach and hoop 0
    // is planned. A Home-slot Big Hoops still owns its single duration roll.
    if (setup.extraStarters.contains(Powerup.shield)) run.state.shield = true;
    if (setup.starter != Powerup.bigHoops &&
        setup.extraStarters.contains(Powerup.bigHoops)) {
      run.state.bigHoops = BigHoopsState(
        duration: run.director.rollBigHoopsDuration(),
        start: run.state.runClock,
      );
    }
    run.open();
    _debugBot = debugAvailable && (d.bot || E2EHooks.autopilot)
        ? Autopilot(run)
        : null;
    if (debugAvailable && d.overlay) run.layers.fx.add(RunDebugOverlay(run));
    // region WP-2d — run HUD (viewport, real time) + pause freeze
    _addFirstRunHint(run, RunHud.ensureFor(run));
    // PRD-2.3.1 §11: the banner shows on the waiting screen (the hovering
    // bird), before the first tap. A VS intro keeps the strip reserved
    // (`_reserveRunBanner`) until this point.
    if (_runBanner) _bannerState.value = BannerState.showing;
    (world as RunScaledWorld).frozenSource = () => state == GameState.paused;
    // endregion WP-2d
  }

  // region WP-5b — versus (PRD-2 §3.13, §5.8)
  /// The opponent taken at START for the run about to begin.
  OpponentRun? _runOpponent;

  /// The VS intro while it plays (tests, screenshots).
  VersusIntro? get versusIntro => _versusIntro;
  VersusIntro? _versusIntro;

  /// PRD-2.3 §25.3 whether the service shows the loading intro.
  bool get _versusLoadingIntro {
    try {
      return versus.loadingIntro;
    } catch (_) {
      return false;
    }
  }

  /// PRD-2.3 §25.3 an opponent is held for START.
  bool _hasHeldOpponent() {
    try {
      return versus.holdsOpponent;
    } catch (_) {
      return false;
    }
  }

  /// PRD-2.3 §10 hook for the waiting start: called once the VS intro has
  /// finished (its white fade covers the screen), right before the run
  /// starts — `versus` true when the run has an opponent, false when the
  /// intro landed on NO RIVAL FOUND (a solo run). Null = nothing to do.
  void Function({required bool versus})? onVersusIntroFinished;

  /// §3.13 takes the prefetched opponent (sync, never waits) and logs
  /// `versus_matched` / `versus_skipped {reason: no_opponent}` (§6).
  /// PRD-2.3 §25.3 [waitedMs] is how long the VS intro waited for it.
  OpponentRun? _takeRunOpponent({int waitedMs = 0}) {
    OpponentRun? o;
    try {
      o = versus.takeOpponent();
    } catch (_) {
      o = null;
    }
    _runOpponent = o;
    if (o == null) {
      services.track('versus_skipped', {'reason': 'no_opponent'});
      _logVersusSolo(waitedMs: waitedMs);
    } else {
      services.track('versus_matched', {
        'opp_level': o.level,
        'opp_score': o.score,
        'level': menu.levels.level,
      });
    }
    return o;
  }

  /// PRD-2.2 §4 a VERSUS START went solo: why, for us only (analytics
  /// `versus_solo {reason, reads, level}` and a logcat line; the debug panel
  /// shows [VersusService.lastSearch]). The player sees nothing.
  void _logVersusSolo({int waitedMs = 0}) {
    VersusSoloReason reason;
    int reads;
    try {
      reason = versus.soloReason;
      reads = versus.lastSearch.reads;
    } catch (_) {
      reason = VersusSoloReason.error;
      reads = 0;
    }
    services.track('versus_solo', {
      'reason': reason.code,
      'reads': reads,
      'level': menu.levels.level,
      'waited_ms': waitedMs, // PRD-2.3 §25.3
    });
    debugPrint(versusSoloLogLine(reason, reads));
  }

  // --- PRD-2.2 §2 mode button ------------------------------------------------

  /// The Home mode (VERSUS / FREE FLY), remembered in `homeMode`.
  HomeMode get homeMode => storage.homeMode;

  /// PRD-2.2 §2.2 the mode button: switches the mode (remembered), plays
  /// `mode_to_vs` / `mode_to_ff`, logs `mode_changed`. The menu knock comes
  /// from the button. Ignored while a run starts or a popup is up.
  void toggleHomeMode() {
    if (!_homeInteractive) return;
    final next = homeMode.toggled;
    unawaited(storage.saveHomeMode(next));
    sound.play(next == HomeMode.versus ? Sfx.modeToVs : Sfx.modeToFf);
    services.track('mode_changed', {'mode': next.analytics});
    _home?.syncMode();
  }

  /// The panels cover the home screen: drop it at once (its chrome goes
  /// with it), so nothing of it shows through a shake or the white fade.
  void _dropHomeUnderIntro() {
    final home = _home;
    if (home == null) return;
    _home = null;
    home.active = false;
    unregisterTintable(home);
    _chromeHosts.remove(home);
    home.removeFromParent();
    _updateMenuChrome();
  }

  OpponentRun? _consumeRunOpponent() {
    final o = _runOpponent;
    _runOpponent = null;
    return o;
  }

  /// §5.8 plays the VS intro over the home screen (state `versusIntro`,
  /// taps do nothing) and returns when its white fade has covered the
  /// screen; the run then starts under the white, which fades out (0.3 s).
  ///
  /// PRD-2.3 §25.3 [opponent] null: the intro is the loading screen. The
  /// search ([VersusService.searchForStart]) runs while the reel cycles; a
  /// result inside the 3 s is taken and handed to the reel
  /// ([VersusIntro.resolve]); a later one stays held for the next START.
  Future<void> _playVersusIntro(OpponentRun? opponent) async {
    state = GameState.versusIntro;
    _introPending = true; // PRD-2.3 §10.3b
    final intro = VersusIntro(
      opponent: opponent,
      myName: myVersusName,
      myLook: menu.items.look,
      myLevel: menu.levels.level,
      onCovered: _dropHomeUnderIntro,
    );
    _versusIntro = intro;
    world.add(intro);
    if (opponent == null) {
      Future<bool> search;
      try {
        search = versus.searchForStart();
      } catch (_) {
        search = Future.value(false);
      }
      unawaited(
        search.catchError((_) => false).then((found) {
          if (!intro.waiting || _versusIntro != intro) return;
          OpponentRun? o;
          if (found) {
            try {
              o = versus.takeOpponent();
            } catch (_) {}
          }
          intro.resolve(o);
        }),
      );
    }
    _ground.priority = groundOverMenusPriority;
    _ceiling.priority = groundOverMenusPriority;
    // The panels slide over the home screen *and* its coin pill.
    _coinPill.priority = VersusIntro.priorityOnTop - 1;
    try {
      if (E2EHooks.skipVersusIntroWait) {
        await intro.loaded;
        intro.finishNow();
      }
      await intro.done;
      if (intro.waited) _afterLoadingIntro(intro);
      onVersusIntroFinished?.call(versus: _runOpponent != null);
      _versusIntroFinishedForWaiting(); // PRD-2.3 §10.3b
    } finally {
      _introPending = false; // PRD-2.3 §10.3b (also when the intro aborts)
      if (state == GameState.versusIntro) state = GameState.start;
      _versusIntro = null;
      _coinPill.priority = 21;
      intro.removeFromParent();
      _ceiling.priority = SpikeStrip.basePriority;
      _syncGroundPriority();
      final white = RectangleComponent(
        position: Vector2(-extraWidth, 0), // WP-TAB: full width
        size: Vector2(Config.worldWidth + 2 * extraWidth, viewHeight),
        paint: Paint()..color = const Color(0xFFFFFFFF),
        priority: 1000,
      );
      world.add(white);
      fadeOpacity(
        white,
        from: 1,
        to: 0,
        duration: VersusConfig.whiteFade,
        removeOnDone: true,
      );
    }
  }

  /// PRD-2.3 §25.3 the loading intro ended: its opponent (if the reel
  /// landed on one) becomes the run's, logged like a held one; NO RIVAL
  /// FOUND logs `versus_solo` with `waited_ms`. Either way
  /// `versus_intro_wait {waited_ms, found}`.
  void _afterLoadingIntro(VersusIntro intro) {
    final o = intro.opponent;
    final waited = intro.waitedMs;
    services.track('versus_intro_wait', {
      'waited_ms': waited,
      'found': o != null ? 1 : 0,
    });
    _runOpponent = o;
    if (o == null) {
      services.track('versus_skipped', {'reason': 'no_opponent'});
      _logVersusSolo(waitedMs: waited);
    } else {
      services.track('versus_matched', {
        'opp_level': o.level,
        'opp_score': o.score,
        'level': menu.levels.level,
      });
    }
  }
  // endregion WP-5b

  /// The run bird's centre on screen (null without a bird).
  Vector2? get runBirdPosition {
    final b = _bird;
    if (b == null || !b.isLoaded) return null;
    return b.body.position.clone();
  }

  /// The run bird's vertical velocity (pt/s).
  double? get runBirdVelocityY {
    final b = _bird;
    if (b == null || !b.isLoaded) return null;
    return b.body.linearVelocity.y;
  }

  /// Score + HUD (the run's `RunContext.addScore`).
  void showRunScore(int value) {
    score = value;
    _hud.setScore(value);
  }

  /// §3.0.8 debug force: into the running run, else queued for the next.
  void debugForceElement(ElementId e) {
    final run = _run;
    if (run != null && state == GameState.playing) {
      run.debugForce(e);
    } else if (!runDebug.force.contains(e)) {
      runDebug.force.add(e);
    }
  }

  /// §3.0.8 debug: the next portal takes [r].
  void debugForceRide(RideId r) {
    final run = _run;
    if (run != null && state == GameState.playing) {
      run.debugForceRide(r);
    } else {
      runDebug.forcedRide = r;
    }
  }

  // endregion WP-0b

  // region WP-2d — HUD, pause, revive v2 (PRD-2 §3.14, §5.7, §5.9)
  PauseScreen? _pauseScreen;
  RunMenuBackdrop? _runBackdrop;
  void Function()? _reviveShopClosed;
  bool _runSettingsOpen = false;

  /// The pause screen while the run is paused (null otherwise).
  PauseScreen? get pauseScreen => _pauseScreen;

  /// The revive offer while it is up (null otherwise).
  ReviveScreen? get reviveScreen =>
      camera.viewport.children.whereType<ReviveScreen>().firstOrNull;

  /// The giant score circle (one master, PRD-2 §3.0.9; PRD-2.2 §18.1 a
  /// portal ride moves it into its scene).
  ScoreHud get scoreHud => _hud;

  /// The run's HUD (null without a run).
  RunHud? get runHud {
    final run = _run;
    return run == null ? null : RunHud.of(run);
  }

  /// True while a menu screen (Shop / settings) sits over a paused run.
  bool get _runMenuOverlayOpen => _runBackdrop != null;

  /// Settings opened from the pause screen (tests).
  bool get runSettingsOpen => _runSettingsOpen;

  /// The Shop opened from the revive offer (tests).
  bool get reviveShopOpen => _reviveShopClosed != null;

  /// §5.7 pause (button, Esc, backgrounding): the world freezes (runClock,
  /// Forge2D, hoops, particles), the pause card comes up. Only while
  /// playing (not during the tumble, revive or results).
  void pause() {
    if (state != GameState.playing) return;
    final run = _run;
    // PRD-2.3 §10.1 a waiting run pauses like a running one.
    if (run == null || run.dying || run.ended) return;
    state = GameState.paused;
    run.pause();
    final screen = PauseScreen();
    _pauseScreen = screen;
    camera.viewport.add(screen);
    pushBack(_pauseBack);
    sound.play(Sfx.click);
  }

  /// RESUME: straight back in — no 3-2-1 (owner decision 2026-10-08).
  void resume() {
    if (state != GameState.paused || _runMenuOverlayOpen) return;
    popBack(_pauseBack);
    _pauseScreen?.removeFromParent();
    _pauseScreen = null;
    state = GameState.playing;
    _run?.resume();
    sound.play(Sfx.click);
  }

  bool _pauseBack() {
    if (_runSettingsOpen) {
      closeRunSettings();
    } else {
      resume();
    }
    return true;
  }

  /// §5.7 the pause screen's settings button: the settings panel over the
  /// paused run (same panel and chrome as from home).
  void openRunSettings() {
    if (state != GameState.paused || _runMenuOverlayOpen) return;
    sound.play(Sfx.skTab);
    _pauseScreen?.hidden = true;
    _openRunBackdrop();
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
      onDeleteMyData: openDeleteDataConfirm,
      onPrivacyOptions: privacyOptionsShown ? openPrivacyOptions : null,
      onSupport: openSupport,
      onRedeemCode: redeemCodeAvailable ? openRedeemCode : null,
    );
    _settingsPanel = settings;
    _runSettingsOpen = true;
    _chromeHosts.add(settings);
    world.add(settings);
    (world as RunScaledWorld).realTime.add(settings);
    registerTintable(settings);
    fadeOpacity(settings, from: 0, to: 1);
    pushBack(_settingsBack);
  }

  /// Back from the run's settings: the pause card again.
  void closeRunSettings() {
    final settings = _settingsPanel;
    if (!_runSettingsOpen || settings == null) return;
    sound.play(Sfx.click);
    _settingsPanel = null;
    _runSettingsOpen = false;
    popBack(_settingsBack);
    unregisterTintable(settings);
    fadeOpacity(settings, from: settings.opacity, to: 0, removeOnDone: true);
    _closeRunBackdrop();
    _pauseScreen?.hidden = false;
  }

  /// §3.14 GET COINS ›: the Shop as an overlay on the paused game; the
  /// revive countdown waits ([onClose] when the Shop's back is pressed),
  /// the music plays at × 0.5.
  void openReviveShop({required void Function() onClose}) {
    if (state != GameState.reviving || _runMenuOverlayOpen) return;
    services.track('shop_open', {'source': 'revive'});
    _reviveShopClosed = onClose;
    _openRunBackdrop();
    unawaited(sound.duckMusic(ReviveConfig.shopMusicDuck));
    _menuTrail.clear();
    sound.play(Sfx.click);
    // PRD-2.3 §26.2: GET COINS is never locked.
    _showShop(allowLock: false);
  }

  void _closeReviveShop() {
    sound.play(Sfx.click);
    _dismissShop();
    menuScene = MenuScene.home;
    _closeRunBackdrop();
    unawaited(sound.duckMusic(1));
    final cb = _reviveShopClosed;
    _reviveShopClosed = null;
    cb?.call();
  }

  void _openRunBackdrop() {
    final b = RunMenuBackdrop();
    _runBackdrop = b;
    world.add(b);
    (world as RunScaledWorld).realTime.add(b);
    fadeOpacity(b, from: 0, to: 1);
    // The strips draw over the sheet, as over the menus.
    _ceiling.priority = kRunMenuBackdropPriority + 1;
    _ground.priority = groundOverMenusPriority;
  }

  void _closeRunBackdrop() {
    final b = _runBackdrop;
    _runBackdrop = null;
    if (b != null) {
      fadeOpacity(b, from: b.opacity, to: 0, removeOnDone: true);
    }
    _ceiling.priority = SpikeStrip.basePriority;
    _syncGroundPriority();
  }

  /// Drops the pause screen and any in-run menu overlay at once (replay).
  void _clearRunOverlays() {
    popBack(_pauseBack);
    _pauseScreen?.removeFromParent();
    _pauseScreen = null;
    if (_runSettingsOpen) {
      final settings = _settingsPanel;
      _settingsPanel = null;
      _runSettingsOpen = false;
      popBack(_settingsBack);
      if (settings != null) {
        unregisterTintable(settings);
        settings.removeFromParent();
      }
    }
    if (_reviveShopClosed != null) {
      _reviveShopClosed = null;
      _dismissShop();
      menuScene = MenuScene.home;
      unawaited(sound.duckMusic(1));
    }
    _runBackdrop?.removeFromParent();
    _runBackdrop = null;
    _ceiling.priority = SpikeStrip.basePriority;
    _syncGroundPriority();
    (world as RunScaledWorld).frozenSource = null;
  }

  /// §3.0.5 / §3.14 the tumble is over (1.5 s, or resting): the revive
  /// offer when at least 6 hoops were passed, else the run ends (bonus /
  /// results). A death with ≤ 5 hoops uses no ladder step.
  void runDeathSettled(RunController run) {
    if (!identical(run, _run)) return;
    final revive = PostRunScreens.revive;
    if (state == GameState.dying &&
        revive != null &&
        ReviveLadder.eligible(
          run.state,
          showcase: run.setup.showcase?.freeRevive ?? false,
        )) {
      state = GameState.reviving;
      unawaited(_offerRevive(run, revive));
      return;
    }
    endRun(run.endRun());
  }

  Future<void> _offerRevive(
    RunController run,
    ReviveScreenFactory revive,
  ) async {
    var outcome = ReviveOutcome.declined;
    try {
      outcome = await revive.show(this, run.summarize());
    } catch (_) {
      outcome = ReviveOutcome.declined;
    }
    if (!identical(run, _run) || outcome == ReviveOutcome.revived) return;
    if (state == GameState.reviving) endRun(run.endRun());
  }

  /// §3.14 straight back in at the end of the phoenix (1.65 s): the bird
  /// flies again at the safe line [y], flaps up once (flap.mp3), and the
  /// run resumes with 2 s of invulnerability.
  void finishRevive(RunController run, ReviveKind k, int price, double y) {
    if (!identical(run, _run) || state != GameState.reviving) return;
    state = GameState.playing;
    final bird = _bird;
    if (bird != null) {
      bird
        ..reviveFlight(y)
        ..setSpriteOpacity(1)
        ..flap();
    }
    run.finishRevive(k, price, y);
  }
  // endregion WP-2d

  // region WP-1a — hoops replace pipes (PRD-2 §3.0.4, §3.0.5, §3.1)
  /// The run bird (null on the home screen before a run / after a reset).
  Bird? get runBird => _bird;

  /// Audit HIDE: whether the run bird is drawn right now ([Bird.presented]).
  /// Every attachment of the bird reads this one signal.
  bool get runBirdPresented => _bird?.presented ?? false;

  /// The current colour stage's palette key (0, 5, …, 50).
  int get stageKey => _stage;

  /// §3.0.1 colour stage of a run: [stageIndex] = floor(hoopsPassed / 10)
  /// mod 11, the existing 11 palettes in order (gold last).
  void applyRunStage(int stageIndex) {
    final key = paletteKeyForStageIndex(stageIndex);
    if (key == _stage) return;
    _stage = key;
    _startColorFade(paletteForStage(key));
  }

  /// §3.0.5 a death that is not saved: the bird turns into the ballistic
  /// tumble (the run drives it) and the game waits in [GameState.dying]
  /// until the run hands over to the post-run flow ([endRun]).
  void beginDying() {
    if (state != GameState.playing) return;
    state = GameState.dying;
    sound.play(Sfx.gameover);
    _bird?.die();
  }
  // endregion WP-1a

  /// True while the home screen is up with nothing over it.
  bool get _homeInteractive =>
      // region P26-G2c
      _streakLostPopup == null &&
      // endregion
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
    // WP-2d: also the Shop opened over a paused run (revive GET COINS).
    final menusUp = state == GameState.start || _runMenuOverlayOpen;
    if (!menusUp || menuScene != scene || _runStarting) {
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

  /// Mounted [MenuScreen]s. While any is, the ground spike strip draws
  /// above them, so their scroll lists show only through the gaps between
  /// the teeth instead of being cut off flat at the tips.
  final Set<MenuScreen> _menuScreens = {};

  /// Priority of the ground strip while a [MenuScreen] is mounted: above
  /// the screens (20), below popups, toasts and flashes (25+). Shares 21
  /// with the coin pill, which never overlaps it.
  static const int groundOverMenusPriority = 21;

  /// Ground strip priority (tests).
  int get groundStripPriority => _ground.priority;

  void menuScreenMounted(MenuScreen screen) {
    _menuScreens.add(screen);
    _syncGroundPriority();
  }

  void menuScreenRemoved(MenuScreen screen) {
    _menuScreens.remove(screen);
    _syncGroundPriority();
  }

  /// WP-NAME open Settings panels: their body scrolls under the ground
  /// strip too (like a [MenuScreen]'s list).
  int _groundHolds = 0;

  /// A Settings panel mounted ([on]) or left.
  void holdGroundOverMenus(bool on) {
    _groundHolds = max(0, _groundHolds + (on ? 1 : -1));
    _syncGroundPriority();
  }

  void _syncGroundPriority() {
    _ground.priority = _menuScreens.isEmpty && _groundHolds == 0
        ? SpikeStrip.basePriority
        : groundOverMenusPriority;
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
        // PRD-2.3 §26.2: nothing under the lock scrolls.
        if (!(_shop?.locked ?? false)) _shop?.scrollToCoins();
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

  void _showShop({bool scrollToCoins = false, bool allowLock = true}) {
    menuScene = MenuScene.shop;
    // PRD-2.3 §26: the Shop opens dimmed below the unlock best (from Home,
    // the coin pill or Skins; never the revive shop, [allowLock] false).
    final lock = allowLock && menu.locked
        ? ['SCORE ${Config.menuUnlockBest} POINTS', 'TO UNLOCK THE SHOP']
        : null;
    if (lock != null) {
      services.track('menu_locked_view', {
        'screen': 'shop',
        'best': storage.bestScore,
      });
    }
    final shop = ShopScreen(onBack: closeShop, lock: lock);
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
    if (_reviveShopClosed != null) {
      _closeReviveShop();
      return;
    }
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

  // region PRD-2.2 §7.9 — privacy options entry
  /// The Settings "Privacy options" link shows (EEA/UK: the UMP privacy
  /// options are required; never on iOS / Linux, whose consent is a fake
  /// that never requires them).
  bool get privacyOptionsShown => monetization.consent.privacyOptionsRequired;

  bool _privacyOptionsBusy = false;

  /// Opens the UMP privacy options form. The consent helper re-reads
  /// `canRequestAds` when it closes: withdrawn → the ad loaders stop and
  /// banner / interstitial are off from the next START; granted → the SDK
  /// starts and the ads preload (the services listen to it).
  Future<void> openPrivacyOptions() async {
    if (_privacyOptionsBusy) return;
    _privacyOptionsBusy = true;
    sound.play(Sfx.click);
    services.track('privacy_options_opened');
    try {
      await monetization.consent.showPrivacyOptions();
    } catch (e) {
      debugPrint('privacy options failed: ${redactSecrets(e)}');
    } finally {
      _privacyOptionsBusy = false;
    }
  }
  // endregion PRD-2.2 §7.9

  /// Shop free-coins row: a rewarded ad for +[FreeCoinsPolicy.reward]
  /// coins, within the policy's cooldown / daily cap. PRD-2.2 §7.7: NO ADS
  /// owners watch the ad like everyone (the 2.1 CLAIM without an ad is
  /// gone).
  Future<void> claimFreeCoins() async {
    if (!_sceneOnTop(MenuScene.shop) || _freeCoinsBusy) return;
    final policy = menu.freeCoins;
    if (!policy.canClaim) return;
    sound.play(Sfx.bnAdBtn);
    _freeCoinsBusy = true;
    try {
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
    if (state != GameState.start && !_runMenuOverlayOpen) return;
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
    if (state != GameState.start && !_runMenuOverlayOpen) return;
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
    if (state != GameState.start && !_runMenuOverlayOpen) return;
    sound.play(Sfx.click);
    await purchases.restore();
  }

  /// Shop featured-item row: the skin shop on [item]'s tab with it tried
  /// on.
  void openFeaturedItem(SkinItem item) => _runMenuOverlayOpen
      ? null // WP-2d: no skin shop over a paused run
      : openSkins(layer: item.layer, tryOnId: item.id, source: 'shop_featured');

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
    final tryOn =
        layer != null && tryOnId != null && !menu.items.isOwned(layer, tryOnId)
        ? tryOnId
        : null;
    // PRD-2.3 §26: the Skins open dimmed below the unlock best.
    final lock = menu.locked
        ? ['SCORE ${Config.menuUnlockBest} POINTS', 'TO UNLOCK SKINS']
        : null;
    if (lock != null) {
      services.track('menu_locked_view', {
        'screen': 'skins',
        'best': storage.bestScore,
      });
    }
    final screen = SkinShopScreen(
      onBack: closeSkins,
      initialTab: layer ?? SkinLayer.bird,
      initialTryOn: tryOn,
      lock: lock,
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
      final wasEquipped = items.isEquipped(layer, id) && screen.tryOnId == null;
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
    // PRD-2.3.1 §12.2 / §12.5 the shop always counts; its toast shows at once.
    achievements.onShopPurchase(
      owned: items.ownedCount,
      total: kCollectibleTotal,
    );
    // QA P19: the toast is queued once the unlock is durable.
    unawaited(achievements.flush().then((_) => showAchievementToasts()));
    _coinPill
      ..balance = menu.wallet.balance
      ..countFrom(before);
    if (identical(_skinShop, screen)) {
      screen
        ..clearTryOn()
        ..celebrate(item);
    }
  }

  // region P26-G2c
  StreakLostPopup? _streakLostPopup;
  StreakLostPopup? get streakLostPopup => _streakLostPopup;
  double _streakLostSettle = 0;
  int _streakLostVisit = 0;
  int _streakRestoreTries = 0;
  bool _streakLostBusy = false;

  bool get streakLostPending => dayStreak.shouldOfferLost(
    today: storage.today,
    runNumber: storage.gamesPlayed + 1,
  );

  Future<void> _saveLostStreak(DayStreak next) async {
    await storage.saveStreakDays(next.streakDays);
    await storage.saveStreakLastDay(next.streakLastDay);
    await storage.saveStreakLostDays(next.streakLostDays);
    await storage.saveStreakLostSeenDay(next.streakLostSeenDay);
  }

  void _checkStreakLost(double dt) {
    if (!_homeInteractive ||
        _home?.built != true ||
        _home!.opacity < 1 ||
        modalPopupOpen ||
        _popupQueue.isNotEmpty ||
        !streakLostPending ||
        _adsShowing > 0 ||
        _fakeAd != null) {
      _streakLostSettle = 0;
      return;
    }
    _streakLostSettle += dt;
    if (_streakLostSettle < Config.levelUpSettleDelay) return;
    _streakLostSettle = 0;
    homeMoments.tryShow(HomeMoment.streakLost, () {
      unawaited(_openStreakLost());
    });
  }

  Future<void> _openStreakLost() async {
    if (_streakLostPopup != null || !streakLostPending) return;
    final next = dayStreak.markLostShown(
      today: storage.today,
      runNumber: storage.gamesPlayed + 1,
    );
    final popup = StreakLostPopup(
      state: next,
      noAds: menu.noAds,
      balance: () => menu.wallet.balance,
      onRestore: () => unawaited(restoreLostStreak()),
      onGiveUp: () => unawaited(giveUpLostStreak()),
      onDismiss: () => unawaited(dismissLostStreak()),
      onMomentDone: _closeStreakLost,
    );
    // Own the modal slot before persisting or mounting any content.
    _streakLostPopup = popup;
    _streakRestoreTries = 0;
    await _saveLostStreak(next);
    world.add(popup);
    pushBack(_streakLostBack);
    services.track('streak_lost_shown', {
      'days': next.streakLostDays,
      'visit': _streakLostVisit,
    });
  }

  bool _streakLostBack() {
    unawaited(dismissLostStreak());
    return true;
  }

  void _closeStreakLost() {
    final popup = _streakLostPopup;
    if (popup == null) return;
    final restored = popup.phase == StreakLostPhase.restoring;
    popup.active = false;
    popup.removeFromParent();
    _streakLostPopup = null;
    _streakLostBusy = false;
    popBack(_streakLostBack);
    if (restored && !reduceMotion) {
      final chips = _home?.children.whereType<StreakStrip>();
      if (chips != null && chips.isNotEmpty) {
        chips.first.add(
          ScaleEffect.by(
            Vector2.all(1.14),
            EffectController(duration: .16, reverseDuration: .16),
          ),
        );
      }
    }
    _drainPopups();
  }

  Future<void> dismissLostStreak() async {
    final popup = _streakLostPopup;
    if (popup == null || !popup.active || popup.resolving) return;
    // Cancels any pending load by dropping its popup identity. It cannot
    // grant later, even if an SDK future eventually completes.
    _closeStreakLost();
    await _saveLostStreak(
      dayStreak.dismissLost(
        today: storage.today,
        runNumber: storage.gamesPlayed + 1,
      ),
    );
  }

  Future<void> giveUpLostStreak() async {
    final popup = _streakLostPopup;
    if (popup == null || !popup.active || popup.resolving) return;
    popup.giveUpMoment();
    final next = dayStreak.giveUp(
      today: storage.today,
      runNumber: storage.gamesPlayed + 1,
    );
    await _saveLostStreak(next);
    services.track('streak_give_up', {'days': popup.state.streakLostDays});
  }

  Future<void> restoreLostStreak() async {
    final popup = _streakLostPopup;
    if (popup == null ||
        !popup.isLoaded ||
        !popup.canRestore ||
        _streakLostBusy) {
      return;
    }
    _streakLostBusy = true;
    final before = menu.wallet.balance;
    final noAds = menu.noAds;
    final payment = dayStreak.restorePayment(noAds: noAds, coins: before);
    if (!payment.enabled) {
      _streakLostBusy = false;
      return;
    }
    popup.loading(coins: noAds);
    if (noAds) popup.active = false;
    bool current() => identical(_streakLostPopup, popup) && !popup.resolving;
    var paid = false;
    try {
      if (noAds) {
        paid = await menu.wallet.spend(
          payment.coins,
          CoinSource.streakRestore.analyticsName,
        );
        if (paid && !reduceMotion) {
          _coinPill.countFrom(before, duration: .65, linear: true);
          final done = Completer<void>();
          world.add(
            CoinFly(
              coin: Sprite(images.fromCache('menu/coin.png')),
              from: Rect.fromCenter(
                center: _coinPill.coinFlyTarget,
                width: 24,
                height: 18,
              ),
              to: popup.buttonRect.center,
              count: 6,
              duration: .45,
              delay: 0,
              stagger: .035,
              random: coinFlyRandom,
              onDone: () {
                if (!done.isCompleted) done.complete();
              },
            ),
          );
          // Payment is committed; don't permit dismissal during the flight.
          popup.active = false;
          await done.future;
        }
      } else {
        _streakRestoreTries++;
        // An unavailable/failed/incomplete video keeps LOADING visible for
        // about eight seconds, while GIVE UP and × remain available.
        final started = storage.now();
        var result = AdResult.unavailable;
        if (await monetization.ads.ensureLoaded(
          timeout: const Duration(seconds: 8),
        )) {
          if (!current()) return;
          result = await showRewardedAd(AdPlacement.streakRestore);
        }
        if (!current()) return;
        paid = result == AdResult.completed;
        if (!paid) {
          final remaining =
              const Duration(seconds: 8) - storage.now().difference(started);
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
          if (!current()) return;
          await _saveLostStreak(
            dayStreak.dismissLost(
              today: storage.today,
              runNumber: storage.gamesPlayed + 1,
            ),
          );
          services.track('streak_restore_ad_fail', {'reason': result.name});
          popup.retry();
          return;
        }
      }
      if (!current()) return;
      if (!paid) {
        popup.retry();
        return;
      }
      popup.active = false;
      final next = dayStreak.restore(
        today: storage.today,
        runNumber: storage.gamesPlayed + 1,
        noAds: noAds,
        coins: before,
        paymentCompleted: paid,
      );
      await _saveLostStreak(next);
      services.track('streak_restore', {
        'days': next.streakDays,
        'method': noAds ? 'coins' : 'ad',
        'ad_tries': _streakRestoreTries,
      });
      popup.restoreMoment(
        next.streakDays,
        flewToday: next.flewToday(storage.today),
      );
    } catch (_) {
      if (current()) {
        if (!noAds) {
          services.track('streak_restore_ad_fail', {'reason': 'error'});
        }
        popup.retry();
      }
    } finally {
      if (identical(_streakLostPopup, popup)) {
        _streakLostBusy = false;
        popup.active = true;
      }
    }
  }
  // endregion

  // region P26-G2b
  StreakCard? _streakCard;
  StreakCard? get streakCard => _streakCard;
  double _streakSettle = 0;
  bool _streakCollecting = false;
  double _streakSlotPop = 0;
  bool _streakStartInFlight = false;
  MenuTag? _streakFreeTag;

  DayStreak get dayStreak => DayStreak(
    streakDays: storage.streakDays,
    streakLastDay: storage.streakLastDay,
    streakPaidDay: storage.streakPaidDay,
    streakLostDays: storage.streakLostDays,
    streakLostSeenDay: storage.streakLostSeenDay,
  ).refresh(today: storage.today, runNumber: storage.gamesPlayed + 1);

  bool get streakRewardPending => dayStreak.rewardPending(
    today: storage.today,
    runNumber: storage.gamesPlayed + 1,
  );

  StreakReward get previewStreakReward => DayStreak.rewardForDay(
    dayStreak.streakDays,
    canReceiveFeather: storage.feathers < 3,
    canReceivePiece: storage.puzzlePieces != 15,
  );

  bool get streakFreeStart =>
      storage.armedPowerup == 'streak:bigHoops' ||
      storage.armedPowerup == 'streak:shield';
  Powerup get streakStarter => storage.armedPowerup == 'streak:shield'
      ? Powerup.shield
      : Powerup.bigHoops;

  /// Run-end integration seam. The run owner supplies its 1-based number and
  /// eligibility; Home never infers a finished run from an arrival.
  Future<void> recordStreakRun({
    required int runNumber,
    bool debug = false,
  }) async {
    final next = dayStreak.finishRun(
      today: storage.today,
      runNumber: runNumber,
      debug: debug,
    );
    await storage.saveStreakDays(next.streakDays);
    await storage.saveStreakLastDay(next.streakLastDay);
    await storage.saveStreakLostDays(next.streakLostDays);
    await storage.saveStreakLostSeenDay(next.streakLostSeenDay);
  }

  void _checkStreakReward(double dt) {
    if (!_homeInteractive ||
        _home?.built != true ||
        _home!.opacity < 1 ||
        modalPopupOpen ||
        _popupQueue.isNotEmpty ||
        !streakRewardPending ||
        _adsShowing > 0 ||
        _fakeAd != null) {
      _streakSettle = 0;
      return;
    }
    _streakSettle += dt;
    if (_streakSettle < Config.levelUpSettleDelay) return;
    _streakSettle = 0;
    homeMoments.tryShow(
      HomeMoment.streakReward,
      () => _openStreak(reward: true),
    );
  }

  void openStreakCard() {
    if (!_homeInteractive ||
        modalPopupOpen ||
        !DayStreak.unlocked(storage.gamesPlayed + 1)) {
      return;
    }
    _openStreak(reward: false);
  }

  void _openStreak({required bool reward}) {
    if (_streakCard != null) return;
    final popup = StreakCard(
      state: dayStreak,
      today: storage.today,
      reward: reward,
      onDismiss: closeStreakCard,
      onCollect: (from) => unawaited(collectStreakReward(from)),
    );
    _streakCard = popup;
    world.add(popup);
    pushBack(_streakBack);
    sound.play(Sfx.skTap);
  }

  bool _streakBack() {
    closeStreakCard();
    return true;
  }

  void closeStreakCard() {
    if (_streakCollecting) return;
    final card = _streakCard;
    if (card == null) return;
    _streakCard = null;
    card.active = false;
    card.removeFromParent();
    popBack(_streakBack);
    _drainPopups();
  }

  Future<void> collectStreakReward(Rect from) async {
    if (_streakCard?.reward != true || _streakCollecting) return;
    final result = dayStreak.collect(
      today: storage.today,
      runNumber: storage.gamesPlayed + 1,
      canReceiveFeather: storage.feathers < 3,
      canReceivePiece: storage.puzzlePieces != 15,
    );
    final reward = result.reward;
    if (reward == null) {
      closeStreakCard();
      return;
    }
    _streakCollecting = true;
    _streakCard!.active = false;
    try {
      // Mark before awaiting animations: duplicate taps cannot pay twice.
      await storage.saveStreakPaidDay(result.state.streakPaidDay);
      if (reward.coins > 0) {
        playCoinReward(
          CoinRewardAnimation(
            amount: reward.coins,
            from: from,
            coins: 6,
            countDuration: .6,
            ticks: 8,
            confetti: 18,
          ),
        );
        await menu.wallet.add(reward.coins, CoinSource.streak);
      }
      switch (reward.item) {
        case StreakRewardItem.bigHoops:
        case StreakRewardItem.shield:
          final item = reward.item!;
          await storage.saveArmedPowerup(
            item == StreakRewardItem.shield
                ? 'streak:shield'
                : 'streak:bigHoops',
          );
          _flyStreakStart(item, from.center);
        case StreakRewardItem.feather:
          await storage.saveFeathers(storage.feathers + 1);
        case StreakRewardItem.piece:
          final missing = (~storage.puzzlePieces) & 15;
          await storage.savePuzzlePieces(
            storage.puzzlePieces | (missing & -missing),
          );
        case null:
          break;
      }
      services.track('day_streak', {'days': result.state.streakDays});
    } finally {
      _streakCollecting = false;
      closeStreakCard();
    }
  }

  void _flyStreakStart(StreakRewardItem item, Offset from) {
    final slot = _home?.slotButton;
    if (slot == null) return;
    final target = Offset(slot.x + slot.width / 2, slot.y + slot.height / 2);
    _streakStartInFlight = !reduceMotion;
    void land() {
      _streakStartInFlight = false;
      sound.play(
        item == StreakRewardItem.shield ? Sfx.puShieldGet : Sfx.skHoop,
      );
      if (!reduceMotion) {
        _streakSlotPop = .32;
        slot.add(StreakSlotLanding());
        world.add(
          ConfettiBurst.burst(
            origin: target,
            count: 22,
            speed: 110,
            driftX: 0,
            priority: 1001,
          ),
        );
      }
    }

    if (reduceMotion) {
      land();
      return;
    }
    sound.play(Sfx.vsWhoosh);
    world.add(
      FetchFlight(
        from: from,
        to: target,
        spec: const FetchSpec(grow: 0, fly: .6, trail: false),
        art: (canvas, scale, rotation) =>
            paintStreakPowerup(canvas, item, 30 * scale),
        onLand: land,
        priority: 1001,
      ),
    );
  }

  void syncStreakSlot(PowerupSlotButton slot) {
    if (streakFreeStart) {
      slot.setState(offered: streakStarter, noAds: true, adAvailable: true);
    }
    if (_streakFreeTag?.parent != slot) {
      _streakFreeTag?.removeFromParent();
      _streakFreeTag = null;
    }
    if (streakFreeStart && !_streakStartInFlight && _streakFreeTag == null) {
      slot.add(
        _streakFreeTag = MenuTag(
          'FREE',
          position: Vector2(slot.width - 24, -9),
          priority: 20,
        ),
      );
    } else if (!streakFreeStart) {
      _streakFreeTag?.removeFromParent();
      _streakFreeTag = null;
    }
    if (_streakSlotPop > 0) {
      slot.pulse.scale = reduceMotion
          ? 1
          : 1 + .14 * math.sin(math.pi * (1 - _streakSlotPop / .32));
    }
  }
  // endregion

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
    fadeOpacity(screen, from: 0, to: 1, duration: Config.levelsEnterDuration);
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

  // region P26-C2L
  /// Q-H1 interim trigger: once home has been up with nothing over it for
  /// [Config.levelUpSettleDelay] and a LEVEL UP is owed (a run reached a
  /// new level, or the catch-up after the update), the popup opens. The
  /// C2 visit budget gives an owed LEVEL UP priority over No-Ads.
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
    homeMoments.show(HomeMoment.levelUp, () {
      _showLevelUpPopup(pending);
    });
  }

  // endregion

  void _showLevelUpPopup(PendingLevelUp pending) {
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

  // region PRD-2.3 §23 — rating prompt

  /// The storage reload that the latest [replay] started (PRD-2.3 §24.2).
  Future<void>? _homeReload;

  /// The rating trigger of the results page on screen (`run5` / `new_best`),
  /// or null. Set by [endRun]; cleared once the request goes out.
  String? _ratingTrigger;

  /// A rating request the C2 budget deferred to a later Home visit. The
  /// results page's own [Config.ratingDelaySeconds] window has passed, so
  /// the next arrival offers the sheet directly.
  String? _deferredRatingTrigger;

  /// Seconds the results page has been settled with no overlay open (the
  /// §23.2 item 4 count).
  double _ratingSettle = 0;

  /// The sheet was requested during this run's results: its NEXT skips the
  /// interstitial (reason `rating`) and its Home arrival skips the No-Ads
  /// popup (PRD-2.3 §24.2). Reset when the next run starts.
  bool _ratingRequestedThisRun = false;

  /// §23.2 item 4: the request is due once the results page has settled for
  /// [Config.ratingDelaySeconds] with no overlay open. The count starts again
  /// after an overlay closes. A NEXT before that cancels it (no request and
  /// no cooldown, §23.2 item 5).
  void _checkRatingPrompt(double dt) {
    final trigger = _ratingTrigger;
    final page = _results;
    if (trigger == null || page == null || state != GameState.results) {
      _ratingSettle = 0;
      return;
    }
    final ready =
        page.settled &&
        !page.leaving &&
        !modalPopupOpen &&
        _debugPanel == null &&
        _fakeAd == null &&
        _adsShowing == 0 &&
        !_interstitialBusy;
    if (!ready) {
      _ratingSettle = 0;
      return;
    }
    _ratingSettle += dt;
    if (_ratingSettle < Config.ratingDelaySeconds) return;
    _ratingSettle = 0;
    _requestRating(trigger);
  }

  /// §23.2: writes the cooldown, then asks the store for its sheet. Nothing
  /// happens (no request, no cooldown) when the sheet is not available here
  /// (§23.4) or when a request went out in the last [Config.ratingCooldown].
  void _requestRating(String trigger) {
    final opened = homeMoments.tryShow(HomeMoment.rating, () {
      _requestRatingNow(trigger);
    });
    if (opened) {
      _ratingTrigger = null;
    } else {
      // A higher-priority moment owns this Home visit. Keep the rating due;
      // the next arrival includes it in the visit requests.
      _ratingTrigger = null;
      _deferredRatingTrigger = trigger;
    }
  }

  /// Offers a rating request that the previous Home visit deferred because a
  /// higher-priority popup took it. Only the settled Home can show it; if the
  /// current visit's selected moment wins again, it stays deferred.
  void _checkDeferredRating() {
    final trigger = _deferredRatingTrigger;
    final home = _home;
    if (trigger == null ||
        !_homeInteractive ||
        home == null ||
        !home.built ||
        home.opacity < 1 ||
        modalPopupOpen ||
        _debugPanel != null ||
        _fakeAd != null ||
        _adsShowing > 0 ||
        _interstitialBusy) {
      return;
    }
    final opened = homeMoments.tryShow(HomeMoment.rating, () {
      _deferredRatingTrigger = null;
      _requestRatingNow(trigger);
    });
    if (opened) _deferredRatingTrigger = null;
  }

  void _requestRatingNow(String trigger) {
    if (!rating.available) return;
    final now = storage.now();
    if (!RatingRules.cooldownOver(
      lastRequestAt: storage.lastRatingRequestAt,
      now: now,
      cooldown: Config.ratingCooldown,
    )) {
      return;
    }
    _ratingRequestedThisRun = true;
    unawaited(
      storage.saveLastRatingRequestAt(now.millisecondsSinceEpoch ~/ 1000),
    );
    services.track('rate_requested', {
      'trigger': trigger,
      'runs': storage.gamesPlayed,
      'best': storage.bestScore,
    });
    unawaited(rating.request());
  }
  // endregion PRD-2.3 §23

  // region PRD-2.3 §24 — the No-Ads popup after a run
  /// PRD-2.3 §24.2: the No-Ads offer on a Home arrival after a run. Never on
  /// the arrival of a run that requested the rating sheet (item 3), and not
  /// when a gift came up on this visit (PRD-2.3 §0 item 2).
  void _offerNoAdsAfterRun() {
    if (_ratingRequestedThisRun || giftThisHomeVisit) return;
    _queueNoAdsOffer(
      check: 'after_run',
      stale: () =>
          giftThisHomeVisit ||
          menu.noAds ||
          state != GameState.start ||
          menuScene != MenuScene.home,
    );
  }
  // endregion PRD-2.3 §24

  // --- No-ads popup (PRD-1 §5.1) ------------------------------------------

  /// The automatic session-start upsell (PO change 2026-10-05: the
  /// popup's only path — home-tile / Shop-banner taps buy directly now;
  /// the schedule is [_startSession] + NoAdsPopupPolicy). [reason] is the
  /// `noads_popup_shown` reason (videos / best / level / fallback; the
  /// debug force passes `forced`). No-op during a run, over another
  /// popup / the debug panel / a fake ad, or while the menus are
  /// transitioning; owners get a toast instead.
  void openNoAdsPopup({String? reason, String check = 'session'}) {
    if (_noAdsPopup == null && modalPopupOpen) {
      // Another popup is up: the upsell takes its turn after it (only one
      // offer ever waits).
      if (_noAdsOfferQueued) return;
      _noAdsOfferQueued = true;
      _queuePopup(() => true, () {
        _noAdsOfferQueued = false;
        openNoAdsPopup(reason: reason, check: check);
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
    // region P26-C2L
    // The debug panel's explicit force bypasses automatic pacing. Keep
    // normal offers routed through C2, and leave the visit budget intact.
    final show = reason == 'forced' ? homeMoments.showDebug : homeMoments.show;
    show(HomeMoment.noAds, () {
      services.track('noads_popup_shown', {
        'trigger': _launchTrigger,
        'reason': ?reason,
        // PRD-2.3 §24.4: session (app launch / return) or after_run.
        'check': check,
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
    });
    // endregion
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
  /// credited. In the menus the pack's coins burst from its pack art in
  /// the Shop (the screen centre when the Shop is not on top, e.g. a late
  /// store callback) into the pill and count up; during a run the pill is
  /// hidden and simply shows the new balance later.
  void _onPackPurchased(IapProduct product) {
    if (state != GameState.start) return;
    final shop = _sceneOnTop(MenuScene.shop) && (_shop?.built ?? false)
        ? _shop
        : null;
    final from =
        shop?.packFor(product)?.artRect ??
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

  // region PRD-2.3 §22 — gift codes

  /// PRD-2.3 §0 item 2 (several popups on one Home visit): true from the
  /// moment a gift is granted until the next run starts. The gift popup
  /// goes first, then the LEVEL UP reward (it waits for an empty popup
  /// queue); the No-Ads popup is skipped for the rest of this visit — every
  /// No-Ads popup trigger (the session start here, PRD-2.3 §24's
  /// after-run check) must read this flag.
  bool get giftThisHomeVisit => _giftThisHomeVisit;
  bool _giftThisHomeVisit = false;

  /// Gift popups granted but not shown yet (tests).
  int get pendingGiftPopups => _pendingGiftPopups;
  int _pendingGiftPopups = 0;

  /// PRD-2.3 §22.2 item 4: a gift code was granted (called right before
  /// the coins / No Ads are credited). The pill keeps its number and the
  /// owned looks wait; the gift popup opens the next time a menu is up
  /// (never mid-run), one per code, one after the other.
  void _onGiftGranted(GiftGrant gift) {
    _giftThisHomeVisit = true;
    _pendingGiftPopups++;
    if (gift.noAds) {
      _noAdsRevealHeld = true;
      _noAdsVideoHeld = true;
    }
    _coinPill
      ..hold()
      ..reserve(gift.coins);
    _queuePopup(() => _menusUp && _fakeAd == null && _adsShowing == 0, () {
      _pendingGiftPopups--;
      openNoAdsCelebration(gift: gift);
    });
  }
  // endregion PRD-2.3 §22

  /// The celebration itself (also the debug panel's preview): `noads_unlock`,
  /// a white flash and a short shake (not under reduce motion), the popup,
  /// and at 0.43 s a confetti burst from the card plus a rain over the
  /// screen.
  void openNoAdsCelebration({GiftGrant? gift}) {
    if (_noAdsCelebration != null) return;
    if (gift == null) services.logNoAdsCelebrationShown(_noAdsSource);
    sound.play(Sfx.noadsUnlock);
    final motion = !reduceMotion;
    final popup = gift != null
        ? NoAdsCelebration.gift(
            gift,
            onClaim: () => _claimNoAdsBonus(claimed: true),
            onDismiss: () => _claimNoAdsBonus(claimed: false),
          )
        : NoAdsCelebration(
            onClaim: () => _claimNoAdsBonus(claimed: true),
            onDismiss: () => _claimNoAdsBonus(claimed: false),
          );
    _noAdsCelebration = popup;
    world.add(popup);
    fadeOpacity(popup, from: 0, to: 1, duration: 0.16);
    pushBack(_noAdsCelebrationBack);
    if (motion) {
      world.add(
        ScreenFlash(
          size: Vector2(Config.worldWidth + 2 * extraWidth, viewHeight),
        )..position.x = -extraWidth, // WP-TAB: full width
      );
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
              width: viewWidth, // WP-TAB: the whole screen
              left: -extraWidth / 2,
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
    final gift = popup.gift;
    final int reservation;
    if (gift != null) {
      // PRD-2.3 §22.2: the gift's coins were reserved when it was granted.
      reservation = gift.coins;
    } else {
      reservation = _noAdsBonusReserved ? kNoAdsBonusCoins : 0;
      _noAdsBonusReserved = false;
    }
    playCoinReward(
      CoinRewardAnimation.noAdsBonus(
        from: from,
        amount: popup.bonusCoins,
        reservation: reservation,
        onDone: () => _after(Config.noAdsFlipDelay, _flipNoAdsOwned),
      ),
    );
    _drainPopups();
  }

  /// §7 owned states, `noads_stamp`: the Shop banner flips to AD-FREE ·
  /// THANK YOU; on home the No-ads tile flips to ✓ AD-FREE and the slot's
  /// video icon shrinks away. PRD-2.2 §7.7: the Shop's GET chip keeps its
  /// video icon (free coins need an ad for everyone). Screens opened later
  /// simply show the owned state.
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
    void dropVideo() => _noAdsVideoHeld = false;

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

  // region PRD-2.2 §28 — game audio around ads, death and other apps

  /// [sound] exists (lifecycle events can arrive before onLoad made it).
  bool _soundReady = false;

  /// iOS round 2: the iOS-only audio steps (a test seam).
  @visibleForTesting
  bool Function() isIOS = () => !kIsWeb && Platform.isIOS;

  /// When the last full-screen ad ended (any outcome): the ad's own player
  /// may still be listed as "other music" right after it closes.
  DateTime? _lastAdEndedAt;

  bool get _adJustEnded {
    final t = _lastAdEndedAt;
    return t != null && storage.now().difference(t) < Config.adAudioSettle;
  }

  /// PRD-2.2 §28.3 (S7-13): is the player's own music playing? The full
  /// answer (Android: the playback list or the `isMusicActive()` stream
  /// fallback) is trusted while the game is quiet; when the game's own
  /// sound may be on the music stream ([SoundService.ownSoundRecent]) a
  /// "yes" is confirmed by the playback list alone, so the game's flaps
  /// never count as other music (docs/p22/ADS.md).
  Future<bool> _otherMusicNow() async {
    // PRD-2.3 §13.4: while the game's own music plays, isMusicActive() is
    // always true; only the playback list can answer.
    if (sound.musicPlaying) return audioFocus.isOtherMediaListed();
    if (!await audioFocus.isOtherMusicActive()) return false;
    if (!sound.ownSoundRecent) return true;
    return audioFocus.isOtherMediaListed();
  }

  Future<void> _startMusicChecked() async {
    // PRD-2.3 §13.4: "own music" only after two "yes" answers 1 s apart.
    musicGuard.confirmOwnMusic(
      'launch',
      then: () => unawaited(sound.startMusic()),
    );
  }

  /// §28.2 / §28.3: the music pauses whenever the app is not in the
  /// foreground; coming back, a stale ad suspend is cleared and the
  /// player's own music (if it plays now) keeps the game music off.
  ///
  /// PRD-2.3 §13.4: `inactive` (a heads-up banner, the notification shade,
  /// a system sheet) is not the background: the music keeps playing. On a
  /// real return the check runs [Config.musicForegroundCheckDelay] after
  /// it and needs two "yes" answers; the music stays held until then.
  void _audioLifecycle(AppLifecycleState state) {
    if (kDebugMode) debugPrint('Sound: lifecycle ${state.name}');
    if (!_soundReady) return;
    // iOS round 2b: no audio player is created while not active. Android:
    // `inactive` (a consent form, a Play Games banner, the notification
    // shade) is still the foreground and its players work, so only the
    // background gates it there (2.4.0 (23): core sounds stayed silent
    // after an inactive launch).
    sound.setAppActive(
      state == AppLifecycleState.resumed ||
          (state == AppLifecycleState.inactive && !isIOS()),
    );
    if (state == AppLifecycleState.inactive) return;
    if (state != AppLifecycleState.resumed) {
      musicGuard.onBackground();
      sound.setBackground(true);
      return;
    }
    musicGuard.onForeground();
    // iOS round 2 §2: after a long background (the app was suspended, the
    // screen locked) the sound-effect players are created afresh: an
    // AVPlayer whose item failed meanwhile plays nothing and never says so.
    final since = _backgroundSince;
    final away = since == null ? null : storage.now().difference(since);
    sound.logMusic(
      'foreground-check away=${away?.inSeconds ?? -1}s '
      'hold=${sound.musicHoldReason ?? '-'}',
    );
    // Round 2b: ONE rebuild on the return, also for any number of
    // media-services resets that were deferred while in the background.
    final long = isIOS() && away != null && away >= Config.iosVoiceRebuildAfter;
    if (sound.rebuildPending || long) {
      unawaited(
        sound.rebuildVoices(
          'foreground after ${away?.inSeconds ?? -1}s'
          '${sound.rebuildPending ? ' (deferred reset)' : ''}',
        ),
      );
    }
    if (_adsShowing == 0) sound.clearSuspend();
    if (!sound.background) return;
    if (_adsShowing > 0 || _adJustEnded) {
      sound.setBackground(false);
      _startMusicIfDropped();
      return;
    }
    musicGuard.confirmOwnMusic(
      'foreground',
      delay: Config.musicForegroundCheckDelay,
      then: () {
        sound.setBackground(false);
        _startMusicIfDropped();
      },
    );
  }

  /// Audit A3-3: a background during the launch check dropped that check
  /// and the music start with it; the return starts the music instead
  /// (a no-op once the music was started).
  void _startMusicIfDropped() {
    if (!sound.musicWanted) unawaited(sound.startMusic());
  }

  /// §28.2 / §28.3 at a scene change (Home arrival, run start): a stale
  /// suspend is cleared, and skipped game music comes back when the
  /// player's own music has stopped (never mid-run).
  void _audioSceneChange() {
    if (!_soundReady) return;
    if (_adsShowing == 0) sound.clearSuspend();
    if (!sound.ownMusicSkipped || _adJustEnded) return;
    // A moment later, so the scene's own click / flap has rung out (the
    // Android check also counts the game's SFX on the music stream).
    _after(Config.ownMusicRecheckDelay, () {
      unawaited(() async {
        final other = await _otherMusicNow();
        if (!other) sound.setOtherMusicActive(false, sceneChange: true);
      }());
    });
  }

  /// §28.2 a full-screen ad is displayed: everything suspended until
  /// [_adAudioEnd].
  bool _adAudioBegin(bool suspended) {
    if (!_soundReady) return false;
    if (!suspended) sound.suspend();
    return true;
  }

  void _adAudioEnd(bool suspended) {
    _lastAdEndedAt = storage.now();
    if (suspended && _soundReady) sound.resume();
  }
  // endregion PRD-2.2 §28

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
    var suspended = false;
    try {
      final result = await _showRewardedAd(
        placement,
        onDisplayed: () => suspended = _adAudioBegin(suspended),
      );
      // PRD-2.2 §7.6 guards 3 / 4: a displayed rewarded ad (completed or
      // closed early) counts for "rewarded this run" and the 60 s gap.
      if (result == AdResult.completed || result == AdResult.dismissed) {
        _lastFullScreenAdClosedAt = storage.now();
        if (state != GameState.start) _rewardedWatchedThisRun = true;
      }
      // PRD-menu-v4 §8: completed rewarded videos feed the upsell trigger.
      if (result == AdResult.completed && isLoaded) {
        unawaited(menu.noAdsPopup.recordRewardedVideo());
      }
      return result;
    } finally {
      _adsShowing--;
      _adAudioEnd(suspended);
    }
  }

  Future<AdResult> _showRewardedAd(
    AdPlacement placement, {
    required void Function() onDisplayed,
  }) async {
    final ads = monetization.ads;
    // Exactly one impression per displayed ad, logged at display time.
    var shownLogged = false;
    void logShown() {
      if (shownLogged) return;
      shownLogged = true;
      services.track('ad_rewarded_shown', {
        'placement': placement.analyticsName,
      });
      // PRD-2.2 §28.2: game audio suspended while the ad is up.
      onDisplayed();
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
    onDisplayed(); // §28.2 the fake overlay suspends on mount too
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

  // region PRD-2.2 §7.4–§7.6 — gameplay banner, resize per scene, interstitial

  final List<PlayfieldResizable> _resizables = [];

  /// §7.5.2: persistent components that cache `viewHeight`-derived layout
  /// register here (like [registerTintable]); [setPlayfieldHeight] calls
  /// their [PlayfieldResizable.onPlayfieldResize].
  void registerResizable(PlayfieldResizable resizable) {
    if (!_resizables.contains(resizable)) _resizables.add(resizable);
  }

  void unregisterResizable(PlayfieldResizable resizable) =>
      _resizables.remove(resizable);

  /// The registered [PlayfieldResizable]s (tests).
  List<PlayfieldResizable> get resizables => List.unmodifiable(_resizables);

  /// §7.5.2: the ONE entry point that changes the playfield. [visible] is the
  /// height the game view shows (the camera's resolution); [stripDrop] the
  /// part of the bottom spike strip that lies under the view's bottom edge
  /// (§7.5.4). `viewHeight` becomes `visible + stripDrop`. Called only at
  /// START (run with a banner) and on the Home arrival.
  void setPlayfieldHeight(double visible, {double stripDrop = 0}) {
    final layout = visible + stripDrop;
    final changed = layout != _viewHeight || stripDrop != _stripDrop;
    _viewHeight = layout;
    _stripDrop = stripDrop;
    final viewport = camera.viewport;
    if (viewport is PlayfieldViewport) {
      viewport.setResolution(viewWidth, visible);
    }
    if (!changed) return;
    for (final r in List.of(_resizables)) {
      r.onPlayfieldResize(layout);
    }
  }

  final ValueNotifier<BannerState> _bannerState = ValueNotifier(
    BannerState.off,
  );

  /// §7.10: what the app shell's banner slot shows (off / reserved / ad).
  ValueListenable<BannerState> get bannerState => _bannerState;

  final ValueNotifier<Color> _bannerStripColor = ValueNotifier(
    kPalettes[0]!.foreground,
  );

  /// §7.5.4: the empty strip's grey = the spike strips' colour (the stage
  /// foreground, darkened by the revive dim: #828282 → #313131).
  ValueListenable<Color> get bannerStripColor => _bannerStripColor;

  bool _runBanner = false;
  bool _bannerImpressionLogged = false;

  /// Whether the current run reserved a banner strip (read once at START).
  bool get runHasBanner => _runBanner;

  /// The banner strip's height in points on this device (null = no size).
  double? get bannerStripHeight {
    final b = monetization.banner;
    final dp = b.heightDp;
    if (dp == null || dp <= 0 || b.widthDp <= 0) return null;
    // WP-TAB: points per dp from the screen's full width in game points.
    return dp * _screenWidthPoints / b.widthDp;
  }

  /// §7.5.6: the banner is off for NO ADS owners, without consent, on Test
  /// Lab devices / iOS / Linux without the fake, and in E2E builds unless a
  /// test asks for it ([E2EHooks.banner]).
  bool get bannerWanted {
    if (menu.noAds) return false;
    if (kE2E && !E2EHooks.banner) return false;
    if (kSoakNoBanner) return false; // S7-19 soak diagnosis only
    if (!monetization.banner.canShow) return false;
    return bannerStripHeight != null;
  }

  /// §7.5.1: preload the banner on Home (invisible) when one may be used.
  void _preloadBanner() {
    if (state == GameState.start && !_runBanner && bannerWanted) {
      monetization.banner.preload();
    }
  }

  /// §7.5.2 shrink at START (before the VS intro and the run scene): the
  /// flag is read once here, so a NO ADS purchase applies from the next run.
  void _reserveRunBanner() {
    if (_runBanner || !bannerWanted) return;
    _runBanner = true;
    _bannerImpressionLogged = false;
    final visible = clampRunViewHeight(screenHeight - bannerStripHeight!);
    setPlayfieldHeight(visible, stripDrop: Config.bannerStripDrop);
    _syncBannerStripColor();
    _bannerState.value = BannerState.reservedEmpty;
    monetization.banner.onImpression = _onBannerImpression;
    // Home normally preloaded it already; no-op then.
    monetization.banner.preload();
  }

  /// §7.4: the first frame of `playing` starts the interstitial loading. The
  /// banner is already up since the waiting screen (PRD-2.3.1 §11).
  void _onFirstFlight() {
    _rewardedWatchedThisRun = false;
    _ratingRequestedThisRun = false;
    // PRD-2.3 §18.2/§18.5: nothing loads during the new-player grace, by the
    // same predicate as the show (finished runs only; the run just started
    // is not finished). A grace that ends during or at the end of this run
    // loads at run end ([_preloadInterstitialAfterGrace]).
    _interstitialPreloadedThisRun = false;
    _preloadInterstitialAfterGrace();
  }

  /// PRD-2.3 §18.5 (S8-10): whether this run already asked for the
  /// interstitial.
  bool _interstitialPreloadedThisRun = false;

  /// PRD-2.3 §18.2/§18.5: loads the interstitial once per run when the
  /// new-player grace (finished runs, playtime) no longer covers it.
  void _preloadInterstitialAfterGrace() {
    if (_interstitialPreloadedThisRun || menu.noAds) return;
    if (AdGrace.active(
      runs: storage.gamesPlayed,
      playtimeSeconds: storage.playtimeSeconds,
    )) {
      return;
    }
    _interstitialPreloadedThisRun = true;
    monetization.interstitial.preload();
  }

  /// §7.5.2 grow on the Home arrival: full height, no strip; the used
  /// banner is dropped and the next one loads on Home.
  void _releaseRunBanner() {
    final had = _runBanner;
    _runBanner = false;
    _bannerState.value = BannerState.off;
    final full = _clampViewHeight(screenHeight);
    if (_viewHeight != full || _stripDrop != 0) setPlayfieldHeight(full);
    if (had) {
      // After the slot has unmounted the ad widget.
      _after(0.1, () {
        monetization.banner.dispose();
        _preloadBanner();
      });
    }
  }

  void _onBannerImpression() {
    if (_bannerImpressionLogged || !_runBanner) return;
    _bannerImpressionLogged = true;
    services.track('ad_banner_shown');
  }

  void _syncBannerStripColor() {
    // PRD-2.2 §31: the empty strip under a balloon bonus or results page is
    // the page's grey, whatever stage the run ended on.
    var c = _postRunPage ? kPostRunPalette.foreground : _fgColor;
    for (final dim in world.children.whereType<ReviveDim>()) {
      if (dim.alpha > 0) {
        c = Color.lerp(c, ReviveConfig.dimColor, dim.alpha.clamp(0.0, 1.0))!;
      }
    }
    if (_bannerStripColor.value != c) _bannerStripColor.value = c;
  }

  bool _interstitialBusy = false;
  bool _rewardedWatchedThisRun = false;
  DateTime? _lastFullScreenAdClosedAt;
  bool _inBackground = false;

  /// §7.6 guard 3: a rewarded ad was displayed in this run.
  bool get rewardedWatchedThisRun => _rewardedWatchedThisRun;

  /// §7.6 guard 4: when the last full-screen ad closed (this app session).
  DateTime? get lastFullScreenAdClosedAt => _lastFullScreenAdClosedAt;

  /// True while the interstitial between NEXT and Home is up.
  bool get interstitialShowing => _interstitialBusy;

  /// §7.6: why NEXT goes straight Home, or null when the video ad plays.
  InterstitialSkip? interstitialSkipReason() {
    if (menu.noAds) return InterstitialSkip.noAds;
    // PRD-2.3 §18.2: the new-player grace (5 runs or 5 min) replaces the
    // PRD-2.2 "first 3 runs" rule.
    if (AdGrace.active(
      runs: storage.gamesPlayed,
      playtimeSeconds: storage.playtimeSeconds,
    )) {
      return InterstitialSkip.newPlayer;
    }
    // PRD-2.3 §23.2 / §0 item 1: a run that asked for the rating sheet
    // has no interstitial (NEXT goes straight Home).
    if (_ratingRequestedThisRun) return InterstitialSkip.rating;
    if (_rewardedWatchedThisRun) return InterstitialSkip.rewardedThisRun;
    final last = _lastFullScreenAdClosedAt;
    if (last != null &&
        storage.now().difference(last) < Config.interstitialMinGap) {
      return InterstitialSkip.cooldown;
    }
    if (!monetization.interstitial.isAvailable) {
      return InterstitialSkip.notLoaded;
    }
    if (_inBackground) return InterstitialSkip.background;
    return null;
  }

  /// §7.6: plays the interstitial like a rewarded ad (`_adsShowing`: input
  /// blocked, motion / popups held), then the Home arrival.
  Future<void> _showInterstitialThenHome() async {
    _interstitialBusy = true;
    _adsShowing++;
    var shown = false;
    var suspended = false;
    void suspendAudio() => suspended = _adAudioBegin(suspended); // §28.2
    void onShown() {
      if (shown) return;
      shown = true;
      suspendAudio();
      services.track('ad_interstitial_shown');
      // PRD-2.3 §18.4: the first interstitial ever, once.
      if (!storage.firstInterstitialShown) {
        services.track('first_interstitial', {
          'runs': storage.gamesPlayed,
          'playtime_s': storage.playtimeSeconds,
        });
        unawaited(storage.saveFirstInterstitialShown());
      }
      // §7.6: a displayed video ad feeds the NO ADS upsell trigger.
      if (isLoaded) unawaited(menu.noAdsPopup.recordRewardedVideo());
    }

    try {
      final ads = monetization.interstitial;
      final AdResult result;
      if (monetization.showFakeAdOverlay &&
          ads is FakeInterstitialAds &&
          _fakeAd == null) {
        result = await _showFakeInterstitial(ads, onShown, suspendAudio);
      } else {
        result = await ads.show(onShown: onShown);
      }
      if (shown || result == AdResult.completed) {
        _lastFullScreenAdClosedAt = storage.now();
      }
    } catch (e) {
      debugPrint('interstitial failed: ${redactSecrets(e)}');
    } finally {
      _adsShowing--;
      _interstitialBusy = false;
      _adAudioEnd(suspended);
    }
    _arriveHome();
  }

  /// The Linux / desktop stand-in: "TEST AD" for
  /// [Config.fakeInterstitialSeconds].
  Future<AdResult> _showFakeInterstitial(
    FakeInterstitialAds ads,
    void Function() onShown,
    void Function() onMounted,
  ) async {
    final scripted = await ads.show();
    if (scripted == AdResult.unavailable) return scripted;
    final overlay = FakeAdOverlay(
      interstitial: true,
      fails: scripted != AdResult.completed,
    );
    _fakeAd = overlay;
    world.add(overlay);
    fadeOpacity(overlay, from: 0, to: 1, duration: Config.popupFadeDuration);
    pushBack(_fakeAdBack);
    // §28.2: the fake overlay suspends on mount (also its fail variant).
    onMounted();
    if (scripted == AdResult.completed) onShown();
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
    return result;
  }
  // endregion PRD-2.2 §7.4–§7.6

  /// Invite tile: the share sheet with a card and a text (PRD-2.3 §2.2; no
  /// reward, PRD-1 §3.4).
  void invite() {
    if (!_homeInteractive) return;
    sound.play(Sfx.skTap);
    services.track('invite_tap');
    final share = onInvite;
    if (share == null) {
      showToast('Coming soon');
    } else {
      unawaited(_invite(share));
    }
  }

  Future<void> _invite(FutureOr<void> Function(ShareCardData) share) async {
    if (_sharing) return;
    _sharing = true;
    try {
      final data = shareContent.invite(
        best: storage.bestScore,
        lastScore: storage.lastScore,
        level: menu.levels.level,
        look: menu.items.look,
        name: await shareName(),
      );
      services.track('invite', {
        'card': data.kind.analytics,
        ...data.analytics,
      });
      await share(data);
    } catch (e) {
      debugPrint('invite failed: ${redactSecrets(e)}');
    } finally {
      _sharing = false;
    }
  }

  /// True while a share or invite is being prepared (a second tap waits).
  bool _sharing = false;

  /// PRD-2.3 §2.2 the username on the card: the custom name (WP-NAME),
  /// else the versus nickname (WP-AV:
  /// never a platform name), created first when there is none ('' only when that
  /// fails: the card then has no name tag).
  Future<String> shareName() async {
    // WP-NAME others see the custom name when the player chose one.
    final custom = validCustomName(storage.versusCustomName);
    if (custom.isNotEmpty) return custom;
    try {
      final n = versus.me.name.trim();
      if (n.isNotEmpty) return n;
    } catch (_) {}
    try {
      final nick = await storage.ensureVersusNickname(
        () => generateNickname(Random()),
      );
      try {
        final n = versus.me.name.trim();
        if (n.isNotEmpty) return n;
      } catch (_) {}
      return nick.trim();
    } catch (_) {
      return '';
    }
  }

  // --- back stack & keyboard -------------------------------------------------

  /// Registers a back handler (topmost wins). Pair with [popBack].
  void pushBack(bool Function() handler) {
    _backHandlers.add(handler);
    _syncSystemBackWanted();
  }

  /// Removes [handler] wherever it is in the stack.
  void popBack(bool Function() handler) {
    _backHandlers.remove(handler);
    _syncSystemBackWanted();
  }

  /// S7-20: true while a system back would close something (a menu screen
  /// or popup over Home): the same gate as [handleSystemBack].
  bool get systemBackWanted =>
      state == GameState.start &&
      !_runStarting &&
      _fakeAd == null &&
      _backHandlers.isNotEmpty;

  /// S7-20: called with [systemBackWanted] whenever it changes. main.dart
  /// shows the (gesture) navigation bar while it is true: in sticky
  /// immersive mode Android spends the first edge swipe on revealing the
  /// hidden bars, so a single back swipe could not close a menu.
  void Function(bool wanted)? onSystemBackWanted;
  bool _systemBackWantedSent = false;

  void _syncSystemBackWanted() {
    final wanted = systemBackWanted;
    if (wanted == _systemBackWantedSent) return;
    _systemBackWantedSent = wanted;
    onSystemBackWanted?.call(wanted);
  }

  /// Back (Esc): runs the topmost handler. False when nothing handled it.
  bool handleBack() => _backHandlers.isNotEmpty && _backHandlers.last.call();

  /// PRD-2.2 §8: the Android system back (the edge swipe in gesture
  /// navigation, or the 3-button back). It closes the menu screens and popups
  /// exactly as their back arrow / ✕ does ([handleBack], topmost first). In a
  /// run (every state but start, the post-run pages included), while a run is
  /// starting and while a video ad is up it does nothing. One close per
  /// gesture: while a close is still fading out, further backs are ignored.
  /// Returns true when something closed. The app never leaves on back: the
  /// observer in main.dart always reports the back as handled.
  bool handleSystemBack() {
    wakeFrames();
    if (state != GameState.start || _runStarting || _fakeAd != null) {
      return false;
    }
    if (_systemBackLock > 0 || _backHandlers.isEmpty) {
      return false;
    }
    final screen = _backScreenName(_backHandlers.last);
    if (!handleBack()) {
      return false;
    }
    _systemBackLock = Config.systemBackDebounce;
    services.track('back_gesture', {'screen': screen});
    return true;
  }

  /// The `back_gesture` analytics name of a back handler.
  String _backScreenName(bool Function() handler) {
    if (handler == _settingsBack) return 'settings';
    if (handler == _shopBack) return 'shop';
    if (handler == _skinsBack) return 'skins';
    if (handler == _levelsBack) return 'levels';
    if (handler == _debugBack) return 'debug';
    return 'popup';
  }

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
    wakeFrames();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (state == GameState.results) {
        // The results page's NEXT, once it has faded in (WP-2e).
        _results?.next();
      } else {
        onScreenTap();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      // WP-2d: Esc while playing pauses (ARCH §2.3).
      if (state == GameState.playing) {
        pause();
        return KeyEventResult.handled;
      }
      if (state == GameState.results) {
        // Back from a finished run is the results page's NEXT: a fresh home
        // arrival (PRD-1 §3.6), once the page accepts input (WP-2e).
        final results = _results;
        if (results != null && results.canContinue) {
          results.next();
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

  /// A mistake through the run's pipeline (ARCH §2.6) from outside the
  /// run's own physics (tests, debug): a death plays the §3.0.5 tumble and
  /// the run then ends via [endRun].
  void onBirdHit([MistakeCause cause = MistakeCause.missedHoop]) {
    if (state != GameState.playing) {
      return;
    }
    final run = _run;
    if (run != null && run.started && !run.ended) {
      if (debugAvailable && runDebug.god) return;
      run.mistake(Mistake(cause));
      return;
    }
    endRun(null);
  }

  // region P26-E1
  /// Shared eligibility gate for versus and the WP-LB board submit.
  bool get _countsForUpload => _run?.countsForUpload ?? false;
  // endregion

  /// The end of a run (ARCH §2.3): persistence, `noAdsPopup.recordRun`,
  /// game-over / new-best analytics, the leaderboard submit, the versus
  /// upload, then the [PostRunFlow] (ending on the WP-2e results page).
  void endRun(RunSummary? summary) {
    if (state != GameState.playing &&
        state != GameState.dying &&
        state != GameState.reviving) {
      return;
    }
    if (state == GameState.playing) {
      // No tumble ran (a run-less end): the 1.0 game over.
      sound.play(Sfx.gameover);
      _bird?.die();
    }
    state = GameState.results;
    // §3.0.5 the dead bird stays lying on the floor spikes until the results
    // page covers it. Coins were credited per pass (§3.2).

    final previousBest = storage.bestScore;
    final previousLevel = menu.levels.level;
    // region P23-14 — PRD-2.3 §14.2 the run that showed a feather / piece
    // (never in two runs in a row), recorded before gamesPlayed counts it.
    final shown = _run?.state;
    if (shown != null && shown.featherSpawned) {
      unawaited(storage.saveLastFeatherRun(storage.gamesPlayed));
    }
    if (shown != null && shown.pieceSpawned) {
      unawaited(storage.saveLastPieceRun(storage.gamesPlayed));
    }
    // endregion P23-14
    storage.incrementGamesPlayed();
    // region P26-B2
    showcaseProgress.onRunEnd(
      gamesPlayed: storage.gamesPlayed,
      hoopsPassed: summary?.hoopsPassed ?? _run?.state.hoopsPassed ?? 0,
      score: summary?.score ?? score,
      cause: (summary?.cause ?? MistakeCause.missedHoop).analyticsName,
      shieldUsed: summary?.shieldUsed ?? _run?.state.shieldUsed ?? false,
      reviveUsed: (summary?.revives ?? _run?.state.revivesThisGame ?? 0) > 0,
    );
    // endregion
    switch (storage.gamesPlayed) {
      case 1:
        ftueTracker.step(FtueStep.run1End, gamesPlayed: storage.gamesPlayed);
      case 2:
        ftueTracker.step(FtueStep.run2End, gamesPlayed: storage.gamesPlayed);
      case 3:
        ftueTracker.step(FtueStep.run3End, gamesPlayed: storage.gamesPlayed);
      case 20:
        ftueTracker.step(FtueStep.run20End, gamesPlayed: storage.gamesPlayed);
    }
    // region WP-L — owner 2026-10-17: the stored level steps up by exactly
    // one when this run's score reaches the next threshold (the cache is
    // updated at once; the write follows).
    unawaited(menu.levels.recordRun(score));
    _resultsLevels = (previousLevel, menu.levels.level);
    // endregion WP-L
    // region P231-E — PRD-2.3.1 §12.2 ranks (WP-L: they follow the stored
    // level) and the daily streak, for a counting run only
    final achRun = _run;
    final counts = achRun != null && achRun.countsForAchievements;
    // P1E-03: the run's staged unlocks commit only if it still counts;
    // PRD-2.3.1 §19.2 a counting run then unlocks at most one (the oldest
    // pending), after its ranks and daily streak are earned.
    achievements.finishRun(
      counts: counts,
      level: menu.levels.level,
      day: storage.today,
    );
    // endregion P231-E
    // PRD-2.3 §18.3 (S8-09): the run's playtime is saved at run end; §18.5
    // (S8-10): a grace that ended with this finished run loads now.
    unawaited(playtime.flush());
    _preloadInterstitialAfterGrace();
    unawaited(storage.saveLastScore(score));
    // region P26-K
    _run?.saveBestRunHoops(score, previousBest);
    // endregion
    if (score > storage.bestScore) {
      storage.saveBestScore(score);
    }
    // region PRD-2.3 §23.2 — the results page's rating trigger (run 5, or a
    // new best after it); the request itself waits for the settled page.
    _ratingTrigger = RatingRules.trigger(
      runs: storage.gamesPlayed,
      newBest: score > previousBest,
      minRuns: Config.ratingMinRunsFor(storage.showcaseDoneAt),
    );
    _ratingSettle = 0;
    // endregion PRD-2.3 §23.2
    // region WP-2e — results page (PRD-2 §3.14, §7)
    // A new level's reward is owed from now on: kept until CLAIM / NEXT so
    // an app kill never loses it (credited at the next app start).
    final owed = menu.levels.pendingLevelUp;
    if (owed != null && menu.levels.level > previousLevel) {
      unawaited(storage.saveUnclaimedLevelReward(owed.reward));
    }
    // endregion WP-2e
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
    // region P26-LB2
    unawaited(
      leaderboardSubmit.onRunEnd(
        summary,
        countsForAchievements: counts,
        countsForUpload: _countsForUpload,
        mode: homeMode == HomeMode.freeFly ? 'free' : 'versus',
        look: menu.items.look,
      ),
    );
    // endregion
    // region P26-E1
    if (summary != null && _countsForUpload) {
      unawaited(versus.submitRun(summary, menu.items.look));
    }
    // endregion

    final s =
        summary ??
        _run?.endRun() ??
        // A run-less end (tests): the bare score.
        RunSummary(
          score: score,
          hoopsPassed: 0,
          coins: 0,
          bestBefore: previousBest,
          bestAfter: max(score, previousBest),
          runSeconds: 0,
          cause: MistakeCause.missedHoop,
          hoopIndex: 0,
          timeline: RunTimeline.empty(),
        );
    // region P26-E2
    unawaited(recordDuelRun(storage, s, counts: _countsForUpload));
    // endregion
    unawaited(PostRunFlow(this).run(s));
    fadeOpacity(_hud, from: 1, to: 0, duration: Config.gameplayFadeDuration);
  }

  // region WP-2e — results page (PRD-2 §3.14, §5.10)

  /// PRD-2.2 §31: a balloon bonus or results page is up (from its start to
  /// the next run's start). While it is, the run's strips draw their normal
  /// reach in the page grey and the banner strip takes it too.
  bool _postRunPage = false;
  bool get postRunPageUp => _postRunPage;

  /// A2-5: the priority below which the run world is not drawn, while the
  /// results page is opaque and covers the whole view (the page's background
  /// is drawn over whatever is under it). Null when the world could show
  /// through: the page fades in or out, is not mounted yet, is smaller than
  /// the view, or a run shake has moved the view (and the page with it).
  int? _worldCoveredBelow() {
    final page = _results;
    if (page == null || !page.isMounted || page.isRemoved) return null;
    if (page.opacity < 1 || !page.position.isZero()) return null;
    if (page.size.x < Config.worldWidth || page.size.y < viewHeight) {
      return null;
    }
    final vf = camera.viewfinder;
    if (!cameraShake.isZero() || vf.zoom != 1) return null;
    return page.priority;
  }

  void _setPostRunPage(bool on) {
    _postRunPage = on;
    _ground.onPage = on;
    _ceiling.onPage = on;
    _syncBannerStripColor();
  }

  /// WP-L the stored level before / after the last ended run (the results
  /// page's level stage); null before the first run end.
  (int, int)? _resultsLevels;

  /// The results page while it is up (tests, keyboard).
  ResultsScreen? get resultsScreen => _results;

  /// Puts up the results page for [s] (PRD-2 §5.10; replaces the 1.0
  /// game-over panel). The strips are lifted above it, as over the menu
  /// screens.
  void showResults(RunSummary s) {
    if (_results != null || state != GameState.results) return;
    final page = ResultsScreen(
      summary: s,
      model: ResultsModel.of(
        s,
        pending: menu.levels.pendingLevelUp,
        levelBefore: _resultsLevels?.$1,
        levelAfter: _resultsLevels?.$2,
      ),
    );
    _results = page;
    world.add(page);
    _setPostRunPage(true);
    _ground.priority = groundOverMenusPriority;
    _ceiling.priority = groundOverMenusPriority;
  }

  void _removeResults() {
    // iOS round 2 §6 (both platforms): a player who taps through the page
    // before it settled no longer loses the unshown toasts: the pill on
    // screen keeps going and the rest follow on Home
    // ([_checkAchievementToasts]).
    final page = _results;
    _results = null;
    page?.removeFromParent();
    _ceiling.priority = SpikeStrip.basePriority;
    _syncGroundPriority();
    _setPostRunPage(false);
  }

  /// §3.14 / §7: a level reward still owed when the app was closed on the
  /// results page is credited at the next start, without animation.
  Future<void> _creditUnclaimedLevelReward() async {
    // Either a pending reward (the ran-end flag) or the record of a claim
    // a kill interrupted mid-way (S6-22); both are settled here.
    if (storage.unclaimedLevelReward <= 0 && storage.levelRewardPayout <= 0) {
      return;
    }
    await claimLevelRewards(this, 'app_start');
  }
  // endregion WP-2e

  // region WP-4a — balloon bonus (PRD-2 §3.15, §5.14)
  BonusScreen? _bonus;

  /// The balloon bonus screen while it is up (tests).
  BonusScreen? get bonusScreen => _bonus;

  /// §3.15 the bonus screen between the revive offer and the results
  /// (`PostRunFlow`): state [GameState.bonus], the feathers go back to 0
  /// as it opens (`bonus_shown`), the strips are lifted over it as over the
  /// results page. Completes on NO THANKS / NEXT (state back to
  /// [GameState.results], the results page then comes up over it; the
  /// screen removes itself a moment later).
  Future<void> showBonus(RunSummary s) async {
    if (_bonus != null || state != GameState.results) return;
    state = GameState.bonus;
    unawaited(storage.saveFeathers(0));
    services.track('bonus_shown');
    final rng = _run?.director.rng.timing ?? Random();
    final screen = BonusScreen(
      summary: s,
      prizes: BonusRules.shuffledPrizes(rng),
      seed: rng.nextInt(1 << 30),
    );
    _bonus = screen;
    world.add(screen);
    _setPostRunPage(true);
    _ground.priority = groundOverMenusPriority;
    _ceiling.priority = groundOverMenusPriority;
    await screen.finished;
    if (!identical(_bonus, screen)) return;
    _bonus = null;
    if (state == GameState.bonus) state = GameState.results;
  }

  void _removeBonus() {
    final screen = _bonus;
    _bonus = null;
    if (_results == null) _setPostRunPage(false);
    if (screen == null) return;
    screen.removeFromParent();
    _ceiling.priority = SpikeStrip.basePriority;
    _syncGroundPriority();
  }
  // endregion WP-4a

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
      onDeleteMyData: openDeleteDataConfirm,
      onPrivacyOptions: privacyOptionsShown ? openPrivacyOptions : null,
      onSupport: openSupport,
      onRedeemCode: redeemCodeAvailable ? openRedeemCode : null,
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
    if (_runSettingsOpen) {
      closeRunSettings();
      return;
    }
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

  // region WP-4c — Delete my data (PRD-2 §3.13 / Q22)

  /// §3.13 Settings row: the confirm dialog (never two popups at once).
  void openDeleteDataConfirm() {
    if (_deleteDataPopup != null ||
        modalPopupOpen ||
        _debugPanel != null ||
        _fakeAd != null ||
        (state != GameState.start && state != GameState.paused)) {
      return;
    }
    sound.play(Sfx.skDialog);
    final popup = DeleteDataPopup(
      step: DeleteDataStep.confirm,
      onConfirm: confirmDeleteMyData,
      onDismiss: closeDeleteDataPopup,
    );
    _deleteDataPopup = popup;
    world.add(popup);
    fadeOpacity(popup, from: 0, to: 1, duration: Config.popupFadeDuration);
    pushBack(_deleteDataBack);
  }

  /// The confirm face's DELETE: runs [VersusService.deleteMyData] (which
  /// deletes the online data and does the local reset; never throws) and
  /// swaps to the PRD's result text — done, or the offline / failure text
  /// with nothing touched.
  Future<void> confirmDeleteMyData() async {
    final popup = _deleteDataPopup;
    if (popup == null || popup.step != DeleteDataStep.confirm || popup.busy) {
      return;
    }
    popup.setBusy(true);
    var ok = false;
    try {
      ok = await versus.deleteMyData();
    } catch (_) {
      ok = false;
    }
    if (ok) {
      // region P26-LB2
      await leaderboardQueue.resetLocal();
      // endregion
      // PRD-2.2 §9.1: the stored music volume is cleared and the music goes
      // back to its default, live; the Settings slider follows.
      await storage.resetMusicVolume();
      unawaited(sound.setMusicVolume(storage.musicVolume));
      // PRD-2.2 §2.2: the mode goes back to VERSUS.
      await storage.resetHomeMode();
      // Owner 2026-10-17 (WP-L): the stored level goes back to unranked
      // (the claimed rewards stay claimed: a level reached again never
      // pays twice).
      await menu.levels.reset();
      _home?.syncMode(animate: false);
      _settingsPanel?.setMusicVolume(sound.musicVolume);
    }
    if (_deleteDataPopup != popup) return;
    _deleteDataPopup = null;
    popBack(_deleteDataBack);
    popup.active = false;
    fadeOpacity(
      popup,
      from: popup.opacity,
      to: 0,
      duration: Config.popupFadeDuration,
      removeOnDone: true,
    );
    sound.play(ok ? Sfx.skProgress : Sfx.skNoCoins);
    // The result face, over the same screen (settings stays up).
    final result = DeleteDataPopup(
      step: ok ? DeleteDataStep.done : DeleteDataStep.failed,
      onConfirm: () {},
      onDismiss: closeDeleteDataPopup,
    );
    _deleteDataPopup = result;
    world.add(result);
    fadeOpacity(result, from: 0, to: 1, duration: Config.popupFadeDuration);
    pushBack(_deleteDataBack);
  }

  /// OK / ✕ / dim / Esc: `sk_close` and a short fade.
  void closeDeleteDataPopup() {
    final popup = _deleteDataPopup;
    if (popup == null) return;
    _deleteDataPopup = null;
    popBack(_deleteDataBack);
    popup.active = false;
    sound.play(Sfx.skClose);
    fadeOpacity(
      popup,
      from: popup.opacity,
      to: 0,
      duration: Config.popupFadeDuration,
      removeOnDone: true,
    );
    _drainPopups();
  }

  bool _deleteDataBack() {
    closeDeleteDataPopup();
    return true;
  }
  // endregion WP-4c

  /// The results page's NEXT: back to the home screen as a NEW arrival —
  /// the powerup slot re-rolls (PRD-1 §3.6).
  void goHome() {
    if (state != GameState.results || _interstitialBusy) {
      return;
    }
    // region PRD-2.2 §7.6 — the video ad between NEXT and Home
    final skip = interstitialSkipReason();
    if (skip == null) {
      unawaited(_showInterstitialThenHome());
      return;
    }
    services.track('ad_interstitial_skipped', {'reason': skip.analyticsName});
    // endregion PRD-2.2 §7.6
    _arriveHome();
  }

  /// The Home arrival after a run (after the interstitial, or at once).
  void _arriveHome() {
    if (state != GameState.results) return;
    menu.slot.rollForArrival();
    replay();
    _logSlotShown();
    // PRD-2.3 §18.3: the run's playtime is saved when the Home arrives (the
    // results page does no I/O of its own).
    unawaited(playtime.flush());
    // PRD-2.3 §24.2: the No-Ads popup is checked on every Home arrival after
    // a run (after the interstitial, which is over by now). The check waits
    // for the arrival's storage reload, so a reload that lands late can never
    // revert a show that was recorded in the meantime. The budget starts
    // after that reload, so its candidates see the run's saved mood.
    final reload = _homeReload;
    if (reload == null) {
      _beginHomeVisit();
      _offerNoAdsAfterRun();
    } else {
      unawaited(
        reload.catchError((Object _) {}).then((_) {
          _beginHomeVisit();
          _offerNoAdsAfterRun();
        }),
      );
    }
  }

  /// Full scene reset with a 0.3 s white fade, ending on the home screen at
  /// colour stage 0. [goHome] wraps it with the new-arrival bookkeeping.
  void replay() {
    sound.play(Sfx.click);

    // region WP-2d — drop the pause screen / in-run menu overlays
    _clearRunOverlays();
    // endregion WP-2d

    // Full scene reset.
    _bird?.removeFromParent();
    _bird = null;
    _birdAdapter = null;
    _run?.disposeRun();
    _run = null;
    // PRD-2.2 §33.6 (S7-19): the run's own sound pools go with it.
    sound.endRun();
    _debugBot = null;
    (world as RunScaledWorld).timeScaleSource = null;
    _removeResults();
    _ratingTrigger = null; // PRD-2.3 §23.2: a request needs the results page
    _ratingSettle = 0;
    // region WP-4a — drop a bonus screen still up
    _removeBonus();
    // endregion WP-4a
    final oldHome = _home;
    _home = null;
    if (oldHome != null) {
      unregisterTintable(oldHome);
      _chromeHosts.remove(oldHome);
      oldHome.removeFromParent();
    }
    score = 0;
    _stage = 0;
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
    _homeReload = storage.load().then((_) {
      sound.muted = storage.muteSound;
    });

    // PRD-2.2 §7.5.2: the playfield grows back inside the Home arrival,
    // before the menus are rebuilt at full height.
    _releaseRunBanner();

    _setupStartScene();

    // 0.3 s white fade.
    final overlay = RectangleComponent(
      position: Vector2(-extraWidth, 0), // WP-TAB: full width
      size: Vector2(Config.worldWidth + 2 * extraWidth, viewHeight),
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

  /// PRD-2.3 §2.0 the results-page share button: the Spotlight card of this
  /// run (the sharer's own score and best, never an opponent's).
  void shareScore() {
    sound.play(Sfx.click);
    unawaited(_shareScore(score));
  }

  Future<void> _shareScore(int points) async {
    if (_sharing) return;
    _sharing = true;
    try {
      final data = shareContent.spotlight(
        score: points,
        best: storage.bestScore,
        level: menu.levels.level,
        look: menu.items.look,
        name: await shareName(),
      );
      services.logShareScore(points, data.analytics);
      await onShareScore?.call(data);
    } catch (e) {
      debugPrint('share failed: ${redactSecrets(e)}');
    } finally {
      _sharing = false;
    }
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
        _showServiceMessage(_signInUnavailable);
      case ShowLeaderboardResult.leaderboardFailed:
        _showServiceMessage('Leaderboard unavailable — try again');
      case ShowLeaderboardResult.opened:
      case ShowLeaderboardResult.unavailable:
      case ShowLeaderboardResult.busy:
        break; // nothing to report
    }
  }

  // region P231-E — achievements (PRD-2.3.1 §12.5)
  /// The Home medal button: opens the native achievements list (Play Games
  /// / Game Center), with the leaderboard's failure toasts.
  Future<void> showAchievements({Sfx sfx = Sfx.click}) async {
    if (state == GameState.start && !_homeInteractive) return;
    sound.play(sfx);
    final result = await services.showAchievements();
    services.track('achievements_open', {'result': result.name});
    switch (result) {
      case ShowAchievementsResult.signInFailed:
        _showServiceMessage(_signInUnavailable);
      case ShowAchievementsResult.failed:
        _showServiceMessage('Achievements unavailable — try again');
      case ShowAchievementsResult.opened:
      case ShowAchievementsResult.unavailable:
      case ShowAchievementsResult.busy:
        break;
    }
  }

  /// The sign-in failure message names the platform's service (iOS round
  /// 2: Game Center on iOS).
  String get _signInUnavailable => isIOS()
      ? 'Game Center sign-in unavailable'
      : 'Play Games sign-in unavailable';

  AchievementToast? _achToast;

  /// The unlock toast on screen (tests; null when none).
  AchievementToast? get achievementToast {
    final t = _achToast;
    return t == null || t.isRemoved || t.isRemoving ? null : t;
  }

  /// Starts the queued unlock toasts (one pill at a time; the 5th of more
  /// than 5 reads "+N more"). No-op while one is showing (it continues
  /// with the queue) or when nothing is queued.
  void showAchievementToasts() {
    if (achievementToast != null) return;
    final queue = achievements.toastQueue;
    if (queue.isEmpty) return;
    final toast = AchievementToast(
      queue: queue,
      onDone: () {
        _achToast = null;
      },
    );
    _achToast = toast;
    world.add(toast);
  }

  /// §12.5 the run's unlocks toast on the results page once its sequence
  /// has played out (after the LEVEL UP and its CLAIM, if any).
  void _checkAchievementToasts() {
    if (achievements.toastQueue.isEmpty || _achToast != null) return;
    // iOS round 2 §6: toasts carried over from a results page that was
    // left early show on Home once nothing is over it.
    if (state == GameState.start) {
      if (_homeInteractive) {
        diag(
          'FS-Ach ${achievements.toastQueue.length} carried-over toast(s) '
          'shown on Home',
        );
        showAchievementToasts();
      }
      return;
    }
    final page = _results;
    if (page == null || state != GameState.results) return;
    if (!page.settled || page.leaving) return;
    showAchievementToasts();
  }

  /// Takes the pill off the screen (a new run); the unshown rest of the
  /// queue is kept (iOS round 2 §6).
  void _hideAchievementToast() {
    final t = _achToast;
    _achToast = null;
    t?.removeFromParent();
  }
  // endregion P231-E

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
    final menuScreen = state == GameState.start && menuScene != MenuScene.home;
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

  /// Settings → Privacy policy: opens `Config.privacyPolicyUrl` in the
  /// in-app browser (§20.3; owner 2026-10-19).
  Future<void> openPrivacyPolicy() => _openLink(Config.privacyPolicyUrl);

  // region PRD-2.3 §20 / §22 — Settings links

  /// Opens [uri] outside the game in [mode]: the web pages in the in-app
  /// browser (Chrome Custom Tab / SFSafariViewController), the redeem link
  /// in the Play Store app. Tests replace it to record the links; the
  /// default never throws.
  Future<void> Function(Uri uri, LaunchMode mode) urlOpener = _launchLink;

  static Future<void> _launchLink(Uri uri, LaunchMode mode) async {
    try {
      // Play links (Redeem code) go to the Play Store app itself, never a
      // browser; the browser is only the fallback (no Play Store).
      if (mode == LaunchMode.externalApplication &&
          uri.host == 'play.google.com' &&
          await launchUrl(
            uri,
            mode: LaunchMode.externalNonBrowserApplication,
          )) {
        return;
      }
    } catch (_) {}
    try {
      if (await launchUrl(uri, mode: mode)) return;
    } catch (_) {}
    if (mode == LaunchMode.inAppBrowserView) {
      // No in-app browser here (the Linux desktop target) or it would not
      // open: the link still opens in the external browser.
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        // No usable browser (or plugin unavailable in tests): ignore.
      }
    }
  }

  Future<void> _openLink(
    String url, {
    LaunchMode mode = LaunchMode.inAppBrowserView,
  }) async {
    sound.play(Sfx.click);
    try {
      await urlOpener(Uri.parse(url), mode);
    } catch (_) {}
  }

  /// Settings → Support: `Config.supportUrl` in the in-app browser (§20.3).
  Future<void> openSupport() => _openLink(Config.supportUrl);

  /// Settings → the footer's music credit (the name): `Config.musicCreditUrl`
  /// in the in-app browser (WP-SET, owner 2026-10-19).
  Future<void> openMusicCredit() => _openLink(Config.musicCreditUrl);

  /// Settings → Redeem code exists on Android only: the gift codes are
  /// Google Play promo codes and the gift products are Play-only (PORT-IOS
  /// §2; iOS never queries or shows them).
  bool get redeemCodeAvailable => defaultTargetPlatform != TargetPlatform.iOS;

  /// Settings → Redeem code (PRD-2.3 §22.2): the Play Store's redeem
  /// screen; the gift arrives through the purchase sync on return. Not the
  /// in-app browser: the redeem must run in the Play app for the purchasing
  /// account (owner decision 2026-10-13, see [Config.redeemCodeUrl]).
  Future<void> openRedeemCode() {
    services.track('redeem_code_opened');
    return _openLink(
      Config.redeemCodeUrl,
      mode: LaunchMode.externalApplication,
    );
  }

  /// The Settings footer's version source (PRD-2.3 §20.2; `main.dart`
  /// installs `PluginAppInfo`, tests a fake).
  AppInfo appInfo = const NoAppInfo();

  /// Whether the sound service exists yet (the Settings tiles' click).
  bool get soundReady => _soundReady;

  /// A Restore purchases is waiting for the store (the Settings spinner).
  bool get purchasesRestoring => _purchases?.restoring ?? false;
  // endregion PRD-2.3 §20 / §22

  // --- color stages --------------------------------------------------------

  /// Crossfades the background and foreground to [palette]. The bird keeps
  /// its own colours at every stage (PRD-2.2 §20): no skin blend follows.
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
    _syncBannerStripColor(); // PRD-2.2 §31: the empty strip follows the fade
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
    // §33.4 item 5: the first frame after an idle-frame restart gets the
    // real elapsed time (Flame restarts its loop with dt = 0).
    dt = idleFrames.frameDt(dt);
    // PRD-2.3 §18.3: the playtime counts the real frame time (at most a
    // second, so a long stall adds no more than that), outside full-screen
    // ads and only while resumed; the clamped step below is for the game.
    if (_resumed && !_inBackground && _adsShowing == 0 && !_interstitialBusy) {
      playtime.advance(min(dt, 1.0));
    }
    // One clamped clock for the whole simulation (Config.maxFrameStep):
    // super.update runs the component tree (Forge2D world step, bird,
    // pipes, camera) with this same dt, and everything below uses it too,
    // so a stalled frame slows the game uniformly instead of letting the
    // spawner or fades run ahead of the bodies.
    dt = min(dt, Config.maxFrameStep);
    _clock += dt;
    if (_systemBackLock > 0) _systemBackLock = max(0.0, _systemBackLock - dt);
    _syncSystemBackWanted();
    super.update(dt);
    _purchases?.update(dt);
    _tickLaunchOwnershipWait(dt);
    if (_soundReady) {
      sound.maintain();
      musicGuard.update(dt); // PRD-2.3 §13.4
    }
    _drainPopups();

    if (_colorFadeT < 1) {
      _colorFadeT = (_colorFadeT + dt / Config.colorFadeDuration).clamp(
        0.0,
        1.0,
      );
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
    _updateMenuChrome();
    final levelsIn = _levelsOpenIn;
    if (levelsIn != null) {
      _levelsOpenIn = levelsIn - dt;
      if (_levelsOpenIn! <= 0) openLevels();
    }
    // region P26-G2c
    if (state == GameState.start) _checkStreakLost(dt);
    // endregion
    if (state == GameState.start) _checkLevelUp(dt);
    // region P26-G2b
    _streakSlotPop = math.max(0, _streakSlotPop - dt);
    if (state == GameState.start) _checkStreakReward(dt);
    // endregion
    _checkRatingPrompt(dt);
    _checkDeferredRating();
    _checkAchievementToasts(); // PRD-2.3.1 §12.5
    if (_bannerState.value != BannerState.off) _syncBannerStripColor();

    // region P22-33 — FS_SOAK driver (§33.3)
    soak?.update(dt);
    // endregion P22-33
    // region WP-0b — debug / e2e autopilot
    final bot = _debugBot;
    if (bot != null && state == GameState.playing && bot.shouldFlap()) {
      onScreenTap();
    }
    // endregion WP-0b
    // region P22-33c — idle menus draw fewer frames (§33.4 item 5)
    if (idleFrames.enabled) {
      _idleQuiet = _menuIdle ? _idleQuiet + dt : 0;
      idleFrames.endFrame(idle: _idleQuiet >= Config.idleMenuDelay);
    }
    // endregion P22-33c
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

/// WP-TAB: [FlappySpikesGame.bleedRect] seen from [c] (the plain 320 pt
/// wide rect when [c] is not in a game, e.g. a standalone widget test).
Rect bleedRectFor(Component c, double height, {double top = 0}) {
  final g = c.findGame();
  return g is FlappySpikesGame
      ? g.bleedRect(height, top: top)
      : Rect.fromLTWH(0, top, Config.worldWidth, height);
}
