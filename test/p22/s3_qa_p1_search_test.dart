import 'dart:async';
import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../versus/s3_13_service_test.dart' as fixture;

class _PendingBackend extends fixture.FakeBackend {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<PoolEntry>> readPool(String id) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.readPool(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('§3 START during an in-flight search still allows a fresh search '
      'on the next Home visit', () async {
    SharedPreferences.setMockInitialValues({'bestScore': 120});
    final storage = GameStorage();
    await storage.load();
    final backend = _PendingBackend();
    final versus = FirebaseVersusService(
      storageOf: () => storage,
      backend: backend,
      identity: fixture.FakeIdentity(),
      random: Random(5),
    );
    addTearDown(versus.dispose);
    final init = versus.initialize();
    await backend.entered.future;
    expect(versus.takeOpponent(), isNull);
    versus.onRunStart(); // User never waits for Home's network search.
    backend.release.complete();
    await init;
    expect(backend.poolReads, hasLength(44));
    await versus.prefetch(); // Return to Home after that run.
    expect(backend.poolReads, hasLength(88));
  });
}
