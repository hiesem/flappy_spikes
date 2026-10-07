import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:in_app_purchase/in_app_purchase.dart';

/// Store products (Play Console / App Store Connect product IDs in
/// [IapProductInfo.storeId]).
enum IapProduct { coins1000, coins10000, coins17000, coins100000, noAds }

extension IapProductInfo on IapProduct {
  /// Store product ID.
  String get storeId => switch (this) {
    IapProduct.coins1000 => 'coins_1000',
    IapProduct.coins10000 => 'coins_10000',
    IapProduct.coins17000 => 'coins_17000',
    IapProduct.coins100000 => 'coins_100000',
    IapProduct.noAds => 'no_ads',
  };

  /// Coins granted by a coin pack (0 for No ads — its bonus is
  /// [kNoAdsBonusCoins]).
  int get coins => switch (this) {
    IapProduct.coins1000 => 1000,
    IapProduct.coins10000 => 10000,
    IapProduct.coins17000 => 17000,
    IapProduct.coins100000 => 100000,
    IapProduct.noAds => 0,
  };

  /// Coin packs are consumable; No ads is a one-time (restorable) purchase.
  bool get consumable => this != IapProduct.noAds;

  /// Shown until (or unless) the store returns the localized price
  /// (PRD-menu-v4 §3): a US-dollar placeholder ("$1.29"), used offline /
  /// before the products load / on Linux / in tests.
  String get placeholderPrice => switch (this) {
    IapProduct.coins1000 => r'$1.29',
    IapProduct.coins10000 => r'$9.99',
    IapProduct.coins17000 => r'$15.99',
    IapProduct.coins100000 => r'$84.99',
    IapProduct.noAds => r'$3.49',
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
  const IapEvent(this.product, this.status, [this.message, this.code]);

  final IapProduct product;
  final IapStatus status;

  /// For [IapStatus.failed]: a short player-facing reason ("Product not
  /// found", "Item unavailable", ...), shown as `Purchase failed: <reason>`.
  final String? message;

  /// For [IapStatus.failed]: a machine-readable code for analytics
  /// (`not_found`, `billing_unavailable`, a Billing response name, a plugin
  /// error code, ...).
  final String? code;

  @override
  String toString() =>
      'IapEvent(${product.name}, ${status.name}'
      '${message == null ? '' : ', $message'}'
      '${code == null ? '' : ' [$code]'})';
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

  /// Re-queries product details that are still missing (store not
  /// reachable at launch, products not yet live). Cheap when nothing is
  /// missing; called on app resume and when the Shop opens. Never throws.
  Future<void> refresh();

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
  Future<void> refresh() async {}

  @override
  bool get isAvailable => false;

  @override
  String priceOf(IapProduct p) => p.placeholderPrice;

  @override
  Stream<IapEvent> get events => _events.stream;

  @override
  Future<void> buy(IapProduct p) async {
    _events.add(IapEvent(p, IapStatus.failed, 'Store unavailable', 'noop'));
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

  /// Number of [refresh] calls (tests: resume / Shop open trigger it).
  int refreshes = 0;

  @override
  Future<void> refresh() async {
    refreshes++;
  }

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
        _events.add(IapEvent(p, IapStatus.failed, 'Fake error', 'fake'));
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

/// The slice of `in_app_purchase` that [StoreIapService] uses. The default
/// [PluginIapStore] forwards to `InAppPurchase.instance`; tests inject an
/// in-memory store so they never touch the plugin.
abstract class IapStore {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<bool> isAvailable();
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids);
  Future<bool> buyConsumable(PurchaseParam param);
  Future<bool> buyNonConsumable(PurchaseParam param);
  Future<void> completePurchase(PurchaseDetails purchase);
  Future<void> restorePurchases();
}

/// [IapStore] backed by the real plugin. `InAppPurchase.instance` is only
/// touched on first use, never at construction.
class PluginIapStore implements IapStore {
  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) =>
      _iap.queryProductDetails(ids);

  @override
  Future<bool> buyConsumable(PurchaseParam param) =>
      _iap.buyConsumable(purchaseParam: param, autoConsume: true);

  @override
  Future<bool> buyNonConsumable(PurchaseParam param) =>
      _iap.buyNonConsumable(purchaseParam: param);

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();
}

/// IAP diagnostics. Plain `print` on purpose: unlike `dart:developer`'s
/// `log`, it reaches logcat (tag `flutter`) in release builds too, so a
/// Play-installed build can be debugged with `adb logcat -s flutter`.
/// Product ids and store codes only — no PII.
void iapLog(String message) {
  // ignore: avoid_print
  print('[IAP] $message');
}

/// Short player-facing reason (shown as `Purchase failed: <reason>`) plus
/// a machine code for analytics, derived from a store error.
@visibleForTesting
({String reason, String code}) iapFailureFrom(IAPError error) {
  final message = error.message;
  // Android purchase errors carry the Billing response as the message
  // ("BillingResponse.itemUnavailable"); the code is generic.
  const prefix = 'BillingResponse.';
  if (message.startsWith(prefix)) {
    final name = message.substring(prefix.length);
    return (reason: _billingReasons[name] ?? _short(name), code: name);
  }
  return (
    reason: message.isEmpty ? 'Store error' : _short(message),
    code: error.code,
  );
}

const Map<String, String> _billingReasons = {
  'serviceTimeout': 'Store timeout',
  'featureNotSupported': 'Not supported',
  'serviceDisconnected': 'Store disconnected',
  'serviceUnavailable': 'No connection',
  'billingUnavailable': 'Billing unavailable',
  'itemUnavailable': 'Item unavailable',
  'developerError': 'Developer error',
  'error': 'Store error',
  'itemAlreadyOwned': 'Already owned',
  'itemNotOwned': 'Not owned',
  'networkError': 'Network error',
};

/// Short reason for an exception thrown by a plugin call.
({String reason, String code}) _failureFromException(Object e) {
  if (e is PlatformException) {
    final reason = switch (e.code) {
      'NOT_FOUND' => 'Product not found',
      'ACTIVITY_UNAVAILABLE' => 'App in background',
      _ => _short(e.code),
    };
    return (reason: reason, code: e.code);
  }
  if (e is TimeoutException) {
    return (reason: 'Store timeout', code: 'timeout');
  }
  return (reason: 'Store error', code: e.runtimeType.toString());
}

/// Keeps `Purchase failed: <reason>` inside the 320 pt playfield.
String _short(String text) =>
    text.length <= 18 ? text : '${text.substring(0, 17)}…';

/// Google Play Billing / StoreKit via `in_app_purchase` (through [IapStore]).
///
/// Listens to the plugin's purchase stream for the app's lifetime (started
/// in [initialize], i.e. at launch, so purchases completed while the app was
/// closed are delivered), maps each update to an [IapEvent] and acknowledges
/// it with `completePurchase`. Coin packs are bought with
/// `buyConsumable(autoConsume: true)`, No ads with `buyNonConsumable`.
///
/// Product details are queried at launch and re-queried when still missing:
/// on [refresh] (app resume, Shop open) and right before a [buy] — new Play
/// products can take a while to become queryable, and a single launch-time
/// query used to turn that into a permanent "Purchase failed". Only one
/// query runs at a time. Failures carry a short reason + code
/// ([IapEvent.message] / [IapEvent.code]).
///
/// Every plugin call is try/caught: the store must never take the game down.
class StoreIapService implements IapService {
  StoreIapService({
    IapStore? store,
    this.queryTimeout = const Duration(seconds: 5),
    this.launchErrorGrace = const Duration(seconds: 2),
  }) : _store = store ?? PluginIapStore();

