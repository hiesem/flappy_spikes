import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/run/config/bonus_config.dart';
import 'package:flappy_spikes/run/config/revive_config.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/screens/bonus_screen.dart';
import 'package:flappy_spikes/run/screens/revive_ladder.dart';
import 'package:flappy_spikes/run/screens/revive_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §7.7 the NO ADS table row by row (banner, video ad after the
/// run, revive, Shop free coins, home slot, balloon bonus) and the
/// `ReviveOfferKind.free` ladder; §7.8 the bonus "▶ feather ×3" offer that
/// always appears and waits up to 5 s for its ad.
void main() {
  // ------------------------------------------------------------ the ladder
  group('§7.7 revive ladder for NO ADS owners', () {
    RunState fresh() => RunState(seed: 1, viewHeight: 711);

    test('1st offer of a game is free even with no ad loaded; then 250, 500; '
        'a new game gives a free one again', () {
      final s = fresh();
      final seen = <String>[];
      for (var i = 0; i < 4; i++) {
        final o = ReviveLadder.offer(s, adReady: false, noAds: true);
        seen.add(o.toString());
        ReviveLadder.record(s, o);
      }
      expect(seen, ['free', '250', '500', '1000']);
      // With an ad loaded: still free (regardless of ad availability).
      expect(
        ReviveLadder.offer(fresh(), adReady: true, noAds: true),
        const ReviveOffer.free(),
      );
      final free = ReviveLadder.offer(fresh(), adReady: true, noAds: true);
      expect(free.kind, ReviveOfferKind.free);
      expect(free.price, 0);
      expect(free.noAdLabel, isFalse);
      expect(free.isFree, isTrue);
      expect(free.isAd, isFalse);
      expect(free.isCoins, isFalse);
    });

    test('record(free) uses up the step like an ad; the coin price is not '
        'raised', () {
      final s = fresh();
      ReviveLadder.record(s, const ReviveOffer.free());
      expect(s.adStepAvailableThisGame, isFalse);
      expect(s.coinRevives, 0);
      expect(ReviveLadder.offer(s, adReady: true, noAds: true).price, 250);
    });

    test('normal players unchanged: ad, or NO AD AVAILABLE + 250', () {
      expect(ReviveLadder.offer(fresh(), adReady: true).isAd, isTrue);
      expect(
        ReviveLadder.offer(fresh(), adReady: false),
        const ReviveOffer.coins(250, noAdLabel: true),
      );
      expect(ReviveKind.values, contains(ReviveKind.free));
    });
  });

  // ------------------------------------------------------------ in game
  final spy = AnalyticsSpy();

  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
    Monetization? monetization,
    double h = 711,
  }) => FlameTester<FlappySpikesGame>(
    () {
      spy.events.clear();
      return createRunTestGame(
        prefs: prefs,
        services: spy,
        worldHeight: h,
        monetization: monetization,
      );
    },
    gameSize: Vector2(320, h),
  );

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
  }

  /// A death with ≥ 6 hoops: the revive offer, faded in.
  Future<(RunController, ReviveScreen)> toOffer(FlappySpikesGame g) async {
    final run = g.run ?? await startRun(g);
    run.state.invulnerable = 0;
    for (var i = 0; i < 6; i++) {
      run.debugPass(perfect: true);
    }
    killRunThroughSaves(g);
    for (var i = 0; i < 600 && g.state == GameState.dying; i++) {
      g.update(1 / 60);
    }
    await flushAndMount(g);
    expect(g.state, GameState.reviving);
    final screen = g.reviveScreen!;
    for (var i = 0; i < 30 && screen.ui < 1; i++) {
      g.update(1 / 60);
    }
    return (run, screen);
  }

  Future<void> throughPhoenix(FlappySpikesGame g) async {
    for (var i = 0; i < 400 && g.state == GameState.reviving; i++) {
      g.update(1 / 60);
      if (i % 10 == 0) await flushAndMount(g);
    }
  }

  tester(
    prefs: {'noAds': true},
    monetization: Monetization(
      ads: FakeRewardedAds()..mode = FakeAdMode.unavailable,
    ),
  ).testGameWidget(
    '§7.7 revive row: a NO ADS owner\'s 1st revive of the game is FREE (no '
    'ad, even with none loaded): pink heart, REVIVE, no label / price; '
    'straight to the phoenix; then 250',
    setUp: boot,
    verify: (g, _) async {
      final ads = g.monetization.ads as FakeRewardedAds;
      final (run, screen) = await toOffer(g);
      final balance = g.menu.wallet.balance;
      expect(screen.offer, const ReviveOffer.free());
      expect(screen.locked, isFalse, reason: 'free never locks');
      expect(
        spy.events.where((e) => e.$1 == 'revive_offered').single.$2,
        {'offer': 'free', 'price': 0, 'revive_index': 1},
      );
      final phoenix = <RevivePhoenixStarted>[];
      run.events.on<RevivePhoenixStarted>(phoenix.add);
      screen.tapHeart();
      expect(screen.phase, RevivePhase.paying, reason: 'no ad phase');
      await throughPhoenix(g);
      expect(g.state, GameState.playing);
      expect(ads.shown, 0);
      expect(g.menu.wallet.balance, balance, reason: 'price 0');
      expect(phoenix.single.kind, ReviveKind.free);
      expect(phoenix.single.price, 0);
      expect(
        spy.events.where((e) => e.$1 == 'revive_free_used').single.$2,
        {'revive_index': 1},
      );
      expect(spy.events.map((e) => e.$1), isNot(contains('revive_ad_started')));
      // The 2nd death of the game: 250 coins.
      await stepSeconds(g, ReviveConfig.invulnerable + .1);
      final (_, second) = await toOffer(g);
      expect(second.offer.isCoins, isTrue);
      expect(second.offer.price, 250);
      expect(second.offer.noAdLabel, isFalse);
    },
  );

  tester(prefs: {'gamesPlayed': 5, 'noAds': true}).testGameWidget(
    '§7.7 banner + video ad rows: NO ADS owners get neither (no strip, no '
    'resize, the interstitial skipped as no_ads)',
    setUp: boot,
    verify: (g, _) async {
      await startRun(g);
      expect(g.bannerState.value, BannerState.off);
      expect(g.runHasBanner, isFalse);
      expect(g.bottomStripInset, 44);
      killRunThroughSaves(g);
      await declineRevive(g);
      await flushAndMount(g);
      expect(g.interstitialSkipReason()?.analyticsName, 'no_ads');
    },
  );

  tester(prefs: {'noAds': true}).testGameWidget(
    '§7.7 Shop free coins row: NO ADS owners watch the ad like everyone',
    setUp: boot,
    verify: (g, _) async {
      final ads = g.monetization.ads as FakeRewardedAds;
      g.openShop();
      await stepSeconds(g, .6);
      await g.claimFreeCoins();
      await flushAndMount(g);
      expect(ads.placements, [AdPlacement.shopFreeCoins]);
      expect(
        spy.events.where((e) => e.$1 == 'ad_rewarded_shown').single.$2,
        {'placement': 'shop_free_coins'},
      );
      expect(g.shopScreen!.freeCoins.chipText, isNot('CLAIM'));
    },
  );

  tester(prefs: {'noAds': true}).testGameWidget(
    '§7.7 home power-up slot row: unchanged, free for NO ADS owners',
    setUp: boot,
    verify: (g, _) async {
      final ads = g.monetization.ads as FakeRewardedAds;
      await g.tapPowerupSlot();
      await flushAndMount(g);
      expect(ads.shown, 0);
      expect(g.run, isNotNull);
    },
  );

  // ------------------------------------------------------------ the bonus
  /// Pops three balloons and waits only until the offer is up.
  Future<BonusScreen> toBonusOffer(FlappySpikesGame g) async {
    await startRun(g);
    killRunThroughSaves(g);
    await flushAndMount(g);
    expect(g.state, GameState.bonus);
    final b = g.bonusScreen!;
    await stepSeconds(g, .2);
    for (final i in [0, 1, 2]) {
      expect(b.tapTile(i), isTrue);
      await stepSeconds(g, BonusConfig.busy + .05);
    }
    for (var i = 0; i < 240 && b.phase == BonusPhase.pick; i++) {
      g.update(1 / 60);
    }
    expect(b.phase, BonusPhase.offer);
    return b;
  }

  Map<String, Object>? offerShown() =>
      spy.events.where((e) => e.$1 == 'bonus_offer_shown').singleOrNull?.$2;

  tester(prefs: {'feathers': 3, 'noAds': true}).testGameWidget(
    '§7.7 balloon bonus row: NO ADS owners get the ▶ ad offer (never a free '
    'refill); watching refills 3 feathers for 3 more pops, once',
    setUp: boot,
    verify: (g, _) async {
      final ads = g.monetization.ads as FakeRewardedAds;
      final b = await toBonusOffer(g);
      expect(b.offer, BonusOffer.ad);
      expect(b.adWaiting, isFalse);
      expect(offerShown(), {'wait_ms': 0, 'outcome': 'ad'});
      await b.tapOffer();
      expect(ads.placements, [AdPlacement.bonusFeathers]);
      await stepSeconds(g, 1.5);
      expect(b.feathers, 3);
      for (final i in [3, 4, 5]) {
        expect(b.tapTile(i), isTrue);
        await stepSeconds(g, BonusConfig.busy + .05);
      }
      await stepSeconds(g, 2);
      expect(b.pops, 6);
      expect(b.phase, BonusPhase.done, reason: 'once per screen');
    },
  );

  tester(
    prefs: {'feathers': 3},
    monetization: Monetization(
      ads: FakeRewardedAds()..mode = FakeAdMode.unavailable,
    ),
  ).testGameWidget(
    '§7.8 no ad ready: the offer still appears in its loading state, asks '
    'for a load, and turns active when the ad arrives within 5 s',
    setUp: boot,
    verify: (g, _) async {
      final ads = g.monetization.ads as FakeRewardedAds;
      final b = await toBonusOffer(g);
      expect(b.offer, BonusOffer.ad);
      expect(b.adWaiting, isTrue);
      expect(ads.loadRequests, 1, reason: 'ensureLoaded asked at once');
      await b.tapOffer();
      expect(b.phase, BonusPhase.offer, reason: 'no taps while loading');
      expect(ads.placements, isEmpty);
      await stepSeconds(g, 2);
      expect(b.adWaiting, isTrue);
      ads.mode = FakeAdMode.succeed; // the load lands
      await stepSeconds(g, .1);
      expect(b.adWaiting, isFalse);
      final shown = offerShown()!;
      expect(shown['outcome'], 'ad');
      expect(shown['wait_ms'] as int, inInclusiveRange(1900, 2300));
      await b.tapOffer();
      expect(ads.placements, [AdPlacement.bonusFeathers]);
      await stepSeconds(g, 1.5);
      expect(b.feathers, 3);
    },
  );

  tester(
    prefs: {'feathers': 3},
    monetization: Monetization(
      ads: FakeRewardedAds()..mode = FakeAdMode.unavailable,
    ),
  ).testGameWidget(
    '§7.8 no ad within 5 s: the offer fades out and NEXT is shown',
    setUp: boot,
    verify: (g, _) async {
      final b = await toBonusOffer(g);
      await stepSeconds(g, 4.8);
      expect(b.phase, BonusPhase.offer);
      expect(b.adWaiting, isTrue);
      await stepSeconds(g, .3);
      expect(b.adWaiting, isFalse);
      expect(offerShown()!['outcome'], 'timeout');
      expect(offerShown()!['wait_ms'] as int, inInclusiveRange(4950, 5100));
      await stepSeconds(g, BonusConfig.adWaitFadeOut + .05);
      expect(b.phase, BonusPhase.done);
      await stepSeconds(g, .5);
      expect(b.nextShown, isTrue);
      b.tapNext();
      await flushAndMount(g);
      expect(g.state, GameState.results);
    },
  );

  tester(
    prefs: {'feathers': 3},
    monetization: Monetization(consent: FakeAdsConsent(canRequestAds: false)),
  ).testGameWidget(
    '§7.8 ads impossible (no consent / iOS / Test Lab): no offer, NEXT',
    setUp: boot,
    verify: (g, _) async {
      await startRun(g);
      killRunThroughSaves(g);
      await flushAndMount(g);
      final b = g.bonusScreen!;
      await stepSeconds(g, .2);
      for (final i in [0, 1, 2]) {
        b.tapTile(i);
        await stepSeconds(g, BonusConfig.busy + .05);
      }
      await stepSeconds(g, 2);
      expect(b.offer, BonusOffer.none);
      expect(b.phase, BonusPhase.done);
    },
  );
}
