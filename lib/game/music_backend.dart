import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'audio_counter.dart';

/// PRD-2.3 §16.4: the player behind the background music.
///
/// [SoundService] keeps its music API and the PRD-2.2 §28 logic; only the
/// plugin calls go through this interface.
/// - Android: [JustAudioMusic] (ExoPlayer, `LoopMode.one`), step 2 of §16.4:
///   audioplayers' `MediaPlayer` loop left a 250–265 ms gap at every wrap of
///   the OGG on the Pixel 6 (docs/p23/MUSIC.md).
/// - Linux desktop (just_audio has no Linux backend) and iOS (paused, MP3):
///   [AudioplayersMusic], the 2.2 path (`FlameAudio.bgm`).
abstract class MusicBackend {
  /// Loads [file] (in assets/audio) and plays it looping from the start at
  /// [volume] and [rate].
  Future<void> start(String file, {required double volume, required double rate});

  /// Pauses, keeping the position.
  Future<void> pause();

  /// Resumes from the paused position.
  Future<void> resume();

  /// Stops (the PRD-2.3 §13.4 watchdog then starts it again from the top).
  Future<void> stop();

  Future<void> setVolume(double volume);

  /// §3.30 Hourglass rate.
  Future<void> setRate(double rate);

  /// The real player state (`playing`, `paused`, `stopped`, `completed`,
  /// `disposed`, `none`) for the §13.4 watchdog and the §13.3 log.
  String get state;

  /// The platform's backend (see the class comment).
  static MusicBackend forPlatform({
    required Future<void> Function() audioContext,
  }) {
    if (!kIsWeb && Platform.isAndroid) return JustAudioMusic();
    return AudioplayersMusic(audioContext);
  }
}

/// The 2.2 music player: `FlameAudio.bgm` (audioplayers, Android
/// `MediaPlayer` with `isLooping`). Linux desktop and iOS.
class AudioplayersMusic implements MusicBackend {
  AudioplayersMusic(this._context);

  /// Applies the game audio context ([SoundService.gameAudioContext]).
  final Future<void> Function() _context;
  bool _initialized = false;

  @override
  Future<void> start(String file, {required double volume, required double rate}) async {
    final bgm = FlameAudio.bgm;
    if (!_initialized) {
      // §28.3 mixWithOthers (the player's own music keeps playing);
      // no Bgm lifecycle observer: [SoundService.setBackground] pauses /
      // resumes.
      await _context();
      // PRD-2.2 §33.4 item 2: the music never polls its position (it
      // polled 60×/s all session, also on Home).
      bgm.audioPlayer.positionUpdater = null;
      _initialized = true;
    }
    await bgm.play(file, volume: volume);
    if (rate != 1) await bgm.audioPlayer.setPlaybackRate(rate);
  }

  @override
  Future<void> pause() => FlameAudio.bgm.pause();

  @override
  Future<void> resume() => FlameAudio.bgm.resume();

  @override
  Future<void> stop() => FlameAudio.bgm.stop();

  @override
  Future<void> setVolume(double volume) =>
      FlameAudio.bgm.audioPlayer.setVolume(volume);

  @override
  Future<void> setRate(double rate) =>
      FlameAudio.bgm.audioPlayer.setPlaybackRate(rate);

  @override
  String get state {
    if (!_initialized) return 'none';
    return switch (FlameAudio.bgm.audioPlayer.state) {
      PlayerState.playing => 'playing',
      PlayerState.paused => 'paused',
      PlayerState.stopped => 'stopped',
      PlayerState.completed => 'completed',
      PlayerState.disposed => 'disposed',
    };
  }
}

/// The subset of just_audio's `AudioPlayer` the music uses (a fake in the
/// §16.5 tests). No position API on purpose: PRD-2.2 §33.4 / PRD-2.3 §16.4
/// forbid subscribing to `positionStream` or any per-frame stream.
abstract class MusicPlayerPort {
  Future<void> setAndroidAudioAttributes(AndroidAudioAttributes attributes);
  Future<void> setAsset(String asset);
  Future<void> setLoopMode(ja.LoopMode mode);
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> seekToStart();

  /// Starts playing (does not wait for the playback to end).
  void play();
  Future<void> pause();
  Future<void> stop();

