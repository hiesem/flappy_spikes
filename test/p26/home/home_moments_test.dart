import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  test('one Home moment wins per visit in the C2 priority order', () {
    final policy = HomeMomentBudget();
    final gifts = [
      HomeGiftBoxRequest(id: 'newest', availableAt: DateTime(2026, 10, 24, 12)),
      HomeGiftBoxRequest(id: 'oldest', availableAt: DateTime(2026, 10, 24, 10)),
      HomeGiftBoxRequest(id: 'middle', availableAt: DateTime(2026, 10, 24, 11)),
    ];
    var streakLost = true;
    var levelUp = true;
    var streakReward = true;
    var missionsChest = true;
    var starRoad = true;
    var noAds = true;
    var rating = true;
    final opened = <HomeMoment>[];

    for (var visit = 0; visit < 10; visit++) {
      policy.beginVisit(
        HomeVisit(
          day: DateTime(2026, 10, 24),
          gamesPlayed: 3,
          requests: HomeVisitRequests(
            streakLost: streakLost,
            levelUpCatchUp: levelUp,
            streakReward: streakReward,
            leaderboardGifts: gifts,
            missionsChest: missionsChest,
            starRoad: starRoad,
            noAds: noAds,
            rating: rating,
          ),
        ),
      );
      final before = opened.length;
      for (final moment in HomeMoment.values) {
        policy.show(moment, () => opened.add(moment));
      }
      expect(opened.length, before + 1, reason: 'visit ${visit + 1}');
      switch (opened.last) {
        case HomeMoment.streakLost:
          streakLost = false;
        case HomeMoment.levelUp:
          levelUp = false;
        case HomeMoment.streakReward:
          streakReward = false;
        case HomeMoment.leaderboardCollect:
          gifts.remove(policy.selectedGift!);
        case HomeMoment.missionsChest:
          missionsChest = false;
        case HomeMoment.starRoad:
          starRoad = false;
        case HomeMoment.noAds:
          noAds = false;
        case HomeMoment.rating:
          rating = false;
      }
    }

    expect(opened, [
      HomeMoment.streakLost,
      HomeMoment.levelUp,
      HomeMoment.streakReward,
      HomeMoment.leaderboardCollect,
      HomeMoment.leaderboardCollect,
      HomeMoment.leaderboardCollect,
      HomeMoment.missionsChest,
      HomeMoment.starRoad,
      HomeMoment.noAds,
      HomeMoment.rating,
    ]);
    expect(policy.selectedGift, isNull);
  });

  test('gift boxes are oldest-first and only one is offered per visit', () {
    final policy = HomeMomentBudget();
    final gifts = [
      HomeGiftBoxRequest(id: 'c', availableAt: DateTime(2026, 10, 24, 12)),
      HomeGiftBoxRequest(id: 'a', availableAt: DateTime(2026, 10, 24, 10)),
      HomeGiftBoxRequest(id: 'b', availableAt: DateTime(2026, 10, 24, 11)),
    ];

    for (final expected in ['a', 'b', 'c']) {
      policy.beginVisit(
        HomeVisit(
          day: DateTime(2026, 10, 24),
          gamesPlayed: 3,
          requests: HomeVisitRequests(leaderboardGifts: gifts),
        ),
      );
      expect(policy.selectedMoment, HomeMoment.leaderboardCollect);
      expect(policy.selectedGift!.id, expected);
      gifts.remove(policy.selectedGift!);
    }
    expect(gifts, isEmpty);
  });

  test('Star Road is gated by runs and shown once a day', () {
    final policy = HomeMomentBudget();
    DateTime day(int value) => DateTime(2026, 11, value);
    HomeVisit visit(
      DateTime visitDay,
      int gamesPlayed,
      HomeVisitRequests requests,
    ) => HomeVisit(day: visitDay, gamesPlayed: gamesPlayed, requests: requests);

    policy.beginVisit(
      visit(day(1), 2, const HomeVisitRequests(starRoad: true, noAds: true)),
    );
    expect(policy.selectedMoment, HomeMoment.noAds);

    policy.beginVisit(
      visit(
        day(1),
        3,
        const HomeVisitRequests(missionsChest: true, starRoad: true),
      ),
    );
    expect(policy.selectedMoment, HomeMoment.missionsChest);
    var starRoadOpened = false;
    policy.show(HomeMoment.starRoad, () => starRoadOpened = true);
    expect(starRoadOpened, isFalse);

    policy.beginVisit(
      visit(day(1), 3, const HomeVisitRequests(starRoad: true, rating: true)),
    );
    expect(policy.selectedMoment, HomeMoment.starRoad);
    policy.show(HomeMoment.starRoad, () {});

    policy.beginVisit(
      visit(day(1), 3, const HomeVisitRequests(starRoad: true, rating: true)),
    );
    expect(policy.selectedMoment, HomeMoment.rating);

    policy.beginVisit(
      visit(day(2), 3, const HomeVisitRequests(starRoad: true, rating: true)),
    );
    expect(policy.selectedMoment, HomeMoment.starRoad);
  });

  test('STREAK LOST is first on each new day while it stays pending', () {
    final policy = HomeMomentBudget();
    final firstDay = DateTime(2026, 10, 24);
    final secondDay = DateTime(2026, 10, 25);

    policy.beginVisit(
      HomeVisit(
        day: firstDay,
        gamesPlayed: 3,
        requests: const HomeVisitRequests(
          streakLost: true,
          levelUpCatchUp: true,
        ),
      ),
    );
    expect(policy.selectedMoment, HomeMoment.streakLost);

    policy.beginVisit(
      HomeVisit(
        day: secondDay,
        gamesPlayed: 3,
        requests: const HomeVisitRequests(
          streakLost: true,
          levelUpCatchUp: true,
        ),
      ),
    );
    expect(policy.selectedMoment, HomeMoment.streakLost);
  });

  test('two HomeMomentBudget instances keep their own visit and day state', () {
    final first = HomeMomentBudget();
    final second = HomeMomentBudget();
    final day = DateTime(2026, 11, 1);
    final visit = HomeVisit(
      day: day,
      gamesPlayed: 3,
      requests: const HomeVisitRequests(starRoad: true),
    );

    first.beginVisit(visit);
    expect(first.selectedMoment, HomeMoment.starRoad);
    var firstOpened = false;
    expect(
      first.tryShow(HomeMoment.starRoad, () => firstOpened = true),
      isTrue,
    );
    expect(firstOpened, isTrue);
    expect(first.tryShow(HomeMoment.starRoad, () {}), isFalse);

    second.beginVisit(visit);
    expect(second.selectedMoment, HomeMoment.starRoad);
    var secondOpened = false;
    expect(
      second.tryShow(HomeMoment.starRoad, () => secondOpened = true),
      isTrue,
      reason: "the first instance's visit must not consume the second",
    );
    expect(secondOpened, isTrue);

    first.beginVisit(visit);
    expect(first.selectedMoment, isNull, reason: 'the first instance used today');
    second.beginVisit(
      HomeVisit(
        day: day,
        gamesPlayed: 3,
        requests: const HomeVisitRequests(starRoad: true, rating: true),
      ),
    );
    expect(
      second.selectedMoment,
      HomeMoment.rating,
      reason: "the first instance's Star Road day must not leak",
    );
  });

  final withLiveSources = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      'playerLevel': 1,
      'claimedLevels': <String>[],
    });
    return createRunTestGame(
      prefs: {'playerLevel': 1, 'claimedLevels': <String>[]},
      worldHeight: Config.worldHeight,
    );
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));

  withLiveSources.testGameWidget(
    'LEVEL UP wins over No-Ads; achievement toasts stay outside the budget',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final moments = game.homeMoments as HomeMomentBudget;
      moments.beginVisit(
        HomeVisit(
          day: DateTime(2026, 10, 24),
          gamesPlayed: 3,
          requests: const HomeVisitRequests(levelUpCatchUp: true, noAds: true),
        ),
      );

      game.openNoAdsPopup(reason: 'forced', check: 'forced');
      await flushAndMount(game);
      expect(game.noAdsPopup, isNull);

      game.openLevelUpPopup();
      await flushAndMount(game);
      expect(game.levelUpPopup, isNotNull);

      game.achievements.toastQueue.add(AchievementId.firstRevive);
      game.showAchievementToasts();
      await flushAndMount(game);
      expect(game.achievementToast, isNotNull);

      await game.claimLevelUp();
      await flushAndMount(game);
      moments.beginVisit(
        HomeVisit(
          day: DateTime(2026, 10, 24),
          gamesPlayed: 3,
          requests: const HomeVisitRequests(noAds: true),
        ),
      );
      game.openNoAdsPopup(reason: 'forced', check: 'forced');
      await flushAndMount(game);
      expect(game.noAdsPopup, isNotNull);
    },
  );

  final normalTransitions = FlameTester<FlappySpikesGame>(() {
    return createRunTestGame(
      prefs: {
        'playerLevel': 1,
        'claimedLevels': ['1'],
        'gamesPlayed': 12,
        'firstSessionDone': true,
        'lastScore': 5,
        'noAdsPopupVideos': 3,
        'installDay': 1,
      },
      worldHeight: Config.worldHeight,
      clock: () => DateTime(2026, 10, 24, 12),
    );
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));

  normalTransitions.testGameWidget(
    'normal Home arrivals show one moment and defer the next to a later visit',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
      // A launch session offer is outside the post-run popup budget.
      game.closeNoAdsPopup();
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      Future<void> io() async {
        for (var round = 0; round < 4; round++) {
          for (var i = 0; i < 20; i++) {
            await Future<void>.value();
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
      }

      Future<void> finishRun(int score) async {
        final run = await startRun(game);
        run.state.score = score;
        game.showRunScore(score);
        killRunThroughSaves(game);
        await declineRevive(game);
        await flushAndMount(game);
        game.goHome();
        await io();
        await flushAndMount(game);
        expect(game.state, GameState.start);
      }

      // The first run owes LEVEL UP and also opens the No-Ads window. C2
      // picks LEVEL UP; No-Ads stays pending for the next visit.
      await finishRun(50);
      stepGame(game, Config.levelUpSettleDelay + .1);
      await flushAndMount(game);
      expect(game.levelUpPopup, isNotNull);
      expect(game.noAdsPopup, isNull);

      // The achievement toast is outside the budget.
      game.achievements.toastQueue.add(AchievementId.firstRevive);
      game.showAchievementToasts();
      await flushAndMount(game);
      expect(game.achievementToast, isNotNull);

      game.levelUpPopup!.claimButton.onPressed();
      await io();
      await flushAndMount(game);
      expect(game.levelUpPopup, isNull);
      expect(game.noAdsPopup, isNull, reason: 'one moment on this visit');

      // A second, lower-scoring run reaches Home: the deferred No-Ads offer
      // is now the one moment of that visit.
      await finishRun(8);
      stepGame(game, Config.levelUpSettleDelay + .1);
      await io();
      await flushAndMount(game);
      expect(game.levelUpPopup, isNull);
      expect(game.noAdsPopup, isNotNull);
    },
  );
}
