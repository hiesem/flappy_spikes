import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../p231/tuning_23.dart';

/// PRD-2.3 §14.3 (rewrites the PRD-2.2 §11.5 perfect-zone tests): perfect
/// = a pass with **no rim touch**, anywhere in the gap (Flappy Dunk's
/// swish). The centre zone is retired; the Bullseye keeps its own ±12 pt
/// band; rides stay always perfect.
void main() {
  late AnalyticsSpy spy;
  final tester = FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, services: spy, seed: 5);
  }, gameSize: Vector2(320, 711));

  Future<void> prepare(FlappySpikesGame g) async {
    // This file pins the 2.3 rule (no perfect band: any rim-free pass is
    // perfect). PRD-2.3.1 §0 made the live band (±18 → ±8) the default;
    // the band has its own tests (test/p23/s14_perfect_band_test.dart).
    useTuning(tuning23(['point_perfect_band']));
    addTearDown(resetTuning);
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  /// The first unresolved hoop ahead of the bird (normal hoops from the
  /// start of a fresh run).
  Future<(RunController, Hoop, List<RunEvent>)> firstHoop(
    FlappySpikesGame g,
  ) async {
    final run = await startRun(g);
    final events = <RunEvent>[];
    run.events.onAny(events.add);
    await flyUntil(g, (r) => r.spawner.nextHoopAhead() != null);
    return (run, run.spawner.nextHoopAhead()!, events);
  }

  // PRD-2.3 §14.3 every rim-free pass is perfect, centred or not (the
  // offsets reach ±30 pt of the 118 pt hoop 0 without touching a rim).
  for (final dy in [0.0, 18.0, -20.0, 30.0, -28.0]) {
    tester.testGameWidget(
      '§14.3 offset $dy, no rim touch → perfect: +2 coins, streak +1, '
      'banner, shake',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h, events) = await firstHoop(game);
        expect(h.opening, closeTo(118, 1));
        final streak0 = run.state.streak;
        rumbleLog(game).clear();
        expect(await passHoopAt(game, h, dy: dy), isTrue);
        expect(h.takenRing, 0);
        expect(h.touched, isFalse);
        expect(h.passOffset, isNotNull);
        final passed = events.whereType<HoopPassed>().single;
        expect(passed.perfect, isTrue);
        expect(passed.clean, isFalse);
        expect(passed.rimTouched, isFalse);
        expect(run.state.streak, streak0 + 1);
        final coins = events.whereType<CoinsEarned>().single;
        expect(coins.source, CoinSource.perfect);
        expect(coins.amount, 2);
        expect(RunHud.of(run)!.banners.current, isA<StreakBanner>());
        expect(rumbleLog(game), [RumbleKind.shake]);
        expect(run.state.perfectPasses, 1);
        expect(run.state.cleanPasses, 0);
      },
    );
  }

  tester.testGameWidget(
    '§14.3 a rim touch then a centred pass → graze (not perfect): +1 '
    'coin, streak reset, no knock at the pass',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, h, events) = await firstHoop(game);
      run.state.streak = 3; // a streak running
      h.touched = true; // the rim was touched earlier on this hoop
      rumbleLog(game).clear();
      expect(await passHoopAt(game, h), isTrue);
      final passed = events.whereType<HoopPassed>().single;
      expect(passed.perfect, isFalse);
      expect(run.state.streak, 0);
      expect(passed.clean, isFalse);
      expect(passed.rimTouched, isTrue);
      expect(events.whereType<CoinsEarned>().single.amount, 1);
      expect(rumbleLog(game), isEmpty);
      expect(run.state.cleanPasses, 0);
    },
  );

  tester.testGameWidget(
    '§14.3 rides: a ride ring passed far off-centre is perfect',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, h, events) = await firstHoop(game);
      run.state.ride = RideState(kind: RideKind.comet);
      expect(await passHoopAt(game, h, dy: 34), isTrue);
      final passed = events.whereType<HoopPassed>().single;
      expect(passed.perfect, isTrue);
      expect(passed.duringRide, isTrue);
      expect(h.passOffset!.abs(), greaterThan(24));
    },
  );

  tester.testGameWidget(
    '§14.3 FEVER: a rim-free off-centre pass is perfect and sets the '
    'streak to 5',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 15,
        force: [ElementId.fever],
      );
      await flyUntil(
        game,
        (_) => firstHoopOf(game, HoopKindId.fever) != null,
        maxSeconds: 120, // PRD-2.3.1 §0: the forced ring waits longer
      );
      final h = firstHoopOf(game, HoopKindId.fever)!;
      // The later the ring, the smaller its opening: 14 pt off stays
      // rim-free at any index (24 at hoop 15).
      run.state.streak = 0;
      expect(
        await passHoopAt(game, h, dy: h.plan.index <= 20 ? 24 : 14),
        isTrue,
      );
      expect(h.takenRing, 0);
      expect(h.touched, isFalse);
      expect(run.state.streak, 5);
      expect(run.state.onFire, isTrue);
    },
  );

  tester.testGameWidget(
    '§14.3 FEVER: a centred pass sets the streak to 5',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 15,
        force: [ElementId.fever],
      );
      await flyUntil(
        game,
        (_) => firstHoopOf(game, HoopKindId.fever) != null,
        maxSeconds: 120, // PRD-2.3.1 §0: the forced ring waits longer
      );
      final h = firstHoopOf(game, HoopKindId.fever)!;
      run.state.streak = 0;
      expect(await passHoopAt(game, h), isTrue);
      expect(run.state.streak, 5);
      expect(run.state.onFire, isTrue);
    },
  );

  tester.testGameWidget(
    '§14.3 Bullseye: a centred pass is perfect and pays +2 and the '
    'bullseye +3 (PRD-2.3.1 §6; 2.3.0 had +2)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 6,
        force: [ElementId.bullseye],
      );
      final events = <RunEvent>[];
      run.events.onAny(events.add);
      await flyUntil(
        game,
        (_) => firstHoopOf(game, HoopKindId.bullseye) != null,
      );
      final h = firstHoopOf(game, HoopKindId.bullseye)!;
      expect(await passHoopAt(game, h), isTrue);
      final sources = events
          .whereType<CoinsEarned>()
          .map((e) => (e.source, e.amount))
          .toList();
      expect(sources, contains((CoinSource.perfect, 2)));
      expect(sources, contains((CoinSource.bullseye, 3)));
      expect(
        events.whereType<HoopPassed>().where((e) => e.hoop == h).single.perfect,
        isTrue,
      );
    },
  );

  tester.testGameWidget(
    '§14.3 pairs: a rim-free pass through either ring is perfect',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 12,
        force: [ElementId.pair],
      );
      final events = <RunEvent>[];
      run.events.onAny(events.add);
      final h = await flyToHoop(game, HoopKindId.pair, ElementId.pair);
      expect(h, isNotNull);
      expect(h!.rings, hasLength(2));
      // Glide through the second ring's centre.
      await glideInto(
        game,
        h,
        h.position.y + h.rings[1],
        until: (_) => h.resolved,
        seconds: 2,
      );
      expect(h.takenRing, 1);
      expect(h.touched, isFalse);
      final p = events.whereType<HoopPassed>().where((e) => e.hoop == h);
      expect(p.single.perfect, isTrue);
    },
  );

  tester.testGameWidget(
    '§11.5 summary / analytics: cleanPasses counts and run_end.clean_passes '
    'is sent (plus score and max_streak, §13.6, and the PRD-2.3 §14.8 '
    'perfect_rate / coins_per_hoop)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      run.debugPass(perfect: true);
      run.debugPass(perfect: true);
      run.debugPass(clean: true);
      run.debugPass(clean: true);
      run.debugPass();
      final s = run.endRun();
      expect(s.cleanPasses, 2);
      expect(s.perfectPasses, 2);
      expect(s.maxStreak, 2);
      final end = spy.events.where((e) => e.$1 == 'run_end').single.$2!;
      expect(end['clean_passes'], 2);
      expect(end['max_streak'], 2);
      expect(end['score'], run.state.score);
      expect(end['hoops'], 5);
      expect(end['perfect_rate'], .4);
      expect(end['coins_per_hoop'], closeTo(s.coins / 5, .006));
    },
  );
}
