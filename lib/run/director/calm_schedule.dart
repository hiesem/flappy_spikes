import 'dart:math' show Random, min;

/// PRD-2.6 D4 periodic and event-driven calm stretches.
class CalmSchedule {
  /// D4's reference schedule starts at hoop 32. A standalone schedule uses
  /// this fixed seed; the director always injects its seeded timing stream.
  static const int _defaultTimingSeed = 4;
  static const _firstMin = 30;
  static const _firstMax = 34;
  static const _intervalMultiplier = 1.2;
  static const _intervalCap = 55;
  static const _periodicLength = 3;
  static const _reviveLength = 3;
  static const _eventLength = 2;
  static const _minimumGap = 12;

  /// [timing] supplies only the first periodic calm draw. That draw happens
  /// now, before any run-event outcome, so event suppression can never change
  /// the number or order of stream draws.
  CalmSchedule([Random? timing])
    : _timing = timing ?? Random(_defaultTimingSeed) {
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

  static int _rollFirst(Random timing) =>
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

  void onSqueezeEnded(int hoop) => _start(hoop, _eventLength, force: false);

  void onRideStart(int hoop) => _resetPeriodicAfter(hoop);

  void onRideEnded(int hoop) => _start(hoop, _eventLength, force: false);

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
