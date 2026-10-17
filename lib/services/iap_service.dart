import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show BillingResponse, PurchaseStateWrapper;
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    show GooglePlayPurchaseDetails, InAppPurchaseAndroidPlatformAddition;

import 'redact.dart';

/// Store products (Play Console / App Store Connect product IDs in
/// [IapProductInfo.storeId]).
///
/// PRD-2.3 §22.1: [giftCoins10000] and [giftNoAdsCoins10000] are gift-only
/// products, handed out with store promo codes. The game never sells or
/// shows them ([IapProductInfo.isGift]); it only knows them to grant them.
enum IapProduct {
  coins1000,
  coins10000,
  coins17000,
  coins100000,
  noAds,
  giftCoins10000,
  giftNoAdsCoins10000,
}

extension IapProductInfo on IapProduct {
  /// Store product ID.
  String get storeId => switch (this) {
    IapProduct.coins1000 => 'coins_1000',
    IapProduct.coins10000 => 'coins_10000',
    IapProduct.coins17000 => 'coins_17000',
    IapProduct.coins100000 => 'coins_100000',
    IapProduct.noAds => 'no_ads',
    IapProduct.giftCoins10000 => 'gift_coins_10000',
    IapProduct.giftNoAdsCoins10000 => 'gift_noads_coins_10000',
  };

  /// Coins granted by a coin pack or gift (0 for No ads — its bonus is
  /// [kNoAdsBonusCoins]). The No Ads gift's 10 000 are paid once, ever
  /// (PRD-2.3 §22.2).
  int get coins => switch (this) {
    IapProduct.coins1000 => 1000,
    IapProduct.coins10000 => 10000,
    IapProduct.coins17000 => 17000,
    IapProduct.coins100000 => 100000,
    IapProduct.noAds => 0,
    IapProduct.giftCoins10000 => 10000,
    IapProduct.giftNoAdsCoins10000 => 10000,
  };

  /// Coin packs and the coins gift are consumable; No ads and the No Ads
  /// gift are one-time (restorable) purchases.
  bool get consumable =>
      this != IapProduct.noAds && this != IapProduct.giftNoAdsCoins10000;

  /// PRD-2.3 §22.1: a gift-only product (promo codes; never in the Shop,
  /// never in a price query).
  bool get isGift =>
      this == IapProduct.giftCoins10000 ||
      this == IapProduct.giftNoAdsCoins10000;

  /// Whether owning it turns No Ads on.
  bool get grantsNoAds =>
      this == IapProduct.noAds || this == IapProduct.giftNoAdsCoins10000;

  /// Shown until (or unless) the store returns the localized price
  /// (PRD-menu-v4 §3; the values are PRD-2.2 §32.5's): a US-dollar
  /// placeholder ("$0.99"), used offline / before the products load / on
  /// Linux / in tests.
  String get placeholderPrice => switch (this) {
    IapProduct.coins1000 => r'$0.99',
    IapProduct.coins10000 => r'$8.99',
    IapProduct.coins17000 => r'$14.99',
    IapProduct.coins100000 => r'$79.99',
    IapProduct.noAds => r'$2.99',
    // Never shown (gift-only, PRD-2.3 §22.1).
    IapProduct.giftCoins10000 => '',
    IapProduct.giftNoAdsCoins10000 => '',
  };
}

/// The products the Shop sells and whose prices are queried for display
/// (PRD-2.3 §22.2 item 5: the gift products are left out).
final List<IapProduct> kShopProducts = [
  for (final p in IapProduct.values)
    if (!p.isGift) p,
];

/// Bonus coins granted together with the No-ads purchase (PRD-1 §3.5).
const int kNoAdsBonusCoins = 1000;

