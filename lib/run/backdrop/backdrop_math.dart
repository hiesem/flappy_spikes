import 'dart:math' as math;

/// PRD-2.4 §3 — the numbers and small helpers of `docs/p24/endless_vertical.html`
/// (its "helpers" and "the endless world" blocks), ported 1:1.

/// The design view (320 × 568). Taller views keep this and grow the sky above
/// (PRD-2.4 §3.3 "Tall screens").
const double kVW = 320;
const double kVH = 568;

/// `TAU`.
const double kTau = math.pi * 2;

/// Hoops per scene (seam k is centred on hoop 20·k). Owner 2026-10-19
/// (2.4.0+38): 20 (was the prototype's 40).
const int kHoopsPerScene = 20;

/// World distance per hoop in the prototype (300 pt between hoop planes).
const double kPerHoop = 300;

/// The world: a stage (scene) is [kE] long ([kHoopsPerScene] hoops at
/// [kPerHoop] = 6 000), [kNST] stages make the loop, a seam's camera move
/// spans [kVWIN] (5 hoops, a quarter of the stage as in the prototype's
/// 3 000 of 12 000), centred on the seam, which sits at the screen centre
/// [kANCH].
const double kE = kHoopsPerScene * kPerHoop;
const int kNST = 10;
const double kTotal = kE * kNST;
const double kVWIN = kE / 4;
const double kANCH = kVW / 2;

/// Floor-move pieces stay in place this far beyond the window, until they
/// have scrolled away (`LINGER`; the prototype's 3 500 of a 12 000 stage,
/// scaled with it). A seam's window plus linger (±2 500) ends 1 000 before
/// the next seam's begins.
const double kLinger = kE * 3500 / 12000;

/// The prototype's stage length (12 000): what a landmark's sweep
/// (`mark`) was designed for. A landmark sweeps the same screen distance
/// over its (shorter) stage, so it still enters and leaves inside it.
const double kProtoStage = 12000;

/// `mod`: always in [0, n).
double modD(double a, double n) => ((a % n) + n) % n;
int modI(int a, int n) => ((a % n) + n) % n;

double clampD(double v, double a, double b) => v < a ? a : (v > b ? b : v);

/// `smooth` (smoothstep, clamped).
double smooth(double x) {
  x = clampD(x, 0, 1);
  return x * x * (3 - 2 * x);
}

/// JS `Math.round` (halves round towards +∞).
int jsRound(double x) => (x + 0.5).floor();

/// JS `ToInt32` of an integral number.
int _toInt32(num n) {
  final i = n is int ? n : n.truncate();
  return i & 0xFFFFFFFF;
}

/// `hash(n)`: the prototype's integer hash, mapped to [0, 1).
double hash(num n) {
  var x = _toInt32(n);
  x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xFFFFFFFF;
  x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xFFFFFFFF;
  x ^= x >> 16;
  return x / 4294967296;
}

/// `rng(k, s)`: a deterministic stream per tile. Reusable ([reset]) so the
/// hot path allocates nothing.
class Rng {
  Rng([int k = 0, int s = 0]) {
    reset(k, s);
  }

  int _base = 0;
  int _i = 0;

  void reset(int k, int s) {
    _base = k * 7919 + s * 104729 + 12345;
    _i = 0;
  }

  double call() => hash(_base + (_i++) * 31337);
}
