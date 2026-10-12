import 'dart:math' as math;
import 'dart:ui';

import '../../../../game/flappy_game.dart';
import '../../../config/switch_config.dart';
import '../../../director/plans.dart' show SwitchDesign;
import '../../../effects/dashed_path.dart';
import '../../../effects/shock_ring.dart';
import '../ring_arcs.dart';
import 'switch_kind.dart';

/// Power Iris (PRD-2 §5.19; mock `TH.iris`): a steel ring (`#3B424C` 12 pt
/// with `#AEB7C2` / `#6E7884` 7 pt) with 8 dark bulbs, a 6-blade camera
/// iris shut tight in the opening, and a cable (dashed stage foreground
/// 3 pt, 75 %) from the lever to the ring end nearest it, with a small
/// plug block — it shows with the lever, before the ring is on screen. The
/// switch: a white plate with a dark slot and a lever, red knob down.
///
/// Timeline: 0–0.1 s the lever flips up (green); 0.1–0.32 s a white spark
/// races along the cable, leaving it solid gold with a glow; 0.32–0.5 s
/// the bulbs light one by one; 0.5 s the iris spins open over 0.3 s (open
/// at 0.8 s — the ≤ 0.8 s rule; the mock's 1.07 s timing is superseded), a
/// gold ring pulses out, "POWER ON". Crash: the iris shudders, gold / white
/// / orange sparks fall.
class PowerIrisArt extends SwitchDesignArt {
  const PowerIrisArt();

  @override
  SwitchDesign get design => SwitchDesign.powerIris;

  static final Paint _p = Paint();

  static double _open(SwitchRingState s) =>
      RingArcs.io(RingArcs.clamp01((s.hitT - .5) / .3));

