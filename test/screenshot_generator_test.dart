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
/// - World scrolling, pipe spawning, the score sensor (score fires via real
///   contact), collision -> game over and the panel fades are all real.
/// - The bird flies honestly (flap impulses) until the pipes get close, then
///   its y is choreographed onto a smooth path through the gap band. Kept
///   purely for a deterministic, well-framed shot — the physics no longer
///   require it (flap rise ~55 pt fits the 105 - 29.5 = 75.5 pt usable gap
///   band); real play threads gaps diagonally.
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
    () => createTestGame({'bestScore': 12, 'gamesPlayed': 34}),
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
      game.onScreenTap();
      game.update(dt); // first auto-spawned pipe
      await flushAndMount(game);

      // Replace the random auto-spawned pair with three staged pairs whose
      // gaps are aligned with the bird's choreographed band. Spacing is
      // tighter than the in-game 300 pt so two pairs frame the shot nicely.
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
      // t = 0 now (game just started; staged pipes at x = 364/564/764).
      // Fly honestly for 0.8 s, then choreograph onto a sine path through
      // the gap band [246, 351] (edges stay >= 5 pt clear of the pipes).
      stepGame(game, 0.8, flapBelow: 320);
      var t = 0.8;
      double? blendFrom;
      const captureT = 2.42; // pipe B centered on the bird, pipe C entering

      // Steps one frame, flushing microtasks so newly spawned pipes finish
      // loading (otherwise their pending ADD blocks the whole lifecycle
      // queue, starving removals), and suppressing natural spawns whose
      // random gaps could hit the staged bird.
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
      expect(game.world.children.query<PipePair>(), hasLength(2),
          reason: 'two staged pipe pairs should be on screen');
      await tester.runAsync(
        () => capturePng(game, '../shots/store_gameplay.png'),
      );

      // --- shot 3: game over -------------------------------------------------
      // Force a collision: teleport the bird into the middle pipe's bottom
      // half (pipe B is centered on the bird right now).
      bird.body.setTransform(Vector2(Config.birdX, 401), 0);
      final frozenT = t + 0.2; // a few frames for the contact to fire
      while (t < frozenT) {
        await stepFrame();
      }
      expect(game.state, GameState.gameOver);

      // For a readable store shot, clear the frozen pipes: the game-over
      // title and labels are tinted with the same fg color as the pipes and
      // would otherwise camouflage against the pipe columns.
      for (final pipe in game.world.children.query<PipePair>()) {
        pipe.removeFromParent();
      }
      final revealT = t + 1.0; // panel staggered fade-in is 0.9 s
      while (t < revealT) {
        await stepFrame();
      }
      await flushAndMount(game);
      expect(game.world.children.query<GameOverPanel>(), hasLength(1));
      await tester.runAsync(
        () => capturePng(game, '../shots/store_gameover.png'),
      );
    },
  );
}
