import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/debug/force_menu.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/kinds/fever.dart';
import 'package:flappy_spikes/run/hoops/kinds/pair/pair_kind.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flappy_spikes/run/hoops/kinds/saw/saw_kind.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/run/items/big_hoops.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/items/hourglass.dart';
import 'package:flappy_spikes/run/items/piggy.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/items/timed_powerup.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/pickups/star_trail.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

T feature<T>(RunController r) => r.features.whereType<T>().single;

void qa(
  String name,
  Future<void> Function(FlappySpikesGame) verify, {
  double height = 711,
  int seed = 5,
  bool realAsync = false,
}) {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      worldHeight: height,
      seed: seed,
      prefs: {'coins': 50000, 'noAds': true},
    ),
    gameSize: Vector2(320, height),
  ).testGameWidget(
    name,
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, tester) async {
      if (realAsync) {
        await tester.runAsync(() => verify(g));
      } else {
        await verify(g);
      }
    },
  );
}

Future<void> pauseSnapshot(FlappySpikesGame g) async {
  final r = g.run!;
  g.pause();
  await flushAndMount(g);
  final clock = r.state.runClock;
  final cam = Vector2(r.state.camX, r.state.camY);
  final bird = g.runBirdPosition!.clone();
  final remaining = r.state.timed?.remaining;
  final phaseT = feature<SqueezeFeature>(r).phaseT;
  final phase = feature<PortalRideFeature>(r).ride?.phase;
  stepGame(g, 2);
  expect(g.state, GameState.paused);
  expect(r.state.runClock, clock);
  expect(Vector2(r.state.camX, r.state.camY), cam);
  expect(g.runBirdPosition, bird);
  expect(r.state.timed?.remaining, remaining);
  expect(feature<SqueezeFeature>(r).phaseT, phaseT);
  expect(feature<PortalRideFeature>(r).ride?.phase, phase);
  g.resume();
  await flushAndMount(g);
  expect(g.state, GameState.playing);
}

