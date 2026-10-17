import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/store_iap_service_test.dart' show FakeStore;

/// Audit A3-4 (iOS): StoreKit re-delivers an unfinished coin-pack
/// transaction at launch, possibly before the game listens. It was kept
/// unfinished, and StoreKit's restore leaves consumables out, so it was
/// never granted and blocked buying that pack again. It is now held and
/// replayed to the first listener. Google Play keeps the old path (the
/// launch sync re-delivers it).
PurchaseDetails _purchase(String id, String source, {String product = 'coins_1000'}) =>
    PurchaseDetails(
      purchaseID: id,
      productID: product,
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: 'receipt',
        source: source,
      ),
      transactionDate: '0',
      status: PurchaseStatus.purchased,
    )..pendingCompletePurchase = true;

void main() {
  test('A3-4 an App Store purchase delivered before the game listens is '
      'granted and finished once it listens', () async {
    final store = FakeStore()
      ..goLive(IapProduct.values)
      ..consumeApplies = false; // StoreKit: finishing is the consume
    final service = StoreIapService(store: store);
    await service.initialize();
    final early = _purchase('2000000123', 'app_store');
    store.purchases.add([early]);
    await pumpEventQueue();
    expect(store.completed, isEmpty, reason: 'nobody granted it yet');

    final grants = <IapEvent>[];
    final sub = service.events.listen((e) {
      grants.add(e);
      e.granted?.complete();
    });
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(grants, hasLength(1));
    expect(grants.single.product, IapProduct.coins1000);
    expect(grants.single.status, IapStatus.purchased);
    expect(grants.single.transactionIds, ['id:2000000123']);
    expect(store.completed, [early]);
  });

  test('A3-4 a held App Store purchase is replayed once, even when '
      'StoreKit delivered it twice', () async {
    final store = FakeStore()
      ..goLive(IapProduct.values)
      ..consumeApplies = false;
    final service = StoreIapService(store: store);
    await service.initialize();
    store.purchases.add([_purchase('2000000124', 'app_store')]);
    await pumpEventQueue();
    store.purchases.add([_purchase('2000000124', 'app_store')]);
    await pumpEventQueue();
    final grants = <IapEvent>[];
    final sub = service.events.listen((e) {
      grants.add(e);
      e.granted?.complete();
    });
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(grants, hasLength(1));
  });

  test('A3-4 Google Play is unchanged: an early purchase is kept for the '
      'launch sync, not replayed', () async {
    final store = FakeStore()..goLive(IapProduct.values);
    final service = StoreIapService(store: store);
    await service.initialize();
    store.purchases.add([_purchase('GPA.1', 'google_play')]);
    await pumpEventQueue();
    final grants = <IapEvent>[];
    final sub = service.events.listen((e) {
      grants.add(e);
      e.granted?.complete();
    });
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(grants, isEmpty);
    expect(store.consumed, isEmpty);
    expect(store.completed, isEmpty);
  });
}
