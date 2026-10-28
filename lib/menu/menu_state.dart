import 'dart:math';

import '../game/config.dart';
import '../game/storage.dart';
import '../levels/level_progress.dart';
import '../skins/item_store.dart';
// region P26-F1
import '../skins/catalog.dart';
// endregion
import 'free_coins_policy.dart';
import 'noads_popup_policy.dart';
import 'powerup_slot.dart';
import 'wallet.dart';

/// Menu-side aggregate the game owns, built on a loaded [GameStorage].
class MenuState {
  MenuState(
    this.storage, {
    Random? random,
    void Function(int, CoinSource)? onEarned,
    void Function(int, String)? onSpent,
    // region P26-F1
    void Function(SkinItem, int, int, int, bool)? onItemBought,
    // endregion
  }) {
    wallet = Wallet(storage, onEarned: onEarned, onSpent: onSpent);
    // region P26-F1
    items = ItemStore(storage, wallet, onItemBought: onItemBought);
    // endregion
    slot = PowerupSlot(storage, random: random);
    noAdsPopup = NoAdsPopupPolicy(storage);
    freeCoins = FreeCoinsPolicy(storage);
    // region P26-J2
    levels = LevelProgress(storage, wallet, items: items, random: random);
    // endregion
  }

  final GameStorage storage;
  late final Wallet wallet;

  /// PRD-menu-v2 wardrobe.
  late final ItemStore items;
  late final PowerupSlot slot;
  late final NoAdsPopupPolicy noAdsPopup;
  late final FreeCoinsPolicy freeCoins;

  /// PRD-home-v3 §4: ranks on the best score + one-time rewards.
  late final LevelProgress levels;

  bool get noAds => storage.noAds;

  // region P26-F1
  /// PRD-2.6 R8: the shared Shop and Skins unlock has three paths.
  static bool menuUnlocked(int best, int games, int level) =>
      best >= Config.menuUnlockBest ||
      games >= Config.menuUnlockGames ||
      level >= 1;

  bool get locked =>
      !menuUnlocked(storage.bestScore, storage.gamesPlayed, storage.lvlIndex);
  // endregion

  Future<void> setNoAds(bool value) => storage.saveNoAds(value);
}
