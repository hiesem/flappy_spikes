import 'dart:math' as math;
import 'dart:ui';

import '../../../config/switch_config.dart';
import '../../../director/plans.dart' show SwitchDesign;
import '../ring_arcs.dart';
import 'lockdown.dart';
import 'switch_kind.dart';

/// Gift Wrap (PRD-2 §5.19; mock `TH.gift`): the normal pink ring with its
/// opening wrapped in white paper with pink polka dots (r 2.1, 8 pt grid),
/// a gold ribbon cross (7 pt vertical, 10 pt horizontal with darker edges)
/// and a gold bow 5 pt above the ring, swaying. The switch: pink scissors
/// snipping open and shut (≈ 1.6 Hz).
///
/// Timeline: 0–0.3 s the scissors fly to the ribbon; 0.3–0.5 s two snips;
/// 0.5 s cut: the ribbon pieces fall, the bow pops off spinning, the paper
/// tears open from the middle with a zig-zag edge over 0.3 s, 34 confetti
/// squares, "SNIP!". Crash: the paper bulges and wobbles like a drum skin
/// (≈ 0.6 s) and the bird bounces back (the shared knock).
class GiftWrapArt extends SwitchDesignArt {
  const GiftWrapArt();

  @override
  SwitchDesign get design => SwitchDesign.giftWrap;

  static final Paint _p = Paint();

