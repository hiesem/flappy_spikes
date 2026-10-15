import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// PRD-2.2 §28.3: other apps' audio, observed WITHOUT taking audio focus
/// (the game keeps mixing with the player's own music).
///
/// - [interruptions]: true while another app's call, ringtone, alarm or
///   assistant is playing (the game pauses its music and mutes its sound
///   effects), false when it ends.
/// - [isOtherMusicActive]: someone else's music is playing right now
///   (checked at launch, on foreground and at scene changes while the game
///   music is skipped). On Android this includes the `isMusicActive()`
///   stream fallback, which also counts the game's own sound effects.
/// - [isOtherMediaListed]: only the public playback list (other apps'
///   media players, never the game's `USAGE_GAME` players). The game asks
///   it when [isOtherMusicActive] said yes while its own sound was ringing
///   (S7-13, docs/p22/ADS.md).
///
/// Android: `flappy_spikes/audio` in `MainActivity.kt` (an
/// `AudioPlaybackCallback` + audio-mode listener for the interruptions,
/// `AudioManager.isMusicActive()` for the music check). iOS: the same
/// channels in `AppDelegate.swift` (`AudioWatch`): `AVAudioSession`
/// interruptions for `interrupted`, `secondaryAudioShouldBeSilencedHint`
/// (another app's non-mixable audio, never the game's own) for the music
/// checks and `media`; `notification` is always false there. Every call is
/// guarded: audio checks never take the game down.
abstract class AudioFocus {
  Stream<bool> get interruptions;

  Future<bool> isOtherMusicActive();

  /// Another app's media player is listed as playing (no stream fallback).
  Future<bool> isOtherMediaListed();

  /// PRD-2.3 §13.4: every change of the other apps' audio (interruption,
  /// notification sound, media player), pushed by the platform's playback
  /// callback.
  Stream<AudioWatchState> get changes;

  /// PRD-2.3 §13.4: the state right now (the 0.5 s re-check while the
  /// music is held for an interruption or a notification).
  Future<AudioWatchState> snapshot();

  /// PRD-2.3 §13.3: one line of the music diagnostic log (Android: logcat
  /// tag `FS-Music`).
  void log(String line);
}

/// PRD-2.3 §13.3 / §13.4: other apps' audio as `AudioWatch` sees it.
@immutable
class AudioWatchState {
  const AudioWatchState({
    this.interrupted = false,
    this.notification = false,
    this.media = false,
    this.musicActive = false,
    this.stateKnown = true,
    this.players = const [],
  });

  /// A call / ringtone / alarm / assistant plays (or the audio mode is a
  /// call): the music pauses and the sound effects go quiet.
  final bool interrupted;

  /// A notification sound plays (any `NOTIFICATION*` usage): the music
  /// pauses, the sound effects keep playing.
  final bool notification;

  /// Another app's `MEDIA` / `UNKNOWN` player plays.
  final bool media;

  /// `AudioManager.isMusicActive()` (also counts the game's own sounds).
  final bool musicActive;

  /// Whether the platform gave every listed player's state (else listed
  /// players count as playing).
  final bool stateKnown;

  /// The raw playback list, `usage:state` (1 playing, 0 listed but not
  /// playing, ? unknown).
  final List<String> players;

  static AudioWatchState fromPlatform(Object? e) {
    if (e is Map) {
      return AudioWatchState(
        interrupted: e['interrupted'] == true,
        notification: e['notification'] == true,
        media: e['media'] == true,
        musicActive: e['musicActive'] == true,
        stateKnown: e['stateKnown'] != false,
        players: [for (final p in (e['players'] as List?) ?? const []) '$p'],
      );
    }
    // A bare bool (2.2 payload): the interruption flag.
    return AudioWatchState(interrupted: e == true);
  }

  /// The diagnostic-log form: `[5:1,1:0] music=1 known=1`.
  String get logLine =>
      '[${players.join(',')}] music=${musicActive ? 1 : 0}'
      '${stateKnown ? '' : ' known=0'}';
}

/// Tests, Linux: nothing is ever interrupted.
class NoopAudioFocus implements AudioFocus {
  const NoopAudioFocus();

