// Audit A2-1 (2026-10-17): the rainbow / echo / prism / paint trails keep a
// path history that only moves while emitting; after a streak break or a
// death it stayed on screen as a frozen stripe behind the bird. Switching
// the trail off now drops the path (live particles still fade out), as the
// shop preview does. (The hidden-bird case is Audit HIDE's: kept.)
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/items/streak.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  );

  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  /// [frames] frames with the autopilot flapping (the bird stays alive).
  Future<void> step(FlappySpikesGame g, int frames) async {
    await flyUntil(g, (_) => false, maxSeconds: frames / 60 - 1e-6);
  }

  for (final id in ['rainbow', 'echo', 'prism', 'paint']) {
    tester().testGameWidget(
      'A2-1 $id: a streak break drops the path (no frozen stripe)',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game);
        await flyUntil(game, (r) => r.state.hoopsPassed >= 1);
        final streak = run.features.whereType<StreakFeature>().single;
        final trail = streak.trail!..trailId = id;
        run.state.streak = 5;
        await step(game, 30);
        expect(streak.trailActive, isTrue);
        expect(trail.emitter.pathLength, greaterThan(1));
        run.state.streak = 0;
        await step(game, 1);
        expect(streak.trailActive, isFalse);
        expect(trail.emitter.pathLength, 0, reason: 'no frozen stripe');
        await step(game, 30);
        expect(trail.emitter.pathLength, 0);
        // Back on: a fresh path from the bird.
        run.state.streak = 5;
        await step(game, 5);
        expect(trail.emitter.pathLength, greaterThan(0));
      },
    );
  }

  tester().testGameWidget(
    'A2-1 a death drops the trail path',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      await flyUntil(game, (r) => r.state.hoopsPassed >= 1);
      final streak = run.features.whereType<StreakFeature>().single;
      final trail = streak.trail!..trailId = 'rainbow';
      run.state.streak = 5;
      await step(game, 30);
      expect(trail.emitter.pathLength, greaterThan(1));
      run.mistake(const Mistake(MistakeCause.spikes));
      expect(run.dying, isTrue);
      game.update(1 / 60);
      expect(trail.emitter.pathLength, 0, reason: 'no frozen stripe');
    },
  );
}
