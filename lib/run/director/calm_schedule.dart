import 'dart:math' show Random, min;

import '../config/tuning_values.dart';

/// PRD-2.6 D4 periodic and event-driven calm stretches.
class CalmSchedule {
  /// D4's reference schedule starts at hoop 32. A standalone schedule uses
  /// this fixed seed; the director always injects its seeded timing stream.
  static const int _defaultTimingSeed = 4;
  late final int _firstMin, _firstMax, _intervalCap, _periodicLength;
  late final int _reviveLength, _squeezeLength, _rideLength, _minimumGap;
  late final double _intervalMultiplier;

  /// [timing] supplies only the first periodic calm draw. That draw happens
  /// now, before any run-event outcome, so event suppression can never change
  /// the number or order of stream draws.
  CalmSchedule([Random? timing])
    : _timing = timing ?? Random(_defaultTimingSeed) {
    final every = tuning.obj('calm_every');
    final after = tuning.obj('calm_after');
    _firstMin = every['first_min']!.toInt();
    _firstMax = every['first_max']!.toInt();
    _intervalMultiplier = every['mult']!.toDouble();
    _intervalCap = every['cap']!.toInt();
    _periodicLength = every['len']!.toInt();
    _minimumGap = every['min_gap']!.toInt();
    _reviveLength = after['revive']!.toInt();
    _squeezeLength = after['squeeze']!.toInt();
    _rideLength = after['ride']!.toInt();
    final first = _rollFirst(_timing);
    _nextPeriodicAt = first.toDouble();
    _nextInterval = _firstMin * _intervalMultiplier;
  }

  final Random _timing;
  double _nextPeriodicAt = 0;
  late double _nextInterval;
  int? _lastCalmAt;
  int? _activeStart;
  int _activeEnd = -1;

  int _rollFirst(Random timing) =>
      timing.nextInt(_firstMax - _firstMin + 1) + _firstMin;

  /// Whether the slot at [hoop] must be calm.
  bool isCalm(int hoop) => dueAt(hoop);

  /// Whether a squeeze warning may occupy [hoop]. Warnings never start inside
  /// an active or due periodic calm stretch.
  bool allowsSqueezeWarning(int hoop) => !isCalm(hoop);

  /// Whether an already-started stretch, an event-driven stretch, or the due
  /// periodic stretch covers [hoop].
  bool dueAt(int hoop) {
    if (_activeStart != null && hoop >= _activeStart! && hoop <= _activeEnd) {
      return true;
    }
    return _periodicIsDue(hoop);
  }

  int remainingAt(int hoop) {
    if (_activeStart != null && hoop >= _activeStart! && hoop <= _activeEnd) {
      return _activeEnd - hoop + 1;
    }
    return _periodicIsDue(hoop) ? _periodicLength : 0;
  }

  /// Starts a calm stretch. Non-revive callers must respect the minimum gap;
  /// a revive can force a stretch so the player always gets its recovery.
  void startAt(int hoop, int length) => _start(hoop, length, force: false);

  void onRevive(int hoop) => _start(hoop, _reviveLength, force: true);

  /// The spawner already planned the first recovery hoop before the death.
  /// Include it in this revive's stretch without growing the interval twice.
  void includePlannedReviveSlot(int hoop) {
    final start = _activeStart;
    if (start == null) return;
    final shift = hoop - start;
    _activeStart = hoop;
    _activeEnd += shift;
    _lastCalmAt = hoop;
    _nextPeriodicAt += shift;
  }

  void onSqueezeEnded(int hoop) => _start(hoop, _squeezeLength, force: false);

  void onRideStart(int hoop) => _resetPeriodicAfter(hoop);

  void onRideEnded(int hoop) => _start(hoop, _rideLength, force: false);

  bool _periodicIsDue(int hoop) =>
      hoop >= _nextPeriodicAt &&
      (_lastCalmAt == null || hoop - _lastCalmAt! >= _minimumGap);

  void _start(int hoop, int length, {required bool force}) {
    if (!force && _lastCalmAt != null) {
      final gap = hoop - _lastCalmAt!;
      final overlap =
          _activeStart != null && hoop >= _activeStart! && hoop <= _activeEnd;
      if (gap < _minimumGap || overlap) return;
    }

    _activeStart = hoop;
    _activeEnd = hoop + length - 1;
    _lastCalmAt = hoop;
    _resetPeriodicAfter(hoop);
  }

  void _resetPeriodicAfter(int hoop) {
    _nextPeriodicAt = (hoop + _nextInterval).roundToDouble();
    _nextInterval = min(
      _intervalCap.toDouble(),
      _nextInterval * _intervalMultiplier,
    );
  }
}
