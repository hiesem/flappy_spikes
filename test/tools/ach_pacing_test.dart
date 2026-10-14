// PRD-2.3.1 §19.1 / §19.6 achievement pacing dev tool, skipped unless
// FS_ACH is set:
//   FS_ACH=rates  FS_ACH_SEEDS=40 FS_ACH_HOOPS=20 \
//     flutter test test/tools/ach_pacing_test.dart
//     → the bot's catches per item per run (all elements met, gates open;
//       god mode so every run reaches FS_ACH_HOOPS).
//   FS_ACH=pacing FS_ACH_SEEDS=5 FS_ACH_RUNS=30 FS_ACH_HOOPS=20 \
//     flutter test test/tools/ach_pacing_test.dart
//     → a simulated new player (first-meet, lifetime gates, the real
//       tracker and its 1-per-run pacing): unlocks per run, per seed.
import 'dart:io';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/achievements/achievements_feature.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final env = Platform.environment;
  final mode = env['FS_ACH'] ?? '';
  final seeds = int.tryParse(env['FS_ACH_SEEDS'] ?? '') ?? 40;
  final hoops = int.tryParse(env['FS_ACH_HOOPS'] ?? '') ?? 20;
  final runs = int.tryParse(env['FS_ACH_RUNS'] ?? '') ?? 30;

  // --- catch rates --------------------------------------------------------------
  final catches = <AchievementId, int>{};
  var rateRuns = 0, ratePasses = 0;
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
      'catch rates seed $seed',
      skip: mode != 'rates',
      setUp: (g, _) async {
        await g.ready();
        g.sound.enabled = false;
        await preloadImages(g);
      },
      verify: (g, _) async {
        g.runDebug.god = true;
        final run = await startRun(g);
        run.events.on<PickupCollected>((e) {
          final id = AchievementsFeature.catchFor(e);
          if (id != null) catches[id] = (catches[id] ?? 0) + 1;
        });
        await flyRun(g, untilHoops: hoops, maxSeconds: 600);
        rateRuns++;
        ratePasses += run.state.hoopsPassed;
      },
    );
  }

  // --- new-player pacing ------------------------------------------------------------
  final curves = <List<int>>[];
  final earnedCurves = <List<int>>[];
  final hoopsFlown = <int>[];
  final firstUnlock = <String, List<int>>{};
  for (var seed = 1; seed <= seeds; seed++) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: 711,
        seed: seed,
        prefs: {'firstSessionDone': true},
      ),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'pacing seed $seed',
      skip: mode != 'pacing',
      setUp: (g, _) async {
        await g.ready();
        g.sound.enabled = false;
        await preloadImages(g);
      },
      verify: (g, _) async {
        g.runDebug.ignoreGates = false; // the lifetime gates of a new player
        g.achievements.countDebugRuns = true;
        final curve = <int>[];
        final earned = <int>[];
        final mine = <String, int>{};
        for (var r = 0; r < runs; r++) {
          final before = g.storage.achUnlocked.length;
          final earnedBefore = g.achievements.earned.length;
          g.runSeed = seed * 1000 + r;
          // Home: the No-Ads popup is dismissed, the LEVEL UP claimed.
          if (g.noAdsPopup != null) {
            g.closeNoAdsPopup();
            stepGame(g, 1);
            await flushAndMount(g);
          }
          for (var i = 0; i < 5 && g.levelUpPopup != null; i++) {
            await g.claimLevelUp();
            stepGame(g, 1);
            await flushAndMount(g);
          }
          final RunController run;
          try {
            run = await startRun(g);
          } catch (_) {
            // ignore: avoid_print
            print('ACHDBG seed $seed run $r: no run (${g.state}) '
                '${g.world.children.map((c) => c.runtimeType).toList()}');
            rethrow;
          }
          await flyRun(g, untilHoops: hoops, maxSeconds: 600);
          // A mistake cannot end a ride: fly on until the run can end.
          for (var k = 0; k < 120 && g.state == GameState.playing; k++) {
            killRunThroughSaves(g);
            if (g.state == GameState.playing) {
              await flyRun(g, maxSeconds: 0.5);
            }
          }
          hoopsFlown.add(run.state.hoopsPassed);
          await declineRevive(g);
          await flushAndMount(g);
          // The balloon bonus: pop every balloon, then NEXT.
          for (var i = 0; i < 2000 && g.state == GameState.bonus; i++) {
            final b = g.bonusScreen;
            if (b != null) {
              for (var t = 0; t < 9; t++) {
                if (b.tapTile(t)) break;
              }
              b
                ..tapNext()
                ..tapNoThanks();
            }
            g.update(1 / 60);
            if (i % 10 == 0) await flushAndMount(g);
          }
          await flushAndMount(g);
          for (final k in g.storage.achUnlocked) {
            mine.putIfAbsent(k, () => r + 1);
          }
          if (env['FS_ACH_DEBUG'] == '1') {
            // ignore: avoid_print
            print('ACHDBG seed $seed run $r: ${g.state} hoops '
                '${run.state.hoopsPassed} score ${run.state.score} counted '
                '${g.achievements.lastRunCounted} pending '
                '${g.storage.achPending} unlocked ${g.storage.achUnlocked}');
          }
          curve.add(g.storage.achUnlocked.length - before);
          earned.add(g.achievements.earned.length - earnedBefore);
          g.goHome();
          await flushAndMount(g);
          stepGame(g, 1);
          await flushAndMount(g);
        }
        mine.forEach((k, r) => (firstUnlock[k] ??= []).add(r));
        // ignore: avoid_print
        print('ACHDBG seed $seed counts ${g.storage.achItemCounts} '
            'pending ${g.storage.achPending}');
        curves.add(curve);
        earnedCurves.add(earned);
      },
    );
  }

  tearDownAll(() {
    final out = <String>[];
    if (mode == 'rates' && rateRuns > 0) {
      out.add(
        'ACH rates (a Star Trail counts once): $rateRuns runs, ${(ratePasses / rateRuns).toStringAsFixed(1)} '
        'hoops/run (target $hoops)',
      );
      for (final id in kItemAchievements) {
        final n = catches[id] ?? 0;
        out.add(
          'ACH   ${id.key}: ${(n / rateRuns).toStringAsFixed(3)} catches/run',
        );
      }
    }
    if (mode == 'pacing' && curves.isNotEmpty) {
      String row(List<List<int>> cs, int r) {
        final v = [for (final c in cs) c[r]];
        final avg = v.reduce((a, b) => a + b) / v.length;
        return '${avg.toStringAsFixed(2)} ${v.join(',')}';
      }

      final avgHoops =
          hoopsFlown.reduce((a, b) => a + b) / hoopsFlown.length;
      out.add(
        'ACH pacing: ${curves.length} players × $runs runs, '
        '${avgHoops.toStringAsFixed(1)} hoops/run',
      );
      var total = 0.0;
      for (var r = 0; r < runs; r++) {
        total += [for (final c in curves) c[r]].reduce((a, b) => a + b) /
            curves.length;
        out.add(
          'ACH   run ${r + 1}: unlocked ${row(curves, r)} · earned '
          '${row(earnedCurves, r)} · cumulative ${total.toStringAsFixed(1)}',
        );
      }
      for (final id in AchievementId.values) {
        final l = firstUnlock[id.key];
        if (l == null || l.isEmpty) continue;
        l.sort();
        out.add(
          'ACH   ${id.key}: unlocked by ${l.length}/${curves.length} '
          '(median run ${l[l.length ~/ 2]})',
        );
      }
    }
    // ignore: avoid_print
    out.forEach(print);
  });
}
