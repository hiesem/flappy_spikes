import 'dart:async';

import '../menu/menu_state.dart';
import '../menu/wallet.dart';
import '../services/game_services.dart';
import '../services/iap_service.dart';
import '../services/purchase_verifier.dart';
import 'config.dart';

/// Grants what the store sells (PRD-1 §3.2, §3.5): listens to
/// [IapService.events] for the game's lifetime and turns each update into
/// coins / the No-ads flag, analytics and feedback. Also tracks which
/// products have a purchase in flight (their buttons are disabled) and the
/// restore-purchases timeout.
///
/// Feedback (PRD-home-v3 §5–7) goes through the optional hooks; each one
/// left null falls back to the PRD-1 toast:
/// - [onPackPurchased]: a coin pack was bought — called right BEFORE the
///   coins are credited (so the pill can hold its number for the
///   celebration). Fallback toast "+1,800 coins".
/// - [onNoAdsPurchased]: a FRESH No-ads purchase (one the player started
///   with [Purchases.buy] in this session; never a restore, a store
///   re-delivery or an old receipt replayed as `purchased`) — called right
///   before the flag and the bonus are granted. Fallback toast "Ads removed · +1,000 coins".
/// - [onPurchaseProblem]: cancelled (always, also a user back-out) or
///   failed (any reason; `iap_error` is logged either way for failures).
///   Fallback: failures toast the store's reason, cancels stay silent.
/// A pending purchase toasts "Purchase pending…" (through [pendingToast]
/// when set) and completes later; [onResolved] fires as soon as that
/// product's purchase resolves (purchased / restored / failed / canceled),
/// before any other feedback, so the game can drop the pending toast.
///
/// Coin packs grant once per store transaction (S1-71): the ids in
/// [IapEvent.transactionIds] are persisted with the grant, and a later
/// `purchased` event carrying one of them is ignored (the store layer still
/// completes it so it stops re-delivering). After handling a `purchased` /
/// `restored` event, [IapEvent.granted] is completed.
///
/// PRD-2.3 §22 gift codes: [sync] (launch and every resume, at most once
/// per [Config.iapSyncInterval]) asks the store for purchases made outside
/// the game. A gift product, or a `no_ads` the player did not start here
/// and the store has not acknowledged yet (a promo code), is granted once
/// per purchase id and reported through [onGift]; a re-delivery of an
/// already granted / acknowledged one only restores No Ads, silently.
///
/// Plain Dart (no Flame), so it is unit-testable on its own; the game owns
/// one, [start]s it in onLoad, [dispose]s it in onRemove and drives the
/// restore timeout from its update loop ([update]).
class Purchases {
  Purchases({
    required this.iap,
    required this.menu,
    required this.services,
    required this.toast,
    this.onNoAdsGranted,
    this.onPackPurchased,
    this.onNoAdsPurchased,
    this.onPurchaseProblem,
    this.pendingToast,
    this.onResolved,
    this.onGift,
    DateTime Function()? clock,
    PurchaseVerifier? verifier,
  }) : _clock = clock ?? DateTime.now,
       verifier = verifier ?? PurchaseVerifier.instance;

  /// PRD-2.5 §3.8 WP-IAP: server verification after each grant (the
  /// app-wide [PurchaseVerifier.instance] unless a test passes one).
  final PurchaseVerifier verifier;

  final DateTime Function() _clock;

  /// PRD-2.3 §22.2 item 4: a gift code was granted (coins credited / No
  /// Ads on, already persisted): the game queues the gift popup.
  final void Function(GiftGrant gift)? onGift;

  final IapService iap;
  final MenuState menu;
  final GameServices services;

  /// Shows a short message (the game's showToast).
  final void Function(String text) toast;

  /// Called after No ads was bought or restored (closes the popup).
  final void Function()? onNoAdsGranted;

  /// See the class doc (PRD-home-v3 §5).
  final void Function(IapProduct product)? onPackPurchased;

  /// See the class doc (PRD-home-v3 §7).
  final void Function()? onNoAdsPurchased;

  /// See the class doc (PRD-home-v3 §6); [code] = the store error code.
  final void Function(
    IapProduct product,
    PurchaseProblem problem,
    String? code,
  )?
  onPurchaseProblem;

  /// Shows the "Purchase pending…" toast for [product] (null = [toast]).
  final void Function(IapProduct product, String text)? pendingToast;

  /// See the class doc.
  final void Function(IapProduct product)? onResolved;

  StreamSubscription<IapEvent>? _sub;
  final Set<IapProduct> _inFlight = {};

