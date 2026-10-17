import 'dart:convert';
import 'dart:typed_data';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A timeline of [n] points, 1 s apart (no flags).
RunTimeline line(int n, {double end = 1}) {
  final t = RunTimeline();
  for (var i = 1; i <= n; i++) {
    t.addPoint(i.toDouble());
  }
  t.end(n + end);
  return t;
}

RunSummary summary(int score, {int bestBefore = 0, RunTimeline? tl}) =>
    RunSummary(
      score: score,
      hoopsPassed: score,
      coins: 0,
      bestBefore: bestBefore,
      bestAfter: score > bestBefore ? score : bestBefore,
      runSeconds: score + 1.0,
      cause: MistakeCause.missedHoop,
      hoopIndex: score,
      timeline: tl ?? line(score),
    );

RunEntry entry(int score, {int bestBefore = 0, String id = 'r'}) =>
    RunEntry.fromSummary(
      summary(score, bestBefore: bestBefore),
      runId: id,
      name: 'SwiftKiwi482',
      ts: DateTime.utc(2026, 10, 8, 12),
    );

/// The server's decode (`functions/src/timeline.ts`): deltas + flags.
List<int> decodeDeltas(String tl) {
  final b = base64Decode(tl);
  final v = ByteData.sublistView(b);
  return [for (var i = 0; i < b.length; i += 2) v.getUint16(i, Endian.little)];
}

