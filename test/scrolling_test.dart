import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
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
    'world scrolls leftward at a constant 200 pt/s',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
      game.update(1 / 60);
      await game.ready(); // mount the first auto-spawned pipe pair
    },
    verify: (game, tester) async {
      const dt = 1 / 60;

      // Let the first pipe pair spawn and the scrolling settle in.
      stepGame(game, 0.3, dt: dt, flapBelow: 320);
      final pipe = game.world.children.query<PipePair>().first;
      final x0 = pipe.body.position.x;

      // Measure over the next 0.7 s (bird kept airborne by flapping; the
      // pipe is still well right of the bird at the end of the window).
      stepGame(game, 0.7, dt: dt, flapBelow: 320);
      final x1 = pipe.body.position.x;

      final speed = (x0 - x1) / 0.7;
      expect(
        speed,
        closeTo(Config.scrollSpeed, 0.5),
        reason: 'measured scroll speed $speed pt/s',
      );
      expect(x1, lessThan(x0), reason: 'world must scroll leftward');
    },
  );

  withGame.testGameWidget(
    'world does not scroll in the start state',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, tester) async {
      expect(game.state, GameState.start);
      final strip = game.world.children.query<SpikeStrip>().first;
      final tiles = strip.children.whereType<SpriteComponent>().toList();
      final xs = tiles.map((t) => t.position.x).toList();
      stepGame(game, 0.5);
      final xsAfter = tiles.map((t) => t.position.x).toList();
      for (var i = 0; i < xs.length; i++) {
        expect(xsAfter[i], closeTo(xs[i], 1e-9));
      }
    },
  );

  withGame.testGameWidget(
    'spike strip physics bodies span exactly the screen width',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, tester) async {
      // SPEC: "Both ... are static physics bodies spanning the full width."
      for (final strip in game.world.children.query<SpikeStrip>()) {
        final shape = strip.body.fixtures.first.shape as PolygonShape;
        final xs = shape.vertices.map((v) => v.x);
        final halfWidth =
            (xs.reduce(math.max) - xs.reduce(math.min)) / 2;
        expect(
          halfWidth,
          closeTo(Config.worldWidth / 2, 1e-6),
          reason: '${strip.isCeiling ? "ceiling" : "ground"} strip '
              'half-width is $halfWidth, expected ${Config.worldWidth / 2}',
        );
        final ys = shape.vertices.map((v) => v.y);
        final halfHeight =
            (ys.reduce(math.max) - ys.reduce(math.min)) / 2;
        expect(halfHeight, closeTo(Config.spikeHeight / 2, 1e-6));
      }
    },
  );
}
