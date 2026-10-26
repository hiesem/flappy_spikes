import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/formations.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/motion/hoop_motion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

// region P26-D-SYNC
// Pin the real director to a seed whose opening formation is the requested
// sync rail length; production has no separate debug force for formations.
int _syncSeed(int start, int count) {
  for (var seed = 0; seed < 1000; seed++) {
    final director = RunDirector(
      seed: seed,
      enabled: ElementId.values.toSet(),
      met: {},
      startHoopIndex: start,
      firstTrackX: RunConfig.worldWidth + RunConfig.firstHoopOffscreen,
    );
    final context = DirectorContext.open(711);
    final first = director.nextSlot(context);
    if (first.formation != FormationId.syncRails) continue;
    var length = 1;
    while (director.nextSlot(context).formation == FormationId.syncRails) {
      length++;
    }
    if (length == count) return seed;
  }
  throw StateError('No $count-ring sync rails seed from hoop $start');
}
// endregion

void main() {
  // region P26-D-SYNC
  test('D7.8 sync rail offsets agree at cruise arrivals across seeds', () {
    for (final start in [150, 250]) {
      for (var seed = 0; seed < 200; seed++) {
        final rails = Formations(
          seed: seed,
        ).build(FormationId.syncRails, start);
        final first = rails.first.motion!;
        expect(first.halfTravel, inInclusiveRange(30, 45));
        expect(first.speed, inInclusiveRange(34, 42));
        for (final time in [0.0, .37, 2.1, 13.9]) {
          final target = HoopMotion.fromSpec(first).offsetAt(time).y;
          for (var k = 0; k < rails.length; k++) {
            final motion = rails[k].motion!;
            expect(motion.type, MotionType.rail);
            expect(motion.halfTravel, first.halfTravel);
            expect(motion.speed, first.speed);
            expect(motion.phase, allOf(greaterThanOrEqualTo(0), lessThan(1)));
            final arrival =
                time + k * RunConfig.spacing / RunConfig.cruise(start);
            expect(
              HoopMotion.fromSpec(motion).offsetAt(arrival).y,
              closeTo(target, 1e-9),
              reason: 'start=$start seed=$seed ring=$k time=$time',
            );
          }
        }
      }
    }
  });

  for (final start in [150, 250]) {
    for (final count in [3, 4]) {
      final seed = _syncSeed(start, count);
      for (final height in [568.0, 711.0]) {
        FlameTester<FlappySpikesGame>(
          () => createRunTestGame(worldHeight: height, seed: seed),
          gameSize: Vector2(Config.worldWidth, height),
        ).testGameWidget(
          'D7.8 $count sync rails align at real plane crossings '
          'from $start height $height',
          setUp: (game, _) async {
            await game.ready();
            await preloadImages(game);
          },
          verify: (game, _) async {
            final run = await startRun(game, startHoopIndex: start);
            expect(run.spawner.slotLog.first.formation, FormationId.syncRails);
            final offsets = <int, double>{};
            final flight = await flyRun(
              game,
              untilHoops: count,
              onFrame: (r) {
                final birdX = r.state.camX + RunConfig.birdX;
                for (final hoop in r.spawner.hoops) {
                  if (hoop.plan.index >= start + count ||
                      offsets.containsKey(hoop.plan.index) ||
                      birdX < hoop.planeX) {
                    continue;
                  }
                  expect(hoop.plan.formation, FormationId.syncRails);
                  expect(hoop.touched, isFalse);
                  expect(
                    r.state.forwardSpeed,
                    closeTo(RunConfig.cruise(start), 1e-9),
                  );
                  offsets[hoop.plan.index] = hoop.motion!.offset.y;
                }
              },
            );
            expect(
              flight.hoops,
              count,
              reason: '${flight.cause} ${flight.trace}',
            );
            expect(offsets, hasLength(count));
            final values = offsets.values.toList()..sort();
            expect(values.last - values.first, lessThanOrEqualTo(4));
          },
        );
      }
    }
  }
  // endregion

  test('schedules formations every 12–20 hoops from hoop 150', () {
    final starts = <int>[];
    final shapes = <FormationId>{};

    for (var seed = 0; seed < 200; seed++) {
      final formations = Formations(seed: seed);
      final seedStarts = <int>[];
      FormationId? previous;
      FormationId? beforePrevious;

      for (var hoop = 0; hoop < 500; hoop++) {
        final id = formations.nextAt(hoop);
        if (id == null) continue;

        expect(hoop, greaterThanOrEqualTo(150));
        expect(id, isNot(anyOf(previous, beforePrevious)));
        seedStarts.add(hoop);
        shapes.add(id);
        beforePrevious = previous;
        previous = id;
      }

      expect(seedStarts.first, 150);
      for (var index = 1; index < seedStarts.length; index++) {
        final gap = seedStarts[index] - seedStarts[index - 1];
        expect(gap, allOf(greaterThanOrEqualTo(12), lessThanOrEqualTo(20)));
      }
      starts.addAll(seedStarts);
    }

    expect(starts, isNotEmpty);
    expect(shapes, containsAll(FormationId.values));
  });

  test('emits the six D7 shape geometries', () {
    for (var seed = 0; seed < 200; seed++) {
      final formations = Formations(seed: seed);

      final stairs = formations.build(FormationId.stairs, 150);
      expect(stairs, hasLength(4));
      final stairStep = stairs[1].centreY - stairs[0].centreY;
      expect(
        stairStep.abs(),
        allOf(greaterThanOrEqualTo(70), lessThanOrEqualTo(90)),
      );
      expect(
        stairs.map((plan) => plan.centreY - stairs.first.centreY).toList(),
        [for (var index = 0; index < 4; index++) index * stairStep],
      );
      expect(stairs.map((plan) => plan.tiltDeg.abs()), everyElement(15));
      expect(
        stairs.map((plan) => plan.tiltDeg),
        everyElement(stairs.first.tiltDeg),
      );

      final slalom = formations.build(FormationId.slalom, 150);
      expect(slalom, hasLength(4));
      final slalomCentre = (slalom[0].centreY + slalom[1].centreY) / 2;
      final slalomOffsets = [
        for (var index = 0; index < 4; index++)
          (slalom[index].centreY - slalomCentre).abs(),
      ];
      expect(
        slalomOffsets,
        everyElement(allOf(greaterThanOrEqualTo(110), lessThanOrEqualTo(130))),
      );
      for (var index = 0; index < slalom.length; index++) {
        final sign = index.isEven ? -1 : 1;
        final expected = sign * slalomOffsets[index];
        expect(slalom[index].centreY, closeTo(slalomCentre + expected, 1e-9));
        expect(slalom[index].tiltDeg, 0);
      }

      final wave = formations.build(FormationId.tiltWave, 150);
      expect(wave.map((plan) => plan.tiltDeg), [-30, -15, 0, 15, 30]);
      for (var index = 1; index < wave.length; index++) {
        final plan = wave[index];
        final approach = plan.centreY - wave[index - 1].centreY;
        if (plan.tiltDeg != 0) {
          expect(
            plan.tiltDeg.sign,
            approach.sign,
            reason: 'D7 wave hoop $index follows its approach',
          );
        }
        if (plan.tiltDeg.abs() >= 20) {
          expect(
            approach.abs(),
            greaterThanOrEqualTo(40),
            reason: 'D2 strong wave tilt $index has the minimum Δy',
          );
        }
      }
      expect(wave[2].centreY, lessThan(wave[1].centreY));
      expect(wave[2].centreY, lessThan(wave[3].centreY));
      expect(wave.first.centreY, wave.last.centreY);

      final rails = formations.build(FormationId.syncRails, 150);
      expect(rails.length, anyOf(3, 4));
      // region P26-D-SYNC
      // D7.8 synchronizes arrival poses, so absolute phases differ.
      expect(
        rails.map((plan) => plan.motion?.halfTravel),
        everyElement(rails.first.motion?.halfTravel),
      );
      expect(
        rails.map((plan) => plan.motion?.speed),
        everyElement(rails.first.motion?.speed),
      );
      // endregion
      expect(rails.first.motion?.type, MotionType.rail);
      expect(
        rails.map((plan) => plan.centreY),
        everyElement(rails.first.centreY),
      );

      final sawGate = formations.build(FormationId.sawGate, 150);
      expect(sawGate, hasLength(3));
      expect(sawGate.map((plan) => plan.kind), [
        HoopKindId.normal,
        HoopKindId.saw,
        HoopKindId.normal,
      ]);
      expect(
        sawGate.map((plan) => plan.centreY),
        everyElement(sawGate.first.centreY),
      );
      expect(sawGate.map((plan) => plan.tiltDeg), everyElement(0));

      final switchChain = formations.build(FormationId.switchChain, 150);
      expect(switchChain, hasLength(3));
      expect(
        switchChain.map((plan) => plan.kind),
        everyElement(HoopKindId.switchRing),
      );
      final switchSides = <int>[];
      for (final plan in switchChain) {
        switchSides.add(plan.attached.single.y! > plan.centreY ? 1 : -1);
      }
      expect(switchSides[1], -switchSides[0]);
      expect(switchSides[2], -switchSides[1]);
    }
  });

  test(
    'every template fits the D3 budget and keeps hoop planes 310 pt apart',
    () {
      for (var seed = 0; seed < 200; seed++) {
        final formations = Formations(seed: seed);
        for (final id in FormationId.values) {
          final plans = formations.build(
            id,
            150,
            startTrackX: 930,
            centreY: 355,
          );
          expect(plans.map((plan) => plan.formation), everyElement(id));
          expect(
            plans.map((plan) => plan.advance),
            everyElement(RunConfig.spacing),
          );
          for (var index = 1; index < plans.length; index++) {
            expect(
              plans[index].trackX - plans[index - 1].trackX,
              RunConfig.spacing,
            );
          }
          expect(
            Formations.fourSlotHazardCost(plans),
            lessThanOrEqualTo(Formations.hazardBudgetAt150),
          );
        }
      }
    },
  );

  test('mix chapters rotate at an equal total weight', () {
    expect(Formations.chapterAt(150), MixChapter.sawHeavy);
    expect(Formations.chapterAt(199), MixChapter.sawHeavy);
    expect(Formations.chapterAt(200), MixChapter.switchHeavy);
    expect(Formations.chapterAt(249), MixChapter.switchHeavy);
    expect(Formations.chapterAt(250), MixChapter.movingHeavy);
    expect(Formations.chapterAt(300), MixChapter.sawHeavy);

    const base = {
      MixWeightKey.saw: 26,
      MixWeightKey.switchRing: 14,
      MixWeightKey.moving: 58,
    };
    final total = base.values.reduce((a, b) => a + b).toDouble();
    final weighted = [
      for (var hoop = 150; hoop < 350; hoop += 50)
        Formations.mixWeightsAt(hoop, base),
    ];
    expect(
      weighted.map((weights) => weights.values.reduce((a, b) => a + b)),
      everyElement(total),
    );
    expect(
      weighted[0][MixWeightKey.saw]!,
      greaterThan(weighted[0][MixWeightKey.moving]!),
    );
    expect(
      weighted[1][MixWeightKey.switchRing]!,
      greaterThan(weighted[1][MixWeightKey.saw]!),
    );
    expect(
      weighted[2][MixWeightKey.moving]!,
      greaterThan(weighted[2][MixWeightKey.switchRing]!),
    );
  });
}
