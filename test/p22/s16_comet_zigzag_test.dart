import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/comet_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/rides/comet_ride.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/services/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §16 comet ride: zigzag hoops (±70 pt around the middle,
/// alternating, the first opposite the star hoop, only hoops reached during
/// the ride), the ease-in-out curve from hoop centre to hoop centre and the
/// tilt along the flight direction (max ±35°).
final Set<ElementId> _all = ElementId.values.toSet();

CometFeature _comet(RunController r) =>
    r.features.whereType<CometFeature>().single;

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

FlameTester<FlappySpikesGame> _tester(double h, {int seed = 5}) =>
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: seed),
      gameSize: Vector2(320, h),
    );

Future<void> _setUp(FlappySpikesGame game, _) async {
  await game.ready();
  await preloadImages(game);
}

/// What the whole boost did.
class _BoostTrace {
  late double starY;
  late double endX;
  late int firstZigIndex;
  final Map<int, double> heldCentres = {};
  final List<double> crossErr = [];
  final List<double> crossSlope = [];
  final List<double> tilts = [];
  final List<(double, double)> midTilts = [];
  final List<double> startSteps = [];
  double endJump = 0;
  final List<double> zigY = [];
  bool afterRideNormal = false;
}

Future<_BoostTrace> _boost(FlappySpikesGame game, {bool pair = false}) async {
  final tr = _BoostTrace();
  late RunController run;
  if (pair) {
    run = await startRun(game, startHoopIndex: 12);
    await _flyUntil(
      game,
      run,
      () => run.spawner.hoops.length >= 2,
      maxSeconds: 6,
    );
    tr.starY = game.runBirdPosition!.y;
    run.events.emit(const PickupCollected(ElementId.comet, null));
  } else {
    run = await startRun(
      game,
      startHoopIndex: ElementId.comet.firstPossible!,
      force: [ElementId.comet],
    );
    await _flyUntil(game, run, () => _comet(run).active);
    expect(_comet(run).active, isTrue, reason: 'the bot collects the star');
    tr.starY = run.spawner.slotLog.lastWhere((p) => p.cometHang).centreY;
  }
  final ride = _comet(run).ride!;
  tr.endX = run.director.cometEndTrackX!;
  // PRD-2.3.1 §16.1 A: the hoops not yet visible at the pickup moved into
  // the comet layout; from then on every spawned / planned hoop keeps its
  // height.
  for (final h in run.spawner.hoops) {
    tr.heldCentres[h.plan.index] = h.plan.centreY;
  }
  final ahead = run.spawner.plannedAhead;
  if (ahead != null) tr.heldCentres[ahead.index] = ahead.centreY;
  tr.firstZigIndex = run.spawner.slotLog
      .firstWhere(
        (p) => p.duringRide,
        orElse: () => run.spawner.slotLog.last,
      )
      .index;
  var prevY = ride.y;
  var prevBx = run.state.camX + RunConfig.birdX;
  for (var f = 0; f < 60 * 11 && !ride.done; f++) {
    final targets = {
      for (final h in run.spawner.hoops)
        if (!h.resolved) h: h.plan.centreY,
    };
    game.update(1 / 60);
    if (f % 10 == 0) await flushAndMount(game);
    if (ride.done) {
      tr.endJump = (game.runBirdPosition!.y - prevY).abs();
      break;
    }
    final bx = run.state.camX + RunConfig.birdX;
    if (f < 6) tr.startSteps.add((ride.y - prevY).abs());
    tr.tilts.add(ride.tilt);
    for (final e in targets.entries) {
      final h = e.key;
      if (prevBx < h.planeX && bx >= h.planeX && h.plan.duringRide) {
        // The frame that reached the plane: on the centre, level.
        tr.crossErr.add(
          (_yAtPlane(prevY, ride.y, prevBx, bx, h.planeX) - e.value).abs(),
        );
        tr.crossSlope.add(ride.slope.abs());
      }
    }
    // Mid-curve: the tilt matches the flight direction.
    final tgt = ride.nextPlaneAhead();
    if (tgt != null && ride.slope.abs() > .2) {
      tr.midTilts.add((ride.tilt, ride.flightAngle));
    }
    prevY = ride.y;
    prevBx = bx;
  }
  final mid = run.state.viewHeight / 2;
  for (final p in run.spawner.slotLog.where(
    (p) => p.index >= tr.firstZigIndex && p.duringRide,
  )) {
    if (p.trackX <= tr.endX) {
      tr.zigY.add(p.centreY - mid);
    } else {
      tr.afterRideNormal =
          ((p.centreY - mid).abs() - CometConfig.zigzagAmp).abs() > 1e-6;
    }
  }
  // Held hoops: the spawned plan of each index keeps its centre.
  for (final p in run.spawner.slotLog) {
    final held = tr.heldCentres[p.index];
    if (held != null && p.index >= tr.firstZigIndex - 1) {
      expect(p.centreY, closeTo(held, 3), reason: 'slot ${p.index} kept');
    }
  }
  return tr;
}

