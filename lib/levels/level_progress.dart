import 'package:flutter/foundation.dart';

import '../game/storage.dart';
import '../menu/wallet.dart';
import 'levels.dart';

/// A LEVEL UP popup that is owed (PRD-home-v3 §4.3): the player is at
/// [toLevel] and the rewards of every reached-but-unclaimed level (all of
/// them <= [toLevel]) add up to [reward]. [fromLevel] is the highest level
/// already claimed below it (0 = none).
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

  LevelDef get def => levelDef(toLevel)!;

  @override
  bool operator ==(Object other) =>
      other is PendingLevelUp &&
      other.fromLevel == fromLevel &&
      other.toLevel == toLevel &&
      other.reward == reward;

  @override
  int get hashCode => Object.hash(fromLevel, toLevel, reward);

  @override
  String toString() => 'PendingLevelUp($fromLevel -> $toLevel, +$reward)';
}

/// Levels derived from [GameStorage.bestScore] plus the one-time rewards
/// (`claimedLevels`), shaped like [ItemStore]. The level itself is never
/// stored (§11) and never lost.
///
/// [pendingLevelUp] covers both a fresh level-up (a run crossed one or
/// more thresholds: one popup for the highest, rewards added) and the
/// catch-up for players who update with a best already past some levels
/// (claimed set empty: one popup paying everything reached).
class LevelProgress extends ChangeNotifier {
  LevelProgress(this._storage, this._wallet);

  final GameStorage _storage;
  final Wallet _wallet;

  int get best => _storage.bestScore;

  /// Current level (0 = unranked).
  int get level => levelFor(best);

  /// Current rank, null while unranked.
  LevelDef? get current => levelDef(level);

  /// The next rank to reach, null at LEGEND.
  LevelDef? get next => nextLevel(level);

  bool isClaimed(int level) => _storage.claimedLevels.contains(level);

  /// The owed popup, or null when every reached level is claimed.
  PendingLevelUp? get pendingLevelUp {
    final to = level;
    var reward = 0;
    var from = 0;
    var owed = false;
    for (var l = 1; l <= to; l++) {
      if (isClaimed(l)) {
        from = l;
      } else {
        owed = true;
        reward += levelDef(l)!.reward;
      }
    }
    if (!owed) return null;
    return PendingLevelUp(fromLevel: from, toLevel: to, reward: reward);
  }

  /// Pays the owed rewards (`wallet.add(reward, CoinSource.levelReward)`)
  /// and marks every level <= the current one claimed. Returns what was
  /// paid (0 when nothing was owed); a second call never pays again.
  Future<int> claim() async {
    final pending = pendingLevelUp;
    if (pending == null) return 0;
    // Mark first (saveClaimedLevels updates memory before its first
    // await): a re-entrant claim sees nothing owed.
    await _storage.saveClaimedLevels({
      ..._storage.claimedLevels,
      for (var l = 1; l <= pending.toLevel; l++) l,
    });
    await _wallet.add(pending.reward, CoinSource.levelReward);
    notifyListeners();
    return pending.reward;
  }

  /// Debug panel "LEVEL UP": raises the best to the next threshold (a
  /// pending level-up on the next home). At LEGEND it un-claims the top
  /// level instead so the popup can be shown again.
  Future<void> debugForceLevelUp() async {
    final up = next;
    if (up != null) {
      await _storage.saveBestScore(up.threshold);
    } else {
      await _storage.saveClaimedLevels(
        _storage.claimedLevels.difference({kMaxLevel}),
      );
    }
    notifyListeners();
  }
}
