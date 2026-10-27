import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/physics/hoop_frame.dart';
import 'package:flappy_spikes/run/pickups/comet_star.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

final class _ShowcasePlan extends ShowcasePlan {
  const _ShowcasePlan(this.result);

  final ShowcaseRunPlan? result;

  @override
  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  }) => result;
}

FlappySpikesGame _game({ShowcaseRunPlan? plan}) {
  SharedPreferences.setMockInitialValues({});
  return FlappySpikesGame(
    worldHeight: Config.worldHeight,
    soundEnabled: false,
    showcasePlan: _ShowcasePlan(plan),
  )..runSeed = 35;
}

FlameTester<FlappySpikesGame> _tester({ShowcaseRunPlan? plan}) =>
    FlameTester<FlappySpikesGame>(
      () => _game(plan: plan),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );

Future<void> _prepare(FlappySpikesGame game) async {
  await game.ready();
  await preloadImages(game);
}

Future<Hoop> _forceHoop(
  FlappySpikesGame game,
  RunController run,
  ElementId element,
  HoopKindId kind,
) async {
  run.debugForce(element);
  expect(await flyUntil(game, (_) => firstHoopOf(game, kind) != null), isTrue);
  return firstHoopOf(game, kind)!;
}

Future<CometStar> _forceComet(FlappySpikesGame game, RunController run) async {
  run.debugForce(ElementId.comet);
  final found = await flyUntil(
    game,
    (_) => game.run?.spawner.pickups.whereType<CometStar>().isNotEmpty ?? false,
  );
  expect(found, isTrue);
  return run.spawner.pickups.whereType<CometStar>().single;
}

// Use the real update/physics path across the plane, with enough clearance
// to touch neither rim. The initial placement only sets up the approach.
Future<void> _crossOutsidePortal(FlappySpikesGame game, Hoop portal) async {
  final run = game.run!;
  expect(
    await flyUntil(game, (r) {
      return portal.planeX - r.birdTrackPosition()!.x <= 12;
    }),
    isTrue,
  );
  final frame = portal.frame();
  final offset = frame.opening / 2 + 60;
  final y = frame.centre.y < game.viewHeight / 2
      ? frame.centre.y + offset
      : frame.centre.y - offset;
  game.runBird!.setFlight(y: y, vy: 0);
  expect(frame.toLocal(run.birdTrackPosition()!).x, lessThan(0));
  expect((y - frame.centre.y).abs(), greaterThan(frame.opening / 2 + 7));
  expect(
    await flyUntil(
      game,
      (_) => portal.resolved,
      maxSeconds: 1,
      autopilot: false,
    ),
    isTrue,
  );
  // A grab is queued at the crossing and starts on the next update.
  game.update(1 / 60);
}

Hoop _detachedFeverHoop(RunController run) {
  final source = run.spawner.hoops.first;
  final plan = source.plan.copyWith(
    kind: HoopKindId.fever,
    element: ElementId.fever,
    motion: () => null,
  );
  return Hoop(plan: plan, kind: hoopKindFor(HoopKindId.fever)!);
}

