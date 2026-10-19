// PRD-2.3.1 §15: a pass through the FEVER ring without a rim touch is always
// perfect, whatever the perfect band (`point_perfect_band`); every other
// hoop keeps the band; a rim touch on the FEVER ring is unchanged.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/streak_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  void useTuning(Map<String, String> extra) {
    TuningValues.current = TuningValues.resolve({
      'ui_unlock_best': '0',
      ...extra,
    });
  }

  tearDown(() => useTuning(const {}));

  late AnalyticsSpy spy;
  final tester = FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, services: spy, seed: 6);
  }, gameSize: Vector2(320, 711));

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    useTuning({'point_perfect_band': '[[0,8]]'});
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  List<Map<String, Object>?> paramsOf(String name) =>
      spy.events.where((e) => e.$1 == name).map((e) => e.$2).toList();

  /// A run with a FEVER ring forced; flies until it is the next hoop, just
  /// ahead of the bird.
  Future<(RunController, Hoop, List<RunEvent>)> toFever(
    FlappySpikesGame g,
  ) async {
    final run = await startRun(g, startHoopIndex: 15, force: [ElementId.fever]);
    expect(PerfectBandConfig.bandAt(20), 8);
    expect(
      await flyUntil(g, (_) => firstHoopOf(g, HoopKindId.fever) != null),
      isTrue,
    );
    final h = firstHoopOf(g, HoopKindId.fever)!;
    expect(
      await flyUntil(g, (r) {
        final b = r.birdTrackPosition();
        return b != null && h.planeX - b.x <= 60;
      }),
      isTrue,
    );
    expect(h.resolved, isFalse);
    final events = <RunEvent>[];
    run.events.onAny(events.add);
    return (run, h, events);
  }

  /// Passes [h] [dy] off centre; returns its pass event.
  Future<HoopPassed> passAt(FlappySpikesGame g, Hoop h, double dy) async {
    HoopPassed? got;
    g.run!.events.on<HoopPassed>((e) {
      if (identical(e.hoop, h)) got = e;
    });
    expect(await passHoopAt(g, h, dy: dy), isTrue);
    expect(got, isNotNull);
    return got!;
  }

  tester.testGameWidget(
    '§15.3 a rim-free FEVER pass 20 pt off centre with band [[0,8]]: '
    'perfect, the fire lights, streak ≥ 5, 2 coins, +2 points (§15.1); the same offset through '
    'a normal hoop is not perfect',
    setUp: boot,
    verify: (g, _) async {
      final (run, h, events) = await toFever(g);
      run.debugPass(perfect: false); // a fresh FEVER: streak 0
      expect(run.state.streak, 0);
      final before = run.state.streak;
      final perfects = run.state.perfectPasses;
      final score = run.state.score;
      final e = await passAt(g, h, 20);
      // P1-04: points max(2, streak) before the FEVER boost: +2, not +5.
      expect(run.state.score - score, 2);
      expect(run.state.pointStreak, isNull);
      expect(h.touched, isFalse);
      expect(h.passOffset!.abs(), greaterThan(8));
      expect(e.perfect, isTrue);
      expect(e.clean, isFalse);
      expect(run.state.perfectPasses, perfects + 1);
      expect(run.state.onFire, isTrue);
      expect(run.state.fever, isTrue);
      expect(
        run.state.streak,
        StreakConfig.feverMinStreak > before + 1
            ? StreakConfig.feverMinStreak
            : before + 1,
      );
      expect(run.state.streak, greaterThanOrEqualTo(5));
      final coins = events
          .whereType<CoinsEarned>()
          .where((c) => c.source == CoinSource.perfect)
          .toList();
      expect(coins.single.amount, 2);
      expect(RunHud.of(run)!.banners.fever, isNotNull);
      expect(paramsOf('fever_ring_passed').single!['perfect'], 1);

      // The same offset through a normal hoop: not perfect (the band holds).
      Hoop? n;
      await flyUntil(g, (r) {
        final b = r.birdTrackPosition();
        for (final x in hoopsOf(g)) {
          if (x.plan.kind != HoopKindId.normal || x.resolved) continue;
          if (x.tilt != 0 || x.plan.ringOffsets.length != 1) continue;
          if (b != null && x.planeX < b.x + 120) continue;
          n = x;
          return true;
        }
        return false;
      });
      expect(n, isNotNull);
      final e2 = await passAt(g, n!, 20);
      expect(n!.touched, isFalse);
      expect(n!.passOffset!.abs(), greaterThan(8));
      expect(e2.perfect, isFalse);
      expect(e2.clean, isTrue);
    },
  );

  tester.testGameWidget(
    '§15.3 a burning bird (streak 6) passes FEVER outside the band: it '
    'keeps burning and the streak becomes 7',
    setUp: boot,
    verify: (g, _) async {
      final (run, h, _) = await toFever(g);
      run.debugPass(); // a graze: streak 0, no fire
      for (var i = 0; i < 6; i++) {
        run.debugPass(perfect: true);
      }
      expect(run.state.streak, 6);
      expect(run.state.onFire, isTrue);
      final score = run.state.score;
      final e = await passAt(g, h, 20);
      // P1-04: scored like an ordinary perfect pass at streak 6 (→ 7).
      expect(run.state.score - score, 7);
      expect(h.touched, isFalse);
      expect(h.passOffset!.abs(), greaterThan(8));
      expect(e.perfect, isTrue);
      expect(run.state.onFire, isTrue);
      expect(run.state.fever, isTrue);
      expect(run.state.streak, 7);
      expect(paramsOf('fever_ring_passed').single, {
        'perfect': 1,
        'streak_before': 6,
        'streak_after': 7,
      });
      expect(paramsOf('fever_fire_out'), isEmpty);
    },
  );

  tester.testGameWidget(
    '§15.3 a FEVER pass with a rim touch: no fire, the streak resets '
    '(unchanged)',
    setUp: boot,
    verify: (g, _) async {
      final (run, h, _) = await toFever(g);
      h.touched = true;
      final e = await passAt(g, h, 0);
      expect(e.perfect, isFalse);
      expect(run.state.onFire, isFalse);
      expect(run.state.streak, 0);
      expect(RunHud.of(run)!.banners.fever, isNull);
      expect(paramsOf('fever_ring_passed').single!['perfect'], 0);
    },
  );
}
