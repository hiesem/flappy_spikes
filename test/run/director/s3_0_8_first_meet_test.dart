import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/director/first_meet.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../p231/tuning_23.dart';

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

/// PRD-2.2 §19.2 / PRD-2.6 §D2 the early pool may show Bullseye and the
/// Star Trail from index 4 (before their normal unlock); the first meet
/// itself is unchanged.
int earliest(ElementId e) => switch (e) {
  ElementId.bullseye ||
  ElementId.starTrail => DirectorTables.prd2.earlyPool!.from,
  _ => e.firstPossible!,
};

/// The slot / gap at [index] showed [e] because of the §19.2 early pool.
bool fromPool(RunDirector d, ElementId e, int index) =>
    switch (d.earlyPicks[index]) {
      EarlyPick.bullseye => e == ElementId.bullseye,
      EarlyPick.starTrail => e == ElementId.starTrail,
      _ => false,
    };

void main() {
  final firstMeet = ElementId.values.where((e) => e.firstMeet).toList();

  group('§3.0.8 first-meet guarantee', () {
    // PRD-2.3.1 §0: the live set (RC v21) opens most rows before their
    // static first-meet index, so the elements come naturally before the
    // guarantee is due. The guarantee is measured on the 2.3 spawn set.
    setUp(() => useTuning(tuning23Spawn()));
    tearDown(resetTuning);
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
          expect(at!, greaterThanOrEqualTo(earliest(e)));
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
          expect(
            first[e],
            isNotNull,
            reason: 'seed $seed never met ${e.storageId}',
          );
          expect(first[e]!, greaterThanOrEqualTo(earliest(e)));
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
      // PRD-2.2 §19.2: the early pool may still draw it (not a force).
      for (var k = 0; k < 8; k++) {
        final ctx = DirectorContext.open(711);
        final s = d.nextSlot(ctx);
        final g = d.nextGap(ctx, s);
        if (shown(s, g).contains(ElementId.bullseye)) {
          expect(fromPool(d, ElementId.bullseye, s.index), isTrue);
          expect(s.forced, isFalse);
        }
      }
    });

    test('§3.0.8 one forced element at a time, oldest unlock first', () {
      final fm = FirstMeet({}, {
        ElementId.bullseye,
        ElementId.train,
        ElementId.starTrail,
      });
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
      for (final e in [
        ElementId.squeeze,
        ElementId.feather,
        ElementId.puzzlePiece,
      ]) {
        expect(e.firstMeet, isFalse);
      }
    });
  });
}