/// The comet's y where the frame's motion crossed the plane [px].
double _yAtPlane(double y0, double y1, double x0, double x1, double px) {
  if (x1 == x0) return y1;
  return y0 + (y1 - y0) * ((px - x0) / (x1 - x0)).clamp(0.0, 1.0);
}

void _expectZigzag(_BoostTrace tr) {
  expect(tr.zigY.length, greaterThanOrEqualTo(4));
  for (var i = 0; i < tr.zigY.length; i++) {
    expect(tr.zigY[i].abs(), closeTo(CometConfig.zigzagAmp, 1e-6));
    if (i > 0) expect(tr.zigY[i].sign, -tr.zigY[i - 1].sign);
  }
}

void main() {
  void useTuning(Map<String, String> extra) {
    Tuning.instance = Tuning(
      active: TuningValues.resolve({'ui_unlock_best': '0', ...extra}),
    );
    TuningValues.current = Tuning.instance.active;
  }

  group('2.3.0 (19) comet hoop gap (PRD-2.3.1 §16: the target spacing)', () {
    tearDown(() => useTuning(const {}));
    test('default 560: ride hoops evenly ≈ 560 pt apart up to end − tail; '
        'the first hoop after the ride ≥ end + after gap', () {
      expect(RunConfig.cometHoopGap, 560);
      final d = RunDirector(
        seed: 7,
        enabled: _all,
        met: _all,
        startHoopIndex: 20,
      );
      final ctx = DirectorContext.open(711);
      for (var i = 0; i < 3; i++) {
        d.nextGap(ctx, d.nextSlot(ctx));
      }
      final end = d.nextTrackX + 2799;
      d
        ..onRideStart(RideKind.comet)
        ..onCometStart(
          fromY: 300,
          endTrackX: end,
          viewHeight: 711,
          amplitude: CometConfig.zigzagAmp,
        );
      final ride = DirectorContext.open(
        711,
        rideActive: true,
        ride: RideKind.comet,
      );
      final k = d.cometStations.length;
      expect(k, 5);
      final plans = [for (var i = 0; i <= k; i++) d.nextSlot(ride)];
      final step = plans[1].trackX - plans[0].trackX;
      expect(step, inInclusiveRange(560 * .75, 560 * 1.4));
      for (var i = 0; i < k - 1; i++) {
        expect(plans[i + 1].trackX - plans[i].trackX, closeTo(step, 1e-6));
      }
      expect(plans[k - 1].trackX, closeTo(end - RunConfig.cometTail, 1e-6));
      expect(
        plans[k].trackX,
        greaterThanOrEqualTo(end + RunConfig.cometAfterGap - 1e-6),
      );
    });
  });

  group('§16.4 director (pure)', () {
    // The zigzag rules at the normal spacing (pinned; the 2.3.0 (19) comet
    // gap is tested above).
    setUp(() => useTuning({'ride_comet_hoop_gap': '310'}));
    tearDown(() => useTuning(const {}));
    for (final h in [524.0, 568.0, 711.0]) {
      for (final starAbove in [true, false]) {
        test('§16.1 at $h pt (star ${starAbove ? 'above' : 'below'} the '
            'middle): ride hoops alternate ±70 around viewHeight / 2, the '
            'first opposite the star; a hoop reached after the ride is '
            'normal', () {
          final d = RunDirector(
            seed: 7,
            enabled: _all,
            met: _all,
            startHoopIndex: 20,
          );
          final ctx = DirectorContext.open(h);
          for (var i = 0; i < 3; i++) {
            final s = d.nextSlot(ctx);
            d.nextGap(ctx, s);
          }
          final mid = h / 2;
          final starY = starAbove ? mid - 60 : mid + 60;
          d
            ..onRideStart(RideKind.comet)
            ..onCometStart(
              fromY: starY,
              endTrackX: d.nextTrackX + 4 * d.spacing + 1,
              viewHeight: h,
              amplitude: CometConfig.zigzagAmp,
            );
          final ride = DirectorContext.open(
            h,
            rideActive: true,
            ride: RideKind.comet,
          );
          final plans = [for (var i = 0; i < 7; i++) d.nextSlot(ride)];
          final zig = plans.take(5).map((p) => p.centreY - mid).toList();
          expect(zig.first, starAbove ? 70 : -70);
          for (var i = 0; i < zig.length; i++) {
            expect(zig[i].abs(), closeTo(70, 1e-9));
            if (i > 0) expect(zig[i], -zig[i - 1]);
          }
          for (final p in plans) {
            expect(p.duringRide, isTrue);
            expect(p.opening, RunConfig.opening0);
            expect(p.tiltDeg, 0);
            expect(p.motion, isNull);
            // Far inside the band (items keep their edge margin).
            expect(
              p.centreY - p.opening / 2,
              greaterThan(RunConfig.stripHeight + RunConfig.itemEdgeMargin),
            );
            expect(
              p.centreY + p.opening / 2,
              lessThan(h - RunConfig.stripHeight - RunConfig.itemEdgeMargin),
            );
          }
          // After the predicted end: the normal layout again.
          for (final p in plans.skip(5)) {
            expect(((p.centreY - mid).abs() - 70).abs(), greaterThan(1e-6));
          }
          d.onRideEnd(RideKind.comet);
          expect(d.cometEndTrackX, isNull);
          final after = d.nextSlot(ctx);
          expect(after.duringRide, isFalse);
        });
      }
    }

    test('§16.2 the end prediction is refreshed while the ride flies', () {
      final d = RunDirector(seed: 1, enabled: _all, met: _all);
      d.updateCometEnd(500);
      expect(d.cometEndTrackX, isNull);
      d
        ..onRideStart(RideKind.comet)
        ..onCometStart(
          fromY: 100,
          endTrackX: 900,
          viewHeight: 568,
          amplitude: 70,
        )
        ..updateCometEnd(950);
      expect(d.cometEndTrackX, 950);
    });

    test('§16.1 config: ±70 pt, tilt max 35°', () {
      expect(CometConfig.zigzagAmp, 70);
      expect(CometConfig.maxTiltDeg, 35);
    });
  });

  group('§16.4 comet ride in a run', () {
    for (final h in [568.0, 711.0]) {
      _tester(h).testGameWidget(
        '§16 at $h pt: zigzag hoops, held hoops, the curve through every '
        'centre (level), tilt ≤ 35° along the flight direction, no jumps',
        setUp: _setUp,
        verify: (game, _) async {
          final tr = await _boost(game);
          _expectZigzag(tr);
          final mid = game.run!.state.viewHeight / 2;
          expect(tr.zigY.first.sign, tr.starY < mid ? 1 : -1);
          expect(tr.crossErr, isNotEmpty);
          for (final e in tr.crossErr) {
            expect(e, lessThanOrEqualTo(1));
          }
          for (final s in tr.crossSlope) {
            // ≈ level: the slope at the plane is tiny.
            expect(s, lessThan(.05));
          }
          for (final t in tr.tilts) {
            expect(t.abs(), lessThanOrEqualTo(35 * math.pi / 180 + 1e-9));
          }
          expect(tr.midTilts, isNotEmpty);
          const cap = 35 * math.pi / 180;
          for (final (tilt, dir) in tr.midTilts) {
            expect(tilt, closeTo(dir.clamp(-cap, cap), 4 * math.pi / 180));
          }
          for (final s in tr.startSteps) {
            expect(s, lessThan(6));
          }
          expect(tr.endJump, lessThan(8));
        },
      );
    }

    _tester(711).testGameWidget(
      '§16.1 the pair COMET gift zigzags the same way (opposite the bird)',
      setUp: _setUp,
      verify: (game, _) async {
        final tr = await _boost(game, pair: true);
        _expectZigzag(tr);
        final mid = game.run!.state.viewHeight / 2;
        expect(tr.zigY.first.sign, tr.starY < mid ? 1 : -1);
      },
    );
  });

  test('§16.2 CometRide.cruiseMultAt integrates to the predicted end', () {
    // 10 s at 1.7 × with the eases: ≈ 16.6 cruise-seconds of track.
    var sum = 0.0;
    for (var t = 0.0; t < 10; t += 1 / 600) {
      sum += CometRide.cruiseMultAt(t) / 600;
    }
    expect(sum, closeTo(10 * 1.7 - .45 * .7 / 2 - .9 * .7 / 2, .05));
  });
}
