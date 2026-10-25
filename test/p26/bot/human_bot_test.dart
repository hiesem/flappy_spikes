import 'dart:io';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
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
      if (frame % 27 == 0) scheduler.planBase(now);
      scheduler.flapDue(now);
      planned = scheduler.plannedFlapTimes.length;
    }
    for (
      var frame = baseFlaps * 27;
      scheduler.flapTimes.length < baseFlaps + scheduler.extraFlaps;
      frame++
    ) {
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

  test('flap jitter is 90 ms sigma and extra flaps are 10 percent', () {
    const flaps = 1000;
    final scheduler = schedule(seed: 7, baseFlaps: flaps);
    final mean = scheduler.jitterSeconds.reduce((a, b) => a + b) / flaps;
    final variance =
        scheduler.jitterSeconds
            .map((value) => (value - mean) * (value - mean))
            .reduce((a, b) => a + b) /
        (flaps - 1);
    final sigmaMilliseconds = math.sqrt(variance) * 1000;

    expect(sigmaMilliseconds, closeTo(90, 10));
    expect(scheduler.extraFlaps / flaps, closeTo(.1, .02));
  });

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
          'cause ${result.cause}',
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
