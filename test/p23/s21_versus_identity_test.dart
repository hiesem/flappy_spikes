import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/services/avatar_upload.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/pg_salt.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/matcher.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../versus/s3_13_service_test.dart' as fixture;

/// A fake salt (PRD-2.3 §0 item 7: the real one lives in Remote Config only).
const _salt = 'test-salt-not-the-real-one';

/// A Play Games picture as the plugin hands it over (base64 PNG), noisy so
/// the JPEG is not trivially small.
String _icon({int side = 256, int seed = 1}) {
  final r = Random(seed);
  final im = img.Image(width: side, height: side);
  for (final p in im) {
    p
      ..r = r.nextInt(256)
      ..g = r.nextInt(256)
      ..b = r.nextInt(256);
  }
  return base64Encode(img.encodePng(im));
}

/// Grape, Shades, Cap, Neon, Bubbles (PRD-2.3 §21.5).
const _fancy = Look(
  bird: 'grape',
  gear: 'shades',
  hat: 'cap',
  hoop: 'neon',
  trail: 'bubbles',
);

/// PRD-2.3 §21.3 / §21.4 / §21.5 the versus identity: the uploaded picture,
/// the hashed Play Games id and the self-match guard, the account-switch
/// clean-up, and the look round trip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStorage storage;
  late fixture.FakeBackend backend;
  late fixture.FakeIdentity identity;
  late FirebaseVersusService versus;

  Future<void> build({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues({'bestScore': 120, ...prefs});
    storage = GameStorage();
    await storage.load();
    backend = fixture.FakeBackend(myUid: 'anon');
    identity = fixture.FakeIdentity();
    versus = FirebaseVersusService(
      storageOf: () => storage,
      backend: backend,
      identity: identity,
      random: Random(5),
      pgSalt: const FixedPgSalt(_salt),
    );
  }

  Future<void> signIn(PlatformPlayer p) async {
    identity.controller.add(p);
    await Future<void>.delayed(Duration.zero);
    await versus.settleIdentity();
    await Future<void>.delayed(Duration.zero);
    await versus.settleIdentity();
  }

  group('§21.3 pictures', () {
    test('§21.5 encodeVersusAvatar: 96 × 96 JPEG within 30 KB', () {
      for (final side in [64, 96, 256, 512]) {
        final jpg = encodeVersusAvatar(base64Decode(_icon(side: side)))!;
        expect(jpg.length, lessThanOrEqualTo(VersusConfig.avatarMaxBytes));
        final back = img.decodeJpg(jpg)!;
        expect((back.width, back.height), (96, 96));
      }
      expect(encodeVersusAvatar(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('§21.5 an upload happens once per picture change; the run\'s '
        'avatar holds the URL', () async {
      await build();
      await versus.initialize();
      final pic = _icon();
      await signIn(PlatformPlayer(id: 'g1', displayName: 'Hiesem', iconImage: pic));
      expect(backend.avatarUploads, hasLength(1));
      final (uid, bytes) = backend.avatarUploads.single;
      expect(uid, 'anon');
      expect(bytes.length, lessThanOrEqualTo(30 * 1024));
      expect(img.decodeJpg(bytes)!.width, 96);
      final url = storage.versusAvatar!.url;
      expect(url, startsWith('https://storage.example/avatars/anon.jpg'));
      expect(versus.me.avatarUrl, url);

      // The same picture again (a new player event, an app restart): no upload.
      await signIn(PlatformPlayer(id: 'g1', displayName: 'Hiesem', iconImage: pic));
      expect(backend.avatarUploads, hasLength(1));

      // The run carries the URL in `avatar`.
      await versus.submitRun(fixture.summary(30, bestBefore: 120), _fancy);
      await versus.flush();
      final (q, f) = backend.writes.single;
      expect(q.entry.avatar, url);
      expect(f.avatar, url);

      // A new picture: one more upload.
      await signIn(
        PlatformPlayer(id: 'g1', displayName: 'Hiesem', iconImage: _icon(seed: 2)),
      );
      expect(backend.avatarUploads, hasLength(2));
      expect(storage.versusAvatar!.url, endsWith('v=2'));
    });

    test('§21.3 players without a Play Games picture upload nothing; a failed '
        'upload leaves avatar empty', () async {
      await build();
      await versus.initialize();
      await signIn(const PlatformPlayer(id: 'g1', displayName: 'NoPic'));
      expect(backend.avatarUploads, isEmpty);
      expect(versus.me.avatarUrl, '');

      await build();
      backend = _FailingUpload(myUid: 'anon');
      versus = FirebaseVersusService(
        storageOf: () => storage,
        backend: backend,
        identity: identity,
        pgSalt: const FixedPgSalt(_salt),
      );
      await versus.initialize();
      await signIn(PlatformPlayer(id: 'g1', displayName: 'X', iconImage: _icon()));
      expect(storage.versusAvatar, isNull);
      expect(versus.me.avatarUrl, '');
    });
  });

  group('§21.4 the hashed Play Games id (pg)', () {
    test('§21.4 pg = SHA-256(id + salt) hex; "" without Play Games or salt', () {
      final pg = hashPlayGamesId('g1', _salt);
      expect(pg, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(hashPlayGamesId('g1', _salt), pg, reason: 'stable');
      expect(hashPlayGamesId('g2', _salt), isNot(pg));
      expect(hashPlayGamesId('', _salt), '');
      expect(hashPlayGamesId('g1', ''), '');
    });

    test('§21.4 each new run stores pg; without Play Games it is ""', () async {
      await build();
      await versus.initialize();
      await versus.submitRun(fixture.summary(30, bestBefore: 120), const Look());
      await signIn(const PlatformPlayer(id: 'g1', displayName: 'Hiesem'));
      await versus.submitRun(fixture.summary(31, bestBefore: 120), const Look());
      await versus.flush();
      expect(backend.writes.map((w) => w.$1.entry.pg), [
        '',
        hashPlayGamesId('g1', _salt),
      ]);
      expect(backend.writes.last.$1.entry.toMap()['pg'], hasLength(64));
    });

    test('§21.5 a candidate with my pg under another uid is never chosen; '
        'runs without pg still match (client)', () async {
      await build();
      await versus.initialize();
      await signIn(const PlatformPlayer(id: 'g1', displayName: 'Hiesem'));
      final mine = hashPlayGamesId('g1', _salt);
      PoolEntry withPg(String uid, String runId, String pg) {
        final e = fixture.pooled(uid, runId, 80, 3);
        return PoolEntry.fromMap({
          ...e.run.toMap(),
          'uid': uid,
          'level': 3,
          'pg': pg,
        })!;
      }

      for (var s = 0; s < VersusConfig.shards; s++) {
        backend.pools['3_$s'] = [withPg('old-anon', 'ghost$s', mine)];
      }
      backend.pools['3_0'] = [
        ...backend.pools['3_0']!,
        fixture.pooled('b', 'nopg', 80, 3),
      ];
      final seen = <String>{};
      for (var i = 0; i < 6; i++) {
        versus.onRunStart();
        await versus.searchForStart();
        final o = versus.takeOpponent();
        if (o != null) seen.add(o.runId);
      }
      expect(seen, {'nopg'}, reason: 'never a ghost run of mine');

      // matcher level: only my-pg runs under other uids → solo.
      final (tier, _) = matchCandidates(
        [PoolCandidate(withPg('old-anon', 'g', mine))],
        myLevel: 3,
        myBest: 120,
        myUid: 'me',
        myPg: mine,
      );
      expect(tier, MatchTier.solo);
    });
  });

  group('§21.4 account switch', () {
    test('§21.5 a credential-already-in-use link deletes the anonymous uid\'s '
        'runs before the switch', () async {
      await build();
      await versus.initialize();
      backend.pools['3_0'] = [fixture.pooled('anon', 'mine1', 50, 3)];
      backend.switchTo = 'owner';
      await signIn(const PlatformPlayer(id: 'g1', displayName: 'Hiesem'));
      expect(backend.deletedOnlineUids, ['anon'], reason: 'deleted as anon');
      expect(backend.myUid, 'owner');
      expect(backend.pools['3_0'], isEmpty);
    });

    test('§21.5 a failing delete does not block the switch', () async {
      await build();
      await versus.initialize();
      backend
        ..switchTo = 'owner'
        ..deleteOnlineFails = true;
      await signIn(const PlatformPlayer(id: 'g1', displayName: 'Hiesem'));
      expect(backend.deletedOnlineUids, isEmpty);
      expect(backend.myUid, 'owner');
      expect(backend.linked, isTrue);
    });
  });

  group('§21.5 looks', () {
    test('§21.5 a non-default look in all five layers survives upload → pool '
        '→ matching → lookFromMap, id for id; the emblem is levelFor(best)',
        () async {
      await build();
      await versus.initialize();
      await versus.submitRun(fixture.summary(60, bestBefore: 50), _fancy);
      await versus.flush();
      final uploaded = backend.writes.single.$1.entry;
      // The wire map (Firestore) → the server's verbatim pool copy.
      final wire = jsonDecode(jsonEncode(uploaded.toMap(ts: 0))) as Map;
      final pooled = PoolEntry.fromMap({
        ...wire,
        'ts': DateTime.utc(2026, 10, 13),
        'uid': 'other',
        'level': levelFor(uploaded.best),
      })!;
      expect(lookToMap(pooled.run.look), {
        'bird': 'grape',
        'gear': 'shades',
        'hat': 'cap',
        'hoop': 'neon',
        'trail': 'bubbles',
      });
      final opp = pooled.toOpponent();
      expect(opp.look, _fancy);
      expect(opp.level, levelFor(uploaded.best));
    });
  });
}

class _FailingUpload extends fixture.FakeBackend {
  _FailingUpload({super.myUid});
  @override
  Future<String> uploadAvatar(Uint8List jpeg) async =>
      throw StateError('storage unavailable');
}
