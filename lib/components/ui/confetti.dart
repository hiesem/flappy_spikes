import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// Confetti of the PRD-home-v3 mocks (`confetti()` in build73 / build74 /
/// build79): flat paper strips in the menu colours, a few gold coins
/// (spinning flat) and white 4-point stars, falling under gravity and
/// fading out at the end of their life. Removes itself when done.
///
/// - [ConfettiBurst.burst]: every piece leaves [origin] in a random
///   direction at 90 + rand x [speed] pt/s (vertical x .8, minus [up]),
///   drifting [driftX] pt/s sideways; gravity 430, fall cap 260; 2.9 s.
/// - [ConfettiBurst.rain]: pieces start above the screen across [width]
///   and drift down (gravity 90, cap 150, a gentle sway); 3.6 s.
///
/// No allocations per frame: the pieces are plain mutable records and one
/// [Paint] / [Path] is reused.
class ConfettiBurst extends Component {
  ConfettiBurst.burst({
    required Offset origin,
    required this.count,
    double speed = 220,
    double up = 170,
    double driftX = -70,
    int coinEvery = 7,
    int starEvery = 9,
    bool stars = false,
    math.Random? random,
    super.priority,
  }) : rain = false,
       life = burstLife {
    final rnd = random ?? math.Random();
    for (var i = 0; i < count; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final v = 90 + rnd.nextDouble() * speed;
      _pieces.add(
        _Piece(
          x: origin.dx,
          y: origin.dy,
          vx: math.cos(a) * v + driftX,
          vy: math.sin(a) * v * .8 - up,
          r: rnd.nextDouble() * 6,
          vr: (rnd.nextDouble() - .5) * 14,
          w: 4 + rnd.nextDouble() * 4,
          h: 2.5 + rnd.nextDouble() * 2.5,
          color: colors[i % colors.length],
          kind: i % coinEvery == 0
              ? _Kind.coin
              : (stars && i % starEvery == 0 ? _Kind.star : _Kind.strip),
        ),
      );
    }
  }

  ConfettiBurst.rain({
    required this.count,
    double width = 320,
    math.Random? random,
    super.priority,
  }) : rain = true,
       life = rainLife {
    final rnd = random ?? math.Random();
    for (var i = 0; i < count; i++) {
      _pieces.add(
        _Piece(
          x: rnd.nextDouble() * width,
          y: -20 - rnd.nextDouble() * 240,
          vx: (rnd.nextDouble() - .5) * 40,
          vy: 60 + rnd.nextDouble() * 80,
          r: rnd.nextDouble() * 6,
          vr: (rnd.nextDouble() - .5) * 10,
          w: 4 + rnd.nextDouble() * 4,
          h: 2.5 + rnd.nextDouble() * 2.5,
          color: colors[i % colors.length],
          kind: i % 8 == 0
              ? _Kind.coin
              : (i % 11 == 0 ? _Kind.star : _Kind.strip),
        ),
      );
    }
  }

  static const double burstLife = 2.9;
  static const double rainLife = 3.6;

  /// Mock `CONF_C`.
  static const List<Color> colors = [
    Color(0xFFFFB529),
    Color(0xFFFFE082),
    Color(0xFFEC008C),
    Color(0xFFFCD9EE),
    Color(0xFFFFFFFF),
    Color(0xFFFF7A1A),
  ];

  static const Color _coinColor = Color(0xFFFFB529);

  final int count;
  final bool rain;

  /// Seconds until the burst removes itself (alpha = life - t near the end).
  final double life;

  final List<_Piece> _pieces = [];
  final Paint _paint = Paint();
  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  /// White 4-point star (radius 6, waist 2).
  static final Path _star = () {
    final path = Path();
    for (var k = 0; k < 8; k++) {
      final rr = k.isOdd ? 2.0 : 6.0;
      final a = k * math.pi / 4;
      final x = math.cos(a) * rr, y = math.sin(a) * rr;
      k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }();

  double _t = 0;

  /// Seconds since the burst started (tests).
  double get elapsed => _t;

  /// Pieces of each kind (tests).
  int get coinCount => _pieces.where((p) => p.kind == _Kind.coin).length;
  int get starCount => _pieces.where((p) => p.kind == _Kind.star).length;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= life) {
      removeFromParent();
      return;
    }
    final gravity = rain ? 90.0 : 430.0;
    final cap = rain ? 150.0 : 260.0;
    for (final p in _pieces) {
      p.vy = math.min(p.vy + gravity * dt, cap);
      p.vx *= math.pow(.99, dt * 60).toDouble();
      p.x += p.vx * dt + (rain ? math.sin(_t * 3 + p.r) * .4 * dt * 60 : 0);
      p.y += p.vy * dt;
      p.r += p.vr * dt;
    }
  }

  @override
  void render(Canvas canvas) {
    final alpha = (life - _t).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    for (final p in _pieces) {
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.r);
      switch (p.kind) {
        case _Kind.coin:
          canvas.scale(math.cos(p.r * 2), 1);
          _paint.color = _coinColor.withValues(alpha: alpha);
          canvas.drawCircle(Offset.zero, 5, _paint);
          _ring.color = Color.fromRGBO(255, 255, 255, .75 * alpha);
          canvas.drawCircle(Offset.zero, 3.2, _ring);
        case _Kind.star:
          _paint.color = Color.fromRGBO(255, 255, 255, alpha);
          canvas.drawPath(_star, _paint);
        case _Kind.strip:
          _paint.color = p.color.withValues(alpha: alpha);
          canvas.drawRect(
            Rect.fromLTWH(
              -p.w / 2,
              -p.h / 2,
              p.w,
              p.h * math.cos(p.r * 1.3).abs() + .6,
            ),
            _paint,
          );
      }
      canvas.restore();
    }
  }
}

enum _Kind { strip, coin, star }

class _Piece {
  _Piece({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.vr,
    required this.w,
    required this.h,
    required this.color,
    required this.kind,
  });

  double x, y, vx, vy, r;
  final double vr, w, h;
  final Color color;
  final _Kind kind;
}