  /// Whether the player started a No-ads [buy] in this app session: only
  /// then is a `purchased` No ads fresh (celebration + bonus). Otherwise it
  /// is an old receipt replayed by the store (reinstall, launch delivery)
  /// and only restores ownership, like a restore.
  bool _noAdsBuyStarted = false;
  double? _restoreRemaining;
  bool _restoreGotEvent = false;

  /// Subscribes to the store's purchase updates (idempotent).
  void start() {
    _sub ??= iap.events.listen(_track);
    // PRD-2.5 §3.8: a refunded No Ads (no other No-Ads purchase known)
    // turns No Ads off; coins are never taken back.
    verifier.onNoAdsRevoked = _onNoAdsRevoked;
    unawaited(verifier.load());
  }

  Future<void> _onNoAdsRevoked() async {
    if (!menu.noAds) return;
    iapLog('No Ads refunded: turned off');
    await menu.setNoAds(false);
  }

  /// PRD-2.3 §24.3 (S8-13): the events being handled right now (grants
  /// still persisting).
  final Set<Future<void>> _handling = {};

  void _track(IapEvent event) {
    final f = _onEvent(event);
    _handling.add(f);
    // An error stays unhandled here, as with the plain listener before.
    unawaited(f.whenComplete(() => _handling.remove(f)));
  }

  /// The first [sync] of the session (the launch sync) until its store query
  /// has answered and the events it delivered are granted; null before.
  /// Never completes with an error.
  Future<void>? get launchSync => _launchSync;
  Future<void>? _launchSync;

