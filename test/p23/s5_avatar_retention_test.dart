import 'dart:convert';
import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/services/identity.dart';
import 'package:flappy_spikes/services/pg_salt.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../versus/s3_13_service_test.dart' as fixture;

/// PRD-2.3 §5.5 / §21.3 (S8-06): the server deletes the picture with the
/// player doc (≈ 60 days after the last run), so the client uploads an
/// unchanged picture again once its last upload is older than
/// [VersusConfig.avatarRefresh].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final icon = base64Encode(img.encodePng(img.Image(width: 64, height: 64)));

  Future<(FirebaseVersusService, fixture.FakeBackend, fixture.FakeIdentity)>
  build(GameStorage storage) async {
    final backend = fixture.FakeBackend(myUid: 'anon');
    final identity = fixture.FakeIdentity();
    final versus = FirebaseVersusService(
      storageOf: () => storage,
      backend: backend,
      identity: identity,
      random: Random(5),
      pgSalt: const FixedPgSalt('salt'),
    );
    await versus.initialize();
    return (versus, backend, identity);
  }

  Future<void> signIn(
    FirebaseVersusService v,
    fixture.FakeIdentity identity,
  ) async {
    identity.controller.add(
      PlatformPlayer(id: 'g1', displayName: 'Me', iconImage: icon),
    );
    for (var i = 0; i < 2; i++) {
      await Future<void>.delayed(Duration.zero);
      await v.settleIdentity();
    }
  }

  test('S8-06 an unchanged picture is uploaded again after the refresh '
      'period, not before; the upload time survives a restart', () async {
    SharedPreferences.setMockInitialValues({'bestScore': 120});
    var now = DateTime(2026, 10, 13);
    final storage = GameStorage(clock: () => now);
    await storage.load();
    final (v, backend, identity) = await build(storage);
    await signIn(v, identity);
    expect(backend.avatarUploads, hasLength(1));
    expect(storage.versusAvatarAt, now);

    // A restart within the period: same picture, no upload.
    now = now.add(VersusConfig.avatarRefresh - const Duration(days: 1));
    final reloaded = GameStorage(clock: () => now);
    await reloaded.load();
    expect(reloaded.versusAvatarAt, DateTime(2026, 10, 13));
    final (v2, backend2, identity2) = await build(reloaded);
    await signIn(v2, identity2);
    expect(backend2.avatarUploads, isEmpty);

    // Past the period: uploaded again (the server may have deleted it).
    now = now.add(const Duration(days: 2));
    final (v3, backend3, identity3) = await build(reloaded);
    await signIn(v3, identity3);
    expect(backend3.avatarUploads, hasLength(1));
    expect(reloaded.versusAvatarAt, now);
  });

  test('S8-06 a record saved without an upload time is refreshed once', () async {
    SharedPreferences.setMockInitialValues({
      'bestScore': 120,
      'versusAvatar': jsonEncode({'uid': 'anon', 'hash': 'x', 'url': 'u'}),
    });
    final storage = GameStorage();
    await storage.load();
    expect(storage.versusAvatar, isNotNull);
    expect(storage.versusAvatarAt, isNull);
  });
}