  @override
  Stream<bool> get interruptions => const Stream<bool>.empty();

  @override
  Future<bool> isOtherMusicActive() async => false;

  @override
  Future<bool> isOtherMediaListed() async => false;

  @override
  Stream<AudioWatchState> get changes => const Stream<AudioWatchState>.empty();

  @override
  Future<AudioWatchState> snapshot() async => const AudioWatchState();

  @override
  void log(String line) {}
}

/// Scriptable in tests.
class FakeAudioFocus implements AudioFocus {
  final StreamController<bool> _events = StreamController<bool>.broadcast();
  final StreamController<AudioWatchState> _changes =
      StreamController<AudioWatchState>.broadcast();

  /// What [isOtherMusicActive] answers.
  bool otherMusic = false;

  int checks = 0;

  /// PRD-2.3 §13.5: the scripted playback state ([snapshot]); [push]
  /// also sends it as a change.
  AudioWatchState state = const AudioWatchState();

  /// Snapshots taken so far.
  int snapshots = 0;

  /// Lines given to [log].
  final List<String> logged = [];

  /// Fires an interruption start (true) or end (false).
  void interrupt(bool on) {
    state = AudioWatchState(
      interrupted: on,
      notification: state.notification,
      media: state.media,
      players: state.players,
    );
    _events.add(on);
    _changes.add(state);
  }

  /// PRD-2.3 §13.5: sets [next] as the playback state; with [notify] the
  /// platform callback fires (a player started / stopped / was released).
  /// Without it, only the re-check sees it (a finished player that stays
  /// listed changes nothing the callback would report).
  void push(AudioWatchState next, {bool notify = true}) {
    state = next;
    if (notify) _changes.add(next);
  }

  @override
  Stream<bool> get interruptions => _events.stream;

  @override
  Stream<AudioWatchState> get changes => _changes.stream;

  @override
  Future<AudioWatchState> snapshot() async {
    snapshots++;
    return state;
  }

  @override
  void log(String line) => logged.add(line);

  @override
  Future<bool> isOtherMusicActive() async {
    checks++;
    return otherMusic;
  }

  /// The scripted other music is another app's listed media player.
  @override
  Future<bool> isOtherMediaListed() async => otherMusic;
}

/// The Android and iOS implementation (MethodChannel + EventChannel; one
/// channel protocol, MainActivity.kt / AppDelegate.swift).
class PlatformAudioFocus implements AudioFocus {
  static const MethodChannel _methods = MethodChannel('flappy_spikes/audio');
  static const EventChannel _events = EventChannel(
    'flappy_spikes/audio_interruptions',
  );

  Stream<AudioWatchState>? _stream;

  @override
  Stream<AudioWatchState> get changes => _stream ??= _events
      .receiveBroadcastStream()
      .map(AudioWatchState.fromPlatform)
      .handleError((Object e) {
        debugPrint('AudioFocus changes failed: $e');
      })
      .asBroadcastStream();

  @override
  Stream<bool> get interruptions =>
      changes.map((s) => s.interrupted).distinct();

  @override
  Future<AudioWatchState> snapshot() async {
    try {
      return AudioWatchState.fromPlatform(
        await _methods.invokeMethod<Object?>('snapshot'),
      );
    } catch (e) {
      debugPrint('AudioFocus snapshot failed: $e');
      return const AudioWatchState();
    }
  }

  @override
  void log(String line) {
    unawaited(
      _methods.invokeMethod<void>('log', line).catchError((Object _) {}),
    );
  }

  @override
  Future<bool> isOtherMusicActive() async {
    try {
      return await _methods.invokeMethod<bool>('isOtherMusicActive') ?? false;
    } catch (e) {
      debugPrint('AudioFocus isOtherMusicActive failed: $e');
      return false;
    }
  }

  @override
  Future<bool> isOtherMediaListed() async {
    try {
      return await _methods.invokeMethod<bool>('isOtherMediaListed') ?? false;
    } catch (e) {
      debugPrint('AudioFocus isOtherMediaListed failed: $e');
      return false;
    }
  }
}
