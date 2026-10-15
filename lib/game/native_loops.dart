import 'dart:async';

import 'package:flutter/services.dart' show MethodChannel;

/// iOS round 2 §3: the sound-effect loops ([SfxLoop]: comet, squeeze hold,
/// saw hums, FEVER crackle) on the runner's `SfxLoops`
/// (`AppDelegate.swift`, channel `flappy_spikes/loops`).
///
/// Android plays them on SoundPool (`PlayerMode.lowLatency`), which loops
/// a decoded sample seamlessly. iOS has no SoundPool: audioplayers' AVPlayer
/// loops by seeking back to 0 when the item ends, a gap every 4-7 s. The
/// runner decodes the same asset (`assets/audio/*.wav`) into a PCM buffer
/// and plays it with `AVAudioPlayerNode` `.loops` (sample-exact).
///
/// Handles are numbered here, so a stop that comes before the start has
/// finished needs no answer (the channel keeps the order).
class NativeSfxLoops {
  NativeSfxLoops({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('flappy_spikes/loops');

  final MethodChannel _channel;
  int _next = 0;

  /// Starts [file] (in assets/audio) looping at [volume]; returns its id.
  int start(String file, double volume) {
    final id = ++_next;
    _send('start', {'id': id, 'asset': 'assets/audio/$file', 'volume': volume});
    return id;
  }

  void setVolume(int id, double volume) =>
      _send('setVolume', {'id': id, 'volume': volume});

  Future<void> stop(int id) => _send('stop', {'id': id});

  Future<void> _send(String method, Map<String, Object> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (_) {
      // Audio failure must never take the game down.
    }
  }
}