  final IapStore _store;

  /// Upper bound for each isAvailable / queryProductDetails call.
  final Duration queryTimeout;

  /// When the billing flow fails to launch, Play usually also reports the
  /// response code on the purchase stream; wait this long for it before
  /// failing with the generic "Not started".
  final Duration launchErrorGrace;

  final StreamController<IapEvent> _events =
      StreamController<IapEvent>.broadcast();
  final Map<IapProduct, ProductDetails> _details = {};

  /// Kept alive for the app's lifetime on purpose (see class doc).
  // ignore: unused_field
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _initialized = false;
  bool _available = false;

  /// The running product query, if any (never two at once).
  Future<void>? _query;

  /// Store ids the last query reported as not found.
  final Set<String> _notFound = {};

  /// Why the last query could not load details (store-level problems).
  ({String reason, String code})? _queryFailure;

  /// The product whose billing flow was launched last and has not finished.
  /// Play reports flow errors / cancels with an EMPTY product id; they are
  /// attributed to this product.
  IapProduct? _buying;

  @override
  bool get isAvailable => _available;

  @override
  Stream<IapEvent> get events => _events.stream;

  @override
  String priceOf(IapProduct p) => _details[p]?.price ?? p.placeholderPrice;

  bool get _complete => _details.length == IapProduct.values.length;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    try {
      _purchaseSub = _store.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) => iapLog('stream error: $e'),
      );
    } catch (e) {
      iapLog('purchaseStream failed: $e');
    }
    await _queryMissing();
  }

  @override
  Future<void> refresh() async {
    if (!_initialized || (_available && _complete)) {
      return;
    }
    await _queryMissing();
  }

  /// Queries the details still missing; joins a query already running.
  Future<void> _queryMissing() =>
      _query ??= _runQuery().whenComplete(() => _query = null);

  Future<void> _runQuery() async {
    try {
      _available = await _store.isAvailable().timeout(queryTimeout);
    } catch (e) {
      iapLog('isAvailable failed: $e');
      _available = false;
      _queryFailure = e is TimeoutException
          ? (reason: 'Store timeout', code: 'timeout')
          : (reason: 'Store unavailable', code: 'is_available_error');
      return;
    }
    if (!_available) {
      iapLog('billing unavailable');
      _queryFailure = (
        reason: 'Store unavailable',
        code: 'billing_unavailable',
      );
      return;
    }
    final ids = {
      for (final p in IapProduct.values)
        if (!_details.containsKey(p)) p.storeId,
    };
    if (ids.isEmpty) {
      _queryFailure = null;
      return;
    }
    try {
      final response = await _store
          .queryProductDetails(ids)
          .timeout(queryTimeout);
      for (final d in response.productDetails) {
        final p = _productForStoreId(d.id);
        if (p != null) _details[p] = d;
      }
      _notFound
        ..removeAll(ids)
        ..addAll(response.notFoundIDs);
      final error = response.error;
      _queryFailure = error == null ? null : iapFailureFrom(error);
      iapLog(
        'query ${ids.length}: found ${response.productDetails.length}'
        '${response.notFoundIDs.isEmpty ? '' : ', notFound ${response.notFoundIDs}'}'
        '${error == null ? '' : ', error ${error.code} ${error.message}'}',
      );
    } catch (e) {
      // Includes a details conversion failure inside the plugin.
      iapLog('queryProductDetails failed: ${e.runtimeType}: $e');
      _notFound.removeAll(ids); // unknown now: report the error instead
      _queryFailure = _failureFromException(e);
    }
  }

  void _fail(IapProduct p, ({String reason, String code}) failure) {
    iapLog('buy ${p.storeId} failed: ${failure.code} (${failure.reason})');
    _events.add(IapEvent(p, IapStatus.failed, failure.reason, failure.code));
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final status = switch (purchase.status) {
        PurchaseStatus.pending => IapStatus.pending,
        PurchaseStatus.purchased => IapStatus.purchased,
        PurchaseStatus.restored => IapStatus.restored,
        PurchaseStatus.error => IapStatus.failed,
        PurchaseStatus.canceled => IapStatus.canceled,
      };
      final error = purchase.error;
      iapLog(
        'update ${purchase.productID.isEmpty ? '(none)' : purchase.productID}'
        ' ${status.name}'
        '${error == null ? '' : ' ${error.code} ${error.message}'}',
      );
      // Flow errors / cancels come without a product id: they belong to the
      // flow in progress. Never grant anything that way.
      final product =
          _productForStoreId(purchase.productID) ??
          (purchase.productID.isEmpty &&
                  (status == IapStatus.failed || status == IapStatus.canceled)
              ? _buying
              : null);
      if (product != null) {
        if (status != IapStatus.pending && product == _buying) {
          _buying = null;
        }
        if (status == IapStatus.failed) {
          _fail(
            product,
            error == null
                ? (reason: 'Store error', code: 'unknown')
                : iapFailureFrom(error),
          );
        } else {
          _events.add(IapEvent(product, status));
        }
      }
      // Acknowledge even unknown products: un-acknowledged Play purchases
      // are refunded after three days.
      if (purchase.pendingCompletePurchase) {
        try {
          await _store.completePurchase(purchase);
        } catch (e) {
          iapLog('completePurchase failed: $e');
        }
      }
    }
  }

  @override
  Future<void> buy(IapProduct p) async {
    if (!_available || !_details.containsKey(p)) {
      iapLog('buy ${p.storeId}: details missing, re-querying');
      await _queryMissing();
    }
    final details = _details[p];
    if (!_available || details == null) {
      _fail(
        p,
        !_available
            ? _queryFailure ??
                  (reason: 'Store unavailable', code: 'billing_unavailable')
            : _notFound.contains(p.storeId)
            ? (reason: 'Product not found', code: 'not_found')
            : _queryFailure ??
                  (reason: 'Product unavailable', code: 'no_details'),
      );
      return;
    }
    _buying = p;
    try {
      final param = PurchaseParam(productDetails: details);
      final started = p.consumable
          ? await _store.buyConsumable(param)
          : await _store.buyNonConsumable(param);
      iapLog('buy ${p.storeId}: launched=$started');
      if (!started && _buying == p) {
        // The response code normally follows on the purchase stream.
        Timer(launchErrorGrace, () {
          if (_buying != p) return;
          _buying = null;
          _fail(p, (reason: 'Not started', code: 'launch_failed'));
        });
      }
    } catch (e) {
      if (_buying == p) _buying = null;
      final failure = _failureFromException(e);
      // The plugin lost its native details cache: re-query next time.
      if (failure.code == 'NOT_FOUND') _details.remove(p);
      iapLog('buy ${p.storeId} threw ${e.runtimeType}');
      _fail(p, failure);
    }
  }

  @override
  Future<void> restore() async {
    if (!_available) {
      await refresh();
      if (!_available) return;
    }
    try {
      await _store.restorePurchases();
    } catch (e) {
      iapLog('restore failed: $e');
    }
  }
}
