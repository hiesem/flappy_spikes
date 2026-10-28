import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flappy_spikes/components/progression/streak_strip.dart';
import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/progression/streak_lost_popup.dart';
import 'package:flappy_spikes/components/noads_celebration.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/widgets.dart';

import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/components/ui/coin_fly.dart';
import 'package:flappy_spikes/progression/day_streak.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

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
  uiTests();
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

class _Events extends GameServices {
  final events = <(String, Map<String, Object>)>[];
  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    events.add((name, parameters ?? {}));
  }

  List<Map<String, Object>> named(String name) => events
      .where((event) => event.$1 == name)
      .map((event) => event.$2)
      .toList();
}

void uiTests() {
  for (final reduced in [false, true]) {
    final now = DateTime(2026, 10, 27, 12);
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        clock: () => now,
        prefs: {
          'gamesPlayed': 4,
          'streakLostDays': 13,
          'streakDays': 2,
          'streakLastDay': streakLocalDay(now),
          'streakPaidDay': streakLocalDay(now),
        },
      )..reduceMotionOverride = reduced,
    ).testGameWidget(
      'restore mounts the R3 rays behind the flame, reduced motion=$reduced',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        await flushAndMount(game);
        stepGame(game, 2);
        await flushAndMount(game);
        final popup = game.streakLostPopup!;
        expect(popup.card.children.whereType<NoAdsCelebrationRays>(), isEmpty);
        await game.restoreLostStreak();
        await flushAndMount(game);
        final rays = popup.card.children
            .whereType<NoAdsCelebrationRays>()
            .single;
        expect(popup.phase, StreakLostPhase.restoring);
        expect(rays.isMounted, isTrue);
        expect(rays, same(popup.restoreRays));
        expect(popup.card.children.first, same(rays));
        expect(rays.priority, lessThan(popup.newCount.priority));
        expect(rays.position.y, 46); // Clip below the P1 header.
        expect(
          rays.rayCenter + ui.Offset(rays.x, rays.y),
          const ui.Offset(200, 87.5),
        );
        stepGame(game, .2);
        expect(rays.phase, reduced ? 0 : greaterThan(0));
        final phase = rays.phase;
        game.reduceMotionOverride = true;
        stepGame(game, .2);
        expect(rays.phase, phase); // Freeze the live rotation clock.
        game.reduceMotionOverride = false;
        stepGame(game, .2);
        expect(rays.phase, greaterThan(phase));
        // Round-2 review permits n + k: G2 RESTORE restores all 15 days.
        expect(popup.newCount.text, '15');
        expect(game.storage.streakDays, 15);
        game.reduceMotionOverride = reduced;
        stepGame(game, .6);
        expect(game.streakLostPopup, isNull);
        await flushAndMount(game);
        final chip = game.homeScreen!.children.whereType<StreakStrip>().single;
        expect(
          chip.children.whereType<ScaleEffect>(),
          reduced ? isEmpty : isNotEmpty,
        );
      },
    );
  }
  for (final complete in [true, false]) {
    var now = DateTime(2026, 10, 27, 12);
    final ads = FakeRewardedAds();
    final events = _Events();
    final monetization = Monetization(ads: ads)..showFakeAdOverlay = true;
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        clock: () => now,
        services: events,
        monetization: monetization,
        prefs: {
          'gamesPlayed': 4,
          'streakLostDays': 13,
          'streakDays': 2,
          'streakLastDay': streakLocalDay(now),
          'streakPaidDay': streakLocalDay(now),
        },
      ),
    ).testGameWidget(
      'UI visible fake restore ad completed=$complete preserves k and reward day',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        await flushAndMount(game);
        stepGame(game, 2);
        await flushAndMount(game);
        final popup = game.streakLostPopup!;
        final restoring = game.restoreLostStreak();
        await flushAndMount(game);
        expect(game.fakeAdOverlay!.placement, AdPlacement.streakRestore);
        expect(ads.placements, [AdPlacement.streakRestore]);
        expect(
          events.named('ad_rewarded_shown').single['placement'],
          'streak_restore',
        );
        expect(game.storage.streakDays, 2); // Only reward completion grants.
        if (complete) {
          stepGame(game, 5);
        } else {
          game.fakeAdOverlay!.close();
          await tester.pump();
          now = now.add(const Duration(seconds: 8));
          await tester.pump(const Duration(seconds: 9));
        }
        await flushAndMount(game);
        await restoring;
        expect(game.storage.streakPaidDay, game.storage.today);
        if (complete) {
          expect(game.storage.streakDays, 15);
          expect(game.storage.streakLostDays, 0);
          expect(popup.detail!.text, ''); // S-40 only before today's run.
          expect(events.named('streak_restore').single, {
            'days': 15,
            'method': 'ad',
            'ad_tries': 1,
          });
          expect(
            events.named('ad_reward_earned').single['placement'],
            'streak_restore',
          );
        } else {
          expect(game.storage.streakDays, 2);
          expect(game.storage.streakLostDays, 13);
          expect(popup.phase, StreakLostPhase.retry);
          expect(events.named('ad_reward_earned'), isEmpty);
        }
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(prefs: {'gamesPlayed': 4, 'streakLostDays': 3}),
  ).testGameWidget(
    'give up drains a queued purchase popup after the moment',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await flushAndMount(game);
      stepGame(game, 2);
      await flushAndMount(game);
      expect(game.streakLostPopup, isNotNull);
      game.openPurchaseResultPopup(
        IapProduct.coins1000,
        PurchaseProblem.failed,
        null,
      );
      expect(game.queuedPopups, 1);
      await game.giveUpLostStreak();
      stepGame(game, .7);
      await flushAndMount(game);
      expect(game.streakLostPopup, isNull);
      expect(game.queuedPopups, 0);
      expect(game.purchaseResultPopup, isNotNull);
    },
  );

  for (final giveUp in [false, true]) {
    final now = DateTime(2026, 10, 27, 12);
    final ads = FakeRewardedAds()
      ..mode = FakeAdMode.unavailable
      ..loadsAfter = const Duration(seconds: 4);
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        clock: () => now,
        monetization: Monetization(ads: ads),
        prefs: {
          'gamesPlayed': 4,
          'streakLostDays': 13,
          'streakLastDay': streakLocalDay(now) - 2,
        },
      ),
    ).testGameWidget(
      'UI cancel a pending load with giveUp=$giveUp never grants late',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        await flushAndMount(game);
        stepGame(game, 2);
        await flushAndMount(game);
        final restoring = game.restoreLostStreak();
        await tester.pump();
        if (giveUp) {
          await game.giveUpLostStreak();
          stepGame(game, .7);
        } else {
          await game.dismissLostStreak();
        }
        await tester.pump(const Duration(seconds: 5));
        await restoring;
        expect(game.streakLostPopup, isNull);
        expect(game.storage.streakDays, 0);
        expect(game.storage.streakLostDays, giveUp ? 0 : 13);
        expect(ads.shown, 0);
      },
    );
  }

  for (final games in [0, 1, 2, 3]) {
    final now = DateTime(2026, 10, 27, 12);
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        clock: () => now,
        prefs: {
          'gamesPlayed': games,
          'streakDays': 1,
          'streakLastDay': streakLocalDay(now) - 2,
        },
      ),
    ).testGameWidget(
      'UI C2 unlock at game four, gamesPlayed=$games',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        await flushAndMount(game);
        stepGame(game, 2);
        await flushAndMount(game);
        if (games < 3) {
          expect(game.streakLostPopup, isNull);
        } else {
          expect(
            (game.homeMoments as HomeMomentBudget).selectedMoment,
            HomeMoment.streakLost,
          );
          expect(game.modalPopupOpen, isTrue);
          await game.startRun();
          expect(game.state, GameState.start);
          final popup = game.streakLostPopup!;
          expect(popup.lostLine.text, '1 day of day streak interrupted!');
          expect(popup.detail!.text, 'Watch a video to restore it.');
          expect(popup.action.text, 'RESTORE');
          expect(game.storage.streakDays, 0);
          expect(game.storage.streakLostDays, 1);
          expect(game.storage.streakLostSeenDay, game.storage.today);
          expect(game.levelUpPopup, isNull);
          expect(game.noAdsPopup, isNull);
        }
      },
    );
  }

  for (final coins in [499, 500]) {
    final now = DateTime(2026, 10, 27, 12);
    final ads = FakeRewardedAds();
    final events = _Events();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        clock: () => now,
        services: events,
        monetization: Monetization(ads: ads),
        prefs: {
          'gamesPlayed': 4,
          'noAds': true,
          'coins': coins,
          'streakLostDays': 13,
          'streakLastDay': streakLocalDay(now) - 2,
        },
      ),
    ).testGameWidget(
      'UI No-Ads $coins: coin payment only, duplicate guard and flight',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        await flushAndMount(game);
        stepGame(game, 2);
        await flushAndMount(game);
        final popup = game.streakLostPopup!;
        expect(popup.detail!.text, 'Restore them for 500 coins.');
        expect(popup.action.text, 'RESTORE · 500');
        expect(
          popup.restoreButton.containsLocalPoint(Vector2(10, 10)),
          coins == 500,
        );
        if (coins == 499) {
          expect(popup.restoreButton.color, const ui.Color(0xFFCFCFCF));
          expect(popup.poorLine!.text, 'You have 499 coins.');
          await game.restoreLostStreak();
          expect(game.storage.streakLostDays, 13);
          expect(game.menu.wallet.balance, 499);
          await game.giveUpLostStreak();
          stepGame(game, .7);
          expect(game.streakLostPopup, isNull);
          expect(game.storage.streakDays, 0);
          expect(game.storage.streakLostDays, 0);
          expect(events.named('streak_give_up').single['days'], 13);
        } else {
          final restoring = game.restoreLostStreak();
          await flushAndMount(game);
          expect(popup.phase, StreakLostPhase.paying);
          expect(popup.action.text, 'RESTORE · 500');
          expect(game.world.children.whereType<CoinFly>(), isNotEmpty);
          await game.restoreLostStreak();
          // A committed payment cannot be dismissed or given up mid-flight.
          await game.dismissLostStreak();
          await game.giveUpLostStreak();
          expect(game.streakLostPopup, same(popup));
          stepGame(game, 1);
          await flushAndMount(game);
          await restoring;
          expect(game.menu.wallet.balance, 0);
          expect(game.storage.streakDays, 13);
          expect(game.storage.streakLastDay, game.storage.today - 1);
          expect(game.storage.streakLostDays, 0);
          expect(popup.title.text, 'STREAK RESTORED!');
          expect(popup.detail!.text, 'Fly one run today to keep it going.');
          expect(events.named('streak_restore').single, {
            'days': 13,
            'method': 'coins',
            'ad_tries': 0,
          });
          expect(
            events.named('coins_spent').single['reason'],
            'streak_restore',
          );
          stepGame(game, 1.2);
          expect(game.streakLostPopup, isNull);
        }
        expect(ads.loadRequests, 0);
        expect(ads.shown, 0);
        expect(ads.placements, isEmpty);
      },
    );
  }

  for (final mode in [FakeAdMode.fail, FakeAdMode.unavailable]) {
    var now = DateTime(2026, 10, 27, 12);
    final ads = FakeRewardedAds()..mode = mode;
    final events = _Events();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        clock: () => now,
        services: events,
        monetization: Monetization(ads: ads),
        prefs: {
          'gamesPlayed': 4,
          'streakLostDays': 1,
          'streakLastDay': streakLocalDay(now) - 2,
        },
      ),
    ).testGameWidget(
      'UI $mode: eight-second retry, next visit and next day pending',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        await flushAndMount(game);
        stepGame(game, 2);
        await flushAndMount(game);
        final popup = game.streakLostPopup!;
        final loading = game.restoreLostStreak();
        await tester.pump();
        expect(popup.action.text, 'LOADING VIDEO');
        expect(popup.giveUpButton.isActive!(), isTrue);
        await tester.pump(const Duration(seconds: 7));
        expect(popup.phase, StreakLostPhase.loading);
        now = now.add(const Duration(seconds: 8));
        await tester.pump(const Duration(seconds: 2));
        await loading;
        expect(popup.phase, StreakLostPhase.retry);
        expect(popup.action.text, 'TRY AGAIN');
        expect(
          popup.detail!.text,
          'No video right now. Your streak waits for you.',
        );
        expect(game.storage.streakLostDays, 1);
        expect(events.named('streak_restore_ad_fail'), hasLength(1));
        await game.dismissLostStreak();
        stepGame(game, 2);
        expect(game.streakLostPopup, isNull); // C2 slot already spent.
        Future<void> visit(Duration after) async {
          game.lifecycleStateChange(AppLifecycleState.paused);
          now = now.add(after);
          game.lifecycleStateChange(AppLifecycleState.resumed);
          await flushAndMount(game);
          stepGame(game, 2);
          await flushAndMount(game);
        }

        await visit(const Duration(minutes: 31));
        expect(game.streakLostPopup, isNotNull);
        expect(game.streakLostPopup!.state.streakLostDays, 1);
        await game.dismissLostStreak();
        await visit(const Duration(days: 1));
        expect(game.streakLostPopup!.state.streakLostDays, 1);
        expect(events.named('streak_lost_shown'), hasLength(3));
        ads.mode = FakeAdMode.succeed;
        await game.restoreLostStreak();
        expect(game.storage.streakDays, 1);
        expect(ads.placements.last, AdPlacement.streakRestore);
        expect(events.named('streak_restore').single, {
          'days': 1,
          'method': 'ad',
          'ad_tries': 1,
        });
        stepGame(game, 1.2);
        expect(game.streakLostPopup, isNull);
      },
    );
  }
}
