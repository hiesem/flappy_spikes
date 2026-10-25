import 'package:flappy_spikes/run/director/formations.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug', () {
    final d = RunDirector(seed: 0, enabled: ElementId.values.toSet(), met: ElementId.values.toSet(), startHoopIndex: 150);
    final plans = <SlotPlan>[];
    for (var k = 0; k < 400; k++) {
      final ctx = DirectorContext.open(711);
      final p = d.nextSlot(ctx);
      d.nextGap(ctx, p);
      plans.add(p);
    }
    final starts = <int>[];
    FormationId? previous;
    for (final p in plans) {
      final id = p.formation;
      if (id != null && id != previous) starts.add(p.index);
      previous = id;
    }
    for (var k=1;k<starts.length;k++) {
      if (starts[k]-starts[k-1] > 20) {
        print('${starts[k-1]} .. ${starts[k]}');
        for (final p in plans) if (p.index >= starts[k-1] && p.index <= starts[k]) print('${p.index} f=${p.formation?.name} kind=${p.kind.name} calm=${p.calm} ride=${p.duringRide} forced=${p.forced}');
      }
    }
  });
}
