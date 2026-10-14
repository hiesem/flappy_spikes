import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/fever_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/items/fever.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final all = ElementId.values.toSet();
  final prefs = {
    'metElements': [for (final e in all) e.storageId],
  };
  FlameTester<FlappySpikesGame> game() => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5, prefs: prefs),
    gameSize: Vector2(320, 711),
  );
  Future<void> boot(FlappySpikesGame g, _) async {
    await g.ready();
    await preloadImages(g);
  }

  group('S7-07', () {
    game().testGameWidget(
      '§21 FEVER retains its loud loop until the streak breaks, beyond five '
      'perfect passes',
      setUp: boot,
      verify: (g, _) async {
        final run = await startRun(g);
        final f = run.features.whereType<FeverFeature>().single;
        run.events.emit(const FeverIgnite('pair'));
        f.update(0, .01);
        final loop = f.loop!;
        expect(loop.volume, FeverConfig.loopVolume);
        for (var i = 0; i < 6; i++) {
          run.debugPass(perfect: true);
        }
        f.update(0, .4);
        expect(run.state.onFire, isTrue);
        expect(run.state.streak, greaterThanOrEqualTo(5));
        expect(
          loop.volume,
          FeverConfig.loopVolume,
          reason: 'FEVER remains unchanged; the streak has not broken',
        );
        expect(run.state.fever, isTrue);
      },
    );
  });

  test('§21 / §27 ordinary streak fire cannot block a FEVER ring', () {
    final d = RunDirector(
      seed: 5,
      enabled: all,
      met: all,
      startHoopIndex: 20,
      forced: [ElementId.fever],
    );
    final ctx = DirectorContext.open(711, onFire: true);
    expect(ctx.activity, isFalse);
    final plan = d.nextSlot(ctx);
    expect(
      plan.kind,
      HoopKindId.fever,
      reason: 'fire is passive; FEVER ring eligibility is unchanged',
    );
  });

  group('S7-12', () {
    for (final modifier in [ElementId.angledRing, ElementId.movingRing]) {
      game().testGameWidget(
        // PRD-2.3.1 §16.1 A (supersedes S7-12 "keeps its geometry"): the
        // planned-ahead slot moves into the comet layout as a plain ride
        // hoop (upright, still) at a station and the zigzag height.
        '§16 / PRD-2.3.1 §16.1 A comet re-places the planned-ahead $modifier '
        'hoop: upright, still, at a comet station',
        setUp: boot,
        verify: (g, _) async {
          final run = await startRun(g, startHoopIndex: 20);
          run.debugForce(modifier);
          await flyUntil(g, (r) {
            final a = r.spawner.plannedAhead;
            return a != null &&
                (modifier == ElementId.angledRing
                    ? a.tiltDeg != 0
                    : a.motion != null);
          }, maxSeconds: 8);
          final planned = run.spawner.plannedAhead!;
          if (modifier == ElementId.angledRing) {
            expect(planned.tiltDeg, isNot(0));
          } else {
            expect(planned.motion, isNotNull);
          }
          final comet = run.features.whereType<CometFeature>().single;
          expect(comet.start(), isTrue);
          await flyUntil(
            g,
            (r) => r.spawner.hoops.any((h) => h.plan.index == planned.index),
            maxSeconds: 4,
          );
          final spawned = run.spawner.hoops.singleWhere(
            (h) => h.plan.index == planned.index,
          );
          expect(spawned.plan.motion, isNull);
          expect(spawned.plan.tiltDeg, 0);
          expect(spawned.plan.duringRide, isTrue);
          expect(
            run.director.cometStations.any(
              (x) => (x - spawned.plan.trackX).abs() < 1e-6,
            ),
            isTrue,
          );
          expect(
            (spawned.plan.centreY - run.state.viewHeight / 2).abs(),
            closeTo(70, 1e-6),
          );
        },
      );
    }
  });
}
