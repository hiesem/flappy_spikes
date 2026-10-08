import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3b screenshot check (ARCH §7.1): real run frames of every portal ride
/// at three moments — in the ride (after a few rings, streak ≈ 8 with its
/// banner), the exit moment and the way back. Compare with
/// `design/menu_v2/ride_<id>_1/2/3.png` (§5.12b) and `portal_2/4/6.png`
/// (cannon). Writes PNGs to `build/shots/run/rides/` (never committed);
/// nothing is asserted beyond "rendered".
const String outDir = 'build/shots/run/rides';

/// (moment name, phase, phase time).
typedef _Moment = (String, RidePhase, double);

const Map<RideId, List<_Moment>> _moments = {
  RideId.cannon: [
    ('1', RidePhase.ride, 3.5),
    ('2', RidePhase.exit, .7),
    ('3', RidePhase.glide, .9),
  ],
  RideId.space: [
    ('1', RidePhase.ride, 3.5),
    ('2', RidePhase.exit, 1.0),
    ('3', RidePhase.fly, .95),
  ],
  RideId.volcano: [
    ('1', RidePhase.ride, 3.5),
    ('2', RidePhase.fly, .3),
    ('3', RidePhase.glide, .5),
  ],
  RideId.sea: [
    ('1', RidePhase.ride, 3.5),
    ('2', RidePhase.fly, .12),
    ('3', RidePhase.glide, .5),
  ],
  RideId.pinball: [
    ('1', RidePhase.ride, 3.5),
    ('2', RidePhase.exit, 1.15),
    ('3', RidePhase.fly, 1.3),
  ],
  RideId.storm: [
    ('1', RidePhase.ride, 3.5),
    ('2', RidePhase.exit, .3),
    ('3', RidePhase.glide, .25),
  ],
};

Future<void> _fonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await Future.wait([lvdc.load(), opificio.load(), fredoka.load()]);
}

/// Same render path as `captureShot` (menu_screenshot_test.dart): resize
/// right before rendering (the harness reverts earlier resizes).
Future<void> _shot(FlappySpikesGame game, double scale, String name) async {
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

double _clock(PortalRide r) => switch (r.phase) {
  RidePhase.ride => r.view.rt,
  RidePhase.exit => r.view.et,
  RidePhase.fly => r.view.ft,
  RidePhase.glide => r.view.gt,
  RidePhase.done => 0,
};

void main() {
  setUpAll(_fonts);
  for (final h in [711.0, 568.0]) {
    for (final e in _moments.entries) {
      if (h == 568 && e.key != RideId.cannon && e.key != RideId.pinball) {
        continue;
      }
      for (final m in e.value) {
        final name = 'ride_${e.key.name}_${m.$1}_${h.round()}';
        FlameTester<FlappySpikesGame>(
          () => createRunTestGame(worldHeight: h, seed: 5),
          gameSize: Vector2(320, h),
        ).testGameWidget(
          '§5.12b $name',
          setUp: (game, _) async {
            await game.ready();
            await preloadImages(game);
          },
          verify: (game, tester) async {
            final run = await startRun(game, startHoopIndex: 25, ride: e.key);
            for (var i = 0; i < 3; i++) {
              run.debugPass(perfect: true);
            }
            final f = run.features.whereType<PortalRideFeature>().single;
            final bot = Autopilot(run);
            var frame = 0;
            while (frame++ < 60 * 40) {
              final r = f.ride;
              if (r == null && bot.shouldFlap()) game.onScreenTap();
              if (r != null &&
                  r.phase.index >= m.$2.index &&
                  (r.phase != m.$2 || _clock(r) >= m.$3)) {
                break;
              }
              game.update(1 / 60);
              if (frame % 10 == 0) await flushAndMount(game);
            }
            await flushAndMount(game);
            run.debugFreeze();
            await tester.runAsync(
              () => _shot(game, 1.5, name),
            );
          },
        );
      }
    }
  }
}
