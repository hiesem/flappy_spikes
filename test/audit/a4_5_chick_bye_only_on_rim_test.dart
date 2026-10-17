// Audit A4-5 (2026-10-17): a shield / extra-life save made the chick fly off
// with "bye!"; SPEC WP-3e: only a rim touch scares it away, a save loses it
// silently (like a crash).
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/items/egg.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<void> _boot(FlappySpikesGame game) async {
  await game.ready();
  game.sound.enabled = false;
  await preloadImages(game);
}

void main() {
  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  );

  tester().testGameWidget(
    'A4-5 a shield save loses the chick silently: no bye pop, no eggBye',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final egg = run.features.whereType<EggFeature>().single;
      run.state.egg = EggState()..stage = EggStage.chick;
      run.state.shield = true;
      await flushAndMount(game);
      final sfx = sfxLog(game);
      final outcome = run.mistake(const Mistake(MistakeCause.spikes));
      expect(outcome, MistakeOutcome.saved);
      expect(run.state.egg, isNull, reason: 'the save loses the chick');
      expect(egg.view!.leaving, isFalse, reason: 'no "bye!" on a save');
      expect(sfx, isNot(contains(Sfx.eggBye.name)));
    },
  );

  tester().testGameWidget(
    'A4-5 a rim touch still scares the chick away with "bye!"',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final egg = run.features.whereType<EggFeature>().single;
      run.state.egg = EggState()..stage = EggStage.chick;
      await flushAndMount(game);
      run.events.emit(
        RimTouched(run.spawner.hoops.first, Vector2(160, 300), Vector2(0, 1)),
      );
      expect(run.state.egg, isNull);
      expect(egg.view!.leaving, isTrue);
    },
  );
}
