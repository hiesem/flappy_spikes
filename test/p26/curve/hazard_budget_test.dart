import 'package:flappy_spikes/run/director/hazard_budget.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SlotPlan plan(
    int index,
    HoopKindId kind, {
    double tiltDeg = 0,
    MotionType? motion,
    double centreY = 100,
    bool forced = false,
  }) => SlotPlan(
    index: index,
    kind: kind,
    element: kind.element,
    trackX: index * 310,
    centreY: centreY,
    opening: 160,
    tiltDeg: tiltDeg,
    motion: motion == null
        ? null
        : MotionSpec(type: motion, halfTravel: 40, speed: 30),
    advance: 310,
    forced: forced,
  );

  test('D7 shape preview checks every window without consuming the ledger', () {
    final budget = HazardBudget();
    final saws = [for (var i = 150; i < 154; i++) plan(i, HoopKindId.saw)];
    expect(budget.allowsSequence(saws, previousY: 100, rowP90: 200), isFalse);
    // A rejected reservation must leave all 5.5 points available.
    expect(
      budget.allowsSequence(saws.take(2).toList(), previousY: 100, rowP90: 200),
      isTrue,
    );
    budget.add(plan(149, HoopKindId.saw));
    expect(
      budget.allowsSequence(saws.take(2).toList(), previousY: 100, rowP90: 200),
      isFalse,
    );
  });

  test(
    'the cost table covers every element, tilt, motion, delta and squeeze',
    () {
      final budget = HazardBudget();
      const elements = [
        HoopKindId.normal,
        HoopKindId.bullseye,
        HoopKindId.fever,
        HoopKindId.luckySpin,
        HoopKindId.portal,
        HoopKindId.rideRing,
        HoopKindId.saw,
        HoopKindId.switchRing,
        HoopKindId.spring,
        HoopKindId.pair,
        HoopKindId.train,
      ];
      const tilts = [0.0, 10.0, 20.0, 30.0, 45.0];
      const motions = [
        null,
        MotionType.rail,
        MotionType.swing,
        MotionType.horizontal,
        MotionType.diagonal,
        MotionType.orbit,
        MotionType.rock,
      ];
      const elementCosts = {
        HoopKindId.normal: 0.0,
        HoopKindId.bullseye: 0.0,
        HoopKindId.fever: 0.0,
        HoopKindId.luckySpin: 0.0,
        HoopKindId.portal: 0.0,
        HoopKindId.rideRing: 0.0,
        HoopKindId.saw: 2.0,
        HoopKindId.switchRing: 1.5,
        HoopKindId.spring: .5,
        HoopKindId.pair: .5,
        HoopKindId.train: .5,
      };
      const tiltCosts = [0.0, .25, .25, 1.0, 1.5];
      const motionCosts = [0.0, 1.0, 1.0, 1.25, 1.25, 1.25, 1.25];
      const zeroCostElements = {
        HoopKindId.bullseye,
        HoopKindId.fever,
        HoopKindId.luckySpin,
        HoopKindId.portal,
        HoopKindId.rideRing,
      };

      for (final element in elements) {
        for (var tiltIndex = 0; tiltIndex < tilts.length; tiltIndex++) {
          for (
            var motionIndex = 0;
            motionIndex < motions.length;
            motionIndex++
          ) {
            for (final aboveP90 in [false, true]) {
              for (final squeeze in [false, true]) {
                final expected = zeroCostElements.contains(element)
                    ? 0.0
                    : elementCosts[element]! +
                          tiltCosts[tiltIndex] +
                          motionCosts[motionIndex] +
                          (aboveP90 ? 1 : 0) +
                          (squeeze ? 1 : 0);
                final actual = budget.costOf(
                  plan(
                    160,
                    element,
                    tiltDeg: tilts[tiltIndex],
                    motion: motions[motionIndex],
                    centreY: aboveP90 ? 150 : 100,
                  ),
                  previousY: 100,
                  rowP90: 40,
                  squeeze: squeeze,
                );
                expect(actual, expected);
              }
            }
          }
        }
      }
    },
  );

  test('the budget curve interpolates its keyframes', () {
    final budget = HazardBudget();
    expect(budget.budgetAt(-1), 0);
    expect(budget.budgetAt(0), 0);
    expect(budget.budgetAt(1), closeTo(1 / 6, 1e-12));
    expect(budget.budgetAt(3), .5);
    expect(budget.budgetAt(6), closeTo(8 / 7, 1e-12));
    expect(budget.budgetAt(10), 2);
    expect(budget.budgetAt(17), closeTo(37 / 15, 1e-12));
    expect(budget.budgetAt(25), 3);
    expect(budget.budgetAt(37), 3.48);
    expect(budget.budgetAt(50), 4);
    expect(budget.budgetAt(75), 4.5);
    expect(budget.budgetAt(100), 5);
    expect(budget.budgetAt(125), 5.25);
    expect(budget.budgetAt(150), 5.5);
    expect(budget.budgetAt(1000), 5.5);
  });

  test(
    'the ledger sums only the last four slots including the current one',
    () {
      final budget = HazardBudget();

      for (final index in [100, 101, 102, 103]) {
        budget.add(plan(index, HoopKindId.saw));
      }
      expect(budget.allows(plan(104, HoopKindId.saw)), isFalse); // 8 > 5.16
      budget.add(plan(104, HoopKindId.saw));
      expect(budget.allows(plan(105, HoopKindId.normal)), isFalse); // 8 > 5.2
      budget.add(plan(105, HoopKindId.normal));
      expect(budget.allows(plan(106, HoopKindId.normal)), isTrue); // 4 ≤ 5.24
      budget.add(plan(106, HoopKindId.normal));
      expect(budget.allows(plan(107, HoopKindId.normal)), isTrue); // 2 ≤ 5.28
    },
  );

  test('a following-slot reservation uses the preceding two slots', () {
    final budget = HazardBudget();
    for (final index in [100, 101, 102, 103]) {
      budget.add(plan(index, HoopKindId.saw));
    }

    // Hoops 100–103 cost 8, but the current slot plus the reserved next slot
    // are the other two entries of the four-slot window. Only hoops 102–103
    // are still relevant, so 4 fits the budget at 105.
    expect(
      budget.allowsFollowing(
        plan(104, HoopKindId.normal),
        nextCost: 0,
        nextIndex: 105,
      ),
      isTrue,
    );
  });

  test('the oldest cost expires when the fifth slot is checked', () {
    final budget = HazardBudget();
    budget.add(plan(100, HoopKindId.saw));
    budget.add(plan(101, HoopKindId.spring));
    budget.add(plan(102, HoopKindId.spring));
    budget.add(plan(103, HoopKindId.spring));

    // Hoop 100's cost expires when hoop 104 is the fifth slot checked: the
    // four slots 101–104 cost 1.5 + 2 = 3.5, not 5.5.
    expect(budget.allows(plan(104, HoopKindId.saw)), isTrue);
    budget.add(plan(104, HoopKindId.saw));
    // Hoop 101 also expires here: the four slots 102–105 cost 3 + 2 = 5.
    expect(budget.allows(plan(105, HoopKindId.saw)), isTrue);
  });

  test('downgrade checks the preceding three slots, not four', () {
    final budget = HazardBudget();
    budget.add(plan(100, HoopKindId.saw));
    budget.add(plan(101, HoopKindId.spring));
    budget.add(plan(102, HoopKindId.spring));
    budget.add(plan(103, HoopKindId.spring));
    final original = plan(
      104,
      HoopKindId.switchRing,
      tiltDeg: 45,
      motion: MotionType.horizontal,
    );

    final downgraded = budget.downgrade(original);
    expect(downgraded.motion, isNull);
    expect(downgraded.tiltDeg, 45);
    expect(downgraded.hazardCost, 3);
  });

  test('downgrade applies one step when dropping motion is enough', () {
    final budget = HazardBudget();
    budget.add(plan(150, HoopKindId.switchRing));
    budget.add(plan(149, HoopKindId.spring));
    final original = plan(
      151,
      HoopKindId.normal,
      tiltDeg: 45,
      motion: MotionType.horizontal,
      centreY: 150,
    );
    final downgraded = budget.downgrade(original, previousY: 100, rowP90: 40);

    expect(downgraded.motion, isNull);
    expect(downgraded.tiltDeg, 45);
    expect(downgraded.centreY, 150);
    expect(downgraded.hazardCost, 2.5);
  });

  test('downgrade continues to tilt when dropping motion is not enough', () {
    final budget = HazardBudget();
    budget.add(plan(150, HoopKindId.switchRing, centreY: 100));
    budget.add(plan(149, HoopKindId.spring, centreY: 100));
    budget.add(plan(149, HoopKindId.spring, centreY: 100));
    final original = plan(
      151,
      HoopKindId.switchRing,
      tiltDeg: 45,
      motion: MotionType.horizontal,
      centreY: 150,
    );
    final downgraded = budget.downgrade(original, previousY: 100, rowP90: 40);

    expect(downgraded.motion, isNull);
    expect(downgraded.tiltDeg, 15);
    expect(downgraded.centreY, 150);
    expect(downgraded.kind, HoopKindId.switchRing);
    expect(downgraded.hazardCost, 2.75);
  });

  test('downgrade reduces delta-y before replacing a special hoop', () {
    final budget = HazardBudget();
    budget.add(plan(150, HoopKindId.spring, centreY: 100));
    final original = plan(
      0,
      HoopKindId.saw,
      tiltDeg: 45,
      motion: MotionType.horizontal,
      centreY: 150,
    );
    final downgraded = budget.downgrade(original, previousY: 100, rowP90: 40);

    expect(downgraded.kind, HoopKindId.normal);
    expect(downgraded.motion, isNull);
    expect(downgraded.tiltDeg, 15);
    expect(downgraded.centreY, 140);
    expect(downgraded.hazardCost, .25);
  });

  test('reward and ride slots always cost zero', () {
    final budget = HazardBudget();
    final zeroSlots = <SlotPlan>[
      for (final kind in const [
        HoopKindId.bullseye,
        HoopKindId.fever,
        HoopKindId.luckySpin,
        HoopKindId.portal,
        HoopKindId.rideRing,
      ])
        plan(100, kind, tiltDeg: 45, motion: MotionType.rock, centreY: 150),
      plan(
        100,
        HoopKindId.normal,
        tiltDeg: 45,
        motion: MotionType.rock,
        centreY: 150,
      ).copyWith(cometHang: true),
      plan(
        100,
        HoopKindId.normal,
        tiltDeg: 45,
        motion: MotionType.rock,
        centreY: 150,
      ).copyWith(duringRide: true),
    ];

    for (final slot in zeroSlots) {
      expect(
        budget.costOf(slot, previousY: 100, rowP90: 40, squeeze: true),
        0,
        reason: slot.kind.name,
      );
    }
  });

  test('downgrade can reduce delta-y to the row p90', () {
    final budget = HazardBudget();
    budget.add(plan(150, HoopKindId.saw, centreY: 100));
    budget.add(plan(149, HoopKindId.saw, centreY: 100));
    budget.add(plan(148, HoopKindId.spring, centreY: 100));
    final original = plan(
      151,
      HoopKindId.normal,
      tiltDeg: 45,
      motion: MotionType.horizontal,
      centreY: 150,
    );
    final downgraded = budget.downgrade(original, previousY: 100, rowP90: 40);

    expect(downgraded.kind, HoopKindId.normal);
    expect(downgraded.motion, isNull);
    expect(downgraded.tiltDeg, 15);
    expect(downgraded.centreY, 140);
    expect(downgraded.hazardCost, .25);
  });

  test('forced slots are never changed but their cost enters the ledger', () {
    final budget = HazardBudget();
    final forced = plan(
      100,
      HoopKindId.saw,
      motion: MotionType.horizontal,
      centreY: 150,
      forced: true,
    );
    expect(budget.allows(forced, previousY: 100, rowP90: 40), isTrue);
    expect(budget.downgrade(forced, previousY: 100, rowP90: 40), same(forced));
    budget.add(forced, previousY: 100, rowP90: 40);

    final next = plan(101, HoopKindId.saw, centreY: 100);
    expect(budget.allows(next), isFalse);
    expect(next.hazardCost, 0);
    expect(budget.costOf(next), 2);
  });

  test('the module is deterministic and never advances a random stream', () {
    final first = HazardBudget();
    final second = HazardBudget();
    final input = plan(
      100,
      HoopKindId.switchRing,
      tiltDeg: 45,
      motion: MotionType.rock,
      centreY: 150,
    );
    final args = (previousY: 100.0, rowP90: 40.0, squeeze: true);

    expect(
      first.costOf(
        input,
        previousY: args.previousY,
        rowP90: args.rowP90,
        squeeze: args.squeeze,
      ),
      second.costOf(
        input,
        previousY: args.previousY,
        rowP90: args.rowP90,
        squeeze: args.squeeze,
      ),
    );
    expect(
      first.downgrade(
        input,
        previousY: args.previousY,
        rowP90: args.rowP90,
        squeeze: args.squeeze,
      ),
      second.downgrade(
        input,
        previousY: args.previousY,
        rowP90: args.rowP90,
        squeeze: args.squeeze,
      ),
    );
  });
}
