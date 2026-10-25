import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
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
