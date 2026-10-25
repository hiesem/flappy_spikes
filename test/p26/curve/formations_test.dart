import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/formations.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      expect(
        rails.map((plan) => plan.motion),
        everyElement(rails.first.motion),
      );
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
