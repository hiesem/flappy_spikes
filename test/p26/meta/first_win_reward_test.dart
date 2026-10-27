import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/progression/first_win_reward.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The platform interface is used to simulate a failed preferences write.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../helpers.dart';

RunSummary result({DuelResult? duel, bool opponent = true, int score = 12}) =>
    RunSummary(
      score: score,
      hoopsPassed: score,
      coins: 12,
      bestBefore: 20,
      bestAfter: 20,
      runSeconds: 10,
      cause: MistakeCause.spikes,
      hoopIndex: score,
      timeline: RunTimeline.empty(),
      duel: duel,
      opponent: opponent
          ? OpponentRun(
              uid: 'other',
              name: 'Molly',
              score: 10,
              best: 20,
              level: 0,
              timeline: RunTimeline.empty(),
            )
          : null,
    );

class FailingPreferences extends InMemorySharedPreferencesStore {
  FailingPreferences(this.failedKey) : super.empty();
  final String failedKey;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.$failedKey') throw StateError('write failed');
    return super.setValue(valueType, key, value);
  }
}

void main() {
  var now = DateTime(2026, 10, 27, 23, 59);
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(clock: () => now),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'PRD 932: only YOU WIN pays, once per local civil day and after reload',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final balance = g.menu.wallet.balance;
      for (final s in [
        result(opponent: false),
        result(opponent: false, duel: DuelResult.win),
        result(duel: DuelResult.draw),
        result(duel: DuelResult.lose),
      ]) {
        expect(await FirstWinReward.pay(g, s), 0);
      }
      expect(g.menu.wallet.balance, balance);
      // Missing explicit duel uses exactly the header's comparison.
      final awards = await Future.wait([
        FirstWinReward.pay(g, result()),
        FirstWinReward.pay(g, result()),
      ]);
      expect(awards, [20, 0]);
      expect(g.menu.wallet.balance, balance + 20);
      final today = Missions.localDay(g.storage.now().toLocal());
      expect(g.storage.firstWinDay, today);
      await g.storage.load();
      expect(await FirstWinReward.pay(g, result()), 0);
      expect(
        (await SharedPreferences.getInstance()).getInt('firstWinDay'),
        today,
      );
      now = DateTime(2026, 10, 28);
      expect(await FirstWinReward.pay(g, result()), 20);
      expect(g.storage.firstWinDay, today + 1);
      // A clock rollback cannot turn yesterday into another daily payout.
      now = DateTime(2026, 10, 27);
      expect(await FirstWinReward.pay(g, result()), 0);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'PRD 932 reduced motion: still line, no flight, reward remains paid after dismissal',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      g.reduceMotionOverride = true;
      final summary = result();
      final before = g.menu.wallet.balance;
      final page = ResultsScreen(
        summary: summary,
        model: ResultsModel.of(summary),
      );
      g.world.add(page);
      await flushAndMount(g);
      expect(g.menu.wallet.balance, before + 20);
      stepGame(g, 8);
      await flushAndMount(g);
      stepGame(g, 2);
      final bonus = page.firstWinReward!;
      expect(bonus.scale.x, 1);
      expect(bonus.opacity, 1);
      expect(bonus.flight, isNull);
      expect(page.shownReward, 32);
      page.removeFromParent();
      await flushAndMount(g);
      expect(await FirstWinReward.pay(g, summary), 0);
      expect(g.menu.wallet.balance, before + 20);
    },
  );

  for (final failedKey in ['firstWinDay', 'coins']) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'storage failure on $failedKey leaves results page usable',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        final previous = SharedPreferencesStorePlatform.instance;
        SharedPreferencesStorePlatform.instance = FailingPreferences(failedKey);
        try {
          final summary = result();
          final page = ResultsScreen(
            summary: summary,
            model: ResultsModel.of(summary),
          );
          g.world.add(page);
          await flushAndMount(g);
          stepGame(g, .4);
          expect(page.canContinue, isTrue);
          expect(page.header!.text, 'YOU WIN!');
          expect(page.firstWinReward, isNull);
        } finally {
          SharedPreferencesStorePlatform.instance = previous;
        }
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'NEXT at CLAIM displays the first-win moment before leaving',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final summary = result();
      const model = ResultsModel(
        score: 12,
        bestBefore: 20,
        bestAfter: 20,
        reward: 12,
        levelBefore: 0,
        levelAfter: 1,
        levelReward: 25,
      );
      final page = ResultsScreen(summary: summary, model: model);
      g.world.add(page);
      await flushAndMount(g);
      stepGame(g, 4.1);
      await flushAndMount(g);
      expect(page.claimShowing, isTrue);
      expect(page.firstWinReward!.opacity, 0);
      page.next();
      expect(page.leaving, isTrue);
      stepGame(g, 3.0);
      await flushAndMount(g);
      expect(page.firstWinReward!.opacity, 1);
      expect(page.firstWinReward!.shownCoins, greaterThan(0));
      expect(page.shownReward, greaterThan(37));
    },
  );

  for (final h in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      'PRD 932 style A at $h: line, coins, combined reward and strip NEXT shift',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        final summary = result();
        final page = ResultsScreen(
          summary: summary,
          model: ResultsModel.of(summary),
        );
        g.world.add(page);
        await flushAndMount(g);
        final bonus = page.firstWinReward!;
        final nextY = page.nextButton.position.y;
        final originalScale = page.content.scale.y;
        final nextScreenY = page.content.position.y + nextY * originalScale;
        expect(
          originalScale,
          closeTo(
            h == 711
                ? 1
                : (ResultsConfig.nextTopFor(h) - 2 - ResultsConfig.topFor(h)) /
                      (581 - ResultsConfig.contentTop),
            1e-5,
          ),
        );
        page.missionsStripVisible = true;
        stepGame(g, .01);
        expect(
          page.content.position.y +
              page.nextButton.position.y * page.content.scale.y,
          closeTo(nextScreenY + 10, 1e-4),
        );
        expect(page.content.scale.y, lessThanOrEqualTo(originalScale));
        expect(
          page.nextButton.width * page.content.scale.x,
          closeTo(292, 1e-4),
        );
        expect(
          page.nextButton.height * page.content.scale.y,
          closeTo(50, 1e-4),
        );
        expect(bonus.position.y, 595);
        // The full 18 pt line clears NEXT even on the short layout.
        expect(bonus.position.y + 9, lessThan(page.nextButton.position.y));
        expect(558, lessThan(bonus.position.y - 9 - 22));
        stepGame(g, 6);
        await flushAndMount(g);
        stepGame(g, 2);
        expect(bonus.shownCoins, 20);
        expect(bonus.flight, isNotNull);
        expect(page.shownReward, 32);
        expect(page.rewardText.text, '32');
        page.missionsStripVisible = false;
        stepGame(g, .01);
        expect(page.nextButton.position.y, closeTo(nextY, 1e-4));
        expect(page.content.scale.y, closeTo(originalScale, 1e-6));
        expect(bonus.position.y, 572);
        expect(bonus.position.y + 9, lessThan(page.nextButton.position.y));
        final duplicate = ResultsScreen(
          summary: summary,
          model: ResultsModel.of(summary),
        );
        g.world.add(duplicate);
        await flushAndMount(g);
        expect(duplicate.firstWinReward, isNull);
      },
    );
  }
}
