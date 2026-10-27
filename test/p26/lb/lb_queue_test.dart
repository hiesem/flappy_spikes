import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flappy_spikes/leaderboard/lb_queue.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameStorage storage;
  late DateTime now;
  late LbQueue queue;
  late List<Map<String, Object?>> calls;
  Object? reply;
  late List<Map<String, Object>> events;
  late bool trusted;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 27);
    storage = GameStorage(clock: () => now);
    await storage.load();
    calls = [];
    events = [];
    trusted = true;
    reply = null;
    queue = LbQueue(
      analytics: (name, parameters) {
        expect(name, 'lb_submit');
        events.add(parameters);
      },
      storage: storage,
      service: FakeLeaderboardService(
        onCall: (_, request) async {
          calls.add(request);
          if (reply is Future) return await (reply as Future);
          return reply;
        },
      ),
      clock: () => now,
      trusted: () => trusted,
      request: (runs) => LbSubmitRunRequest(runs: runs),
    );
  });
  LbSubmittedRun run(int i) => LbSubmittedRun(
    id: 'r$i',
    score: i,
    hoops: i,
    cs: 100,
    endTs: now.millisecondsSinceEpoch + i,
    mode: 'free',
  );
  test(
    'caps at tuning limit, persists, sends oldest ten, retries same ids',
    () async {
      for (var i = 0; i < 35; i++) {
        await queue.enqueue(run(i), bestCandidate: false);
      }
      expect(storage.lbQueue.length, 30);
      final loaded = GameStorage();
      await loaded.load();
      expect(loaded.lbQueue, storage.lbQueue);
      await queue.flush();
      expect((calls.single['runs'] as List).length, 10);
      expect(((calls.single['runs'] as List).first as Map)['id'], 'r5');
      await queue.flush();
      expect(calls[1], calls[0]);
      reply = {
        'accepted': ['r5'],
        'dropped': [
          {'id': 'r6', 'reason': 'bounds'},
        ],
        'group': {
          'id': 'g',
          'end': now.add(const Duration(hours: 20)).millisecondsSinceEpoch,
          'bracket': 0,
        },
        'rank': {'before': 8, 'after': 4},
      };
      await queue.flush();
      expect(storage.lbQueue.length, 28);
      expect(storage.lbGroupId, 'g');
      expect(
        storage.lbGroupEnd,
        now.add(const Duration(hours: 20)).millisecondsSinceEpoch,
      );
      expect(storage.lbLastRank, 4);
      expect(events.last, containsPair('accepted', 1));
      expect(events.last, containsPair('dropped_reason', 'bounds'));
      expect(events.last, containsPair('queued', 28));
      expect(events.last['ms'], isNonNegative);
    },
  );
  test(
    'group-day expires ordinary runs; best candidates survive only seven days',
    () async {
      await storage.saveLbGroupEnd(
        now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
      );
      await queue.enqueue(run(1), bestCandidate: false);
      await queue.enqueue(run(2), bestCandidate: true);
      now = now.add(const Duration(hours: 4));
      await queue.flush();
      expect(storage.lbQueue.length, 1);
      expect(((calls.single['runs'] as List).single as Map)['id'], 'r2');
      now = now.add(const Duration(days: 7));
      await queue.flush();
      expect(storage.lbQueue, isEmpty);
      expect(calls.length, 1);
    },
  );
  test(
    'malformed disk entries dropped and untrusted guard never sends',
    () async {
      await storage.saveLbQueue(['bad']);
      await queue.enqueue(run(1), bestCandidate: false);
      trusted = false;
      await queue.flush();
      expect(calls, isEmpty);
      expect(storage.lbQueue.length, 1);
    },
  );
  test('deletion invalidates in-flight replies and clears the queue', () async {
    final pending = Completer<Object?>();
    reply = pending.future;
    await queue.enqueue(run(1), bestCandidate: true);
    final flush = queue.flush();
    while (calls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final reset = queue.resetLocal();
    pending.complete({
      'accepted': ['r1'],
      'dropped': [],
      'group': {'id': 'deleted', 'end': 99, 'bracket': 0},
      'rank': {'after': 1},
    });
    expect(await flush, isNull);
    await reset;
    expect(storage.lbQueue, isEmpty);
    expect(storage.lbGroupId, isEmpty);
    expect(storage.lbLastRank, 0);
  });
}
