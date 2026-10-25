import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/pickups/heart_pickup.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/services/ftue_tracker.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

final class MeetSpy extends GameServices {
  final List<(String, Map<String, Object>?)> events = [];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      events.add((name, parameters));
}

FlappySpikesGame makeGame(MeetSpy spy, Set<ElementId> unmet) {
  SharedPreferences.setMockInitialValues({
    'metElements': [
      for (final element in ElementId.values)
        if (!unmet.contains(element)) element.storageId,
    ],
  });
  return FlappySpikesGame(worldHeight: 711, services: spy, soundEnabled: false)
    ..runSeed = 7;
}

void tester(
  MeetSpy spy,
  Set<ElementId> unmet,
  String name,
  Future<void> Function(FlappySpikesGame game) body,
) =>
    FlameTester<FlappySpikesGame>(
      () => makeGame(spy, unmet),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      name,
      setUp: (game, _) async {
        await game.ready();
        game.sound.enabled = false;
        await preloadImages(game);
      },
      verify: (game, _) => body(game),
    );

SlotPlan plan(
  int index, {
  ElementId element = ElementId.normalHoop,
  double tilt = 0,
  MotionSpec? motion,
  bool forced = false,
  double trackX = 1000,
}) => SlotPlan(
  index: index,
  kind: element == ElementId.saw ? HoopKindId.saw : HoopKindId.normal,
  element: element,
  trackX: trackX,
  centreY: 300,
  opening: 100,
  tiltDeg: tilt,
  motion: motion,
  advance: 310,
  forced: forced,
);

Hoop hoopFor(SlotPlan plan) =>
    Hoop(plan: plan, kind: hoopKindFor(plan.kind) ?? hoopKindFor(normal)!);

HoopKindId get normal => HoopKindId.normal;

