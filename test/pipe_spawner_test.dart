import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
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

  withGame.testGameWidget(
    'spawn timer fires every 1.5 s',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
      game.update(1 / 60);
      await game.ready(); // mount the first auto-spawned pair
    },
    verify: (game, tester) async {
      const dt = 1 / 60;

      // First pair spawns (almost) immediately when the game starts.
      expect(
        game.world.children.query<PipePair>(),
        isNotEmpty,
        reason: 'first pipe pair should spawn right after the game starts',
      );

      // Baseline: clear the world and start the clock. Pipes are removed as
      // soon as they spawn so they can never collide with the bird.
      for (final pipe in game.world.children.query<PipePair>()) {
        pipe.removeFromParent();
      }
      game.update(dt); // process the removal
      final spawnTimes = <double>[];
      final seen = <PipePair>{};
      var t = 0.0;
      while (t < 5.0) {
        game.update(dt);
        t += dt;
        // Let newly spawned pairs finish loading (their images are already
        // decoded, so a microtask flush is enough) so they become visible
        // to the children query on the next frame.
        await Future<void>.value();
        for (final pipe in game.world.children.query<PipePair>()) {
          if (seen.add(pipe)) {
            spawnTimes.add(t);
            pipe.removeFromParent();
          }
        }
        // Keep the bird alive so the spawner keeps running: flap whenever
        // it sinks too low (a fixed interval could climb into the ceiling).
        final birds = game.world.children.query<Bird>();
        if (game.state == GameState.playing &&
            birds.isNotEmpty &&
            birds.first.body.position.y > 320) {
          game.onScreenTap();
        }
      }

      expect(
        spawnTimes.length,
        greaterThanOrEqualTo(3),
        reason: 'expected several spawns over 5 s, got $spawnTimes',
      );
      for (var i = 1; i < spawnTimes.length; i++) {
        final interval = spawnTimes[i] - spawnTimes[i - 1];
        expect(
          interval,
          inInclusiveRange(
            Config.pipeSpawnInterval - 1e-6,
            Config.pipeSpawnInterval + 2 * dt,
          ),
          reason: 'spawn interval #$i was $interval s (SPEC: every 1.5 s)',
        );
      }
    },
  );

  withGame.testGameWidget(
    'pipes despawn after leaving the left edge of the screen',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
      game.update(1 / 60);
      await game.ready();

      // Controlled world: drop the auto-spawned pair, place one pair just
      // before the despawn line and one safely on screen.
      for (final pipe in game.world.children.query<PipePair>()) {
        pipe.removeFromParent();
      }
      game.update(1 / 60); // process removals
      await game.ready();

      final leaving = PipePair(gapBottomY: 200);
      await game.world.ensureAdd(leaving);
      await leaving.loaded;
      leaving.body.setTransform(Vector2(-80, Config.worldHeight / 2), 0);

      final staying = PipePair(gapBottomY: 200);
      await game.world.ensureAdd(staying);
      await staying.loaded;
      // Far enough right that it cannot drift into the (unflapped, falling)
      // bird during the short verify window and freeze the world early.
      staying.body.setTransform(Vector2(250, Config.worldHeight / 2), 0);
    },
    verify: (game, tester) async {
      expect(game.world.children.query<PipePair>(), hasLength(2));
      // The leaving pair starts 8 pt above its despawn threshold: at
      // 200 pt/s it crosses it after ~0.04 s of scrolling.
      stepGame(game, 0.3);
      final remaining = game.world.children.query<PipePair>();
      expect(remaining, hasLength(1), reason: 'off-screen pair must despawn');
      expect(
        remaining.single.body.position.x,
        greaterThan(-Config.pipeWidth),
        reason: 'the on-screen pair must survive',
      );
    },
  );

  withGame.testGameWidget(
    'pipe sprites align exactly with the physics gap',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      // No game start: the frozen start-state world is enough — this test
      // only checks sprite geometry, and a live game just adds races.
    },
    verify: (game, tester) async {
      const gapBottom = 300.0;
      const gap = 130.0; // arbitrary, not a ramp value, to prove `gap` is used
      final pipe = PipePair(gapBottomY: gapBottom, gap: gap);
      game.world.add(pipe);
      // Drive lifecycle events manually: deterministic under suite CPU
      // contention (awaiting mounted/loaded can starve and time out).
      await flushAndMount(game);
      expect(pipe.isLoaded, isTrue, reason: 'test pipe must finish loading');

      final sprites = pipe.children.whereType<SpriteComponent>().toList();
      expect(sprites, hasLength(2));
      final bottom = sprites[0];
      final top = sprites[1];

      // The body origin sits at worldHeight/2, so world y = local + 284.
      expect(
        bottom.position.y + Config.worldHeight / 2,
        closeTo(gapBottom, 1e-9),
        reason: 'bottom pipe top edge must sit at gapBottomY',
      );
      expect(
        top.position.y + Config.worldHeight / 2,
        closeTo(gapBottom - gap, 1e-9),
        reason: 'top pipe bottom edge must sit at gapBottomY - gap',
      );
      expect(top.anchor, Anchor.bottomLeft,
          reason: 'top pipe is anchored by its bottom-left corner');
      for (final sprite in sprites) {
        expect(sprite.size.x, Config.pipeWidth);
        expect(sprite.size.y, Config.pipeHeight);
      }
      pipe.removeFromParent();
    },
  );

  withGame.testGameWidget(
    'consecutive spawns stay within the max gap jump',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing; first pair spawns on frame 1
      game.update(1 / 60);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final bottoms = <double>[];
      const dt = 1 / 60;
      var t = 0.0;
      // Collect spawn positions for ~8 s; pipes are removed as they spawn so
      // they can never hit the bird.
      while (t < 8.0 && bottoms.length < 5) {
        game.update(dt);
        t += dt;
        await Future<void>.value();
        for (final pipe in game.world.children.query<PipePair>()) {
          bottoms.add(pipe.gapBottomY);
          pipe.removeFromParent();
        }
        final birds = game.world.children.query<Bird>();
        if (game.state == GameState.playing &&
            birds.isNotEmpty &&
            birds.first.body.position.y > 320) {
          game.onScreenTap();
        }
      }
      expect(bottoms.length, greaterThanOrEqualTo(4),
          reason: 'expected several spawns, got $bottoms');
      for (var i = 1; i < bottoms.length; i++) {
        final jump = (bottoms[i] - bottoms[i - 1]).abs();
        expect(
          jump,
          lessThanOrEqualTo(Config.maxGapJump + 1e-9),
          reason: 'gap jump ${bottoms[i - 1]} -> ${bottoms[i]} exceeds the max',
        );
      }
    },
  );

  withGame.testGameWidget(
    'spawned gap follows the score difficulty ramp',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing; first pair spawns on frame 1
      game.update(1 / 60);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      // Polls until a fresh pair spawns, reads its gap, then removes it
      // immediately so it can never collide with the bird.
      Future<double> nextSpawnedGap() async {
        const dt = 1 / 60;
        var t = 0.0;
        while (t < 2.5) {
          game.update(dt);
          t += dt;
          await Future<void>.value(); // let a newly spawned pair mount
          final pipes = game.world.children.query<PipePair>();
          if (pipes.isNotEmpty) {
            final gap = pipes.first.gap;
            for (final pipe in pipes) {
              pipe.removeFromParent();
            }
            game.update(0); // process the removals
            return gap;
          }
          // Keep the bird alive so the spawner keeps running.
          final birds = game.world.children.query<Bird>();
          if (game.state == GameState.playing &&
              birds.isNotEmpty &&
              birds.first.body.position.y > 320) {
            game.onScreenTap();
          }
        }
        fail('no pipe spawned within 2.5 s');
      }

      // Score 0: the pair spawned at game start uses the generous start gap.
      final initial = game.world.children.query<PipePair>();
      expect(initial, isNotEmpty, reason: 'first pair must spawn at start');
      expect(initial.first.gap, closeTo(Config.pipeGapStart, 1e-9));
      for (final pipe in initial) {
        pipe.removeFromParent();
      }
      game.update(0);

      // Mid-ramp: the next spawn must match gapForScore of the live score.
      game.score = 10;
      final midGap = await nextSpawnedGap();
      expect(midGap, closeTo(Config.gapForScore(10), 1e-9));
      expect(midGap, lessThan(Config.pipeGapStart));
      expect(midGap, greaterThan(Config.pipeGap));

      // Fully ramped: from difficultyRampScore on the gap is the final 105.
      game.score = Config.difficultyRampScore + 5;
      final maxGap = await nextSpawnedGap();
      expect(maxGap, closeTo(Config.pipeGap, 1e-9));
    },
  );
}
