import '../game/storage.dart';
import '../run/config/versus_config.dart';
import 'run_entry.dart';

/// What happened to a run offered to the [UploadQueue] (§3.13 upload rules).
enum UploadDecision {
  /// Queued; it counts against today's 3 (a non-best run).
  queued,

  /// Queued; a new best is always uploaded and does not count.
  queuedBest,

  /// Score under 3: never uploaded.
  lowScore,

  /// The 3 non-best uploads of this UTC day are used up.
  dailyCap,

  /// Too long for the rules' size limits.
  tooLong,
}

/// The outcome of one write attempt (the backend's verdict).
enum UploadWrite {
  /// Written: drop it from the queue.
  done,

  /// Offline / timeout / transient: keep it and retry later.
  retry,

  /// Refused for good (rules / shape): drop it so it never blocks the queue.
  drop,
}

/// §3.13 the persisted upload queue (`uploadQueue`, `uploadsToday` +
/// `uploadsDay` in `storage.dart`, §7 table): a new best is always queued;
/// other runs at most 3 per **UTC** day (the server counts per UTC day,
/// `functions/src/schema.ts` `utcDay`); runs under score 3 never. [flush]
/// writes **one run per write** (ARCH §6.1 write contract), oldest first,
/// and stops at the first transient failure (retried on the next flush).
///
/// (S6-60) The server's rate counts runs by the UTC day it *processes*
/// them, so [flush] also paces the non-best writes by the upload day
/// (`uploadsSent` + `uploadsSentDay`): at most 3 a UTC day. Non-best runs
/// over that stay queued (a new best still goes out) and are written on a
/// later day, instead of being rejected for `rate` and lost. The cap of
/// [VersusConfig.queueCap] still evicts the oldest non-best first.
class UploadQueue {
  UploadQueue(this.storage, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final GameStorage storage;
  final DateTime Function() _clock;
  bool _flushing = false;

  /// 'YYYY-MM-DD' of [t] in UTC (schema.ts `utcDay`).
  static String utcDay(DateTime t) =>
      t.toUtc().toIso8601String().substring(0, 10);

  String get today => utcDay(_clock());

  /// Non-best runs queued today (0 on a new UTC day).
  int get uploadsToday =>
      storage.uploadsDay == today ? storage.uploadsToday : 0;

  /// (S6-60) Non-best runs written today, UTC (0 on a new UTC day).
  int get sentToday =>
      storage.uploadsSentDay == today ? storage.uploadsSent : 0;

  /// The pending runs, oldest first (unreadable entries are skipped).
  List<QueuedRun> get pending => [
    for (final s in storage.uploadQueue) ?QueuedRun.fromJson(s),
  ];

  bool get isEmpty => storage.uploadQueue.isEmpty;

  /// Applies the §3.13 upload rules to [entry] and queues it when allowed.
  Future<UploadDecision> offer(RunEntry entry, {required bool newBest}) async {
    if (entry.score < VersusConfig.minUploadScore) {
      return UploadDecision.lowScore;
    }
    if (!entry.fitsLimits) return UploadDecision.tooLong;
    if (!newBest) {
      final used = uploadsToday;
      if (used >= VersusConfig.dailyUploads) return UploadDecision.dailyCap;
      await storage.saveUploadsToday(today, used + 1);
    }
    final queue = [...storage.uploadQueue, QueuedRun(entry, newBest: newBest).toJson()];
    // Cap: drop the oldest non-best entries first (a best is kept longest).
    while (queue.length > VersusConfig.queueCap) {
      final i = queue.indexWhere((s) => QueuedRun.fromJson(s)?.newBest != true);
      queue.removeAt(i < 0 ? 0 : i);
    }
    await storage.saveUploadQueue(queue);
    return newBest ? UploadDecision.queuedBest : UploadDecision.queued;
  }

  /// Writes the queue one run per [write] call, oldest first, at most
  /// [VersusConfig.dailyUploads] non-best runs per UTC upload day (the rest
  /// wait for a later day, S6-60). Returns how many were written.
  /// Re-entrant calls while a flush runs return 0.
  Future<int> flush(Future<UploadWrite> Function(QueuedRun run) write) async {
    if (_flushing) return 0;
    _flushing = true;
    var written = 0;
    try {
      var i = 0;
      while (i < storage.uploadQueue.length) {
        final head = storage.uploadQueue[i];
        final run = QueuedRun.fromJson(head);
        if (run != null &&
            !run.newBest &&
            sentToday >= VersusConfig.dailyUploads) {
          // Today's server allowance is used: keep it for a later day.
          i++;
          continue;
        }
        var verdict = UploadWrite.drop;
        if (run != null) {
          try {
            verdict = await write(run);
          } catch (_) {
            verdict = UploadWrite.retry;
          }
        }
        if (verdict == UploadWrite.retry) break;
        final rest = [...storage.uploadQueue];
        rest.remove(head);
        await storage.saveUploadQueue(rest);
        if (verdict == UploadWrite.done) {
          written++;
          if (run != null && !run.newBest) {
            await storage.saveUploadsSent(today, sentToday + 1);
          }
        }
      }
    } finally {
      _flushing = false;
    }
    return written;
  }

  /// "Delete my data" (§3.13 / ARCH §5): empties the queue and the counter.
  Future<void> clear() async {
    await storage.saveUploadQueue(const []);
    await storage.saveUploadsToday('', 0);
    await storage.saveUploadsSent('', 0);
  }
}
