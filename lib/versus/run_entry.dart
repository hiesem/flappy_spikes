import 'dart:convert';

import '../levels/levels.dart';
import '../run/config/versus_config.dart';
import '../run/run_summary.dart';
import '../skins/catalog.dart';
import '../skins/look.dart';
import 'opponent.dart';
import 'timeline.dart';

/// One run as the client stores it in `players/{uid}` and the server copies
/// into a pool (PRD-2 §3.13, ARCH §6.1 `RunEntry`; mirrors
/// `functions/src/schema.ts`). Exactly the 11 keys the rules accept.
///
/// `ts` is a plain [DateTime] here; the Firestore backend converts it to a
/// `Timestamp` on write and back on read (this file stays plugin-free).
class RunEntry {
  const RunEntry({
    required this.runId,
    required this.score,
    required this.best,
    required this.ts,
    required this.name,
    this.avatar = '',
    this.look = Look.defaults,
    this.platform = 'android',
    required this.tl,
    required this.end,
    required this.fl,
  });

  /// §3.13 the entry for a finished run: `best` = the player's best at
  /// upload (the run's `bestAfter`), the timeline from the recorder.
  factory RunEntry.fromSummary(
    RunSummary s, {
    required String runId,
    required String name,
    String avatar = '',
    Look look = Look.defaults,
    String platform = 'android',
    required DateTime ts,
  }) => RunEntry(
    runId: runId,
    score: s.score,
    best: s.bestAfter < s.score ? s.score : s.bestAfter,
    ts: ts,
    name: clampName(name),
    avatar: avatar.length > VersusConfig.avatarMax ? '' : avatar,
    look: look,
    platform: platform,
    tl: s.timeline.encodeTl(),
    end: s.timeline.endCs.clamp(0, 0xFFFF),
    fl: s.timeline.encodeFlags(),
  );

  final String runId;
  final int score;
  final int best;
  final DateTime ts;
  final String name;
  final String avatar;
  final Look look;

  /// 'android' | 'ios' (analytics only, never used for matching).
  final String platform;

  /// base64 of uint16 LE centisecond deltas, one per timeline entry.
  final String tl;

  /// cs from the last point to the death.
  final int end;

  /// Timeline format v2 (PRD-2.2 §13.5): base64 of the version byte 2,
  /// then per entry the flag byte (ride 1 | train 2 | gift 4 | bonus 8 | puzzle 16) and
  /// the entry's value (uint16 LE). The values sum to [score].
  final String fl;

  RunTimeline get timeline => RunTimeline.decode(tl, fl, end);

  /// The rules' size limits (ARCH §6.1): a longer timeline cannot be
  /// uploaded (≈ 6 000 points).
  bool get fitsLimits =>
      runId.isNotEmpty &&
      runId.length <= 64 &&
      tl.length <= VersusConfig.tlMax &&
      fl.length <= VersusConfig.flMax;

  /// The 11 fields; [ts] is written as given ([DateTime] by default; the
  /// backend passes a `Timestamp`, the queue JSON passes epoch ms).
  Map<String, Object?> toMap({Object? ts}) => {
    'runId': runId,
    'score': score,
    'best': best,
    'ts': ts ?? this.ts,
    'name': name,
    'avatar': avatar,
    'look': lookToMap(look),
    'platform': platform,
    'tl': tl,
    'end': end,
    'fl': fl,
  };

  /// Reads a stored / pooled entry; null when the shape is wrong or the
  /// timeline is not format v2 (PRD-2.2 §13.5: v1 runs are not replayed).
  /// `ts` may be a [DateTime] or epoch ms (the backend converts
  /// `Timestamp`s first).
  static RunEntry? fromMap(Map<Object?, Object?> m) {
    try {
      final ts = m['ts'];
      final look = m['look'];
      final tl = m['tl']! as String;
      final fl = m['fl']! as String;
      final end = (m['end']! as num).toInt();
      if (RunTimeline.tryDecode(tl, fl, end) == null) return null;
      return RunEntry(
        runId: m['runId']! as String,
        score: (m['score']! as num).toInt(),
        best: (m['best']! as num).toInt(),
        ts: ts is DateTime
            ? ts
            : ts is num
            ? DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: true)
            : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        name: m['name']! as String,
        avatar: (m['avatar'] as String?) ?? '',
        look: look is Map ? lookFromMap(look) : Look.defaults,
        platform: (m['platform'] as String?) ?? 'android',
        tl: tl,
        end: end,
        fl: fl,
      );
    } catch (_) {
      return null;
    }
  }

  /// Name rules (ARCH §6.1): 1–32 characters.
  static String clampName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Flappy';
    return n.length > VersusConfig.nameMax
        ? n.substring(0, VersusConfig.nameMax)
        : n;
  }
}

