import 'dart:async';

import 'package:flappy_spikes/game/save_seal.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/integrity_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PRD-2.5 §3.4 WP-SAVE with an in-memory key ([MemorySaveSealer]).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySaveSealer sealer;
  late IntegrityGuard guard;

  /// One app start: a fresh guard and storage over the same prefs + key.
  Future<GameStorage> start() async {
    guard = IntegrityGuard(enforce: true, platformOverride: 'android');
    IntegrityGuard.instance = guard;
    final s = GameStorage(sealer: sealer);
    await s.load();
    await s.sealVerified;
    return s;
  }

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sealer = MemorySaveSealer();
  });
  tearDown(() => IntegrityGuard.instance = IntegrityGuard());

  test(
    'key missing → trusted and sealed (also with existing values)',
    () async {
      SharedPreferences.setMockInitialValues({'coins': 500, 'bestScore': 40});
      final s = await start();
      expect(guard.trusted, isTrue);
      expect(s.sealUntrusted, isFalse);
      expect((await prefs()).getString('saveSeal'), isNotNull);
      await start();
      expect(guard.trusted, isTrue);
    },
  );

  for (final edit in <String, Object>{
    'coins': 999999,
    'bestScore': 2147483647,
    'noAds': true,
  }.entries) {
    test('an edited ${edit.key} → untrusted, value kept, sticky', () async {
      final s = await start();
      await s.saveCoins(120);
      await s.saveBestScore(33);
      final p = await prefs();
      final v = edit.value;
      if (v is int) await p.setInt(edit.key, v);
      if (v is bool) await p.setBool(edit.key, v);

      final a = await start();
      expect(guard.trusted, isFalse);
      expect(guard.reason, 'save');
      expect(a.sealUntrusted, isTrue);
      if (edit.key == 'coins') expect(a.coins, 999999);
      if (edit.key == 'bestScore') expect(a.bestScore, 2147483647);
      if (edit.key == 'noAds') expect(a.noAds, isTrue);

      // Restarting does not launder the edited values.
      final b = await start();
      expect(guard.trusted, isFalse);
      expect(b.sealUntrusted, isTrue);
      // Honest play afterwards keeps it untrusted, values still kept.
      await b.saveCoins(b.coins + 5);
      await start();
      expect(guard.trusted, isFalse);
    });
  }

  test('a forged seal (MAC mismatch) → untrusted', () async {
    final s = await start();
    await s.saveCoins(10);
    final p = await prefs();
    final raw = p.getString('saveSeal')!;
    await p.setString('saveSeal', raw.replaceFirst('"u":false', '"u":true'));
    await start();
    expect(guard.trusted, isFalse);
  });

  test('seal deleted with non-default values → untrusted', () async {
    final s = await start();
    await s.saveCoins(250);
    await (await prefs()).remove('saveSeal');
    await start();
    expect(guard.reason, 'save');
  });

  test('seal deleted with everything at default → trusted', () async {
    await start();
    await (await prefs()).remove('saveSeal');
    await start();
    expect(guard.trusted, isTrue);
  });

  test('killed between the seal and the value write → trusted', () async {
    final s = await start();
    await s.saveCoins(100);
    await s.saveGrantedPurchase(['tx1']);
    // A purchase: the coins' seal and value land, then the granted id's
    // seal lands but the app dies before its value write.
    await s.saveCoins(1100);
    await s.saveGrantedPurchase(['tx2']);
    await (await prefs()).setStringList('grantedPurchases', ['tx1']);
    final a = await start();
    expect(guard.trusted, isTrue);
    expect(a.coins, 1100);
    // And the value write never landing for the coins themselves.
    await a.saveCoins(1200);
    await (await prefs()).setInt('coins', 1100);
    await start();
    expect(guard.trusted, isTrue);
  });

  test('"Delete my data" clears the sticky flag', () async {
    final s = await start();
    await s.saveCoins(10);
    await (await prefs()).setInt('coins', 50000);
    final a = await start();
    expect(a.sealUntrusted, isTrue);
    await a.resetVersusData();
    expect(a.sealUntrusted, isFalse);
    final b = await start();
    expect(guard.trusted, isTrue);
    expect(b.coins, 50000); // never takes anything away
  });

  test('a lost key (restore / transfer) → trusted, resealed', () async {
    final s = await start();
    await s.saveCoins(10);
    await (await prefs()).setInt('coins', 77);
    sealer = MemorySaveSealer(); // the new phone has no key
    await start();
    expect(guard.trusted, isTrue);
  });

  test('sealing unavailable → no seal, trusted', () async {
    sealer = MemorySaveSealer(available: false);
    final s = await start();
    await s.saveCoins(5);
    expect(s.sealWrites, 0);
    expect((await prefs()).getString('saveSeal'), isNull);
    expect(guard.trusted, isTrue);
  });

  test('one reseal per covered setter call, none for other setters', () async {
    final s = await start();
    final before = s.sealWrites;
    await s.saveCoins(1);
    await s.saveBestScore(2);
    await s.saveNoAds(true);
    await s.saveOwnedItems({'hat:a'});
    await s.saveGrantedPurchase(['t']);
    await s.savePlayerLevel(1);
    await s.saveUploadQueue(['{}']);
    expect(s.sealWrites - before, 7);
    await s.saveFeathers(2);
    await s.saveMuteSound(true);
    await s.saveRumble(false);
    expect(s.sealWrites - before, 7);
  });

  test('a reload never loses a covered write still sealing', () async {
    final s = await start();
    unawaited(s.saveBestScore(80));
    unawaited(s.saveCoins(15));
    await s.load();
    expect(s.bestScore, 80);
    expect(s.coins, 15);
    await start();
    expect(guard.trusted, isTrue);
  });

  test(
    'without a sealer (tests, createRunTestGame) nothing is sealed',
    () async {
      expect(GameStorage.defaultSealer, isNull);
      final s = GameStorage();
      await s.load();
      await s.saveCoins(9);
      expect(s.sealVerified, isNull);
      expect((await prefs()).getString('saveSeal'), isNull);
    },
  );
}
