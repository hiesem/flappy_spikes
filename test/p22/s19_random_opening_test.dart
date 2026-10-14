import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';
import '../p231/tuning_23.dart';

/// PRD-2.2 §19: a different opening every run — random first heart, the
/// early random pool, the feather / piece in ≈ 60 % of runs, single pickups
/// at a random spot in their gap. Pure director statistics (500 seeds).
final Set<ElementId> all = ElementId.values.toSet();

RunDirector director(int seed) =>
    RunDirector(seed: seed, enabled: all, met: all);

List<(SlotPlan, GapPlan)> fly(
  RunDirector d,
  int n, {
  DirectorContext Function()? ctx,
}) {
  final out = <(SlotPlan, GapPlan)>[];
  for (var k = 0; k < n; k++) {
    final c = ctx?.call() ?? DirectorContext.open(711);
    final s = d.nextSlot(c);
    out.add((s, d.nextGap(c, s)));
  }
  return out;
}

const singles = {
  ElementId.heart,
  ElementId.shield,
  ElementId.capsule,
  ElementId.egg,
  ElementId.jar,
  ElementId.piggy,
  ElementId.feather,
  ElementId.puzzlePiece,
};

void main() {
  // PRD-2.3.1 §0: the early pool and the feather / piece windows are measured
  // on the 2.3 spawn set (test/p231/tuning_23.dart); the live set has its own
  // checks.
  setUp(() => useTuning(tuning23Spawn()));
  tearDown(resetTuning);
  const seeds = 500;

  test('§19.5 tables: heart (5–27, then 17–27), early pool 4–9 with four '
      'equal options, feather / piece 60 % (PRD-2.3 §14.2: in 10–40)', () {
    final t = DirectorTables.prd2;
    expect(t.heart.first, (5, 27));
    expect(t.heart.then, (17, 27));
    expect(t.featherChance, 0.6);
    expect(t.featherWindow, (10, 40));
    expect(t.pieceChance, 0.6);
    expect(t.pieceWindow, (10, 40));
    expect(t.earlyPool!.from, 4);
    expect(t.earlyPool!.to, 9);
    expect(t.earlyPool!.weights.values.toSet(), {1});
    expect(t.earlyPool!.weights.keys.toSet(), EarlyPick.values.toSet());
  });

  test('§19.1 the first heart spreads over gaps 5–27, no gap above 10 %', () {
    final first = <int, int>{};
    for (var seed = 1; seed <= seeds; seed++) {
      final d = director(seed);
      int? at;
      for (final (s, g) in fly(d, 40)) {
        if (g.items.any((i) => i.kind == ElementId.heart)) {
          at = s.index;
          break;
        }
      }
      expect(at, isNotNull, reason: 'seed $seed');
      // A taken gap pushes it one or two gaps on.
      expect(at!, inInclusiveRange(5, 30), reason: 'seed $seed');
      first[at] = (first[at] ?? 0) + 1;
    }
    expect(first.keys.length, greaterThanOrEqualTo(20));
    for (final e in first.entries) {
      expect(e.value / seeds, lessThanOrEqualTo(.10), reason: 'gap ${e.key}');
    }
  });

  test('§19.2 indices 4–9: one equal-chance draw per index; the first '
      'optional item (index 4) is each pool option ≈ 25 % (± 5)', () {
    final draws = <EarlyPick, int>{};
    final first = <EarlyPick, int>{};
    for (var seed = 1; seed <= seeds; seed++) {
      final d = director(seed);
      final plans = fly(d, 12);
      for (var i = 4; i <= 9; i++) {
        final p = d.earlyPicks[i]!;
        draws[p] = (draws[p] ?? 0) + 1;
      }
      expect(d.earlyPicks.keys.toSet(), {4, 5, 6, 7, 8, 9});
      // What index 4 shows.
      final (s, g) = plans[4];
      final shown = s.kind == HoopKindId.bullseye
          ? EarlyPick.bullseye
          : s.tiltDeg != 0
          ? EarlyPick.angled
          : g.items.any((i) => i.kind == ElementId.starTrail)
          ? EarlyPick.starTrail
          : EarlyPick.nothing;
      first[shown] = (first[shown] ?? 0) + 1;
      if (shown != d.earlyPicks[4]) {
        // Only a scheduled item (the feather / piece) can take the gap.
        expect(d.earlyPicks[4], EarlyPick.starTrail, reason: 'seed $seed');
        expect(
          g.items.map((i) => i.kind),
          anyOf(contains(ElementId.feather), contains(ElementId.puzzlePiece)),
        );
      }
    }
    for (final o in EarlyPick.values) {
      expect(draws[o]! / (6 * seeds), closeTo(.25, .05), reason: '$o draws');
      expect(first[o]! / seeds, closeTo(.25, .05), reason: '$o first');
    }
  });

  test('§19.2 the pool keeps exclusivity and cooldowns: Star Trails ≥ 8 '
      'apart, Bullseyes ≥ 6 apart; from index 10 the normal tables apply',
      () {
    for (var seed = 1; seed <= seeds; seed++) {
      final d = director(seed);
      int? lastTrail, lastBull;
      for (final (s, g) in fly(d, 16)) {
        if (s.kind == HoopKindId.bullseye) {
          if (lastBull != null) {
            expect(s.index - lastBull, greaterThanOrEqualTo(6));
          }
          lastBull = s.index;
        }
        if (g.items.any((i) => i.kind == ElementId.starTrail)) {
          if (lastTrail != null) {
            expect(s.index - lastTrail, greaterThanOrEqualTo(8));
          }
          lastTrail = s.index;
        }
        if (s.index < 4 || s.index > 9) {
          expect(d.earlyPicks[s.index], isNull);
        }
        // Below the regular unlocks only the pool brings them.
        if (s.index < 6 && s.kind == HoopKindId.bullseye) {
          expect(d.earlyPicks[s.index], EarlyPick.bullseye);
        }
        if (s.index < 10 && s.tiltDeg != 0) {
          expect(d.earlyPicks[s.index], EarlyPick.angled);
        }
      }
    }
  });

  test('§19.3 feather in 55–65 % of runs; PRD-2.3 §14.2: at gaps 10–40, the '
      'piece never in the same run (both roll → the feather wins: ≈ 24 %)', () {
    var feathers = 0, pieces = 0;
    for (var seed = 1; seed <= seeds; seed++) {
      final d = director(seed);
      int? f, p;
      for (final (s, g) in fly(d, 60)) {
        for (final it in g.items) {
          if (it.kind == ElementId.feather) {
            expect(f, isNull, reason: 'at most once');
            f = s.index;
          }
          if (it.kind == ElementId.puzzlePiece) {
            expect(p, isNull, reason: 'at most once');
            p = s.index;
          }
        }
      }
      expect(f != null, d.featherThisRun, reason: 'seed $seed');
      expect(p != null, d.pieceThisRun, reason: 'seed $seed');
      // A taken gap pushes it on a little.
      if (f != null) expect(f, inInclusiveRange(10, 44));
      if (p != null) expect(p, inInclusiveRange(10, 44));
      expect(f != null && p != null, isFalse, reason: 'seed $seed');
      if (f != null) feathers++;
      if (p != null) pieces++;
    }
    expect(feathers / seeds, inInclusiveRange(.55, .65));
    expect(pieces / seeds, inInclusiveRange(.18, .30));
  });

  test('§19.5 determinism: the same seed gives the same opening', () {
    for (var seed = 1; seed <= 50; seed++) {
      final a = fly(director(seed), 40);
      final b = fly(director(seed), 40);
      expect(a, b);
    }
    expect(fly(director(1), 40), isNot(fly(director(2), 40)));
  });

  test('§19.4 single pickups sit 30–70 % along the gap and ≤ 50 pt off the '
      'line; patterns keep their shape and stay inside the gap', () {
    var singlesSeen = 0, offLine = 0;
    final kinds = <ElementId>{};
    for (var seed = 1; seed <= 200; seed++) {
      for (final (s, g) in fly(director(seed), 120)) {
        for (final it in g.items) {
          if (singles.contains(it.kind)) {
            singlesSeen++;
            kinds.add(it.kind);
            expect(it.y, isNull, reason: 'on the line, resolved later');
            final u = (it.trackX - s.lastRingX) / RunConfig.spacing;
            expect(u, inInclusiveRange(.3 - 1e-9, .7 + 1e-9));
            expect(it.lineOffset.abs(), lessThanOrEqualTo(50 + 1e-9));
            if (it.lineOffset.abs() > 10) offLine++;
          }
          if (it.kind == ElementId.starTrail) {
            expect(it.trackX - s.lastRingX, RunConfig.starTrailInset);
            expect(
              s.lastRingX + RunConfig.spacing - it.toTrackX!,
              RunConfig.starTrailInset,
            );
          }
        }
      }
    }
    expect(singlesSeen, greaterThan(1000));
    expect(
      kinds,
      containsAll({
        ElementId.heart,
        ElementId.shield,
        ElementId.capsule,
        ElementId.egg,
        ElementId.piggy,
        ElementId.jar,
        ElementId.feather,
        ElementId.puzzlePiece,
      }),
    );
    expect(offLine / singlesSeen, greaterThan(.6), reason: 'spread off line');
    // Patterns: the piggy coins (3 × 45 pt) and the firefly swarm (220 pt)
    // keep their length; their start moves but stays ≥ 40 pt from rings.
    final starts = <double>{};
    for (var seed = 1; seed <= 100; seed++) {
      final d = RunDirector(
        seed: seed,
        enabled: all,
        met: all,
        startHoopIndex: 30,
      );
      for (final (s, g) in fly(
        d,
        3,
        ctx: () => DirectorContext.open(711, piggyRunning: true),
      )) {
        for (final it in g.items.where((i) => i.kind == ElementId.piggyCoins)) {
          expect(it.toTrackX! - it.trackX, closeTo(3 * 45, 1e-9));
          expect(it.trackX - s.lastRingX, greaterThanOrEqualTo(40 - 1e-9));
          expect(
            s.lastRingX + RunConfig.spacing - it.toTrackX!,
            greaterThanOrEqualTo(40 - 1e-9),
          );
          starts.add(it.trackX - s.lastRingX);
        }
      }
      final j = RunDirector(
        seed: seed,
        enabled: all,
        met: all,
        startHoopIndex: 30,
      );
      for (final (s, g) in fly(
        j,
        3,
        ctx: () => DirectorContext.open(711, jarRunning: true),
      )) {
        final sw = g.items.where((i) => i.kind == ElementId.fireflySwarm);
        for (final it in sw) {
          expect(it.toTrackX! - it.trackX, closeTo(220, 1e-9));
          expect(it.trackX - s.lastRingX, greaterThanOrEqualTo(40 - 1e-9));
        }
      }
    }
    expect(starts.length, greaterThan(50), reason: 'the start moves');
  });
}