  void _bulbs(Canvas c, SwitchRingState s, bool front) {
    final lit = s.hitT >= 0
        ? (RingArcs.clamp01((s.hitT - .32) / .18) * 8.99).floor()
        : 0;
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i / 8 * RingArcs.tau + math.pi / 8;
      if (RingArcs.isFront(a) != front) continue;
      final p = RingArcs.ellPt(s.ry, a);
      final on = i < lit;
      if (on) RingArcs.halo(c, p, 11, const Color(0xFFFFD54A), .8);
      c.drawCircle(
        p,
        2.8,
        _p..color = on ? const Color(0xFFFFF59D) : const Color(0xFF424242),
      );
    }
  }

  void _ring(Canvas c, SwitchRingState s, bool front) {
    final path = RingArcs.half(s.ry, front: front);
    RingArcs.stroke(c, path, const Color(0xFF3B424C), 12, cap: StrokeCap.butt);
    RingArcs.stroke(
      c,
      path,
      front ? const Color(0xFFAEB7C2) : const Color(0xFF6E7884),
      7,
      cap: StrokeCap.butt,
    );
    _bulbs(c, s, front);
  }

  @override
  void paintBack(Canvas canvas, SwitchRingState s) {
    _ring(canvas, s, false);
    final u = s.hitT < 0 ? 0.0 : _open(s);
    if (u >= 1) return;
    final shake = s.get('shake') * math.sin(s.t * 70) * 2;
    final ax = RingArcs.rx - 4, ay = s.ry - 4;
    final a = 1.18 * u, sp = u * 1.4 + shake * .05;
    Offset pt(double r, double f) =>
        Offset(shake + r * math.cos(f) * ax, r * math.sin(f) * ay);
    canvas.save();
    canvas.clipPath(
      Path()..addOval(
        Rect.fromCenter(
          center: Offset(shake, 0),
          width: 2 * ax,
          height: 2 * ay,
        ),
      ),
    );
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF4A525E);
    for (var i = 0; i < 6; i++) {
      final f0 = i * math.pi / 3 + sp, f1 = f0 + math.pi / 3;
      final pts = <Offset>[pt(a, f0)];
      for (var k = 0; k <= 8; k++) {
        pts.add(pt(1.05, f0 + .4 + (math.pi / 3 + .12) * k / 8));
      }
      pts.add(pt(a, f1));
      RingArcs.poly(
        canvas,
        pts,
        i.isOdd ? const Color(0xFFAEB7C2) : const Color(0xFF8E99A6),
      );
      canvas.drawLine(pt(a, f0), pt(1.05, f0 + .4), seam);
    }
    canvas.drawCircle(
      Offset(shake, 0),
      1.8 * (1 - u),
      _p..color = const Color(0xFF4A525E),
    );
    canvas.restore();
  }

  @override
  void paintFront(Canvas canvas, SwitchRingState s) {
    _ring(canvas, s, true);
  }

  /// The cable end on the ring (pickup-local): the ring end nearest the
  /// lever, and its side (−1 top, +1 bottom).
  static (Offset, double)? _end(SwitchPickup p) {
    final h = p.ring;
    if (h == null) {
      // PRD-2.2 §15 the ring is planned but not spawned yet: its plan.
      final rp = p.ringPlan;
      if (rp == null) return null;
      final sg = p.position.y < rp.centreY ? -1.0 : 1.0;
      final ry = rp.opening / 2 + 7;
      return (
        Offset(rp.trackX - p.position.x, rp.centreY + sg * (ry + 6) - p.position.y),
        sg,
      );
    }
    final sg = p.position.y < h.position.y ? -1.0 : 1.0;
    final ry = SwitchRingKind.stateOf(h)?.ry ?? h.opening / 2 + 7;
    return (
      Offset(
        h.position.x - p.position.x,
        h.position.y + sg * (ry + 6) - p.position.y,
      ),
      sg,
    );
  }

  static Offset _bez(Offset a, Offset c1, Offset c2, Offset e, double t) {
    final m = 1 - t;
    return a * (m * m * m) +
        c1 * (3 * m * m * t) +
        c2 * (3 * m * t * t) +
        e * (t * t * t);
  }

  @override
  void paintUnder(Canvas canvas, SwitchPickup p) {
    final end = _end(p);
    if (end == null) return;
    final (e, sg) = end;
    const a = Offset(15, 0);
    final c1 = a + const Offset(60, 0);
    final c2 = e + Offset(0, sg * 55);
    const n = 40;
    final path = Path()..moveTo(a.dx, a.dy);
    for (var i = 1; i <= n; i++) {
      final q = _bez(a, c1, c2, e, i / n);
      path.lineTo(q.dx, q.dy);
    }
    final fg = p.ring == null && p.ringPlan == null
        ? const Color(0xFF828282)
        : _fg(p);
    DashedPathPainter.stroke(
      canvas,
      path,
      color: fg.withValues(alpha: .75),
      width: 3,
      dashes: const [7, 5],
      roundCaps: true,
    );
    final st = p.ringState;
    final sp = st == null || st.hitT < 0
        ? 0.0
        : RingArcs.clamp01((st.hitT - .1) / .22);
    if (sp > 0) {
      final lit = Path()..moveTo(a.dx, a.dy);
      for (var i = 1; i <= (n * sp).floor(); i++) {
        final q = _bez(a, c1, c2, e, i / n);
        lit.lineTo(q.dx, q.dy);
      }
      RingArcs.stroke(canvas, lit, SwitchConfig.gold, 3.6, blur: 8);
      if (sp < 1) {
        final q = _bez(a, c1, c2, e, sp);
        RingArcs.halo(canvas, q, 16, const Color(0xFFFFF096), .9);
        RingArcs.star4(canvas, q, 7, const Color(0xFFFFFFFF));
      }
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(e.dx - 5, sg < 0 ? e.dy - 4 : e.dy - 2, 10, 6),
        const Radius.circular(2),
      ),
      _p..color = const Color(0xFF4A525E),
    );
  }

  static Color _fg(SwitchPickup p) {
    final g = p.ringState?.c.game ?? p.findGame();
    return g is FlappySpikesGame
        ? g.foregroundColor
        : const Color(0xFF828282);
  }

  @override
  void paintSwitch(Canvas canvas, SwitchPickup p) {
    final on = p.on;
    final ang = .55 + (-.55 - .55) * RingArcs.io(on);
    RingArcs.halo(
      canvas,
      Offset.zero,
      32,
      on > 0 ? SwitchConfig.green : const Color(0xFFFFD54A),
      .3,
    );
    canvas.save();
    canvas.rotate(.08 * math.sin(p.t * 2.2));
    final plate = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-14, -21, 28, 42),
      const Radius.circular(6),
    );
    canvas.drawRRect(plate, _p..color = const Color(0xFFFFFFFF));
    canvas.drawRRect(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF616161),
    );
    for (final y in const [-16.0, 16.0]) {
      canvas.drawCircle(Offset(0, y), 1.6, _p..color = const Color(0xFFBDBDBD));
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-3.5, -11, 7, 22),
        const Radius.circular(3.5),
      ),
      _p..color = const Color(0xFF424242),
    );
    canvas.save();
    canvas.rotate(ang);
    canvas.drawLine(
      Offset.zero,
      const Offset(0, 16),
      Paint()
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF9E9E9E),
    );
    canvas.drawCircle(
      const Offset(0, 17),
      6,
      _p..color = on > 0 ? SwitchConfig.green : SwitchConfig.red,
    );
    canvas.drawCircle(
      const Offset(-2, 15.5),
      2,
      _p..color = const Color(0x73FFFFFF),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  void tick(SwitchRingState s, double dt) {
    final sh = s.get('shake');
    if (sh > 0) s.fx['shake'] = math.max(0, sh - dt * 2.5);
    if (s.after(.5) && s.once('pulse')) {
      s.c.layers.fx.add(
        ShockRing().play(
          Offset(s.hoop.position.x, s.hoop.position.y),
          rx: RingArcs.rx,
          ry: s.ry,
          color: const Color(0xFFFFD54A),
          length: .7,
          scaleFrom: 1,
          scaleTo: 1,
          grow: 60,
          strokeFrom: 5,
          strokeTo: 1,
        ),
      );
    }
  }

  @override
  void onCrash(SwitchRingState s) {
    s.fx['shake'] = 1;
    final b = s.birdLocal ?? const Offset(-20, 0);
    s.burst(
      s.frontPool,
      Offset(-RingArcs.rx, b.dy),
      14,
      const [Color(0xFFFFD54A), Color(0xFFFFFFFF), Color(0xFFFF9800)],
      speed: 230,
      sMin: 2,
      sMax: 4,
      gravity: 500,
    );
  }
}
