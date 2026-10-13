import 'dart:async';

import '../services/audio_focus.dart';
import 'config.dart';
import 'sound.dart';

/// PRD-2.3 §13.4: the music never stays silent on a menu without a reason
/// that still holds.
///
/// Owned by the game and stepped with the game's clock ([update], so the
/// tests drive it with `stepGame`). It
/// - turns the platform's playback changes ([AudioFocus.changes]) into the
///   music holds: an interruption (call / alarm: music and SFX), a
///   notification sound (music only, resumed right after it ends);
/// - re-checks every [Config.musicTransientPoll] while the music is held
///   for an interruption or a notification, so a finished player that stays
///   listed never keeps the music off;
/// - lets a media sound that started in the foreground count as the
///   player's own music only after [Config.musicMediaSoundOwnAfter], and
///   then only with the two "yes" answers below (S8-04);
/// - confirms "own music" with two "yes" answers
///   [Config.musicOwnConfirmGap] apart (launch, return to the foreground);
/// - re-checks skipped music every [Config.musicOwnRecheckInterval] on a
///   menu (never mid-run, PRD-2.2 §28.3);
/// - clears an ad suspend with no ad showing after
///   [Config.musicSuspendTimeout];
/// - restarts a dead music player (watchdog, every
///   [Config.musicWatchdogInterval] on a menu);
/// - sends `music_held` once per Home visit after
///   [Config.musicHeldReportAfter] of held music with the music setting on.
class MusicGuard {
  MusicGuard({
    required this.sound,
    required this.focus,
    required this.onMenu,
    required this.adShowing,
    required this.adJustEnded,
    required this.otherMusicNow,
    required this.track,
  });

  final SoundService sound;
  final AudioFocus focus;

  /// Home or another menu screen (or the results page): not a live run.
  final bool Function() onMenu;

  /// A full-screen ad is showing.
  final bool Function() adShowing;

  /// A full-screen ad ended within `Config.adAudioSettle`.
  final bool Function() adJustEnded;

  /// The game's "is the player's own music playing?" check.
  final Future<bool> Function() otherMusicNow;

  /// Analytics.
  final void Function(String name, Map<String, Object> params) track;

  StreamSubscription<AudioWatchState>? _sub;
  AudioWatchState _last = const AudioWatchState();

  /// Seconds since the guard started (the game's clock).
  double _t = 0;

  double get time => _t;

  // -- transient holds (interruption, notification, foreground media) --
  double _pollIn = 0;
  bool _polling = false;
  double? _mediaSince;
  double? _notificationSince;

  // -- "own music" --
  _Confirm? _confirm;
  double _ownRecheckIn = Config.musicOwnRecheckInterval;
  bool _ownChecking = false;

  // -- suspend timeout / watchdog --
  double _suspendNoAd = 0;
  double _watchdogIn = Config.musicWatchdogInterval;
  bool _deadSeen = false;

  /// Game time since the music last started / resumed (watchdog grace).
  double _playingSince = 0;
  bool _wasPlaying = false;

  // -- music_held --
  bool _onHome = false;
  bool _heldReported = false;
  double _heldFor = 0;
  String _context = 'launch';
  String? _holdSource;
  String? _pendingSource;

  /// The last `AudioWatch` answer.
  AudioWatchState get lastWatch => _last;

  /// A "two yes" confirmation is pending (tests).
  bool get confirming => _confirm != null;

