import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
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
      // PRD-2.3 §26.3: a best of 25 or more keeps the Shop and Skins open.
      'bestScore': 25, 'playerLevel': 1,
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
        'build/store/screenshots_tablet/${entry.key}_$scene.png',
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
      // PRD-2 (WP-1a): the real hoop course, flown by the hoop-aware
      // autopilot; captured when the next hoop is just ahead of the bird.
      game.onScreenTap();
      game.update(dt);
      await flushAndMount(game);
      final run = game.run!;
      await flyRun(game, untilHoops: 2);
      for (var i = 0; i < 300; i++) {
        final next = run.spawner.nextHoopAhead();
        if (next != null && next.planeX - run.state.camX < 110) break;
        await flyRun(game, maxSeconds: dt);
      }

      // --- shot 2: gameplay -------------------------------------------------
      expect(game.state, GameState.playing);
      expect(game.score, greaterThanOrEqualTo(2),
          reason: 'the bird must have passed real hoops');
      expect(hoopsOf(game), isNotEmpty);
      await tester.runAsync(
        () => captureAll(game, 'gameplay'),
      );

      // --- shot 3: results -----------------------------------------------------
      // Force a collision: the bird onto the floor spikes; the §3.0.5 tumble
      // plays, then the PRD-2 §5.10 results page (counts up by 1.15 s).
      bird.body.setTransform(
        Vector2(Config.birdX, game.viewHeight - Config.spikeHeight),
        0,
      );
      for (var i = 0; i < 180 && game.state != GameState.results; i++) {
        game.update(dt);
      }
      expect(game.state, GameState.results);
      await flushAndMount(game);
      stepGame(game, 1.3);
      await flushAndMount(game);
      expect(game.world.children.query<ResultsScreen>(), hasLength(1));
      await tester.runAsync(
        () => captureAll(game, 'gameover'),
      );
    },
  );
}
