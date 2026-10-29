import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'golden_helpers.dart';

FlameTester<FlappySpikesGame> _tester(double height) {
  return FlameTester<FlappySpikesGame>(() {
    final game = createRunTestGame(
      worldHeight: height,
      clock: goldenClock,
      prefs: const {
        'gamesPlayed': 4,
        'bestScore': 42,
        'bestRunHoops': 1,
        'homeMode': 'freeFly',
        'firstSessionDone': true,
        'firstRunHintSeen': true,
      },
    )..reduceMotionOverride = true;
    game.runDebug.ignoreGates = false;
    return game;
  }, gameSize: Vector2(320, height));
}

Future<void> _ready(FlappySpikesGame game) async {
  await game.ready();
  await preloadImages(game);
  await flushAndMount(game);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadGoldenFonts();

  for (final height in [568.0, 711.0]) {
    _tester(height).testGameWidget(
      'beat-your-best marker at ${height.round()}',
      setUp: (game, _) => _ready(game),
      verify: (game, tester) async {
        final run = await startRun(game);
        await flyRun(game, maxSeconds: .7);
        run.state.camX = 320;
        run.spawner.update(0);
        final hoop = run.spawner.hoops.singleWhere(
          (hoop) => hoop.plan.index == 1,
        );
        run.state.camX = hoop.planeX - 200;
        run.spawner.update(0);
        run.layers.follow(run.state.camX, run.state.camY);
        run.bestLine!.update(0);
        final hud = RunHud.ensureFor(run);
        hud.rowOpacity = 1;
        run.debugFreeze();
        await flushAndMount(game);

        expect(run.bestLine, isNotNull);
        expect(run.bestLine!.flagText, 'BEST 42');
        expect(run.bestLine!.visible, isTrue);
        expect(run.bestLine!.screenX, closeTo(200, .001));
        expect(hud.bestChipVisible, isTrue);
        expect(hud.bestChipScore, 42);
        await expectGameGolden(
          tester,
          game,
          'goldens/beat_your_best_marker_${height.round()}.png',
        );
      },
    );

    _tester(height).testGameWidget(
      'NEW BEST moment at ${height.round()}',
      setUp: (game, _) => _ready(game),
      verify: (game, tester) async {
        final run = await startRun(game);
        await flyRun(game, maxSeconds: .7);
        run.state.camX = 320;
        run.spawner.update(0);
        final hoop = run.spawner.hoops.singleWhere(
          (hoop) => hoop.plan.index == 1,
        );
        run.state.camX = hoop.planeX - 200;
        run.spawner.update(0);
        run.layers.follow(run.state.camX, run.state.camY);
        final line = run.bestLine!..update(0);
        await flushAndMount(game);
        run.state.hoopsPassed = 3;
        run.state.score = 0;
        run.ctx.addScore(43);
        await flushAndMount(game);
        final hud = RunHud.ensureFor(run)..rowOpacity = 1;
        hud.bestBursts?.pool.clear();
        hud.updateTree(.75);
        line.update(.32);
        run.debugFreeze();
        await flushAndMount(game);

        expect(run.beatBestHoop, 3);
        expect(hud.bestSticker, isNotNull);
        expect(hud.bestSticker!.text, 'NEW BEST!');
        expect(hud.bestChipGold, isTrue);
        expect(hud.bestChipScore, 43);
        await expectGameGolden(
          tester,
          game,
          'goldens/beat_your_best_new_${height.round()}.png',
        );
      },
    );
  }
}
