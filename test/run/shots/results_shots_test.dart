import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-2e screenshot check (ARCH §7.1): the §5.10 results page at 568 and
/// 711 in the five approved states. Compare by eye with
/// `design/menu_v2/results_lv_{up,claim,after,newbest,lose}.png` (1.5 x of
/// 320 × 711). Writes PNGs to `build/shots/run/results/` (never committed).
const String outDir = 'build/shots/run/results';

Future<void> _fonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await Future.wait([lvdc.load(), opificio.load(), fredoka.load()]);
}

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
  const claimed6 = ['1', '2', '3', '4', '5', '6'];

  // (name, best before, claimed, score, coins, seconds on the page, claim)
  final states = <(String, int, List<String>, int, int, double, bool)>[
    ('up', 760, claimed6, 815, 65, 3.3, false),
    ('claim', 760, claimed6, 815, 65, 4.6, false),
    ('after', 760, claimed6, 815, 65, 4.3, true),
    ('newbest', 230, ['1', '2', '3', '4'], 262, 65, 3.4, false),
    ('lose', 640, claimed6, 310, 40, 2.5, false),
  ];

  for (final h in [568.0, 711.0]) {
    final tag = h.round();
    for (final st in states) {
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(
          worldHeight: h,
          prefs: {'bestScore': st.$2, 'claimedLevels': st.$3},
        ),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§5.10 results ${st.$1} at $tag',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, tester) async {
          await startRun(game);
          game.run!.ctx.addScore(st.$4);
          game.run!.ctx.earn(st.$5, CoinSource.hoop);
          killRun(game);
          await flushAndMount(game);
          final page = game.resultsScreen!;
          // Real frames mount what the page adds mid-sequence (the sticker,
          // confetti) on the next frame: flush every 0.1 s.
          Future<void> play(double seconds) async {
            for (var t = 0.0; t < seconds - 1e-9; t += .1) {
              stepGame(game, .1);
              await flushAndMount(game);
            }
          }

          if (st.$7) {
            await play(4.0);
            page.claimButton.button.onPressed();
            await flushAndMount(game);
          }
          await play(st.$6);
          await tester.runAsync(() => shot(game, 1.5, 'results_${st.$1}_$tag'));
        },
      );
    }
  }
}
