import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// Fireworks of the results page and the VS intro (PRD-2 §5.10 / §5.8, the
/// mocks' `rocket()` / `burst()`): a 4 × 7 rocket rises from [launchY] to
/// its burst height in 0.5 s, then bursts into 34 streaks (110–190 pt/s,
/// 25 % white, gravity 110, drag 1.2 /s, 0.8–1.1 s, 3 pt lines fading out).
///
/// One component holds every rocket and spark (plain records, one reused
/// [Paint]); it stays mounted until its owner removes it.
class Fireworks extends Component {
  Fireworks({this.launchY = 700, math.Random? random, super.priority})
    : _rnd = random ?? math.Random();

  /// Where rockets start (the bottom of the 711 page in the mock).
  final double launchY;
  final math.Random _rnd;

  /// Seconds a rocket rises.
  static const double rise = .5;

  /// Streaks per burst.
  static const int sparks = 34;

  final List<_Rocket> _rockets = [];
  final List<_Spark> _sparks = [];
  final Paint _paint = Paint()
    ..strokeWidth = 3
    ..style = PaintingStyle.stroke;
  final Paint _fill = Paint();

  /// Rockets still rising and sparks alive (tests).
  int get rocketsAlive => _rockets.length;
  int get sparksAlive => _sparks.length;

  /// Bursts so far (tests).
  int bursts = 0;

  /// Launches a rocket at [x] that bursts at [burstY] in [color], after
  /// [delay] s.
  void launch(double x, double burstY, Color color, {double delay = 0}) {
    _rockets.add(
      _Rocket(
        x: x,
        y: launchY,
        vx: (_rnd.nextDouble() - .5) * 40,
        vy: -(launchY - burstY) / rise,
        burstY: burstY,
        color: color,
        delay: delay,
      ),
    );
  }

  void _burst(double x, double y, Color color) {
    bursts++;
    for (var i = 0; i < sparks; i++) {
      final a = i / sparks * math.pi * 2;
      final v = 110 + _rnd.nextDouble() * 80;
      _sparks.add(
        _Spark(
          x: x,
          y: y,
          vx: math.cos(a) * v,
          vy: math.sin(a) * v,
          color: _rnd.nextDouble() < .25 ? const Color(0xFFFFFFFF) : color,
          life: .8 + _rnd.nextDouble() * .3,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    for (var i = _rockets.length - 1; i >= 0; i--) {
      final r = _rockets[i];
      if (r.delay > 0) {
        r.delay -= dt;
        continue;
      }
      r.x += r.vx * dt;
      r.y += r.vy * dt;
      if (r.y <= r.burstY) {
        _rockets.removeAt(i);
        _burst(r.x, r.y, r.color);
      }
    }
    for (var i = _sparks.length - 1; i >= 0; i--) {
      final s = _sparks[i];
      s.t += dt;
      if (s.t > s.life) {
        _sparks.removeAt(i);
        continue;
      }
      s.vy += 110 * dt;
      final damp = 1 - 1.2 * dt;
      s.vx *= damp;
      s.vy *= damp;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
    }
  }

  @override
  void render(Canvas canvas) {
    for (final r in _rockets) {
      if (r.delay > 0) continue;
      _fill.color = r.color;
      canvas.drawRect(Rect.fromLTWH(r.x - 2, r.y - 2, 4, 7), _fill);
    }
    for (final s in _sparks) {
      final k = (1 - s.t / s.life).clamp(0.0, 1.0);
      _paint.color = s.color.withValues(alpha: k);
      canvas.drawLine(
        Offset(s.x - s.vx * .04, s.y - s.vy * .04),
        Offset(s.x, s.y),
        _paint,
      );
    }
  }
}

class _Rocket {
  _Rocket({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.burstY,
    required this.color,
    required this.delay,
  });

  double x, y, delay;
  final double vx, vy, burstY;
  final Color color;
}

class _Spark {
  _Spark({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.life,
  });

  double x, y, vx, vy, t = 0;
  final Color color;
  final double life;
}