  void attach() {
    sound.musicWatchLine = () => _last.logLine;
    _sub = focus.changes.listen(apply);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// A playback change from the platform (or a re-check's answer).
  void apply(AudioWatchState s) {
    _last = s;
    sound.setInterrupted(s.interrupted);
    // Only actively playing players count: where the platform cannot say,
    // a media player is confirmed by isMusicActive() (§13.4).
    final media =
        s.media &&
        (s.stateKnown || s.musicActive) &&
        !sound.ownMusicSkipped &&
        !adShowing() &&
        !adJustEnded();
    if (media) {
      _mediaSince ??= _t;
    } else {
      _mediaSince = null;
    }
    if (s.notification) {
      _notificationSince ??= _t;
    } else {
      _notificationSince = null;
    }
    var notification = s.notification;
    // A notification player whose state the platform cannot give, still
    // listed long after any ding has ended, no longer holds the music.
    final since = _notificationSince;
    if (notification &&
        !s.stateKnown &&
        since != null &&
        _t - since >= Config.musicUnknownNotificationMaxHold) {
      notification = false;
    }
    sound.setOtherSound(notification || _mediaHolds);
  }

  /// A foreground media sound holds the music once it has played
  /// [Config.musicMediaSoundDebounce] (ad web views open and close media
  /// players for a few ms).
  bool get _mediaHolds {
    final since = _mediaSince;
    return since != null && _t - since >= Config.musicMediaSoundDebounce;
  }

  // ------------------------------------------------------------ the game

  /// The app came back to the foreground (any source of a later hold).
  void onForeground() => _context = 'foreground';

  /// The app left the foreground: a pending confirmation is dropped.
  void onBackground() => _confirm = null;

  /// Home arrival: a new Home visit for `music_held`.
  void onHomeArrival() {
    _context = 'scene';
    _onHome = true;
    _heldReported = false;
    _heldFor = 0;
  }

  /// Run start: the Home visit ends.
  void onRunStart() {
    _context = 'scene';
    _onHome = false;
    _heldFor = 0;
  }

  /// §13.4 "a yes must be real": "own music" only after two "yes" answers
  /// [Config.musicOwnConfirmGap] apart, the first one [delay] s from now
  /// (0 = at once). [then] runs once it is decided either way.
  void confirmOwnMusic(
    String source, {
    double delay = 0,
    required void Function() then,
  }) {
    final c = _Confirm(source, _t + delay, then);
    _confirm = c;
    if (delay <= 0) _runConfirm(c);
  }

  void _runConfirm(_Confirm c) {
    if (c.busy) return;
    c.busy = true;
    otherMusicNow().then((yes) {
      c.busy = false;
      if (!identical(c, _confirm)) return;
      sound.logMusic('check-${c.source}-${c.stage}:${yes ? 'yes' : 'no'}');
      if (yes && c.stage == 0) {
        c
          ..stage = 1
          ..at = _t + Config.musicOwnConfirmGap;
        return;
      }
      _confirm = null;
      if (yes) {
        _pendingSource = c.source;
        sound.setOtherMusicActive(true);
      }
      c.then();
    });
  }

  void update(double dt) {
    _t += dt;
    final c = _confirm;
    if (c != null && !c.busy && _t >= c.at) _runConfirm(c);
    _transient(dt);
    _ownRecheck(dt);
    _suspendTimeout(dt);
    _watchdog(dt);
    _held(dt);
  }

  void _transient(double dt) {
    if (_mediaHolds && !sound.otherSound) apply(_last);
    final since = _mediaSince;
    if (since != null &&
        _t - since >=
            Config.musicMediaSoundOwnAfter - Config.musicOwnConfirmGap &&
        _confirm == null) {
      // A media sound that keeps playing may be the player's own music,
      // but only with two real "yes" answers from the CURRENT playback
      // (S8-04: the last snapshot can still list a ding that just ended),
      // the second one at [Config.musicMediaSoundOwnAfter]: only audio
      // still playing then can trigger the skip (§13.4).
      confirmOwnMusic(
        _context,
        then: () {
          if (sound.ownMusicSkipped) {
            _mediaSince = null;
          } else if (_mediaSince != null) {
            // Not own music: look again after another full window.
            _mediaSince = _t;
          }
          apply(_last);
        },
      );
    }
    final held =
        sound.interrupted ||
        sound.otherSound ||
        _mediaSince != null ||
        _notificationSince != null;
    if (!held) {
      _pollIn = 0;
      return;
    }
    _pollIn -= dt;
    if (_pollIn > 1e-9 || _polling) return;
    // Accumulated, so float steps never stretch the period by a frame.
    _pollIn =
        _pollIn.clamp(-Config.musicTransientPoll, 0.0) +
        Config.musicTransientPoll;
    _polling = true;
    focus.snapshot().then((s) {
      _polling = false;
      apply(s);
    });
  }

  void _ownRecheck(double dt) {
    if (!sound.ownMusicSkipped ||
        !onMenu() ||
        _confirm != null ||
        adShowing() ||
        adJustEnded()) {
      _ownRecheckIn = Config.musicOwnRecheckInterval;
      return;
    }
    _ownRecheckIn -= dt;
    if (_ownRecheckIn > 1e-9 || _ownChecking) return;
    _ownRecheckIn =
        _ownRecheckIn.clamp(-Config.musicOwnRecheckInterval, 0.0) +
        Config.musicOwnRecheckInterval;
    _ownChecking = true;
    otherMusicNow().then((other) {
      _ownChecking = false;
      if (!other && onMenu()) {
        sound.setOtherMusicActive(false, sceneChange: true);
      }
    });
  }

  void _suspendTimeout(double dt) {
    if (!sound.suspended || adShowing()) {
      _suspendNoAd = 0;
      return;
    }
    _suspendNoAd += dt;
    if (_suspendNoAd > Config.musicSuspendTimeout) {
      _suspendNoAd = 0;
      sound.clearSuspend();
    }
  }

  void _watchdog(double dt) {
    final playing = sound.musicPlaying;
    if (playing && !_wasPlaying) _playingSince = _t;
    _wasPlaying = playing;
    if (!onMenu()) {
      _watchdogIn = Config.musicWatchdogInterval;
      return;
    }
    _watchdogIn -= dt;
    if (_watchdogIn > 1e-9) return;
    _watchdogIn += Config.musicWatchdogInterval;
    if (!sound.musicPlaying) return;
    final state = sound.musicPlayerState;
    if (state == 'playing' || state == 'none') {
      _deadSeen = false;
      return;
    }
    if (_t - _playingSince < Config.musicWatchdogGrace) return;
    _deadSeen = true;
    unawaited(sound.restartMusic());
  }

  void _held(double dt) {
    var reason = sound.musicHoldReason;
    if (reason == null && _deadSeen && sound.musicPlaying) {
      reason = 'player_dead';
    }
    final counting =
        _onHome && reason != null && sound.musicWanted && sound.musicVolume > 0;
    if (!counting) {
      _heldFor = 0;
      _holdSource = null;
      return;
    }
    _holdSource ??= _pendingSource ?? _context;
    _pendingSource = null;
    _heldFor += dt;
    if (_heldReported || _heldFor < Config.musicHeldReportAfter) return;
    _heldReported = true;
    sound.logMusic('music_held:$reason/$_holdSource');
    track('music_held', {'reason': reason, 'source': _holdSource!});
  }
}

class _Confirm {
  _Confirm(this.source, this.at, this.then);

  final String source;
  double at;
  final void Function() then;
  int stage = 0;
  bool busy = false;
}
