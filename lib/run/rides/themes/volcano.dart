import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../game/sound.dart';
import '../../director/plans.dart';
import '../../effects/particle_pool.dart';
import '../ride_path.dart';
import '../ride_theme.dart';

class _Rock {
  _Rock(this.x, this.y, this.s, this.a);
  final double x, y, s, a;
}

class _Crystal {
  _Crystal(this.x, this.y, this.col, this.a, this.s);
  final double x, y;
  final Color col;
  final double a, s;
}

/// Volcano eruption (PRD-2 §5.12b, `ride_volcano_1/2/3.png`, `rides84.js`
/// #2): dive down a glowing shaft, a lava tube with three waves, crystals,
/// rock chunks with glowing cracks, a lava river and rising embers; the
/// outside view (dusk sky, dark cone, glowing crater) rumbles and smokes,
/// then the eruption shoots the bird out of the crater like the cannon
/// (lava spray, six glowing lava bombs); volcano and bombs fall away.
class VolcanoTheme extends RideTheme {
  @override
  RideId get id => RideId.volcano;

  @override
  RidePath buildPath() => RidePath.segments(const [
    RideSeg.arc(170, 90),
    RideSeg.line(720),
    RideSeg.arc(230, -90),
    RideSeg.arc(380, -40),
    RideSeg.arc(380, 80),
    RideSeg.arc(380, -40),
    RideSeg.line(420),
    RideSeg.arc(210, -90),
    RideSeg.line(1090),
  ]);

  /// PRD-2.2 §18.1 the score circle in this scene.
  @override
  Color get circleColor => const Color(0xFFC2410C);

  @override
  Color get circleDigits => const Color(0xFF2A140D);

  @override
  (Color, Color) get washTint => (const Color(0xFFFFD3BA), const Color(0xFFFFEBCD));

  @override
  Map<RideCue, Sfx> get sounds => const {
    RideCue.rumble: Sfx.rdVolcRumble,
    RideCue.boom: Sfx.rdVolcErupt,
  };

  @override
  bool get exitFill => true;

  @override
  double get exitDuration => .6;

  @override
  double get worldFadeIn => 1.2;

  @override
  Offset launchPoint(RideView v) => Offset(160, v.fromBottom(552));

  late List<_Rock> _rocks;
  late List<_Crystal> _crys;
  late double _lavaY;
  double _emberAcc = 0, _smokeAcc = 0;

  @override
  void init(RideView v) {
    final r = math.Random(11);
    final path = v.path;
    _rocks = [
      for (var i = 0; i < 60; i++)
        () {
          final s = r.nextDouble() * path.length;
          final p = path.at(s), h = path.headingAt(s);
          final n = (r.nextDouble() < .5 ? -1 : 1) * (150 + r.nextDouble() * 140);
          return _Rock(
            p.x - math.sin(h) * n,
            p.y + math.cos(h) * n,
            20 + r.nextDouble() * 50,
            r.nextDouble() * 6,
          );
        }(),
    ];
    _crys = [
      for (var i = 0; i < 16; i++)
        () {
          final s = 900.0 + i * 170;
          final p = path.at(s), h = path.headingAt(s);
          final n = (i.isOdd ? -1 : 1) * (110 + r.nextDouble() * 40);
          return _Crystal(
            p.x - math.sin(h) * n,
            p.y + math.cos(h) * n,
            i % 3 != 0 ? const Color(0xFFB388FF) : const Color(0xFF22E6FF),
            r.nextDouble() * .8 - .4,
            .8 + r.nextDouble() * .6,
          );
        }(),
    ];
    _lavaY = path.at(1700).y + 150;
  }

  @override
  void paintBackdrop(Canvas c, RideView v, Vector2 cam) {
    final full = Rect.fromLTWH(0, 0, v.w, v.h);
    vGradient(c, full, const Color(0xFF2A140D), const Color(0xFF120705));
    final gl = .25 + .1 * math.sin(v.t * 3);
    radialGlow(
      c,
      full,
      Offset(160, v.h + 60),
      520,
      Color.fromRGBO(255, 90, 26, gl + .2),
      r0: 40,
    );
  }

