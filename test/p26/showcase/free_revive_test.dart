import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/screens/revive_ladder.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

final class _ShowcasePlan extends ShowcasePlan {
  const _ShowcasePlan(this.result);

  final ShowcaseRunPlan? result;

  @override
  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  }) => result;
}

const _plan = ShowcaseRunPlan(
  highlightId: 'portal',
  step: 0,
  attempt: 1,
  extraStarters: [Powerup.bigHoops, Powerup.shield],
);

void main() {
  test(
    'WP-B2 the showcase free step precedes and does not consume the ladder',
    () {
      final state = RunState(seed: 7, viewHeight: 711)..hoopsPassed = 1;
      final free = ReviveLadder.offer(state, adReady: false, showcase: true);
      expect(free, const ReviveOffer.free());
      ReviveLadder.record(state, free);
      state.revivesThisGame++;
      expect(state.adStepAvailableThisGame, isTrue);
      expect(state.coinRevives, 0);
      expect(
        ReviveLadder.offer(state, adReady: true, showcase: true),
        const ReviveOffer.ad(),
      );
    },
  );

  test('WP-B2 the showcase free step also precedes the NO ADS coin ladder', () {
    final state = RunState(seed: 7, viewHeight: 711)..hoopsPassed = 1;
    expect(
      ReviveLadder.offer(state, adReady: false, noAds: true, showcase: true),
      const ReviveOffer.free(),
    );
  });

  final spy = AnalyticsSpy();

  FlameTester<FlappySpikesGame>(() {
    spy.events.clear();
    SharedPreferences.setMockInitialValues(const {'coins': 50000});
    return FlappySpikesGame(
      worldHeight: 711,
      services: spy,
      monetization: Monetization(ads: FakeRewardedAds()),
      soundEnabled: false,
      showcasePlan: const _ShowcasePlan(_plan),
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'WP-B2 showcase: FREE below six hoops, then ad, then coins; no ad for FREE',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final ads = game.monetization.ads as FakeRewardedAds;
      final run = await startRun(game);
      run.state.shield = false;
      run.debugPass(perfect: true);
      killRunThroughSaves(game);
      await flushAndMount(game);
      expect(game.state, GameState.reviving);
      final free = game.reviveScreen!;
      for (var i = 0; i < 30 && free.ui < 1; i++) {
        game.update(1 / 60);
      }
      expect(free.offer, const ReviveOffer.free());
      free.tapHeart();
      expect(ads.shown, 0);
      expect(
        spy.events.where((event) => event.$1.startsWith('revive_ad_')),
        isEmpty,
      );
      for (var i = 0; i < 200 && game.state == GameState.reviving; i++) {
        game.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(game);
      }
      expect(game.state, GameState.playing);
      expect(run.state.revivesThisGame, 1);
      expect(run.state.adStepAvailableThisGame, isTrue);

      run.state.invulnerable = 0;
      for (var i = run.state.hoopsPassed; i < 6; i++) {
        run.debugPass(perfect: true);
      }
      killRunThroughSaves(game);
      await flushAndMount(game);
      final ad = game.reviveScreen!;
      expect(ad.offer, const ReviveOffer.ad());
      ad.tapHeart();
      for (var i = 0; i < 300 && game.state == GameState.reviving; i++) {
        game.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(game);
      }
      expect(game.state, GameState.playing);
      expect(ads.shown, 1);

      run.state.invulnerable = 0;
      killRunThroughSaves(game);
      await flushAndMount(game);
      final coins = game.reviveScreen!;
      expect(coins.offer, const ReviveOffer.coins(250));

      final offered = spy.events
          .where((event) => event.$1 == 'revive_offered')
          .map((event) => event.$2!['offer'])
          .toList();
      expect(offered, ['free', 'ad', 'coins']);
      final outcomes = spy.events
          .where((event) => event.$1 == 'run_fail')
          .map((event) => event.$2!['outcome'])
          .toList();
      expect(outcomes, ['revive_free', 'revive_ad']);
    },
  );

  FlameTester<FlappySpikesGame>(() {
    spy.events.clear();
    SharedPreferences.setMockInitialValues(const {});
    return FlappySpikesGame(
      worldHeight: 711,
      services: spy,
      soundEnabled: false,
      showcasePlan: const _ShowcasePlan(_plan),
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'WP-B2 a death before hoop 0 ends the showcase run without an offer',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      run.state.shield = false;
      killRunThroughSaves(game);
      await flushAndMount(game);
      for (var i = 0; i < 60 && game.state == GameState.reviving; i++) {
        game.update(1 / 60);
        await Future<void>.value();
      }
      expect(game.state, GameState.results);
      expect(game.reviveScreen, isNull);
      expect(run.state.revivesThisGame, 0);
      expect(
        spy.events.map((event) => event.$1),
        isNot(contains('revive_offered')),
      );
    },
  );
}
