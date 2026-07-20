import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'game/flappy_game.dart';
import 'services/game_services.dart';

/// Key on the [RepaintBoundary] wrapping the game, used to capture a
/// screenshot of the game area for sharing.
final GlobalKey _gameBoundaryKey = GlobalKey();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Fullscreen: hide the status bar (and navigation bar).
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

  // Full-bleed playfield: the world is 320 pt wide; its height follows the
  // screen aspect (clamped inside the game) so the spike strips pin to the
  // true top/bottom edges with no letterbox bars.
  final screenSize =
      WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
  final worldHeight = 320 * screenSize.height / screenSize.width;

  // Analytics + leaderboards (Firebase / Play Games / Game Center). No-op
  // when the native config isn't present; never blocks startup on failure.
  final services = GameServices();
  await services.initialize();

  final game = FlappySpikesGame(worldHeight: worldHeight, services: services);
  game.onShareScore = _shareScore;

  runApp(
    RepaintBoundary(
      key: _gameBoundaryKey,
      child: GameWidget(game: game),
    ),
  );
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
