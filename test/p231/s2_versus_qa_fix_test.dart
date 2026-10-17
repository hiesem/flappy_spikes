import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/pg_salt.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 's1_versus_switch_test.dart' as f;

// PRD-2.3.1 §2.2 / §2.5 / §3 — regression tests for the QA round 1
// findings P1-01 (first online resume after a recovery retries the switch),
// P1-02 (the link stays single-flight until its auth work settles; a stale
// link never changes a newer session) and P1-03 (a fallback guest plays
// under the guest name).

/// The network drops right after the first guest's clean-up (P1-01).
class _OfflineAfterDelete extends f.TestBackend {
  _OfflineAfterDelete(super.fake, super.events);

  bool dropOnce = true;

  @override
  Future<bool> deleteOnline() async {
    final ok = await super.deleteOnline();
    if (dropOnce) fake.offline = true;
    dropOnce = false;
    return ok;
  }
}

/// `deleteMyData`: the signed-in user's data and Auth user, then sign out.
class _ResettableBackend extends f.TestBackend {
  _ResettableBackend(super.fake, super.events);

  @override
  Future<bool> deleteMyData() async {
    final uid = fake.current;
    if (uid != null) fake.server.users.remove(uid);
    await fake.signOut();
    return true;
  }
}

/// `signInWithCredential` hangs until [finishSwitch] completes (P1-02).
/// QA P2-01: [log] records every Auth change in order; [overlaps] counts
/// the changes that started while the switch still hung.
class _SlowAuth extends f.FakeAuth {
  _SlowAuth(super.server);

  final finishSwitch = Completer<void>();
  int switchAttempts = 0;
  bool _switching = false;
  int overlaps = 0;
  final List<String> log = [];

  void _change(String what) {
    if (_switching) overlaps++;
    log.add(what);
  }

  @override
  Future<void> signInWithCredential(AuthCredential credential) async {
    _change('switch');
    switchAttempts++;
    _switching = true;
    try {
      await finishSwitch.future;
      await super.signInWithCredential(credential);
    } finally {
      _switching = false;
      log.add('switch settled');
    }
  }

  @override
  Future<void> signInAnonymously() {
    _change('anon');
    return super.signInAnonymously();
  }

  @override
  Future<void> linkWithCredential(AuthCredential credential) {
    _change('link');
    return super.linkWithCredential(credential);
  }

