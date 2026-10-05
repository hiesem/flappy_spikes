import 'dart:async';

import '../menu/menu_state.dart';
import '../menu/wallet.dart';
import '../services/game_services.dart';
import '../services/iap_service.dart';
import 'config.dart';

/// Grants what the store sells (PRD-1 §3.2, §3.5): listens to
/// [IapService.events] for the game's lifetime and turns each update into
/// coins / the No-ads flag, analytics and a toast (failures toast the
/// store's reason and log `iap_error`; cancels stay silent). Also tracks which
/// products have a purchase in flight (their buttons are disabled) and the
/// restore-purchases timeout.
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
  });

  final IapService iap;
  final MenuState menu;
  final GameServices services;

  /// Shows a short message (the game's showToast).
  final void Function(String text) toast;

  /// Called after No ads was bought or restored (closes the popup).
  final void Function()? onNoAdsGranted;

  StreamSubscription<IapEvent>? _sub;
  final Set<IapProduct> _inFlight = {};
  double? _restoreRemaining;
  bool _restoreGotEvent = false;

  /// Subscribes to the store's purchase updates (idempotent).
  void start() {
    _sub ??= iap.events.listen(_onEvent);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
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
    await iap.buy(product);
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
    switch (event.status) {
      case IapStatus.pending:
        _inFlight.add(product);
        toast('Purchase pending…');
      case IapStatus.purchased:
        _inFlight.remove(product);
        await _grantPurchase(product);
      case IapStatus.restored:
        _inFlight.remove(product);
        await _grantRestore(product);
      case IapStatus.failed:
        _inFlight.remove(product);
        final reason = event.message;
        services.track('iap_error', {
          'product': product.storeId,
          'reason': reason ?? 'unknown',
          'code': event.code ?? 'unknown',
        });
        toast(reason == null ? 'Purchase failed' : 'Purchase failed: $reason');
      case IapStatus.canceled:
        _inFlight.remove(product);
    }
  }

  Future<void> _grantPurchase(IapProduct product) async {
    if (product == IapProduct.noAds) {
      if (menu.noAds) {
        // Re-delivered (e.g. at launch): never grant the bonus twice.
        onNoAdsGranted?.call();
        return;
      }
      await menu.setNoAds(true);
      services.track('noads_purchased');
      // The purchase itself, like the coin packs.
      services.track('iap_purchase', {'product': product.storeId});
      onNoAdsGranted?.call();
      await menu.wallet.add(kNoAdsBonusCoins, CoinSource.noadsBonus);
      toast('Ads removed · +${formatAmount(kNoAdsBonusCoins)} coins');
      return;
    }
    services.track('iap_purchase', {'product': product.storeId});
    await menu.wallet.add(product.coins, CoinSource.iap);
    toast('+${formatAmount(product.coins)} coins');
  }

  Future<void> _grantRestore(IapProduct product) async {
    if (product != IapProduct.noAds) return; // consumables never restore
    _restoreGotEvent = true;
    _restoreRemaining = null;
    if (!menu.noAds) {
      await menu.setNoAds(true); // no bonus on restore
      onNoAdsGranted?.call();
    }
    toast('Purchases restored');
  }
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
