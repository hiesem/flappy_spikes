import 'dart:async';

import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory [IapStore]: scriptable availability / catalog / launch result,
/// records every call. No plugin involved.
class FakeStore implements IapStore {
  bool available = true;
  Object? availableError;

  /// Store ids the "Play Console" currently serves.
  final Set<String> live = {};
  IAPError? queryError;
  Object? queryThrows;

  /// Delays each query (concurrency tests).
  Completer<void>? queryGate;

  bool launchResult = true;
  Object? launchError;

  int availableCalls = 0;
  final List<Set<String>> queries = [];
  final List<String> launched = [];
  final List<PurchaseDetails> completed = [];

  final StreamController<List<PurchaseDetails>> purchases =
      StreamController<List<PurchaseDetails>>.broadcast();

  void goLive(Iterable<IapProduct> products) =>
      live.addAll(products.map((p) => p.storeId));

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => purchases.stream;

  @override
  Future<bool> isAvailable() async {
    availableCalls++;
    if (availableError != null) throw availableError!;
    return available;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queries.add(ids);
    if (queryGate != null) await queryGate!.future;
    if (queryThrows != null) throw queryThrows!;
    final found = ids.where(live.contains).toList();
    return ProductDetailsResponse(
      productDetails: [
        for (final id in found)
          ProductDetails(
            id: id,
            title: id,
            description: id,
            price: 'CHF $id',
            rawPrice: 1,
            currencyCode: 'CHF',
          ),
      ],
      notFoundIDs: ids.where((id) => !live.contains(id)).toList(),
      error: queryError,
    );
  }

  Future<bool> _launch(PurchaseParam param) async {
    launched.add(param.productDetails.id);
    if (launchError != null) throw launchError!;
    return launchResult;
  }

  @override
  Future<bool> buyConsumable(PurchaseParam param) => _launch(param);

  @override
  Future<bool> buyNonConsumable(PurchaseParam param) => _launch(param);

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async =>
      completed.add(purchase);

  @override
  Future<void> restorePurchases() async {}

  /// A purchase-stream update like the Android plugin emits it (flow
  /// errors / cancels come with an empty product id).
  void emit(
    String productId,
    PurchaseStatus status, {
    IAPError? error,
    bool pendingComplete = false,
  }) {
    purchases.add([
      PurchaseDetails(
          productID: productId,
          verificationData: PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: '',
            source: 'google_play',
          ),
          transactionDate: null,
          status: status,
        )
        ..error = error
        ..pendingCompletePurchase = pendingComplete,
    ]);
  }
}

IAPError billingError(String name) => IAPError(
  source: 'google_play',
  code: 'purchase_error',
  message: 'BillingResponse.$name',
);

class EventSpy extends GameServices {
  final List<(String, Map<String, Object>?)> events = [];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    events.add((name, parameters));
  }
}

