import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/squeeze_config.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// §3.17 / §7 playability gate (P3 test gate): the spike squeeze forced
/// again as soon as the walls are open (from the run start: the squeeze
/// has no unlock index), at 568 and 711 pt over three seeds. Every hoop
/// spawned in the squeeze window fits the squeezed band, and the bot passes
/// ≥ 12 hoops — through at least two squeezes (the second one tighter).
void main() {
  for (final height in [568.0, 711.0]) {
    for (final seed in [3, 11, 29]) {
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: height, seed: seed),
        gameSize: Vector2(320, height),
      ).testGameWidget(
        '§3.17 squeeze forced back to back: the autopilot passes ≥ 12 hoops '
        'and every window hoop fits the squeezed band '
        '(${height.toInt()} pt, seed $seed)',
        setUp: (game, _) async {
          await game.ready();
          game.sound.enabled = false;
          await preloadImages(game);
        },
        verify: (game, _) async {
          final run = await startRun(game, force: [ElementId.squeeze]);
          final sq = run.features.whereType<SqueezeFeature>().single;
          final bad = <String>[];
          var maxIndex = 0;
          // Every hoop ahead of the bird while the walls warn / close /
          // hold fits the squeezed band (it was spawned under the rule).
          void checkBand(RunController r) {
            final s = r.state.squeeze;
            if (s.phase == SqueezePhase.idle ||
                s.phase == SqueezePhase.opening) {
              return;
            }
            final depth = SqueezeConfig.insetFor(s.index, height);
            final top = RunConfig.stripHeight + depth;
            final floor = height - RunConfig.stripHeight - depth;
            final birdX = r.birdTrackPosition()!.x;
            for (final h in r.spawner.hoops) {
              if (h.resolved || h.planeX < birdX || h.plan.duringRide) continue;
              final half = h.opening / 2 + RunConfig.rimRadius;
              for (final ring in h.rings) {
                final cy = h.position.y + ring;
                if (cy - half < top - .5 || cy + half > floor + .5) {
                  bad.add('hoop ${h.plan.index} y $cy in [$top, $floor]');
                }
              }
            }
          }

          run.events.on<SqueezePhaseChanged>((e) {
            if (e.index > maxIndex) maxIndex = e.index;
          });
          final flight = await flyRun(
            game,
            maxSeconds: 75,
            untilHoops: 45,
            onFrame: (r) {
              checkBand(r);
              if (r.state.squeeze.phase == SqueezePhase.idle &&
                  r.state.squeeze.nextAt - r.state.runClock > 6) {
                r.debugForce(ElementId.squeeze);
              }
            },
          );
          expect(
            flight.hoops,
            greaterThanOrEqualTo(12),
            reason: flight.trace.reversed.take(30).join('\n'),
          );
          expect(sq.started, greaterThanOrEqualTo(2));
          expect(maxIndex, greaterThanOrEqualTo(1));
          expect(bad.toSet(), isEmpty);
          expect(run.ended, isFalse, reason: '${flight.cause}');
        },
      );
    }
  }
}
