import 'package:flutter_test/flutter_test.dart';

import '../game_services_test.dart' show FakeGameServices;

/// 2.4.0 (24) Pixel 8: signed in to Play Games, but the game counted the
/// player as signed out (generated name, in-game achievement toast) until a
/// leaderboard tap. games_services asks isAuthenticated only once at
/// launch; [GameServices.recheckSignIn] asks again, silently, on Android.
void main() {
  FakeGameServices make({required bool android, required bool authed}) {
    final s = FakeGameServices()..isAndroidPlatform = () => android;
    s.authenticated = authed;
    return s;
  }

  test('Android, signed in to Play Games but the stream said signed out: '
      'one silent sign-in fetches the player', () async {
    final s = make(android: true, authed: true)..markInitialized();
    await s.recheckSignIn('test');
    expect(s.authChecks, 1);
    expect(s.signInCalls, 1);
  });

  test('Android, not signed in to Play Games: no sign-in call (never the '
      'profile picker)', () async {
    final s = make(android: true, authed: false)..markInitialized();
    await s.recheckSignIn('test');
    expect(s.authChecks, 1);
    expect(s.signInCalls, 0);
  });

  test('already signed in: nothing is asked', () async {
    final s = make(android: true, authed: true)
      ..markInitialized()
      ..debugSetPlayer('P:1');
    await s.recheckSignIn('test');
    expect(s.authChecks, 0);
    expect(s.signInCalls, 0);
  });

  test('iOS (Game Center: authenticateAtLaunch) and tests: a no-op', () async {
    final s = make(android: false, authed: true)..markInitialized();
    await s.recheckSignIn('test');
    expect(s.authChecks, 0);
    expect(s.signInCalls, 0);
  });

  test('concurrent requests fold into one check', () async {
    final s = make(android: true, authed: true)..markInitialized();
    await Future.wait([
      s.recheckSignIn('a'),
      s.recheckSignIn('b'),
      s.recheckSignIn('c'),
    ]);
    expect(s.authChecks, 1);
    expect(s.signInCalls, 1);
  });

  test('a failing check never throws and signs nothing in', () async {
    final s = make(android: true, authed: true)
      ..markInitialized()
      ..authThrows = true;
    await s.recheckSignIn('test');
    expect(s.signInCalls, 0);
  });
}
