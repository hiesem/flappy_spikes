import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:games_services/games_services.dart';

import '../firebase_options.dart';

/// Firebase Analytics + platform leaderboards (Google Play Games on Android,
/// Game Center on iOS), wrapped so the rest of the game never touches plugin
/// APIs directly.
///
/// The default instance is a NO-OP: [initialize] is only called from main().
/// Unit tests and unconfigured builds (no Firebase options or Play Console IDs
/// yet) therefore run the full game without any plugin side effects. Every
/// plugin call is additionally guarded: services must never take the game
/// down.
class GameServices {
  FirebaseAnalytics? _analytics;
  bool _signedIn = false;

  /// Game Center leaderboard ID (App Store Connect). Same ID the 2014
  /// original used.
  static const String iosLeaderboardId = 'flappy_spikes_leaderboard';

  /// Google Play Games leaderboard ID (Play Console, "Top Scores").
  static const String androidLeaderboardId = 'CgkIsZz8pvUOEAIQAA';

  bool get _androidConfigured => !androidLeaderboardId.startsWith('TODO');

  /// Initializes Firebase Analytics and silently signs the player into the
  /// platform game service. Any failure leaves the service a no-op.
  Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _analytics = FirebaseAnalytics.instance;
    } catch (_) {
      _analytics = null;
    }
    try {
      await GameAuth.signIn();
      _signedIn = await GameAuth.isSignedIn;
    } catch (_) {
      _signedIn = false;
    }
  }

  void logGameStart() => _logEvent('game_start');

  void logGameOver({required int score, required int bestScore}) =>
      _logEvent('game_over', {'score': score, 'best_score': bestScore});

  void logNewBest(int score) => _logEvent('new_best', {'score': score});

  void logShareScore(int score) => _logEvent('share_score', {'score': score});

  void _logEvent(String name, [Map<String, Object>? parameters]) {
    try {
      _analytics?.logEvent(name: name, parameters: parameters);
    } catch (_) {
      // Analytics must never affect gameplay.
    }
  }

  /// Submits [value] to the platform leaderboard (called on a new best).
  Future<void> submitBestScore(int value) async {
    if (!_signedIn || (Platform.isAndroid && !_androidConfigured)) {
      return;
    }
    try {
      await Leaderboards.submitScore(
        score: Score(
          androidLeaderboardID: androidLeaderboardId,
          iOSLeaderboardID: iosLeaderboardId,
          value: value,
        ),
      );
    } catch (_) {}
  }

  /// Opens the platform's native leaderboard UI, attempting sign-in first.
  Future<void> showLeaderboards() async {
    if (Platform.isAndroid && !_androidConfigured) {
      return;
    }
    try {
      if (!_signedIn) {
        await GameAuth.signIn();
        _signedIn = await GameAuth.isSignedIn;
      }
      if (!_signedIn) {
        return;
      }
      await Leaderboards.showLeaderboards(
        androidLeaderboardID: androidLeaderboardId,
        iOSLeaderboardID: iosLeaderboardId,
      );
    } catch (_) {}
  }
}
