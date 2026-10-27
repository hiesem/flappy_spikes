@Tags(['heavy'])
library;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/levels/level_track.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flappy_spikes/run/screens/post_run_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';
import 'p26/bot/economy_probe.dart';

void main() {
  final originalBonus = PostRunScreens.bonus;
  tearDown(() => PostRunScreens.bonus = originalBonus);
  for (final height in [568.0, 711.0]) {
    for (final profile in economyProfiles.entries) {
      FlameTester(
        () =>
            createRunTestGame(worldHeight: height, prefs: {'gamesPlayed': 10}),
        gameSize: Vector2(320, height),
      ).testGameWidget(
        'F5 ${profile.key} 20 seeds at $height',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
          // This gate measures flight income; do not enter balloon minigames.
          PostRunScreens.bonus = null;
        },
        verify: (game, tester) => tester.runAsync(() async {
          game.runDebug.ignoreGates = false;
          final total = EconomySample();
          for (var seed = 0; seed < 20; seed++) {
            total.add(
              await flyEconomyRun(game, seed: seed, sigma: profile.value),
            );
          }
          final label = '${profile.key} h=$height: $total';
          // ignore: avoid_print
          print('ECONOMY $label');
          expect(total.hoops, greaterThan(0));
          // PRD-2.6 F5. Ratios are weighted by observed hoops/time, rather
          // than averaging per-run ratios (which overweights short deaths).
          expect(total.coinsPerHoop, inInclusiveRange(1.4, 2.1), reason: label);
          expect(total.coinsPerMinute, lessThanOrEqualTo(80), reason: label);
          expect(total.nonHoopPerHoop, lessThanOrEqualTo(.35), reason: label);
        }),
        timeout: const Timeout(Duration(minutes: 15)),
      );
    }

    FlameTester<FlappySpikesGame>(() {
      ShowcaseShow.resetProcessMemoryForTests();
      SharedPreferences.setMockInitialValues({});
      return FlappySpikesGame(
        worldHeight: height,
        soundEnabled: false,
        showcaseFactory: (storage) => ShowcaseShow(storage: storage),
      );
    }, gameSize: Vector2(320, height)).testGameWidget(
      'F5 medium first 50 runs, showcase and meta at $height',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        // This gate measures flight income; do not enter balloon minigames.
        PostRunScreens.bonus = null;
      },
      verify: (game, tester) => tester.runAsync(() async {
        final total = EconomySample();
        var showcaseCoins = 0;
        var level = 0;
        var points = 0;
        var levelCoins = 0;
        for (var seed = 0; seed < 50; seed++) {
          final sample = await flyEconomyRun(
            game,
            seed: seed,
            sigma: .05,
            takeFreeRevive: true,
          );
          total.add(sample);
          if (seed < 3) {
            showcaseCoins += sample.coins;
            // ignore: avoid_print
            print('ECONOMY showcase h=$height run=${seed + 1}: $sample');
          }
          // J1's pure production track, pending J2's run-end wiring. Use
          // final score, drop surplus, and award at most one level per run.
          final next = LevelTrack.step(level, points, sample.score);
          level = next.index;
          points = next.points;
          if (next.levelledUp) levelCoins += trackLevelDef(level)!.coins;
        }
        final meta = metaCoinsPerDay.values.reduce((a, b) => a + b);
        final dailyPlay = total.coinsPerMinute * 15;
        final share = meta / (dailyPlay + meta);
        // ignore: avoid_print
        print(
          'ECONOMY first50 h=$height: $total; showcase=$showcaseCoins '
          'level=$level levelCoins=$levelCoins playCoins=${total.coins} '
          'level/play=${levelCoins / total.coins}; '
          'meta/day=$meta play/day=$dailyPlay metaShare=$share',
        );
        // Match all three budgets together so an early showcase failure
        // still reports the level and meta values from the same window.
        expect(
          {
            'showcase coins, runs 1–3': showcaseCoins,
            'level coins, runs 1–50': levelCoins,
            'meta share of 15-minute day': share,
          },
          {
            'showcase coins, runs 1–3': inInclusiveRange(90, 200),
            'level coins, runs 1–50': lessThanOrEqualTo(total.coins),
            'meta share of 15-minute day': lessThanOrEqualTo(.25),
          },
          reason:
              'PRD F5/F12/G6: medium human-noise, FREE showcase revive, '
              'daily first-place gold gift; meta sources=$metaCoinsPerDay',
        );
      }),
      timeout: const Timeout(Duration(minutes: 15)),
    );
  }

  test('F12/G meta source inventory excludes levels, purchases and spends', () {
    expect(
      metaCoinsPerDay.keys,
      unorderedEquals([
        CoinSource.mission,
        CoinSource.missionChest,
        CoinSource.streak,
        CoinSource.firstWinDay,
        CoinSource.leaderboardGift,
        CoinSource.starRoad,
      ]),
    );
    expect(metaCoinsPerDay.values, everyElement(greaterThan(0)));
  });
}
