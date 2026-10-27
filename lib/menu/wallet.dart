import 'package:flutter/foundation.dart';

import '../game/storage.dart';

/// Where coins came from (Firebase Analytics `coins_earned` source).
enum CoinSource {
  play,
  iap,
  rewarded,
  noadsBonus,
  levelReward,
  debug,
  // region WP-0b — PRD-2 §6 coins_earned sources
  hoop,
  perfect,
  winBonus,
  bonus,
  puzzle,
  switchRing,
  pair,
  train,
  bullseye,
  luckySpin,
  starTrail,
  piggy,
  jar,
  frenzy,
  // endregion WP-0b
  // PRD-2.3 §22.2: a gift-code product (gift_coins_10000 /
  // gift_noads_coins_10000).
  gift,
  // region P26-G5a
  weekly,
  // endregion
  // region P26-S0
  mission,
  missionChest,
  streak,
  streakRestore,
  firstWinDay,
  leaderboardGift,
  starRoad,
  album,
  // endregion
}

extension CoinSourceName on CoinSource {
  String get analyticsName => switch (this) {
        // region P26-G5a
        CoinSource.weekly => 'weekly',
        // endregion
        // region P26-S0
        CoinSource.mission => 'mission',
        CoinSource.missionChest => 'mission_chest',
        CoinSource.streak => 'streak',
        CoinSource.streakRestore => 'streak_restore',
        CoinSource.firstWinDay => 'first_win_day',
        CoinSource.leaderboardGift => 'leaderboard_gift',
        CoinSource.starRoad => 'star_road',
        CoinSource.album => 'album',
        // endregion

        CoinSource.play => 'play',
        CoinSource.iap => 'iap',
        CoinSource.rewarded => 'rewarded',
        CoinSource.noadsBonus => 'noads_bonus',
        // Call (ARCH §2.7): keeps its home-v3 name (PRD §6 lists `level`).
        CoinSource.levelReward => 'level_reward',
        CoinSource.debug => 'debug',
        CoinSource.hoop => 'hoop',
        CoinSource.perfect => 'perfect',
        CoinSource.winBonus => 'win_bonus',
        CoinSource.bonus => 'bonus',
        CoinSource.puzzle => 'puzzle',
        CoinSource.switchRing => 'switch',
        CoinSource.pair => 'pair',
        CoinSource.train => 'train',
        CoinSource.bullseye => 'bullseye',
        CoinSource.luckySpin => 'lucky_spin',
        CoinSource.starTrail => 'star_trail',
        CoinSource.piggy => 'piggy',
        CoinSource.jar => 'jar',
        CoinSource.frenzy => 'frenzy',
        CoinSource.gift => 'gift',
      };

  /// In-run sources: `coins_earned` for these is aggregated per source by
  /// the run's analytics router and sent once at run end (call, ARCH §2.7);
  /// every other source is tracked at once.
  bool get aggregatedInRun => switch (this) {
        CoinSource.hoop ||
        CoinSource.perfect ||
        CoinSource.switchRing ||
        CoinSource.pair ||
        CoinSource.train ||
        CoinSource.bullseye ||
        CoinSource.luckySpin ||
        CoinSource.starTrail ||
        CoinSource.piggy ||
        CoinSource.jar ||
        CoinSource.frenzy => true,
        _ => false,
      };
}

/// Coin balance persisted through [GameStorage].
class Wallet extends ChangeNotifier {
  Wallet(this._storage, {this.onEarned, this.onSpent});

  final GameStorage _storage;

  /// Called after coins are added, with the amount and its source.
  final void Function(int amount, CoinSource source)? onEarned;

  /// PRD-2.3 §14.8 called after coins are spent, with the amount and the
  /// analytics reason ([spendReason]): the `coins_spent` event.
  final void Function(int amount, String reason)? onSpent;

  /// PRD-2.3 §14.8 the `coins_spent` reason for a [spend] reason: `skin`
  /// for a shop item (`item:<layer>:<id>`), else the reason itself
  /// (`revive`, …).
  static String spendReason(String reason) =>
      reason.startsWith('item:') ? 'skin' : reason;

  int get balance => _storage.coins;

  // region P26-F1
  int get lifetimeCoinsEarned => _storage.lifetimeCoinsEarned;
  int get lifetimeCoinsSpent => _storage.lifetimeCoinsSpent;
  int get lifetimeCoinsBought => _storage.lifetimeCoinsBought;
  // endregion

  /// Adds [amount] coins. Zero or negative amounts are ignored.
  Future<void> add(int amount, CoinSource source) async {
    if (amount <= 0) return;
    // region P26-F1 — PRD 8.3-10: gifts earned, No-Ads bonus bought.
    final counter = source == CoinSource.iap || source == CoinSource.noadsBonus
        ? _storage.saveLifetimeCoinsBought(
            _storage.lifetimeCoinsBought + amount,
          )
        : _storage.saveLifetimeCoinsEarned(
            _storage.lifetimeCoinsEarned + amount,
          );
    // endregion
    await _storage.saveCoins(_storage.coins + amount);
    // region P26-F1
    await counter;
    // endregion
    notifyListeners();
    onEarned?.call(amount, source);
  }

  /// Spends [amount] coins. Returns false without changing anything when the
  /// balance is too low or [amount] is negative; zero is a true no-op.
  Future<bool> spend(int amount, String reason) async {
    if (amount < 0 || amount > _storage.coins) return false;
    if (amount == 0) return true;
    // region P26-F1
    final counter = _storage.saveLifetimeCoinsSpent(
      _storage.lifetimeCoinsSpent + amount,
    );
    // endregion
    await _storage.saveCoins(_storage.coins - amount);
    // region P26-F1
    await counter;
    // endregion
    notifyListeners();
    onSpent?.call(amount, spendReason(reason));
    return true;
  }
}
