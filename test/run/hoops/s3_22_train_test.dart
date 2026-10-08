import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/special_hoops_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/train.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3c: the Ring Train (PRD-2 §3.22, §5.21).
void main() {
  late AnalyticsSpy spy;
  final tester = FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, services: spy, seed: 9);
  }, gameSize: Vector2(320, 711));

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  Future<(RunController, List<Hoop>, List<RunEvent>)> toTrain(
    FlappySpikesGame game,
  ) async {
    final run = await startRun(
      game,
      startHoopIndex: 8,
      force: [ElementId.train],
    );
    final events = <RunEvent>[];
    run.events.onAny(events.add);
    expect(
      await flyUntil(game, (_) => firstHoopOf(game, HoopKindId.train) != null),
      isTrue,
    );
    final train = hoopsOf(
      game,
    ).where((h) => h.plan.kind == HoopKindId.train).toList();
    return (run, train, events);
  }

  tester.testGameWidget(
    '§3.22 three rings 56 pt apart, ±16 pt per ring in one direction, one '
    'slot: the next hoop follows the usual spacing after the third ring',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, train, _) = await toTrain(game);
      expect(train, hasLength(3));
      expect(train.map((h) => h.plan.index).toSet(), hasLength(1));
      expect(train.map((h) => TrainHoopKind.ringOf(h.plan)), [0, 1, 2]);
      final dir = (train[0].plan.extra! as TrainSpec).dir;
      for (var k = 1; k < 3; k++) {
        expect(train[k].planeX - train[k - 1].planeX, RunConfig.trainDx);
        expect(
          train[k].position.y - train[k - 1].position.y,
          closeTo(dir * RunConfig.trainDy, 1e-9),
        );
        expect(train[k].opening, train[0].opening);
      }
      // One slot: the director counted it once; the next slot is 310 pt
      // after the third ring.
      await flyUntil(
        game,
        (r) => r.spawner.slotLog.any((p) => p.index == train[0].plan.index + 1),
      );
      final next = run.spawner.slotLog.firstWhere(
        (p) => p.index == train[0].plan.index + 1,
      );
      expect(next.trackX - train[2].planeX, closeTo(RunConfig.spacing, 1e-9));
      expect(
        TrainGroup.forSpec(train[0].plan.extra! as TrainSpec).hoops,
        train,
      );
    },
  );

  tester.testGameWidget(
    '§3.22 / §5.21 each ring is a normal hoop (+1 score, coins, streak); '
    'notes C5 / E5 / G5, passed rings gold; all three → +3 coins (train), '
    'TRAIN ×3, the rising finish, train_completed; points flagged train',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, train, events) = await toTrain(game);
      final sfx = sfxLog(game);
      final score0 = run.state.score;
      final streak0 = run.state.streak;
      // §3.22 / Q61 a rim touch still counts for the combo.
      train[1].touched = true;
      for (final h in train) {
        expect(await passHoopAt(game, h), isTrue);
        expect(h.takenRing, 0);
      }
      final g = TrainHoopKind.groupOf(train[0])!;
      expect(g.passedRings, {0, 1, 2});
      expect(g.completed, isTrue);
      expect(run.state.score, score0 + 3);
      final passes = events.whereType<HoopPassed>().where(
        (e) => e.hoop?.plan.kind == HoopKindId.train,
      );
      expect(passes.map((e) => e.perfect), [true, false, true]);
      // The graze on ring 2 broke the streak as on any hoop.
      expect(run.state.streak, 1);
      expect(streak0, 0);
      expect(sfx.where((s) => s.startsWith('train')).toList(), [
        'trainNote1',
        'trainNote2',
        'trainNote3',
        'trainFinish',
      ]);
      final combo = events.whereType<CoinsEarned>().where(
        (e) => e.source == CoinSource.train,
      );
      expect(combo.single.amount, TrainConfig.comboCoins);
      final banner = RunHud.of(run)!.banners.current! as ElementBanner;
      expect(banner.text, 'TRAIN ×3');
      expect(banner.subtitle, 'all three rings · +3 coins');
      expect(spy.events.map((e) => e.$1), contains('train_completed'));
      final flags = events
          .whereType<ScoreChanged>()
          .toList()
          .reversed
          .take(3)
          .map((e) => e.flags);
      expect(flags, everyElement(PointFlags.train));
      expect(game.storage.metElements, contains('train'));
    },
  );

  tester.testGameWidget(
    '§3.22 a miss (saved by an extra life) breaks the combo',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, train, events) = await toTrain(game);
      run.state.extraLife = true;
      expect(await passHoopAt(game, train[0]), isTrue);
      // Fly well outside ring 2: a miss, absorbed by the extra life.
      expect(await passHoopAt(game, train[1], dy: 95), isTrue);
      expect(train[1].takenRing, isNull);
      expect(events.whereType<MistakeSaved>(), hasLength(1));
      expect(await passHoopAt(game, train[2]), isTrue);
      expect(train[2].takenRing, 0);
      final g = TrainHoopKind.groupOf(train[0])!;
      expect(g.broken, isTrue);
      expect(g.completed, isFalse);
      expect(
        events.whereType<CoinsEarned>().where(
          (e) => e.source == CoinSource.train,
        ),
        isEmpty,
      );
      expect(spy.events.map((e) => e.$1), isNot(contains('train_completed')));
    },
  );

  test('§5.21 track fg 50 % 2.5 pt 6/6 moving at 40 pt/s, 34 pt overhang; '
      'dots 6.5 pt 20 pt above; gold #FFB529', () {
    expect(TrainConfig.trackAlpha, .5);
    expect(TrainConfig.trackOverhang, 34);
    expect(TrainConfig.trackSpeed, 40);
    expect(TrainConfig.dotSize, 6.5);
    expect(TrainConfig.dotAbove, 20);
    expect(TrainConfig.gold.toARGB32(), 0xFFFFB529);
    expect(RunConfig.trainDx, 56);
    expect(RunConfig.trainDy, 16);
  });
}
