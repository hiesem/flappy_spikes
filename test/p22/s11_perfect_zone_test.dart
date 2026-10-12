import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/streak_config.dart';
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

/// PRD-2.2 §11.5 the perfect zone: perfect = no rim touch **and** the
/// crossing within min(24, 0.2 × opening) of the passed ring's centre.
void main() {
  group('§11.5 zone half-width', () {
    test('23.6 at opening 118, 18.4 at 92, capped at 24 above 120', () {
      expect(PerfectConfig.halfWidth(118), closeTo(23.6, 1e-9));
      expect(PerfectConfig.halfWidth(92), closeTo(18.4, 1e-9));
      expect(PerfectConfig.halfWidth(120), 24);
      expect(PerfectConfig.halfWidth(177), 24, reason: 'Big Hoops ×1.5');
      expect(PerfectConfig.halfWidth(146), 24, reason: 'saw +28');
      expect(PerfectConfig.zoneFactor, .2);
      expect(PerfectConfig.zoneMax, 24);
    });
    test('the edge is inside; just past it is outside', () {
      expect(PerfectConfig.inZone(23.6, 118), isTrue);
      expect(PerfectConfig.inZone(-23.6, 118), isTrue);
      expect(PerfectConfig.inZone(23.7, 118), isFalse);
      expect(PerfectConfig.inZone(-18.5, 92), isFalse);
    });
    test('the bullseye band ±12 lies inside the zone at every opening', () {
      for (var o = 92.0; o <= 200; o += 1) {
        expect(PerfectConfig.halfWidth(o), greaterThan(12));
      }
    });
  });

  late AnalyticsSpy spy;
  final tester = FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, services: spy, seed: 5);
  }, gameSize: Vector2(320, 711));

  Future<void> prepare(FlappySpikesGame g) async {
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

  // Gravity pulls the gliding bird down by ≈ 2 pt before the plane, so the
  // offsets keep a margin from the zone edge (±23.6 at hoop 0).
  for (final dy in [0.0, 18.0, -20.0]) {
    tester.testGameWidget(
      '§11.5 offset $dy (inside the zone) → perfect: +2 coins, streak +1, '
      'banner, shake',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h, events) = await firstHoop(game);
        expect(h.opening, closeTo(118, 1));
        final streak0 = run.state.streak;
        rumbleLog(game).clear();
        expect(await passHoopAt(game, h, dy: dy), isTrue);
        expect(h.takenRing, 0);
        expect(h.passOffset, isNotNull);
        expect(
          h.passOffset!.abs(),
          lessThanOrEqualTo(PerfectConfig.halfWidth(h.opening)),
        );
        final passed = events.whereType<HoopPassed>().single;
        expect(passed.perfect, isTrue);
        expect(passed.clean, isFalse);
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

  for (final dy in [30.0, -28.0]) {
    tester.testGameWidget(
      '§11.5 offset $dy (outside the zone, no rim touch) → clean: +1 coin, '
      'streak reset, no banner, point sound, one knock',
      setUp: (g, _) => prepare(g),
      verify: (game, _) async {
        final (run, h, events) = await firstHoop(game);
        run.state.streak = 3; // a streak running
        final sfx = sfxLog(game);
        rumbleLog(game).clear();
        expect(await passHoopAt(game, h, dy: dy), isTrue);
        expect(h.takenRing, 0);
        expect(h.touched, isFalse);
        expect(
          h.passOffset!.abs(),
          greaterThan(PerfectConfig.halfWidth(h.opening)),
        );
        final passed = events.whereType<HoopPassed>().single;
        expect(passed.perfect, isFalse);
        expect(passed.clean, isTrue);
        expect(passed.rimTouched, isFalse);
        expect(run.state.streak, 0);
        final coins = events.whereType<CoinsEarned>().single;
        expect(coins.source, CoinSource.hoop);
        expect(coins.amount, 1);
        expect(RunHud.of(run)!.banners.current, isNot(isA<StreakBanner>()));
        expect(sfx, contains('point'));
        expect(sfx.where((s) => s.startsWith('perfect')), isEmpty);
        expect(rumbleLog(game), [RumbleKind.knock]);
        expect(run.state.cleanPasses, 1);
        expect(run.state.perfectPasses, 0);
      },
    );
  }

  tester.testGameWidget(
    '§11.5 a rim touch then a centred pass → graze (non-perfect, not '
    'clean): +1 coin, no knock at the pass',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final (run, h, events) = await firstHoop(game);
      h.touched = true; // the rim was touched earlier on this hoop
      rumbleLog(game).clear();
      expect(await passHoopAt(game, h), isTrue);
      final passed = events.whereType<HoopPassed>().single;
      expect(passed.perfect, isFalse);
      expect(passed.clean, isFalse);
      expect(passed.rimTouched, isTrue);
      expect(events.whereType<CoinsEarned>().single.amount, 1);
      expect(rumbleLog(game), isEmpty);
      expect(run.state.cleanPasses, 0);
    },
  );

  tester.testGameWidget(
    '§11.5 rides: a ride ring passed far off-centre is still perfect',
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
    '§11.5 FEVER: a clean off-centre pass does not set the streak to 5',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 15,
        force: [ElementId.fever],
      );
      await flyUntil(game, (_) => firstHoopOf(game, HoopKindId.fever) != null);
      final h = firstHoopOf(game, HoopKindId.fever)!;
      expect(await passHoopAt(game, h, dy: 30), isTrue);
      expect(h.takenRing, 0);
      expect(run.state.streak, 0);
      expect(run.state.onFire, isFalse);
    },
  );

  tester.testGameWidget(
    '§11.5 FEVER: a centred pass sets the streak to 5',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 15,
        force: [ElementId.fever],
      );
      await flyUntil(game, (_) => firstHoopOf(game, HoopKindId.fever) != null);
      final h = firstHoopOf(game, HoopKindId.fever)!;
      expect(await passHoopAt(game, h), isTrue);
      expect(run.state.streak, 5);
      expect(run.state.onFire, isTrue);
    },
  );

  tester.testGameWidget(
    '§11.5 Bullseye: a centred pass is perfect and pays +2 and +3',
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
    '§11.5 pairs are judged per ring: the passed ring\'s own centre counts',
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
      expect(h.passOffset!.abs(), lessThan(PerfectConfig.halfWidth(h.opening)));
      final p = events.whereType<HoopPassed>().where((e) => e.hoop == h);
      expect(p.single.perfect, isTrue);
    },
  );

  tester.testGameWidget(
    '§11.5 summary / analytics: cleanPasses counts and run_end.clean_passes '
    'is sent (plus score and max_streak, §13.6)',
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
    },
  );
}
