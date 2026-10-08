import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../../../game/config.dart';
import '../../../config/switch_config.dart';
import '../../../director/plans.dart' show SwitchDesign;
import '../ring_arcs.dart';
import 'switch_kind.dart';

/// Lockdown, the reference design (PRD-2 §5.19; mock `TH.lock`): the normal
/// pink ring with two chains crossed over it in an X (13 links each,
/// alternating face / edge links), a gold padlock where they cross and a
/// grey LOCKED sign 34 pt above with a blinking red siren. The switch is a
/// gold key (tilted −35°, rocking ±10°).
///
/// Timeline: 0–0.35 s the key flies on an arc into the padlock; 0.35–0.5 s
/// it turns (click); 0.5 s unlock: 26 links fly off (gravity 900,
/// spinning), the padlock drops with its shackle open, gold sparks, the
/// siren turns green with a ✓ and the sign pops (×1.15) to CLEAR!.
/// Crash: the chains shake (≈ 0.45 s), the siren blinks fast, grey / white
/// bits.
class LockdownArt extends SwitchDesignArt {
  const LockdownArt();

  @override
  SwitchDesign get design => SwitchDesign.lockdown;

  static const _chains = [
    (Offset(-25, -52), Offset(25, 38)),
    (Offset(25, -52), Offset(-25, 38)),
  ];

  static final Paint _p = Paint();
  static final Paint _s = Paint()..style = PaintingStyle.stroke;

