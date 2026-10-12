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

import '../helpers.dart';

/// PRD-2.2 §18 screenshot check: the score circle and the streak banner
/// inside each ride scene (50 %, the scene's colours, behind the scene's
/// objects), the way-back crossfade above the wash, and the normal circle
/// at the glide start. Compare with `design/menu_v2/screen_portal_rides3.html`
/// (`rides89.js`) and `ride_<id>_1/2/3.png`. Writes PNGs to
/// `build/menu_shots/p22/s18/` (never committed).
const String outDir = 'build/menu_shots/p22/s18';

/// (moment name, phase, phase time).
typedef _Moment = (String, RidePhase, double);

const List<_Moment> _moments = [
  ('a_ride', RidePhase.ride, 4.0),
  ('b_exit', RidePhase.exit, .3),
  ('c_fly_mid', RidePhase.fly, .85),
  ('d_glide_start', RidePhase.glide, .02),
];

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
    for (final id in RideId.values) {
      if (h == 568 && id != RideId.sea && id != RideId.volcano) continue;
      for (final m in _moments) {
        final name = '${id.name}_${m.$1}_${h.round()}';
        FlameTester<FlappySpikesGame>(
          () => createRunTestGame(worldHeight: h, seed: 5),
          gameSize: Vector2(320, h),
        ).testGameWidget(
          '§18 $name',
          setUp: (game, _) async {
            await game.ready();
            await preloadImages(game);
          },
          verify: (game, tester) async {
            final run = await startRun(game, startHoopIndex: 25, ride: id);
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
            await tester.runAsync(() => _shot(game, 1.5, name));
          },
        );
      }
    }
  }
}
