import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.3.1 §9 visual check: the HUD top row at 0, 1, 2 and 3 hearts, as
/// PNGs in `build/shots/p231/` (copied to `briefs9/evidence/wpCD/` by hand).
/// Renders the whole game like `captureShot` (menu_screenshot_test.dart) and
/// keeps the top 140 pt, where the heart sits.
const String outDir = 'build/shots/p231';
const double _scale = 3;
const double _cropTop = 140;

Future<void> _shot(FlappySpikesGame game, String name) async {
  final size = Vector2(
    320 * _scale,
    (game.viewHeight * _scale).roundToDouble(),
  );
  // Resize right before rendering: the harness reverts earlier resizes.
  game.onGameResize(size);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  final full = await recorder.endRecording().toImage(
    size.x.toInt(),
    size.y.toInt(),
  );
  final cropH = _cropTop * _scale;
  final cropRecorder = ui.PictureRecorder();
  ui.Canvas(cropRecorder).drawImageRect(
    full,
    ui.Rect.fromLTWH(0, 0, size.x, cropH),
    ui.Rect.fromLTWH(0, 0, size.x, cropH),
    ui.Paint(),
  );
  final cropped = await cropRecorder.endRecording().toImage(
    size.x.toInt(),
    cropH.toInt(),
  );
  final bytes = (await cropped.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  full.dispose();
  cropped.dispose();
  final file = File('$outDir/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('SHOT ${file.path}: ${bytes.length} bytes');
  expect(bytes.length, greaterThan(5000));
}

void main() {
  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  );

  tester.testGameWidget(
    'PRD-2.3.1 §9 HUD heart shots at 0, 1, 2 and 3 hearts',
    setUp: (g, _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    },
    verify: (game, tester) async {
      await startRun(game);
      // Let the run's screen transition and the HUD row finish fading in.
      stepGame(game, 1);
      await flushAndMount(game);
      for (final n in [0, 1, 2, 3]) {
        final run = game.run!;
        run.state.hearts = n;
        game.runHud!.rowOpacity = 1;
        await flushAndMount(game);
        await tester.runAsync(() => _shot(game, 'hud_hearts_$n'));
      }
    },
  );
}
