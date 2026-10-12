import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/store_iap_service_test.dart' show FakeStore;

// §32.6 explicitly requires tests of all five lowered USD placeholders.
// Localized prices and their UI fit are covered by localized_price_fit_test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const prices = {
    IapProduct.coins1000: r'$0.99',
    IapProduct.coins10000: r'$8.99',
    IapProduct.coins17000: r'$14.99',
    IapProduct.coins100000: r'$79.99',
    IapProduct.noAds: r'$2.99',
  };

  for (final entry in prices.entries) {
    test('§32.5 / §32.6 ${entry.key.storeId}: lowered USD price when offline '
        'and before the store catalog loads', () async {
      expect(entry.key.placeholderPrice, entry.value);
      expect(NoopIapService().priceOf(entry.key), entry.value);
      expect(FakeIapService().priceOf(entry.key), entry.value);
      final offline = FakeStore()..available = false;
      final store = StoreIapService(store: offline);
      expect(store.priceOf(entry.key), entry.value);
      await store.initialize();
      expect(store.isAvailable, isFalse);
      expect(store.priceOf(entry.key), entry.value);
      await offline.purchases.close();
    });
  }
}
