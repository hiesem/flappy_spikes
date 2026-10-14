import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/firebase_versus_backend.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/pg_salt.dart';
import 'package:flappy_spikes/services/versus_auth.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/diagnostics.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PRD-2.3.1 §1–§3: the versus account switch after a data reset, with a
// fake Firebase Auth server, a fake Play Games identity and the real
// FirebaseVersusBackend link / start / classify logic.

/// Secrets that plugin messages may carry: never in a log line or event.
const _token = 'ya29.SECRETaccessTOKEN';
const _codePrefix = '4/0AbCdEfGhIjKlMnOp';

/// The Firebase Auth project: users (uid → anonymous), Play Games ids
/// (pg id → owning uid) and the single-use server auth codes.
class FakeAuthServer {
  final Map<String, bool> users = {};
  final Map<String, String> pgOwner = {};
  final Set<String> usedCodes = {};
  int anonCreated = 0;
}

/// One device's Firebase Auth (its persisted current user survives a
/// "relaunch" = a new service with the same [FakeAuth]).
class FakeAuth implements VersusAuth {
  FakeAuth(this.server);

  final FakeAuthServer server;
  String? current;
  bool _anon = false;
  bool offline = false;

  /// `signInWithCredential` always fails (the 2.3.0 symptom).
  bool switchBroken = false;
  int anonSignIns = 0;

  bool get live => current != null && server.users.containsKey(current);

  FirebaseAuthException _err(String code) => FirebaseAuthException(
    code: code,
    message: 'http://localhost?access_token=$_token&code=${_codePrefix}x',
  );

  String _consume(AuthCredential c) {
    final code = (c as OAuthCredential).serverAuthCode!;
    if (server.usedCodes.contains(code)) throw _err('invalid-credential');
    server.usedCodes.add(code);
    return code.split('|').last; // the Play Games id
  }

  @override
  String? get uid => current;

  @override
  bool get isAnonymous => current != null && _anon;

  @override
  bool get linkedToPlayGames =>
      current != null && server.pgOwner.containsValue(current);

  @override
  String get photoUrl => '';

  @override
  Future<void> signInAnonymously() async {
    if (offline) throw _err('network-request-failed');
    final uid = 'anon${++server.anonCreated}';
    server.users[uid] = true;
    current = uid;
    _anon = true;
    anonSignIns++;
  }

  @override
  Future<void> signInWithCredential(AuthCredential credential) async {
    if (offline) throw _err('network-request-failed');
    if (switchBroken) throw _err('internal-error');
    final pg = _consume(credential);
    final owner = server.pgOwner[pg] ?? 'pg-$pg';
    server.users[owner] = false;
    server.pgOwner[pg] = owner;
    current = owner;
    _anon = false;
  }

  @override
  Future<void> linkWithCredential(AuthCredential credential) async {
    if (offline) throw _err('network-request-failed');
    final pg = _consume(credential);
    final owner = server.pgOwner[pg];
    if (owner != null && owner != current) {
      throw _err('credential-already-in-use');
    }
    server.pgOwner[pg] = current!;
    _anon = false;
  }

  @override
  Future<void> signOut() async => current = null;

  Future<void> _check() async {
    if (offline) throw _err('network-request-failed');
    if (current != null && !server.users.containsKey(current)) {
      throw _err('user-not-found');
    }
  }

  @override
  Future<void> reload() => _check();

  @override
  Future<void> refreshToken() => _check();
}

/// Play Games: without `fresh` it hands back the code it already gave
/// (the 2.3.0 cause, PRD §1.3); `fresh` mints a new one.
class FakePlayGames implements PlatformIdentity {
  FakePlayGames({this.pgId = 'g1'});

  final String pgId;
  final controller = StreamController<PlatformPlayer?>.broadcast();
  final List<bool> asks = [];
  bool freshAvailable = true;
  static int _minted = 0; // codes are unique across launches
  String? _cached;

  @override
  String get platform => 'android';

