import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../game/sound.dart';
import '../../director/plans.dart';
import '../../effects/particle_pool.dart';
import '../ride_path.dart';
import '../ride_theme.dart';

class _School {
  _School(this.x, this.y, this.n, this.col, this.ph);
  final double x, y;
  final int n;
  final Color col;
  final double ph;
}

class _Jelly {
  _Jelly(this.x, this.y, this.ph);
  final double x, y, ph;
}

/// Deep sea dive (PRD-2 §5.12b, `ride_sea_1/2/3.png`, `rides84.js` #3):
/// a splash dive, water darkening with depth, light shafts, the surface at
/// the start, schools of fish, pink jellyfish, a sunken ship, swaying
/// seaweed and bubbles from the bird; near the surface a friendly blue
/// whale swims in, the bird lands on its back and the spout fires it out of
/// the water; the sea falls away.
class SeaTheme extends RideTheme {
  @override
  RideId get id => RideId.sea;

  @override
  RidePath buildPath() => RidePath.segments(const [
    RideSeg.arc(160, 90),
    RideSeg.line(520),
    RideSeg.arc(260, -90),
    RideSeg.arc(420, -45),
    RideSeg.arc(420, 90),
    RideSeg.arc(420, -90),
    RideSeg.arc(420, 45),
    RideSeg.line(780),
    RideSeg.arc(600, 30),
  ]);

  @override
  (Color, Color) get washTint => (const Color(0xFFBFE3F5), const Color(0xFFD3F1F7));

  @override
  Map<RideCue, Sfx> get sounds => const {
    RideCue.splash: Sfx.rdSeaSplash,
    RideCue.bubble: Sfx.rdSeaBubble,
    RideCue.whale: Sfx.rdSeaWhale,
    RideCue.thump: Sfx.rdSpaceLand,
    RideCue.spout: Sfx.rdSeaSpout,
  };

  @override
  bool get exitFill => true;

  @override
  double get exitDuration => 1.3;

  @override
  double get worldFadeIn => 1.2;

  @override
  Offset launchPoint(RideView v) => Offset(178, v.fromBottom(448));

  late List<_School> _fish;
  late List<_Jelly> _jelly;
  late Offset _ship;
  late double _floorY;
  double _bubbleAcc = 0;

  @override
  void init(RideView v) {
    final r = math.Random(23);
    final path = v.path;
    const cols = [
      Color(0xFFFFB529),
      Color(0xFFFF7043),
      Color(0xFF66BB6A),
      Color(0xFFFF4FB7),
    ];
    _fish = [
      for (var i = 0; i < 9; i++)
        () {
          final s = 700.0 + i * 380;
          final p = path.at(s), h = path.headingAt(s);
          final n = (i.isOdd ? -1 : 1) * (90 + r.nextDouble() * 80);
          return _School(
            p.x - math.sin(h) * n,
            p.y + math.cos(h) * n,
            4 + (r.nextDouble() * 4).floor(),
            cols[i % 4],
            r.nextDouble() * 6,
          );
        }(),
    ];
    _jelly = [
      for (var i = 0; i < 6; i++)
        () {
          final s = 1100.0 + i * 520;
          final p = path.at(s), h = path.headingAt(s);
          final n = (i.isOdd ? 1 : -1) * (120 + r.nextDouble() * 60);
          return _Jelly(
            p.x - math.sin(h) * n,
            p.y + math.cos(h) * n,
            r.nextDouble() * 6,
          );
        }(),
    ];
    final sp = path.at(2650);
    _ship = Offset(sp.x + 60, sp.y + 250);
    final (_, _, _, maxY) = path.bounds;
    _floorY = maxY + 230;
  }

  static double _wrap(double v, double m) => ((v % m) + m) % m;

