import 'dart:math';

import '../run/config/versus_config.dart';
import 'run_entry.dart';

/// Which rule of §3.13 "Matching" picked the candidates. PRD-2.3 §25.2
/// adds [rematch]: every usable run was met before, so the one met longest
/// ago is replayed.
enum MatchTier { level, any, rematch, solo }

/// What the matcher needs of a pool entry (the fixture's shape).
abstract interface class Matchable {
  String get uid;
  String get runId;
  int get score;
  int get level;

  /// PRD-2.3 §21.4 the hashed Play Games id of the run's player ('' =
  /// none: such runs match as before).
  String get pg;
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
  @override
  String get pg => entry.run.pg;
}

/// PRD-2.3 §21.4 a run that is not mine: not [myUid]'s and, when I have a
/// hashed Play Games id ([myPg]), not one stored under it by another uid
/// (an old anonymous account of mine).
bool isOtherPlayer(Matchable e, {required String myUid, String myPg = ''}) =>
    e.uid != myUid && (myPg.isEmpty || e.pg != myPg);

/// The candidates the client picks from at random (PRD-2 §3.13, PRD-2.3
/// §25.2; mirrors `functions/src/matching.ts` `matchCandidates`). Among the
/// runs that are not mine ([isOtherPlayer]) and not met yet ([met]):
/// 1. a run from a player at [myLevel] with a score below [myBest];
/// 2. otherwise any of them;
/// 3. PRD-2.3 §25.2 when every run that is not mine was met: the one met
///    longest ago ([met] is ordered oldest first), tier
///    [MatchTier.rematch];
/// 4. otherwise solo (the pool holds only my own runs, or nothing).
(MatchTier, List<T>) matchCandidates<T extends Matchable>(
  Iterable<T> pool, {
  required int myLevel,
  required int myBest,
  required String myUid,
  String myPg = '',
  List<String> met = const [],
}) {
  final metSet = met.toSet();
  final open = [
    for (final e in pool)
      if (isOtherPlayer(e, myUid: myUid, myPg: myPg)) e,
  ];
  final fresh = [
    for (final e in open)
      if (!metSet.contains(e.runId)) e,
  ];
  final atLevel = [
    for (final e in fresh)
      if (e.level == myLevel && e.score < myBest) e,
  ];
  if (atLevel.isNotEmpty) return (MatchTier.level, atLevel);
  if (fresh.isNotEmpty) return (MatchTier.any, fresh);
  final oldest = metLongestAgo(open, met: met);
  if (oldest != null) {
    return (MatchTier.rematch, [open.firstWhere((e) => e.runId == oldest)]);
  }
  return (MatchTier.solo, <T>[]);
}

/// PRD-2.3 §25.2 the run id in [pool] that was met longest ago (the
/// lowest index in [met], oldest first); null when [pool] holds none.
String? metLongestAgo(Iterable<Matchable> pool, {required List<String> met}) {
  final ids = {for (final e in pool) e.runId};
  for (final id in met) {
    if (ids.contains(id)) return id;
  }
  return null;
}

