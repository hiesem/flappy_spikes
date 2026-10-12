import 'dart:math' as math;
import 'dart:ui';

import '../../../../game/sound.dart';
import '../../../config/saw_config.dart';
import '../../../effects/particle_pool.dart';
import '../../../director/plans.dart' show SawDesign;
import '../ring_arcs.dart';
import 'saw_kind.dart';

/// Live Wire (PRD-2 §5.17; mock `TH.electric` + the round-4 "cocoon"):
/// a navy core with a glowing cyan rim and a white flickering filament,
/// a soft cyan glow shell, 3–4 thin forked arcs crawling round the ring
/// (redrawn 18×/s), the odd short spark, ≈ 9 % of redraws a big forked
/// strike (70–120 pt) with a thunder crack, and a bolt reaching for the
/// bird within 46 pt of the rim. PRD-2.2 §25: the glow shell, arcs,
/// strikes and sparks scale with the ring ([SawRingState.decor]); the rim
/// and the near-miss bolt (it reaches for the bird) do not.
class LiveWireArt implements SawDesignArt {
  const LiveWireArt();

  @override
  SawDesign get design => SawDesign.liveWire;

  static int _bucket(SawRingState s) => (s.t * SawConfig.wireRedraw).floor();

  static bool _strike(SawRingState s, int b) =>
      RingArcs.rnd(b * 13.7 + s.seed) < SawConfig.wireStrike;

  /// The crawling arcs of the current redraw: (front, back, strike).
  static (List<BoltSeg>, List<BoltSeg>, bool) cocoon(SawRingState s) {
    final b = _bucket(s);
    final cached = s.fx['cocoon'];
    if (cached is (int, List<BoltSeg>, List<BoltSeg>, bool) && cached.$1 == b) {
      return (cached.$2, cached.$3, cached.$4);
    }
    final ry = s.ry, d = s.decor; // PRD-2.2 §25 decoration scale
    final r = Mulberry(b * 977 + s.seed * 31);
    final f = <BoltSeg>[], bk = <BoltSeg>[];
    final st = _strike(s, b);
    final tt = b / SawConfig.wireRedraw;
    final n = 3 + (RingArcs.rnd(b + s.seed) < .5 ? 1 : 0);
    for (var i = 0; i < n; i++) {
      final a0 =
          i * RingArcs.tau / 4 +
          tt * (i.isOdd ? 1.3 : -1.0) +
          RingArcs.rnd(s.seed + i) * 2;
      final sp = .5 + r() * .35, am = a0 + sp / 2;
      final p0 = RingArcs.ellPt(ry, a0, (2 + r() * 5) * d);
      final pm = RingArcs.ellPt(ry, am, (8 + r() * 7) * d);
      final p1 = RingArcs.ellPt(ry, a0 + sp, (2 + r() * 5) * d);
      final l = RingArcs.isFront(am) ? f : bk;
      Lightning.seg(p0.dx, p0.dy, pm.dx, pm.dy, 8 * d, r, l, 1);
      Lightning.seg(pm.dx, pm.dy, p1.dx, p1.dy, 8 * d, r, l, 1);
    }
    if (r() < .35) {
      final a = r() * RingArcs.tau;
      final p = RingArcs.ellPt(ry, a, 2 * d);
      final e = RingArcs.ellPt(ry, a + (r() - .5) * .4, (8 + r() * 10) * d);
      Lightning.seg(
        p.dx,
        p.dy,
        e.dx,
        e.dy,
        6 * d,
        r,
        RingArcs.isFront(a) ? f : bk,
        2,
      );
    }
    if (st) {
      final a = r() * RingArcs.tau;
      final p = RingArcs.ellPt(ry, a, 4 * d);
      final e = RingArcs.ellPt(ry, a + (r() - .5) * .6, (70 + r() * 50) * d);
      Lightning.seg(
        p.dx,
        p.dy,
        e.dx,
        e.dy,
        36 * d,
        r,
        RingArcs.isFront(a) ? f : bk,
        0,
      );
    }
    s.fx['cocoon'] = (b, f, bk, st);
    return (f, bk, st);
  }

