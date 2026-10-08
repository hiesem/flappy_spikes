import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3g screenshot check (ARCH §7.1): real run frames of the spike
/// squeeze next to the §5.16 mocks (`squeeze_fly / squeeze_warn /
/// squeeze_close / squeeze_hold1 / squeeze_hold4.png`). Writes PNGs to
/// `build/shots/run/squeeze/` (never committed); nothing is asserted beyond
/// "rendered".
const String outDir = 'build/shots/run/squeeze';

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

  for (final h in [711.0, 568.0]) {
    for (final (moment, index) in [
      ('fly', 0),
      ('warn', 0),
      ('close', 0),
      ('hold1', 0),
      ('hold4', 3),
      ('lens', 3),
    ]) {
      final name = 'squeeze_${moment}_${h.round()}';
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: h, seed: 4),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§5.16 shot $name',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, tester) async {
          game.sound.enabled = false;
          final run = await startRun(game);
          // a few hoops in, so the score circle shows a number
          await flyUntil(game, (r) => r.state.hoopsPassed >= 3);
          run.state.squeeze.index = index;
          final sq = run.features.whereType<SqueezeFeature>().single;
          sq.force();
          final s = run.state.squeeze;
          switch (moment) {
            case 'fly':
              break;
            case 'warn':
              await flyUntil(
                game,
                (_) => s.phase == SqueezePhase.warning && sq.phaseT >= .25,
              );
            case 'close':
              await flyUntil(
                game,
                (_) => s.phase == SqueezePhase.closing && sq.phaseT >= 1.5,
              );
            default:
              await flyUntil(
                game,
                (_) => s.phase == SqueezePhase.hold && sq.phaseT >= 1,
              );
          }
          await flushAndMount(game);
          run.debugFreeze();
          if (moment == 'lens') {
            // a Black Hole's lensing (WP-3d) on the squeezed strips
            final c = Offset(230, h / 2);
            for (final strip in game.world.children.whereType<SpikeStrip>()) {
              strip.lens = (p) {
                final d = (p - c).distance;
                final k = 40 * math.exp(-d / 170);
                return p + (c - p) / d * k;
              };
            }
          }
          await tester.runAsync(() => shot(game, 1.5, name));
        },
      );
    }
  }
}
