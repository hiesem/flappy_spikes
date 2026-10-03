import 'dart:async';
import 'dart:math';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:games_services/games_services.dart';

import '../firebase_options.dart';

/// Outcome of a [GameServices.showLeaderboards] call, so the game can tell
/// "opened fine" apart from the different failure modes (and from "not a
/// failure at all" states where no user message should appear).
enum ShowLeaderboardResult {
  /// The native leaderboard UI was presented.
  opened,

  /// The interactive sign-in behind the leaderboard button failed or timed
  /// out.
  signInFailed,

  /// Sign-in was fine but the native leaderboard UI failed to open.
  leaderboardFailed,

  /// The service was never initialized (tests, unconfigured builds): the
  /// call was a no-op by design, not a failure.
  unavailable,

  /// A previous call is still in flight (double-tap guard).
  busy,
}

/// Firebase Analytics + platform leaderboards (Google Play Games on Android,
/// Game Center on iOS), wrapped so the rest of the game never touches plugin
/// APIs directly.
///
/// The default instance is a NO-OP: [initialize] is only called from main().
/// Unit tests and unconfigured builds therefore run the full game without any
/// plugin side effects — every plugin call is additionally gated on the
/// [_initialized] flag, so a never-initialized instance never even reaches
/// the method channel. Every plugin call is also individually guarded and
/// time-boxed: services must never take the game down.
class GameServices {
  FirebaseAnalytics? _analytics;
  bool _signedIn = false;
  bool _initialized = false;
  bool _leaderboardBusy = false;

  /// Kept alive for the app's lifetime on purpose: the subscription keeps the
  /// plugin's native auth listener active so [_signedIn] tracks sign-ins.
  // ignore: unused_field
  StreamSubscription<PlayerData?>? _playerSub;

  /// Upper bound on any single plugin call. The plugin is documented to hang
  /// forever in some flows (games_services #197, #221: a second signIn()
  /// overwrites the first MethodChannel.Result, which then never completes);
  /// a timeout is the only way to turn a hang into a reportable event.
  /// Injectable in tests so they don't wait out the real 10 s.
  @visibleForTesting
  Duration pluginTimeout = const Duration(seconds: 10);

  /// Game Center leaderboard ID (App Store Connect). Same ID the 2014
  /// original used.
  static const String iosLeaderboardId = 'flappy_spikes_leaderboard';

  /// Google Play Games leaderboard ID (Play Console, "Top Scores").
  static const String androidLeaderboardId = 'CgkIsZz8pvUOEAIQAA';

