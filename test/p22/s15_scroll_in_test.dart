import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flappy_spikes/run/hoops/kinds/switch/switch_kind.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/pickups/star_trail.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_spawner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../p231/tuning_23.dart';

/// PRD-2.2 §15: items scroll in from the right, never pop in. The director
/// plans one slot ahead, so every hoop and pickup is created off-screen;
/// only feature follow-ups placed at a grab may appear inside the screen,
/// and those pop in.
Future<void> _boot(FlappySpikesGame game) async {
  await game.ready();
  game.sound.enabled = false;
  await preloadImages(game);
}

/// Records every hoop / pickup created in [run] that pops into view: its
/// left edge left of the right screen edge at creation. Exceptions (§15.4):
/// ride rings (a ride effect) and feature follow-ups that pop in.
class _OnScreenWatch {
  _OnScreenWatch(this.run) {
    // What the first tap created (camX ≈ 0) counts too.
    for (final h in run.spawner.hoops) {
      // A debug-forced moving ring on the run's very first slot (created
      // at camX 0, 60 pt off screen) may swing its art into view: real runs
      // begin at hoop 0, which never moves (PRD-2.3 §14.4 curve_moving), so
      // only its count is kept.
      // PRD-2.3 §10.2 hoop 0 stands on screen before the first tap (x 290)
      // by design: §15.4 holds for every later item.
      if (h.plan.motion != null ||
          (h.plan.index == 0 && run.setup.startHoopIndex == 0)) {
        hoops++;
        continue;
      }
      _hoop(HoopSpawned(h, h.plan));
    }
    for (final p in run.spawner.pickups) {
      _pickup(PickupSpawned(p));
    }
    check();
    run.events
      ..on<HoopSpawned>(_hoop)
      ..on<PickupSpawned>(_pickup);
  }

  final RunController run;
  final List<String> bad = [];
  final List<Pickup> _fresh = [];
  int hoops = 0, pickups = 0;
  final Set<ElementId> kinds = {};

  /// One frame of scrolling (a comet boost moves ≈ 4.5 pt per frame).
  static const double slack = 5;

  double get _edge => run.state.camX + RunConfig.worldWidth - slack;

  void _hoop(HoopSpawned e) {
    if (e.plan.kind == HoopKindId.rideRing) return; // ride effect
    hoops++;
    final left = RunSpawner.artLeftX(e.hoop);
    if (left < _edge) {
      bad.add('hoop ${e.plan} at ${(left - run.state.camX).round()}');
    }
  }

  void _pickup(PickupSpawned e) {
    final p = e.pickup;
    pickups++;
    kinds.add(p.id);
    var left = p.position.x - p.hitRadius;
    if (p is StarTrail) left = p.starAt(0).dx - PickupRadii.star;
    if (left < _edge) _fresh.add(p);
  }

  /// After each frame: a pickup created inside must be popping in.
  void check() {
    for (final p in _fresh) {
      if (!run.spawner.poppingIn.contains(p)) {
        bad.add(
          '${p.id.storageId} at '
          '${(p.position.x - p.hitRadius - run.state.camX).round()}',
        );
      }
    }
    _fresh.clear();
  }
}

