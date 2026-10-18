// WP-TRAIL (owner 2026-10-18): every run trail lies along the bird's REAL
// path, like a snake following its tail (vertical climbs, loops, diagonal
// flight), the Rainbow ribbon keeps the shop preview's size relative to the
// bird, and a ride that hides / scales the bird takes the trail with it
// (connected while drawn, shed part fades in place, fresh trail after).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart' show Vector2;
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/config/trail_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/particle_pool.dart';
import 'package:flappy_spikes/run/effects/tier_trail.dart';
import 'package:flappy_spikes/run/items/streak.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const double _dt = 1 / 60;

/// One frame with the autopilot flapping.
void _frame(FlappySpikesGame game, Autopilot bot) {
  if (bot.shouldFlap()) game.onScreenTap();
  game.update(_dt);
}

Autopilot _bot(RunController run) => Autopilot(run);

/// Distance from [p] to the polyline [path].
double _distToPath(Offset p, List<Offset> path) {
  var best = double.infinity;
  for (var i = 0; i + 1 < path.length; i++) {
    final a = path[i], b = path[i + 1];
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = l2 == 0
        ? 0.0
        : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    final q = a + ab * t;
    best = math.min(best, (p - q).distance);
  }
  return best;
}

/// Renders [paint] into a [w] x [h] RGBA buffer.
Future<ByteData> _render(int w, int h, void Function(Canvas) paint) async {
  final rec = PictureRecorder();
  paint(Canvas(rec));
  final img = await rec.endRecording().toImage(w, h);
  final data = (await img.toByteData())!;
  img.dispose();
  return data;
}

/// Painted (alpha > 0) pixel run length of column [x] in [data] (width [w]).
int _columnThickness(ByteData data, int w, int h, int x) {
  var top = -1, bottom = -1;
  for (var y = 0; y < h; y++) {
    if (data.getUint8((y * w + x) * 4 + 3) > 0) {
      if (top < 0) top = y;
      bottom = y;
    }
  }
  return top < 0 ? 0 : bottom - top + 1;
}

int _rowThickness(ByteData data, int w, int y) {
  var left = -1, right = -1;
  for (var x = 0; x < w; x++) {
    if (data.getUint8((y * w + x) * 4 + 3) > 0) {
      if (left < 0) left = x;
      right = x;
    }
  }
  return left < 0 ? 0 : right - left + 1;
}

