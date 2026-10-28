import 'package:flutter/foundation.dart';

import '../game/storage.dart';
import '../menu/wallet.dart';
import 'catalog.dart';
import 'look.dart';

enum ItemPurchaseResult { purchased, alreadyOwned, insufficientCoins, unknown }

/// Owned/equipped wardrobe items plus purchases, persisted through
/// [GameStorage] (PRD-menu-v2 §3.5–3.7). Shaped like the PRD-1 `SkinStore`.
class ItemStore extends ChangeNotifier {
  // region P26-F1
  ItemStore(this._storage, this._wallet, {this.onItemBought});
  final void Function(SkinItem item, int balanceBefore, int games, int minutes, bool first)? onItemBought;
  // endregion

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
      // region P26-F9a
      card: _equippedCard,
      // endregion
    );
  }

  // region P26-F9a
  String get _equippedCard {
    var result = Look(
      card: sanitiseCard(_storage.equippedItems[SkinLayer.card]),
    );
    for (final kind in CardKind.values) {
      final id = result.cardIdFor(kind);
      if (id.isNotEmpty && !isOwned(SkinLayer.card, id)) {
        result = result.withCardItem(kind, '');
      }
    }
    return result.card;
  }
  // endregion

  /// Free items (including both "none" entries) are always owned.
  bool isOwned(SkinLayer layer, String id) {
    // region P26-F9a
    if (layer == SkinLayer.card && id.isEmpty) return true;
    // endregion
    final item = itemById(layer, id);
    if (item == null) return false;
    // region P26-F10a
    if (item.unlock case final unlock?) {
      return _storage.ach.unlocked.contains(unlock.key);
    }
    // endregion
    // region P26-F9a
    // Zero-priced skill cosmetics are not free gifts; F10a supplies unlocks.
    if (item.isFree && !item.isSkillOnly) return true;
    // endregion
    return _storage.ownedItems.contains(item.key);
  }

  // region P26-F9a
  bool isEquipped(SkinLayer layer, String id) {
    if (layer != SkinLayer.card) return look.idFor(layer) == id;
    final kind = itemById(layer, id)?.cardKind;
    return kind != null && look.cardIdFor(kind) == id;
  }

  Future<void> clearCard(CardKind kind) async {
    await _storage.saveEquippedItem(
      SkinLayer.card,
      look.withCardItem(kind, '').card,
    );
    notifyListeners();
  }
  // endregion

  /// Equips [id] when it is owned; unowned ids are ignored. Persists at once.
  Future<void> equip(SkinLayer layer, String id) async {
    if (!isOwned(layer, id)) return;
    await _storage.saveEquippedItem(layer, id);
    notifyListeners();
  }

  // region P26-J2
  /// Grants a persisted reward without equipping it. Replays are harmless.
  Future<void> grant(String key) async {
    // region P26-F10a
    if (!allItems.any((item) => item.key == key && !item.isSkillOnly)) {
      throw ArgumentError.value(key, 'key', 'Unknown reward item');
    }
    // endregion
    await _storage.saveOwnedItems({..._storage.ownedItems, key});
    notifyListeners();
  }
  // endregion

  /// Buys [id] and auto-equips it on success (§3.6).
  Future<ItemPurchaseResult> purchase(SkinLayer layer, String id) async {
    final item = itemById(layer, id);
    // region P26-F9a
    if (item == null || item.isSkillOnly) return ItemPurchaseResult.unknown;
    // endregion
    if (isOwned(layer, id)) return ItemPurchaseResult.alreadyOwned;
    if (_wallet.balance < item.price) {
      return ItemPurchaseResult.insufficientCoins;
    }
    // region P26-F1
    final balanceBefore = _wallet.balance;
    // endregion
    final spent = await _wallet.spend(item.price, 'item:${item.key}');
    if (!spent) return ItemPurchaseResult.insufficientCoins;
    await _storage.saveOwnedItems({..._storage.ownedItems, item.key});
    await _storage.saveEquippedItem(layer, id);
    // region P26-F1
    final first = !_storage.firstItemBought;
    if (first) await _storage.saveFirstItemBought(true);
    onItemBought?.call(item, balanceBefore, _storage.gamesPlayed,
        _storage.playtimeSeconds ~/ 60, first);
    // endregion
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
  // region P26-F9a
  int get ownedCount =>
      kShopLayers.fold(0, (count, layer) => count + ownedCountFor(layer));
  // endregion

  // region P26-F10a
  int get soldOwnedCount => allItems
      .where(
        (item) =>
            !item.isNone && !item.isSkillOnly && isOwned(item.layer, item.id),
      )
      .length;
  // endregion

  /// Owned collectibles on [layer] (the "none" entries never count).
  int ownedCountFor(SkinLayer layer) => itemsFor(
    layer,
  ).where((item) => !item.isNone && isOwned(layer, item.id)).length;

  /// Collectible items on [layer] (the "none" entries never count).
  int totalFor(SkinLayer layer) =>
      itemsFor(layer).where((item) => !item.isNone).length;

  /// NEW badge (§3.3): not owned, not seen, and either in the 2.3 update list
  /// or affordable right now.
  bool isNew(SkinLayer layer, String id) {
    final item = itemById(layer, id);
    // region P26-F10b
    if (item == null || _storage.seenItems.contains(item.key)) return false;
    if (item.isSkillOnly) return isOwned(layer, id);
    if (isOwned(layer, id)) return false;
    // endregion
    // region P26-F9a
    // endregion
    return kNewInUpdate.contains(item.key) || item.price <= _wallet.balance;
  }

  Future<void> markSeen(SkinLayer layer, String id) async {
    final item = itemById(layer, id);
    if (item == null) return;
    await _storage.saveSeenItems({..._storage.seenItems, item.key});
    notifyListeners();
  }

  // region P26-F9a
  bool get hasNewBadge => kShopLayers.any(
    (layer) => itemsFor(layer).any((item) => isNew(layer, item.id)),
  );

  // endregion

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
