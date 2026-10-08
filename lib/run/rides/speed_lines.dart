import 'dart:math' as math;
import 'dart:ui';

import 'ride_theme.dart';

/// Master #12 (PRD-2 §3.0.9): the speed lines are **kept separate on
/// purpose** — the comet boost (`CometSpeedLines`, WP-3a), the cannon ride
/// ([CannonSpeedLines]) and the themed rides ([RideSpeedLines]) each keep
/// the lines of their approved animation.

class _Line {
  _Line(this.x, this.y, this.dir, this.life, {this.hx = 0, this.hy = 0});
  final double x, y;

  /// Vertical travel direction (cannon: +1 down / −1 up).
  final double dir;
  final double hx, hy;
  final double life;
  double t = 0;
}

final Paint _white = Paint()..color = const Color(0xFFFFFFFF);
final Paint _whiteStroke = Paint()
  ..color = const Color(0xFFFFFFFF)
  ..strokeWidth = 2
  ..style = PaintingStyle.stroke;

/// Horizontal launch / glide lines (both rides' way back, §5.12b):
/// 70 × 2 pt, white 0.7, sliding 420 pt to the left in 0.38 s, ≈ 36 per s
/// in the flight, thinning out over 1.4 s of the glide.
class _HLines {
  final List<_Line> lines = [];
  double _acc = 0;

  static const double rate = 36, life = .38, travel = 420, w = 70, h = 2;

  void update(double dt, RideView v) {
    lines.removeWhere((l) => (l.t += dt) >= l.life);
    final double k = switch (v.phase) {
      RidePhase.fly => 1.0,
      RidePhase.glide => 1 - sm(v.gt / 1.4),
      _ => 0.0,
    };
    _acc += dt * rate * k;
    while (_acc >= 1) {
      _acc--;
      lines.add(_Line(v.rand(120, 330), v.rand(60, v.h - 11), 0, life));
    }
  }

  void paint(Canvas c) {
    _white.color = const Color(0xB3FFFFFF);
    for (final l in lines) {
      c.drawRect(Rect.fromLTWH(l.x - l.t / l.life * travel, l.y, w, h), _white);
    }
  }
}

/// §3.12 / §3.0.9 #12 the cannon ride's lines: in the ride, vertical white
/// lines (2 × 60 pt, 0.55) cross the screen top → bottom or bottom → top
/// (820 pt in 0.45 s, ≈ 42 per s); on the way back the horizontal launch
/// lines.
class CannonSpeedLines {
  final List<_Line> _lines = [];
  final _HLines _h = _HLines();
  double _acc = 0;

  static const double rate = 42, life = .45, travel = 820, len = 60, alpha = .55;

  int get count => _lines.length + _h.lines.length;

  void update(double dt, RideView v) {
    _lines.removeWhere((l) => (l.t += dt) >= l.life);
    if (v.phase == RidePhase.ride) {
      _acc += dt * rate;
      while (_acc >= 1) {
        _acc--;
        final down = v.rnd.nextBool();
        _lines.add(
          _Line(v.rand(10, 310), down ? -len : v.h + 49, down ? 1 : -1, life),
        );
      }
    }
    _h.update(dt, v);
  }

  void paint(Canvas c) {
    _white.color = const Color(0x8CFFFFFF);
    for (final l in _lines) {
      final y = l.y + l.dir * travel * (l.t / l.life);
      c.drawRect(Rect.fromLTWH(l.x, y, 2, len), _white);
    }
    _h.paint(c);
  }
}

/// §5.12b / §3.0.9 #12 the themed rides' lines: in the ride, white strokes
/// (2 pt, 60 pt long, 0.55 fading) streaming back along the flight
/// direction (≈ 500 pt over 0.38 s, ≈ 42 per s); on the way back the
/// horizontal launch lines.
class RideSpeedLines {
  final List<_Line> _lines = [];
  final _HLines _h = _HLines();
  double _acc = 0;

  static const double rate = 42, life = .38, travel = 500, len = 60, alpha = .55;

  int get count => _lines.length + _h.lines.length;

  void update(double dt, RideView v, double heading) {
    _lines.removeWhere((l) => (l.t += dt) >= l.life);
    if (v.phase == RidePhase.ride) {
      _acc += dt * rate;
      while (_acc >= 1) {
        _acc--;
        _lines.add(
          _Line(
            v.rand(0, v.w),
            v.rand(80, v.h - 40),
            0,
            life,
            hx: math.cos(heading),
            hy: math.sin(heading),
          ),
        );
      }
    }
    _h.update(dt, v);
  }

  void paint(Canvas c) {
    for (final l in _lines) {
      final k = 1 - l.t / l.life;
      final u = l.t / l.life * travel;
      _whiteStroke.color = Color.fromRGBO(255, 255, 255, alpha * k);
      c.drawLine(
        Offset(l.x - l.hx * u, l.y - l.hy * u),
        Offset(l.x - l.hx * (u + len), l.y - l.hy * (u + len)),
        _whiteStroke,
      );
    }
    _h.paint(c);
  }
}
