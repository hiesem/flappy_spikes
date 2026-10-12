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
/// `AudioManager.isMusicActive()` for the music check). iOS (paused) maps
/// to `AVAudioSession` interruptions and `secondaryAudioShouldBeSilencedHint`
/// (PORT-IOS.md). Every call is guarded: audio checks never take the game
/// down.
abstract class AudioFocus {
  Stream<bool> get interruptions;

  Future<bool> isOtherMusicActive();

  /// Another app's media player is listed as playing (no stream fallback).
  Future<bool> isOtherMediaListed();
}

/// Tests, Linux, iOS (paused): nothing is ever interrupted.
class NoopAudioFocus implements AudioFocus {
  const NoopAudioFocus();

  @override
  Stream<bool> get interruptions => const Stream<bool>.empty();

  @override
  Future<bool> isOtherMusicActive() async => false;

  @override
  Future<bool> isOtherMediaListed() async => false;
}

/// Scriptable in tests.
class FakeAudioFocus implements AudioFocus {
  final StreamController<bool> _events = StreamController<bool>.broadcast();

  /// What [isOtherMusicActive] answers.
  bool otherMusic = false;

  int checks = 0;

  /// Fires an interruption start (true) or end (false).
  void interrupt(bool on) => _events.add(on);

  @override
  Stream<bool> get interruptions => _events.stream;

  @override
  Future<bool> isOtherMusicActive() async {
    checks++;
    return otherMusic;
  }

  /// The scripted other music is another app's listed media player.
  @override
  Future<bool> isOtherMediaListed() async => otherMusic;
}

/// The Android implementation (MethodChannel + EventChannel).
class PlatformAudioFocus implements AudioFocus {
  static const MethodChannel _methods = MethodChannel('flappy_spikes/audio');
  static const EventChannel _events = EventChannel(
    'flappy_spikes/audio_interruptions',
  );

  Stream<bool>? _stream;

  @override
  Stream<bool> get interruptions => _stream ??= _events
      .receiveBroadcastStream()
      .map((e) => e == true)
      .handleError((Object e) {
        debugPrint('AudioFocus interruptions failed: $e');
      })
      .asBroadcastStream();

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
