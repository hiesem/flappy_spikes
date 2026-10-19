import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/identity.dart';
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
  late fixture.FakeIdentity identity;
  late FirebaseVersusService versus;
  var now = DateTime.utc(2026, 10, 19, 12);

  Future<void> build({
    Map<String, Object> prefs = const {},
    Map<String, String> server = const {},
  }) async {
    now = DateTime.utc(2026, 10, 19, 12);
    SharedPreferences.setMockInitialValues(prefs);
    storage = GameStorage();
    await storage.load();
    backend = fixture.FakeBackend()..serverNames.addAll(server);
    identity = fixture.FakeIdentity();
    versus = FirebaseVersusService(
      storageOf: () => storage,
      backend: backend,
      identity: identity,
      random: Random(3),
      clock: () => now,
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

  test('no custom name and nothing sent before: nothing is sent, the '
      "server's name is read once (none)", () async {
    await build();
    await versus.initialize();
    await idle();
    await versus.syncCustomName();
    expect(backend.namesSent, isEmpty);
    expect(backend.nameReads, ['me']);
    expect(storage.versusCustomName, '');
  });

  test('WP-N2 reinstall: the name the server holds for this uid comes back '
      'by itself; read at most once a UTC day afterwards', () async {
    await build(server: {'me': 'Hawk7'});
    await versus.initialize();
    await idle();
    expect(storage.versusCustomName, 'Hawk7');
    expect(storage.versusCustomNameSyncedFor('me'), 'Hawk7');
    expect(backend.namesSent, isEmpty, reason: 'nothing pushed back');
    // Same day: no more reads (runs, resumes).
    await versus.flush();
    await versus.onResume();
    await versus.syncCustomName();
    await idle();
    expect(backend.nameReads, ['me']);
    // The next day: one read (the activity ping that keeps a guest name).
    now = now.add(const Duration(hours: 13));
    await versus.syncCustomName();
    await versus.syncCustomName();
    expect(backend.nameReads, ['me', 'me']);
    // Persisted: a new process the same day does not read again.
    final again = FirebaseVersusService(
      storageOf: () => storage,
      backend: backend,
      identity: fixture.FakeIdentity(),
      clock: () => now,
    );
    await again.initialize();
    await idle();
    expect(backend.nameReads, ['me', 'me']);
  });

  test('WP-N2 a local edit not confirmed yet wins until the server answers; '
      'the server is the source of truth after that', () async {
    await build(
      prefs: {'versusCustomName': 'Flyer99'},
      server: {'me': 'Hawk7'},
    );
    await versus.initialize();
    await idle();
    expect(backend.namesSent, ['Flyer99']);
    expect(backend.nameReads, isEmpty, reason: 'pending edit: sent, not read');
    expect(backend.serverNames['me'], 'Flyer99');
    expect(storage.versusCustomName, 'Flyer99');
    // Released on the server (a guest unused for 30 days): the next daily
    // read clears it here too ("You").
    backend.serverNames.remove('me');
    now = now.add(const Duration(days: 1));
    await versus.syncCustomName();
    expect(storage.versusCustomName, '');
    expect(storage.versusCustomNameSyncedFor('me'), '');
  });

  test('WP-N2 a refused "taken" name puts back what the server holds and '
      'keeps the reason for the card', () async {
    await build(server: {'me': 'Hawk7'});
    await versus.initialize();
    await idle();
    backend.takenNames.add('duck1');
    await storage.saveVersusCustomName('Duck1'); // offline edit
    await versus.syncCustomName();
    expect(storage.versusCustomName, 'Hawk7');
    expect(storage.versusCustomNameError, 'taken');
    final r = await versus.sendCustomName('DUCK1');
    expect((r as CustomNameRefused).reason, CustomNameReason.taken);
    expect(r.current, 'Hawk7');
  });

  test("WP-N2 sign-in switches to an account: the account's name wins; an "
      "account without a name takes this phone's guest name", () async {
    await build(server: {'acct': 'Hawk7'});
    await versus.initialize();
    await idle();
    expect(await versus.sendCustomName('Duck1'), isA<CustomNameAccepted>());
    await storage.saveVersusCustomName('Duck1', syncedUid: 'me');
    // credential-already-in-use → the account's uid.
    backend.switchTo = 'acct';
    identity.controller.add(const PlatformPlayer(id: 'g1'));
    await idle();
    expect(backend.deletedOnlineUids, ['me'], reason: 'guest cleaned up');
    expect(backend.nameReads.last, 'acct');
    expect(storage.versusCustomName, 'Hawk7');
    expect(storage.versusCustomNameSyncedFor('acct'), 'Hawk7');

    // Another phone: a guest name, the account has none → it moves over.
    await build(server: {});
    await versus.initialize();
    await idle();
    await versus.sendCustomName('Duck1');
    await storage.saveVersusCustomName('Duck1', syncedUid: 'me');
    backend.switchTo = 'acct2';
    identity.controller.add(const PlatformPlayer(id: 'g2'));
    await idle();
    expect(backend.serverNames['acct2'], 'Duck1');
    expect(storage.versusCustomNameSyncedFor('acct2'), 'Duck1');

    // … unless someone else holds it meanwhile: "You" and the reason.
    await build(server: {});
    await versus.initialize();
    await idle();
    await storage.saveVersusCustomName('Duck1', syncedUid: 'me');
    backend
      ..switchTo = 'acct3'
      ..takenNames.add('duck1');
    identity.controller.add(const PlatformPlayer(id: 'g3'));
    await idle();
    expect(storage.versusCustomName, '');
    expect(storage.versusCustomNameError, 'taken');
  });

  test('WP-N2 a link on the same uid reads the name again at once (even '
      'when it was read today)', () async {
    await build();
    await versus.initialize();
    await idle();
    expect(backend.nameReads, ['me']);
    backend.serverNames['me'] = 'Hawk7'; // set on another phone
    identity.controller.add(const PlatformPlayer(id: 'g1'));
    await idle();
    expect(backend.links, 1);
    expect(backend.nameReads, ['me', 'me']);
    expect(storage.versusCustomName, 'Hawk7');
  });

  test('WP-N2 offline: the read fails quietly and is tried again', () async {
    await build(server: {'me': 'Hawk7'});
    backend.nameOffline = true;
    await versus.initialize();
    await idle();
    expect(storage.versusCustomName, '');
    backend.nameOffline = false;
    await versus.syncCustomName();
    expect(storage.versusCustomName, 'Hawk7');
  });

  test('WP-N2 name keys fold case and look-alikes; generated-shape names '
      'cannot be chosen (mirror of functions/src/nameclaims.ts)', () {
    final k = customNameKey('Duck1');
    for (final same in ['duck1', 'DUCKl', 'DuckI', 'DUCKL']) {
      expect(customNameKey(same), k, reason: same);
    }
    expect(customNameKey('B0b'), customNameKey('BOB'));
    expect(customNameKey('Ka5h'), customNameKey('kash'));
    expect(customNameKey('Duck2'), isNot(customNameKey('Duck3')));
    for (final g in [
      'SwiftKiwi482',
      'swiftkiwi482',
      'KIWISWIFT482',
      'SW1FTKIWI4O2',
      'DuckTurbo111',
      'SwiftSwift482',
    ]) {
      expect(looksGenerated(g), isTrue, reason: g);
      expect(checkCustomNameLocal(g), CustomNameReason.blocked, reason: g);
    }
    for (final ok in ['SwiftKiwi48', 'WiseOwl', 'Duck1', 'KiwiKiwi482']) {
      expect(looksGenerated(ok), isFalse, reason: ok);
      expect(checkCustomNameLocal(ok), isNull, reason: ok);
    }
    expect(CustomNameReason.fromKey('taken'), CustomNameReason.taken);
    expect(CustomNameReason.taken.message, 'This name is taken.');
  });

  test(
    'audit 17 the daily change cap (resource-exhausted) is a refusal: '
    'the old name stays, the reason is kept, nothing is sent again',
    () async {
      await build(server: {'me': 'OldOwl'});
      await versus.initialize();
      await storage.saveVersusCustomName('OldOwl', syncedUid: 'me');
      backend.nameLimited = true;
      // From the Settings card.
      final r = await versus.sendCustomName('NewOwl');
      expect((r as CustomNameRefused).reason, CustomNameReason.limit);
      expect(r.current, isNull);
      // Re-sending the current name is not a change.
      expect(await versus.sendCustomName('OldOwl'), isA<CustomNameAccepted>());
      // An offline edit sent later: put back, the reason kept for the card.
      await storage.saveVersusCustomName('NewOwl');
      backend.namesSent.clear();
      await versus.syncCustomName();
      expect(backend.namesSent, ['NewOwl']);
      expect(storage.versusCustomName, 'OldOwl');
      expect(storage.versusCustomNameError, 'limit');
      await versus.syncCustomName();
      expect(backend.namesSent, ['NewOwl'], reason: 'no resend');
      expect(backend.serverNames['me'], 'OldOwl');
      // Other callable errors stay "offline" (kept, sent later).
      backend
        ..nameLimited = false
        ..nameOffline = true;
      expect(await versus.sendCustomName('NewOwl'), isA<CustomNameOffline>());
    },
  );

  test('audit 17 only resource-exhausted maps to the daily cap', () {
    for (final c in ['resource-exhausted', 'RESOURCE_EXHAUSTED']) {
      final r = customNameSaveForErrorCode(c);
      expect((r as CustomNameRefused).reason, CustomNameReason.limit);
    }
    for (final c in ['unavailable', 'internal', 'unauthenticated', '', null]) {
      expect(customNameSaveForErrorCode(c), isNull, reason: c);
    }
    expect(CustomNameReason.fromKey('limit'), CustomNameReason.limit);
    expect(
      CustomNameReason.limit.message,
      'Too many changes today. Try tomorrow.',
    );
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
