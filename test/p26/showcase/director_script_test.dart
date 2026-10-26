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

  test('B3 the next portal actually resumes at the re-seeded slot', () {
    for (final step in [0, 2]) {
      for (var attempt = 1; attempt <= 3; attempt++) {
        final script = ShowcaseScript.planFor(step, attempt);
        for (var seed = 0; seed < 200; seed++) {
          final d = RunDirector(
            seed: seed,
            enabled: ElementId.values.toSet(),
            met: ElementId.values.toSet(),
            showcase: script,
          );
          final ctx = DirectorContext.open(711);
          int? resumed;
          final portals = <int>[];
          for (var i = 0; i < 60; i++) {
            final slot = d.nextSlot(ctx);
            d.nextGap(ctx, slot);
            if (slot.kind == HoopKindId.portal) portals.add(i);
            if (script.portalHoops.contains(i)) resumed = d.portalAt;
            if (resumed == i) break;
          }
          expect(resumed! - script.portalHoops.last, inInclusiveRange(25, 40));
          expect(portals, [script.portalHoops.single, resumed]);
        }
      }
    }
  });

  test('B2 normal mix and lifetime gates over 200 seeds', () {
    for (var games = 0; games <= 5; games++) {
      final enabled = GatesConfig.filter(ElementId.values.toSet(), games);
      if (games < 3) expect(enabled, isNot(contains(ElementId.saw)));
      if (games < 5) expect(enabled, isNot(contains(ElementId.squeeze)));
      for (var step = 0; step < 3; step++) {
        for (var attempt = 1; attempt <= 3; attempt++) {
          final script = ShowcaseScript.planFor(step, attempt);
          final highlights = [
            ...script.portalHoops,
            ...script.cometHoops,
            ...script.feverHoops,
          ];
          for (var seed = 0; seed < 200; seed++) {
            final a = RunDirector(
              seed: seed,
              enabled: enabled,
              met: ElementId.values.toSet(),
              fixedFirstHoop: true,
            );
            final b = RunDirector(
              seed: seed,
              enabled: enabled,
              met: ElementId.values.toSet(),
              fixedFirstHoop: true,
              showcase: script,
            );
            final ctx = DirectorContext.open(711, bigHoopsMult: 1.5);
            for (var i = 0; i < 80; i++) {
              final x = a.nextSlot(ctx), y = b.nextSlot(ctx);
              final gx = a.nextGap(ctx, x), gy = b.nextGap(ctx, y);
              final headline = highlights.any((at) => (i - at).abs() < 8);
              final scriptedSlot = [
                ...highlights,
                ...script.bullseyeHoops,
              ].contains(i);
              // The replacement portal schedule may change portal decisions,
              // but never the normal geometry or later random draws.
              final portal =
                  x.kind == HoopKindId.portal || y.kind == HoopKindId.portal;
              final reason =
                  'step $step A=$attempt games $games seed $seed i=$i';
              if (!headline && !scriptedSlot && !portal) {
                expect(y, x, reason: reason);
              }
              final scriptedGap =
                  script.hearts.contains(i) ||
                  script.gapItems.any((item) => item.gap == i);
              if (!headline && !scriptedGap) expect(gy, gx, reason: reason);
            }
          }
        }
      }
    }
  });
}
