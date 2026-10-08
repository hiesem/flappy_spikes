import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/timed_powerup.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// §3.30–§3.32 / §7 playability gate (P3 test gate): each capsule type
/// forced on every allowed gap from its unlock index (gap 10), at 568 and
/// 711 pt over three seeds — the autopilot passes ≥ 12 hoops (the PRD
/// gate; here 30, so several powerups run, end and start again), and the
/// capsules on its line start their powerups.
void main() {
  for (final el in [
    ElementId.hourglass,
    ElementId.miniBird,
    ElementId.coinFrenzy,
  ]) {
    for (final height in [568.0, 711.0]) {
      for (final seed in [3, 11, 29]) {
        FlameTester<FlappySpikesGame>(
          () => createRunTestGame(worldHeight: height, seed: seed),
          gameSize: Vector2(320, height),
        ).testGameWidget(
          '§3.30–§3.32 ${el.storageId} capsule on every gap from gap 10: '
          'the autopilot passes ≥ 12 hoops (${height.toInt()} pt, seed $seed)',
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
            var started = 0, ended = 0, got = 0, spawned = 0;
            run.events
              ..on<PickupCollected>((e) {
                if (e.element == ElementId.capsule) got++;
              })
              ..on<ElementSpawned>((e) {
                if (e.element == ElementId.capsule) spawned++;
              })
              ..on<PowerupStarted>((e) {
                if (e.type.element == el) started++;
              })
              ..on<PowerupEnded>((e) {
                if (e.type.element == el) ended++;
              });
            final flight = await flyRun(
              game,
              maxSeconds: 120,
              untilHoops: 30,
              onFrame: (r) {
                if (!r.director.forcedQueue.contains(el)) r.debugForce(el);
              },
            );
            expect(
              flight.hoops,
              greaterThanOrEqualTo(30),
              reason: flight.trace.join('\n'),
            );
            expect(started, greaterThanOrEqualTo(1));
            expect(ended, greaterThanOrEqualTo(started - 1));
            expect(run.ended, isFalse);
            // Capsules on the line are collected (at least the started
            // ones; one met while another powerup runs starts nothing).
            expect(got, greaterThanOrEqualTo(started));
            expect(spawned, greaterThanOrEqualTo(got));
          },
        );
      }
    }
  }
}
