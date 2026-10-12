import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/items/streak.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-2b screenshot check (ARCH §7.1): real run frames right after a
/// perfect pass at streak tiers 1, 2, 3, 5 and 10 — the banner (#7), the
/// "+2 coin" popup (#8), the small burst (#9), the gold bird (#5), the
/// trail (#10) and the ring field's tier look (#11). Compare with
/// `design/menu_v2/perfect_tier{1,2,3,5,10}.png` (§5.4; minus the rejected
/// big rotating burst / shock rings / flash) and `ringtier_{1,2,3}.png`
/// (§5.3). Writes PNGs to `build/shots/run/streak/` (never committed);
/// nothing is asserted beyond "rendered".
const String outDir = 'build/shots/run/streak';

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
    for (final (tier, after, trail) in [
      (1, .18, 'flame'),
      (2, .18, 'flame'),
      (3, .18, 'flame'),
      (3, .45, 'blocks'),
      (5, .18, 'flame'),
      (10, .18, 'flame'),
      (48, .18, 'flame'), // PRD-2.2 §29 the longest name
    ]) {
      final tag = '${trail == 'flame' ? '' : '${trail}_'}${h.round()}';
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: h),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§5.3 / §5.4 streak tier $tier ($trail trail) at ${h.round()}',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, tester) async {
          if (trail != 'flame') {
            final item = itemById(SkinLayer.trail, trail)!;
            game.storage.ownedItems.add(item.key);
            game.storage.equippedItems[SkinLayer.trail] = trail;
          }
          final run = await startRun(game);
          await flyRun(game, untilHoops: 1);
          while (run.state.streak < tier - 1) {
            run.debugPass(perfect: true);
          }
          if (run.state.streak < tier) {
            // One burst on screen, as in play (not one per catch-up pass).
            run.features.whereType<StreakFeature>().single.burstPool!.clear();
            run.debugPass(perfect: true);
          }
          // Mount the banner (its onLoad completes in a microtask, as
          // between real frames).
          await flushAndMount(game);
          await flyRun(game, maxSeconds: after);
          await flushAndMount(game);
          run.debugFreeze();
          await tester.runAsync(
            () => shot(game, 1.5, 'tier${tier}_$tag'),
          );
        },
      );
    }
  }
}
