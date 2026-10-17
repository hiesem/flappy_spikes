import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-5b screenshot check (ARCH §7.1): the §5.8 VS intro (spin / lock / VS
/// hold), the §5.7 versus bar (opponent scoring, opponent out) and the
/// §5.10 versus results (WIN / LOSE / DRAW) at 568 and 711. Compare by eye
/// with `design/menu_v2/versus_lv_{spin,lock,vs}.png`,
/// `game_versus_g1.png` and `results_lv_{up,lose}.png` (480 wide = 1.5×).
/// Writes PNGs to `build/shots/run/versus/` (never committed).
const String outDir = 'build/shots/run/versus';

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

OpponentRun rival({
  String name = 'Pond',
  int score = 3,
  int best = 820,
  double end = 60,
  Look look = const Look(bird: 'sky', hat: 'crown'),
}) {
  final t = RunTimeline();
  for (var i = 1; i <= score; i++) {
    t.addPoint(i * .4);
  }
  t.end(score * .4 + end);
  return OpponentRun(
    uid: 'u-$name',
    name: name,
    score: score,
    best: best,
    level: 6,
    look: look,
    timeline: t,
    runId: 'r-$name',
  );
}

void main() {
  setUpAll(_fonts);

  void hold(FlappySpikesGame g, double seconds, double y) {
    for (var t = 0.0; t < seconds; t += 1 / 60) {
      if (g.state == GameState.playing) g.runBird!.setFlight(y: y, vy: 0);
      g.update(1 / 60);
    }
  }

  for (final h in [568.0, 711.0]) {
    final tag = h.round();

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: h,
        prefs: const {'bestScore': 700, 'playerLevel': 6},
        versus: FakeVersusService(pool: [rival()]),
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.8 VS intro: spin / lock / VS at $tag',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (game, tester) async {
        game.onScreenTap();
        await flushAndMount(game);
        final intro = game.versusIntro!;
        for (var i = 0; i < 150; i++) {
          game.update(1 / 60);
        }
        await flushAndMount(game);
        intro.debugFreeze(2.6);
        await tester.runAsync(() => shot(game, 1.5, 'vs_spin_$tag'));
        intro.unfreeze();
        intro.debugFreeze(intro.lockAt + .4);
        await tester.runAsync(() => shot(game, 1.5, 'vs_lock_$tag'));
        intro.unfreeze();
        intro.debugFreeze(intro.vsAt + 1.1);
        await tester.runAsync(() => shot(game, 1.5, 'vs_hold_$tag'));
        intro.unfreeze();
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: h,
        versus: FakeVersusService(
          pool: [rival(name: 'Molly', score: 4, end: .5)],
        ),
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.7 versus bar: scoring and out at $tag',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (game, tester) async {
        final run = await startRun(game);
        hold(game, 1.25, h / 2 + 40);
        run.debugPass(perfect: true);
        await flushAndMount(game);
        await tester.runAsync(() => shot(game, 1.5, 'hud_versus_$tag'));
        hold(game, 1.2, h / 2 + 40);
        expect(game.runHud!.versus!.out, isTrue);
        await tester.runAsync(() => shot(game, 1.5, 'hud_versus_out_$tag'));
      },
    );

    for (final (name, mine, theirs, before) in [
      ('win', 58, 41, 46),
      ('lose', 310, 455, 640),
      ('draw', 12, 12, 30),
    ]) {
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(
          worldHeight: h,
          prefs: {'bestScore': before},
          versus: FakeVersusService(
            pool: [rival(name: 'Molly', score: theirs, best: 700)],
          ),
        ),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§5.10 versus results: $name at $tag',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
        },
        verify: (game, tester) async {
          final run = await startRun(game);
          run.state.score = mine - 1;
          run.debugPass(perfect: true);
          run.state.invulnerable = 0;
          killRun(game);
          await flushAndMount(game);
          await declineRevive(game);
          for (var i = 0; i < 30 && game.resultsScreen == null; i++) {
            game.update(1 / 60);
            await flushAndMount(game);
          }
          // Mid-sequence parts (NEW BEST) mount on the next frame: flush
          // every 0.1 s, as results_shots_test does.
          for (var i = 0; i < 17; i++) {
            stepGame(game, .1);
            await flushAndMount(game);
          }
          await tester.runAsync(() => shot(game, 1.5, 'results_${name}_$tag'));
        },
      );
    }
  }
}
