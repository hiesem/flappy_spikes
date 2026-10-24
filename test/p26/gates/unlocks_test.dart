import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/gates_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/first_meet.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

Set<ElementId> _allElements() => {
  ...registeredElements(),
  ...registeredPickupElements(),
  ElementId.squeeze,
};

List<(SlotPlan, GapPlan)> _course(RunDirector director, {int slots = 60}) {
  final out = <(SlotPlan, GapPlan)>[];
  for (var slot = 0; slot < slots; slot++) {
    final plan = director.nextSlot(DirectorContext.open(711));
    out.add((plan, director.nextGap(DirectorContext.open(711), plan)));
  }
  return out;
}

int _firstSawHoop(int seed) {
  final director = RunDirector(
    seed: seed,
    enabled: GatesConfig.filter(_allElements(), 3),
    met: ElementId.values.toSet(),
  );
  for (final (plan, _) in _course(director)) {
    if (plan.element == ElementId.saw) return plan.index;
  }
  return -1;
}

List<String> _gateUi(FlappySpikesGame game) {
  final out = <String>[];
  for (final component in game.world.descendants()) {
    final name = component.runtimeType.toString();
    if (name != 'CoinPopup' &&
        (name.contains('Popup') ||
            name.contains('Card') ||
            name.contains('Sticker'))) {
      out.add(name);
    }
  }
  return out;
}

