import 'dart:math';

/// The seeded random streams of one run (PRD-2 §3.0.3, §7; ARCH §2.2).
///
/// - [layout]: heights, kinds, items, pair rewards, spin prize, designs.
/// - [timing]: rolls that happen on the clock (squeeze moments and holds,
///   Big Hoops D, capsule durations, puzzle bonus, balloon prizes), so the
///   slot sequence never depends on when they happen.
/// - [cosmetic]: visual variety only — never changes spawns.
class RunRandom {
  RunRandom(this.seed)
    : layout = Random(seed),
      timing = Random(seed ^ 0x5bd1e995),
      cosmetic = Random(seed ^ 0x9e3779b9);

  final int seed;
  final Random layout;
  final Random timing;
  final Random cosmetic;

  /// Uniform in [a, b).
  static double range(Random r, double a, double b) =>
      a + (b - a) * r.nextDouble();

  /// Uniform integer in [a, b] (both inclusive).
  static int rangeInt(Random r, int a, int b) => a + r.nextInt(b - a + 1);

  /// Picks a key by weight (entries with weight ≤ 0 are ignored). Iterates
  /// in the map's insertion order, so it is deterministic for a const map.
  /// Returns null for an empty / all-zero map.
  static T? pickWeighted<T>(Random r, Map<T, num> weights) {
    var total = 0.0;
    for (final w in weights.values) {
      if (w > 0) total += w;
    }
    if (total <= 0) return null;
    var s = total * r.nextDouble();
    T? last;
    for (final e in weights.entries) {
      if (e.value <= 0) continue;
      last = e.key;
      s -= e.value;
      if (s < 0) return e.key;
    }
    return last;
  }
}
