// PRD-2.3.1 §14: no free revive for NO ADS owners. Their ladder starts at
// the first coin step (250 … 8 000, at most 6 revives), with no
// "NO AD AVAILABLE" label; everyone else is unchanged; `revive_free_used`
// is never logged.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/revive_config.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/screens/revive_ladder.dart';
import 'package:flappy_spikes/run/screens/revive_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  RunState fresh() => RunState(seed: 1, viewHeight: 711);

  group('PRD-2.3.1 §14 the ladder (pure)', () {
    for (final adReady in [true, false]) {
      test('§14.2 NO ADS owner (ad ${adReady ? 'loaded' : 'not loaded'}): '
          '250, 500, 1 000, 2 000, 4 000, 8 000 without a label, then no '
          'further offer', () {
        final s = fresh()..hoopsPassed = 10;
        final seen = <ReviveOffer>[];
        while (ReviveLadder.eligible(s)) {
          final o = ReviveLadder.offer(s, adReady: adReady, noAds: true);
          seen.add(o);
          ReviveLadder.record(s, o);
          expect(seen.length, lessThanOrEqualTo(10));
        }
        expect(seen, [
          for (final p in [250, 500, 1000, 2000, 4000, 8000])
            ReviveOffer.coins(p),
        ]);
        expect(seen.every((o) => o.isCoins && !o.noAdLabel), isTrue);
        expect(ReviveLadder.exhausted(s), isTrue);
      });
    }

    test('§14.2 non-owner unchanged: ad, then 250 … 8 000 (7 revives)', () {
      final s = fresh()..hoopsPassed = 10;
      final seen = <String>[];
      while (ReviveLadder.eligible(s)) {
        final o = ReviveLadder.offer(s, adReady: true);
        seen.add(o.toString());
        ReviveLadder.record(s, o);
      }
      expect(seen, ['ad', '250', '500', '1000', '2000', '4000', '8000']);
    });

    test('§14.2 non-owner, no ad available: the "NO AD AVAILABLE" path is '
        'unchanged (label on the 250 heart only)', () {
      final s = fresh()..hoopsPassed = 10;
      final first = ReviveLadder.offer(s, adReady: false);
      expect(first, const ReviveOffer.coins(250, noAdLabel: true));
      ReviveLadder.record(s, first);
      // The ad step never comes back in this game, even with an ad loaded.
      expect(
        ReviveLadder.offer(s, adReady: true),
        const ReviveOffer.coins(500),
      );
    });

    test('§14.1 the showcase free offer exists, but not for NO ADS owners', () {
      expect(ReviveOfferKind.values, [
        ReviveOfferKind.ad,
        ReviveOfferKind.coins,
        ReviveOfferKind.free,
      ]);
      expect(ReviveKind.values, [ReviveKind.ad, ReviveKind.coins]);
    });

    test('§14 the 6-hoop minimum is unchanged', () {
      final s = fresh()..hoopsPassed = ReviveConfig.minHoops - 1;
      expect(ReviveLadder.eligible(s), isFalse);
      s.hoopsPassed = ReviveConfig.minHoops;
      expect(ReviveLadder.eligible(s), isTrue);
    });
  });

  // ------------------------------------------------------------ in game
  final spy = AnalyticsSpy();

  FlameTester<FlappySpikesGame> tester({
    required Map<String, Object> prefs,
    FakeAdMode ad = FakeAdMode.succeed,
  }) => FlameTester<FlappySpikesGame>(
    () {
      spy.events.clear();
      return createRunTestGame(
        prefs: prefs,
        services: spy,
        worldHeight: 711,
        monetization: Monetization(ads: FakeRewardedAds()..mode = ad),
      );
    },
    gameSize: Vector2(320, 711),
  );

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
  }

  /// Passes 6 hoops and dies: the revive screen faded in, or null when the
  /// death went straight past the offer.
  Future<(RunController, ReviveScreen?)> die(FlappySpikesGame g) async {
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
    if (g.state != GameState.reviving) return (run, null);
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

  tester(prefs: {'noAds': true, 'coins': 50000}).testGameWidget(
    '§14.2 NO ADS owner, deaths after hoop 6: 250 (no label), 500, 1 000, '
    '2 000, 4 000, 8 000 coin revives, then no further offer; no ad, '
    'revive_free_used never logged',
    setUp: boot,
    verify: (g, _) async {
      final ads = g.monetization.ads as FakeRewardedAds;
      final prices = <int>[];
      final kinds = <ReviveKind>[];
      (await startRun(g)).events.on<RevivePhoenixStarted>(
        (e) => kinds.add(e.kind),
      );
      for (var k = 0; k < 6; k++) {
        final (_, screen) = await die(g);
        expect(screen, isNotNull, reason: 'offer #${k + 1}');
        final o = screen!.offer;
        expect(o.isCoins, isTrue);
        expect(o.noAdLabel, isFalse, reason: 'no NO AD AVAILABLE label');
        expect(screen.locked, isFalse);
        prices.add(o.price);
        final balance = g.menu.wallet.balance;
        screen.tapHeart();
        await throughPhoenix(g);
        expect(g.state, GameState.playing);
        expect(g.menu.wallet.balance, balance - o.price);
        await stepSeconds(g, ReviveConfig.invulnerable + .1);
      }
      expect(prices, [250, 500, 1000, 2000, 4000, 8000]);
      expect(kinds, List.filled(6, ReviveKind.coins));
      final offered = spy.events
          .where((e) => e.$1 == 'revive_offered')
          .map((e) => e.$2!['offer'])
          .toList();
      expect(offered, List.filled(6, 'coins'));
      // The 7th death: no offer any more.
      final (_, last) = await die(g);
      expect(last, isNull);
      expect(g.state, isNot(GameState.reviving));
      expect(ads.shown, 0);
      expect(spy.events.map((e) => e.$1), isNot(contains('revive_free_used')));
      expect(spy.events.map((e) => e.$1), isNot(contains('revive_ad_started')));
    },
  );

  tester(prefs: {'noAds': true, 'coins': 100}).testGameWidget(
    '§14.2 NO ADS owner with fewer than 250 coins: the locked 250 heart, '
    'like any coin revive without enough coins',
    setUp: boot,
    verify: (g, _) async {
      final (run, screen) = await die(g);
      expect(screen, isNotNull);
      expect(screen!.offer, const ReviveOffer.coins(250));
      expect(screen.locked, isTrue);
      final balance = g.menu.wallet.balance;
      expect(balance, lessThan(250));
      final phoenix = <RevivePhoenixStarted>[];
      run.events.on<RevivePhoenixStarted>(phoenix.add);
      screen.tapHeart();
      for (var i = 0; i < 120; i++) {
        g.update(1 / 60);
      }
      expect(phoenix, isEmpty);
      expect(g.state, GameState.reviving);
      expect(g.menu.wallet.balance, balance);
      expect(
        spy.events.where((e) => e.$1 == 'revive_locked_tap').single.$2,
        {'price': 250},
      );
      expect(spy.events.map((e) => e.$1), isNot(contains('revive_free_used')));
    },
  );

  tester(prefs: {'coins': 50000}).testGameWidget(
    '§14.2 non-owner unchanged in game: the ad heart first, then 250',
    setUp: boot,
    verify: (g, _) async {
      final (run, screen) = await die(g);
      expect(screen!.offer, const ReviveOffer.ad());
      final phoenix = <RevivePhoenixStarted>[];
      run.events.on<RevivePhoenixStarted>(phoenix.add);
      screen.tapHeart();
      for (var i = 0; i < 600 && g.state == GameState.reviving; i++) {
        g.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(g);
      }
      expect(g.state, GameState.playing);
      expect(phoenix.single.kind, ReviveKind.ad);
      await stepSeconds(g, ReviveConfig.invulnerable + .1);
      final (_, second) = await die(g);
      expect(second!.offer, const ReviveOffer.coins(250));
      expect(spy.events.map((e) => e.$1), isNot(contains('revive_free_used')));
    },
  );

  tester(
    prefs: {'coins': 50000},
    ad: FakeAdMode.unavailable,
  ).testGameWidget(
    '§14.2 non-owner, no ad available: "NO AD AVAILABLE" over the 250 heart '
    '(unchanged)',
    setUp: boot,
    verify: (g, _) async {
      final (_, screen) = await die(g);
      expect(screen!.offer, const ReviveOffer.coins(250, noAdLabel: true));
    },
  );
}
