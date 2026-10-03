import 'package:flutter/foundation.dart';

import '../game/storage.dart';

/// Where coins came from (Firebase Analytics `coins_earned` source).
enum CoinSource { play, iap, rewarded, noadsBonus, debug }

extension CoinSourceName on CoinSource {
  String get analyticsName => switch (this) {
        CoinSource.play => 'play',
        CoinSource.iap => 'iap',
        CoinSource.rewarded => 'rewarded',
        CoinSource.noadsBonus => 'noads_bonus',
        CoinSource.debug => 'debug',
      };
}

/// Coin balance persisted through [GameStorage].
class Wallet extends ChangeNotifier {
  Wallet(this._storage, {this.onEarned});

  final GameStorage _storage;

  /// Called after coins are added, with the amount and its source.
  final void Function(int amount, CoinSource source)? onEarned;

  int get balance => _storage.coins;

  /// Adds [amount] coins. Zero or negative amounts are ignored.
  Future<void> add(int amount, CoinSource source) async {
    if (amount <= 0) return;
    await _storage.saveCoins(_storage.coins + amount);
    notifyListeners();
    onEarned?.call(amount, source);
  }

  /// Spends [amount] coins. Returns false without changing anything when the
  /// balance is too low or [amount] is negative; zero is a true no-op.
  Future<bool> spend(int amount, String reason) async {
    if (amount < 0 || amount > _storage.coins) return false;
    if (amount == 0) return true;
    await _storage.saveCoins(_storage.coins - amount);
    notifyListeners();
    return true;
  }
}
