import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-1a screenshot check (ARCH §7.1): a run frame with the M0 hoops at 568
/// and 711 (compare with `design/menu_v2/hoops_m0.png`, §5.1), the 44 pt
/// strips, and the §5.13 miss flash at the mock's three moments (compare
/// with `miss_c_flash.png` / `miss_c_wave.png` / `miss_c_ghost.png`).
/// Writes PNGs to `build/shots/run/hoops/` (never committed); nothing is
/// asserted beyond "rendered".
const String outDir = 'build/shots/run/hoops';

Future<void> _fonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  await Future.wait([lvdc.load(), opificio.load()]);
}

/// Same render path as `captureShot` (menu_screenshot_test.dart): resize
/// right before rendering (the harness reverts earlier resizes).
Future<void> shot(FlappySpikesGame game, double scale, String name) async {
  final size = Vector2(320 * scale, (game.viewHeight * scale).roundToDouble());
  game.onGameResize(size);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  final image = await recorder.endRecording().toImage(
    size.x.toInt(),
    size.y.toInt(),
  );
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  final file = File('$outDir/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('SHOT ${file.path}: ${bytes.length} bytes');
  expect(bytes.length, greaterThan(10000));
}

void main() {
  setUpAll(_fonts);

  for (final h in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.1 run frame with M0 hoops at ${h.round()}',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        final run = await startRun(game);
        await flyRun(game, untilHoops: 2);
        // Fly on until the next hoop's plane is just right of the bird.
        for (var i = 0; i < 300; i++) {
          final next = run.spawner.nextHoopAhead();
          if (next != null && next.planeX - run.state.camX < 100) break;
          await flyRun(game, maxSeconds: 1 / 60);
        }
        await tester.runAsync(() => shot(game, 2, 'run_${h.round()}'));
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.13 miss flash at ${h.round()}',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        final run = await startRun(game);
        run.events.recordLog = true;
        // Hold the bird above the first hoop so it misses it.
        await flyRun(
          game,
          maxSeconds: 4,
          autopilot: false,
          onFrame: (r) {
            if (r.state.hoopsPassed == 0 &&
                r.events.log.whereType<HoopMissed>().isEmpty) {
              game.runBird!.setFlight(y: h / 2 - 125, vy: 0);
            }
          },
        );
        expect(run.events.log.whereType<HoopMissed>(), hasLength(1));
        // flyRun stops at the miss (state dying); step to each moment.
        var t = 0.0;
        for (final (at, name) in [
          (0.06, 'flash'),
          (0.3, 'wave'),
          (1.0, 'ghost'),
        ]) {
          while (t < at - 1e-9) {
            game.update(1 / 60);
            t += 1 / 60;
          }
          await flushAndMount(game);
          await tester.runAsync(
            () => shot(game, 1.5, 'miss_${name}_${h.round()}'),
          );
        }
      },
    );
  }
}
