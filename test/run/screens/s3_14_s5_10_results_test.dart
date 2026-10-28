import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flappy_spikes/game/config.dart';
import '../../levels/progression_fixture.dart';
// PRD-2.6 J1–J5 supersedes the legacy ranks, coins and automatic catch-up.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/share/share_card.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

FlappySpikesGame trackGame({
  Map<String, Object> prefs = const {},
  AnalyticsSpy? services,
  double? worldHeight,
}) =>
    createRunTestGame(prefs: trackPrefs(prefs), services: services, worldHeight: worldHeight)
      ..runDebug.ignoreGates = false;

/// One results test on a 320 × [h] game (FlameTester widget binding).
void rt(
  String name,
  FlappySpikesGame Function() create,
  Future<void> Function(FlappySpikesGame g) body, {
  double h = 711,
}) {
  FlameTester<FlappySpikesGame>(
    create,
    gameSize: Vector2(320, h),
  ).testGameWidget(
    name,
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) => body(g),
  );
}

/// PRD-2 §3.14 / §5.10 / §7 results tests (WP-2e).
void main() {
  const claimed1to6 = ['1', '2', '3', '4', '5', '6'];

  group('§5.10 level bar and rank line (pure)', () {
    test('§5.10 WP-L progress label: a run of 815 at HAWK is "185 TO SPIKE '
        'ACE" (one run toward 1 000)', () {
      final b = LevelBar.at(7, score: 815);
      expect(b.level, 7);
      expect(b.label, '0 TO FEATHERWEIGHT');
      expect(b.fraction, closeTo(1.0, 1e-9));
      expect(LevelBar.at(7).label, '500 TO FEATHERWEIGHT');
      expect(LevelBar.at(7).fraction, 0);
      expect(rankText(7), 'HOOP ROOKIE · LV 7');
    });

    test('§5.10 unranked: "UNRANKED", bar toward EGG', () {
      final b = LevelBar.at(0, score: 7);
      expect(b.level, 0);
      expect(b.label, '18 TO HATCHLING');
      expect(b.fraction, closeTo(7 / 25, 1e-9));
      expect(rankText(0), 'UNRANKED');
    });

    test('§5.10 "MAX LEVEL" at level 10, thousands with a space', () {
      expect(LevelBar.at(10, score: 5120).label, '0 TO KINGFISHER');
      expect(LevelBar.at(10).fraction, 0);
      expect(LevelBar.at(8, score: 1500).label, '0 TO SWALLOW');
      expect(LevelBar.at(9, score: 2000).label, '0 TO HUMMINGBIRD');
      expect(LevelBar.at(9, score: 6000).label, '0 TO HUMMINGBIRD');
    });

    test('§3.14 WP-L the model carries the stored level before / after', () {
      const m = ResultsModel(
        score: 815,
        bestBefore: 760,
        bestAfter: 815,
        reward: 65,
        levelReward: 800,
        levelBefore: 6,
        levelAfter: 7,
      );
      expect(m.levelBefore, 6);
      expect(m.levelAfter, 7);
      expect(m.newBest, isTrue);
      expect(m.levelUp, isTrue);
      expect(m.hasClaim, isTrue);
      const lose = ResultsModel(
        score: 310,
        bestBefore: 640,
        bestAfter: 640,
        reward: 40,
        levelBefore: 6,
        levelAfter: 6,
      );
      expect(lose.newBest, isFalse);
      expect(lose.levelUp, isFalse);
      expect(lose.hasClaim, isFalse);
    });
  });

  test('PRD-2.6 J7a accumulated points and endless labels', () {
    final bar = LevelBar.at(10, points: 420, score: 180);
    expect(bar.counter, '600 / 800');
    expect(bar.fraction, .75);
    expect(bar.label, '200 TO KINGFISHER');
    expect(rankText(10), 'HUMMINGBIRD · LV 10');
    expect(rankText(34), 'ETERNAL WING · LV 34');
    expect(LevelBar.at(34, points: 6240).label, '3 760 TO LEVEL 35');
    expect(LevelBar.at(34, points: 6240).counter, '6 240 / 10 000');
  });

  group('§5.10 results page', () {
    rt('J3 debug score 815 at L7 leaves the accumulated level bar unchanged',
      () => trackGame(prefs: {'lvlIndex': 7, 'lvlPoints': 100})
        ..runDebug.ignoreGates = true,
      (g) async {
        await startRun(g);
        g.run!.ctx.addScore(815);
        killRun(g);
        await flushAndMount(g);
        final page = g.resultsScreen!;
        expect(page.model.countsForLevel, isFalse);
        expect(page.model.levelUp, isFalse);
        stepGame(g, 3.5);
        expect(g.menu.levels.points, 100);
        expect(page.bar.fraction, closeTo(.2, 1e-6));
        expect(page.barLabel.text, '400 TO FEATHERWEIGHT');
      },
    );

    rt('J3 bar starts at accumulated points and adds only this eligible run',
      () => trackGame(prefs: {'lvlIndex': 7, 'lvlPoints': 100}),
      (g) async {
        await startRun(g);
        g.run!.ctx.addScore(100);
        killRun(g);
        await flushAndMount(g);
        final page = g.resultsScreen!;
        expect(page.model.pointsBefore, 100);
        expect(page.model.levelUp, isFalse);
        expect(page.bar.fraction, closeTo(.2, 1e-6));
        stepGame(g, 3.5);
        expect(g.menu.levels.points, 200);
        expect(page.bar.fraction, closeTo(.4, 1e-6));
        expect(page.barLabel.text, '300 TO FEATHERWEIGHT');
      },
    );

    /// Starts a run, sets the run [score] and [coins] (hoop coins through
    /// `ctx.earn`) and ends it; returns once the results page is mounted.
    Future<ResultsScreen> endWith(
      FlappySpikesGame g, {
      required int score,
      int coins = 0,
      void Function(FlappySpikesGame g)? extra,
    }) async {
      await startRun(g);
      final run = g.run!;
      run.ctx.addScore(score);
      if (coins > 0) run.ctx.earn(coins, CoinSource.hoop);
      extra?.call(g);
      killRun(g);
      await flushAndMount(g);
      expect(g.state, GameState.results);
      return g.resultsScreen!;
    }

    FlameTester<FlappySpikesGame>(
      () => trackGame(prefs: {'lvlIndex': 10, 'lvlPoints': 700, 'bestScore': 900}),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'J3 background tap skips to reveal',
      setUp: (g, tester) async {
        tester.view.physicalSize = const Size(320, 711);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await g.ready(); await preloadImages(g);
      },
      verify: (g, tester) async {
        final page = await endWith(g, score: 180);
        stepGame(g, .4);
        expect(page.revealReady, isFalse);
        await tester.tapAt(const Offset(10, 350));
        await tester.pump(const Duration(milliseconds: 100));
        expect(page.revealReady, isTrue);
      },
    );

    rt(
      'PRD-2.6 J7a accumulated run fills and settles at 2.15 s',
      () => trackGame(
        prefs: {'lvlIndex': 10, 'lvlPoints': 420, 'bestScore': 900},
      ),
      (g) async {
        final page = await endWith(g, score: 180, coins: 22);
        expect(page.bar.fraction, 420 / 800);
        expect(page.barCounter.text, '420 / 800');
        stepGame(g, 1.24);
        expect(page.bar.fraction, 420 / 800);
        expect(page.settled, isFalse);
        stepGame(g, .36);
        expect(page.bar.fraction, greaterThan(420 / 800));
        expect(page.bar.fraction, lessThan(600 / 800));
        expect(page.scoreGain.text, '+180');
        stepGame(g, .4);
        expect(page.bar.fraction, closeTo(.75, 1e-4));
        expect(page.barCounter.text, '600 / 800');
        expect(page.settled, isFalse);
        stepGame(g, .16);
        expect(page.settled, isTrue);
        expect(page.barLabel.text, '200 TO KINGFISHER');
        expect(page.rank.color, Config.uiAccent);
      },
    );

    rt('PRD-2.6 J7a preserves pre-run points on level-up',
      () => trackGame(prefs: {'lvlIndex': 10, 'lvlPoints': 700, 'bestScore': 900}),
      (g) async {
        final page = await endWith(g, score: 180);
        expect(page.model.pointsBefore, 700);
        expect(page.bar.fraction, closeTo(700 / 800, 1e-6));
        stepGame(g, 2.0);
        expect(page.bar.fraction, closeTo(1, 1e-6));
        expect(page.barCounter.text, '800 / 800');
        expect(page.barLabel.text, isEmpty, reason: 'PRD-2.6 J7a: new level label appears at reset');
        expect(page.surplusLabel.text, '+80 OVER · DROPPED');
        expect(page.surplusLabel.color.a, greaterThan(0));
      });

    rt('J4 reveals all pending rewards before paying',
      () => trackGame(prefs: {'lvlIndex': 10, 'lvlPoints': 700, 'bestScore': 900}),
      (g) async {
        final page = await endWith(g, score: 180);
        expect(page.model.levelUp, isTrue);
        final row = g.menu.levels.pending.single;
        await g.storage.saveLvlPending([row, {...row, 'lvl': 12}]);
        final count = g.menu.levels.pending.length;
        expect(count, greaterThan(1));
        final balance = g.menu.wallet.balance;
        stepGame(g, .4);
        page.skipToReveal();
        await flushAndMount(g);
        await flushAndMount(g);
        for (var i = 0; i < count; i++) {
          final sheet = page.activeRevealSheet!;
          stepGame(g, 2);
          await sheet.choose(false);
          await flushAndMount(g);
          await flushAndMount(g);
          if (i < count - 1) {
            expect(g.menu.wallet.balance, balance);
            expect(g.menu.levels.pending, hasLength(count));
          }
        }
        expect(g.menu.levels.pending, isEmpty);
      });

    rt('J3 exact level threshold hides zero surplus',
      () => trackGame(prefs: {'lvlIndex': 10, 'lvlPoints': 700, 'bestScore': 900}),
      (g) async {
        final page = await endWith(g, score: 100);
        stepGame(g, 2.0);
        expect(page.surplus, 0);
        expect(page.surplusLabel.color.a, 0);
      });

    rt('PRD-2.6 J3 ineligible runs do not advance the level bar',
      () => trackGame(prefs: {'lvlIndex': 10, 'lvlPoints': 420, 'bestScore': 900}),
      (g) async {
        g.runDebug.ignoreGates = true;
        final page = await endWith(g, score: 180);
        expect(page.model.countsForLevel, isFalse);
        expect(page.model.pointsBefore, 420);
        stepGame(g, 2.2);
        expect(page.bar.fraction, closeTo(420 / 800, 1e-6));
        expect(page.barCounter.text, '420 / 800');
        expect(page.barLabel.text, '380 TO KINGFISHER');
        expect(page.scoreGain.text, '+0');
        expect(g.menu.levels.points, 420);
      });

    for (final when in [.4, 1.5, 2.2]) {
      rt('PRD-2.6 J7a skip at $when is silent and preserves reward',
        () => trackGame(prefs: {'lvlIndex': 10, 'lvlPoints': 700, 'bestScore': 900}),
        (g) async {
          final sfx = sfxLog(g);
          final page = await endWith(g, score: 180, coins: 22);
          stepGame(g, when);
          final bursts = page.fx.bursts.length;
          final balance = g.menu.wallet.balance;
          sfx.clear();
          page.skipToReveal();
          expect(page.revealReady, isTrue);
          expect(page.stage.level, 11);
          expect(page.bar.fraction, closeTo(0, 1e-6));
          expect(page.shownReward, 222);
          expect(page.fx.bursts, hasLength(bursts));
          expect(sfx, isEmpty, reason: 'skipped cues must not burst together');
          expect(g.menu.wallet.balance, balance);
          expect(g.storage.lvlPending, isNotEmpty);
          expect(page.rewardChip.children, isEmpty, reason: 'J4 fills L-A18 after reveal');
        });
    }

    rt(
      'PRD-2.6 J7a surplus drop, automatic coins, reset and reveal boundary',
      () => trackGame(prefs: {'lvlIndex': 10, 'bestScore': 900}),
      (g) async {
        final page = await endWith(g, score: 980, coins: 22);
        final before = g.menu.wallet.balance;
        stepGame(g, 1.9);
        expect(page.stage.level, 10);
        stepGame(g, .15);
        expect(page.bar.fraction, closeTo(1, 1e-4));
        expect(page.surplusLabel.text, '+180 OVER · DROPPED');
        expect(page.surplusLabel.color.a, greaterThan(0));
        stepGame(g, .2);
        expect(page.stage.level, 11);
        expect(page.rank.text, 'KINGFISHER · LV 11');
        expect(page.fx.coins, isNull);
        stepGame(g, .4);
        await flushAndMount(g);
        expect(page.fx.coins, isNotNull);
        expect(page.levelCoinsLabel.text, '+200');
        stepGame(g, .41);
        expect(page.bar.fraction, closeTo(0, 1e-5));
        expect(page.barLabel.text, '900 TO RIM SKIMMER');
        expect(page.surplusLabel.color.a, 0);
        expect(page.revealReady, isFalse);
        stepGame(g, .64);
        expect(page.shownReward, 222);
        expect(page.revealReady, isTrue);
        expect(page.settled, isFalse, reason: 'rating waits for the J4 reveal');
        expect(g.menu.wallet.balance, before, reason: 'J4 pays on EQUIP/LATER');
        expect(g.storage.lvlPending, isNotEmpty);
      },
    );

    rt(
      '§3.14 solo: the page replaces the game-over panel, no versus parts, '
      'no ad, NEXT goes home',
      () => trackGame(
        prefs: {
          'bestScore': 900,
          'playerLevel': 7,
          'claimedLevels': claimed1to6 + ['7', '8'],
        },
      ),
      (g) async {
        final page = await endWith(g, score: 12, coins: 14);
        expect(page.model.reward, 14);
        expect(page.you.centreX, ResultsConfig.soloColumnX);
        expect(
          page.content.children.whereType<ResultsPlayerColumn>(),
          hasLength(1),
        );
        expect(page.canContinue, isFalse);
        stepGame(g, .3);
        expect(page.canContinue, isTrue);
        // Count-ups end at 1.15 s.
        stepGame(g, 1);
        expect(page.shownReward, 14);
        expect(page.you.shownScore, 12);
        expect(page.newBestSticker, isNull, reason: 'no new best');
        // WP-L the bar is the run's progress toward the next level (it
        // fills after every run).
        stepGame(g, 2.5);
        expect(
          page.bar.fraction,
          closeTo(LevelBar.at(7, score: 12).fraction, 1e-4),
        );
        expect(page.barLabel.text, '488 TO FEATHERWEIGHT');
        // Strips over the page.
        expect(g.groundStripPriority, greaterThan(ResultsScreen.priorityOnTop));
        page.nextButton.onPressed();
        await flushAndMount(g);
        expect(g.state, GameState.start);
        expect(g.resultsScreen, isNull);
        expect(g.groundStripPriority, lessThan(0));
        expect(
          AdPlacement.values.map((p) => p.name),
          isNot(contains('doubleCoins')),
        );
      },
    );

    rt(
      '§3.14 YOUR REWARD includes puzzle coins and the win / draw bonus, '
      'not the balloon bonus',
      () => trackGame(
        prefs: {
          'bestScore': 900,
          'playerLevel': 7,
          'claimedLevels': claimed1to6 + ['7', '8'],
        },
      ),
      (g) async {
        final page = await endWith(
          g,
          score: 3,
          coins: 5,
          extra: (g) {
            g.run!.ctx.earn(120, CoinSource.puzzle); // 4/4 puzzle payout
            g.run!.ctx.earn(10, CoinSource.winBonus); // versus win (WP-5b)
          },
        );
        // The balloon bonus pays straight into the wallet after the run.
        await g.menu.wallet.add(300, CoinSource.bonus);
        expect(page.model.reward, 5 + 120 + 10);
        stepGame(g, 1.3);
        expect(page.shownReward, 135);
        expect(page.rewardText.text, '135');
      },
    );

    rt(
      '§5.10 new best without a level: NEW BEST at 1.2 s (perfect_1), the '
      'bar fills at 1.25 s (PRD-2.6 J7a), no CLAIM',
      () => trackGame(
        prefs: {
          'bestScore': 230,
          'playerLevel': 6,
          'claimedLevels': claimed1to6,
        },
      ),
      (g) async {
        final sfx = sfxLog(g);
        final page = await endWith(g, score: 262, coins: 30);
        stepGame(g, 1.1);
        expect(page.newBestSticker, isNull);
        stepGame(g, .15);
        await flushAndMount(g);
        expect(page.newBestSticker, isNotNull);
        expect(page.newBestSticker!.text, 'NEW BEST · 262');
        expect(sfx, contains('perfect1'));
        // PRD-2.6 J7a moved the fill to 1.25 s.
        expect(sfx, contains('lvBar'));
        stepGame(g, .45);
        expect(sfx, contains('lvBar'));
        stepGame(g, 1.3);
        // WP-L 262 at FLAPPER: short of GLIDER's 400.
        expect(
          page.bar.fraction,
          closeTo(LevelBar.at(6, score: 262).fraction, 1e-6),
        );
        expect(page.barLabel.text, '138 TO HOOP ROOKIE');
        expect(page.claimShowing, isFalse);
        expect(sfx, isNot(contains('lvUp')));
        expect(g.storage.unclaimedLevelReward, 0);
      },
    );

    rt(
      'PRD-2.6 J7a level up: celebration and pending reward until reveal choice',
      () => trackGame(
        prefs: {
          'bestScore': 760,
          'playerLevel': 6,
          'claimedLevels': claimed1to6,
        },
        services: AnalyticsSpy(),
      ),
      (g) async {
        final spy = g.services as AnalyticsSpy;
        final sfx = sfxLog(g);
        final page = await endWith(g, score: 815, coins: 65);
        // Owed from the run's end on (an app kill never loses it).
        expect(g.menu.levels.pendingLevelUp!.reward, 100);
        final prefs = await SharedPreferences.getInstance();
        expect(
          (jsonDecode(prefs.getString('lvlPending')!) as List).single['coins'],
          100,
        );
        expect(page.model.levelReward, 100);
        // 0 s: the level before this run.
        expect(page.stage.level, 6);
        expect(page.rank.text, 'WING WOBBLER · LV 6');
        // Bar to 100 % (0.9 s from 1.65 s), shake, then the pop at 2.81 s.
        stepGame(g, 2.85);
        await flushAndMount(g);
        expect(page.stage.level, 7);
        expect(page.rank.text, 'HOOP ROOKIE · LV 7');
        expect(page.stage.rays, 1);
        expect(sfx, contains('lvUp'));
        expect(sfx, isNot(contains('lvUpBig')));
        expect(
          page.fx.bursts.single.count,
          60 + 40,
          reason: 'lv 5-8: 100 confetti pieces',
        );
        stepGame(g, .6);
        expect(page.claimShowing, isFalse);
        stepGame(g, .35);
        expect(page.fx.fireworks.bursts, 3, reason: 'three fireworks');
        // PRD-2.6 J7a/J4: the reveal choice, not CLAIM, pays the reward.
        expect(page.claimShowing, isFalse);
        expect(page.revealReady, isTrue);
        final before = g.menu.wallet.balance;
        stepGame(g, .4);
        page.claimButton.button.onPressed();
        await flushAndMount(g);
        expect(
          g.menu.wallet.balance,
          before,
          reason: 'pending until EQUIP/LATER (PRD-2.6 J7a)',
        );
        expect(g.storage.lvlPending, isNotEmpty);
        expect(g.storage.unclaimedLevelReward, 0);
        expect(spy.events.where((e) => e.$1 == 'level_up').single.$2, {
          'level': 7,
          'games': g.storage.gamesPlayed,
          'run_score': 815,
          's_since_install': greaterThanOrEqualTo(0),
        });
        expect(spy.events.where((e) => e.$1 == 'level_reward_claimed'), isEmpty);
        expect(sfx, contains('lvClaim'));
        stepGame(g, 1.5);
        await flushAndMount(g);
        expect(sfx.where((s) => s == 'bnCoin'), hasLength(12));
        expect(page.shownReward, 165);
        // PRD-2.6 J7a: rays remain behind the upcoming item reveal.
        expect(page.stage.rays, 1);
        stepGame(g, 1);
        // WP-L the step used the run: SPIKE ACE needs 1 000 in one run.
        expect(page.barLabel.text, '500 TO FEATHERWEIGHT');
        expect(page.bar.fraction, closeTo(0, 1e-6));
        // PRD-2.6 J4 (PRD:1084-1099): LATER pays once and closes the sheet.
        await page.revealSheet!.choose(false);
        expect(page.settled, isTrue, reason: 'rating may start after reveal payout');
        expect(await claimLevelRewards(g, 'tap'), 0);
        expect(g.menu.wallet.balance, before + 100);
      },
    );

    rt(
      '§3.14 WP-L a run past several thresholds steps up ONE level: one '
      'celebration, that level\'s reward; a run below the best still levels',
      () => trackGame(prefs: {'bestScore': 400, 'playerLevel': 1}),
      (g) async {
        // 230 < best 400 (no new best), past CHICK, FLEDGLING and FLAPPER.
        final page = await endWith(g, score: 230);
        // EGG (unclaimed, the catch-up) 25 + CHICK 50.
        expect(page.model.levelBefore, 1);
        expect(page.model.levelAfter, 2);
        expect(page.model.levelReward, 100);
        expect(g.menu.levels.pendingLevelUp!.reward, 100);
        expect(g.storage.lvlIndex, 2);
        stepGame(g, 2.9);
        await flushAndMount(g);
        expect(page.newBestSticker, isNull);
        expect(page.stage.level, 2);
        expect(page.rank.text, 'FLUFFBALL · LV 2');
        expect(page.fx.bursts, hasLength(1), reason: 'one celebration');
        expect(page.fx.bursts.single.count, 60);
        stepGame(g, 1.4);
        // PRD-2.6 J7a/J4: keep the reward pending for the reveal choice.
        expect(page.claimShowing, isFalse);
        final before = g.menu.wallet.balance;
        page.claimButton.button.onPressed();
        await flushAndMount(g);
        expect(g.menu.wallet.balance, before);
        expect(g.storage.lvlPending, isNotEmpty);
      },
    );

    rt(
      '§5.10 lv 9-10: lv_up_big and a second wave (2 confetti + 2 rockets)',
      () => trackGame(
        prefs: {
          'bestScore': 4600,
          'playerLevel': 9,
          'claimedLevels': claimed1to6 + ['7', '8', '9'],
        },
      ),
      (g) async {
        final sfx = sfxLog(g);
        final page = await endWith(g, score: 5120);
        stepGame(g, 2.85);
        expect(sfx, contains('lvUpBig'));
        expect(page.fx.bursts.single.count, 150);
        stepGame(g, 1);
        expect(page.fx.bursts, hasLength(3));
        stepGame(g, .7);
        expect(page.fx.fireworks.bursts, 5);
        expect(page.rank.text, 'HUMMINGBIRD · LV 10');
      },
    );

    rt(
      'PRD-2.6 J7a NEXT after reveal preserves the pending reward',
      () => trackGame(
        prefs: {
          'bestScore': 760,
          'playerLevel': 6,
          'claimedLevels': claimed1to6,
        },
        services: AnalyticsSpy(),
      ),
      (g) async {
        final spy = g.services as AnalyticsSpy;
        final sfx = sfxLog(g);
        final page = await endWith(g, score: 815, coins: 65);
        stepGame(g, 4);
        expect(page.revealReady, isTrue);
        expect(page.claimShowing, isFalse);
        final before = g.menu.wallet.balance;
        page.nextButton.onPressed();
        await flushAndMount(g);
        expect(g.menu.wallet.balance, before);
        expect(spy.events.where((e) => e.$1 == 'level_reward_claimed'), isEmpty);
        expect(sfx, contains('lvClaim'));
        expect(page.shownReward, 165);
        // PRD-2.6 J4 (PRD:1084-1099): NEXT waits for LATER and payout.
        expect(g.state, GameState.results);
        stepGame(g, 2);
        await flushAndMount(g);
        await page.revealSheet!.choose(false);
        expect(g.menu.wallet.balance, before + 100);
        expect(await g.menu.levels.payPending(), 0);
        page.next();
        await flushAndMount(g);
        expect(g.state, GameState.start);
        expect(g.menu.levels.pendingLevelUp, isNull);
      },
    );

    rt(
      'PRD-2.6 J7a NEXT skips the prelude and preserves the reward',
      () => trackGame(
        prefs: {
          'bestScore': 760,
          'playerLevel': 6,
          'claimedLevels': claimed1to6,
        },
      ),
      (g) async {
        final page = await endWith(g, score: 815);
        stepGame(g, .5);
        final before = g.menu.wallet.balance;
        g.onKeyEvent(
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
            timeStamp: Duration.zero,
          ),
          {},
        );
        await flushAndMount(g);
        // PRD-2.6 J7a: a tap skips to the reveal before any payout.
        expect(page.revealReady, isTrue);
        expect(page.leaving, isFalse);
        expect(g.state, GameState.results);
        expect(g.menu.wallet.balance, before);
        expect(g.storage.lvlPending, isNotEmpty);
        // PRD-2.6 J4 (PRD:1084-1099): NEXT waits for LATER.
        page.next();
        await flushAndMount(g);
        stepGame(g, 2);
        await flushAndMount(g);
        expect(g.state, GameState.results);
        expect(g.menu.wallet.balance, before);
        expect(g.storage.lvlPending, isNotEmpty);
        await page.revealSheet!.choose(false);
        expect(g.menu.wallet.balance, before + page.model.levelReward);
        page.next();
        await flushAndMount(g);
        expect(g.state, GameState.start);
        expect(g.storage.lvlPending, isEmpty);
        expect(g.storage.unclaimedLevelReward, 0);
      },
    );

    rt(
      'PRD 2.6 O64 retains share and removes native leaderboard entry',
      () => trackGame(prefs: {'bestScore': 900, 'playerLevel': 7, 'claimedLevels': claimed1to6 + ['7', '8']}),

      (g) async {
        ShareCardData? shared;
        g.onShareScore = (s) => shared = s;
        final page = await endWith(g, score: 21);
        stepGame(g, .4);
        page.shareButton.onPressed();
        await flushAndMount(g); // PRD-2.3 §2.2 the nickname is made first
        expect(shared?.score, 21);
        expect(shared?.best, 900);
      },
    );
  });

  for (final (level, up) in [(0, false), (10, false), (34, false), (10, true)]) {
    FlameTester<FlappySpikesGame>(
      () => trackGame(
        prefs: {
          'lvlIndex': level,
          'lvlPoints': up ? 700 : level == 0 ? 0 : 100,
          'bestScore': 900,
        },
        worldHeight: 711,
      ),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'PRD-2.6 J7a results golden L$level${up ? ' level-up' : ''}',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
        for (final font in [
          ('Fredoka', 'Fredoka-SemiBold.ttf'),
          ('Opificio Neue', 'Opificio_neue-regular.ttf'),
        ]) {
          await (FontLoader(
            font.$1,
          )..addFont(rootBundle.load('assets/fonts/${font.$2}'))).load();
        }
      },
      verify: (g, tester) async {
        await startRun(g);
        g.run!.ctx.addScore(up ? 180 : 7);
        g.run!.ctx.earn(12, CoinSource.hoop);
        killRun(g);
        await flushAndMount(g);
        stepGame(g, up ? 2.1 : 2.2);
        await flushAndMount(g);
        final image = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          g.resultsScreen!.renderTree(ui.Canvas(recorder));
          return recorder.endRecording().toImage(320, 711);
        });
        await expectLater(
          image!,
          matchesGoldenFile('goldens/j3_results_l$level${up ? '_up' : ''}.png'),
        );
        image.dispose();
      },
    );
  }

  group('§3.14 / §7 unclaimedLevelReward', () {
    rt(
      '§7 an unclaimed level reward is credited at the next app start '
      '(no animation, no popup)',
      () => trackGame(
        prefs: {
          'bestScore': 815,
          'playerLevel': 7,
          'claimedLevels': claimed1to6,
          'unclaimedLevelReward': 800,
          'coins': 100,
        },
        services: AnalyticsSpy(),
      ),
      (g) async {
        final spy = g.services as AnalyticsSpy;
        expect(g.menu.wallet.balance, 100);
        expect(g.menu.levels.pendingLevelUp!.reward, 100);
        expect(await claimLevelRewards(g, 'app_start'), 100);
        expect(g.menu.wallet.balance, 200);
        expect(g.storage.unclaimedLevelReward, 0);
        expect(g.storage.lvlPending, isEmpty);
        expect(g.menu.levels.pendingLevelUp, isNull);
        expect(spy.events.where((e) => e.$1 == 'level_up'), isEmpty);
        expect(
          spy.events
              .where((e) => e.$1 == 'level_reward_claimed')
              .single
              .$2!['coins'],
          100,
        );
        stepGame(g, 2);
        expect(g.levelUpPopup, isNull);
      },
    );

    rt(
      '§7 a stale flag after a finished claim pays nothing twice',
      () => trackGame(
        prefs: {
          'bestScore': 815,
          'playerLevel': 7,
          'claimedLevels': claimed1to6 + ['7'],
          'unclaimedLevelReward': 800,
          'coins': 100,
        },
      ),
      (g) async {
        expect(g.menu.wallet.balance, 100);
        expect(g.storage.unclaimedLevelReward, 0);
      },
    );
  });
}
