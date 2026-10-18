// WP-TRAIL evidence (owner 2026-10-18): every trail in every ride.
//
// Off by default (it flies ~200 rides). Run with
//   WP_TRAIL_SURVEY=<dir> flutter test test/run/effects/trail_ride_survey_test.dart
// It writes <dir>/matrix.tsv (trail x ride: how far the trail lies from the
// bird's real track path, hide / fade / fresh-start checks) and frame
// strips <dir>/strip_<trail>_<ride>.png of the chosen trails.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/streak.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

final String? _out = Platform.environment['WP_TRAIL_SURVEY'];

const List<String> _allTrails = TrailEmitter.ids;

/// Strips: trail -> rides.
const Map<String, List<String>> _strips = {
  'rainbow': ['cannon', 'volcano', 'space', 'comet'],
  'galaxy': ['cannon', 'volcano', 'space'],
  'echo': ['cannon'],
  'bolt': ['cannon'],
  'paint': ['cannon', 'storm'],
  'prism': ['cannon'],
  'supernova': ['pinball'],
  'flame': ['sea'],
};

double _distToTracks(ui.Offset p, List<List<ui.Offset>> tracks) {
  var best = double.infinity;
  for (final t in tracks) {
    best = math.min(best, _distToPath(p, t));
  }
  return best;
}

double _distToPath(ui.Offset p, List<ui.Offset> path) {
  var best = double.infinity;
  for (var i = 0; i + 1 < path.length; i++) {
    final a = path[i], b = path[i + 1];
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = l2 == 0
        ? 0.0
        : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    best = math.min(best, (p - (a + ab * t)).distance);
  }
  return best;
}

double _pct(List<double> v, double q) {
  if (v.isEmpty) return double.nan;
  v.sort();
  return v[((v.length - 1) * q).round()];
}

/// Records the game frame (rasterised later, outside the fake-async zone).
ui.Picture _frame(FlappySpikesGame game) {
  // As the screenshot tests: the canvas at 2x, resized right before.
  const scale = 2.0;
  final w = 320 * scale, h = (game.viewHeight * scale).roundToDouble();
  game.onGameResize(Vector2(w, h));
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(
    ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(c);
  return rec.endRecording();
}

Future<void> _saveStrip(
  List<(String, ui.Picture)> frames,
  String name,
  int w,
  int h,
) async {
  if (frames.isEmpty) return;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  for (var i = 0; i < frames.length; i++) {
    c
      ..save()
      ..translate(i * (w + 4.0), 0)
      ..clipRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()))
      ..drawPicture(frames[i].$2)
      ..restore();
  }
  final img = await rec.endRecording().toImage(
    frames.length * (w + 4) - 4,
    h,
  );
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  File('$_out/strip_$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
  File('$_out/strip_$name.txt').writeAsStringSync(
    '${frames.map((f) => f.$1).join(' | ')}\n',
  );
}

/// The strip moments of a portal ride (label, predicate).
List<(String, bool Function(PortalRide r, bool shown, int hidden))> _moments(String ride) {
  final m = <(String, bool Function(PortalRide, bool, int))>[
    ('ride 1.0s', (r, _, _) => r.phase == RidePhase.ride && r.view.rt >= 1),
  ];
  if (ride == 'cannon') {
    m.addAll([
      ('climb', (r, _, _) => r.phase == RidePhase.ride && r.view.s >= 800),
      ('loop in', (r, _, _) => r.phase == RidePhase.ride && r.view.s >= 1980),
      ('loop top', (r, _, _) => r.phase == RidePhase.ride && r.view.s >= 2230),
      ('loop out', (r, _, _) => r.phase == RidePhase.ride && r.view.s >= 2520),
    ]);
  } else {
    m.addAll([
      ('ride 3s', (r, _, _) => r.phase == RidePhase.ride && r.view.rt >= 3),
      ('ride 5s', (r, _, _) => r.phase == RidePhase.ride && r.view.rt >= 5),
    ]);
  }
  m.addAll([
    ('exit .15', (r, _, _) => r.phase == RidePhase.exit && r.view.et >= .15),
    ('hidden', (r, shown, _) => !shown),
    ('hidden .25s', (r, shown, h) => !shown && h >= 15),
    ('back', (r, shown, _) => shown && r.phase == RidePhase.fly),
    ('fly .5', (r, _, _) => r.phase == RidePhase.fly && r.view.ft >= .5),
    ('glide .4', (r, _, _) => r.phase == RidePhase.glide && r.view.gt >= .4),
  ]);
  return m;
}

