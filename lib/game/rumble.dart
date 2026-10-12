import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// The two rumbles of PRD-2 §3.33.
enum RumbleKind { knock, shake }

/// Phone vibration (PRD-2 §3.33, menu knocks PRD-home-v3 §10): one owner
/// of the RUMBLE setting and the throttle; callers only say [knock] or
/// [shake].
///
/// - knock: one 15 ms pulse at amplitude 90; at most one per
///   [knockThrottle] — a knock inside that window (after any rumble) is
///   skipped.
/// - shake: one 80 ms full-amplitude pulse (PRD-2.2 §10.3, was 45 ms); never skipped, and it starts a
///   new window, so a knock right after it is dropped (shake wins).
///
/// [on] is the user's switch (`GameStorage.rumble`). [hardware] false (or
/// a platform without a vibrator: Linux / desktop / web, tablets) makes
/// the service a pure recorder — tests read [fired]. Every plugin call is
/// try/caught: rumble must never take the game down.
class Rumble {
  Rumble({this.on = true, bool hardware = true, double Function()? clock})
    : hardware = hardware && _platformSupported,
      _clock = clock ?? _stopwatchClock();

  static const int knockMs = 15;
  static const int knockAmplitude = 90;
  /// PRD-2.2 §10.3 (was 45 ms in PRD-2 §3.33).
  static const int shakeMs = 80;
  static const int shakeAmplitude = 255;

  /// Seconds: at most one knock per 90 ms.
  static const double knockThrottle = 0.09;

  /// The RUMBLE setting (applies immediately).
  bool on;

  /// Whether pulses reach the vibration plugin.
  final bool hardware;

  /// Every rumble that passed the setting and the throttle, in order
  /// (recorded with or without [hardware]). PRD-2.2 §33.4 item 6: a test
  /// recorder only — a profile / release build with a vibrator records
  /// nothing, and the list never holds more than [firedCap] (the oldest
  /// half is dropped).
  final List<RumbleKind> fired = [];

  /// PRD-2.2 §33.4 item 6: the most rumbles [fired] keeps.
  static const int firedCap = 2000;

  bool get _records => !hardware || kDebugMode;

  /// Seconds clock for the throttle (the game feeds its own clock).
  double Function() _clock;
  set clock(double Function() value) => _clock = value;

  double? _last;

  /// Device capabilities, probed once on the first pulse.
  Future<({bool vibrator, bool amplitude})>? _caps;

  static bool get _platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static double Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds / 1e6;
  }

  /// A slight knock (menu presses, rim touches, clean passes, pickups).
  /// Throttled.
  void knock() {
    if (!on) return;
    final now = _clock();
    final last = _last;
    if (last != null && now - last < knockThrottle) return;
    _last = now;
    _fire(RumbleKind.knock, knockMs, knockAmplitude);
  }

  /// A proper shake (perfect passes). Never skipped.
  void shake() {
    if (!on) return;
    _last = _clock();
    _fire(RumbleKind.shake, shakeMs, shakeAmplitude);
  }

  void _fire(RumbleKind kind, int ms, int amplitude) {
    if (_records) {
      if (fired.length >= firedCap) fired.removeRange(0, firedCap ~/ 2);
      fired.add(kind);
    }
    if (!hardware) return;
    unawaited(_vibrate(ms, amplitude));
  }

  Future<void> _vibrate(int ms, int amplitude) async {
    try {
      final caps = await (_caps ??= _probe());
      if (!caps.vibrator) return;
      // Devices without amplitude control get a plain pulse of the same
      // length (§3.33 fallback).
      await Vibration.vibrate(
        duration: ms,
        amplitude: caps.amplitude ? amplitude : -1,
      );
    } catch (_) {
      // Rumble must never take the game down.
    }
  }

  Future<({bool vibrator, bool amplitude})> _probe() async {
    try {
      final vibrator = await Vibration.hasVibrator();
      final amplitude = vibrator && await Vibration.hasAmplitudeControl();
      // PRD-2.2 §10.2 1: the capabilities, once, in debug builds.
      if (kDebugMode) {
        debugPrint(
          'rumble: hasVibrator=$vibrator hasAmplitudeControl=$amplitude',
        );
      }
      return (vibrator: vibrator, amplitude: amplitude);
    } catch (_) {
      return (vibrator: false, amplitude: false);
    }
  }
}