/// WP-5b PRD-2 §3.13 / §7: the run entry (ARCH §6.1), the player-doc write
/// contract (one new run per write) and the persisted upload queue (3 a
/// day per UTC day, best always, score ≥ 3, retry).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('§3.13 run entry (ARCH §6.1)', () {
    test('§3.13 an entry carries score, best, name, look, platform and the '
        'timeline (tl / end / fl v2); the values sum to the score', () {
      final e = entry(7, bestBefore: 3);
      expect(e.score, 7);
      expect(e.best, 7);
      // PRD-2.3 §21.4 adds `pg` (12 keys).
      expect(e.toMap().keys, hasLength(12));
      expect(e.toMap().keys, containsAll([
        'runId', 'score', 'best', 'ts', 'name', 'avatar', 'look', //
        'platform', 'tl', 'end', 'fl',
      ]));
      expect(decodeDeltas(e.tl), hasLength(7));
      expect(decodeDeltas(e.tl).skip(1), everyElement(100));
      // PRD-2.2 §13.5 fl v2: version byte 2, then (flag, value u16) each.
      final fl = base64Decode(e.fl);
      expect(fl, hasLength(1 + 7 * 3));
      expect(fl[0], 2);
      expect(e.end, 100);
      expect(e.timeline.scoreAt(3.5), 3);
      expect(e.fitsLimits, isTrue);
      // Not a new best: best stays the old best.
      expect(entry(5, bestBefore: 40).best, 40);
    });

    test('§3.13 JSON round trip (upload queue) and pool entry → opponent '
        '(level from their best, not the run score)', () {
      final q = QueuedRun(entry(12, bestBefore: 100), newBest: false);
      final back = QueuedRun.fromJson(q.toJson())!;
      expect(back.newBest, isFalse);
      expect(back.entry.toMap(ts: 0), q.entry.toMap(ts: 0));
      expect(back.entry.ts, q.entry.ts);
      final pool = PoolEntry.fromMap({
        ...entry(12, bestBefore: 220).toMap(),
        'uid': 'u9',
        'level': 4,
      })!;
      final o = pool.toOpponent();
      expect(o.uid, 'u9');
      expect(o.score, 12);
      expect(o.best, 220);
      expect(o.level, 4, reason: 'levelFor(220): 200 → 4 (not the run score)');
      expect(o.runId, 'r');
      expect(o.scoreAt(12.0), 12);
      expect(o.outAt(13.5), isTrue);
      expect(PoolEntry.fromMap({'uid': 'x'}), isNull);
    });

    test('§3.13 cross-platform looks: unknown item ids fall back to the '
        "layer's default", () {
      final look = lookFromMap({
        'bird': 'sky',
        'gear': 'jetpack',
        'hat': 'future-hat-99',
        'hoop': 'nope',
        'trail': 'flame',
      });
      expect(look.bird, 'sky');
      expect(look.gear, 'jetpack');
      expect(look.hat, Look.defaults.hat);
      expect(look.hoop, Look.defaults.hoop);
      expect(lookToMap(const Look()).keys, ['bird', 'gear', 'hat', 'hoop', 'trail']);
    });

    test('§3.13 names: 1–32 chars', () {
      expect(RunEntry.clampName('  '), 'Flappy');
      expect(RunEntry.clampName('x' * 40), hasLength(32));
    });
  });

  group('§3.13 player doc — one new run per write (ARCH §6.1)', () {
    Map<String, Object?> doc(
      Map<String, Object?>? old,
      RunEntry e, {
      required bool newBest,
    }) => nextPlayerDoc(
      old: old,
      run: e.toMap(),
      newBest: newBest,
      name: 'SwiftKiwi482',
      platform: 'android',
      look: const Look(),
      uploadsDay: '2026-10-08',
      uploadsCount: 1,
    );

    test('§3.13 create: recent = [run], a new best is the same object in '
        'bestRun, best / level from it', () {
      final e = entry(60);
      final d = doc(null, e, newBest: true);
      expect(d['recent'], hasLength(1));
      expect(identical(d['bestRun'], (d['recent']! as List).first), isTrue);
      expect(d['best'], 60);
      expect(d['level'], 2);
      expect(d['uploads'], {'day': '2026-10-08', 'count': 1});
      expect(d.keys.toSet(), {
        'name', 'avatar', 'platform', 'look', 'best', 'level', 'bestRun', //
        'recent', 'uploads',
      });
    });

    test('§3.13 update: the new run is recent[0], the rest shift down '
        'unchanged (≤ 5), bestRun stays unless new; best never decreases', () {
      Map<String, Object?>? d;
      final runs = <Map<String, Object?>>[];
      for (var i = 0; i < 7; i++) {
        final e = entry(10 + i, bestBefore: 100, id: 'r$i');
        d = doc(d, e, newBest: false);
        runs.insert(0, (d['recent']! as List).first as Map<String, Object?>);
      }
      final recent = d!['recent']! as List;
      expect(recent, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(identical(recent[i], runs[i]), isTrue);
      }
      expect(d['bestRun'], isNull);
      expect(d['best'], 100);
      // A new best replaces bestRun.
      final b = entry(150, bestBefore: 100, id: 'best');
      final d2 = doc(d, b, newBest: true);
      expect((d2['bestRun']! as Map)['runId'], 'best');
      expect(d2['best'], 150);
      // A later non-best keeps it.
      final d3 = doc(d2, entry(20, bestBefore: 150, id: 'x'), newBest: false);
      expect(identical(d3['bestRun'], d2['bestRun']), isTrue);
      expect(d3['best'], 150);
    });
  });

  group('§3.13 upload queue (§7: uploadQueue, uploadsToday + uploadsDay)', () {
    late GameStorage storage;
    late DateTime now;
    late UploadQueue queue;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      now = DateTime.utc(2026, 10, 8, 23, 30);
      storage = GameStorage(clock: () => now);
      await storage.load();
      queue = UploadQueue(storage, clock: () => now);
    });

    test('§3.13 runs under score 3 are never uploaded', () async {
      expect(await queue.offer(entry(2), newBest: true), UploadDecision.lowScore);
      expect(queue.isEmpty, isTrue);
      expect(await queue.offer(entry(3), newBest: false), UploadDecision.queued);
    });

    test('§3.13 at most 3 non-best runs per UTC day; a new best always; the '
        'count resets on the next UTC day', () async {
      for (var i = 0; i < 3; i++) {
        expect(
          await queue.offer(entry(5, bestBefore: 50, id: 'n$i'), newBest: false),
          UploadDecision.queued,
        );
      }
      expect(
        await queue.offer(entry(6, bestBefore: 50), newBest: false),
        UploadDecision.dailyCap,
      );
      expect(
        await queue.offer(entry(60, bestBefore: 50, id: 'b'), newBest: true),
        UploadDecision.queuedBest,
      );
      expect(queue.pending, hasLength(4));
      expect(storage.uploadsToday, 3);
      expect(storage.uploadsDay, '2026-10-08');
      // 23:30 UTC → 00:30 UTC next day: a fresh allowance (UTC, the
      // server's window — not the phone's local day).
      now = now.add(const Duration(hours: 1));
      expect(queue.uploadsToday, 0);
      expect(
        await queue.offer(entry(7, bestBefore: 60, id: 'n4'), newBest: false),
        UploadDecision.queued,
      );
      expect(storage.uploadsDay, '2026-10-09');
      expect(storage.uploadsToday, 1);
      expect(UploadQueue.utcDay(DateTime.parse('2026-10-08T23:59:00-05:00')),
          '2026-10-09');
    });

    test('§3.13 flush writes ONE run per write, oldest first; a transient '
        'failure keeps the rest for the retry; a refused run is dropped', () async {
      for (var i = 0; i < 3; i++) {
        await queue.offer(entry(5 + i, bestBefore: 50, id: 'q$i'), newBest: false);
      }
      final writes = <String>[];
      var fail = 'q1';
      Future<UploadWrite> write(QueuedRun r) async {
        if (r.entry.runId == fail) return UploadWrite.retry;
        writes.add(r.entry.runId);
        return UploadWrite.done;
      }

      expect(await queue.flush(write), 1);
      expect(writes, ['q0']);
      expect(queue.pending.map((r) => r.entry.runId), ['q1', 'q2']);
      // Persisted: survives an app restart.
      final reloaded = GameStorage(clock: () => now);
      await reloaded.load();
      expect(reloaded.uploadQueue, hasLength(2));
      // Back online.
      fail = '';
      expect(await queue.flush(write), 2);
      expect(writes, ['q0', 'q1', 'q2']);
      expect(queue.isEmpty, isTrue);
      // A refused run never blocks the queue.
      await queue.offer(entry(60, bestBefore: 50, id: 'bad'), newBest: true);
      await queue.offer(entry(61, bestBefore: 60, id: 'ok'), newBest: true);
      expect(
        await queue.flush(
          (r) async =>
              r.entry.runId == 'bad' ? UploadWrite.drop : UploadWrite.done,
        ),
        1,
      );
      expect(queue.isEmpty, isTrue);
      // A throwing writer counts as transient.
      await queue.offer(entry(62, bestBefore: 61, id: 't'), newBest: true);
      expect(await queue.flush((_) async => throw StateError('offline')), 0);
      expect(queue.pending, hasLength(1));
    });

    test('§3.13 the queue is capped (oldest non-best dropped first); Delete '
        'my data clears it and the counter', () async {
      for (var i = 0; i < 20; i++) {
        await storage.saveUploadsToday('', 0);
        await queue.offer(
          entry(10 + i, bestBefore: i == 0 ? 0 : 100, id: 'c$i'),
          newBest: i == 0,
        );
      }
      final ids = queue.pending.map((r) => r.entry.runId).toList();
      expect(ids, hasLength(12));
      expect(ids.first, 'c0', reason: 'the best is kept');
      await queue.clear();
      expect(queue.isEmpty, isTrue);
      expect(storage.uploadsToday, 0);
      expect(storage.uploadsDay, '');
    });
  });
}
