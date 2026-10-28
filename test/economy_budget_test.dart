@Tags(['heavy'])
library;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/levels/level_track.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
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

    // PRD §8.3-17: newcomer showcase budget is a mean over 20 fresh
    // three-run sequences, excluding any run fast-tracked out at START.
    group('F5 newcomer showcase at $height', () {
      final totals = <int, int>{};
      var extras = 0;
      tearDownAll(() {
        expect(totals, hasLength(20));
        final ordered = [for (var seed = 0; seed < 20; seed++) totals[seed]!];
        final mean = ordered.reduce((a, b) => a + b) / ordered.length;
        // ignore: avoid_print
        print(
          'ECONOMY newcomer h=$height totals=$ordered mean=$mean '
          'extraFlaps=$extras sigma=90ms extraChance=10%',
        );
        expect(
          extras,
          greaterThan(0),
          reason: 'The newcomer actually emits extra flaps',
        );
        expect(
          mean,
          inInclusiveRange(90, 200),
          reason: 'PRD §8.3-17: mean of showcase-at-START flight coins only',
        );
      });
      for (var sequence = 0; sequence < 20; sequence++) {
        FlameTester<FlappySpikesGame>(() {
          ShowcaseShow.resetProcessMemoryForTests();
          SharedPreferences.setMockInitialValues({});
          return FlappySpikesGame(
            worldHeight: height,
            soundEnabled: false,
            showcaseFactory: (storage) => ShowcaseShow(storage: storage),
          );
        }, gameSize: Vector2(320, height)).testGameWidget(
          'fresh sequence $sequence',
          setUp: (game, _) async {
            await game.ready();
            await preloadImages(game);
            PostRunScreens.bonus = null;
          },
          verify: (game, tester) => tester.runAsync(() async {
            var coins = 0;
            for (var run = 0; run < 3; run++) {
              final sample = await flyEconomyRun(
                game,
                seed: sequence * 3 + run,
                sigma: economyProfiles['weak']!,
                takeFreeRevive: true,
              );
              if (run == 0) expect(sample.showcaseAtStart, isTrue);
              if (sample.showcaseAtStart) {
                coins += sample.coins;
                extras += sample.extraFlaps;
              }
            }
            totals[sequence] = coins;
          }),
          timeout: const Timeout(Duration(minutes: 5)),
        );
      }
    });

    FlameTester<FlappySpikesGame>(() {
      ShowcaseShow.resetProcessMemoryForTests();
      SharedPreferences.setMockInitialValues({});
      return FlappySpikesGame(
        worldHeight: height,
        soundEnabled: false,
        showcaseFactory: (storage) => ShowcaseShow(storage: storage),
      );
    }, gameSize: Vector2(320, height)).testGameWidget(
      'F5 medium first 50 runs, level guard and meta at $height',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        // This gate measures flight income; do not enter balloon minigames.
        PostRunScreens.bonus = null;
      },
      verify: (game, tester) => tester.runAsync(() async {
        final total = EconomySample();
        var showcaseCoins = 0;
        var mediumFirstThreeCoins = 0;
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
            mediumFirstThreeCoins += sample.coins;
            if (sample.showcaseAtStart) showcaseCoins += sample.coins;
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
        // PRD §8.3-17 separates a typical day from a daily gold winner.
        final typicalMeta = meta - metaCoinsPerDay[CoinSource.leaderboardGift]!;
        final typicalShare = typicalMeta / (dailyPlay + typicalMeta);
        final worstShare = meta / (dailyPlay + meta);
        // ignore: avoid_print
        print(
          'ECONOMY first50 h=$height: $total; showcase=$showcaseCoins '
          'mediumFirstThree=$mediumFirstThreeCoins '
          'level=$level levelCoins=$levelCoins playCoins=${total.coins} '
          'level/play=${levelCoins / total.coins}; '
          'typicalMeta/day=$typicalMeta worstMeta/day=$meta play/day=$dailyPlay '
          'typicalShare=$typicalShare worstShare=$worstShare',
        );
        // Medium showcase income stays diagnostic; only the newcomer mean
        // above carries that assertion (PRD §8.3-17).
        expect(
          {
            'level coins, runs 1–50': levelCoins,
            'typical meta share': typicalShare,
            'worst-case meta share': worstShare,
          },
          {
            'level coins, runs 1–50': lessThanOrEqualTo(total.coins),
            'typical meta share': lessThanOrEqualTo(.25),
            'worst-case meta share': lessThanOrEqualTo(.30),
          },
          reason:
              'PRD F5/F12/G6, §8.3-17: medium human-noise, FREE showcase revive, '
              'daily first-place gold gift; meta sources=$metaCoinsPerDay',
        );
      }),
      timeout: const Timeout(Duration(minutes: 15)),
    );
  }

  test('F12/G meta source inventory excludes levels, purchases and spends', () {
    // Every source must be classified when the enum grows.
    expect(CoinSource.values.toSet(), {
      ...metaCoinsPerDay.keys,
      CoinSource.play,
      CoinSource.iap,
      CoinSource.rewarded,
      CoinSource.noadsBonus,
      CoinSource.levelReward,
      CoinSource.debug,
      CoinSource.hoop,
      CoinSource.perfect,
      CoinSource.winBonus,
      CoinSource.bonus,
      CoinSource.puzzle,
      CoinSource.switchRing,
      CoinSource.pair,
      CoinSource.train,
      CoinSource.bullseye,
      CoinSource.luckySpin,
      CoinSource.starTrail,
      CoinSource.piggy,
      CoinSource.jar,
      CoinSource.frenzy,
      CoinSource.gift,
      CoinSource.weekly,
      CoinSource.streakRestore,
      CoinSource.album,
    });
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
    // PRD G6/F12 and §8.3-17: daily projections include every approved
    // source, with gold expressed as its expected coin payout. These exact
    // amounts prevent an omitted or understated source from hiding a breach.
    final tuning = TuningValues.current;
    expect(metaCoinsPerDay[CoinSource.mission], tuning.ints('mission_rewards').reduce((a, b) => a + b));
    expect(metaCoinsPerDay[CoinSource.missionChest], tuning.i('mission_chest_coins'));
    final streak = tuning.raw('streak_rewards') as List;
    final streakCoins = streak.fold<int>(0, (sum, value) => sum + (value is int ? value : int.tryParse(value.toString().split('+').last) ?? 0));
    expect(metaCoinsPerDay[CoinSource.streak], closeTo(streakCoins / 7, 1e-9));
    expect(metaCoinsPerDay[CoinSource.firstWinDay], 20);
    expect(metaCoinsPerDay[CoinSource.starRoad], closeTo(960 / 28, 1e-9));
    expect(metaCoinsPerDay[CoinSource.leaderboardGift], 100);
    final typical = metaCoinsPerDay.entries
        .where((entry) => entry.key != CoinSource.leaderboardGift)
        .fold<double>(0, (sum, entry) => sum + entry.value);
    expect(typical, closeTo(232.857142857, 1e-6));
    expect(
      typical + metaCoinsPerDay[CoinSource.leaderboardGift]!,
      closeTo(332.857142857, 1e-6),
    );
  });
}
