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

/// The pool document read first (own level, random shard) and the fallback
/// on a miss (a random shard of a random other level), as
/// `functions/src/matching.ts` `poolReadPlan`.
({String first, String fallback}) poolReadPlan(int level, Random r) {
  const shards = VersusConfig.shards;
  const maxLevel = VersusConfig.maxLevel;
  final first = poolId(level.clamp(0, maxLevel), r.nextInt(shards));
  var other = r.nextInt(maxLevel); // 0..maxLevel-1
  if (other >= level) other++;
  return (first: first, fallback: poolId(other, r.nextInt(shards)));
}