void main() {
  test('portal grabbing sees a forward crossing outside the ring', () {
    final frame = HoopFrame(centre: Vector2(100, 300), opening: 100);
    const outside = 500.0;
    expect(
      RunController.portalPlaneCrossed(
        frame,
        Vector2(99.0, outside),
        Vector2(101.0, outside),
      ),
      isTrue,
    );
    expect(
      RunController.portalPlaneCrossed(
        frame,
        Vector2(101.0, outside),
        Vector2(102.0, outside),
      ),
      isFalse,
    );
  });

  _tester(
    plan: ShowcaseRunPlan(
      highlightId: 'portal',
      step: 0,
      attempt: 1,
      extraStarters: [Powerup.bigHoops, Powerup.shield],
    ),
  ).testGameWidget(
    'a showcase crossing outside the portal ring still starts the ride',
    setUp: (game, _) => _prepare(game),
    verify: (game, _) async {
      final run = await startRun(game);
      final portal = await _forceHoop(
        game,
        run,
        ElementId.portal,
        HoopKindId.portal,
      );
      final feature = run.features.whereType<PortalRideFeature>().single;
      final events = <HighlightStarted>[];
      final passes = <HoopPassed>[];
      run.events.on<HighlightStarted>(events.add);
      run.events.on<HoopPassed>(passes.add);

      await _crossOutsidePortal(game, portal);

      expect(passes.where((e) => identical(e.hoop, portal)), isEmpty);
      expect(feature.ride, isNotNull);
      expect(run.state.ride?.kind, RideKind.portal);
      expect(events.single, isA<HighlightStarted>());
      expect(events.single.id, 'portal');
      // PRD §A / B2: no matching plan slot in this fixture.
      expect(events.single.scripted, isFalse);
      expect(events.single.hoop, portal.plan.index);
    },
  );

  _tester().testGameWidget(
    'outside the showcase a portal beside the bird keeps the miss rule',
    setUp: (game, _) => _prepare(game),
    verify: (game, _) async {
      final run = await startRun(game);
      final portal = await _forceHoop(
        game,
        run,
        ElementId.portal,
        HoopKindId.portal,
      );
      final feature = run.features.whereType<PortalRideFeature>().single;
      final misses = <HoopMissed>[];
      final highlights = <HighlightStarted>[];
      run.events.on<HoopMissed>(misses.add);
      run.events.on<HighlightStarted>(highlights.add);
      await _crossOutsidePortal(game, portal);
      expect(misses.single.hoop, same(portal));
      expect(highlights, isEmpty);
      expect(portal.takenRing, isNull);
      expect(feature.ride, isNull);
      expect(run.state.ride, isNull);
    },
  );

  _tester(
    plan: ShowcaseRunPlan(
      highlightId: 'comet',
      step: 1,
      attempt: 1,
      extraStarters: [Powerup.bigHoops, Powerup.shield],
    ),
  ).testGameWidget(
    'the showcase comet star uses radius 60 and drifts toward the bird',
    setUp: (game, _) => _prepare(game),
    verify: (game, _) async {
      final run = await startRun(game);
      final star = await _forceComet(game, run);
      expect(star.hitRadius, 60);
      final bird = run.birdTrackPosition()!;
      star.position.setFrom(Vector2(bird.x + 200, bird.y + 50));
      final before = star.position.clone();
      star.update(1);
      final move = star.position - before;
      expect(move.length, closeTo(90, .001));
      expect(move.dot(bird - before), greaterThan(0));

      final events = <HighlightStarted>[];
      run.events.on<HighlightStarted>(events.add);
      final feature = run.features.whereType<CometFeature>().single;
      expect(feature.start(), isTrue);
      expect(feature.started, 1);
      expect(events.single.id, 'comet');
      // PRD §A / B2: no matching plan slot in this fixture.
      expect(events.single.scripted, isFalse);
    },
  );

  _tester().testGameWidget(
    'a normal comet star keeps radius 18 and no drift',
    setUp: (game, _) => _prepare(game),
    verify: (game, _) async {
      final run = await startRun(game);
      final star = await _forceComet(game, run);
      expect(star.hitRadius, 18);
      final before = star.position.clone();
      star.update(1);
      expect(star.position, before);

      final events = <HighlightStarted>[];
      run.events.on<HighlightStarted>(events.add);
      final feature = run.features.whereType<CometFeature>().single;
      expect(feature.start(), isTrue);
      expect(events.single.scripted, isFalse);
    },
  );

  _tester(
    plan: ShowcaseRunPlan(
      highlightId: 'fever',
      step: 2,
      attempt: 1,
      extraStarters: [Powerup.bigHoops, Powerup.shield],
    ),
  ).testGameWidget(
    'a rim-touched FEVER still lights in a showcase run',
    setUp: (game, _) => _prepare(game),
    verify: (game, _) async {
      final run = await startRun(game);
      final fever = _detachedFeverHoop(run);
      final events = <RunEvent>[];
      run.events.onAny(events.add);
      fever.touched = true;
      run.debugPassHoop(fever);

      expect(events.whereType<HoopPassed>().single.perfect, isTrue);
      expect(events.whereType<FeverStarted>(), hasLength(1));
      final highlight = events.whereType<HighlightStarted>().single;
      expect(highlight.id, 'fever');
      // PRD §A / B2: no matching plan slot in this fixture.
      expect(highlight.scripted, isFalse);
      expect(highlight.hoop, fever.plan.index);
    },
  );

  _tester().testGameWidget(
    'a rim-touched FEVER stays cold outside the showcase',
    setUp: (game, _) => _prepare(game),
    verify: (game, _) async {
      final run = await startRun(game);
      final fever = _detachedFeverHoop(run);
      final events = <RunEvent>[];
      run.events.onAny(events.add);
      fever.touched = true;
      run.debugPassHoop(fever);

      expect(events.whereType<HoopPassed>().single.perfect, isFalse);
      expect(events.whereType<FeverStarted>(), isEmpty);
      expect(events.whereType<HighlightStarted>(), isEmpty);
    },
  );
}
