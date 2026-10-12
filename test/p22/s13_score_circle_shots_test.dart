import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/score_hud.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../run/shots/streak_shots_test.dart' show shot;

/// PRD-2.2 §13.2 visual check: the score circle at 999, 1 000 and 12 345
/// points (shrink-to-fit from 4 digits). Writes PNGs to
/// `build/shots/run/streak/score_*.png` (never committed).
void main() {
  setUpAll(() async {
    final lvdc = FontLoader('LVDC Common2')
      ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
    final opificio = FontLoader('Opificio Neue')
      ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
    await Future.wait([lvdc.load(), opificio.load()]);
  });

  for (final v in [999, 1000, 12345]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      '§13.2 the score circle at $v points',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        final run = await startRun(game);
        await flyRun(game, maxSeconds: 1);
        await flushAndMount(game);
        run.ctx.addScore(v - run.state.score);
        final hud = game.world.children.whereType<ScoreHud>().single;
        for (var i = 0; i < 40; i++) {
          hud.update(1 / 60);
        }
        expect(hud.shownScore, v);
        run.debugFreeze();
        await tester.runAsync(() => shot(game, 1.5, 'score_$v'));
      },
    );
  }
}
