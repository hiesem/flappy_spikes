import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// §3.10 / §3.0.4 5 (WP-P1int): a tilted ring stays "the next hoop" until
/// the bird is fully past its rightmost point — not once the bird is past
/// the plane's centre x, which it is while still crossing the upper or
/// lower half of a tilted ring.
void main() {
  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 568, seed: 11),
    gameSize: Vector2(320, 568),
  );

  tester.testGameWidget(
    '§3.10 nextHoopAhead keeps a tilted ring until the bird is fully past it',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 35,
        force: [ElementId.angledRing],
      );
      var checked = 0, midCrossing = 0;
      await flyRun(
        game,
        maxSeconds: 30,
        untilHoops: 8,
        onFrame: (r) {
          if (!r.director.forcedQueue.contains(ElementId.angledRing)) {
            r.debugForce(ElementId.angledRing);
          }
          final bird = r.birdTrackPosition();
          if (bird == null) return;
          final rad = RunConfig.birdRadius * r.state.birdScale;
          // The definition: the first unresolved hoop whose rightmost point
          // the bird circle has not fully passed.
          final expected = r.spawner.hoops
              .where((h) => !h.resolved && bird.x - rad <= h.frame().rightmostX)
              .firstOrNull;
          expect(r.spawner.nextHoopAhead(), same(expected));
          if (expected != null &&
              expected.plan.tiltDeg != 0 &&
              (expected.planeX - bird.x).abs() < 40) {
            checked++;
            // Mid-crossing of a tilted ring: the plane centre may already be
            // behind the bird; the ring is still the one ahead.
            if (expected.planeX <= bird.x - 4) midCrossing++;
          }
        },
      );
      expect(checked, greaterThan(0), reason: 'no tilted crossing seen');
      // Seed-dependent (which half the bot crosses): logged, not gated.
      debugPrint('tilted crossings $checked, past the centre $midCrossing');
      expect(run.state.hoopsPassed, greaterThanOrEqualTo(8));
    },
  );
}
