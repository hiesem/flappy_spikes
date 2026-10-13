import 'dart:async';
import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/diagnostics.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../versus/s3_13_service_test.dart' as fixture;

/// The §3.13 fake backend with scriptable failures and a clock hook.
class _Backend extends fixture.FakeBackend {
  /// Thrown by [start] when set.
  Object? startError;

  /// When set, [start] waits for it (sign-in still pending).
  Completer<void>? startGate;

  /// Thrown by [readPool] when set.
  Object? readError;

  /// When set, [readPool] never completes (a hanging read).
  bool hang = false;

  /// Called before every read (tests advance the clock in it).
  void Function()? onRead;

  @override
  Future<String> start() async {
    final gate = startGate;
    if (gate != null) await gate.future;
    final e = startError;
    if (e != null) throw e;
    return super.start();
  }

  @override
  Future<List<PoolEntry>> readPool(String id) async {
    onRead?.call();
    poolReads.add(id);
    final e = readError;
    if (e != null) throw e;
    if (hang) return Completer<List<PoolEntry>>().future;
    return pools[id] ?? const [];
  }
}

/// PRD-2.2 §3 the opponent search in the versus service (stop at the first
/// hit, own uid skipped, 44-read cap, 6 s limit, cached per Home visit) and
/// §4 the solo reasons, each produced by a fake backend.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStorage storage;
  late _Backend backend;
  late FirebaseVersusService versus;
  var now = DateTime.utc(2026, 10, 12, 12);

  Future<void> build({
    Map<String, Object> prefs = const {'bestScore': 120}, // level 3
    Duration searchLimit = VersusConfig.searchLimit,
  }) async {
    now = DateTime.utc(2026, 10, 12, 12);
    SharedPreferences.setMockInitialValues(prefs);
    storage = GameStorage(clock: () => now);
    await storage.load();
    backend = _Backend();
    versus = FirebaseVersusService(
      storageOf: () => storage,
      backend: backend,
      identity: fixture.FakeIdentity(),
      random: Random(5),
      clock: () => now,
      searchLimit: searchLimit,
    );
  }

  group('PRD-2.2 §3 search in the service', () {
    test('§3 own level shards first; stops at the first hit; the found '
        'search is recorded (reads, opponent)', () async {
      await build();
      backend.pools['4_2'] = [fixture.pooled('a', 'a1', 150, 4)];
      backend.pools['5_0'] = [fixture.pooled('b', 'b1', 300, 5)];
      await versus.initialize();
      final reads = backend.poolReads;
      expect(reads.take(4), everyElement(startsWith('3_')));
      // PRD-2.3 §25.2 a level's 4 shards are one parallel round: the hit
      // is in the last round read (levels 3, 2, 4).
      expect(reads.sublist(reads.length - 4), contains('4_2'),
          reason: 'stopped after the round of the first hit');
      expect(reads, isNot(contains('5_0')));
      expect(reads.length, 12);
      final s = versus.lastSearch;
      expect(s.state, VersusSearchState.found);
      expect(s.reads, reads.length);
      expect(s.level, 3);
      expect(s.opponentUid, 'a');
      expect(s.debugLine, 'Versus: last search found / ${reads.length} '
          'reads / opponent a');
      expect(versus.takeOpponent()!.runId, 'a1');
    });

    test('§3 skips the own uid: a pool with only my runs is no hit', () async {
      await build();
      for (var s = 0; s < 4; s++) {
        backend.pools['3_$s'] = [fixture.pooled('me', 'm$s', 90, 3)];
      }
      backend.pools['2_1'] = [fixture.pooled('c', 'c1', 60, 2)];
      await versus.initialize();
      // PRD-2.3 §25.2 the round of level 2 (after level 3's) holds the hit.
      expect(backend.poolReads, hasLength(8));
      expect(backend.poolReads.skip(4), contains('2_1'));
      expect(versus.takeOpponent()!.uid, 'c');
    });

    test('§3 nobody anywhere: 44 reads (the cap), no_rival; the result is '
        'cached for the Home visit; after a run start a new search runs',
        () async {
      await build();
      await versus.initialize();
      expect(backend.poolReads, hasLength(VersusConfig.maxSearchReads));
      expect(versus.lastSearch.reads, 44);
      expect(versus.lastSearch.state, VersusSearchState.solo);
      expect(versus.soloReason, VersusSoloReason.noRival);
      expect(
        versus.lastSearch.debugLine,
        'Versus: last search no_rival / 44 reads / opponent -',
      );
      // Back on Home (e.g. from the Shop): no new search.
      await versus.prefetch();
      expect(backend.poolReads, hasLength(44));
      // A run starts (solo); PRD-2.3 §25.2 the run start searches again.
      expect(versus.takeOpponent(), isNull);
      backend.pools['7_3'] = [fixture.pooled('d', 'd1', 900, 7)];
      versus.onRunStart();
      await versus.searchForStart();
      expect(backend.poolReads.length, greaterThan(44));
      expect(backend.poolReads.skip(44), contains('7_3'));
      expect(versus.lastSearch.state, VersusSearchState.found);
    });

    test('§3 / §4 the 6 s limit (clock): the search stops, reason timeout',
        () async {
      await build();
      backend.onRead = () => now = now.add(const Duration(seconds: 1));
      await versus.initialize();
      // PRD-2.3 §25.2 rounds of 4 parallel reads: the limit is checked
      // before each round (4 s after the first, 8 s after the second).
      expect(versus.lastSearch.reads, 8, reason: '2 rounds of 4 reads, 1 s each');
      expect(versus.soloReason, VersusSoloReason.timeout);
      expect(versus.lastSearch.reason, VersusSoloReason.timeout);
    });

    test('§4 a hanging read hits the search limit: timeout', () async {
      await build(searchLimit: const Duration(milliseconds: 40));
      backend.hang = true;
      await versus.initialize();
      // PRD-2.3 §25.2 the first round's 4 reads, counted as they happen.
      expect(versus.lastSearch.reads, 4);
      expect(versus.soloReason, VersusSoloReason.timeout);
    });

    test('§4 START while the search still runs: timeout', () async {
      await build(searchLimit: const Duration(seconds: 2));
      backend.hang = true;
      unawaited(versus.initialize());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(versus.ready, isTrue);
      expect(versus.lastSearch.state, VersusSearchState.running);
      expect(versus.takeOpponent(), isNull);
      expect(versus.soloReason, VersusSoloReason.timeout);
      expect(versus.lastSearch.debugLine, startsWith('Versus: last search running'));
      await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 100));
    });
  });

  group('PRD-2.2 §4 reason codes from a fake backend', () {
    for (final r in [
      VersusSoloReason.offline,
      VersusSoloReason.appCheck,
      VersusSoloReason.rules,
      VersusSoloReason.auth,
    ]) {
      test('§4 a read refused as ${r.code}', () async {
        await build();
        backend.readError = VersusFailure(r, 'scripted');
        await versus.initialize();
        expect(versus.ready, isTrue);
        expect(versus.soloReason, r);
        expect(versus.lastSearch.reads, 4,
            reason: 'the search stops after its first round (PRD-2.3 §25.2)');
        expect(versus.lastSearch.reason, r);
      });
    }

    test('§4 any other read failure: error', () async {
      await build();
      backend.readError = StateError('boom');
      await versus.initialize();
      expect(versus.soloReason, VersusSoloReason.error);
    });

    test('§4 sign-in failed: auth; App Check refused at start: app_check; '
        'no network at start: offline', () async {
      await build();
      backend.startError = StateError('sign-in failed');
      await versus.initialize();
      expect(versus.ready, isFalse);
      expect(versus.soloReason, VersusSoloReason.auth);

      await build();
      backend.startError = const VersusFailure(VersusSoloReason.appCheck);
      await versus.initialize();
      expect(versus.soloReason, VersusSoloReason.appCheck);

      await build();
      backend.startError = const VersusFailure(VersusSoloReason.offline);
      await versus.initialize();
      expect(versus.soloReason, VersusSoloReason.offline);
    });

    test('§4 sign-in still pending: auth', () async {
      await build();
      backend.startGate = Completer<void>();
      unawaited(versus.initialize());
      await Future<void>.delayed(Duration.zero);
      expect(versus.ready, isFalse);
      expect(versus.takeOpponent(), isNull);
      expect(versus.soloReason, VersusSoloReason.auth);
      backend.startGate!.complete();
      await versus.initialize();
      expect(versus.ready, isTrue);
    });

    test('§4 every reason code has its analytics value', () {
      expect(VersusSoloReason.values.map((r) => r.code), [
        'no_rival',
        'timeout',
        'offline',
        'auth',
        'app_check',
        'rules',
        'error',
      ]);
      expect(soloReasonOf(TimeoutException('x')), VersusSoloReason.timeout);
      expect(soloReasonOf(StateError('x')), VersusSoloReason.error);
      expect(
        soloReasonOf(const VersusFailure(VersusSoloReason.rules)),
        VersusSoloReason.rules,
      );
      expect(
        versusSoloLogLine(VersusSoloReason.appCheck, 3),
        'versus: solo (app_check, 3 reads)',
      );
    });
  });
}
