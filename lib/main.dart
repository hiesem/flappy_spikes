import 'dart:async';
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/audio_counter.dart';
import 'components/banner_slot.dart';
import 'game/flappy_game.dart';
import 'services/app_info.dart';
import 'services/game_services.dart';
import 'services/e2e.dart';
import 'services/ads_service.dart';
import 'services/audio_focus.dart';
import 'services/monetization.dart';
import 'services/rating_prompt.dart';
import 'services/reminders.dart';
import 'services/soak.dart';
import 'services/tuning.dart';
import 'services/tuning_firebase.dart';
import 'run/config/versus_config.dart';
import 'services/avatars.dart';
import 'services/versus_service.dart';
import 'share/share_flow.dart';

/// PRD-2.3 §2: the share card painter and the share sheet (results share
/// button and the Invite tile).
final ShareFlow _shareFlow = ShareFlow();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The Linux desktop build is a local test target only: no Firebase / Play
  // Games, and no orientation or system-UI control.
  final isLinux = !kIsWeb && Platform.isLinux;
  // region P22-33 — FS_SOAK profile build (§33.3): the player's saved data
  // is never touched (in-memory prefs), no Firebase / Play Games / versus /
  // reminders (no analytics, leaderboard or pool writes from the bot), and
  // the live audio player counter wraps the audioplayers platform before
  // the first player exists.
  if (kSoak) {
    // The in-memory store on purpose (the release e2e does the same).
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'bestScore': 0,
      'coins': 0,
      'firstSessionDone': true,
    });
    CountingAudioPlatform.install();
  }
  // endregion P22-33
  try {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // Fullscreen: hide the status bar (and navigation bar).
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [],
    );
    // S7-20: when the navigation bar is shown over a menu (see
    // SystemBackObserver), it is see-through: only the gesture handle shows
    // over the bottom spike strip; the playfield never moves (edge-to-edge).
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Color(0x00000000),
        systemNavigationBarDividerColor: Color(0x00000000),
        systemNavigationBarContrastEnforced: false,
      ),
    );
  } catch (_) {
    // Unsupported on desktop; never block startup on it.
  }

  // Full-bleed playfield: the world is 320 pt wide; its height follows the
  // screen aspect (clamped inside the game) so the spike strips pin to the
  // true top/bottom edges with no letterbox bars.
  final worldHeight = await _worldHeight(isLinux);

  // Analytics + leaderboards (Firebase / Play Games / Game Center). No-op
  // when the native config isn't present.
  final services = GameServices();

  // region P23-15 — remote tuning (PRD-2.3 §15.2): FS_TUNING tester builds
  // only. activate() applies the values fetched last time (before the first
  // run can start: a run reads them at its start), then a background
  // fetch() stores new ones for the next start. The production build (no
  // flag) never creates the backend and makes no Remote Config request.
  if (kTuning && _isMobile && !kSoak) {
    Tuning.instance = Tuning(
      backend: FirebaseTuningBackend(ensureFirebase: services.ensureFirebase),
    );
    // S8-02: wait for activation (bounded: Firebase.initializeApp has no
    // timeout) so it lands before the first run can start. A slower
    // activation still never changes a begun run (Tuning.beginRun pins).
    try {
      await Tuning.instance.initialize().timeout(
        const Duration(seconds: 3),
      );
    } on TimeoutException {
      debugPrint('Tuning: activation still pending after 3 s');
    }
  }
  // endregion P23-15

  // Rewarded ads + in-app purchases: AdMob / Play Billing / StoreKit on
  // mobile, in-memory fakes elsewhere (Linux).
  // Off mobile the fakes are in use: show a visible test ad (countdown
  // overlay) instead of completing instantly.
  // region WP-0b — FS_E2E builds use the fake ads with the visible overlay
  // (succeed) and the in-memory store (ARCH §7.3).
  // PRD-2.2 §7.5.1: the adaptive banner size is worked out for the screen
  // width in dp. Off mobile (Linux) the fake interstitial ("TEST AD", 3 s)
  // and a grey fake banner strip show the flow (§7.10); E2E builds keep both
  // off unless a test asks for them.
  final widthDp = _screenWidthDp();
  final monetization =
      (kE2E
            ? Monetization()
            : _isMobile
            ? Monetization.forPlatform(bannerWidthDp: widthDp)
            : Monetization(
                interstitial: FakeInterstitialAds(mode: FakeAdMode.succeed),
                banner: FakeBannerAds(enabled: true, widthDp: widthDp),
              ))
        ..showFakeAdOverlay = kE2E || !_isMobile;
  // endregion WP-0b

  // region WP-5b — versus (PRD-2 §3.13): the Firebase service on Android
  // only (iOS later, Linux desktop never); everything else keeps the no-op.
  // It reads the game's storage lazily (the game is built right below).
  late final FlappySpikesGame game;
  final VersusService versus = _isAndroid && !kSoak
      ? FirebaseVersusService(
          storageOf: () => game.storage,
          // S6-66: a failed start-up auth retries in the background.
          retryBase: VersusConfig.authRetryBase,
          // S6-F01 / S6-F02: every start (main below, Home prefetch, an
          // early resume) waits for the ONE shared Firebase.initializeApp
          // and for the game's storage load.
          startAfter: () async {
            if (!await services.ensureFirebase()) {
              throw StateError('Firebase is not initialized');
            }
            await game.loaded;
          },
        )
      : NoopVersusService();
  // endregion WP-5b

  // PRD-2.3 §23.4: the store's own rating sheet (Google Play's in-app review,
  // Apple's prompt) on the mobile products only; the Linux desktop target and
  // FS_E2E / soak builds never request it.
  final rating = RatingPrompt(
    backend: _isMobile && !kE2E && !kSoak ? const InAppReviewBackend() : null,
  );

  game = FlappySpikesGame(
    worldHeight: worldHeight,
    services: services,
    monetization: monetization,
    versus: versus,
    // S6-64: Play Games avatars over https on the products only.
    avatarSource: _isMobile && !kE2E && !kSoak ? HttpAvatarSource() : null,
    rating: rating,
  );
  // PRD-2.2 §33.4 item 5: idle menus draw at Config.idleMenuFps. Not in
  // FS_E2E builds, whose tests pump the frames themselves.
  if (!kE2E) {
    game.idleFrames
      ..enabled = true
      ..attach();
  }
  game.onShareScore = _shareFlow.share;
  game.onInvite = _shareFlow.share;
  // PRD-2.2 §28.3: other apps' calls / alarms / music (Android; iOS later).
  if (_isAndroid) game.audioFocus = PlatformAudioFocus();
  // PRD-2.3 §20.2: the Settings footer's version (package_info_plus).
  game.appInfo = PluginAppInfo();

  // region PRD-2.2 §8 — the Android system back closes the menus only, and
  // never the app (SystemBackObserver below).
  SystemBackObserver(game).install();
  // endregion PRD-2.2 §8

  // region WP-4b — reminder notifications (PRD-2 §3.34)
  // Real local notifications on the mobile products only; the Linux desktop
  // target and FS_E2E builds keep the no-op default. The game asks for the
  // permission once and lays out the first 7-day plan from onLoad.
  if (_isMobile && !kE2E && !kSoak) {
    game.reminders = LocalReminders(storage: game.storage, services: services);
  }
  // endregion WP-4b

  // PRD-2.2 §7.5.2: the game over the banner slot. PRD-2.3 §2.0: shares are
  // a drawn card, never a screen capture.
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RepaintBoundary(child: GameWidget(game: game)),
          ),
          BannerSlot(game: game),
        ],
      ),
    ),
  );

  // Fire-and-forget AFTER runApp: Firebase.initializeApp has no timeout and
  // can stall cold start on a slow/offline device. initialize() swallows its
  // own errors; the service is a safe no-op until it lands.
  if (!isLinux && !kSoak) {
    // region WP-5b — versus after Firebase.initializeApp (services) and the
    // game's storage load (S6-F01: its startAfter gate, shared with every
    // other start path); initialize() never throws (failure = solo).
    unawaited(services.initialize());
    // versus.initialize() waits for Firebase + storage itself (startAfter).
    unawaited(versus.initialize());
    // endregion WP-5b
    // PRD-2.3 §23.4: asks the platform once whether the rating sheet can show.
    unawaited(rating.prepare());
  }
  // Same fire-and-forget rule: the UMP consent form may be shown here, and
  // initialize() never throws; until it lands ads are simply unavailable.
  unawaited(monetization.initialize());
}

