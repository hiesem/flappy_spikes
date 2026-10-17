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

/// The stored player level (owner 2026-10-17, WP-L:
/// [GameStorage.playerLevel], one step per run, see [recordRun]) plus the
/// one-time rewards (`claimedLevels`), shaped like [ItemStore].
///
/// [pendingLevelUp] covers a fresh level-up (one step: one popup, its
/// reward) and the catch-up of every reached-but-unclaimed level <= the
/// stored one (an app kill before CLAIM, a debug reset of the claims).
class LevelProgress extends ChangeNotifier {
  LevelProgress(this._storage, this._wallet);

  final GameStorage _storage;
  final Wallet _wallet;

  int get best => _storage.bestScore;

  /// Current level (0 = unranked), the stored one.
  int get level => _storage.playerLevel.clamp(0, kMaxLevel);

  /// Current rank, null while unranked.
  LevelDef? get current => levelDef(level);

  /// The next rank to reach, null at LEGEND.
  LevelDef? get next => nextLevel(level);

  /// A run of [score] ended: the level steps up by one when the score
  /// reaches the next threshold ([levelAfterRun]); the new level is stored
  /// (its cache at once, before the first await). Returns the level after
  /// the run.
  Future<int> recordRun(int score) async {
    final before = level;
    final after = levelAfterRun(before, score);
    if (after == before) return before;
    final saved = _storage.savePlayerLevel(after);
    notifyListeners();
    await saved;
    return after;
  }

  /// "Delete my data" / debug resets: back to unranked.
  Future<void> reset() async {
    await _storage.savePlayerLevel(0);
    notifyListeners();
  }

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
  ///
  /// §3.14 (call, S6-22) the claim is recoverable: it records the balance
  /// its credit is to reach ([GameStorage.levelRewardPayout]) *before*
  /// marking the levels and crediting, and clears that record right after
  /// the credit (before [GameStorage.unclaimedLevelReward]). A kill
  /// anywhere in between is resumed at the next start and pays the rest
  /// exactly once — the reward is never lost and never paid twice.
  Future<int> claim() async {
    // A concurrent / re-entrant call pays nothing (the claim in flight
    // pays everything owed).
    if (_claimInFlight) return 0;
    _claimInFlight = true;
    try {
      return await _claim();
    } finally {
      _claimInFlight = false;
    }
  }

  Future<int> _claim() async {
    final pending = pendingLevelUp;
    if (pending == null) {
      // A killed claim that had already marked the levels: pay the rest
      // of the recorded credit (0 when it landed or there is no record).
      final rest = _owedPayout;
      if (rest <= 0) {
        // Nothing owed and nothing in flight: drop a stale record / flag.
        if (_storage.levelRewardPayout != 0 ||
            _storage.unclaimedLevelReward != 0) {
          await _storage.endLevelRewardClaim();
        }
        return 0;
      }
      await _wallet.add(rest, CoinSource.levelReward);
      await _storage.endLevelRewardClaim();
      notifyListeners();
      return rest;
    }
    final reward = pending.reward;
    // The record + claim go first (memory is updated before the first
    // await), then the credit, then the settle.
    await _storage.beginLevelRewardClaim(
      payout: _wallet.balance + reward,
      claimed: {
        ..._storage.claimedLevels,
        for (var l = 1; l <= pending.toLevel; l++) l,
      },
    );
    await _wallet.add(reward, CoinSource.levelReward);
    await _storage.endLevelRewardClaim();
    notifyListeners();
    return reward;
  }

  /// A claim in flight: a re-entrant / concurrent call pays nothing.
  bool _claimInFlight = false;

  /// §3.14 the part of an interrupted credit the wallet has not received
  /// yet ([GameStorage.levelRewardPayout] minus the balance).
  int get _owedPayout {
    final due = _storage.levelRewardPayout - _wallet.balance;
    return due > 0 ? due : 0;
  }

  /// Debug panel "LEVEL UP": raises the stored level by one (a pending
  /// level-up on the next home; the best rises to its threshold when below
  /// it). At LEGEND it un-claims the top level instead so the popup can be
  /// shown again.
  Future<void> debugForceLevelUp() async {
    final up = next;
    if (up != null) {
      await _storage.savePlayerLevel(up.level);
      if (_storage.bestScore < up.threshold) {
        await _storage.saveBestScore(up.threshold);
      }
    } else {
      await _storage.saveClaimedLevels(
        _storage.claimedLevels.difference({kMaxLevel}),
      );
    }
    notifyListeners();
  }
}
