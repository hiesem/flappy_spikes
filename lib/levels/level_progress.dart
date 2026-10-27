import 'dart:math';

import 'package:flutter/foundation.dart';

import '../game/storage.dart';
import '../menu/wallet.dart';
import '../services/game_services.dart';
import '../skins/catalog.dart';
import '../skins/item_store.dart';
import 'level_reward_roll.dart';
import 'level_track.dart';

/// Temporary aggregate for the 2.5 popup, until J5 supplies the reveal.
@immutable
class PendingLevelUp {
  const PendingLevelUp({
    required this.fromLevel,
    required this.toLevel,
    required this.reward,
  });
  final int fromLevel;
  final int toLevel;
  final int reward;
  TrackLevelDef get def => trackLevelDef(toLevel)!;
  @override
  bool operator ==(Object other) =>
      other is PendingLevelUp &&
      other.fromLevel == fromLevel &&
      other.toLevel == toLevel &&
      other.reward == reward;
  @override
  int get hashCode => Object.hash(fromLevel, toLevel, reward);
}

/// PRD-2.6 J3–J5. Only completed, eligible runs contribute points.
class LevelProgress extends ChangeNotifier {
  LevelProgress(
    this._storage,
    this._wallet, {
    ItemStore? items,
    Random? random,
    this.services,
  }) : _items = items ?? ItemStore(_storage, _wallet),
       _random = random ?? Random();
  final GameStorage _storage;
  final Wallet _wallet;
  final ItemStore _items;
  final Random _random;
  GameServices? services;
  int get best => _storage.bestScore;
  int get level => _storage.lvlIndex;
  int get points => _storage.lvlPoints;
  TrackLevelDef? get current => trackLevelDef(level);
  TrackLevelDef? get next => trackLevelDef(level + 1);
  List<Map<String, Object?>> get pending => List.unmodifiable([
    for (final row in _storage.lvlPending)
      Map<String, Object?>.unmodifiable(row),
  ]);
  PendingLevelUp? get pendingLevelUp => pending.isEmpty
      ? null
      : PendingLevelUp(
          fromLevel: (pending.first['lvl'] as int) - 1,
          toLevel: pending.last['lvl'] as int,
          reward: pending.fold(
            0,
            (sum, row) =>
                sum + (row['coins'] as int) + (row['extraCoins'] as int),
          ),
        );

  Future<int> recordRun(int score, {bool counts = true}) async {
    if (!counts) return level;
    final step = LevelTrack.step(level, points, score);
    if (step.levelledUp) {
      final roll = rollLevelReward(step.index, _storage.ownedItems, {
        for (final row in pending)
          if (row['item'] is String) row['item'] as String,
      }, _random);
      // Persist the roll first. load() recovers the index if killed between writes.
      final saved = _storage.saveLevelStep(
        index: step.index,
        points: 0,
        pending: [
          ...pending,
          {
            'lvl': step.index,
            'coins': trackLevelDef(step.index)!.coins,
            'item': roll.item,
            'extraCoins': roll.extraCoins,
            'fallback': roll.fallback,
          },
        ],
      );
      await saved;
      notifyListeners();
      services?.logLevelUp(
        step.index,
        games: _storage.gamesPlayed,
        runScore: score,
        sinceInstall:
            ((DateTime.now().millisecondsSinceEpoch - _storage.installAtMs) ~/
                    1000)
                .clamp(0, 1 << 53),
      );
    } else {
      await _storage.saveLvlPoints(step.points);
      notifyListeners();
    }
    services?.setUserProperty('fs_level', '$level');
    return level;
  }

  bool _paying = false;

  /// Target balance precedes grants and credit; pending clears before the target.
  /// Replaying any interrupted stage is idempotent, including item grants.
  Future<int> payPending() async {
    if (_paying) return 0;
    _paying = true;
    try {
      final rows = pending;
      if (rows.isEmpty) {
        if (_storage.lvlPayout != 0) await _storage.saveLvlPayout(0);
        return 0;
      }
      final total = pendingLevelUp!.reward;
      if (_storage.lvlPayout == 0) {
        await _storage.saveLvlPayout(_wallet.balance + total);
      }
      for (final row in rows) {
        final key = row['item'] as String?;
        if (key != null) await _items.grant(key);
      }
      final due = max(0, _storage.lvlPayout - _wallet.balance);
      await _wallet.add(due, CoinSource.levelReward);
      await _storage.saveLvlPending(const []);
      await _storage.saveLvlPayout(0);
      for (final row in rows) {
        final item = allItems
            .where((item) => item.key == row['item'])
            .firstOrNull;
        services?.logLevelRewardClaimed(
          row['lvl'] as int,
          (row['coins'] as int) + (row['extraCoins'] as int),
          itemLayer: item?.layer.key ?? 'none',
          rarity: item?.rarity?.name ?? 'none',
          fallback: row['fallback'] as String? ?? 'none',
        );
      }
      notifyListeners();
      return due;
    } finally {
      _paying = false;
    }
  }

  Future<int> claim() => payPending();
  Future<void> reset() async {
    await _storage.saveLvlPending(const []);
    await _storage.saveLvlPayout(0);
    await _storage.saveLvlIndex(0);
    await _storage.saveLvlPoints(0);
    notifyListeners();
  }

  Future<void> debugForceLevelUp() => recordRun(needFor(level)).then((_) {});
}
