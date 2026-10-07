import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../menu_screenshot_test.dart' show loadFonts;
import '../purchase_feedback_test.dart' show run;
import '../services/store_iap_service_test.dart' show FakeStore;
import '../shop_flow_test.dart' show openShop;
import 'menu_v4_qa_helpers.dart';

// Exercise StoreIapService -> Purchases -> the real Flame UI; only the native
// store is replaced. Prices represent account-country formats, verbatim.
class _LocalizedStore extends FakeStore {
  final prices = <String, String>{};
  final consumables = <PurchaseParam>[];
  final nonConsumables = <PurchaseParam>[];

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queries.add(Set.of(ids));
    return ProductDetailsResponse(
      productDetails: [
        for (final id in ids.where(prices.containsKey))
          ProductDetails(
            id: id,
            title: id,
            description: id,
            price: prices[id]!,
            rawPrice: 1,
            currencyCode: 'EUR',
          ),
      ],
      notFoundIDs: ids.where((id) => !prices.containsKey(id)).toList(),
    );
  }

  @override
  Future<bool> buyConsumable(PurchaseParam param) async {
    consumables.add(param);
    return super.buyConsumable(param);
  }

  @override
  Future<bool> buyNonConsumable(PurchaseParam param) async {
    nonConsumables.add(param);
    return super.buyNonConsumable(param);
  }
}

const _ids = ['coins_1000', 'coins_10000', 'coins_17000', 'coins_100000'];
const _amounts = [1000, 10000, 17000, 100000];
const _placeholders = [r'$1.29', r'$9.99', r'$15.99', r'$84.99'];
const _localized = ['1,29 €', '¥1,600', r'R$ 89,90', 'CHF 72.00'];

