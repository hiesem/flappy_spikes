import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../game/sound.dart';
import '../../director/plans.dart';
import '../../effects/particle_pool.dart';
import '../ride_path.dart';
import '../ride_theme.dart';

class _Star {
  _Star(this.x, this.y, this.s, this.tw);
  final double x, y, s, tw;
}

class _Planet {
  _Planet(this.x, this.y, this.r, this.kind);
  final double x, y, r;
  final String kind;
}

class _Peel {
  _Peel(this.x, this.y);
  double x, y, vx = 300, vy = -500, t = 0;
}

/// Space trip (PRD-2 §5.12b, `ride_space_1/2/3.png`, `rides84.js` #1):
/// night sky, two nebulae, three twinkling parallax star layers, a ringed
/// planet, a blue planet and a moon; Mars rises, the bird lands in red
/// dust, hops into a small rocket that ignites, shakes and launches; the
/// nose cone pops at 0.85 s of the flight and the empty rocket peels away.
class SpaceTheme extends RideTheme {
  @override
  RideId get id => RideId.space;

  @override
  RidePath buildPath() => RidePath.segments(const [
    RideSeg.arc(180, -90),
    RideSeg.line(1050),
    RideSeg.arc(320, 90),
    RideSeg.arc(440, -50),
    RideSeg.arc(440, 100),
    RideSeg.arc(440, -50),
    RideSeg.line(520),
    RideSeg.arc(600, 35),
  ]);

  /// PRD-2.2 §18.1 the score circle in this scene.
  @override
  Color get circleColor => const Color(0xFF6E5BD6);

  @override
  Color get circleDigits => const Color(0xFF1F1252);

  @override
  (Color, Color) get washTint => (const Color(0xFFCFC8F2), const Color(0xFFC9E7F6));

  @override
  Map<RideCue, Sfx> get sounds => const {
    RideCue.thump: Sfx.rdSpaceLand,
    RideCue.rocket: Sfx.rdSpaceRocket,
    RideCue.pop: Sfx.rdSpacePop,
  };

  @override
  double get exitDuration => 1.6;

  @override
  double get worldFadeIn => 1.2;

  @override
  Offset launchPoint(RideView v) => Offset(215, v.fromBottom(470));

  late List<List<_Star>> _stars;
  late List<_Planet> _planets;
  _Peel? _peel;

  @override
  void init(RideView v) {
    final r = math.Random(7);
    _stars = [
      for (var l = 0; l < 3; l++)
        [
          for (var i = 0; i < 70; i++)
            _Star(
              r.nextDouble() * v.w,
              r.nextDouble() * v.h,
              .6 + r.nextDouble() * (1 + l),
              r.nextDouble() * 6,
            ),
        ],
    ];
    final a = v.path.at(1500), b = v.path.at(2550), m = v.path.at(3500);
    _planets = [
      _Planet(a.x + 210, a.y - 40, 70, 'ring'),
      _Planet(b.x - 210, b.y + 170, 55, 'blue'),
      _Planet(m.x + 150, m.y - 170, 26, 'moon'),
    ];
  }

  static double _wrap(double v, double m) => ((v % m) + m) % m;

  @override
  void paintBackdrop(Canvas c, RideView v, Vector2 cam) {
    final full = Rect.fromLTWH(0, 0, v.w, v.h);
    vGradient(c, full, const Color(0xFF08071F), const Color(0xFF1F1252));
    for (final (wx, wy, col) in const [
      (60.0, -200.0, Color(0x29EC008C)),
      (400.0, -900.0, Color(0x337C4DFF)),
    ]) {
      radialGlow(c, full, Offset(wx - cam.x * .25, wy - cam.y * .25), 260, col);
    }
    for (var l = 0; l < 3; l++) {
      final f = .15 + l * .3;
      for (final s in _stars[l]) {
        final x = _wrap(s.x - cam.x * f, v.w), y = _wrap(s.y - cam.y * f, v.h);
        final tw = .5 + .5 * math.sin(v.t * 2 + s.tw);
        c.drawRect(
          Rect.fromLTWH(x, y, s.s, s.s),
          fillOf(const Color(0xFFFFFFFF), .4 + .6 * tw),
        );
      }
    }
  }