  void _aura(Canvas canvas, SawRingState s, bool front) {
    final (f, bk, st) = cocoon(s);
    final fl = .7 + .3 * RingArcs.rnd((s.t * 30).floor() + s.seed);
    final d = s.decor; // PRD-2.2 §25
    RingArcs.glowShell(canvas, s.ry, front, [
      (34 * d, .06 * fl * (st ? 2.5 : 1)),
      (18 * d, .12 * fl * (st ? 1.8 : 1)),
    ], const Color(0xFF3CD2FF));
    Lightning.paint(canvas, front ? f : bk, k: (st ? 1 : .7) * d);
  }

  void _ring(Canvas canvas, SawRingState s, bool front) {
    final ry = s.ry;
    final path = RingArcs.half(ry, front: front);
    RingArcs.stroke(
      canvas,
      path,
      front ? SawConfig.wireCore : SawConfig.wireCoreBack,
      11,
    );
    RingArcs.stroke(
      canvas,
      path,
      front ? SawConfig.wireCyan : SawConfig.wireCyanBack,
      4,
      blur: 16,
      glow: SawConfig.wireGlow,
    );
    // The white filament crawling round the rim.
    final a0 = front ? math.pi / 2 : -math.pi / 2;
    final sd = (s.t * 24).floor() + s.seed;
    final fil = Path();
    for (var i = 0; i <= 26; i++) {
      final a = a0 + math.pi * i / 26;
      final j = (RingArcs.rnd(sd * 31 + i) - .5) * 10;
      final x = (RingArcs.rx + j * .5) * math.cos(a);
      final y = (ry + j) * math.sin(a);
      i == 0 ? fil.moveTo(x, y) : fil.lineTo(x, y);
    }
    RingArcs.stroke(canvas, fil, const Color(0xFFFFFFFF), 1.6);
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
    _near(canvas, s);
  }

  /// §5.17 near miss: within 46 pt of the rim a forked bolt reaches toward
  /// the bird.
  void _near(Canvas canvas, SawRingState s) {
    final b = s.birdLocal;
    if (b == null || s.hoop.resolved) return;
    final reach = SawConfig.wireNear + s.birdR;
    Offset? best;
    var bd = double.infinity;
    for (final side in const [-1.0, 1.0]) {
      final e = Offset(0, side * s.ry);
      final d = (e - Offset(b.x, b.y)).distance;
      if (d < bd) {
        bd = d;
        best = e;
      }
    }
    if (best == null || bd >= reach) return;
    final k = .4 + .45 * (1 - bd / reach);
    final r = Mulberry((s.t * 25).floor() * 7 + s.seed);
    final segs = <BoltSeg>[];
    Lightning.seg(
      best.dx,
      best.dy,
      best.dx + (b.x - best.dx) * k,
      best.dy + (b.y - best.dy) * k,
      14,
      r,
      segs,
      0,
    );
    Lightning.paint(canvas, segs, k: .7);
  }

  @override
  void ambient(SawRingState s, double dt) {
    final b = _bucket(s);
    if (s.fx['lb'] != b) {
      s.fx['lb'] = b;
      if (_strike(s, b)) s.c.sfx(Sfx.sawWireThunder);
    }
    final r = s.c.cosmetic;
    if (r.nextDouble() < dt * 5) {
      final a = r.nextDouble() * RingArcs.tau;
      final d = s.decor; // PRD-2.2 §25
      final p = RingArcs.ellPt(s.ry, a, (4 + r.nextDouble() * 8) * d);
      s.frontPool.spawn(
        shape: ParticleShape.circle,
        x: p.dx,
        y: p.dy,
        vx: math.cos(a) * 60 * d,
        vy: math.sin(a) * 60 * d,
        w: 1.8 * 2 * d,
        color: r.nextBool() ? const Color(0xFFFFFFFF) : SawConfig.wireCyan,
        life: .25,
        gravity: 300,
      );
    }
    // The odd crackle while near.
    final bl = s.birdLocal;
    if (bl != null && !s.hoop.resolved) {
      final d = math.min(
        (Offset(bl.x, bl.y) - Offset(0, -s.ry)).distance,
        (Offset(bl.x, bl.y) - Offset(0, s.ry)).distance,
      );
      if (d < SawConfig.wireNear + s.birdR && r.nextDouble() < dt * 4) {
        s.c.sfx(Sfx.sawWireCrackle);
      }
    }
  }
}