  @override
  Stream<PlatformPlayer?> get player => controller.stream;

  @override
  Future<AuthCredential?> firebaseCredential({bool fresh = false}) async {
    asks.add(fresh);
    if (fresh && !freshAvailable) return null;
    if (fresh || _cached == null) _cached = '$_codePrefix${++_minted}|$pgId';
    return PlayGamesAuthProvider.credential(serverAuthCode: _cached!);
  }
}

RunTimeline _line(int n) {
  final t = RunTimeline();
  for (var i = 1; i <= n; i++) {
    t.addPoint(i * 1.5);
  }
  t.end(n * 1.5 + 1);
  return t;
}

var _runs = 0;

PoolEntry _rival(int level) => PoolEntry(
  uid: 'rival',
  level: level,
  run: RunEntry(
    runId: 'r$level-${_runs++}',
    score: 10,
    best: 10,
    ts: DateTime.utc(2026, 10, 14),
    name: 'Rival',
    tl: _line(10).encodeTl(),
    end: 100,
    fl: _line(10).encodeFlags(),
  ),
);

/// The real backend's link / start logic; the Firestore / Functions /
/// Storage calls are simulated against the fake Auth server (the rules:
/// `pools` readable by any live signed-in user).
class TestBackend extends FirebaseVersusBackend {
  TestBackend(this.fake, this.events)
    : super(
        auth: fake,
        appCheck: () async {},
        analytics: (name, params) => events.add((name, params)),
      );

  final FakeAuth fake;
  final List<(String, Map<String, Object>)> events;

  /// uid of every pool read, in order.
  final List<String?> readsBy = [];
  final List<String> deletedOnline = [];
  bool alwaysDenied = false;
  int starts = 0;

  @override
  Future<String> start() {
    starts++;
    return super.start();
  }

  @override
  Future<List<PoolEntry>> readPool(String id) async {
    readsBy.add(fake.current);
    if (alwaysDenied || !fake.live) {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      throw VersusFailure(
        await FirebaseVersusBackend.classify(
          e,
          liveUser: () async => !alwaysDenied && fake.live,
        ),
        e,
      );
    }
    return [_rival(int.parse(id.split('_').first))];
  }

  @override
  Future<UploadWrite> writeRun(QueuedRun run, PlayerFields f) async =>
      UploadWrite.done;

  /// `deleteMyData` for the signed-in uid: its data AND its Auth user.
  @override
  Future<bool> deleteOnline() async {
    final uid = fake.current!;
    deletedOnline.add(uid);
    fake.server.users.remove(uid);
    return true;
  }

  @override
  Future<String> uploadAvatar(Uint8List jpeg) async => '';

  @override
  Future<void> resetAnalytics() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthServer server;
  late List<String> logs;
  late List<(String, Map<String, Object>)> events;

  setUp(() {
    server = FakeAuthServer()
      // The player's account from before the reset owns the Play Games id.
      ..users['old'] = false
      ..pgOwner['g1'] = 'old';
    logs = [];
    events = [];
    final saved = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    addTearDown(() => debugPrint = saved);
  });

  List<String> linkLines() => [
    for (final l in logs)
      if (l.startsWith('versus: link ')) l,
  ];

