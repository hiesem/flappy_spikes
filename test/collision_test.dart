import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/gameover_panel.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final withGame = FlameTester<FlappySpikesGame>(
    createTestGame,
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  /// Starts the game and lets the first auto-spawned pipe pair fully load
  /// (setUp runs inside runAsync, so real image decodes complete here).
  Future<void> startPlaying(FlappySpikesGame game) async {
    game.sound.enabled = false;
    await preloadImages(game);
    game.onScreenTap(); // start -> playing
    game.update(1 / 60); // let the spawner fire
    await game.ready(); // mount everything that is pending
  }

  /// Removes every pipe pair from the world.
  Future<void> clearPipes(FlappySpikesGame game) async {
    for (final pipe in game.world.children.query<PipePair>()) {
      pipe.removeFromParent();
    }
    game.update(1 / 60); // process removals (no new spawn yet: timer reset)
    await game.ready();
  }

  withGame.testGameWidget(
    'score sensor contact increments the score exactly once per pair',
    setUp: (game, tester) async {
      await game.ready();
      await startPlaying(game);
      await clearPipes(game);

      // Gap vertically centered on the bird so only the sensor touches it.
      final pipe = PipePair(gapBottomY: Config.birdY + Config.pipeGap / 2);
      await game.world.ensureAdd(pipe);
      await pipe.loaded;
      // Sensor (111 pt right of center, 10 pt wide) overlaps the bird's
      // right edge; the pipe bodies are far left of the bird.
      pipe.body.setTransform(Vector2(-20, Config.worldHeight / 2), 0);
    },
    verify: (game, tester) async {
      stepGame(game, 1 / 60); // one frame: sensor contact begins
      expect(game.score, 1, reason: 'sensor contact must score one point');

      // Keep flying through and past the sensor: no further increments from
      // the same pair.
      game.onScreenTap(); // flap to hold altitude inside the gap
      stepGame(game, 0.25);
      expect(game.score, 1, reason: 'a pair must never score twice');
      expect(game.state, GameState.playing,
          reason: 'sensor contact must not kill the bird');
    },
  );

  withGame.testGameWidget(
    'bird-pipe contact triggers game over exactly once',
    setUp: (game, tester) async {
      await game.ready();
      await startPlaying(game);
      await clearPipes(game);

      // Gap high above the bird: the bottom pipe overlaps the bird.
      final pipe = PipePair(gapBottomY: 150);
      await game.world.ensureAdd(pipe);
      await pipe.loaded;
      pipe.body.setTransform(Vector2(Config.birdX, Config.worldHeight / 2), 0);
    },
    verify: (game, tester) async {
      stepGame(game, 1 / 60); // one frame: contact begins
      expect(game.state, GameState.gameOver);
      await flushAndMount(game); // let the game-over panel finish mounting
      expect(
        game.world.children.query<GameOverPanel>(),
        hasLength(1),
        reason: 'exactly one game-over panel must be built',
      );
      expect(game.storage.gamesPlayed, 1);

      // Further contact events / frames must not fire game over again.
      stepGame(game, 0.5);
      await flushAndMount(game);
      expect(game.state, GameState.gameOver);
      expect(game.world.children.query<GameOverPanel>(), hasLength(1));
      expect(game.storage.gamesPlayed, 1);
      expect(game.score, 0, reason: 'bird never reached the score sensor');
    },
  );

  withGame.testGameWidget(
    'bird-spike contact triggers game over exactly once',
    setUp: (game, tester) async {
      await game.ready();
      await startPlaying(game);
    },
    verify: (game, tester) async {
      // Never flap again: the bird rises, then falls onto the ground spikes.
      stepGame(game, 1.5);
      expect(game.state, GameState.gameOver,
          reason: 'an unassisted bird must hit the ground spikes');
      await flushAndMount(game);
      expect(game.world.children.query<GameOverPanel>(), hasLength(1));
      expect(game.storage.gamesPlayed, 1);

      stepGame(game, 0.5);
      await flushAndMount(game);
      expect(game.world.children.query<GameOverPanel>(), hasLength(1));
      expect(game.storage.gamesPlayed, 1);
    },
  );
}
