import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/pg_salt.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../versus/s3_13_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final switchUid in [false, true]) {
    test(
      'S8-03 §21.4 held opponent is revalidated after '
      '${switchUid ? 'account switch' : 'Play Games identity arrives'}',
      () async {
        SharedPreferences.setMockInitialValues({'bestScore': 120, 'playerLevel': 3});
        final storage = GameStorage();
        await storage.load();
        final backend = fixture.FakeBackend(myUid: 'anon');
        final identity = fixture.FakeIdentity();
        const salt = 'qa-salt';
        final ghost = fixture.pooled('owner', 'ghost', 80, 3);
        backend.pools['3_0'] = [
          PoolEntry.fromMap({
            ...ghost.run.toMap(ts: ghost.run.ts),
            'uid': ghost.uid,
            'level': ghost.level,
            'pg': hashPlayGamesId('g1', salt),
          })!,
        ];
        final service = FirebaseVersusService(
          storageOf: () => storage,
          backend: backend,
          identity: identity,
          random: Random(7),
          pgSalt: const FixedPgSalt(salt),
        );
        await service.initialize();
        expect(service.held?.runId, 'ghost', reason: 'prefetched anonymously');
        if (switchUid) backend.switchTo = 'owner';
        identity.controller.add(
          const PlatformPlayer(id: 'g1', displayName: 'Me'),
        );
        await pumpEventQueue();
        await service.settleIdentity();
        final opponent = service.takeOpponent();
        expect(
          opponent?.runId,
          isNot('ghost'),
          reason: 'the held run now belongs to my uid or my pg',
        );
      },
    );
  }
}
