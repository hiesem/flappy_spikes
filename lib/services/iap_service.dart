import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Store products (Play Console / App Store Connect product IDs in
/// [IapProductInfo.storeId]).
enum IapProduct { coins500, coins1800, coins5000, coins12000, noAds }

extension IapProductInfo on IapProduct {
  /// Store product ID.
  String get storeId => switch (this) {
    IapProduct.coins500 => 'coins_500',
    IapProduct.coins1800 => 'coins_1800',
    IapProduct.coins5000 => 'coins_5000',
    IapProduct.coins12000 => 'coins_12000',
    IapProduct.noAds => 'no_ads',
  };

  /// Coins granted by a coin pack (0 for No ads — its bonus is
  /// [kNoAdsBonusCoins]).
  int get coins => switch (this) {
    IapProduct.coins500 => 500,
    IapProduct.coins1800 => 1800,
    IapProduct.coins5000 => 5000,
    IapProduct.coins12000 => 12000,
    IapProduct.noAds => 0,
  };

  /// Coin packs are consumable; No ads is a one-time (restorable) purchase.
  bool get consumable => this != IapProduct.noAds;

  /// Shown until (or unless) the store returns the localized price.
  String get placeholderPrice => switch (this) {
    IapProduct.coins500 => '€0.99',
    IapProduct.coins1800 => '€2.99',
    IapProduct.coins5000 => '€6.99',
    IapProduct.coins12000 => '€14.99',
    IapProduct.noAds => '€2.99',
  };
}

/// Bonus coins granted together with the No-ads purchase (PRD-1 §3.5).
const int kNoAdsBonusCoins = 1000;

IapProduct? _productForStoreId(String id) {
  for (final p in IapProduct.values) {
    if (p.storeId == id) return p;
  }
  return null;
}

enum IapStatus { pending, purchased, restored, failed, canceled }

/// A purchase update. Granting coins / No ads on [IapStatus.purchased] and
/// [IapStatus.restored] is the listener's job, not this layer's.
class IapEvent {
  const IapEvent(this.product, this.status, [this.message]);

  final IapProduct product;
  final IapStatus status;
  final String? message;

  @override
  String toString() =>
      'IapEvent(${product.name}, ${status.name}'
      '${message == null ? '' : ', $message'})';
}

/// In-app purchase service. The game only talks to this interface, so tests
/// and desktop builds run with [NoopIapService] / [FakeIapService] and never
/// touch the plugin.
abstract class IapService {
  /// Connects to the store and queries product details (prices). Never
  /// throws.
  Future<void> initialize();

  /// Whether the store is reachable and purchases can be attempted.
  bool get isAvailable;

  /// Store-localized price, else [IapProductInfo.placeholderPrice].
  String priceOf(IapProduct p);

  /// Purchase updates (broadcast).
  Stream<IapEvent> get events;

  /// Starts a purchase. Never throws; the outcome arrives on [events].
  Future<void> buy(IapProduct p);

  /// Restores owned non-consumables: an owned No ads arrives as
  /// `IapEvent(noAds, restored)`. Never throws.
  Future<void> restore();
}

/// Purchases disabled: every [buy] fails immediately.
class NoopIapService implements IapService {
  final StreamController<IapEvent> _events =
      StreamController<IapEvent>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  bool get isAvailable => false;

  @override
  String priceOf(IapProduct p) => p.placeholderPrice;

  @override
  Stream<IapEvent> get events => _events.stream;

  @override
  Future<void> buy(IapProduct p) async {
    _events.add(IapEvent(p, IapStatus.failed, 'Store unavailable'));
  }

  @override
  Future<void> restore() async {}
}

/// Behaviour of [FakeIapService.buy].
enum FakeIapMode { succeed, fail, pending, cancel }

/// Scriptable in-memory store for tests, Linux and the debug panel.
///
/// [buy] emits `pending`, then (after [delay]) the mode's result —
/// `purchased` / `failed` / `canceled`; in [FakeIapMode.pending] only
/// `pending` is emitted. A successfully bought No ads is remembered so
/// [restore] emits `restored` for it.
class FakeIapService implements IapService {
  FakeIapMode mode = FakeIapMode.succeed;

  /// Simulated store round-trip between `pending` and the result.
  Duration delay = Duration.zero;

  /// Products bought via [buy], in order (every attempt, any mode).
  final List<IapProduct> purchases = [];

  bool _ownsNoAds = false;

  /// Whether No ads was bought successfully (what [restore] restores).
  bool get ownsNoAds => _ownsNoAds;

  final StreamController<IapEvent> _events =
      StreamController<IapEvent>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  bool get isAvailable => true;

  @override
  String priceOf(IapProduct p) => p.placeholderPrice;

  @override
  Stream<IapEvent> get events => _events.stream;

  @override
  Future<void> buy(IapProduct p) async {
    purchases.add(p);
    _events.add(IapEvent(p, IapStatus.pending));
    if (mode == FakeIapMode.pending) {
      return;
    }
    await Future<void>.delayed(delay);
    switch (mode) {
      case FakeIapMode.succeed:
        if (p == IapProduct.noAds) _ownsNoAds = true;
        _events.add(IapEvent(p, IapStatus.purchased));
      case FakeIapMode.fail:
        _events.add(IapEvent(p, IapStatus.failed, 'Fake purchase failed'));
      case FakeIapMode.cancel:
        _events.add(IapEvent(p, IapStatus.canceled));
      case FakeIapMode.pending:
        break;
    }
  }

  @override
  Future<void> restore() async {
    if (_ownsNoAds) {
      _events.add(const IapEvent(IapProduct.noAds, IapStatus.restored));
    }
  }
}

/// Google Play Billing / StoreKit via `in_app_purchase`.
///
/// Listens to the plugin's purchase stream for the app's lifetime (started
/// in [initialize], i.e. at launch, so purchases completed while the app was
/// closed are delivered), maps each update to an [IapEvent] and acknowledges
/// it with `completePurchase`. Coin packs are bought with
/// `buyConsumable(autoConsume: true)`, No ads with `buyNonConsumable`.
/// Every plugin call is try/caught: the store must never take the game down.
class StoreIapService implements IapService {
  final StreamController<IapEvent> _events =
      StreamController<IapEvent>.broadcast();
  final Map<IapProduct, ProductDetails> _details = {};

  /// Kept alive for the app's lifetime on purpose (see class doc).
  // ignore: unused_field
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _initialized = false;
  bool _available = false;

  @override
  bool get isAvailable => _available;

  @override
  Stream<IapEvent> get events => _events.stream;

  @override
  String priceOf(IapProduct p) => _details[p]?.price ?? p.placeholderPrice;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    final iap = InAppPurchase.instance;
    try {
      _purchaseSub = iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) => debugPrint('StoreIapService stream error: $e'),
      );
    } catch (e) {
      debugPrint('StoreIapService purchaseStream failed: $e');
    }
    try {
      _available = await iap.isAvailable();
    } catch (e) {
      debugPrint('StoreIapService isAvailable failed: $e');
      _available = false;
    }
    if (!_available) {
      return;
    }
    try {
      final response = await iap.queryProductDetails(
        IapProduct.values.map((p) => p.storeId).toSet(),
      );
      if (response.error != null) {
        debugPrint('StoreIapService query error: ${response.error!.message}');
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
          'StoreIapService products not found: '
          '${response.notFoundIDs}',
        );
      }
      for (final d in response.productDetails) {
        final p = _productForStoreId(d.id);
        if (p != null) _details[p] = d;
      }
    } catch (e) {
      debugPrint('StoreIapService queryProductDetails failed: $e');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final product = _productForStoreId(purchase.productID);
      if (product != null) {
        final status = switch (purchase.status) {
          PurchaseStatus.pending => IapStatus.pending,
          PurchaseStatus.purchased => IapStatus.purchased,
          PurchaseStatus.restored => IapStatus.restored,
          PurchaseStatus.error => IapStatus.failed,
          PurchaseStatus.canceled => IapStatus.canceled,
        };
        _events.add(IapEvent(product, status, purchase.error?.message));
      }
      // Acknowledge even unknown products: un-acknowledged Play purchases
      // are refunded after three days.
      if (purchase.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(purchase);
        } catch (e) {
          debugPrint('StoreIapService completePurchase failed: $e');
        }
      }
    }
  }

  @override
  Future<void> buy(IapProduct p) async {
    final details = _details[p];
    if (!_available || details == null) {
      _events.add(IapEvent(p, IapStatus.failed, 'Product unavailable'));
      return;
    }
    try {
      final param = PurchaseParam(productDetails: details);
      final started = p.consumable
          ? await InAppPurchase.instance.buyConsumable(
              purchaseParam: param,
              autoConsume: true,
            )
          : await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
      if (!started) {
        _events.add(IapEvent(p, IapStatus.failed, 'Purchase not started'));
      }
    } catch (e) {
      debugPrint('StoreIapService buy failed: $e');
      _events.add(IapEvent(p, IapStatus.failed, e.toString()));
    }
  }

  @override
  Future<void> restore() async {
    if (!_available) {
      return;
    }
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('StoreIapService restore failed: $e');
    }
  }
}