/// The plugin's error code for a consume Play refused
/// (`in_app_purchase_android` `kConsumptionFailedErrorCode`).
const String kConsumeFailedCode = 'consume_purchase_failed';

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
  const IapEvent(this.product, this.status, [this.message, this.code])
    : transactionIds = const [],
      granted = null,
      acknowledged = null;

  /// A store purchase update carrying the transaction identity.
  const IapEvent.store(
    this.product,
    this.status, {
    this.transactionIds = const [],
    this.granted,
    this.acknowledged,
  }) : message = null,
       code = null;

  /// PRD-2.3 §22.2: whether the store says this purchase was acknowledged
  /// (granted) before — on Google Play `Purchase.isAcknowledged`; null when
  /// the store does not tell (iOS, fakes). An acknowledged one-time
  /// purchase is a re-delivery (restore, reinstall): it restores
  /// ownership, never coins. `false` on a purchase the player did not
  /// start in this session = a promo code redeemed in the store.
  final bool? acknowledged;

  final IapProduct product;
  final IapStatus status;

  /// S1-71: the store identity of this transaction (purchaseID, and on
  /// Google Play also the purchase token; empty when the store gave none).
  /// A `purchased` coin pack whose id was granted before is a re-delivery
  /// of the same paid transaction and must not grant again.
  final List<String> transactionIds;

  /// Completed by the listener once the event was handled (coins granted
  /// and the transaction id persisted). [StoreIapService] waits for it
  /// (bounded) before it completes / consumes the purchase with the store:
  /// grant first, then acknowledge.
  final Completer<void>? granted;

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

  /// PRD-2.3 §22.2: looks for purchases made outside the game (promo codes
  /// redeemed in the Play Store) and for ones not yet granted or consumed;
  /// they arrive on [events] as `restored` and go through the normal
  /// granting (once per purchase id). Silent; the game calls it on launch
  /// and on every resume, at most once per [Config.iapSyncInterval] (the
  /// throttle lives in `Purchases.sync`). Never throws.
  Future<void> syncPurchases();
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

  @override
  Future<void> syncPurchases() async {}
}

/// A purchase the [FakeIapService] "store" holds (PRD-2.3 §22.6 tests): a
/// redeemed promo code until it is consumed / acknowledged.
class FakeHeldPurchase {
  FakeHeldPurchase(this.product, this.id, {this.acknowledged = false});
  final IapProduct product;
  final String id;
  bool acknowledged;
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
    _deliverHeld();
  }

  // region PRD-2.3 §22 — gift codes (fake store side)

  /// Purchases the fake store holds: promo codes redeemed with [redeem],
  /// until a consumable is consumed (it then leaves the list) — one-time
  /// products stay (acknowledged) and come back on every sync / restore.
  final List<FakeHeldPurchase> held = [];

  /// Ids of consumed purchases, in order.
  final List<String> consumed = [];

  /// Number of [syncPurchases] calls.
  int syncs = 0;

  /// A promo code for [product] redeemed in the store with purchase [id]
  /// (outside the game: it arrives on the next [syncPurchases]).
  void redeem(IapProduct product, String id) =>
      held.add(FakeHeldPurchase(product, id));

  /// Pushes [event] onto the purchase stream as the store would.
  void deliver(IapEvent event) => _events.add(event);

  @override
  Future<void> syncPurchases() async {
    syncs++;
    _deliverHeld();
  }

  void _deliverHeld() {
    for (final h in List.of(held)) {
      final granted = Completer<void>();
      _events.add(
        IapEvent.store(
          h.product,
          IapStatus.restored,
          transactionIds: ['id:${h.id}'],
          granted: granted,
          acknowledged: h.acknowledged,
        ),
      );
      // Like StoreIapService: grant first, then consume / acknowledge.
      granted.future.then((_) {
        if (h.product.consumable) {
          if (held.remove(h)) consumed.add(h.id);
        } else {
          h.acknowledged = true;
        }
      });
    }
  }
  // endregion PRD-2.3 §22
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

  /// PRD-2.3 §22.2: consumes a consumable purchase the game granted itself
  /// (the coins gift; `completePurchase` alone only acknowledges it on
  /// Android). Returns false where consuming does not apply (not Google
  /// Play): the caller completes the purchase instead.
  Future<bool> consumePurchase(PurchaseDetails purchase);
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
      // Owner 2026-10-13 (2.3.0 (17)): the game consumes coin packs itself,
      // once, after the grant ([StoreIapService]); the plugin's auto-consume
      // raced a resume sync that had already consumed the purchase and
      // turned a paid, credited pack into "Purchase failed".
      // StoreKit has no separate consume step (the storekit plugin asserts
      // autoConsume: true; finishing the transaction is the consume), so
      // iOS keeps the default.
      _iap.buyConsumable(
        purchaseParam: param,
        autoConsume: defaultTargetPlatform == TargetPlatform.iOS,
      );

  @override
  Future<bool> buyNonConsumable(PurchaseParam param) =>
      _iap.buyNonConsumable(purchaseParam: param);

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();

  @override
  Future<bool> consumePurchase(PurchaseDetails purchase) async {
    if (purchase is! GooglePlayPurchaseDetails) return false;
    final addition = _iap
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final result = await addition.consumePurchase(purchase);
    if (result.responseCode != BillingResponse.ok) {
      iapLog('consume ${purchase.productID}: ${result.responseCode}');
    }
    return true;
  }
}

