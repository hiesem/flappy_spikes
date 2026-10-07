import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/gameover_panel.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'screenshot_generator_test.dart' show loadFonts;

/// Generates the 7-inch and 10-inch tablet screenshots for the Play Store
/// listing: the same three scenes as the phone shots (start / gameplay /
/// game over), rendered at tablet resolutions with the REQUIRED 9:16 aspect
/// (console rule: 16:9 or 9:16 only — 7": 1080x1920, 10": 1440x2560, the
/// 10-inch section also requires sides of 1080-7680 px).
///
/// Scene staging is identical to test/screenshot_generator_test.dart — see
/// that file for the authenticity notes.
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  final sizes = <String, Vector2>{
    'tablet7': Vector2(1080, 1920),
    'tablet10': Vector2(1440, 2560),
  };
  const dt = 1 / 60;

  final withGame = FlameTester<FlappySpikesGame>(
    () => createTestGame({
      'bestScore': 12,
      'gamesPlayed': 34,
      // EGG already claimed: no LEVEL UP popup over the captures.
      'claimedLevels': ['1'],
    }),
    gameSize: Vector2(1200, 1920),
  );

  /// Renders the current frame at [size] and writes it as a PNG. Must be
  /// called inside tester.runAsync (real event loop needed for toImage).
  Future<void> capturePng(
    FlappySpikesGame game,
    String path,
    Vector2 size,
  ) async {
    game.onGameResize(size);
    final w = size.x.toInt();
    final h = size.y.toInt();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      ui.Paint()..color = game.backgroundColor(),
    );
    game.render(canvas);
    final image = await recorder.endRecording().toImage(w, h);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    image.dispose();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    debugPrint('SHOT $path: ${bytes.length} bytes');
    expect(bytes.length, greaterThan(20000),
        reason: '$path should be a non-trivial render');
  }

  Future<void> captureAll(FlappySpikesGame game, String scene) async {
    for (final entry in sizes.entries) {
      await capturePng(
        game,
        '../flappy_spikes/store/screenshots_tablet/${entry.key}_$scene.png',
        entry.value,
      );
    }
  }

  withGame.testGameWidget(
    'generates tablet store screenshots (7" + 10")',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onGameResize(Vector2(1200, 1920));
    },
    verify: (game, tester) async {
      final bird = game.world.children.query<Bird>().single;

      // --- shot 1: start scene ---------------------------------------------
      stepGame(game, 0.4);
      expect(game.state, GameState.start);
      await tester.runAsync(() => captureAll(game, 'start'));

      // --- enter playing state ----------------------------------------------
      game.onScreenTap();
      game.update(dt);
      await flushAndMount(game);

      for (final pipe in game.world.children.query<PipePair>()) {
        pipe.removeFromParent();
      }
      game.update(dt);
      final staged = <PipePair>{};
      for (final x in [364.0, 564.0, 764.0]) {
        final pipe = PipePair(gapBottomY: 351);
        await game.world.add(pipe);
        await pipe.loaded;
        game.update(0);
        pipe.body.setTransform(Vector2(x, Config.worldHeight / 2), 0);
        staged.add(pipe);
      }

      // --- shot 2: gameplay -------------------------------------------------
      stepGame(game, 0.8, flapBelow: 320);
      var t = 0.8;
      double? blendFrom;
      const captureT = 2.42;

      Future<void> stepFrame() async {
        game.update(dt);
        t += dt;
        await Future<void>.value();
        for (final pipe in game.world.children.query<PipePair>()) {
          if (!staged.contains(pipe)) {
            pipe.removeFromParent();
          }
        }
      }

      while (t < captureT) {
        await stepFrame();
        if (game.state == GameState.playing) {
          blendFrom ??= bird.body.position.y;
          final blend = ((t - 0.8) / 0.25).clamp(0.0, 1.0);
          final target = 298.5 + 32 * math.sin(2 * math.pi * (t - 0.8) / 1.4);
          bird.body.linearVelocity.setZero();
          bird.body.setTransform(
            Vector2(Config.birdX, blendFrom + (target - blendFrom) * blend),
            0,
          );
        }
      }

      expect(game.state, GameState.playing);
      expect(game.score, greaterThanOrEqualTo(1),
          reason: 'bird must have passed a score sensor');
      expect(game.world.children.query<PipePair>(), hasLength(2));
      await tester.runAsync(() => captureAll(game, 'gameplay'));

      // --- shot 3: game over -------------------------------------------------
      bird.body.setTransform(Vector2(Config.birdX, 401), 0);
      final frozenT = t + 0.2;
      while (t < frozenT) {
        await stepFrame();
      }
      expect(game.state, GameState.gameOver);

      for (final pipe in game.world.children.query<PipePair>()) {
        pipe.removeFromParent();
      }
      final revealT = t + 1.0;
      while (t < revealT) {
        await stepFrame();
      }
      await flushAndMount(game);
      expect(game.world.children.query<GameOverPanel>(), hasLength(1));
      await tester.runAsync(() => captureAll(game, 'gameover'));
    },
  );
}