  @override
  void paintWorld(Canvas c, RideView v, Vector2 cam) {
    final bx = 70.0, by = v.h * 360 / 711;
    for (final p in _planets) {
      final x = p.x - cam.x * .6 - bx * .4, y = p.y - cam.y * .6 - by * .4;
      if (x < -160 || x > v.w + 160 || y < -160 || y > v.h + 160) continue;
      switch (p.kind) {
        case 'ring':
          c.drawCircle(Offset(x, y), p.r, fillOf(const Color(0xFFF2B880)));
          for (var i = -2; i <= 2; i++) {
            c.drawRect(
              Rect.fromLTWH(x - p.r * .9, y + i * 18 - 4, p.r * 1.8, 6),
              fillOf(const Color(0xFFE0915A)),
            );
          }
          c
            ..save()
            ..translate(x, y)
            ..rotate(-.35)
            ..drawOval(
              Rect.fromCenter(center: Offset.zero, width: p.r * 3.4, height: p.r * .84),
              strokeOf(const Color(0xFFFFE0B2), 7),
            )
            ..restore();
        case 'blue':
          c
            ..drawCircle(Offset(x, y), p.r, fillOf(const Color(0xFF29B6F6)))
            ..drawCircle(Offset(x - 14, y - 10), 18, fillOf(const Color(0xFF66BB6A)))
            ..drawCircle(Offset(x + 20, y + 16), 12, fillOf(const Color(0xFF66BB6A)));
        default:
          c
            ..drawCircle(Offset(x, y), p.r, fillOf(const Color(0xFFCFD8DC)))
            ..drawCircle(Offset(x - 7, y - 4), 5, fillOf(const Color(0xFF90A4AE)))
            ..drawCircle(Offset(x + 8, y + 7), 4, fillOf(const Color(0xFF90A4AE)));
      }
    }
  }

  @override
  void paintExit(Canvas c, RideView v, double et, Offset off) {
    // Mars rises from below (glow, craters); the rocket sits on it until
    // the launch.
    final rise = easeOut(et / .5);
    final cy = v.h + 620 - rise * 190;
    c
      ..save()
      ..translate(-off.dx, -off.dy)
      ..drawCircle(Offset(160, cy), 640, fillOf(const Color(0x40FF7850)))
      ..drawCircle(Offset(160, cy), 610, fillOf(const Color(0xFFD2542E)));
    for (final (dx, dy, r) in const [
      (-120.0, -560.0, 26.0),
      (60.0, -585.0, 16.0),
      (150.0, -540.0, 22.0),
      (-30.0, -520.0, 12.0),
    ]) {
      c.drawOval(
        Rect.fromCenter(center: Offset(160 + dx, cy + dy), width: 2 * r, height: .8 * r),
        fillOf(const Color(0xFFA83E22)),
      );
    }
    if (et < exitDuration) {
      final shake = et > 1.2 ? math.sin(et * 80) * 1.2 : 0;
      rocket(c, Offset(215, cy - 644 + shake), 0, fire: et > 1.2, t: et);
    }
    c.restore();
  }

  @override
  BirdPose exitPose(RideView v, double et) {
    final l = v.lastBird;
    final land = Offset(175, v.fromBottom(548));
    if (et < .8) {
      final k = easeOut(et / .8);
      if (et > .78 && v.once('land')) {
        v.cue(RideCue.thump);
        _dust(v, Offset(175, v.fromBottom(560)), const Color(0xFFC9643F));
      }
      return BirdPose(lerpO(l, land, k), rot: lerpD(v.lastRot, 0, k));
    }
    if (et < 1.2) {
      final k = (et - .8) / .4;
      return BirdPose(
        Offset(lerpD(175, 215, k), land.dy - math.sin(k * math.pi) * 50 - k * 30),
        scale: 1 - k * .5,
        hidden: et > 1.15,
      );
    }
    if (v.once('rocket')) v.cue(RideCue.rocket);
    return BirdPose(land, hidden: true);
  }

