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
  }, skip: 'S8-05');
}
