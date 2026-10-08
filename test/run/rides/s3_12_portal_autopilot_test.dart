import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// §3.12 / §7 playability gate (P3 test gate): the portal forced on every
/// allowed slot from its unlock index (25), at 568 and 711 pt over three
/// seeds — the bot flies through the portal, the ride runs by itself, and
/// normal play continues between rides. ≥ 12 hoops after the unlock is the
/// PRD gate; the run must also survive two rides and the normal hoops in
/// between (26 hoops).
void main() {
  for (final height in [568.0, 711.0]) {
    for (final seed in [3, 11, 29]) {
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: height, seed: seed),
        gameSize: Vector2(320, height),
      ).testGameWidget(
        '§3.12 portal on every slot from hoop 25: the autopilot passes ≥ 12 '
        'hoops (${height.toInt()} pt, seed $seed)',
        setUp: (game, _) async {
          await game.ready();
          game.sound.enabled = false;
          await preloadImages(game);
        },
        verify: (game, _) async {
          final run = await startRun(
            game,
            startHoopIndex: ElementId.portal.firstPossible!,
            force: [ElementId.portal],
          );
          final flight = await flyRun(
            game,
            maxSeconds: 90,
            untilHoops: 26,
            onFrame: (r) {
              if (!r.director.forcedQueue.contains(ElementId.portal)) {
                r.debugForce(ElementId.portal);
              }
            },
          );
          final rides = run.features.whereType<PortalRideFeature>().single;
          expect(
            flight.hoops,
            greaterThanOrEqualTo(26),
            reason: flight.trace.join('\n'),
          );
          expect(rides.started.length, greaterThanOrEqualTo(2));
          // Never the same ride twice in a row.
          for (var i = 1; i < rides.started.length; i++) {
            expect(rides.started[i], isNot(rides.started[i - 1]));
          }
          expect(run.ended, isFalse);
        },
      );
    }
  }
}
