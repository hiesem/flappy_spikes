import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/portal_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/fever.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_spawner.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../p231/tuning_23.dart';

/// PRD-2.3 §17 one big bonus on screen: the planner rule (§17.3), the
/// waiting bonus (rule 4), the per-slot creation edge (§17.4), the narrowed
/// `clearRewardsAhead` (§17.5) and the forced scenarios (§17.6). The
/// invariant soak is `s17_soak_test.dart`.

final Set<ElementId> _all = ElementId.values.toSet();

/// Every element met: no first-meet forcing gets in the way.
final Map<String, Object> _allMet = {
  'metElements': [for (final e in ElementId.values) e.storageId],
};

Future<void> _boot(FlappySpikesGame game) async {
  await game.ready();
  game.sound.enabled = false;
  await preloadImages(game);
}

FlameTester<FlappySpikesGame> _tester({double h = 711, int seed = 5}) =>
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: seed, prefs: _allMet),
      gameSize: Vector2(320, h),
    );

bool _bigSlot(SlotPlan s) => RunDirector.isBigSlot(s);
bool _bigGap(GapPlan g) => g.items.any((i) => RunDirector.isBigItem(i.kind));

/// A pure-director course where a big bonus is open while the bird has not
/// passed it (the bird flies ≈ 2 gaps behind the slot being planned, PRD-2.2
/// §15); every big bonus is missed (no activities). Returns the number of
/// big bonuses and the slots flown.
(int, int) _modelRun(int seed, {required bool rule, int n = 120}) {
  final d = RunDirector(
    seed: seed,
    enabled: _all,
    met: _all,
    startHoopIndex: 1,
    oneBigBonus: rule,
  );
  final open = <double>[];
  var big = 0;
  for (var k = 0; k < n; k++) {
    final birdX = d.nextTrackX - 2 * RunConfig.spacing;
    open.removeWhere((x) => x <= birdX);
    final ctx = DirectorContext.open(711, bigBonusOpen: open.isNotEmpty);
    final s = d.nextSlot(ctx);
    if (RunDirector.rewardKinds.contains(s.kind)) {
      big++;
      open.add(s.trackX);
    }
    for (final a in s.attached) {
      if (RunDirector.isBigItem(a.kind)) {
        big++;
        open.add(a.trackX);
      }
    }
    final ctx2 = DirectorContext.open(711, bigBonusOpen: open.isNotEmpty);
    final g = d.nextGap(ctx2, s);
    for (final i in g.items) {
      if (RunDirector.isBigItem(i.kind)) {
        big++;
        open.add(i.toTrackX ?? i.trackX);
      }
    }
  }
  return (big, n);
}

