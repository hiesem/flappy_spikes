import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flame_audio/flame_audio.dart' show AudioCache;

import 'package:flappy_spikes/game/sfx_pool.dart';
import 'package:flappy_spikes/game/sound.dart';

/// PRD-2.2 §22.4 / §33.7 plugin-free audio: a fake voice per created
/// player, with every start / stop / dispose recorded.
class FakeVoice implements SfxVoice {
  FakeVoice(this.file, this.audio);

  final String file;
  final FakeAudio audio;
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  bool playing = false;

  /// Start times (ms of [FakeAudio.clock]) and stop times, in order.
  final List<int> startedAt = [];
  final List<int> stoppedAt = [];

  Object? startError;
  Object? stopError;

  @override
  Future<void> start() async {
    if (disposed) throw StateError('start on a disposed voice');
    starts++;
    audio.starts++;
    startedAt.add(audio.clock.elapsedMilliseconds);
    final e = startError;
    if (e != null) throw e;
    playing = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    stoppedAt.add(audio.clock.elapsedMilliseconds);
    playing = false;
    final e = stopError;
    if (e != null) throw e;
  }

  @override
  Future<void> dispose() async {
    if (disposed) throw StateError('double dispose');
    disposed = true;
    playing = false;
    audio.disposes++;
  }

  /// The real voice turns position updates off; a fake has none at all.
  bool get hasPositionUpdater => false;
}

/// A voice factory with counters ([created] − [disposes] = live players).
class FakeAudio {
  final Stopwatch clock = Stopwatch()..start();
  final List<FakeVoice> voices = [];
  int disposes = 0;
  int starts = 0;

  /// Files whose voice creation returns null (never ready).
  final Set<String> failing = {};

  /// Per-file gate: voice creation for that file waits for the completer.
  final Map<String, Completer<void>> gates = {};

  int get created => voices.length;
  int get live => created - disposes;

  Iterable<FakeVoice> of(String file) => voices.where((v) => v.file == file);

  Future<SfxVoice?> create(String file) async {
    final gate = gates[file];
    if (gate != null) await gate.future;
    if (failing.contains(file)) return null;
    final v = FakeVoice(file, this);
    voices.add(v);
    return v;
  }

  /// A service wired to this fake (enabled, not muted).
  SoundService service({bool muted = false, bool enabled = true}) =>
      SoundService(muted: muted, enabled: enabled)..voiceFactory = create;
}

/// Lets the pool creation's awaited futures run to their next suspension.
Future<void> flushAudio() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.value();
  }
}

/// A plugin-free audioplayers platform (PRD-2.2 §33.7): lets the REAL
/// [PlayerVoice] / music / loop code run in a unit test. Wrap it in a
/// `CountingAudioPlatform` to count creates / disposes / position polls.
class FakeAudioPlatform extends AudioplayersPlatformInterface {
  final Map<String, StreamController<AudioEvent>> _events = {};
  final Set<String> live = {};
  final Map<String, PlayerMode> modes = {};
  final List<String> contextWrites = [];
  int resumes = 0;

  @override
  Future<void> create(String playerId) async {
    live.add(playerId);
    _events[playerId] = StreamController<AudioEvent>.broadcast();
  }

  @override
  Future<void> dispose(String playerId) async {
    live.remove(playerId);
    await _events.remove(playerId)?.close();
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _events[playerId]!.stream;

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    scheduleMicrotask(
      () => _events[playerId]?.add(
        const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
      ),
    );
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async =>
      modes[playerId] = playerMode;

  @override
  Future<void> setAudioContext(String playerId, AudioContext ctx) async =>
      contextWrites.add(playerId);

  @override
  Future<void> resume(String playerId) async => resumes++;

  @override
  Future<void> pause(String playerId) async {}
  @override
  Future<void> stop(String playerId) async {}
  @override
  Future<void> release(String playerId) async {}
  @override
  Future<void> seek(String playerId, Duration position) async {}
  @override
  Future<void> setBalance(String playerId, double balance) async {}
  @override
  Future<void> setVolume(String playerId, double volume) async {}
  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode mode) async {}
  @override
  Future<void> setPlaybackRate(String playerId, double rate) async {}
  @override
  Future<int?> getDuration(String playerId) async => null;
  @override
  Future<int?> getCurrentPosition(String playerId) async => null;
  @override
  Future<void> emitLog(String playerId, String message) async {}
  @override
  Future<void> emitError(String playerId, String code, String message) async {}
}

class FakeGlobalAudioPlatform extends GlobalAudioplayersPlatformInterface {
  final List<AudioContext> contexts = [];
  @override
  Future<void> init() async {}
  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async =>
      contexts.add(ctx);
  @override
  Future<void> emitGlobalLog(String message) async {}
  @override
  Future<void> emitGlobalError(String code, String message) async {}
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
}

/// An [AudioCache] that never touches the file system.
class FakeAudioCache extends AudioCache {
  FakeAudioCache() : super(prefix: 'assets/audio/');
  @override
  Future<String> loadPath(String fileName) async => '/fake/$fileName';
}
