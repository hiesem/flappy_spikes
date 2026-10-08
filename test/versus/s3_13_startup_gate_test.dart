import 'dart:async';
import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/nickname.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 's3_13_service_test.dart' show FakeBackend, FakeIdentity;

/// Fix P6 R1 (S6-F01 / S6-F02), PRD-2 §3.13 + ARCH §6.5: versus starts only
/// after Firebase.initializeApp and the storage load (the shared
/// `startAfter` gate), and the generated nickname is created once per
/// install and never overwritten by a start that beat the storage load.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('§3.13 S6-F01 start-up gate', () {
    late GameStorage storage;
    late FakeBackend backend;
    late Completer<void> gate;
    late int gateCalls;
    late FirebaseVersusService versus;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = GameStorage();
      await storage.load();
      backend = FakeBackend();
      gate = Completer<void>();
      gateCalls = 0;
      versus = FirebaseVersusService(
        storageOf: () => storage,
        backend: backend,
        identity: FakeIdentity(),
        random: Random(1),
        startAfter: () {
          gateCalls++;
          return gate.future;
        },
      );
    });

    test('§3.13 Home prefetch and an early resume wait for Firebase + '
        'storage; one start once the gate opens', () async {
      final init = versus.initialize();
      final prefetch = versus.prefetch(); // Home (_setupStartScene)
      final resume = versus.onResume(); // AppLifecycleState.resumed
      await pumpEventQueue();
      expect(backend.starts, 0, reason: 'no Auth / App Check before init');
      expect(versus.ready, isFalse);
      expect(gateCalls, 1, reason: 'every caller shares one attempt');
      gate.complete();
      await Future.wait([init, prefetch, resume]);
      expect(backend.starts, 1);
      expect(versus.ready, isTrue);
      expect(backend.poolReads, isNotEmpty, reason: 'first prefetch ran');
    });

    test('§3.13 a failed gate (Firebase init failed) is a failed start: '
        'solo now, retried on the next recovery', () async {
      var fail = true;
      versus = FirebaseVersusService(
        storageOf: () => storage,
        backend: backend,
        identity: FakeIdentity(),
        startAfter: () async {
          gateCalls++;
          if (fail) throw StateError('Firebase is not initialized');
        },
      );
      await versus.initialize();
      expect(versus.ready, isFalse);
      expect(backend.starts, 0);
      fail = false;
      await versus.prefetch(); // Home again → recovers
      expect(gateCalls, 2);
      expect(versus.ready, isTrue);
      expect(backend.starts, 1);
    });
  });

  group('§3.13 / §7 versusNickname S6-F02', () {
    test(
      '§7 a start before the storage load keeps the saved nickname',
      () async {
        SharedPreferences.setMockInitialValues({
          'versusNickname': 'SwiftKiwi482',
        });
        final storage = GameStorage(); // not loaded: the field is still null
        expect(storage.versusNickname, isNull);
        final versus = FirebaseVersusService(
          storageOf: () => storage,
          backend: FakeBackend(),
          identity: FakeIdentity(),
        );
        await versus.initialize();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('versusNickname'), 'SwiftKiwi482');
        expect(storage.versusNickname, 'SwiftKiwi482');
        await storage.load();
        expect(storage.versusNickname, 'SwiftKiwi482');
      },
    );

    test('§3.13 created once per install: concurrent callers share one '
        'name, later cold starts read it back', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      var generated = 0;
      String gen() {
        generated++;
        return generateNickname(Random(generated));
      }

      final names = await Future.wait([
        storage.ensureVersusNickname(gen),
        storage.ensureVersusNickname(gen),
        storage.ensureVersusNickname(gen),
      ]);
      expect(generated, 1);
      expect(names.toSet(), hasLength(1));
      expect(isGeneratedNickname(names.first), isTrue);
      // Next cold start: a fresh, unloaded storage over the same prefs.
      final next = GameStorage();
      expect(await next.ensureVersusNickname(gen), names.first);
      expect(generated, 1);
    });
  });
}