void main() {
  group('§17.3 planner rules (pure director)', () {
    test('rule 1: while a big bonus is open no big bonus is planned '
        '(slot, gap, reward ring, portal, comet)', () {
      for (var seed = 1; seed <= 40; seed++) {
        final d = RunDirector(
          seed: seed,
          enabled: _all,
          met: _all,
          startHoopIndex: 1,
        );
        for (var k = 0; k < 150; k++) {
          final ctx = DirectorContext.open(711, bigBonusOpen: true);
          final s = d.nextSlot(ctx);
          expect(_bigSlot(s), isFalse, reason: 'seed $seed slot $s');
          final g = d.nextGap(ctx, s);
          expect(_bigGap(g), isFalse, reason: 'seed $seed gap ${g.items}');
        }
      }
    });

    test('rule 4: a big bonus drawn while blocked waits, at most one waits, '
        'and it comes before any new big draw once allowed', () {
      var placedWaiting = 0;
      for (var seed = 1; seed <= 60; seed++) {
        final d = RunDirector(
          seed: seed,
          enabled: _all,
          met: _all,
          startHoopIndex: 12,
        );
        // Blocked until something waits.
        var k = 0;
        while (k++ < 200 && d.waitingRing == null && d.waitingItem == null) {
          final ctx = DirectorContext.open(711, bigBonusOpen: true);
          final s = d.nextSlot(ctx);
          d.nextGap(ctx, s);
          // One waits at most (rule 4).
          expect(d.waitingRing != null && d.waitingItem != null, isFalse);
        }
        final ring = d.waitingRing, item = d.waitingItem;
        if (ring == null && item == null) continue;
        // More blocked slots: the waiting one stays the same.
        for (var j = 0; j < 30; j++) {
          final ctx = DirectorContext.open(711, bigBonusOpen: true);
          final s = d.nextSlot(ctx);
          d.nextGap(ctx, s);
          expect(d.waitingRing, ring, reason: 'seed $seed');
          expect(d.waitingItem, item, reason: 'seed $seed');
        }
        // Free again: the first big bonus planned is the waiting one (the
        // portal schedule is not a draw and may come first).
        for (var j = 0; j < 40; j++) {
          const ctx = DirectorContext(
            viewHeight: 711,
            topTooth: RunConfig.stripHeight,
            floorTooth: 711 - RunConfig.stripHeight,
          );
          final s = d.nextSlot(ctx);
          if (s.kind == HoopKindId.portal) {
            d.nextGap(ctx, s);
            continue;
          }
          if (_bigSlot(s)) {
            expect(item, isNull, reason: 'seed $seed: $s before $item');
            expect(s.kind, ring, reason: 'seed $seed');
            placedWaiting++;
            break;
          }
          final g = d.nextGap(ctx, s);
          final bigs = [
            for (final i in g.items)
              if (RunDirector.isBigItem(i.kind)) i.kind,
          ];
          if (bigs.isNotEmpty) {
            expect(ring, isNull, reason: 'seed $seed: $bigs before $ring');
            expect(bigs, [item], reason: 'seed $seed');
            placedWaiting++;
            break;
          }
        }
      }
      expect(placedWaiting, greaterThan(20));
    });

    test('rule 4: with a bonus waiting, a new big draw falls back to a '
        'non-big element', () {
      var fallbacks = 0;
      for (var seed = 1; seed <= 60; seed++) {
        final d = RunDirector(
          seed: seed,
          enabled: _all,
          met: _all,
          startHoopIndex: 12,
        );
        for (var k = 0; k < 200; k++) {
          final waits = d.bonusWaits;
          // Nothing is open, but a bonus waits: free slots, yet the draws
          // never place a second, different big bonus while it waits.
          final ctx = DirectorContext.open(711, bigBonusOpen: !waits);
          final ring = d.waitingRing, item = d.waitingItem;
          final s = d.nextSlot(ctx);
          // The gap sees the slot it follows (a big slot is open then).
          final g = d.nextGap(
            DirectorContext.open(711, bigBonusOpen: !waits || _bigSlot(s)),
            s,
          );
          if (!waits || (ring == null && item == null)) continue;
          for (final i in g.items) {
            if (!RunDirector.isBigItem(i.kind)) continue;
            expect(
              i.kind,
              item,
              reason: 'seed $seed: a new $i while $item waits',
            );
          }
          if (RunDirector.rewardKinds.contains(s.kind) &&
              s.kind != HoopKindId.portal) {
            expect(s.kind, ring, reason: 'seed $seed: $s while $ring waits');
          }
          if (s.kind == HoopKindId.normal && g.items.isNotEmpty) fallbacks++;
        }
      }
      expect(fallbacks, greaterThan(0));
    });

    test('the rule off (the §17.6 baseline) plans as before', () {
      for (var seed = 1; seed <= 10; seed++) {
        final a = RunDirector(
          seed: seed,
          enabled: _all,
          met: _all,
          startHoopIndex: 1,
          oneBigBonus: false,
        );
        final b = RunDirector(
          seed: seed,
          enabled: _all,
          met: _all,
          startHoopIndex: 1,
          oneBigBonus: false,
        );
        for (var k = 0; k < 80; k++) {
          final open = DirectorContext.open(711, bigBonusOpen: true);
          final shut = DirectorContext.open(711);
          final sa = a.nextSlot(open), sb = b.nextSlot(shut);
          expect(sa.kind, sb.kind);
          expect(sa.centreY, sb.centreY);
          final ga = a.nextGap(open, sa), gb = b.nextGap(shut, sb);
          expect(
            ga.items.map((i) => i.kind).toList(),
            gb.items.map((i) => i.kind).toList(),
          );
        }
      }
    });

    // PRD-2.3 §17.6 "within 10 %; if it drops more, report it, and the rule 4
    // waiting is checked": this model counts every big bonus as missed (no
    // activity, no cool-down), the densest case; it drops ≈ 14 % (reported
    // in the WP report). The guard here is 20 %; the in-run numbers come
    // from `s17_soak_test.dart`.
    test('bonus count: big bonuses per 50 hoops with the rule vs the same '
        'seeds without it (director model, 400 runs × 120 slots)', () {
      // PRD-2.3.1 §0: calibrated on the 2.3 spawn set; the live set (RC v21)
      // drops 43 % in this model (reported, PRD-2.3 §17.6).
      useTuning(tuning23Spawn());
      addTearDown(resetTuning);
      var withRule = 0, without = 0, slots = 0;
      for (var seed = 1; seed <= 400; seed++) {
        final (a, n) = _modelRun(seed, rule: true);
        final (b, _) = _modelRun(seed, rule: false);
        withRule += a;
        without += b;
        slots += n;
      }
      final per50a = 50 * withRule / slots, per50b = 50 * without / slots;
      // ignore: avoid_print
      print(
        'S17 model: ${per50a.toStringAsFixed(2)} big / 50 hoops with the '
        'rule, ${per50b.toStringAsFixed(2)} without',
      );
      expect((per50b - per50a) / per50b, lessThanOrEqualTo(.20));
    });
  });

  group('§17.2 / §17.4 visual reach and the per-slot creation edge', () {
    SlotPlan plan(HoopKindId k, {double opening = 88, Object? extra}) =>
        SlotPlan(
          index: 30,
          kind: k,
          element: k.element,
          trackX: 1000,
          centreY: 300,
          opening: opening,
          advance: RunConfig.spacing,
          extra: extra,
        );

    test('normal hoops keep 60 pt; the portal is created at 66 + 12 + 8', () {
      expect(RunSpawner.creationEdge(plan(HoopKindId.normal)), 60);
      expect(RunSpawner.creationEdge(plan(HoopKindId.saw)), 60);
      expect(PortalConfig.visualReach, 78);
      expect(RunSpawner.creationEdge(plan(HoopKindId.portal)), 86);
    });

    test('FEVER: its beam (125 pt + streaks, decor-scaled) sets the edge', () {
      for (final o in [66.0, 88.0, 118.0, 160.0]) {
        final e = RunSpawner.creationEdge(plan(HoopKindId.fever, opening: o));
        expect(e, FeverRingPainter.visualReach(o) + 8);
        expect(e, greaterThan(60));
      }
    });

    test('a pair: its wider gift tag; a comet-star hoop: the star tail', () {
      final pair = plan(
        HoopKindId.pair,
        extra: const PairRewards(PairReward.coins, PairReward.shield),
      );
      expect(RunSpawner.slotReach(pair), greaterThan(40));
      final comet = plan(HoopKindId.normal).copyWith(
        cometHang: true,
        attached: [
          const GapItemPlan(
            kind: ElementId.comet,
            trackX: 1000 + RunConfig.cometHang,
            y: 300,
          ),
        ],
      );
      expect(
        RunSpawner.slotReach(comet),
        RunSpawner.itemReach(ElementId.comet) - RunConfig.cometHang,
      );
    });
  });

  // --- §17.6 forced scenarios (in the run) ----------------------------------

  _tester().testGameWidget(
    '§17.6 pig missed: while the pig is open the forced portal waits; after '
    'the bird passes the pig it comes at the next slot, beam from the right',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        startHoopIndex: 10,
        force: [ElementId.piggy],
      );
      run.debugForce(ElementId.portal);
      Pickup? pig;
      int? nextSlot;
      Hoop? portal;
      double? portalLeft;
      final bad = <String>[];
      run.events.on<HoopSpawned>((e) {
        if (e.plan.kind != HoopKindId.portal || portal != null) return;
        portal = e.hoop;
        portalLeft =
            RunSpawner.hoopVisualLeftX(e.hoop) -
            (run.state.camX + RunConfig.worldWidth);
      });
      await flyUntil(game, (r) {
        pig ??= r.spawner.pickups
            .where((p) => p.id == ElementId.piggy)
            .firstOrNull;
        final p = pig;
        if (p != null && nextSlot == null) {
          if (r.spawner.slotLog.any((s) => s.kind == HoopKindId.portal)) {
            bad.add('portal planned while the pig is open');
          }
          // Keep the bird away from the pig: it is missed.
          final b = r.birdTrackPosition()!;
          final dx = p.position.x - b.x;
          if (dx < 70 && dx > -40) {
            final y = p.position.y - r.state.camY;
            game.runBird!.setFlight(
              y: y < r.state.viewHeight / 2 ? y + 130 : y - 130,
              vy: 0,
            );
          }
          if (p.escaped) nextSlot = r.director.hoopIndex;
        }
        return portal != null;
      }, maxSeconds: 40);
      expect(bad, isEmpty);
      expect(pig, isNotNull);
      expect(pig!.collected, isFalse, reason: 'the pig was missed');
      expect(nextSlot, isNotNull);
      expect(portal, isNotNull);
      expect(portal!.plan.index, nextSlot, reason: 'the next slot planned');
      // It enters from the right, beam included (≥ 8 pt out, minus at most
      // one frame of scroll).
      expect(portalLeft, greaterThan(8 - 5));
    },
  );

  _tester().testGameWidget(
    '§17.6 pig collected: nothing big is planned during the Piggy Bank run or '
    'its cool-down; the waiting portal comes at the first allowed slot',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        startHoopIndex: 10,
        force: [ElementId.piggy],
      );
      run.debugForce(ElementId.portal);
      final got = await collectPickup(game, ElementId.piggy, reforce: false);
      expect(got, isNotNull);
      expect(
        run.spawner.slotLog.where((s) => s.kind == HoopKindId.portal),
        isEmpty,
      );
      final slots0 = run.spawner.slotLog.length;
      final gaps0 = run.spawner.gapLog.length;
      await flyUntil(
        game,
        (r) => r.spawner.slotLog.any((s) => s.kind == HoopKindId.portal),
        maxSeconds: 60,
      );
      final slots = run.spawner.slotLog.sublist(slots0);
      final portal = slots.firstWhere((s) => s.kind == HoopKindId.portal);
      for (final s in slots.takeWhile((s) => !identical(s, portal))) {
        expect(_bigSlot(s), isFalse, reason: '$s');
      }
      for (final g in run.spawner.gapLog.sublist(gaps0)) {
        if (g.index >= portal.index) break;
        expect(_bigGap(g), isFalse, reason: 'gap ${g.index} ${g.items}');
      }
      // The first slot after the run's end + the 2-hoop cool-down.
      expect(
        portal.index,
        run.state.activityEndedAtSlot + RunConfig.activityCooldownHoops - 1,
      );
    },
  );

  _tester().testGameWidget(
    '§17.6 comet with a Firefly Jar due: the jar is never open together '
    'with the comet star; collecting the comet clears nothing visible '
    'outside the moved hoops\' gaps (PRD-2.3.1 §16.1 A)',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        startHoopIndex: 10,
        force: [ElementId.comet, ElementId.jar],
      );
      final bad = <String>[];
      run.events.on<PickupCleared>((e) {
        // PRD-2.3.1 §16.1 A a comet drops every pickup in the gaps of the
        // hoops it moves (past the last hoop that stays), visible ones too.
        final anchor = run.spawner.cometAnchorX;
        final comet = run.state.ride?.kind == RideKind.comet;
        if (comet && anchor != null && e.pickup.position.x > anchor) return;
        if (run.spawner.isVisible(e.pickup)) bad.add('cleared ${e.element}');
      });
      final ringsOnScreen = <Hoop>{};
      void watch(RunController r) {
        bool open(Pickup p) => !p.collected && !p.escaped && !p.isRemoved;
        final star = r.spawner.pickups.any(
          (p) => p.id == ElementId.comet && open(p),
        );
        final jar =
            r.spawner.pickups.any((p) => p.id == ElementId.jar && open(p)) ||
            r.spawner.pendingItems.any((i) => i.kind == ElementId.jar);
        if (star && jar) bad.add('jar open with the comet star');
        if (r.spawner.openBigCount > 1) bad.add('two big bonuses open');
        for (final h in r.spawner.hoops) {
          if (r.spawner.hoopVisible(h)) {
            ringsOnScreen.add(h);
          }
          if (h.rewardStripped && ringsOnScreen.contains(h)) {
            bad.add('a visible ring lost its reward');
          }
        }
      }

      final star = await collectPickup(game, ElementId.comet, reforce: false);
      watch(run);
      expect(star, isNotNull, reason: 'the bot takes the comet star');
      Pickup? jar;
      run.events.on<PickupSpawned>((e) {
        if (e.pickup.id == ElementId.jar) jar ??= e.pickup;
      });
      await flyUntil(game, (r) {
        watch(r);
        return jar != null;
      }, maxSeconds: 60);
      expect(jar, isNotNull, reason: 'the jar came after the ride');
      expect(bad, isEmpty);
    },
  );

  _tester().testGameWidget(
    '§17.6 a portal due while a capsule is open waits for the capsule to '
    'resolve',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        startHoopIndex: 10,
        force: [ElementId.hourglass],
      );
      run.debugForce(ElementId.portal);
      Pickup? capsule;
      var resolvedAt = -1;
      final bad = <String>[];
      await flyUntil(game, (r) {
        capsule ??= r.spawner.pickups
            .where((p) => p.id == ElementId.capsule)
            .firstOrNull;
        final c = capsule;
        final portal = r.spawner.slotLog.any(
          (s) => s.kind == HoopKindId.portal,
        );
        if (c != null && !(c.collected || c.escaped) && portal) {
          bad.add('portal planned while the capsule is open');
        }
        if (c != null && (c.collected || c.escaped) && resolvedAt < 0) {
          resolvedAt = r.spawner.slotLog.length;
        }
        return portal;
      }, maxSeconds: 80);
      expect(capsule, isNotNull);
      expect(bad, isEmpty);
      expect(resolvedAt, greaterThanOrEqualTo(0));
      final i = run.spawner.slotLog.indexWhere(
        (s) => s.kind == HoopKindId.portal,
      );
      expect(i, greaterThanOrEqualTo(resolvedAt));
    },
  );

  _tester().testGameWidget(
    '§17.6 small items unaffected: a heart and a shield are open together '
    'with an open Piggy Bank',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        startHoopIndex: 10,
        force: [ElementId.piggy, ElementId.heart, ElementId.shield],
      );
      var together = false;
      await flyUntil(game, (r) {
        final pig = r.spawner.pickups.any(
          (p) => p.id == ElementId.piggy && !p.collected && !p.escaped,
        );
        bool planned(ElementId e) =>
            r.spawner.pickups.any(
              (p) => p.id == e && !p.collected && !p.escaped,
            ) ||
            r.spawner.pendingItems.any((i) => i.kind == e);
        together = pig && planned(ElementId.heart) && planned(ElementId.shield);
        return together;
      }, maxSeconds: 20);
      expect(together, isTrue);
      expect(run.spawner.openBigCount, 1);
    },
  );

  _tester().testGameWidget(
    '§17.5 an activity start clears only what is not visible: an off-screen '
    'feather is cleared (owed), a heart on screen stays',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game, startHoopIndex: 10);
      final s = run.state;
      final right = s.camX + RunConfig.worldWidth;
      final heart = run.spawner.spawnItem(
        GapItemPlan(kind: ElementId.heart, trackX: right - 40, y: 300),
      )!;
      final feather = run.spawner.spawnItem(
        GapItemPlan(kind: ElementId.feather, trackX: right + 60, y: 300),
      )!;
      s.featherSpawned = true;
      await flushAndMount(game);
      final cleared = <Pickup>[];
      run.events.on<PickupCleared>((e) => cleared.add(e.pickup));
      expect(run.spawner.isVisible(heart), isTrue);
      expect(run.spawner.isVisible(feather), isFalse);
      s.jar = JarState();
      game.update(1 / 60);
      expect(s.activity, RunActivity.jar);
      // PRD-2.3.1 §0: the live puzzle window (gaps 5–30) may have put an
      // off-screen piece out too; only what is not visible goes.
      expect(cleared, contains(feather));
      expect(cleared.every((p) => !run.spawner.isVisible(p)), isTrue);
      expect(feather.escaped, isTrue);
      expect(s.featherSpawned, isFalse, reason: 'owed');
      expect(run.spawner.pickups, contains(heart));
      expect(heart.escaped, isFalse);
    },
  );
}
