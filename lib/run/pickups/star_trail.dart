import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/run_config.dart';
import '../config/star_trail_config.dart';
import '../director/plans.dart';
import '../effects/collect_art.dart';
import '../effects/dashed_path.dart';
import '../effects/particle_pool.dart';
import '../elements.dart';
import '../run_context.dart';
import '../run_events.dart';
import 'pickup.dart';

/// The Star Trail (PRD-2 §3.26): the director's star-trail `GapItemPlan`
/// (§3.0.3: gap 5, weight 30, ≥ 8 gaps apart, in an empty gap; stars from
/// 40 pt after one hoop to 40 pt before the next, on a 40 pt arc) becomes a
/// [StarTrail]. What the trail *does* when it is over (the PERFECT LINE
/// banner and +5 coins, the "n / 8" pop) is `StarTrailFeature`
/// (items/star_trail_feature.dart).
class StarTrailKind extends PickupKind {
  @override
  ElementId get element => ElementId.starTrail;

  @override
  Pickup build(GapItemPlan p, RunContext c) => StarTrail(p);
}

/// §5.25 the 8-star arc: gold 4-point stars (8 pt, twinkling ±1.6 pt at
/// 6 rad/s) with a soft gold halo (r 16, α 0.45) and a pale core at 0.5×,
/// on a dotted gold line (2 pt, 2 / 6, α 0.45). Each star collected shows
/// the sparkle (§5.25) and plays the next note of C major (§5.25).
///
/// One [Pickup] holds all 8 stars: `touches` / `isPast` / `onCollect` are
/// overridden so the shared spawner hit test (§3.0.3) collects one star at a
/// time (`collected` is reset so the trail stays collectable until its last
/// star is behind the bird). `position` / `hitRadius` are set so the
/// spawner's announce and cull windows span the whole arc.
class StarTrail extends Pickup {
  StarTrail(GapItemPlan plan)
    : caught = List<bool>.filled(StarTrailConfig.stars, false),
      super(
        id: ElementId.starTrail,
        hitRadius: _halfWidth(plan),
        plan: plan,
        position: Vector2(_midX(plan), plan.y ?? 0),
        size: Vector2.all(PickupRadii.star * 2),
        // Local origin == `position`, so the arc draws at its absolute
        // track coordinates minus `position` (render below).
        anchor: Anchor.topLeft,
      );

  @override
  GapItemPlan get plan => super.plan!;

  /// Per-star collected flags (index 0..7 along the arc).
  final List<bool> caught;

  int _hit = -1;
  double _t = 0;

  static double _span(GapItemPlan p) => (p.toTrackX ?? p.trackX) - p.trackX;
  static double _halfWidth(GapItemPlan p) =>
      _span(p) / 2 + PickupRadii.star;
  static double _midX(GapItemPlan p) => (p.trackX + (p.toTrackX ?? p.trackX)) / 2;

  /// The track position of star [i] (mock: u = (i + 1) / 9, y − sin(u π)·bulge).
  Offset starAt(int i) {
    final u = StarTrailConfig.u(i);
    final x0 = plan.trackX, x1 = plan.toTrackX ?? plan.trackX;
    final y0 = plan.y ?? 0, y1 = plan.toY ?? y0;
    return Offset(
      x0 + (x1 - x0) * u,
      y0 + (y1 - y0) * u - math.sin(math.pi * u) * RunConfig.starTrailBulge,
    );
  }

  int get caughtCount {
    var n = 0;
    for (final c in caught) {
      if (c) n++;
    }
    return n;
  }

  /// The trail's identity for `RunState.trails.caught` (its start x).
  int get trailId => plan.trackX.round();

  @override
  bool touches(Vector2 birdTrack, double birdR) {
    for (var i = 0; i < caught.length; i++) {
      if (caught[i]) continue;
      final s = starAt(i);
      if (birdTrack.distanceTo(Vector2(s.dx, s.dy)) - birdR <=
          PickupRadii.star) {
        _hit = i;
        return true;
      }
    }
    return false;
  }

  @override
  bool isPast(double birdTrackX, double birdR) {
    final last = starAt(caught.length - 1);
    return last.dx + PickupRadii.star < birdTrackX - birdR;
  }

  @override
  void onCollect(RunContext c) {
    if (_hit < 0 || _hit >= caught.length) return;
    caught[_hit] = true;
    final at = starAt(_hit);
    // §5.25 a 12 pt #FFF59D twinkle rising at 30 pt/s for 0.4 s.
    c.run.particles.spawn(
      shape: ParticleShape.twinkle,
      x: at.dx,
      y: at.dy,
      vy: -StarTrailConfig.sparkleRise,
      w: StarTrailConfig.sparkleSize,
      color: StarTrailConfig.sparkleColor,
      life: StarTrailConfig.sparkleLife,
    );
    // §5.25 the next note of C major (C5 → C6 as stars are caught).
    final n = caughtCount.clamp(1, StarTrailConfig.notes.length);
    c.sfx(StarTrailConfig.notes[n - 1]);
    // One star per frame; the trail stays collectable for the rest.
    collected = false;
  }

  /// §3.26 the trail is over (its last star went behind the bird): the
  /// feature decides between PERFECT LINE and the "n / 8" pop.
  @override
  void onPassedUncaught(RunContext c) => c.emit(StarTrailFinished(this));

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    final remaining = <Offset>[
      for (var i = 0; i < caught.length; i++)
        if (!caught[i]) starAt(i),
    ];
    if (remaining.isEmpty) return;
    canvas.save();
    canvas.translate(-position.x, -position.y);
    // The dotted line follows the stars still on the course (mock drawBg).
    if (remaining.length > 1) {
      final path = Path()..moveTo(remaining.first.dx, remaining.first.dy);
      for (final s in remaining.skip(1)) {
        path.lineTo(s.dx, s.dy);
      }
      DashedPathPainter.stroke(
        canvas,
        path,
        color: StarTrailConfig.gold.withValues(alpha: StarTrailConfig.lineAlpha),
        width: StarTrailConfig.lineWidth,
        dashes: StarTrailConfig.lineDashes,
      );
    }
    for (var i = 0; i < caught.length; i++) {
      if (caught[i]) continue;
      final s = starAt(i);
      final size =
          StarTrailConfig.starBase +
          StarTrailConfig.starPulse *
              math.sin(_t * StarTrailConfig.starPulseOmega + i);
      CollectArt.halo(
        canvas,
        s,
        StarTrailConfig.haloR,
        StarTrailConfig.halo,
        StarTrailConfig.haloAlpha,
      );
      CollectArt.star4(canvas, s, size, StarTrailConfig.gold);
      CollectArt.star4(
        canvas,
        s,
        size * StarTrailConfig.coreScale,
        StarTrailConfig.core,
      );
    }
    canvas.restore();
  }
}
