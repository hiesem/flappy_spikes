import 'dart:math' as math;
import 'dart:ui';

import '../../../config/switch_config.dart';
import '../../../director/plans.dart' show SwitchDesign;
import '../../../effects/particle_pool.dart';
import '../ring_arcs.dart';
import 'switch_kind.dart';

/// Laser Gate (PRD-2 §5.19; mock `TH.laser`): the normal pink ring with two
/// black emitters (24 × 11, a red lens r 3.6 with a glow; green when off)
/// and, closed, a 12 % red tint over the opening plus three vertical beams
/// (x −6 / 0 / +6; glow 8 pt, core 2.6 pt, white 0.9 pt centre) flickering
/// at 30 Hz with red / white sparks dropping from the emitters (≈ 7/s).
/// The switch: a red arcade button with a power symbol, pulsing ±5 %.
///
/// Timeline: 0 s the button presses (dome 12 → 5 pt) and turns green;
/// 0.12 s power-down: the beams retract into both emitters over 0.4 s, the
/// lenses turn green, sparks burst at the emitters, "POWER OFF".
/// Crash: the beams flare wider, the bird flashes black / normal at 14 Hz
/// for 1.2 s, red / white / gold sparks, grey smoke puffs.
class LaserGateArt extends SwitchDesignArt {
  const LaserGateArt();

  @override
  SwitchDesign get design => SwitchDesign.laserGate;

  static final Paint _p = Paint();
  static final Paint _l = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// 0..1 power-down progress (eased).
  static double off(SwitchRingState s) =>
      RingArcs.io(RingArcs.clamp01((s.hitT - .12) / .4));