void main() {
  final elements = {
    ...registeredElements(),
    ...registeredPickupElements(),
  }.where(
    (e) =>
        (e.isSlotElement || e.isGapElement) &&
        e != ElementId.piggyCoins &&
        e != ElementId.fireflySwarm &&
        e != ElementId.normalHoop,
  ).toList()..sort((a, b) => a.index.compareTo(b.index));

  group('§15.4 on-screen spawn gate (every element forced)', () {
    test('the gate covers the catalogue', () {
      expect(elements.length, greaterThanOrEqualTo(20));
      expect(
        elements,
        containsAll([
          ElementId.heart,
          ElementId.shield,
          ElementId.starTrail,
          ElementId.capsule,
          ElementId.switchRing,
          ElementId.comet,
          ElementId.portal,
          ElementId.piggy,
          ElementId.jar,
          ElementId.feather,
          ElementId.puzzlePiece,
        ]),
      );
    });

    for (final h in [568.0, 711.0]) {
      for (final e in elements) {
        FlameTester<FlappySpikesGame>(
          () => createRunTestGame(worldHeight: h, seed: 5),
          gameSize: Vector2(320, h),
        ).testGameWidget(
          '§15.4 ${e.storageId} (${h.round()} pt): every hoop and pickup is '
          'created right of the screen edge',
          setUp: (g, _) {
            // PRD-2.3.1 §0: these 14 s windows were set on the 2.3 spawn
            // set; the live set (a portal at hoop 12–25, a reward ring open
            // most of the time) holds some forced elements past them. The
            // natural runs below fly the live set.
            useTuning(tuning23Spawn());
            addTearDown(resetTuning);
            return _boot(g);
          },
          verify: (game, _) async {
            game.runDebug.god = true;
            final run = await startRun(
              game,
              startHoopIndex: e.firstPossible ?? 0,
              force: [e],
            );
            final watch = _OnScreenWatch(run);
            // The forced element may already have spawned while startRun
            // settled (PRD-2.3 §14 course: it lands on the first slot).
            var seen =
                run.state.metThisRun.contains(e) ||
                run.spawner.hoops.any(
                  (h) =>
                      h.announced &&
                      (h.plan.element == e ||
                          (e == ElementId.movingRing &&
                              h.plan.motion != null) ||
                          (e == ElementId.angledRing && h.plan.tiltDeg != 0)),
                );
            run.events.on<ElementSpawned>((x) {
              if (x.element == e) seen = true;
            });
            await flyRun(
              game,
              maxSeconds: 14,
              onFrame: (_) => watch.check(),
            );
            expect(seen, isTrue, reason: '${e.storageId} came on screen');
            // (A portal ride holds the course: few slots.)
            expect(watch.hoops, greaterThan(e == ElementId.portal ? 0 : 4));
            expect(watch.bad, isEmpty);
          },
        );
      }
    }

    for (final h in [568.0, 711.0]) {
      for (final seed in [2, 9]) {
        FlameTester<FlappySpikesGame>(
          () => createRunTestGame(worldHeight: h, seed: seed),
          gameSize: Vector2(320, h),
        ).testGameWidget(
          '§15.4 a natural run (${h.round()} pt, seed $seed): nothing pops in',
          setUp: (g, _) => _boot(g),
          verify: (game, _) async {
            game.runDebug.god = true;
            final run = await startRun(game);
            final watch = _OnScreenWatch(run);
            await flyRun(
              game,
              maxSeconds: 70,
              onFrame: (_) => watch.check(),
            );
            // PRD-2.3.1 §0: the live set's portal (hoop 12–25) and comets
            // hold the course for a while: ≥ 26 hoops in 70 s (2.3: > 30).
            expect(watch.hoops, greaterThan(25));
            // PRD-2.6 D2/C3's early pool replaces one star-trail third with
            // "nothing"; this seed now naturally meets three pickups.
            expect(watch.pickups, greaterThanOrEqualTo(3));
            expect(watch.bad, isEmpty);
          },
        );
      }
    }
  });

  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  );

  for (final e in [ElementId.heart, ElementId.shield]) {
    tester.testGameWidget(
      '§15.4 a ${e.storageId} on the line between two hoops exists before '
      'its gap reaches the screen edge (the screenshots\' regression)',
      setUp: (g, _) => _boot(g),
      verify: (game, _) async {
        game.runDebug.god = true;
        final run = await startRun(
          game,
          startHoopIndex: e.firstPossible ?? 0,
          force: [e],
        );
        // Created at the run start (camX 0) or later.
        Pickup? item = pickupsOf(game).where((p) => p.id == e).firstOrNull;
        double? camAt = item == null ? null : 0;
        run.events.on<PickupSpawned>((x) {
          if (x.pickup.id == e && item == null) {
            item = x.pickup;
            camAt = run.state.camX;
          }
        });
        await flyUntil(game, (_) => item != null, maxSeconds: 10);
        final p = item!;
        expect(p.plan!.y, isNotNull, reason: 'resolved on the line');
        // The whole gap (its left hoop included) is still off-screen.
        final gap = run.spawner.slotLog.lastWhere(
          (s) => s.lastRingX < p.position.x,
        );
        expect(gap.lastRingX, greaterThanOrEqualTo(camAt! + 320 + 50));
        expect(
          p.position.x - p.hitRadius,
          greaterThan(camAt! + RunConfig.worldWidth),
        );
      },
    );
  }

  tester.testGameWidget(
    '§15.4 the Star Trail\'s first star is created off-screen',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        startHoopIndex: 5,
        force: [ElementId.starTrail],
      );
      StarTrail? trail = pickupsOf(game).whereType<StarTrail>().firstOrNull;
      double? camAt = trail == null ? null : 0;
      run.events.on<PickupSpawned>((x) {
        if (x.pickup is StarTrail && trail == null) {
          trail = x.pickup as StarTrail;
          camAt = run.state.camX;
        }
      });
      await flyUntil(game, (_) => trail != null, maxSeconds: 10);
      expect(
        trail!.starAt(0).dx - PickupRadii.star,
        greaterThan(camAt! + RunConfig.worldWidth),
      );
    },
  );

  tester.testGameWidget(
    '§15.1 a feature follow-up created inside the screen pops in (scale '
    '0 → 1.15 → 1 over 0.25 s + a sparkle); one created outside does not',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game);
      final bird = run.birdTrackPosition()!;
      final inside = run.spawner.spawnItem(
        GapItemPlan(
          kind: ElementId.piggyCoins,
          trackX: bird.x + 60,
          toTrackX: bird.x + 195,
          y: bird.y,
          toY: bird.y,
          extra: 4,
        ),
      )!;
      final outside = run.spawner.spawnItem(
        GapItemPlan(
          kind: ElementId.piggyCoins,
          trackX: run.state.camX + 400,
          toTrackX: run.state.camX + 535,
          y: bird.y,
          toY: bird.y,
          extra: 4,
        ),
      )!;
      expect(run.spawner.poppingIn, contains(inside));
      expect(run.spawner.poppingIn, isNot(contains(outside)));
      expect(inside.popScale, 0);
      expect(outside.popScale, 1);
      expect(run.spawner.popSparkle!.pool.alive, RunConfig.popInSparkle);
      await flushAndMount(game);
      var peak = 0.0;
      for (var i = 0; i < 20; i++) {
        game.update(1 / 60);
        if (inside.popScale > peak) peak = inside.popScale;
      }
      expect(peak, closeTo(RunConfig.popInOvershoot, .03));
      expect(inside.popScale, 1);
      expect(run.spawner.poppingIn, isEmpty);
      expect(outside.popScale, 1);
      // The curve itself.
      expect(RunSpawner.popInScale(0), 0);
      expect(RunSpawner.popInScale(.15), closeTo(1.15, 1e-9));
      expect(RunSpawner.popInScale(.25), closeTo(1, 1e-9));
    },
  );

  tester.testGameWidget(
    '§15.1 a grabbed piggy\'s own-gap coins pop in when inside the screen; '
    'its follow-up fields come with the normal gaps, off-screen',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        startHoopIndex: 12,
        force: [ElementId.piggy],
      );
      final watch = _OnScreenWatch(run);
      final popped = <Pickup>[];
      final fields = <Pickup>[];
      run.events.on<PickupSpawned>((x) {
        if (x.pickup.id == ElementId.piggyCoins) fields.add(x.pickup);
      });
      final got = await collectPickup(game, ElementId.piggy, reforce: false);
      expect(got, isNotNull);
      popped.addAll(run.spawner.poppingIn);
      await flyRun(
        game,
        maxSeconds: 12,
        onFrame: (_) => watch.check(),
      );
      expect(fields.length, greaterThanOrEqualTo(4));
      expect(watch.bad, isEmpty);
    },
  );

  tester.testGameWidget(
    '§15.1 the switch is created with its ring\'s plan (one gap ahead), off '
    'screen, and linked to the ring when the ring spawns',
    setUp: (g, _) {
      // PRD-2.3.1 §0: timed on the 2.3 spawn set (the live portal sits at
      // hoop 12–25, right where this run starts).
      useTuning(tuning23Spawn());
      addTearDown(resetTuning);
      return _boot(g);
    },
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        startHoopIndex: 12,
        force: [ElementId.switchRing],
      );
      SwitchPickup? sw = pickupsOf(game).whereType<SwitchPickup>().firstOrNull;
      double? camAt = sw == null ? null : 0;
      run.events.on<PickupSpawned>((x) {
        if (x.pickup is SwitchPickup && sw == null) {
          sw = x.pickup as SwitchPickup;
          camAt = run.state.camX;
        }
      });
      await flyUntil(game, (_) => sw != null, maxSeconds: 10);
      final p = sw!;
      expect(p.position.x - p.hitRadius, greaterThan(camAt! + 320));
      expect(p.ring, isNull, reason: 'its ring is planned, not spawned');
      expect(p.ringPlan?.kind, HoopKindId.switchRing);
      // PRD-2.3 §14 course: a ring train (3 rings, one wide slot) can sit
      // before the switch ring, so its spawn may take longer than 4 s.
      await flyUntil(game, (_) => p.ring != null, maxSeconds: 8);
      final ring = p.ring!;
      expect(ring.plan.kind, HoopKindId.switchRing);
      expect(SwitchRingKind.stateOf(ring)?.pickup, same(p));
      expect(ring.open, isFalse);
    },
  );

  tester.testGameWidget(
    '§15.2 plan one ahead: the planned-ahead slot is the next index, has no '
    'hoop yet, and the line items before it already exist',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game);
      for (var f = 0; f < 600; f++) {
        game.update(1 / 60);
        final ahead = run.spawner.plannedAhead!;
        expect(ahead.index, run.state.hoopIndex);
        expect(run.director.hoopIndex, ahead.index + 1);
        expect(
          run.spawner.hoops.any((h) => h.plan.index == ahead.index),
          isFalse,
        );
        expect(
          ahead.trackX,
          greaterThan(run.state.camX + RunConfig.worldWidth + 60),
        );
        if (f % 10 == 0) await flushAndMount(game);
      }
    },
  );

  // Every element met: no first-meet comet / capsule (an activity would
  // hold the heart back, §27).
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      worldHeight: 711,
      seed: 5,
      prefs: {
        'metElements': [for (final e in ElementId.values) e.storageId],
      },
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§15.4 director: a heart after a lost life still comes (lost one gap '
    'before its gap is planned)',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game);
      // No activity may hold the heart back (§27): only hearts this run.
      run.director.enabled.removeWhere(
        (e) =>
            e != ElementId.heart &&
            (RunDirector.isRewardItem(e) ||
                RunDirector.rewardKinds.contains(HoopKindId.specialFor(e)) ||
                e == ElementId.portal),
      );
      run.state.extraLife = true;
      final due = run.director.heartAt;
      await flyUntil(
        game,
        (r) => r.director.hoopIndex >= due,
        maxSeconds: 60,
      );
      // The life is lost before the heart's gap is planned.
      expect(run.director.hoopIndex, due);
      expect(run.state.extraLife, isTrue);
      run.state.extraLife = false;
      Hoop? before;
      Pickup? heart;
      run.events.on<PickupSpawned>((x) {
        if (x.pickup.id == ElementId.heart) heart ??= x.pickup;
      });
      before = run.spawner.hoops.lastOrNull;
      await flyUntil(game, (_) => heart != null, maxSeconds: 8);
      expect(
        heart,
        isNotNull,
        reason:
            'due $due now ${run.director.heartAt} idx ${run.director.hoopIndex} '
            '${run.spawner.gapLog.where((g) => g.index >= due - 2).take(4)}',
      );
      expect(before, isNotNull);
      final gaps = run.spawner.gapLog
          .where((g) => g.items.any((i) => i.kind == ElementId.heart))
          .map((g) => g.index);
      expect(gaps.first - due, lessThanOrEqualTo(1));
    },
  );
}
