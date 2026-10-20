import 'dart:math' as math;
import 'dart:ui';

/// The world shake (ARCH §3 "RunShake"): every frame the world is offset by
/// a uniform random ±A on x and y (the mocks' shake); the owner applies
/// [offset] to the run world (never the HUD) and fills exposed edges with
/// the strip grey. A = max(kick, sustain): a *kick* starts at an amplitude
/// and falls linearly at `decay` pt/s; a *sustain* is a floor the owner
/// sets every frame (squeeze phases).
///
/// Presets (mock values): [feverPass] 6 pt − 20 pt/s, [piggySmash] 4 pt −
/// 20 pt/s, [blackHoleBoom] 8 pt − 18 pt/s, [blackHolePull] 2 + 4 k;
/// squeeze sustains: warning ramp 0 → 2.6 over 0.6 s, closing 2.2, lock
/// thump 3 pt vertical ([thump], PRD 2.5.1), opening 1.4 · (1 − t / 0.8),
/// hold ticks ≤ 1.44.
///
/// A *thump* (PRD 2.5.1 WP-THUMP) is a separate, deterministic vertical
/// channel: a damped bounce `dy = −A · e^(−3 t / time) · sin(2π f t)`
/// (dx = 0), added to the random kick / sustain offset and exactly 0 once
/// `time` has passed. The negative sign moves the viewfinder up, i.e. the
/// world down first.
class RunShake {
  RunShake({math.Random? random}) : _r = random ?? math.Random();

  final math.Random _r;
  double _kick = 0, _decay = 0;

  /// The running thump (PRD 2.5.1): amplitude, length, frequency and age.
  double _thumpA = 0, _thumpTime = 0, _thumpFreq = 0, _thumpT = 0;

  /// Floor amplitude (pt), set by the owner each frame; 0 = none.
  double sustain = 0;

  Offset _offset = Offset.zero;

  /// The current amplitude (pt).
  double get amplitude => math.max(_kick, sustain);

  /// This frame's offset (pt).
  Offset get offset => _offset;

  /// True while a [thump] runs.
  bool get thumping => _thumpA > 0;

  bool get active => amplitude > 0 || thumping;

  /// PRD 2.5.1 WP-THUMP: starts a vertical damped bounce of at most
  /// [amplitude] pt over [time] s at [freq] Hz, world moving down first.
  /// Replaces a running thump.
  void thump(double amplitude, {double time = .3, double freq = 7}) {
    if (amplitude <= 0 || time <= 0) return;
    _thumpA = amplitude;
    _thumpTime = time;
    _thumpFreq = freq;
    _thumpT = 0;
  }

  /// The thump's viewfinder dy at [t] s for [amplitude] / [time] / [freq]
  /// (0 from [time] on).
  static double thumpAt(
    double t, {
    required double amplitude,
    required double time,
    required double freq,
  }) {
    if (t <= 0 || t >= time) return 0;
    return -amplitude *
        math.exp(-3 * t / time) *
        math.sin(2 * math.pi * freq * t);
  }

  /// Starts (or raises) a decaying shake.
  void kick(double amplitude, {double decay = 20}) {
    if (amplitude >= _kick) {
      _kick = amplitude;
      _decay = decay;
    }
  }

  void feverPass() => kick(6, decay: 20);
  void piggySmash() => kick(4, decay: 20);
  void blackHoleBoom() => kick(8, decay: 18);

  /// Black Hole pull: sustain 2 + 4 k for k = t / 0.8 (owner calls per frame).
  void blackHolePull(double k) => sustain = 2 + 4 * k.clamp(0.0, 1.0);

  /// Squeeze warning sustain at [t] s into the 1.5 s warning.
  static double squeezeWarning(double t) => 2.6 * (t / .6).clamp(0.0, 1.0);

  /// Squeeze closing sustain.
  static const double squeezeClosing = 2.2;

  /// Squeeze opening sustain at [t] s into the opening.
  static double squeezeOpening(double t) => math.max(0, 1.4 * (1 - t / .8));

  void stop() {
    _kick = 0;
    sustain = 0;
    _thumpA = 0;
    _thumpT = 0;
    _offset = Offset.zero;
  }

  void update(double dt) {
    if (_kick > 0) _kick = math.max(0, _kick - _decay * dt);
    var dy = 0.0;
    if (_thumpA > 0) {
      _thumpT += dt;
      if (_thumpT >= _thumpTime) {
        _thumpA = 0;
        _thumpT = 0;
      } else {
        dy = thumpAt(
          _thumpT,
          amplitude: _thumpA,
          time: _thumpTime,
          freq: _thumpFreq,
        );
      }
    }
    final a = amplitude;
    _offset = a <= 0
        ? Offset(0, dy)
        : Offset(
            (_r.nextDouble() * 2 - 1) * a,
            (_r.nextDouble() * 2 - 1) * a + dy,
          );
  }
}
