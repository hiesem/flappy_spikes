import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/custom_name.dart';
import 'package:flappy_spikes/versus/nickname.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A scripted backend: pools by id, records writes, can fail.
class FakeBackend implements VersusBackend {
  FakeBackend({this.myUid = 'me'});

  String myUid;
  final Map<String, List<PoolEntry>> pools = {};
  final List<String> poolReads = [];
  final List<(QueuedRun, PlayerFields)> writes = [];
  bool offline = false;
  bool linked = false;
  int starts = 0, deletes = 0, resets = 0, links = 0;
  UploadWrite Function(QueuedRun r)? verdict;

  @override
  Future<String> start() async {
    if (offline) throw StateError('offline');
    starts++;
    return myUid;
  }

  @override
  String? get uid => myUid;

  @override
  bool get linkedToPlatform => linked;

  @override
  Future<List<PoolEntry>> readPool(String id) async {
    poolReads.add(id);
    if (offline) throw StateError('offline');
    return pools[id] ?? const [];
  }

  @override
  Future<UploadWrite> writeRun(QueuedRun run, PlayerFields fields) async {
    if (offline) return UploadWrite.retry;
    writes.add((run, fields));
    return verdict?.call(run) ?? UploadWrite.done;
  }

  /// PRD-2.3 §21.4 scripted `credential-already-in-use`: the link switches
  /// to [switchTo] (the uid owning the Play Games id), calling
  /// `beforeSwitch` first while still signed in as the anonymous uid.
  String? switchTo;
  final List<String> deletedOnlineUids = [];
  bool deleteOnlineFails = false;

  @override
  Future<void> link(
    PlatformIdentity identity, {
    Future<void> Function()? beforeSwitch,
  }) async {
    links++;
    final to = switchTo;
    if (to != null) {
      if (beforeSwitch != null) {
        try {
          await beforeSwitch();
        } catch (_) {}
      }
      myUid = to;
    }
    linked = true;
  }

  @override
  Future<bool> deleteOnline() async {
    if (deleteOnlineFails) throw StateError('unavailable');
    deletedOnlineUids.add(myUid);
    pools.updateAll(
      (_, v) => [for (final e in v) if (e.uid != myUid) e],
    );
    return true;
  }

  @override
  Future<bool> deleteMyData() async {
    deletes++;
    myUid = 'fresh';
    return true;
  }

  @override
  Future<void> resetAnalytics() async => resets++;

  /// WP-NAME the names the callable got, the server's state per uid and a
  /// scripted answer (refused 'blocked' when the name holds "bad").
  /// [nameOffline] throws like an unreachable server.
  final List<String> namesSent = [];
  final Map<String, String> serverNames = {};
  bool nameOffline = false;

  /// Audit 17: the daily change cap is reached (the callable answers
  /// `resource-exhausted`, as the real backend throws it).
  bool nameLimited = false;

  @override
  Future<CustomNameSave> setCustomName(String name) async {
    namesSent.add(name);
    if (nameOffline) throw StateError('offline');
    if (nameLimited && serverNames[myUid] != name) {
      throw FirebaseFunctionsException(
        message: 'Name not saved.',
        code: 'resource-exhausted',
      );
    }
    if (name.toLowerCase().contains('bad')) {
      return const CustomNameRefused(CustomNameReason.blocked);
    }
    // WP-N2 one owner per name: [takenNames] (lower case) belong to
    // another player.
    if (takenNames.contains(name.toLowerCase())) {
      return CustomNameRefused(
        CustomNameReason.taken,
        current: serverNames[myUid] ?? '',
      );
    }
    serverNames[myUid] = name;
    return CustomNameAccepted(myUid);
  }

  /// WP-N2 names (lower case) another player holds.
  final Set<String> takenNames = {};

  /// WP-N2 the uids the server's name was read for (`getVersusName`).
  final List<String> nameReads = [];

