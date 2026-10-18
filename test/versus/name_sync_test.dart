import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/custom_name.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 's3_13_service_test.dart' as fixture;

/// WP-NAME the custom versus name on the service side: the callable path,
/// the offline save sent later (and again for a new uid), a refusal that
/// puts the last confirmed name back with its reason, the local reset;
/// pool entries carry the custom name to opponents.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStorage storage;
  late fixture.FakeBackend backend;
  late FirebaseVersusService versus;

  Future<void> build({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    storage = GameStorage();
    await storage.load();
    backend = fixture.FakeBackend();
    versus = FirebaseVersusService(
      storageOf: () => storage,
      backend: backend,
      identity: fixture.FakeIdentity(),
      random: Random(3),
    );
  }

  Future<void> idle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.value();
    }
  }

  test(
    'sendCustomName: accepted for the uid, refused with the reason, '
    'offline when the server cannot be reached or versus is not up',
    () async {
      await build();
      expect(await versus.sendCustomName('WiseOwl'), isA<CustomNameOffline>());
      await versus.initialize();
      final ok = await versus.sendCustomName('WiseOwl');
      expect(ok, isA<CustomNameAccepted>());
      expect((ok as CustomNameAccepted).uid, 'me');
      final no = await versus.sendCustomName('BadName');
      expect((no as CustomNameRefused).reason, CustomNameReason.blocked);
      backend.nameOffline = true;
      expect(await versus.sendCustomName('Other'), isA<CustomNameOffline>());
    },
  );

  test('a name saved offline is sent once versus is up, and again after '
      'the uid changes', () async {
    await build(prefs: {'versusCustomName': 'Flyer99'});
    await versus.initialize();
    await idle();
    expect(backend.namesSent, ['Flyer99']);
    expect(storage.versusCustomNameSyncedFor('me'), 'Flyer99');
    // In sync: nothing more is sent.
    await versus.flush();
    await versus.syncCustomName();
    expect(backend.namesSent, ['Flyer99']);
    // An account switch (Play Games link): the new uid gets it too.
    backend.myUid = 'linked';
    await versus.syncCustomName();
    expect(backend.namesSent, ['Flyer99', 'Flyer99']);
    expect(backend.serverNames['linked'], 'Flyer99');
  });

  test('no custom name and nothing sent before: no call at all', () async {
    await build();
    await versus.initialize();
    await idle();
    await versus.syncCustomName();
    expect(backend.namesSent, isEmpty);
  });

  test('a refused offline name puts back the last confirmed one and keeps '
      'the reason for the Settings card', () async {
    await build();
    await versus.initialize();
    await storage.saveVersusCustomName('GoodName', syncedUid: 'me');
    await storage.saveVersusCustomName('BadName1'); // offline edit
    await versus.syncCustomName();
    expect(storage.versusCustomName, 'GoodName');
    expect(storage.versusCustomNameError, 'blocked');
    // Without a confirmed one it goes back to "You".
    await storage.saveVersusCustomNameSync('', '');
    backend.myUid = 'other';
    await storage.saveVersusCustomName('BadName2');
    await versus.syncCustomName();
    expect(storage.versusCustomName, '');
  });

  test('Delete my data clears the custom name keys', () async {
    await build();
    await storage.saveVersusCustomName('WiseOwl', syncedUid: 'me');
    await storage.saveVersusCustomNameError('blocked');
    await storage.resetVersusData();
    final fresh = GameStorage();
    await fresh.load();
    expect(fresh.versusCustomName, '');
    expect(fresh.versusCustomNameSync, '');
    expect(fresh.versusCustomNameError, '');
  });

  test('a pool entry with a custom name shows it to opponents; without '
      '(or an invalid one) the generated name', () {
    final base = fixture.pooled('u1', 'r1', 5, 0).run.toMap();
    PoolEntry entry(Object? custom) => PoolEntry.fromMap({
      ...base,
      'uid': 'u1',
      'level': 0,
      'customName': ?custom,
    })!;
    expect(entry('WiseOwl').toOpponent().name, 'WiseOwl');
    expect(entry(null).toOpponent().name, 'P-u1');
    expect(entry('Wise Owl').toOpponent().name, 'P-u1');
    expect(entry('x' * 15).toOpponent().name, 'P-u1');
  });
}
