import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:games_services/games_services.dart';

import '../run/config/versus_config.dart';

/// The platform games account a player may be signed in to (PRD-2 §3.13
/// "Who plays", ARCH §6.4): its display name, and once signed in the
/// credential that links it to the anonymous Firebase user.
class PlatformPlayer {
  const PlatformPlayer({
    required this.id,
    required this.displayName,
    this.iconImage = '',
  });

  final String id;
  final String displayName;

  /// The icon-size profile image, base64 ('' when none; games_services
  /// 5.1.0 `PlayerData.iconImage`, S6-64).
  final String iconImage;
}

/// Platform identity behind a small interface (ARCH §8: platform code stays
/// in `lib/services/`). Android = Play Games; iOS = Game Center (a stub
/// until iOS work reopens).
abstract class PlatformIdentity {
  /// 'android' | 'ios'.
  String get platform;

  /// The signed-in platform player, or null. Android: the app-lifetime
  /// `GameAuth.player` stream — never `GameAuth.isSignedIn` and never
  /// `GameAuth.signIn()` at launch (CLAUDE.md invariants).
  Stream<PlatformPlayer?> get player;

  /// The Firebase credential of the signed-in player (null when signed out
  /// or unavailable). Never shows any UI.
  Future<AuthCredential?> firebaseCredential();
}

/// Play Games (Android): the player comes from `GameAuth.player`; the link
/// credential is `PlayGamesAuthProvider.credential(serverAuthCode:)` with a
/// server auth code for the OAuth web client id
/// ([VersusConfig.playGamesWebClientId]) from `GameAuth.getAuthCode`
/// (games_services 5.1.0 exposes it; it calls `requestServerSideAccess`,
/// which needs a signed-in player and shows no UI).
class PlayGamesIdentity implements PlatformIdentity {
  PlayGamesIdentity({this.timeout = VersusConfig.callTimeout});

  final Duration timeout;
  PlatformPlayer? _last;

  @override
  String get platform => 'android';

  @override
  Stream<PlatformPlayer?> get player => GameAuth.player.map((p) {
    final id = p?.playerID;
    _last = p == null
        ? null
        : PlatformPlayer(
            id: id ?? '',
            displayName: p.displayName,
            iconImage: p.iconImage ?? '',
          );
    return _last;
  });

  @override
  Future<AuthCredential?> firebaseCredential() async {
    if (_last == null) return null;
    try {
      final code = await GameAuth.getAuthCode(
        VersusConfig.playGamesWebClientId,
      ).timeout(timeout);
      if (code == null || code.isEmpty) return null;
      return PlayGamesAuthProvider.credential(serverAuthCode: code);
    } catch (_) {
      return null;
    }
  }
}

/// Game Center (iOS) — a stub until iOS work is reopened (ARCH §6.4): no
/// player, no credential; iOS players duel with their nickname. Later:
/// `GameCenterAuthProvider.credential()` and the Game Center name/avatar.
class GameCenterIdentity implements PlatformIdentity {
  const GameCenterIdentity();

  @override
  String get platform => 'ios';

  @override
  Stream<PlatformPlayer?> get player => const Stream.empty();

  @override
  Future<AuthCredential?> firebaseCredential() async => null;
}
