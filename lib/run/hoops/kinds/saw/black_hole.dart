import 'dart:math' as math;
import 'dart:ui';

import '../../../../game/sound.dart';
import '../../../config/saw_config.dart';
import '../../../director/plans.dart' show SawDesign;
import '../../../effects/dashed_path.dart';
import '../ring_arcs.dart';
import 'saw_kind.dart';

class _Star {
  const _Star(this.a, this.o, this.w, this.s, this.c, this.chunk);
  final double a, o, w, s;
  final Color c;
  final bool chunk;
}

/// Black Hole (PRD-2 §5.17; mock `TH.hole`, round 4): a black torus 16 pt
/// with a thin hot photon ring on its inner and outer edge, plasma racing
/// round it (near side brighter, a slight strobe); a smooth dark void ≈ 36
/// pt round the ring that also darkens the opening; stars and debris
/// spiralling in; ripples shrinking into the rim. Every 3.4 s it inhales
/// for 0.9 s: the void grows ≈ 60 %, a red glow appears, the swirl speeds
/// up, the photon ring turns pink, the strips bend more (`SawFeature`),
/// the pull peaks at 570 pt/s² and the inhale sound plays. PRD-2.2 §25:
/// the void, swirl, ripples and stars scale with the ring
/// ([SawRingState.decor]); the torus, photon ring and plasma (the rim) do
/// not.
class BlackHoleArt implements SawDesignArt {
  const BlackHoleArt();

  @override
  SawDesign get design => SawDesign.blackHole;

  static double _k(SawRingState s) => SawHoopKind.hunger(s.clock, s.seed);

  static List<_Star> _stars(SawRingState s) {
    final cached = s.fx['stars'];
    if (cached is List<_Star>) return cached;
    final r = Mulberry(s.seed * 104729 + 11);
    final out = <_Star>[];
    for (var i = 0; i < SawConfig.holeStars; i++) {
      final a = r() * RingArcs.tau,
          o = r(),
          w = .6 + r() * .8,
          sz = .8 + r() * 1.8;
      final c = r() < .55
          ? const Color(0xFFFFFFFF)
          : (r() < .5 ? const Color(0xFFB388FF) : const Color(0xFFFFB04D));
      out.add(_Star(a, o, w, sz, c, r() < .12));
    }
    s.fx['stars'] = out;
    return out;
  }

  /// The void: a dark shell that eats the stage round the ring.
  void _void(Canvas canvas, SawRingState s, double k) {
    final ry = s.ry, d = s.decor; // PRD-2.2 §25 decoration scale
    final e = SawConfig.holeVoid * (1 + SawConfig.holeVoidHunger * k) * d;
    final r = ry + e, rim = ry / r;
    canvas.save();
    canvas.scale((RingArcs.rx + e) / r, 1);
    final paint = Paint()
      ..shader = Gradient.radial(
        Offset.zero,
        r,
        [
          const Color(0xD1060010),
          const Color(0xF2020008),
          const Color(0xFF000000),
          Color.fromRGBO(4, 0, 14, .8 + .15 * k),
          Color.fromRGBO(30, 0, 60, .32 + .2 * k),
          const Color(0x001E003C),
        ],
        [0, rim * .8, rim, rim + (1 - rim) * .35, rim + (1 - rim) * .7, 1],
      );
    canvas.drawCircle(Offset.zero, r, paint);
    canvas.restore();
    if (k > 0) {
      RingArcs.stroke(
        canvas,
        RingArcs.half(
          ry + 14 * d,
          front: false,
          x: RingArcs.rx + 14 * d,
          full: true,
        ),
        SawConfig.holeHunger.withValues(alpha: .3 * k),
        (22 * k + 4) * d,
        blur: 14 * k * d,
      );
    }
  }

