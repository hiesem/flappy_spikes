import 'dart:async';

import 'package:flame_audio/flame_audio.dart';

/// Sound effects used by the game (files live in assets/audio/).
enum Sfx { flap, point, gameover, click }

class SoundService {
  SoundService({this.muted = false, this.enabled = true});

  static const Map<Sfx, String> _files = {
    Sfx.flap: 'flap.mp3',
    Sfx.point: 'point.mp3',
    Sfx.gameover: 'gameover.mp3',
    Sfx.click: 'click.mp3',
  };

  static const String _musicFile = 'HappyBeat_8-Bit_Retro_Game_Loop.mp3';

  bool muted;

  /// Master switch for audio output. Headless tests set this to false so no
  /// calls reach the audioplayers platform channel (which has no test
  /// backend and would throw [MissingPluginException]).
  bool enabled;

  double _musicVolume = 0.6;
  bool _musicStarted = false;
  bool _bgmInitialized = false;

  /// Preloaded low-latency pools, one per SFX. Without these, FlameAudio.play
  /// creates a brand-new AudioPlayer (decoder + AudioTrack + audio-focus
  /// request) for EVERY effect — that made flap sounds laggy and churned CPU
  /// on the Pixel 8 (2026-07-22).
  ///
  /// The pools use SoundPool mode ([PlayerMode.lowLatency]): sounds are
  /// decoded ONCE at warmup and each play is a sub-millisecond queue on an
  /// open stream. The default MediaPlayer mode made every play open+close an
  /// audio route, which stalled frames on the Pixel 8 (few-frame freeze on
  /// every flap, 2026-07-22). Caveat of SoundPool mode: onPlayerComplete
  /// never fires, so [play] stops each sound after its measured duration to
  /// return the player to the pool.
  final Map<Sfx, AudioPool> _pools = {};
  final Map<Sfx, Duration> _durations = {};
  bool _poolsStarted = false;

  /// Background-music volume (0..1). Independent of [muted], which only
  /// gates sound effects.
  double get musicVolume => _musicVolume;

  void play(Sfx sfx) {
    if (muted || !enabled) {
      return;
    }
    final pool = _pools[sfx];
    if (pool == null) {
      // Pools not ready yet: fall back to a one-shot player and warm them up
      // for next time.
      unawaited(_initPools());
      FlameAudio.play(_files[sfx]!);
      return;
    }
    // SoundPool mode never reports completion: stop after the known duration
    // so the player returns to the pool (see the field comment).
    unawaited(
      pool.start().then((stop) {
        Timer(
          _durations[sfx]! + const Duration(milliseconds: 100),
          () => unawaited(stop()),
        );
      }),
    );
  }

  /// Creates the SFX pools once. No-op when [enabled] is false (tests) and
  /// idempotent afterwards; failures degrade silently to [FlameAudio.play].
  Future<void> _initPools() async {
    if (!enabled || _poolsStarted) {
      return;
    }
    _poolsStarted = true;
    try {
      for (final entry in _files.entries) {
        final pool = await AudioPool.create(
          source: AssetSource(entry.value),
          audioCache: FlameAudio.audioCache,
          minPlayers: 2,
          maxPlayers: 4,
          playerMode: PlayerMode.lowLatency,
          audioContext: AudioContextConfig(
            focus: AudioContextConfigFocus.mixWithOthers,
          ).build(),
        );
        _pools[entry.key] = pool;
        _durations[entry.key] =
            await pool.getDuration() ?? const Duration(milliseconds: 500);
      }
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }

  /// Starts the looping background music. Idempotent: only the first
  /// successful call starts playback. No-op when [enabled] is false.
  Future<void> startMusic() async {
    if (!enabled || _musicStarted) {
      return;
    }
    try {
      if (!_bgmInitialized) {
        // Registers Bgm's WidgetsBinding observer so the music pauses when
        // the app backgrounds and resumes on foreground.
        await FlameAudio.bgm.initialize();
        _bgmInitialized = true;
      }
      await FlameAudio.bgm.play(_musicFile, volume: _musicVolume);
      _musicStarted = true;
    } catch (_) {
      // Audio failure must never take the game down.
    }
    unawaited(_initPools());
  }

  /// Stores the music volume (clamped to 0..1) and applies it live when
  /// music is playing. Never touches the plugin when [enabled] is false.
  Future<void> setMusicVolume(double volume) async {
    _musicVolume = volume.clamp(0.0, 1.0).toDouble();
    if (!enabled || !_musicStarted) {
      return;
    }
    try {
      await FlameAudio.bgm.audioPlayer.setVolume(_musicVolume);
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }
}
