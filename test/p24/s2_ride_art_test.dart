import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.4 §4 test 6 (§2.4 ride-ring art): every ride theme drawn with the
/// curve size at hoop 120 (71.3 pt) and with Big Hoops on (71.3 × 1.5 =
/// 106.95 pt). Nothing may throw, and the rings have
/// that size. PNGs of the ride (3.5 s in) and of the exit go to
/// `build/shots/p24/` (never committed) for the visual check.
const String outDir = 'build/shots/p24';

Future<void> _fonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await Future.wait([lvdc.load(), opificio.load(), fredoka.load()]);
}

/// Renders the whole game at its current size to `build/shots/p24/[name].png`.
Future<void> _shot(FlappySpikesGame game, String name) async {
  final size = Vector2(320, game.viewHeight.roundToDouble());
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
  for (final mult in [1.0, RunConfig.bigHoopsMult]) {
    for (final id in RideId.values) {
      final tag = mult == 1 ? '71.3' : '106.95';
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: 711, seed: 5),
        gameSize: Vector2(320, 711),
      ).testGameWidget(
        '§2.4 ride art: ${id.name} with ring size $tag'
        '${mult == 1 ? '' : ' (71.3 × Big Hoops)'} draws through the ride and '
        'its exit without throwing',
        setUp: (game, _) async {
          await game.ready();
          game.sound.enabled = false;
          await preloadImages(game);
        },
        verify: (game, tester) async {
          game.runDebug.god = true;
          final run = await startRun(
            game,
            startHoopIndex: 120,
            force: [ElementId.portal],
            ride: id,
            starter: mult == 1 ? Powerup.none : Powerup.bigHoops,
          );
          final f = run.features.whereType<PortalRideFeature>().single;
          final bot = Autopilot(run);
          for (var frame = 0; frame < 60 * 40 && f.ride == null; frame++) {
            if (bot.shouldFlap()) game.onScreenTap();
            game.update(1 / 60);
            if (frame % 10 == 0) await flushAndMount(game);
          }
          final ride = f.ride;
          expect(ride, isNotNull, reason: '${id.name} started');
          expect(ride!.theme.id, id);
          expect(ride.rings, isNotEmpty);
          for (final r in ride.rings) {
            expect(r.opening, closeTo(71.3 * mult, 1e-9), reason: 'ring size');
          }
          // The ride itself: frames while rings are ahead of the bird (1.2 s
          // and 2.4 s in), then the exit (the bird's way back).
          for (final (name, at) in [('1', 1.2), ('2', 2.4)]) {
            for (var frame = 0; frame < 60 * 20; frame++) {
              if (ride.phase != RidePhase.ride) break;
              if (ride.view.rt >= at) break;
              if (bot.shouldFlap()) game.onScreenTap();
              game.update(1 / 60);
              if (frame % 10 == 0) await flushAndMount(game);
            }
            await flushAndMount(game);
            await tester.runAsync(
              () => _shot(game, 'ride_${id.name}_${tag}_$name'),
            );
          }
          // The exit: the first frames once the ride is leaving.
          for (var frame = 0; frame < 60 * 20; frame++) {
            if (ride.phase.index >= RidePhase.exit.index) break;
            if (bot.shouldFlap()) game.onScreenTap();
            game.update(1 / 60);
            if (frame % 10 == 0) await flushAndMount(game);
          }
          await flushAndMount(game);
          await tester.runAsync(() => _shot(game, 'ride_${id.name}_${tag}_3'));
        },
      );
    }
  }
}
