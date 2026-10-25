import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/formations.dart';
import 'package:flappy_spikes/run/director/hazard_budget.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.6 D7 director wiring: the pure formation generator owns whole runs
/// of otherwise-normal slots from hoop 150. These tests fly the real director
/// (not the generator in isolation).
typedef WireCourse = ({List<SlotPlan> slots, List<GapPlan> gaps});

WireCourse _course(
  int seed, {
  int startHoopIndex = 150,
  int slots = 400,
  double viewHeight = 711,
}) {
  final director = RunDirector(
    seed: seed,
    enabled: ElementId.values.toSet(),
    met: ElementId.values.toSet(),
    startHoopIndex: startHoopIndex,
  );
  final plans = <SlotPlan>[];
  final gaps = <GapPlan>[];
  for (var i = 0; i < slots; i++) {
    final ctx = DirectorContext.open(viewHeight);
    final plan = director.nextSlot(ctx);
    plans.add(plan);
    gaps.add(director.nextGap(ctx, plan));
  }
  return (slots: plans, gaps: gaps);
}

List<SlotPlan> _formationSlots(List<SlotPlan> plans) => [
  for (final plan in plans)
    if (plan.formation != null) plan,
];

List<int> _formationStarts(List<SlotPlan> plans) {
  final starts = <int>[];
  FormationId? previous;
  for (final plan in plans) {
    final id = plan.formation;
    if (id != null && id != previous) starts.add(plan.index);
    previous = id;
  }
  return starts;
}

void main() {
  test('D7 formations start every 12–20 hoops at 150 and 250, all six '
      'shapes appear and every slot names its shape', () {
    final shapes = <FormationId, int>{};
    final startsByRun = <(int, int), List<int>>{};

    for (final start in [150, 250]) {
      for (var seed = 0; seed < 200; seed++) {
        final course = _course(seed, startHoopIndex: start);
        final plans = course.slots;
        final starts = _formationStarts(plans);
        startsByRun[(start, seed)] = starts;

        expect(starts.first, start, reason: 'start $start seed $seed');
        for (var k = 1; k < starts.length; k++) {
          expect(
            starts[k] - starts[k - 1],
            inInclusiveRange(12, 20),
            reason: 'start $start seed $seed starts $starts',
          );
        }

        // All completed formations keep their full multi-slot shape.
        for (final startIndex in starts) {
          final shape = plans[startIndex - start].formation!;
          final length = plans
              .skip(startIndex - start)
              .takeWhile((p) => p.formation == shape)
              .length;
          if (startIndex + 5 > start + plans.length) continue;
          expect(length, switch (shape) {
            FormationId.stairs || FormationId.slalom => 4,
            FormationId.tiltWave => 5,
            FormationId.syncRails => inInclusiveRange(3, 4),
            FormationId.sawGate || FormationId.switchChain => 3,
          });
        }

        FormationId? previous;
        FormationId? beforePrevious;
        for (final plan in plans) {
          final id = plan.formation;
          expect(
            plan.calm && id != null,
            isFalse,
            reason: 'start $start seed $seed calm formation ${plan.index}',
          );
          expect(
            plan.duringRide && id != null,
            isFalse,
            reason: 'start $start seed $seed ride formation ${plan.index}',
          );
          expect(
            plan.advance,
            id == null ? isNot(lessThan(RunConfig.spacing)) : RunConfig.spacing,
            reason: 'start $start seed $seed hoop ${plan.index} advance',
          );
          if (id == null) continue;
          shapes[id] = (shapes[id] ?? 0) + 1;
          if (id != previous) {
            expect(id, isNot(previous));
            expect(id, isNot(beforePrevious));
            beforePrevious = previous;
            previous = id;
          }
        }

        final formationSlots = _formationSlots(plans);
        for (var k = 1; k < formationSlots.length; k++) {
          final a = formationSlots[k - 1];
          final b = formationSlots[k];
          if (a.formation == b.formation) {
            expect(b.trackX - a.trackX, RunConfig.spacing);
          }
        }
      }
    }

    expect(startsByRun, hasLength(400));
    expect(shapes.keys, containsAll(FormationId.values));
    // ignore: avoid_print
    print('D7 formation slots by shape over 400 courses: $shapes');
  });

  test('D7 the rolling hazard ledger holds through every formation', () {
    final budget = HazardBudget();
    var formationsSeen = 0;
    for (var seed = 0; seed < 200; seed++) {
      for (final start in [150, 250]) {
        final course = _course(seed, startHoopIndex: start);
        final window = <SlotPlan>[];
        for (final plan in course.slots) {
          window.add(plan);
          if (window.length > HazardBudget.windowSize) window.removeAt(0);
          final sum = window.fold(0.0, (total, p) => total + p.hazardCost);
          if (plan.formation != null) formationsSeen++;
          expect(
            sum,
            lessThanOrEqualTo(budget.budgetAt(plan.index) + 1e-9),
            reason: 'start $start seed $seed hoop ${plan.index} sum $sum',
          );
        }
      }
    }
    expect(formationsSeen, greaterThan(0));
  });

  test(
    'D7 hard-family shares rotate every 50 hoops at equal ledger budget',
    () {
      final counts = {
        for (final chapter in MixChapter.values)
          chapter: {for (final family in MixWeightKey.values) family: 0},
      };
      for (var seed = 0; seed < 200; seed++) {
        for (final p in _course(seed, slots: 450).slots) {
          final chapter = Formations.chapterAt(p.index);
          final family = p.kind == HoopKindId.saw
              ? MixWeightKey.saw
              : p.kind == HoopKindId.switchRing
              ? MixWeightKey.switchRing
              : p.motion != null
              ? MixWeightKey.moving
              : null;
          if (family != null) {
            counts[chapter]![family] = counts[chapter]![family]! + 1;
          }
        }
      }
      for (final family in MixWeightKey.values) {
        final favoured = MixChapter.values[family.index];
        final high = counts[favoured]![family]!;
        for (final chapter in MixChapter.values.where((c) => c != favoured)) {
          expect(
            high,
            greaterThan(counts[chapter]![family]! * 1.25),
            reason: '$family counts: $counts',
          );
        }
      }
    },
  );

  test(
    'D7 the wired course is deterministic and keeps planes 310 pt apart',
    () {
      WireCourse run() => _course(1234, startHoopIndex: 250);
      final first = run();
      final second = run();
      expect(first.slots, second.slots);
      expect(first.gaps, second.gaps);

      final plans = first.slots;
      for (var k = 1; k < plans.length; k++) {
        final previous = plans[k - 1];
        final plan = plans[k];
        expect(plan.trackX - previous.trackX, previous.advance);
        if (previous.formation != null) {
          expect(previous.advance, RunConfig.spacing);
        }
      }
    },
  );
}
