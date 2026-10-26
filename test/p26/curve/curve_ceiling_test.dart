import 'dart:math' as math;

import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/hazard_budget.dart';
import 'package:flappy_spikes/run/director/layout_sampler.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

// Independent PRD D3 oracle: do not trust a plan's own reported cost.
double _hazardCost(SlotPlan p, double dy, double p90, bool squeeze) {
  if (p.cometHang ||
      p.duringRide ||
      {
        HoopKindId.bullseye,
        HoopKindId.fever,
        HoopKindId.luckySpin,
        HoopKindId.portal,
        HoopKindId.rideRing,
      }.contains(p.kind)) {
    return 0;
  }
  var cost = switch (p.kind) {
    HoopKindId.saw => 2.0,
    HoopKindId.switchRing => 1.5,
    HoopKindId.spring || HoopKindId.pair || HoopKindId.train => .5,
    _ => 0.0,
  };
  final tilt = p.tiltDeg.abs();
  if (tilt > 0) {
    cost += tilt <= 20
        ? .25
        : tilt <= 30
        ? 1
        : 1.5;
  }
  if (p.motion case final motion?) {
    cost += switch (motion.type) {
      MotionType.rail || MotionType.swing => 1,
      _ => 1.25,
    };
  }
  if (dy.abs() > p90 + 1e-6) {
    cost++;
  }
  if (squeeze) {
    cost++;
  }
  return cost;
}

