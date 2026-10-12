import 'dart:async';

import 'package:flame_audio/flame_audio.dart';

/// PRD-2.2 §22 / §33.4: our own fixed-size low-latency player set per sound,
/// in place of audioplayers' `AudioPool` (which creates a new player whenever
/// none is free and only `release()`s the surplus: the §33 player leak).
///
/// Rules (docs/gameplay-v2/ARCH.md "Audio pool rules"):
/// - a pool owns at most [SfxPool.capacity] voices, created once (never mid
///   play); when every voice is busy the **oldest copy is stopped and
///   reused**;
/// - a play is stopped after the file's table length + margin (SoundPool
///   never reports completion or duration);
/// - voices are only ever **disposed** (pool eviction / teardown), never
///   released;
/// - no voice polls its position (`positionUpdater = null`).

/// One native player bound to one sound file.
abstract class SfxVoice {
  /// Starts the sound from the beginning. The voice is stopped (idle) when
  /// this is called.
  Future<void> start();

  /// Stops the sound (re-arms the voice for the next [start]).
  Future<void> stop();

  /// Frees the native player. The voice is unusable afterwards.
  Future<void> dispose();
}

/// The real voice: an audioplayers [AudioPlayer] in low-latency (Android
/// SoundPool) mode with position updates off.
class PlayerVoice implements SfxVoice {
  PlayerVoice._(this.player);

  final AudioPlayer player;

  /// Creates and loads one voice for [file]. Callers must create the voices
  /// of one file sequentially (a player attaching while the first load of
  /// the same file still runs can stay silent, PERF.md §5) and only after
  /// the global audio context is set (mixWithOthers: no focus request per
  /// play).
  static Future<PlayerVoice> create(String file) async {
    final p = AudioPlayer()..audioCache = FlameAudio.audioCache;
    // §33.4 item 2: no per-frame getCurrentPosition over the channel.
    p.positionUpdater = null;
    final voice = PlayerVoice._(p);
    try {
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setSource(AssetSource(file));
    } catch (_) {
      await voice.dispose();
      rethrow;
    }
    return voice;
  }

  @override
  Future<void> start() => player.resume();

  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> dispose() async {
    try {
      await player.dispose();
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }
}

/// A fixed voice ring for one sound. Every native call runs on a per-voice
/// chain (start / stop / dispose keep their order) and is error-contained.
class SfxPool {
  SfxPool({
    required this.file,
    required this.length,
    required this.capacity,
    required this.stopMargin,
    required int nowMs,
  }) : lastUsedMs = nowMs;

  final String file;

  /// The file's designed length (§22 table).
  final Duration length;

  /// Hard cap on voices (§22.1).
  final int capacity;

  /// Added to [length] before a play is stopped (§22.1: 100 ms).
  final Duration stopMargin;

  final List<SfxVoice> _voices = [];
  final List<Timer?> _stopTimers = [];
  final List<int> _startedAt = [];
  final List<Future<void>> _chains = [];
  int _startSeq = 0;

  /// Monotonic ms of the last [play] (or creation / preload touch).
  int lastUsedMs;

  /// Monotonic ms of the last real [play]; null while the pool has never
  /// played (a preloaded pool is not ringing, PRD-2.2 §33.4 item 3, S7-11).
  int? lastPlayedMs;

  bool _disposed = false;
  bool get disposed => _disposed;

  /// Voices created so far (≤ [capacity]).
  int get voiceCount => _voices.length;

  /// Voices playing now (their stop timer is pending).
  int get busyCount => _stopTimers.where((t) => t != null).length;

  /// Plays that reused the oldest busy voice (soak / tests).
  int steals = 0;

  /// Diagnostics (FS_SOAK): called when a play's stop timer fires, with the
  /// measured ms from [play] to the stop (§22 device check).
  void Function(String file, int playedMs)? onStopped;

  /// Adds one created voice. Returns false (and the caller disposes the
  /// voice) when the pool is full or already disposed.
  bool add(SfxVoice voice) {
    if (_disposed || _voices.length >= capacity) return false;
    _voices.add(voice);
    _stopTimers.add(null);
    _startedAt.add(0);
    _chains.add(Future<void>.value());
    return true;
  }

  /// Plays once: on a free voice, else stops the oldest copy and restarts
  /// it. Never creates a player. Returns the voice index (-1 = no voice).
  int play(int nowMs) {
    if (_disposed || _voices.isEmpty) return -1;
    lastUsedMs = nowMs;
    lastPlayedMs = nowMs;
    var slot = _stopTimers.indexWhere((t) => t == null);
    final steal = slot < 0;
    if (steal) {
      slot = 0;
      for (var i = 1; i < _voices.length; i++) {
        if (_startedAt[i] < _startedAt[slot]) slot = i;
      }
      _stopTimers[slot]?.cancel();
      steals++;
    }
    _startedAt[slot] = ++_startSeq;
    final voice = _voices[slot];
    if (steal) _run(slot, voice.stop);
    _run(slot, voice.start);
    final watch = onStopped == null ? null : (Stopwatch()..start());
    _stopTimers[slot] = Timer(length + stopMargin, () {
      _stopTimers[slot] = null;
      _run(slot, voice.stop);
      if (watch != null) onStopped?.call(file, watch.elapsedMilliseconds);
    });
    return slot;
  }

  void _run(int slot, Future<void> Function() op) {
    _chains[slot] = _chains[slot].then((_) async {
      try {
        await op();
      } catch (_) {
        // Audio failure must never take the game down.
      }
    });
  }

  /// PRD-2.2 §28.2 / §28.3 (S7-09): stops every copy that is ringing now
  /// (a full-screen ad or a call / alarm / assistant starts). The stop is
  /// queued after any start still on the voice's chain, so a start that was
  /// already requested ends stopped (no late burst after the hold).
  /// Returns the number of voices stopped.
  int stopAll() {
    if (_disposed) return 0;
    var n = 0;
    for (var i = 0; i < _voices.length; i++) {
      final t = _stopTimers[i];
      if (t == null) continue;
      t.cancel();
      _stopTimers[i] = null;
      _run(i, _voices[i].stop);
      n++;
    }
    return n;
  }

  /// Stops every voice and disposes it (eviction / teardown). Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pending = <Future<void>>[];
    for (var i = 0; i < _voices.length; i++) {
      _stopTimers[i]?.cancel();
      _stopTimers[i] = null;
      _run(i, _voices[i].dispose);
      pending.add(_chains[i]);
    }
    await Future.wait(pending);
  }
}
