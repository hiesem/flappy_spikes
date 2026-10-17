import 'dart:async';

import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Audit A3-2: games_services 5.1.0 (Auth.kt) keeps ONE pending sign-in
/// result: a second signIn() overwrites the first MethodChannel.Result,
/// which then never completes. This fake mirrors that.
class SinglePendingServices extends GameServices {
  Completer<void>? _pending;
  int signInCalls = 0;
  int maxConcurrent = 0;
  int _inFlight = 0;
  int shown = 0;

  @override
  Future<bool> isAuthenticatedPlugin() async => true;

  @override
  Future<void> signInPlugin() {
    signInCalls++;
    _inFlight++;
    if (_inFlight > maxConcurrent) maxConcurrent = _inFlight;
    final c = Completer<void>();
    _pending = c; // the previous Result is lost (never completed)
    return c.future.whenComplete(() => _inFlight--);
  }

  /// The native sign-in pipeline finishes.
  void nativeSignInDone() {
    _pending?.complete();
    _pending = null;
  }

  @override
  Future<void> showLeaderboardsPlugin() async => shown++;

  @override
  Future<void> showAchievementsPlugin() async => shown++;
}

SinglePendingServices _services() => SinglePendingServices()
  ..isAndroidPlatform = (() => true)
  ..pluginTimeout = const Duration(milliseconds: 300)
  ..markInitialized();

void main() {
  test('A3-2 leaderboard tap, then the resume recheck: one sign-in, the '
      'leaderboard opens', () async {
    final s = _services();
    final tap = s.showLeaderboards();
    final recheck = s.recheckSignIn('resume');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    s.nativeSignInDone();
    expect(await tap, ShowLeaderboardResult.opened);
    await recheck;
    expect(s.maxConcurrent, 1);
    expect(s.shown, 1);
  });

  test('A3-2 achievements tap, then the resume recheck: one sign-in, the '
      'list opens', () async {
    final s = _services();
    final tap = s.showAchievements();
    final recheck = s.recheckSignIn('resume');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    s.nativeSignInDone();
    expect(await tap, ShowAchievementsResult.opened);
    await recheck;
    expect(s.maxConcurrent, 1);
  });

  test('A3-2 a recheck already signing in, then a leaderboard tap: the tap '
      'waits for it instead of overlapping', () async {
    final s = _services();
    final recheck = s.recheckSignIn('resume');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(s.signInCalls, 1, reason: 'the recheck is signing in');
    final tap = s.showLeaderboards();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    s.nativeSignInDone();
    await recheck;
    // The tap may sign in once more afterwards (silent for a signed-in
    // player), but never at the same time.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    s.nativeSignInDone();
    expect(await tap, ShowLeaderboardResult.opened);
    expect(s.maxConcurrent, 1);
  });
}
