import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// §3.18 / §3.20 / §3.21 / §7 playability gate for WP-3d: saw rings (from
/// hoop 20), switch rings (from 12) and pairs of powerup rings (from 12)
/// are each forced on every slot the director allows from the unlock index,
/// and the hoop-aware autopilot (switch first, the nearer pair ring, the
/// Black Hole pull in its rollout) passes ≥ 12 hoops at 568 and 711 pt
/// over three seeds.
void main() {
  for (final (element, kind, start) in [
    (ElementId.saw, HoopKindId.saw, 20),
    (ElementId.switchRing, HoopKindId.switchRing, 12),
    (ElementId.pair, HoopKindId.pair, 12),
  ]) {
    for (final height in [568.0, 711.0]) {
      for (final seed in [7, 21, 1234]) {
        FlameTester<FlappySpikesGame>(
          () => createRunTestGame(worldHeight: height, seed: seed),
          gameSize: Vector2(320, height),
        ).testGameWidget(
          '§7 ${element.storageId} forced from hoop $start on every slot: '
          'the autopilot passes ≥ 12 hoops (${height.toInt()} pt, seed $seed)',
          setUp: (game, _) async {
            await game.ready();
            game.sound.enabled = false;
            await preloadImages(game);
          },
          verify: (game, _) async {
            final run = await startRun(
              game,
              startHoopIndex: start,
              force: [element],
            );
            final seen = <int>{};
            var specials = 0;
            final flight = await flyRun(
              game,
              maxSeconds: 80,
              untilHoops: 14,
              onFrame: (r) {
                if (!r.director.forcedQueue.contains(element)) {
                  r.debugForce(element);
                }
                for (final h in hoopsOf(game)) {
                  if (h.plan.kind == kind && seen.add(h.plan.index)) {
                    specials++;
                  }
                }
              },
            );
            expect(
              flight.hoops,
              greaterThanOrEqualTo(12),
              reason:
                  'died at ${flight.hoops} (${flight.cause})\n'
                  '${flight.trace.reversed.take(16).join('\n')}',
            );
            expect(run.ended, isFalse);
            expect(specials, greaterThanOrEqualTo(3));
            // ignore: avoid_print
            print(
              '${element.storageId} h=$height seed=$seed: '
              '${flight.hoops} hoops, $specials specials',
            );
          },
        );
      }
    }
  }
}
