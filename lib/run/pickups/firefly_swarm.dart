import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/jar_config.dart';
import '../config/run_config.dart';
import '../director/plans.dart';
import '../effects/collect_art.dart';
import '../effects/particle_pool.dart' show ParticleShape;
import '../elements.dart';
import '../run_context.dart';
import '../run_events.dart';
import 'pickup.dart';

/// The Firefly Jar's swarms (PRD-2 §3.29): each `fireflySwarm` gap item the
/// director places while the jar runs becomes a [FireflySwarm] of 7 weaving
/// fireflies. What they *do* (count into the jar, escape, break it) is
/// `JarFeature` (items/jar.dart).
class FireflySwarmKind extends PickupKind {
  @override
  ElementId get element => ElementId.fireflySwarm;

  @override
  Pickup build(GapItemPlan p, RunContext c) => FireflySwarm(p, c);
}

/// §5.28 / §3.29 a swarm of `extra` fireflies weaving around their centre
/// (`t = 1.3 · clock + ph; x = cx + cos t · 24 + sin(1.7t) · 8;
/// y = cy + sin(1.2t) · 22`). Flying within 16 pt of one (Q68) catches it;
/// one that passes the bird uncaught escapes (each emits `PickupEscaped`).
/// When the jar is gone (`RunState.jar == null`: full, broke, death or a
/// portal ride cleared them) the remaining fireflies fly up and away,
/// unjudged.
class FireflySwarm extends Pickup {
  FireflySwarm(GapItemPlan p, this.c)
    : count = p.extra is int ? p.extra! as int : RunConfig.fireflySwarm,
      caught = List<bool>.filled(
        p.extra is int ? p.extra! as int : RunConfig.fireflySwarm,
        false,
      ),
      escapedFly = List<bool>.filled(
        p.extra is int ? p.extra! as int : RunConfig.fireflySwarm,
        false,
      ),
      super(
        id: ElementId.fireflySwarm,
        hitRadius: _halfSpan(p),
        plan: p,
        position: Vector2(_centreX(p), p.y ?? 0),
        size: Vector2.all(PickupRadii.firefly * 2),
        anchor: Anchor.topLeft,
      ) {
    final r = math.Random(p.trackX.round());
    for (var i = 0; i < count; i++) {
      phases.add(r.nextDouble() * 20);
    }
  }

  final RunContext c;

  /// Fireflies in this swarm (§3.29: 7).
  final int count;
  final List<bool> caught;
  final List<bool> escapedFly;

  /// Per-firefly weave phase (mock `Math.random()*20`; seeded per swarm).
  final List<double> phases = [];

  int _hit = -1;
  double _t = 0;

  static double _span(GapItemPlan p) => (p.toTrackX ?? p.trackX) - p.trackX;
  static double _halfSpan(GapItemPlan p) => _span(p).abs() / 2 +
      JarConfig.weaveAx +
      JarConfig.weaveBx +
      PickupRadii.firefly;
  static double _centreX(GapItemPlan p) =>
      (p.trackX + (p.toTrackX ?? p.trackX)) / 2;

  /// The track position of firefly [i] at the swarm's clock.
  Offset flyAt(int i) {
    final t = JarConfig.weaveRate * _t + phases[i];
    return Offset(
      position.x +
          math.cos(t) * JarConfig.weaveAx +
          math.sin(t * JarConfig.weaveBk) * JarConfig.weaveBx,
      position.y + math.sin(t * JarConfig.weaveKy) * JarConfig.weaveAy,
    );
  }

  int get caughtCount {
    var n = 0;
    for (final b in caught) {
      if (b) n++;
    }
    return n;
  }

  int get escapedCount {
    var n = 0;
    for (final b in escapedFly) {
      if (b) n++;
    }
    return n;
  }

  /// The track position of the firefly caught last (for the HUD flight).
  Offset? get lastCollectedAt =>
      _hit >= 0 && _hit < count ? flyAt(_hit) : null;

  bool get done => caughtCount + escapedCount >= count;

  @override
  bool touches(Vector2 birdTrack, double birdR) {
    if (escaped || done) return false;
    for (var i = 0; i < count; i++) {
      if (caught[i] || escapedFly[i]) continue;
      final p = flyAt(i);
      if (birdTrack.distanceTo(Vector2(p.dx, p.dy)) - birdR <=
          PickupRadii.firefly) {
        _hit = i;
        return true;
      }
    }
    return false;
  }

  @override
  bool isPast(double birdTrackX, double birdR) => done;

  @override
  void onCollect(RunContext c) {
    if (_hit < 0 || _hit >= count) return;
    caught[_hit] = true;
    // One firefly per frame; the swarm stays collectable for the rest.
    collected = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (escaped) return;
    if (c.s.jar == null) {
      _flyAway();
      return;
    }
    final bird = c.run.birdTrackPosition();
    if (bird == null) return;
    final r = RunConfig.birdRadius * c.s.birdScale;
    for (var i = 0; i < count; i++) {
      if (caught[i] || escapedFly[i]) continue;
      final p = flyAt(i);
      if (p.dx + r + PickupRadii.firefly < bird.x) {
        escapedFly[i] = true;
        c.emit(const PickupEscaped(ElementId.fireflySwarm));
      }
    }
  }

  void _flyAway() {
    final r = c.cosmetic;
    for (var i = 0; i < count; i++) {
      if (caught[i] || escapedFly[i]) continue;
      escapedFly[i] = true;
      final p = flyAt(i);
      c.run.particles.spawn(
        shape: ParticleShape.circle,
        x: p.dx,
        y: p.dy,
        vx: JarConfig.awayVxMin + r.nextDouble() * (JarConfig.awayVxMax - JarConfig.awayVxMin),
        vy: -(JarConfig.awayVyMin + r.nextDouble() * (JarConfig.awayVyMax - JarConfig.awayVyMin)),
        w: JarConfig.awaySize,
        color: JarConfig.awayColor,
        life: 1,
      );
    }
    if (done) escaped = true;
  }

  @override
  void render(Canvas canvas) {
    for (var i = 0; i < count; i++) {
      if (caught[i] || escapedFly[i]) continue;
      final p = flyAt(i);
      final at = Offset(p.dx - position.x, p.dy - position.y);
      final bl = .55 + .45 * math.sin(_t * JarConfig.flyBlinkOmega + phases[i] * 3);
      CollectArt.halo(
        canvas,
        at,
        JarConfig.flyHaloR,
        JarConfig.flyHalo,
        JarConfig.flyHaloAlpha * bl,
      );
      final dot = Paint()..color = JarConfig.dot;
      canvas.drawCircle(at, JarConfig.dotR, dot);
      final body = Paint()..color = JarConfig.flyBody;
      canvas.drawRect(
        Rect.fromLTWH(at.dx - 1, at.dy - 5, 2, 3),
        body,
      );
    }
  }
}