  /// A launch of the game on [auth]'s device: a fresh service.
  Future<(FirebaseVersusService, TestBackend, FakePlayGames)> launch(
    FakeAuth auth, {
    FakePlayGames? pg,
    bool signedInToPlayGames = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage(clock: () => DateTime.utc(2026, 10, 14, 12));
    await storage.load();
    final backend = TestBackend(auth, events);
    final identity = pg ?? FakePlayGames();
    final versus = FirebaseVersusService(
      storageOf: () => storage,
      backend: backend,
      identity: identity,
      random: Random(5),
      clock: () => DateTime.utc(2026, 10, 14, 12),
      pgSalt: const FixedPgSalt('salt'),
    );
    await versus.initialize();
    if (signedInToPlayGames) {
      identity.controller.add(
        const PlatformPlayer(id: 'g1', displayName: 'Owner'),
      );
      // The player stream starts the link; let it finish.
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return (versus, backend, identity);
  }

  test('§3 a collision, then a switch with a FRESH code: the user ends on '
      'the existing uid and the guest is deleted once', () async {
    final auth = FakeAuth(server);
    final (versus, backend, pg) = await launch(auth);
    expect(auth.current, 'old');
    expect(auth.live, isTrue);
    expect(backend.deletedOnline, ['anon1'], reason: 'the guest, once');
    expect(server.users.containsKey('anon1'), isFalse);
    expect(pg.asks, [false, true], reason: '§2.1 a new code for the switch');
    expect(linkLines(), ['versus: link switched none']);
    expect(events, hasLength(1));
    expect(events.single.$1, 'versus_link');
    expect(events.single.$2, {'outcome': 'switched', 'code': 'none'});
    // The next launch: already linked, no clean-up and no new guest.
    logs.clear();
    final (_, again, _) = await launch(auth);
    expect(auth.current, 'old');
    expect(again.deletedOnline, isEmpty);
    expect(auth.anonSignIns, 1);
    expect(linkLines(), isEmpty);
    versus.dispose();
  });

  test('§3 a collision, then the switch fails: a NEW live anonymous user, '
      'the pool reads succeed, and the next launch retries', () async {
    final auth = FakeAuth(server)..switchBroken = true;
    final (versus, backend, _) = await launch(auth);
    expect(backend.deletedOnline, ['anon1']);
    expect(auth.current, 'anon2', reason: '§2.2 a new guest at once');
    expect(auth.live, isTrue);
    expect(linkLines(), [
      'versus: link switch_failed internal-error',
      'versus: link fallback_anon none',
    ]);
    // Versus works at once under the new guest.
    backend.readsBy.clear();
    versus.takeOpponent(); // the start-up search's match is used
    versus.onRunStart();
    expect(await versus.searchForStart(), isTrue);
    expect(backend.readsBy, isNotEmpty);
    expect(backend.readsBy.toSet(), {'anon2'});
    expect(versus.lastSearch.state, VersusSearchState.found);
    // The next launch completes the switch.
    auth.switchBroken = false;
    logs.clear();
    final (_, next, _) = await launch(auth);
    expect(auth.current, 'old');
    expect(next.deletedOnline, ['anon2']);
    expect(linkLines(), ['versus: link switched none']);
    versus.dispose();
  });

  test('§2.2 a failed switch is retried on resume', () async {
    final auth = FakeAuth(server)..switchBroken = true;
    final (versus, _, _) = await launch(auth);
    expect(auth.current, 'anon2');
    auth.switchBroken = false;
    await versus.onResume();
    expect(auth.current, 'old');
    versus.dispose();
  });

  test(
    '§3 no fresh code: nothing is deleted and the guest stays signed in',
    () async {
      final auth = FakeAuth(server);
      final pg = FakePlayGames()..freshAvailable = false;
      final (versus, backend, _) = await launch(auth, pg: pg);
      expect(auth.current, 'anon1');
      expect(auth.live, isTrue);
      expect(backend.deletedOnline, isEmpty);
      expect(server.users.containsKey('anon1'), isTrue);
      expect(linkLines(), ['versus: link switch_failed no_fresh_code']);
      // A later try with a code available switches.
      pg.freshAvailable = true;
      await versus.onResume();
      expect(auth.current, 'old');
      expect(backend.deletedOnline, ['anon1']);
      versus.dispose();
    },
  );

  test('§3 a persisted user deleted on the server: start() signs in '
      'anonymously again before any pool read', () async {
    final auth = FakeAuth(server)
      ..current = 'ghost'
      .._anon = true; // the 2.3.0 dead guest
    final (versus, backend, _) = await launch(auth, signedInToPlayGames: false);
    expect(auth.current, 'anon1');
    expect(backend.readsBy, isNotEmpty);
    expect(backend.readsBy, everyElement('anon1'), reason: 'no read as ghost');
    expect(versus.lastSearch.state, VersusSearchState.found);
    expect(logs, contains('versus: start dead_user'));
    versus.dispose();
  });

  test(
    '§2.3 a live persisted user is kept; offline the user is kept too',
    () async {
      final auth = FakeAuth(server)..current = 'old';
      final b = TestBackend(auth, events);
      expect(await b.start(), 'old');
      auth.offline = true;
      server.users.remove('old'); // unknown while offline
      expect(await b.start(), 'old', reason: 'no server answer: keep it');
      expect(auth.anonSignIns, 0);
    },
  );

  test('§3 permission-denied with no live user is classified auth', () async {
    final e = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    expect(
      await FirebaseVersusBackend.classify(e, liveUser: () async => false),
      VersusSoloReason.auth,
    );
    expect(
      await FirebaseVersusBackend.classify(
        e,
        liveUser: () async => throw StateError('x'),
      ),
      isNot(VersusSoloReason.auth),
      reason: 'unknown liveness: not auth',
    );
  });

  test('§3 permission-denied with no live user: the search re-authenticates '
      'once and retries', () async {
    final auth = FakeAuth(server);
    final (versus, backend, _) = await launch(auth, signedInToPlayGames: false);
    expect(auth.current, 'anon1');
    // The account dies behind the game's back.
    server.users.remove('anon1');
    backend.readsBy.clear();
    final startsBefore = backend.starts;
    versus.takeOpponent(); // the start-up search's match is used
    versus.onRunStart();
    expect(await versus.searchForStart(), isTrue);
    expect(backend.starts, startsBefore + 1, reason: 're-authenticated once');
    expect(auth.current, 'anon2');
    expect(backend.readsBy.first, 'anon1');
    expect(backend.readsBy.last, 'anon2');
    expect(versus.lastSearch.state, VersusSearchState.found);
    versus.dispose();
  });

  test('§2.3 a search still refused after the re-authentication ends solo '
      'with its reason: retried only once', () async {
    final auth = FakeAuth(server);
    final (versus, backend, _) = await launch(auth, signedInToPlayGames: false);
    backend.alwaysDenied = true;
    final startsBefore = backend.starts;
    versus.takeOpponent(); // the start-up search's match is used
    versus.onRunStart();
    expect(await versus.searchForStart(), isFalse);
    expect(backend.starts, startsBefore + 1);
    expect(versus.soloReason, VersusSoloReason.auth);
    versus.dispose();
  });

  test('§3 the release log lines and versus_link events carry error codes '
      'only: never tokens or auth codes', () async {
    final auth = FakeAuth(server)..switchBroken = true;
    final (versus, _, _) = await launch(auth);
    // A non-collision link error too.
    final other = FakeAuth(FakeAuthServer())..current = null;
    await other.signInAnonymously();
    other.offline = true;
    final b = TestBackend(other, events);
    await expectLater(b.link(FakePlayGames()), throwsA(isA<Exception>()));
    final lines = linkLines();
    expect(lines, hasLength(3));
    final shape = RegExp(
      r'^versus: link (linked|switched|switch_failed|fallback_anon|failed) '
      r'[a-z0-9_\-]{1,40}$',
    );
    for (final l in lines) {
      expect(l, matches(shape));
    }
    for (final l in logs) {
      expect(l, isNot(contains(_token)));
      expect(l, isNot(contains(_codePrefix)));
      expect(l, isNot(contains('access_token')));
    }
    for (final (name, params) in events) {
      expect(name, 'versus_link');
      expect(params.keys.toSet(), {'outcome', 'code'});
      for (final v in params.values) {
        expect('$v', isNot(contains(_token)));
        expect('$v', isNot(contains(_codePrefix)));
      }
    }
    expect(linkErrorCode(TimeoutException('x')), 'timeout');
    expect(linkErrorCode(StateError('ya29.$_token')), 'error');
    versus.dispose();
  });
}
