import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.3.1 §17 at most `ride_portal_max` portal rides per run (default 2,
/// 0 = no limit), counted per run in the director (monotonic: every placed
/// portal counts, also one later turned plain / owed, and debug-forced
/// ones; at the cap nothing is owed); a revive does not reset the count;
/// comets are not affected.
final Set<ElementId> _all = ElementId.values.toSet();

void _useTuning(Map<String, String> extra) {
  TuningValues.current = TuningValues.resolve({
    'ui_unlock_best': '0',
    ...extra,
  });
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

  /// Plans until the first portal; returns it.
  SlotPlan firstPortal(RunDirector d, DirectorContext ctx) {
    for (var k = 0; k < 120; k++) {
      final s = d.nextSlot(ctx);
      d.nextGap(ctx, s);
      if (s.kind == HoopKindId.portal) return s;
    }
    fail('no portal in 120 slots');
  }

  // P1-06: the count is monotonic — every placed portal counts, also one
  // turned plain (revive / ride) or cleared off-screen (activity).
  test('§17 a placed portal turned plain (revive before it spawned) still '
      'counts: owed once below the cap, 2 placements in all', () {
    _useTuning({'ride_portal_then': '[10,10]'});
    final d = _director();
    final ctx = DirectorContext.open(711);
    final portal = firstPortal(d, ctx);
    expect(d.portalCount, 1);
    d.onRevive();
    d.plainSlot(portal, ctx);
    expect(d.portalCount, 1);
    final rest = _run(d, hoops: 120);
    expect(1 + _portals(rest), 2);
    expect(d.portalCount, 2);
    expect(d.portalCapped, isTrue);
  });

  test('§17 a spawned off-screen portal cleared by an activity (oweSlot) '
      'still counts', () {
    _useTuning({'ride_portal_then': '[10,10]'});
    final d = _director();
    final ctx = DirectorContext.open(711);
    final portal = firstPortal(d, ctx);
    // It spawned (one more slot planned ahead), then an activity clears it.
    final next = d.nextSlot(ctx);
    d.nextGap(ctx, next);
    d.oweSlot(portal);
    expect(d.portalCount, 1);
    final rest = _run(d, hoops: 120);
    expect(1 + _portals([next, ...rest]), 2);
    expect(d.portalCount, 2);
  });

  test('§17 at the cap a portal turned plain / cleared owes nothing', () {
    _useTuning({'ride_portal_then': '[10,10]'});
    final d = _director();
    final ctx = DirectorContext.open(711);
    final plans = <SlotPlan>[];
    for (var k = 0; k < 120 && d.portalCount < 2; k++) {
      final s = d.nextSlot(ctx);
      d.nextGap(ctx, s);
      plans.add(s);
    }
    expect(d.portalCapped, isTrue);
    final second = plans.lastWhere((p) => p.kind == HoopKindId.portal);
    d.onRevive();
    d.plainSlot(second, ctx);
    d.oweSlot(second);
    expect(d.portalCount, 2);
    expect(_portals(_run(d, hoops: 120)), 0);
    expect(d.portalCount, 2);
  });

  // P1-07: debug-forced portals respect the cap.
  test('§17 a debug-forced portal counts and, at the cap, is discarded '
      '(not owed); the next debug item still comes', () {
    _useTuning({'ride_portal_then': '[10,10]'});
    final d = _director();
    expect(_portals(_run(d)), 2);
    expect(d.portalCapped, isTrue);
    d.debugForceRide(RideId.cannon);
    final after = _run(d, hoops: 20);
    expect(_portals(after), 0);
    expect(d.portalCount, 2);
    expect(d.forcedQueue, isNot(contains(ElementId.portal)));
    // The discarded portal does not block a later forced item.
    expect(d.debugForce(ElementId.normalHoop), isTrue);
    _run(d, hoops: 3);
    expect(d.forcedQueue, isEmpty);
    expect(_portals(_run(d, hoops: 40)), 0);
  });

  test('§17 a debug-forced portal below the cap counts', () {
    _useTuning({
      'ride_portal_then': '[200,200]',
      'ride_portal_first': '[200,200]',
    });
    final d = _director();
    final pre = _run(d, hoops: 10);
    expect(_portals(pre), 0);
    d.debugForceRide(RideId.cannon);
    final forced = _run(d, hoops: 20);
    expect(_portals(forced), 1);
    expect(d.portalCount, 1);
  });

  test('§17 cap 0 (no limit): forcing a portal after many still works', () {
    _useTuning({'ride_portal_then': '[10,10]', 'ride_portal_max': '0'});
    final d = _director();
    expect(_portals(_run(d)), greaterThan(2));
    final before = d.portalCount;
    d.debugForceRide(RideId.cannon);
    expect(_portals(_run(d, hoops: 3)), greaterThanOrEqualTo(1));
    expect(d.portalCount, greaterThan(before));
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
