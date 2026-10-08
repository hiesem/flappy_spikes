import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

int componentCount(Component c) =>
    1 + c.children.fold(0, (n, child) => n + componentCount(child));

void main() {
  for (final height in [568.0, 711.0]) {
    for (final seed in [7, 21, 1234]) {
      final spy = AnalyticsSpy();
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: height, seed: seed, services: spy),
        gameSize: Vector2(320, height),
      ).testGameWidget(
        'P3 all elements allowed long autopilot h=$height seed=$seed',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
        },
        verify: (g, _) async {
          final run = await startRun(g);
          final flight = await flyRun(g, maxSeconds: 180);
          // Natural deaths are allowed in a long course; §7 requires ≥12.
          expect(
            flight.hoops,
            greaterThanOrEqualTo(12),
            reason: flight.trace.reversed.take(20).join('\n'),
          );
          // ignore: avoid_print
          print(
            'P3 NATURAL h=$height seed=$seed: ${flight.hoops} hoops, '
            '${flight.seconds.toStringAsFixed(2)}s, ${flight.cause}; '
            'spawned=${run.summarize().spawned}; '
            'met=${g.storage.metElements.toList()..sort()}',
          );
          // Finish the real journey and audit the emitted §6 summary.
          // Ride input/mistakes are ignored; wait for its actual landing.
          if (run.state.ride != null) {
            expect(await flyUntil(g, (r) => r.state.ride == null), isTrue);
          }
          killRunThroughSaves(g);
          await declineRevive(g);
          final names = spy.events.map((e) => e.$1).toList();
          expect(
            names,
            containsAllInOrder([
              'run_end',
              'run_director_hoops',
              'run_director_items',
            ]),
          );
          for (final name in ['run_director_hoops', 'run_director_items']) {
            final params = spy.events.singleWhere((e) => e.$1 == name).$2!;
            expect(params.length, lessThanOrEqualTo(25));
            expect(params.values, everyElement(isA<int>()));
          }
          final spawned = run.summarize().spawned;
          for (final (kind, event) in [
            ('fever', 'fever_ring_spawned'),
            ('saw', 'sawring_spawned'),
            ('switch_ring', 'switchring_spawned'),
            ('pair', 'pair_spawned'),
          ]) {
            expect(
              spy.events.where((e) => e.$1 == event).length,
              spawned[kind] ?? 0,
            );
          }
          for (final e in spy.events.where((e) => e.$1 == 'coins_earned')) {
            expect(e.$2!['amount'], isA<int>());
            expect(e.$2!['source'], isA<String>());
            expect(e.$2!['egg_x2'], anyOf(0, 1));
          }
          expect(run.ended, isTrue);
        },
      );
    }
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: height, seed: 1234),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'P3 390 second soak h=$height: mounted components stay bounded',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        final run = await startRun(g);
        // Ignore mistakes only in the soak, so it reaches six minutes.
        g.runDebug.god = true;
        final bot = Autopilot(run);
        final counts = <int>[];
        for (var f = 0; f < 390 * 60; f++) {
          if (bot.shouldFlap()) g.onScreenTap();
          g.update(1 / 60);
          if (f % 10 == 0) await flushAndMount(g);
          if (f % 600 == 0) counts.add(componentCount(g));
        }
        expect(run.state.runClock, greaterThan(360));
        expect(run.ended, isFalse);
        expect(counts.reduce(math.max), lessThan(250));
        final earlyMax = counts.skip(6).take(12).reduce(math.max);
        final lateMax = counts.skip(24).reduce(math.max);
        expect(lateMax, lessThanOrEqualTo(earlyMax + 40));
        expect(run.spawner.hoops.length, lessThan(12));
        expect(run.spawner.pickups.length, lessThan(12));
        expect(run.state.metElements, contains(ElementId.squeeze));
        // ignore: avoid_print
        print(
          'P3 SOAK h=$height: clock=${run.state.runClock}, '
          'hoops=${run.state.hoopsPassed}, counts=$counts, '
          'spawned=${run.summarize().spawned}',
        );
      },
    );
  }
}
