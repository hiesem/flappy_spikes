// region P26-C2W
import 'package:flappy_spikes/components/leaderboard/gift_popup.dart';
import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/run/run_end_bookkeeping.dart';
// endregion
import '../../levels/progression_fixture.dart';
// PRD-2.6 J4: popup fixtures carry explicit persisted pending rolls.
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

// region P26-C2W
class _HomeGiftBoard extends NoopLeaderboardService {
  @override
  Future<LbGetBoardResult?> getBoard({LbBoardTab tab = LbBoardTab.today}) async =>
      LbGetBoardResult(
        today: LbBoardPayload(tab: LbBoardTab.today, rows: const [], gifts: [
          LbGift(gid: 'old', tier: 'gold', boardRank: 1, createdAt: DateTime.utc(2026, 10, 1)),
        ]),
        best: const LbBoardPayload(tab: LbBoardTab.best, rows: []),
      );
  @override
  Future<LbClaimGiftResult?> claimGift(String id, {List<String>? owned}) async =>
      const LbClaimGiftResult(ok: true, id: 'gift-prize', tier: 'gold',
        prize: LbGiftRoll(kind: 'coins', coins: 175));
}
// endregion

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

  test('debug force bypasses C2 without consuming or resetting the visit', () {
    final policy = HomeMomentBudget();
    policy.beginVisit(
      HomeVisit(
        day: DateTime(2026, 10, 24),
        gamesPlayed: 3,
        requests: const HomeVisitRequests(levelUpCatchUp: true, noAds: true),
      ),
    );
    final opened = <HomeMoment>[];
    policy.showDebug(HomeMoment.noAds, () => opened.add(HomeMoment.noAds));
    expect(policy.selectedMoment, HomeMoment.levelUp);
    expect(
      policy.tryShow(HomeMoment.levelUp, () => opened.add(HomeMoment.levelUp)),
      isTrue,
    );
    policy.showDebug(HomeMoment.noAds, () => opened.add(HomeMoment.noAds));
    expect(
      policy.tryShow(HomeMoment.noAds, () => fail('visit already spent')),
      isFalse,
    );
    expect(opened, [HomeMoment.noAds, HomeMoment.levelUp, HomeMoment.noAds]);
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
    expect(
      first.selectedMoment,
      isNull,
      reason: 'the first instance used today',
    );
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

  // region P26-C2W
  test('persisted Star Road day gates a new policy and cannot bypass chest', () {
    final day = DateTime(2026, 11, 1);
    final policy = HomeMomentBudget();
    policy.beginVisit(HomeVisit(day: day, dayKey: 42, starRoadPopupDay: 42,
      gamesPlayed: 3, requests: const HomeVisitRequests(starRoad: true)));
    expect(policy.selectedMoment, isNull);
    expect(policy.tryShow(HomeMoment.starRoad, () => fail('daily cap')), isFalse);
    policy.beginVisit(HomeVisit(day: day, dayKey: 43, starRoadPopupDay: 42,
      gamesPlayed: 3, requests: const HomeVisitRequests(missionsChest: true, starRoad: true)));
    expect(policy.selectedMoment, HomeMoment.missionsChest);
    expect(policy.tryShow(HomeMoment.starRoad, () => fail('chest wins')), isFalse);
  });

  var starNow = DateTime(2026, 11, 1, 12);
  final starTransitions = FlameTester<FlappySpikesGame>(() => createRunTestGame(
    // PRD 2.6 G6 / G6eB: stars belong to the live season; a season-0 board is
    // the pre-season board and is rolled over (paying out) before Home.
    prefs: trackPrefs({'gamesPlayed': 3, 'firstSessionDone': true,
      'playerLevel': 1, 'claimedLevels': ['1'], 'starRoadSeason': 1,
      'starRoadXp': 8}),
    worldHeight: Config.worldHeight, clock: () => starNow,
  ), gameSize: Vector2(Config.worldWidth, Config.worldHeight));
  starTransitions.testGameWidget('Star Road uses live tiers and persists its day on Home arrivals',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      var shown = 0;
      game.registerStarRoadPopup(() => shown++);
      Future<void> resume() async {
        game.lifecycleStateChange(AppLifecycleState.paused);
        starNow = starNow.add(Config.sessionGap);
        game.lifecycleStateChange(AppLifecycleState.resumed);
        await flushAndMount(game);
        stepGame(game, Config.levelUpSettleDelay + .1);
        await flushAndMount(game);
      }
      await resume();
      expect(shown, 1);
      expect(game.storage.starRoadPopupDay, game.storage.today);
      await resume();
      expect(shown, 1);
      starNow = starNow.add(const Duration(days: 1));
      await resume();
      expect(shown, 2);
    },
  );
  // endregion

  // region P26-C2W
  var orderedNow = DateTime(2026, 11, 1, 9);
  final orderedSources = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues(trackPrefs({
      'gamesPlayed': 4, 'firstSessionDone': true,
      'playerLevel': 1, 'claimedLevels': ['1'],
    }));
    return FlappySpikesGame(worldHeight: Config.worldHeight, soundEnabled: false,
      clock: () => orderedNow, leaderboard: _HomeGiftBoard());
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));
  orderedSources.testGameWidget(
    'live sources use one ordered budget across normal Home sessions',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      var starShown = 0;
      game.registerStarRoadPopup(() => starShown++);
      await game.storage.saveStarRoadXp(8);
      await game.storage.saveStreakDays(2);
      await game.storage.saveStreakLastDay(game.storage.today);
      await game.storage.saveStreakLostDays(5);
      await game.storage.saveStreakLostSeenDay(-1);
      await game.storage.saveStreakPaidDay(-1);
      final missions = Missions(day: game.storage.today, missions: const [
        MissionProgress(template: MissionTemplate.m01, target: 3, progress: 3, paid: true),
        MissionProgress(template: MissionTemplate.m03, target: 15, progress: 15, paid: true),
        MissionProgress(template: MissionTemplate.m11, target: 10, progress: 10, paid: true),
      ]);
      await game.storage.saveMissionDay(missions.day);
      await game.storage.saveMissions(missions.toRecords());
      expect(game.missionsChestOpenerRegistered, isTrue);
      expect(RunEndBookkeeping.currentMissions(game.storage).chestPending, isTrue);

      Future<void> settle() async {
        await tester.runAsync(() async {
          for (var i = 0; i < 20; i++) { await Future<void>.delayed(Duration.zero); }
        });
        await flushAndMount(game);
        stepGame(game, Config.levelUpSettleDelay + .2);
        await flushAndMount(game);
      }
      Future<void> nextVisit() async {
        game.lifecycleStateChange(AppLifecycleState.paused);
        orderedNow = orderedNow.add(Config.sessionGap);
        game.lifecycleStateChange(AppLifecycleState.resumed);
        await settle();
      }
      final budget = game.homeMoments as HomeMomentBudget;
      await nextVisit();
      expect(budget.selectedMoment, HomeMoment.streakLost);
      expect(game.streakLostPopup, isNotNull);
      expect(game.streakCard, isNull);
      expect(game.missionsChestPopup, isNull);
      expect(starShown, 0);
      await game.giveUpLostStreak();
      stepGame(game, 3);
      await flushAndMount(game);

      await nextVisit();
      expect(budget.selectedMoment, HomeMoment.streakReward);
      expect(game.streakCard?.reward, isTrue);
      expect(game.world.children.whereType<GiftPopup>(), isEmpty);
      expect(game.missionsChestPopup, isNull);
      expect(starShown, 0);
      game.streakCard!.collectButton!.onPressed();
      await settle();

      await nextVisit();
      expect(budget.selectedMoment, HomeMoment.leaderboardCollect);
      final gift = game.world.children.whereType<GiftPopup>().single;
      expect(gift.gift.gid, 'old');
      expect(game.missionsChestPopup, isNull);
      expect(starShown, 0);
      gift.onCollect();
      await flushAndMount(game);
      final opening = game.world.children.whereType<GiftOpeningPopup>().single;
      await opening.open();
      stepGame(game, 2);
      await flushAndMount(game);
      opening.finish(opening.prize!, opening.claimRect);
      await settle();

      await nextVisit();
      expect(budget.selectedMoment, HomeMoment.missionsChest);
      expect(game.missionsChestPopup, isNotNull);
      expect(starShown, 0);
      stepGame(game, 2);
      game.missionsChestPopup!.onDismiss();
      await settle();
      expect(RunEndBookkeeping.currentMissions(game.storage).chestPending, isFalse);
      expect(starShown, 0, reason: 'the chest spent this visit');

      await nextVisit();
      expect(budget.selectedMoment, HomeMoment.starRoad);
      expect(game.missionsChestPopup, isNull);
      expect(starShown, 1);
    },
  );
  // endregion

  final withLiveSources = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      'playerLevel': 1,
      'claimedLevels': <String>[],
    });
    return createRunTestGame(
      prefs: trackPrefs({'playerLevel': 1, 'claimedLevels': <String>[]}),
      worldHeight: Config.worldHeight,
    );
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));

  withLiveSources.testGameWidget(
    'debug LEVEL UP bypasses the spent visit budget',
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
          requests: const HomeVisitRequests(noAds: true),
        ),
      );
      expect(moments.tryShow(HomeMoment.noAds, () {}), isTrue);
      game.openLevelUpPopup();
      expect(game.levelUpPopup, isNull);
      game.openLevelUpPopup(debugForce: true);
      await flushAndMount(game);
      expect(game.levelUpPopup, isNotNull);
      expect(moments.tryShow(HomeMoment.noAds, () {}), isFalse);
    },
  );

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

      game.openNoAdsPopup(reason: 'videos');
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
      game.openNoAdsPopup(reason: 'videos');
      await flushAndMount(game);
      expect(game.noAdsPopup, isNotNull);
    },
  );

  // PRD C2 / O3: launch and resumed sessions are Home visits too. A native
  // sheet's inactive/resumed cycle neither consumes nor resets their slot.
  for (final atLaunch in [true, false]) {
    var now = DateTime(2026, 10, 24, 12);
    final sessionTransitions = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: trackPrefs({
          'playerLevel': 1,
          'claimedLevels': atLaunch ? <String>[] : ['1'],
          'gamesPlayed': 12,
          'firstSessionDone': true,
          'lastScore': Config.noAdsPopupMinScore,
          'noAdsPopupVideos': 3,
          'installDay': 1,
          // Keep the launch empty in the resume case, so the owed level is
          // created later, without any run-end bookkeeping.
          if (!atLaunch) 'noAdsPopupLastMs': now.millisecondsSinceEpoch,
        }),
        worldHeight: Config.worldHeight,
        clock: () => now,
      ),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );

    sessionTransitions.testGameWidget(
      '${atLaunch ? 'launch' : 'resume'}: owed LEVEL UP beats No-Ads; next visit offers No-Ads',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, _) async {
        final budget = game.homeMoments as HomeMomentBudget;
        Future<void> nextSession() async {
          game.lifecycleStateChange(AppLifecycleState.paused);
          now = now.add(const Duration(days: 1));
          game.lifecycleStateChange(AppLifecycleState.resumed);
          await flushAndMount(game);
        }

        expect(budget.visitActive, isTrue);
        if (!atLaunch) {
          expect(budget.selectedMoment, isNull);
          expect(game.noAdsPopup, isNull);
          await game.menu.levels.debugForceLevelUp();
          await nextSession();
        }
        expect(game.menu.levels.pendingLevelUp, isNotNull);
        expect(game.menu.noAdsPopup.evaluate(), isNotNull);
        expect(budget.selectedMoment, HomeMoment.levelUp);
        expect(game.noAdsPopup, isNull);
        stepGame(game, Config.levelUpSettleDelay + .1);
        await flushAndMount(game);
        expect(game.levelUpPopup, isNotNull);
        expect(game.noAdsPopup, isNull);
        expect(game.storage.noAdsPopupShowsToday, 0);
        expect(
          game.storage.noAdsPopupVideos,
          3,
          reason: 'a deferred offer keeps its live trigger',
        );

        // System sheets are outside C2. Their ordinary lifecycle round trip
        // must leave the active visit and its chosen popup intact (O3).
        game.lifecycleStateChange(AppLifecycleState.inactive);
        game.lifecycleStateChange(AppLifecycleState.resumed);
        await flushAndMount(game);
        expect(game.levelUpPopup, isNotNull);
        expect(budget.selectedMoment, HomeMoment.levelUp);

        await game.claimLevelUp();
        stepGame(game, Config.popupFadeDuration + .1);
        await flushAndMount(game);
        game.openNoAdsPopup(reason: 'videos');
        await flushAndMount(game);
        expect(game.levelUpPopup, isNull);
        expect(game.noAdsPopup, isNull, reason: 'this visit used its one slot');

        await nextSession();
        await flushAndMount(game);
        expect(budget.selectedMoment, HomeMoment.noAds);
        expect(game.levelUpPopup, isNull);
        expect(game.noAdsPopup, isNotNull);
        expect(game.storage.noAdsPopupShowsToday, 1);
      },
    );
  }

  final normalTransitions = FlameTester<FlappySpikesGame>(() {
    return createRunTestGame(
      prefs: {
        'lvlIndex': 1,
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
      // Finish the launch visit before testing the post-run arrivals.
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
        game.runDebug.ignoreGates = false; // PRD-2.6 J3 counting run.
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

      // PRD-2.6 J7: choose LATER after the box reveal.
      final reveal = game.levelUpPopup!.reveal;
      await flushAndMount(game);
      stepGame(game, 2);
      await reveal.current.choose(false);
      await io();
      await flushAndMount(game);
      expect(game.levelUpPopup, isNull);
      expect(game.noAdsPopup, isNull, reason: 'one moment on this visit');

      // PRD §8.3 item 19: the first counting run earned a day-streak
      // reward. C2 selects it before the deferred No-Ads offer.
      await finishRun(8);
      stepGame(game, Config.levelUpSettleDelay + .1);
      await io();
      await flushAndMount(game);
      expect(game.levelUpPopup, isNull);
      expect(game.noAdsPopup, isNull);
      expect(game.streakCard, isNotNull);
      expect(game.streakCard!.reward, isTrue);
      game.streakCard!.collectButton!.onPressed();
      await io();
      await flushAndMount(game);
      await finishRun(8);
      stepGame(game, Config.levelUpSettleDelay + .1);
      await io();
      await flushAndMount(game);
      expect(game.noAdsPopup, isNotNull);
    },
  );
}
