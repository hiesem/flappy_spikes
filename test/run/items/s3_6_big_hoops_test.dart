import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/run/items/big_hoops.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-2a: Big Hoops, run side (PRD-2 §3.0.1, §3.6, §5.1).
void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  group('§3.6 BigHoopsState', () {
    test('§3.6 ×1.5 until D − 8 s, easing linearly 1.5 → 1.0 over the last '
        '8 s, 1 after D', () {
      final b = BigHoopsState(duration: 34, start: 2);
      expect(b.mult(2), 1.5);
      expect(b.mult(2 + 26), 1.5);
      expect(b.mult(2 + 30), closeTo(1.25, 1e-9));
      expect(b.mult(2 + 33.99), closeTo(1.0006, 1e-3));
      expect(b.mult(2 + 34), 1);
      expect(b.mult(60), 1);
      // Monotone non-increasing.
      var last = 9.0;
      for (var t = 2.0; t < 40; t += .1) {
        final m = b.mult(t);
        expect(m, lessThanOrEqualTo(last + 1e-12));
        last = m;
      }
    });
  });

  for (final h in [568.0, 711.0]) {
    final spy = AnalyticsSpy();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, services: spy),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§3.6 ($h) the home-slot Big Hoops is consumed at the start and rolls '
      'D in 30–40 s on the timing stream; no run without it is boosted',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game, starter: Powerup.bigHoops);
        expect(game.storage.armedPowerup, 'none');
        expect(analyticsLog(spy).map((e) => e.$1), contains('big_hoops_used'));
        final b = run.state.bigHoops!;
        expect(b.start, 0);
        expect(b.duration, inInclusiveRange(30, 40));
        // The first hoop (opening 118) is 1.5× and gold.
        final first = run.spawner.hoops.first;
        expect(first.opening, closeTo(RunConfig.opening0 * 1.5, 1e-9));
        expect(first.look.colors, RingColors.gold);
        expect(BigHoopsFeature.isGold(first), isTrue);
        // The next run (nothing armed) is plain.
        killRun(game);
        await flushAndMount(game);
        game.goHome();
        stepGame(game, 1);
        await flushAndMount(game);
        final run2 = await startRun(game);
        expect(run2.state.bigHoops, isNull);
        expect(run2.spawner.hoops.first.opening, RunConfig.opening0);
        expect(run2.spawner.hoops.first.look.colors, isNull);
      },
    );
  }

  test('§3.6 D over many seeds: every value in [30, 40], spread over the '
      'range, same seed → same D', () {
    final ds = <double>[];
    for (var seed = 1; seed <= 200; seed++) {
      final d = RunDirector(seed: seed, enabled: const {}, met: const {});
      ds.add(d.rollBigHoopsDuration());
      expect(
        RunDirector(
          seed: seed,
          enabled: const {},
          met: const {},
        ).rollBigHoopsDuration(),
        ds.last,
      );
    }
    expect(ds.every((d) => d >= 30 && d <= 40), isTrue);
    expect(ds.reduce(min), lessThan(31));
    expect(ds.reduce(max), greaterThan(39));
  });

  for (final h in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: 21),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§3.6 ($h) every hoop spawned is sized by the multiplier at its spawn '
      'time (1.5 → eased → 1), capped to the band, gold only while > 1; a '
      'hoop never changes size on screen',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game, starter: Powerup.bigHoops);
        game.runDebug.god = true;
        final b = run.state.bigHoops!;
        final spawned = <(double, double, int, bool, bool)>[];
        // The first hoop was spawned at run start (runClock 0).
        final f = run.spawner.hoops.first;
        spawned.add((0, f.opening, f.plan.index, f.look.colors != null, true));
        final sizes = <Object, double>{};
        run.events.on<HoopSpawned>((e) {
          spawned.add((
            run.state.runClock,
            e.hoop.opening,
            e.plan.index,
            e.hoop.look.colors == RingColors.gold,
            // WP-3c: special kinds keep their own look (§3.6).
            e.plan.kind == HoopKindId.normal,
          ));
          sizes[e.hoop] = e.hoop.opening;
        });
        await flyRun(
          game,
          maxSeconds: b.duration + 6,
          onFrame: (r) {
            for (final hp in r.spawner.hoops) {
              final s0 = sizes[hp];
              if (s0 != null) expect(hp.opening, s0);
            }
          },
        );
        expect(run.state.runClock, greaterThan(b.duration));
        final band = h - 2 * RunConfig.stripHeight;
        final cap = band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin);
        var sawEase = false, sawPlain = false;
        for (final (t, opening, idx, gold, normal) in spawned) {
          final m = b.mult(t);
          final base = run.director.openingFor(idx, ride: false);
          expect(opening, closeTo(min(base * m, cap), 1e-6), reason: 't=$t');
          if (normal) expect(gold, m > 1, reason: 't=$t m=$m');
          if (!normal) expect(gold, isFalse, reason: 'special at t=$t');
          if (m > 1 && m < 1.5) sawEase = true;
          if (m == 1) sawPlain = true;
        }
        expect(sawEase, isTrue);
        expect(sawPlain, isTrue);
        expect(run.state.bigHoops, isNull, reason: 'cleared after D');
      },
    );
  }

  test('§3.6 knobs (bigHoopsMult 1.5, bigHoopsMin 30, bigHoopsMax 40, '
      'bigHoopsEase 8)', () {
    expect(RunConfig.bigHoopsMult, 1.5);
    expect(RunConfig.bigHoopsMin, 30);
    expect(RunConfig.bigHoopsMax, 40);
    expect(RunConfig.bigHoopsEase, 8);
    expect(HoopKindId.normal, isNotNull);
  });
}
