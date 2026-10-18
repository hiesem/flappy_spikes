import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_world.dart';
import 'package:flappy_spikes/run/backdrop/run_backdrop.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'backdrop_harness.dart';

/// 2026-10-19 WP-BG: the run background animates
/// `Config.backgroundSpeedFactor` (2×) faster — the layers' scroll and the
/// ambient clock — while the scene pacing (seam on hoop 40·k) stays, and it
/// carries on seamlessly through every portal ride, pause and revive.
const double _dt = 1 / 60;
const double _k = Config.backgroundSpeedFactor;

/// One rendered backdrop frame: the scroll and clock the painters read.
class _Shot {
  _Shot(this.cam, this.t, this.w, this.drawn, this.ride);
  final double cam, t, w;
  final bool drawn, ride;
}

/// Renders only [b] (the painters fill `painter.ctx`) and returns what they
/// read this frame.
_Shot _shoot(RunBackdrop b) {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  // a stale ctx means nothing was drawn (a themed ride hides the world)
  b.painter.ctx.t = double.nan;
  b.render(canvas);
  rec.endRecording().dispose();
  final ctx = b.painter.ctx;
  return _Shot(ctx.cam, ctx.t, b.worldDistance, !ctx.t.isNaN, b.rideHook != null);
}

void main() {
  test('the knob is 2', () => expect(Config.backgroundSpeedFactor, 2.0));

  test('painter: scroll and clock scale by speed, the pacing does not', () async {
    final p = BackdropPainter();
    final rec = ui.PictureRecorder();
    p.paint(ui.Canvas(rec),
        cam: 30000, t: 7, viewHeight: 568, bg: const ui.Color(0xFFF1F1F1), fg: const ui.Color(0xFF828282), speed: 2);
    rec.endRecording().dispose();
    expect(p.ctx.cam, 60000, reason: 'layers scroll at 2× the world distance');
    expect(p.ctx.t, 14, reason: 'ambient clock at 2×');
    expect(p.ctx.world, 30000, reason: 'scene / seam selection keeps the world distance');
  });

  test('Nest Canopy at speed 2 is exactly the 1× picture at twice the scroll and clock', () async {
    // In the first loop below 6 000 the world is pure Nest Canopy, so the
    // only difference speed makes is the scroll and the clock.
    for (final (w, t) in [(1200.0, 3.0), (2100.0, 5.4)]) {
      final fast = await renderBackdrop(cam: w, t: t, speed: 2);
      final slow = await renderBackdrop(cam: 2 * w, t: 2 * t);
      final base = await renderBackdrop(cam: w, t: t);
      final a = await rgbaOf(fast), b = await rgbaOf(slow), c = await rgbaOf(base);
      expect(diffPixels(a, b, threshold: 0), 0, reason: 'w $w');
      expect(diffPixels(a, c, threshold: 3), greaterThan(1000), reason: 'speed 2 differs from 1×');
      for (final i in [fast, slow, base]) {
        i.dispose();
      }
    }
  });

  FlameTester<FlappySpikesGame> tester({double h = 568}) => FlameTester(
        () => createRunTestGame(
          seed: 5,
          worldHeight: h,
          prefs: const {'firstRunHintSeen': true, 'coins': 1000},
        ),
        gameSize: Vector2(320, h),
      );

  Future<void> boot(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
  }

  tester().testGameWidget(
    'in a run the painters read 2× the world distance and 2× the run clock',
    setUp: (g, _) async => boot(g),
    verify: (g, _) async {
      final run = await startRun(g);
      final b = RunBackdrop.of(g)!;
      final bot = Autopilot(run);
      double? w0, cam0, t0, rc0;
      for (var i = 0; i < 240; i++) {
        if (bot.shouldFlap()) g.onScreenTap();
        g.update(_dt);
        if (i % 10 == 0) await flushAndMount(g);
        final s = _shoot(b);
        expect(s.cam, closeTo(_k * s.w, 1e-6));
        expect(s.t, closeTo(_k * run.state.runClock, 1e-9));
        if (i == 60) (w0, cam0, t0, rc0) = (s.w, s.cam, s.t, run.state.runClock);
        if (i == 239) {
          expect(s.w - w0!, greaterThan(100), reason: 'the run moved');
          expect((s.cam - cam0!) / (s.w - w0), closeTo(2, 1e-6), reason: 'scroll 2×');
          expect((s.t - t0!) / (run.state.runClock - rc0!), closeTo(2, 1e-6), reason: 'clock 2×');
        }
      }
    },
  );

  tester().testGameWidget(
    'pause / resume: frozen, then one frame of motion (no jump, no catch-up)',
    setUp: (g, _) async => boot(g),
    verify: (g, _) async {
      final run = await startRun(g);
      await flyUntil(g, (r) => r.state.runClock > 2);
      final b = RunBackdrop.of(g)!;
      g.update(_dt);
      final a0 = _shoot(b);
      g.update(_dt);
      final a1 = _shoot(b);
      final frame = a1.cam - a0.cam;
      expect(frame, greaterThan(1));
      g.pause();
      for (var i = 0; i < 120; i++) {
        g.update(_dt);
      }
      final p = _shoot(b);
      expect(p.cam, a1.cam, reason: 'frozen on pause');
      expect(p.t, a1.t);
      g.resume();
      await flushAndMount(g);
      g.update(_dt);
      final r1 = _shoot(b);
      expect(r1.cam - p.cam, closeTo(frame, frame * .25 + .1), reason: 'resume frame = one frame');
      expect(r1.t - p.t, closeTo(_k * _dt, 1e-9));
      expect(run.state.ride, isNull);
    },
  );

  tester().testGameWidget(
    'revive: frozen through the offer and phoenix, then one frame of motion',
    setUp: (g, _) async => boot(g),
    verify: (g, _) async {
      final run = await startRun(g);
      await flyUntil(g, (r) => r.state.runClock > 2);
      for (var i = 0; i < 6; i++) {
        run.debugPass(perfect: true);
      }
      final b = RunBackdrop.of(g)!;
      run.state.invulnerable = 0;
      killRun(g);
      await flushAndMount(g);
      expect(g.state, GameState.reviving);
      final d = _shoot(b);
      g.reviveScreen!.tapHeart();
      final shots = <_Shot>[];
      for (var i = 0; i < 900 && g.state == GameState.reviving; i++) {
        g.update(_dt);
        if (i % 10 == 9) await flushAndMount(g);
        shots.add(_shoot(b));
      }
      expect(g.state, GameState.playing);
      for (final s in shots) {
        expect(s.t, d.t, reason: 'clock frozen through the revive');
      }
      final last = shots.last;
      final after = <_Shot>[];
      final bot = Autopilot(run);
      for (var i = 0; i < 30; i++) {
        if (bot.shouldFlap()) g.onScreenTap();
        g.update(_dt);
        after.add(_shoot(b));
      }
      var prev = last;
      for (final s in after) {
        expect((s.t - prev.t), closeTo(_k * _dt, 1e-9));
        expect((s.cam - prev.cam).abs(), lessThan(_k * 10), reason: 'no jump after the revive');
        prev = s;
      }
    },
  );

  // Every portal ride: the visible background never jumps, and the frame
  // control returns on moves by one frame's worth.
  for (final id in RideId.values) {
    tester().testGameWidget(
      '$id: background continuous through the ride and its return',
      setUp: (g, _) async => boot(g),
      verify: (g, _) async {
        final run = await startRun(g, startHoopIndex: 25, ride: id);
        for (var i = 0; i < 3; i++) {
          run.debugPass(perfect: true);
        }
        final f = run.features.whereType<PortalRideFeature>().single;
        final b = RunBackdrop.of(g)!;
        final bot = Autopilot(run);
        final shots = <_Shot>[];
        final camX = <double>[];
        var seen = false;
        var tail = 0.0;
        for (var frame = 0; frame < 60 * 60; frame++) {
          final r = f.ride;
          if (r != null) seen = true;
          if (seen && r == null) {
            tail += _dt;
            if (tail > 2) break;
          }
          if (r == null && bot.shouldFlap()) g.onScreenTap();
          g.update(_dt);
          if (frame % 10 == 0) await flushAndMount(g);
          shots.add(_shoot(b));
          camX.add(run.state.camX);
        }
        expect(seen, isTrue);
        // the clock: 2× run time every frame (it never stops in a ride)
        for (var i = 1; i < shots.length; i++) {
          if (shots[i].drawn && shots[i - 1].drawn) {
            expect(shots[i].t - shots[i - 1].t, closeTo(_k * _dt, 1e-9), reason: 'frame $i');
          }
        }
        // the scroll: between two drawn frames it moves with the camera
        // (≤ 2 × the world rate's bound × the camera step + a little)
        var maxStep = 0.0;
        for (var i = 1; i < shots.length; i++) {
          if (!shots[i].drawn || !shots[i - 1].drawn) continue;
          final step = (shots[i].cam - shots[i - 1].cam).abs();
          final dcam = (camX[i] - camX[i - 1]).abs();
          expect(step, lessThan(_k * (dcam * 1.2 + 12)), reason: 'frame $i of $id');
          if (step > maxStep) maxStep = step;
        }
        // the return frame (hook removed): one frame's worth, like its
        // neighbours
        final ret = shots.indexWhere((s) => !s.ride, shots.indexWhere((s) => s.ride));
        expect(ret, greaterThan(2));
        final before = shots[ret - 1].cam - shots[ret - 2].cam;
        final on = shots[ret].cam - shots[ret - 1].cam;
        final next = shots[ret + 1].cam - shots[ret].cam;
        // ignore: avoid_print
        print('$id return: before $before on $on next $next (max visible step $maxStep)');
        expect(shots[ret].drawn && shots[ret - 1].drawn, isTrue);
        expect(on, greaterThan(0));
        expect((on - before).abs(), lessThan(.25 * before + .5), reason: 'no hitch on the return frame');
        expect((next - on).abs(), lessThan(.25 * on + .5));
      },
    );
  }
}