void main() {
  test('WP-C1 the silent gate table and first-meet rules', () {
    for (final entry in {
      ElementId.spring: 0,
      ElementId.pair: 0,
      ElementId.egg: 0,
      ElementId.feather: 0,
      ElementId.puzzlePiece: 0,
      ElementId.piggy: 0,
      ElementId.jar: 0,
      ElementId.fever: 0,
      ElementId.luckySpin: 0,
      ElementId.switchRing: 0,
      ElementId.saw: 3,
      ElementId.squeeze: 5,
    }.entries) {
      expect(GatesConfig.gateFor(entry.key), entry.value);
      expect(GatesConfig.keys[entry.key], isNotNull);
    }

    final sawOnly = FirstMeet(const {}, {ElementId.saw});
    expect(sawOnly.dueSlot(30), isNull);
    final bullseyeOnly = FirstMeet(const {}, {ElementId.bullseye});
    expect(bullseyeOnly.dueSlot(6), ElementId.bullseye);
  });

  test('WP-C1 200 seeds × 60 hoops: saw and squeeze follow their curves', () {
    var sawAt3 = false;
    var scheduledSqueeze = false;
    for (var seed = 1; seed <= 200; seed++) {
      for (final games in [0, 1, 2]) {
        expect(
          _course(
            RunDirector(
              seed: seed,
              enabled: GatesConfig.filter(_allElements(), games),
              met: ElementId.values.toSet(),
            ),
          ).any((entry) => entry.$1.element == ElementId.saw),
          isFalse,
          reason: 'seed $seed, games $games',
        );
      }
      sawAt3 |= _firstSawHoop(seed) >= 0;

      final closed = RunDirector(
        seed: seed,
        enabled: GatesConfig.filter(_allElements(), 4),
        met: ElementId.values.toSet(),
      );
      final open = RunDirector(
        seed: seed,
        enabled: GatesConfig.filter(_allElements(), 5),
        met: ElementId.values.toSet(),
      );
      final closedAt = closed.rollSqueezeAt(0, hoop: 0, first: true);
      final openAt = open.rollSqueezeAt(0, hoop: 0, first: true);
      expect(openAt, closedAt, reason: 'seed $seed');
      scheduledSqueeze |=
          openAt >= RunConfig.secondsForHoops(0, 25) &&
          openAt <= RunConfig.secondsForHoops(0, 40);
    }
    expect(sawAt3, isTrue);
    expect(scheduledSqueeze, isTrue);
    for (var games = 0; games < 5; games++) {
      expect(GatesConfig.isOpen(ElementId.squeeze, games), isFalse);
    }
    expect(GatesConfig.isOpen(ElementId.squeeze, 5), isTrue);
  });

  test('WP-C1 gamesPlayed 0 keeps the D1 hoop starts', () {
    final firstTilt = <int>{}, firstMoving = <int>{}, firstSwitch = <int>{};
    for (var seed = 1; seed <= 200; seed++) {
      final director = RunDirector(
        seed: seed,
        enabled: GatesConfig.filter(_allElements(), 0),
        met: ElementId.values.toSet(),
      );
      for (final (plan, _) in _course(director)) {
        if (plan.tiltDeg != 0) firstTilt.add(plan.index);
        if (plan.motion != null) firstMoving.add(plan.index);
        if (plan.element == ElementId.switchRing) firstSwitch.add(plan.index);
      }
    }
    expect(firstTilt.reduce((a, b) => a < b ? a : b), 10);
    expect(firstTilt.every((index) => index >= 10), isTrue);
    expect(firstMoving.reduce((a, b) => a < b ? a : b), 25);
    expect(firstMoving.every((index) => index >= 25), isTrue);
    expect(firstSwitch.reduce((a, b) => a < b ? a : b), 15);
    expect(firstSwitch.every((index) => index >= 15), isTrue);
  });

  test('WP-C1 the squeeze gate is a pure filter (same streams and plans)', () {
    List<(String, GapPlan)> course(int games) {
      final director = RunDirector(
        seed: 987,
        enabled: GatesConfig.filter(_allElements(), games),
        met: ElementId.values.toSet(),
      );
      return [
        for (final (plan, gap) in _course(director, slots: 80))
          (plan.toString(), gap),
      ];
    }

    expect(course(4), course(5));
  });

  for (final games in [4, 5]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {'gamesPlayed': games},
        worldHeight: 711,
        seed: 17,
      ),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'WP-C1 the squeeze trigger is ${games >= 5 ? 'open' : 'closed'} '
      'at gamesPlayed $games',
      setUp: (game, _) async {
        await game.ready();
        game.sound.enabled = false;
        await preloadImages(game);
      },
      verify: (game, _) async {
        game.runDebug
          ..ignoreGates = false
          ..god = true;
        final run = await startRun(game);
        expect(run.setup.ignoreGates, isFalse);
        await flyUntil(game, (r) => r.state.hoopsPassed >= 1);
        run.state.squeeze.nextAt = run.state.runClock + .02;
        final started = await flyUntil(
          game,
          (r) => r.state.squeeze.phase == SqueezePhase.warning,
          maxSeconds: .25,
        );
        expect(started, games >= 5);
        expect(
          run.features.whereType<SqueezeFeature>().single.started,
          games >= 5 ? 1 : 0,
        );
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      prefs: {
        'gamesPlayed': 0,
        'metElements': [
          for (final element in ElementId.values) element.storageId,
        ],
      },
      worldHeight: 711,
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'WP-C1 ignoreGates bypasses saw and squeeze',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      game.runDebug
        ..ignoreGates = true
        ..god = true;
      final run = await startRun(game);
      expect(run.enabled, contains(ElementId.saw));
      await flyUntil(game, (r) => r.state.hoopsPassed >= 1);
      run.state.squeeze.nextAt = run.state.runClock + .02;
      expect(
        await flyUntil(
          game,
          (r) => r.state.squeeze.phase == SqueezePhase.warning,
          maxSeconds: .25,
        ),
        isTrue,
      );
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      prefs: {
        'gamesPlayed': 5,
        'metElements': [
          for (final element in ElementId.values)
            if (element != ElementId.saw) element.storageId,
        ],
      },
      worldHeight: 711,
      seed: 37,
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'WP-C1 first saw and first squeeze mount no gate UI',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      game.runDebug
        ..ignoreGates = false
        ..god = true;
      final run = await startRun(game, force: [ElementId.saw]);
      final saw = await flyToHoop(
        game,
        HoopKindId.saw,
        ElementId.saw,
        maxSeconds: 120,
      );
      expect(saw, isNotNull);
      expect(_gateUi(game), isEmpty);
      await flyUntil(game, (_) => saw!.resolved);
      run.state.squeeze.nextAt = run.state.runClock + .02;
      await flyUntil(
        game,
        (r) => r.state.squeeze.phase == SqueezePhase.warning,
        maxSeconds: 120,
      );
      expect(run.features.whereType<SqueezeFeature>().single.started, 1);
      expect(_gateUi(game), isEmpty);
    },
  );

  for (final (games, height) in [
    (0, 568.0),
    (0, 711.0),
    (10, 568.0),
    (10, 711.0),
  ]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {'gamesPlayed': games},
        worldHeight: height,
        seed: 7,
      ),
      gameSize: Vector2(Config.worldWidth, height),
    ).testGameWidget(
      'WP-C1 gated autopilot at gamesPlayed $games and ${height.round()} pt',
      setUp: (game, _) async {
        await game.ready();
        game.sound.enabled = false;
        await preloadImages(game);
      },
      verify: (game, _) async {
        game.runDebug.ignoreGates = false;
        await startRun(game);
        final flight = await flyRun(game, maxSeconds: 90, untilHoops: 30);
        expect(
          flight.hoops,
          greaterThanOrEqualTo(12),
          reason: flight.trace.join('\n'),
        );
      },
    );
  }
}
