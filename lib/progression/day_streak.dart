import 'dart:math' as math;

import '../menu/wallet.dart';
import '../run/config/tuning_values.dart';

/// A calendar-day ordinal, independent of DST and of the clock's time of day.
/// Pass a local DateTime (or one converted to the player's local timezone).
int streakLocalDay(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

enum StreakRewardItem { bigHoops, shield, feather, piece }

/// An instruction to the caller, not a wallet/inventory mutation. Free starts
/// must be persisted by the caller until consumed by the next run (G2b).
class StreakReward {
  const StreakReward({this.coins = 0, this.item});

  final int coins;
  final StreakRewardItem? item;
  CoinSource get coinSource => CoinSource.streak;
}

enum StreakRestoreMethod { rewardedVideo, coins }

class StreakRestorePayment {
  const StreakRestorePayment(this.method, this.coins, this.enabled);

  final StreakRestoreMethod method;
  final int coins;
  final bool enabled;
  CoinSource get coinSource => CoinSource.streakRestore;
}

/// Immutable, side-effect-free G2 state, using exactly the five S0 storage keys.
/// Hydrate these fields from storage and persist each returned transition before
/// presenting its effects. No achievement streak keys are read or changed.
///
/// [today] parameters are [streakLocalDay] ordinals. [runNumber] is the current
/// run's 1-based lifetime number (on Home, gamesPlayed + 1). Runs 1–3 are locked.
class DayStreak {
  const DayStreak({
    this.streakDays = 0,
    this.streakLastDay = -1,
    this.streakPaidDay = -1,
    this.streakLostDays = 0,
    this.streakLostSeenDay = -1,
  }) : assert(streakDays >= 0),
       assert(streakLostDays >= 0);

  final int streakDays;
  final int streakLastDay;
  final int streakPaidDay;
  final int streakLostDays;
  final int streakLostSeenDay;

  static bool unlocked(int runNumber) => runNumber >= 4;

  DayStreak _copy({int? days, int? last, int? paid, int? lost, int? seen}) =>
      DayStreak(
        streakDays: days ?? streakDays,
        streakLastDay: last ?? streakLastDay,
        streakPaidDay: paid ?? streakPaidDay,
        streakLostDays: lost ?? streakLostDays,
        streakLostSeenDay: seen ?? streakLostSeenDay,
      );

  /// Check at Home arrival and before every action. A break is consumed only
  /// once: zeroing k preserves an open offer across further idle days. A new
  /// nonzero k breaking REPLACES n, including after an earlier restore (O73).
  DayStreak refresh({required int today, required int runNumber}) {
    if (!unlocked(runNumber) || streakDays == 0 || today <= streakLastDay + 1) {
      return this;
    }
    return _copy(days: 0, lost: streakDays, seen: -1);
  }

  DayStreak finishRun({
    required int today,
    required int runNumber,
    bool debug = false,
  }) {
    if (debug || !unlocked(runNumber)) return this;
    final state = refresh(today: today, runNumber: runNumber);
    // Same-day runs and clock rollback never advance the streak.
    if (today <= state.streakLastDay) return state;
    return state._copy(days: state.streakDays + 1, last: today);
  }

  bool flewToday(int today) => streakDays > 0 && streakLastDay == today;

  bool rewardPending({required int today, required int runNumber}) =>
      unlocked(runNumber) && flewToday(today) && today > streakPaidDay;

  /// Returns the 1–7 track tile, wrapping each week.
  int get trackDay => streakDays == 0 ? 0 : (streakDays - 1) % 7 + 1;

  /// Inventory eligibility comes from the caller's existing inventory rules.
  /// Resolve at COLLECT, so a feather/piece acquired since opening is respected.
  static StreakReward rewardForDay(
    int days, {
    required bool canReceiveFeather,
    required bool canReceivePiece,
    TuningValues? tuning,
  }) {
    if (days < 1) throw ArgumentError.value(days, 'days');
    final track =
        (tuning ?? TuningValues.current).raw('streak_rewards') as List;
    final entry = track[(days - 1) % 7];
    if (entry is int) return StreakReward(coins: entry);
    return switch (entry) {
      'bighoops' => const StreakReward(item: StreakRewardItem.bigHoops),
      'shield' => const StreakReward(item: StreakRewardItem.shield),
      'feather+60' =>
        canReceiveFeather
            ? const StreakReward(coins: 60, item: StreakRewardItem.feather)
            : canReceivePiece
            ? const StreakReward(coins: 60, item: StreakRewardItem.piece)
            : const StreakReward(coins: 110),
      _ => throw StateError('Unsupported streak reward: $entry'),
    };
  }

  /// COLLECT is the sole payout transition. Persist the returned paid-day with
  /// the caller's payout; replaying that persisted state produces no reward.
  ({DayStreak state, StreakReward? reward}) collect({
    required int today,
    required int runNumber,
    required bool canReceiveFeather,
    required bool canReceivePiece,
    TuningValues? tuning,
  }) {
    final state = refresh(today: today, runNumber: runNumber);
    if (!state.rewardPending(today: today, runNumber: runNumber)) {
      return (state: state, reward: null);
    }
    final reward = rewardForDay(
      state.streakDays,
      canReceiveFeather: canReceiveFeather,
      canReceivePiece: canReceivePiece,
      tuning: tuning,
    );
    return (state: state._copy(paid: today), reward: reward);
  }

  bool shouldOfferLost({required int today, required int runNumber}) {
    final state = refresh(today: today, runNumber: runNumber);
    return unlocked(runNumber) &&
        state.streakLostDays > 0 &&
        today >= state.streakLastDay &&
        today > state.streakLostSeenDay;
  }

  DayStreak markLostShown({required int today, required int runNumber}) {
    final state = refresh(today: today, runNumber: runNumber);
    return state.shouldOfferLost(today: today, runNumber: runNumber)
        ? state._copy(seen: today)
        : state;
  }

  /// × (and a failed/incomplete ad) permits the next Home visit to retry today.
  /// Without dismissal, a still-pending offer returns on the next local day.
  DayStreak dismissLost({required int today, required int runNumber}) {
    final state = refresh(today: today, runNumber: runNumber);
    if (!unlocked(runNumber) || today < state.streakLastDay) return state;
    return state._copy(seen: -1);
  }

  StreakRestorePayment restorePayment({
    required bool noAds,
    required int coins,
    TuningValues? tuning,
  }) {
    if (!noAds) {
      return const StreakRestorePayment(
        StreakRestoreMethod.rewardedVideo,
        0,
        true,
      );
    }
    final price = (tuning ?? TuningValues.current).i('streak_restore_coins');
    return StreakRestorePayment(
      StreakRestoreMethod.coins,
      price,
      coins >= price,
    );
  }

  /// Invoke with paymentCompleted only after the rewarded callback or a
  /// successful CoinSource.streakRestore spend. [coins] is the pre-spend balance.
  /// No wallet write or ad request happens here (G2c owns those operations).
  DayStreak restore({
    required int today,
    required int runNumber,
    required bool noAds,
    required int coins,
    required bool paymentCompleted,
    TuningValues? tuning,
  }) {
    final state = refresh(today: today, runNumber: runNumber);
    if (!unlocked(runNumber) ||
        state.streakLostDays == 0 ||
        today < state.streakLastDay) {
      return state;
    }
    final payment = state.restorePayment(
      noAds: noAds,
      coins: coins,
      tuning: tuning,
    );
    if (!paymentCompleted || !payment.enabled) {
      return state.dismissLost(today: today, runNumber: runNumber);
    }
    return state._copy(
      days: state.streakLostDays + state.streakDays,
      last: math.max(state.streakLastDay, today - 1),
      lost: 0,
      seen: -1,
    );
  }

  DayStreak giveUp({required int today, required int runNumber}) {
    final state = refresh(today: today, runNumber: runNumber);
    if (!unlocked(runNumber) || today < state.streakLastDay) return state;
    return state._copy(lost: 0, seen: -1);
  }

  // S-28/29/30 and their O72 singular variants; the popup consumes these.
  String get lostMessage => streakLostDays == 1
      ? '1 day of day streak interrupted!'
      : '$streakLostDays days of day streak interrupted!';

  String restoreMessage({required bool noAds, TuningValues? tuning}) {
    final pronoun = streakLostDays == 1 ? 'it' : 'them';
    final price = (tuning ?? TuningValues.current).i('streak_restore_coins');
    return noAds
        ? 'Restore $pronoun for $price coins.'
        : 'Watch a video to restore $pronoun.';
  }
}
