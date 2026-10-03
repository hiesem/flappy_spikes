import 'dart:math';

import '../game/storage.dart';
import 'free_coins_policy.dart';
import 'noads_popup_policy.dart';
import 'powerup_slot.dart';
import 'skin_catalog.dart';
import 'wallet.dart';

/// Menu-side aggregate the game owns, built on a loaded [GameStorage].
class MenuState {
  MenuState(
    this.storage, {
    Random? random,
    void Function(int, CoinSource)? onEarned,
  }) {
    wallet = Wallet(storage, onEarned: onEarned);
    skins = SkinStore(storage, wallet);
    slot = PowerupSlot(storage, random: random);
    noAdsPopup = NoAdsPopupPolicy(storage);
    freeCoins = FreeCoinsPolicy(storage);
  }

  final GameStorage storage;
  late final Wallet wallet;
  late final SkinStore skins;
  late final PowerupSlot slot;
  late final NoAdsPopupPolicy noAdsPopup;
  late final FreeCoinsPolicy freeCoins;

  bool get noAds => storage.noAds;

  Future<void> setNoAds(bool value) => storage.saveNoAds(value);
}
