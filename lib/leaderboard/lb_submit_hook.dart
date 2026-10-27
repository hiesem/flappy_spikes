import 'dart:math';
import 'package:flutter/foundation.dart';

import '../game/storage.dart';
import '../run/run_summary.dart';
import '../services/integrity_guard.dart';
import '../services/tester.dart';
import '../skins/look.dart';
import '../versus/run_entry.dart';
import 'lb_models.dart';
import 'lb_queue.dart';

/// Run-end adapter, kept outside the shared game bookkeeping seam (J2).
class LbSubmitHook {
  LbSubmitHook(this.queue, this.storage);
  final LbQueue queue;
  final GameStorage storage;
  static final _random = Random.secure();
  static const testerBuild =
      !kReleaseMode || kTester || bool.fromEnvironment('FS_E2E');

  static LbSubmittedRun fromSummary(
    RunSummary summary, {
    required String id,
    required DateTime end,
    required String mode,
    Look look = Look.defaults,
    int? verifiedBest,
    int? bestFloor,
  }) {
    // Local bests may never have reached the server. Until a board read
    // supplies a verified best, keep proof for every positive score (O55).
    final best = verifiedBest ?? 0;
    final notable =
        summary.score > best ||
        summary.score > max(500, best * 2) ||
        (bestFloor != null && bestFloor > 0 && summary.score >= bestFloor);
    final entry = notable
        ? RunEntry.fromSummary(
            summary,
            runId: id,
            name: 'Flappy',
            look: look,
            ts: end,
          )
        : null;
    final include = entry != null && entry.fitsLimits;
    return LbSubmittedRun(
      id: id,
      score: summary.score,
      hoops: summary.hoopsPassed,
      cs: (summary.runSeconds * 100).round(),
      endTs: end.millisecondsSinceEpoch,
      mode: mode,
      tl: include ? entry.tl : null,
      fl: include ? entry.fl : null,
    );
  }

  Future<LbSubmitRunResult?> onRunEnd(
    RunSummary? summary, {
    required bool countsForAchievements,
    required bool countsForUpload,
    required String mode,
    required Look look,
  }) async {
    if (summary != null &&
        countsForAchievements &&
        countsForUpload &&
        IntegrityGuard.instance.trusted) {
      final now = storage.now().toUtc();
      final id =
          '${now.microsecondsSinceEpoch.toRadixString(36)}-${_random.nextInt(1 << 32).toRadixString(36)}';
      await queue.enqueue(
        fromSummary(
          summary,
          id: id,
          end: now,
          mode: mode,
          look: look,
          verifiedBest: queue.service.verifiedBest,
          bestFloor: queue.service.bestFloor,
        ),
        bestCandidate: summary.newBest,
      );
    }
    return queue.flush();
  }
}
