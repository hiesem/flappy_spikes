import 'dart:async';

import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game_services_test.dart' show FakeGameServices;
import '../versus/s3_13_service_test.dart' show FakeBackend, FakeIdentity;

/// iOS round 2 §5 / §6: Game Center authenticates at launch on iOS only.
void main() {
  FakeGameServices make({required bool ios}) =>
      FakeGameServices()..isIOSPlatform = () => ios;

  test('iOS: one GameAuth.signIn after initialize and the launch consent '
      'flow', () async {
    final s = make(ios: true);
    final consent = Completer<void>();
    final done = s.authenticateAtLaunch(after: consent.future);
    await pumpEventQueue();
    expect(s.signInCalls, 0, reason: 'waits for initialize');
    s.markInitialized();
    await pumpEventQueue();
    expect(s.signInCalls, 0, reason: 'waits for the consent / ATT flow');
    consent.complete();
    await done;
    expect(s.signInCalls, 1);
  });

  test(
    'Android: never at launch (Play Games profile picker, CLAUDE.md)',
    () async {
      final s = make(ios: false)..markInitialized();
      await s.authenticateAtLaunch();
      expect(s.signInCalls, 0);
    },
  );

  test('iOS: already signed in (player stream): no second sign-in', () async {
    final s = make(ios: true)
      ..markInitialized()
      ..debugSetPlayer('G:1');
    await s.authenticateAtLaunch();
    expect(s.signInCalls, 0);
  });

  test('iOS: a failed launch sign-in is reported and never throws', () async {
    final s = make(ios: true)
      ..markInitialized()
      ..signInError = Exception('cancelled');
    await s.authenticateAtLaunch();
    expect(s.signInCalls, 1);
    expect(
      s.events.where(
        (e) => e['name'] == 'pgs_error' && e['op'] == 'sign_in_launch',
      ),
      hasLength(1),
    );
  });

  test('§5 the profile name is the platform name as soon as the player '
      'stream has it, before the versus start-up finished', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    final gate = Completer<void>();
    final identity = FakeIdentity();
    final versus = FirebaseVersusService(
      storageOf: () => storage,
      backend: FakeBackend(),
      identity: identity,
      random: Random(3),
      startAfter: () => gate.future,
    );
    final init = versus.initialize();
    await pumpEventQueue();
    identity.controller.add(
      const PlatformPlayer(id: 'G:1', displayName: 'hiesem'),
    );
    await pumpEventQueue();
    expect(versus.ready, isFalse, reason: 'start-up still waiting');
    expect(versus.me.name, 'hiesem');
    gate.complete();
    await init;
    expect(versus.ready, isTrue);
    expect(versus.me.name, 'hiesem');
  });
}
