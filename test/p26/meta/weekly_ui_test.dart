import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/progression/weekly_results.dart';
import 'package:flappy_spikes/components/progression/weekly_card.dart';
import 'package:flappy_spikes/components/progression/missions_panel.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/progression/weekly_course.dart';
import 'package:flappy_spikes/run/effects/best_line.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
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
    },
  );
}
