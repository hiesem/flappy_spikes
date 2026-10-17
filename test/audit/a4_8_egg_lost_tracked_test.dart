// Audit A4-8 (2026-10-17): an unhatched egg lost to a crash or to a
// shield / extra-life save sent no analytics event (ARCH §25 names
// `egg_lost`). It now tracks `egg_lost {cause: crash | save}`.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, seed: 5, services: spy);
  }, gameSize: Vector2(320, 711));

  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  List<Map<String, Object>?> lost() =>
      spy.events.where((e) => e.$1 == 'egg_lost').map((e) => e.$2).toList();

  tester().testGameWidget(
    'A4-8 an egg lost to a shield save tracks egg_lost {cause: save}',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      run.state.egg = EggState()..cracks = 2;
      run.state.shield = true;
      expect(
        run.mistake(const Mistake(MistakeCause.spikes)),
        MistakeOutcome.saved,
      );
      expect(run.state.egg, isNull);
      expect(lost(), [
        {'cause': 'save'},
      ]);
      expect(spy.events.map((e) => e.$1), isNot(contains('chick_lost')));
    },
  );

  tester().testGameWidget(
    'A4-8 an egg lost to a crash tracks egg_lost {cause: crash}',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      run.state.egg = EggState();
      expect(
        run.mistake(const Mistake(MistakeCause.spikes)),
        MistakeOutcome.died,
      );
      expect(lost(), [
        {'cause': 'crash'},
      ]);
    },
  );

  tester().testGameWidget(
    'A4-8 a lost chick sends chick_lost, not egg_lost',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      run.state.egg = EggState()..stage = EggStage.chick;
      run.mistake(const Mistake(MistakeCause.spikes));
      expect(lost(), isEmpty);
      expect(spy.events.map((e) => e.$1), contains('chick_lost'));
    },
  );
}
