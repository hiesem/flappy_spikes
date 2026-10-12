import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/audio_counter.dart';
import 'components/banner_slot.dart';
import 'game/config.dart';
import 'game/flappy_game.dart';
import 'services/game_services.dart';
import 'services/e2e.dart';
import 'services/ads_service.dart';
import 'services/audio_focus.dart';
import 'services/monetization.dart';
import 'services/reminders.dart';
import 'services/soak.dart';
import 'run/config/versus_config.dart';
import 'services/avatars.dart';
import 'services/versus_service.dart';

/// Key on the [RepaintBoundary] wrapping the game, used to capture a
/// screenshot of the game area for sharing.
final GlobalKey _gameBoundaryKey = GlobalKey();

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

  game = FlappySpikesGame(
    worldHeight: worldHeight,
    services: services,
    monetization: monetization,
    versus: versus,
    // S6-64: Play Games avatars over https on the products only.
    avatarSource: _isMobile && !kE2E && !kSoak ? HttpAvatarSource() : null,
  );
  // PRD-2.2 §33.4 item 5: idle menus draw at Config.idleMenuFps. Not in
  // FS_E2E builds, whose tests pump the frames themselves.
  if (!kE2E) {
    game.idleFrames
      ..enabled = true
      ..attach();
  }
  game.onShareScore = _shareScore;
  game.onInvite = _invite;
  // PRD-2.2 §28.3: other apps' calls / alarms / music (Android; iOS later).
  if (_isAndroid) game.audioFocus = PlatformAudioFocus();

  // region PRD-2.2 §8 — the Android system back closes the menus only, and
  // never the app (SystemBackObserver below).
  WidgetsBinding.instance.addObserver(SystemBackObserver(game));
  // endregion PRD-2.2 §8

  // region WP-4b — reminder notifications (PRD-2 §3.34)
  // Real local notifications on the mobile products only; the Linux desktop
  // target and FS_E2E builds keep the no-op default. The game asks for the
  // permission once and lays out the first 7-day plan from onLoad.
  if (_isMobile && !kE2E && !kSoak) {
    game.reminders = LocalReminders(storage: game.storage, services: services);
  }
  // endregion WP-4b

  // PRD-2.2 §7.5.2: the game over the banner slot. The share capture keeps
  // using the RepaintBoundary around the game only, so the ad is never in a
  // shared image.
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RepaintBoundary(
              key: _gameBoundaryKey,
              child: GameWidget(game: game),
            ),
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
  }
  // Same fire-and-forget rule: the UMP consent form may be shown here, and
  // initialize() never throws; until it lands ads are simply unavailable.
  unawaited(monetization.initialize());
}

/// PRD-2.2 §8.2: the Android system back (the gesture, or the 3-button back)
/// reaches the game's back stack. It is always reported as handled, so
/// Flutter never calls `SystemNavigator.pop` and the app never leaves on back.
class SystemBackObserver extends WidgetsBindingObserver {
  SystemBackObserver(this.game);

  final FlappySpikesGame game;

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

/// Home Invite tile: share sheet with the store link (no reward, PRD-1
/// §3.4).
Future<void> _invite() async {
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Can you beat me at Flappy Spikes? ${Config.storeListingUrl}',
      ),
    );
  } catch (_) {
    // No share sheet available (desktop): ignore.
  }
}

Future<void> _shareScore(int score) async {
  final text = 'OMG! I got $score points in Flappy Spikes!';
  try {
    final boundary = _gameBoundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      await SharePlus.instance.share(ShareParams(text: text));
      return;
    }
    final image = await boundary.toImage(pixelRatio: 2);
    // PRD-2.2 §33.4 item 6: the capture is freed as soon as it is encoded.
    final ByteData? bytes;
    try {
      bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    if (bytes == null) {
      await SharePlus.instance.share(ShareParams(text: text));
      return;
    }
    final file = File('${Directory.systemTemp.path}/flappy_spikes_score.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        files: [XFile(file.path, mimeType: 'image/png')],
      ),
    );
  } catch (_) {
    // Fall back to sharing just the text.
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
