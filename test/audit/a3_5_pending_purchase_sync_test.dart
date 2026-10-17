import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    show GooglePlayPurchaseDetails;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/store_iap_service_test.dart' show FakeStore;

/// Audit A3-5: a store "pending" purchase left the open purchase flow set,
/// so every later sync was skipped for the session (gift codes redeemed
/// outside the game and background-completed pending purchases were not
/// picked up until the next cold start); a skipped sync also used up the
/// sync throttle.
GooglePlayPurchaseDetails _playPending(IapProduct product) =>
    GooglePlayPurchaseDetails(
      purchaseID: 'GPA.pending',
      productID: product.storeId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: 'token-pending',
        source: 'google_play',
      ),
      transactionDate: '0',
      billingClientPurchase: PurchaseWrapper(
        orderId: 'GPA.pending',
        packageName: 'com.duoleads.flappyspikes',
        purchaseTime: 0,
        purchaseToken: 'token-pending',
        signature: '',
        products: [product.storeId],
        isAutoRenewing: false,
        originalJson: '{}',
        isAcknowledged: false,
        purchaseState: PurchaseStateWrapper.pending,
      ),
      status: PurchaseStatus.pending,
    );

PurchaseDetails _appStorePending(IapProduct product) => PurchaseDetails(
  productID: product.storeId,
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: '',
    source: 'app_store',
  ),
  transactionDate: null,
  status: PurchaseStatus.pending,
);

Future<(StoreIapService, FakeStore)> _rig() async {
  final store = FakeStore()..goLive(IapProduct.values);
  final service = StoreIapService(store: store);
  service.events.listen((e) {
    final granted = e.granted;
    if (granted != null && !granted.isCompleted) granted.complete();
  });
  await service.initialize();
  return (service, store);
}

class _BlockedSyncIap extends FakeIapService {
  bool blocked = true;

  @override
  bool get purchaseInProgress => blocked;
}

void main() {
  for (final (name, pending) in [
    ('Google Play', _playPending),
    ('App Store', _appStorePending),
  ]) {
    test('A3-5 a $name pending purchase ends the open flow: the next sync '
        'runs', () async {
      final (service, store) = await _rig();
      await service.buy(IapProduct.coins1000);
      expect(service.purchaseInProgress, isTrue);
      store.purchases.add([pending(IapProduct.coins1000)]);
      await pumpEventQueue();
      expect(service.purchaseInProgress, isFalse);
      final before = store.restoreCalls;
      await service.syncPurchases();
      expect(store.restoreCalls, before + 1);
    });
  }

  test('A3-5 a sync skipped for an open purchase flow does not use up the '
      'throttle', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    var now = DateTime(2026, 10, 17, 12);
    final iap = _BlockedSyncIap();
    final purchases = Purchases(
      iap: iap,
      menu: MenuState(storage),
      services: GameServices(),
      toast: (_) {},
      clock: () => now,
    )..start();
    addTearDown(purchases.dispose);
    expect(purchases.sync(), isFalse, reason: 'a purchase flow is open');
    expect(iap.syncs, 0);
    iap.blocked = false;
    now = now.add(const Duration(seconds: 1)); // < Config.iapSyncInterval
    expect(Config.iapSyncInterval, greaterThan(const Duration(seconds: 1)));
    expect(purchases.sync(), isTrue);
    expect(iap.syncs, 1);
  });
}
