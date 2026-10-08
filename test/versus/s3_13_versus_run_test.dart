import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/run/items/versus_recorder.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// An opponent whose points land at [times] (s of their runClock) and who
/// dies [end] s after the last point.
OpponentRun opponentAt(
  List<double> times, {
  double end = 1,
  String name = 'Molly',
  int best = 31,
}) {
  final t = RunTimeline();
  for (final s in times) {
    t.addPoint(s);
  }
  t.end((times.isEmpty ? 0 : times.last) + end);
  return OpponentRun(
    uid: 'u-$name',
    name: name,
    score: times.length,
    best: best,
    level: 3,
    timeline: t,
    runId: 'run-$name',
  );
}

Future<void> boot(FlappySpikesGame g) async {
  await g.ready();
  await preloadImages(g);
}

/// Keeps the bird safe mid-screen while time passes (no hoop is reached in
/// these short holds; the score comes from `debugPass`).
void hold(FlappySpikesGame g, double seconds) {
  for (var t = 0.0; t < seconds - 1e-9; t += 1 / 60) {
    if (g.state == GameState.playing) {
      g.runBird!.setFlight(y: g.viewHeight / 2, vy: 0);
    }
    g.update(1 / 60);
  }
}

void vt(
  String name,
  VersusService Function() versus,
  Future<void> Function(FlappySpikesGame g, AnalyticsSpy spy) body, {
  double h = 711,
}) {
  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: h, services: spy, versus: versus());
  }, gameSize: Vector2(320, h)).testGameWidget(
    name,
    setUp: (g, _) => boot(g),
    verify: (g, _) => body(g, spy),
  );
}

/// Ends the run with [score] points (≤ 5 hoops: no revive offer) and lets
/// the results page mount.
Future<void> finishWith(FlappySpikesGame g, RunController run, int score) async {
  for (var i = 0; i < score; i++) {
    run.debugPass(perfect: false);
  }
  run.state.invulnerable = 0;
  killRun(g);
  await flushAndMount(g);
  for (var i = 0; i < 30 && g.resultsScreen == null; i++) {
    g.update(1 / 60);
    await flushAndMount(g);
  }
}

