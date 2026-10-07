import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/ui/coin_reward.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'menu_screenshot_test.dart' show captureShot, loadFonts;
import 'purchase_feedback_test.dart' show run;
import 'shop_flow_test.dart' show openShop, settle, shopTest;

/// PRD-menu-v4 §2–4 focused tests: the new coin packs (1 000 / 10 000 /
/// 17 000 / 100 000), their USD placeholders, the store price for the
/// player's account, the Shop tags and the celebration tiers.

/// A store stand-in that returns localized store prices (like the real
/// `ProductDetails.price`), falling back to the placeholder for products it
/// was not given (PRD-menu-v4 §4).
class _PriceyIap extends FakeIapService {
  _PriceyIap(this._prices);

  final Map<IapProduct, String> _prices;

  @override
  String priceOf(IapProduct p) => _prices[p] ?? p.placeholderPrice;
}

void main() {
  setUpAll(loadFonts);

  test('the four packs map positionally to the four celebration tiers', () {
    const stack = Rect.fromLTWH(0, 0, 44, 30);
    const order = [
      IapProduct.coins1000,
      IapProduct.coins10000,
      IapProduct.coins17000,
      IapProduct.coins100000,
    ];
    final rewards = [
      for (final product in order) CoinRewardAnimation.pack(product, from: stack),
    ];
    expect(rewards.map((r) => r.amount), [1000, 10000, 17000, 100000]);
    expect(rewards.map((r) => r.coins), [6, 9, 12, 16]);
    expect(rewards.map((r) => r.countDuration), [.9, 1.2, 1.5, 1.9]);
    expect(rewards.map((r) => r.confetti), [40, 70, 100, 150]);
    expect(rewards.map((r) => r.jingle), [
      Sfx.skBuyCommon,
      Sfx.skBuyRare,
      Sfx.skBuyEpic,
      Sfx.skBuyLegendary,
    ]);
    expect(rewards.map((r) => r.flash), [false, false, false, true]);
  });

  shopTest(
    'every pack grants its coins and plays its tier celebration',
    prefs: const {'coins': 0},
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openShop(game);
      var balance = 0;
      for (final pack in shop.packs) {
        final product = pack.product;
        pack.onPressed();
        await settle(game);
        balance += product.coins;
        expect(game.menu.wallet.balance, balance);
        expect(spy.last('iap_purchase'), {'product': product.storeId});
        expect(spy.last('coins_earned'), {
          'amount': product.coins,
          'source': 'iap',
        });
        expect(game.coinReward!.amount, product.coins);
        await run(game, 6);
        expect(game.coinReward, isNull);
        expect(shop.coinPill.shownBalance, balance);
      }
      expect(game.purchaseResultPopup, isNull);
    },
  );

  shopTest(
    'store price shown when present (Shop banner, packs, No-ads popup)',
    iapService: _PriceyIap(const {
      IapProduct.coins1000: 'CHF 1.00',
      IapProduct.coins10000: 'CHF 9.50',
      IapProduct.coins17000: 'CHF 13.50',
      IapProduct.coins100000: 'CHF 72.00',
      IapProduct.noAds: 'CHF 3.00',
    }),
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openShop(game);
      expect(shop.banner.price, 'CHF 3.00');
      expect(shop.packs.map((p) => p.priceLabel.text).toList(), [
        'CHF 1.00',
        'CHF 9.50',
        'CHF 13.50',
        'CHF 72.00',
      ]);
      game.openNoAdsPopup();
      await flushAndMount(game);
      expect(game.noAdsPopup!.priceLabel.text, 'CHF 3.00');
    },
  );

  shopTest(
    'USD placeholders while no store price exists (Shop + No-ads popup)',
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openShop(game);
      expect(shop.banner.price, r'$3.49');
      expect(shop.packs.map((p) => p.priceLabel.text).toList(), [
        r'$1.29',
        r'$9.99',
        r'$15.99',
        r'$84.99',
      ]);
      expect(shop.packs.map((p) => p.tag).toList(), [
        null,
        'MOST POPULAR',
        null,
        'BEST DEAL',
      ]);
      game.openNoAdsPopup();
      await flushAndMount(game);
      expect(game.noAdsPopup!.priceLabel.text, r'$3.49');
    },
  );

  // Visual check (PRD-menu-v4 §2–3): the Shop with the new amounts, tags and
  // USD placeholders; the 100,000 amount must fit the 142 pt tile. Written
  // to build/menu_shots/.
  FlameTester<FlappySpikesGame>(
    () => createTestGame(const {'coins': 1250}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'WP-K1 screenshot: Shop with the new packs (100,000 fits)',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final shop = await openShop(game);
      final big = shop.packs[3];
      expect(big.amount.text, '100,000');
      expect(
        big.amount.width,
        lessThanOrEqualTo(big.width),
        reason: 'the 100,000 amount must fit the 142 pt tile',
      );
      expect(shop.packs[1].tagComponent, isNotNull, reason: 'MOST POPULAR');
      expect(shop.packs[3].tagComponent, isNotNull, reason: 'BEST DEAL');
      await tester.runAsync(() => captureShot(game, 1.5, 'wp_k1_shop_711'));
      await tester.runAsync(() => captureShot(game, 2, 'wp_k1_shop_711@2x'));
    },
  );
}
