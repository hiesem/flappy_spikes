import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/score_hud.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/scoring.dart';
import 'package:flappy_spikes/run/run_context.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/screens/revive_ladder.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §13.7 points vs coins: the score becomes points with the streak
/// multiplier; coins stay as in 2.1.
void main() {
  group('§13.1 points table', () {
    test('non-perfect 1; perfect max(2, streak): 1 → 2, 2 → 2, 3 → 3, '
        '10 → 10, 12 → 12', () {
      expect(ScoringFeature.pointsFor(perfect: false, streak: 0), 1);
      expect(ScoringFeature.pointsFor(perfect: false, streak: 7), 1);
      for (final (streak, points) in [
        (1, 2),
        (2, 2),
        (3, 3),
        (10, 10),
        (12, 12),
        (60, 60),
      ]) {
        expect(ScoringFeature.pointsFor(perfect: true, streak: streak), points);
      }
    });

    test(
      'coin bonus sources pay points; hoop / perfect / win bonus do not',
      () {
        for (final s in [
          CoinSource.bullseye,
          CoinSource.train,
          CoinSource.pair,
          CoinSource.luckySpin,
          CoinSource.starTrail,
          CoinSource.jar,
          CoinSource.piggy,
          CoinSource.frenzy,
          CoinSource.switchRing,
          CoinSource.puzzle,
        ]) {
          expect(RunContext.paysPoints(s), isTrue, reason: s.name);
        }
        for (final s in [
          CoinSource.hoop,
          CoinSource.perfect,
          CoinSource.winBonus,
        ]) {
          expect(RunContext.paysPoints(s), isFalse, reason: s.name);
        }
      },
    );
  });

  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame> tester({double h = 711}) =>
      FlameTester<FlappySpikesGame>(() {
        spy = AnalyticsSpy();
        return createRunTestGame(worldHeight: h, services: spy, seed: 5);
      }, gameSize: Vector2(320, h));

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  tester().testGameWidget(
    '§13.7 a run of passes: points 2, 2, 3, …, 12 for a perfect streak; '
    'a non-perfect pass is 1 and restarts at 2; coins stay 2 / 1',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final events = <RunEvent>[];
      run.events.onAny(events.add);
      for (var i = 0; i < 12; i++) {
        run.debugPass(perfect: true);
      }
      run.debugPass(clean: true);
      run.debugPass(perfect: true);
      run.debugPass();
      final gains = [
        for (final e in events.whereType<ScoreChanged>())
          e.newScore - e.oldScore,
      ];
      expect(gains, [2, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 1, 2, 1]);
      final coins = [for (final e in events.whereType<CoinsEarned>()) e.amount];
      expect(coins, [for (var i = 0; i < 12; i++) 2, 1, 2, 1]);
      expect(run.state.score, gains.fold(0, (a, b) => a + b));
      expect(run.state.hoopsPassed, 15);
    },
  );

  tester().testGameWidget(
    '§13.7 bonuses: each coin bonus adds the same points (flag bonus); the '
    'win bonus adds 0 points; the pair gift +5',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final s = run.state;
      for (final (src, n) in [
        (CoinSource.bullseye, 3),
        (CoinSource.train, 3),
        (CoinSource.pair, 10),
        (CoinSource.luckySpin, 20),
        (CoinSource.starTrail, 5),
        (CoinSource.jar, 25),
        (CoinSource.piggy, 40),
        (CoinSource.frenzy, 5),
        (CoinSource.switchRing, 1),
      ]) {
        final p0 = s.score, c0 = s.coinsThisRun;
        run.ctx.earn(n, src);
        expect(s.coinsThisRun - c0, n, reason: src.name);
        expect(s.score - p0, n, reason: src.name);
        expect(s.timeline.flags.last, PointFlags.bonus);
        expect(s.timeline.values.last, n);
      }
      final p0 = s.score;
      run.ctx.earn(10, CoinSource.winBonus);
      expect(s.score, p0, reason: 'win / draw bonus: 0 points');
      run.ctx.addScore(5, flags: PointFlags.gift);
      expect(s.score, p0 + 5);
      expect(s.timeline.points, s.score);
    },
  );

  tester().testGameWidget(
    '§13.7 chick: doubles points and coins for a pass, a bonus and the pair '
    'gift',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final s = run.state;
      s.egg = EggState()..stage = EggStage.chick;
      var p0 = s.score, c0 = s.coinsThisRun;
      run.debugPass(perfect: true); // streak 1 → 2 points, 2 coins
      expect(s.score - p0, 4);
      expect(s.coinsThisRun - c0, 4);
      p0 = s.score;
      c0 = s.coinsThisRun;
      run.ctx.earn(3, CoinSource.bullseye);
      expect(s.coinsThisRun - c0, 6);
      expect(s.score - p0, 6);
      p0 = s.score;
      run.ctx.addScore(5, flags: PointFlags.gift);
      expect(s.score - p0, 10);
      p0 = s.score;
      run.debugPass(); // a graze: 1 point × 2
      expect(s.score - p0, 2);
      expect(s.timeline.points, s.score);
    },
  );

  tester().testGameWidget(
    '§13.7 FEVER: a centred FEVER pass at streak 2 gives 5 points',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 15,
        force: [ElementId.fever],
      );
      await flyUntil(game, (_) => firstHoopOf(game, HoopKindId.fever) != null);
      final h = firstHoopOf(game, HoopKindId.fever)!;
      await flyUntil(game, (r) {
        final b = r.birdTrackPosition();
        return b != null && h.planeX - b.x <= 40;
      });
      run.state.streak = 2;
      final p0 = run.state.score;
      expect(await passHoopAt(game, h), isTrue);
      expect(run.state.streak, 5);
      expect(run.state.score - p0, 5);
    },
  );

  tester().testGameWidget(
    '§13.7 stages and revive still count hoops: 10 perfect passes (58 '
    'points) change the colour stage once',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      for (var i = 0; i < 10; i++) {
        run.debugPass(perfect: true);
      }
      expect(run.state.score, 2 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10);
      expect(run.state.hoopsPassed, 10);
      expect(run.state.stage, 1);
      run.state.hoopsPassed = 5;
      run.state.score = 500;
      expect(ReviveLadder.eligible(run.state), isFalse, reason: 'by hoops');
    },
  );

  group('§13.2 HUD circle', () {
    setUpAll(() async {
      final l = FontLoader('LVDC Common2')
        ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
      await l.load();
    });

    tester().testGameWidget(
      '§13.7 a +25 gain rolls up over ≈ 0.3 s and ends with the pop; two '
      'gains in a row end on the right total; +1 shows at once',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final run = await startRun(game);
        final hud = game.world.children.whereType<ScoreHud>().single;
        run.ctx.addScore(1);
        expect(hud.shownScore, 1, reason: '+1 at once');
        expect(hud.counting, isFalse);
        run.ctx.addScore(25, flags: PointFlags.bonus);
        expect(hud.score, 26);
        expect(hud.shownScore, 1);
        void step(double seconds) {
          for (var t = 0.0; t < seconds - 1e-9; t += 1 / 120) {
            hud.update(1 / 120);
          }
        }

        step(.1);
        final mid = hud.shownScore;
        expect(mid, greaterThan(1));
        expect(mid, lessThan(26));
        step(.1);
        // A new gain during the count continues to the new total.
        final atGain = hud.shownScore;
        run.ctx.addScore(7, flags: PointFlags.bonus);
        expect(hud.counting, isTrue);
        expect(hud.shownScore, atGain);
        step(.3);
        expect(hud.shownScore, 33);
        expect(hud.counting, isFalse);
        expect(hud.popping, isTrue, reason: 'the pop at the end');
        step(.2);
        expect(hud.popping, isFalse);
        // A plain count: ≈ 0.3 s.
        run.ctx.addScore(25, flags: PointFlags.bonus);
        step(.28);
        expect(hud.counting, isTrue);
        step(.03);
        expect(hud.counting, isFalse);
        expect(hud.shownScore, 58);
      },
    );

    test('§13.2 font (S7-01): min(125 pt, the size at which the widest '
        'n-digit number fits the circle with the side margin)', () {
      final maxW = Config.scoreCircleSize.x - 2 * ScoreHud.sideMargin;
      double widthAt(String text, double size) {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(fontFamily: Config.scoreFont, fontSize: size),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        return tp.width;
      }

      expect(ScoreHud.fontSizeFor(1), 125);
      var last = 125.0;
      for (var n = 1; n <= 6; n++) {
        final size = ScoreHud.fontSizeFor(n);
        expect(size, lessThanOrEqualTo(last), reason: '$n digits');
        last = size;
        for (var d = 0; d <= 9; d++) {
          expect(
            widthAt('$d' * n, size),
            lessThanOrEqualTo(maxW + .5),
            reason: '$d × $n at $size pt',
          );
        }
      }
      // The PRD's ≈ 95 / ≈ 76 pt for 4 / 5 digits are upper bounds.
      expect(ScoreHud.fontSizeFor(4), lessThanOrEqualTo(95));
      expect(ScoreHud.fontSizeFor(5), lessThanOrEqualTo(76));
    });

    tester().testGameWidget(
      '§13.7 scores of 1 to 5 digits (incl. wide 888, 8888, 88888) fit the '
      'circle with the side margin; the size changes only with the digit '
      'count',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        await startRun(game);
        final hud = game.world.children.whereType<ScoreHud>().single;
        final maxW = Config.scoreCircleSize.x - 2 * ScoreHud.sideMargin;
        final sizeByDigits = <int, double>{};
        for (final v in [7, 88, 111, 888, 999, 1000, 8888, 12345, 88888]) {
          hud.setScore(0);
          hud.setScore(v);
          for (var i = 0; i < 60; i++) {
            hud.update(1 / 60);
          }
          expect(hud.shownScore, v);
          expect(hud.textWidth, lessThanOrEqualTo(maxW + .5), reason: '$v');
          expect(hud.textFontSize, lessThanOrEqualTo(125));
          final n = '$v'.length;
          expect(
            hud.textFontSize,
            sizeByDigits[n] ??= hud.textFontSize,
            reason: '$v',
          );
        }
        expect(sizeByDigits[1], 125);
        expect(sizeByDigits[5], lessThan(sizeByDigits[3]!));
      },
    );
  });

  tester().testGameWidget(
    '§13.7 results: the card shows points, YOUR REWARD coins; NEW BEST by '
    'points',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      for (var i = 0; i < 4; i++) {
        run.debugPass(perfect: true); // 2 + 2 + 3 + 4 = 11 points, 8 coins
      }
      killRun(game);
      await declineRevive(game);
      await flushAndMount(game);
      final page = game.resultsScreen!;
      expect(page.model.score, 11);
      expect(page.model.reward, 8);
      expect(page.model.newBest, isTrue);
      expect(game.storage.bestScore, 11);
      stepGame(game, 1.5);
      expect(page.you.shownScore, 11);
      expect(page.shownReward, 8);
    },
  );

  test('§13.2 results card: 5 digits still fit a versus column at the long '
      'size', () async {
    final l = FontLoader('Opificio Neue')
      ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
    await l.load();
    final tp = TextPainter(
      text: const TextSpan(
        text: '88888',
        style: TextStyle(fontFamily: 'Opificio Neue', fontSize: 36),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // A versus column is half the 292 pt card.
    expect(tp.width, lessThan(292 / 2 - 16));
  });
}
