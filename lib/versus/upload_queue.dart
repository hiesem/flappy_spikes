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

  /// Writes the queue one run per [write] call, oldest first. Returns how
  /// many were written. Re-entrant calls while a flush runs return 0.
  Future<int> flush(Future<UploadWrite> Function(QueuedRun run) write) async {
    if (_flushing) return 0;
    _flushing = true;
    var written = 0;
    try {
      while (storage.uploadQueue.isNotEmpty) {
        final head = storage.uploadQueue.first;
        final run = QueuedRun.fromJson(head);
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
        if (verdict == UploadWrite.done) written++;
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
  }
}
