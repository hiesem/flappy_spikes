import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';

/// PRD-2.2 §33.3 debug counter of live native audio players: a delegating
/// [AudioplayersPlatformInterface] that counts `create` / `dispose` (a
/// native `WrappedPlayer` lives from create until dispose; `release` keeps
/// it alive) and the `getCurrentPosition` polls (the per-frame
/// `FramePositionUpdater`, §33 item 2).
///
/// Installed only by the FS_SOAK profile build ([install], before the first
/// `AudioPlayer` is constructed: each player reads the instance once).
class CountingAudioPlatform extends AudioplayersPlatformInterface {
  CountingAudioPlatform(this._inner);

  final AudioplayersPlatformInterface _inner;

  /// The installed counter (null = not installed: normal builds).
  static CountingAudioPlatform? installed;

  /// Wraps the current platform instance once.
  static CountingAudioPlatform install() {
    final existing = installed;
    if (existing != null) return existing;
    final c = CountingAudioPlatform(AudioplayersPlatformInterface.instance);
    AudioplayersPlatformInterface.instance = c;
    return installed = c;
  }

  int creates = 0;
  int disposes = 0;
  int releases = 0;
  int positionPolls = 0;
  int starts = 0;

  /// PRD-2.3 §16.4: the just_audio music player (Android), one player.
  int musicPlayers = 0;

  /// Native players alive now (created, not yet disposed), the just_audio
  /// music player included.
  int get live => creates - disposes + musicPlayers;

  @override
  Future<void> create(String playerId) {
    creates++;
    return _inner.create(playerId);
  }

  @override
  Future<void> dispose(String playerId) {
    disposes++;
    return _inner.dispose(playerId);
  }

  @override
  Future<void> release(String playerId) {
    releases++;
    return _inner.release(playerId);
  }

  @override
  Future<int?> getCurrentPosition(String playerId) {
    positionPolls++;
    return _inner.getCurrentPosition(playerId);
  }

  @override
  Future<void> resume(String playerId) {
    starts++;
    return _inner.resume(playerId);
  }

  @override
  Future<void> pause(String playerId) => _inner.pause(playerId);

  @override
  Future<void> stop(String playerId) => _inner.stop(playerId);

  @override
  Future<void> seek(String playerId, Duration position) =>
      _inner.seek(playerId, position);

  @override
  Future<void> setBalance(String playerId, double balance) =>
      _inner.setBalance(playerId, balance);

  @override
  Future<void> setVolume(String playerId, double volume) =>
      _inner.setVolume(playerId, volume);

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) =>
      _inner.setReleaseMode(playerId, releaseMode);

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) =>
      _inner.setPlaybackRate(playerId, playbackRate);

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) =>
      _inner.setSourceUrl(playerId, url, isLocal: isLocal, mimeType: mimeType);

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) => _inner.setSourceBytes(playerId, bytes, mimeType: mimeType);

  @override
  Future<void> setAudioContext(String playerId, AudioContext audioContext) =>
      _inner.setAudioContext(playerId, audioContext);

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) =>
      _inner.setPlayerMode(playerId, playerMode);

  @override
  Future<int?> getDuration(String playerId) => _inner.getDuration(playerId);

  // Pure delegation (the interface requires these test hooks).
  @override
  Future<void> emitLog(String playerId, String message) =>
      // ignore: invalid_use_of_visible_for_testing_member
      _inner.emitLog(playerId, message);

  @override
  Future<void> emitError(String playerId, String code, String message) =>
      // ignore: invalid_use_of_visible_for_testing_member
      _inner.emitError(playerId, code, message);

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _inner.getEventStream(playerId);
}
