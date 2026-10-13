import 'dart:async';

import '../game/config.dart';
import '../game/storage.dart';

/// PRD-2.3 §18.2 the new-player ad grace: no interstitial until the player
/// has finished [Config.adsGraceRuns] runs or has [Config.adsGraceSeconds]
/// of foreground playtime since install, whichever comes first. Both
/// counters only grow (Delete my data keeps them), so the grace ends for
/// good.
abstract final class AdGrace {
  /// Whether the grace covers an interstitial decision with [runs] finished
  /// runs (the run that just ended included) and [playtimeSeconds] played.
  static bool active({required int runs, required int playtimeSeconds}) =>
      runs < Config.adsGraceRuns && playtimeSeconds < Config.adsGraceSeconds;
}

/// PRD-2.3 §18.3 the playtime counter: every second the app is in the
/// foreground (`AppLifecycleState.resumed`, outside full-screen ads) counts
/// until the grace has ended. The caller ([FlappySpikesGame.update]) passes
/// the frame's time only when those hold.
///
/// Saved every [saveEvery] counted seconds, on going to the background
/// ([flush]) and at run end ([flush]), so a crash loses at most 10 s.
class PlaytimeCounter {
  PlaytimeCounter(this._storage);

  /// Seconds between two writes while counting.
  static const double saveEvery = 10;

  final GameStorage _storage;

  /// The part of a second not yet added to [GameStorage.playtimeSeconds].
  double _fraction = 0;

  /// Counted seconds since the last write.
  double _sinceSave = 0;

  /// Counted since the last write (no write when nothing changed).
  bool _dirty = false;

  /// Whether time still counts (the new-player grace has not ended).
  bool get counting => AdGrace.active(
    runs: _storage.gamesPlayed,
    playtimeSeconds: _storage.playtimeSeconds,
  );

  /// Adds [dt] seconds of foreground time (no-op once the grace has ended).
  /// Writes every [saveEvery] counted seconds in every counted state, runs
  /// and results included (PRD-2.3 §18.3, S8-09).
  void advance(double dt) {
    if (dt <= 0 || !counting) return;
    _fraction += dt;
    _sinceSave += dt;
    if (_fraction >= 1) {
      final whole = _fraction.floor();
      _fraction -= whole;
      _storage.playtimeSeconds += whole;
      _dirty = true;
    }
    if (_sinceSave >= saveEvery) {
      _sinceSave = 0;
      unawaited(flush());
    }
  }

  /// Writes the current value when it changed (background, run end, the Home
  /// arrival after a run, every [saveEvery] counted seconds).
  Future<void> flush() {
    _sinceSave = 0;
    if (!_dirty) return Future.value();
    _dirty = false;
    return _storage.savePlaytimeSeconds(_storage.playtimeSeconds);
  }
}
