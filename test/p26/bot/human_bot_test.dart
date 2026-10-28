import 'dart:io';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/debug/human_bot.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  HumanNoiseFlapScheduler schedule({required int seed, int baseFlaps = 1000}) {
    final scheduler = HumanNoiseFlapScheduler(seed: seed);
    var planned = 0;
    for (var frame = 0; planned < baseFlaps; frame++) {
      final now = frame / 60;
      if (frame % 27 == 0) {
        // A known future request lets the scheduler exercise early jitter
        // on a frame clock rather than collapsing it into the planning frame.
        scheduler.planBase(now + 0.3, now: now);
      }
      scheduler.flapDue(now);
      planned = scheduler.plannedFlapTimes.length;
    }
    for (var frame = baseFlaps * 27; scheduler.pendingFlaps > 0; frame++) {
      scheduler.flapDue(frame / 60);
    }
    return scheduler;
  }

  test('the same seed gives the same flap times and extra flaps', () {
    final first = schedule(seed: 42);
    final second = schedule(seed: 42);
    final other = schedule(seed: 43);

    expect(second.flapTimes, first.flapTimes);
    expect(second.extraFlaps, first.extraFlaps);
    expect(other.flapTimes, isNot(first.flapTimes));
  });

  test(
    'emitted base-flap offsets are 90 ms sigma and extra flaps are 10 percent',
    () {
      const flaps = 1000;
      final scheduler = schedule(seed: 7, baseFlaps: flaps);
      final offsets = scheduler.baseFlapOffsets;
      expect(offsets, hasLength(flaps));
      expect(scheduler.flapTimes, hasLength(flaps + scheduler.extraFlaps));
      final mean = offsets.reduce((a, b) => a + b) / flaps;
      final variance =
          offsets
              .map((value) => (value - mean) * (value - mean))
              .reduce((a, b) => a + b) /
          (flaps - 1);
      final sigmaMilliseconds = math.sqrt(variance) * 1000;

      expect(sigmaMilliseconds, closeTo(90, 10));
      expect(mean * 1000, closeTo(0, 10));
      expect(scheduler.extraFlaps / flaps, closeTo(.1, .02));
    },
  );

  test('caller-observed base flaps include early and late 90 ms offsets', () {
    // PRD-2.6 §0.3 item 4: measure the returned actions on a frame clock,
    // independently of the scheduler's diagnostic jitter/offset lists.
    final scheduler = HumanNoiseFlapScheduler(seed: 7, extraFlapChance: 0);
    final emitted = <double>[];
    const count = 1000;
    for (var frame = 0; frame < (count + 1) * 60; frame++) {
      final now = frame / 60;
      if (frame % 60 == 0 && frame < count * 60) {
        scheduler.planBase(now + .4, now: now);
      }
      if (scheduler.flapDue(now)) emitted.add(now);
    }
    expect(emitted, hasLength(count));
    final offsets = List.generate(count, (i) => emitted[i] - (i + .4));
    final mean = offsets.reduce((a, b) => a + b) / count;
    final variance =
        offsets
            .map((offset) => math.pow(offset - mean, 2))
            .reduce((a, b) => a + b) /
        (count - 1);
    expect(offsets.where((offset) => offset < 0).length, greaterThan(400));
    expect(offsets.where((offset) => offset > 0).length, greaterThan(400));
    expect(mean * 1000, closeTo(0, 10));
    expect(math.sqrt(variance) * 1000, closeTo(90, 10));
    expect(scheduler.baseFlapOffsets, orderedEquals(offsets));
    expect(scheduler.flapTimes, orderedEquals(emitted));
  });

  test('early jitter cannot schedule before time zero', () {
    for (var seed = 0; seed < 50; seed++) {
      final scheduler = HumanNoiseFlapScheduler(seed: seed, extraFlapChance: 0);
      scheduler.planBase(0);
      scheduler.flapDue(0);
      expect(scheduler.flapTimes.every((time) => time >= 0), isTrue);
    }
  });

  test('offsets record the polling frame even when a flap is overdue', () {
    final scheduler = HumanNoiseFlapScheduler(
      seed: 7,
      jitterSigma: 0,
      extraFlapChance: 1,
    );
    scheduler.planBase(1, now: 0);
    expect(scheduler.flapDue(.9), isFalse);
    expect(scheduler.flapDue(1.05), isTrue);
    expect(scheduler.baseFlapOffsets.single, closeTo(.05, 1e-9));
    expect(scheduler.flapDue(1.1), isTrue);
    expect(scheduler.baseFlapOffsets, hasLength(1));
    expect(scheduler.extraFlaps, 1);
    expect(scheduler.flapTimes, [1.05, 1.1]);
    expect(scheduler.pendingFlaps, 0);
  });

  // region P26-D-BOT
  for (final height in [568.0, 711.0]) {
    FlameTester(
      () => createRunTestGame(worldHeight: height, prefs: {'gamesPlayed': 10}),
      gameSize: Vector2(Config.worldWidth, height),
    ).testGameWidget(
      'σ 0 / extra 0 reproduces `flyRun` at $height',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        Future<void> reset() async {
          game.replay();
          await flushAndMount(game);
          stepGame(game, .4);
          await flushAndMount(game);
        }

        game.runDebug.ignoreGates = false;
        for (var seed = 0; seed <= 20; seed++) {
          game.runSeed = seed;
          game.storage
            ..gamesPlayed = 10
            ..metElements = {}
            ..lastPortalRide = null
            ..lastFeatherRun = -1
            ..lastPieceRun = -1
            ..feathers = 0
            ..puzzlePieces = 0;
          await startRun(game);
          final ideal = await flyRun(game, maxSeconds: 60);
          await reset();
          // First meets, ride no-repeat and collectible history also affect
          // the course. Restore every course input before the paired replay.
          game.storage
            ..gamesPlayed = 10
            ..metElements = {}
            ..lastPortalRide = null
            ..lastFeatherRun = -1
            ..lastPieceRun = -1
            ..feathers = 0
            ..puzzlePieces = 0;
          await startRun(game);
          final noisy = await flyHumanNoiseBotToDeath(
            game,
            seed: seed,
            maxSeconds: 60,
            jitterSigma: 0,
            extraFlapChance: 0,
          );
          expect(
            noisy.hoops,
            ideal.hoops,
            reason:
                'seed=$seed h=$height ideal=${ideal.cause}/${ideal.seconds} noisy=${noisy.cause}/${noisy.seconds}',
          );
          expect(
            noisy.cause,
            ideal.cause,
            reason:
                'seed=$seed h=$height ideal=${ideal.cause}/${ideal.seconds} noisy=${noisy.cause}/${noisy.seconds}',
          );
          expect(noisy.extraFlaps, 0);
          expect(noisy.baseFlapOffsets, everyElement(0));
          await reset();
        }
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }

  FlameTester(
    () => createRunTestGame(seed: 7),
    gameSize: Vector2(Config.worldWidth, 568),
  ).testGameWidget(
    'closed-loop trace records actual taps and extras follow emitted bases by 80 ms',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      // Every base deliberately doubles here; protect one mistake so this
      // timing fixture observes enough pairs even on the normal course.
      final run = await startRun(game, starter: Powerup.shield);
      final bot = HumanNoiseBot(run, jitterSigma: 0, extraFlapChance: 1);
      final emitted = <double>[];
      final dueExtras = <double>[];
      for (var frame = 0; frame < 60 * 20; frame++) {
        if (game.state != GameState.playing) break;
        final now = run.state.runClock;
        final extrasBefore = bot.extraFlaps;
        if (bot.shouldFlap()) {
          emitted.add(now);
          if (bot.extraFlaps > extrasBefore) {
            expect(dueExtras, isNotEmpty);
            final elapsed = now - dueExtras.removeAt(0);
            expect(elapsed, greaterThanOrEqualTo(HumanNoiseBot.extraFlapGap));
            expect(
              elapsed,
              lessThan(HumanNoiseBot.extraFlapGap + 1 / 60 + 1e-9),
            );
          } else {
            dueExtras.add(now);
            expect(bot.baseFlapOffsets.last, now - bot.plannedFlapTimes.last);
          }
        }
        game.update(1 / 60);
        if (frame % 10 == 9) await flushAndMount(game);
      }
      expect(bot.baseFlapOffsets.length, greaterThan(10));
      expect(bot.extraFlaps, greaterThan(0));
      expect(bot.flapTimes, orderedEquals(emitted));
      expect(emitted.length, bot.baseFlapOffsets.length + bot.extraFlaps);
    },
  );

  FlameTester(
    () => createRunTestGame(prefs: {'gamesPlayed': 10}),
    gameSize: Vector2(Config.worldWidth, 568),
  ).testGameWidget(
    'closed-loop emitted offsets and extras retain the human-noise distribution',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final offsets = <double>[];
      var extras = 0;
      game.runDebug.ignoreGates = false;
      for (var seed = 0; seed < 50; seed++) {
        game.runSeed = seed;
        game.storage.gamesPlayed = 10;
        await startRun(game);
        final result = await flyHumanNoiseBotToDeath(
          game,
          seed: seed,
          maxSeconds: 60,
        );
        offsets.addAll(result.baseFlapOffsets);
        extras += result.extraFlaps;
        expect(result.flaps, result.baseFlapOffsets.length + result.extraFlaps);
        game.replay();
        await flushAndMount(game);
        stepGame(game, .4);
        await flushAndMount(game);
      }
      expect(offsets.length, greaterThanOrEqualTo(500));
      final mean = offsets.reduce((a, b) => a + b) / offsets.length;
      final variance =
          offsets
              .map((offset) => math.pow(offset - mean, 2))
              .reduce((a, b) => a + b) /
          (offsets.length - 1);
      final sd = math.sqrt(variance);
      // Measure emitted actions, including frame quantization, rather than
      // merely testing the Gaussian generator's raw draws.
      expect(mean * 1000, closeTo(0, 10));
      expect(sd * 1000, closeTo(90, 10));
      expect(extras / offsets.length, closeTo(.1, .03));
      // ignore: avoid_print
      print(
        'CLOSED LOOP: n=${offsets.length} mean=${mean * 1000}ms '
        'sd=${sd * 1000}ms extra=${extras / offsets.length}',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
  // endregion

  for (final height in [568.0, 711.0]) {
    FlameTester(
      () => createRunTestGame(worldHeight: height, seed: 11),
      gameSize: Vector2(Config.worldWidth, height),
    ).testGameWidget(
      'the helper flies to death and records highlights at ${height.round()} pt',
      setUp: (game, _) async {
        await game.ready();
        game.sound.enabled = false;
        await preloadImages(game);
      },
      verify: (game, _) async {
        await startRun(game);
        var emittedHighlight = false;
        final result = await flyHumanNoiseBotToDeath(
          game,
          seed: 23,
          // PRD-2.6 D2 softens the course: retain the death assertion,
          // with enough flight time to reach the harder rows.
          maxSeconds: 180,
          onFrame: (run) {
            if (!emittedHighlight) {
              emittedHighlight = true;
              run.events.emit(
                const HighlightStarted(
                  'human-bot-test',
                  scripted: false,
                  hoop: 0,
                ),
              );
            }
          },
        );

        expect(result.cause, isA<MistakeCause>());
        expect(result.seconds, greaterThan(0));
        expect(result.flaps, greaterThan(0));
        expect(result.highlightIds, contains('human-bot-test'));
        // Keep a concrete cross-height signal in failure output without making
        // this issue own the later ceiling gate.
        // ignore: avoid_print
        print(
          'HUMAN BOT h=$height: ${result.hoops} hoops, '
          '${result.flaps} flaps (${result.extraFlaps} extra), '
          'cause ${result.cause}, offsets ${result.baseFlapOffsets.length}',
        );
      },
    );
  }

  test('the human bot is not imported or referenced outside debug code', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains(Platform.pathSeparator) &&
          entity.path.startsWith(
            'lib${Platform.pathSeparator}run${Platform.pathSeparator}debug',
          )) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (source.contains('human_bot.dart') ||
          source.contains('HumanNoiseBot') ||
          source.contains('HumanNoiseFlapScheduler')) {
        violations.add(entity.path);
      }
    }
    expect(violations, isEmpty);
  });
}
