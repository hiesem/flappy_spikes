import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/coin_frenzy.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/pickups/capsule.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3f screenshot check (ARCH §7.1): real run frames of the powerup
/// capsules — a capsule ahead of the bird, and each powerup running (timer
/// pill, Hourglass vignette / ghosts / clock ring, Mini Bird, Coin Frenzy
/// coin rings / border / +5). Compare with `design/menu_v2/lab_slow2.png`,
/// `lab_mini2.png` and `lab_frenzy.png` (§5.29–§5.31). Writes PNGs to
/// `build/shots/run/capsules/` (never committed); nothing is asserted
/// beyond "rendered".
const String outDir = 'build/shots/run/capsules';

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

double _elapsed(RunController r, TimedPowerup t) {
  final s = r.state.timed;
  if (s == null || s.type != t) return -1;
  return s.duration - s.remaining;
}

/// (name, forced capsule, stop condition).
final List<(String, ElementId, bool Function(RunController r))> _moments = [
  (
    'capsule',
    ElementId.hourglass,
    (r) {
      final p = r.spawner.pickups.whereType<CapsulePickup>().firstOrNull;
      return p != null && p.position.x - r.state.camX < 210;
    },
  ),
  (
    'mini_capsule',
    ElementId.miniBird,
    (r) {
      final p = r.spawner.pickups.whereType<CapsulePickup>().firstOrNull;
      return p != null && p.position.x - r.state.camX < 210;
    },
  ),
  (
    'hourglass',
    ElementId.hourglass,
    (r) => _elapsed(r, TimedPowerup.hourglass) >= 3,
  ),
  ('mini', ElementId.miniBird, (r) => _elapsed(r, TimedPowerup.mini) >= 2.5),
  (
    'frenzy',
    ElementId.coinFrenzy,
    (r) =>
        _elapsed(r, TimedPowerup.frenzy) >= 1 &&
        r.features.whereType<CoinFrenzyFeature>().single.paid > 0 &&
        r.spawner.hoops.any(
          (h) => !h.resolved && h.position.x - r.state.camX < 250,
        ),
  ),
];

void main() {
  setUpAll(_fonts);
  for (final h in [711.0, 568.0]) {
    for (final m in _moments) {
      if (h == 568 && m.$1 != 'hourglass') continue;
      final name = 'capsule_${m.$1}_${h.round()}';
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: h, seed: 5),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§5.29–§5.31 $name',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, tester) async {
          final run = await startRun(
            game,
            startHoopIndex: ElementId.capsule.firstPossible!,
            force: [m.$2],
          );
          final bot = Autopilot(run);
          var frame = 0;
          while (frame++ < 60 * 60 && !m.$3(run)) {
            // Fly into the capsule (the run start), then the bot.
            final cap = run.spawner.pickups
                .whereType<CapsulePickup>()
                .where((p) => !p.collected)
                .firstOrNull;
            final bird = game.runBird!;
            if (run.state.timed == null &&
                cap != null &&
                !m.$1.contains('capsule') &&
                cap.position.x - run.state.camX < 160) {
              if (bird.body.position.y > cap.position.y + 4 &&
                  bird.body.linearVelocity.y > -40) {
                game.onScreenTap();
              }
            } else if (bot.shouldFlap()) {
              game.onScreenTap();
            }
            game.update(1 / 60);
            if (frame % 10 == 0) await flushAndMount(game);
            if (run.state.timed == null &&
                !run.director.forcedQueue.contains(m.$2) &&
                !m.$1.contains('capsule')) {
              run.debugForce(m.$2);
            }
          }
          expect(m.$3(run), isTrue, reason: 'moment ${m.$1} reached');
          expect(CapsuleType.values, isNotEmpty);
          await flushAndMount(game);
          run.debugFreeze();
          await tester.runAsync(() => _shot(game, 1.5, name));
        },
      );
    }
  }
}