/// WP-5b PRD-2 §3.13 / §5.7 / §5.8 / §5.10 and the §7 versus test list:
/// solo start, the VS intro gate, the timeline on runClock (pause, revive
/// offer, phoenix, Hourglass), the opponent going out, WIN / LOSE / DRAW
/// and the +10 / +5 bonus in YOUR REWARD.
void main() {
  setUp(E2EHooks.reset);

  group('§3.13 duel rules (pure)', () {
    test('§3.13 WIN higher, LOSE lower, DRAW equal; +10 / +5 / 0', () {
      expect(duelOf(5, 3), DuelResult.win);
      expect(duelOf(2, 3), DuelResult.lose);
      expect(duelOf(3, 3), DuelResult.draw);
      expect(bonusFor(DuelResult.win), 10);
      expect(bonusFor(DuelResult.draw), 5);
      expect(bonusFor(DuelResult.lose), 0);
      expect(VersusConfig.winBonus, 10);
      expect(VersusConfig.drawBonus, 5);
      expect(VersusConfig.dailyUploads, 3);
      expect(VersusConfig.minUploadScore, 3);
    });
  });

  vt(
    '§3.13 solo start: no prefetched opponent → START goes straight into a '
    'solo run (no intro, no bar); versus_skipped {reason: no_opponent}; the '
    'results page has no header or opponent column',
    () => FakeVersusService(),
    (g, spy) async {
      g.onScreenTap();
      expect(g.state, GameState.playing, reason: 'no intro, no waiting');
      expect(g.versusIntro, isNull);
      await flushAndMount(g);
      final run = g.run!;
      expect(run.setup.opponent, isNull);
      expect(g.runHud!.versus, isNull);
      expect(
        analyticsLog(spy).where((e) => e.$1 == 'versus_skipped').single.$2,
        {'reason': 'no_opponent'},
      );
      await finishWith(g, run, 4);
      final page = g.resultsScreen!;
      expect(page.header, isNull);
      expect(page.them, isNull);
      expect(page.duel, isNull);
      expect(run.summarize().duel, isNull);
      expect(run.state.timeline.points, 4);
    },
  );

  vt(
    '§5.8 / §3.13 a prefetched opponent: START plays the VS intro (taps do '
    'nothing), the reel lands on the real opponent and their level, then the '
    'run starts with them; versus_matched',
    () => FakeVersusService(pool: [opponentAt([1, 2, 3], name: 'Pond')]),
    (g, spy) async {
      final sfx = sfxLog(g);
      g.onScreenTap();
      expect(g.state, GameState.versusIntro);
      await flushAndMount(g);
      final intro = g.versusIntro!;
      expect(intro.opponent.name, 'Pond');
      expect(
        analyticsLog(spy).where((e) => e.$1 == 'versus_matched'),
        hasLength(1),
      );
      // Not skippable: taps do nothing.
      for (var i = 0; i < 120; i++) {
        if (i % 20 == 0) {
          g.onScreenTap();
          g.onPlayfieldTap();
        }
        g.update(1 / 60);
      }
      expect(g.state, GameState.versusIntro);
      expect(g.run, isNull);
      // Before the lock the reel spins filler names.
      expect(intro.locked, isFalse);
      while (!intro.locked) {
        g.update(1 / 60);
      }
      g.update(1 / 60);
      expect(intro.reelName, 'Pond');
      expect(intro.oppPlate.name, 'Pond');
      expect(intro.oppPlate.emblem.level, 3);
      expect(intro.youPlate.emblem.level, g.menu.levels.level);
      expect(intro.endAt, closeTo(7.34, .1));
      expect(
        sfx,
        containsAll([
          'vsWhoosh', 'vsTick', 'vsChime', 'vsRocket', 'vsBoing', 'flap', //
        ]),
      );
      await finishVersusIntro(g);
      expect(g.state, GameState.playing);
      expect(g.versusIntro, isNull);
      expect(sfx, containsAll(['vsThud', 'vsPop']));
      final run = g.run!;
      expect(run.setup.opponent!.name, 'Pond');
      expect(g.runHud!.versus, isNotNull);
      expect(g.runHud!.versus!.them.left, 170);
    },
  );

  vt(
    '§5.8 E2E: skipVersusIntroWait plays the intro to its end at once',
    () => FakeVersusService(pool: [opponentAt([1, 2, 3])]),
    (g, spy) async {
      E2EHooks.skipVersusIntroWait = true;
      g.onScreenTap();
      await flushAndMount(g);
      await flushAndMount(g);
      expect(g.state, GameState.playing);
      expect(g.run!.setup.opponent, isNotNull);
    },
  );

  vt(
    '§3.13 timeline replay on runClock: the opponent score follows my '
    'runClock — stops in pause, slows with the Hourglass — and the box goes '
    'out at the end of their timeline (score stays final)',
    () => FakeVersusService(
      pool: [opponentAt([1, 2, 3, 4], end: 1)],
    ),
    (g, spy) async {
      final run = await startRun(g);
      final bar = g.runHud!.versus!;
      expect(bar.theirScore, 0);
      hold(g, 1.05);
      expect(bar.theirScore, 1);
      // Pause: runClock stops, so does their score.
      g.pause();
      expect(g.state, GameState.paused);
      final clock = run.state.runClock;
      for (var i = 0; i < 180; i++) {
        g.update(1 / 60);
      }
      expect(run.state.runClock, clock);
      expect(bar.theirScore, 1);
      g.resume();
      // Hourglass: the world (and runClock) at 0.45.
      run.state.timeScale = .45;
      hold(g, 1);
      expect(run.state.runClock - clock, closeTo(.45, .03));
      expect(bar.theirScore, 1, reason: 'their 2nd point is at 2.0 s');
      run.state.timeScale = 1;
      hold(g, 1);
      expect(bar.theirScore, 2);
      expect(bar.out, isFalse);
      hold(g, 2.1);
      expect(bar.theirScore, 4);
      expect(bar.out, isFalse);
      hold(g, 1);
      expect(bar.out, isTrue, reason: 'their run ended 1 s after the last point');
      expect(bar.theirScore, 4);
    },
  );

  vt(
    '§3.13 the replay holds through the revive offer and the phoenix '
    '(runClock stops) and goes on after the revive',
    () => FakeVersusService(
      pool: [opponentAt([for (var i = 1; i <= 20; i++) i * 1.0])],
    ),
    (g, spy) async {
      final run = await startRun(g);
      final bar = g.runHud!.versus!;
      hold(g, 2.05);
      expect(bar.theirScore, 2);
      for (var i = 0; i < 6; i++) {
        run.debugPass(perfect: true);
      }
      run.state.invulnerable = 0;
      killRun(g);
      await flushAndMount(g);
      expect(g.state, GameState.reviving);
      final clock = run.state.runClock;
      final screen = g.reviveScreen!;
      hold(g, .5);
      screen.tapHeart(); // the ad step (fake ad succeeds)
      for (var i = 0; i < 400 && g.state == GameState.reviving; i++) {
        g.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(g);
        expect(run.state.runClock, clock);
        expect(bar.theirScore, 2);
      }
      expect(g.state, GameState.playing);
      hold(g, 1);
      expect(bar.theirScore, 3);
    },
  );

  vt(
    '§3.13 the timeline records every point on runClock: one entry per '
    'point, a pair "+5" as gift-flagged points at the same time, ride / '
    'train flags; the point count equals the score',
    () => FakeVersusService(),
    (g, spy) async {
      final run = await startRun(g);
      hold(g, .3);
      run.debugPass(perfect: true);
      hold(g, .95);
      run.ctx.addScore(4, flags: PointFlags.gift);
      hold(g, .3);
      run.ctx.addScore(1, flags: PointFlags.ride);
      final tl = run.state.timeline;
      expect(tl.points, run.state.score);
      expect(tl.points, 6);
      expect(tl.flags, [0, 4, 4, 4, 4, 1]);
      expect(tl.cs[1], greaterThan(90));
      expect(tl.cs.sublist(2, 5), everyElement(0));
      expect(tl.scoreAt(run.state.runClock), 6);
    },
  );

  for (final (mine, theirs, result, bonus) in [
    (5, 3, DuelResult.win, 10),
    (2, 3, DuelResult.lose, 0),
    (3, 3, DuelResult.draw, 5),
  ]) {
    vt(
      '§3.13 / §5.10 ${result.name.toUpperCase()}: $mine vs $theirs → '
      '+$bonus (win_bonus) credited before the summary, so YOUR REWARD '
      'includes it; versus_result; the header and opponent column',
      () => FakeVersusService(
        pool: [opponentAt([for (var i = 1; i <= theirs; i++) i * 1.0])],
      ),
      (g, spy) async {
        final run = await startRun(g);
        final wallet0 = g.menu.wallet.balance;
        await finishWith(g, run, mine);
        final runCoins = mine; // 1 per rim pass (debugPass non-perfect)
        final s = run.summarize();
        expect(s.duel, result);
        expect(run.state.duelBonus, bonus);
        expect(s.coins, runCoins + bonus);
        expect(g.menu.wallet.balance, wallet0 + runCoins + bonus);
        final r = analyticsLog(spy).where((e) => e.$1 == 'versus_result').single;
        expect(r.$2, {'result': result.name, 'score': mine, 'opp_score': theirs});
        if (bonus > 0) {
          expect(
            analyticsLog(spy).any(
              (e) =>
                  e.$1 == 'coins_earned' &&
                  e.$2?['source'] == CoinSource.winBonus.analyticsName,
            ),
            isTrue,
          );
        }
        final page = g.resultsScreen!;
        expect(page.model.reward, runCoins + bonus);
        expect(page.duel, result);
        final header = page.header!;
        expect(
          header.text,
          switch (result) {
            DuelResult.win => 'YOU WIN!',
            DuelResult.lose => 'YOU LOSE',
            DuelResult.draw => 'DRAW',
          },
        );
        expect(header.pink, result == DuelResult.win);
        final them = page.them!;
        expect(them.name, 'Molly');
        expect(them.winner, result == DuelResult.lose);
        expect(page.you.winner, result == DuelResult.win);
        expect(them.lower, result == DuelResult.win);
        expect(page.you.lower, result == DuelResult.lose);
        // Both scores count up.
        for (var i = 0; i < 90; i++) {
          g.update(1 / 60);
        }
        expect(page.you.shownScore, mine);
        expect(them.shownScore, theirs);
        expect(page.shownReward, runCoins + bonus);
      },
    );
  }
}
