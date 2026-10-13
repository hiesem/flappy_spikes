import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../menu_screenshot_test.dart' show captureShot, loadFonts;
import '../purchase_feedback_test.dart' show run;
import '../services/store_iap_service_test.dart' show FakeStore;
import '../shop_flow_test.dart' show openShop;
import 'menu_v4_qa_helpers.dart';

// Replace only native billing. All grants, pricing and feedback use the game.
class _PriceStore extends FakeStore {
  final prices = <String, String>{};

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
            currencyCode: 'IDR',
          ),
      ],
      notFoundIDs: ids.where((id) => !prices.containsKey(id)).toList(),
    );
  }
}

void main() {
  setUpAll(loadFonts);

  final retiredStore = FakeStore()..goLive(IapProduct.values);
  v4Journey(
    'v4 R2: retired receipts are acknowledged without a grant or celebration',
    iap: StoreIapService(store: retiredStore),
    (game, rig, tester) async {
      for (final amount in [500, 1800, 5000, 12000]) {
        retiredStore.emit(
          'coins_$amount',
          PurchaseStatus.purchased,
          pendingComplete: true,
        );
      }
      await v4Settle(game, tester);
      expect(game.menu.wallet.balance, 0);
      expect(game.coinReward, isNull);
      expect(rig.events.count('iap_purchase'), 0);
      expect(retiredStore.completed, hasLength(4));
      expect(retiredStore.queries.first, {
        'coins_1000',
        'coins_10000',
        'coins_17000',
        'coins_100000',
        'no_ads',
      });
    },
  );

  for (final product in kShopProducts.where((p) => p.consumable)) {
    final store = FakeStore()..goLive(IapProduct.values);
    v4Journey(
      'v4 R2: ${product.storeId} pending -> restart -> late exact grant',
      iap: StoreIapService(store: store),
      (game, rig, tester) async {
        await openShop(game);
        await game.buyProduct(product);
        store.emit(product.storeId, PurchaseStatus.pending);
        await v4Settle(game, tester);
        expect(game.menu.wallet.balance, 0);
        final restarted = await v4Restart(game, rig, tester);
        store.emit(
          product.storeId,
          PurchaseStatus.purchased,
          pendingComplete: true,
        );
        await v4Settle(restarted, tester);
        expect(restarted.menu.wallet.balance, product.coins);
        expect(restarted.coinReward!.amount, product.coins);
        expect(store.completed, hasLength(1));
        await run(restarted, 6);
        final again = await v4Restart(restarted, rig, tester);
        expect(again.menu.wallet.balance, product.coins);
        expect(rig.events.count('iap_purchase'), 1);
      },
    );

    final repeatStore = FakeStore()..goLive(IapProduct.values);
    v4Journey(
      'v4 R2: ${product.storeId} two distinct paid transactions both grant',
      iap: StoreIapService(store: repeatStore),
      (game, rig, tester) async {
        await openShop(game);
        for (var n = 0; n < 2; n++) {
          await game.buyProduct(product);
          repeatStore.purchases.add([
            PurchaseDetails(
              purchaseID: 'r2-distinct-${product.storeId}-$n',
              productID: product.storeId,
              verificationData: PurchaseVerificationData(
                localVerificationData: 'receipt-$n',
                serverVerificationData: 'token-$n',
                source: 'google_play',
              ),
              transactionDate: '${rig.clock.now.millisecondsSinceEpoch}',
              status: PurchaseStatus.purchased,
            )..pendingCompletePurchase = true,
          ]);
          await v4Settle(game, tester);
          expect(game.menu.wallet.balance, product.coins * (n + 1));
          await run(game, 6);
        }
        expect(repeatStore.completed, hasLength(2));
        expect(rig.events.count('iap_purchase'), 2);
      },
    );
  }

  final restoreStore = FakeStore()..goLive(IapProduct.values);
  v4Journey(
    'v4 R2: restored no_ads while offer is open closes it without bonus',
    eligible: true,
    iap: StoreIapService(store: restoreStore),
    (game, rig, tester) async {
      expect(game.noAdsPopup, isNotNull);
      restoreStore.emit(
        'no_ads',
        PurchaseStatus.restored,
        pendingComplete: true,
      );
      await v4Settle(game, tester);
      expect(game.menu.noAds, isTrue);
      expect(game.noAdsPopup, isNull);
      expect(game.noAdsCelebration, isNull);
      expect(game.menu.wallet.balance, 0);
      await v4Background(game, rig, tester, const Duration(days: 2));
      final next = await v4Restart(game, rig, tester);
      expect(next.noAdsPopup, isNull);
      expect(next.menu.noAds, isTrue);
      expect(next.menu.wallet.balance, 0);
    },
  );

  group('S1-71', () {
    for (final product in kShopProducts.where((p) => p.consumable)) {
      final store = FakeStore()..goLive(IapProduct.values);
      v4Journey(
        '${product.storeId}: redelivery of the same transaction grants once',
        iap: StoreIapService(store: store),
        (game, rig, tester) async {
          await openShop(game);
          await game.buyProduct(product);
          final receipt = PurchaseDetails(
            purchaseID: 'r2-single-transaction-${product.storeId}',
            productID: product.storeId,
            verificationData: PurchaseVerificationData(
              localVerificationData: 'same-receipt',
              serverVerificationData: 'same-token',
              source: 'google_play',
            ),
            transactionDate: '${rig.clock.now.millisecondsSinceEpoch}',
            status: PurchaseStatus.purchased,
          )..pendingCompletePurchase = true;
          store.purchases.add([receipt]);
          await v4Settle(game, tester);
          expect(game.menu.wallet.balance, product.coins);
          final next = await v4Restart(game, rig, tester);
          store.purchases.add([receipt]);
          await v4Settle(next, tester);
          expect(
            next.menu.wallet.balance,
            product.coins,
            reason:
                'the same purchaseID/token is one paid pack across restarts',
          );
          expect(rig.events.count('iap_purchase'), 1);
        },
      );
    }
  });

  group('S2-71', () {
    for (final height in [568.0, 711.0]) {
      final store = _PriceStore()
        ..prices.addAll({
          'coins_1000': 'Rp 29.000,00',
          'coins_10000': 'Rp 179.000,00',
          'coins_17000': 'Rp 299.000,00',
          'coins_100000': 'Rp 1.599.000,00',
          'no_ads': 'Rp 69.000,00',
        });
      v4Journey(
        '($height) localized prices fit their pack buttons',
        height: height,
        iap: StoreIapService(store: store),
        (game, rig, tester) async {
          final shop = await openShop(game);
          await tester.runAsync(
            () => captureShot(game, 1.5, 'r2_idr_shop_$height'),
          );
          // Store strings are representative input, not device-observed prices.
          // The UI must display them verbatim without crossing adjacent cards.
          for (final pack in shop.packs.reversed) {
            expect(pack.priceLabel.text, store.prices[pack.product.storeId]);
            expect(
              pack.priceLabel.width,
              lessThanOrEqualTo(pack.priceButton.width),
              reason:
                  '${pack.product.storeId} price must stay inside its button',
            );
            expect(pack.priceLabel.position.x, greaterThanOrEqualTo(0));
          }
        },
      );

      final bannerStore = _PriceStore()..prices['no_ads'] = 'Rp 69.000,00';
      v4Journey(
        '($height) localized No-ads banner price does not cover REMOVE ADS',
        height: height,
        iap: StoreIapService(store: bannerStore),
        (game, rig, tester) async {
          final shop = await openShop(game);
          expect(shop.banner.priceLabel!.text, 'Rp 69.000,00');
          expect(
            shop.banner.priceChip!.position.x,
            greaterThanOrEqualTo(
              shop.banner.label!.position.x + shop.banner.label!.width,
            ),
            reason: 'the gold price chip must not paint over the product label',
          );
        },
      );
    }
  });
}