  @override
  void paintBack(Canvas canvas, SwitchRingState s) {
    SwitchDesignArt.pinkHalf(canvas, s, front: false);
    final u = s.hitT < 0 ? 0.0 : off(s);
    if (u >= 1) return;
    final ry = s.ry;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: 2 * (RingArcs.rx - 3),
        height: 2 * (ry - 3),
      ),
      _p..color = Color.fromRGBO(255, 59, 92, .12 * (1 - u)),
    );
    final zap = s.get('zap');
    final l = ry * (1 - u);
    for (final dx in const [-6.0, 0.0, 6.0]) {
      final fl = .75 + .25 * RingArcs.rnd((s.t * 30).floor() + dx * 7);
      for (final (y0, y1) in [(-ry, -ry + l), (ry - l, ry)]) {
        for (final (col, w) in [
          (Color.fromRGBO(255, 59, 92, .28 * fl), 8 + zap * 6),
          (SwitchConfig.red.withValues(alpha: fl), 2.6),
          (Color.fromRGBO(255, 255, 255, fl), .9),
        ]) {
          canvas.drawLine(
            Offset(dx, y0),
            Offset(dx, y1),
            _l
              ..strokeWidth = w
              ..color = col,
          );
        }
      }
    }
  }

  void _emitter(Canvas c, double ry, bool top, bool on) {
    final y = top ? -ry - 1 : ry + 1;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-12, top ? y - 11 : y, 24, 11),
        const Radius.circular(3),
      ),
      _p..color = const Color(0xFF2E3440),
    );
    c.drawRect(
      Rect.fromLTWH(-12, top ? y - 4 : y, 24, 4),
      _p..color = const Color(0xFF4A525E),
    );
    final ly = top ? y + 1 : y - 1;
    final col = on ? SwitchConfig.green : SwitchConfig.red;
    RingArcs.halo(c, Offset(0, ly), 13, col, .7);
    c.drawCircle(Offset(0, ly), 3.6, _p..color = col);
  }

  @override
  void paintFront(Canvas canvas, SwitchRingState s) {
    SwitchDesignArt.pinkHalf(canvas, s, front: true);
    final on = s.hitT >= 0 && off(s) >= .5;
    _emitter(canvas, s.ry, true, on);
    _emitter(canvas, s.ry, false, on);
  }

  @override
  void paintSwitch(Canvas canvas, SwitchPickup p) {
    final pr = p.on, on = pr > 0;
    RingArcs.halo(
      canvas,
      Offset.zero,
      32,
      on ? SwitchConfig.green : SwitchConfig.red,
      .3,
    );
    canvas.save();
    canvas.scale(1.1 + .05 * math.sin(p.t * 2 * math.pi));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 11), width: 42, height: 18),
      _p..color = const Color(0xFFFFFFFF),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 10), width: 37, height: 14),
      _p..color = const Color(0xFF616161),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 7), width: 37, height: 14),
      _p..color = const Color(0xFF9E9E9E),
    );
    final dh = 12 - pr * 7;
    final col = on ? SwitchConfig.green : SwitchConfig.red;
    final dk = on ? const Color(0xFF137A42) : const Color(0xFFB3122E);
    final side = Path()
      ..addArc(
        Rect.fromCenter(center: const Offset(0, 6), width: 27, height: 11),
        0,
        math.pi,
      )
      ..lineTo(-13.5, 6 - dh)
      ..arcTo(
        Rect.fromCenter(center: Offset(0, 6 - dh), width: 27, height: 11),
        math.pi,
        -math.pi,
        false,
      )
      ..close();
    canvas.drawPath(side, _p..color = dk);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(0, 6 - dh), width: 27, height: 11),
      _p..color = col,
    );
    final sym = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFFF);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(0, 6 - dh), width: 10, height: 4.4),
      -math.pi / 2 + .8,
      2 * math.pi - 1.6,
      false,
      sym,
    );
    canvas.drawLine(Offset(0, 6 - dh - 3.6), Offset(0, 6 - dh - .8), sym);
    canvas.restore();
  }

  @override
  void tick(SwitchRingState s, double dt) {
    final zap = s.get('zap');
    if (zap > 0) s.fx['zap'] = math.max(0, zap - dt * 3);
    final ry = s.ry;
    final r = s.c.cosmetic;
    if (s.hitT >= .12) {
      if (s.once('powerOff')) {
        s.burst(
          s.frontPool,
          Offset(0, -ry),
          8,
          const [SwitchConfig.red, Color(0xFFFFFFFF)],
          speed: 120,
          sMin: 2,
          sMax: 4,
        );
        s.burst(
          s.frontPool,
          Offset(0, ry),
          8,
          const [SwitchConfig.red, Color(0xFFFFFFFF)],
          speed: 120,
          sMin: 2,
          sMax: 4,
        );
      }
    } else if (r.nextDouble() < dt * 7) {
      final top = r.nextBool();
      s.backPool.spawn(
        x: (r.nextDouble() - .5) * 12,
        y: top ? -ry + 2 : ry - 2,
        vx: (r.nextDouble() - .5) * 90,
        vy: (top ? 1 : -1) * (40 + r.nextDouble() * 60),
        w: 2.4,
        color: r.nextBool() ? SwitchConfig.red : const Color(0xFFFFFFFF),
        life: .35,
      );
    }
    // §5.19 crash: the bird flashes black (X-ray stripes) / normal at 14 Hz
    // for 1.2 s.
    final b = s.c.game.runBird;
    if (s.crashT >= 0 && b != null) {
      if (s.crashT < 1.2) {
        final black = (s.crashT * 14 * 2).floor().isEven;
        b.deathTint = black ? const Color(0xFF000000) : null;
        b.deathTintAmount = black ? 1 : 0;
      } else if (s.once('zapEnd')) {
        b.deathTint = null;
        b.deathTintAmount = 0;
      }
    }
  }

  @override
  void onCrash(SwitchRingState s) {
    s.fx['zap'] = 1;
    final b = s.birdLocal ?? const Offset(-20, 0);
    s.burst(
      s.frontPool,
      Offset(b.dx + 8, b.dy),
      12,
      const [SwitchConfig.red, Color(0xFFFFFFFF), Color(0xFFFFD54A)],
      speed: 200,
      sMin: 2,
      sMax: 5,
    );
    final r = s.c.cosmetic;
    for (var i = 0; i < 8; i++) {
      s.frontPool.spawn(
        shape: ParticleShape.circle,
        x: b.dx + (r.nextDouble() - .5) * 20,
        y: b.dy,
        vx: -30 + (r.nextDouble() - .5) * 40,
        vy: -50 - r.nextDouble() * 40,
        w: 10,
        color: const Color(0x735A5A5A),
        life: 1.1,
        scale1: 4,
      );
    }
  }
}
