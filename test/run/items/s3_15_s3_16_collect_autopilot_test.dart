import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// §3.15 / §3.16 / §7 playability gate (P3 test gate): the golden feather
/// and the puzzle piece forced on every allowed gap from their unlock
/// index (gap 3 / gap 14), at 568 and 711 pt over three seeds — the
/// autopilot passes ≥ 12 hoops. The PRD's bot does not chase the detour
/// pickups (they sit 64–200 pt above the hoop line), so nothing is taught;
/// the pickups only have to leave the course flyable.
void main() {
  for (final el in [ElementId.feather, ElementId.puzzlePiece]) {
    for (final height in [568.0, 711.0]) {
      for (final seed in [3, 11, 29]) {
        FlameTester<FlappySpikesGame>(
          () => createRunTestGame(worldHeight: height, seed: seed),
          gameSize: Vector2(320, height),
        ).testGameWidget(
          '§3.15 / §3.16 ${el.storageId} on every gap from gap '
          '${el.firstPossible}: the autopilot passes ≥ 12 hoops '
          '(${height.toInt()} pt, seed $seed)',
          setUp: (game, _) async {
            await game.ready();
            game.sound.enabled = false;
            await preloadImages(game);
          },
          verify: (game, _) async {
            final run = await startRun(
              game,
              startHoopIndex: el.firstPossible!,
              force: [el],
            );
            var spawned = 0;
            run.events.on<ElementSpawned>((e) {
              if (e.element == el) spawned++;
            });
            final flight = await flyRun(
              game,
              maxSeconds: 120,
              untilHoops: 20,
              onFrame: (r) {
                if (!r.director.forcedQueue.contains(el)) r.debugForce(el);
              },
            );
            expect(
              flight.hoops,
              greaterThanOrEqualTo(20),
              reason: flight.trace.join('\n'),
            );
            expect(run.ended, isFalse);
            expect(spawned, greaterThanOrEqualTo(5));
          },
        );
      }
    }
  }
}