Map<String, Object> meet(MeetSpy spy) =>
    spy.events.firstWhere((event) => event.$1 == 'first_meet').$2!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sawPositive = MeetSpy();
  tester(sawPositive, {ElementId.saw}, 'a passed first saw survives', (
    game,
  ) async {
    final run = await startRun(game);
    sawPositive.events.clear();
    final hoop = hoopFor(plan(11, element: ElementId.saw, forced: false));
    run.events
      ..emit(HoopSpawned(hoop, hoop.plan))
      ..emit(const ElementSpawned(ElementId.saw))
      ..emit(HoopPassed(hoop));
    run.endRun();

    expect(meet(sawPositive), {
      'element': 'saw',
      'hoop': 11,
      'games': 1,
      'forced': false,
      'survived': true,
    });
  });

  final sawNegative = MeetSpy();
  tester(sawNegative, {ElementId.saw}, 'a first saw death does not survive', (
    game,
  ) async {
    final run = await startRun(game);
    sawNegative.events.clear();
    final hoop = hoopFor(plan(12, element: ElementId.saw, forced: true));
    run.events
      ..emit(HoopSpawned(hoop, hoop.plan))
      ..emit(const ElementSpawned(ElementId.saw));
    run.pipeline.onResolved!(
      Mistake(MistakeCause.saw, hoop: hoop),
      MistakeResolution.end,
    );
    run.endRun();

    expect(meet(sawNegative)['survived'], false);
    expect(meet(sawNegative)['forced'], true);
  });

  final angled = MeetSpy();
  tester(angled, {ElementId.angledRing}, 'angled survival follows its hoop', (
    game,
  ) async {
    final run = await startRun(game);
    angled.events.clear();
    final first = hoopFor(plan(10, tilt: 12));
    final later = hoopFor(plan(21, tilt: 18));
    run.events
      ..emit(HoopSpawned(first, first.plan))
      ..emit(HoopSpawned(later, later.plan))
      ..emit(const ElementSpawned(ElementId.normalHoop))
      ..emit(const ElementSpawned(ElementId.angledRing))
      ..emit(HoopPassed(first))
      ..emit(const ElementSpawned(ElementId.normalHoop))
      ..emit(const ElementSpawned(ElementId.angledRing));
    run.pipeline.onResolved!(
      Mistake(MistakeCause.missedHoop, hoop: later),
      MistakeResolution.end,
    );
    run.endRun();

    expect(
      angled.events.where((event) => event.$1 == 'first_meet'),
      hasLength(1),
    );
    expect(meet(angled)['hoop'], 10);
    expect(meet(angled)['forced'], false);
    expect(meet(angled)['survived'], true);
  });

  final moving = MeetSpy();
  tester(moving, {ElementId.movingRing}, 'moving survival follows its hoop', (
    game,
  ) async {
    final run = await startRun(game);
    moving.events.clear();
    const motion = MotionSpec(
      type: MotionType.rail,
      axisDeg: 20,
      halfTravel: 50,
      speed: 35,
      phase: 0,
    );
    final first = hoopFor(plan(25, motion: motion, forced: true));
    run.events
      ..emit(HoopSpawned(first, first.plan))
      ..emit(const ElementSpawned(ElementId.normalHoop))
      ..emit(const ElementSpawned(ElementId.movingRing));
    run.events.emit(HoopPassed(first));
    run.endRun();

    expect(meet(moving)['hoop'], 25);
    expect(meet(moving)['forced'], true);
    expect(meet(moving)['survived'], true);
  });

  final angledNegative = MeetSpy();
  tester(
    angledNegative,
    {ElementId.angledRing},
    'an angled first encounter death does not survive',
    (game) async {
      final run = await startRun(game);
      angledNegative.events.clear();
      final first = hoopFor(plan(16, tilt: 14));
      run.events
        ..emit(HoopSpawned(first, first.plan))
        ..emit(const ElementSpawned(ElementId.normalHoop))
        ..emit(const ElementSpawned(ElementId.angledRing));
      run.pipeline.onResolved!(
        Mistake(MistakeCause.missedHoop, hoop: first),
        MistakeResolution.end,
      );
      run.endRun();

      expect(
        angledNegative.events.where((event) => event.$1 == 'first_meet'),
        hasLength(1),
      );
      expect(meet(angledNegative)['hoop'], 16);
      expect(meet(angledNegative)['survived'], false);
    },
  );

  final movingNegative = MeetSpy();
  tester(
    movingNegative,
    {ElementId.movingRing},
    'a moving first encounter death does not survive',
    (game) async {
      final run = await startRun(game);
      movingNegative.events.clear();
      const motion = MotionSpec(
        type: MotionType.rail,
        axisDeg: 20,
        halfTravel: 50,
        speed: 35,
        phase: 0,
      );
      final first = hoopFor(plan(26, motion: motion));
      run.events
        ..emit(HoopSpawned(first, first.plan))
        ..emit(const ElementSpawned(ElementId.normalHoop))
        ..emit(const ElementSpawned(ElementId.movingRing));
      run.pipeline.onResolved!(
        Mistake(MistakeCause.missedHoop, hoop: first),
        MistakeResolution.end,
      );
      run.endRun();

      expect(meet(movingNegative)['hoop'], 26);
      expect(meet(movingNegative)['survived'], false);
    },
  );

  final squeezePositive = MeetSpy();
  tester(
    squeezePositive,
    {ElementId.squeeze},
    'a completed first squeeze survives',
    (game) async {
      final run = await startRun(game);
      squeezePositive.events.clear();
      // Drive the production feature: _done advances index before idle.
      final feature = run.features.whereType<SqueezeFeature>().single;
      final sq = run.state.squeeze;
      sq.phase = SqueezePhase.opening;
      run.events
        ..emit(const ElementSpawned(ElementId.squeeze))
        ..emit(const SqueezePhaseChanged(SqueezePhase.opening, 0));
      feature.phaseT = 100;
      feature.update(1 / 60, 1 / 60);
      expect(sq.index, 1);
      expect(sq.phase, SqueezePhase.idle);
      // A later instance's spike death cannot change that completed meet.
      sq.phase = SqueezePhase.hold;
      run.pipeline.onResolved!(
        Mistake(MistakeCause.spikes),
        MistakeResolution.end,
      );
      run.endRun();

      expect(meet(squeezePositive)['survived'], true);
    },
  );

  final squeezeNegative = MeetSpy();
  tester(
    squeezeNegative,
    {ElementId.squeeze},
    'an unfinished first squeeze does not survive',
    (game) async {
      final run = await startRun(game);
      squeezeNegative.events.clear();
      run.events
        ..emit(const ElementSpawned(ElementId.squeeze))
        ..emit(const SqueezePhaseChanged(SqueezePhase.warning, 0));
      run.endRun();

      expect(meet(squeezeNegative)['survived'], false);
    },
  );

  final pickup = MeetSpy();
  tester(pickup, {ElementId.heart}, 'pickup metadata follows its own gap', (
    game,
  ) async {
    final run = await startRun(game);
    pickup.events.clear();
    final host = hoopFor(plan(13, trackX: 1000));
    final item = HeartPickup(
      GapItemPlan(kind: ElementId.heart, trackX: 1150, y: 300),
    );
    run.events
      ..emit(HoopSpawned(host, host.plan))
      ..emit(PickupSpawned(item))
      ..emit(const ElementSpawned(ElementId.heart))
      ..emit(PickupCollected(ElementId.heart, item));
    run.endRun();

    expect(meet(pickup)['hoop'], 13);
    expect(meet(pickup)['forced'], false);
    expect(meet(pickup)['survived'], true);
  });

  final forcedPickup = MeetSpy();
  tester(forcedPickup, {ElementId.heart}, 'forced pickup metadata is forced', (
    game,
  ) async {
    final run = await startRun(game, force: [ElementId.normalHoop]);
    forcedPickup.events.clear();
    run.setup.forced.add(ElementId.heart);
    final host = hoopFor(plan(17));
    final item = HeartPickup(
      GapItemPlan(kind: ElementId.heart, trackX: 1150, y: 300),
    );
    run.events
      ..emit(HoopSpawned(host, host.plan))
      ..emit(PickupSpawned(item))
      ..emit(const ElementSpawned(ElementId.heart))
      ..emit(PickupCollected(ElementId.heart, item));
    run.endRun();

    expect(meet(forcedPickup)['hoop'], 17);
    expect(meet(forcedPickup)['forced'], true);
  });

  for (final clear in [true, false]) {
    final spy = MeetSpy();
    tester(
      spy,
      {ElementId.angledRing},
      'first encounter skips ${clear ? 'portal-cleared' : 'comet-replanned'} hoops',
      (game) async {
        final run = await startRun(game);
        spy.events.clear();
        // Use the same live collection used by RunSpawner._announce. A removed
        // object can remain mounted while its portal-clear fade finishes.
        final live = run.spawner.hoops as List<Hoop>;
        final old = hoopFor(plan(15, tilt: 12, forced: true));
        live.add(old);
        run.events.emit(HoopSpawned(old, old.plan));
        if (clear) {
          run.spawner.clearAhead();
        } else {
          run.spawner.startCometLayout(
            fromY: 300,
            endTrackX: 6000,
            viewHeight: 711,
            amplitude: 80,
          );
          expect(live.contains(old), false);
        }
        final replacement = hoopFor(plan(16, tilt: 18));
        live.add(replacement);
        run.events.emit(HoopSpawned(replacement, replacement.plan));
        replacement.announced = true;
        run.events
          ..emit(const ElementSpawned(ElementId.normalHoop))
          ..emit(const ElementSpawned(ElementId.angledRing))
          ..emit(HoopPassed(replacement));
        run.endRun();
        expect(meet(spy)['hoop'], 16);
        expect(meet(spy)['forced'], false);
        expect(meet(spy)['survived'], true);
      },
    );
  }

  final attachedPickup = MeetSpy();
  tester(
    attachedPickup,
    {ElementId.heart},
    'an attached pickup announced before its hoop uses that slot',
    (game) async {
      final run = await startRun(game);
      attachedPickup.events.clear();
      const itemPlan = GapItemPlan(kind: ElementId.heart, trackX: 900, y: 300);
      final slot = plan(23, trackX: 1000).copyWith(attached: [itemPlan]);
      run.spawner.slotLog.add(slot);
      final item = run.spawner.spawnItem(itemPlan)!;
      item.announced = true;
      run.events
        ..emit(const ElementSpawned(ElementId.heart))
        ..emit(PickupCollected(ElementId.heart, item));
      run.endRun();
      expect(meet(attachedPickup)['hoop'], 23);
      expect(meet(attachedPickup)['survived'], true);
    },
  );

  final clearedPickup = MeetSpy();
  tester(
    clearedPickup,
    {ElementId.heart},
    'portal clear discards an unannounced gap pickup',
    (game) async {
      final run = await startRun(game);
      clearedPickup.events.clear();
      run.spawner.spawnItem(
        const GapItemPlan(kind: ElementId.heart, trackX: 1150, y: 300),
      );
      run.spawner.clearAhead();
      final host = hoopFor(plan(22, trackX: 2000));
      run.events.emit(HoopSpawned(host, host.plan));
      final item = run.spawner.spawnItem(
        const GapItemPlan(kind: ElementId.heart, trackX: 2150, y: 300),
      )!;
      item.announced = true;
      run.events
        ..emit(const ElementSpawned(ElementId.heart))
        ..emit(PickupCollected(ElementId.heart, item));
      run.endRun();
      expect(meet(clearedPickup)['hoop'], 22);
      expect(meet(clearedPickup)['survived'], true);
    },
  );

  final restart = MeetSpy();
  tester(restart, {ElementId.saw}, 'a killed process still sends one meet', (
    game,
  ) async {
    final run = await startRun(game);
    restart.events.clear();
    final hoop = hoopFor(plan(14, element: ElementId.saw));
    run.events
      ..emit(HoopSpawned(hoop, hoop.plan))
      ..emit(const ElementSpawned(ElementId.saw))
      ..emit(HoopPassed(hoop));
    for (var i = 0; i < 4; i++) {
      await Future<void>.value();
    }

    final afterRestart = MeetSpy();
    for (var i = 0; i < 4; i++) {
      await Future<void>.value();
    }
    final restartedStorage = GameStorage();
    await restartedStorage.load();
    await PersistedFtueTracker(
      services: afterRestart,
      storage: restartedStorage,
    ).flushPendingFirstMeets();

    final meets = afterRestart.events
        .where((event) => event.$1 == 'first_meet')
        .toList();
    expect(meets, hasLength(1));
    expect(meets.single.$2, {
      'element': 'saw',
      'hoop': 14,
      'games': 1,
      'forced': false,
      'survived': true,
    });
  });
}
