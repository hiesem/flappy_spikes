import 'package:flame/extensions.dart';
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

  Bird bird(FlappySpikesGame game) =>
      game.world.children.query<Bird>().single;

  withGame.testGameWidget(
    'flap zeroes the velocity before applying the upward impulse',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
    },
    verify: (game, tester) async {
      final b = bird(game);
      // Give the bird a strong downward velocity, then flap.
      b.body.linearVelocity.setValues(0, 800);
      b.flap();
      // If the velocity had not been zeroed first, the resulting velocity
      // would be 800 - flapVelocity instead of exactly -flapVelocity.
      expect(b.body.linearVelocity.y, closeTo(-Config.flapVelocity, 1e-6));
      expect(b.body.linearVelocity.x, closeTo(0, 1e-9));
    },
  );

  withGame.testGameWidget(
    'flap is ignored unless the game is playing',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, tester) async {
      final b = bird(game);
      b.flap(); // state == start: must do nothing
      expect(b.body.linearVelocity.y, closeTo(0, 1e-9));
    },
  );

  withGame.testGameWidget(
    'CALIBRATION: a single flap from rest rises 45-65 pt before falling',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing (performs the first flap)
    },
    verify: (game, tester) async {
      final b = bird(game);
      final startY = b.body.position.y;
      expect(startY, closeTo(Config.birdY, 2));

      // Step at 60 fps and track the apex until the bird is clearly falling.
      var minY = startY;
      var fellAfterApex = 0.0;
      var t = 0.0;
      const dt = 1 / 60;
      while (t < 2.0 && fellAfterApex < 0.5) {
        game.update(dt);
        t += dt;
        final y = b.body.position.y;
        if (y < minY) {
          minY = y;
          fellAfterApex = 0;
        } else {
          fellAfterApex += dt;
        }
      }

      final rise = startY - minY;
      expect(
        rise,
        inInclusiveRange(45, 65),
        reason: 'flap rise was ${rise.toStringAsFixed(2)} pt '
            '(SPEC: 45-65 pt from rest, ~half the final pipe gap)',
      );
    },
  );

  withGame.testGameWidget(
    'terminal velocity: fall speed is capped at maxFallSpeed',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing (+ first flap)
      game.update(1 / 60);
      // No pipes: let the bird free-fall without pipe collisions.
      for (final pipe in game.world.children.query<PipePair>()) {
        pipe.removeFromParent();
      }
      game.update(1 / 60);
    },
    verify: (game, tester) async {
      final b = bird(game);
      var maxVy = 0.0;
      const dt = 1 / 60;
      // The bird arcs up from the start flap, then free-falls (unclamped it
      // would pass 700 pt/s before reaching the ground spikes).
      for (var t = 0.0; t < 2.0 && game.state == GameState.playing; t += dt) {
        game.update(dt);
        final vy = b.body.linearVelocity.y;
        expect(
          vy,
          lessThanOrEqualTo(Config.maxFallSpeed + 1e-6),
          reason: 'fall speed must never exceed the terminal velocity '
              '(t=${t.toStringAsFixed(2)}s, vy=$vy)',
        );
        if (vy > maxVy) {
          maxVy = vy;
        }
      }
      expect(
        maxVy,
        greaterThan(Config.maxFallSpeed - 1),
        reason: 'the clamp must actually engage during a free fall '
            '(max observed vy was $maxVy)',
      );
    },
  );
}
