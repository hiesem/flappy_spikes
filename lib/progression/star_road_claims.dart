// region P26-G6eB
import 'dart:async';
// endregion
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/storage.dart';
import '../menu/wallet.dart';
import '../services/obf_strings.g.dart';
import '../levels/level_reward_roll.dart';
import '../skins/item_store.dart';
import '../skins/look.dart';
import 'star_road.dart';

/// Journaled single-tier payout. The complete outcome and target values are
/// saved before any reward or claim marker is changed. Recovery is idempotent.
class StarRoadClaims {
  StarRoadClaims(this.storage, this.wallet, this.items, {Random? random})
    : random = random ?? Random();
  final GameStorage storage;
  final Wallet wallet;
  final ItemStore items;
  final Random random;
  bool _busy = false;
  // region P26-G6eB
  Completer<void>? _idle;
  Future<void> waitUntilIdle() => _idle?.future ?? Future<void>.value();
  void _beginBusy() { _busy = true; _idle = Completer<void>(); }
  void _endBusy() { _busy = false; final idle = _idle; _idle = null; idle?.complete(); }
  // endregion
  int _itemsSeason = 0;
  final Map<int, String> awardedItems = {};

  Future<void> _loadItems(SharedPreferences prefs) async {
    final raw = prefs.getString(Obf.prefStarRoadItems);
    if (raw == null) return;
    if (storage.starRoadSeason == 0) {
      awardedItems.clear();
      _itemsSeason = 0;
      await prefs.remove(Obf.prefStarRoadItems);
      return;
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    _itemsSeason = data['season'] as int;
    awardedItems.clear();
    if (_itemsSeason == storage.starRoadSeason) {
      final rows = data['items'] as Map<String, dynamic>;
      for (final entry in rows.entries) {
        final tier = int.tryParse(entry.key);
        if (tier != null && entry.value is String) {
          awardedItems[tier] = entry.value as String;
        }
      }
    }
  }

  Future<void> _saveItem(
    SharedPreferences prefs,
    int season,
    int tier,
    String item,
  ) async {
    if (_itemsSeason != season) {
      awardedItems.clear();
      _itemsSeason = season;
    }
    awardedItems[tier] = item;
    await prefs.setString(
      Obf.prefStarRoadItems,
      jsonEncode({
        'season': season,
        'items': {
          for (final entry in awardedItems.entries) '${entry.key}': entry.value,
        },
      }),
    );
  }

  StarRoad get road => StarRoad(
    season: storage.starRoadSeason,
    xp: storage.starRoadXp,
    claimed: storage.starRoadClaimed,
    popupDay: storage.starRoadPopupDay,
  );

  Future<StarRoadClaim?> claim(int tier) async {
    if (_busy) return null;
    // region P26-G6eB
    _beginBusy();
    // endregion
    try {
      await _recover();
      final outcome = road.claim(tier);
      final reward = outcome.reward;
      if (reward == null) return null;
      String kind = reward.kind.name;
      String? item;
      var coins = reward.kind == StarRoadRewardKind.coins ? reward.coins : 0;
      if (reward.kind == StarRoadRewardKind.feather && storage.feathers >= 3) {
        kind = 'coins';
        coins = reward.coins;
      }
      final pieces = [
        1,
        2,
        4,
        8,
      ].where((bit) => storage.puzzlePieces & bit != 0).length;
      if (reward.kind == StarRoadRewardKind.piece && pieces >= 3) {
        kind = 'coins';
        coins = reward.coins;
      }
      if ({
        StarRoadRewardKind.rare,
        StarRoadRewardKind.epic,
        StarRoadRewardKind.legendary,
      }.contains(reward.kind)) {
        final rarity = switch (reward.kind) {
          StarRoadRewardKind.rare => Rarity.rare,
          StarRoadRewardKind.epic => Rarity.epic,
          _ => Rarity.legendary,
        };
        final pending = {
          for (final row in storage.lvlPending)
            if (row['item'] is String) row['item'] as String,
        };
        // R9: exhaust the requested rarity first, then higher rarities.
        for (var r = rarity.index; r < Rarity.values.length; r++) {
          final candidates = eligibleProgressionItems(
            storage.ownedItems,
            pending,
          ).where((item) => item.rarity == Rarity.values[r]).toList();
          if (candidates.isNotEmpty) {
            item = candidates[random.nextInt(candidates.length)].key;
            break;
          }
        }
        if (item == null) {
          kind = 'coins';
          coins = reward.coins;
        } else {
          kind = 'item';
        }
      }
      final piece = kind == 'piece'
          ? [1, 2, 4, 8].firstWhere((bit) => storage.puzzlePieces & bit == 0)
          : 0;
      final journal = <String, Object?>{
        'season': road.season,
        'tier': tier,
        'kind': kind,
        'item': item,
        'coins': coins,
        'balance': wallet.balance + coins,
        'earned': storage.lifetimeCoinsEarned + coins,
        'feathers': storage.feathers + (kind == 'feather' ? 1 : 0),
        'pieces': storage.puzzlePieces | piece,
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(Obf.prefStarRoadJournal, jsonEncode(journal));
      await _apply(journal, prefs);
      return StarRoadClaim(tier: tier, kind: kind, coins: coins, item: item);
    } finally {
      // region P26-G6eB
      _endBusy();
      // endregion
    }
  }

  Future<void> recover() async {
    if (_busy) return;
    // region P26-G6eB
    _beginBusy();
    // endregion
    try {
      await _recover();
    } finally {
      // region P26-G6eB
      _endBusy();
      // endregion
    }
  }

  Future<void> _recover() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadItems(prefs);
    final encoded = prefs.getString(Obf.prefStarRoadJournal);
    if (encoded == null) return;
    final data = Map<String, Object?>.from(jsonDecode(encoded) as Map);
    await _apply(data, prefs);
  }

  Future<void> _apply(Map<String, Object?> j, SharedPreferences prefs) async {
    final tier = j['tier'] as int;
    final season = j['season'] as int;
    // region P26-G6eB
    // Save the actual outcome to the rollover summary before applying it; the
    // claim journal replays this step if the process dies between the two.
    final rollover = prefs.getString(Obf.prefStarRoadRollover);
    if (rollover != null) {
      final data = jsonDecode(rollover) as Map<String, dynamic>;
      if (data['pending'] == true && data['from'] == season) {
        final awards = Map<String, dynamic>.from(data['awards'] as Map? ?? {});
        awards['$tier'] = {'kind': j['kind'], 'coins': j['coins'], 'item': j['item']};
        data['awards'] = awards;
        await prefs.setString(Obf.prefStarRoadRollover, jsonEncode(data));
      }
    }
    // endregion
    if (storage.starRoadSeason == season && j['kind'] == 'item') {
      await _saveItem(prefs, season, tier, j['item'] as String);
    }
    if (storage.starRoadSeason == season) {
      await storage.saveStarRoadClaimed({...storage.starRoadClaimed, tier});
    }
    switch (j['kind']) {
      case 'coins':
        await wallet.settleStarRoad(
          balance: j['balance'] as int,
          earned: j['earned'] as int,
        );
      case 'item':
        await items.grant(j['item'] as String);
      case 'feather':
        if (storage.feathers < (j['feathers'] as int)) {
          await storage.saveFeathers(j['feathers'] as int);
        }
      case 'piece':
        await storage.savePuzzlePieces(
          storage.puzzlePieces | (j['pieces'] as int),
        );
    }
    await prefs.remove(Obf.prefStarRoadJournal);
  }
}

class StarRoadClaim {
  const StarRoadClaim({
    required this.tier,
    required this.kind,
    required this.coins,
    required this.item,
  });
  final int tier, coins;
  final String kind;
  final String? item;
}
