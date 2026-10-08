import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../game/sound.dart';
import '../../director/plans.dart';
import '../../effects/dashed_path.dart';
import '../ride_path.dart';
import '../ride_theme.dart';

class _Drop {
  _Drop(this.x, this.y, this.l);
  final double x, y, l;
}

class _Debris {
  _Debris(this.u, this.ph, this.kind);
  final double u, ph;
  final String kind;
}

/// Storm & tornado (PRD-2 §5.12b, `ride_storm_1/2/3.png`, `rides84.js`
/// #5): a short curve into a corkscrew — 4.2 turns up a narrowing funnel
/// (radius 150 → 70 pt), rings and bird scale ±12 % with depth; storm
/// gradient, dark clouds, slanted rain, spinning funnel bands, circling
/// debris (leaves, a plank, a cow), a random lightning bolt + white flash
/// every 1.4–2.4 s. The tornado spits the bird out at the top (0.4 s,
/// flash); in the glide home a pink umbrella pops open over it and folds
/// 0.3 s after the landing.
class StormTheme extends RideTheme {
  @override
  RideId get id => RideId.storm;

  /// §5.12b corkscrew: height (pt), turns, radius from → to (pt), the
  /// vertical squash of the circle (depth look).
  static const double helixHeight = 3350;
  static const double turns = 4.2;
  static const double r0 = 150, r1 = 70;
  static const double squash = .22;

  @override
  RidePath buildPath() {
    final pre = RidePath.segments(const [
      RideSeg.arc(220, -55),
      RideSeg.line(120),
    ]).points;
    final last = pre.last;
    final cx = last.x;
    final pts = [
      for (final p in pre) RidePoint(p.x, p.y, h: p.h),
      for (var i = 1; i <= 900; i++)
        () {
          final u = i / 900;
          final th = -math.pi / 2 + turns * 2 * math.pi * u;
          final r = lerpD(r0, r1, u);
          return RidePoint(
            cx - r * math.cos(th),
            last.y - helixHeight * u + r * squash * math.cos(th),
            d: math.cos(th),
          );
        }(),
    ];
    return RidePath.sampled(pts)..axisX = cx;
  }

  @override
  (Color, Color) get washTint => (const Color(0xFFCDD3DE), const Color(0xFFE4E8EF));

  @override
  Map<RideCue, Sfx> get sounds => const {
    RideCue.thunder: Sfx.rdStormThunder,
    RideCue.wind: Sfx.rdStormWind,
    RideCue.umbrella: Sfx.rdStormUmbrella,
  };

  @override
  bool get depth => true;

  @override
  bool get umbrella => true;

  @override
  double get exitDuration => .4;

  @override
  double get worldFadeIn => 1.2;

  @override
  Offset launchPoint(RideView v) => const Offset(190, 170);

  late List<_Drop> _rain;
  late List<_Debris> _debris;
  late double _y0, _y1;
  double _flash = 0, _nextBolt = 1.5;
  List<Offset>? _bolt;

  @override
  void init(RideView v) {
    final r = math.Random(31);
    _rain = [
      for (var i = 0; i < 70; i++)
        _Drop(r.nextDouble() * v.w, r.nextDouble() * v.h, 10 + r.nextDouble() * 14),
    ];
    const kinds = ['leaf', 'leaf', 'plank', 'cow', 'leaf', 'plank', 'leaf'];
    _debris = [
      for (var i = 0; i < 7; i++) _Debris(.1 + i * .12, r.nextDouble() * 6, kinds[i]),
    ];
    final p = v.path.points;
    _y0 = p[math.min(60, p.length - 1)].y;
    _y1 = p.last.y;
  }

  static double _wrap(double v, double m) => ((v % m) + m) % m;