  @override
  void paintWorld(Canvas c, RideView v, Vector2 cam) {
    final t = v.t;
    final depth = ((cam.y + 360) / 1200).clamp(0.0, 1.0);
    int l(double a, double b) => lerpD(a, b, depth).round();
    final top = Color.fromARGB(255, l(79, 8), l(201, 58), l(242, 104));
    final bot = Color.fromARGB(255, l(14, 4), l(74, 30), l(125, 60));
    vGradient(c, Rect.fromLTWH(0, 0, v.w, v.h), top, bot);
    final shaft = fillOf(const Color(0xFFFFFFFF), .08 * (1 - depth * .6));
    for (var i = 0; i < 4; i++) {
      final x = _wrap(i * 110 - cam.x * .2, 440) - 60;
      c.drawPath(poly([x, 0, x + 50, 0, x + 160, v.h, x + 90, v.h]), shaft);
    }
    final sy = 20 - cam.y;
    if (sy > -20) {
      final sky = Path()
        ..moveTo(0, 0)
        ..lineTo(v.w, 0);
      final line = Path();
      for (var x = v.w; x >= 0; x -= 10) {
        sky.lineTo(x, sy + math.sin(x / 25 + t * 4) * 4);
      }
      for (var x = 0.0; x <= v.w; x += 10) {
        final y = sy + math.sin(x / 25 + t * 4) * 4;
        x == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
      }
      c
        ..drawPath(sky..close(), fillOf(const Color(0xFFF1F1F1)))
        ..drawPath(line, strokeOf(const Color(0xFFFFFFFF), 3));
    }
    final fy = _floorY - cam.y;
    if (fy < v.h + 40) {
      c.drawRect(Rect.fromLTWH(0, fy, v.w, v.h), fillOf(const Color(0xFF0B2F4F)));
      final weed = strokeOf(const Color(0xFF2E7D32), 5);
      for (var i = 0; i < 12; i++) {
        final x = _wrap(i * 47 - cam.x, 560) - 120;
        c.drawPath(
          Path()
            ..moveTo(x, fy)
            ..quadraticBezierTo(
              x + math.sin(t * 2 + i) * 14,
              fy - 40,
              x + math.sin(t * 2 + i + 1) * 10,
              fy - 70,
            ),
          weed,
        );
      }
    }
    final x = _ship.dx - cam.x, y = _ship.dy - cam.y;
    if (x > -200 && x < v.w + 200 && y > -200 && y < v.h + 200) {
      final hull = fillOf(const Color(0xBF141E28));
      c
        ..drawPath(poly([x - 90, y, x + 80, y - 14, x + 64, y + 30, x - 70, y + 40]), hull)
        ..drawRect(Rect.fromLTWH(x - 10, y - 110, 6, 100), hull)
        ..drawPath(poly([x - 4, y - 104, x + 40, y - 80, x - 4, y - 60]), hull);
    }
    for (final f in _fish) {
      for (var j = 0; j < f.n; j++) {
        final fx =
            f.x - cam.x + j * 22 + math.sin(t * 2 + f.ph + j) * 6 + (t * 40) % 600 - 300;
        final fyy = f.y - cam.y + (j % 2) * 14 + math.cos(t * 3 + j) * 4;
        if (fx < -30 || fx > v.w + 30 || fyy < -30 || fyy > v.h + 30) continue;
        c
          ..drawOval(
            Rect.fromCenter(center: Offset(fx, fyy), width: 18, height: 10),
            fillOf(f.col),
          )
          ..drawPath(poly([fx - 8, fyy, fx - 15, fyy - 5, fx - 15, fyy + 5]), fillOf(f.col))
          ..drawRect(Rect.fromLTWH(fx + 4, fyy - 2, 2, 2), fillOf(const Color(0xFFFFFFFF)));
      }
    }
    final tent = strokeOf(const Color(0x99FFB4E6), 2);
    for (final j in _jelly) {
      final jx = j.x - cam.x, jy = j.y - cam.y + math.sin(t * 1.5 + j.ph) * 14;
      if (jx < -40 || jx > v.w + 40 || jy < -60 || jy > v.h + 60) continue;
      c.drawArc(
        Rect.fromCircle(center: Offset(jx, jy), radius: 16),
        math.pi,
        math.pi,
        true,
        fillOf(const Color(0x99FF8AD8)),
      );
      for (var k = 0; k < 4; k++) {
        final bx = jx - 10 + k * 7;
        c.drawPath(
          Path()
            ..moveTo(bx, jy)
            ..quadraticBezierTo(bx + math.sin(t * 3 + k) * 5, jy + 14, bx, jy + 28),
          tent,
        );
      }
    }
  }