/// One random candidate of [matchCandidates], or null (solo).
T? pickOpponent<T extends Matchable>(
  Iterable<T> pool, {
  required int myLevel,
  required int myBest,
  required String myUid,
  String myPg = '',
  List<String> met = const [],
  required Random r,
}) {
  final (_, c) = matchCandidates(
    pool,
    myLevel: myLevel,
    myBest: myBest,
    myUid: myUid,
    myPg: myPg,
    met: met,
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

/// Whether [pool] holds a usable opponent: a run that is not mine
/// ([isOtherPlayer]); exactly when [matchCandidates] is not solo. PRD-2.3
/// §25.2: met runs count too (a rematch beats a solo run).
bool hasUsableOpponent(
  Iterable<Matchable> pool, {
  required String myUid,
  String myPg = '',
}) => pool.any((e) => isOtherPlayer(e, myUid: myUid, myPg: myPg));

/// PRD-2.3 §25.2 whether [pool] holds a usable run not met yet (the search
/// stops at the first round with one).
bool hasFreshOpponent(
  Iterable<Matchable> pool, {
  required String myUid,
  String myPg = '',
  List<String> met = const [],
}) {
  final m = met.toSet();
  return pool.any(
    (e) => isOtherPlayer(e, myUid: myUid, myPg: myPg) && !m.contains(e.runId),
  );
}

/// The outcome of [searchPools].
class PoolSearch<T> {
  const PoolSearch({
    required this.poolId,
    required this.pool,
    required this.reads,
    this.timedOut = false,
  });

  /// The pool document with the chosen opponent (null = none).
  final String? poolId;

  /// That document's entries (empty when [poolId] is null).
  final List<T> pool;

  /// Pool documents read.
  final int reads;

  /// The search stopped because its time limit was hit.
  final bool timedOut;

  bool get found => poolId != null;
}

/// PRD-2.2 §3 / PRD-2.3 §25.2 reads the pools in [order] in rounds of
/// [parallel] documents at the same time (the 4 shards of a level, then
/// the next level's 4, …: about 11 rounds instead of 44 sequential reads)
/// and stops after the first round holding a usable run not met yet
/// ([hasFreshOpponent]; the first such document in [order] wins). When the
/// whole search finds only met runs, the document holding the one met
/// longest ago is the result (a rematch); solo only when no document holds
/// a run that is not mine. At most [maxReads] reads.
///
/// Before every round [expired] is asked: true stops the search as timed
/// out (a met fallback found so far is still returned, as found). [onRead]
/// gets the running count as each read is issued (PRD-2.3 §25.2 item 4: a
/// `timeout` reports the real count). A [read] that throws ends the search
/// with that error after its round, unless a met fallback is known (the
/// caller maps it to a `versus_solo` reason). Mirrors `matching.ts`
/// `searchPools`.
Future<PoolSearch<T>> searchPools<T extends Matchable>({
  required List<String> order,
  required Future<List<T>> Function(String id) read,
  required String myUid,
  String myPg = '',
  List<String> met = const [],
  int maxReads = VersusConfig.maxSearchReads,
  int parallel = VersusConfig.shards,
  bool Function()? expired,
  void Function(int reads)? onRead,
}) async {
  var reads = 0;
  String? fallbackId;
  List<T> fallbackPool = const [];
  var fallbackAge = 1 << 30;
  final metIndex = <String, int>{
    for (var i = 0; i < met.length; i++) met[i]: i,
  };
  PoolSearch<T> result({bool timedOut = false}) => fallbackId == null
      ? PoolSearch(
          poolId: null,
          pool: const [],
          reads: reads,
          timedOut: timedOut,
        )
      : PoolSearch(poolId: fallbackId, pool: fallbackPool, reads: reads);

  final step = max(1, parallel);
  for (var i = 0; i < order.length; i += step) {
    if (reads >= maxReads) break;
    if (expired?.call() ?? false) return result(timedOut: true);
    final round = order
        .sublist(i, min(i + step, order.length))
        .take(maxReads - reads)
        .toList();
    final pending = <Future<(List<T>?, Object?, StackTrace?)>>[];
    for (final id in round) {
      reads++;
      onRead?.call(reads);
      pending.add(
        Future(() => read(id)).then<(List<T>?, Object?, StackTrace?)>(
          (v) => (v, null, null),
          onError: (Object e, StackTrace s) => (null, e, s),
        ),
      );
    }
    final results = await Future.wait(pending);
    for (var k = 0; k < round.length; k++) {
      final entries = results[k].$1;
      if (entries != null &&
          hasFreshOpponent(entries, myUid: myUid, myPg: myPg, met: met)) {
        return PoolSearch(poolId: round[k], pool: entries, reads: reads);
      }
    }
    for (var k = 0; k < round.length; k++) {
      final entries = results[k].$1;
      if (entries == null) continue;
      for (final e in entries) {
        if (!isOtherPlayer(e, myUid: myUid, myPg: myPg)) continue;
        final age = metIndex[e.runId];
        if (age != null && age < fallbackAge) {
          fallbackAge = age;
          fallbackId = round[k];
          fallbackPool = entries;
        }
      }
    }
    if (fallbackId == null) {
      for (final r in results) {
        final e = r.$2;
        if (e != null) Error.throwWithStackTrace(e, r.$3 ?? StackTrace.current);
      }
    }
  }
  return result();
}