  static void key(Canvas c, double x, double y, double rot, [double sc = 1]) {
    c.save();
    c.translate(x, y);
    c.rotate(rot);
    c.scale(sc);
    Path body() => Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: const Offset(-11, 0), radius: 9))
      ..addOval(Rect.fromCircle(center: const Offset(-11, 0), radius: 4.3))
      ..addRect(const Rect.fromLTWH(-3, -2.8, 22, 5.6))
      ..addRect(const Rect.fromLTWH(11, 2.8, 3.6, 5.5))
      ..addRect(const Rect.fromLTWH(16, 2.8, 3, 3.8));
    final outline = Path()
      ..addOval(Rect.fromCircle(center: const Offset(-11, 0), radius: 9))
      ..addRect(const Rect.fromLTWH(-3, -2.8, 22, 5.6))
      ..addRect(const Rect.fromLTWH(11, 2.8, 3.6, 5.5))
      ..addRect(const Rect.fromLTWH(16, 2.8, 3, 3.8));
    c.drawPath(
      outline,
      _s
        ..strokeWidth = 4.4
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFFFFFFF),
    );
    c.drawPath(body(), _p..color = SwitchConfig.gold);
    c.drawCircle(
      const Offset(-11, 0),
      6.6,
      _s
        ..strokeWidth = 1.6
        ..color = SwitchConfig.goldDark,
    );
    c.drawRect(
      const Rect.fromLTWH(-1, -1.8, 12, 1.4),
      _p..color = const Color(0xB3FFFFFF),
    );
    c.restore();
  }

  static void padlock(
    Canvas c,
    double x,
    double y, {
    double open = 0,
    double rot = 0,
  }) {
    c.save();
    c.translate(x, y);
    c.rotate(rot);
    final shackle = Path()
      ..addArc(
        Rect.fromCircle(center: Offset(open * 4, -8 - open * 6), radius: 7.5),
        math.pi,
        math.pi,
      );
    c.drawPath(
      shackle,
      _s
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF8A8A8A),
    );
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-12, -9, 24, 20),
      const Radius.circular(4),
    );
    c.drawRRect(body, _p..color = SwitchConfig.gold);
    c.drawRRect(
      body,
      _s
        ..strokeWidth = 2
        ..color = SwitchConfig.goldDark,
    );
    c.drawCircle(const Offset(0, -1), 3, _p..color = SwitchConfig.plum);
    c.drawRect(const Rect.fromLTWH(-1.3, 0, 2.6, 6), _p);
    c.restore();
  }

  static void link(
    Canvas c,
    int i,
    double x,
    double y,
    double a, [
    double alpha = 1,
  ]) {
    c.save();
    c.translate(x, y);
    c.rotate(a);
    if (i.isOdd) {
      final r = Rect.fromCenter(center: Offset.zero, width: 14, height: 8.4);
      c.drawOval(r, _p..color = Color.fromRGBO(199, 199, 199, alpha));
      c.drawOval(
        r,
        _s
          ..strokeWidth = 2.6
          ..color = Color.fromRGBO(94, 94, 94, alpha),
      );
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 6.8, height: 2.4),
        _p..color = Color.fromRGBO(94, 94, 94, alpha),
      );
    } else {
      final r = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-7, -2, 14, 4),
        const Radius.circular(2),
      );
      c.drawRRect(r, _p..color = Color.fromRGBO(158, 158, 158, alpha));
      c.drawRRect(
        r,
        _s
          ..strokeWidth = 1.6
          ..color = Color.fromRGBO(94, 94, 94, alpha),
      );
    }
    c.restore();
  }

  @override
  void paintBack(Canvas canvas, SwitchRingState s) =>
      SwitchDesignArt.pinkHalf(canvas, s, front: false);

  /// The key's flight from the switch to the padlock (ring-local).
  static Offset flyPos(
    SwitchRingState s,
    Offset to,
    double u, [
    double arc = -46,
  ]) {
    final e = RingArcs.io(u);
    final f = s.switchFrom;
    return Offset(
      f.dx + (to.dx - f.dx) * e,
      f.dy + (to.dy - f.dy) * e + arc * math.sin(math.pi * e),
    );
  }

  @override
  void paintFront(Canvas canvas, SwitchRingState s) {
    SwitchDesignArt.pinkHalf(canvas, s, front: true);
    final u = s.hitT;
    final sh = s.get('shake');
    final burst = s.after(.5);
    final jx = (s.c.cosmetic.nextDouble() - .5) * sh * 7;
    if (!burst) {
      canvas.save();
      canvas.translate(jx, 0);
      for (final (a, b) in _chains) {
        final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
        const n = SwitchConfig.chainLinks - 1;
        for (var i = 0; i <= n; i++) {
          final p = Offset.lerp(a, b, i / n)!;
          link(canvas, i, p.dx, p.dy, ang);
        }
      }
      padlock(canvas, 0, -7, rot: sh * .3 * math.sin(s.t * 60));
      canvas.restore();
    }
    // The key flying in and turning.
    if (u >= 0 && u < .55) {
      if (u < .35) {
        final k = u / .35;
        final at = flyPos(s, const Offset(0, -6), k);
        key(
          canvas,
          at.dx - 14 * (1 - RingArcs.io(k)),
          at.dy,
          -.6 + .6 * RingArcs.io(k),
          1 + (.75 - 1) * k,
        );
      } else {
        final k = RingArcs.clamp01((u - .35) / .15);
        canvas.save();
        canvas.translate(0, -6);
        canvas.scale(1, math.cos(k * math.pi / 2) * .8 + .2);
        key(canvas, -14, 0, 0, .75);
        canvas.restore();
      }
    }
    s.paintBits(canvas);
    _sign(canvas, s, jx, burst);
  }

  void _sign(Canvas c, SwitchRingState s, double jx, bool ok) {
    final sy = -s.ry - SwitchConfig.signAbove;
    final pop = ok ? RingArcs.back(RingArcs.clamp01((s.hitT - .5) / .3)) : 1.0;
    final blink = .5 + .5 * math.sin(s.t * (s.get('shake') > 0 ? 40 : 12));
    c.save();
    c.translate(jx * .4, sy);
    c.scale(pop);
    if (!ok) {
      RingArcs.halo(c, const Offset(0, -20), 26, SwitchConfig.red, .45 * blink);
    } else {
      RingArcs.halo(c, const Offset(0, -20), 24, SwitchConfig.green, .35);
    }
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-11, -17, 22, 6),
        const Radius.circular(2),
      ),
      _p..color = const Color(0xFF9E9E9E),
    );
    c.drawArc(
      Rect.fromCircle(center: const Offset(0, -17), radius: 10),
      math.pi,
      math.pi,
      true,
      _p..color = ok ? SwitchConfig.green : SwitchConfig.red,
    );
    c.drawOval(
      Rect.fromCenter(center: const Offset(-4, -22), width: 4.4, height: 7),
      _p..color = const Color(0x59FFFFFF),
    );
    if (ok) {
      c.drawPath(
        Path()
          ..moveTo(-4, -20.5)
          ..lineTo(-1, -18)
          ..lineTo(4.5, -24),
        _s
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFFFFFF),
      );
    } else {
      c.drawRect(
        const Rect.fromLTWH(-1.3, -25.5, 2.6, 6),
        _p..color = const Color(0xFFFFFFFF),
      );
      c.drawRect(const Rect.fromLTWH(-1.3, -18.5, 2.6, 2.4), _p);
    }
    final plate = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-40, -11, 80, 24),
      const Radius.circular(6),
    );
    c.drawRRect(plate, _p..color = const Color(0xFFBDBDBD));
    c.drawRRect(
      plate,
      _s
        ..strokeWidth = 2.5
        ..color = const Color(0xFF616161),
    );
    for (final o in const [
      Offset(-34, -5),
      Offset(34, -5),
      Offset(-34, 7),
      Offset(34, 7),
    ]) {
      c.drawCircle(o, 2, _p..color = const Color(0xFF8A8A8A));
    }
    outlinedText(
      c,
      ok ? 'CLEAR!' : 'LOCKED',
      const Offset(0, 1.5),
      13,
      const Color(0xFFFFFFFF),
      const Color(0xFF424242),
      3.4,
    );
    c.restore();
  }

  /// Centred outlined text (Opificio).
  static void outlinedText(
    Canvas c,
    String text,
    Offset at,
    double size,
    Color fill,
    Color stroke,
    double width,
  ) {
    for (final paint in [
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..color = stroke,
      Paint()..color = fill,
    ]) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: Config.uiFont,
            fontSize: size,
            foreground: paint,
          ),
        ),
        textDirection: p.TextDirection.ltr,
      )..layout();
      tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  void paintSwitch(Canvas canvas, SwitchPickup p) {
    RingArcs.halo(canvas, Offset.zero, 30, const Color(0xFFFFD54A), .35);
    key(
      canvas,
      0,
      0,
      -.6 + .18 * math.sin(p.t * 2.4),
      1.15 + .06 * math.sin(p.t * 2 * math.pi),
    );
  }

  @override
  void tick(SwitchRingState s, double dt) {
    final sh = s.get('shake');
    if (sh > 0) s.fx['shake'] = math.max(0, sh - dt * 2.2);
    if (s.after(.5) && s.once('burst')) {
      final r = s.c.cosmetic;
      for (final (a, b) in _chains) {
        for (var i = 0; i <= 12; i++) {
          final p = Offset.lerp(a, b, i / 12)!;
          final ang = math.atan2(p.dy, p.dx);
          final idx = i;
          s.bits.add(
            SwitchBit(
              x: p.dx,
              y: p.dy,
              vx: math.cos(ang) * (80 + r.nextDouble() * 120),
              vy: math.sin(ang) * 90 - 120,
              rot: r.nextDouble() * 6,
              spin: (r.nextDouble() - .5) * 14,
              gravity: 900,
              life: 1.1,
              draw: (c, bit) => link(c, idx, 0, 0, 0, bit.alpha),
            ),
          );
        }
      }
      s.bits.add(
        SwitchBit(
          x: 0,
          y: -7,
          vx: -30,
          vy: -160,
          spin: 3,
          gravity: 1000,
          life: 1.4,
          draw: (c, bit) => padlock(c, 0, 0, open: 1),
        ),
      );
      s.burst(
        s.frontPool,
        const Offset(0, -7),
        14,
        const [Color(0xFFFFB529), Color(0xFFFFFFFF), Color(0xFFFFD54A)],
        speed: 190,
        sMin: 4,
        sMax: 7,
      );
    }
  }

  @override
  void onCrash(SwitchRingState s) {
    s.fx['shake'] = 1;
    final b = s.birdLocal ?? Offset(-20, 0);
    s.burst(
      s.frontPool,
      Offset(-10, b.dy),
      8,
      const [Color(0xFF9E9E9E), Color(0xFFFFFFFF)],
      speed: 140,
      sMin: 3,
      sMax: 6,
    );
  }
}