void main() {
  test('D2 short-screen formation steps stay under 240 pt', () {
    for (var seed = 1; seed <= 100; seed++) {
      final director = RunDirector(
        seed: seed,
        enabled: {
          ElementId.normalHoop,
          ElementId.angledRing,
          ElementId.movingRing,
        },
        met: ElementId.values.toSet(),
      );
      SlotPlan? previous;
      for (var i = 0; i < 260; i++) {
        final ctx = DirectorContext.open(568, prevCentreY: previous?.centreY);
        final p = director.nextSlot(ctx);
        director.nextGap(ctx, p);
        if (previous != null) {
          expect(
            (p.centreY - previous.centreY).abs(),
            lessThanOrEqualTo(240 + 1e-8),
            reason:
                'seed=$seed previous=$previous ${previous.formation} current=$p ${p.formation}',
          );
        }
        previous = p;
      }
    }
  });

  // PRD-2.6 WP-D: exercise shipped plans, including specials, formations,
  // gap draws and deterministic hazard downgrades, rather than sampler rolls.
  for (final height in [568.0, 711.0, 730.0]) {
    for (final squeezed in [false, true]) {
      test('D ceiling 200 seeds x 400 slots h=$height squeeze=$squeezed', () {
        var downgrades = 0;
        var strong = 0;
        for (var seed = 0; seed < 200; seed++) {
          RunDirector director() => RunDirector(
            seed: seed,
            enabled: ElementId.values.toSet(),
            met: ElementId.values.toSet(),
          );
          final first = director(), replay = director();
          final costs = <double>[];
          double? previous;
          var lastCalm = -1;
          var wasCalm = false;
          var calmInterval = 36.0;
          for (var i = 0; i < 400; i++) {
            // Squeeze is an in-run state; hold it over realistic windows.
            final squeeze = squeezed && i >= 35 && i % 40 >= 30;
            final ctx = DirectorContext.open(
              height,
              squeezeWindow: squeeze,
              squeezeInset: squeeze ? 100 : 0,
              prevCentreY: previous,
            );
            final p = first.nextSlot(ctx);
            final tag = 'seed=$seed slot=$i h=$height squeeze=$squeeze $p';
            expect(p, replay.nextSlot(ctx), reason: tag);
            final gap = first.nextGap(ctx, p);
            expect(gap, replay.nextGap(ctx, p), reason: tag);
            // D1 changes these introductions. Other specials and gap items
            // retain the approved 2.5 tuning (SPEC PRD-2.3.1 §0).
            final introducedAt = const {
              ElementId.angledRing: 10,
              ElementId.movingRing: 25,
              ElementId.switchRing: 15,
              ElementId.saw: 30,
              ElementId.portal: 12,
            }[p.element];
            if (introducedAt != null) {
              expect(i, greaterThanOrEqualTo(introducedAt), reason: tag);
            }
            if (p.formation != null) {
              expect(i, greaterThanOrEqualTo(150), reason: tag);
            }
            final dy = previous == null ? 0.0 : p.centreY - previous;
            expect(dy.abs(), lessThanOrEqualTo(270 + 1e-8), reason: tag);
            if (p.tiltDeg.abs() >= 20) {
              strong++;
              expect(dy.abs(), greaterThanOrEqualTo(40 - 1e-8), reason: tag);
              expect(p.tiltDeg.sign, dy.sign, reason: tag);
            }
            if (p.kind == HoopKindId.normal && !p.duringRide && !p.cometHang) {
              expect(
                p.opening,
                closeTo(
                  RunConfig.openingFor(i) + (p.tiltDeg.abs() == 45 ? 6 : 0),
                  1e-8,
                ),
                reason: tag,
              );
              final angle = p.tiltDeg * math.pi / 180;
              double window(double slope) =>
                  2 *
                  ((p.opening / 2 + RunConfig.rimRadius) *
                          (math.cos(angle) + slope * math.sin(angle)).abs() -
                      (RunConfig.birdRadius + RunConfig.rimRadius) *
                          math.sqrt(1 + slope * slope));
              expect(window(0), greaterThanOrEqualTo(15 - 1e-8), reason: tag);
              expect(
                window(.5 * (p.tiltDeg < 0 ? -1 : 1)),
                greaterThanOrEqualTo(35 - 1e-8),
                reason: tag,
              );
            }
            if (p.motion != null) {
              expect(i, greaterThanOrEqualTo(25), reason: tag);
              final swing = LayoutSampler(
                first.tables,
                math.Random(0),
              ).motionTiltDeg(p.motion);
              expect(
                p.tiltDeg.abs() + swing,
                lessThanOrEqualTo(i < 150 ? 15 : 30),
                reason: tag,
              );
              final from = switch (p.motion!.type) {
                MotionType.rail => 25,
                MotionType.swing => 35,
                MotionType.horizontal || MotionType.diagonal => 70,
                MotionType.orbit || MotionType.rock => 90,
              };
              expect(i, greaterThanOrEqualTo(from), reason: tag);
            }
            if (p.tiltDeg != 0) {
              expect(i, greaterThanOrEqualTo(10), reason: tag);
            }
            if (p.tiltDeg.abs() >= 20) {
              expect(i, greaterThanOrEqualTo(50), reason: tag);
            }
            if (p.tiltDeg.abs() == 45) {
              expect(i, greaterThanOrEqualTo(60), reason: tag);
            }
            if (p.kind == HoopKindId.saw) {
              expect(i, greaterThanOrEqualTo(squeeze ? 100 : 30), reason: tag);
            }
            if (p.kind == HoopKindId.switchRing) {
              expect(i, greaterThanOrEqualTo(15), reason: tag);
            }
            final cost = _hazardCost(
              p,
              dy,
              first.tables.bandFor(i).dy.$2 * math.min(ctx.band, 540),
              squeeze,
            );
            expect(p.hazardCost, closeTo(cost, 1e-8), reason: tag);
            costs.add(cost);
            if (costs.length > 4) costs.removeAt(0);
            if (!p.forced) {
              expect(
                costs.reduce((a, b) => a + b),
                lessThanOrEqualTo(HazardBudget().budgetAt(i) + 1e-8),
                reason: '$tag costs=$costs forced=${p.forced}',
              );
            }
            if (p.calm) {
              expect(p.kind, HoopKindId.normal, reason: tag);
              expect(p.motion, isNull, reason: tag);
              expect(p.tiltDeg.abs(), lessThanOrEqualTo(10), reason: tag);
              expect(
                dy.abs(),
                lessThanOrEqualTo(
                  first.tables.bandFor(i).dy.$1 * math.min(ctx.band, 540) +
                      1e-8,
                ),
                reason: tag,
              );
              if (!wasCalm) {
                if (lastCalm < 0) {
                  expect(i, inInclusiveRange(30, 35), reason: tag);
                }
                if (lastCalm >= 0) {
                  expect(i - lastCalm, inInclusiveRange(12, 59), reason: tag);
                }
                if (lastCalm >= 0) {
                  expect(
                    i,
                    inInclusiveRange(
                      (lastCalm + calmInterval).round() - 4,
                      (lastCalm + calmInterval).round() + 4,
                    ),
                    reason: tag,
                  );
                  calmInterval = math.min(55, calmInterval * 1.2);
                }
                lastCalm = i;
              }
            }
            wasCalm = p.calm;
            previous = p.centreY;
          }
          downgrades += first.downgrades;
          expect(lastCalm, greaterThanOrEqualTo(340));
          expect(first.downgrades, replay.downgrades);
        }
        expect(downgrades, greaterThan(0));
        expect(strong, greaterThan(0));
      }, timeout: const Timeout(Duration(minutes: 5)));
    }
  }
}
