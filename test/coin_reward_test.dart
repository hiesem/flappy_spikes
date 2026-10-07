import 'dart:math' as math;
import 'dart:ui';

import 'package:flappy_spikes/components/ui/coin_reward.dart';
import 'package:flappy_spikes/components/ui/confetti.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'home_flow_test.dart' show homeTest;
import 'shop_flow_test.dart' show openShop;

/// Steps [seconds] in 50 ms chunks, mounting what each chunk spawned.
Future<void> run(FlappySpikesGame game, double seconds) async {
  for (var t = 0.0; t < seconds - 1e-9; t += .05) {
    stepGame(game, .05);
    await flushAndMount(game);
  }
}

/// Starts [reward] the way callers do: hold, credit, play.
Future<CoinRewardAnimation> start(
  FlappySpikesGame game,
  CoinRewardAnimation reward,
) async {
  game.coinPill.hold();
  await game.menu.wallet.add(reward.amount, CoinSource.iap);
  game.playCoinReward(reward);
  await flushAndMount(game);
  return reward;
}

const Rect _stack = Rect.fromLTWH(40, 300, 44, 30);
const Rect _button = Rect.fromLTWH(60, 420, 200, 44);

void main() {
  group('CoinRewardAnimation presets (PRD-home-v3 §5 table)', () {
    test('pack table', () {
      final table = {
        for (final p in [
          IapProduct.coins1000,
          IapProduct.coins10000,
          IapProduct.coins17000,
          IapProduct.coins100000,
        ])
          p: CoinRewardAnimation.pack(p, from: _stack),
      };
      expect(table.values.map((a) => a.amount), [1000, 10000, 17000, 100000]);
      expect(table.values.map((a) => a.coins), [6, 9, 12, 16]);
      expect(table.values.map((a) => a.countDuration), [.9, 1.2, 1.5, 1.9]);
      expect(table.values.map((a) => a.confetti), [40, 70, 100, 150]);
      expect(table.values.map((a) => a.jingle), [
        Sfx.skBuyCommon,
        Sfx.skBuyRare,
        Sfx.skBuyEpic,
        Sfx.skBuyLegendary,
      ]);
      expect(table.values.map((a) => a.flash), [false, false, false, true]);
      expect(table.values.map((a) => a.flyDuration), everyElement(.7));
      expect(table.values.map((a) => a.stagger), everyElement(.055));
      expect(
        () => CoinRewardAnimation.pack(IapProduct.noAds, from: _stack),
        throwsArgumentError,
      );
    });

    test('level reward and No-ads bonus', () {
      final level = CoinRewardAnimation.levelReward(600, 6, from: _button);
      expect(level.amount, 600);
      expect(level.level, 6);
      expect(
        level.coins,
        math.min(14, 5 + (math.log(600) / math.ln10 * 2).round()),
      );
      expect(
        level.countDuration,
        closeTo(.8 + math.log(600) / math.ln10 * .3, 1e-9),
      );
      expect(level.confetti, 40);
      expect(level.jingle, isNull);
      expect(CoinRewardAnimation.levelReward(20000, 10).coins, 14);
      expect(CoinRewardAnimation.levelReward(50, 1).coins, 8);
      final bonus = CoinRewardAnimation.noAdsBonus(from: _button);
      expect(bonus.amount, 1000);
      expect(bonus.coins, 12);
      expect(bonus.countDuration, 1.4);
      expect(bonus.flyDuration, .75);
      final get = CoinRewardAnimation.freeCoins(from: _button);
      expect(get.amount, 40);
      expect(get.coins, 6);
      expect(get.ticks, 0);
      expect(get.confetti, 0);
    });
  });

  group('CoinRewardAnimation in the game', () {
    homeTest(
      '10 000 pack: fly, count-up with ticks and glow, payoff, sounds in order',
      prefs: const {'coins': 1250},
      verify: (game, spy, ads, tester) async {
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        game.coinFlyRandom = math.Random(3);
        var done = 0;
        final reward = await start(
          game,
          CoinRewardAnimation.pack(
            IapProduct.coins10000,
            from: _stack,
            onDone: () => done++,
          ),
        );
        final pill = game.coinPill;
        expect(game.coinFly!.count, 9);
        // Nothing lands for 0.7 s: the pill waits.
        await run(game, .6);
        expect(pill.shownBalance, 1250);
        expect(sounds, isEmpty);
        // First landing: bn_coin, then the count starts with a tick.
        await run(game, .15);
        expect(sounds.take(2), [Sfx.bnCoin, Sfx.skTick]);
        expect(reward.counting, isTrue);
        await run(game, .4);
        expect(pill.glow, isTrue);
        expect(pill.glowLevel, 1);
        expect(pill.label.color, Config.menuGold);
        expect(pill.shownBalance, inExclusiveRange(1250, 11250));
        // End of the count (0.7 + 1.2 s): jingle, pops, confetti, label.
        await run(game, .8);
        expect(reward.countDone, isTrue);
        expect(pill.shownBalance, 11250);
        expect(sounds.last, Sfx.skBuyRare);
        expect(reward.confettiBurst!.count, 70);
        expect(reward.confettiBurst!.isMounted, isTrue);
        await run(game, .1);
        expect(pill.pillScale, greaterThan(1.05));
        expect(pill.coinScale, greaterThan(1.2));
        expect(sounds, isNot(contains(Sfx.skProgress)));
        await run(game, .7);
        expect(sounds.last, Sfx.skProgress);
        expect(done, 1);
        expect(game.coinReward, isNull);
        await run(game, .5);
        expect(pill.glowLevel, 0);
        expect(pill.label.color, Config.menuSoft);
        expect(sounds.where((s) => s == Sfx.bnCoin).length, 9);
        expect(sounds.where((s) => s == Sfx.skTick).length, 17);
        expect(sounds.where((s) => s == Sfx.skProgress).length, 1);
        final jingleAt = sounds.indexOf(Sfx.skBuyRare);
        expect(
          sounds.sublist(0, jingleAt),
          everyElement(isIn([Sfx.bnCoin, Sfx.skTick])),
        );
        // Everything cleans itself up.
        await run(game, 3);
        expect(reward.isMounted, isFalse);
        expect(pill.held, isFalse);
        expect(pill.shownBalance, 11250);
        expect(done, 1);
      },
    );

    homeTest(
      '100 000 pack: white flash, 150 confetti with coins and stars',
      verify: (game, spy, ads, tester) async {
        final reward = await start(
          game,
          CoinRewardAnimation.pack(IapProduct.coins100000, from: _stack),
        );
        await run(game, .7 + 1.9 + .05);
        expect(reward.countDone, isTrue);
        final confetti = reward.confettiBurst!;
        expect(confetti.count, 150);
        expect(confetti.coinCount, greaterThan(0));
        expect(confetti.starCount, greaterThan(0));
        expect(reward.children.whereType<ConfettiBurst>().length, 1);
        expect(
          reward.children.where((c) => c.runtimeType.toString() == '_Flash'),
          hasLength(1),
        );
        await run(game, 4);
        expect(game.coinPill.shownBalance, 100000);
      },
    );

    homeTest(
      'reduce motion: no confetti or flash, the count still runs',
      prefs: const {'coins': 5},
      verify: (game, spy, ads, tester) async {
        game.reduceMotionOverride = true;
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        final reward = await start(
          game,
          CoinRewardAnimation.pack(IapProduct.coins100000, from: _stack),
        );
        await run(game, 1.5);
        expect(game.coinPill.shownBalance, inExclusiveRange(5, 100005));
        await run(game, 1.3);
        expect(reward.countDone, isTrue);
        expect(reward.confettiBurst, isNull);
        expect(
          reward.children.where((c) => c.runtimeType.toString() == '_Flash'),
          isEmpty,
        );
        expect(game.coinPill.shownBalance, 100005);
        await run(game, 1);
        expect(sounds.last, Sfx.skProgress);
        expect(sounds, contains(Sfx.skBuyLegendary));
      },
    );

    homeTest(
      'level reward: coins from CLAIM, +amount, no jingle',
      prefs: const {'coins': 100},
      verify: (game, spy, ads, tester) async {
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        final reward = await start(
          game,
          CoinRewardAnimation.levelReward(1550, 6, from: _button),
        );
        expect(game.coinFly!.count, reward.coins);
        await run(game, .7 + reward.countDuration + .1);
        expect(reward.countDone, isTrue);
        expect(game.coinPill.shownBalance, 1650);
        expect(reward.confettiBurst!.count, 40);
        await run(game, 1);
        expect(sounds.where((s) => s == Sfx.bnCoin).length, reward.coins);
        expect(sounds.where((s) => s == Sfx.skTick).length, 16);
        expect(sounds.last, Sfx.skProgress);
        expect(
          sounds,
          isNot(anyOf(contains(Sfx.skBuyCommon), contains(Sfx.skBuyRare))),
        );
      },
    );

    homeTest(
      'No-ads bonus: 12 coins, 1.4 s count to +1 000',
      verify: (game, spy, ads, tester) async {
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        final reward = await start(
          game,
          CoinRewardAnimation.noAdsBonus(from: _button),
        );
        expect(game.coinFly!.count, 12);
        await run(game, .75 + 1.4 + .1);
        expect(reward.countDone, isTrue);
        expect(game.coinPill.shownBalance, 1000);
        expect(reward.confettiBurst!.count, 50);
        await run(game, 1);
        expect(sounds.where((s) => s == Sfx.skTick).length, 18);
        expect(sounds.last, Sfx.skProgress);
        expect(reward.finished, isTrue);
      },
    );

    homeTest(
      'GET (Shop free coins) runs the freeCoins preset: still +40, no ticks',
      prefs: const {'coins': 1250},
      verify: (game, spy, ads, tester) async {
        await openShop(game);
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        await game.claimFreeCoins();
        await flushAndMount(game);
        final reward = game.coinReward!;
        expect(reward.amount, 40);
        expect(reward.ticks, 0);
        expect(game.coinFly!.count, 6);
        await run(game, 2);
        expect(game.coinPill.shownBalance, 1290);
        expect(game.menu.wallet.balance, 1290);
        expect(sounds, [Sfx.bnAdBtn, Sfx.bnCoin, Sfx.skProgress]);
        expect(reward.confettiBurst, isNull);
        expect(game.coinReward, isNull);
      },
    );

    homeTest(
      'removed mid-flight: pill released, glow off, onDone once',
      prefs: const {'coins': 10},
      verify: (game, spy, ads, tester) async {
        var done = 0;
        final reward = await start(
          game,
          CoinRewardAnimation.pack(
            IapProduct.coins1000,
            from: _stack,
            onDone: () => done++,
          ),
        );
        await run(game, .8);
        expect(game.coinPill.glow, isTrue);
        reward.removeFromParent();
        await run(game, 1);
        expect(done, 1);
        expect(game.coinPill.glow, isFalse);
        expect(game.coinPill.held, isFalse);
        expect(game.coinPill.shownBalance, 1010);
      },
    );
  });

  group('ConfettiBurst', () {
    test('burst: count, every 7th a coin, stars only when asked', () {
      final plain = ConfettiBurst.burst(
        origin: Offset.zero,
        count: 70,
        random: math.Random(1),
      );
      expect(plain.count, 70);
      expect(plain.coinCount, 10);
      expect(plain.starCount, 0);
      final big = ConfettiBurst.burst(
        origin: Offset.zero,
        count: 100,
        stars: true,
        random: math.Random(1),
      );
      expect(big.coinCount, 15);
      expect(big.starCount, greaterThan(0));
      expect(big.life, ConfettiBurst.burstLife);
    });

    test('rain mode lives 3.6 s', () {
      final rain = ConfettiBurst.rain(count: 90, random: math.Random(2));
      expect(rain.rain, isTrue);
      expect(rain.life, 3.6);
      expect(rain.coinCount, greaterThan(0));
      expect(rain.starCount, greaterThan(0));
      for (var i = 0; i < 200; i++) {
        rain.update(1 / 60);
      }
      expect(rain.elapsed, closeTo(200 / 60, 1e-9));
    });
  });
}
