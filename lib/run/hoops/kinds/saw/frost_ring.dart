import 'dart:math' as math;
import 'dart:ui';

import '../../../../game/sound.dart';
import '../../../config/saw_config.dart';
import '../../../director/plans.dart' show SawDesign;
import '../../../effects/particle_pool.dart';
import '../ring_arcs.dart';
import 'saw_kind.dart';

/// One ice shard of the Frost Ring (§5.17).
class _Shard {
  const _Shard(this.a, this.da, this.l, this.w, this.g);
  final double a, da, l, w, g;
}

/// Frost Ring (PRD-2 §5.17; mock `TH.ice` + the round-4 shards): the rim
/// `#2F7FB0` 12 pt with `#9BE3FF` 8 pt and a white frost zig-zag, ice
/// shards all round the ring (2–3 per point at 46 points, pointing out,
/// longest at the top and bottom curves — up to ≈ 35 pt — and about half
/// at the sides so the flight path stays clean; each tip glints in turn),
/// a cold fog shell, fog puffs and drifting snow, the odd ice "tink".
/// PRD-2.2 §25: the fog shell, shards, glints and particles scale with the
/// ring ([SawRingState.decor]); the rim and its zig-zag do not.
class FrostRingArt implements SawDesignArt {
  const FrostRingArt();

  @override
  SawDesign get design => SawDesign.frostRing;

  static List<_Shard> _shards(SawRingState s) {
    final cached = s.fx['shards'];
    if (cached is List<_Shard>) return cached;
    final r = Mulberry(s.seed * 7919 + 3);
    final out = <_Shard>[];
    for (var i = 0; i < SawConfig.frostPoints; i++) {
      final a = i / SawConfig.frostPoints * RingArcs.tau + (r() - .5) * .1;
      final side = math.sin(a).abs();
      final k = .5 + .5 * math.pow(side, .6);
      final n = 2 + (r() < .45 ? 1 : 0);
      for (var j = 0; j < n; j++) {
        out.add(
          _Shard(
            a,
            (r() - .5) * .8,
            (9 + r() * 26) * k * (j > 0 ? .7 : 1),
            2.4 + r() * 3.6,
            r() * 3,
          ),
        );
      }
    }
    s.fx['shards'] = out;
    return out;
  }

  void _aura(Canvas canvas, SawRingState s, bool front) {
    final d = s.decor; // PRD-2.2 §25 decoration scale
    RingArcs.glowShell(canvas, s.ry, front, [
      (64 * d, .09),
      (40 * d, .14),
      (22 * d, .22),
    ], const Color(0xFFC8EEFF));
    final ry = s.ry;
    for (final sh in _shards(s)) {
      if (RingArcs.isFront(sh.a) != front) continue;
      final p = RingArcs.ellPt(ry, sh.a, 1);
      final ang = RingArcs.normal(ry, sh.a) + sh.da;
      final l = sh.l * d * (1 + .05 * math.sin(s.t * 3 + sh.g * 5));
      final tip = p + Offset(math.cos(ang) * l, math.sin(ang) * l);
      final w = sh.w * d;
      final n = Offset(-math.sin(ang) * w, math.cos(ang) * w);
      RingArcs.poly(canvas, [
        p + n,
        tip,
        p - n,
      ], front ? const Color(0xEBCDF4FF) : const Color(0xCC8CC8EB));
      RingArcs.poly(canvas, [
        p + n * .15,
        tip,
        p - n,
      ], front ? const Color(0x8C6EBEEB) : const Color(0x80468CBE));
      if (!front) continue;
      final edge = Path()
        ..moveTo(p.dx + n.dx * .4, p.dy + n.dy * .4)
        ..lineTo(tip.dx, tip.dy);
      RingArcs.stroke(canvas, edge, const Color(0xF2FFFFFF), .9 * d);
      final g = (s.t * 1.1 + sh.g) % 3;
      if (g < .2) {
        final z = 1 - (g - .1).abs() / .1;
        final gp = tip - (tip - p) * .12;
        RingArcs.star4(canvas, gp, 6 * z * d, const Color(0xFFFFFFFF));
      }
    }
  }

  void _ring(Canvas canvas, SawRingState s, bool front) {
    final ry = s.ry;
    final path = RingArcs.half(ry, front: front);
    RingArcs.stroke(
      canvas,
      path,
      front ? SawConfig.frostRim : SawConfig.frostRimBack,
      12,
    );
    RingArcs.stroke(
      canvas,
      path,
      front ? SawConfig.frostInner : SawConfig.frostInnerBack,
      8,
    );
    if (!front) return;
    final zig = Path();
    for (var i = 0; i <= 30; i++) {
      final a = math.pi / 2 + math.pi * i / 30;
      final j = i.isOdd ? -2.5 : 2.5;
      final x = (RingArcs.rx + j * .4) * math.cos(a);
      final y = (ry + j) * math.sin(a);
      i == 0 ? zig.moveTo(x, y) : zig.lineTo(x, y);
    }
    RingArcs.stroke(canvas, zig, const Color(0xF2FFFFFF), 1.6);
  }

  @override
  void paintBack(Canvas canvas, SawRingState s) {
    _aura(canvas, s, false);
    _ring(canvas, s, false);
  }

  @override
  void paintFront(Canvas canvas, SawRingState s) {
    _ring(canvas, s, true);
    _aura(canvas, s, true);
  }

  @override
  void ambient(SawRingState s, double dt) {
    final r = s.c.cosmetic;
    final d = s.decor; // PRD-2.2 §25
    if (r.nextDouble() < dt * 14) {
      final a = r.nextDouble() * RingArcs.tau;
      final p = RingArcs.ellPt(s.ry, a, (10 + r.nextDouble() * 14) * d);
      (RingArcs.isFront(a) ? s.frontPool : s.backPool).spawn(
        shape: ParticleShape.circle,
        x: p.dx,
        y: p.dy,
        vx: math.cos(a) * 14 * d,
        vy: (math.sin(a) * 14 + 6) * d,
        w: 2 * (4 + r.nextDouble() * 5) * d,
        color: const Color(0x80EBFAFF),
        life: 1.8,
        scale1: 4,
      );
    }
    if (r.nextDouble() < dt * 10) {
      final a = r.nextDouble() * RingArcs.tau;
      final p = RingArcs.ellPt(s.ry, a, (20 + r.nextDouble() * 30) * d);
      s.frontPool.spawn(
        shape: ParticleShape.circle,
        x: p.dx,
        y: p.dy,
        vx: (r.nextDouble() - .5) * 16 * d,
        vy: (20 + r.nextDouble() * 20) * d,
        w: 2 * (1.4 + r.nextDouble() * 1.4) * d,
        color: const Color(0xFFFFFFFF),
        life: 1.6,
      );
    }
    if (r.nextDouble() < dt * 1.4) s.c.sfx(Sfx.sawFrostTink);
    if (s.fx['hiss'] == null) {
      s.fx['hiss'] = true;
      s.c.sfx(Sfx.sawFrostHiss);
    }
  }
}
