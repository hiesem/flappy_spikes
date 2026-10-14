import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/free_coins_policy.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.3.1 §5: the Shop free-coins ad pays 75 coins (`shop_ad_coins`,
/// default 75; a remote value replaces it). The row label follows the reward.
void main() {
  tearDown(() => TuningValues.current = TuningValues.defaults());

  final spy = AnalyticsSpy();

  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
    FakeRewardedAds? ads,
  }) => FlameTester<FlappySpikesGame>(
    () {
      spy.events.clear();
      return createTestGame(
        prefs,
        711,
        spy,
        Monetization(ads: ads ?? FakeRewardedAds()),
      );
    },
    gameSize: Vector2(320, 711),
  );

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
  }

  /// The gold "FREE +N" label of the Shop row.
  String freeLabel(FlappySpikesGame g) => g.shopScreen!.freeCoins.children
      .query<MenuText>()
      .map((t) => t.text)
      .singleWhere((t) => t.startsWith('FREE'));

  group('PRD-2.3.1 §5 Shop free-coins ad', () {
    test('the default reward is 75 coins', () {
      expect(TuningValues.defaults().i('shop_ad_coins'), 75);
      expect(FreeCoinsPolicy.reward, 75);
    });

    tester().testGameWidget(
      'one Shop ad adds 75 coins to the wallet, and the row reads "FREE +75"',
      setUp: boot,
      verify: (g, _) async {
        final ads = g.monetization.ads as FakeRewardedAds;
        expect(g.menu.wallet.balance, 0);
        g.openShop();
        await stepSeconds(g, .6);
        expect(freeLabel(g), 'FREE +75');

        await g.claimFreeCoins();
        await flushAndMount(g);
        expect(ads.shown, 1);
        expect(ads.placements, [AdPlacement.shopFreeCoins]);
        expect(g.menu.wallet.balance, 75);
        expect(
          spy.events.where((e) => e.$1 == 'coins_earned').single.$2,
          {'amount': 75, 'source': 'rewarded'},
        );
        expect(freeLabel(g), 'FREE +75');
      },
    );

    tester().testGameWidget(
      'remote shop_ad_coins = 60: one ad adds 60 coins and the row reads '
      '"FREE +60"',
      setUp: boot,
      verify: (g, _) async {
        TuningValues.current = TuningValues.resolve({'shop_ad_coins': '60'});
        final ads = g.monetization.ads as FakeRewardedAds;
        g.openShop();
        await stepSeconds(g, .6);
        expect(freeLabel(g), 'FREE +60');

        await g.claimFreeCoins();
        await flushAndMount(g);
        expect(ads.shown, 1);
        expect(g.menu.wallet.balance, 60);
        expect(
          spy.events.where((e) => e.$1 == 'coins_earned').single.$2,
          {'amount': 60, 'source': 'rewarded'},
        );
        expect(freeLabel(g), 'FREE +60');
      },
    );
  });
}
