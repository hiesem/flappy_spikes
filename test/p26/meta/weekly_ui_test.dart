import 'dart:async';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/home/home_screen.dart'
    show MenuCornerBox;
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/components/progression/weekly_results.dart';
import 'package:flappy_spikes/components/progression/weekly_card.dart';
import 'package:flappy_spikes/components/progression/missions_panel.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/progression/weekly_course.dart';
import 'package:flappy_spikes/run/effects/best_line.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/run/screens/level_reveal_sheet.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  test('G5 hint respects unlock, day, tier and 568 mission rule', () {
    bool eligible({
      bool weekly = false,
      bool counts = true,
      int games = 6,
      int best = 40,
      int weekBest = 34,
      int shown = 99,
      int today = 100,
      double height = 568,
      bool moved = false,
    }) => showWeeklyHint(
      weekly: weekly,
      counts: counts,
      games: games,
      bestHoops: best,
      weeklyBest: weekBest,
      shownDay: shown,
      today: today,
      height: height,
      missionMoved: moved,
    );
    expect(eligible(), isTrue);
    expect(eligible(weekly: true), isFalse);
    expect(eligible(counts: false), isFalse);
    expect(eligible(games: 5), isFalse);
    expect(eligible(best: 39), isFalse);
    expect(eligible(weekBest: 120), isFalse);
    expect(eligible(shown: 100), isFalse);
    expect(eligible(shown: 101), isFalse);
    expect(eligible(moved: true), isFalse);
    expect(eligible(height: 711, moved: true), isTrue);
    expect(weeklyHintText(0), "Try this week's course →");
    expect(weeklyHintText(34), "Try this week's course → beat hoop 34");
  });

  final monday = DateTime.utc(2026, 10, 26);
  for (final weekly in [false, true]) {
    late FakeInterstitialAds ads;
    late AnalyticsSpy spy;
    late Completer<void> adClosed;
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({
        Obf.prefGamesPlayed: 6,
        Obf.prefBestHoops: 40,
      });
      ads = FakeInterstitialAds(mode: FakeAdMode.succeed);
      spy = AnalyticsSpy();
      adClosed = Completer<void>();
      ads.hold = adClosed.future;
      return FlappySpikesGame(
        soundEnabled: false,
        worldHeight: 711,
        clock: () => monday,
        services: spy,
        monetization: Monetization(interstitial: ads),
      );
    }, gameSize: Vector2(320, 711)).testGameWidget(
      'G5 ${weekly ? 'FLY AGAIN' : 'hint'} observes interstitial and Home arrival',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        await g.storage.saveArmedPowerup('shield');
        if (weekly) {
          await g.startWeeklyCourse();
        } else {
          await g.startRun();
        }
        await flushAndMount(g);
        final run = g.run!;
        final summary = run.endRun();
        g.endRun(summary);
        await g.weeklyWritesSettled;
        g.showResults(summary);
        await flushAndMount(g);
        stepGame(g, 1);
        final page = g.resultsScreen!;
        final priorSlotEvents = spy.events
            .where((e) => e.$1 == 'home_slot_shown')
            .length;
        if (weekly) {
          page.nextButton.onPressed();
        } else {
          expect(page.weeklyHintVisible, isTrue);
          page.content.children
              .whereType<MenuButton>()
              .singleWhere(
                (button) => button.children.whereType<MenuText>().any(
                  (text) => text.text == weeklyHintText(0),
                ),
              )
              .onPressed();
        }
        await flushAndMount(g);
        expect(g.interstitialShowing, isTrue);
        expect(ads.shown, 1);
        expect(g.run, same(run));
        expect(
          spy.events.where((e) => e.$1 == 'ad_interstitial_shown'),
          hasLength(1),
        );
        adClosed.complete();
        await flushAndMount(g);
        expect(g.interstitialShowing, isFalse);
        expect(g.run?.setup.weekly, isTrue);
        expect(g.run, isNot(same(run)));
        expect(
          spy.events.where((e) => e.$1 == 'home_slot_shown').length,
          priorSlotEvents + 1,
        );
        if (weekly) expect(g.storage.armedPowerup, 'shield');
      },
    );
  }
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 12,
      Obf.prefBestHoops: 40,
      'firstSessionDone': true,
      'noAdsPopupLastMs': monday.millisecondsSinceEpoch,
      Obf.prefStreakPaidDay: Missions.localDay(monday.toLocal()),
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 711,
      clock: () => monday,
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'G5 weekly replay waits for a Home no-ads popup',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
      await flushAndMount(g);
    },
    verify: (g, _) async {
      await g.startWeeklyCourse();
      await flushAndMount(g);
      final oldRun = g.run!;
      final summary = oldRun.endRun();
      g.endRun(summary);
      await g.weeklyWritesSettled;
      g.showResults(summary);
      await flushAndMount(g);
      await g.storage.saveNoAdsPopupLastMs(0);
      await g.storage.saveNoAdsPopupVideos(3);
      await g.storage.saveLastScore(Config.noAdsPopupMinScore);
      stepGame(g, 1);
      g.resultsScreen!.nextButton.onPressed();
      await flushAndMount(g);
      expect(g.noAdsPopup, isNotNull);
      expect(g.state, GameState.start);
      expect(g.run, isNull);
      g.closeNoAdsPopup();
      await flushAndMount(g);
      expect(g.run?.setup.weekly, isTrue);
      expect(g.run, isNot(same(oldRun)));
    },
  );
  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({
        Obf.prefGamesPlayed: 6,
        Obf.prefBestHoops: 40,
      });
      return FlappySpikesGame(
        soundEnabled: false,
        worldHeight: height,
        clock: () => monday,
      );
    }, gameSize: Vector2(320, height)).testGameWidget(
      'G5 missions card starts the weekly course at $height',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
        await flushAndMount(g);
      },
      verify: (g, _) async {
        final strip = g.homeScreen!.children
            .whereType<MissionsHomeStrip>()
            .single;
        strip.onPressed();
        await flushAndMount(g);
        final panel = g.world.children.whereType<MissionsPanel>().single;
        final card = panel.card.children.whereType<WeeklyCard>().single;
        expect(card.position.y, 58);
        expect(panel.card.y, greaterThanOrEqualTo(44));
        expect(
          panel.card.y + panel.card.height,
          lessThanOrEqualTo(height - 44),
        );
        card.children.whereType<MenuButton>().single.onPressed();
        await flushAndMount(g);
        expect(g.run?.setup.weekly, isTrue);
      },
    );
  }
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 6,
      Obf.prefBestHoops: 40,
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 711,
      clock: () => monday,
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'G5 normal results persist the daily hint and start a weekly run',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      await g.startRun();
      await flushAndMount(g);
      final run = g.run!;
      final summary = run.endRun();
      g.endRun(summary);
      g.showResults(summary);
      await flushAndMount(g);
      final page = g.resultsScreen!;
      expect(page.weeklyHintVisible, isTrue);
      expect(g.storage.weeklyHintDay, Missions.localDay(monday.toLocal()));
      await g.storage.load();
      expect(g.storage.weeklyHintDay, Missions.localDay(monday.toLocal()));
      stepGame(g, 1);
      final hint = page.content.children.whereType<MenuButton>().singleWhere(
        (button) => button.children.whereType<MenuText>().any(
          (text) => text.text == weeklyHintText(0),
        ),
      );
      hint.onPressed();
      await flushAndMount(g);
      expect(g.run?.setup.weekly, isTrue);
    },
  );
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 6,
      Obf.prefBestHoops: 40,
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 568,
      clock: () => monday,
    );
  }, gameSize: Vector2(320, 568)).testGameWidget(
    'G5 short results hint fits above NEXT when no mission moved',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      await g.startRun();
      await flushAndMount(g);
      final summary = g.run!.endRun();
      g.endRun(summary);
      g.missionsAtRunStart = null;
      g.showResults(summary);
      await flushAndMount(g);
      final page = g.resultsScreen!;
      expect(page.weeklyHintVisible, isTrue);
      final hint = page.content.children.whereType<MenuButton>().singleWhere(
        (button) => button.children.whereType<MenuText>().any(
          (text) => text.text == weeklyHintText(0),
        ),
      );
      expect(
        hint.position.y + hint.height,
        lessThanOrEqualTo(page.nextButton.position.y),
      );
    },
  );
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 6,
      Obf.prefBestHoops: 40,
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 711,
      clock: () => monday,
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'G5 hint cannot open a second level reveal',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      await g.startRun();
      await flushAndMount(g);
      g.score = 25;
      g.run!.state.score = 25;
      final summary = g.run!.endRun();
      g.endRun(summary);
      g.showResults(summary);
      await flushAndMount(g);
      final page = g.resultsScreen!;
      expect(page.weeklyHintVisible, isTrue);
      stepGame(g, 8);
      await flushAndMount(g);
      final reveal = page.revealSheet!;
      final hint = page.content.children.whereType<MenuButton>().singleWhere(
        (button) => button.children.whereType<MenuText>().any(
          (text) => text.text == weeklyHintText(0),
        ),
      );
      hint.onPressed();
      await flushAndMount(g);
      expect(page.revealSheet, same(reveal));
      expect(page.children.whereType<LevelRevealSheet>(), hasLength(1));
      expect(g.state, GameState.results);
    },
  );
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 6,
      Obf.prefBestHoops: 40,
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 711,
      clock: () => monday,
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'G5 weekly results retain album reward and then the level reveal',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
      await g.storage.saveAlbumCounts(List.filled(8, 1));
    },
    verify: (g, _) async {
      await g.startWeeklyCourse();
      await flushAndMount(g);
      final run = g.run!;
      g.score = 25;
      run.state.score = 25;
      final summary = run.endRun();
      g.endRun(summary);
      await g.weeklyWritesSettled;
      g.showResults(summary);
      await flushAndMount(g);
      final page = g.resultsScreen!;
      expect(page.model.levelUp, isTrue);
      stepGame(g, 1);
      page.nextButton.onPressed();
      expect(g.run, same(run));
      stepGame(g, 9);
      await flushAndMount(g);
      final album = page.revealSheet!;
      expect(album.album, isTrue);
      stepGame(g, 3);
      await album.choose(false);
      await flushAndMount(g);
      expect(g.storage.albumRewardClaimed, isTrue);
      page.nextButton.onPressed();
      await flushAndMount(g);
      final level = page.revealSheet!;
      expect(level.album, isFalse);
      stepGame(g, 3);
      await level.choose(false);
      await flushAndMount(g);
      expect(g.run?.setup.weekly, isTrue);
      expect(g.run, isNot(same(run)));
    },
  );
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 6,
      Obf.prefBestHoops: 40,
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 711,
      clock: () => monday,
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'G5 weekly level reveal waits until leaving results',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      await g.startWeeklyCourse();
      await flushAndMount(g);
      final run = g.run!;
      run.state.score = 25;
      g.score = 25;
      final summary = run.endRun();
      g.endRun(summary);
      await g.weeklyWritesSettled;
      g.showResults(summary);
      await flushAndMount(g);
      final page = g.resultsScreen!;
      expect(page.model.levelUp, isTrue);
      stepGame(g, 8);
      await flushAndMount(g);
      expect(page.revealSheet, isNull);
      expect(g.menu.levels.pending, isNotEmpty);
      page.nextButton.onPressed();
      await flushAndMount(g);
      final reveal = page.revealSheet!;
      expect(g.run, same(run));
      stepGame(g, 2);
      await reveal.choose(false);
      await flushAndMount(g);
      expect(g.menu.levels.pending, isEmpty);
      expect(g.run?.setup.weekly, isTrue);
      expect(g.run, isNot(same(run)));
    },
  );
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 6,
      Obf.prefBestHoops: 40,
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 711,
      clock: () => monday,
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'G5 weekly hoop marker, results tiers, board and replay',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
      await g.storage.saveWeeklyBest({WeeklyWeek.at(monday).key: 14});
    },
    verify: (g, _) async {
      await g.startWeeklyCourse();
      await flushAndMount(g);
      final run = g.run!;
      expect(run.weeklyBestBefore, 14);
      expect(run.bestTargetHoops, 14);
      expect(run.bestLine, isA<BestLine>());
      expect(run.bestLine!.flagText, 'WEEK 14');
      run.state.hoopsPassed = 14;
      run.events.emit(const HoopPassed(null));
      expect(run.beatBestHoop, -1);
      run.state.hoopsPassed = 15;
      run.events.emit(const HoopPassed(null));
      expect(run.beatBestHoop, 15);
      expect(RunHud.of(run)!.bestSticker!.text, 'NEW WEEK BEST!');
      final summary = run.endRun();
      g.endRun(summary);
      await g.weeklyWritesSettled;
      g.showResults(summary);
      await flushAndMount(g);
      final page = g.resultsScreen!;
      expect(page.isWeekly, isTrue);
      expect(
        page.content.children.whereType<ResultsHeader>().single.text,
        'WEEKLY COURSE',
      );
      expect(
        page.content.children.whereType<WeeklyResultsDaysTag>(),
        hasLength(1),
      );
      final tiers = page.content.children
          .whereType<WeeklyResultsTiers>()
          .single;
      final next = tiers.children.whereType<WeeklyNextTierBox>().single;
      expect(next.size, Vector2(240, 22));
      expect(next.complete, isFalse);
      expect(page.rank.parent, isNull);
      expect(page.bar.parent, isNull);
      expect(page.weeklyTierCoins, 40);
      expect(
        page.content.children.whereType<WeeklyResultsTiers>(),
        hasLength(1),
      );
      expect(
        page.content.children.whereType<ResultsLevelStage>().single.position.x,
        -1000,
      );
      stepGame(g, 4);
      await flushAndMount(g);
      expect(page.you.shownScore, 15);
      expect(page.newBestSticker!.text, 'NEW WEEK BEST!');
      expect(page.shownReward, summary.coins + 40);
      page.weeklyBoardButton!.onPressed();
      await flushAndMount(g);
      expect(g.resultsBoard, isNotNull);
      final board = g.resultsBoard!;
      expect(board.children.whereType<MenuCornerBox>(), hasLength(1));
      expect(board.children.whereType<MenuCornerBox>().single.gearMix, 0);
      expect(board.backButton.onPressed, isNotNull);
      g.onKeyEvent(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
        {},
      );
      expect(g.resultsBoard, isNull);
      page.nextButton.onPressed();
      await flushAndMount(g);
      expect(g.run?.setup.weekly, isTrue);
      expect(g.run, isNot(same(run)));
      expect(g.storage.armedPowerup, isNot('consumed'));
      final second = g.run!;
      second.state.hoopsPassed = 120;
      final finalSummary = second.endRun();
      g.endRun(finalSummary);
      await g.weeklyWritesSettled;
      g.showResults(finalSummary);
      await flushAndMount(g);
      final finalTiers = g.resultsScreen!.content.children
          .whereType<WeeklyResultsTiers>()
          .single;
      final allDone = finalTiers.children.whereType<WeeklyNextTierBox>().single;
      expect(allDone.size, Vector2(240, 22));
      expect(allDone.complete, isTrue);
      expect(allDone.text, 'ALL TIERS DONE THIS WEEK!');
    },
  );
}
