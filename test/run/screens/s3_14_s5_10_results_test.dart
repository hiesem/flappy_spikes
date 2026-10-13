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
    test('§5.10 progress label "185 TO SPIKE ACE" at 815 (HAWK)', () {
      final b = LevelBar.at(815);
      expect(b.level, 7);
      expect(b.label, '185 TO SPIKE ACE');
      expect(b.fraction, closeTo(15 / 200, 1e-9));
      expect(rankText(7), 'HAWK · LV 7');
    });

    test('§5.10 unranked: "UNRANKED", bar toward EGG', () {
      final b = LevelBar.at(7);
      expect(b.level, 0);
      expect(b.label, '3 TO EGG');
      expect(b.fraction, closeTo(.7, 1e-9));
      expect(rankText(0), 'UNRANKED');
    });

    test('§5.10 "MAX LEVEL" at level 10, thousands with a space', () {
      expect(LevelBar.at(5120).label, 'MAX LEVEL');
      expect(LevelBar.at(5120).fraction, 1);
      expect(LevelBar.at(1500).label, '500 TO PHOENIX');
      expect(LevelBar.at(2000).label, '3 000 TO LEGEND');
    });

    test('§3.14 the model reads the level from the best before / after', () {
      const m = ResultsModel(
        score: 815,
        bestBefore: 760,
        bestAfter: 815,
        reward: 65,
        levelReward: 800,
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
      );
      expect(lose.newBest, isFalse);
      expect(lose.levelUp, isFalse);
      expect(lose.hasClaim, isFalse);
    });
  });

  group('§5.10 results page', () {
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

    rt(
      '§3.14 solo: the page replaces the game-over panel, no versus parts, '
      'no ad, NEXT goes home',
      () => createRunTestGame(prefs: {'bestScore': 900, 'claimedLevels': claimed1to6 + ['7', '8']}),
      (g) async {
        final page = await endWith(g, score: 12, coins: 14);
        expect(page.model.reward, 14);
        expect(page.you.centreX, ResultsConfig.soloColumnX);
        expect(page.content.children.whereType<ResultsPlayerColumn>(), hasLength(1));
        expect(page.canContinue, isFalse);
        stepGame(g, .3);
        expect(page.canContinue, isTrue);
        // Count-ups end at 1.15 s.
        stepGame(g, 1);
        expect(page.shownReward, 14);
        expect(page.you.shownScore, 12);
        expect(page.newBestSticker, isNull, reason: 'no new best');
        expect(page.bar.fraction, closeTo(LevelBar.at(900).fraction, 1e-9),
            reason: 'no new best: the bar does not move');
        // Strips over the page.
        expect(g.groundStripPriority, greaterThan(ResultsScreen.priorityOnTop));
        page.nextButton.onPressed();
        await flushAndMount(g);
        expect(g.state, GameState.start);
        expect(g.resultsScreen, isNull);
        expect(g.groundStripPriority, lessThan(0));
        expect(AdPlacement.values.map((p) => p.name), isNot(contains('doubleCoins')));
      },
    );

    rt(
      '§3.14 YOUR REWARD includes puzzle coins and the win / draw bonus, '
      'not the balloon bonus',
      () => createRunTestGame(prefs: {'bestScore': 900, 'claimedLevels': claimed1to6 + ['7', '8']}),
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
      'bar fills at 1.65 s (lv_bar), no CLAIM',
      () => createRunTestGame(prefs: {'bestScore': 230, 'claimedLevels': ['1', '2', '3', '4']}),
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
        expect(sfx, isNot(contains('lvBar')));
        stepGame(g, .45);
        expect(sfx, contains('lvBar'));
        stepGame(g, 1.3);
        expect(page.bar.fraction, closeTo(LevelBar.at(262).fraction, 1e-6));
        expect(page.barLabel.text, LevelBar.at(262).label);
        expect(page.claimShowing, isFalse);
        expect(sfx, isNot(contains('lvUp')));
        expect(g.storage.unclaimedLevelReward, 0);
      },
    );

    rt(
      '§3.14 level up (one level): celebration, CLAIM credits wallet.add '
      '(level_reward) at the claim, the reward counts up',
      () => createRunTestGame(
        prefs: {'bestScore': 760, 'claimedLevels': claimed1to6},
        services: AnalyticsSpy(),
      ),
      (g) async {
        final spy = g.services as AnalyticsSpy;
        final sfx = sfxLog(g);
        final page = await endWith(g, score: 815, coins: 65);
        // Owed from the run's end on (an app kill never loses it).
        expect(g.storage.unclaimedLevelReward, 800);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('unclaimedLevelReward'), 800);
        expect(page.model.levelReward, 800);
        // 0 s: the level before this run.
        expect(page.stage.level, 6);
        expect(page.rank.text, 'FALCON · LV 6');
        // Bar to 100 % (0.9 s from 1.65 s), shake, then the pop at 2.81 s.
        stepGame(g, 2.85);
        await flushAndMount(g);
        expect(page.stage.level, 7);
        expect(page.rank.text, 'HAWK · LV 7');
        expect(page.stage.rays, 1);
        expect(sfx, contains('lvUp'));
        expect(sfx, isNot(contains('lvUpBig')));
        expect(page.fx.bursts.single.count, 60 + 40,
            reason: 'lv 5-8: 100 confetti pieces');
        stepGame(g, .6);
        expect(page.claimShowing, isFalse);
        stepGame(g, .35);
        expect(page.fx.fireworks.bursts, 3, reason: 'three fireworks');
        expect(page.claimShowing, isTrue, reason: 'CLAIM 0.9 s after LEVEL UP');
        final before = g.menu.wallet.balance;
        stepGame(g, .4);
        page.claimButton.button.onPressed();
        await flushAndMount(g);
        expect(g.menu.wallet.balance, before + 800, reason: 'credited at the claim');
        expect(g.storage.claimedLevels, containsAll([7]));
        expect(g.storage.unclaimedLevelReward, 0);
        expect(spy.events.where((e) => e.$1 == 'level_up').single.$2, {
          'from': 6,
          'to': 7,
          'reward': 800,
          'claim': 'tap',
        });
        expect(
          spy.events.where((e) => e.$1 == 'coins_earned').last.$2,
          {'amount': 800, 'source': 'level_reward'},
        );
        expect(sfx, contains('lvClaim'));
        stepGame(g, 1.5);
        await flushAndMount(g);
        expect(sfx.where((s) => s == 'bnCoin'), hasLength(12));
        expect(page.shownReward, 865);
        expect(page.stage.rays, 0);
        stepGame(g, 1);
        expect(page.barLabel.text, '185 TO SPIKE ACE');
        expect(page.bar.fraction, closeTo(15 / 200, 1e-6));
        // A second claim pays nothing.
        expect(await claimLevelRewards(g, 'tap'), 0);
        expect(g.menu.wallet.balance, before + 800);
      },
    );

    rt(
      '§3.14 several levels in one run: one celebration for the highest, '
      'rewards added together',
      () => createRunTestGame(prefs: {'bestScore': 40}),
      (g) async {
        final page = await endWith(g, score: 230);
        // EGG 50 + CHICK 100 + FLEDGLING 150 + FLAPPER 250.
        expect(page.model.levelReward, 550);
        expect(g.storage.unclaimedLevelReward, 550);
        stepGame(g, 2.9);
        await flushAndMount(g);
        expect(page.stage.level, 4);
        expect(page.rank.text, 'FLAPPER · LV 4');
        expect(page.fx.bursts, hasLength(1), reason: 'one celebration');
        expect(page.fx.bursts.single.count, 60);
        stepGame(g, 1.4);
        expect(page.claimShowing, isTrue);
        final before = g.menu.wallet.balance;
        page.claimButton.button.onPressed();
        await flushAndMount(g);
        expect(g.menu.wallet.balance, before + 550);
        expect(g.storage.claimedLevels, {1, 2, 3, 4});
      },
    );

    rt(
      '§5.10 lv 9-10: lv_up_big and a second wave (2 confetti + 2 rockets)',
      () => createRunTestGame(
        prefs: {
          'bestScore': 4600,
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
        expect(page.rank.text, 'LEGEND · LV 10');
      },
    );

    rt(
      '§3.14 NEXT while CLAIM shows claims first (same animation), then home',
      () => createRunTestGame(
        prefs: {'bestScore': 760, 'claimedLevels': claimed1to6},
        services: AnalyticsSpy(),
      ),
      (g) async {
        final spy = g.services as AnalyticsSpy;
        final sfx = sfxLog(g);
        final page = await endWith(g, score: 815, coins: 65);
        stepGame(g, 4);
        expect(page.claimShowing, isTrue);
        final before = g.menu.wallet.balance;
        page.nextButton.onPressed();
        await flushAndMount(g);
        expect(g.menu.wallet.balance, before + 800);
        expect(spy.events.where((e) => e.$1 == 'level_up').single.$2!['claim'],
            'auto_next');
        expect(g.state, GameState.results, reason: 'the claim plays first');
        expect(sfx, contains('lvClaim'));
        stepGame(g, 1.3);
        expect(g.state, GameState.results);
        expect(page.shownReward, 865);
        stepGame(g, .4);
        await flushAndMount(g);
        expect(g.state, GameState.start);
        expect(g.levelUpPopup, isNull, reason: 'no home LEVEL UP popup');
        expect(g.menu.levels.pendingLevelUp, isNull);
      },
    );

    rt(
      '§3.14 NEXT before CLAIM came up still pays the reward (never lost)',
      () => createRunTestGame(prefs: {'bestScore': 760, 'claimedLevels': claimed1to6}),
      (g) async {
        final page = await endWith(g, score: 815);
        stepGame(g, .5);
        final before = g.menu.wallet.balance;
        g.onKeyEvent(KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ), {});
        await flushAndMount(g);
        expect(page.leaving, isTrue);
        expect(g.state, GameState.start);
        expect(g.menu.wallet.balance, before + 800);
        expect(g.storage.unclaimedLevelReward, 0);
      },
    );

    rt(
      '§5.10 the kept share and leaderboard buttons',
      () => createRunTestGame(prefs: {'bestScore': 900, 'claimedLevels': claimed1to6 + ['7', '8']}),
      (g) async {
        ShareCardData? shared;
        g.onShareScore = (s) => shared = s;
        final page = await endWith(g, score: 21);
        stepGame(g, .4);
        page.shareButton.onPressed();
        await flushAndMount(g); // PRD-2.3 §2.2 the nickname is made first
        expect(shared?.score, 21);
        expect(shared?.best, 900);
        page.leaderboardButton.onPressed(); // no-op services: must not throw
      },
    );
  });

  group('§3.14 / §7 unclaimedLevelReward', () {
    rt(
      '§7 an unclaimed level reward is credited at the next app start '
      '(no animation, no popup)',
      () => createRunTestGame(
        prefs: {
          'bestScore': 815,
          'claimedLevels': claimed1to6,
          'unclaimedLevelReward': 800,
          'coins': 100,
        },
        services: AnalyticsSpy(),
      ),
      (g) async {
        final spy = g.services as AnalyticsSpy;
        expect(g.menu.wallet.balance, 900);
        expect(g.storage.unclaimedLevelReward, 0);
        expect(g.storage.claimedLevels, contains(7));
        expect(g.menu.levels.pendingLevelUp, isNull);
        expect(spy.events.where((e) => e.$1 == 'level_up').single.$2, {
          'from': 6,
          'to': 7,
          'reward': 800,
          'claim': 'app_start',
        });
        stepGame(g, 2);
        expect(g.levelUpPopup, isNull);
      },
    );

    rt(
      '§7 a stale flag after a finished claim pays nothing twice',
      () => createRunTestGame(
        prefs: {
          'bestScore': 815,
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
