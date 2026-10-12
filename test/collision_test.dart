import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// The 1.0 collision tests ported to hoops (WP-1a, PRD-2 §3.1 / §3.0.4 /
/// §3.0.5): the plane crossing inside the opening scores exactly once, a
/// miss and a spike contact end the run exactly once (after the death
/// tumble), with one results panel and one game counted.
void main() {
  final withGame = FlameTester<FlappySpikesGame>(
    createTestGame,
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  /// Holds the bird level at [y] every frame.
  void Function(dynamic) hold(FlappySpikesGame game, double y) =>
      (_) => game.runBird!.setFlight(y: y, vy: 0);

  withGame.testGameWidget(
    '§3.1 crossing the plane inside the opening scores exactly once',
    setUp: (game, _) => boot(game),
    verify: (game, _) async {
      final run = await startRun(game);
      run.events.recordLog = true;
      final y = game.viewHeight / 2; // hoop 0 sits at the exact centre
      await flyRun(
        game,
        maxSeconds: 2.6,
        autopilot: false,
        onFrame: hold(game, y),
      );
      expect(game.state, GameState.playing);
      expect(run.events.log.whereType<HoopPassed>(), hasLength(1));
      // PRD-2.2 §13: a centred pass is perfect (streak 1): 2 points.
      expect(game.score, 2, reason: 'one hoop, one perfect pass');
      // Keep flying level well past the hoop: no second point from it.
      await flyRun(
        game,
        maxSeconds: 0.5,
        autopilot: false,
        onFrame: hold(game, y),
      );
      expect(game.score, 2, reason: 'a hoop never scores twice');
      expect(run.events.log.whereType<HoopMissed>(), isEmpty);
    },
  );

  withGame.testGameWidget(
    '§3.1 missing a hoop ends the run exactly once',
    setUp: (game, _) => boot(game),
    verify: (game, _) async {
      final run = await startRun(game);
      run.events.recordLog = true;
      // Above the first hoop (its top rim end is at 284 − 66 = 218).
      await flyRun(
        game,
        maxSeconds: 3,
        autopilot: false,
        onFrame: hold(game, 150),
      );
      expect(run.events.log.whereType<HoopMissed>(), hasLength(1));
      expect(game.state, GameState.dying, reason: '§3.0.5 the tumble first');
      stepGame(game, 2);
      await flushAndMount(game);
      expect(game.state, GameState.results);
      expect(game.world.children.query<ResultsScreen>(), hasLength(1));
      expect(game.storage.gamesPlayed, 1);
      expect(run.events.log.whereType<RunDied>(), hasLength(1));
      expect(
        run.events.log.whereType<RunDied>().single.mistake.cause,
        MistakeCause.missedHoop,
      );

      stepGame(game, 0.5);
      await flushAndMount(game);
      expect(game.world.children.query<ResultsScreen>(), hasLength(1));
      expect(game.storage.gamesPlayed, 1);
      expect(game.score, 0);
    },
  );

  withGame.testGameWidget(
    '§3.1 bird-spike contact ends the run exactly once',
    setUp: (game, _) => boot(game),
    verify: (game, _) async {
      final run = await startRun(game);
      run.events.recordLog = true;
      // Never flap again: the bird rises, then falls onto the floor spikes.
      stepGame(game, 1.5);
      expect(
        game.state,
        isNot(GameState.playing),
        reason: 'an unassisted bird must hit the floor spikes',
      );
      expect(
        run.events.log.whereType<RunDied>().single.mistake.cause,
        MistakeCause.spikes,
      );
      stepGame(game, 1.6);
      await flushAndMount(game);
      expect(game.state, GameState.results);
      expect(game.world.children.query<ResultsScreen>(), hasLength(1));
      expect(game.storage.gamesPlayed, 1);

      stepGame(game, 0.5);
      await flushAndMount(game);
      expect(game.world.children.query<ResultsScreen>(), hasLength(1));
      expect(game.storage.gamesPlayed, 1);
    },
  );
}