  @override
  Future<void> signOut() {
    _change('signOut');
    return super.signOut();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late f.FakeAuthServer server;
  late GameStorage storage;
  late f.FakePlayGames identity;

  setUp(() async {
    server = f.FakeAuthServer()
      ..users['old'] = false
      ..pgOwner['g1'] = 'old';
    SharedPreferences.setMockInitialValues({});
    storage = GameStorage();
    await storage.load();
    identity = f.FakePlayGames();
    final saved = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {};
    addTearDown(() async {
      debugPrint = saved;
      await identity.controller.close();
    });
  });

  FirebaseVersusService service(
    f.TestBackend backend, {
    Duration timeout = const Duration(seconds: 2),
  }) => FirebaseVersusService(
    storageOf: () => storage,
    backend: backend,
    identity: identity,
    pgSalt: const FixedPgSalt('salt'),
    timeout: timeout,
  );

  Future<void> signInToPlayGames() async {
    identity.controller.add(const PlatformPlayer(id: 'g1'));
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('P1-01 the first online resume after a recovery retries the '
      'interrupted account switch', () async {
    final auth = f.FakeAuth(server);
    final backend = _OfflineAfterDelete(auth, []);
    final versus = service(backend);
    addTearDown(versus.dispose);
    await versus.initialize();
    await signInToPlayGames();
    // The switch and the fallback guest both failed offline.
    expect(auth.current, isNull);
    expect(versus.ready, isFalse);
    expect(backend.deletedOnline, ['anon1']);

    auth.offline = false;
    await versus.onResume();
    expect(versus.ready, isTrue);
    expect(auth.current, 'old', reason: '§2.2 the next resume switches');
    expect(auth.live, isTrue);
    expect(backend.deletedOnline, [
      'anon1',
      'anon2',
    ], reason: 'each guest once');
    expect(identity.asks, [false, true, false, true]);
  });

  test('P1-02 a timed-out link stays single-flight until its auth work '
      'settles: one switch, one deletion', () async {
    final auth = _SlowAuth(server);
    final backend = f.TestBackend(auth, []);
    final versus = service(backend, timeout: const Duration(milliseconds: 10));
    addTearDown(versus.dispose);
    await versus.initialize();
    await signInToPlayGames();
    // Let the caller's time box (3 × 10 ms) run out.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(auth.switchAttempts, 1);
    expect(auth.current, 'anon1');
    expect(auth.live, isFalse, reason: 'the guest is already deleted');

    await versus.onResume();
    expect(
      auth.switchAttempts,
      1,
      reason: 'no second auth transaction while the first still runs',
    );
    expect(backend.deletedOnline, ['anon1']);

    auth.finishSwitch.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(auth.current, 'old');
    expect(auth.switchAttempts, 1);
    expect(backend.deletedOnline, ['anon1'], reason: 'the guest once');
  });

  /// QA P2-01 the switch hangs (the caller's 3 × 10 ms wait has run out);
  /// a data reset or a re-authentication is asked for meanwhile.
  Future<(_SlowAuth, _ResettableBackend, FirebaseVersusService)> hungSwitch({
    bool fails = false,
  }) async {
    final auth = _SlowAuth(server)..switchBroken = fails;
    final backend = _ResettableBackend(auth, []);
    final versus = service(backend, timeout: const Duration(milliseconds: 10));
    addTearDown(versus.dispose);
    await versus.initialize();
    await signInToPlayGames();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(auth.switchAttempts, 1);
    expect(auth.current, 'anon1');
    expect(auth.live, isFalse, reason: 'the guest is already deleted');
    return (auth, backend, versus);
  }

  /// A pool read refused for the deleted guest: the search re-authenticates.
  Future<void> searchWithReauth(FirebaseVersusService versus) async {
    versus.takeOpponent();
    versus.onRunStart();
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  for (final late in ['success', 'failure']) {
    for (final path in ['deleteMyData', 're-authentication']) {
      test('P2-01 a late switch $late after $path: no second Auth change '
          'starts while the switch hangs; the dropped one never runs '
          'late', () async {
        final (auth, backend, versus) = await hungSwitch(
          fails: late == 'failure',
        );
        if (path == 'deleteMyData') {
          // The caller's wait is time-boxed: nothing was deleted, so the
          // reset reports the failure and keeps the account (WP-4c).
          expect(await versus.deleteMyData(), isFalse);
        } else {
          await searchWithReauth(versus);
        }
        expect(auth.overlaps, 0);
        expect(auth.current, 'anon1', reason: 'no newer session started');
        expect(backend.starts, 1);

        auth.finishSwitch.complete();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(auth.overlaps, 0);
        expect(backend.starts, 1, reason: 'the dropped start never runs');
        if (late == 'success') {
          expect(auth.current, 'old');
          expect(server.users.containsKey('old'), isTrue, reason: 'no reset');
          // WP-AV the generated name, never the platform name.
          expect(versus.me.name, storage.versusNickname);
        } else {
          expect(auth.current, 'anon2', reason: '§2.2 the fallback guest');
        }
        expect(auth.live, isTrue);
        expect(auth.log.last, late == 'success' ? 'switch settled' : 'anon');
      });
    }
  }

  test('P2-01 a data reset asked for during a switch runs after it settles '
      '(in order, never next to it)', () async {
    final auth = _SlowAuth(server);
    final backend = _ResettableBackend(auth, []);
    final versus = service(backend, timeout: const Duration(milliseconds: 40));
    addTearDown(versus.dispose);
    await versus.initialize();
    await signInToPlayGames();
    expect(auth.switchAttempts, 1);

    final reset = versus.deleteMyData();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(auth.current, 'anon1', reason: 'the reset waits for its turn');
    auth.finishSwitch.complete();
    expect(await reset, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(auth.overlaps, 0);
    // The switch settled, THEN the reset signed out, THEN a new start.
    final settled = auth.log.indexOf('switch settled');
    final signOut = auth.log.indexOf('signOut');
    expect(settled, greaterThanOrEqualTo(0));
    expect(signOut, greaterThan(settled));
    expect(auth.log.indexOf('anon', signOut), greaterThan(signOut));
    expect(backend.starts, 2);
    expect(versus.ready, isTrue);
    expect(auth.live, isTrue);
  });

  test('P2-01 a stuck switch never freezes a caller: each wait is '
      'time-boxed and versus just stays unavailable', () async {
    final (auth, _, versus) = await hungSwitch();
    final watch = Stopwatch()..start();
    await versus.onResume();
    await versus.onPlatformSignIn();
    await versus.searchForStart();
    expect(await versus.deleteMyData(), isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(auth.overlaps, 0);
    expect(auth.switchAttempts, 1);
  });

  test('P1-03 a fallback guest plays under the nickname; a successful '
      'retry keeps the nickname (WP-AV: never the platform name); the pg '
      'guard stays', () async {
    final auth = f.FakeAuth(server)..switchBroken = true;
    final backend = f.TestBackend(auth, []);
    final versus = service(backend);
    addTearDown(versus.dispose);
    await versus.initialize();
    await signInToPlayGames();
    expect(auth.current, 'anon2');
    expect(auth.isAnonymous, isTrue);

    final nickname = storage.versusNickname;
    expect(nickname, isNotNull);
    expect(versus.me.name, nickname, reason: '§2.2 under a guest name');
    await versus.settleIdentity();
    expect(versus.pg, isNotEmpty, reason: '§2.5 the pg guard is unchanged');

    auth.switchBroken = false;
    await versus.onResume();
    expect(auth.current, 'old');
    expect(versus.me.name, nickname, reason: 'WP-AV the generated name');
    expect(versus.pg, isNotEmpty);
  });
}
