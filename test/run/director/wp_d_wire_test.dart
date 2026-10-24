import 'package:flappy_spikes/run/config/layout_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/hazard_budget.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WP-D3 the rolling four-slot hazard ledger holds on every screen', () {
    const heights = [568.0, 711.0, 730.0];
    final budget = HazardBudget();

    for (final height in heights) {
      for (var seed = 1; seed <= 200; seed++) {
        final director = RunDirector(
          seed: seed,
          enabled: ElementId.values.toSet(),
          met: ElementId.values.toSet(),
        );
        final window = <SlotPlan>[];
        for (var slot = 0; slot < 400; slot++) {
          final plan = director.nextSlot(DirectorContext.open(height));
          director.nextGap(DirectorContext.open(height), plan);
          window.add(plan);
          if (window.length > HazardBudget.windowSize) {
            window.removeAt(0);
          }
          final forced = window.any((entry) => entry.forced);
          final sum = window.fold(
            0.0,
            (total, entry) => total + entry.hazardCost,
          );
          expect(plan.hazardCost, greaterThanOrEqualTo(0));
          if (!forced) {
            expect(
              sum,
              lessThanOrEqualTo(budget.budgetAt(plan.index) + 1e-9),
              reason:
                  'height $height seed $seed hoop ${plan.index} '
                  'sum $sum',
            );
          }
        }
      }
    }
  });

  test('WP-D3 forced slots are counted but exempt from the budget', () {
    final director = RunDirector(
      seed: 54,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );
    final first = director.nextSlot(DirectorContext.open(711));
    director.debugForce(ElementId.saw);
    final forced = director.nextSlot(DirectorContext.open(711));

    expect(first.hazardCost, 0);
    expect(forced.forced, isTrue);
    expect(forced.kind, HoopKindId.saw);
    expect(forced.hazardCost, 2);
    expect(first.hazardCost + forced.hazardCost, greaterThan(0));
  });

  test('WP-D4 revive, squeeze-end and ride-end calm stretches are exact', () {
    RunDirector make() => RunDirector(
      seed: 54,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );

    var director = make();
    for (var slot = 0; slot < 10; slot++) {
      final plan = director.nextSlot(DirectorContext.open(711));
      director.nextGap(DirectorContext.open(711), plan);
    }
    director.onRevive();
    for (var slot = 0; slot < 4; slot++) {
      final plan = director.nextSlot(DirectorContext.open(711));
      expect(plan.calm, slot < 3);
      if (slot < 3) expect(plan.kind, HoopKindId.normal);
      expect(plan.motion, isNull);
      expect(plan.tiltDeg.abs(), lessThanOrEqualTo(10));
      expect(plan.opening, closeTo(RunConfig.openingFor(plan.index), 1e-9));
    }
    expect(director.allowsSqueezeWarning(10), isFalse);
    expect(director.allowsSqueezeWarning(11), isFalse);
    expect(director.allowsSqueezeWarning(12), isFalse);

    director = make();
    for (var slot = 0; slot < 10; slot++) {
      director.nextSlot(DirectorContext.open(711));
    }
    director.onSqueezeEnded(9);
    for (var slot = 0; slot < 3; slot++) {
      expect(
        director.nextSlot(DirectorContext.open(711)).calm,
        slot < 2,
        reason: 'squeeze slot $slot',
      );
    }

    director = make();
    for (var slot = 0; slot < 10; slot++) {
      director.nextSlot(DirectorContext.open(711));
    }
    director.onRideEnd(RideKind.portal);
    for (var slot = 0; slot < 3; slot++) {
      expect(
        director.nextSlot(DirectorContext.open(711)).calm,
        slot < 2,
        reason: 'ride slot $slot',
      );
    }
  });

  test('WP-D4 periodic calm follows the schedule and minimum spacing', () {
    final starts = <int>[];
    SlotPlan? previous;
    final director = RunDirector(
      seed: 17,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );
    for (var slot = 0; slot < 240; slot++) {
      final plan = director.nextSlot(DirectorContext.open(711));
      director.nextGap(DirectorContext.open(711), plan);
      if (plan.calm && (previous == null || !previous.calm)) {
        starts.add(plan.index);
      }
      if (plan.calm) {
        expect(plan.kind, HoopKindId.normal);
        expect(plan.motion, isNull);
        expect(plan.tiltDeg.abs(), lessThanOrEqualTo(10));
        if (previous != null) {
          final median =
              LayoutConfig.bandFor(plan.index).dy.$1 * RunConfig.dyRefBand;
          expect(
            (plan.centreY - previous.centreY).abs(),
            lessThanOrEqualTo(median + 1e-9),
          );
        }
      }
      previous = plan;
    }

    expect(starts.first, inInclusiveRange(30, 34));
    final expected = [
      starts.first,
      starts.first + 36,
      starts.first + 36 + 43,
      starts.first + 36 + 43 + 52,
      starts.first + 36 + 43 + 52 + 55,
    ];
    for (var index = 0; index < expected.length; index++) {
      expect(starts[index], closeTo(expected[index], 4));
    }
    for (var index = 1; index < starts.length; index++) {
      expect(starts[index] - starts[index - 1], greaterThanOrEqualTo(12));
    }
  });

  test('WP-D5 a revive keeps the squeeze index', () {
    RunDirector make(int index) => RunDirector(
      seed: 54,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );

    final preserved = make(3);
    for (var slot = 0; slot < 12; slot++) {
      preserved.nextSlot(DirectorContext.open(711));
    }
    preserved.onRevive();
    final afterRevive = preserved.rollSqueezeAt(
      100,
      hoop: preserved.hoopIndex,
      index: 3,
    );
    final reference = make(3).rollSqueezeAt(100, hoop: 12, index: 3);

    expect(afterRevive, reference);
  });

  test('WP-D6 ride, squeeze and bonus headlines stay eight hoops apart', () {
    const bonusKinds = {
      HoopKindId.pair,
      HoopKindId.luckySpin,
      HoopKindId.fever,
    };
    for (var seed = 1; seed <= 40; seed++) {
      final director = RunDirector(
        seed: seed,
        enabled: ElementId.values.toSet(),
        met: ElementId.values.toSet(),
      );
      final headlines = <(String, int)>[];
      for (var slot = 0; slot < 240; slot++) {
        final plan = director.nextSlot(DirectorContext.open(711));
        final gap = director.nextGap(DirectorContext.open(711), plan);
        if (plan.kind == HoopKindId.portal || plan.cometHang) {
          headlines.add(('ride', plan.index));
        } else if (bonusKinds.contains(plan.kind)) {
          headlines.add(('big-bonus', plan.index));
        } else if (gap.items.any((item) => RunDirector.isBigItem(item.kind))) {
          headlines.add(('big-bonus', gap.index));
        }

        if (plan.index >= 25 && director.allowsSqueezeWarning(plan.index)) {
          headlines.add(('squeeze', plan.index));
          director.onSqueezeWarning(plan.index);
        }
      }

      for (var left = 0; left < headlines.length; left++) {
        for (var right = left + 1; right < headlines.length; right++) {
          expect(
            headlines[right].$2 - headlines[left].$2,
            greaterThanOrEqualTo(8),
            reason: 'seed $seed: ${headlines[left]} then ${headlines[right]}',
          );
        }
      }
    }
  });

  test('WP-D filters keep timing rolls off the layout stream', () {
    List<(SlotPlan, GapPlan)> course(RunDirector director) {
      final out = <(SlotPlan, GapPlan)>[];
      for (var slot = 0; slot < 80; slot++) {
        final plan = director.nextSlot(DirectorContext.open(711));
        out.add((plan, director.nextGap(DirectorContext.open(711), plan)));
      }
      return out;
    }

    final plain = course(
      RunDirector(
        seed: 5,
        enabled: ElementId.values.toSet(),
        met: ElementId.values.toSet(),
      ),
    );
    final mixedDirector = RunDirector(
      seed: 5,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );
    final mixed = <(SlotPlan, GapPlan)>[];
    for (var slot = 0; slot < 80; slot++) {
      mixedDirector.rollSqueezeAt(slot.toDouble(), hoop: slot);
      mixedDirector.rollBigHoopsDuration();
      mixedDirector.rollPuzzleBonus();
      final plan = mixedDirector.nextSlot(DirectorContext.open(711));
      mixed.add((plan, mixedDirector.nextGap(DirectorContext.open(711), plan)));
    }

    expect(mixed.map((entry) => entry.$1), plain.map((entry) => entry.$1));
    expect(mixed.map((entry) => entry.$2), plain.map((entry) => entry.$2));
  });

  test('WP-D wiring is deterministic for the same seed', () {
    RunDirector make() => RunDirector(
      seed: 1234,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
    );

    List<(SlotPlan, GapPlan)> course(RunDirector director) {
      final out = <(SlotPlan, GapPlan)>[];
      for (var slot = 0; slot < 240; slot++) {
        final plan = director.nextSlot(DirectorContext.open(711));
        out.add((plan, director.nextGap(DirectorContext.open(711), plan)));
      }
      return out;
    }

    final first = course(make());
    final second = course(make());
    expect(first.map((entry) => entry.$1), second.map((entry) => entry.$1));
    expect(first.map((entry) => entry.$2), second.map((entry) => entry.$2));
  });
}
