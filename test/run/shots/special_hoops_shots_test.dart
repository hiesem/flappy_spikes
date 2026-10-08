import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/kinds/lucky_spin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3c screenshot check (ARCH §7.1): real run frames of the Bullseye
/// (§5.23 `lab_bull.png`), Ring Train (§5.21 `lab_train.png`), Spring
/// (§5.22 `lab_spring.png`), Lucky Spin (§5.24 `lab_lucky.png`) and the
/// FEVER ring (§5.18 `fever_approach / fever_pass / fever_burning.png`).
/// Writes PNGs to `build/shots/run/special/` (never committed); nothing is
/// asserted beyond "rendered".
const String outDir = 'build/shots/run/special';

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
    for (final (element, kind, start, moment) in [
      (ElementId.bullseye, HoopKindId.bullseye, 6, 'approach'),
      (ElementId.bullseye, HoopKindId.bullseye, 6, 'hit'),
      (ElementId.train, HoopKindId.train, 8, 'approach'),
      (ElementId.train, HoopKindId.train, 8, 'two'),
      (ElementId.spring, HoopKindId.spring, 10, 'approach'),
      (ElementId.spring, HoopKindId.spring, 10, 'boing'),
      (ElementId.luckySpin, HoopKindId.luckySpin, 15, 'approach'),
      (ElementId.luckySpin, HoopKindId.luckySpin, 15, 'stop'),
      (ElementId.fever, HoopKindId.fever, 15, 'approach'),
      (ElementId.fever, HoopKindId.fever, 15, 'pass'),
      (ElementId.fever, HoopKindId.fever, 15, 'burning'),
    ]) {
      final name = '${element.storageId}_${moment}_${h.round()}';
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: h, seed: 4),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§5.18 / §5.21–§5.24 shot $name',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, tester) async {
          game.sound.enabled = false;
          final run = await startRun(
            game,
            startHoopIndex: start,
            force: [element],
          );
          await flyUntil(game, (_) => firstHoopOf(game, kind) != null);
          final hoops = hoopsOf(game).where((x) => x.plan.kind == kind).toList();
          final hoop = hoops.first;
          switch (moment) {
            case 'approach':
              await flyUntil(game, (r) => hoop.planeX - r.state.camX <= 150);
            case 'hit':
              await passHoopAt(game, hoop);
              await flyUntil(game, (_) => false, maxSeconds: .12);
            case 'two':
              await passHoopAt(game, hoops[0]);
              await passHoopAt(game, hoops[1]);
              await flyUntil(game, (_) => false, maxSeconds: .05);
            case 'boing':
              await passHoopAt(game, hoop);
              await flyUntil(game, (_) => false, maxSeconds: .15);
            case 'stop':
              await passHoopAt(game, hoop);
              final w = LuckySpinHoopKind.wheelOf(hoop)!;
              await flyUntil(game, (_) => w.stopped, maxSeconds: 3);
              await flyUntil(game, (_) => false, maxSeconds: .3);
            case 'pass':
              await passHoopAt(game, hoop);
              await flyUntil(game, (_) => false, maxSeconds: .12);
            case 'burning':
              await passHoopAt(game, hoop);
              await flyUntil(game, (_) => false, maxSeconds: 1.2);
          }
          await flushAndMount(game);
          run.debugFreeze();
          await tester.runAsync(() => shot(game, 1.5, name));
        },
      );
    }
  }
}
