// Owner 2026-10-14 gameplay tuning: the bot's averages for one tuning set —
// coins (by source) and points per hoop, perfect rate, special hoops and gap
// items per 10 hoops, rides per run. Dev tool, skipped unless FS_FUN=1.
//   FS_FUN=1 FS_FUN_RC=<json {key: value}> FS_FUN_SEEDS=25 FS_FUN_HOOPS=80 \
//     flutter test test/tools/fun_budget_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/debug/run_stats.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/services/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final env = Platform.environment;
  final on = env['FS_FUN'] == '1';
  final seeds = int.tryParse(env['FS_FUN_SEEDS'] ?? '') ?? 25;
  final hoops = int.tryParse(env['FS_FUN_HOOPS'] ?? '') ?? 80;
  final rcFile = env['FS_FUN_RC'];
  final overrides = <String, String>{
    'ui_unlock_best': '0',
    if (rcFile != null)
      for (final e
          in (jsonDecode(File(rcFile).readAsStringSync()) as Map).entries)
        e.key as String: e.value as String,
  };
  final all = <RunStats>[];

  for (var seed = 1; seed <= seeds; seed++) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: 711,
        seed: seed,
        prefs: {
          'firstSessionDone': true,
          'metElements': [for (final e in ElementId.values) e.storageId],
        },
      ),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'fun seed $seed',
      skip: !on,
      setUp: (g, _) async {
        Tuning.instance = Tuning(active: TuningValues.resolve(overrides));
        TuningValues.current = Tuning.instance.active;
        await g.ready();
        g.sound.enabled = false;
        await preloadImages(g);
      },
      verify: (game, _) async {
        game.runDebug.god = true;
        final run = await startRun(game);
        final s = RunStats(run);
        await flyRun(game, untilHoops: hoops, maxSeconds: 900);
        all.add(s);
      },
    );
  }

  tearDownAll(() {
    if (!on || all.isEmpty) return;
    var passes = 0, perfects = 0, coins = 0, points = 0;
    var specials = 0, items = 0, rides = 0;
    final by = <CoinSource, int>{};
    for (final s in all) {
      passes += s.passes;
      perfects += s.perfects;
      coins += s.coins;
      points += s.points;
      specials += s.specials;
      items += s.items;
      rides += s.rides;
      s.coinsBy.forEach((k, v) => by[k] = (by[k] ?? 0) + v);
    }
    String per(int n) => (n / passes).toStringAsFixed(3);
    final lines = [
      'FUN runs ${all.length} · hoops $passes ($hoops/run target)',
      'FUN coins/hoop ${per(coins)} · points/hoop ${per(points)} · '
          'perfect ${(perfects / passes * 100).toStringAsFixed(1)} %',
      'FUN specials/10h ${(specials / passes * 10).toStringAsFixed(2)} · '
          'items/10h ${(items / passes * 10).toStringAsFixed(2)} · '
          'rides/run ${(rides / all.length).toStringAsFixed(2)}',
      for (final e in (by.entries.toList()..sort((a, b) => b.value - a.value)))
        'FUN   ${e.key.name}: ${per(e.value)}/hoop',
    ];
    // ignore: avoid_print
    lines.forEach(print);
  });
}
