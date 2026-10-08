import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/pickups/comet_star.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3a screenshot check (ARCH §7.1): real run frames of the comet boost —
/// the star hanging in its hoop, the boost after a few hoops (banner, ring
/// draining, streaks), a high tier near the end and the landing pop.
/// Compare with `design/menu_v2/boost_pickup.png`, `boost_active.png`,
/// `boost_tier.png` and `boost_landing.png` (§5.6). Writes PNGs to
/// `build/shots/run/comet/` (never committed); nothing is asserted beyond
/// "rendered".
const String outDir = 'build/shots/run/comet';

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

CometFeature _comet(RunController r) =>
    r.features.whereType<CometFeature>().single;

/// (name, stop condition).
final Map<String, bool Function(RunController r)> _moments = {
  // The star in its hoop, a little ahead of the bird.
  'pickup': (r) {
    final star = r.spawner.pickups.whereType<CometStar>().firstOrNull;
    return star != null && star.position.x - r.state.camX < 200;
  },
  // Mid-boost, clear of the banner lane (§5.6 `boost_active.png`).
  'active': (r) {
    final ride = _comet(r).ride;
    return ride != null && ride.t >= 2.5 && ride.y > 320 && ride.y < 420;
  },
  'tier': (r) => (_comet(r).ride?.t ?? 0) >= 8.1,
  'landing': (r) {
    final ride = _comet(r).ride;
    return ride != null && ride.done;
  },
};

void main() {
  setUpAll(_fonts);
  for (final h in [711.0, 568.0]) {
    for (final m in _moments.entries) {
      if (h == 568 && m.key != 'active') continue;
      final name = 'comet_${m.key}_${h.round()}';
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: h, seed: 5),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§5.6 $name',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, tester) async {
          final run = await startRun(
            game,
            startHoopIndex: ElementId.comet.firstPossible!,
            force: [ElementId.comet],
          );
          final bot = Autopilot(run);
          var frame = 0;
          while (frame++ < 60 * 40 && !m.value(run)) {
            if (bot.shouldFlap()) game.onScreenTap();
            game.update(1 / 60);
            if (frame % 10 == 0) await flushAndMount(game);
          }
          if (m.key == 'landing') {
            for (var i = 0; i < 3; i++) {
              game.update(1 / 60);
            }
          }
          await flushAndMount(game);
          run.debugFreeze();
          await tester.runAsync(() => _shot(game, 1.5, name));
        },
      );
    }
  }
}
