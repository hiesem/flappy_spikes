import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

// Independent PRD B3 A=1 expectations: do not derive these from the script
// under test. Gap numbers refer to the gap after that numbered hoop.
const _gaps = <List<(int, ElementId)>>[
  [
    (2, ElementId.starTrail),
    (5, ElementId.starTrail),
    (4, ElementId.feather),
    (10, ElementId.heart),
    (13, ElementId.heart),
    (16, ElementId.heart),
  ],
  [
    (3, ElementId.coinFrenzy),
    (6, ElementId.starTrail),
    (12, ElementId.heart),
    (15, ElementId.heart),
    (18, ElementId.heart),
  ],
  [(8, ElementId.puzzlePiece), (11, ElementId.hourglass)],
];

ElementId _element(GapItemPlan p) =>
    p.extra is CapsuleType ? (p.extra! as CapsuleType).element : p.kind;

void main() {
  for (final height in [568.0, 711.0]) {
    for (var step = 0; step < 3; step++) {
      final script = ShowcaseScript.planFor(step, 1);
      FlameTester<FlappySpikesGame>(() {
        SharedPreferences.setMockInitialValues({});
        return FlappySpikesGame(
          worldHeight: height,
          soundEnabled: false,
          showcasePlan: FixedShowcase(script),
        )..runSeed = 7;
      }, gameSize: Vector2(320, height)).testGameWidget(
        'B3 flown step ${step + 1} A1 spawns every script item at $height',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, _) async {
          final run = await startRun(game);
          final events = <RunEvent>[];
          run.events.onAny(events.add);
          RideKind? bullseyeRide;
          run.events.on<HoopSpawned>((e) {
            if (e.plan.index == 14 && e.plan.kind == HoopKindId.bullseye) {
              bullseyeRide = run.state.ride?.kind;
            }
          });
          final flight = await flyRun(game, untilHoops: 21, maxSeconds: 100);
          expect(
            flight.hoops,
            greaterThanOrEqualTo(21),
            reason: flight.trace.join('\n'),
          );
          expect(run.setup.forced, isEmpty);
          expect(
            events.whereType<HighlightStarted>().map((e) => e.id),
            contains(script.highlightId),
          );

          final hoops = events.whereType<HoopSpawned>().toList();
          HoopSpawned slot(int index) => hoops.singleWhere(
            (e) => e.plan.index == index && e.plan.kind != HoopKindId.rideRing,
          );
          switch (step) {
            case 0:
              expect(slot(7).plan.kind, HoopKindId.portal);
              expect(slot(7).plan.extra, RideId.cannon);
              expect(
                events.whereType<RideEnded>().map((e) => e.rideId),
                contains(RideId.cannon),
              );
            case 1:
              expect(slot(9).plan.cometHang, isTrue);
              expect(
                events.whereType<PickupSpawned>().any(
                  (e) =>
                      e.pickup.id == ElementId.comet &&
                      e.pickup.plan?.trackX ==
                          slot(9).plan.attached.single.trackX,
                ),
                isTrue,
                reason: 'scripted comet star must physically spawn',
              );
              expect(slot(14).plan.kind, HoopKindId.bullseye);
              expect(
                bullseyeRide,
                RideKind.comet,
                reason: 'bullseye 14 must survive the active comet ride',
              );
            case 2:
              expect(slot(5).plan.kind, HoopKindId.fever);
              expect(events.whereType<FeverStarted>(), isNotEmpty);
              expect(slot(15).plan.kind, HoopKindId.portal);
              expect(slot(15).plan.extra, RideId.space);
              expect(
                events.whereType<RideStarted>().map((e) => e.rideId),
                contains(RideId.space),
              );
          }

          for (final (gap, element) in _gaps[step]) {
            final planned = run.spawner.gapLog
                .singleWhere((p) => p.index == gap)
                .items
                .where((p) => _element(p) == element)
                .toList();
            expect(planned, isNotEmpty, reason: '$element in gap $gap planned');
            // Match by track position as well as kind: a random heart or
            // another trail cannot cover for a scripted item lost to a clear.
            for (final item in planned) {
              expect(
                events.whereType<PickupSpawned>().any((e) {
                  final p = e.pickup.plan;
                  return p != null &&
                      _element(p) == element &&
                      p.trackX == item.trackX;
                }),
                isTrue,
                reason: '$element in gap $gap must physically spawn',
              );
              expect(
                events.whereType<PickupCleared>().any((e) {
                  final p = e.pickup.plan;
                  return p != null &&
                      _element(p) == element &&
                      p.trackX == item.trackX;
                }),
                isFalse,
                reason: '$element in gap $gap must survive ride clears',
              );
            }
          }
        },
      );
    }
  }
}
