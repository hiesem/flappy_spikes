import 'package:flutter/foundation.dart';

import '../game/storage.dart';
import 'wallet.dart';

/// One purchasable bird skin. All bodies are stage-tinted; accessory skins
/// additionally draw a fixed-colour overlay on every frame.
class SkinDef {
  const SkinDef({
    required this.id,
    required this.name,
    required this.price,
    this.accessory = false,
  });

  final String id;
  final String name;
  final int price;
  final bool accessory;

  String get normal => id == 'pink' ? 'bird.png' : 'skins/$id.png';
  String get flap => id == 'pink' ? 'bird_flap.png' : 'skins/${id}_flap.png';
  String get dead => id == 'pink' ? 'bird_dead.png' : 'skins/${id}_dead.png';
  String? get overlay => accessory ? 'skins/${id}_acc.png' : null;
}

/// Display order and prices (BRIEF.md).
const List<SkinDef> kSkins = [
  SkinDef(id: 'pink', name: 'Pink', price: 0),
  SkinDef(id: 'blue', name: 'Sky', price: 100),
  SkinDef(id: 'green', name: 'Lime', price: 150),
  SkinDef(id: 'purple', name: 'Grape', price: 200),
  SkinDef(id: 'grey', name: 'Stone', price: 300),
  SkinDef(id: 'sand', name: 'Sand', price: 800),
  SkinDef(id: 'crown', name: 'King', price: 1000, accessory: true),
  SkinDef(id: 'tophat', name: 'Gentleman', price: 600, accessory: true),
  SkinDef(id: 'sunglasses', name: 'Cool', price: 500, accessory: true),
  SkinDef(id: 'headband', name: 'Ninja', price: 700, accessory: true),
  SkinDef(id: 'partyhat', name: 'Party', price: 450, accessory: true),
  SkinDef(id: 'ghost', name: 'Ghost', price: 900),
];

SkinDef? skinById(String id) {
  for (final skin in kSkins) {
    if (skin.id == id) return skin;
  }
  return null;
}

enum SkinPurchaseResult { purchased, alreadyOwned, insufficientCoins, unknown }

/// Owned/equipped skins plus purchases, persisted through [GameStorage].
class SkinStore extends ChangeNotifier {
  SkinStore(this._storage, this._wallet);

  final GameStorage _storage;
  final Wallet _wallet;

  String get equipped => _storage.equippedSkin;

  SkinDef get equippedSkin => skinById(equipped) ?? kSkins.first;

  bool isOwned(String id) => _storage.ownedSkins.contains(id);

  bool isEquipped(String id) => equipped == id;

  /// Not owned yet, affordable with the current balance and not seen.
  bool isNew(String id) {
    final skin = skinById(id);
    if (skin == null || isOwned(id)) return false;
    return skin.price <= _wallet.balance && !_storage.seenSkins.contains(id);
  }

  bool get hasNewBadge => kSkins.any((skin) => isNew(skin.id));

  /// Equips [id] when owned; unowned ids are ignored.
  Future<void> equip(String id) async {
    if (!isOwned(id)) return;
    await _storage.saveEquippedSkin(id);
    notifyListeners();
  }

  /// Buys [id] and auto-equips it on success.
  Future<SkinPurchaseResult> purchase(String id) async {
    final skin = skinById(id);
    if (skin == null) return SkinPurchaseResult.unknown;
    if (isOwned(id)) return SkinPurchaseResult.alreadyOwned;
    if (_wallet.balance < skin.price) {
      return SkinPurchaseResult.insufficientCoins;
    }
    final spent = await _wallet.spend(skin.price, 'skin:$id');
    if (!spent) return SkinPurchaseResult.insufficientCoins;
    await _storage.saveOwnedSkins({..._storage.ownedSkins, id});
    await _storage.saveEquippedSkin(id);
    notifyListeners();
    return SkinPurchaseResult.purchased;
  }

  /// Marks every currently-new skin as seen (clears the NEW badge).
  Future<void> markAllSeen() async {
    await _storage.saveSeenSkins({
      ..._storage.seenSkins,
      for (final skin in kSkins)
        if (isNew(skin.id)) skin.id,
    });
    notifyListeners();
  }
}
