import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/pair_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/pair/gift_tag.dart';
import 'package:flappy_spikes/run/hoops/kinds/pair/pair_kind.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/items/scoring.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3d: pairs of two powerup rings, "Gift Box" (PRD-2 §3.21, §5.20).
void main() {
  test('§3.21 gifts: +3 coins (PRD-2.3 §14.2, was +10), +5 score, FEVER sets the streak to ≥ ×5; '
      '§5.20 reward colours and words; the skipped ring fades to 60 % in '
      '0.45 s', () {
    expect(PairConfig.coins, 3);
    expect(PairConfig.score, 5);
    expect(PairConfig.feverStreak, 5);
    expect(PairConfig.skipFade, .45);
    expect(PairConfig.skipScale, .6);
    expect(PairConfig.confetti, 22);
    expect(PairConfig.tagOut, 30);
    final shield = PairConfig.style(PairReward.shield);
    expect([shield.main, shield.dark, shield.light].map((c) => c.toARGB32()), [
      0xFF2F80FF,
      0xFF1646A8,
      0xFFA9D0FF,
    ]);
    expect(PairConfig.style(PairReward.comet).main.toARGB32(), 0xFFFF7A1A);
    expect(PairConfig.style(PairReward.coins).main.toARGB32(), 0xFFFFB529);
    expect(PairConfig.style(PairReward.score).main.toARGB32(), 0xFF8E5CFF);
    expect(PairConfig.style(PairReward.fever).main.toARGB32(), 0xFFFF3B3B);
    expect(PairReward.values.map((r) => PairConfig.style(r).tag), [
      'SHIELD',
      'COMET',
      '+3 COINS',
      '+5 SCORE',
      'FEVER',
    ]);
  });

  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame> tester({double h = 711, int seed = 13}) =>
      FlameTester<FlappySpikesGame>(() {
        spy = AnalyticsSpy();
        return createRunTestGame(worldHeight: h, services: spy, seed: seed);
      }, gameSize: Vector2(320, h));

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  Future<(RunController, Hoop)> pairRun(
    FlappySpikesGame game, {
    bool Function(Hoop h)? where,
  }) async {
    final run = await startRun(
      game,
      startHoopIndex: 12,
      force: [ElementId.pair],
    );
    final h = await flyToHoop(
      game,
      HoopKindId.pair,
      ElementId.pair,
      where: where,
      maxSeconds: 120,
    );
    expect(h, isNotNull);
    return (run, h!);
  }

  for (final height in [711.0, 568.0]) {
    tester(h: height).testGameWidget(
      '§3.21 geometry at ${height.toInt()} pt: two rings at the same x, '
      'offset 230 × viewHeight / 711, the normal opening; both rings and '
      'their tags fit between the HUD bottom and the floor tooth line',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await pairRun(game);
        final o = 230 * height / 711;
        expect(h.rings, [closeTo(-o / 2, 1e-9), closeTo(o / 2, 1e-9)]);
        expect(
          h.opening,
          closeTo(run.director.openingFor(h.plan.index, ride: false), 1e-9),
        );
        final ry = RingPainter.ryFor(h.opening);
        final top = h.position.y - o / 2 - ry;
        final bottom = h.position.y + o / 2 + ry;
        expect(top, greaterThanOrEqualTo(RunConfig.hudBottom - 1e-6));
        expect(
          bottom,
          lessThanOrEqualTo(height - RunConfig.stripHeight + 1e-6),
        );
        // §5.20 the tags hang outside the pair (never in the gap).
        expect(top - PairConfig.tagOut, lessThan(top));
        expect(h.kind.usesTierLook, isFalse);
        expect(spy.events.map((e) => e.$1), contains('pair_spawned'));
      },
    );
  }

  for (final ring in [0, 1]) {
    tester().testGameWidget(
      '§3.21 flying through the ${ring == 0 ? 'top' : 'bottom'} ring takes '
      'its gift, scores like a normal hoop (+1, coins, streak) and the other '
      'ring shrinks and fades; resolves once; pair_picked',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h) = await pairRun(game);
        final events = <RunEvent>[];
        run.events.onAny(events.add);
        final take = PairHoopKind.rewardOf(h, ring);
        final skip = PairHoopKind.rewardOf(h, 1 - ring);
        final score = run.state.score;
        await glideInto(
          game,
          h,
          h.position.y + h.rings[ring],
          seconds: .5,
          until: (_) => h.resolved,
        );
        expect(h.takenRing, ring);
        expect(run.dying, isFalse);
        final passes = events.whereType<HoopPassed>().toList();
        expect(passes, hasLength(1), reason: 'one hoop, resolved once');
        // PRD-2.2 §13.1 the pass's points, the +5 gift, and the coins gift
        // (PRD-2.3 §14.2: +3) paid in points too.
        expect(
          run.state.score,
          score +
              ScoringFeature.pointsFor(
                perfect: passes.single.perfect,
                streak: run.state.streak,
              ) +
              (take == PairReward.score ? 5 : 0) +
              (take == PairReward.coins ? 3 : 0) +
              ScoringFeature.chickBonus(run.state),
        );
        final st = PairHoopKind.stateOf(h)!;
        expect(st.picked, ring);
        for (var i = 0; i < 30; i++) {
          game.update(1 / 60);
        }
        final (scale, alpha) = st.fadeOf(1 - ring);
        expect(scale, closeTo(.6, 1e-9));
        expect(alpha, 0);
        expect(st.fadeOf(ring), (1, 1));
        expect(spy.events.lastWhere((e) => e.$1 == 'pair_picked').$2, {
          'reward': take.name,
          'skipped_reward': skip.name,
          'ring': ring == 0 ? 'top' : 'bottom',
          'perfect': 1,
        });
        expect(game.storage.metElements, contains('pair'));
      },
    );
  }

  tester().testGameWidget(
    '§3.21 flying through neither ring (between them) is a miss: '
    'pair_missed, the miss flash, MistakeCause.pairMissed',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, h) = await pairRun(game);
      final events = <RunEvent>[];
      run.events.onAny(events.add);
      await glideInto(
        game,
        h,
        h.position.y,
        seconds: .6,
        until: (r) => r.dying,
      );
      expect(run.dying, isTrue);
      expect(events.whereType<HoopMissed>().single.hoop, same(h));
      expect(
        events.whereType<RunDied>().single.mistake.cause,
        MistakeCause.pairMissed,
      );
      expect(spy.events.map((e) => e.$1), contains('pair_missed'));
      expect(h.takenRing, isNull);
    },
  );

  for (final reward in PairReward.values) {
    tester().testGameWidget(
      '§3.21 the ${reward.name} gift does what it says',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 12);
        await flyUntil(game, (_) => false, maxSeconds: .5);
        final events = <RunEvent>[];
        run.events.onAny(events.add);
        final sfx = sfxLog(game);
        run.state.streak = 2;
        final score = run.state.score, coins = run.state.coinsThisRun;
        PairHoopKind.applyGift(reward, run.ctx);
        game.update(1 / 60);
        expect(sfx, contains(PairConfig.style(reward).sound.name));
        switch (reward) {
          case PairReward.shield:
            expect(run.state.shield, isTrue);
          case PairReward.comet:
            final c = events.whereType<PickupCollected>().single;
            expect(c.element, ElementId.comet);
            expect(c.pickup, isNull, reason: "WP-3a's pair-gift contract");
          case PairReward.coins:
            expect(run.state.coinsThisRun, coins + 3);
            expect(
              events.whereType<CoinsEarned>().single.source,
              CoinSource.pair,
            );
          case PairReward.score:
            expect(run.state.score, score + 5);
            final s = events.whereType<ScoreChanged>().single;
            expect(s.newScore - s.oldScore, 5);
            expect(s.flags, PointFlags.gift);
          case PairReward.fever:
            expect(run.state.streak, 5);
            expect(run.state.onFire, isTrue);
            expect(RunHud.of(run)!.banners.fever, isNotNull);
            expect(
              events.whereType<StreakChanged>().single.cause,
              StreakCause.fever,
            );
        }
      },
    );
  }

  tester().testGameWidget(
    '§3.21 FEVER gift keeps a higher streak (at least ×5)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game, startHoopIndex: 12);
      run.state.streak = 7;
      PairHoopKind.applyGift(PairReward.fever, run.ctx);
      expect(run.state.streak, 7);
      expect(run.state.onFire, isTrue);
    },
  );

  test('§5.20 the gift tag: the word + 40 pt wide', () {
    for (final r in PairReward.values) {
      expect(GiftTag.width(r), greaterThan(40));
    }
  });
}
