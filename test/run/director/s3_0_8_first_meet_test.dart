import 'package:flappy_spikes/run/director/first_meet.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

/// The elements a slot / gap plan shows (incl. modifiers and capsule types).
Set<ElementId> shown(SlotPlan s, GapPlan g) => {
  s.element,
  if (s.tiltDeg != 0) ElementId.angledRing,
  if (s.motion != null) ElementId.movingRing,
  for (final a in s.attached) a.kind,
  for (final it in g.items) ...{
    it.kind,
    if (it.extra case final CapsuleType c) c.element,
  },
};

/// Index of the first slot / gap that shows [e] (or null within [n]).
int? firstShown(RunDirector d, ElementId e, {int n = 120}) {
  for (var k = 0; k < n; k++) {
    final ctx = DirectorContext.open(711);
    final s = d.nextSlot(ctx);
    final g = d.nextGap(ctx, s);
    if (shown(s, g).contains(e)) return s.index;
  }
  return null;
}

void main() {
  final firstMeet = ElementId.values.where((e) => e.firstMeet).toList();

  group('§3.0.8 first-meet guarantee', () {
    for (final e in firstMeet) {
      test('§3.0.8 never-met ${e.storageId} is forced within 5 slots / gaps of '
          'hoop ${e.firstPossible}', () {
        for (var seed = 1; seed <= 25; seed++) {
          final d = RunDirector(
            seed: seed,
            enabled: {
              ElementId.normalHoop,
              e,
              if (e.isCapsuleType) ElementId.capsule,
            },
            met: {},
          );
          final at = firstShown(d, e);
          expect(at, isNotNull, reason: 'seed $seed');
          expect(at!, greaterThanOrEqualTo(e.firstPossible!));
          expect(
            at - e.firstPossible!,
            lessThanOrEqualTo(5),
            reason: 'seed $seed: ${e.storageId} at $at',
          );
        }
      });
    }

    test('§3.0.8 every element is met in a full run with all elements on '
        '(one at a time, oldest unlock first)', () {
      for (var seed = 1; seed <= 30; seed++) {
        final d = RunDirector(
          seed: seed,
          enabled: ElementId.values.toSet(),
          met: {},
        );
        final first = <ElementId, int>{};
        for (var k = 0; k < 200; k++) {
          final ctx = DirectorContext.open(711);
          final s = d.nextSlot(ctx);
          final g = d.nextGap(ctx, s);
          for (final e in shown(s, g)) {
            first.putIfAbsent(e, () => s.index);
          }
        }
        for (final e in firstMeet) {
          expect(first[e], isNotNull, reason: 'seed $seed never met ${e.storageId}');
          expect(first[e]!, greaterThanOrEqualTo(e.firstPossible!));
        }
        expect(d.firstMeet.met, containsAll(firstMeet));
      }
    });

    test('§3.0.8 a met element is never forced (normal weights only)', () {
      // Bullseye met: with the special budget 0 below hoop 8 it can only
      // come by a forced first meet — and it must not.
      final d = RunDirector(
        seed: 3,
        enabled: {ElementId.normalHoop, ElementId.bullseye},
        met: {ElementId.bullseye},
      );
      expect(firstShown(d, ElementId.bullseye, n: 8), isNull);
    });

    test('§3.0.8 one forced element at a time, oldest unlock first', () {
      final fm = FirstMeet(
        {},
        {ElementId.bullseye, ElementId.train, ElementId.starTrail},
      );
      expect(fm.due(4), isNull);
      expect(fm.due(5), ElementId.starTrail);
      expect(fm.due(9), ElementId.starTrail, reason: 'still the head');
      fm.markMet(ElementId.starTrail);
      expect(fm.due(9), ElementId.bullseye);
      fm.markMet(ElementId.bullseye);
      expect(fm.due(9), ElementId.train);
      fm.markMet(ElementId.train);
      expect(fm.due(50), isNull);
    });

    test('§3.0.8 a head stuck past its patience goes behind the others', () {
      final fm = FirstMeet({}, {ElementId.shield, ElementId.jar});
      expect(fm.due(12), ElementId.shield);
      expect(fm.due(15), ElementId.shield);
      expect(fm.due(12 + FirstMeet.patience + 1), ElementId.jar);
    });

    test('§3.0.8 the squeeze, the feather and the piece are never forced', () {
      for (final e in [ElementId.squeeze, ElementId.feather, ElementId.puzzlePiece]) {
        expect(e.firstMeet, isFalse);
      }
    });
  });
}
