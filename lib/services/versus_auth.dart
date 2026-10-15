import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// PRD-2.3.1 §2 the Firebase Auth calls of the versus start-up and the Play
/// Games link, behind a small port so the account switch (fresh code, clean
/// up only with a fresh credential, never staying on a deleted user) is
/// unit-tested with a fake (`test/p231/s1_versus_switch_test.dart`). Only
/// [FirebaseVersusBackend] uses it.
abstract class VersusAuth {
  /// The signed-in uid, or null when signed out.
  String? get uid;

  /// Whether the signed-in user is anonymous (a guest).
  bool get isAnonymous;

  /// Whether the signed-in user is linked to Play Games.
  bool get linkedToPlayGames;

  /// The signed-in user's photo URL, or ''.
  String get photoUrl;

  Future<void> signInAnonymously();
  Future<void> signInWithCredential(AuthCredential credential);

  /// `linkWithCredential` on the signed-in user.
  Future<void> linkWithCredential(AuthCredential credential);
  Future<void> signOut();

  /// Reloads the signed-in user from the server. A user deleted on the
  /// server throws a [FirebaseAuthException] with one of [deadUserCodes].
  Future<void> reload();

  /// Forces an id-token refresh (same throws as [reload]).
  Future<void> refreshToken();
}

/// PRD-2.3.1 §2.3 the Auth error codes of a persisted user that no longer
/// exists (or can no longer be used) on the server.
const Set<String> deadUserCodes = {
  'user-not-found',
  'user-token-expired',
  'user-disabled',
  'invalid-user-token',
};

/// The FlutterFire implementation (lazy: constructing it never touches
/// Firebase).
class FirebaseVersusAuth implements VersusAuth {
  FirebaseVersusAuth({this.app});

  final FirebaseApp? app;

  FirebaseAuth get _auth =>
      app == null ? FirebaseAuth.instance : FirebaseAuth.instanceFor(app: app!);

  @override
  String? get uid => _auth.currentUser?.uid;

  @override
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  /// Linked to the platform's game account: Play Games on Android, Game
  /// Center on iOS (`gc.apple.com`). Checking only Play Games made every
  /// iOS launch re-link an already linked account (`provider-already-linked`).
  @override
  bool get linkedToPlayGames =>
      _auth.currentUser?.providerData.any(
        (p) =>
            p.providerId == PlayGamesAuthProvider.PROVIDER_ID ||
            p.providerId == GameCenterAuthProvider.PROVIDER_ID,
      ) ??
      false;

  @override
  String get photoUrl => _auth.currentUser?.photoURL ?? '';

  @override
  Future<void> signInAnonymously() => _auth.signInAnonymously();

  @override
  Future<void> signInWithCredential(AuthCredential credential) =>
      _auth.signInWithCredential(credential);

  @override
  Future<void> linkWithCredential(AuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) throw FirebaseAuthException(code: 'no-current-user');
    await user.linkWithCredential(credential);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> reload() async => _auth.currentUser?.reload();

  @override
  Future<void> refreshToken() async => _auth.currentUser?.getIdToken(true);
}
