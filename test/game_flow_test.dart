import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
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
    'state machine: start -> playing -> results -> replay -> start',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, tester) async {
      expect(game.state, GameState.start);
      expect(game.world.children.query<HomeScreen>(), hasLength(1));
      expect(game.world.children.query<Bird>(), hasLength(1));

      // start -> playing, waiting (PRD-2.3 §10.1); the first tap flaps.
      game.onScreenTap();
      expect(game.state, GameState.playing);
      expect(game.run!.waiting, isTrue);
      game.onScreenTap();
      expect(game.run!.started, isTrue);
      final bird = game.world.children.query<Bird>().single;
      expect(
        bird.body.linearVelocity.y,
        closeTo(-Config.flapVelocity, 1e-6),
        reason: 'the first tap must start the game AND flap immediately',
      );

      // Taps while playing are flaps, not transitions.
      game.onScreenTap();
      expect(game.state, GameState.playing);

      // The home screen fades out and is then removed.
      stepGame(game, Config.uiFadeDuration + 0.2, flapBelow: 320);
      await flushAndMount(game);
      expect(game.world.children.query<HomeScreen>(), isEmpty);

      // playing -> dying (§3.0.5 tumble) -> gameOver.
      game.onBirdHit();
      expect(game.state, GameState.dying);
      killRun(game);
      expect(game.state, GameState.results);
      await flushAndMount(game);
      expect(game.world.children.query<ResultsScreen>(), hasLength(1));

      // Taps on empty areas are ignored on the game-over scene.
      game.onScreenTap();
      expect(game.state, GameState.results);

      // gameOver -> replay -> start (fresh home scene, old panel gone).
      game.replay();
      await flushAndMount(game);
      expect(game.state, GameState.start);
      expect(game.score, 0);
      expect(game.world.children.query<ResultsScreen>(), isEmpty);
      expect(game.world.children.query<HomeScreen>(), hasLength(1));
      expect(game.world.children.query<Bird>(), hasLength(1));
    },
  );

  final withPersistedGame = FlameTester<FlappySpikesGame>(
    () => createTestGame({'bestScore': 3, 'gamesPlayed': 7}),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  withPersistedGame.testGameWidget(
    'full loop: START -> flap -> collision -> game over -> replay',
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

      // --- a tap on an empty area does NOT start (PRD-1 §4.2) ---------------
      await flushAndMount(game);
      final rect = tester.getRect(find.byGame<FlappySpikesGame>());
      Offset screenOf(Vector2 world) {
        final p = game.camera.localToGlobal(world);
        return rect.topLeft + Offset(p.x, p.y);
      }

      // Right of the START button, between the title and the tiles.
      await tester.tapAt(screenOf(Vector2(300, 240)));
      // Advance past the MultiTapGestureRecognizer's 40 ms countdown so no
      // fake-async timer is left pending at teardown.
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.state, GameState.start);

      // --- the START button starts the game ---------------------------------
      final start = Config.homeStartRectFor(game.viewHeight);
      await tester.tapAt(screenOf(start.center.toVector2()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.state, GameState.playing);
      // PRD-2.3 §10.1 the run waits for the first playfield tap.
      game.onPlayfieldTap();

      // --- simulate ~1 s of flapping ---------------------------------------
      stepGame(game, 1.0, flapBelow: 320);
      await flushAndMount(game);
      expect(game.state, GameState.playing);
      expect(hoopsOf(game), isNotEmpty);

      // --- force a collision: teleport the bird onto the floor spikes -------
      final bird = game.world.children.query<Bird>().single;
      bird.body.setTransform(
        Vector2(Config.birdX, game.viewHeight - Config.spikeHeight),
        0,
      );
      stepGame(game, 1 / 60);
      expect(game.state, GameState.dying, reason: '§3.0.5 the tumble first');
      // The results come after the tumble (≤ 1.5 s).
      stepGame(game, 1.6);
      expect(game.state, GameState.results);

      // --- game-over panel appears and builds fully ------------------------
      await flushAndMount(game);
      expect(game.world.children.query<ResultsScreen>(), hasLength(1));
      expect(game.storage.gamesPlayed, 8,
          reason: 'gamesPlayed must increment on each game over');
      expect(game.storage.bestScore, 3,
          reason: 'score 0 must not beat the stored best of 3');

      // PRD-2 §5.10: the results page fades in, then takes input.
      final panel = game.world.children.query<ResultsScreen>().single;
      expect(panel.canContinue, isFalse);
      stepGame(game, ResultsConfig.pageFadeIn + 0.1);
      expect(panel.opacity, 1, reason: 'the page must fade in completely');
      expect(panel.canContinue, isTrue);

      // --- replay resets to the start state --------------------------------
      game.replay();
      await flushAndMount(game);
      expect(game.state, GameState.start);
      expect(game.score, 0);
      expect(game.world.children.query<ResultsScreen>(), isEmpty);
      expect(hoopsOf(game), isEmpty);

      final newHome = game.world.children.query<HomeScreen>().single;
      final newBird = game.world.children.query<Bird>().single;
      expect(identical(newBird, bird), isFalse,
          reason: 'replay must reset the scene with a fresh bird');
      expect(newBird.body.position.y, closeTo(Config.birdY, 1e-6));
      // PRD-home-v3 §3.1: BEST / LAST read the persisted best and the
      // last run's score (games played moved to the LEVELS header).
      expect(newHome.bestStat.value, '3');
      expect(game.storage.gamesPlayed, 8);

      // The world is frozen again: no gravity on the fresh bird.
      stepGame(game, 0.5);
      expect(newBird.body.position.y, closeTo(Config.birdY, 1e-6));
      expect(game.state, GameState.start);
    },
  );
}
