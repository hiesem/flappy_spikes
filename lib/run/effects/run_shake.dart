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
/// 6 · (1 − t / 0.35), opening 1.4 · (1 − t / 0.8), hold ticks ≤ 1.44.
class RunShake {
  RunShake({math.Random? random}) : _r = random ?? math.Random();

  final math.Random _r;
  double _kick = 0, _decay = 0;

  /// Floor amplitude (pt), set by the owner each frame; 0 = none.
  double sustain = 0;

  Offset _offset = Offset.zero;

  /// The current amplitude (pt).
  double get amplitude => math.max(_kick, sustain);

  /// This frame's offset (pt).
  Offset get offset => _offset;

  bool get active => amplitude > 0;

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

  /// Squeeze lock sustain at [t] s after the walls lock.
  static double squeezeLock(double t) => math.max(0, 6 * (1 - t / .35));

  /// Squeeze opening sustain at [t] s into the opening.
  static double squeezeOpening(double t) => math.max(0, 1.4 * (1 - t / .8));

  void stop() {
    _kick = 0;
    sustain = 0;
    _offset = Offset.zero;
  }

  void update(double dt) {
    if (_kick > 0) _kick = math.max(0, _kick - _decay * dt);
    final a = amplitude;
    _offset = a <= 0
        ? Offset.zero
        : Offset((_r.nextDouble() * 2 - 1) * a, (_r.nextDouble() * 2 - 1) * a);
  }
}
