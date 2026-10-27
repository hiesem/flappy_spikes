import 'dart:math';

import '../game/storage.dart';
import '../run/run_summary.dart';
import 'matcher.dart';
import 'opponent.dart';

/// PRD-2.6 E5: the staircase is independent of best-score pool brackets.
const duelStepStart = -2;

enum DuelTier { band, closest, rematch, solo }

int duelStepAfter(int step, DuelResult result) =>
    (step +
            switch (result) {
              DuelResult.win => 1,
              DuelResult.lose => -2,
              DuelResult.draw => 0,
            })
        .clamp(-4, 8);

double duelMedian(List<int> recentScores) {
  final scores = recentScores.skip(max(0, recentScores.length - 10)).toList()
    ..sort();
  if (scores.isEmpty) return 0;
  final mid = scores.length ~/ 2;
  return scores.length.isOdd
      ? scores[mid].toDouble()
      : (scores[mid - 1] + scores[mid]) / 2;
}

// Like matching.ts, retain the integer factor in tenths through band checks.
// An even history can have a half-integer median, which is exact in binary.
double _targetTenths(int step, List<int> scores) =>
    (8 + step).clamp(4, 16) * duelMedian(scores);

double duelTarget(int step, List<int> recentScores) =>
    _targetTenths(step, recentScores) / 10;

class DuelPick<T extends Matchable> {
  const DuelPick(this.tier, this.entry, this.target);
  final DuelTier tier;
  final T? entry;
  final double target;
}

DuelPick<T> pickDuelOpponent<T extends Matchable>(
  Iterable<T> pool, {
  required String myUid,
  String myPg = '',
  int step = duelStepStart,
  required List<int> recentScores,
  List<String> met = const [],
  required Random r,
}) {
  final tenths = _targetTenths(step, recentScores);
  final target = tenths / 10;
  final seen = met.toSet();
  final open = pool
      .where((e) => isOtherPlayer(e, myUid: myUid, myPg: myPg))
      .toList();
  final fresh = open.where((e) => !seen.contains(e.runId)).toList();
  final band = fresh
      .where((e) => e.score >= 3 * tenths / 40 && e.score <= 5 * tenths / 40)
      .toList();
  if (band.isNotEmpty) {
    return DuelPick(DuelTier.band, band[r.nextInt(band.length)], target);
  }
  if (fresh.isNotEmpty) {
    var closest = fresh.first;
    for (final e in fresh.skip(1)) {
      if ((e.score - target).abs() < (closest.score - target).abs()) {
        closest = e;
      }
    }
    return DuelPick(DuelTier.closest, closest, target);
  }
  final oldest = metLongestAgo(open, met: met);
  if (oldest != null) {
    return DuelPick(
      DuelTier.rematch,
      open.firstWhere((e) => e.runId == oldest),
      target,
    );
  }
  return DuelPick(DuelTier.solo, null, target);
}

/// Session-only selection metadata follows the actual opponent through prefetch.
/// It is deliberately neither uploaded nor added to the ghost schema.
class DuelMatchInfo {
  const DuelMatchInfo({
    required this.tier,
    required this.step,
    required this.target,
  });
  final DuelTier tier;
  final int step;
  final double target;
  bool get first => tier != DuelTier.rematch;
}

final _matchInfo = Expando<DuelMatchInfo>('duel match');
void setDuelMatchInfo(OpponentRun opponent, DuelMatchInfo info) =>
    _matchInfo[opponent] = info;
DuelMatchInfo? duelMatchInfo(OpponentRun opponent) => _matchInfo[opponent];

/// One run-end seam for all modes. Debug/killed runs never move the staircase
/// or its score history. Storage setters update memory before their first await.
Future<void> recordDuelRun(
  GameStorage storage,
  RunSummary summary, {
  required bool counts,
}) async {
  if (!counts) return;
  final scores = [...storage.recentScores, summary.score];
  final writes = <Future<void>>[
    storage.saveRecentScores(scores.skip(max(0, scores.length - 10)).toList()),
    if (summary.opponent != null && summary.duel != null)
      storage.saveDuelStep(duelStepAfter(storage.duelStep, summary.duel!)),
  ];
  await Future.wait(writes);
}
