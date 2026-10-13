import 'dart:io';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.3 §6.1 budget check (reported, not a gate): the bot's average
/// `coins_per_hoop` over 50-hoop seeded runs (god mode, every element met
/// and unlocked — an experienced player's run). Skipped unless the
/// environment has `FS_BUDGET=1`; the numbers go to
/// docs/p23/REPORT_tune.md.
///
///   FS_BUDGET=1 flutter test test/p23/budget_report_test.dart
void main() {
  final on = Platform.environment['FS_BUDGET'] == '1';
  const seeds = 20;
  const hoops = 50;
  final results = <String>[];
  var coins = 0, passed = 0;

  for (var seed = 1; seed <= seeds; seed++) {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: 711,
        seed: seed,
        prefs: {
          'firstSessionDone': true,
          'metElements': [for (final e in ElementId.values) e.storageId],
        },
      ),
      gameSize: Vector2(320, 711),
    );
    tester.testGameWidget(
      'budget seed $seed',
      skip: !on,
      setUp: (g, _) async {
        await g.ready();
        g.sound.enabled = false;
        await preloadImages(g);
      },
      verify: (game, _) async {
        game.runDebug.god = true;
        await startRun(game);
        final f = await flyRun(game, untilHoops: hoops, maxSeconds: 400);
        coins += f.coins;
        passed += f.hoops;
        results.add(
          'seed $seed: ${f.hoops} hoops, ${f.coins} coins, '
          '${(f.coins / (f.hoops < 1 ? 1 : f.hoops)).toStringAsFixed(2)} '
          'coins/hoop',
        );
      },
    );
  }

  tearDownAll(() {
    if (!on) return;
    for (final r in results) {
      // ignore: avoid_print
      print(r);
    }
    // ignore: avoid_print
    print(
      'BUDGET average: ${(coins / (passed < 1 ? 1 : passed)).toStringAsFixed(3)} '
      'coins/hoop over $passed hoops ($seeds runs)',
    );
  });
}
