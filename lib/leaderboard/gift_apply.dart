import '../game/storage.dart';
import '../menu/wallet.dart';
import '../services/game_services.dart';
import '../skins/catalog.dart';
import '../skins/look.dart';
import 'lb_models.dart';
import 'lb_service.dart';

/// A resolved, already credited prize retained until LB7 finishes its reveal.
class AppliedLbGift {
  const AppliedLbGift({
    required this.id,
    required this.tier,
    required this.kind,
    required this.coins,
    required this.fallback,
    this.item,
    this.rarity,
  });

  final String id, tier, kind;
  final int coins;
  final bool fallback;
  final String? item, rarity;

  factory AppliedLbGift._read(Map<String, Object?> data) => AppliedLbGift(
    id: data['id'] as String,
    tier: data['tier'] as String,
    kind: data['kind'] as String,
    coins: data['coins'] as int,
    fallback: data['fallback'] as bool,
    item: data['item'] as String?,
    rarity: data['rarity'] as String?,
  );
}

/// One app-lifetime instance. Recover before other economy mutations on Home
/// or resume: the journal records absolute targets, as existing puzzle payouts
/// do. Only one unshown gift is kept; finish its reveal before claiming another.
class GiftApply {
  GiftApply({
    required this.storage,
    required this.wallet,
    required this.leaderboard,
    required this.services,
  });

  final GameStorage storage;
  final Wallet wallet;
  final LeaderboardService leaderboard;
  final GameServices services;
  final LbCallSerializer _lane = LbCallSerializer();

  Future<AppliedLbGift?> claim(String id) => _lane.run(() async {
    if (storage.lbGiftPending.isNotEmpty) return _recover();
    if (storage.lbGiftsClaimed.contains(id)) return null;
    LbClaimGiftResult? response;
    try {
      response = await leaderboard.claimGift(
        id,
        owned: allItems
            .where((i) => i.isFree || storage.ownedItems.contains(i.key))
            .map((i) => i.key)
            .toList(),
      );
    } catch (_) {
      return null;
    }
    final roll = response?.prize;
    final canonical = response?.id;
    final tier = response?.tier;
    if (response?.ok != true ||
        roll == null ||
        canonical == null ||
        canonical.isEmpty ||
        !{'bronze', 'silver', 'gold'}.contains(tier) ||
        !{'coins', 'feather', 'piece', 'item'}.contains(roll.kind) ||
        roll.coins <= 0 ||
        storage.lbGiftsClaimed.contains(canonical)) {
      return null;
    }
    var kind = roll.kind;
    SkinItem? item;
    if (kind == 'feather' && storage.feathers >= 3) kind = 'piece';
    // PRD-2.6 LB2/O68: meta gifts cannot complete a run puzzle.
    // As with G1's chest and G6d's Star Road, three held is the limit.
    final piecesHeld = [
      1,
      2,
      4,
      8,
    ].where((bit) => storage.puzzlePieces & bit != 0).length;
    if (kind == 'piece' && piecesHeld >= 3) kind = 'coins';
    if (kind == 'item') {
      for (final candidate in allItems) {
        if (candidate.key == roll.item &&
            candidate.price > 0 &&
            candidate.price <= 750 &&
            {Rarity.common, Rarity.rare}.contains(candidate.rarity) &&
            !storage.ownedItems.contains(candidate.key)) {
          item = candidate;
          break;
        }
      }
      // Only sold wardrobe items in the catalogue qualify. Card/skill keys
      // are absent from this catalogue and never become an ownership grant.
      if (item == null) kind = 'coins';
    }
    final piece = kind == 'piece'
        ? [1, 2, 4, 8].firstWhere((bit) => storage.puzzlePieces & bit == 0)
        : 0;
    await storage.saveLbGiftPending({
      'id': canonical,
      'request_id': id,
      'tier': tier!,
      'kind': kind,
      'coins': kind == 'coins' ? roll.coins : 0,
      'fallback': kind != roll.kind,
      if (item != null) 'item': item.key,
      if (item != null) 'rarity': item.rarity!.name,
      'target': switch (kind) {
        'coins' => wallet.balance + roll.coins,
        'feather' => storage.feathers + 1,
        'piece' => storage.puzzlePieces | piece,
        _ => 0,
      },
      'applied': false,
    });
    return _recover();
  });

  Future<AppliedLbGift?> recover() => _lane.run(_recover);

  Future<AppliedLbGift?> _recover() async {
    final data = storage.lbGiftPending;
    if (data.isEmpty) return null;
    final gift = AppliedLbGift._read(data);
    if (data['applied'] == true) return gift;
    // Durable seal must precede every reward mutation, including recovery.
    await storage.saveLbGiftsClaimed({
      ...storage.lbGiftsClaimed,
      gift.id,
      data['request_id'] as String,
    });
    final target = data['target'] as int;
    switch (gift.kind) {
      case 'coins':
        await wallet.add(target - wallet.balance, CoinSource.leaderboardGift);
      case 'feather':
        if (storage.feathers < target) await storage.saveFeathers(target);
      case 'piece':
        await storage.savePuzzlePieces(storage.puzzlePieces | target);
      case 'item':
        await storage.saveOwnedItems({...storage.ownedItems, gift.item!});
    }
    await storage.saveLbGiftPending({...data, 'applied': true});
    services.track('lb_gift_collect', {
      'tier': gift.tier,
      'kind': gift.kind,
      'coins': gift.coins,
      'rarity': gift.rarity ?? 'none',
      'fallback': gift.fallback ? 1 : 0,
    });
    return gift;
  }

  /// Call after showing the result. A stale popup cannot clear a newer gift.
  Future<void> markShown(String id) => _lane.run(() async {
    if (storage.lbGiftPending['id'] == id &&
        storage.lbGiftPending['applied'] == true) {
      await storage.saveLbGiftPending({});
    }
  });
}