  @override
  void paintWorld(Canvas c, RideView v, Vector2 cam) {
    final crack = strokeOf(const Color(0x73FF6E28), 2);
    for (final k in _rocks) {
      final x = k.x - cam.x, y = k.y - cam.y;
      if (x < -80 || x > v.w + 80 || y < -80 || y > v.h + 80) continue;
      final s = k.s;
      c
        ..save()
        ..translate(x, y)
        ..rotate(k.a)
        ..drawPath(
          poly([-s, 0, -s * .3, -s * .7, s * .6, -s * .5, s, s * .2, 0, s * .6]),
          fillOf(const Color(0xFF3D2016)),
        )
        ..drawPath(
          Path()
            ..moveTo(-s * .5, 0)
            ..lineTo(0, -s * .2)
            ..lineTo(s * .4, s * .1),
          crack,
        )
        ..restore();
    }
    for (final k in _crys) {
      final x = k.x - cam.x, y = k.y - cam.y;
      if (x < -60 || x > v.w + 60 || y < -60 || y > v.h + 60) continue;
      final blur = 7 + 3 * math.sin(v.t * 4 + x);
      final glow = Paint()
        ..color = k.col
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      c
        ..save()
        ..translate(x, y)
        ..rotate(k.a)
        ..scale(k.s);
      for (final (dx, h2, w2) in const [
        (0.0, 46.0, 12.0),
        (-12.0, 30.0, 9.0),
        (12.0, 34.0, 9.0),
      ]) {
        final tri = poly([dx - w2 / 2, 0, dx, -h2, dx + w2 / 2, 0]);
        c
          ..drawPath(tri, glow)
          ..drawPath(tri, fillOf(k.col));
      }
      c.restore();
    }
    final ly = _lavaY - cam.y;
    if (ly < v.h + 60 && ly > -200) {
      final top = Path()..moveTo(0, v.h);
      final crest = Path();
      for (var x = 0.0; x <= v.w; x += 10) {
        final y = ly + math.sin(x / 30 + v.t * 3) * 6;
        top.lineTo(x, y);
        x == 0 ? crest.moveTo(x, y) : crest.lineTo(x, y);
      }
      top
        ..lineTo(v.w, v.h)
        ..close();
      for (var x = v.w; x >= 0; x -= 10) {
        crest.lineTo(x, ly + 6 + math.sin(x / 30 + v.t * 3) * 6);
      }
      crest.close();
      c
        ..drawPath(top, fillOf(const Color(0xFFFF5A1A)))
        ..drawPath(crest, fillOf(const Color(0xFFFFD54A)));
    }
  }

  @override
  void tick(RideView v, double dt) {
    if (v.phase == RidePhase.ride) {
      // Embers rising (≈ 14 per s).
      _emberAcc += dt * 14;
      while (_emberAcc >= 1) {
        _emberAcc--;
        v.screen.spawn(
          x: v.rand(0, v.w),
          y: v.h + 10,
          vx: v.rand(-10, 10),
          vy: v.rand(-120, -60),
          w: 3,
          color: const Color(0xFFFFB04A),
          life: v.rand(1.5, 3),
        );
      }
    }
    if (v.phase == RidePhase.exit && v.et < .6) {
      // Rumble smoke from the crater (≈ 24 per s).
      _smokeAcc += dt * 24;
      while (_smokeAcc >= 1) {
        _smokeAcc--;
        v.scenePool.spawn(
          shape: ParticleShape.circle,
          x: 160 + v.rand(-30, 30),
          y: v.fromBottom(555),
          vx: v.rand(-20, 20),
          vy: v.rand(-60, -30),
          w: 2 * v.rand(10, 20),
          color: const Color(0xFF786E69),
          life: 1.2,
          alpha0: .7,
          scale1: 1.5,
        );
      }
    }
  }

  @override
  void paintExitBackdrop(Canvas c, RideView v, double et, Offset off) {
    vGradient(
      c,
      Rect.fromLTWH(0, 0, v.w, v.h),
      const Color(0xFFFF8A50),
      const Color(0xFFFFD29A),
    );
  }

  @override
  void paintExit(Canvas c, RideView v, double et, Offset off) {
    final sh = et < .6 ? math.sin(et * 90) * 4 * (et / .6) : 0.0;
    final rim = v.fromBottom(560);
    c
      ..save()
      ..translate(-off.dx + sh, -off.dy)
      ..drawPath(
        poly([-40, v.h + 200, 110, rim, 210, rim, 360, v.h + 200]),
        fillOf(const Color(0xFF4A2A1D)),
      )
      ..drawRect(Rect.fromLTWH(112, rim - 4, 96, 8), fillOf(const Color(0xFFFF5A1A)))
      ..drawPath(
        poly([60, v.h + 200, 130, rim + 40, 160, rim + 80, 110, v.h + 200]),
        fillOf(const Color(0xFF3A2015)),
      )
      ..restore();
  }

  @override
  BirdPose exitPose(RideView v, double et) {
    if (v.once('rumble')) v.cue(RideCue.rumble);
    return BirdPose(v.lastBird, hidden: true);
  }

  @override
  void onLaunch(RideView v) {
    v.cue(RideCue.boom);
    final y = v.fromBottom(556);
    for (var i = 0; i < 70; i++) {
      v.blobs.add(
        RideBlob(
          RideBlobKind.lava,
          x: 160 + v.rand(-20, 20),
          y: y,
          vx: v.rand(-160, 160),
          vy: v.rand(-900, -450),
          r: v.rand(3, 7),
          life: v.rand(1, 1.8),
          gravity: 900,
          scene: true,
        ),
      );
    }
    for (var i = 0; i < 6; i++) {
      v.blobs.add(
        RideBlob(
          RideBlobKind.bomb,
          x: 160,
          y: y,
          vx: v.rand(-220, 220),
          vy: v.rand(-820, -560),
          r: v.rand(9, 14),
          life: 2.2,
          gravity: 900,
          scene: true,
        ),
      );
    }
  }
}
