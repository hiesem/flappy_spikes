import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/bonus_config.dart';
import 'package:flappy_spikes/run/screens/bonus_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// PRD-2 §3.15 / §5.14 the balloon bonus screen: shown after the run with
/// 3 feathers (between the revive offer and the results), the feathers go
/// back to 0 as it opens, 9 shuffled prizes, a wallet credit per pop, the
/// once-per-screen ad offer (▶ feather ×3, NO THANKS after 3 s), NEXT after
/// 6 pops, no reveal of unpopped balloons, YOUR REWARD without it.
void main() {
  group('§3.15 bonus rules (pure)', () {
    // PRD-2.3 §14.2: the 2.2 set [25,25,50,50,75,75,100,150,250] became
    // [25,25,25,50,50,50,75,75,150], jackpot 150.
    test(
      '§3.15 / 2.3 §14.2 prizes 25, 25, 25, 50, 50, 50, 75, 75, 150 shuffled',
      () {
        expect(BonusConfig.prizes, [25, 25, 25, 50, 50, 50, 75, 75, 150]);
        expect(BonusConfig.jackpot, 150);
        final a = BonusRules.shuffledPrizes(math.Random(1));
        final b = BonusRules.shuffledPrizes(math.Random(2));
        expect(List.of(a)..sort(), BonusConfig.prizes);
        expect(List.of(b)..sort(), BonusConfig.prizes);
        expect(a, isNot(equals(b)));
      },
    );

    test('§5.14 3–8 coins fly per prize and add up to it', () {
      expect(BonusRules.coinsFor(25), 3);
      expect(BonusRules.coinsFor(100), 5);
      expect(BonusRules.coinsFor(250), 8);
      for (final p in BonusConfig.prizes) {
        final split = BonusRules.coinSplit(p);
        expect(split.length, inInclusiveRange(3, 8));
        expect(split.fold<int>(0, (s, v) => s + v), p);
      }
    });

    test('§3.15 / PRD-2.2 §7.7–§7.8 the offer: once, always when ads are '
        'possible (no free variant), none when ads are impossible', () {
      expect(
        BonusRules.offerFor(adUsed: false, adsPossible: true),
        BonusOffer.ad,
      );
      expect(
        BonusRules.offerFor(adUsed: false, adsPossible: false),
        BonusOffer.none,
      );
      expect(
        BonusRules.offerFor(adUsed: true, adsPossible: true),
        BonusOffer.none,
      );
      expect(BonusOffer.values, [BonusOffer.none, BonusOffer.ad]);
    });

    test('§5.14 layout: 1:1 at 711, fits between the strips at 568', () {
      final (k711, o711) = BonusRules.layoutFor(711);
      expect(k711, 1);
      expect(o711, Offset.zero);
      expect(BonusRules.bandShiftFor(711), 0);
      final (k568, o568) = BonusRules.layoutFor(568);
      // S6-63: the column above the bottom band scales into what the
      // unscaled, bottom-anchored band leaves (568 − 159 − 44 of 552 − 44).
      expect(k568, closeTo(365 / 508, 1e-9));
      final band = BonusRules.bandShiftFor(568);
      // NO THANKS (y 641, unscaled band) stays above the bottom strip.
      expect(651 + band, lessThan(568 - 44));
      expect(o568.dy + 52 * k568, greaterThan(44));
      // The scaled column meets the band without overlapping it.
      expect(
        o568.dy + BonusConfig.bandTop * k568,
        closeTo(BonusConfig.bandTop + band, 1e-9),
      );
      expect(BonusRules.tileRect(0), const Rect.fromLTWH(22, 230, 88, 88));
      expect(BonusRules.tileRect(8), const Rect.fromLTWH(210, 418, 88, 88));
      expect(BonusRules.rowSlot(2), const Offset(208, 588));
    });

    test('§5.14 geometry knobs', () {
      expect(BonusConfig.pill, const Rect.fromLTWH(204, 52, 102, 38));
      expect(BonusConfig.hero, const Offset(160, 146));
      expect(BonusConfig.heroRadius, 42);
      expect(BonusConfig.panel, const Rect.fromLTRB(14, 222, 306, 522));
      expect(BonusConfig.adButton, const Rect.fromLTRB(50, 562, 270, 612));
      expect(BonusConfig.nextButton, const Rect.fromLTRB(14, 562, 306, 612));
      expect(BonusConfig.promptY, 541);
      expect(BonusConfig.noThanksY, 641);
      expect(BonusConfig.noThanksDelay, 3);
      expect(BonusConfig.featherFly, .42);
      expect(BonusConfig.popAt, .32);
      expect(BonusConfig.cardAt, .6);
      expect(BonusConfig.busy, closeTo(1.12, 1e-9));
      expect(BonusConfig.refillFly, .5);
      expect(BonusConfig.refillGap, .22);
    });
  });

  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
    Monetization? monetization,
  }) {
    return FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {'feathers': 3, ...prefs},
        services: AnalyticsSpy(),
        monetization: monetization,
      ),
      gameSize: Vector2(320, 568),
    );
  }

  Future<BonusScreen> openBonus(FlappySpikesGame g) async {
    await startRun(g);
    killRun(g);
    await flushAndMount(g);
    expect(g.state, GameState.bonus);
    final b = g.bonusScreen!;
    await stepSeconds(g, .2);
    return b;
  }

  Future<void> popThree(FlappySpikesGame g, BonusScreen b, List<int> tiles) async {
    for (final i in tiles) {
      expect(b.tapTile(i), isTrue, reason: 'tile $i');
      await stepSeconds(g, BonusConfig.busy + .05);
    }
    await stepSeconds(g, 3);
  }

  tester().testGameWidget(
    '§3.15 opens after the run with 3 feathers; feathers back to 0; '
    'a pop credits its prize at once; taps ignored while a balloon opens',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final b = await openBonus(g);
      expect(g.storage.feathers, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('feathers'), 0);
      expect(analyticsLog(g.services as AnalyticsSpy).map((e) => e.$1), contains('bonus_shown'));
      expect(List.of(b.prizes)..sort(), BonusConfig.prizes);
      final before = g.menu.wallet.balance;
      expect(b.tapTile(4), isTrue);
      expect(g.menu.wallet.balance, before + b.prizes[4]);
      expect(b.feathers, 2);
      // §3.15 taps are ignored while the balloon opens (≈ 1.1 s).
      expect(b.tapTile(0), isFalse);
      await stepSeconds(g, .5);
      expect(b.tapTile(0), isFalse);
      expect(b.isRevealed(4), isFalse);
      await stepSeconds(g, .7);
      expect(b.isRevealed(4), isTrue);
      expect(b.tapTile(4), isFalse, reason: 'already popped');
      expect(b.tapTile(0), isTrue);
      final pop = analyticsLog(g.services as AnalyticsSpy).where((e) => e.$1 == 'bonus_pop').toList();
      expect(pop.length, 2);
      expect(pop.first.$2, {'prize': b.prizes[4], 'pop': 1});
      expect(pop.last.$2, {'prize': b.prizes[0], 'pop': 2});
    },
  );

  tester().testGameWidget(
    '§3.15 out of feathers: ad offer alone, NO THANKS after 3 s → results; '
    'unpopped balloons never revealed; YOUR REWARD excludes the bonus',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final b = await openBonus(g);
      final runCoins = g.run!.state.coinsThisRun;
      await popThree(g, b, [0, 1, 2]);
      expect(b.phase, BonusPhase.offer);
      expect(b.offer, BonusOffer.ad);
      expect(analyticsLog(g.services as AnalyticsSpy).map((e) => e.$1), contains('bonus_ad_offered'));
      expect(b.noThanksShown, isFalse);
      b.tapNoThanks();
      expect(g.state, GameState.bonus);
      await stepSeconds(g, 3.1);
      expect(b.noThanksShown, isTrue);
      b.tapNoThanks();
      await flushAndMount(g);
      expect(g.state, GameState.results);
      expect(g.resultsScreen, isNotNull);
      expect(g.resultsScreen!.summary.coins, runCoins);
      for (var i = 3; i < 9; i++) {
        expect(b.isRevealed(i), isFalse);
      }
      expect(
        analyticsLog(g.services as AnalyticsSpy).where((e) => e.$1 == 'bonus_declined').single.$2,
        {'pops': 3},
      );
      expect(b.credited, b.prizes[0] + b.prizes[1] + b.prizes[2]);
      await stepSeconds(g, 1);
      expect(g.bonusScreen, isNull);
      expect(b.isMounted, isFalse);
    },
  );

  tester().testGameWidget(
    '§3.15 the ad gives 3 more feathers once; after 6 pops only NEXT',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final ads = g.monetization.ads as FakeRewardedAds;
      final b = await openBonus(g);
      final start = g.menu.wallet.balance;
      await popThree(g, b, [0, 4, 8]);
      expect(b.phase, BonusPhase.offer);
      final ad = b.tapOffer();
      for (var i = 0; i < 20 && b.phase != BonusPhase.pick; i++) {
        await flushAndMount(g);
      }
      await ad;
      expect(ads.placements, [AdPlacement.bonusFeathers]);
      expect(
        analyticsLog(g.services as AnalyticsSpy).map((e) => e.$1),
        containsAll(['bonus_ad_completed', 'ad_rewarded_shown']),
      );
      expect(b.phase, BonusPhase.pick);
      await stepSeconds(g, 1.3);
      expect(b.feathers, 3);
      await popThree(g, b, [1, 2, 3]);
      expect(b.pops, 6);
      expect(b.phase, BonusPhase.done);
      expect(ads.placements.length, 1);
      expect(
        g.menu.wallet.balance,
        start + [0, 4, 8, 1, 2, 3].fold<int>(0, (s, i) => s + b.prizes[i]),
      );
      expect(b.shown, b.credited);
      expect(b.nextShown, isTrue);
      b.tapNext();
      await flushAndMount(g);
      expect(g.state, GameState.results);
      expect(g.resultsScreen, isNotNull);
    },
  );

  tester(
    monetization: Monetization(
      ads: FakeRewardedAds()..mode = FakeAdMode.unavailable,
    ),
  ).testGameWidget(
    '§3.15 / PRD-2.2 §7.8 no rewarded ad loaded: the offer still appears, '
    'waits 5 s, then fades out to NEXT',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final b = await openBonus(g);
      await popThree(g, b, [3, 4, 5]);
      expect(b.phase, BonusPhase.offer);
      expect(b.adWaiting, isTrue);
      await stepSeconds(g, 5.5);
      expect(b.phase, BonusPhase.done);
      expect(
        analyticsLog(g.services as AnalyticsSpy).where((e) => e.$1 == 'bonus_offer_shown').single.$2!['outcome'],
        'timeout',
      );
      await stepSeconds(g, 1);
      b.tapNext();
      await flushAndMount(g);
      expect(g.state, GameState.results);
    },
  );

  tester(prefs: {'noAds': true}).testGameWidget(
    '§3.15 / PRD-2.2 §7.7 no-ads owners watch the ad like everyone (once); '
    'never a free refill',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final ads = g.monetization.ads as FakeRewardedAds;
      final b = await openBonus(g);
      await popThree(g, b, [6, 7, 8]);
      expect(b.phase, BonusPhase.offer);
      expect(b.offer, BonusOffer.ad);
      await b.tapOffer();
      expect(ads.shown, 1);
      expect(ads.placements.single, AdPlacement.bonusFeathers);
      await stepSeconds(g, 1.3);
      expect(b.feathers, 3);
      await popThree(g, b, [0, 1, 2]);
      expect(b.phase, BonusPhase.done);
    },
  );

  tester(prefs: {'feathers': 2}).testGameWidget(
    '§3.15 fewer than 3 feathers: no bonus, straight to the results',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      await startRun(g);
      killRun(g);
      await flushAndMount(g);
      expect(g.state, GameState.results);
      expect(g.bonusScreen, isNull);
      expect(g.storage.feathers, 2);
    },
  );

  tester().testGameWidget(
    '§3.15 / §4 order: revive offer declined → bonus → results',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final run = await startRun(g);
      for (var i = 0; i < 8; i++) {
        run.debugPass(perfect: true);
      }
      killRun(g);
      await flushAndMount(g);
      expect(g.state, GameState.reviving);
      expect(g.storage.feathers, 3, reason: 'not before the bonus opens');
      await declineRevive(g);
      expect(g.state, GameState.bonus);
      expect(g.storage.feathers, 0);
      final b = g.bonusScreen!;
      await popThree(g, b, [0, 1, 2]);
      await stepSeconds(g, 3.1);
      b.tapNoThanks();
      await flushAndMount(g);
      expect(g.state, GameState.results);
      expect(g.resultsScreen, isNotNull);
      await stepSeconds(g, 1);
      g.resultsScreen!.next();
      await stepSeconds(g, 1);
      expect(g.state, GameState.start);
    },
  );
}
