import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../run/config/versus_config.dart';

/// PRD-2.3 §21.4 / §0 item 7: where the app salt of the hashed Play Games
/// id comes from. The salt is a random 32-byte value generated at deploy
/// time and kept in Remote Config ([VersusConfig.pgSaltKey]), never in the
/// repo. Implementations never throw: '' = unknown (runs then store no
/// `pg` and match as before).
abstract class PgSaltSource {
  Future<String> salt();
}

/// Tests: a fixed (fake) salt.
class FixedPgSalt implements PgSaltSource {
  const FixedPgSalt(this.value);
  final String value;
  @override
  Future<String> salt() async => value;
}

/// The app: the Remote Config parameter [VersusConfig.pgSaltKey], fetched
/// once per process (time-boxed). Only built from the Firebase versus
/// service, after `Firebase.initializeApp`.
class RemoteConfigPgSalt implements PgSaltSource {
  RemoteConfigPgSalt({this.timeout = VersusConfig.callTimeout});

  final Duration timeout;
  Future<String>? _value;

  @override
  Future<String> salt() => _value ??= _load().then((v) {
    if (v.isEmpty) _value = null; // try again next time
    return v;
  });

  Future<String> _load() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      var v = rc.getString(VersusConfig.pgSaltKey);
      if (v.isEmpty) {
        await rc.fetchAndActivate().timeout(timeout);
        v = rc.getString(VersusConfig.pgSaltKey);
      }
      return v.trim();
    } catch (_) {
      return '';
    }
  }
}

/// PRD-2.3 §21.4 `pg`: SHA-256 of the Play Games player id plus the app
/// salt, lowercase hex (64 characters); '' when either is missing.
String hashPlayGamesId(String playerId, String salt) {
  if (playerId.isEmpty || salt.isEmpty) return '';
  return sha256.convert(utf8.encode('$playerId$salt')).toString();
}
