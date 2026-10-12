import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/config/comet_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/comet_star.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/rides/comet_ride.dart';
import 'package:flappy_spikes/run/rides/speed_lines.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

CometFeature _comet(RunController r) =>
    r.features.whereType<CometFeature>().single;

CometStar? _star(FlappySpikesGame g) =>
    pickupsOf(g).whereType<CometStar>().firstOrNull;

/// Flies with the bot until [until] holds (or [maxSeconds] pass).
Future<void> _flyUntil(
  FlappySpikesGame game,
  RunController run,
  bool Function() until, {
  double maxSeconds = 40,
}) async {
  final bot = Autopilot(run);
  for (var f = 0; f < maxSeconds * 60 && !until(); f++) {
    if (bot.shouldFlap()) game.onScreenTap();
    game.update(1 / 60);
    if (f % 10 == 0) await flushAndMount(game);
  }
}

/// Starts a run at hoop 10 with the comet forced and flies until the boost
/// starts.
Future<RunController> _intoBoost(FlappySpikesGame game) async {
  final run = await startRun(
    game,
    startHoopIndex: ElementId.comet.firstPossible!,
    force: [ElementId.comet],
  );
  await _flyUntil(game, run, () => _comet(run).active);
  expect(_comet(run).active, isTrue, reason: 'the bot collects the star');
  return run;
}

void _step(FlappySpikesGame game, double seconds) {
  for (var t = 0.0; t < seconds - 1e-9; t += 1 / 60) {
    game.update(1 / 60);
  }
}

FlameTester<FlappySpikesGame> _tester({
  double h = 711,
  int seed = 5,
  AnalyticsSpy? spy,
}) => FlameTester<FlappySpikesGame>(
  () => createRunTestGame(worldHeight: h, seed: seed, services: spy),
  gameSize: Vector2(320, h),
);

Future<void> _setUp(FlappySpikesGame game, _) async {
  await game.ready();
  await preloadImages(game);
}