/// Lets queued microtasks / stream deliveries run.
Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeStore store;
  late StoreIapService iap;
  late List<IapEvent> events;
  late StreamSubscription<IapEvent> sub;

  setUp(() {
    store = FakeStore();
    iap = StoreIapService(
      store: store,
      queryTimeout: const Duration(milliseconds: 200),
      launchErrorGrace: const Duration(milliseconds: 50),
    );
    events = [];
    // Acts like the game's Purchases: confirms each grant.
    sub = iap.events.listen((e) {
      events.add(e);
      e.granted?.complete();
    });
  });

  tearDown(() => sub.cancel());

  group('StoreIapService', () {
    test('launch query: real prices for live products, placeholders for '
        'the rest', () async {
      store.goLive([IapProduct.coins1000, IapProduct.noAds]);
      await iap.initialize();
      expect(iap.isAvailable, isTrue);
      expect(store.queries.single, hasLength(5));
      expect(iap.priceOf(IapProduct.coins1000), 'CHF coins_1000');
      expect(iap.priceOf(IapProduct.noAds), 'CHF no_ads');
      expect(iap.priceOf(IapProduct.coins10000), r'$9.99');
    });

    test('missing details at buy time -> re-query -> billing flow '
        'launches', () async {
      await iap.initialize(); // nothing live yet (fresh Play products)
      expect(iap.priceOf(IapProduct.coins10000), r'$9.99');
      store.goLive(IapProduct.values);

      await iap.buy(IapProduct.coins10000);
      await pump();
      expect(store.queries, hasLength(2));
      expect(store.queries.last, hasLength(5), reason: 're-queries missing');
      expect(store.launched, ['coins_10000']);
      expect(events, isEmpty, reason: 'no failure');
      expect(iap.priceOf(IapProduct.coins10000), 'CHF coins_10000');

      // Purchase completes on the stream: granted + acknowledged.
      store.emit(
        'coins_10000',
        PurchaseStatus.purchased,
        pendingComplete: true,
      );
      await pump();
      expect(events.single.status, IapStatus.purchased);
      expect(events.single.product, IapProduct.coins10000);
      expect(store.completed, hasLength(1));

      // Everything known now: a further buy does not query again.
      await iap.buy(IapProduct.coins1000);
      expect(store.queries, hasLength(2));
    });

    test('store unavailable at launch -> re-checked at buy time', () async {
      store.available = false;
      store.goLive(IapProduct.values);
      await iap.initialize();
      expect(iap.isAvailable, isFalse);
      expect(store.queries, isEmpty);

      store.available = true;
      await iap.buy(IapProduct.noAds);
      expect(iap.isAvailable, isTrue);
      expect(store.launched, ['no_ads']);
      expect(events, isEmpty);
    });

    test('product not in the store -> "Product not found"', () async {
      store.goLive([IapProduct.coins1000]);
      await iap.initialize();
      await iap.buy(IapProduct.coins100000);
      await pump();
      expect(store.launched, isEmpty);
      expect(events.single.status, IapStatus.failed);
      expect(events.single.message, 'Product not found');
      expect(events.single.code, 'not_found');
    });

    test('billing unavailable -> "Store unavailable"', () async {
      store.available = false;
      await iap.initialize();
      await iap.buy(IapProduct.coins1000);
      await pump();
      expect(store.availableCalls, 2, reason: 're-checked before failing');
      expect(events.single.message, 'Store unavailable');
      expect(events.single.code, 'billing_unavailable');
    });

    test('isAvailable throwing -> "Store unavailable"', () async {
      store.availableError = PlatformException(code: 'boom');
      await iap.buy(IapProduct.coins1000); // never initialized: still safe
      await pump();
      expect(events.single.message, 'Store unavailable');
      expect(events.single.code, 'is_available_error');
    });

    test('query error is surfaced with its code', () async {
      store.goLive([IapProduct.noAds]);
      store.queryError = IAPError(
        source: 'google_play',
        code: 'serviceDisconnected',
        message: '',
      );
      await iap.initialize();
      // The failed re-query invalidates the earlier notFound: its error wins.
      store.queryThrows = PlatformException(code: 'BILLING_GLITCH');
      await iap.buy(IapProduct.coins1000);
      await pump();
      expect(events.single.message, 'BILLING_GLITCH');
      expect(events.single.code, 'BILLING_GLITCH');
    });

    test(
      'details conversion failure inside the plugin -> "Store error"',
      () async {
        store.queryThrows = TypeError();
        await iap.initialize();
        await iap.buy(IapProduct.noAds);
        await pump();
        expect(events.single.message, 'Store error');
        expect(events.single.code, 'TypeError');
      },
    );

    test('refresh: only while something is missing; never two queries at '
        'once', () async {
      await iap.initialize();
      expect(store.queries, hasLength(1));

      store.queryGate = Completer<void>();
      final a = iap.refresh();
      final b = iap.refresh();
      final c = iap.buy(IapProduct.coins1000);
      await pump();
      expect(store.queries, hasLength(2), reason: 'joined, not stacked');
      store.goLive(IapProduct.values);
      store.queryGate!.complete();
      await Future.wait([a, b, c]);
      expect(store.launched, ['coins_1000']);

      store.queryGate = null;
      await iap.refresh();
      expect(store.queries, hasLength(2), reason: 'all known: no query');
    });

    test('purchase error on the stream carries the Billing response', () async {
      store.goLive(IapProduct.values);
      await iap.initialize();
      await iap.buy(IapProduct.coins17000);
      // Play reports flow errors with an empty product id.
      store.emit(
        '',
        PurchaseStatus.error,
        error: billingError('itemUnavailable'),
      );
      await pump();
      expect(events.single.product, IapProduct.coins17000);
      expect(events.single.status, IapStatus.failed);
      expect(events.single.message, 'Item unavailable');
      expect(events.single.code, 'itemUnavailable');
    });

    test(
      'cancel with an empty product id finishes the flow silently',
      () async {
        store.goLive(IapProduct.values);
        await iap.initialize();
        await iap.buy(IapProduct.noAds);
        store.emit('', PurchaseStatus.canceled);
        await pump();
        expect(events.single.product, IapProduct.noAds);
        expect(events.single.status, IapStatus.canceled);
        expect(events.single.message, isNull);

        // A stray empty-id update with no flow running is ignored, and an
        // empty-id "purchased" never grants anything.
        store.emit('', PurchaseStatus.error, error: billingError('error'));
        await pump();
        await iap.buy(IapProduct.coins1000);
        store.emit('', PurchaseStatus.purchased);
        await pump();
        expect(events, hasLength(1));
      },
    );

    test(
      'launch not ok: waits for the stream code, else "Not started"',
      () async {
        store.goLive(IapProduct.values);
        store.launchResult = false;
        await iap.initialize();

        await iap.buy(IapProduct.coins1000);
        store.emit(
          '',
          PurchaseStatus.error,
          error: billingError('developerError'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(events.single.message, 'Developer error');
        expect(events.single.code, 'developerError');

        events.clear();
        await iap.buy(IapProduct.coins1000);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(events.single.message, 'Not started');
        expect(events.single.code, 'launch_failed');
      },
    );

    test(
      'plugin exception -> its code; NOT_FOUND re-queries next time',
      () async {
        store.goLive(IapProduct.values);
        await iap.initialize();
        store.launchError = PlatformException(code: 'NOT_FOUND');
        await iap.buy(IapProduct.coins1000);
        await pump();
        expect(events.single.message, 'Product not found');
        expect(events.single.code, 'NOT_FOUND');

        store.launchError = null;
        await iap.buy(IapProduct.coins1000);
        expect(store.queries, hasLength(2));
        expect(store.launched, ['coins_1000', 'coins_1000']);
      },
    );

    test('query timeout -> "Store timeout"', () async {
      store.queryGate = Completer<void>(); // never completes
      await iap.initialize();
      await iap.buy(IapProduct.coins1000);
      await pump();
      expect(events.single.message, 'Store timeout');
      expect(events.single.code, 'timeout');
    });
  });

  group('iapFailureFrom', () {
    test('Billing responses map to short reasons, codes keep the name', () {
      expect(iapFailureFrom(billingError('billingUnavailable')), (
        reason: 'Billing unavailable',
        code: 'billingUnavailable',
      ));
      expect(iapFailureFrom(billingError('itemAlreadyOwned')), (
        reason: 'Already owned',
        code: 'itemAlreadyOwned',
      ));
      expect(iapFailureFrom(billingError('somethingNew')), (
        reason: 'somethingNew',
        code: 'somethingNew',
      ));
      expect(
        iapFailureFrom(
          IAPError(source: 'google_play', code: 'purchase_error', message: ''),
        ),
        (reason: 'Store error', code: 'purchase_error'),
      );
      // Long store messages are cut so the toast fits the playfield.
      final long = iapFailureFrom(
        IAPError(
          source: 'google_play',
          code: 'x',
          message: 'A very long store message that never fits',
        ),
      );
      expect(long.reason.length, lessThanOrEqualTo(18));
      expect(long.reason, endsWith('…'));
    });
  });

  group('Purchases toast + iap_error', () {
    late List<String> toasts;
    late EventSpy spy;
    late Purchases purchases;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      toasts = [];
      spy = EventSpy();
      purchases = Purchases(
        iap: iap,
        menu: MenuState(storage),
        services: spy,
        toast: toasts.add,
      )..start();
    });

    tearDown(() => purchases.dispose());

    test('not found', () async {
      await iap.initialize();
      await purchases.buy(IapProduct.coins1000);
      await pump();
      expect(toasts, ['Purchase failed: Product not found']);
      expect(spy.events.single.$1, 'iap_error');
      expect(spy.events.single.$2, {
        'product': 'coins_1000',
        'reason': 'Product not found',
        'code': 'not_found',
      });
      expect(purchases.isPending(IapProduct.coins1000), isFalse);
    });

    test('store unavailable', () async {
      store.available = false;
      await iap.initialize();
      await purchases.buy(IapProduct.noAds);
      await pump();
      expect(toasts, ['Purchase failed: Store unavailable']);
      expect(spy.events.single.$2!['code'], 'billing_unavailable');
    });

    test('Billing error code reaches the toast', () async {
      store.goLive(IapProduct.values);
      await iap.initialize();
      await purchases.buy(IapProduct.coins10000);
      expect(purchases.isPending(IapProduct.coins10000), isTrue);
      store.emit('', PurchaseStatus.error, error: billingError('networkError'));
      await pump();
      expect(toasts, ['Purchase failed: Network error']);
      expect(spy.events.single.$2, {
        'product': 'coins_10000',
        'reason': 'Network error',
        'code': 'networkError',
      });
      expect(purchases.isPending(IapProduct.coins10000), isFalse);
    });

    test('cancel stays silent and re-enables the button', () async {
      store.goLive(IapProduct.values);
      await iap.initialize();
      await purchases.buy(IapProduct.coins10000);
      store.emit('', PurchaseStatus.canceled);
      await pump();
      expect(toasts, isEmpty);
      expect(spy.events, isEmpty);
      expect(purchases.isPending(IapProduct.coins10000), isFalse);
    });
  });

  group('S1-71 one grant per store transaction', () {
    late MenuState menu;
    late GameStorage storage;
    late Purchases purchases;
    late EventSpy spy;

    PurchaseDetails receipt(
      String product, {
      String? id,
      String token = '',
      String source = 'google_play',
    }) => PurchaseDetails(
      purchaseID: id,
      productID: product,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: token,
        source: source,
      ),
      transactionDate: null,
      status: PurchaseStatus.purchased,
    )..pendingCompletePurchase = true;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = GameStorage();
      await storage.load();
      spy = EventSpy();
      menu = MenuState(storage);
      purchases = Purchases(iap: iap, menu: menu, services: spy, toast: (_) {})
        ..start();
      store.goLive(IapProduct.values);
      await iap.initialize();
    });

    tearDown(() => purchases.dispose());

    test('transactionIdsOf: purchaseID + Play token; never an iOS receipt', () {
      expect(
        transactionIdsOf(receipt('coins_1000', id: 'GPA.1', token: 'tok')),
        ['id:GPA.1', 'token:tok'],
      );
      expect(
        transactionIdsOf(
          receipt('coins_1000', id: '1000', token: 'R', source: 'app_store'),
        ),
        ['id:1000'],
      );
      expect(transactionIdsOf(receipt('coins_1000')), isEmpty);
    });

    test(
      'same transaction re-delivered: one grant, completed both times',
      () async {
        final r = receipt('coins_10000', id: 'GPA.7', token: 'tok-7');
        store.purchases.add([r]);
        await pump();
        store.purchases.add([r]);
        await pump();
        expect(menu.wallet.balance, 10000);
        expect(store.completed, hasLength(2));
        expect(spy.events.where((e) => e.$1 == 'iap_purchase'), hasLength(1));
        expect(storage.grantedPurchases, ['id:GPA.7', 'token:tok-7']);
      },
    );

    test(
      'a replay is recognised by its token alone (order id appears later)',
      () async {
        store.purchases.add([receipt('coins_1000', token: 'tok-9')]);
        await pump();
        store.purchases.add([
          receipt('coins_1000', id: 'GPA.9', token: 'tok-9'),
        ]);
        await pump();
        expect(menu.wallet.balance, 1000);
      },
    );

    test('the ledger survives a restart', () async {
      store.purchases.add([receipt('coins_17000', id: 'GPA.3')]);
      await pump();
      final reloaded = GameStorage();
      await reloaded.load();
      expect(reloaded.isPurchaseGranted(['id:GPA.3']), isTrue);
    });

    test('distinct transactions both grant', () async {
      store.purchases.add([receipt('coins_1000', id: 'a', token: 'ta')]);
      store.purchases.add([receipt('coins_1000', id: 'b', token: 'tb')]);
      await pump();
      expect(menu.wallet.balance, 2000);
    });

    test('grant happens before the store completes the purchase', () async {
      var balanceAtComplete = -1;
      final gated = _GatedStore(() => balanceAtComplete = menu.wallet.balance)
        ..goLive(IapProduct.values);
      final service = StoreIapService(store: gated);
      final p = Purchases(
        iap: service,
        menu: menu,
        services: spy,
        toast: (_) {},
      )..start();
      await service.initialize();
      gated.purchases.add([receipt('coins_1000', id: 'g1')]);
      await pump();
      await pump();
      expect(balanceAtComplete, 1000);
      p.dispose();
    });

    test('ledger is bounded', () async {
      for (var i = 0; i < GameStorage.maxGrantedPurchases + 10; i++) {
        await storage.saveGrantedPurchase(['id:$i']);
      }
      expect(
        storage.grantedPurchases,
        hasLength(GameStorage.maxGrantedPurchases),
      );
      expect(
        storage.grantedPurchases.last,
        'id:${GameStorage.maxGrantedPurchases + 9}',
      );
      expect(storage.isPurchaseGranted(['id:0']), isFalse);
    });
  });
}

class _GatedStore extends FakeStore {
  _GatedStore(this.onComplete);

  final void Function() onComplete;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    onComplete();
    return super.completePurchase(purchase);
  }
}
