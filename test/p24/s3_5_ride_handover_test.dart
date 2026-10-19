import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_scene.dart';
import 'package:flappy_spikes/run/backdrop/run_backdrop.dart';
import 'package:flappy_spikes/run/config/handover_config.dart';
import 'package:flappy_spikes/run/config/portal_config.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/rides/portal_handover.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_reveal.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.4 §3.5 / §4 test 11: the run background around all six portal
/// rides. The background follows the ride camera on the ride (shares,
/// `softY`), holds on the exit, rushes with the cannon's flight camera and
/// eases back on the glide; the five themed rides replace the way-back
/// wash with the reveal (complete 1.7 s after the launch, no wash in the
/// glide); every ride catches up, bumps on the landing and hands back with
/// all offsets 0 by the end of the settle; the cannon's tint path is
/// unchanged. Also (WP-R): no hold at a seam and no creeping after a ride.
const double _dt = 1 / 60;

/// The follow's zero of each ride (its hook's camY0).
final Map<PortalRide, double> camY0Of = {};

/// One frame of a ride.
class _Frame {
  _Frame(this.phase, this.tau, this.gt, this.offsets, this.w, this.camX,
      this.camY, this.hidden, this.covers, this.progress);
  final RidePhase phase;
  final double tau, gt, w, camX, camY, progress;
  final List<ui.Offset> offsets;
  final bool hidden, covers;
}

/// Flies a forced [id] ride from hoop [start] and records every frame
/// (rendering each [renderEvery]th so the paint path runs).
Future<(List<_Frame>, PortalRide, RunController)> _fly(
  FlappySpikesGame g,
  RideId id, {
  int start = 25,
  int renderEvery = 3,
  double after = 3,
  void Function(RunController run, double w)? onFrame,
}) async {
  final run = await startRun(g, startHoopIndex: start, ride: id);
  for (var i = 0; i < 3; i++) {
    run.debugPass(perfect: true);
  }
  final f = run.features.whereType<PortalRideFeature>().single;
  final bot = Autopilot(run);
  final frames = <_Frame>[];
  PortalRide? ride;
  var frame = 0;
  var tail = 0.0;
  while (frame++ < 60 * 60) {
    final r = f.ride;
    if (r != null) ride = r;
    if (ride != null && r == null) {
      tail += _dt;
      if (tail > after) break;
    }
    if (r == null && bot.shouldFlap()) g.onScreenTap();
    g.update(_dt);
    if (frame % 10 == 0) await flushAndMount(g);
    final b = RunBackdrop.of(g)!;
    onFrame?.call(run, b.worldDistance);
    final cur = f.ride;
    final h = cur?.handover;
    if (cur != null && h != null) camY0Of[cur] = h.camY0;
    if (cur != null && frame % renderEvery == 0) {
      final rec = ui.PictureRecorder();
      g.render(ui.Canvas(rec));
      rec.endRecording().dispose();
    }
    frames.add(_Frame(
      cur?.phase ?? RidePhase.done,
      h?.tau ?? 99,
      cur?.view.gt ?? 0,
      [for (final band in Band.layers) b.rideHook?.bandOffset(band) ?? ui.Offset.zero],
      b.worldDistance,
      run.state.camX,
      run.state.camY,
      b.rideHook?.hidden ?? false,
      h != null && h.cover(ui.Path(), g.viewHeight),
      h?.progress ?? 1,
    ));
  }
  expect(ride, isNotNull, reason: 'the $id ride started');
  return (frames, ride!, run);
}

/// The frames after the ride (control back).
List<_Frame> _afterRide(List<_Frame> frames) {
  final last = frames.lastIndexWhere((f) => f.phase != RidePhase.done);
  return frames.sublist(last + 1);
}

