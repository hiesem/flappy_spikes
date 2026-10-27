import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/progression/day_streak.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flutter_test/flutter_test.dart';

DayStreak restore(
  DayStreak state,
  int day, {
  bool completed = true,
  bool noAds = false,
  int coins = 0,
}) => state.restore(
  today: day,
  runNumber: 4,
  noAds: noAds,
  coins: coins,
  paymentCompleted: completed,
);

void main() {
  test('every n >= 1 gets an offer and O72 singular texts', () {
    for (final n in [1, 2, 13, 30]) {
      final state = DayStreak(
        streakDays: n,
        streakLastDay: 100,
      ).refresh(today: 102, runNumber: 4);
      expect(state.streakLostDays, n);
      expect(state.shouldOfferLost(today: 102, runNumber: 4), isTrue);
      expect(
        state.lostMessage,
        n == 1
            ? '1 day of day streak interrupted!'
            : '$n days of day streak interrupted!',
      );
      final pronoun = n == 1 ? 'it' : 'them';
      expect(
        state.restoreMessage(noAds: false),
        'Watch a video to restore $pronoun.',
      );
      expect(
        state.restoreMessage(noAds: true),
        'Restore $pronoun for 500 coins.',
      );
    }
  });

  test('pending is reoffered each day; x retries on the next Home visit', () {
    const lost = DayStreak(streakLastDay: 100, streakLostDays: 13);
    final shown = lost.markLostShown(today: 102, runNumber: 4);
    expect(shown.streakLostSeenDay, 102);
    expect(shown.shouldOfferLost(today: 102, runNumber: 4), isFalse);
    expect(shown.shouldOfferLost(today: 103, runNumber: 4), isTrue);
    final closed = shown.dismissLost(today: 102, runNumber: 4);
    expect(closed.streakLostDays, 13);
    expect(closed.shouldOfferLost(today: 102, runNumber: 4), isTrue);
    final hydrated = DayStreak(
      streakLastDay: shown.streakLastDay,
      streakLostDays: shown.streakLostDays,
      streakLostSeenDay: shown.streakLostSeenDay,
    );
    expect(hydrated.shouldOfferLost(today: 102, runNumber: 4), isFalse);
    expect(hydrated.shouldOfferLost(today: 103, runNumber: 4), isTrue);
    expect(hydrated.refresh(today: 200, runNumber: 4).streakLostDays, 13);
  });

  test('O73 cases A/B/C restore only the most recently broken streak', () {
    final broken13 = const DayStreak(
      streakDays: 13,
      streakLastDay: 100,
    ).refresh(today: 102, runNumber: 4);
    final starts = [
      broken13.giveUp(today: 102, runNumber: 4), // A
      broken13.dismissLost(today: 102, runNumber: 4), // B
      restore(broken13, 102), // C
    ];
    for (var i = 0; i < starts.length; i++) {
      var state = starts[i]
          .finishRun(today: 102, runNumber: 4)
          .finishRun(today: 103, runNumber: 4);
      expect(state.streakDays, i == 2 ? 15 : 2);
      state = state.refresh(today: 105, runNumber: 4);
      expect(state.streakDays, 0);
      expect(state.streakLostDays, i == 2 ? 15 : 2);
      expect(restore(state, 105).streakDays, i == 2 ? 15 : 2);
    }
  });

  test('pending runs build and collect k; completed video restores n+k', () {
    var state = const DayStreak(streakLastDay: 100, streakLostDays: 13);
    for (final day in [102, 103]) {
      state = state.finishRun(today: day, runNumber: 4);
      final claim = state.collect(
        today: day,
        runNumber: 4,
        canReceiveFeather: true,
        canReceivePiece: true,
      );
      expect(claim.reward!.coins, day == 102 ? 20 : 30);
      state = claim.state;
    }
    final restored = restore(state, 103);
    expect(restored.streakDays, 15);
    expect(restored.streakLastDay, 103); // max(last, yesterday)
    expect(restored.streakPaidDay, 103);
    expect(restored.rewardPending(today: 103, runNumber: 4), isFalse);
    expect(restored.streakLostDays, 0);
    expect(restore(restored, 103), same(restored));
  });

  test(
    'restore before today\'s run anchors yesterday; run continues normally',
    () {
      const lost = DayStreak(streakLastDay: 100, streakLostDays: 13);
      final restored = restore(lost, 110);
      expect(restored.streakDays, 13);
      expect(restored.streakLastDay, 109);
      expect(restored.flewToday(110), isFalse);
      expect(restored.rewardPending(today: 110, runNumber: 4), isFalse);
      final today = restored.finishRun(today: 110, runNumber: 4);
      expect(today.streakDays, 14);
      expect(
        today
            .collect(
              today: 110,
              runNumber: 4,
              canReceiveFeather: true,
              canReceivePiece: true,
            )
            .reward!
            .coins,
        60,
      );
      expect(today.finishRun(today: 110, runNumber: 5), same(today));
      // No limit on subsequent legitimate restore operations.
      final lostAgain = today.refresh(today: 112, runNumber: 4);
      expect(restore(lostAgain, 112).streakDays, 14);
    },
  );

  test(
    'failed, no-fill, offline and incomplete ad never consume the offer',
    () {
      for (final failure in ['failed', 'no fill', 'offline', 'incomplete']) {
        final shown = const DayStreak(
          streakLastDay: 100,
          streakLostDays: 1,
        ).markLostShown(today: 102, runNumber: 4);
        final failed = restore(shown, 102, completed: false);
        expect(failed.streakLostDays, 1, reason: failure);
        expect(failed.streakDays, 0);
        expect(failed.shouldOfferLost(today: 102, runNumber: 4), isTrue);
        expect(failed.shouldOfferLost(today: 103, runNumber: 4), isTrue);
      }
    },
  );

  test('No-Ads quotes only coins: 500 spend, disabled below 500', () {
    const state = DayStreak(streakLastDay: 100, streakLostDays: 13);
    for (final coins in [0, 499, 500, 501]) {
      final quote = state.restorePayment(noAds: true, coins: coins);
      expect(quote.method, StreakRestoreMethod.coins);
      expect(quote.coins, 500);
      expect(quote.coinSource, CoinSource.streakRestore);
      expect(quote.enabled, coins >= 500);
      final result = restore(state, 102, noAds: true, coins: coins);
      expect(result.streakDays, coins >= 500 ? 13 : 0);
      expect(result.streakLostDays, coins >= 500 ? 0 : 13);
    }
    expect(
      restore(
        state,
        102,
        noAds: true,
        coins: 500,
        completed: false,
      ).streakLostDays,
      13,
    );
    final video = state.restorePayment(noAds: false, coins: 1000);
    expect(video.method, StreakRestoreMethod.rewardedVideo);
    expect(video.coins, 0);
    final tuning = TuningValues.resolve({'streak_restore_coins': '600'});
    expect(
      state.restorePayment(noAds: true, coins: 500, tuning: tuning).enabled,
      isFalse,
    );
  });

  test('GIVE UP retains k, or grey zero until another finished run (O74)', () {
    const lost = DayStreak(streakLastDay: 100, streakLostDays: 13);
    final empty = lost.giveUp(today: 102, runNumber: 4);
    expect(empty.streakDays, 0);
    expect(empty.streakLostDays, 0);
    expect(empty.flewToday(102), isFalse);
    expect(empty.refresh(today: 110, runNumber: 4).streakLostDays, 0);
    expect(empty.finishRun(today: 110, runNumber: 4).streakDays, 1);
    final flown = lost
        .finishRun(today: 102, runNumber: 4)
        .finishRun(today: 103, runNumber: 4);
    final givenUp = flown.giveUp(today: 103, runNumber: 4);
    expect(givenUp.streakDays, 2);
    expect(givenUp.streakLastDay, 103);
    expect(givenUp.streakLostDays, 0);
  });

  test('runs 1–3 cannot show, dismiss, restore or give up an offer', () {
    const state = DayStreak(
      streakDays: 2,
      streakLastDay: 100,
      streakLostDays: 13,
    );
    for (var run = 1; run <= 3; run++) {
      expect(state.refresh(today: 103, runNumber: run), same(state));
      expect(state.shouldOfferLost(today: 103, runNumber: run), isFalse);
      expect(state.markLostShown(today: 103, runNumber: run), same(state));
      expect(state.dismissLost(today: 103, runNumber: run), same(state));
      expect(state.giveUp(today: 103, runNumber: run), same(state));
      expect(
        state.restore(
          today: 103,
          runNumber: run,
          noAds: false,
          coins: 0,
          paymentCompleted: true,
        ),
        same(state),
      );
    }
  });

  test(
    'rollback cannot relight, resolve, dismiss or reoffer a future state',
    () {
      const state = DayStreak(
        streakDays: 2,
        streakLastDay: 103,
        streakLostDays: 13,
        streakLostSeenDay: 103,
      );
      expect(state.shouldOfferLost(today: 102, runNumber: 4), isFalse);
      expect(state.markLostShown(today: 102, runNumber: 4), same(state));
      expect(state.dismissLost(today: 102, runNumber: 4), same(state));
      expect(restore(state, 102), same(state));
      expect(state.giveUp(today: 102, runNumber: 4), same(state));
    },
  );
}
