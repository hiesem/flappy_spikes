import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/services/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.3.1 §17 at most `ride_portal_max` portal rides per run (default 2,
/// 0 = no limit), counted per run in the director; a revive does not reset
/// the count; comets are not affected.
final Set<ElementId> _all = ElementId.values.toSet();

void _useTuning(Map<String, String> extra) {
  Tuning.instance = Tuning(
    active: TuningValues.resolve({'ui_unlock_best': '0', ...extra}),
  );
  TuningValues.current = Tuning.instance.active;
}

/// Plans [hoops] slots; [reviveAt] hoop indexes get a revive first.
List<SlotPlan> _run(
  RunDirector d, {
  int hoops = 120,
  Set<int> reviveAt = const {},
}) {
  final ctx = DirectorContext.open(711);
  final out = <SlotPlan>[];
  for (var k = 0; k < hoops; k++) {
    if (reviveAt.contains(d.hoopIndex)) d.onRevive();
    final s = d.nextSlot(ctx);
    d.nextGap(ctx, s);
    out.add(s);
  }
  return out;
}

int _portals(List<SlotPlan> plans) =>
    plans.where((p) => p.kind == HoopKindId.portal).length;

RunDirector _director({int seed = 4}) => RunDirector(
  seed: seed,
  tables: DirectorTables.prd2,
  enabled: _all,
  met: _all,
);

void main() {
  tearDown(() => _useTuning(const {}));

  test('§17 default ride_portal_max = 2', () {
    expect(DirectorTables.prd2.portalMax, 2);
  });

  for (final seed in [1, 4, 9]) {
    test('§17 seed $seed: ride_portal_then [10,10], cap 2: a 120-hoop run '
        'places exactly 2 portals', () {
      _useTuning({'ride_portal_then': '[10,10]'});
      final d = _director(seed: seed);
      final plans = _run(d);
      expect(_portals(plans), 2);
      expect(d.portalCount, 2);
      expect(d.portalCapped, isTrue);
    });

    test('§17 seed $seed: cap 0 (no limit) places more', () {
      _useTuning({'ride_portal_then': '[10,10]', 'ride_portal_max': '0'});
      final d = _director(seed: seed);
      final plans = _run(d);
      expect(_portals(plans), greaterThan(2));
      expect(d.portalCapped, isFalse);
    });

    test('§17 seed $seed: a revive between the portals does not reset the '
        'count', () {
      _useTuning({'ride_portal_then': '[10,10]'});
      // Find the first portal, then revive right after it.
      final probe = _run(_director(seed: seed));
      final first = probe.firstWhere((p) => p.kind == HoopKindId.portal).index;
      final d = _director(seed: seed);
      final plans = _run(d, reviveAt: {first + 2, first + 15, first + 40});
      expect(_portals(plans), 2);
      expect(d.portalCount, 2);
    });
  }

  test('§17 cap 3 is honoured too', () {
    _useTuning({'ride_portal_then': '[10,10]', 'ride_portal_max': '3'});
    final plans = _run(_director());
    expect(_portals(plans), 3);
  });

  test('§17 a portal turned plain (revive before it spawned) is owed again '
      'and does not count', () {
    _useTuning({'ride_portal_then': '[10,10]'});
    final d = _director();
    final ctx = DirectorContext.open(711);
    SlotPlan? portal;
    for (var k = 0; k < 120 && portal == null; k++) {
      final s = d.nextSlot(ctx);
      d.nextGap(ctx, s);
      if (s.kind == HoopKindId.portal) portal = s;
    }
    expect(portal, isNotNull);
    expect(d.portalCount, 1);
    d.plainSlot(portal!, ctx);
    expect(d.portalCount, 0);
    final rest = _run(d, hoops: 120);
    expect(_portals(rest), 2);
  });

  test('§17 comets are not affected by the cap', () {
    _useTuning({
      'ride_portal_then': '[10,10]',
      'ride_portal_max': '1',
      'ride_comet_chance': '1',
    });
    final d = _director();
    final plans = _run(d, hoops: 200);
    expect(_portals(plans), 1);
    expect(plans.where((p) => p.cometHang), isNotEmpty);
  });
}