void main() {
  const settleEnd = PortalConfig.glideTime + PortalConfig.settleTime;
  const flyEnd = PortalConfig.flyTime - PortalConfig.flyEndEarly;

  FlameTester<FlappySpikesGame> tester({double h = 568, bool met = false}) => FlameTester(
        () => createRunTestGame(
          seed: 5,
          worldHeight: h,
          prefs: {
            'firstRunHintSeen': true,
            if (met) 'metElements': [for (final e in ElementId.values) e.storageId],
          },
        ),
        gameSize: Vector2(320, h),
      );

  test('the reveal: smooth(τ/1.7) leaves, layers arrive by lag + 1.9 s', () {
    expect(RideReveal.progress(-1), 0);
    expect(RideReveal.progress(0), 0);
    expect(RideReveal.progress(.85), closeTo(.5, 1e-9));
    expect(RideReveal.progress(1.69), lessThan(1));
    expect(RideReveal.progress(1.7), 1);
    expect(RideReveal.arrived, closeTo(2.3, 1e-9));
    for (var b = 0; b < 4; b++) {
      final lag = HandoverConfig.arriveLag[b];
      expect(RideReveal.remaining(b, lag), 1);
      expect(RideReveal.remaining(b, lag + 1.9), 0);
    }
    expect(RideReveal.of(RideId.cannon), isNull);
    for (final id in RideId.values.where((i) => i != RideId.cannon)) {
      expect(RideReveal.of(id), isNotNull);
    }
    // softY caps: 720 up, 100 down
    expect(PortalHandover.softY(-1e6), closeTo(-720, 1e-6));
    expect(PortalHandover.softY(1e6), closeTo(100, 1e-6));
    expect(PortalHandover.softY(0), 0);
  });

  for (final h in [568.0, 730.0]) {
    for (final id in RideId.values) {
      if (h == 730 && id != RideId.cannon && id != RideId.volcano) continue;
      final themed = id != RideId.cannon;
      tester(h: h).testGameWidget(
        '§3.5 $id @${h.round()}: follow, launch, ${themed ? 'reveal' : 'tint'}, catch-up, bump, offsets 0 by the settle end',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
        },
        verify: (g, _) async {
          final (frames, ride, _) = await _fly(g, id);
          final inRide = frames.where((f) => f.phase != RidePhase.done).toList();
          expect(inRide, isNotEmpty);

          // On the ride: each layer follows the camera's height by its share
          // (softY-capped); when the themed scene covers, nothing is drawn.
          final camY0 = camY0Of[ride]!;
          for (final f in inRide.where((f) => f.phase == RidePhase.ride)) {
            final cy = PortalHandover.softY(f.camY - camY0);
            for (var b = 0; b < 4; b++) {
              expect(f.offsets[b].dy, closeTo(-cy * HandoverConfig.share[b], 1e-6));
              expect(f.offsets[b].dx, 0);
            }
          }
          // On the exit: the world holds still.
          final exit = inRide.where((f) => f.phase == RidePhase.exit).toList();
          expect(exit, isNotEmpty);
          for (final f in exit) {
            expect(f.w, exit.first.w);
            expect(f.offsets, exit.first.offsets);
            expect(f.hidden, themed);
          }

          // The launch: the world rushes forward with the flight camera.
          final fly = inRide.where((f) => f.phase == RidePhase.fly).toList();
          expect(fly.length, greaterThan(60));
          expect(fly.last.w - fly[1].w, greaterThan(.9 * PortalHandover.rate * (fly.last.camX - fly[1].camX)));

          if (themed) {
            final rv = RideReveal.of(id)!;
            for (final f in fly) {
              expect(f.progress, closeTo(RideReveal.progress(f.tau), 1e-9));
              expect(f.progress, lessThan(1));
              if (f.tau > 0) expect(f.covers, isTrue, reason: 'the scene still covers part of the screen');
              for (var b = 0; b < 4; b++) {
                final d = rv.distance[b] * RideReveal.remaining(b, f.tau);
                expect(f.offsets[b].dx, closeTo(rv.dirX * d, 1e-6));
                expect(f.offsets[b].dy, closeTo(rv.dirY * d, 1e-6));
              }
            }
            // the reveal is complete 1.7 s after the launch
            final done = inRide.where((f) => f.tau >= HandoverConfig.sceneLeave);
            expect(done, isNotEmpty);
            for (final f in done) {
              expect(f.progress, 1);
              expect(f.covers, isFalse);
            }
            // every layer has arrived by 2.3 s (before the landing)
            for (final f in inRide.where((f) => f.tau >= 2.3 && f.gt < PortalConfig.glideTime)) {
              expect(f.offsets, everyElement(ui.Offset.zero));
            }
            // no wash in the glide
            expect(ride.washInGlide, isFalse);
          } else {
            // the cannon: the world sinks as the flight camera rises, the
            // tint path is unchanged (wash in the glide), no reveal
            for (final f in fly) {
              final cy = PortalHandover.softY(f.camY - camY0);
              expect(f.offsets[Band.near.index].dy, closeTo(-cy * .5, 1e-6));
              expect(f.covers, isFalse);
              expect(f.hidden, isFalse);
            }
            expect(ride.washInGlide, isTrue);
            expect(ride.handover, isNull, reason: 'removed at the end');
          }

          // The glide: the catch-up (faster than the camera at first).
          final glide = inRide.where((f) => f.phase == RidePhase.glide).toList();
          expect(glide.length, greaterThan(150));
          final g0 = glide[1], g1 = glide[31];
          final cam = g1.camX - g0.camX, world = g1.w - g0.w;
          expect(world, greaterThan(1.5 * PortalHandover.rate * cam), reason: 'catching up');
          // ...and the landing bump on pu_land (≈ 3 pt on the ground).
          final bump = glide.where((f) => f.gt >= PortalConfig.glideTime).map((f) => f.offsets[Band.near.index].dy.abs());
          expect(bump.reduce((a, b) => a > b ? a : b), inInclusiveRange(1.5, 3.2));
          final sky = glide.where((f) => f.gt >= PortalConfig.glideTime).map((f) => f.offsets[Band.sky.index].dy.abs());
          expect(sky.reduce((a, b) => a > b ? a : b), lessThan(1));

          // Offsets are 0 by the end of the settle; the hook is gone.
          final last = glide.last;
          expect(last.gt, greaterThan(settleEnd - 2 * _dt));
          for (final o in last.offsets) {
            expect(o.distance, lessThan(.1));
          }
          final back = _afterRide(frames);
          expect(back, isNotEmpty);
          for (final f in back) {
            expect(f.offsets, everyElement(ui.Offset.zero));
          }
          expect(RunBackdrop.of(g)!.rideHook, isNull);

          // Control back: normal parallax, no hold, no creeping.
          final a = back[5], z = back[back.length - 1];
          expect((z.w - a.w) / (z.camX - a.camX), greaterThan(HandoverConfig.afterRideMinRate - 1e-6));
          for (var i = 1; i < back.length; i++) {
            if (back[i].camX > back[i - 1].camX + .5) {
              expect(back[i].w, greaterThan(back[i - 1].w), reason: 'never holds while the camera moves');
            }
          }
          expect(flyEnd, closeTo(1.65, 1e-9));
        },
      );
    }
  }

  // WP-W1 behaviour fixed by WP-R: a ride near a seam whose hoop is not
  // planned yet no longer holds the world still and then creeps.
  for (final id in [RideId.sea, RideId.cannon, RideId.space]) {
    tester(met: true).testGameWidget(
      '§3.5 $id near seam 1: no hold under the launch, no creep after; '
      '${id == RideId.cannon ? 'seam within a few hoops of 20' : 'seam on hoop 20'}',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        g.runDebug.god = true;
        double? atPlane;
        final (frames, _, _) = await _fly(g, id, start: 14, after: 12, onFrame: (r, w) {
          for (final hp in r.spawner.hoops) {
            if (hp.plan.index == kHoopsPerScene && hp.plan.kind != HoopKindId.rideRing) {
              if (atPlane == null && r.state.camX + kANCH >= hp.plan.trackX) atPlane = w;
            }
          }
        });
        final fly = frames.where((f) => f.phase == RidePhase.fly).toList();
        for (var i = 2; i < fly.length; i++) {
          expect(fly[i].w, greaterThan(fly[i - 1].w), reason: 'rushes forward at the launch');
        }
        final back = _afterRide(frames);
        for (var i = 1; i < back.length; i++) {
          final dc = back[i].camX - back[i - 1].camX;
          // (the frame that lands the seam stops exactly on it)
          final landing = (back[i].w / kE).floor() != (back[i - 1].w / kE).floor();
          if (dc > .5 && !landing) {
            expect((back[i].w - back[i - 1].w) / dc, greaterThan(HandoverConfig.afterRideMinRate - .01));
          }
        }
        // where is the world when hoop 20's plane reaches the screen centre?
        expect(atPlane, isNotNull);
        if (id != RideId.cannon) {
          // the themed ride re-synced under its scene: seam 1 lands on 20
          expect((atPlane! - kE).abs(), lessThan(6), reason: 'w $atPlane');
        } else {
          // the cannon's world is seen all along: it re-syncs at ≥ 0.6×
          // after the ride, so a seam right after it comes a little early
          expect(atPlane! - kE, inInclusiveRange(0, 6 * kPerHoop), reason: 'w $atPlane');
        }
      },
    );
  }
}
