import 'dart:math';

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/portal_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.4 §2 one hoop size through rides: tests 2, 3 and 5 of PRD-2.4 §4
/// (comet, portal ride, Big Hoops) plus the director's ride-time slots.
///
/// Expected sizes: a hoop takes `openingFor(index)` × the Big Hoops
/// multiplier (hoop 0 stays 118); the portal stays 118 × the multiplier
/// (unchanged from 2.3.1); the five ride rings take `openingFor(portal index)` × the
/// multiplier.

const _mult = RunConfig.bigHoopsMult;

/// The size a planned hoop of [index] must have (Big Hoops on: × 1.5).
double _expected(int index, {required bool bigHoops}) {
  if (index <= 0) return RunConfig.opening0;
  return RunConfig.openingFor(index) * (bigHoops ? _mult : 1);
}

/// Starts a run at hoop [start] with [force] queued. With [bigHoops] the
/// Big Hoops multiplier is 1.5 from the first slot on (it is kept on).
Future<RunController> _start(
  FlappySpikesGame game, {
  required int start,
  required List<ElementId> force,
  RideId? ride,
  bool bigHoops = false,
}) async {
  game.runDebug.god = true;
  final run = await startRun(
    game,
    startHoopIndex: start,
    force: force,
    ride: ride,
    starter: bigHoops ? Powerup.bigHoops : Powerup.none,
  );
  if (bigHoops) run.state.bigHoops = BigHoopsState(duration: 1000, start: 0);
  return run;
}

/// Flies with the autopilot until [done] holds (at most [maxSeconds]).
Future<void> _flyUntil(
  FlappySpikesGame game,
  RunController run,
  bool Function() done, {
  double maxSeconds = 60,
}) async {
  final bot = Autopilot(run);
  for (var f = 0; f < maxSeconds * 60 && !done(); f++) {
    if (bot.shouldFlap()) game.onScreenTap();
    game.update(1 / 60);
    if (f % 10 == 0) await flushAndMount(game);
  }
}

void _cometChecks({required bool bigHoops}) {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§2 comet at hoop 40${bigHoops ? ' with Big Hoops' : ''}: every comet '
    'hoop and the first hoop after it take openingFor(index)'
    '${bigHoops ? ' × 1.5' : ''}; none is 118',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await _start(
        game,
        start: 40,
        force: [ElementId.comet],
        bigHoops: bigHoops,
      );
      final comet = run.features.whereType<CometFeature>().single;
      await _flyUntil(game, run, () => comet.active);
      expect(comet.active, isTrue, reason: 'the bot collects the star');
      await _flyUntil(game, run, () => !comet.active, maxSeconds: 30);
      expect(comet.active, isFalse, reason: 'the comet ended');
      // Every planned slot (the spawner's log holds each one once).
      final during = run.spawner.slotLog.where((p) => p.duringRide).toList();
      expect(during.length, greaterThanOrEqualTo(4));
      for (final p in during) {
        expect(p.kind, HoopKindId.normal, reason: 'comet hoop ${p.index}');
        expect(
          p.opening,
          closeTo(_expected(p.index, bigHoops: bigHoops), 1e-9),
          reason: 'comet hoop ${p.index}',
        );
        if (p.index >= 3) expect(p.opening, isNot(closeTo(118, 1e-6)));
      }
      final last = during.map((p) => p.index).reduce(max);
      // The first hoop after the comet is planned about a gap ahead.
      bool planned() =>
          run.spawner.slotLog.any((p) => !p.duringRide && p.index > last);
      await _flyUntil(game, run, planned, maxSeconds: 10);
      expect(planned(), isTrue, reason: 'a hoop after the comet is planned');
      final plans = run.spawner.slotLog.toList();
      final after = plans.firstWhere((p) => !p.duringRide && p.index > last);
      expect(after.duringRide, isFalse);
      expect(
        after.opening,
        closeTo(_expected(after.index, bigHoops: bigHoops), 1e-9),
        reason: 'the first hoop after the comet (index ${after.index})',
      );
      for (final h in run.spawner.hoops) {
        if (h.plan.kind == HoopKindId.normal) {
          expect(h.opening, closeTo(h.plan.opening, 1e-9));
        }
      }
    },
  );
}

