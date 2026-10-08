import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
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
    'PRD-2 §3.0.1 the world scrolls leftward at the cruise speed (150 pt/s '
    '+ 3.5 %/min), hoops and spike teeth alike',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
      game.update(1 / 60);
      await game.ready(); // mount the first hoop
    },
    verify: (game, tester) async {
      const dt = 1 / 60;
      stepGame(game, 0.3, dt: dt, flapBelow: 320);
      final hoop = hoopsOf(game).first;
      final run = game.run!;
      final strip = game.world.children.query<SpikeStrip>().first;
      final x0 = hoop.planeX - run.state.camX;
      final teeth0 = strip.toothOffset;

      // Measure over the next 0.7 s (bird kept airborne by flapping; the
      // hoop is still well right of the bird at the end of the window).
      stepGame(game, 0.7, dt: dt, flapBelow: 320);
      final x1 = hoop.planeX - run.state.camX;

      final speed = (x0 - x1) / 0.7;
      expect(
        speed,
        closeTo(RunConfig.cruise(run.state.runClock), 0.5),
        reason: 'measured scroll speed $speed pt/s',
      );
      expect(x1, lessThan(x0), reason: 'world must scroll leftward');
      expect((teeth0 - strip.toothOffset) / 0.7, closeTo(speed, 0.5),
          reason: 'the spike teeth scroll with the world');
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