  void _swirl(Canvas canvas, SawRingState s, bool front, double k) {
    final ry = s.ry, t = s.clock, d = s.decor; // PRD-2.2 §25
    final spd = 1 + 1.6 * k;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint();
    for (final st in _stars(s)) {
      final u = ((st.o - t * .22 * spd * st.w) % 1 + 1) % 1;
      final off = (5 + 32 * u) * d;
      final ang = st.a + t * spd * (1.2 + 3.2 * (1 - u)) * st.w;
      if (RingArcs.isFront(ang) != front) continue;
      final a0 = ang - .12 - .25 * (1 - u);
      final p1 = RingArcs.ellPt(ry, ang, off);
      final p0 = RingArcs.ellPt(ry, a0, off + 3 * d);
      final alpha = math.min(1.0, u * 3) * (front ? 1 : .7);
      if (st.chunk) {
        canvas.save();
        canvas.translate(p1.dx, p1.dy);
        canvas.rotate(ang * 3);
        canvas.drawRect(
          Rect.fromLTWH(-2.5 * d, -2.5 * d, 5 * d, 5 * d),
          fill..color = Color.fromRGBO(90, 84, 104, alpha),
        );
        canvas.restore();
      } else {
        paint
          ..strokeWidth = st.s * d
          ..color = st.c.withValues(alpha: alpha);
        canvas.drawLine(p0, p1, paint);
      }
    }
    for (var j = 0; j < 3; j++) {
      final u = (t * (.7 + 1.3 * k) + j / 3) % 1;
      final o = 36 * (1 - u) * d;
      RingArcs.stroke(
        canvas,
        RingArcs.half(ry + o, front: front, x: RingArcs.rx + o),
        Color.fromRGBO(210, 180, 255, .45 * u),
        1.3 * d,
      );
    }
  }

  void _ring(Canvas canvas, SawRingState s, bool front, double k) {
    final ry = s.ry, t = s.clock;
    final strobe = .65 + .35 * RingArcs.rnd((t * 40).floor() + s.seed);
    RingArcs.stroke(
      canvas,
      RingArcs.half(ry, front: front),
      const Color(0xFF000000),
      SawConfig.holeTorus,
    );
    final hot = k > .3;
    final photon = (hot ? const Color(0xFFFFD0DA) : SawConfig.holePhoton)
        .withValues(alpha: front ? 1 : .7);
    for (final o in const [8.5, -8.5]) {
      RingArcs.stroke(
        canvas,
        RingArcs.half(ry + o, front: front, x: RingArcs.rx + o),
        photon,
        1.6,
        blur: 14,
        glow: hot ? SawConfig.holeHunger : SawConfig.holePhotonGlow,
      );
    }
    const dashes = [
      (3.0, [14.0, 10.0], -520.0),
      (2.4, [6.0, 14.0], 380.0),
      (1.7, [3.0, 9.0], -700.0),
      (1.4, [2.0, 18.0], 900.0),
    ];
    final path = RingArcs.half(ry, front: front);
    for (var i = 0; i < dashes.length; i++) {
      final (w, d, sp) = dashes[i];
      DashedPathPainter.stroke(
        canvas,
        path,
        color: SawConfig.holePlasma[i].withValues(
          alpha: (front ? 1 : .45) * strobe,
        ),
        width: w,
        dashes: d,
        phase: -(t * sp * (1 + k)),
        roundCaps: true,
      );
    }
  }

  @override
  void paintBack(Canvas canvas, SawRingState s) {
    final k = _k(s);
    _void(canvas, s, k);
    _swirl(canvas, s, false, k);
    _ring(canvas, s, false, k);
  }

  @override
  void paintFront(Canvas canvas, SawRingState s) {
    final k = _k(s);
    _ring(canvas, s, true, k);
    _swirl(canvas, s, true, k);
  }

  @override
  void ambient(SawRingState s, double dt) {
    final from = SawConfig.inhalePeriod - SawConfig.inhaleLength;
    final u =
        (s.clock + s.seed * SawConfig.inhalePhasePerSeed) %
        SawConfig.inhalePeriod;
    final last = s.fx['lu'];
    if (u >= from && last is double && last < from) {
      s.c.sfx(Sfx.sawHoleInhale);
    }
    s.fx['lu'] = u;
  }
}