  @override
  void tick(RideView v, double dt) {
    if (v.phase != RidePhase.ride) return;
    if (v.rt > .25 && v.once('splash')) v.cue(RideCue.splash);
    // Bubbles from the bird (≈ 10 per s; a quarter of them blub).
    _bubbleAcc += dt * 10;
    while (_bubbleAcc >= 1) {
      _bubbleAcc--;
      v.blobs.add(
        RideBlob(
          RideBlobKind.bubble,
          x: v.bird.dx - 14 + v.rand(-6, 6),
          y: v.bird.dy + v.rand(-6, 6),
          vx: v.rand(-10, 10),
          vy: v.rand(-80, -40),
          r: v.rand(2, 5),
          life: v.rand(.8, 1.4),
        ),
      );
      if (v.rnd.nextDouble() < .25) v.cue(RideCue.bubble);
    }
  }

  @override
  void paintExit(Canvas c, RideView v, double et, Offset off) {
    c.drawRect(Rect.fromLTWH(0, 0, v.w, v.h), fillOf(const Color(0xFFF1F1F1)));
    c
      ..save()
      ..translate(-off.dx, -off.dy);
    const wl = 150.0;
    vGradient(
      c,
      Rect.fromLTWH(-400, wl, v.w + 1600, v.h + 1200),
      const Color(0xFF3A9FD6),
      const Color(0xFF0B3A6B),
    );
    final wave = Path();
    for (var x = -400.0; x <= v.w + 1200; x += 10) {
      final y = wl + math.sin(x / 25 + v.t * 4) * 4;
      x == -400 ? wave.moveTo(x, y) : wave.lineTo(x, y);
    }
    c.drawPath(wave, strokeOf(const Color(0xFFFFFFFF), 3));
    whale(c, Offset(lerpD(-260, 150, easeOut(et / .9)), v.fromBottom(520)), v.t);
    c.restore();
  }

  @override
  BirdPose exitPose(RideView v, double et) {
    if (v.once('whale')) v.cue(RideCue.whale);
    final back = Offset(178, v.fromBottom(470));
    if (et < .9) {
      final k = easeOut(et / .9);
      return BirdPose(lerpO(v.lastBird, back, k), rot: lerpD(v.lastRot, 0, k));
    }
    if (v.once('land')) v.cue(RideCue.thump);
    return BirdPose(back.translate(0, math.sin((et - .9) * 20) * 1.5));
  }

  @override
  void onLaunch(RideView v) {
    v.cue(RideCue.spout);
    for (var i = 0; i < 60; i++) {
      v.scenePool.spawn(
        shape: ParticleShape.circle,
        x: 178 + v.rand(-10, 10),
        y: v.fromBottom(460),
        vx: v.rand(-80, 80),
        vy: v.rand(-800, -420),
        w: 2 * v.rand(2, 5),
        color: const Color(0xFFB3F5FF),
        life: 1.1,
        gravity: 900,
      );
    }
  }

  /// §5.12b the friendly blue whale.
  static void whale(Canvas c, Offset at, double t) {
    final body = fillOf(const Color(0xFF3F7FD9));
    c
      ..save()
      ..translate(at.dx, at.dy)
      ..drawOval(Rect.fromCenter(center: Offset.zero, width: 240, height: 92), body)
      ..drawPath(
        poly([
          -110,
          -6,
          -170,
          -40 + math.sin(t * 4) * 8,
          -160,
          0,
          -170,
          36 + math.sin(t * 4) * 8,
        ]),
        body,
      )
      ..drawArc(
        Rect.fromCenter(center: const Offset(10, 22), width: 180, height: 40),
        0,
        math.pi,
        true,
        fillOf(const Color(0xFFCFE3FF)),
      )
      ..drawCircle(const Offset(70, -8), 7, fillOf(const Color(0xFFFFFFFF)))
      ..drawCircle(const Offset(72, -8), 3.5, fillOf(const Color(0xFF112233)))
      ..drawArc(
        Rect.fromCircle(center: const Offset(78, 6), radius: 14),
        .2,
        1,
        false,
        strokeOf(const Color(0xFF112233), 3),
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(28, -44), width: 18, height: 8),
        fillOf(const Color(0xFF2B5FA8)),
      )
      ..restore();
  }
}