void main() {
  setUpAll(loadFonts);

  for (final height in [568.0, 711.0]) {
    final store = _LocalizedStore();
    v4Journey(
      'v4 ($height): Shop placeholders -> partial store catalog -> all prices',
      iap: StoreIapService(store: store),
      height: height,
      (game, rig, tester) async {
        await run(game, .5);
        await v4Tap(game.homeScreen!.shopTile, game, tester);
        await run(game, .5);
        final shop = game.shopScreen!;
        expect(shop.packs.map((p) => p.product.storeId), _ids);
        expect(shop.packs.map((p) => p.amount.text), [
          '1,000',
          '10,000',
          '17,000',
          '100,000',
        ]);
        expect(shop.packs.map((p) => p.tag), [
          null,
          'MOST POPULAR',
          null,
          'BEST DEAL',
        ]);
        expect(shop.packs.map((p) => p.priceLabel.text), _placeholders);
        expect(shop.banner.priceLabel!.text, r'$3.49');
        for (final pack in shop.packs) {
          expect(pack.amount.width, lessThanOrEqualTo(pack.width));
        }
        expect(store.queries.first, {..._ids, 'no_ads'});

        store.prices.addAll({'coins_1000': _localized[0], 'no_ads': '1,29 €'});
        await rig.iap.refresh();
        await v4Settle(game, tester);
        expect(shop.banner.priceLabel!.text, '1,29 €');
        expect(shop.packs.map((p) => p.priceLabel.text), [
          _localized[0],
          ..._placeholders.skip(1),
        ]);
        for (var i = 0; i < _ids.length; i++) {
          store.prices[_ids[i]] = _localized[i];
        }
        await rig.iap.refresh();
        await v4Settle(game, tester);
        expect(shop.packs.map((p) => p.priceLabel.text), _localized);
        expect(store.queries.last, _ids.skip(1).toSet());
      },
    );
  }

  final popupStore = _LocalizedStore();
  v4Journey(
    'v4: automatic No-ads popup reprices while open, buys at the store price',
    eligible: true,
    iap: StoreIapService(store: popupStore),
    (game, rig, tester) async {
      final popup = game.noAdsPopup!;
      expect(popup.priceLabel.text, r'$3.49');
      popupStore.prices['no_ads'] = r'R$ 17,90';
      await rig.iap.refresh();
      await v4Settle(game, tester);
      expect(identical(game.noAdsPopup, popup), isTrue);
      expect(popup.priceLabel.text, r'R$ 17,90');
      await run(game, .3);
      await v4Tap(popup.priceButton, game, tester);
      expect(
        popupStore.nonConsumables.single.productDetails.price,
        r'R$ 17,90',
      );
      expect(popupStore.launched, ['no_ads']);
      popupStore.emit(
        'no_ads',
        PurchaseStatus.purchased,
        pendingComplete: true,
      );
      await v4Settle(game, tester);
      expect(game.menu.noAds, isTrue);
      expect(game.menu.wallet.balance, 1000);
      expect(game.noAdsPopup, isNull);
      expect(game.noAdsCelebration, isNotNull);
      expect(v4ModalCount(game), 1);
      game.handleBack();
      await run(game, 6);
      final restarted = await v4Restart(game, rig, tester);
      expect(restarted.menu.noAds, isTrue);
      expect(restarted.menu.wallet.balance, 1000);
      expect(restarted.noAdsPopup, isNull);
      expect(restarted.noAdsCelebration, isNull);
      popupStore.emit(
        'no_ads',
        PurchaseStatus.purchased,
        pendingComplete: true,
      );
      await v4Settle(restarted, tester);
      expect(restarted.menu.wallet.balance, 1000, reason: 'bonus only once');
      expect(restarted.noAdsCelebration, isNull);
    },
  );

  final packsStore = _LocalizedStore()
    ..prices.addAll({
      for (var i = 0; i < _ids.length; i++) _ids[i]: _localized[i],
    });
  v4Journey(
    'v4: tap each pack -> billing -> exact grant, tier, analytics, restart',
    iap: StoreIapService(store: packsStore),
    (game, rig, tester) async {
      final shop = await openShop(game);
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      const jingles = [
        Sfx.skBuyCommon,
        Sfx.skBuyRare,
        Sfx.skBuyEpic,
        Sfx.skBuyLegendary,
      ];
      var balance = 0;
      for (var i = 0; i < shop.packs.length; i++) {
        final pack = shop.packs[i];
        await v4Tap(pack, game, tester);
        expect(packsStore.launched.last, _ids[i]);
        expect(packsStore.consumables.last.productDetails.price, _localized[i]);
        expect(game.purchases.isPending(pack.product), isTrue);
        packsStore.emit(
          _ids[i],
          PurchaseStatus.purchased,
          pendingComplete: true,
        );
        await v4Settle(game, tester);
        balance += _amounts[i];
        expect(game.menu.wallet.balance, balance);
        expect(rig.events.last('iap_purchase'), {'product': _ids[i]});
        expect(rig.events.last('coins_earned'), {
          'amount': _amounts[i],
          'source': 'iap',
        });
        final reward = game.coinReward!;
        expect(reward.from, pack.stackRect);
        expect(reward.amount, _amounts[i]);
        expect(reward.coins, [6, 9, 12, 16][i]);
        expect(reward.countDuration, [.9, 1.2, 1.5, 1.9][i]);
        expect(reward.confetti, [40, 70, 100, 150][i]);
        expect(reward.jingle, jingles[i]);
        expect(reward.flash, i == 3);
        await run(game, 6);
        expect(shop.coinPill.shownBalance, balance);
        expect(sounds, contains(jingles[i]));
      }
      expect(balance, 128000);
      expect(packsStore.completed, hasLength(4));
      expect(packsStore.nonConsumables, isEmpty);
      final persisted = GameStorage(clock: rig.clock.call);
      await persisted.load();
      expect(persisted.coins, balance);
      final restarted = await v4Restart(game, rig, tester);
      expect(restarted.menu.wallet.balance, balance);
    },
  );

  final missingStore = _LocalizedStore();
  v4Journey(
    'v4: missing pack keeps USD price and reports failure without a grant',
    iap: StoreIapService(store: missingStore),
    (game, rig, tester) async {
      final shop = await openShop(game);
      await v4Tap(shop.packs.last, game, tester);
      expect(shop.packs.last.priceLabel.text, r'$84.99');
      expect(game.purchaseResultPopup, isNotNull);
      expect(game.menu.wallet.balance, 0);
      expect(missingStore.launched, isEmpty);
      expect(rig.events.last('iap_error')!['product'], 'coins_100000');
    },
  );
}