  /// Initializes Firebase Analytics and starts tracking the game-service
  /// sign-in state. Any failure leaves the service a no-op.
  ///
  /// This NEVER requests sign-in: an explicit sign-in call at launch makes
  /// Play Games show its profile-picker popup when it cannot sign in
  /// silently (multiple profiles, no default picked). Play Games v2 signs
  /// returning players in automatically, and new players are only prompted
  /// when they tap a leaderboard button ([showLeaderboards]).
  ///
  /// Sign-in state comes from the plugin's player stream, kept alive for the
  /// app's lifetime: native code pushes auth changes there (after automatic
  /// and explicit sign-ins). `GameAuth.isSignedIn` is deliberately NOT used —
  /// in games_services 5.1.0 it completes with the STALE cached player before
  /// the real native check lands, i.e. false on every cold call.
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
      _playerSub = GameAuth.player.listen((player) {
        _signedIn = player != null;
      });
    } catch (_) {
      _signedIn = false;
    }
    // Set even when the plugin setup above failed: initialize() having RUN is
    // what distinguishes the real app from tests/unconfigured builds.
    _initialized = true;
  }

  /// Test seam: simulates a main()-initialized service without touching
  /// plugins (the game-level spy overrides the public methods anyway).
  @visibleForTesting
  void markInitialized() {
    _initialized = true;
  }

  void logGameStart() => logEvent('game_start');

  void logGameOver({required int score, required int bestScore}) =>
      logEvent('game_over', {'score': score, 'best_score': bestScore});

  void logNewBest(int score) => logEvent('new_best', {'score': score});

  void logShareScore(int score) => logEvent('share_score', {'score': score});

  /// Menu / economy analytics (PRD-1 §6: coins_earned, shop_open,
  /// home_slot_shown, ...). Goes through [logEvent], so test spies that
  /// override it see these too.
  void track(String name, [Map<String, Object>? parameters]) =>
      logEvent(name, parameters);

  /// Non-private so tests can record events instead of sending them;
  /// production behavior is unchanged (analytics, try/caught).
  @visibleForTesting
  void logEvent(String name, [Map<String, Object>? parameters]) {
    try {
      _analytics?.logEvent(name: name, parameters: parameters);
    } catch (_) {
      // Analytics must never affect gameplay.
    }
  }

  // --- plugin seams (overridable in tests) --------------------------------

  @visibleForTesting
  Future<void> signInPlugin() async {
    await GameAuth.signIn();
  }

  @visibleForTesting
  Future<void> showLeaderboardsPlugin() async {
    await Leaderboards.showLeaderboards(
      androidLeaderboardID: androidLeaderboardId,
      iOSLeaderboardID: iosLeaderboardId,
    );
  }

  @visibleForTesting
  Future<void> submitScorePlugin(int value) async {
    await Leaderboards.submitScore(
      score: Score(
        androidLeaderboardID: androidLeaderboardId,
        iOSLeaderboardID: iosLeaderboardId,
        value: value,
      ),
    );
  }

  // --- error reporting -----------------------------------------------------

  /// Reports a plugin failure to Analytics (and logcat in debug builds).
  ///
  /// Plugin error codes to expect (see the plugin's PluginError.kt):
  /// `failed_to_authenticate`, `not_authenticated`, `leaderboard_not_found`,
  /// `failed_to_send_score`, `operation_canceled`.
  ///
  /// Diagnostic note: `failed_to_authenticate` with an EMPTY message means
  /// Google returned a well-formed *unauthenticated* result — in practice a
  /// configuration problem (unpublished PGS project / consent screen still in
  /// Testing / SHA-1 mismatch), not a transient error. That is the exact
  /// signature the 2026-07 production outage produced.
  void _reportPgsError(String op, Object error) {
    final String code;
    String message;
    if (error is PlatformException) {
      code = error.code;
      message = error.message ?? '';
    } else if (error is TimeoutException) {
      code = 'timeout';
      message = '';
    } else {
      code = 'unknown';
      message = error.toString();
    }
    // Analytics parameter values are capped at 100 chars — truncate at 90.
    message = message.substring(0, min(90, message.length));
    debugPrint('GameServices pgs_error: op=$op code=$code message=$message');
    logEvent('pgs_error', {'op': op, 'code': code, 'message': message});
  }

  // --- leaderboards ---------------------------------------------------------

  /// Submits [value] to the platform leaderboard (called with the local best
  /// after every game; the service keeps each player's single highest score).
  ///
  /// Attempted even when the local sign-in state is unknown: Play Games v2
  /// auto sign-in is not always visible to us, and submitting while signed
  /// out simply fails (reported as `pgs_error`). Never blocks gameplay, never
  /// requests interactive sign-in, and deliberately never gates on a
  /// `getPlayerScore()` read-back: brand-new Play Games players return null
  /// there while the backend provisions them, which would silently drop
  /// scores (games_services #202).
  Future<void> submitBestScore(int value) async {
    if (!_initialized) {
      return;
    }
    try {
      await submitScorePlugin(value).timeout(pluginTimeout);
    } catch (e) {
      _reportPgsError('submit_score', e);
    }
  }

  /// Opens the platform's native leaderboard UI, attempting sign-in first.
  ///
  /// Re-entrant-safe: the plugin keeps a SINGLE pendingOperation, so a second
  /// concurrent signIn() would overwrite the first MethodChannel.Result and
  /// hang it forever — a double-tap on the small leaderboard button would
  /// deadlock the call. The [_leaderboardBusy] guard returns
  /// [ShowLeaderboardResult.busy] instead, and every plugin call is
  /// time-boxed by [pluginTimeout].
  Future<ShowLeaderboardResult> showLeaderboards() async {
    if (!_initialized) {
      return ShowLeaderboardResult.unavailable;
    }
    if (_leaderboardBusy) {
      return ShowLeaderboardResult.busy;
    }
    _leaderboardBusy = true;
    try {
      if (!_signedIn) {
        try {
          await signInPlugin().timeout(pluginTimeout);
          // A completed signIn() means the player is authenticated — the
          // plugin only succeeds then (see its Auth.kt). Do NOT double-check
          // via GameAuth.isSignedIn (stale-cache race, see [initialize]).
          _signedIn = true;
        } catch (e) {
          _reportPgsError('sign_in', e);
          return ShowLeaderboardResult.signInFailed;
        }
      }
      try {
        await showLeaderboardsPlugin().timeout(pluginTimeout);
        return ShowLeaderboardResult.opened;
      } catch (e) {
        _reportPgsError('show_leaderboards', e);
        return ShowLeaderboardResult.leaderboardFailed;
      }
    } finally {
      _leaderboardBusy = false;
    }
  }
}