void main() {
  final rows = <String>[
    'trail\tride\tframes\thidden\tpath_p50\tpath_p95\tparticle_p50\t'
        'particle_p90\temit_hidden\tfade_ok\tfresh_ok\tmax_particles',
  ];

  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(
    () {
      final g = createRunTestGame(worldHeight: 711, seed: 5);
      g.runDebug.god = true;
      return g;
    },
    gameSize: Vector2(320, 711),
  );

  for (final id in _allTrails) {
    for (final ride in [...RideId.values.map((r) => r.name), 'comet']) {
      tester().testGameWidget(
        'survey $id x $ride',
        skip: _out == null,
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
        },
        verify: (game, tester) async {
          final comet = ride == 'comet';
          final run = comet
              ? await startRun(
                  game,
                  startHoopIndex: ElementId.comet.firstPossible!,
                  force: [ElementId.comet],
                )
              : await startRun(
                  game,
                  startHoopIndex: 25,
                  ride: RideId.values.byName(ride),
                );
          final streak = run.features.whereType<StreakFeature>().single;
          final trail = streak.trail!..trailId = id;
          final f = run.features.whereType<PortalRideFeature>().single;
          final bot = Autopilot(run);
          final bird = game.runBird!;
          final tracks = <List<ui.Offset>>[[]];
          final pathD = <double>[], partD = <double>[];
          var frames = 0, hidden = 0, emitHidden = 0, maxP = 0;
          var fadeOk = true, freshOk = true, wasHidden = false, back = 0;
          final strip = <(String, ui.Picture)>[];
          final moments = comet ? const <(String, bool Function(PortalRide, bool, int))>[] : _moments(ride);
          var next = 0;
          final wantStrip = _strips[id]?.contains(ride) ?? false;
          var cometShots = 0;
          for (var i = 0; i < 60 * 70; i++) {
            if (bot.shouldFlap()) game.onScreenTap();
            final before = trail.emitter.particleCount;
            game.update(1 / 60);
            if (i % 10 == 0) await flushAndMount(game);
            final s = run.state;
            final inRide = comet
                ? s.ride?.kind == RideKind.comet
                : f.ride != null;
            if (!inRide) {
              if (frames > 0) break;
              continue;
            }
            frames++;
            final b = game.runBirdPosition!;
            final shown = bird.presented;
            final glide = f.ride?.phase == RidePhase.glide;
            if (shown) {
              if (wasHidden && back == 0) tracks.add([]);
              final w = ui.Offset(b.x + s.camX, b.y + s.camY);
              final t = tracks.last;
              // Recent path only (the trail lives < 2 s), every >= 2 pt.
              if (t.isEmpty || (t.last - w).distance >= 2) t.add(w);
              if (t.length > 400) t.removeAt(0);
            }
            maxP = math.max(maxP, trail.emitter.particleCount);
            if (!shown) {
              hidden++;
              wasHidden = true;
              // Emission while hidden: more particles than before.
              if (!trail.usesBlocks &&
                  trail.emitter.particleCount > before &&
                  hidden > 1) {
                emitHidden++;
              }
              if (TrailEmitter.isPathTrail(id) && hidden > 20) {
                if (trail.drawAlpha > 0) fadeOk = false;
              }
            } else if (wasHidden && ++back == 3) {
              if (TrailEmitter.isPathTrail(id)) {
                for (var j = 0; j < trail.emitter.pathLength; j++) {
                  if ((trail.emitter.pathPoint(j) - ui.Offset(b.x, b.y))
                          .distance >
                      40) {
                    freshOk = false;
                  }
                }
              }
            }
            // Distances to the real track path (sampled every 6 frames,
            // once there is some path).
            if (shown && !glide && tracks.last.length > 30 && i % 20 == 0) {
              final e = trail.emitter;
              if (trail.usesBlocks) {
                // (the blocks live in the component's pool; skipped)
              } else {
                for (var j = 1; j < e.pathLength; j += 3) {
                  final p = e.pathPoint(j);
                  pathD.add(
                    _distToTracks(
                      ui.Offset(p.dx + s.camX, p.dy + s.camY),
                      tracks,
                    ),
                  );
                }
                var q = 0;
                for (final p in e.particlePositions) {
                  if (q++ % 4 != 0) continue;
                  partD.add(
                    _distToTracks(
                      ui.Offset(p.dx + s.camX, p.dy + s.camY),
                      tracks,
                    ),
                  );
                }
              }
            }
            if (wantStrip) {
              final r = f.ride;
              if (r != null && next < moments.length) {
                if (moments[next].$2(r, shown, hidden)) {
                  strip.add((moments[next].$1, _frame(game)));
                  next++;
                }
              } else if (comet && frames % 50 == 0 && cometShots < 6) {
                cometShots++;
                strip.add(('comet ${frames ~/ 60}s', _frame(game)));
              }
            }
          }
          String n(double v) => v.isNaN ? '-' : v.toStringAsFixed(1);
          rows.add(
            '$id\t$ride\t$frames\t$hidden\t${n(_pct(pathD, .5))}\t'
            '${n(_pct(pathD, .95))}\t${n(_pct(partD, .5))}\t'
            '${n(_pct(partD, .9))}\t$emitHidden\t'
            '${hidden == 0 ? '-' : fadeOk}\t${hidden == 0 ? '-' : freshOk}\t'
            '$maxP',
          );
          if (wantStrip) {
            await tester.runAsync(
              () => _saveStrip(
                strip,
                '${id}_$ride',
                640,
                (game.viewHeight * 2).round(),
              ),
            );
          }
          expect(frames, greaterThan(60));
          expect(emitHidden, 0);
          expect(fadeOk, isTrue);
          expect(freshOk, isTrue);
        },
      );
    }
  }

  tearDownAll(() {
    if (_out == null) return;
    File('$_out/matrix.tsv')
      ..createSync(recursive: true)
      ..writeAsStringSync('${rows.join('\n')}\n');
  });
}