void main() {
  group('WP-TRAIL path following (TierTrail, no game)', () {
    test('vertical climb: the rainbow lies on the past path, full width '
        'across it (not collapsed / offset vertically)', () async {
      final t = TierTrail(trailId: 'rainbow', random: math.Random(1));
      final pool = ParticlePool(capacity: 8);
      // The bird climbs straight up the screen at 240 pt/s (camera still).
      const x = 160.0;
      final path = <Offset>[];
      var y = 600.0;
      for (var f = 0; f < 60; f++) {
        y -= 240 * _dt;
        path.add(Offset(x, y + TrailConfig.runBack));
        t.update(
          pool,
          _dt,
          Offset(x, y),
          -math.pi / 2,
          active: true,
          tail: Offset(x, y + TrailConfig.runBack),
        );
      }
      final e = t.emitter;
      expect(e.pathLength, greaterThan(40));
      for (var i = 0; i < e.pathLength; i++) {
        final p = e.pathPoint(i);
        expect(p.dx, closeTo(x, 1e-6), reason: 'point $i on the path');
        expect(p.dy, greaterThanOrEqualTo(y + TrailConfig.runBack - 1e-6));
      }
      // Drawn: six stripes side by side across the climb (horizontal width
      // = the ribbon's full width), not stacked into one thin line.
      final data = await _render(320, 700, t.paint);
      final across = _rowThickness(data, 320, (y + 120).round());
      final full = 6 * 2.6 * t.k + .5;
      expect(across, closeTo(full, 2.5), reason: 'ribbon width across');
    });

    test('a circle (loop): ribbon points and Prism / Paint stroke points '
        'lie on the circle', () {
      for (final id in ['rainbow', 'echo', 'prism', 'paint']) {
        final t = TierTrail(trailId: id, random: math.Random(2));
        final pool = ParticlePool(capacity: 8);
        const c = Offset(160, 300), r = 90.0;
        var a = 0.0;
        for (var f = 0; f < 90; f++) {
          a += 3 * _dt; // 270 pt/s around
          final bird = c + Offset(math.cos(a), math.sin(a)) * r;
          final back = a - TrailConfig.runBack / r;
          final tail = c + Offset(math.cos(back), math.sin(back)) * r;
          t.update(
            pool,
            _dt,
            bird,
            a + math.pi / 2,
            active: true,
            tail: tail,
          );
        }
        final e = t.emitter;
        expect(e.pathLength, greaterThan(10), reason: id);
        for (var i = 0; i < e.pathLength; i++) {
          final d = (e.pathPoint(i) - c).distance;
          expect(d, closeTo(r, .01), reason: '$id point $i');
        }
      }
    });

    test('the world moves under a climbing bird (ride camera): galaxy dust '
        'and flame particles stay on the line below the bird', () {
      for (final id in ['galaxy', 'flame', 'supernova', 'bolt']) {
        final t = TierTrail(trailId: id, random: math.Random(3));
        final pool = ParticlePool(capacity: 8);
        // Bird fixed on screen; the camera climbs at 300 pt/s, so the world
        // (and the trail already shed) moves down 5 pt a frame.
        const bird = Offset(150, 300);
        for (var f = 0; f < 60; f++) {
          t.shift(pool, 0, 300 * _dt);
          t.update(
            pool,
            _dt,
            bird,
            -math.pi / 2,
            active: true,
            tail: bird + const Offset(0, TrailConfig.runBack),
          );
        }
        final ps = t.emitter.particlePositions.toList();
        expect(ps.length, greaterThan(2), reason: id);
        var below = 0;
        for (final p in ps) {
          // Across the path: jitter + own drift only (the mock's ±8 art
          // units at k ≈ 2, plus a little drift).
          expect((p.dx - bird.dx).abs(), lessThan(45), reason: '$id $p');
          if (p.dy > bird.dy + 40) below++;
        }
        expect(below / ps.length, greaterThan(.5), reason: '$id stays behind');
      }
    });

    test('shop preview unchanged: the default (shop) mode still drifts '
        'level with vx and offsets stripes straight down', () {
      final e = TrailEmitter('rainbow', random: math.Random(4));
      expect(e.worldLocked, isFalse);
      for (var f = 0; f < 30; f++) {
        e.emit(const Offset(100, 100), _dt, k: 1.9, vx: -150);
      }
      // Points drift left with the scroll, at the head's height.
      expect(e.pathPoint(10).dx, lessThan(e.pathPoint(0).dx - 10));
      expect(e.pathPoint(10).dy, 100);
    });
  });

  group('WP-TRAIL rainbow size matches the shop preview', () {
    test('ribbon thickness / bird scale: run == shop preview', () async {
      // Shop preview: k = the preview bird's scale (1.9), level flight.
      final shop = TrailEmitter('rainbow', random: math.Random(5));
      for (var f = 0; f < 40; f++) {
        shop.emit(const Offset(250, 160), _dt, k: Config.skinShopBirdScale);
      }
      final a = await _render(320, 320, (c) => shop.paint(c, k: 1.9));
      final shopT = _columnThickness(a, 320, 320, 200) / Config.skinShopBirdScale;
      // Run: level flight, the bird at its look scale.
      final run = TierTrail(trailId: 'rainbow', random: math.Random(5));
      final pool = ParticlePool(capacity: 8);
      for (var f = 0; f < 40; f++) {
        run.shift(pool, -200 * _dt, 0);
        run.update(pool, _dt, const Offset(270, 160), 0, active: true);
      }
      final b = await _render(320, 320, run.paint);
      final runT = _columnThickness(b, 320, 320, 200) / Config.lookScale;
      expect(shopT, greaterThan(10));
      expect(runT, closeTo(shopT, shopT * .1));
      // The Afterimage copies are bird-sized too.
      expect(TierTrail(trailId: 'echo').k, Config.lookScale);
    });
  });

  group('WP-TRAIL in a run', () {
    FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(
      () {
        final g = createRunTestGame(worldHeight: 711, seed: 5);
        g.runDebug.god = true;
        return g;
      },
      gameSize: Vector2(320, 711),
    );

    Future<void> setUp(FlappySpikesGame g, _) async {
      await g.ready();
      await preloadImages(g);
    }

    tester().testGameWidget(
      'cannon roller coaster (climb + loop): every rainbow point lies on the '
      'bird\'s real track path',
      setUp: setUp,
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 25, ride: RideId.cannon);
        final streak = run.features.whereType<StreakFeature>().single;
        final trail = streak.trail!..trailId = 'rainbow';
        final f = run.features.whereType<PortalRideFeature>().single;
        final track = <Offset>[];
        var checked = 0;
        final bot = _bot(run);
        for (var i = 0; i < 60 * 60 && checked < 40; i++) {
          run.state.streak = 5;
          _frame(game, bot);
          if (i % 10 == 0) await flushAndMount(game);
          final b = game.runBirdPosition!;
          final s = run.state;
          track.add(Offset(b.x + s.camX, b.y + s.camY));
          final r = f.ride;
          if (r == null || r.phase != RidePhase.ride || r.view.rt < 1.5) {
            continue;
          }
          if (i % 15 != 0) continue;
          final e = trail.emitter;
          expect(e.pathLength, greaterThan(20));
          for (var j = 1; j < e.pathLength; j++) {
            final p = e.pathPoint(j);
            final w = Offset(p.dx + s.camX, p.dy + s.camY);
            expect(
              _distToPath(w, track),
              lessThan(1.5),
              reason: 'frame $i point $j (ride ${r.view.s.round()} pt)',
            );
          }
          checked++;
        }
        expect(checked, greaterThan(10));
      },
    );

    tester().testGameWidget(
      'normal flight: the rainbow lies on the real flap path (full scroll, '
      'not the old 0.7 share)',
      setUp: setUp,
      verify: (game, _) async {
        final run = await startRun(game);
        await flyUntil(game, (r) => r.state.hoopsPassed >= 1);
        final streak = run.features.whereType<StreakFeature>().single;
        final trail = streak.trail!..trailId = 'rainbow';
        final track = <Offset>[];
        await flyUntil(game, (r) {
          r.state.streak = 5;
          final b = game.runBirdPosition!;
          track.add(Offset(b.x + r.state.camX, b.y + r.state.camY));
          return track.length > 150;
        });
        final s = run.state;
        final e = trail.emitter;
        expect(e.pathLength, greaterThan(20));
        for (var j = 1; j < e.pathLength; j++) {
          final p = e.pathPoint(j);
          expect(
            _distToPath(Offset(p.dx + s.camX, p.dy + s.camY), track),
            lessThan(2),
            reason: 'point $j',
          );
        }
      },
    );

    for (final (id, ride) in [
      ('rainbow', RideId.cannon),
      ('galaxy', RideId.volcano),
      ('paint', RideId.space),
    ]) {
      tester().testGameWidget(
        '$id in the ${ride.name} ride: connected (bird scale) while drawn, '
        'fades in place while hidden, fresh from the bird when it is back',
        setUp: setUp,
        verify: (game, _) async {
          final run = await startRun(game, startHoopIndex: 25, ride: ride);
          final streak = run.features.whereType<StreakFeature>().single;
          final trail = streak.trail!..trailId = id;
          final f = run.features.whereType<PortalRideFeature>().single;
          var hiddenFrames = 0, backFrames = 0, rideFrames = 0;
          var wasHidden = false;
          double? hiddenAt;
          Offset? shedPoint;
          var shedStart = 0.0, cam0 = Offset.zero;
          final bot = _bot(run);
          final bird = game.runBird!;
          for (var i = 0; i < 60 * 60; i++) {
            _frame(game, bot);
            if (i % 10 == 0) await flushAndMount(game);
            final r = f.ride;
            if (r == null) {
              if (backFrames > 0) break;
              continue;
            }
            rideFrames++;
            if (rideFrames < 2) continue;
            final shown = bird.presented;
            final scale = bird.drawnScale, opacity = bird.drawnOpacity;
            if (shown) {
              expect(streak.trailActive, isTrue);
              expect(trail.paintScale, closeTo(scale, 1e-9));
              expect(trail.drawAlpha, closeTo(opacity, 1e-9));
            }
            if (!shown) {
              hiddenFrames++;
              expect(streak.trailActive, isFalse);
              if (!wasHidden) {
                hiddenAt = _dt; // the fade starts on the first hidden frame
                if (TrailEmitter.isPathTrail(id)) {
                  shedPoint = trail.emitter.pathPoint(0);
                } else {
                  shedPoint = trail.emitter.particlePositions.first;
                }
                shedStart = trail.drawAlpha;
                cam0 = Offset(run.state.camX, run.state.camY);
              } else {
                hiddenAt = hiddenAt! + _dt;
              }
              wasHidden = true;
              if (TrailEmitter.isPathTrail(id)) {
                // Fades out in place over detachFade.
                final want = math.max(
                  0.0,
                  1 - hiddenAt / TrailConfig.detachFade,
                );
                expect(trail.drawAlpha, closeTo(want, .04), reason: 'fade');
                if (hiddenAt > _dt && trail.emitter.pathLength > 0) {
                  // In place: the shed head moved with the world only.
                  final cam = Offset(run.state.camX, run.state.camY);
                  final now = trail.emitter.pathPoint(0);
                  expect(
                    (now - (shedPoint! - (cam - cam0))).distance,
                    lessThan(1e-6),
                  );
                }
              }
            } else if (wasHidden) {
              backFrames++;
              if (backFrames == 3) {
                // Fresh: everything of the path is near the bird now.
                final b = game.runBirdPosition!;
                expect(trail.drawAlpha, closeTo(1, 1e-9));
                if (TrailEmitter.isPathTrail(id)) {
                  for (var j = 0; j < trail.emitter.pathLength; j++) {
                    expect(
                      (trail.emitter.pathPoint(j) - Offset(b.x, b.y)).distance,
                      lessThan(40),
                      reason: 'fresh point $j',
                    );
                  }
                }
              }
            }
          }
          expect(shedStart, greaterThan(.9));
          expect(hiddenFrames, greaterThan(10));
          expect(backFrames, greaterThan(3));
        },
      );
    }
  });
}
