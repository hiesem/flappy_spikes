import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/debug/human_bot.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const economyProfiles = <String, double>{
  'weak': .09,
  'medium': .05,
  'strong': .03,
};

/// Observed income only: no fabricated passes, pickups, invulnerability or
/// tuning overrides. Hoop income includes perfect-pass awards; everything
/// else emitted by the run is non-hoop income (PRD F5).
class EconomySample {
  final bySource = <CoinSource, int>{};
  int hoops = 0;
  int score = 0;
  double seconds = 0;

  int get coins => bySource.values.fold(0, (a, b) => a + b);
  int get nonHoopCoins =>
      coins -
      (bySource[CoinSource.hoop] ?? 0) -
      (bySource[CoinSource.perfect] ?? 0);
  double get coinsPerHoop => coins / hoops;
  double get coinsPerMinute => coins * 60 / seconds;
  double get nonHoopPerHoop => nonHoopCoins / hoops;

  void add(EconomySample other) {
    hoops += other.hoops;
    score += other.score;
    seconds += other.seconds;
    other.bySource.forEach((source, amount) {
      bySource.update(
        source,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
    });
  }

  @override
  String toString() =>
      'hoops=$hoops coins=$coins seconds=${seconds.toStringAsFixed(1)} '
      'coins/hoop=${coinsPerHoop.toStringAsFixed(3)} '
      'coins/min=${coinsPerMinute.toStringAsFixed(3)} '
      'non-hoop/hoop=${nonHoopPerHoop.toStringAsFixed(3)} '
      'sources=${bySource.map((k, v) => MapEntry(k.name, v))}';
}

Future<EconomySample> flyEconomyRun(
  FlappySpikesGame game, {
  required int seed,
  required double sigma,
  bool takeFreeRevive = false,
}) async {
  game.runSeed = seed;
  // Completing runs can queue the legacy level / No-Ads Home popups.
  // Close them through the same Back action a player uses before START.
  for (var popup = 0; popup < 10 && game.modalPopupOpen; popup++) {
    expect(game.handleBack(), isTrue);
    await flushAndMount(game);
    stepGame(game, .5);
    await flushAndMount(game);
  }
  expect(game.modalPopupOpen, isFalse, reason: 'before START seed=$seed');
  final run = await startRun(game);
  expect(
    run.countsForUpload,
    isTrue,
    reason: 'Economy probes must use an eligible, unforced run',
  );
  final sample = EconomySample();
  void earned(CoinsEarned event) {
    sample.bySource.update(
      event.source,
      (value) => value + event.amount,
      ifAbsent: () => event.amount,
    );
  }

  run.events.on<CoinsEarned>(earned);
  try {
    Future<void> fly(int noiseSeed) async {
      final result = await flyHumanNoiseBotToDeath(
        game,
        seed: noiseSeed,
        jitterSigma: sigma,
        maxSeconds: 600,
      );
      sample.seconds += result.seconds;
      expect(
        result.cause,
        isNotNull,
        reason: 'Income must cover a complete flight, seed=$seed sigma=$sigma',
      );
    }

    await fly(seed);
    if (takeFreeRevive &&
        run.state.hoopsPassed > 0 &&
        run.setup.showcase?.freeRevive == true) {
      // Advance only the death tumble/UI; never include menu time in run-min.
      for (
        var frame = 0;
        frame < 600 && game.state == GameState.dying;
        frame++
      ) {
        game.update(1 / 60);
        if (frame % 10 == 0) await flushAndMount(game);
      }
      await flushAndMount(game);
      final screen = game.reviveScreen;
      if (screen != null && screen.offer.isFree) {
        stepGame(game, 1);
        screen.tapHeart();
        for (
          var frame = 0;
          frame < 600 && game.state == GameState.reviving;
          frame++
        ) {
          game.update(1 / 60);
          if (frame % 10 == 0) await flushAndMount(game);
        }
        expect(game.state, GameState.playing);
        await fly(seed + 10000);
      }
    }
    sample.hoops = run.state.hoopsPassed;
    sample.score = run.state.score;
    expect(sample.coins, run.state.coinsThisRun);
    // Finish bookkeeping while declining paid/ad revives and balloon play.
    game.endRun(run.endRun());
    await flushAndMount(game);
    final showcase = game.showcasePlan;
    if (showcase is ShowcaseShow) await showcase.writesSettled;
  } finally {
    run.events.off<CoinsEarned>(earned);
  }
  game.replay();
  await flushAndMount(game);
  stepGame(game, .4);
  await flushAndMount(game);
  return sample;
}

/// G/LB builders replace these PRD projections with their shipped reward
/// tables as those packages land. Keep every coin-paying meta source here;
/// level coins, ads/IAP and coin spends are deliberately separate from meta.
/// Gold is the expected coin payout for first place EVERY day (F12), not the
/// lower payout of an average leaderboard participant. Item value is not coins.
const metaCoinsPerDay = <CoinSource, double>{
  CoinSource.mission: 20 + 35 + 55,
  CoinSource.missionChest: 40,
  CoinSource.streak: 200 / 7,
  CoinSource.firstWinDay: 20,
  CoinSource.leaderboardGift: .5 * (100 + 300) / 2,
  CoinSource.starRoad: 960 / 28,
};
