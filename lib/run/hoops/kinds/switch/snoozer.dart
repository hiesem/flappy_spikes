import 'dart:math' as math;
import 'dart:ui';

import '../../../config/switch_config.dart';
import '../../../director/plans.dart' show SwitchDesign;
import '../../../effects/particle_pool.dart';
import '../ring_arcs.dart';
import 'lockdown.dart';
import 'switch_kind.dart';

/// Snoozer (PRD-2 §5.19; mock `TH.sleepy`): a sleeping purple ring
/// creature (`#8E44FF` / `#5420B0` 10 pt, breathing ±2 %) with two frog
/// eyes on top (closed lids), pink cheeks, the closed mouth filling the
/// opening (`#A970FF` with a wavy seam) and purple "z" letters drifting up
/// (≈ 1.6/s). The switch: a red alarm clock with gold bells that rattles
/// every ≈ 1.3 s.
///
/// Timeline: 0 s the clock rings and a gold "!" pops above the creature;
/// 0.2 s the eyes snap open (plum pupils track the bird); 0.38 s it yawns
/// (the mouth opens wide over 0.35 s, dark mouth, pink tongue), "WAKE UP!";
/// 0.78 s the mouth fill fades, leaving two fangs at the top and the tongue
/// at the bottom. Crash: angry eyes, puffed cheeks (×1.45, 0.9 s), purple
/// puffs, the bird is spat back (the shared knock).
class SnoozerArt extends SwitchDesignArt {
  const SnoozerArt();

  @override
  SwitchDesign get design => SwitchDesign.snoozer;

  static const Color purple = Color(0xFF8E44FF);
  static const Color purpleBack = Color(0xFF5420B0);
  static final Paint _p = Paint();

  double _breath(SwitchRingState s) => 1 + .02 * math.sin(s.t * 2.2);

