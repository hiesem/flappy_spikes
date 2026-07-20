import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/gameover_panel.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/components/start_panel.dart';
import 'package:flappy_spikes/components/ui/sprite_button.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final withGame = FlameTester<FlappySpikesGame>(
    createTestGame,
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  withGame.testGameWidget(
    'state machine: start -> playing -> gameOver -> replay -> start',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, tester) async {
      expect(game.state, GameState.start);
      expect(game.world.children.query<StartPanel>(), hasLength(1));
      expect(game.world.children.query<Bird>(), hasLength(1));

      // start -> playing (+ immediate flap).
      game.onScreenTap();
      expect(game.state, GameState.playing);
      final bird = game.world.children.query<Bird>().single;
      expect(
        bird.body.linearVelocity.y,
        closeTo(-Config.flapVelocity, 1e-6),
        reason: 'the first tap must start the game AND flap immediately',
      );

      // Taps while playing are flaps, not transitions.
      game.onScreenTap();
      expect(game.state, GameState.playing);

      // The start panel fades out over 0.5 s and is then removed.
      stepGame(game, 0.7, flapBelow: 320);
      await flushAndMount(game);
      expect(game.world.children.query<StartPanel>(), isEmpty);

      // playing -> gameOver.
      game.onBirdHit();
      expect(game.state, GameState.gameOver);
      await flushAndMount(game);
      expect(game.world.children.query<GameOverPanel>(), hasLength(1));

      // Taps on empty areas are ignored on the game-over scene.
      game.onScreenTap();
      expect(game.state, GameState.gameOver);

      // gameOver -> replay -> start (fresh scene, old panel gone).
      game.replay();
      await flushAndMount(game);
      expect(game.state, GameState.start);
      expect(game.score, 0);
      expect(game.world.children.query<GameOverPanel>(), isEmpty);
      expect(game.world.children.query<StartPanel>(), hasLength(1));
      expect(game.world.children.query<Bird>(), hasLength(1));
    },
  );

  final withPersistedGame = FlameTester<FlappySpikesGame>(
    () => createTestGame({'bestScore': 3, 'gamesPlayed': 7}),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  withPersistedGame.testGameWidget(
    'full loop: tap to play -> flap -> collision -> game over -> replay',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, tester) async {
      // --- start scene -----------------------------------------------------
      expect(game.state, GameState.start);
      expect(game.storage.bestScore, 3);
      expect(game.storage.gamesPlayed, 7);

      // --- tap on empty area starts the game -------------------------------
      final rect = tester.getRect(find.byGame<FlappySpikesGame>());
      await tester.tapAt(Offset(rect.center.dx, rect.top + 30));
      // Advance past the MultiTapGestureRecognizer's 40 ms countdown so no
      // fake-async timer is left pending at teardown.
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.state, GameState.playing);

      // --- simulate ~1 s of flapping ---------------------------------------
      stepGame(game, 1.0, flapBelow: 320);
      await flushAndMount(game);
      expect(game.state, GameState.playing);
      expect(game.world.children.query<PipePair>(), isNotEmpty);

      // --- force a collision: teleport the bird into a pipe ----------------
      final pipe = game.world.children.query<PipePair>().first;
      final bird = game.world.children.query<Bird>().single;
      bird.body.setTransform(
        Vector2(pipe.body.position.x, pipe.gapBottomY + 50),
        0,
      );
      // The broadphase pair is created on the first step after the
      // teleport and the contact fires on the next one.
      stepGame(game, 0.2);
      expect(game.state, GameState.gameOver);

      // --- game-over panel appears and builds fully ------------------------
      await flushAndMount(game);
      expect(game.world.children.query<GameOverPanel>(), hasLength(1));
      expect(game.storage.gamesPlayed, 8,
          reason: 'gamesPlayed must increment on each game over');
      expect(game.storage.bestScore, 3,
          reason: 'score 0 must not beat the stored best of 3');

      stepGame(game, 1.0); // staggered fade-in: 0.5 + 2 * 0.2 = 0.9 s
      final panel = game.world.children.query<GameOverPanel>().single;
      for (final button in panel.children.whereType<SpriteButton>()) {
        expect(button.opacity, 1,
            reason: 'panel buttons must fade in completely');
      }

      // --- replay resets to the start state --------------------------------
      game.replay();
      await flushAndMount(game);
      expect(game.state, GameState.start);
      expect(game.score, 0);
      expect(game.world.children.query<GameOverPanel>(), isEmpty);
      expect(game.world.children.query<PipePair>(), isEmpty);

      final newPanel = game.world.children.query<StartPanel>().single;
      final newBird = game.world.children.query<Bird>().single;
      expect(identical(newBird, bird), isFalse,
          reason: 'replay must reset the scene with a fresh bird');
      expect(newBird.body.position.y, closeTo(Config.birdY, 1e-6));
      expect(newPanel.bestScore, 3);
      expect(newPanel.gamesPlayed, 8);

      // The world is frozen again: no gravity on the fresh bird.
      stepGame(game, 0.5);
      expect(newBird.body.position.y, closeTo(Config.birdY, 1e-6));
      expect(game.state, GameState.start);
    },
  );
}
