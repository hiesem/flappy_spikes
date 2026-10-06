import 'package:flutter/foundation.dart';

import '../game/storage.dart';
import '../menu/wallet.dart';
import 'catalog.dart';
import 'look.dart';

enum ItemPurchaseResult { purchased, alreadyOwned, insufficientCoins, unknown }

/// Owned/equipped wardrobe items plus purchases, persisted through
/// [GameStorage] (PRD-menu-v2 §3.5–3.7). Shaped like the PRD-1 `SkinStore`.
class ItemStore extends ChangeNotifier {
  ItemStore(this._storage, this._wallet);

  final GameStorage _storage;
  final Wallet _wallet;

  /// The equipped look, sanitised: an id that is unknown or no longer owned
  /// falls back to the layer's free default, so menus and runs never render a
  /// locked or removed item.
  Look get look {
    String resolve(SkinLayer layer) {
      final defaultId = defaultItemId(layer);
      final id = _storage.equippedItems[layer] ?? defaultId;
      if (itemById(layer, id) == null) return defaultId;
      return isOwned(layer, id) ? id : defaultId;
    }

    return Look(
      bird: resolve(SkinLayer.bird),
      gear: resolve(SkinLayer.gear),
      hat: resolve(SkinLayer.hat),
      hoop: resolve(SkinLayer.hoop),
      trail: resolve(SkinLayer.trail),
    );
  }

  /// Free items (including both "none" entries) are always owned.
  bool isOwned(SkinLayer layer, String id) {
    final item = itemById(layer, id);
    if (item == null) return false;
    if (item.isFree) return true;
    return _storage.ownedItems.contains(item.key);
  }

  bool isEquipped(SkinLayer layer, String id) => look.idFor(layer) == id;

  /// Equips [id] when it is owned; unowned ids are ignored. Persists at once.
  Future<void> equip(SkinLayer layer, String id) async {
    if (!isOwned(layer, id)) return;
    await _storage.saveEquippedItem(layer, id);
    notifyListeners();
  }

  /// Buys [id] and auto-equips it on success (§3.6).
  Future<ItemPurchaseResult> purchase(SkinLayer layer, String id) async {
    final item = itemById(layer, id);
    if (item == null) return ItemPurchaseResult.unknown;
    if (isOwned(layer, id)) return ItemPurchaseResult.alreadyOwned;
    if (_wallet.balance < item.price) {
      return ItemPurchaseResult.insufficientCoins;
    }
    final spent = await _wallet.spend(item.price, 'item:${item.key}');
    if (!spent) return ItemPurchaseResult.insufficientCoins;
    await _storage.saveOwnedItems({..._storage.ownedItems, item.key});
    await _storage.saveEquippedItem(layer, id);
    notifyListeners();
    return ItemPurchaseResult.purchased;
  }

  /// Coins still needed to buy [id] (0 when affordable / unknown).
  int shortfall(SkinLayer layer, String id) {
    final item = itemById(layer, id);
    if (item == null) return 0;
    final missing = item.price - _wallet.balance;
    return missing > 0 ? missing : 0;
  }

  /// Owned collectible items across all layers, out of [kCollectibleTotal].
  int get ownedCount => SkinLayer.values.fold(
        0,
        (count, layer) => count + ownedCountFor(layer),
      );

  /// Owned collectibles on [layer] (the "none" entries never count).
  int ownedCountFor(SkinLayer layer) => itemsFor(layer)
      .where((item) => !item.isNone && isOwned(layer, item.id))
      .length;

  /// Collectible items on [layer] (the "none" entries never count).
  int totalFor(SkinLayer layer) =>
      itemsFor(layer).where((item) => !item.isNone).length;

  /// NEW badge (§3.3): not owned, not seen, and either in the 2.0 update list
  /// or affordable right now.
  bool isNew(SkinLayer layer, String id) {
    final item = itemById(layer, id);
    if (item == null || isOwned(layer, id)) return false;
    if (_storage.seenItems.contains(item.key)) return false;
    return kNewInUpdate.contains(item.key) || item.price <= _wallet.balance;
  }

  Future<void> markSeen(SkinLayer layer, String id) async {
    final item = itemById(layer, id);
    if (item == null) return;
    await _storage.saveSeenItems({..._storage.seenItems, item.key});
    notifyListeners();
  }

  bool get hasNewBadge => SkinLayer.values.any(
        (layer) => itemsFor(layer).any((item) => isNew(layer, item.id)),
      );

  /// Clears every persisted menu field (the debug panel's "Reset menu
  /// state") and notifies, so live views — the home bird above all — render
  /// the defaults immediately instead of keeping the deleted outfit until
  /// their screen is rebuilt.
  Future<void> resetAll() async {
    await _storage.resetMenuState();
    notifyListeners();
  }

  /// Grants every catalogue item (debug panel / QA only).
  Future<void> grantAll() async {
    await _storage.saveOwnedItems({for (final item in allItems) item.key});
    notifyListeners();
  }
}
