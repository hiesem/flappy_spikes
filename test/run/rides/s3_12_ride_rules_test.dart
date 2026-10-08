import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/portal_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/portal.dart';
import 'package:flappy_spikes/run/items/streak.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_path.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flappy_spikes/run/rides/themes/storm.dart';
import 'package:flappy_spikes/run/rides/themes/themes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

PortalRideFeature _feature(RunController r) =>
    r.features.whereType<PortalRideFeature>().single;

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

FlameTester<FlappySpikesGame> _tester([double h = 711]) =>
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: 5),
      gameSize: Vector2(320, h),
    );

Future<void> _setUp(FlappySpikesGame game, _) async {
  await game.ready();
  await preloadImages(game);
}

void main() {
  group('§3.12 ride paths (pure)', () {
    test('§3.12 the cannon path: curve up r 180, climb 1 600, loop r 220, '
        'dive 2 000; rings every 380 pt from 190', () {
      final t = rideThemeFor(RideId.cannon);
      final p = t.buildPath();
      final expected = 180 * math.pi / 2 + 1600 + 220 * math.pi + 2000;
      expect(p.length, closeTo(expected, expected * .005));
      final st = t.ringStations(p);
      expect(st, hasLength(11));
      for (var k = 0; k < 11; k++) {
        expect(st[k], closeTo(190 + 380 * k, 1e-9));
      }
      expect(st.last, lessThan(p.length));
      // Up at the top of the climb, down at the end (the dive).
      expect(p.headingAt(283 + 800), closeTo(-math.pi / 2, .01));
      expect(math.sin(p.headingAt(p.length - 10)), closeTo(1, .01));
    });

    for (final id in RideId.values) {
      test('§3.12 / §7 ${id.name}: 11 rings at equal arc length along the '
          'path, facing the path', () {
        final t = rideThemeFor(id);
        final p = t.buildPath();
        final st = t.ringStations(p);
        expect(st, hasLength(PortalConfig.rideRings));
        expect(st.first, closeTo(PortalConfig.firstRing, 1e-9));
        final step = st[1] - st[0];
        for (var i = 1; i < st.length; i++) {
          expect(st[i] - st[i - 1], closeTo(step, 1e-6));
        }
        expect(st.last, lessThan(p.length - 100));
        // Arc length really is arc length: integrate the polyline.
        var s = 0.0;
        var prev = p.at(st[3]);
        for (var x = st[3] + 1; x <= st[4]; x += 1) {
          final q = p.at(x);
          s += (q - prev).length;
          prev = q;
        }
        expect(s, closeTo(step, step * .01));
        if (id != RideId.cannon) {
          // §5.12b paths ≈ 4 250 pt (each theme's own shape).
          expect(p.length, inInclusiveRange(3600, 5200), reason: '${p.length}');
          expect(
            st.last,
            closeTo(p.length - PortalConfig.themedRingEndMargin, 1e-6),
          );
        }
        // The ride ring is rotated to the heading at its station.
        expect(p.headingAt(st[5]).isFinite, isTrue);
      });
    }

    test('§5.12b storm: a 4.2-turn corkscrew up a funnel narrowing from '
        'r 150 to 70; depth ±1', () {
      final p = rideThemeFor(RideId.storm).buildPath();
      final pts = p.points;
      final helix = pts.where((q) => q.d != 0 || q.x != pts.first.x).toList();
      var minD = 0.0, maxD = 0.0;
      for (final q in pts) {
        minD = math.min(minD, q.d);
        maxD = math.max(maxD, q.d);
      }
      expect(minD, closeTo(-1, .01));
      expect(maxD, closeTo(1, .01));
      // Radius at the end of the funnel.
      final last = pts.last;
      final r = (last.x - p.axisX).abs() / math.max(1e-9, last.d.abs());
      expect(r, closeTo(StormTheme.r1, 1));
      // 4.2 turns: the depth (cos θ) crosses zero ≈ 8.4 times.
      var crossings = 0;
      for (var i = 1; i < pts.length; i++) {
        if ((pts[i - 1].d < 0) != (pts[i].d < 0) && pts[i - 1].d != 0) {
          crossings++;
        }
      }
      expect(crossings, inInclusiveRange(8, 9));
      expect(helix, isNotEmpty);
    });

    test('§7 RidePath.segments: arcs turn by their angle, lines go straight',
        () {
      final p = RidePath.segments(const [RideSeg.line(100), RideSeg.arc(50, 90)]);
      expect(p.length, closeTo(100 + 50 * math.pi / 2, .2));
      expect(p.at(100).x, closeTo(100, 1e-6));
      expect(p.headingAt(p.length), closeTo(math.pi / 2, 1e-6));
      expect(p.end.y, closeTo(50, .01));
    });
  });

  group('§3.12 ride rules (run)', () {
    _tester().testGameWidget(
      '§3.12 chain: the first curve ring is visible ahead, the rest hidden '
      'until the ride; then only rings ≤ 1 500 pt ahead are shown',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 25, ride: RideId.space);
        final f = _feature(run);
        await flushAndMount(game);
        final portal = run.spawner.hoops.firstWhere(
          (h) => h.plan.kind == HoopKindId.portal,
        );
        expect(portal.kind, isA<PortalHoopKind>());
        final preview = f.previewOf(portal)!;
        expect(preview.isMounted, isTrue);
        expect(preview.plan.kind, HoopKindId.rideRing);
        final path = rideThemeFor(RideId.space).buildPath();
        final p0 = path.at(PortalConfig.firstRing);
        expect(preview.position.x, closeTo(portal.planeX + p0.x, .01));
        expect(preview.position.y, closeTo(portal.position.y + p0.y, .01));
        // Only one ride ring before the ride.
        expect(
          game.world.descendants().whereType<Hoop>().where(
            (h) => h.plan.kind == HoopKindId.rideRing,
          ),
          hasLength(1),
        );
        await _flyUntil(game, run, () => f.ride != null);
        final r = f.ride!;
        for (var i = 0; i < 300 && r.phase == RidePhase.ride; i++) {
          game.update(1 / 60);
          if (i % 10 == 0) await flushAndMount(game);
          final shown = r.rings.where((h) => h.isMounted || h.isLoading);
          for (final h in shown) {
            final idx = r.rings.indexOf(h);
            final st = r.stations[idx];
            expect(st - r.view.s, lessThan(PortalConfig.ringsAhead + 10));
          }
        }
      },
    );

    _tester().testGameWidget(
      '§3.12 entering: the camera starts at the live scroll speed, the bird '
      'accelerates to 480 pt/s over 2.2 s and moves to its ride position; '
      'everything ahead is cleared; rims are ignored',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 25, ride: RideId.cannon);
        final f = _feature(run);
        double? cruise;
        await _flyUntil(game, run, () {
          cruise = run.state.forwardSpeed;
          return f.ride != null;
        });
        final r = f.ride!;
        expect(r.speed, closeTo(cruise!, 12));
        final bird = game.runBirdPosition!;
        expect(
          run.spawner.hoops.where((h) => h.planeX > run.state.camX + bird.x),
          isEmpty,
          reason: 'hoops ahead cleared',
        );
        expect(run.state.ride?.kind, RideKind.portal);
        expect(run.state.rideOrSqueezeBlocksSpawns(), isTrue);
        for (var t = 0.0; t < 2.3; t += 1 / 60) {
          game.update(1 / 60);
        }
        expect(r.speed, closeTo(PortalConfig.rideSpeed, 1));
        final p = game.runBirdPosition!;
        expect(p.x, closeTo(RunConfig.birdX + PortalConfig.rideOffsetX, 1));
        expect(p.y, closeTo(711 / 2 + PortalConfig.rideOffsetY, 1));
        // The ride's hoops never get rims.
        expect(r.rings.first.kind.rimMode(r.rings.first, run.state).name, 'ignored');
      },
    );

    _tester().testGameWidget(
      '§3.12 the shot: ballistic 560 / −640 pt/s with g 520, the camera '
      'follows; the bird glides home to (70, viewHeight / 2); strips fade '
      'back in with the teeth scrolling right to left',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 25, ride: RideId.cannon);
        final f = _feature(run);
        await _flyUntil(game, run, () => f.ride?.phase == RidePhase.fly);
        final r = f.ride!;
        final launch = r.launch;
        for (var i = 0; i < 60; i++) {
          game.update(1 / 60);
        }
        final ft = r.view.ft;
        // World offset + screen position = launch + ballistic.
        final pos = r.pose.pos;
        expect(
          pos.dx + r.view.off.dx,
          closeTo(launch.dx + PortalConfig.launchVx * ft, .5),
        );
        expect(
          pos.dy + r.view.off.dy,
          closeTo(
            launch.dy +
                PortalConfig.launchVy * ft +
                .5 * PortalConfig.launchGravity * ft * ft,
            .5,
          ),
        );
        await _flyUntil(game, run, () => r.phase == RidePhase.glide);
        final shift0 = r.teethShift;
        game.update(1 / 60);
        game.update(1 / 60);
        expect(shift0 - r.teethShift, closeTo(2 * PortalConfig.teethScroll / 60, 3));
        await _flyUntil(
          game,
          run,
          () => r.view.gt >= PortalConfig.glideTime,
        );
        expect(r.pose.pos.dx, closeTo(RunConfig.birdX, 1));
        expect(r.pose.pos.dy, closeTo(711 / 2, 2));
        await _flyUntil(game, run, () => f.ride == null);
        final b = game.runBirdPosition!;
        expect(b.x, closeTo(RunConfig.birdX, .01));
        expect(b.y, closeTo(711 / 2, 2));
      },
    );

    _tester().testGameWidget(
      '§3.12 / §3.0.3 a running Hourglass / Mini / Frenzy is paused in the '
      'ride and resumes after the landing',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 25, ride: RideId.storm);
        final f = _feature(run);
        run.state.timed = TimedPowerupState(type: TimedPowerup.hourglass, duration: 30);
        final events = <RunEvent>[];
        run.events.onAny(events.add);
        await _flyUntil(game, run, () => f.ride != null);
        expect(run.state.timed!.paused, isTrue);
        expect(events.whereType<PowerupPaused>(), hasLength(1));
        await _flyUntil(game, run, () => f.ride == null);
        expect(run.state.timed!.paused, isFalse);
        expect(events.whereType<PowerupResumed>(), hasLength(1));
      },
    );

    for (final id in [RideId.cannon, RideId.sea]) {
      _tester().testGameWidget(
        '§3.0.9 #12 ${id.name}: its own speed lines '
        '(${id == RideId.cannon ? 'CannonSpeedLines' : 'RideSpeedLines'})',
        setUp: _setUp,
        verify: (game, _) async {
          final run = await startRun(game, startHoopIndex: 25, ride: id);
          final f = _feature(run);
          await _flyUntil(game, run, () => (f.ride?.view.rt ?? 0) > 1);
          final r = f.ride!;
          if (id == RideId.cannon) {
            expect(r.cannonLines.count, greaterThan(10));
            expect(r.rideLines.count, 0);
          } else {
            expect(r.rideLines.count, greaterThan(10));
            expect(r.cannonLines.count, 0);
          }
        },
      );
    }

    _tester().testGameWidget(
      '§3.12 the bird is hidden in the barrel: no trail; the trail follows '
      'the bird in the ride',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 25, ride: RideId.cannon);
        final f = _feature(run);
        final streak = run.features.whereType<StreakFeature>().single;
        await _flyUntil(game, run, () => (f.ride?.view.rt ?? 0) > .5);
        game.update(1 / 60);
        expect(streak.trailActive, isTrue);
        await _flyUntil(
          game,
          run,
          () => f.ride?.phase == RidePhase.exit && f.ride!.view.et > .5,
        );
        game.update(1 / 60);
        expect(run.state.ride!.birdHidden, isTrue);
        expect(streak.trailActive, isFalse);
      },
    );

    _tester().testGameWidget(
      '§3.12 never the same ride twice in a row — also across runs '
      '(lastPortalRide)',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 25, ride: RideId.volcano);
        final f = _feature(run);
        await _flyUntil(game, run, () => f.ride != null);
        expect(game.storage.lastPortalRide, 'volcano');
        // §3.12 the run cannot end during the ride.
        killRun(game);
        expect(game.state, GameState.playing);
        expect(run.ended, isFalse);
        await _flyUntil(game, run, () => f.ride == null);
        killRunThroughSaves(game);
        await declineRevive(game);
        game.goHome();
        await flushAndMount(game);
        final run2 = await startRun(game, startHoopIndex: 25);
        expect(identical(run2, run), isFalse);
        expect(run2.director.lastRide, RideId.volcano);
        run2.debugForce(HoopKindId.portal.element);
        await _flyUntil(game, run2, () => run2.spawner.slotLog.any(
          (p) => p.kind == HoopKindId.portal,
        ));
        final first = run2.spawner.slotLog.firstWhere(
          (p) => p.kind == HoopKindId.portal,
        );
        expect(first.extra, isNot(RideId.volcano));
      },
    );

    _tester().testGameWidget(
      '§3.0.8 force portal ride from the debug menu during a run: the next '
      'slot is the portal with that ride',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game);
        final f = _feature(run);
        await _flyUntil(game, run, () => run.state.hoopsPassed >= 1);
        game.debugForceRide(RideId.pinball);
        await _flyUntil(game, run, () => f.ride != null, maxSeconds: 20);
        expect(f.ride?.rideId, RideId.pinball);
        expect(run.state.ride?.rideId, RideId.pinball);
      },
    );
  });
}