  @override
  void paintBack(Canvas canvas, SwitchRingState s) {
    RingArcs.stroke(
      canvas,
      RingArcs.half(s.ry * _breath(s), front: false),
      purpleBack,
      10,
      cap: StrokeCap.butt,
    );
    final yawn = s.hitT < 0
        ? 0.0
        : RingArcs.io(RingArcs.clamp01((s.hitT - .38) / .35));
    final fade = s.hitT < 0 ? 0.0 : RingArcs.clamp01((s.hitT - .78) / .25);
    final puff = s.get('puff');
    final ry = s.ry;
    if (fade < 1) {
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromRGBO(0, 0, 0, 1 - fade),
      );
      final ax = (RingArcs.rx - 3) * (1 + puff * .45), ay = ry - 3;
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 2 * ax, height: 2 * ay),
        _p..color = const Color(0xFFA970FF),
      );
      for (final yy in const [22.0, 30.0]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(-3, yy - 8),
            width: 9 * (1 + puff * .5),
            height: 6,
          ),
          _p..color = const Color(0x80FF4FB7),
        );
      }
      if (yawn <= 0) {
        final seam = Path()..moveTo(0, -24);
        for (var i = 0; i <= 16; i++) {
          seam.lineTo(math.sin(i * 1.3) * 1.6 * (1 - puff), -24 + i * 3.0);
        }
        RingArcs.stroke(canvas, seam, purpleBack, 2.4);
      } else {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: 2 * ax * math.min(1, yawn * 1.6),
            height: 2 * ay * yawn,
          ),
          _p..color = const Color(0xFF2A0A40),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, ay * yawn * .62),
            width: 2 * ax * .8 * math.min(1, yawn * 1.6),
            height: 2 * ay * yawn * .32,
          ),
          _p..color = const Color(0xFFFF4FB7),
        );
      }
      canvas.restore();
    }
    if (yawn >= 1) {
      for (final dx in const [-4.0, 4.0]) {
        RingArcs.poly(canvas, [
          Offset(dx - 3, -ry + 4),
          Offset(dx + 3, -ry + 4),
          Offset(dx, -ry + 13),
        ], const Color(0xFFFFFFFF));
      }
      canvas.drawArc(
        Rect.fromCenter(center: Offset(0, ry - 5), width: 14, height: 8),
        math.pi,
        math.pi,
        true,
        _p..color = const Color(0xCCFF4FB7),
      );
    }
  }

  List<Offset> _eyes(SwitchRingState s) => [
    Offset(-9, -s.ry - 3),
    Offset(7, -s.ry + 1),
  ];

  @override
  void paintFront(Canvas canvas, SwitchRingState s) {
    RingArcs.stroke(
      canvas,
      RingArcs.half(s.ry * _breath(s), front: true),
      purple,
      10,
      cap: StrokeCap.butt,
    );
    final awake = s.hitT >= .2 || s.crashT >= 0;
    final awakeT = s.crashT >= 0 && s.hitT < .2
        ? s.crashT + .2
        : math.max(0.0, s.hitT - .2);
    final angry = s.get('puff') > 0;
    final bird = s.birdLocal ?? const Offset(-100, 0);
    final eyes = _eyes(s);
    for (var i = 0; i < eyes.length; i++) {
      final e = eyes[i];
      canvas.drawCircle(e, 9, _p..color = purple);
      if (!awake) {
        canvas.drawArc(
          Rect.fromCircle(center: e + const Offset(0, 1), radius: 5),
          .15 * math.pi,
          .7 * math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF3A1078),
        );
        continue;
      }
      final op = RingArcs.back(RingArcs.clamp01(awakeT / .2));
      canvas.drawOval(
        Rect.fromCenter(center: e, width: 13, height: 13 * op),
        _p..color = const Color(0xFFFFFFFF),
      );
      final a = math.atan2(bird.dy - e.dy, bird.dx - e.dx);
      canvas.drawCircle(
        e + Offset(math.cos(a) * 2.6, math.sin(a) * 2.6 * op),
        3,
        _p..color = const Color(0xFF2A0A40),
      );
      if (angry) {
        canvas.drawLine(
          e + Offset(-7, i == 1 ? -6 : -10),
          e + Offset(6, i == 1 ? -10 : -6),
          Paint()
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF3A1078),
        );
      }
    }
    final bang = s.get('bang');
    if (bang > 0) {
      final u = 1 - bang;
      LockdownArt.outlinedText(
        canvas,
        '!',
        Offset(20, -s.ry - 22 - u * 8),
        26 * RingArcs.back(RingArcs.clamp01(u / .25)),
        SwitchConfig.gold,
        SwitchConfig.plum,
        4,
      );
    }
    s.paintBits(canvas);
  }

  @override
  void paintSwitch(Canvas canvas, SwitchPickup p) {
    final ph = p.t % 1.3;
    final ringing = ph < .36;
    final sh = ringing ? math.sin(p.t * 70) * .22 : 0.0;
    RingArcs.halo(canvas, Offset.zero, 30, SwitchConfig.red, .25);
    canvas.save();
    canvas.rotate(sh);
    canvas.scale(1.1);
    final leg = Paint()
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = SwitchConfig.plum;
    canvas.drawLine(const Offset(-7, 10), const Offset(-10, 16), leg);
    canvas.drawLine(const Offset(7, 10), const Offset(10, 16), leg);
    for (final sg in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(sg * 9, -11);
      canvas.rotate(sg * .6);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: 7.4),
        math.pi,
        math.pi,
        true,
        _p..color = const Color(0xFFFFFFFF),
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: 6),
        math.pi,
        math.pi,
        true,
        _p..color = SwitchConfig.gold,
      );
      canvas.restore();
    }
    canvas.drawCircle(
      const Offset(0, 1),
      15,
      _p..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(const Offset(0, 1), 13, _p..color = SwitchConfig.red);
    canvas.drawCircle(
      const Offset(0, 1),
      9.5,
      _p..color = const Color(0xFFFFFFFF),
    );
    final hand = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = SwitchConfig.plum;
    canvas.drawLine(const Offset(0, 1), const Offset(0, -5), hand);
    canvas.drawLine(const Offset(0, 1), const Offset(4.5, 3), hand);
    canvas.restore();
    if (ringing) {
      final lines = Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = SwitchConfig.red;
      for (final sg in const [-1.0, 1.0]) {
        canvas.drawLine(Offset(sg * 20, -12), Offset(sg * 26, -16), lines);
        canvas.drawLine(Offset(sg * 21, -2), Offset(sg * 28, -2), lines);
      }
    }
  }

  @override
  void onTouch(SwitchRingState s) {
    s.fx['bang'] = 1;
  }

  @override
  void tick(SwitchRingState s, double dt) {
    final bang = s.get('bang');
    if (bang > 0) s.fx['bang'] = math.max(0, bang - dt);
    final puff = s.get('puff');
    if (puff > 0) s.fx['puff'] = math.max(0, puff - dt / .9);
    if (s.hitT < 0 && s.crashT < 0) {
      // "z" letters drifting up from the sleeping creature.
      final r = s.c.cosmetic;
      if (r.nextDouble() < dt * SwitchConfig.zzzRate) {
        s.bits.add(
          SwitchBit(
            x: 4,
            y: -s.ry - 12,
            vx: 22,
            vy: -30,
            life: 1.6,
            draw: (c, b) => LockdownArt.outlinedText(
              c,
              'z',
              Offset.zero,
              13 + b.t * 4,
              purple.withValues(alpha: b.alpha),
              Color.fromRGBO(255, 255, 255, b.alpha),
              3,
            ),
          ),
        );
      }
    }
  }

  @override
  void onCrash(SwitchRingState s) {
    s.fx['puff'] = 1;
    final b = s.birdLocal ?? const Offset(-20, 0);
    final r = s.c.cosmetic;
    for (var i = 0; i < 5; i++) {
      s.frontPool.spawn(
        shape: ParticleShape.circle,
        x: -RingArcs.rx,
        y: b.dy + (r.nextDouble() - .5) * 20,
        vx: -120 - r.nextDouble() * 60,
        vy: (r.nextDouble() - .5) * 60,
        w: 10,
        color: const Color(0x80A970FF),
        life: .6,
        scale1: 4,
      );
    }
  }
}
