import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/director/formations.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

RunDirector _director(int seed) => RunDirector(
  seed: seed,
  enabled: ElementId.values.toSet(),
  met: ElementId.values.toSet(),
  startHoopIndex: 150,
);

List<SlotPlan> _events(int seed) {
  final director = _director(seed);
  final plans = <SlotPlan>[];
  for (var offset = 0; offset < 100; offset++) {
    if (offset == 1) director.onRevive();
    if (offset == 18) director.onRideStart(RideKind.portal);
    if (offset == 28) director.onRideEnd(RideKind.portal);
    if (offset == 48) director.onSqueezeEnded(director.hoopIndex - 1);
    final ctx = DirectorContext.open(
      568,
      rideActive: offset >= 18 && offset < 28,
      squeezeWindow: offset >= 38 && offset < 48,
      squeezeInset: 90,
    );
    final plan = director.nextSlot(ctx);
    director.nextGap(ctx, plan);
    expect(plan.advance, greaterThanOrEqualTo(RunConfig.spacing));
    if (ctx.rideActive || ctx.squeezeWindow || plan.calm) {
      expect(plan.formation, isNull, reason: 'seed $seed slot ${plan.index}');
    }
    if (offset >= 1 && offset <= 3) expect(plan.calm, isTrue);
    plans.add(plan);
  }
  return plans;
}

void main() {
  test(
    'D7 a spring immediately before a due formation keeps its 240 pt target',
    () {
      for (final height in [568.0, 711.0]) {
        for (var seed = 0; seed < 20; seed++) {
          final director = RunDirector(
            seed: seed,
            enabled: {
              ElementId.normalHoop,
              ElementId.spring,
              ElementId.angledRing,
            },
            met: ElementId.values.toSet(),
            startHoopIndex: 149,
          );
          final ctx = DirectorContext.open(height);
          director.debugForce(ElementId.spring);
          final spring = director.nextSlot(ctx);
          director.nextGap(ctx, spring);
          expect(spring.kind, HoopKindId.spring);
          final landing = director.nextSlot(ctx);
          director.nextGap(ctx, landing);
          expect(landing.formation, isNull);
          final direction = spring.extra == SpringDir.up ? -1 : 1;
          expect(
            landing.centreY - spring.centreY,
            closeTo(direction * RunConfig.springJump, 1e-8),
          );
        }
      }
    },
  );

  test('D7 preserves spring landings and aligns final formation tilts', () {
    var springLandings = 0;
    var strongTilts = 0;
    var waveEntries = 0;
    var strongWaveEntries = 0;
    for (final height in [568.0, 711.0]) {
      for (final start in [0, 150, 250]) {
        for (var seed = 0; seed < 200; seed++) {
          final director = RunDirector(
            seed: seed,
            enabled: ElementId.values.toSet(),
            met: ElementId.values.toSet(),
            startHoopIndex: start,
          );
          final ctx = DirectorContext.open(height);
          SlotPlan? previous;
          for (var k = 0; k < 400; k++) {
            final plan = director.nextSlot(ctx);
            director.nextGap(ctx, plan);
            final reason =
                'height $height start $start seed $seed '
                'hoop ${plan.index}';
            if (previous?.kind == HoopKindId.spring && !plan.calm) {
              springLandings++;
              final direction = previous!.extra == SpringDir.up ? -1 : 1;
              expect(plan.formation, isNull, reason: reason);
              // The exact landing before a due formation is checked above;
              // here audit formation ownership throughout ordinary courses.
              expect(
                (plan.centreY - previous.centreY).sign,
                direction.toDouble(),
                reason: reason,
              );
            }
            if (plan.formation != null) {
              final dy = plan.centreY - (previous?.centreY ?? height / 2);
              if (plan.formation == FormationId.tiltWave &&
                  previous?.formation != FormationId.tiltWave) {
                waveEntries++;
                if (plan.tiltDeg.abs() >= 20) strongWaveEntries++;
              }
              if (plan.tiltDeg.abs() >= 20) {
                strongTilts++;
                expect(
                  dy.abs(),
                  greaterThanOrEqualTo(40 - 1e-9),
                  reason: reason,
                );
                expect(plan.tiltDeg.sign, dy.sign, reason: reason);
              }
            }
            previous = plan;
          }
        }
      }
    }
    expect(springLandings, greaterThan(0));
    expect(strongTilts, greaterThan(0));
    expect(waveEntries, greaterThan(0));
    expect(strongWaveEntries, greaterThan(0));
  });

  test(
    'D7 recovery, rides and squeezes interrupt shapes deterministically',
    () {
      for (var seed = 0; seed < 200; seed++) {
        expect(_events(seed), _events(seed));
      }
    },
  );

  test('D7 switches stay before their own plane and shapes fit the band', () {
    var switches = 0;
    for (final height in [568.0, 711.0]) {
      for (var seed = 0; seed < 20; seed++) {
        final director = _director(seed);
        final ctx = DirectorContext.open(height);
        for (var k = 0; k < 400; k++) {
          final plan = director.nextSlot(ctx);
          director.nextGap(ctx, plan);
          if (plan.formation == null) continue;
          final reach =
              plan.opening / 2 +
              RunConfig.rimRadius +
              RunConfig.bandMargin +
              (plan.motion?.halfTravel ?? 0);
          expect(
            plan.centreY - reach,
            greaterThanOrEqualTo(ctx.topTooth - 1e-9),
            reason:
                'seed $seed height $height plan $plan shape ${plan.formation}',
          );
          expect(
            plan.centreY + reach,
            lessThanOrEqualTo(ctx.floorTooth + 1e-9),
          );
          for (final item in plan.attached) {
            if (item.kind != ElementId.switchRing) continue;
            switches++;
            expect(
              plan.trackX - item.trackX,
              closeTo(
                RunConfig.cruise(plan.index) * RunConfig.switchLeadSeconds,
                1e-9,
              ),
            );
            expect(
              item.y,
              inInclusiveRange(
                ctx.topTooth + RunConfig.itemEdgeMargin - 1e-9,
                ctx.floorTooth - RunConfig.itemEdgeMargin + 1e-9,
              ),
            );
          }
        }
      }
    }
    expect(switches, greaterThan(0));
  });

  test('D7 ride replanning clears formation metadata', () {
    final director = _director(7);
    final ctx = DirectorContext.open(711);
    final plan = director.nextSlot(ctx);
    expect(plan.formation, isNotNull);
    expect(director.plainSlot(plan, ctx, ride: true).formation, isNull);
  });

  test('D7 debug force interrupts a reserved formation', () {
    final director = _director(7);
    final ctx = DirectorContext.open(711);
    expect(director.nextSlot(ctx).formation, isNotNull);
    director.debugForce(ElementId.normalHoop);
    final forced = director.nextSlot(ctx);
    expect(forced.forced, isTrue);
    expect(forced.formation, isNull);
  });
}