  static void bow(
    Canvas c,
    double x,
    double y, [
    double rot = 0,
    double sc = 1,
  ]) {
    c.save();
    c.translate(x, y);
    c.rotate(rot);
    c.scale(sc);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = SwitchConfig.goldDark;
    for (final sg in const [-1.0, 1.0]) {
      RingArcs.poly(c, [
        Offset.zero,
        Offset(sg * 5, 12),
        Offset(sg * 2, 13),
      ], SwitchConfig.gold);
      c.save();
      c.translate(sg * 9, -5);
      c.rotate(sg * .55);
      final o = Rect.fromCenter(center: Offset.zero, width: 20, height: 12);
      c.drawOval(o, _p..color = SwitchConfig.gold);
      c.drawOval(o, edge);
      c.restore();
      c.save();
      c.translate(sg * 7, -4);
      c.rotate(sg * .55);
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 6.8, height: 4),
        _p..color = SwitchConfig.goldDark,
      );
      c.restore();
    }
    c.drawCircle(const Offset(0, -1), 4.5, _p..color = SwitchConfig.gold);
    c.drawCircle(const Offset(0, -1), 4.5, edge);
    c.restore();
  }

  static void scissors(
    Canvas c,
    double x,
    double y,
    double rot,
    double open, [
    double sc = 1.15,
  ]) {
    c.save();
    c.translate(x, y);
    c.rotate(rot);
    c.scale(sc);
    for (final sg in const [-1.0, 1.0]) {
      c.save();
      c.rotate(sg * open);
      RingArcs.poly(c, const [
        Offset(-2, -2.6),
        Offset(19, -.6),
        Offset(19, .6),
        Offset(-2, 2.6),
      ], const Color(0xFF616161));
      RingArcs.poly(c, const [
        Offset(-1, -1.6),
        Offset(18, -.3),
        Offset(18, .4),
        Offset(-1, 1.6),
      ], const Color(0xFFBDBDBD));
      final ring = Paint()..style = PaintingStyle.stroke;
      c.drawCircle(
        Offset(-9, sg * 5),
        5.4,
        ring
          ..strokeWidth = 6.4
          ..color = const Color(0xFFFFFFFF),
      );
      c.drawCircle(
        Offset(-9, sg * 5),
        5.4,
        ring
          ..strokeWidth = 3.6
          ..color = SwitchConfig.pink,
      );
      c.restore();
    }
    c.drawCircle(Offset.zero, 1.8, _p..color = SwitchConfig.plum);
    c.restore();
  }

  @override
  void paintBack(Canvas canvas, SwitchRingState s) {
    SwitchDesignArt.pinkHalf(canvas, s, front: false);
    final u = s.hitT < 0
        ? 0.0
        : RingArcs.io(RingArcs.clamp01((s.hitT - .5) / .3));
    if (u >= 1) return;
    final bl = s.get('bulge');
    final ry = s.ry;
    final ax = (RingArcs.rx - 3) * (1 - bl * .35 * math.sin(s.t * 40));
    final ay = ry - 3, gap = ay * u;
    canvas.save();
    canvas.clipPath(
      Path()..addOval(
        Rect.fromCenter(
          center: Offset(-bl * 4, 0),
          width: 2 * ax,
          height: 2 * ay,
        ),
      ),
    );
    if (gap > 0) {
      final keep = Path();
      for (final sg in const [-1.0, 1.0]) {
        keep.moveTo(-30, sg * (ay + 6));
        for (var i = 0; i <= 8; i++) {
          keep.lineTo(-30 + i * 7.5, sg * (gap + (i.isOdd ? 5 : 0)));
        }
        keep
          ..lineTo(30, sg * (ay + 6))
          ..close();
      }
      canvas.clipPath(keep);
    }
    canvas.drawRect(
      Rect.fromLTWH(-30, -ay - 4, 60, ay * 2 + 8),
      _p..color = const Color(0xFFFFFFFF),
    );
    _p.color = const Color(0xFFFF4FB7);
    final rows = (ay * 2 / 8).ceil() + 1;
    for (var r = 0; r < rows; r++) {
      for (var k = 0; k < 4; k++) {
        canvas.drawCircle(
          Offset(-12 + k * 8.0 + (r.isOdd ? 4 : 0), -ay + r * 8.0),
          2.1,
          _p,
        );
      }
    }
    if (!s.after(.5)) {
      _p.color = SwitchConfig.gold;
      canvas.drawRect(Rect.fromLTWH(-3.5, -ay - 4, 7, ay * 2 + 8), _p);
      canvas.drawRect(const Rect.fromLTWH(-30, -5, 60, 10), _p);
      _p.color = SwitchConfig.goldDark;
      canvas.drawRect(const Rect.fromLTWH(-30, -5, 60, 1.6), _p);
      canvas.drawRect(const Rect.fromLTWH(-30, 3.4, 60, 1.6), _p);
    }
    canvas.restore();
  }

  @override
  void paintFront(Canvas canvas, SwitchRingState s) {
    SwitchDesignArt.pinkHalf(canvas, s, front: true);
    if (!s.after(.5)) {
      bow(canvas, 0, -s.ry - 5, .06 * math.sin(s.t * 3), 1.15);
    }
    final u = s.hitT;
    if (u >= 0 && u < .55) {
      final k = RingArcs.clamp01(u / .3);
      final at = u < .3
          ? LockdownArt.flyPos(s, const Offset(-4, 0), k)
          : const Offset(-4, 0);
      final open = u < .3
          ? .4
          : (math.sin((u - .3) * math.pi / .125)).abs() * .45;
      scissors(canvas, at.dx, at.dy, -.5 + .5 * RingArcs.io(k), open, 1);
    }
    s.paintBits(canvas);
  }

  @override
  void paintSwitch(Canvas canvas, SwitchPickup p) {
    RingArcs.halo(canvas, Offset.zero, 30, const Color(0xFFFF4FB7), .25);
    scissors(
      canvas,
      0,
      0,
      -.5 + .12 * math.sin(p.t * 2.3),
      .12 + .3 * math.sin(p.t * 5).abs(),
      1.6,
    );
  }

  @override
  void tick(SwitchRingState s, double dt) {
    final bl = s.get('bulge');
    if (bl > 0) s.fx['bulge'] = math.max(0, bl - dt * 1.6);
    if (!s.after(.5) || !s.once('cut')) return;
    final r = s.c.cosmetic;
    final ry = s.ry;
    s.bits.add(
      SwitchBit(
        x: 0,
        y: -ry - 5,
        vx: 70,
        vy: -260,
        spin: 7,
        gravity: 700,
        life: 1.4,
        draw: (c, b) => bow(c, 0, 0, 0, 1.15),
      ),
    );
    for (var i = 0; i < 8; i++) {
      final horiz = i < 4;
      s.bits.add(
        SwitchBit(
          x: horiz ? -20 + i * 12 : 0,
          y: horiz ? 0 : -50 + (i - 4) * 30,
          vx: (r.nextDouble() - .5) * 160,
          vy: -80 - r.nextDouble() * 80,
          rot: horiz ? 0 : math.pi / 2,
          spin: (r.nextDouble() - .5) * 10,
          gravity: 800,
          life: 1,
          draw: (c, b) => c.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: 11,
              height: horiz ? 10 : 7,
            ),
            Paint()..color = SwitchConfig.gold.withValues(alpha: b.alpha),
          ),
        ),
      );
    }
    s.burst(
      s.frontPool,
      Offset.zero,
      SwitchConfig.giftConfetti,
      const [
        Color(0xFFEC008C),
        Color(0xFFFFB529),
        Color(0xFFFFFFFF),
        Color(0xFFFF4FB7),
        Color(0xFF0CD9FF),
      ],
      speed: 260,
      sMin: 4,
      sMax: 8,
      gravity: 420,
      life: 1.1,
    );
  }

  @override
  void onCrash(SwitchRingState s) {
    s.fx['bulge'] = 1;
  }
}
