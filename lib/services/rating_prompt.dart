import 'dart:async';

import 'package:in_app_review/in_app_review.dart';

/// PRD-2.3 §23.4 the platform calls behind [RatingPrompt], so tests can
/// fake them. Implementations may throw; [RatingPrompt] try/catches.
abstract class RatingBackend {
  /// Whether this device can show the store's sheet (Play Store installed on
  /// Android 5+, iOS 10.3+).
  Future<bool> isAvailable();

  /// Asks the store to show its own rating sheet (the store decides whether
  /// it shows: quotas and limits can make it show nothing).
  Future<void> requestReview();
}

/// The real backend: the `in_app_review` package (Google Play's in-app review
/// on Android, Apple's review prompt on iPhone).
class InAppReviewBackend implements RatingBackend {
  const InAppReviewBackend();

  @override
  Future<bool> isAvailable() => InAppReview.instance.isAvailable();

  @override
  Future<void> requestReview() => InAppReview.instance.requestReview();
}

/// PRD-2.3 §23.4 one `RatingPrompt` service around the store's native review
/// sheet. It follows the `GameServices` pattern: the default instance has no
/// backend and is never available (tests, unconfigured builds), so no
/// request is ever made there, and every platform call is try/caught.
///
/// [prepare] asks the platform once (at app start); after it, [available] is
/// a synchronous answer the game can read when it decides on a request, so
/// the cooldown is only written when a request really goes out.
class RatingPrompt {
  RatingPrompt({this.backend});

  /// Null = no store sheet here (tests, the default instance).
  final RatingBackend? backend;

  bool _available = false;

  /// Whether a request can go out now (after [prepare] said so).
  bool get available => _available;

  /// Asks the platform whether the sheet can show. Never throws; false when
  /// there is no backend or the call fails or hangs.
  Future<bool> prepare() async {
    final b = backend;
    if (b == null) return _available = false;
    try {
      _available = await b.isAvailable().timeout(const Duration(seconds: 5));
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  /// Requests the store's sheet. False (nothing requested) when it is not
  /// [available] or the call fails. Never throws.
  Future<bool> request() async {
    final b = backend;
    if (b == null || !_available) return false;
    try {
      await b.requestReview();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// PRD-2.3 §23.2 the pure rules of when a request is due.
abstract final class RatingRules {
  /// The trigger for a finished run: `run5` when it is run [minRuns] itself,
  /// `new_best` when it set a new best after that run, else null (no
  /// request). [runs] is `gamesPlayed` after this run was counted.
  static String? trigger({
    required int runs,
    required bool newBest,
    required int minRuns,
  }) {
    if (runs == minRuns) return 'run5';
    if (runs > minRuns && newBest) return 'new_best';
    return null;
  }

  /// Whether the cooldown lets a request go out: none in the last
  /// [cooldownDays] days. [lastRequestAt] is the stored wall-clock second
  /// (0 = never); [now] the current wall-clock time.
  static bool cooldownOver({
    required int lastRequestAt,
    required DateTime now,
    required Duration cooldown,
  }) {
    if (lastRequestAt <= 0) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(lastRequestAt * 1000);
    return now.difference(last) >= cooldown;
  }
}
