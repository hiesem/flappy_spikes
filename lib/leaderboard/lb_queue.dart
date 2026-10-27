import 'dart:convert';

import '../game/storage.dart';
import '../services/integrity_guard.dart';
import 'lb_config.dart';
import 'lb_models.dart';
import 'lb_service.dart';

class _Pending {
  _Pending(this.run, this.groupEnd, this.best);
  final LbSubmittedRun run;
  final int groupEnd;
  final bool best;
  String encode() =>
      jsonEncode({'run': run.toJson(), 'groupEnd': groupEnd, 'best': best});
  static _Pending? decode(String value) {
    try {
      final json = jsonDecode(value) as Map;
      return _Pending(
        LbSubmittedRun.fromJson(Map<String, Object?>.from(json['run'] as Map)),
        json['groupEnd'] as int,
        json['best'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One durable FIFO; all mutations share a lane, including deletion. A reset
/// invalidates in-flight replies immediately so they cannot restore old ranks.
class LbQueue {
  LbQueue({
    required this.storage,
    required this.service,
    required this.request,
    this.analytics,
    DateTime Function()? clock,
    bool Function()? trusted,
  }) : _clock = clock ?? storage.now,
       _trusted = trusted ?? (() => IntegrityGuard.instance.trusted);
  final GameStorage storage;
  final LeaderboardService service;
  final LbSubmitRunRequest Function(List<LbSubmittedRun>) request;
  final void Function(String, Map<String, Object>)? analytics;
  final DateTime Function() _clock;
  final bool Function() _trusted;
  final _lane = LbCallSerializer();
  int _generation = 0;

  List<_Pending> _read() {
    final now = _clock().millisecondsSinceEpoch;
    final entries = <_Pending>[];
    for (final raw in storage.lbQueue) {
      final p = _Pending.decode(raw);
      if (p == null) continue;
      final expiry = p.best
          ? p.run.endTs + const Duration(days: 7).inMilliseconds
          : p.groupEnd;
      if (now >= expiry) {
        _log(0, 'expired', entries.length, 0);
      } else {
        entries.add(p);
      }
    }
    entries.sort((a, b) => a.run.endTs.compareTo(b.run.endTs));
    return entries;
  }

  Future<void> _save(List<_Pending> entries) => storage.saveLbQueue(
    entries
        .skip((entries.length - LbConfig.queueCap).clamp(0, entries.length))
        .map((p) => p.encode())
        .toList(),
  );

  Future<void> enqueue(LbSubmittedRun run, {required bool bestCandidate}) {
    final generation = _generation;
    return _lane.run(() async {
      if (generation != _generation || !_trusted()) return;
      final entries = _read();
      if (entries.any((p) => p.run.id == run.id)) return;
      final groupEnd = storage.lbGroupEnd > run.endTs
          ? storage.lbGroupEnd
          : run.endTs + const Duration(days: 1).inMilliseconds;
      entries.add(_Pending(run, groupEnd, bestCandidate));
      if (entries.length > LbConfig.queueCap) {
        _log(0, 'capacity', entries.length, 0);
      }
      await _save(entries);
    });
  }

  Future<LbSubmitRunResult?> flush() {
    final generation = _generation;
    return _lane.run(() async {
      if (generation != _generation || !_trusted()) return null;
      final entries = _read();
      await _save(entries);
      if (entries.isEmpty) return null;
      final batch = entries.take(LbConfig.batchSize).map((p) => p.run).toList();
      final watch = Stopwatch()..start();
      LbSubmitRunResult? result;
      try {
        result = await service.submitRun(request(batch));
      } catch (_) {}
      if (generation != _generation) return null;
      if (result == null) {
        _log(0, 'retry', entries.length, watch.elapsedMilliseconds);
        return null;
      }
      final done = {...result.accepted, ...result.dropped.map((r) => r.id)};
      entries.removeWhere((p) => done.contains(p.run.id));
      // Once the server assigns the first group, all ordinary queued runs
      // belong to that group-day rather than separate rolling 24h windows.
      final group = result.group;
      if (group != null) {
        await storage.saveLbGroupId(group.id);
        await storage.saveLbGroupEnd(group.end);
        for (var i = 0; i < entries.length; i++) {
          final p = entries[i];
          if (p.run.endTs < group.end) {
            entries[i] = _Pending(p.run, group.end, p.best);
          }
        }
      }
      if (result.rank != null) {
        await storage.saveLbLastRank(result.rank!.after ?? 0);
      }
      await _save(entries);
      _log(
        result.accepted.length,
        result.dropped.map((d) => d.reason).join(','),
        entries.length,
        watch.elapsedMilliseconds,
      );
      return result;
    });
  }

  Future<void> resetLocal() {
    _generation++;
    return _lane.run(() async {
      await service.resetLocal();
      await storage.resetLeaderboardData();
    });
  }

  void _log(int accepted, String reason, int queued, int ms) =>
      analytics?.call('lb_submit', {
        'accepted': accepted,
        'dropped_reason': reason,
        'queued': queued,
        'ms': ms,
      });
}
