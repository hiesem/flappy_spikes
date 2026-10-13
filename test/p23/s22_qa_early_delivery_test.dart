import 'dart:async';

import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/store_iap_service_test.dart' show FakeStore;

void main() {
  test('S8-05 §22.2 a gift delivered before the game subscribes '
      'must stay available for the launch sync', () async {
    // main.dart initializes monetization concurrently with game.onLoad;
    // the purchase coordinator subscribes only after storage has loaded.
    final store = FakeStore()..goLive(IapProduct.values);
    final service = StoreIapService(store: store);
    await service.initialize();
    final purchase = PurchaseDetails(
      purchaseID: 'GPA.early-gift',
      productID: 'gift_coins_10000',
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: 'early-token',
        source: 'google_play',
      ),
      transactionDate: '0',
      status: PurchaseStatus.purchased,
    );
    store.purchases.add([purchase]);
    await pumpEventQueue();
    expect(
      store.consumed,
      isEmpty,
      reason: 'nobody has received or persisted the 10,000 coin grant',
    );
    expect(store.completed, isEmpty);
  });

  PurchaseDetails gift(String id) => PurchaseDetails(
    purchaseID: id,
    productID: 'gift_coins_10000',
    verificationData: PurchaseVerificationData(
      localVerificationData: '{}',
      serverVerificationData: 'token-$id',
      source: 'google_play',
    ),
    transactionDate: '0',
    status: PurchaseStatus.purchased,
  );

  for (final outcome in ['timeout', 'error']) {
    test('S8-05 §22.2 a gift whose grant is not confirmed ($outcome) is '
        'neither consumed nor acknowledged', () async {
      final store = FakeStore()..goLive(IapProduct.values);
      final service = StoreIapService(
        store: store,
        grantTimeout: const Duration(milliseconds: 20),
      );
      await service.initialize();
      final sub = service.events.listen((e) {
        if (outcome == 'error') {
          e.granted
            ?..future.ignore()
            ..completeError(StateError('disk full'));
        }
        // 'timeout': never confirmed.
      });
      addTearDown(sub.cancel);
      store.purchases.add([gift('GPA.unconfirmed')]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(store.consumed, isEmpty);
      expect(store.completed, isEmpty);
    });
  }

  test('S8-05 §22.2 the early gift is granted and consumed once the launch '
      'sync delivers it to a listener', () async {
    final store = FakeStore()..goLive(IapProduct.values);
    final service = StoreIapService(store: store);
    await service.initialize();
    final early = gift('GPA.early-gift');
    store.purchases.add([early]);
    await pumpEventQueue();
    expect(store.consumed, isEmpty);
    // The game subscribes, then the launch sync re-delivers it.
    final grants = <IapEvent>[];
    final sub = service.events.listen((e) {
      grants.add(e);
      e.granted?.complete();
    });
    addTearDown(sub.cancel);
    store.owned.add(early);
    await service.syncPurchases();
    await pumpEventQueue();
    expect(grants, hasLength(1));
    expect(store.consumed, [early]);
  });
}