  @override
  Future<String?> getCustomName() async {
    nameReads.add(myUid);
    if (nameOffline) throw StateError('offline');
    return serverNames[myUid] ?? '';
  }
}

class FakeIdentity implements PlatformIdentity {
  final controller = StreamController<PlatformPlayer?>.broadcast();
  @override
  String get platform => 'android';
  @override
  Stream<PlatformPlayer?> get player => controller.stream;
  @override
  Future<AuthCredential?> firebaseCredential({bool fresh = false}) async =>
      null;
}

RunTimeline line(int n) {
  final t = RunTimeline();
  for (var i = 1; i <= n; i++) {
    t.addPoint(i * 1.5);
  }
  t.end(n * 1.5 + 1);
  return t;
}

PoolEntry pooled(String uid, String runId, int score, int level, {int? best}) =>
    PoolEntry(
      uid: uid,
      level: level,
      run: RunEntry(
        runId: runId,
        score: score,
        best: best ?? score,
        ts: DateTime.utc(2026, 10, 8),
        name: 'P-$uid',
        tl: line(score).encodeTl(),
        end: 100,
        fl: line(score).encodeFlags(),
      ),
    );

RunSummary summary(int score, {int bestBefore = 0}) => RunSummary(
  score: score,
  hoopsPassed: score,
  coins: 0,
  bestBefore: bestBefore,
  bestAfter: score > bestBefore ? score : bestBefore,
  runSeconds: 10,
  cause: MistakeCause.missedHoop,
  hoopIndex: score,
  timeline: line(score),
);

