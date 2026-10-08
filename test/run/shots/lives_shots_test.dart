import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/heart_pickup.dart';
import 'package:flappy_spikes/run/pickups/shield_pickup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-2a screenshot check (ARCH §7.1): hearts / extra life / shield / Big
/// Hoops in a run frame at 568 and 711. Compare by eye with
/// `design/menu_v2/hoops_m0_big.png` (§5.1 Big Hoops), `screen_hearts_v2`
/// state 1b (§5.2 heart pickup) and `screen_shield3.html` (§5.5 badge,
/// circle, hit). Writes PNGs to `build/shots/run/lives/` (never committed).
const String outDir = 'build/shots/run/lives';

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
    final tag = h.round();

    void hold(FlappySpikesGame g, double seconds, double y) {
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        g.runBird!.setFlight(y: y, vy: 0);
        g.update(1 / 60);
      }
    }

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.1 / §5.2 / §5.5 Big Hoops, heart pickup, extra-life badge at $tag',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        final run = await startRun(game, starter: Powerup.bigHoops);
        final y = h / 2 + 110;
        hold(game, .6, y);
        // §5.2 a heart pickup ahead of the bird (mid-gap, on screen).
        final s = run.state;
        run.layers.items.add(
          HeartPickup(
            GapItemPlan(
              kind: ElementId.heart,
              trackX: s.camX + 175,
              y: y - 150,
            ),
          ),
        );
        run.state.extraLife = true;
        hold(game, .8, y);
        await flushAndMount(game);
        await tester.runAsync(() => shot(game, 1.5, 'big_heart_badge_$tag'));
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.5 shield circle, shield pickup and the hit at $tag',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        final run = await startRun(game, starter: Powerup.shield);
        final y = h / 2;
        final s = run.state;
        run.layers.items.add(
          ShieldPickup(
            GapItemPlan(
              kind: ElementId.shield,
              trackX: s.camX + 230,
              y: y - 120,
            ),
          ),
        );
        hold(game, .9, y);
        await flushAndMount(game);
        await tester.runAsync(() => shot(game, 1.5, 'shield_circle_$tag'));
        run.mistake(const Mistake(MistakeCause.missedHoop));
        hold(game, .12, y);
        await tester.runAsync(() => shot(game, 1.5, 'shield_hit_$tag'));
        run.state.extraLife = true;
        hold(game, 2.2, y);
        run.mistake(const Mistake(MistakeCause.spikes));
        hold(game, .15, y);
        await tester.runAsync(() => shot(game, 1.5, 'extra_life_pop_$tag'));
      },
    );
  }
}
