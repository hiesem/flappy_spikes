import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/menu/free_coins_policy.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/bonus_config.dart';
import 'package:flappy_spikes/run/config/capsule_config.dart';
import 'package:flappy_spikes/run/config/jar_config.dart';
import 'package:flappy_spikes/run/config/pair_config.dart';
import 'package:flappy_spikes/run/config/piggy_config.dart';
import 'package:flappy_spikes/run/config/revive_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/special_hoops_config.dart';
import 'package:flappy_spikes/run/config/star_trail_config.dart';
import 'package:flappy_spikes/run/config/switch_config.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/scoring.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/screens/revive_ladder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PRD-2.3 §14.2 coins and §14.3 scoring (pure parts; the in-run paths are
/// covered by the rewritten 2.2 tests: s11_perfect_zone, s3_27_egg, …).
void main() {
  tearDown(() => TuningValues.current = TuningValues.defaults());

  group('§14.2 each item pays its new coin value', () {
    test('the table', () {
      expect(ScoringFeature.coinsFor(perfect: false), 1);
      expect(ScoringFeature.coinsFor(perfect: true), 2);
      expect(PiggyConfig.total, 20);
      expect(PiggyConfig.payoutFor(20), 10, reason: 'max 10');
      expect(PiggyConfig.payoutFor(19), 9);
      expect(PiggyConfig.payoutFor(1), 0);
      expect(JarConfig.reward, 8);
      expect(JarConfig.fullSub, '20 fireflies · +8 coins');
      expect(RunConfig.luckySpinSlices, [1, 2, 3, 5, 1, 2]);
      expect(StarTrailConfig.reward, 2);
      expect(StarTrailConfig.bannerSub, '8 / 8 stars · +2 coins');
      expect(BullseyeConfig.coins, 3); // PRD-2.3.1 §6 (was 2)
      expect(TrainConfig.comboCoins, 1);
      expect(TrainConfig.bannerSub, 'all three rings · +1 coin');
      expect(SwitchConfig.coins, 0);
      expect(PairConfig.coins, 3);
      expect(PairConfig.style(PairReward.coins).tag, '+3 COINS');
      expect(PairConfig.style(PairReward.coins).word, '+3 COINS');
      expect(CapsuleConfig.frenzyCoins, 1);
      expect(VersusConfig.winBonus, 10);
      expect(VersusConfig.drawBonus, 5);
      expect(FreeCoinsPolicy.reward, 75); // PRD-2.3.1 §5 (was 40)
      expect(FreeCoinsPolicy.maxPerDay, 5);
      expect(FreeCoinsPolicy.cooldown, const Duration(minutes: 5));
    });

    test('a lucky spin slice is one of the six new values', () {
      final seen = <int>{};
      for (var seed = 1; seed <= 200; seed++) {
        final all = ElementId.values.toSet();
        final d = RunDirector(
          seed: seed,
          enabled: all,
          met: all,
          forced: [ElementId.luckySpin],
          startHoopIndex: 20,
        );
        final s = d.nextSlot(DirectorContext.open(711));
        expect(s.kind, HoopKindId.luckySpin);
        final prize = s.extra! as SpinPrize;
        expect(prize.coins, RunConfig.luckySpinSlices[prize.slice]);
        seen.add(prize.coins);
      }
      expect(seen, {1, 2, 3, 5});
    });

    test('balloon prizes are the new set (525, jackpot 150)', () {
      expect(BonusConfig.prizes, [25, 25, 25, 50, 50, 50, 75, 75, 150]);
      expect(BonusConfig.prizes.fold<int>(0, (a, b) => a + b), 525);
      expect(BonusConfig.jackpot, 150);
    });

    test('the puzzle reward is 50–150 in steps of 5', () {
      final all = ElementId.values.toSet();
      final d = RunDirector(seed: 3, enabled: all, met: all);
      final seen = <int>{};
      for (var k = 0; k < 2000; k++) {
        final b = d.rollPuzzleBonus();
        expect(b, inInclusiveRange(50, 150));
        expect(b % 5, 0);
        seen.add(b);
      }
      expect(seen.length, 21);
    });

    test('the revive ladder is 250…8000, and no revive is offered after 6 '
        'paid', () {
      expect(ReviveConfig.coinLadder, [250, 500, 1000, 2000, 4000, 8000]);
      expect(ReviveConfig.minHoops, 6);
      final s = RunState(seed: 1, viewHeight: 711)..hoopsPassed = 30;
      // The ad revive first.
      expect(ReviveLadder.eligible(s), isTrue);
      final ad = ReviveLadder.offer(s, adReady: true);
      expect(ad.isAd, isTrue);
      ReviveLadder.record(s, ad);
      final prices = <int>[];
      while (ReviveLadder.eligible(s)) {
        final o = ReviveLadder.offer(s, adReady: true);
        expect(o.isCoins, isTrue);
        prices.add(o.price);
        ReviveLadder.record(s, o);
      }
      expect(prices, [250, 500, 1000, 2000, 4000, 8000]);
      expect(s.coinRevives, 6);
      expect(ReviveLadder.eligible(s), isFalse);
      // Under 6 hoops: no offer, as before.
      final short = RunState(seed: 1, viewHeight: 711)..hoopsPassed = 5;
      expect(ReviveLadder.eligible(short), isFalse);
    });

    test('the level ladder is unchanged (10,350 in all)', () {
      expect([for (final l in kLevels) l.reward], [
        50, 100, 150, 250, 400, 600, 800, 1000, 2000, 5000, //
      ]);
      expect(kLevels.fold<int>(0, (a, l) => a + l.reward), kLevelRewardTotal);
      expect(kLevelRewardTotal, 10350);
    });

    test('tuning: a remote value reaches the getter (coin_jar, '
        'revive_ladder, level_rewards)', () {
      TuningValues.current = TuningValues.resolve({
        'coin_jar': '11',
        'revive_ladder': '[100,200]',
        'level_rewards': '[1,2,3,4,5,6,7,8,9,10]',
      });
      expect(JarConfig.reward, 11);
      expect(ReviveConfig.coinLadder, [100, 200]);
      expect(ReviveLadder.coinPrice(5), 200);
      expect(kLevels.first.reward, 1);
      expect(kLevels.last.reward, 10);
    });
  });

  group('§14.3 scoring', () {
    test('points: 1 for a pass, max(2, streak) for a perfect, no streak '
        'cap', () {
      expect(ScoringFeature.pointsFor(perfect: false, streak: 0), 1);
      expect(ScoringFeature.pointsFor(perfect: true, streak: 1), 2);
      expect(ScoringFeature.pointsFor(perfect: true, streak: 9), 9);
      expect(ScoringFeature.pointsFor(perfect: true, streak: 75), 75);
    });

    test('the chick adds +1 per hoop (0 without it)', () {
      final s = RunState(seed: 1, viewHeight: 711);
      expect(ScoringFeature.chickBonus(s), 0);
      s.egg = EggState();
      expect(ScoringFeature.chickBonus(s), 0, reason: 'still an egg');
      s.egg!.stage = EggStage.chick;
      expect(ScoringFeature.chickBonus(s), 1);
    });
  });

  group('§14.8 coins_spent', () {
    test('Wallet.spend reports amount and reason (skin / revive)', () async {
      SharedPreferences.setMockInitialValues({'coins': 1000});
      final storage = GameStorage();
      await storage.load();
      final spent = <(int, String)>[];
      final w = Wallet(storage, onSpent: (a, r) => spent.add((a, r)));
      expect(await w.spend(250, 'revive'), isTrue);
      expect(await w.spend(100, 'item:hat:crown'), isTrue);
      expect(await w.spend(5000, 'revive'), isFalse);
      expect(await w.spend(0, 'revive'), isTrue);
      expect(spent, [(250, 'revive'), (100, 'skin')]);
      expect(Wallet.spendReason('item:bird:golden'), 'skin');
    });
  });
}