void main() {
  for (final height in [568.0, 711.0]) {
    for (final id in RideId.values) {
      qa('P3 $id + Hourglass: pause every ride phase, suspend and resume '
          'the effect h=$height', (g) async {
        final run = await startRun(g, startHoopIndex: 25, ride: id);
        expect(
          feature<TimedPowerupSlot>(run).start(CapsuleType.hourglass),
          isTrue,
        );
        expect(
          await flyUntil(g, (r) => r.state.ride?.kind == RideKind.portal),
          isTrue,
        );
        final timed = run.state.timed!;
        final remaining = timed.remaining;
        expect(timed.paused, isTrue);
        expect(run.state.timeScale, 1);
        final ride = feature<PortalRideFeature>(run).ride!;
        for (final phase in [
          RidePhase.ride,
          RidePhase.exit,
          RidePhase.fly,
          RidePhase.glide,
        ]) {
          expect(await flyUntil(g, (_) => ride.phase == phase), isTrue);
          await pauseSnapshot(g);
          expect(timed.remaining, closeTo(remaining, .03));
          expect(run.state.timeScale, 1);
        }
        expect(await flyUntil(g, (r) => r.state.ride == null), isTrue);
        expect(timed.paused, isFalse);
        expect(timed.remaining, closeTo(remaining, .06));
        await flyRun(g, maxSeconds: .6);
        expect(run.state.timeScale, closeTo(.45, .001));
        expect(feature<HourglassFeature>(run).on, isTrue);
        expect(timed.remaining, closeTo(remaining - .6, .1));
      }, height: height);
    }

    qa('P3 comet + due squeeze: pause boost, delay warning until landing +2s '
        'h=$height', (g) async {
      final run = await startRun(
        g,
        startHoopIndex: 10,
        force: [ElementId.comet],
      );
      expect(
        await flyUntil(g, (r) => r.state.ride?.kind == RideKind.comet),
        isTrue,
      );
      run.state.squeeze.nextAt = run.state.runClock + 1;
      await pauseSnapshot(g);
      double? endedAt;
      run.events.on<RideEnded>((e) {
        if (e.kind == RideKind.comet) endedAt = run.state.runClock;
      });
      expect(
        await flyUntil(g, (r) {
          expect(r.state.squeeze.phase, SqueezePhase.idle);
          return r.state.ride == null;
        }),
        isTrue,
      );
      expect(endedAt, isNotNull);
      expect(
        await flyUntil(g, (r) => r.state.squeeze.phase != SqueezePhase.idle),
        isTrue,
      );
      expect(run.state.runClock - endedAt!, closeTo(2, .05));
      for (final phase in [
        SqueezePhase.warning,
        SqueezePhase.closing,
        SqueezePhase.hold,
        SqueezePhase.opening,
      ]) {
        expect(
          await flyUntil(g, (r) => r.state.squeeze.phase == phase),
          isTrue,
        );
        await pauseSnapshot(g);
      }
      expect(feature<CometFeature>(run).started, 1);
    }, height: height);

    for (final element in [
      ElementId.switchRing,
      ElementId.pair,
      ElementId.saw,
    ]) {
      final s644 = element == ElementId.switchRing;
      group(
        s644 ? 'S6-44 regression' : 'P3 Mini Bird',
        () {
          qa('P3 Mini Bird through $element h=$height', (g) async {
            final run = await startRun(g, startHoopIndex: 20, force: [element]);
            expect(
              feature<TimedPowerupSlot>(run).start(CapsuleType.miniBird),
              isTrue,
            );
            var miniPasses = 0;
            run.events.on<HoopPassed>((e) {
              if (e.hoop?.plan.element == element && run.state.birdScale < .6) {
                miniPasses++;
              }
            });
            final flight = await flyRun(
              g,
              maxSeconds: 60,
              untilHoops: 20,
              onFrame: (r) {
                if (!r.director.forcedQueue.contains(element)) {
                  r.debugForce(element);
                }
                if (r.state.timed == null && r.state.ride == null) {
                  feature<TimedPowerupSlot>(r).start(CapsuleType.miniBird);
                }
              },
            );
            expect(
              flight.hoops,
              greaterThanOrEqualTo(20),
              reason: flight.trace.join('\n'),
            );
            expect(miniPasses, greaterThan(2));
            expect(run.dying, isFalse);
          }, height: height);
        },
      );
    }
    qa('P3 S6-44 control: full-size switch autopilot h=$height', (g) async {
      await startRun(g, startHoopIndex: 20, force: [ElementId.switchRing]);
      final flight = await flyRun(g, maxSeconds: 10, untilHoops: 3);
      expect(
        flight.hoops,
        greaterThanOrEqualTo(3),
        reason: flight.trace.join('\n'),
      );
    }, height: height);

    qa('P3 FEVER + streak + Big Hoops + Coin Frenzy restores painter owners '
        'h=$height', (g) async {
      final run = await startRun(
        g,
        starter: Powerup.bigHoops,
        force: [ElementId.fever],
      );
      expect(await flyUntil(g, (r) => r.state.onFire), isTrue);
      expect(run.state.streak, greaterThanOrEqualTo(5));
      expect(
        feature<TimedPowerupSlot>(run).start(CapsuleType.coinFrenzy),
        isTrue,
      );
      final h = run.spawner.hoops.firstWhere((h) => BigHoopsFeature.isGold(h));
      final before = h.look.colors;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      h.paintBack!(canvas);
      h.front.paintFront!(canvas);
      recorder.endRecording().dispose();
      expect(h.look.colors, before);
      expect(h.look.colors, RingColors.gold);
      expect(h.look.strokeWidth, 7);
      await pauseSnapshot(g);
      var frenzyCoins = 0;
      run.events.on<CoinsEarned>((e) {
        if (e.source.name == 'frenzy') frenzyCoins += e.amount;
      });
      await flyRun(g, maxSeconds: 7);
      expect(frenzyCoins, greaterThanOrEqualTo(5));
      expect(run.state.timed, isNull);
      expect(run.state.onFire, isTrue);
      expect(run.dying, isFalse);
    }, height: height);

    qa('P3 Black Hole lens + squeeze walls + FEVER shake compose and reset '
        'h=$height', (g) async {
      final run = await startRun(g, startHoopIndex: 20, force: [ElementId.saw]);
      final h = await flyToHoop(
        g,
        HoopKindId.saw,
        ElementId.saw,
        where: (h) => SawHoopKind.designOf(h) == SawDesign.blackHole,
      );
      expect(h, isNotNull);
      expect(await flyUntil(g, (r) => h!.planeX - r.state.camX < 300), isTrue);
      final camera = g.camera.viewfinder.position.clone();
      // The scheduler seam makes the warning due while the hole is on screen.
      run.state.squeeze.nextAt = run.state.runClock;
      g.update(1 / 60);
      expect(run.state.squeeze.phase, SqueezePhase.warning);
      g.world.add(FeverShake(run.ctx));
      await flushAndMount(g);
      g.update(1 / 60);
      final strips = g.world.children.whereType<SpikeStrip>().toList();
      expect(strips.every((s) => s.lens != null), isTrue);
      final p = const ui.Offset(160, 44);
      expect(strips.first.lens!(p), isNot(p));
      await pauseSnapshot(g);
      expect(
        await flyUntil(
          g,
          (r) => r.state.squeeze.phase == SqueezePhase.idle,
          maxSeconds: 30,
        ),
        isTrue,
      );
      await flyRun(g, maxSeconds: 1);
      expect(g.camera.viewfinder.position.distanceTo(camera), lessThan(.001));
      expect(
        strips.every((s) => s.squeezeInset == 0 && s.toothFlash == 0),
        isTrue,
      );
    }, height: height);
  }

  group('S6-40 regression', () {
    qa(
      'S6-40 a physical rim touch extinguishes FEVER before plane resolution',
      (g) async {
        final run = await startRun(g);
        PairHoopKind.applyGift(PairReward.fever, run.ctx);
        final h = run.spawner.hoops.first;
        // Place a real unresolved rim just ahead; outside-half contact knocks
        // the bird back rather than letting it cross the plane this frame.
        final b = run.birdTrackPosition()!;
        h.basePosition.setValues(b.x + 10, g.viewHeight / 2);
        h.position.setFrom(h.basePosition);
        g.runBird!.setFlight(y: h.position.y - h.opening / 2 - 7, vy: 0);
        g.update(1 / 60);
        expect(h.touched, isTrue);
        expect(h.resolved, isFalse);
        expect(run.state.onFire, isFalse);
      },
    );
  });

  group('S6-41 regression', () {
    qa('S6-41 portal clears the last 4 bank coins without early payout', (
      g,
    ) async {
      final run = await startRun(g);
      // Reachable bank state: 16 caught, the final field of 4 still ahead.
      // Use the real field, clearAhead, PickupCleared and PiggyFeature.
      run.state.piggy = PiggyState()..caught = 16;
      final x = run.birdTrackPosition()!.x + 120;
      run.spawner.spawnItem(
        GapItemPlan(
          kind: ElementId.piggyCoins,
          trackX: x,
          toTrackX: x + 100,
          y: 350,
          toY: 350,
          extra: 4,
        ),
      );
      await flushAndMount(g);
      final before = run.state.coinsThisRun;
      run.spawner.clearAhead();
      expect(
        run.state.coinsThisRun,
        before,
        reason:
            'A portal is not a bank payout: 4 unresolved coins must '
            'continue after landing, not resolve as voided.',
      );
      expect(run.state.piggy, isNotNull);
      expect(feature<PiggyFeature>(run).paid, 0);
    });
  });

  group('S6-42 regression', () {
    qa('S6-42 a partial Star Trail requests trailPop', (g) async {
      final run = await startRun(g);
      final sounds = sfxLog(g);
      final x = run.birdTrackPosition()!.x - 200;
      run.spawner.spawnItem(
        GapItemPlan(
          kind: ElementId.starTrail,
          trackX: x,
          toTrackX: x + 100,
          y: 350,
          toY: 350,
        ),
      );
      final trail = run.spawner.pickups.whereType<StarTrail>().single;
      for (var i = 0; i < 6; i++) {
        trail.caught[i] = true;
      }
      await flushAndMount(g);
      g.update(1 / 60);
      expect(trail.escaped, isTrue);
      expect(sounds, contains('trailPop'));
    });
  });

  group('S6-43 regression', () {
    qa('S6-43 +10 COINS pair spray retains the pale inner coin ring', (
      g,
    ) async {
      final run = await startRun(g);
      run.particles.clear();
      PairHoopKind.applyGift(PairReward.coins, run.ctx);
      expect(run.particles.alive, 10);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.translate(150, 150);
      final b = run.birdTrackPosition()!;
      canvas.translate(-b.x, -b.y);
      run.particles.paint(canvas);
      final image = await recorder.endRecording().toImage(300, 300);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      image.dispose();
      var pale = 0, gold = 0;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        final r = data.getUint8(i),
            green = data.getUint8(i + 1),
            blue = data.getUint8(i + 2),
            a = data.getUint8(i + 3);
        if (a < 240) continue;
        if (r > 230 && green > 215 && blue > 155) pale++;
        if (r > 230 && green > 130 && green < 200 && blue < 90) gold++;
      }
      expect(gold, greaterThan(20));
      expect(
        pale,
        greaterThan(10),
        reason: 'Every coin must include coin.png\'s pale inner ring.',
      );
    }, realAsync: true);
  });

  group('S6-45 regression', () {
    test('S6-45 every switch remains 70–100 pt off its ring centre', () {
      final enabled = {...registeredElements(), ...registeredPickupElements()};
      for (var seed = 1; seed <= 60; seed++) {
        final d = RunDirector(seed: seed, enabled: enabled, met: enabled);
        final c = DirectorContext.open(711, scrollSpeed: 180);
        for (var i = 0; i < 150; i++) {
          final p = d.nextSlot(c);
          d.nextGap(c, p);
          if (p.kind != HoopKindId.switchRing) continue;
          final dy = (p.attached.single.y! - p.centreY).abs();
          expect(
            dy,
            inInclusiveRange(70, 100),
            reason:
                'seed=$seed slot=${p.index} ringY=${p.centreY} '
                'switchY=${p.attached.single.y}',
          );
        }
      }
    });
  });

  group('S6-46 regression', () {
    for (final piggy in [true, false]) {
      test('S6-46 ${piggy ? 'Piggy Bank' : 'Firefly Jar'} suspends new gap '
          'fields in the squeeze window', () {
        final enabled = {
          ...registeredElements(),
          ...registeredPickupElements(),
        };
        final d = RunDirector(
          seed: 7,
          enabled: enabled,
          met: enabled,
          startHoopIndex: 50,
        );
        final c = DirectorContext.open(
          711,
          squeezeWindow: true,
          squeezeInset: 177.75,
          piggyRunning: piggy,
          jarRunning: !piggy,
        );
        final p = d.nextSlot(c);
        final gap = d.nextGap(c, p);
        expect(
          gap.items.every(
            (p) => p.kind == ElementId.heart || p.kind == ElementId.starTrail,
          ),
          isTrue,
          reason: 'Squeeze gap contains ${gap.items.map((p) => p.kind)}',
        );
      });
    }
  });

  group('S6-47 regression', () {
    qa('S6-47 portal clearing fades a mounted normal ring over 0.2 s', (
      g,
    ) async {
      final run = await startRun(g);
      final h = run.spawner.hoops.first;
      Future<int> alphaSum() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..translate(150, 150);
        h.render(canvas);
        h.front.render(canvas);
        final image = await recorder.endRecording().toImage(300, 300);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        image.dispose();
        var sum = 0;
        for (var i = 3; i < bytes.lengthInBytes; i += 4) {
          sum += bytes.getUint8(i);
        }
        return sum;
      }

      final before = await alphaSum();
      expect(before, greaterThan(10000));
      run.spawner.clearAhead();
      run.spawner.update(.1);
      await flushAndMount(g);
      expect(h.isMounted, isTrue);
      final midway = await alphaSum();
      expect(midway, greaterThan(0));
      expect(
        midway,
        lessThan(before * .9),
        reason: 'A ring halfway through its clear fade must be translucent.',
      );
    }, realAsync: true);
  });

  test('P3 director budget / cooldown / exclusivity audit across 30 seeds', () {
    final enabled = {...registeredElements(), ...registeredPickupElements()};
    final specials = List<int>.filled(6, 0);
    final total = List<int>.filled(6, 0);
    var gapsWithItems = 0;
    for (var seed = 1; seed <= 30; seed++) {
      final d = RunDirector(seed: seed, enabled: enabled, met: enabled);
      final c = DirectorContext.open(711);
      final last = <HoopKindId, int>{};
      var coolUntil = -1;
      for (var i = 0; i < 200; i++) {
        final p = d.nextSlot(c);
        final gap = d.nextGap(c, p);
        final row = i < 5
            ? 0
            : i < 8
            ? 1
            : i < 20
            ? 2
            : i < 35
            ? 3
            : i < 50
            ? 4
            : 5;
        total[row]++;
        if (gap.items.isNotEmpty) gapsWithItems++;
        final rule = DirectorTables.prd2.specials[p.kind];
        if (rule == null) continue;
        specials[row]++;
        expect(i, greaterThanOrEqualTo(rule.from));
        expect(i, greaterThan(coolUntil));
        final prev = last[p.kind];
        if (prev != null) expect(i - prev, greaterThanOrEqualTo(rule.minSince));
        last[p.kind] = i;
        coolUntil = i + rule.cooldown;
      }
      for (final ride in RideKind.values) {
        final riding = DirectorContext.open(711, rideActive: true, ride: ride);
        final p = d.nextSlot(riding);
        expect(p.kind, HoopKindId.normal);
        expect(p.motion, isNull);
        expect(p.tiltDeg, 0);
        expect(p.cometHang, isFalse);
        expect(d.nextGap(riding, p).items, isEmpty);
      }
      final squeezing = DirectorContext.open(
        711,
        squeezeWindow: true,
        squeezeInset: 177.75,
      );
      for (var i = 0; i < 30; i++) {
        final p = d.nextSlot(squeezing);
        expect([
          HoopKindId.normal,
          HoopKindId.saw,
          HoopKindId.fever,
          HoopKindId.bullseye,
        ], contains(p.kind));
        expect(p.motion, isNull);
        expect(p.cometHang, isFalse);
        expect(
          d
              .nextGap(squeezing, p)
              .items
              .every(
                (p) =>
                    p.kind == ElementId.heart || p.kind == ElementId.starTrail,
              ),
          isTrue,
        );
      }
    }
    // Observed shares are informational: cooldowns / unlocks reduce budget
    // probabilities; this pure sample does not simulate rides or pickups.
    // ignore: avoid_print
    print(
      'P3 DIRECTOR 6000 slots: specials=$specials / totals=$total; '
      'occupied gaps=$gapsWithItems /6000',
    );
  });

  test(
    'P3 force menu contains every newly built element and all six rides',
    () {
      expect(
        ForceMenu.forceable,
        containsAll([
          ElementId.comet,
          ElementId.portal,
          ElementId.fever,
          ElementId.train,
          ElementId.spring,
          ElementId.bullseye,
          ElementId.luckySpin,
          ElementId.saw,
          ElementId.switchRing,
          ElementId.pair,
          ElementId.starTrail,
          ElementId.egg,
          ElementId.piggy,
          ElementId.jar,
          ElementId.hourglass,
          ElementId.miniBird,
          ElementId.coinFrenzy,
          ElementId.squeeze,
        ]),
      );
      expect(RideId.values, hasLength(6));
    },
  );

  for (final height in [568.0, 711.0]) {
    for (final element in [
      ElementId.comet,
      ElementId.portal,
      ElementId.fever,
      ElementId.train,
      ElementId.spring,
      ElementId.bullseye,
      ElementId.luckySpin,
      ElementId.saw,
      ElementId.switchRing,
      ElementId.pair,
      ElementId.starTrail,
      ElementId.egg,
      ElementId.piggy,
      ElementId.jar,
      ElementId.hourglass,
      ElementId.miniBird,
      ElementId.coinFrenzy,
      ElementId.squeeze,
    ]) {
      qa(
        'P3 revive after $element: lose collectables, end timed effect, '
        'reset squeeze and continue h=$height',
        (g) async {
          final run = await startRun(
            g,
            startHoopIndex: element.isCapsuleType ? 0 : 45,
            force: [element],
          );
          // The debug invulnerability is only for reaching the chosen element;
          // it is off before the death / phoenix / resumed flight assertions.
          g.runDebug.god = true;
          var used = false;
          run.events
            ..on<PickupCollected>((e) {
              if (e.element == element) used = true;
            })
            ..on<HoopPassed>((e) {
              if (e.hoop?.plan.element == element) used = true;
            })
            ..on<PowerupStarted>((e) {
              if (e.type.element == element) used = true;
            });
          if (element == ElementId.squeeze) {
            expect(
              await flyUntil(
                g,
                (r) => r.state.squeeze.phase == SqueezePhase.hold,
                maxSeconds: 40,
              ),
              isTrue,
            );
          } else {
            expect(
              await flyUntil(g, (r) {
                // Guide into the real forced capsule, before other timed items
                // unlock. The regular bot primarily plans hoop crossings.
                if (element.isCapsuleType && r.state.timed == null) {
                  for (final p in r.spawner.pickups) {
                    final type = p.plan?.extra;
                    if (type is! CapsuleType || type.element != element) {
                      continue;
                    }
                    if ((p.position.x - r.birdTrackPosition()!.x).abs() < 20) {
                      g.runBird!.setFlight(y: p.position.y, vy: 0);
                    }
                  }
                }
                return used;
              }, maxSeconds: 60),
              isTrue,
              reason: '$element never used',
            );
          }
          await pauseSnapshot(g);
          if (run.state.ride != null) await flyOutOfRide(g, maxSeconds: 45);
          expect(run.state.ride, isNull);
          // Eligibility is six real passed hoops. Keep active timed / bank
          // state until death where possible (the death resets are shared).
          if (run.state.hoopsPassed < 6) {
            final flight = await flyRun(g, untilHoops: 6, maxSeconds: 30);
            expect(flight.hoops, greaterThanOrEqualTo(6));
          }
          run.state
            ..egg ??= EggState()
            ..piggy ??= PiggyState()
            ..jar ??= JarState();
          final coins = run.state.coinsThisRun;
          final score = run.state.score;
          g.runDebug.god = false;
          run.state
            ..shield = false
            ..extraLife = false
            ..invulnerable = 0;
          killRun(g);
          await flushAndMount(g);
          expect(g.state, GameState.reviving);
          expect(run.state.egg, isNull);
          expect(run.state.piggy, isNull);
          expect(run.state.jar, isNull);
          expect(run.state.timed, isNull);
          expect(run.state.onFire, isFalse);
          expect(run.state.timeScale, 1);
          expect(run.state.birdScale, 1);
          expect(run.state.coinsThisRun, coins);
          expect(run.state.score, score);
          final deathClock = run.state.runClock;
          stepGame(g, .6);
          g.reviveScreen!.tapHeart();
          for (var f = 0; f < 300 && g.state == GameState.reviving; f++) {
            g.update(1 / 60);
            if (f % 10 == 0) await flushAndMount(g);
          }
          await flushAndMount(g);
          expect(g.state, GameState.playing);
          expect(run.state.runClock, closeTo(deathClock, .05));
          expect(run.state.squeeze.inset, 0);
          expect(run.state.squeeze.phase, SqueezePhase.idle);
          expect(run.state.invulnerable, greaterThan(1.9));
          expect(g.runBirdPosition!.x, closeTo(70, .001));
          final next = await flyRun(
            g,
            untilHoops: run.state.hoopsPassed + 2,
            maxSeconds: 15,
          );
          expect(next.cause, isNull, reason: next.trace.join('\n'));
          expect(run.dying, isFalse);
        },
        height: height,
        seed: 7,
      );
    }
  }
}
