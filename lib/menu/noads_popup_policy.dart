import '../game/config.dart';
import '../game/storage.dart';

/// Why the No-ads popup shows (`noads_popup_shown` `reason` param).
enum NoAdsPopupReason {
  /// >= [Config.noAdsPopupVideos] rewarded videos since the last show.
  videos,

  /// The previous run set a new best.
  best,

  /// The previous run reached a new level.
  level,

  /// No good moment, but >= [Config.noAdsPopupFallback] since the last show.
  fallback,
}

/// The run-mood values stored in [GameStorage.lastRunMood].
abstract final class RunMood {
  static const String none = '';
  static const String best = 'best';
  static const String level = 'level';
}

/// PRD-menu-v4 §8 / PRD-2.3 §24: when the No-ads upsell may show. Asked at
/// the session-start home arrival (app launch, or a return after
/// >= [Config.sessionGap] in the background — the game tracks that) and on
/// every Home arrival after a run (PRD-2.3 §24.2).
///
/// The window: not to owners, never in the first session, from install
/// day 2 or after [Config.noAdsPopupMinRuns] finished runs, >=
/// [Config.noAdsPopupMinGap] since the last SHOW (PRD-2.3 §24.2: closing no
/// longer restarts the gap), at most [Config.noAdsPopupMaxPerDay] shows per
/// local day, and never right after a run below [Config.noAdsPopupMinScore].
/// Inside it: a good moment (videos, then level, then best — a new level is
/// always a new best too, so the more specific one wins), else the fallback
/// ([Config.noAdsPopupFallback] since the last show). Dismissals are counted
/// for analytics only (no limit).
///
/// The wall clock is [GameStorage.now] shifted by the debug day offset, so
/// the debug panel's "Next day" also moves the hour gaps on.
class NoAdsPopupPolicy {
  NoAdsPopupPolicy(this._storage);

  final GameStorage _storage;

  bool _sessionStarted = false;
  bool _firstSession = false;

  /// Whether the current session is the install's first one (only known
  /// after [startSession]).
  bool get inFirstSession => _firstSession;

  int get _nowMs =>
      _storage.now().millisecondsSinceEpoch +
      _storage.debugDayOffset * Duration.millisecondsPerDay;

  /// A session starts (app launch, or a return after the session gap): the
  /// first call of an install marks that install's first session; every
  /// later one is not first.
  Future<void> startSession() async {
    if (!_sessionStarted) {
      _sessionStarted = true;
      _firstSession = !_storage.firstSessionDone;
    } else {
      _firstSession = false;
    }
    if (!_storage.firstSessionDone) await _storage.saveFirstSessionDone(true);
  }

  /// Shows on today's local day (0 once the day rolled over).
  int get showsToday => _storage.noAdsPopupLastDay == _storage.today
      ? _storage.noAdsPopupShowsToday
      : 0;

  /// Whether the "not too early" rule is met: install day 2 or 10 runs.
  bool get pastWarmUp {
    final installDay = _storage.installDay;
    return (installDay != null && _storage.today > installDay) ||
        _storage.gamesPlayed >= Config.noAdsPopupMinRuns;
  }

  /// The reason to show the popup at this session-start arrival, or null
  /// when it must not show.
  NoAdsPopupReason? evaluate() {
    if (_storage.noAds || !_sessionStarted || _firstSession) return null;
    if (!pastWarmUp) return null;
    final last = _storage.lastScore;
    if (last != null && last < Config.noAdsPopupMinScore) return null;
    final lastMs = _storage.noAdsPopupLastMs;
    final sinceMs = lastMs == 0 ? null : _nowMs - lastMs;
    // PRD-2.3 §24.2: the gap and the fallback both run from the last show.
    if (sinceMs != null &&
        sinceMs < Config.noAdsPopupMinGap.inMilliseconds) {
      return null;
    }
    if (showsToday >= Config.noAdsPopupMaxPerDay) return null;
    if (_storage.noAdsPopupVideos >= Config.noAdsPopupVideos) {
      return NoAdsPopupReason.videos;
    }
    if (_storage.lastRunMood == RunMood.level) return NoAdsPopupReason.level;
    if (_storage.lastRunMood == RunMood.best) return NoAdsPopupReason.best;
    if (sinceMs == null ||
        sinceMs >= Config.noAdsPopupFallback.inMilliseconds) {
      return NoAdsPopupReason.fallback;
    }
    return null;
  }

  /// The popup is on screen: starts the gap, counts the day's show and
  /// clears the good-moment triggers.
  Future<void> markShown() async {
    final today = _storage.today;
    final shows = showsToday + 1;
    await _storage.saveNoAdsPopupLastMs(_nowMs);
    await _storage.saveNoAdsPopupLastDay(today);
    await _storage.saveNoAdsPopupShowsToday(shows);
    await _storage.saveNoAdsPopupVideos(0);
    await _storage.saveLastRunMood(RunMood.none);
  }

  /// A completed rewarded video (powerup slot, free coins, ...).
  Future<void> recordRewardedVideo() =>
      _storage.saveNoAdsPopupVideos(_storage.noAdsPopupVideos + 1);

  /// A finished run: remembers its good moment for the next arrival.
  Future<void> recordRun({required bool newBest, required bool newLevel}) =>
      _storage.saveLastRunMood(
        newLevel
            ? RunMood.level
            : newBest
            ? RunMood.best
            : RunMood.none,
      );

  /// ✕ / dim / back / Esc: counts the dismissal (analytics only — no
  /// limit since PRD-menu-v4 §8). PRD-2.3 §24.2: it no longer restarts the
  /// gap, which runs from the last show.
  Future<void> markDismissed() async {
    await _storage.saveNoAdsPopupClosedMs(_nowMs);
    await _storage.saveNoAdsPopupDismissals(_storage.noAdsPopupDismissals + 1);
  }
}
