import 'dart:math';

import '../game/storage.dart';
import '../levels/level_progress.dart';
import '../skins/item_store.dart';
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
  }) {
    wallet = Wallet(storage, onEarned: onEarned, onSpent: onSpent);
    items = ItemStore(storage, wallet);
    slot = PowerupSlot(storage, random: random);
    noAdsPopup = NoAdsPopupPolicy(storage);
    freeCoins = FreeCoinsPolicy(storage);
    levels = LevelProgress(storage, wallet);
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

  Future<void> setNoAds(bool value) => storage.saveNoAds(value);
}
