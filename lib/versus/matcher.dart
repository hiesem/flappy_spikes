import 'dart:math';

import '../run/config/versus_config.dart';
import 'run_entry.dart';

/// Which rule of §3.13 "Matching" picked the candidates.
enum MatchTier { level, any, solo }

/// What the matcher needs of a pool entry (the fixture's shape).
abstract interface class Matchable {
  String get uid;
  String get runId;
  int get score;
  int get level;
}

/// A [PoolEntry] as a [Matchable].
class PoolCandidate implements Matchable {
  const PoolCandidate(this.entry);
  final PoolEntry entry;
  @override
  String get uid => entry.uid;
  @override
  String get runId => entry.runId;
  @override
  int get score => entry.score;
  @override
  int get level => entry.level;
}

/// The candidates the client picks from at random (PRD-2 §3.13, mirrors
/// `functions/src/matching.ts` `matchCandidates`):
/// 1. a run from a player at [myLevel] with a score below [myBest];
/// 2. otherwise any run;
/// 3. otherwise solo.
/// Never [myUid]'s runs; never a run in [seen] (met this session).
(MatchTier, List<T>) matchCandidates<T extends Matchable>(
  Iterable<T> pool, {
  required int myLevel,
  required int myBest,
  required String myUid,
  Set<String> seen = const {},
}) {
  final open = [
    for (final e in pool)
      if (e.uid != myUid && !seen.contains(e.runId)) e,
  ];
  final atLevel = [
    for (final e in open)
      if (e.level == myLevel && e.score < myBest) e,
  ];
  if (atLevel.isNotEmpty) return (MatchTier.level, atLevel);
  if (open.isNotEmpty) return (MatchTier.any, open);
  return (MatchTier.solo, <T>[]);
}

/// One random candidate of [matchCandidates], or null (solo).
T? pickOpponent<T extends Matchable>(
  Iterable<T> pool, {
  required int myLevel,
  required int myBest,
  required String myUid,
  Set<String> seen = const {},
  required Random r,
}) {
  final (_, c) = matchCandidates(
    pool,
    myLevel: myLevel,
    myBest: myBest,
    myUid: myUid,
    seen: seen,
  );
  if (c.isEmpty) return null;
  return c[r.nextInt(c.length)];
}

/// `pools/{level}_{shard}` document id (schema.ts `poolId`).
String poolId(int level, int shard) => '${level}_$shard';

/// The pool documents of [level] (every shard), in random order.
List<String> _shardsOf(int level, Random r) {
  final shards = [for (var i = 0; i < VersusConfig.shards; i++) i]..shuffle(r);
  return [for (final s in shards) poolId(level, s)];
}

/// PRD-2.2 §3 the opponent search order (replaces the 2.1 `poolReadPlan`):
/// all shards of the player's own [level] in random order, then the other
/// levels nearest first (distance 1, 2, … up to [VersusConfig.maxLevel];
/// at each distance the lower level before the higher one), every shard of
/// each level in random order. Every pool document exactly once, so at
/// most [VersusConfig.maxSearchReads] (44) ids. Mirrors
/// `functions/src/matching.ts` `poolSearchOrder`.
List<String> poolSearchOrder(int level, Random r) {
  const maxLevel = VersusConfig.maxLevel;
  final own = level.clamp(0, maxLevel);
  final order = _shardsOf(own, r);
  for (var d = 1; d <= maxLevel; d++) {
    for (final l in [own - d, own + d]) {
      if (l >= 0 && l <= maxLevel) order.addAll(_shardsOf(l, r));
    }
  }
  return order;
}

/// Whether [pool] holds a usable opponent: one that is not [myUid]'s and
/// not met this session ([seen]) — exactly when [matchCandidates] is not
/// solo.
bool hasUsableOpponent(
  Iterable<Matchable> pool, {
  required String myUid,
  Set<String> seen = const {},
}) => pool.any((e) => e.uid != myUid && !seen.contains(e.runId));

/// The outcome of [searchPools].
class PoolSearch<T> {
  const PoolSearch({
    required this.poolId,
    required this.pool,
    required this.reads,
    this.timedOut = false,
  });

  /// The pool document with the first usable opponent (null = none).
  final String? poolId;

  /// That document's entries (empty when [poolId] is null).
  final List<T> pool;

  /// Pool documents read.
  final int reads;

  /// The search stopped because its time limit was hit.
  final bool timedOut;

  bool get found => poolId != null;
}

/// PRD-2.2 §3 reads the pools in [order] and stops at the first one with a
/// usable opponent ([hasUsableOpponent]); at most [maxReads] reads. Before
/// every read [expired] is asked: true stops the search as timed out. A
/// [read] that throws ends the search with that error (the caller maps it
/// to a `versus_solo` reason). Mirrors `matching.ts` `searchPools`.
Future<PoolSearch<T>> searchPools<T extends Matchable>({
  required List<String> order,
  required Future<List<T>> Function(String id) read,
  required String myUid,
  Set<String> seen = const {},
  int maxReads = VersusConfig.maxSearchReads,
  bool Function()? expired,
  void Function(int reads)? onRead,
}) async {
  var reads = 0;
  for (final id in order) {
    if (reads >= maxReads) break;
    if (expired?.call() ?? false) {
      return PoolSearch(poolId: null, pool: const [], reads: reads, timedOut: true);
    }
    reads++;
    onRead?.call(reads);
    final entries = await read(id);
    if (hasUsableOpponent(entries, myUid: myUid, seen: seen)) {
      return PoolSearch(poolId: id, pool: entries, reads: reads);
    }
  }
  return PoolSearch(poolId: null, pool: const [], reads: reads);
}
