import 'dart:async';
import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/diagnostics.dart';
import 'package:flappy_spikes/versus/matcher.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../versus/s3_13_service_test.dart' as fixture;

/// A fake backend whose reads can be held open (search timing).
class _SlowBackend extends fixture.FakeBackend {
  /// When true every read waits for [release] (reads in flight are counted).
  bool holdReads = false;
  final List<Completer<void>> _held = [];
  int inFlight = 0, maxInFlight = 0;

  /// When true, reads never complete.
  bool hang = false;

  void release() {
    final c = [..._held];
    _held.clear();
    for (final x in c) {
      x.complete();
    }
  }

  @override
  Future<List<PoolEntry>> readPool(String id) async {
    poolReads.add(id);
    inFlight++;
    maxInFlight = max(maxInFlight, inFlight);
    try {
      if (hang) await Completer<void>().future;
      if (holdReads) {
        final c = Completer<void>();
        _held.add(c);
        await c.future;
      }
      return pools[id] ?? const [];
    } finally {
      inFlight--;
    }
  }
}

/// PRD-2.3 §25.2 / §25.4 matching: "already met" is a preference (met
/// longest ago), the search starts at run start, the 4 shards of a level
/// are read in parallel, and a timeout reports its real read count.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStorage storage;
  late _SlowBackend backend;
  late FirebaseVersusService versus;

  Future<void> build({
    Map<String, Object> prefs = const {'bestScore': 120, 'playerLevel': 3},
    Duration searchLimit = VersusConfig.searchLimit,
    Duration readTimeout = VersusConfig.readTimeout,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    storage = GameStorage();
    await storage.load();
    backend = _SlowBackend();
    versus = FirebaseVersusService(
      storageOf: () => storage,
      backend: backend,
      identity: fixture.FakeIdentity(),
      random: Random(7),
      searchLimit: searchLimit,
      readTimeout: readTimeout,
    );
  }

  /// One VERSUS START (+ the run that follows): what START took, then the
  /// run start's search for the next opponent, awaited.
  Future<String?> start() async {
    final o = versus.takeOpponent();
    versus.onRunStart();
    await versus.searchForStart();
    return o?.runId;
  }

  group('§25.2 met longest ago', () {
    for (final sameShard in [true, false]) {
      test('§25.4 a pool of 2 non-own runs (${sameShard ? 'one shard' : 'two '
          'levels'}): 10 VERSUS starts in a row are all versus, alternating '
          'A, B, A, B', () async {
        await build();
        backend.pools['3_1'] = [
          fixture.pooled('me', 'm1', 50, 3),
          fixture.pooled('a', 'A', 80, 3),
          if (sameShard) fixture.pooled('b', 'B', 90, 3),
        ];
        if (!sameShard) backend.pools['5_2'] = [fixture.pooled('b', 'B', 450, 5)];
        await versus.initialize();
        final got = <String?>[];
        for (var i = 0; i < 10; i++) {
          got.add(await start());
        }
        expect(got, everyElement(isNotNull), reason: 'never a silent solo');
        for (var i = 2; i < got.length; i++) {
          expect(got[i], got[i - 2], reason: 'alternating: $got');
        }
        expect(got[0], isNot(got[1]));
        expect({...got}, {'A', 'B'});
      });
    }

    test('§25.4 only own runs: no_rival', () async {
      await build();
      for (var s = 0; s < 4; s++) {
        backend.pools['3_$s'] = [fixture.pooled('me', 'm$s', 90, 3)];
      }
      await versus.initialize();
      expect(versus.takeOpponent(), isNull);
      expect(versus.lastSearch.reason, VersusSoloReason.noRival);
      expect(versus.soloReason, VersusSoloReason.noRival);
      // Known at once: the START does not search again.
      final reads = backend.poolReads.length;
      expect(await versus.searchForStart(), isFalse);
      expect(backend.poolReads, hasLength(reads));
    });

    test('§25.4 the met list caps at 100 (oldest dropped first)', () async {
      await build();
      final pool = [
        for (var i = 0; i < 130; i++) fixture.pooled('u$i', 'r$i', 80, 3),
      ];
      backend.pools['3_0'] = pool;
      await versus.initialize();
      for (var i = 0; i < 120; i++) {
        expect(versus.takeOpponent(), isNotNull, reason: 'start $i');
        versus.onRunStart();
        await versus.searchForStart();
      }
      expect(versus.met, hasLength(VersusConfig.metCap));
      expect(VersusConfig.metCap, 100);
      expect(versus.met.toSet(), hasLength(100));
    });

    test('§25.2 matchCandidates: met runs are a preference, not a block', () {
      final pool = [
        PoolCandidate(fixture.pooled('a', 'a1', 80, 3)),
        PoolCandidate(fixture.pooled('b', 'b1', 90, 3)),
      ];
      final (tier, c) = matchCandidates(
        pool,
        myLevel: 3,
        myBest: 120,
        myUid: 'me',
        met: const ['b1', 'a1'],
      );
      expect(tier, MatchTier.rematch);
      expect(c.single.runId, 'b1');
    });
  });

  group('§25.2 search timing', () {
    test('§25.4 the search starts at run start (not at Home)', () async {
      await build();
      await versus.initialize();
      final before = backend.poolReads.length;
      backend.pools['3_2'] = [fixture.pooled('a', 'a1', 80, 3)];
      versus.onRunStart();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(backend.poolReads.length, greaterThan(before),
          reason: 'run start searches at once');
      await versus.searchForStart();
      expect(versus.holdsOpponent, isTrue);
    });

    test('§25.4 a START after a short run finds the opponent held', () async {
      await build();
      backend.pools['3_0'] = [fixture.pooled('a', 'a1', 80, 3)];
      await versus.initialize();
      expect(versus.takeOpponent()!.runId, 'a1');
      backend.pools['4_1'] = [fixture.pooled('b', 'b1', 220, 4)];
      versus.onRunStart(); // the short run…
      await versus.searchForStart();
      // …and back on Home: held, no wait.
      expect(versus.holdsOpponent, isTrue);
      expect(versus.takeOpponent()!.runId, 'b1');
    });

    test('§25.4 the 4 shards of a level are read in parallel', () async {
      await build();
      backend.holdReads = true;
      unawaited(versus.initialize());
      for (var i = 0; i < 10 && backend.inFlight < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(backend.inFlight, 4, reason: 'level 3: four reads at once');
      expect(backend.poolReads.toSet(), {'3_0', '3_1', '3_2', '3_3'});
      backend.release();
      for (var i = 0; i < 10 && backend.poolReads.length < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(backend.poolReads.skip(4), everyElement(startsWith('2_')));
      backend.holdReads = false;
      backend.release();
      await versus.searchForStart();
      expect(backend.maxInFlight, 4);
      expect(backend.poolReads, hasLength(44));
    });

    test('§25.4 a timeout reports the real read count (not 0)', () async {
      await build(
        searchLimit: const Duration(milliseconds: 120),
        readTimeout: const Duration(milliseconds: 60),
      );
      backend.hang = true;
      await versus.initialize();
      expect(versus.lastSearch.reason, VersusSoloReason.timeout);
      expect(versus.lastSearch.reads, 4);
      expect(VersusConfig.readTimeout, const Duration(seconds: 4));
    });

    test('§25.2 item 4: while the search runs the read count is live',
        () async {
      await build();
      backend.holdReads = true;
      unawaited(versus.initialize());
      for (var i = 0; i < 10 && backend.inFlight < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(versus.lastSearch.state, VersusSearchState.running);
      expect(versus.lastSearch.reads, 4);
      backend.holdReads = false;
      backend.release();
      await versus.searchForStart();
    });
  });
}
