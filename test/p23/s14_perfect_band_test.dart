import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/special_hoops_config.dart';
import 'package:flappy_spikes/run/config/streak_config.dart';
import 'package:flappy_spikes/run/config/tuning_defaults.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/bullseye.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/services/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Owner 2026-10-13 (after the 2.3 release): the remote perfect band
/// (`point_perfect_band`) and the remote Bullseye hit band
/// (`point_bullseye_band`), PRD-2.3 §14.3 + §15.
void main() {
  // The test-wide set (flutter_test_config.dart) plus [extra].
  void useTuning(Map<String, String> extra) {
    Tuning.instance = Tuning(
      active: TuningValues.resolve({'ui_unlock_best': '0', ...extra}),
    );
    TuningValues.current = Tuning.instance.active;
  }

  tearDown(() => useTuning(const {}));

  group('config', () {
    test('defaults: perfect band [[0,0]] (off), bullseye band 12', () {
      final defs = {for (final d in kTuningDefaults) d.key: d};
      expect(defs['point_perfect_band']!.value, [
        [0, 0],
      ]);
      expect(defs['point_bullseye_band']!.value, 12.0);
      expect(PerfectBandConfig.bandAt(0), 0);
      expect(PerfectBandConfig.bandAt(80), 0);
      expect(BullseyeConfig.band, 12);
      expect(BullseyeConfig.drawBand, 12);
    });

    test(
      'band ≤ 0: any rim-free pass is perfect (§14.3); a rim touch never',
      () {
        for (final off in [0.0, 20.0, -40.0, null]) {
          expect(
            PerfectBandConfig.isPerfect(
              touched: false,
              hoopIndex: 5,
              offset: off,
            ),
            isTrue,
          );
          expect(
            PerfectBandConfig.isPerfect(
              touched: true,
              hoopIndex: 5,
              offset: off,
            ),
            isFalse,
          );
        }
      },
    );

    test('band 16: 20 pt off is not perfect, 10 pt off is', () {
      useTuning({'point_perfect_band': '[[0,16]]'});
      expect(
        PerfectBandConfig.isPerfect(touched: false, hoopIndex: 3, offset: 20),
        isFalse,
      );
      expect(
        PerfectBandConfig.isPerfect(touched: false, hoopIndex: 3, offset: -20),
        isFalse,
      );
      expect(
        PerfectBandConfig.isPerfect(touched: false, hoopIndex: 3, offset: 10),
        isTrue,
      );
      expect(
        PerfectBandConfig.isPerfect(touched: false, hoopIndex: 3, offset: -16),
        isTrue,
      );
      expect(
        PerfectBandConfig.isPerfect(touched: true, hoopIndex: 3, offset: 0),
        isFalse,
      );
    });

    test('the band curve interpolates by hoop index', () {
      useTuning({'point_perfect_band': '[[0,0],[10,0],[20,30],[40,10]]'});
      expect(PerfectBandConfig.bandAt(5), 0);
      expect(PerfectBandConfig.bandAt(15), closeTo(15, 1e-9));
      expect(PerfectBandConfig.bandAt(20), 30);
      expect(PerfectBandConfig.bandAt(30), closeTo(20, 1e-9));
      expect(PerfectBandConfig.bandAt(99), 10);
      // Hoop 5: no band yet; hoop 15: ±15.
      expect(
        PerfectBandConfig.isPerfect(touched: false, hoopIndex: 5, offset: 40),
        isTrue,
      );
      expect(
        PerfectBandConfig.isPerfect(touched: false, hoopIndex: 15, offset: 16),
        isFalse,
      );
      expect(
        PerfectBandConfig.isPerfect(touched: false, hoopIndex: 15, offset: 14),
        isTrue,
      );
    });

    test('bullseye band 8: 10 pt off is no bullseye; default 12: it is', () {
      expect(BullseyeHoopKind.isBullseyeOffset(10), isTrue);
      useTuning({'point_bullseye_band': '8'});
      expect(BullseyeConfig.band, 8);
      expect(BullseyeConfig.drawBand, 12, reason: 'the drawing stays fixed');
      expect(BullseyeHoopKind.isBullseyeOffset(10), isFalse);
      expect(BullseyeHoopKind.isBullseyeOffset(-7.5), isTrue);
    });
  });

  // ----------------------------------------------------------- in a run

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
  }

  /// The next straight normal hoop well ahead of the bird.
  Future<Hoop?> nextNormal(FlappySpikesGame g) async {
    Hoop? found;
    await flyUntil(g, (r) {
      final b = r.birdTrackPosition();
      for (final h in hoopsOf(g)) {
        if (h.plan.kind != HoopKindId.normal || h.resolved) continue;
        if (h.tilt != 0 || h.plan.ringOffsets.length != 1) continue;
        if (b != null && h.planeX < b.x + 120) continue;
        found = h;
        return true;
      }
      return false;
    });
    return found;
  }

  /// Passes [h] at [dy] off its centre; returns the pass event.
  Future<HoopPassed?> passAt(FlappySpikesGame g, Hoop h, double dy) async {
    HoopPassed? got;
    g.run!.events.on<HoopPassed>((e) {
      if (identical(e.hoop, h)) got = e;
    });
    expect(await passHoopAt(g, h, dy: dy), isTrue);
    return got;
  }

  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  );

  tester.testGameWidget(
    'default: a rim-free pass 20 pt off-centre is perfect (today\'s rule)',
    setUp: boot,
    verify: (g, _) async {
      await startRun(g, startHoopIndex: 3);
      final h = await nextNormal(g);
      expect(h, isNotNull);
      final e = await passAt(g, h!, 20);
      expect(e, isNotNull);
      expect(h.touched, isFalse);
      expect(h.passOffset!.abs(), greaterThan(16));
      expect(e!.perfect, isTrue);
    },
  );

  tester.testGameWidget(
    'band 16: a rim-free pass 20 pt off is not perfect (clean), 10 pt off is',
    setUp: (g, t) async {
      useTuning({'point_perfect_band': '[[0,16]]'});
      await boot(g, t);
    },
    verify: (g, _) async {
      final run = await startRun(g, startHoopIndex: 3);
      final h1 = await nextNormal(g);
      expect(h1, isNotNull);
      final e1 = await passAt(g, h1!, 20);
      expect(h1.touched, isFalse);
      expect(h1.passOffset!.abs(), greaterThan(16));
      expect(e1!.perfect, isFalse);
      expect(e1.clean, isTrue);
      expect(e1.rimTouched, isFalse);
      expect(run.state.streak, 0);

      final h2 = await nextNormal(g);
      expect(h2, isNotNull);
      final perfects = run.state.perfectPasses;
      final e2 = await passAt(g, h2!, 10);
      expect(h2.touched, isFalse);
      expect(h2.passOffset!.abs(), lessThanOrEqualTo(16));
      expect(e2!.perfect, isTrue);
      expect(run.state.perfectPasses, perfects + 1);
    },
  );

  tester.testGameWidget(
    'a band set mid-run does not change the current run (beginRun lock)',
    setUp: boot,
    verify: (g, _) async {
      await startRun(g, startHoopIndex: 3);
      // The console value arrives after the run began.
      Tuning.instance = Tuning(
        active: TuningValues.resolve({
          'ui_unlock_best': '0',
          'point_perfect_band': '[[0,16]]',
        }),
      );
      final h = await nextNormal(g);
      expect(h, isNotNull);
      final e = await passAt(g, h!, 20);
      expect(h.passOffset!.abs(), greaterThan(16));
      expect(e!.perfect, isTrue, reason: 'the run pinned the old set');
      expect(PerfectBandConfig.bandAt(h.plan.index), 0);
    },
  );

  for (final (band, hit) in [(null, true), ('8', false)]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {'gamesPlayed': 20},
        worldHeight: 711,
        seed: 5,
      ),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'bullseye band ${band ?? 'default 12'}: a pass 10 pt off is '
      '${hit ? '' : 'not '}a bullseye',
      setUp: (g, t) async {
        if (band != null) useTuning({'point_bullseye_band': band});
        await boot(g, t);
      },
      verify: (g, _) async {
        await startRun(g, startHoopIndex: 15, force: [ElementId.bullseye]);
        final h = await flyToHoop(
          g,
          HoopKindId.bullseye,
          ElementId.bullseye,
          where: (h) => h.tilt == 0,
        );
        expect(h, isNotNull);
        // Glide in slightly above the band edge: gravity pulls the bird
        // down toward the centre, so aim for a ~10 pt crossing.
        expect(await passHoopAt(g, h!, dy: -12), isTrue);
        final off = h.passOffset!.abs();
        expect(off, inInclusiveRange(8.5, 11.5));
        expect(BullseyeHoopKind.flashOf(h) > 0, hit);
      },
    );
  }
}