void _portalChecks({required bool bigHoops}) {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§2 portal ride at hoop 40${bigHoops ? ' with Big Hoops' : ''}: the portal '
    'is 118; the ride rings are openingFor(portal index)'
    '${bigHoops ? ' × 1.5' : ''}; hoops planned during the ride take their '
    "index's size",
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await _start(
        game,
        start: 40,
        force: [ElementId.portal],
        ride: RideId.space,
        bigHoops: bigHoops,
      );
      final portal = run.spawner.slotLog.firstWhere(
        (p) => p.kind == HoopKindId.portal,
      );
      expect(
        portal.opening,
        closeTo(RunConfig.portalOpening * (bigHoops ? _mult : 1), 1e-9),
      );
      await _flyUntil(game, run, () => run.state.ride?.kind == RideKind.portal);
      expect(run.state.ride?.kind, RideKind.portal, reason: 'the ride started');
      final ride = run.features.whereType<PortalRideFeature>().single.ride!;
      expect(ride.rings, hasLength(PortalConfig.rideRings));
      for (final r in ride.rings) {
        expect(r.plan.kind, HoopKindId.rideRing);
        expect(r.plan.index, portal.index);
        expect(
          r.opening,
          closeTo(_expected(portal.index, bigHoops: bigHoops), 1e-9),
          reason: 'ride ring',
        );
      }
      await _flyUntil(game, run, () => run.state.ride == null, maxSeconds: 90);
      expect(run.state.ride, isNull, reason: 'the ride ended');
      final during = run.spawner.slotLog.where((p) => p.duringRide).toList();
      expect(during, isNotEmpty);
      for (final p in during) {
        if (p.kind == HoopKindId.rideRing) continue;
        expect(
          p.opening,
          closeTo(_expected(p.index, bigHoops: bigHoops), 1e-9),
          reason: 'hoop ${p.index} (${p.kind.name}) planned during the ride',
        );
      }
      // The rings keep their size after the ride.
      for (final r in ride.rings) {
        expect(
          r.opening,
          closeTo(_expected(portal.index, bigHoops: bigHoops), 1e-9),
        );
      }
    },
  );
}

void main() {
  group('PRD-2.4 §2 director: ride-time slots take the curve size', () {
    test('§2.2 slot order 1: a ride slot is the curve size of its index', () {
      final d = RunDirector(
        seed: 7,
        enabled: ElementId.values.toSet(),
        met: ElementId.values.toSet(),
        startHoopIndex: 40,
      );
      final ctx = DirectorContext.open(
        711,
        rideActive: true,
        ride: RideKind.comet,
      );
      for (var k = 0; k < 6; k++) {
        final s = d.nextSlot(ctx);
        expect(s.duringRide, isTrue);
        expect(s.opening, closeTo(RunConfig.openingFor(s.index), 1e-9));
      }
    });

    test('§2.2 slot order 1 with Big Hoops: × 1.5 (hoop 0 stays 118)', () {
      final d = RunDirector(
        seed: 7,
        enabled: {ElementId.normalHoop},
        met: const {},
        startHoopIndex: 40,
      );
      final s = d.nextSlot(
        DirectorContext.open(
          711,
          rideActive: true,
          ride: RideKind.comet,
          bigHoopsMult: _mult,
        ),
      );
      expect(s.index, 40);
      expect(s.opening, closeTo(RunConfig.openingFor(40) * _mult, 1e-9));
    });

    test('§2.2 a re-plan during a ride (plainSlot, ride) takes the curve size '
        'of its index, also a portal that turns plain', () {
      final d = RunDirector(
        seed: 7,
        enabled: {ElementId.normalHoop, ElementId.portal},
        met: const {},
        startHoopIndex: 40,
        forced: [ElementId.portal],
        forcedRide: RideId.space,
      );
      final portal = d.nextSlot(DirectorContext.open(711));
      expect(portal.kind, HoopKindId.portal);
      expect(portal.opening, closeTo(RunConfig.portalOpening, 1e-9));
      final plain = d.plainSlot(
        portal,
        DirectorContext.open(711, bigHoopsMult: _mult),
        ride: true,
      );
      expect(plain.kind, HoopKindId.normal);
      expect(plain.duringRide, isTrue);
      expect(plain.opening, closeTo(RunConfig.openingFor(40) * _mult, 1e-9));
    });

    test('§2.3 the portal keeps 118 × Big Hoops, unchanged from 2.3.1 (the '
        'rings take the multiplier too)', () {
      final d = RunDirector(
        seed: 7,
        enabled: {ElementId.normalHoop, ElementId.portal},
        met: const {},
        startHoopIndex: 40,
        forced: [ElementId.portal],
        forcedRide: RideId.space,
      );
      final portal = d.nextSlot(DirectorContext.open(711, bigHoopsMult: _mult));
      expect(portal.kind, HoopKindId.portal);
      expect(portal.opening, closeTo(RunConfig.portalOpening * _mult, 1e-9));
    });
  });

  group('PRD-2.4 §2 comets in a run', () {
    _cometChecks(bigHoops: false); // test 2
    _cometChecks(bigHoops: true); // test 5
  });

  group('PRD-2.4 §2 portal rides in a run', () {
    _portalChecks(bigHoops: false); // test 3
    _portalChecks(bigHoops: true); // test 5
  });
}