/// PRD-2.2 §8.2: the Android system back (the gesture, or the 3-button back)
/// reaches the game's back stack. It is always reported as handled, so
/// Flutter never calls `SystemNavigator.pop` and the app never leaves on back.
///
/// S7-20: with predictive back (targetSdk 36, Android 14+) the system only
/// hands back to the app while the engine's `OnBackInvokedCallback` is
/// registered, and the engine registers it only when the framework says it
/// handles back (`SystemNavigator.setFrameworkHandlesBack(true)`, normally
/// sent by `WidgetsApp`, which this game does not use). Without it a back
/// swipe / KEYCODE_BACK finished the activity and [didPopRoute] was never
/// reached. [install] claims back for the whole app lifetime (MainActivity
/// also claims it natively in onCreate, before Dart runs); the predictive
/// commit then lands in [didPopRoute] via `handlePopRoute`.
class SystemBackObserver extends WidgetsBindingObserver {
  SystemBackObserver(this.game);

  final FlappySpikesGame game;

  /// Adds the observer and claims system back for the framework.
  void install() {
    WidgetsBinding.instance.addObserver(this);
    _claimBack();
    game.onSystemBackWanted = showNavigationBar;
  }

  /// S7-20: Android's sticky immersive mode spends the first edge swipe on
  /// revealing the hidden system bars, so the back swipe would need two
  /// swipes. While a menu screen / popup is open (the only place back does
  /// something) the navigation bar (the gesture handle) is shown, so one
  /// swipe closes it; Home and runs stay fully immersive (an accidental
  /// edge swipe there only reveals the bars, as before). The status bar is
  /// always hidden.
  static void showNavigationBar(bool show) {
    if (!_isAndroid) return;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: show ? const [SystemUiOverlay.bottom] : const [],
      ).catchError((Object _) {}),
    );
  }

  static void _claimBack() {
    unawaited(
      SystemNavigator.setFrameworkHandlesBack(true).catchError((Object _) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-assert after returning to the app (a recreated activity starts
    // without the engine callback until told again).
    if (state == AppLifecycleState.resumed) _claimBack();
  }

  @override
  Future<bool> didPopRoute() async {
    game.handleSystemBack();
    return true;
  }
}

/// Android / iOS host (where [Monetization.forPlatform] picks the real
/// plugins).
bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// The versus backend runs on Android only for now (WP-5b; iOS paused).
bool get _isAndroid => !kIsWeb && Platform.isAndroid;

/// The screen width in logical pixels (dp); 360 when unknown.
double _screenWidthDp() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return 360;
  final view = views.first;
  final w = view.physicalSize.width / view.devicePixelRatio;
  return w.isFinite && w > 0 ? w : 360;
}

/// Fallback aspect (9:19.5 -> ~693 pt) when no usable window size exists
/// yet: the Linux runner opens a fixed 9:19.5 window.
const double _fallbackWorldHeight = 320 * 19.5 / 9;

/// 320 x (screen aspect) world height. On Linux the GTK window can still be
/// 0x0 before runApp, so it polls briefly for a real size and then falls
/// back to 9:19.5; mobile reads the size once, as before.
Future<double> _worldHeight(bool isLinux) async {
  double? fromView() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return null;
    final size = views.first.physicalSize;
    final height = 320 * size.height / size.width;
    return size.isEmpty || !height.isFinite || height <= 0 ? null : height;
  }

  var height = fromView();
  if (isLinux) {
    for (var i = 0; height == null && i < 15; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      height = fromView();
    }
  }
  return height ?? _fallbackWorldHeight;
}

