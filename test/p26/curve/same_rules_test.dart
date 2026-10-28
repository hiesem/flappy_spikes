import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/director/layout_sampler.dart';
import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/ab_arms.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_setup.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

List<(SlotPlan, GapPlan)> _plans(RunDirector director, double height) {
  double? previous;
  return List.generate(400, (i) {
    final ctx = DirectorContext.open(height, prevCentreY: previous);
    final slot = director.nextSlot(ctx);
    previous = slot.centreY;
    return (slot, director.nextGap(ctx, slot));
  });
}

void main() {
  final originalTuning = TuningValues.current;
  tearDown(() => TuningValues.current = originalTuning);
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'R2 same seed has the same rules across ordinary player setups',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      game.runDebug.ignoreGates = false;
      game.storage.metElements = {
        for (final element in ElementId.values) element.storageId,
      };
      for (final seed in [7, 21, 1234]) {
        List<(SlotPlan, GapPlan)>? baseline;
        for (final games in [6, 500]) {
          for (final best in [0, 32500000]) {
            for (final level in [0, 31, 36]) {
              for (final mode in HomeMode.values) {
                for (final noAds in [false, true]) {
                  for (final arm in AbArms.profiles.keys) {
                    await game.storage.saveAbArmV1(arm);
                    TuningValues.current = TuningValues.defaults().withArm(arm);
                    game.storage
                      ..gamesPlayed = games
                      ..bestScore = best
                      ..playerLevel = level
                      ..noAds = noAds;
                    await game.storage.saveHomeMode(mode);
                    final setup = RunSetup(
                      seed: seed,
                      viewHeight: 711,
                      opponent: mode == HomeMode.versus
                          ? OpponentRun(
                              uid: 'rival',
                              name: 'Rival',
                              score: 50,
                              best: 500,
                              level: 31,
                              timeline: RunTimeline()..end(100),
                              runId: 'rival-run',
                            )
                          : null,
                    );
                    final run = RunController(setup: setup, game: game);
                    expect(run.setup.showcase, isNull);
                    expect(run.setup.ignoreGates, isFalse);
                    expect(run.countsForUpload, isTrue);
                    final plans = _plans(run.director, 711);
                    baseline ??= plans;
                    expect(
                      plans,
                      baseline,
                      reason:
                          'seed=$seed games=$games best=$best level=$level '
                          'mode=$mode noAds=$noAds arm=$arm',
                    );
                  }
                }
              }
            }
          }
        }
      }
    },
  );

  // PRD §8.3 decision 3 (#97/#118) replaces final-centre identity with
  // drawn-Δy identity: the row edges scale with the full live band.
  test('R2 drawn delta y in points is identical at 711 and 730', () {
    var differentEdgeSteps = 0;
    for (final squeezed in [false, true]) {
      for (var seed = 0; seed < 200; seed++) {
        final a = LayoutSampler(DirectorTables.prd2, math.Random(seed));
        final b = LayoutSampler(DirectorTables.prd2, math.Random(seed));
        final oracle = math.Random(seed);
        for (var i = 0; i < 400; i++) {
          final previousA = a.lastY;
          final previousB = b.lastY;
          // Identical modifier inputs isolate the layout rule from later
          // geometry-dependent motion/special/hazard decisions.
          final hard = i % 7 == 0;
          double next(LayoutSampler sampler, double height) =>
              sampler.nextCentre(
                i,
                DirectorContext(
                  viewHeight: height,
                  topTooth: 44,
                  floorTooth: height - 44,
                  squeezeWindow: squeezed,
                  squeezeTopTooth: 44 + (squeezed ? 54 : 0),
                  squeezeFloorTooth: height - 44 - (squeezed ? 54 : 0),
                ),
                RunConfig.openingFor(i),
                hardFollowUp: hard,
              );
          final ya = next(a, 711);
          final yb = next(b, 730);
          if (i == 0) {
            expect(a.lastDrawnDy, isNull);
            expect(b.lastDrawnDy, isNull);
            continue;
          }
          final u = oracle.nextDouble();
          oracle.nextDouble(); // direction draw
          final q = DirectorTables.prd2.bandFor(i).dy;
          final raw = LayoutSampler.sampleDy(q, u) * 540;
          final expected = hard ? math.min(raw, q.$3 * 540 * .85) : raw;
          final tag = 'seed=$seed hoop=$i squeeze=$squeezed';
          expect(a.lastDrawnDy, closeTo(expected, 1e-9), reason: tag);
          expect(b.lastDrawnDy, a.lastDrawnDy, reason: tag);
          if (((ya - previousA!) - (yb - previousB!)).abs() > 1e-8) {
            differentEdgeSteps++;
          }
        }
      }
    }
    expect(differentEdgeSteps, greaterThan(0));
  });
  test('R2 director retains the same draw for plain slots at both heights', () {
    var compared = 0;
    for (var seed = 0; seed < 100; seed++) {
      RunDirector director() => RunDirector(seed: seed, enabled: {}, met: {});
      final a = director();
      final b = director();
      for (var i = 0; i < 10; i++) {
        final pa = a.nextSlot(DirectorContext.open(711));
        final pb = b.nextSlot(DirectorContext.open(730));
        if (pa.kind == HoopKindId.normal &&
            pb.kind == HoopKindId.normal &&
            a.debugLastDrawnDy != null &&
            b.debugLastDrawnDy != null) {
          expect(
            a.debugLastDrawnDy,
            b.debugLastDrawnDy,
            reason: 'seed=$seed slot=$i',
          );
          compared++;
        }
        a.nextGap(DirectorContext.open(711), pa);
        b.nextGap(DirectorContext.open(730), pb);
      }
    }
    expect(compared, greaterThan(100));
  });
}