  Future<void> _settle(Future<void> query) async {
    try {
      await query;
    } catch (_) {
      // The store layer logs its own failures.
    }
    // Events added during the query are delivered on later microtasks.
    await Future<void>.microtask(() {});
    while (_handling.isNotEmpty) {
      try {
        await Future.wait(List.of(_handling));
      } catch (_) {
        // A failed grant is reported by its own handler.
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    if (verifier.onNoAdsRevoked == _onNoAdsRevoked) {
      verifier.onNoAdsRevoked = null;
    }
  }

  /// Whether a purchase of [product] was started and has not finished
  /// (purchased / failed / canceled) yet — including store-side `pending`.
  bool isPending(IapProduct product) => _inFlight.contains(product);

  /// Whether a restore is waiting for the store.
  bool get restoring => _restoreRemaining != null;

  /// Starts buying [product]; ignored while one is already in flight. The
  /// outcome arrives on the event stream.
  Future<void> buy(IapProduct product) async {
    if (_inFlight.contains(product)) return;
    if (product == IapProduct.noAds && menu.noAds) {
      toast('Already ad-free');
      return;
    }
    _inFlight.add(product);
    if (product == IapProduct.noAds) _noAdsBuyStarted = true;
    await iap.buy(product);
  }

  DateTime? _lastSync;

  /// PRD-2.3 §22.2: [IapService.syncPurchases], at most once per
  /// [Config.iapSyncInterval]. Returns whether it ran.
  bool sync() {
    // PRD-2.5 §3.8: launch + every resume also check queued purchases with
    // the server (background, own backoff per item).
    unawaited(verifier.drain());
    final now = _clock();
    final last = _lastSync;
    if (last != null && now.difference(last) < Config.iapSyncInterval) {
      return false;
    }
    // Audit A3-5: the store layer skips a sync while a purchase flow is
    // open; such a sync does not use up the throttle.
    if (iap.purchaseInProgress) {
      iapLog('sync skipped: purchase in progress');
      return false;
    }
    _lastSync = now;
    final query = iap.syncPurchases();
    _launchSync ??= _settle(query);
    unawaited(query.catchError((Object _) {}));
    return true;
  }

  /// Restore purchases: an owned No ads comes back as a `restored` event;
  /// if nothing arrives within [Config.restoreTimeout] the player is told
  /// there was nothing to restore.
  Future<void> restore() async {
    if (restoring) return;
    _restoreRemaining = Config.restoreTimeout;
    _restoreGotEvent = false;
    await iap.restore();
  }

  /// Advances the restore timeout by [dt] seconds.
  void update(double dt) {
    final remaining = _restoreRemaining;
    if (remaining == null) return;
    final next = remaining - dt;
    if (next > 0) {
      _restoreRemaining = next;
      return;
    }
    _restoreRemaining = null;
    if (!_restoreGotEvent) toast('Nothing to restore');
  }

  Future<void> _onEvent(IapEvent event) async {
    final product = event.product;
    if (event.status != IapStatus.pending) onResolved?.call(product);
    if (_mayBeRevoked(event) && await _skipRevoked(event)) return;
    switch (event.status) {
      case IapStatus.pending:
        _inFlight.add(product);
        const text = 'Purchase pending…';
        final pending = pendingToast;
        if (pending != null) {
          pending(product, text);
        } else {
          toast(text);
        }
      case IapStatus.purchased || IapStatus.restored
          when product.isGift || _isPromoNoAds(event):
        _inFlight.remove(product);
        try {
          await _grantGift(event);
        } catch (e) {
          _confirm(event, error: e);
          rethrow;
        }
        _verify(event);
        _confirm(event);
      case IapStatus.purchased:
        _inFlight.remove(product);
        try {
          await _grantPurchase(product, event.transactionIds);
        } catch (e) {
          _confirm(event, error: e);
          rethrow;
        }
        _verify(event);
        _confirm(event);
      case IapStatus.restored:
        _inFlight.remove(product);
        try {
          // A consumable a sync brought back (its consume failed) is a
          // purchase not granted yet: once per id, like a fresh one.
          if (product.consumable && event.transactionIds.isNotEmpty) {
            await _grantPurchase(product, event.transactionIds);
          } else {
            await _grantRestore(product);
          }
        } catch (e) {
          _confirm(event, error: e);
          rethrow;
        }
        _verify(event);
        _confirm(event);
      case IapStatus.failed:
        _inFlight.remove(product);
        final reason = event.message;
        services.track('iap_error', {
          'product': product.storeId,
          'reason': reason ?? 'unknown',
          'code': event.code ?? 'unknown',
        });
        final problem = onPurchaseProblem;
        if (problem != null) {
          problem(product, PurchaseProblem.failed, event.code);
        } else {
          toast(
            reason == null ? 'Purchase failed' : 'Purchase failed: $reason',
          );
        }
      case IapStatus.canceled:
        _inFlight.remove(product);
        onPurchaseProblem?.call(product, PurchaseProblem.cancelled, null);
    }
  }

  /// PRD-2.5 §3.8: a No-Ads purchase whose id was refunded (the server said
  /// `revoked`) is not granted again when the store re-delivers it (the
  /// launch sync / a restore); it is only completed with the store.
  /// Synchronous (no extra async step) for every other event.
  bool _mayBeRevoked(IapEvent event) =>
      verifier.enabled &&
      (event.status == IapStatus.purchased ||
          event.status == IapStatus.restored) &&
      event.product.grantsNoAds &&
      event.transactionIds.isNotEmpty;

  Future<bool> _skipRevoked(IapEvent event) async {
    if (!verifier.loaded) await verifier.load();
    if (!verifier.isRevoked(event.transactionIds)) return false;
    iapLog('${event.product.storeId}: refunded purchase re-delivered, skipped');
    _inFlight.remove(event.product);
    _confirm(event);
    return true;
  }

  /// PRD-2.5 §3.8: the grant persisted, queue the server check (background;
  /// never awaited, never throws).
  void _verify(IapEvent event) {
    if (event.transactionIds.isEmpty) return;
    unawaited(
      verifier
          .enqueue(event.product, event.transactionIds)
          .catchError((Object _) {}),
    );
  }

  /// Tells the store layer the event was handled (it completes the
  /// purchase with the store next).
  ///
  /// S8-05: a grant that threw completes with the [error], so the store
  /// layer keeps the purchase (not consumed / acknowledged) for a retry.
  void _confirm(IapEvent event, {Object? error}) {
    final granted = event.granted;
    if (granted == null || granted.isCompleted) return;
    if (error == null) {
      granted.complete();
    } else {
      // Handled by the store layer; never an unhandled async error here.
      granted.future.ignore();
      granted.completeError(error);
    }
  }

  /// Transaction ids being granted right now (a re-delivery racing the
  /// first grant is skipped too).
  final Set<String> _granting = {};

  Future<void> _grantPurchase(
    IapProduct product, [
    List<String> transactionIds = const [],
  ]) async {
    if (product == IapProduct.noAds) {
      if (menu.noAds) {
        // Re-delivered (e.g. at launch): never grant the bonus twice.
        onNoAdsGranted?.call();
        return;
      }
      if (!_noAdsBuyStarted) {
        // Not bought in this session: an old receipt (reinstall / store
        // replay). Recover ownership silently — no celebration, no bonus.
        await menu.setNoAds(true);
        onNoAdsGranted?.call();
        return;
      }
      final celebrate = onNoAdsPurchased;
      celebrate?.call();
      await menu.setNoAds(true);
      services.track('noads_purchased');
      // The purchase itself, like the coin packs.
      services.track('iap_purchase', {'product': product.storeId});
      onNoAdsGranted?.call();
      await menu.wallet.add(kNoAdsBonusCoins, CoinSource.noadsBonus);
      if (celebrate == null) {
        toast('Ads removed · +${formatAmount(kNoAdsBonusCoins)} coins');
      }
      return;
    }
    // S1-71: one grant per store transaction. A re-delivery of an already
    // granted purchase (same purchaseID / token) is only acknowledged.
    final storage = menu.storage;
    if (transactionIds.any(_granting.contains) ||
        storage.isPurchaseGranted(transactionIds)) {
      return;
    }
    _granting.addAll(transactionIds);
    try {
      services.track('iap_purchase', {'product': product.storeId});
      final celebrate = onPackPurchased;
      celebrate?.call(product);
      await menu.wallet.add(product.coins, CoinSource.iap);
      // Coins first, then the id: a crash in between can at worst pay a
      // replay again, never lose a paid pack.
      if (transactionIds.isNotEmpty) {
        await storage.saveGrantedPurchase(transactionIds);
      }
      if (celebrate == null) toast('+${formatAmount(product.coins)} coins');
    } finally {
      _granting.removeAll(transactionIds);
    }
  }

  Future<void> _grantRestore(IapProduct product) async {
    if (!product.grantsNoAds) return; // consumables never restore
    // PRD-2.3 §22.2: a restore the player did not ask for (the launch /
    // resume sync) is silent.
    final asked = restoring;
    _restoreGotEvent = true;
    _restoreRemaining = null;
    if (!menu.noAds) {
      await menu.setNoAds(true); // no bonus on restore
      onNoAdsGranted?.call();
    }
    if (asked) toast('Purchases restored');
  }

  // region PRD-2.3 §22 — gift codes

  /// A `no_ads` purchase the player did not start in this session, that
  /// the store has not acknowledged yet, on a phone without No Ads: a
  /// promo code redeemed in the store (§22.2 "no_ads from a code": the
  /// normal No Ads path with its 1 000 bonus coins).
  bool _isPromoNoAds(IapEvent event) =>
      event.product == IapProduct.noAds &&
      !_noAdsBuyStarted &&
      event.acknowledged == false &&
      !menu.noAds &&
      !menu.storage.isPurchaseGranted(event.transactionIds);

  Future<void> _grantGift(IapEvent event) async {
    final product = event.product;
    final ids = event.transactionIds;
    final storage = menu.storage;
    final redelivery =
        ids.any(_granting.contains) ||
        storage.isPurchaseGranted(ids) ||
        // One-time gifts the store already acknowledged were granted
        // before (a reinstall wiped the ids): No Ads only, never coins.
        (!product.consumable && event.acknowledged == true);
    if (redelivery) {
      if (product.grantsNoAds) await _grantRestore(product);
      return;
    }
    _granting.addAll(ids);
    try {
      final coins = product == IapProduct.noAds
          ? kNoAdsBonusCoins
          : product.coins;
      final noAds = product.grantsNoAds && !menu.noAds;
      services.track('gift_redeemed', {
        'product': product.storeId,
        'source': 'promo',
      });
      // Like the packs: the popup hook runs right BEFORE the credit, so the
      // pill and the No Ads looks hold from the start.
      final gift = GiftGrant(product, coins: coins, noAds: noAds);
      final hook = onGift;
      hook?.call(gift);
      if (noAds) await menu.setNoAds(true);
      await menu.wallet.add(
        coins,
        CoinSource.gift,
      );
      // Coins first, then the id (as the packs).
      if (ids.isNotEmpty) await storage.saveGrantedPurchase(ids);
      if (noAds) onNoAdsGranted?.call();
      if (hook == null) {
        toast('A gift for you! +${formatAmount(coins)} coins');
      }
    } finally {
      _granting.removeAll(ids);
    }
  }
  // endregion PRD-2.3 §22
}

/// PRD-2.3 §22.2 item 4: one granted gift code — what its popup shows.
class GiftGrant {
  const GiftGrant(this.product, {required this.coins, required this.noAds});

  final IapProduct product;

  /// Coins credited with it (already in the wallet).
  final int coins;

  /// Whether it turned No Ads on.
  final bool noAds;

  @override
  String toString() => 'GiftGrant(${product.storeId}, $coins, noAds: $noAds)';
}

/// Why a store purchase did not complete (PRD-home-v3 §6).
enum PurchaseProblem {
  /// The player backed out of the store sheet (or the store says so).
  cancelled,

  /// Anything else: no connection, declined, item unavailable, ...
  failed;

  /// Analytics `outcome`.
  String get analyticsName => name;

  String get title => switch (this) {
    cancelled => 'PURCHASE CANCELLED',
    failed => 'PURCHASE FAILED',
  };

  String get message => switch (this) {
    cancelled => 'The purchase was cancelled.',
    failed => 'Your purchase could not be completed.',
  };

  String get smallLine => switch (this) {
    cancelled => 'You have not been charged.',
    failed => 'You have not been charged. Please try again later.',
  };
}

/// Formats an amount like the Shop mock ("1,800", "12,000").
String formatAmount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