  /// Player state changes (the only stream used, for the §13.4 watchdog).
  Stream<ja.PlayerState> get playerStateStream;
}

/// The real port around just_audio's `AudioPlayer`.
class JustAudioPort implements MusicPlayerPort {
  JustAudioPort()
    : _player = ja.AudioPlayer(
        // §16.4: the game's own AudioWatch handles calls / alarms /
        // notifications; the music never requests audio focus and never
        // activates an audio session (mixWithOthers, like 2.2).
        handleInterruptions: JustAudioMusic.handleInterruptions,
        handleAudioSessionActivation:
            JustAudioMusic.handleAudioSessionActivation,
        // The attributes are set on the player directly (below), not from a
        // shared audio-session configuration.
        androidApplyAudioAttributes: JustAudioMusic.applySessionAttributes,
      );

  final ja.AudioPlayer _player;

  @override
  Future<void> setAndroidAudioAttributes(AndroidAudioAttributes attributes) =>
      _player.setAndroidAudioAttributes(attributes);

  @override
  Future<void> setAsset(String asset) => _player.setAsset(asset);

  @override
  Future<void> setLoopMode(ja.LoopMode mode) => _player.setLoopMode(mode);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> seekToStart() => _player.seek(Duration.zero);

  @override
  void play() => unawaited(_player.play().catchError((Object _) {}));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Stream<ja.PlayerState> get playerStateStream => _player.playerStateStream;
}

/// PRD-2.3 §16.4 step 2: the music on just_audio (Android, ExoPlayer,
/// seamless `LoopMode.one`). The sound effects and loops stay on
/// audioplayers exactly as tuned in 2.2.
class JustAudioMusic implements MusicBackend {
  JustAudioMusic({MusicPlayerPort Function()? port})
    : _makePort = port ?? JustAudioPort.new;

  /// §16.4: no audio focus, no session activation, attributes set on the
  /// player (tests read these).
  static const bool handleInterruptions = false;
  static const bool handleAudioSessionActivation = false;
  static const bool applySessionAttributes = false;

  /// §16.4: `USAGE_GAME` / `CONTENT_TYPE_MUSIC`, so `MainActivity.kt`'s
  /// `otherMediaListed()` never counts the game's own music.
  static const AndroidAudioAttributes attributes = AndroidAudioAttributes(
    contentType: AndroidAudioContentType.music,
    usage: AndroidAudioUsage.game,
  );

  final MusicPlayerPort Function() _makePort;
  MusicPlayerPort? _port;
  StreamSubscription<ja.PlayerState>? _stateSub;
  ja.PlayerState? _state;
  String? _loaded;

  MusicPlayerPort _ensure() {
    final existing = _port;
    if (existing != null) return existing;
    final p = _port = _makePort();
    // PRD-2.2 §33.3: the FS_SOAK counter counts it as one music player.
    CountingAudioPlatform.installed?.musicPlayers++;
    _stateSub = p.playerStateStream.listen((s) => _state = s);
    return p;
  }

  @override
  Future<void> start(String file, {required double volume, required double rate}) async {
    final p = _ensure();
    final asset = 'assets/audio/$file';
    if (_loaded != asset) {
      // Attributes before the source (just_audio: avoids an ExoPlayer
      // glitch), then the loop mode.
      await p.setAndroidAudioAttributes(attributes);
      await p.setAsset(asset);
      _loaded = asset;
    } else {
      await p.seekToStart();
    }
    await p.setLoopMode(ja.LoopMode.one);
    await p.setVolume(volume);
    if (rate != 1) await p.setSpeed(rate);
    p.play();
  }

  @override
  Future<void> pause() async => _port?.pause();

  @override
  Future<void> resume() async => _port?.play();

  @override
  Future<void> stop() async {
    await _port?.stop();
    // A stopped just_audio player is idle: the next start loads again.
    _loaded = null;
  }

  @override
  Future<void> setVolume(double volume) async => _port?.setVolume(volume);

  @override
  Future<void> setRate(double rate) async => _port?.setSpeed(rate);

  @override
  String get state {
    final s = _state;
    if (_port == null || s == null) return 'none';
    if (s.processingState == ja.ProcessingState.completed) return 'completed';
    if (s.processingState == ja.ProcessingState.idle) return 'stopped';
    return s.playing ? 'playing' : 'paused';
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
  }
}
