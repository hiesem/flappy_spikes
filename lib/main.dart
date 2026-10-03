import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'game/config.dart';
import 'game/flappy_game.dart';
import 'services/game_services.dart';
import 'services/monetization.dart';

/// Key on the [RepaintBoundary] wrapping the game, used to capture a
/// screenshot of the game area for sharing.
final GlobalKey _gameBoundaryKey = GlobalKey();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The Linux desktop build is a local test target only: no Firebase / Play
  // Games, and no orientation or system-UI control.
  final isLinux = !kIsWeb && Platform.isLinux;
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
  final monetization = Monetization.forPlatform();

  final game = FlappySpikesGame(
    worldHeight: worldHeight,
    services: services,
    monetization: monetization,
  );
  game.onShareScore = _shareScore;
  game.onInvite = _invite;

  runApp(
    RepaintBoundary(
      key: _gameBoundaryKey,
      child: GameWidget(game: game),
    ),
  );

  // Fire-and-forget AFTER runApp: Firebase.initializeApp has no timeout and
  // can stall cold start on a slow/offline device. initialize() swallows its
  // own errors; the service is a safe no-op until it lands.
  if (!isLinux) {
    unawaited(services.initialize());
  }
  // Same fire-and-forget rule: the UMP consent form may be shown here, and
  // initialize() never throws; until it lands ads are simply unavailable.
  unawaited(monetization.initialize());
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
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
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
