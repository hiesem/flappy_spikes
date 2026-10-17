import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/run_scaled_world.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A2-5: the run world is not drawn under the opaque results page (its
/// background covers the whole view). The frames while the page is up must
/// be byte-identical with and without that gate; the gate must stay open
/// while the page fades in and while a run shake has moved the view.
void main() {
  Future<Uint8List> render(FlappySpikesGame game, double h) async {
    game.onGameResize(Vector2(320, h));
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, 320, h));
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, 320, h),
      ui.Paint()..color = game.backgroundColor(),
    );
    game.render(canvas);
    final pic = rec.endRecording();
    final img = await pic.toImage(320, h.round());
    pic.dispose();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    img.dispose();
    return bytes.buffer.asUint8List();
  }

  for (final h in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, prefs: {'firstRunHintSeen': true}),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      'A2-5 the results page hides the run world only while it covers the view ($h)',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        final world = game.world as RunScaledWorld;
        await startRun(game);
        game.run!.ctx.addScore(12);
        killRun(game);
        await flushAndMount(game);
        final page = game.resultsScreen!;

        // The page fades in first: the world shows through, so the gate is open.
        expect(page.opacity, lessThan(1));
        expect(world.coveredBelowSource!(), isNull);

        for (var k = 0; k < 30; k++) {
          stepGame(game, .1);
          await flushAndMount(game);
        }
        expect(page.opacity, 1);
        expect(world.coveredBelowSource!(), page.priority);

        // The same state drawn with the gate on and off is byte-identical.
        final gate = world.coveredBelowSource;
        final gated = await tester.runAsync(() => render(game, h));
        world.coveredBelowSource = null;
        final open = await tester.runAsync(() => render(game, h));
        world.coveredBelowSource = gate;
        expect(
          sha256.convert(gated!).toString(),
          sha256.convert(open!).toString(),
          reason: 'the gated results frame must match the ungated one',
        );

        // A shaken view moves the page with it: the gate opens.
        game.camera.viewfinder.position = Vector2(3, 0);
        expect(world.coveredBelowSource!(), isNull);
        game.camera.viewfinder.position = Vector2.zero();
        expect(world.coveredBelowSource!(), page.priority);
      },
    );
  }
}