/// The five look ids keyed bird / gear / hat / hoop / trail (ARCH §6.1).
Map<String, String> lookToMap(Look look) => {
  for (final layer in SkinLayer.values)
    layer.key: _clip(look.idFor(layer), VersusConfig.lookIdMax),
};

/// §3.13 cross-platform looks: an id this build does not know falls back to
/// the default item of its layer, so every opponent renders.
Look lookFromMap(Map<Object?, Object?> m) {
  String read(SkinLayer layer) {
    final v = m[layer.key];
    if (v is String && itemById(layer, v) != null) return v;
    return defaultItemId(layer);
  }

  return Look(
    bird: read(SkinLayer.bird),
    gear: read(SkinLayer.gear),
    hat: read(SkinLayer.hat),
    hoop: read(SkinLayer.hoop),
    trail: read(SkinLayer.trail),
  );
}

String _clip(String s, int max) => s.length > max ? s.substring(0, max) : s;

/// A pool entry (ARCH §6.1): a run plus its owner's uid and the
/// server-computed level.
class PoolEntry {
  const PoolEntry({required this.run, required this.uid, required this.level});

  final RunEntry run;
  final String uid;
  final int level;

  String get runId => run.runId;
  int get score => run.score;

  static PoolEntry? fromMap(Map<Object?, Object?> m) {
    final run = RunEntry.fromMap(m);
    final uid = m['uid'];
    final level = m['level'];
    if (run == null || uid is! String || level is! num) return null;
    return PoolEntry(run: run, uid: uid, level: level.toInt());
  }

  /// The opponent replayed in a run. The emblem level comes from their best
  /// score (§5.8 "never from the recorded run's own score").
  OpponentRun toOpponent() => OpponentRun(
    uid: uid,
    name: run.name,
    avatarUrl: run.avatar,
    look: run.look,
    score: run.score,
    best: run.best,
    level: levelFor(run.best),
    timeline: run.timeline,
    platform: run.platform,
    runId: run.runId,
  );
}

/// A queued upload (persisted as JSON in `uploadQueue`, §7).
class QueuedRun {
  const QueuedRun(this.entry, {required this.newBest});

  final RunEntry entry;

  /// The run beat the best it started with (uploaded regardless of the
  /// daily cap; becomes `bestRun`).
  final bool newBest;

  String toJson() => jsonEncode({
    ...entry.toMap(ts: entry.ts.millisecondsSinceEpoch),
    'newBest': newBest,
  });

  static QueuedRun? fromJson(String s) {
    try {
      final m = jsonDecode(s);
      if (m is! Map) return null;
      final e = RunEntry.fromMap(m);
      if (e == null) return null;
      return QueuedRun(e, newBest: m['newBest'] == true);
    } catch (_) {
      return null;
    }
  }
}

/// The next `players/{uid}` document for one new run (ARCH §6.1 write
/// contract), without `updatedAt` / `expireAt` (the backend adds the server
/// timestamp and now + 60 d). [old] is the stored doc (null = create);
/// [run] is the new run's map with `ts` already in the backend's type.
///
/// - one new run per write: `recent = [run, ...old.recent]` (≤ 5, the rest
///   shift down unchanged);
/// - a new best is the same object in `bestRun` and `recent[0]`; otherwise
///   `bestRun` stays what it was;
/// - `best` never decreases (`max(old.best, run.best)`), `level` from it.
Map<String, Object?> nextPlayerDoc({
  required Map<String, Object?>? old,
  required Map<String, Object?> run,
  required bool newBest,
  required String name,
  required String avatar,
  required String platform,
  required Look look,
  required String uploadsDay,
  required int uploadsCount,
}) {
  final oldBest = (old?['best'] as num?)?.toInt() ?? 0;
  final runBest = (run['best']! as num).toInt();
  final runScore = (run['score']! as num).toInt();
  final best = runBest > oldBest ? runBest : oldBest;
  final oldRecent = old?['recent'];
  final recent = <Object?>[
    run,
    if (oldRecent is List) ...oldRecent.take(VersusConfig.recentRuns - 1),
  ];
  final isBest = newBest && runScore == best && runScore > oldBest;
  final oldBestRun = old?['bestRun'];
  return {
    'name': RunEntry.clampName(name),
    'avatar': avatar.length > VersusConfig.avatarMax ? '' : avatar,
    'platform': platform,
    'look': lookToMap(look),
    'best': best,
    'level': levelFor(best),
    'bestRun': isBest ? run : oldBestRun,
    'recent': recent,
    'uploads': {'day': uploadsDay, 'count': uploadsCount},
  };
}
