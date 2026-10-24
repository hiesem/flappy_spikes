import 'dart:io';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/motion/hoop_motion.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/physics/hoop_frame.dart';
import 'package:flappy_spikes/run/physics/rim_collision.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/services/reminders.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../helpers.dart';

/// Independent P1 QA. The S6 regressions contain the expected PRD behavior
/// (S6-02..09 fixed in Fix P1 R1; S6-01 stays skipped until WP-2d lands);
/// `flutter test --run-skipped test/e2e/p1_gameplay_e2e_test.dart` runs it.
/// S6-08 starts only the demo Firebase emulators, never production.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  Future<void> boot(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
  }

  Future<RunController> startHomeSlot(
    FlappySpikesGame g,
    Powerup powerup, {
    List<ElementId> force = const [],
  }) async {
    g.menu.slot.debugForce = powerup;
    g.menu.slot.rollForArrival();
    g.runDebug.force
      ..clear()
      ..addAll(force);
    stepGame(g, .6); // finish the home input fade
    await flushAndMount(g);
    await g.tapPowerupSlot(); // real slot -> completed fake ad -> START
    await flushAndMount(g);
    expect(g.state, GameState.playing);
    expect(g.storage.noAdsPopupVideos, 1);
    return g.run!;
  }

  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: height, seed: 21),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'P1 journey ($height): home shield, forced angled/moving/heart, '
      'autopilot, saves, death, existing results, home',
      setUp: (g, _) => boot(g),
      verify: (g, _) async {
        final run = await startHomeSlot(
          g,
          Powerup.shield,
          force: [ElementId.angledRing, ElementId.movingRing, ElementId.heart],
        );
        expect(g.storage.armedPowerup, 'none');
        expect(run.state.shield, isTrue);
        final walletBefore = g.storage.coins;
        final flight = await flyRun(g, untilHoops: 12, maxSeconds: 45);
        expect(
          flight.hoops,
          greaterThanOrEqualTo(12),
          reason: flight.trace.join('\n'),
        );
        expect(run.spawner.slotLog.any((p) => p.tiltDeg != 0), isTrue);
        expect(run.spawner.slotLog.any((p) => p.motion != null), isTrue);
        expect(
          run.spawner.gapLog.any(
            (p) => p.items.any((i) => i.kind == ElementId.heart),
          ),
          isTrue,
        );
        expect(g.storage.coins - walletBefore, run.state.coinsThisRun);
        // WP-3a: a ride (the comet boost, first met at hoop 10) ignores
        // mistakes — finish it first.
        await flyOutOfRide(g);
        // The same pipeline used by contacts: shield precedes extra life.
        run.state
          ..shield = true
          ..extraLife = true
          ..invulnerable = 0;
        expect(
          run.mistake(const Mistake(MistakeCause.spikes)),
          MistakeOutcome.saved,
        );
        expect(run.state.shield, isFalse);
        expect(run.state.extraLife, isTrue);
        expect(run.state.invulnerable, 2);
        run.state.invulnerable = 0;
        expect(
          run.mistake(const Mistake(MistakeCause.missedHoop)),
          MistakeOutcome.saved,
        );
        expect(run.state.extraLife, isFalse);
        run.state.invulnerable = 0;
        final coins = g.storage.coins;
        killRun(g);
        await flushAndMount(g);
        await declineRevive(g);
        expect(g.state, GameState.results);
        expect(g.world.children.query<ResultsScreen>(), hasLength(1));
        expect(g.storage.coins, coins, reason: 'passes were already credited');
        // Tumble continues through the current results flow to a floor rest.
        stepGame(g, 5);
        expect(run.tumble!.settledFlat, isTrue);
        expect(run.tumble!.position.y, closeTo(height - 44 - 14.75 + 2, .01));
        g.goHome();
        await flushAndMount(g);
        expect(g.state, GameState.start);
        expect(g.run, isNull);
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: height, seed: 21),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'P1 journey ($height): home Big Hoops expiry and spawn-only easing',
      setUp: (g, _) => boot(g),
      verify: (g, _) async {
        final run = await startHomeSlot(g, Powerup.bigHoops);
        final boost = run.state.bigHoops!;
        expect(boost.duration, inInclusiveRange(30, 40));
        expect(g.storage.armedPowerup, 'none');
        final originals = {
          run.spawner.hoops.first: run.spawner.hoops.first.opening,
        };
        final mults = <double>[1.5];
        // PRD-2.2 §15: a slot is sized when it is planned, one gap before
        // its hoop spawns.
        final planned = <int, double>{
          for (final p in run.spawner.slotLog) p.index: run.state.runClock,
        };
        run.events.on<HoopSpawned>((e) {
          final mult = boost.mult(planned[e.plan.index] ?? run.state.runClock);
          mults.add(mult);
          // PRD-2.4 §2: comet-boost hoops take their index's curve size × Big
          // Hoops; the portal stays 118; a ride ring takes the multiplier when
          // its ride starts (test/p24/s2_ride_hoop_sizes_test.dart).
          if (e.plan.kind != HoopKindId.rideRing) {
            expect(
              e.hoop.opening,
              closeTo(
                e.plan.kind == HoopKindId.portal
                    ? RunConfig.portalOpening
                    : RunConfig.openingFor(e.plan.index) * mult,
                .001,
              ),
            );
          }
          originals[e.hoop] = e.hoop.opening;
        });
        // WP-3f: an Hourglass capsule on the way slows runClock (§3.30), so
        // fly until D has passed in run time, not for a fixed real time.
        var flight = RunFlight();
        for (
          var i = 0;
          i < 4 && run.state.runClock <= boost.duration + 2;
          i++
        ) {
          flight = await flyRun(
            g,
            maxSeconds: boost.duration + 6 - run.state.runClock,
            onFrame: (_) {
              for (final p in run.spawner.slotLog) {
                planned.putIfAbsent(p.index, () => run.state.runClock);
              }
              for (final hoop in run.spawner.hoops) {
                expect(
                  hoop.opening,
                  originals[hoop],
                  reason: 'visible hoops never resize',
                );
              }
            },
          );
          if (run.ended) break;
        }
        expect(
          flight.hoops,
          greaterThanOrEqualTo(12),
          reason: flight.trace.join('\n'),
        );
        expect(run.state.runClock, greaterThan(boost.duration));
        expect(run.state.bigHoops, isNull);
        expect(mults.any((m) => m > 1 && m < 1.5), isTrue);
        expect(mults.last, 1);
        // The state clock contract also holds with a nonzero start time.
        expect(BigHoopsState(duration: 34, start: 2).mult(32), 1.25);
      },
    );
  }

  test(
    'P1 journey: persisted reminders across 35 days and autumn DST',
    () async {
      // PRD-2.6 §539 gates four reminder texts on met elements. This suite
      // exercises the complete 20-message rotation, so seed those elements.
      SharedPreferences.setMockInitialValues({
        'metElements': [
          ElementId.squeeze.storageId,
          ElementId.luckySpin.storageId,
          ElementId.egg.storageId,
          ElementId.fever.storageId,
        ],
      });
      var now = tz.TZDateTime(
        tz.getLocation('Europe/Amsterdam'),
        2026,
        10,
        8,
        9,
      );
      final platform = FakeReminderPlatform();
      var store = GameStorage(clock: () => now);
      await store.load();
      final delivered = <int, DateTime>{};
      for (var day = 0; day < 35; day++) {
        // Recreate the service/storage to exercise restart persistence.
        store = GameStorage(clock: () => now);
        await store.load();
        final reminders = LocalReminders(
          storage: store,
          platform: platform,
          scheduler: ReminderScheduler(
            random: Random(day + 7),
            location: now.location,
          ),
        );
        await reminders.initialize();
        await reminders.requestPermissionIfNeeded();
        for (final raw in platform.pending) {
          final p = ReminderPayload.decode(raw)!;
          final time = tz.TZDateTime.fromMillisecondsSinceEpoch(
            now.location,
            p.epochMs,
          );
          if (time.isAfter(now)) continue;
          final previous = delivered[p.messageNumber];
          if (previous != null) {
            final gap = DateTime.utc(time.year, time.month, time.day)
                .difference(
                  DateTime.utc(previous.year, previous.month, previous.day),
                );
            expect(gap.inDays, greaterThanOrEqualTo(10));
          }
          delivered[p.messageNumber] = time;
        }
        platform.deliverDue(now);
        await reminders.reschedule();
        expect(platform.scheduled, hasLength(14));
        for (final r in platform.scheduled) {
          final p = ReminderPayload.decode(r.payload)!;
          final minute = r.time.hour * 60 + r.time.minute;
          expect(
            minute,
            inInclusiveRange(p.slot.startMinute, p.slot.endMinute - 1),
          );
        }
        now = tz.TZDateTime(now.location, now.year, now.month, now.day + 1, 9);
      }
      expect(platform.permissionCalls, 1);
      expect(delivered.length, 20);
    },
  );

  group('S6-01 regression', () {
    FlameTester<FlappySpikesGame>(() => createRunTestGame()).testGameWidget(
      'S6-01 home Big Hoops starts gold at tier zero (known integration issue)',
      setUp: (g, _) => boot(g),
      verify: (g, _) async {
        final run = await startRun(g, starter: Powerup.bigHoops);
        expect(g.storage.armedPowerup, 'none');
        // Owner 2026-10-19 (deviation from PRD-2.3 §0 item 3): hoop 0 is
        // 118 × 1.5 = 177 with Big Hoops, like every hoop after it.
        expect(run.spawner.hoops.first.opening, closeTo(177, 1e-9));
        expect(run.spawner.hoops.first.look.colors, RingColors.gold);
      },
    );
  });

  group('S6-02 regression', () {
    FlameTester<FlappySpikesGame>(() => createRunTestGame()).testGameWidget(
      'S6-02 separating inside-rim overlap is still a graze',
      setUp: (g, _) => boot(g),
      verify: (g, _) async {
        final run = await startRun(g);
        final hoop = run.spawner.hoops.first;
        final y = hoop.plan.centreY - hoop.frame().reach + 20;
        run.state.camX = hoop.planeX - RunConfig.birdX - 1;
        g.runBird!.setFlight(y: y, vy: 80);
        final contact = collideRims(
          hoop.frame(),
          BirdCircle(run.birdTrackPosition()!),
          Vector2(150, 80),
        );
        expect(contact, isNotNull);
        expect(
          contact!.bounced,
          isFalse,
          reason: 'overlapping but already separating',
        );
        run.events.recordLog = true;
        g.update(0); // real controller contact/push-out
        g.update(1 / 60); // inside-plane crossing
        final pass = run.events.log.whereType<HoopPassed>().single;
        expect(
          g.state,
          GameState.playing,
          reason: 'inside-rim touch cannot kill',
        );
        expect(
          pass.perfect,
          isFalse,
          reason: 'any rim touch breaks the streak',
        );
        expect(run.state.coinsThisRun, 1);
      },
    );
  });

  group('S6-03 regression', () {
    FlameTester<FlappySpikesGame>(() => createRunTestGame()).testGameWidget(
      'S6-03 first-meet persistence waits until the tilted ring enters view',
      setUp: (g, _) => boot(g),
      verify: (g, _) async {
        final run = await startRun(g, force: [ElementId.angledRing]);
        g.update(.02);
        // PRD-2.3 §10.2 hoop 0 stays plain: the forced tilted ring is the
        // next slot; check it on the frame it spawns.
        g.runDebug.god = true;
        await flyUntil(
          g,
          (r) => r.spawner.hoops.any((h) => h.plan.tiltDeg != 0),
        );
        final hoop = run.spawner.hoops.firstWhere((h) => h.plan.tiltDeg != 0);
        final f = hoop.frame();
        // Even an intentionally generous 24 pt horizontal art allowance is offscreen.
        final left =
            f.centre.x - sin(f.tilt).abs() * f.reach - 24 - run.state.camX;
        expect(left, greaterThan(320));
        expect(g.storage.metElements, isNot(contains('angled_ring')));
      },
    );
  });

  late AnalyticsSpy spy;
  group('S6-04 regression', () {
    FlameTester<FlappySpikesGame>(() {
      spy = AnalyticsSpy();
      return createRunTestGame(services: spy);
    }).testGameWidget(
      'S6-04 run_end reports the missed slot index, not the next spawn index',
      setUp: (g, _) => boot(g),
      verify: (g, _) async {
        final run = await startRun(g);
        run.events.recordLog = true;
        await flyRun(
          g,
          maxSeconds: 4,
          autopilot: false,
          onFrame: (_) {
            if (g.state == GameState.playing) {
              g.runBird!.setFlight(y: g.viewHeight / 2 - 125, vy: 0);
            }
          },
        );
        final missed = run.events.log.whereType<HoopMissed>().single.hoop;
        stepGame(g, 2);
        final event = spy.events.singleWhere((e) => e.$1 == 'run_end').$2!;
        expect(event['cause'], 'missed_hoop');
        expect(event['hoop_index'], missed.plan.index);
      },
    );
  });

  test(
    'S6-05 service reschedules in the current device zone after travel',
    () async {
      SharedPreferences.setMockInitialValues({});
      var deviceZone = 'Europe/Amsterdam';
      const channel = MethodChannel('flutter_timezone');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => deviceZone);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        tz.setLocalLocation(tz.UTC);
      });
      var now = DateTime.utc(2026, 10, 8, 7);
      final store = GameStorage(clock: () => now);
      await store.load();
      final platform = FakeReminderPlatform();
      final reminders = LocalReminders(storage: store, platform: platform);
      await reminders.initialize();
      await reminders.reschedule();
      deviceZone = 'America/Denver';
      now = DateTime.utc(2026, 10, 9, 15);
      platform.deliverDue(now);
      await reminders.reschedule();
      for (final r in platform.scheduled) {
        final local = tz.TZDateTime.from(r.time, tz.getLocation(deviceZone));
        final payload = ReminderPayload.decode(r.payload)!;
        expect(
          local.hour * 60 + local.minute,
          inInclusiveRange(
            payload.slot.startMinute,
            payload.slot.endMinute - 1,
          ),
          reason: 'device $deviceZone: $local',
        );
      }
    },
  );

  test('S6-06 skipped slots do not extend reminders past seven days', () {
    final zone = tz.getLocation('Europe/Amsterdam');
    final now = tz.TZDateTime(zone, 2026, 10, 8, 12);
    final deadline = tz.TZDateTime(zone, 2026, 10, 15, 12);
    for (var seed = 1; seed <= 30; seed++) {
      final plan = ReminderScheduler(random: Random(seed), location: zone).plan(
        now: now,
        lastPlayedAt: now,
        state: ReminderState.empty,
        best: 12,
        coins: 100,
      );
      for (final r in plan.reminders) {
        expect(
          r.time.isAfter(deadline),
          isFalse,
          reason: 'seed $seed: ${r.time}',
        );
      }
    }
  });

  test(
    'S6-07 failed notification scheduling does not consume the rotation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStorage(clock: () => DateTime.utc(2026, 10, 8, 7));
      await store.load();
      final platform = FakeReminderPlatform()..throwOnSchedule = true;
      final reminders = LocalReminders(
        storage: store,
        platform: platform,
        scheduler: ReminderScheduler(
          random: Random(7),
          location: tz.getLocation('Europe/Amsterdam'),
        ),
      );
      await reminders.initialize();
      await reminders.reschedule();
      expect(platform.scheduled, isEmpty);
      expect(
        store.notifLastSent,
        isEmpty,
        reason: 'no reminder was scheduled or sent',
      );
      expect(store.notifPosition, 0);
    },
  );

  test(
    'S6-08 delayed versus write cannot recreate deleted online data',
    () async {
      final result = await Process.run(
        'npm',
        ['--prefix', 'functions', 'test', '--', '--grep', 'S6-08'],
        environment: {'S6_QA_OPEN': '1'},
        runInShell: true,
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    // Needs the firebase CLI + Java; `npm --prefix functions test` runs it in
    // the backend gate. Set FS_EMULATOR_TESTS=1 to run it from here.
    skip: Platform.environment['FS_EMULATOR_TESTS'] == '1'
        ? false
        : 'emulator test: runs in npm --prefix functions test',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  group('S6-09 regression', () {
    FlameTester<FlappySpikesGame>(() => createRunTestGame()).testGameWidget(
      'S6-09 rocking rim bounce includes the rim end angular velocity',
      setUp: (g, _) => boot(g),
      verify: (g, _) async {
        final run = await startRun(g);
        final hoop = run.spawner.hoops.first;
        final motion = RockMotion(
          const MotionSpec(
            type: MotionType.rock,
            amplitudeDeg: 15,
            period: 3,
            phase: 0,
          ),
        );
        hoop.motion = motion;
        hoop.syncMotion(0);
        final f = hoop.frame();
        final rimSpeed = motion.angularVelocity * pi / 180 * f.reach;
        expect(rimSpeed, greaterThan(30));
        final contact = collideRims(
          f,
          BirdCircle(f.rimEnd(0, -1) + Vector2(20.75, 0)),
          Vector2.zero(),
        )!;
        expect(
          contact.velocity.x,
          closeTo((1 + .85) * rimSpeed, .01),
          reason:
              'the top rim rotates into the bird despite a stationary centre',
        );
      },
    );
  });
}