/// IAP diagnostics. Plain `print` on purpose: unlike `dart:developer`'s
/// `log`, it reaches logcat (tag `flutter`) in release builds too, so a
/// Play-installed build can be debugged with `adb logcat -s flutter`.
/// Product ids and store codes only — no PII.
void iapLog(String message) {
  // ignore: avoid_print
  print('[IAP] ${redactSecrets(message)}'); // S7-18
}

/// The store identity of [purchase] (S1-71): its purchaseID (Play order id /
/// StoreKit transaction id) and, on Google Play, the purchase token. iOS
/// tokens are the whole app receipt (shared by every transaction), so they
/// are never used as an id.
@visibleForTesting
List<String> transactionIdsOf(PurchaseDetails purchase) {
  final ids = <String>[];
  final id = purchase.purchaseID;
  if (id != null && id.isNotEmpty) ids.add('id:$id');
  final data = purchase.verificationData;
  if (data.source == 'google_play' && data.serverVerificationData.isNotEmpty) {
    ids.add('token:${data.serverVerificationData}');
  }
  return ids;
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
/// `buyConsumable(autoConsume: false)` and consumed by this service after the
/// grant, No ads with `buyNonConsumable`.
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
    this.grantTimeout = const Duration(seconds: 5),
  }) : _store = store ?? PluginIapStore();

  /// Upper bound for waiting on [IapEvent.granted]; an unconfirmed grant
  /// leaves the purchase with the store (S8-05), never completes it.
  final Duration grantTimeout;

  final IapStore _store;

  /// Upper bound for each isAvailable / queryProductDetails call.
  final Duration queryTimeout;

  /// When the billing flow fails to launch, Play usually also reports the
  /// response code on the purchase stream; wait this long for it before
  /// failing with the generic "Not started".
  final Duration launchErrorGrace;

  late final StreamController<IapEvent> _events =
      StreamController<IapEvent>.broadcast(onListen: _replayHeld);

  /// Audit A3-4 (iOS): App Store purchases delivered before anyone listened
  /// (StoreKit re-delivers an unfinished transaction at launch, possibly
  /// before the game subscribes). StoreKit's restore leaves consumables
  /// out, so no sync would bring them back: they are replayed to the first
  /// listener instead. Google Play purchases are not held: the launch sync
  /// re-delivers them (S8-05).
  final List<PurchaseDetails> _held = [];

  void _replayHeld() {
    if (_held.isEmpty) return;
    final held = List.of(_held);
    _held.clear();
    iapLog('replaying ${held.length} held purchase(s)');
    scheduleMicrotask(() => unawaited(_onPurchases(held)));
  }
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

  bool get _complete => _details.length == kShopProducts.length;

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
    if (_syncWanted) {
      _syncWanted = false;
      await syncPurchases();
    }
    // PRD-2.3 §24.3 (S8-13): a sync asked for before initialization
    // completes once the deferred sync has run.
    final deferred = _deferredSync;
    _deferredSync = null;
    if (deferred != null && !deferred.isCompleted) deferred.complete();
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
    // PRD-2.3 §22.2 item 5: never the gift products.
    final ids = {
      for (final p in kShopProducts)
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
    // Owner 2026-10-13 (2.3.0 (16)) gift diagnosis: every delivery from the
    // store, also an empty one, with each purchase's product, plugin status,
    // Play state and acknowledgement (never tokens or order ids).
    iapLog('purchases ${purchases.length}');
    for (final purchase in purchases) {
      final playState = purchase is GooglePlayPurchaseDetails
          ? purchase.billingClientPurchase.purchaseState
          : null;
      iapLog(
        'purchase ${purchase.productID.isEmpty ? '(none)' : purchase.productID}'
        ' status=${purchase.status.name}'
        ' play=${playState?.name ?? '-'}'
        ' ack=${purchase is GooglePlayPurchaseDetails ? purchase.billingClientPurchase.isAcknowledged : '-'}'
        ' complete=${purchase.pendingCompletePurchase}',
      );
      // PRD-2.3 §22.2: the plugin's restorePurchases (our sync) marks
      // every owned purchase `restored`, also one still waiting for
      // payment: that one is pending, never granted.
      final status = playState == PurchaseStateWrapper.pending
          ? IapStatus.pending
          : switch (purchase.status) {
              PurchaseStatus.pending => IapStatus.pending,
              PurchaseStatus.purchased => IapStatus.purchased,
              PurchaseStatus.restored => IapStatus.restored,
              PurchaseStatus.error => IapStatus.failed,
              PurchaseStatus.canceled => IapStatus.canceled,
            };
      if (status == IapStatus.pending && playState != null) {
        // Nothing to grant or acknowledge until it is paid.
        iapLog('pending ${purchase.productID}: skipped until paid');
        if (_productForStoreId(purchase.productID) case final p?) {
          if (purchase.status != PurchaseStatus.restored) {
            _events.add(IapEvent(p, IapStatus.pending));
          }
        }
        continue;
      }
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
        if (status == IapStatus.failed && error?.code == kConsumeFailedCode) {
          // 2.3.0 (17): a consume Play refused (already consumed by a sync)
          // is no purchase failure: the purchase was paid and granted.
          iapLog('consume refused for ${product.storeId}: ignored');
        } else if (status == IapStatus.failed) {
          _fail(
            product,
            error == null
                ? (reason: 'Store error', code: 'unknown')
                : iapFailureFrom(error),
          );
        } else if (status == IapStatus.purchased ||
            status == IapStatus.restored) {
          final granted = Completer<void>();
          final hasListener = _events.hasListener;
          _events.add(
            IapEvent.store(
              product,
              status,
              transactionIds: transactionIdsOf(purchase),
              granted: granted,
              acknowledged: purchase is GooglePlayPurchaseDetails
                  ? purchase.billingClientPurchase.isAcknowledged
                  : null,
            ),
          );
          // Grant before completing (S1-71): if the app dies first, the
          // store re-delivers and the persisted id stops a double grant.
          // S8-05 (PRD-2.3 §22.2): consume / acknowledge ONLY after the
          // listener confirmed the grant was credited and saved. With no
          // listener yet (a delivery during start-up), a failed grant or a
          // timeout, the purchase is left with the store: the launch sync
          // (or the next one) delivers it again.
          var confirmed = false;
          if (hasListener) {
            try {
              await granted.future.timeout(grantTimeout);
              confirmed = true;
            } catch (_) {
              iapLog('grant of ${product.storeId} not confirmed in time');
            }
          } else if (purchase.verificationData.source == 'app_store') {
            iapLog('grant of ${product.storeId}: no listener yet, held');
            final id = purchase.purchaseID;
            _held
              ..removeWhere((h) => id != null && h.purchaseID == id)
              ..add(purchase);
          } else {
            iapLog('grant of ${product.storeId}: no listener yet, kept');
          }
          if (!confirmed) continue;
        } else {
          _events.add(IapEvent(product, status));
        }
      }
      // PRD-2.3 §22.2: a granted consumable that the plugin did not
      // auto-consume (a coins gift from a promo code, or a pack whose
      // consume failed and that a sync brought back) is consumed now, so
      // the same player can redeem another code for it; consuming also
      // acknowledges it on Google Play.
      // 2.3.0 (17): every granted consumable is consumed here (the plugin
      // no longer auto-consumes coin packs).
      if (product != null &&
          product.consumable &&
          (status == IapStatus.purchased || status == IapStatus.restored)) {
        try {
          if (await _store.consumePurchase(purchase)) continue;
        } catch (e) {
          iapLog('consumePurchase failed: $e');
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

  /// A sync asked for before [initialize] subscribed to the stream: runs
  /// right after it.
  bool _syncWanted = false;

  /// Completes when the sync deferred until [initialize] has run.
  Completer<void>? _deferredSync;

  @override
  Future<void> syncPurchases() async {
    if (!_initialized) {
      _syncWanted = true;
      return (_deferredSync ??= Completer<void>()).future;
    }
    if (!_available) {
      await _queryMissing();
      if (!_available) return;
    }
    // 2.3.0 (17): never while a purchase flow is open: its own result
    // grants and consumes it; a sync on the resume that closes the Play
    // sheet raced it (double consume → a false "Purchase failed").
    if (_buying != null) {
      iapLog('sync skipped: purchase in progress');
      return;
    }
    try {
      iapLog('sync');
      await _store.restorePurchases();
    } catch (e) {
      iapLog('sync failed: $e');
    }
  }
}