  @override
  bool projectileActive(RideView v, double ft) => ft < .85;

  @override
  bool paintProjectile(Canvas c, RideView v, double ft, Offset at, double ang) {
    if (ft >= .85) return false;
    rocket(c, at, ang + math.pi / 2, fire: true, t: ft);
    return true;
  }

  @override
  void tick(RideView v, double dt) {
    // §5.12b the nose cone pops at 0.85 s of the flight; the bird flies
    // on and the empty rocket peels away.
    if (v.phase == RidePhase.fly && v.ft >= .85 && v.once('pop')) {
      v.cue(RideCue.pop);
      _puff(v, v.bird, const Color(0xFFFFFFFF));
      _peel = _Peel(v.bird.dx, v.bird.dy);
    }
    final p = _peel;
    if (p == null) return;
    p
      ..t += dt
      ..vy += 300 * dt
      ..x += p.vx * dt
      ..y += p.vy * dt;
  }

  @override
  void paintExtra(Canvas c, RideView v) {
    final p = _peel;
    if (p == null || p.t >= 1.2) return;
    c.saveLayer(
      Rect.fromLTWH(0, 0, v.w, v.h),
      Paint()..color = Color.fromRGBO(0, 0, 0, 1 - p.t / 1.2),
    );
    rocket(c, Offset(p.x, p.y), .6 + p.t * 2, fire: false, t: p.t);
    c.restore();
  }

  static void _dust(RideView v, Offset at, Color col) {
    for (var i = 0; i < 22; i++) {
      v.screen.spawn(
        shape: ParticleShape.circle,
        x: at.dx,
        y: at.dy,
        vx: v.rand(-140, 140),
        vy: v.rand(-90, -10),
        w: 2 * v.rand(4, 9),
        color: col,
        life: v.rand(.6, 1),
        alpha0: .8,
        gravity: 60,
        drag: 2,
      );
    }
  }

  static void _puff(RideView v, Offset at, Color col) {
    for (var i = 0; i < 18; i++) {
      final a = v.rand(0, 2 * math.pi), s = v.rand(60, 160);
      v.screen.spawn(
        shape: ParticleShape.circle,
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * s,
        vy: math.sin(a) * s,
        w: 2 * v.rand(5, 10),
        color: col,
        life: .7,
        alpha0: .8,
        gravity: 60,
        drag: 2,
      );
    }
  }

  /// §5.12b the small rocket: white body, pink fins, gold / blue window.
  static void rocket(
    Canvas c,
    Offset at,
    double rot, {
    required bool fire,
    required double t,
  }) {
    c
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(rot);
    if (fire) {
      const cols = [Color(0xFFFFD54A), Color(0xFFFF7A1A), Color(0xFFE53935)];
      for (var i = 0; i < 3; i++) {
        final l = 26 + i * 10 + math.sin(t * 60 + i) * 6;
        c.drawPath(
          poly([-9.0 + i * 2, 22, 0, 22 + l, 9.0 - i * 2, 22]),
          fillOf(cols[i]),
        );
      }
    }
    c
      ..drawPath(poly(const [-14, 22, -24, 30, -14, 6]), fillOf(const Color(0xFFEC008C)))
      ..drawPath(poly(const [14, 22, 24, 30, 14, 6]), fillOf(const Color(0xFFEC008C)));
    final body = Path()
      ..moveTo(-14, 22)
      ..lineTo(-14, -14)
      ..quadraticBezierTo(0, -44, 14, -14)
      ..lineTo(14, 22)
      ..close();
    c
      ..drawPath(body, fillOf(const Color(0xFFF5F5F5)))
      ..drawCircle(const Offset(0, -6), 7, fillOf(const Color(0xFFFFB529)))
      ..drawCircle(const Offset(0, -6), 4.5, fillOf(const Color(0xFF29B6F6)))
      ..restore();
  }
}
