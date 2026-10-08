import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/score_hud.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/squeeze_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/run_shake.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/kinds/fever.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/physics/hoop_frame.dart';
import 'package:flappy_spikes/run/physics/spike_walls.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3g: the spike squeeze (PRD-2 §3.17, §5.16).
void main() {
  // ------------------------------------------------------------ numbers
  group('§3.17 how far', () {
    test('§3.17 each wall moves 134 / 152 / 170 / 187 pt at 711 and '
        '98 / 112 / 125 / 125 at 568 (44 pt strips, band 623 / 480); '
        '4th and later = the limit', () {
      final at711 = [for (var i = 0; i < 6; i++) SqueezeConfig.insetFor(i, 711)];
      // the PRD's "≈" values (40 % of 711 = 284.4 → 169.3)
      for (final (i, v) in [134, 152, 170, 187, 187, 187].indexed) {
        expect(at711[i], closeTo(v, 1));
      }
      final at568 = [for (var i = 0; i < 6; i++) SqueezeConfig.insetFor(i, 568)];
      expect(at568.map((v) => v.round()), [98, 112, 125, 125, 125, 125]);
      // both walls move the same distance: the band stays centred
      for (final h in [568.0, 711.0]) {
        for (var i = 0; i < 4; i++) {
          final d = SqueezeConfig.insetFor(i, h);
          final top = RunConfig.stripHeight + d;
          final floor = h - RunConfig.stripHeight - d;
          expect((top + floor) / 2, closeTo(h / 2, 1e-9));
          expect(floor - top, closeTo(SqueezeConfig.openFor(i, h), 1e-9));
        }
      }
    });

    test('§3.17 open space 50 / 45 / 40 / 35 % of the screen, never under '
        '230 pt (568: the floor from the 3rd squeeze)', () {
      expect(SqueezeConfig.openFractions, [.5, .45, .4, .35]);
      expect(SqueezeConfig.minOpen, 230);
      expect(SqueezeConfig.openFor(0, 711), closeTo(355.5, 1e-9));
      expect(SqueezeConfig.openFor(3, 711), closeTo(248.85, 1e-9));
      expect(SqueezeConfig.openFor(1, 568), closeTo(255.6, 1e-9));
      expect(SqueezeConfig.openFor(2, 568), 230);
      expect(SqueezeConfig.openFor(9, 568), 230);
    });

    test('§3.17 schedule knobs: 60–120 s, hold 10–20 s, window 3 s before '
        'the warning, waits until a ride / revive ends + 2 s', () {
      expect(RunConfig.squeezeGapMin, 60);
      expect(RunConfig.squeezeGapMax, 120);
      expect(RunConfig.squeezeHoldMin, 10);
      expect(RunConfig.squeezeHoldMax, 20);
      expect(RunConfig.squeezeWindowLead, 3);
      expect(SqueezeConfig.waitAfter, 2);
    });
  });

  group('§3.17 / §5.16 sequence and look', () {
    test('§3.17 phases: warning 1.5 s, closing 3 s, opening 3 s, ticks in '
        'the last 3 s; ease-in-out', () {
      expect(SqueezeConfig.warning, 1.5);
      expect(SqueezeConfig.closing, 3);
      expect(SqueezeConfig.opening, 3);
      expect(SqueezeConfig.lastTicks, 3);
      expect(SqueezeConfig.ease(0), 0);
      expect(SqueezeConfig.ease(.5), .5);
      expect(SqueezeConfig.ease(1), 1);
      expect(SqueezeConfig.ease(.25), closeTo(.125, 1e-9));
      expect(SqueezeConfig.ease(.75), closeTo(.875, 1e-9));
    });

    test('§3.17 shake: warning 0 → 2.6 pt, closing 2.2, lock 6 pt over '
        '0.35 s, opening 1.4 pt over 0.8 s (the RunShake helpers)', () {
      expect(SqueezeConfig.warnShake, RunShake.squeezeWarning(1.5));
      expect(SqueezeConfig.closeShake, RunShake.squeezeClosing);
      expect(SqueezeConfig.lockShake, RunShake.squeezeLock(0));
      expect(RunShake.squeezeLock(SqueezeConfig.lockShakeTime), 0);
      expect(SqueezeConfig.openShake, RunShake.squeezeOpening(0));
      expect(RunShake.squeezeOpening(SqueezeConfig.openShakeTime), 0);
      expect(SqueezeConfig.tickTremble, closeTo(1.44, 1e-9));
    });

    test('§5.16 warning flash: #FF3B5C on the teeth, pulsing every 0.5 s '
        'through the 1.5 s warning and the first 0.4 s of closing', () {
      expect(SqueezeConfig.flashColor.toARGB32(), 0xFFFF3B5C);
      expect(SqueezeConfig.flashPeriod, .5);
      expect(SqueezeConfig.flashIntoClosing, .4);
      expect(SqueezeConfig.flashAt(0), closeTo(0, 1e-9));
      expect(SqueezeConfig.flashAt(.25), closeTo(SqueezeConfig.flashPeak, 1e-9));
      expect(SqueezeConfig.flashAt(.5), closeTo(0, 1e-9));
      expect(SqueezeConfig.flashAt(1.25), closeTo(SqueezeConfig.flashPeak, 1e-9));
      expect(SqueezeConfig.flashAt(1.75), closeTo(SqueezeConfig.flashPeak, 1e-9));
      expect(SqueezeConfig.flashAt(1.7), greaterThan(.5), reason: 'into closing');
      expect(SqueezeConfig.flashAt(1.9), 0);
      expect(SqueezeConfig.flashAt(-1), 0);
    });

    test('§5.16 bits 2–5 pt ≈ 28/s fading over 0.7 s; lock dust 40 squares '
        '3–7 pt', () {
      expect(SqueezeConfig.bitsPerSecond, 28);
      expect([SqueezeConfig.bitMin, SqueezeConfig.bitMax], [2, 5]);
      expect(SqueezeConfig.bitLife, .7);
      expect(SqueezeConfig.dustCount, 40);
      expect([SqueezeConfig.dustMin, SqueezeConfig.dustMax], [3, 7]);
    });

    test('§3.17 score circle cover: 0 until a tooth line reaches the circle, '
        'then up to 1 over 30 pt', () {
      expect(SqueezeConfig.coverRamp, 30);
      double cover(double top, double floor) => ScoreHud.coverFor(
        centreY: 390.5,
        radius: 91.5,
        top: top,
        floor: floor,
      );
      expect(cover(44, 667), 0);
      expect(cover(44, 482), 0);
      expect(cover(44, 467), closeTo(.5, 1e-9));
      expect(cover(44, 400), 1);
      expect(cover(314, 667), closeTo(.5, 1e-9));
    });
  });

  // ------------------------------------------------------------ flows
  Future<void> boot(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  SqueezeFeature feature(RunController r) =>
      r.features.whereType<SqueezeFeature>().single;

  /// Starts a run (god mode: the bot cannot die while the test drives the
  /// squeeze) and brings the squeeze in at once.
  Future<RunController> squeezeNow(
    FlappySpikesGame g, {
    int index = 0,
    bool god = true,
  }) async {
    g.runDebug.god = god;
    final run = await startRun(g);
    await flyUntil(g, (r) => r.state.hoopsPassed >= 1);
    run.state.squeeze
      ..index = index
      ..nextAt = run.state.runClock + .02;
    return run;
  }

  for (final h in [711.0, 568.0]) {
    final spy = AnalyticsSpy();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, services: spy),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§3.17 a squeeze from start to open (${h.toInt()} pt): moment 60–120 s, '
      'warning 1.5 s → closing 3 s → lock → hold 10–20 s with 3 ticks → '
      'opening 3 s; walls = the strips; sounds, loop, shake, flash, bits, '
      'dust, met, analytics; the next one 60–120 s later and tighter',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        game.runDebug.god = true;
        final run = await startRun(game);
        final s = run.state;
        final sq = s.squeeze;
        final f = feature(run);
        expect(sq.phase, SqueezePhase.idle);
        expect(sq.nextAt, inInclusiveRange(60, 120));
        final sfx = sfxLog(game);
        final loops = <SfxLoop>[];
        game.sound.onLoop = (l, v) => loops.add(l);
        final at = <SqueezePhase, double>{};
        run.events.on<SqueezePhaseChanged>((e) => at[e.phase] = s.runClock);
        final vf0 = game.camera.viewfinder.position.clone();
        // Fly to the moment (the bot keeps the bird alive).
        await flyUntil(game, (r) => r.state.hoopsPassed >= 1);
        sq.nextAt = s.runClock + .5;
        await flyUntil(game, (_) => sq.phase == SqueezePhase.warning);
        expect(at[SqueezePhase.warning], closeTo(sq.nextAt, 1 / 30));
        expect(s.metThisRun, contains(ElementId.squeeze));
        expect(sfx, contains(Sfx.sqWarn.name));
        expect(sq.inset, 0);
        final strips = game.world.children.whereType<SpikeStrip>().toList();
        expect(strips, hasLength(2));
        // Flash peak 0.25 s in, shake building, bits falling, no text.
        var shook = false;
        await flyUntil(game, (_) {
          shook |= (game.camera.viewfinder.position - vf0).length > .01;
          return f.phaseT >= .25;
        });
        expect(strips.first.toothFlash, greaterThan(.8));
        expect(shook, isTrue);
        expect(f.pool!.alive, greaterThan(0));
        expect(f.shake.sustain, closeTo(2.6 * .25 / .6, .1));
        // Closing: the walls ease in; 3 s; the strips follow.
        await flyUntil(game, (_) => sq.phase == SqueezePhase.closing);
        expect(
          at[SqueezePhase.closing]! - at[SqueezePhase.warning]!,
          closeTo(1.5, 1 / 30),
        );
        expect(sfx, contains(Sfx.sqClose.name));
        final depth = SqueezeConfig.insetFor(0, h);
        await flyUntil(game, (_) => f.phaseT >= 1.5);
        expect(sq.inset, closeTo(depth / 2, depth * .05));
        expect(strips.first.toothFlash, 0, reason: 'flash ends 0.4 s in');
        expect(f.shake.sustain, 2.2);
        game.update(0);
        expect(strips.first.squeezeInset, sq.inset);
        expect(strips.first.squeezedReach, 44 + sq.inset);
        expect(run.walls.top, closeTo(44 + sq.inset, 1e-9));
        expect(run.walls.floor, closeTo(h - 44 - sq.inset, 1e-9));
        // Lock: full depth, punch, dust, the hold loop.
        await flyUntil(game, (_) => sq.phase == SqueezePhase.hold);
        expect(
          at[SqueezePhase.hold]! - at[SqueezePhase.closing]!,
          closeTo(3, 1 / 30),
        );
        expect(sq.inset, depth);
        expect(sfx, contains(Sfx.sqLock.name));
        expect(f.pool!.alive, greaterThanOrEqualTo(SqueezeConfig.dustCount));
        expect(f.shake.amplitude, greaterThan(5));
        expect(sq.holdS, inInclusiveRange(10, 20));
        expect(loops, [SfxLoop.sqHold]);
        expect(
          game.sound.activeLoops.map((l) => l.loop),
          contains(SfxLoop.sqHold),
        );
        expect(strips.first.toothFlash, 0);
        // Hold: no ticks until the last 3 s, then one per second.
        await flyUntil(game, (_) => f.phaseT >= sq.holdS - 3.1);
        expect(sfx.where((n) => n == Sfx.sqTick.name), isEmpty);
        await flyUntil(game, (_) => sq.phase == SqueezePhase.opening);
        expect(sfx.where((n) => n == Sfx.sqTick.name), hasLength(3));
        expect(
          at[SqueezePhase.opening]! - at[SqueezePhase.hold]!,
          closeTo(sq.holdS, 1 / 30),
        );
        // Opening: the loop stops, relief sound, walls ease out.
        expect(sfx, contains(Sfx.sqOpen.name));
        expect(
          game.sound.activeLoops.map((l) => l.loop),
          isNot(contains(SfxLoop.sqHold)),
        );
        await flyUntil(game, (_) => sq.phase == SqueezePhase.idle);
        expect(
          at[SqueezePhase.idle]! - at[SqueezePhase.opening]!,
          closeTo(3, 1 / 30),
        );
        expect(sq.inset, 0);
        expect(sq.index, 1);
        expect(sq.nextAt - s.runClock, inInclusiveRange(60, 120));
        await flyUntil(game, (_) => false, maxSeconds: 1);
        expect((game.camera.viewfinder.position - vf0).length, lessThan(1e-3));
        expect(run.ended, isFalse);
        final events = analyticsLog(spy);
        final startedEv = events.where((e) => e.$1 == 'squeeze_started').single;
        expect(startedEv.$2!['index'], 1);
        expect(
          startedEv.$2!['open_pct'],
          (SqueezeConfig.openFor(0, h) / h * 100).round(),
        );
        expect(startedEv.$2!['hold_s'], sq.holdS.round());
        expect(
          events.where((e) => e.$1 == 'squeeze_survived').single.$2,
          {'index': 1},
        );
        // The second squeeze leaves less room.
        sq.nextAt = s.runClock + .1;
        await flyUntil(game, (_) => sq.phase == SqueezePhase.hold);
        expect(sq.inset, SqueezeConfig.insetFor(1, h));
        expect(sq.inset, greaterThan(depth));
        // No rumble for the squeeze (§3.33).
        expect(f.started, 2);
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§3.17 a squeeze never starts during a ride: it waits until the ride '
    'ends + 2 s; the same after a revive',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await squeezeNow(game);
      final s = run.state;
      s.ride = RideState(kind: RideKind.comet);
      for (var i = 0; i < 60; i++) {
        game.update(1 / 60);
      }
      expect(s.squeeze.phase, SqueezePhase.idle);
      s.ride = null;
      run.events.emit(const RideEnded(RideKind.comet));
      final endedAt = s.runClock;
      await flyUntil(game, (_) => s.squeeze.phase != SqueezePhase.idle);
      expect(s.runClock - endedAt, closeTo(2, 1 / 30));
      expect(s.squeeze.phase, SqueezePhase.warning);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§3.17 the window: from 3 s before the warning until open the director '
    'places in the squeezed band of the coming squeeze; a debug force waits '
    'until every hoop already ahead is behind the 3 s line',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game);
      await flyUntil(game, (r) => r.state.hoopsPassed >= 1);
      final s = run.state;
      expect(run.directorContext().squeezeWindow, isFalse);
      run.debugForce(ElementId.squeeze);
      final birdX = run.birdTrackPosition()!.x;
      final cruise = RunConfig.cruise(s.runClock);
      for (final h in run.spawner.hoops) {
        final cross = s.runClock + (h.planeX - birdX) / cruise;
        expect(cross, lessThanOrEqualTo(s.squeeze.nextAt - 3));
      }
      // Window on (3 s before the warning): the coming squeeze's band.
      await flyUntil(
        game,
        (_) => s.runClock >= s.squeeze.nextAt - 3 + .1,
      );
      final ctx = run.directorContext();
      final d = SqueezeConfig.insetFor(0, 711);
      expect(ctx.squeezeWindow, isTrue);
      expect(s.squeeze.inset, 0);
      expect(ctx.squeezeTopTooth, closeTo(44 + d, 1e-9));
      expect(ctx.squeezeFloorTooth, closeTo(711 - 44 - d, 1e-9));
      expect(ctx.topTooth, 44, reason: 'the normal band is unchanged');
      // Still on while the walls open; off once they are open.
      await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.opening);
      expect(run.directorContext().squeezeWindow, isTrue);
      await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.idle);
      expect(run.directorContext().squeezeWindow, isFalse);
      expect(run.directorContext().squeezeTopTooth, 44);
    },
  );

  for (final h in [711.0, 568.0]) {
    final spy = AnalyticsSpy();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, services: spy),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§3.17 the moving walls are the spikes: touching the squeezed floor is '
      'a spike death, the tumble rests on the squeezed floor (§3.0.5), '
      'squeeze_death (index, phase) (${h.toInt()} pt)',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await squeezeNow(game);
        final s = run.state;
        await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.hold);
        final floor = run.walls.floor;
        expect(floor, closeTo(h - 44 - SqueezeConfig.insetFor(0, h), 1e-9));
        // plain math: the bird circle reaching the squeezed tooth line
        final r = RunConfig.birdRadius;
        expect(
          run.walls.touches(BirdCircle(Vector2(100, floor - r + .5), r)),
          SpikeSide.floor,
        );
        expect(
          run.walls.touches(BirdCircle(Vector2(100, floor - r - .5), r)),
          isNull,
        );
        game.runDebug.god = false;
        s.invulnerable = 0;
        // stop flapping: the bird falls onto the squeezed floor
        await flyUntil(game, (_) => run.dying, autopilot: false);
        expect(run.lastDeath?.cause, MistakeCause.spikes);
        expect(
          game.sound.activeLoops.map((l) => l.loop),
          isNot(contains(SfxLoop.sqHold)),
        );
        for (var i = 0; i < 120 && !run.tumble!.resting; i++) {
          game.update(1 / 60);
        }
        expect(run.tumble!.floor, floor);
        expect(game.runBirdPosition!.y, lessThanOrEqualTo(floor + 1));
        expect(game.runBirdPosition!.y, greaterThan(floor - 3 * r));
        expect(
          analyticsLog(spy).where((e) => e.$1 == 'squeeze_death').single.$2,
          {'index': 1, 'phase': 'hold'},
        );
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§3.17 a save on a squeezed wall bounces off the squeezed tooth line '
    '(shield, as on the normal spikes)',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await squeezeNow(game);
      final s = run.state;
      await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.hold);
      game.runDebug.god = false;
      s
        ..invulnerable = 0
        ..shield = true;
      final saves = <MistakeSaved>[];
      run.events.on<MistakeSaved>(saves.add);
      final top = run.walls.top;
      game.runBird!.setFlight(y: top + RunConfig.birdRadius - 1, vy: -200);
      game.update(1 / 60);
      expect(saves, hasLength(1));
      expect(run.dying, isFalse);
      expect(game.runBirdPosition!.y, greaterThan(top + RunConfig.birdRadius - .1));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§3.17 / §3.14 a revived death during a squeeze: the walls slide out '
    'over 0.5 s (bits fall), the interrupted squeeze counts (the next is '
    'tighter), the next comes 60–120 s later; a due squeeze waits 2 s '
    'after the revive',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await squeezeNow(game);
      final s = run.state;
      final f = feature(run);
      await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.hold);
      final depth = s.squeeze.inset;
      game.runDebug.god = false;
      for (var i = 0; i < 6; i++) {
        run.debugPass(perfect: true);
      }
      s.invulnerable = 0;
      killRun(game);
      await flushAndMount(game);
      expect(game.state, GameState.reviving);
      expect(s.squeeze.inset, depth, reason: 'the walls stay while dying');
      final screen = game.reviveScreen!;
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      screen.tapHeart();
      for (var i = 0; i < 60 && screen.phoenix == null; i++) {
        game.update(1 / 60);
        await flushAndMount(game);
      }
      expect(s.squeeze.phase, SqueezePhase.idle);
      expect(s.squeeze.index, 1);
      expect(s.squeeze.nextAt - s.runClock, inInclusiveRange(60, 120));
      for (var i = 0; i < 15; i++) {
        game.update(1 / 60);
      }
      expect(s.squeeze.inset, inExclusiveRange(0, depth));
      expect(f.pool!.alive, greaterThan(0));
      for (var i = 0; i < 20; i++) {
        game.update(1 / 60);
      }
      expect(s.squeeze.inset, 0);
      for (var i = 0; i < 400 && game.state == GameState.reviving; i++) {
        game.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(game);
      }
      expect(game.state, GameState.playing);
      // A squeeze due right after the revive waits 2 s.
      game.runDebug.god = true;
      final revivedAt = s.runClock;
      s.squeeze.nextAt = s.runClock;
      await flyUntil(game, (_) => s.squeeze.phase != SqueezePhase.idle);
      expect(s.runClock - revivedAt, closeTo(2, .05));
      await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.hold);
      expect(s.squeeze.inset, SqueezeConfig.insetFor(1, 711));
    },
  );

  for (final (h, index, covered) in [
    (568.0, 3, true),
    (711.0, 0, false),
  ]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§3.17 the score circle turns white while a wall covers it and is '
      'painted over the walls (${h.toInt()} pt, squeeze ${index + 1})',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await squeezeNow(game, index: index);
        final hud = game.world.children.whereType<ScoreHud>().single;
        final overlay = game.world.children.whereType<ScoreCoverOverlay>().single;
        expect(overlay.priority, greaterThan(SpikeStrip.basePriority));
        await flyUntil(game, (_) => run.state.squeeze.phase == SqueezePhase.hold);
        final expected = ScoreHud.coverFor(
          centreY: hud.position.y,
          radius: Config.scoreCircleSize.x / 2,
          top: run.walls.top,
          floor: run.walls.floor,
        );
        expect(hud.squeezeCover, closeTo(expected, 1e-9));
        expect(hud.squeezeCover > 0, covered);
        expect(overlay.floor, run.walls.floor);
        await flyUntil(game, (_) => run.state.squeeze.phase == SqueezePhase.idle);
        await flyUntil(game, (_) => false, maxSeconds: .1);
        expect(hud.squeezeCover, 0);
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§5.16 the hold loop stops in pause and plays again on resume; the run '
    'clock (and the squeeze) stands still while paused',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await squeezeNow(game);
      final s = run.state;
      await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.hold);
      final t = feature(run).phaseT;
      game.pause();
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      expect(
        game.sound.activeLoops.map((l) => l.loop),
        isNot(contains(SfxLoop.sqHold)),
      );
      expect(feature(run).phaseT, t);
      game.resume();
      game.update(1 / 60);
      expect(
        game.sound.activeLoops.map((l) => l.loop),
        contains(SfxLoop.sqHold),
      );
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§3.0.8 the squeeze is forceable from the debug menu (queued from home '
    'into the run) and counts as met when it shows',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game, force: [ElementId.squeeze]);
      final s = run.state;
      expect(s.squeeze.nextAt, lessThan(10));
      await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.warning);
      expect(s.metThisRun, contains(ElementId.squeeze));
      expect(game.storage.metElements, contains('squeeze'));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§5.16 / §5.18 / §5.17 the squeeze shake composes with the FEVER pass '
    'shake (camera deltas; the camera comes back), and the squeezed strips '
    'still bend through the Black Hole lens',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await squeezeNow(game);
      final s = run.state;
      final vf0 = game.camera.viewfinder.position.clone();
      await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.closing);
      game.world.add(FeverShake(run.ctx));
      await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.hold);
      // lens + squeeze + flash render together
      final strip = game.world.children.whereType<SpikeStrip>().first;
      strip.lens = (p) => Offset(p.dx, p.dy + 10);
      strip.toothFlash = .5;
      final recorder = PictureRecorder();
      strip.renderTree(Canvas(recorder));
      recorder.endRecording().dispose();
      strip.lens = null;
      await flyUntil(game, (_) => s.squeeze.phase == SqueezePhase.idle);
      await flyUntil(game, (_) => false, maxSeconds: 1);
      expect(game.world.children.whereType<FeverShake>(), isEmpty);
      expect((game.camera.viewfinder.position - vf0).length, lessThan(1e-3));
    },
  );
}