  @override
  void paintWorld(Canvas c, RideView v, Vector2 cam) {
    final t = v.t;
    vGradient(
      c,
      Rect.fromLTWH(0, 0, v.w, v.h),
      const Color(0xFF252C3A),
      const Color(0xFF4A5468),
    );
    final cloud = fillOf(const Color(0xE61E2430));
    for (var i = 0; i < 6; i++) {
      final x = _wrap(i * 90 - cam.x * .3, 540) - 110;
      final y = 40 + (i * 37) % 60 - cam.y * .05;
      c
        ..drawCircle(Offset(x, y), 60, cloud)
        ..drawCircle(Offset(x + 50, y + 10), 45, cloud);
    }
    final ax = v.path.axisX - cam.x;
    for (var i = 0; i < 32; i++) {
      final yy = _y0 - i * 110 - cam.y;
      if (yy < -80 || yy > v.h + 80) continue;
      final rw = lerpD(190, 100, i / 32);
      DashedPathPainter.stroke(
        c,
        Path()..addOval(
          Rect.fromCenter(center: Offset(ax, yy), width: 2 * rw, height: 2 * rw * squash),
        ),
        color: Color.fromRGBO(200, 210, 225, .18 + .08 * math.sin(t * 6 + i)),
        width: 10,
        dashes: const [30, 22],
        phase: t * 240 + i * 30,
      );
    }
    for (final d in _debris) {
      final th = t * 3.2 + d.ph;
      final ry = lerpD(_y0, _y1, d.u) - cam.y;
      final rx = ax + math.cos(th) * lerpD(170, 90, d.u);
      if (ry < -50 || ry > v.h + 50) continue;
      c
        ..save()
        ..translate(rx, ry + math.sin(th) * 20)
        ..rotate(th * 2);
      switch (d.kind) {
        case 'leaf':
          c.drawOval(
            Rect.fromCenter(center: Offset.zero, width: 18, height: 8),
            fillOf(const Color(0xFF7CB342)),
          );
        case 'plank':
          c.drawRect(const Rect.fromLTWH(-16, -4, 32, 8), fillOf(const Color(0xFF8D6E63)));
        default:
          c
            ..drawRect(const Rect.fromLTWH(-14, -9, 28, 18), fillOf(const Color(0xFFFFFFFF)))
            ..drawRect(const Rect.fromLTWH(-8, -9, 8, 8), fillOf(const Color(0xFF222222)))
            ..drawRect(const Rect.fromLTWH(4, 0, 7, 6), fillOf(const Color(0xFF222222)))
            ..drawRect(const Rect.fromLTWH(12, -6, 7, 9), fillOf(const Color(0xFFFFAB91)));
      }
      c.restore();
    }
    final rain = strokeOf(const Color(0x73C8D7EB), 1.4);
    for (final r in _rain) {
      final x = _wrap(r.x - t * 120 - cam.x * .2, v.w);
      final y = _wrap(r.y + t * 700, v.h);
      c.drawLine(Offset(x, y), Offset(x - 5, y + r.l), rain);
    }
    if (_flash > 0) {
      c.drawRect(
        Rect.fromLTWH(0, 0, v.w, v.h),
        fillOf(const Color(0xFFFFFFFF), _flash * .5),
      );
      final bolt = _bolt;
      if (bolt != null) {
        final p = Path()..moveTo(bolt.first.dx, bolt.first.dy);
        for (final b in bolt.skip(1)) {
          p.lineTo(b.dx, b.dy);
        }
        c.drawPath(p, strokeOf(const Color(0xFFFFFAC8), 3, _flash));
      }
    }
  }

  @override
  void tick(RideView v, double dt) {
    _flash = math.max(0, _flash - dt * 2.5);
    if (v.phase != RidePhase.ride) return;
    _nextBolt -= dt;
    if (_nextBolt <= 0) {
      _nextBolt = v.rand(1.4, 2.4);
      _flash = 1;
      var x = v.rand(40, 280), y = 0.0;
      final b = [Offset(x, y)];
      while (y < v.h * .7) {
        x += v.rand(-30, 30);
        y += v.rand(30, 60);
        b.add(Offset(x, y));
      }
      _bolt = b;
      v.cue(RideCue.thunder);
    }
  }

  @override
  BirdPose exitPose(RideView v, double et) {
    if (v.once('spit')) {
      v.cue(RideCue.wind);
      _flash = 1;
    }
    final k = easeOut(et / .4);
    return BirdPose(lerpO(v.lastBird, const Offset(190, 170), k), rot: et * 30);
  }

  /// §5.12b the pink umbrella over the gliding bird ([s] = open 0..1).
  static void paintUmbrella(Canvas c, Offset at, double rot, double s) {
    if (s <= 0) return;
    c
      ..save()
      ..translate(at.dx, at.dy - 4)
      ..rotate(rot * .5)
      ..scale(s)
      ..drawLine(Offset.zero, const Offset(0, -58), strokeOf(const Color(0xFF7A0044), 2));
    final canopy = Path()
      ..moveTo(-46, -50)
      ..quadraticBezierTo(0, -110, 46, -50);
    for (var i = 3; i >= 0; i--) {
      canopy.quadraticBezierTo(-46 + i * 23 + 11.5, -58, -46.0 + i * 23, -50);
    }
    c
      ..drawPath(canopy..close(), fillOf(const Color(0xFFEC008C)))
      ..drawCircle(const Offset(0, -82), 4, fillOf(const Color(0xFFFFB529)))
      ..restore();
  }
}
