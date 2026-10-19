import 'dart:math' as math;
import 'dart:ui';

/// The random idle actions of [BirdIdle].
enum BirdIdleAction { hop, lean, doubleBlink, flip, blink }

/// One pink / gold square of a tap burst.
class IdleParticle {
  IdleParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
  });

  double x, y, vx, vy;
  double life = 0;
  final Color color;
  final double size;

  static const double maxLife = 0.5;
  double get opacity => (1 - life / maxLife).clamp(0.0, 1.0);
}

/// The playful idle bird of the live home (PRD-menu-v2 §8.2) — a port of
/// `Bird` in `design/menu_v2/build55.py`. Pure state, no drawing: a
/// component steps it and reads [offset], [angle], [scaleX] / [scaleY],
/// [flap], [blinking] and [particles].
///
/// Bob ±2.2 pt (≈ 4.8 s); idle flap 1.4 cycles/s; a blink (0.24 s) now and
/// then; every 6–12 s one random action (small hop, a 2.2 s lean towards
/// START — 7 pt forward, 8° —, a double blink, or rarer a 1 s backward flip
/// with a hop); squash / stretch ±12 % on take-off and landing. [calm]
/// (the Shop's featured bird) only leans or blinks. Under reduce motion
/// ([step]'s `still`) only the bob and the flap run.
class BirdIdle {
  BirdIdle({math.Random? random, this.calm = false, double firstAction = 4.4})
    : _random = random ?? math.Random(),
      _next = firstAction;

  final math.Random _random;
  final bool calm;

  static const double gravity = 700;
  static const double kick = 170; // pt/s per unit of hop power
  static const double blinkDuration = 0.24;
  static const double doubleBlinkGap = 0.52;
  static const double leanDuration = 2.2;
  static const double leanDistance = 7;
  static const double leanAngle = 0.14; // rad, ≈ 8°
  static const double flipDuration = 1;
  static const double minGap = 6;
  static const double maxGap = 12;
  static const double bobAmplitude = 2.2;
  static const double bobSpeed = 1.3; // rad/s -> 4.8 s period
  static const double squash = 0.12;
  static const int burstCount = 7;
  static const List<Color> burstColors = [Color(0xFFEC008C), Color(0xFFFFB529)];

  double _t = 0;
  double _y = 0;
  double _vy = 0;
  double _rot = 0;
  double _sq = 0;
  double _blink = 0;
  double _lean = 0;
  double _next;
  double? _pendingBlink;
  BirdIdleAction? _act;
  double _at = 0;

  /// The gap (s) drawn when the last action fired (tests).
  double? lastGap;

  /// The last random action that fired (tests).
  BirdIdleAction? lastAction;

  final List<IdleParticle> particles = [];

  double get time => _t;

  double get velocity => _vy;
  bool get airborne => _vy != 0;

  /// Body offset from the resting centre (pt): lean forward, hop and bob.
  Offset get offset =>
      Offset(_lean * leanDistance, _y + math.sin(_t * bobSpeed) * bobAmplitude);

  /// Body rotation (rad): flip + lean + a tilt following the velocity.
  double get angle => _rot + _lean * leanAngle + (_vy / gravity).clamp(-.3, .2);

  double get scaleX => 1 + _sq * squash;
  double get scaleY => 1 - _sq * squash;

  /// Wing down: 10 cycles/s in the air (half down), 1.4 at rest (30 %).
  bool get flap => airborne ? (_t * 10) % 1 < .5 : (_t * 1.4) % 1 < .3;

  bool get blinking => _blink > 0;

  /// A hop of [power] (1 = −170 pt/s); [burst] also sprays 7 squares
  /// (taps: the bird 1.2, START 0.9).
  void hop(double power, {bool burst = false}) {
    _vy = -kick * power;
    _sq = 1;
    if (!burst) return;
    for (var i = 0; i < burstCount; i++) {
      particles.add(
        IdleParticle(
          x: -14 + _random.nextDouble() * 6,
          y: 6,
          vx: -20 - _random.nextDouble() * 60,
          vy: -30 + _random.nextDouble() * 60,
          color: burstColors[_random.nextDouble() < .5 ? 0 : 1],
          size: 3 + _random.nextDouble() * 3,
        ),
      );
    }
  }

  /// Advances by [dt]. [still] (reduce motion): no random actions or
  /// blinks; the bob, flap and any running hop continue.
  void step(double dt, {bool still = false}) {
    _t += dt;
    _vy += gravity * dt;
    _y += _vy * dt;
    if (_y > 0) {
      if (_vy > 120) _sq = -.8; // landing squash
      _y = 0;
      _vy = 0;
    }
    _sq *= math.pow(.002, dt);
    _blink -= dt;
    final pending = _pendingBlink;
    if (pending != null) {
      _pendingBlink = pending - dt;
      if (_pendingBlink! <= 0) {
        _pendingBlink = null;
        if (!still) _blink = blinkDuration;
      }
    }
    if (!still) {
      _next -= dt;
      if (_next <= 0) _fire();
    }
    final act = _act;
    if (act != null) {
      _at += dt;
      if (act == BirdIdleAction.lean) {
        _lean = math.sin(math.min(1, _at / leanDuration) * math.pi);
        if (_at > leanDuration) {
          _act = null;
          _lean = 0;
        }
      } else if (act == BirdIdleAction.flip) {
        _rot = -math.min(1, _at / flipDuration) * 2 * math.pi;
        if (_at > flipDuration) {
          _act = null;
          _rot = 0;
        }
      }
    }
    if (!still && _blink <= 0 && _random.nextDouble() < dt * .125) {
      _blink = blinkDuration;
    }
    for (final p in particles) {
      p.life += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 200 * dt;
    }
    particles.removeWhere((p) => p.life >= IdleParticle.maxLife);
  }

  void _fire() {
    final r = _random.nextDouble();
    final gap = minGap + _random.nextDouble() * (maxGap - minGap);
    _next = gap;
    lastGap = gap;
    final BirdIdleAction action;
    if (calm) {
      action = r < .5 ? BirdIdleAction.lean : BirdIdleAction.blink;
    } else if (r < .34) {
      action = BirdIdleAction.hop;
    } else if (r < .62) {
      action = BirdIdleAction.lean;
    } else if (r < .82) {
      action = BirdIdleAction.doubleBlink;
    } else {
      action = BirdIdleAction.flip;
    }
    lastAction = action;
    switch (action) {
      case BirdIdleAction.hop:
        hop(.55);
      case BirdIdleAction.lean:
        _act = BirdIdleAction.lean;
        _at = 0;
      case BirdIdleAction.blink:
        _blink = blinkDuration;
      case BirdIdleAction.doubleBlink:
        _blink = blinkDuration;
        _pendingBlink = doubleBlinkGap;
      case BirdIdleAction.flip:
        _act = BirdIdleAction.flip;
        _at = 0;
        hop(.8);
    }
  }
}
