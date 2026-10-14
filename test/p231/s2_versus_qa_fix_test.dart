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
class _SlowAuth extends f.FakeAuth {
  _SlowAuth(super.server);

  final finishSwitch = Completer<void>();
  int switchAttempts = 0;

  @override
  Future<void> signInWithCredential(AuthCredential credential) async {
    switchAttempts++;
    await finishSwitch.future;
    await super.signInWithCredential(credential);
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
    identity.controller.add(
      const PlatformPlayer(
        id: 'g1',
        displayName: 'Owner',
        iconImage: 'aWNvbg==',
      ),
    );
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

  test('P1-02 a stale link never changes a newer session', () async {
    final auth = _SlowAuth(server)..switchBroken = true;
    final backend = _ResettableBackend(auth, []);
    final versus = service(backend, timeout: const Duration(milliseconds: 10));
    addTearDown(versus.dispose);
    await versus.initialize();
    await signInToPlayGames();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(auth.switchAttempts, 1);

    // A data reset while the switch still hangs: a new session (guest).
    expect(await versus.deleteMyData(), isTrue);
    expect(auth.current, 'anon2');
    expect(auth.live, isTrue);

    // The old switch fails late: it must not sign the new guest out.
    auth.finishSwitch.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(auth.current, 'anon2', reason: 'the newer session keeps its user');
    expect(auth.live, isTrue);
    expect(auth.anonSignIns, 2);
    expect(backend.deletedOnline, ['anon1']);
    expect(versus.ready, isTrue);
  });

  test('P1-03 a fallback guest plays under the guest name; a successful '
      'retry brings the owner profile back; the pg guard stays', () async {
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
    expect(versus.me.avatarImage, isNot(contains('aWNvbg==')));
    await versus.settleIdentity();
    expect(versus.pg, isNotEmpty, reason: '§2.5 the pg guard is unchanged');

    auth.switchBroken = false;
    await versus.onResume();
    expect(auth.current, 'old');
    expect(versus.me.name, 'Owner');
    expect(versus.me.avatarImage, contains('aWNvbg=='));
    expect(versus.pg, isNotEmpty);
  });
}
