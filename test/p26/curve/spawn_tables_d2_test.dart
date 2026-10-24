import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

List<(SlotPlan, GapPlan)> _course(
  int seed, {
  int count = 40,
  int startHoopIndex = 0,
  bool squeeze = false,
  List<ElementId> forced = const [],
  bool portals = true,
}) {
  final enabled = ElementId.values.toSet();
  if (!portals) enabled.remove(ElementId.portal);
  final director = RunDirector(
    seed: seed,
    enabled: enabled,
    met: ElementId.values.toSet(),
    startHoopIndex: startHoopIndex,
    forced: forced,
  );
  final plans = <(SlotPlan, GapPlan)>[];
  for (var i = 0; i < count; i++) {
    final context = DirectorContext.open(
      711,
      squeezeWindow: squeeze,
      squeezeInset: squeeze ? 54 : 0,
    );
    final slot = director.nextSlot(context);
    plans.add((slot, director.nextGap(context, slot)));
  }
  return plans;
}

void main() {
  test('D2 / C3 firstPossible and first natural appearances', () {
    expect(ElementId.switchRing.firstPossible, 15);
    expect(ElementId.movingRing.firstPossible, 25);
    expect(ElementId.saw.firstPossible, 30);
    expect(ElementId.portal.firstPossible, 12);

    for (var seed = 1; seed <= 200; seed++) {
      final plans = _course(seed, count: 40);
      for (final (slot, _) in plans) {
        if (slot.index < 15) {
          expect(slot.kind, isNot(HoopKindId.switchRing), reason: 'seed $seed');
        }
        if (slot.index < 25) {
          expect(slot.motion, isNull, reason: 'seed $seed');
        }
        if (slot.index < 30) {
          expect(slot.kind, isNot(HoopKindId.saw), reason: 'seed $seed');
        }
        if (slot.index < 12) {
          expect(slot.kind, isNot(HoopKindId.portal), reason: 'seed $seed');
        }
      }
      expect(
        plans.any((entry) => entry.$1.kind == HoopKindId.portal),
        isTrue,
        reason: 'seed $seed: portal schedule starts at 12–25',
      );
    }
  });

  test('D2 the early pool never yields a tilted ring at hoops 4–9', () {
    for (var seed = 1; seed <= 200; seed++) {
      final plans = _course(seed, count: 10);
      for (var index = 4; index <= 9; index++) {
        expect(plans[index].$1.tiltDeg, 0, reason: 'seed $seed hoop $index');
      }
    }

    final pool = DirectorTables.prd2.earlyPool!;
    expect(pool.from, 4);
    expect(pool.to, 9);
    expect(pool.weights, {
      EarlyPick.starTrail: 1,
      EarlyPick.bullseye: 1,
      EarlyPick.nothing: 1,
    });
  });

  test('D2 the saw weight follows the 30 / 60 / 100 keyframe curve', () {
    final saw = DirectorTables.prd2.specials[HoopKindId.saw]!;
    expect(saw.from, 30);
    expect(saw.weightAt(30), 14);
    expect(saw.weightAt(45), 17);
    expect(saw.weightAt(60), 20);
    expect(saw.weightAt(80), 23);
    expect(saw.weightAt(100), 26);
    expect(saw.weightAt(150), 26);
  });

  test(
    'D2 saw is barred from squeezes before hoop 100 and allowed from 100',
    () {
      for (var seed = 1; seed <= 200; seed++) {
        final plans = _course(
          seed,
          count: 70,
          startHoopIndex: 30,
          squeeze: true,
        );
        for (final (slot, _) in plans) {
          expect(slot.kind, isNot(HoopKindId.saw), reason: 'seed $seed');
        }
      }

      final before = _course(
        7,
        count: 1,
        startHoopIndex: 99,
        squeeze: true,
        forced: [ElementId.saw],
        portals: false,
      ).single.$1;
      expect(before.kind, isNot(HoopKindId.saw));

      final at100 = _course(
        7,
        count: 1,
        startHoopIndex: 100,
        squeeze: true,
        forced: [ElementId.saw],
        portals: false,
      ).single.$1;
      expect(at100.kind, HoopKindId.saw);
    },
  );

  test('D2 same seed and context sequence produce the same plans', () {
    final first = _course(1234, count: 150);
    final second = _course(1234, count: 150);
    expect(first.map((entry) => entry.$1).toList(), [
      for (final entry in second) entry.$1,
    ]);
    expect(first.map((entry) => entry.$2).toList(), [
      for (final entry in second) entry.$2,
    ]);
  });
}
