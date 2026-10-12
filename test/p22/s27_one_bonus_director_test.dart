import 'dart:math';

import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.2 §27 one bonus at a time — the director side (pure Dart): the
/// activity state, the blocked reward items, the 2-hoop cool-down, the
/// deferred schedules and a 500-seed statistics run.
final Set<ElementId> all = ElementId.values.toSet();

bool rewardSlot(SlotPlan s) => RunDirector.isRewardSlot(s);

Iterable<GapItemPlan> rewardItems(GapPlan g) =>
    g.items.where((i) => RunDirector.isRewardItem(i.kind));

/// The starter of an activity a slot / gap brings (the bird takes it).
RunActivity? starterOf(SlotPlan s, GapPlan g) {
  if (s.kind == HoopKindId.portal) return RunActivity.portal;
  if (s.cometHang) return RunActivity.comet;
  for (final i in g.items) {
    switch (i.kind) {
      case ElementId.piggy:
        return RunActivity.piggy;
      case ElementId.jar:
        return RunActivity.jar;
      case ElementId.capsule:
        return RunActivity.capsule;
      default:
        break;
    }
  }
  return null;
}

void main() {
  group('§27.1 activities', () {
    test('comet / portal ride, piggy / jar run and a capsule power-up are '
        'activities; egg / chick, shield, extra life, Big Hoops, fire and '
        'FEVER are not', () {
      RunState fresh() => RunState(seed: 1, viewHeight: 711);
      expect(RunActivity.of(fresh()), isNull);
      expect(
        RunActivity.of(fresh()..ride = RideState(kind: RideKind.portal)),
        RunActivity.portal,
      );
      expect(
        RunActivity.of(fresh()..ride = RideState(kind: RideKind.comet)),
        RunActivity.comet,
      );
      expect(
        RunActivity.of(
          fresh()
            ..timed = TimedPowerupState(type: TimedPowerup.comet, duration: 10),
        ),
        RunActivity.comet,
      );
      expect(RunActivity.of(fresh()..piggy = PiggyState()), RunActivity.piggy);
      expect(RunActivity.of(fresh()..jar = JarState()), RunActivity.jar);
      for (final t in [
        TimedPowerup.hourglass,
        TimedPowerup.mini,
        TimedPowerup.frenzy,
      ]) {
        expect(
          RunActivity.of(
            fresh()..timed = TimedPowerupState(type: t, duration: 10),
          ),
          RunActivity.capsule,
        );
      }
      final passive = fresh()
        ..egg = EggState()
        ..shield = true
        ..extraLife = true
        ..bigHoops = BigHoopsState(duration: 30, start: 0)
        ..onFire = true;
      expect(RunActivity.of(passive), isNull);
    });
  });

  group('§27.2 what is blocked', () {
    test('during an activity no reward ring / comet hoop / reward item is '
        'planned; obstacle rings still are; the activity\'s own items keep '
        'coming', () {
      var obstacles = 0, coins = 0;
      for (var seed = 1; seed <= 100; seed++) {
        final d = RunDirector(
          seed: seed,
          enabled: all,
          met: all,
          startHoopIndex: 20,
        );
        for (var k = 0; k < 80; k++) {
          final ctx = DirectorContext.open(711, piggyRunning: k < 6).copyActivity();
          final s = d.nextSlot(ctx);
          final g = d.nextGap(ctx, s);
          expect(rewardSlot(s), isFalse, reason: 'seed $seed $s');
          expect(rewardItems(g), isEmpty, reason: 'seed $seed $g');
          if (s.kind != HoopKindId.normal) obstacles++;
          coins += g.items.where((i) => i.kind == ElementId.piggyCoins).length;
        }
      }
      expect(obstacles, greaterThan(1000), reason: 'obstacle rings continue');
      expect(coins, greaterThan(300), reason: 'the piggy keeps its coins');
    });

    test('a debug force of a reward waits for the activity too (exclusivity)',
        () {
      final d = RunDirector(
        seed: 3,
        enabled: all,
        met: all,
        startHoopIndex: 20,
        forced: [ElementId.heart, ElementId.pair],
      );
      for (var k = 0; k < 5; k++) {
        final ctx = DirectorContext.open(711).copyActivity();
        final s = d.nextSlot(ctx);
        final g = d.nextGap(ctx, s);
        expect(s.kind, isNot(HoopKindId.pair));
        expect(rewardItems(g), isEmpty);
      }
      expect(d.forcedQueue, containsAll([ElementId.heart, ElementId.pair]));
    });

    test('cool-down: after the end (next slot n) reward rings come from slot '
        'n + 1, gap rewards from gap n', () {
      for (var seed = 1; seed <= 200; seed++) {
        final d = RunDirector(
          seed: seed,
          enabled: all,
          met: all,
          startHoopIndex: 30,
        );
        for (var k = 0; k < 3; k++) {
          final ctx = DirectorContext.open(711).copyActivity();
          d.nextGap(ctx, d.nextSlot(ctx));
        }
        final n = d.hoopIndex;
        for (var k = 0; k < 6; k++) {
          final ctx = DirectorContext.open(
            711,
          ).copyActivity(on: false, endedAt: n);
          final s = d.nextSlot(ctx);
          final g = d.nextGap(ctx, s);
          if (s.index < n + 1) expect(rewardSlot(s), isFalse);
          if (g.index < n) expect(rewardItems(g), isEmpty);
        }
      }
    });

    test('scheduled items wait: a portal / comet hoop due during a piggy run '
        'comes at the first allowed slot after the pay-out + 2 hoops', () {
      var portals = 0, comets = 0;
      for (var seed = 1; seed <= 100; seed++) {
        final d = RunDirector(seed: seed, enabled: all, met: all);
        final due = d.portalAt;
        // The piggy run covers the portal's slot.
        var k = 0;
        for (; d.hoopIndex <= due + 2; k++) {
          final on = d.hoopIndex >= due - 3;
          final ctx = on
              ? DirectorContext.open(711, piggyRunning: true).copyActivity()
              : DirectorContext.open(711);
          final s = d.nextSlot(ctx);
          if (on) expect(s.kind, isNot(HoopKindId.portal));
          d.nextGap(ctx, s);
        }
        final n = d.hoopIndex;
        int? portalAt;
        for (var j = 0; j < 20 && portalAt == null; j++) {
          final ctx = DirectorContext.open(
            711,
          ).copyActivity(on: false, endedAt: n);
          final s = d.nextSlot(ctx);
          d.nextGap(ctx, s);
          if (s.kind == HoopKindId.portal) portalAt = s.index;
        }
        expect(portalAt, n + 1, reason: 'seed $seed');
        portals++;
        // The comet hoop: due during the run, after it at the first
        // allowed slot (≥ n + 1; it also keeps 10 hoops from the portal).
        final c = RunDirector(seed: seed, enabled: all..remove(ElementId.portal), met: all);
        all.add(ElementId.portal);
        final cd = c.cometAt;
        for (; c.hoopIndex <= cd + 2;) {
          final on = c.hoopIndex >= cd - 2;
          final ctx = on
              ? DirectorContext.open(711, jarRunning: true).copyActivity()
              : DirectorContext.open(711);
          final s = c.nextSlot(ctx);
          if (on) expect(s.cometHang, isFalse);
          c.nextGap(ctx, s);
        }
        final m = c.hoopIndex;
        int? cometAt;
        for (var j = 0; j < 20 && cometAt == null; j++) {
          final ctx = DirectorContext.open(
            711,
          ).copyActivity(on: false, endedAt: m);
          final s = c.nextSlot(ctx);
          c.nextGap(ctx, s);
          if (s.cometHang) cometAt = s.index;
        }
        expect(cometAt, isNotNull, reason: 'seed $seed');
        expect(cometAt!, greaterThanOrEqualTo(m + 1));
        expect(cometAt - (m + 1), lessThanOrEqualTo(3), reason: 'seed $seed');
        comets++;
      }
      expect(portals, 100);
      expect(comets, 100);
    });

    test('passive states (egg / chick, shield, Big Hoops, fire) block neither '
        'a heart nor a capsule', () {
      var hearts = 0, capsules = 0;
      for (var seed = 1; seed <= 60; seed++) {
        final d = RunDirector(seed: seed, enabled: all, met: all);
        final heartAt = d.heartAt;
        int? heart;
        for (var k = 0; k < 120; k++) {
          final ctx = DirectorContext.open(
            711,
            eggOrChick: true,
            shieldArmed: true,
            bigHoopsMult: 1.5,
            onFire: true,
          );
          final s = d.nextSlot(ctx);
          final g = d.nextGap(ctx, s);
          if (g.items.any((i) => i.kind == ElementId.heart)) {
            hearts++;
            heart ??= s.index;
          }
          capsules += g.items.where((i) => i.kind == ElementId.capsule).length;
        }
        expect(heart, isNotNull);
        expect(heart! - heartAt, lessThan(3));
      }
      expect(hearts, greaterThan(60));
      expect(capsules, greaterThan(30));
    });
  });

  test('§27.5 statistics over 500 seeds: never two activities at once, never '
      'a reward item during an activity or its 2-hoop cool-down', () {
    var activities = 0;
    for (var seed = 1; seed <= 500; seed++) {
      final d = RunDirector(seed: seed, enabled: all, met: all);
      final r = Random(seed);
      RunActivity? on;
      var until = -1;
      var endedAt = -99;
      // The starter planned in slot / gap i is taken when the bird gets
      // there: the planner is one slot ahead, so it starts 1 slot later.
      final pending = <int, RunActivity>{};
      for (var k = 0; k < 150; k++) {
        final i = d.hoopIndex;
        if (on != null && i >= until) {
          on = null;
          endedAt = i;
        }
        final start = pending.remove(i);
        if (start != null) {
          expect(on, isNull, reason: 'seed $seed: two activities at $i');
          on = start;
          until = i + 3 + r.nextInt(8);
          activities++;
        }
        final ctx = DirectorContext.open(
          711,
          piggyRunning: on == RunActivity.piggy,
          jarRunning: on == RunActivity.jar,
          timedPowerupRunning: on == RunActivity.capsule,
          rideActive: on == RunActivity.comet || on == RunActivity.portal,
        ).copyActivity(on: on != null, endedAt: endedAt);
        final s = d.nextSlot(ctx);
        final g = d.nextGap(ctx, s);
        final blockedSlot = on != null || s.index < endedAt + 1;
        final blockedGap = on != null || g.index < endedAt;
        if (blockedSlot) expect(rewardSlot(s), isFalse, reason: 'seed $seed $s');
        if (blockedGap) {
          expect(rewardItems(g), isEmpty, reason: 'seed $seed $g');
        }
        final a = starterOf(s, g);
        if (a != null) {
          // Ignored if it would start while one runs (cannot happen: the
          // starters are reward items).
          expect(on, isNull, reason: 'seed $seed: starter during $on');
          pending[i + 1] = a;
        }
      }
    }
    expect(activities, greaterThan(500));
  });
}

extension on DirectorContext {
  /// A copy with the §27 activity fields (the factory has no parameters
  /// for them on purpose: the run controller fills them).
  DirectorContext copyActivity({bool on = true, int endedAt = -99}) =>
      DirectorContext(
        viewHeight: viewHeight,
        topTooth: topTooth,
        floorTooth: floorTooth,
        squeezeTopTooth: squeezeTopTooth,
        squeezeFloorTooth: squeezeFloorTooth,
        squeezeWindow: squeezeWindow,
        rideActive: rideActive,
        ride: ride,
        timedPowerupRunning: timedPowerupRunning,
        onFire: onFire,
        shieldArmed: shieldArmed,
        extraLifeActive: extraLifeActive,
        eggOrChick: eggOrChick,
        piggyRunning: piggyRunning,
        jarRunning: jarRunning,
        shieldPickupsThisRun: shieldPickupsThisRun,
        scrollSpeed: scrollSpeed,
        runClock: runClock,
        bigHoopsMult: bigHoopsMult,
        prevCentreY: prevCentreY,
        hudBottom: hudBottom,
        featherWanted: featherWanted,
        puzzleMask: puzzleMask,
        activity: on,
        activityEndedAtSlot: endedAt,
      );
}
