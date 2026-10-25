import 'package:flappy_spikes/run/config/gates_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final height in [568.0, 711.0, 730.0]) {
    for (var step = 0; step < 3; step++) {
      for (var attempt = 1; attempt <= 3; attempt++) {
        test('B3 step $step attempt $attempt at $height', () {
          final script = ShowcaseScript.planFor(step, attempt);
          for (var seed = 0; seed < 50; seed++) {
            final d = RunDirector(
              seed: seed,
              enabled: ElementId.values.toSet(),
              met: {},
              showcase: script,
              fixedFirstHoop: true,
            );
            final ctx = DirectorContext.open(height, bigHoopsMult: 1.5);
            expect(d.firstMeet.due(100), isNull);
            for (var i = 0; i < 20; i++) {
              final slot = d.nextSlot(ctx);
              final gap = d.nextGap(ctx, slot);
              if (script.portalHoops.contains(i)) {
                expect(slot.kind, HoopKindId.portal);
                expect(slot.extra, script.portals.single.theme);
                expect(d.portalAt - i, inInclusiveRange(25, 40));
              }
              if (script.cometHoops.contains(i)) {
                expect(slot.cometHang, isTrue);
                expect(slot.attached.single.kind, ElementId.comet);
              }
              if (script.feverHoops.contains(i)) {
                expect(slot.kind, HoopKindId.fever);
              }
              if (script.bullseyeHoops.contains(i)) {
                expect(slot.kind, HoopKindId.bullseye);
              }
              if (script.portalHoops.contains(i) ||
                  script.cometHoops.contains(i) ||
                  script.feverHoops.contains(i) ||
                  script.bullseyeHoops.contains(i)) {
                expect(slot.forced, isFalse);
                expect(slot.hazardCost, 0);
              }
              for (final item in script.gapItems.where(
                (item) => item.gap == i,
              )) {
                final id = ElementId.fromStorageId(item.id)!;
                expect(
                  gap.items.any(
                    (p) =>
                        p.kind == id ||
                        p.kind == ElementId.capsule &&
                            (p.extra as CapsuleType).element == id,
                  ),
                  isTrue,
                  reason: '$item seed $seed',
                );
              }
              if (script.hearts.contains(i)) {
                expect(gap.items.map((p) => p.kind), contains(ElementId.heart));
              }
            }
          }
        });
      }
    }
  }

  test('B2 normal mix and lifetime gates over 200 seeds', () {
    // A plan with no scripted indices isolates the planner integration:
    // B2 disables first-meet pulls, so the baseline has all elements met.
    const script = ShowcaseRunPlan(highlightId: 'portal', step: 0, attempt: 1);
    for (var games = 0; games <= 5; games++) {
      final enabled = GatesConfig.filter(ElementId.values.toSet(), games);
      if (games < 3) expect(enabled, isNot(contains(ElementId.saw)));
      if (games < 5) expect(enabled, isNot(contains(ElementId.squeeze)));
      for (var seed = 0; seed < 200; seed++) {
        final a = RunDirector(
          seed: seed,
          enabled: enabled,
          met: ElementId.values.toSet(),
        );
        final b = RunDirector(
          seed: seed,
          enabled: enabled,
          met: ElementId.values.toSet(),
          showcase: script,
        );
        final ctx = DirectorContext.open(711);
        for (var i = 0; i < 80; i++) {
          final x = a.nextSlot(ctx), y = b.nextSlot(ctx);
          expect(y, x, reason: 'games $games seed $seed index $i');
          expect(b.nextGap(ctx, y), a.nextGap(ctx, x));
        }
      }
    }
  });
}
