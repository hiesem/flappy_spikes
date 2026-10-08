import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Generates real rendered frames for the Play Store listing.
///
/// Rendering approach: PictureRecorder -> game.render(canvas) -> toImage ->
/// PNG bytes. The letterbox-bar color (the foreground tint, painted by the
/// GameWidget in production) is filled manually; the world's own background
/// is drawn by the game's in-world backdrop rect.
///
/// Authenticity notes:
/// - World scrolling, hoop spawning, the pass test, the spike contact ->
///   tumble -> game over and the panel fades are all real (PRD-2, WP-1a);
///   the bird is flown by the hoop-aware autopilot on the seeded course.
/// Loads the game's fonts into the engine. Must run before the game boots:
/// TextPainter caches its laid-out paragraph, so any text component first
/// laid out before the font is registered renders as tofu boxes for the
/// rest of the session.
Future<void> loadFonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  await Future.wait([lvdc.load(), opificio.load()]);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  final shotSize = Vector2(1080, 1920);
  const dt = 1 / 60;

  final withGame = FlameTester<FlappySpikesGame>(
    () => createTestGame({
      'bestScore': 12,
      'gamesPlayed': 34,
      // EGG already claimed: no LEVEL UP popup over the captures.
      'claimedLevels': ['1'],
    }),
    gameSize: shotSize,
  );

  /// Renders the current frame and writes it as a PNG. Must be called
  /// inside tester.runAsync (real event loop needed for toImage/toByteData).
  Future<void> capturePng(FlappySpikesGame game, String path) async {
    // Force the render transform to the shot size right before rendering:
    // the harness's widget pumps can revert a resize done earlier.
    game.onGameResize(shotSize);
    final w = shotSize.x.toInt();
    final h = shotSize.y.toInt();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, shotSize.x, shotSize.y),
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
    expect(
      bytes.length,
      greaterThan(20000),
      reason: '$path should be a non-trivial render',
    );
  }

  withGame.testGameWidget(
    'generates store screenshots (start / gameplay / gameover)',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onGameResize(shotSize);
    },
    verify: (game, tester) async {
      final bird = game.world.children.query<Bird>().single;

      // --- shot 1: start scene ---------------------------------------------
      stepGame(game, 0.4); // let the idle animation advance a little
      expect(game.state, GameState.start);
      await tester.runAsync(() => capturePng(game, '../shots/store_start.png'));

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
        () => capturePng(game, '../shots/store_gameplay.png'),
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
        () => capturePng(game, '../shots/store_gameover.png'),
      );
    },
  );
}
