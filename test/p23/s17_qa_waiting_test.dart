import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S8-11 §17.3 rule 4 a gap bonus blocked by cooldown becomes due', () {
    const enabled = {ElementId.normalHoop, ElementId.piggy};
    var eligibleDraws = 0;
    for (var seed = 1; seed <= 60; seed++) {
      RunDirector make() => RunDirector(
        seed: seed,
        enabled: enabled,
        met: enabled,
        startHoopIndex: 30,
      );
      final free = make();
      final freeSlot = free.nextSlot(DirectorContext.open(711));
      final draw = free.nextGap(DirectorContext.open(711), freeSlot);
      if (!draw.items.any((p) => p.kind == ElementId.piggy)) continue;
      eligibleDraws++;
      final blocked = make();
      const cooldown = DirectorContext(
        viewHeight: 711,
        topTooth: 44,
        floorTooth: 667,
        activityEndedAtSlot: 31,
      );
      final slot = blocked.nextSlot(cooldown);
      expect(blocked.nextGap(cooldown, slot).items, isEmpty);
      expect(
        blocked.waitingItem,
        ElementId.piggy,
        reason: 'seed $seed drew a pig, so cooldown must delay that draw',
      );
      final next = blocked.nextSlot(DirectorContext.open(711));
      expect(
        blocked.nextGap(DirectorContext.open(711), next).items.single.kind,
        ElementId.piggy,
        reason: 'the delayed pig comes at the first allowed gap',
      );
    }
    expect(eligibleDraws, greaterThan(0));
  });
}