/// WP-5b PRD-2 §3.13: the Firebase versus service's logic over a fake
/// backend — solo on any failure, local matching from one pool read,
/// held opponent at START, the upload queue, Delete my data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStorage storage;
  late FakeBackend backend;
  late FakeIdentity identity;
  late FirebaseVersusService versus;
  var now = DateTime.utc(2026, 10, 8, 12);

  Future<void> build({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    storage = GameStorage(clock: () => now);
    await storage.load();
    backend = FakeBackend();
    identity = FakeIdentity();
    versus = FirebaseVersusService(
      storageOf: () => storage,
      backend: backend,
      identity: identity,
      random: Random(3),
      clock: () => now,
    );
  }

  setUp(() => now = DateTime.utc(2026, 10, 8, 12));

  test('§3.13 initialize: a nickname once per install, anonymous auth, the '
      'first prefetch (PRD-2.2 §3: own level shards, then the other levels)', () async {
    await build(prefs: {'bestScore': 120, 'playerLevel': 3}); // level 3 (100 → 3)
    await versus.initialize();
    expect(versus.ready, isTrue);
    final nick = storage.versusNickname!;
    expect(isGeneratedNickname(nick), isTrue);
    expect(versus.me.name, nick);
    expect(versus.me.level, 3);
    // PRD-2.2 §3 (changed from the 2.1 two-read plan): nothing anywhere →
    // all 44 pools, own level first.
    expect(backend.poolReads, hasLength(44));
    expect(backend.poolReads.take(4), everyElement(startsWith('3_')));
    expect(backend.poolReads.skip(4), everyElement(isNot(startsWith('3_'))));
    expect(versus.takeOpponent(), isNull, reason: 'nothing anywhere: solo');
    // Second initialize keeps the nickname.
    await build(prefs: {'versusNickname': nick});
    await versus.initialize();
    expect(storage.versusNickname, nick);
  });

  test('§3.13 matching from the prefetched pool: a beatable run at my level '
      'first, never mine, never the same run twice in a session; START '
      'takes it synchronously and the next is held at once', () async {
    await build(prefs: {'bestScore': 120, 'playerLevel': 3});
    final pool = [
      pooled('me', 'm1', 50, 3),
      pooled('a', 'a1', 80, 3, best: 300),
      pooled('b', 'b1', 90, 3),
      pooled('c', 'c1', 400, 5),
    ];
    for (var s = 0; s < 4; s++) {
      backend.pools['3_$s'] = pool;
    }
    await versus.initialize();
    final first = versus.takeOpponent()!;
    expect(['a1', 'b1'], contains(first.runId));
    expect(first.level, first.runId == 'a1' ? 4 : 2, // 300 → 4 (200..399)
        reason: 'emblem level from their best');
    final second = versus.takeOpponent()!;
    expect(['a1', 'b1'], contains(second.runId));
    expect(second.runId, isNot(first.runId));
    // Level candidates used up → any other run (not mine).
    final third = versus.takeOpponent()!;
    expect(third.runId, 'c1');
    expect(versus.takeOpponent(), isNull);
    expect(versus.seen, containsAll(['a1', 'b1', 'c1']));
    expect(versus.seen, isNot(contains('m1')));
  });

  test('§3.13 offline / any failure: solo, never a crash or a blocked START',
      () async {
    await build();
    backend.offline = true;
    await versus.initialize();
    expect(versus.ready, isFalse);
    expect(versus.takeOpponent(), isNull);
    await versus.submitRun(summary(10), const Look());
    expect(storage.uploadQueue, hasLength(1), reason: 'queued for later');
    expect(await versus.flush(), 0);
    // Back online: initialize again flushes the queue.
    backend.offline = false;
    await versus.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(backend.writes, hasLength(1));
    expect(storage.uploadQueue, isEmpty);
  });

  test('§3.13 submitRun: the upload rules, one run per write with the '
      'player fields (name, platform, look, UTC upload count)', () async {
    await build(prefs: {'bestScore': 50, 'playerLevel': 2});
    await versus.initialize();
    await versus.submitRun(summary(2), const Look()); // < 3: never
    await versus.submitRun(summary(60, bestBefore: 50), const Look(bird: 'sky'));
    for (var i = 0; i < 4; i++) {
      await versus.submitRun(summary(10, bestBefore: 60), const Look());
    }
    await versus.flush();
    expect(backend.writes, hasLength(4), reason: 'best + 3 a day');
    final (best, f) = backend.writes.first;
    expect(best.newBest, isTrue);
    expect(best.entry.score, 60);
    expect(best.entry.look.bird, 'sky');
    expect(f.platform, 'android');
    expect(f.name, storage.versusNickname);
    expect(f.uploadsDay, '2026-10-08');
    expect(backend.writes.skip(1).every((w) => !w.$1.newBest), isTrue);
    expect(backend.writes.map((w) => w.$1.entry.runId).toSet(), hasLength(4));
  });

  test('§3.13 a Play Games player links the account; WP-AV the name stays '
      'the generated nickname', () async {
    await build();
    await versus.initialize();
    identity.controller.add(const PlatformPlayer(id: 'g1'));
    await Future<void>.delayed(Duration.zero);
    expect(backend.links, 1);
    expect(versus.me.name, storage.versusNickname);
    identity.controller.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(versus.me.name, storage.versusNickname);
  });

  test('§3.13 Delete my data: the callable + analytics reset; locally a new '
      'nickname, an empty queue and counter; versus starts fresh', () async {
    await build();
    backend.offline = false;
    await versus.initialize();
    final nick = storage.versusNickname;
    backend.verdict = (_) => UploadWrite.retry;
    await versus.submitRun(summary(10), const Look());
    expect(storage.uploadQueue, hasLength(1));
    await versus.deleteMyData();
    expect(backend.deletes, 1);
    expect(backend.resets, 1);
    expect(storage.uploadQueue, isEmpty);
    expect(storage.uploadsToday, 0);
    expect(storage.versusNickname, isNot(nick));
    expect(versus.ready, isTrue);
    expect(backend.starts, 2);
  });

  test('§3.13 no-op default and the scripted fake (tests / FS_E2E)', () async {
    final noop = NoopVersusService();
    await noop.initialize();
    expect(noop.ready, isFalse);
    expect(noop.takeOpponent(), isNull);
    final fake = FakeVersusService();
    expect(fake.takeOpponent(), isNull);
  });
}