void main() {
  group('§3.8 comet boost rules (pure)', () {
    test('§3.8 10 s at 1.7 × cruise: ease-in 0.45 s, the last 0.9 s eases '
        'back down', () {
      expect(CometConfig.duration, 10);
      expect(CometConfig.speedMult, 1.7);
      expect(CometConfig.easeIn, .45);
      expect(CometConfig.easeOut, .9);
      expect(CometRide.cruiseMultAt(0), 1);
      expect(CometRide.cruiseMultAt(.225), closeTo(1.35, 1e-9));
      expect(CometRide.cruiseMultAt(.45), closeTo(1.7, 1e-9));
      expect(CometRide.cruiseMultAt(5), closeTo(1.7, 1e-9));
      expect(CometRide.cruiseMultAt(9.1), closeTo(1.7, 1e-9));
      expect(CometRide.cruiseMultAt(9.55), closeTo(1.35, 1e-9));
      expect(CometRide.cruiseMultAt(10), 1);
      // ≈ 255 pt/s at the start of a run.
      expect(
        RunConfig.cruise(0) * CometRide.cruiseMultAt(3),
        closeTo(255, .01),
      );
      // Monotone up, flat, monotone down.
      var prev = 1.0;
      for (var t = 0.0; t <= .45; t += .01) {
        final m = CometRide.cruiseMultAt(t);
        expect(m, greaterThanOrEqualTo(prev - 1e-12));
        prev = m;
      }
      prev = CometRide.cruiseMultAt(9.1);
      for (var t = 9.1; t < 10; t += .01) {
        final m = CometRide.cruiseMultAt(t);
        expect(m, lessThanOrEqualTo(prev + 1e-12));
        prev = m;
      }
    });

    test('§3.8 / §3.0.3 the star: hit radius 18, hangs 20 pt past the plane',
        () {
      expect(PickupRadii.comet, 18);
      expect(PickupRadii.forElement(ElementId.comet), 18);
      expect(RunConfig.cometHang, 20);
      expect(pickupKindFor(ElementId.comet), isA<CometStarKind>());
      expect(registeredPickupElements(), contains(ElementId.comet));
    });

    test('§3.9 sounds: loop from 1.2 s at 30 %, 0.3 s fade', () {
      expect(CometConfig.loopDelay, 1.2);
      expect(CometConfig.loopVolume, .3);
      expect(CometConfig.loopFade, .3);
    });

    test('§5.6 the fireball and countdown: bird 90 %, shell r 28 / rim 3.5 '
        '/ inner r 22, ring r 34 gold 6 pt, label 18 pt 50 pt below', () {
      expect(CometConfig.birdScale, .9);
      expect(CometConfig.shellR, 28);
      expect(CometConfig.shellStroke, 3.5);
      expect(CometConfig.shellInnerR, 22);
      expect(CometConfig.ringR, 34);
      expect(CometConfig.ringStroke, 6);
      expect(CometConfig.labelBelow, 50);
      expect(CometConfig.labelSize, 18);
      // Tail: gold 45 %, pink 55 % triangles behind the shell.
      expect(CometConfig.tailGoldAlpha, .45);
      expect(CometConfig.tailPinkAlpha, .55);
      expect(CometConfig.tailGoldTipX, lessThan(CometConfig.tailPinkTipX));
    });

    test('§5.6 the pickup: 46 pt star, 2 pt outline, wobble ±14°, pulse '
        '±8 %', () {
      expect(CometConfig.starSize, 46);
      expect(CometConfig.starOutline, 2);
      expect(CometConfig.starWobbleDeg, 14);
      expect(CometConfig.starPulse, .08);
    });

    test('§5.6 / §3.0.9 #12 comet speed streaks: 2 pt, 30–110 pt, 0.7, '
        'every ≈ 34 ms, −460 pt in 260 ms', () {
      expect(CometConfig.lineThickness, 2);
      expect(CometConfig.lineAlpha, .7);
      expect(CometConfig.lineEvery, closeTo(.034, 1e-9));
      expect(CometConfig.lineTravel, 460);
      expect(CometConfig.lineLife, .26);
      final lines = CometSpeedLines();
      final r = math.Random(1);
      var spawned = 0;
      var prev = 0;
      for (var i = 0; i < 60; i++) {
        lines.update(1 / 60, 711, r);
        // Count newly added streaks (none expire in the first 0.26 s).
        if (i < 15) {
          spawned += lines.count - prev;
          prev = lines.count;
        }
      }
      // 0.25 s at one per 34 ms ≈ 7.
      expect(spawned, inInclusiveRange(6, 8));
      // In the steady state ≈ 0.26 / 0.034 ≈ 7–8 streaks are alive.
      expect(lines.count, inInclusiveRange(6, 9));
      for (var i = 0; i < 30; i++) {
        lines.update(1 / 60, 711, r, active: false);
      }
      expect(lines.count, 0);
    });

    test('§3.8 the pop: white flash 0.7, 10 pink / gold squares of 9 pt, a '
        'gold ring; the graphic pops 0.4 → 1.3 → 1 in 0.38 s', () {
      expect(CometConfig.flashAlpha, .7);
      expect(CometConfig.pop.squares, 10);
      expect(CometConfig.pop.squareMin, 9);
      expect(CometConfig.pop.squareMax, 9);
      expect(CometConfig.pop.ringLength, greaterThan(0));
      expect(CometConfig.popLength, .38);
      expect(CometConfig.popFrom, .4);
      expect(CometConfig.popPeak, 1.3);
    });
  });

  group('§3.8 comet boost in a run', () {
    _tester().testGameWidget(
      '§3.8 / §3.0.3 the comet hoop: normal, upright, still; the star hangs '
      '20 pt past its plane at its centre and is met on screen',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(
          game,
          startHoopIndex: ElementId.comet.firstPossible!,
          force: [ElementId.comet],
        );
        await _flyUntil(game, run, () => _star(game)?.announced ?? false);
        final star = _star(game)!;
        final hoop = hoopsOf(
          game,
        ).firstWhere((h) => h.plan.cometHang);
        expect(hoop.plan.kind, HoopKindId.normal);
        expect(hoop.plan.tiltDeg, 0);
        expect(hoop.plan.motion, isNull);
        expect(star.position.x, closeTo(hoop.plan.trackX + 20, 1e-9));
        expect(star.position.y, closeTo(hoop.plan.centreY, 1e-9));
        expect(star.hitRadius, 18);
        game.update(1 / 60);
        expect(game.storage.metElements, contains(ElementId.comet.storageId));
      },
    );

    final spy = AnalyticsSpy();
    _tester(spy: spy).testGameWidget(
      '§3.8 / §3.9 / §6 collecting the star starts the boost: ride + timed '
      'slot, pu_comet_get, knock, comet_collected; taps are ignored',
      setUp: (game, t) async {
        await _setUp(game, t);
        spy.events.clear();
      },
      verify: (game, _) async {
        final sfx = sfxLog(game);
        final run = await startRun(
          game,
          startHoopIndex: ElementId.comet.firstPossible!,
          force: [ElementId.comet],
        );
        run.events.recordLog = true;
        final rumbles = rumbleLog(game);
        await _flyUntil(game, run, () => _comet(run).active);
        final s = run.state;
        expect(s.ride?.kind, RideKind.comet);
        expect(s.timed?.type, TimedPowerup.comet);
        expect(s.timed?.duration, 10);
        expect(sfx, contains(Sfx.puCometGet.name));
        expect(rumbles, contains(RumbleKind.knock));
        final sent = analyticsLog(
          spy,
        ).where((e) => e.$1 == 'comet_collected').toList();
        expect(sent, hasLength(1));
        expect(sent.single.$2, {'source': 'hoop'});
        expect(run.events.log.whereType<RideStarted>().single.kind,
            RideKind.comet);
        expect(
          run.events.log.whereType<PowerupStarted>().single.type,
          TimedPowerup.comet,
        );
        expect(run.director.ride, RideKind.comet);
        // Taps are ignored: no flap sound, the comet keeps steering.
        sfx.clear();
        final y0 = game.runBirdPosition!.y;
        game.onScreenTap();
        game.update(1 / 60);
        expect(sfx, isNot(contains(Sfx.flap.name)));
        expect(game.runBird!.inRide, isTrue);
        expect((game.runBirdPosition!.y - y0).abs(), lessThan(40));
      },
    );

    _tester().testGameWidget(
      '§3.8 during the boost: 1.7 × cruise after the ease-in; hoops spawned '
      'now are 118 pt, upright, still; every hoop is a perfect pass with the '
      'streak, +2 coins and the tier sounds',
      setUp: _setUp,
      verify: (game, _) async {
        final sfx = sfxLog(game);
        final run = await _intoBoost(game);
        final s = run.state;
        final spawnedBefore = run.spawner.slotLog.length;
        final streak0 = s.streak;
        final coins0 = s.coinsThisRun;
        final passed0 = s.hoopsPassed;
        final passes = <HoopPassed>[];
        run.events.on<HoopPassed>(passes.add);
        sfx.clear();
        _step(game, .6);
        expect(
          s.forwardSpeed,
          closeTo(RunConfig.cruise(s.runClock) * 1.7, .5),
        );
        _step(game, 7.5);
        await flushAndMount(game);
        expect(_comet(run).active, isTrue);
        final during = run.spawner.slotLog.skip(spawnedBefore).toList();
        expect(during, isNotEmpty);
        for (final p in during) {
          expect(p.duringRide, isTrue);
          expect(p.kind, HoopKindId.normal);
          expect(p.tiltDeg, 0);
          expect(p.motion, isNull);
          expect(p.opening, closeTo(RunConfig.opening0, 1e-9));
          expect(p.cometHang, isFalse);
        }
        expect(passes.length, greaterThanOrEqualTo(5));
        for (final p in passes) {
          expect(p.perfect, isTrue);
          expect(p.duringRide, isTrue);
        }
        expect(s.hoopsPassed - passed0, passes.length);
        expect(s.streak - streak0, passes.length);
        expect(s.coinsThisRun - coins0, 2 * passes.length);
        expect(sfx, contains(Sfx.perfect3.name));
        expect(sfx, isNot(contains(Sfx.point.name)));
      },
    );

    _tester().testGameWidget(
      '§3.8 / §3.9 the end: speed eases back, pu_comet_end, the loop ran at '
      '30 % from 1.2 s and stops, control returns, the streak carries on, '
      'no extra invulnerability',
      setUp: _setUp,
      verify: (game, _) async {
        final loops = <(SfxLoop, double)>[];
        game.sound.onLoop = (l, v) => loops.add((l, v));
        final sfx = sfxLog(game);
        final run = await _intoBoost(game);
        run.events.recordLog = true;
        final ride = _comet(run).ride!;
        final s = run.state;
        _step(game, 1.1);
        expect(loops, isEmpty);
        _step(game, .2);
        expect(loops, [(SfxLoop.cometLoop, CometConfig.loopVolume)]);
        _step(game, 9.6 - ride.t);
        expect(s.ride?.phase, 'landing');
        final streakBefore = s.streak;
        expect(sfx, isNot(contains(Sfx.puCometEnd.name)));
        _step(game, 10.05 - ride.t);
        expect(ride.done, isTrue);
        expect(sfx, contains(Sfx.puCometEnd.name));
        expect(s.ride, isNull);
        expect(s.timed, isNull);
        expect(s.cruiseMult, 1);
        expect(run.director.ride, isNull);
        expect(s.forwardSpeed, closeTo(RunConfig.cruise(s.runClock), 1));
        expect(game.runBird!.inRide, isFalse);
        expect(s.invulnerable, 0);
        expect(s.streak, greaterThanOrEqualTo(streakBefore));
        expect(
          run.events.log.whereType<PowerupEnded>().single.type,
          TimedPowerup.comet,
        );
        expect(run.events.log.whereType<RideEnded>().single.kind,
            RideKind.comet);
        // Control is back: a tap flaps.
        sfx.clear();
        game.onScreenTap();
        expect(sfx, contains(Sfx.flap.name));
        _step(game, .7);
        expect(game.sound.activeLoops, isEmpty);
        expect(_comet(run).ride, isNull);
      },
    );

    _tester().testGameWidget(
      '§3.8 / §3.0.3 the comet flies through what is spawned: rims ignored, '
      'mistakes ignored (spikes), closed switches do not stop it',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await _intoBoost(game);
        final hoop = run.spawner.nextHoopAhead()!;
        expect(hoop.kind.rimMode(hoop, run.state), RimMode.ignored);
        expect(
          run.mistake(const Mistake(MistakeCause.spikes)),
          MistakeOutcome.ignored,
        );
        expect(
          run.mistake(const Mistake(MistakeCause.closedSwitch)),
          MistakeOutcome.ignored,
        );
        expect(run.dying, isFalse);
      },
    );

    _tester().testGameWidget(
      '§3.8 the comet steers to the ring nearest its line and (PRD-2.2 §16) '
      'tilts along its flight direction, max ±35°',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await _intoBoost(game);
        final ride = _comet(run).ride!;
        for (var i = 0; i < 60 * 3; i++) {
          game.update(1 / 60);
          final bird = game.runBirdPosition!;
          expect(bird.x, RunConfig.birdX);
          expect(bird.y, closeTo(ride.y, 1e-3));
          expect(ride.tilt.abs(), lessThanOrEqualTo(35 * math.pi / 180 + 1e-9));
        }
        // Right before a plane the comet sits on the ring centre.
        Hoop? h;
        for (var i = 0; i < 60 * 3; i++) {
          h = run.spawner.nextHoopAhead();
          if (h != null && h.planeX - (run.state.camX + RunConfig.birdX) < 8) {
            break;
          }
          game.update(1 / 60);
        }
        expect(ride.y, closeTo(ride.ringYAtCrossing(h!), 3));
      },
    );

    _tester().testGameWidget(
      '§3.21 a pair COMET gift (PickupCollected without a star) starts the '
      'boost with source pair; nothing starts while one runs',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game);
        game.update(1 / 60);
        run.events.emit(const PickupCollected(ElementId.comet, null));
        final f = _comet(run);
        expect(f.active, isTrue);
        expect(f.ride!.source, 'pair');
        expect(f.started, 1);
        run.events.emit(const PickupCollected(ElementId.comet, null));
        expect(f.started, 1);
      },
    );

    _tester().testGameWidget(
      '§3.8 combines with the shield and the extra life: both stay armed '
      'through the boost',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game);
        run.state
          ..shield = true
          ..extraLife = true;
        game.update(1 / 60);
        run.events.emit(const PickupCollected(ElementId.comet, null));
        _step(game, 10.5);
        expect(run.state.shield, isTrue);
        expect(run.state.extraLife, isTrue);
        expect(_comet(run).active, isFalse);
      },
    );

    _tester().testGameWidget(
      '§3.9 a paused run silences the comet loop; resume brings it back',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game);
        game.update(1 / 60);
        run.events.emit(const PickupCollected(ElementId.comet, null));
        _step(game, 1.5);
        final loop = game.sound.activeLoops.single;
        expect(loop.loop, SfxLoop.cometLoop);
        game.pause();
        game.update(1 / 60);
        expect(_comet(run).ride!.loopSilenced, isTrue);
        game.resume();
        game.update(1 / 60);
        expect(_comet(run).ride!.loopSilenced, isFalse);
      },
    );

    _tester().testGameWidget(
      '§3.0.8 first meet: from hoop 10 a never-met comet is forced within 5 '
      'slots',
      setUp: _setUp,
      verify: (game, _) async {
        // §3.0.8: one forced element at a time, oldest unlock first — other
        // elements unlocking by hoop 10 (angled, spring, bullseye …) would
        // queue ahead, so every element but the comet is already met here.
        await game.storage.saveMetElements({
          for (final e in ElementId.values)
            if (e != ElementId.comet) e.storageId,
        });
        final run = await startRun(game, startHoopIndex: 10);
        await _flyUntil(
          game,
          run,
          () => run.spawner.slotLog.length >= 6,
          maxSeconds: 20,
        );
        expect(
          run.spawner.slotLog.take(6).where((p) => p.cometHang),
          isNotEmpty,
        );
      },
    );

    _tester().testGameWidget(
      '§3.8 replay mid-boost tidies up (bird, speed, loop)',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game);
        game.update(1 / 60);
        run.events.emit(const PickupCollected(ElementId.comet, null));
        _step(game, 2);
        run.disposeRun();
        expect(run.state.ride, isNull);
        expect(run.state.cruiseMult, 1);
        expect(game.runBird!.inRide, isFalse);
      },
    );
  });
}
