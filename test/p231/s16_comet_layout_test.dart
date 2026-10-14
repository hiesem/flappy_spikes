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
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_spawner.dart';
import 'package:flappy_spikes/services/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.3.1 §16 comet hoop layout: the hoops not yet visible at the
/// pickup move into the comet layout (their gap items go), the comet hoops
/// are evenly spaced up to the predicted end − `ride_comet_tail`, and the
/// first hoop after the comet is ≥ the end + `ride_comet_after_gap`, at a
/// normal height.
final Set<ElementId> _all = ElementId.values.toSet();

void _useTuning(Map<String, String> extra) {
  Tuning.instance = Tuning(
    active: TuningValues.resolve({'ui_unlock_best': '0', ...extra}),
  );
  TuningValues.current = Tuning.instance.active;
}

CometFeature _comet(RunController r) =>
    r.features.whereType<CometFeature>().single;

Future<void> _fly(
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

/// Equal steps (± 1 pt) within [gap × 0.75, gap × 1.4], the last at
/// `end − tail` (± 1 pt).
void _expectEven(List<double> st, double from, double end) {
  final gap = RunConfig.cometHoopGap;
  expect(st, isNotEmpty);
  final xs = [from, ...st];
  final step = xs[1] - xs[0];
  expect(step, inInclusiveRange(gap * .75, gap * 1.4));
  for (var i = 1; i < xs.length; i++) {
    expect(xs[i] - xs[i - 1], closeTo(step, 1));
  }
  expect(st.last, closeTo(end - RunConfig.cometTail, 1));
}

/// One comet from start to end, then a few hoops of normal play.
class _Trace {
  late double endAtStart;
  late double endAtEnd;
  late List<double> stations;
  late double anchor;
  int deaths = 0;

  /// The bird's track x at each death.
  final List<double> deathAt = [];
  int saved = 0;
  int hoopsAfter = 0;
}

Future<_Trace> _cometRun(
  FlappySpikesGame game, {
  required int at,
  required bool pair,
}) async {
  final tr = _Trace();
  late RunController run;
  if (pair) {
    run = await startRun(game, startHoopIndex: at);
    await _fly(game, run, () => run.spawner.hoops.length >= 2, maxSeconds: 6);
    run.events.emit(const PickupCollected(ElementId.comet, null));
    await flushAndMount(game);
  } else {
    run = await startRun(game, startHoopIndex: at, force: [ElementId.comet]);
    await _fly(game, run, () => _comet(run).active);
  }
  expect(_comet(run).active, isTrue, reason: 'the comet started');
  run.events
    ..on<RunDied>((e) {
      tr.deaths++;
      tr.deathAt.add(run.state.camX + RunConfig.birdX);
    })
    ..on<MistakeSaved>((_) => tr.saved++);
  final ride = _comet(run).ride!;
  tr.endAtStart = run.director.cometLockedEnd!;
  tr.stations = run.director.cometStations;
  final st = tr.stations;
  tr.anchor = st.length >= 2 ? 2 * st[0] - st[1] : st.first;
  for (var f = 0; f < 60 * 11 && !ride.done; f++) {
    game.update(1 / 60);
    if (f % 10 == 0) await flushAndMount(game);
  }
  expect(ride.done, isTrue);
  tr.endAtEnd = run.state.camX + RunConfig.birdX;
  final passedBefore = run.state.hoopsPassed;
  await _fly(
    game,
    run,
    () => run.ended || run.state.hoopsPassed - passedBefore >= 8,
    maxSeconds: 25,
  );
  tr.hoopsAfter = run.state.hoopsPassed - passedBefore;
  return tr;
}

void main() {
  tearDown(() => _useTuning(const {}));

  group('§16.1 B / C director (pure)', () {
    RunDirector director() {
      final d = RunDirector(
        seed: 3,
        enabled: _all,
        met: _all,
        startHoopIndex: 30,
      );
      final ctx = DirectorContext.open(711);
      for (var i = 0; i < 3; i++) {
        d.nextGap(ctx, d.nextSlot(ctx));
      }
      return d;
    }

    for (final stretch in [2400.0, 2900.0, 3300.0, 3700.0]) {
      test('stretch $stretch: equal steps up to end − tail; the first hoop '
          'after ≥ end + after gap (normal height)', () {
        final d = director();
        const anchor = 1000.0;
        final end = anchor + stretch + RunConfig.cometTail;
        d
          ..onRideStart(RideKind.comet)
          ..onCometStart(
            fromY: 300,
            endTrackX: end,
            viewHeight: 711,
            amplitude: CometConfig.zigzagAmp,
            anchorX: anchor,
          );
        final st = d.cometStations;
        _expectEven(st, anchor, end);
        final ride = DirectorContext.open(
          711,
          rideActive: true,
          ride: RideKind.comet,
        );
        final plans = [for (var i = 0; i <= st.length; i++) d.nextSlot(ride)];
        for (var i = 0; i < st.length; i++) {
          expect(plans[i].trackX, closeTo(st[i], 1e-9));
          expect((plans[i].centreY - 711 / 2).abs(), closeTo(70, 1e-9));
        }
        final after = plans.last;
        expect(
          after.trackX,
          greaterThanOrEqualTo(end + RunConfig.cometAfterGap - 1e-9),
        );
        expect(((after.centreY - 711 / 2).abs() - 70).abs(), greaterThan(1e-6));
      });
    }

    test('updateCometEnd moves only the hoop after the ride', () {
      final d = director();
      d
        ..onRideStart(RideKind.comet)
        ..onCometStart(
          fromY: 300,
          endTrackX: 4000,
          viewHeight: 711,
          amplitude: 70,
          anchorX: 1000,
        );
      final st = List.of(d.cometStations);
      d.updateCometEnd(4100);
      expect(d.cometStations, st, reason: 'locked at the start');
      expect(d.cometAfterMin, 4100 + RunConfig.cometAfterGap);
      final ride = DirectorContext.open(
        711,
        rideActive: true,
        ride: RideKind.comet,
      );
      final plans = [for (var i = 0; i <= st.length; i++) d.nextSlot(ride)];
      expect(plans.last.trackX, greaterThanOrEqualTo(4100 + 310 - 1e-9));
      // The ride ends: the next slot is normal play.
      d.onRideEnd(RideKind.comet);
      expect(d.nextSlot(DirectorContext.open(711)).duringRide, isFalse);
    });

    test(
      '§16.2 remote keys ride_comet_tail / ride_comet_after_gap are used',
      () {
        _useTuning({'ride_comet_tail': '200', 'ride_comet_after_gap': '500'});
        expect(RunConfig.cometTail, 200);
        expect(RunConfig.cometAfterGap, 500);
        final d = director();
        d
          ..onRideStart(RideKind.comet)
          ..onCometStart(
            fromY: 300,
            endTrackX: 4000,
            viewHeight: 711,
            amplitude: 70,
            anchorX: 1000,
          );
        expect(d.cometStations.last, closeTo(3800, 1e-9));
        expect(d.cometAfterMin, 4500);
        _expectEven(d.cometStations, 1000, 4000);
      },
    );

    test('§16.2 defaults: tail 100, after gap 310, target gap 560', () {
      expect(RunConfig.cometTail, 100);
      expect(RunConfig.cometAfterGap, 310);
      expect(RunConfig.cometHoopGap, 560);
    });
  });

  group('§16.4 hoops planned before the pickup', () {
    for (final h in [568.0, 711.0]) {
      for (final seed in [5, 9, 21]) {
        _tester(h, seed: seed).testGameWidget(
          '$h pt seed $seed: the off-screen hoop and the planned-ahead slot '
          'move to the comet spacing and zigzag height; on-screen hoops stay; '
          'their gap items are gone',
          setUp: _setUp,
          verify: (game, _) async {
            final run = await startRun(game, startHoopIndex: 30);
            final sp = run.spawner;
            // Fly until a hoop has spawned beyond the right edge.
            await _fly(
              game,
              run,
              () => sp.hoops.any(
                (x) => !x.resolved && !sp.hoopVisible(x) && x.planeX > 300,
              ),
              maxSeconds: 8,
            );
            final hidden = {
              for (final x in sp.hoops)
                if (!x.resolved && !sp.hoopVisible(x)) x.plan.index,
            };
            expect(hidden, isNotEmpty);
            final shown = {
              for (final x in sp.hoops)
                if (!hidden.contains(x.plan.index))
                  x: (x.planeX, x.plan.centreY),
            };
            final aheadIndex = sp.plannedAhead!.index;
            // P1-05: the last hoop that stays, and the moved hoops' gaps.
            final birdX =
                run.birdTrackPosition()?.x ?? run.state.camX + RunConfig.birdX;
            final anchor = shown.keys
                .where((x) => x.planeX > birdX)
                .map((x) => x.planeX)
                .fold(birdX, (a, b) => a > b ? a : b);
            final firstHidden = sp.hoops
                .where((x) => hidden.contains(x.plan.index))
                .map((x) => x.planeX)
                .reduce((a, b) => a < b ? a : b);
            // A visible pickup in the gap of the first moved hoop.
            final right = run.state.camX + RunConfig.worldWidth;
            final vx = math.min((anchor + firstHidden) / 2, right - 30);
            expect(vx, greaterThan(anchor));
            final visibleInGap = sp.spawnItem(
              GapItemPlan(kind: ElementId.heart, trackX: vx, y: 60),
            )!;
            // A pickup in an unaffected gap (the gap before the last hoop
            // that stays) is kept.
            final kept = sp.spawnItem(
              GapItemPlan(kind: ElementId.heart, trackX: anchor - 20, y: 60),
            )!;
            await flushAndMount(game);
            expect(sp.isVisible(visibleInGap), isTrue);
            final hiddenItems = [
              for (final p in sp.pickups)
                if (!p.collected && !p.escaped && p.position.x > anchor) p,
            ];
            expect(hiddenItems, contains(visibleInGap));
            run.events.emit(const PickupCollected(ElementId.comet, null));
            expect(kept.escaped, isFalse);
            expect(sp.pickups, contains(kept));
            final st = run.director.cometStations;
            expect(st, isNotEmpty);
            final mid = h / 2;
            // Shown hoops stayed where they were.
            for (final e in shown.entries) {
              expect(e.key.isRemoved, isFalse);
              expect(sp.hoops, contains(e.key));
              expect(e.key.planeX, e.value.$1);
              expect(e.key.plan.centreY, e.value.$2);
            }
            // The hidden hoop(s) and the planned-ahead slot took the first
            // stations, in order, at the zigzag height.
            final moved = [
              for (final i in [...hidden.toList()..sort(), aheadIndex])
                i == aheadIndex
                    ? sp.plannedAhead!
                    : sp.hoops.singleWhere((x) => x.plan.index == i).plan,
            ];
            for (var k = 0; k < moved.length; k++) {
              final p = moved[k];
              expect(p.trackX, closeTo(st[k], 1e-6));
              expect((p.centreY - mid).abs(), closeTo(70, 1e-6));
              expect(p.duringRide, isTrue);
              expect(p.kind, HoopKindId.normal);
              expect(p.tiltDeg, 0);
              expect(p.motion, isNull);
              expect(p.attached, isEmpty);
            }
            // Alternating zigzag.
            for (var k = 1; k < moved.length; k++) {
              expect(
                (moved[k].centreY - mid).sign,
                -(moved[k - 1].centreY - mid).sign,
              );
            }
            // Their gap items are gone (never judged), nothing waits.
            for (final p in hiddenItems) {
              expect(p.escaped, isTrue);
              expect(sp.pickups, isNot(contains(p)));
            }
            expect(sp.pendingItems, isEmpty);
            // The anchor is the last hoop that stays.
            final last = shown.keys
                .map((x) => x.planeX)
                .fold(
                  run.state.camX + RunConfig.birdX,
                  (a, b) => a > b ? a : b,
                );
            _expectEven(st, last, run.director.cometLockedEnd!);
            await flushAndMount(game);
            game.update(1 / 60);
            expect(RunSpawner.creationEdge(moved.last), greaterThan(0));
          },
        );
      }
    }
  });

  group(
    '§16.4 after the ride (568 / 711, hoops 10 / 50 / 150, both sources)',
    () {
      for (final h in [568.0, 711.0]) {
        for (final at in [10, 50, 150]) {
          for (final pair in [false, true]) {
            _tester(h, seed: 3 + at).testGameWidget(
              '$h pt, comet at hoop $at (${pair ? 'pair COMET gift' : 'star hoop'}): '
              'even comet hoops, the first hoop after ≥ end + after gap at a '
              'normal height, the bot flies on without a death',
              setUp: _setUp,
              verify: (game, _) async {
                final tr = await _cometRun(game, at: at, pair: pair);
                final run = game.run!;
                _expectEven(tr.stations, tr.anchor, tr.endAtStart);
                expect(tr.stations.length, inInclusiveRange(4, 7));
                final log = run.spawner.slotLog;
                // Every station got a ride hoop there.
                for (final x in tr.stations) {
                  expect(
                    log.where(
                      (p) => p.duringRide && (p.trackX - x).abs() < 1e-6,
                    ),
                    hasLength(1),
                    reason: 'a comet hoop at $x',
                  );
                }
                final after = log.firstWhere(
                  (p) => p.trackX > tr.stations.last + 1e-6,
                );
                expect(
                  after.trackX,
                  greaterThanOrEqualTo(
                    // The prediction at planning time (it drifts ≈ 2 pt).
                    tr.endAtEnd + RunConfig.cometAfterGap - 5,
                  ),
                );
                final mid = h / 2;
                expect(
                  ((after.centreY - mid).abs() - CometConfig.zigzagAmp).abs(),
                  greaterThan(1e-6),
                  reason: 'a normal height',
                );
                // The comet hoops, the first hoop after and the one after it
                // (the recovery) pass without a death or a save; later bot
                // misses (Ring Trains at speed) are not part of this gate.
                final recovery = after.trackX + after.advance + 40;
                expect(
                  tr.deathAt.where((x) => x <= recovery),
                  isEmpty,
                  reason: 'no death in the recovery',
                );
                expect(tr.saved, 0, reason: 'no mistake after the ride');
                expect(
                  tr.hoopsAfter,
                  greaterThanOrEqualTo(tr.deaths == 0 ? 8 : 2),
                );
              },
            );
          }
        }
      }
    },
  );
}
