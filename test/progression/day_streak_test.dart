import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/progression/day_streak.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flutter_test/flutter_test.dart';

({DayStreak state, StreakReward? reward}) collect(DayStreak state, int today) =>
    state.collect(
      today: today,
      runNumber: 4,
      canReceiveFeather: true,
      canReceivePiece: true,
    );

void main() {
  test('local calendar ordinals cross midnight, month, year and DST dates', () {
    for (final date in [
      DateTime(2026, 3, 29),
      DateTime(2026, 10, 25),
      DateTime(2026, 12, 31),
      DateTime(2028, 2, 29),
    ]) {
      final late = DateTime(date.year, date.month, date.day, 23, 59);
      final next = DateTime(date.year, date.month, date.day + 1);
      expect(streakLocalDay(late), streakLocalDay(date));
      expect(streakLocalDay(next), streakLocalDay(date) + 1);
    }
  });

  test('one finished run per day, every mode uses the same transition', () {
    var state = const DayStreak();
    expect(state.trackDay, 0);
    for (var day = 100; day < 115; day++) {
      state = state.finishRun(today: day, runNumber: 4);
      expect(state.streakDays, day - 99);
      expect(state.streakLastDay, day);
      expect(state.trackDay, (day - 100) % 7 + 1);
      expect(state.flewToday(day), isTrue);
      expect(state.finishRun(today: day, runNumber: 5), same(state));
    }
    expect(state.flewToday(115), isFalse);
    expect(state.refresh(today: 115, runNumber: 4), same(state));
  });

  test('a missed day breaks immediately, with no automatic bridge', () {
    const before = DayStreak(streakDays: 7, streakLastDay: 100);
    final broken = before.refresh(today: 102, runNumber: 4);
    expect(broken.streakDays, 0);
    expect(broken.streakLostDays, 7);
    expect(broken.flewToday(102), isFalse);
    final run = before.finishRun(today: 102, runNumber: 4);
    expect(run.streakDays, 1);
    expect(run.streakLostDays, 7);
    expect(run.streakLastDay, 102);
  });

  test('runs 1–3 and debug runs do not advance or offer rewards', () {
    for (var run = 1; run <= 3; run++) {
      const state = DayStreak();
      expect(state.finishRun(today: 100, runNumber: run), same(state));
      const seeded = DayStreak(streakDays: 1, streakLastDay: 100);
      expect(seeded.rewardPending(today: 100, runNumber: run), isFalse);
      expect(
        seeded
            .collect(
              today: 100,
              runNumber: run,
              canReceiveFeather: true,
              canReceivePiece: true,
            )
            .reward,
        isNull,
      );
    }
    const state = DayStreak(streakDays: 5, streakLastDay: 100);
    expect(state.finishRun(today: 103, runNumber: 4, debug: true), same(state));
  });

  test('clock rollback cannot extend, break, pay or lower the last day', () {
    const state = DayStreak(
      streakDays: 5,
      streakLastDay: 100,
      streakPaidDay: 100,
    );
    expect(state.finishRun(today: 99, runNumber: 4), same(state));
    expect(state.refresh(today: 98, runNumber: 4), same(state));
    expect(collect(state, 99).reward, isNull);
    final next = state.finishRun(today: 101, runNumber: 4);
    expect(next.streakDays, 6);
  });

  test(
    'COLLECT alone pays; paid day survives hydration and repeat callbacks',
    () {
      final flown = const DayStreak().finishRun(today: 100, runNumber: 4);
      expect(flown.streakPaidDay, -1);
      expect(flown.rewardPending(today: 100, runNumber: 4), isTrue);
      final result = collect(flown, 100);
      expect(result.reward!.coins, 20);
      expect(result.reward!.coinSource, CoinSource.streak);
      expect(result.state.streakPaidDay, 100);
      final reloaded = DayStreak(
        streakDays: result.state.streakDays,
        streakLastDay: result.state.streakLastDay,
        streakPaidDay: result.state.streakPaidDay,
        streakLostDays: result.state.streakLostDays,
        streakLostSeenDay: result.state.streakLostSeenDay,
      );
      expect(collect(reloaded, 100).reward, isNull);
      expect(collect(reloaded, 101).reward, isNull);
      final tomorrow = reloaded.finishRun(today: 101, runNumber: 4);
      expect(collect(tomorrow, 101).reward!.coins, 30);
    },
  );

  test('an unseen day is not auto-paid or banked into later days', () {
    final first = const DayStreak().finishRun(today: 100, runNumber: 4);
    expect(collect(first, 101).reward, isNull);
    final second = first.finishRun(today: 101, runNumber: 4);
    expect(collect(second, 101).reward!.coins, 30);
    final broken = collect(first, 104);
    expect(broken.reward, isNull);
    expect(broken.state.streakLostDays, 1);
  });

  test(
    'seven-day rewards repeat: 200 coins, two free starts and a feather',
    () {
      var state = const DayStreak();
      for (var week = 0; week < 2; week++) {
        final rewards = <StreakReward>[];
        for (var tile = 0; tile < 7; tile++) {
          final today = 100 + week * 7 + tile;
          state = state.finishRun(today: today, runNumber: 4);
          final result = collect(state, today);
          rewards.add(result.reward!);
          state = result.state;
        }
        expect(rewards.map((r) => r.coins), [20, 30, 0, 40, 0, 50, 60]);
        expect(rewards.map((r) => r.item), [
          null,
          null,
          StreakRewardItem.bigHoops,
          null,
          StreakRewardItem.shield,
          null,
          StreakRewardItem.feather,
        ]);
        expect(rewards.fold(0, (sum, r) => sum + r.coins), 200);
      }
    },
  );

  test('day 7 resolves feather then piece then 50 extra coins at COLLECT', () {
    const state = DayStreak(streakDays: 7, streakLastDay: 100);
    for (final feather in [true, false]) {
      for (final piece in [true, false]) {
        final reward = state
            .collect(
              today: 100,
              runNumber: 4,
              canReceiveFeather: feather,
              canReceivePiece: piece,
            )
            .reward!;
        expect(
          reward.item,
          feather
              ? StreakRewardItem.feather
              : piece
              ? StreakRewardItem.piece
              : null,
        );
        expect(reward.coins, feather || piece ? 60 : 110);
      }
    }
  });

  test('reads existing reward tuning and rejects nonpositive track days', () {
    final tuning = TuningValues.resolve({
      'streak_rewards': '[21,31,"bighoops",41,"shield",51,"feather+60"]',
    });
    expect(
      DayStreak.rewardForDay(
        8,
        canReceiveFeather: true,
        canReceivePiece: true,
        tuning: tuning,
      ).coins,
      21,
    );
    expect(
      () => DayStreak.rewardForDay(
        0,
        canReceiveFeather: true,
        canReceivePiece: true,
      ),
      throwsArgumentError,
    );
  });
}
