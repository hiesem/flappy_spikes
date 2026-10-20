import 'package:firebase_auth/firebase_auth.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/firebase_versus_backend.dart';
import 'package:flappy_spikes/services/integrity_guard.dart';
import 'package:flappy_spikes/services/versus_auth.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PRD-2.5 §3.3 WP-GUARD: an untrusted install's versus upload is skipped
/// silently. The queue, the daily counters and the flush result are those
/// of a real write, and Firestore is never touched (no Firebase app exists
/// here, so any Firestore call would fail instead of returning `done`).
class _SignedIn implements VersusAuth {
  @override
  String? get uid => 'u1';
  @override
  bool get isAnonymous => true;
  @override
  bool get linkedToPlayGames => false;
  @override
  Future<void> signInAnonymously() async {}
  @override
  Future<void> signInWithCredential(AuthCredential credential) async {}
  @override
  Future<void> linkWithCredential(AuthCredential credential) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<void> refreshToken() async {}
}

RunEntry _entry(int score, int i) {
  final t = RunTimeline();
  for (var p = 1; p <= score; p++) {
    t.addPoint(p * 1.5);
  }
  t.end(score * 1.5 + 1);
  return RunEntry(
    runId: 'run$i',
    score: score,
    best: score,
    ts: DateTime.utc(2026, 10, 20, 12),
    name: 'Me',
    tl: t.encodeTl(),
    end: 100,
    fl: t.encodeFlags(),
  );
}

const _fields = PlayerFields(
  name: 'Me',
  platform: 'android',
  look: Look.defaults,
  uploadsDay: '2026-10-20',
  uploadsCount: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clock = DateTime.utc(2026, 10, 20, 12);

  Future<(GameStorage, UploadQueue)> queued() async {
    SharedPreferences.setMockInitialValues({});
    final s = GameStorage(clock: () => clock);
    await s.load();
    final q = UploadQueue(s, clock: () => clock);
    await q.offer(_entry(12, 1), newBest: true);
    await q.offer(_entry(5, 2), newBest: false);
    await q.offer(_entry(6, 3), newBest: false);
    return (s, q);
  }

  IntegrityGuard untrusted() =>
      IntegrityGuard(enforce: true, platformOverride: 'android')
        ..markUntrusted('sig');

  test('untrusted writeRun: done, without Firestore', () async {
    final (_, q) = await queued();
    final backend = FirebaseVersusBackend(
      auth: _SignedIn(),
      appCheck: () async {},
      analytics: (_, _) {},
      integrity: untrusted(),
    );
    final run = q.pending.first;
    expect(await backend.writeRun(run, _fields), UploadWrite.done);

    // The same call on a trusted install goes to Firestore (and fails here,
    // where no Firebase app exists).
    final trusted = FirebaseVersusBackend(
      auth: _SignedIn(),
      appCheck: () async {},
      analytics: (_, _) {},
      integrity: IntegrityGuard(enforce: true, platformOverride: 'android'),
    );
    Object? outcome;
    try {
      outcome = await trusted.writeRun(run, _fields);
    } catch (e) {
      outcome = e;
    }
    expect(outcome, isNot(UploadWrite.done));
  });

  test('the queue and counters match a real (trusted) write', () async {
    final (a, qa) = await queued();
    final backend = FirebaseVersusBackend(
      auth: _SignedIn(),
      appCheck: () async {},
      analytics: (_, _) {},
      integrity: untrusted(),
    );
    final wroteA = await qa.flush((run) => backend.writeRun(run, _fields));
    final stateA = (
      a.uploadQueue.toList(),
      a.uploadsSent,
      a.uploadsSentDay,
      a.uploadsToday,
      a.uploadsDay,
    );

    final (b, qb) = await queued();
    final wroteB = await qb.flush((run) async => UploadWrite.done);
    final stateB = (
      b.uploadQueue.toList(),
      b.uploadsSent,
      b.uploadsSentDay,
      b.uploadsToday,
      b.uploadsDay,
    );

    expect(wroteA, 3);
    expect(wroteA, wroteB);
    expect(stateA.toString(), stateB.toString());
    expect(a.uploadQueue, isEmpty);
  });
}
