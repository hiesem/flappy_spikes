import 'package:flame/components.dart';

import 'config/run_config.dart';
import 'director/run_director.dart';
import 'elements.dart';
import 'hoops/hoop.dart';
import 'hoops/kinds/registry.dart';
import 'pickups/pickup.dart';
import 'pickups/registry.dart';
import 'run_controller.dart';
import 'run_events.dart';

/// Turns director plans into components (ARCH §1.1): keeps the next slot
/// planned once its plane is within 60 pt of the right edge (§3.0.1 first
/// hoop "60 pt past the right edge"), resolves line items between two
/// hoops, announces elements entering the screen, runs the pickup hit test
/// (§3.0.3) and removes parts that left the screen.
class RunSpawner {
  RunSpawner(this.run);

  final RunController run;
  final List<Hoop> _hoops = [];
  final List<Pickup> _pickups = [];
  final List<(Component, double)> _fading = [];
  final List<(GapItemPlan, SlotPlan)> _pending = [];

  /// Every plan, in order (tests, debug overlay).
  final List<SlotPlan> slotLog = [];
  final List<GapPlan> gapLog = [];

  Iterable<Hoop> get hoops => _hoops;
  Iterable<Pickup> get pickups => _pickups;

  /// Hoops are live once WP-1a registers the normal hoop (or a test does).
  /// Until then the 1.0 pipes run and the spawner stays idle.
  bool get live => hoopKindFor(HoopKindId.normal) != null;

  void update(double dt) {
    if (!live) return;
    final s = run.state;
    final edge =
        s.camX + RunConfig.worldWidth + RunConfig.firstHoopOffscreen + 1e-6;
    var guard = 0;
    while (run.director.nextTrackX <= edge && guard++ < 8) {
      _spawnSlot();
    }
    _announce();
    _hitTest();
    _cull(dt);
  }

  void _spawnSlot() {
    final ctx = run.directorContext();
    final plan = run.director.nextSlot(ctx);
    slotLog.add(plan);
    run.state.hoopIndex = run.director.hoopIndex;
    _resolvePending(plan);
    final kind = hoopKindFor(plan.kind) ?? hoopKindFor(HoopKindId.normal)!;
    final hoop = Hoop(plan: plan, kind: kind);
    kind.onSpawn(hoop, run.ctx);
    kind.buildVisual(hoop, run.ctx);
    run.layers.back.add(hoop);
    run.layers.front.add(hoop.front);
    _hoops.add(hoop);
    run.events.emit(HoopSpawned(hoop, plan));
    for (final a in plan.attached) {
      _spawnItem(a);
    }
    final gap = run.director.nextGap(run.directorContext(), plan);
    gapLog.add(gap);
    run.state.gapIndex = plan.index;
    for (final item in gap.items) {
      if (item.y == null) {
        _pending.add((item, plan));
      } else {
        _spawnItem(item);
      }
    }
  }

  /// Items "on the straight line between the hoops" (§3.0.3) wait for the
  /// next slot's centre.
  void _resolvePending(SlotPlan next) {
    final lo = run.geo.topTooth + RunConfig.itemEdgeMargin;
    final hi = run.geo.floorTooth - RunConfig.itemEdgeMargin;
    for (final (item, prev) in _pending) {
      final x0 = prev.lastRingX;
      final y0 = prev.extra is TrainSpec
          ? prev.centreY +
                2 *
                    (prev.extra! as TrainSpec).dy *
                    (prev.extra! as TrainSpec).dir
          : prev.centreY;
      final x1 = next.trackX;
      final y1 = next.centreY;
      double line(double x) {
        final u = x1 == x0 ? 0.0 : ((x - x0) / (x1 - x0)).clamp(0.0, 1.0);
        return y0 + (y1 - y0) * u;
      }

      final y = (line(item.trackX) + item.lineOffset).clamp(lo, hi).toDouble();
      final toX = item.toTrackX;
      _spawnItem(item.resolved(y: y, toY: toX == null ? null : line(toX)));
    }
    _pending.clear();
  }

  void _spawnItem(GapItemPlan item) {
    final kind = pickupKindFor(item.kind);
    if (kind == null) return;
    final p = kind.build(item, run.ctx);
    run.layers.items.add(p);
    _pickups.add(p);
  }

  void _announce() {
    final s = run.state;
    final right = s.camX + RunConfig.worldWidth;
    for (final h in _hoops) {
      if (h.announced || h.planeX - h.opening / 2 > right) continue;
      h.announced = true;
      run.events.emit(ElementSpawned(h.plan.element));
      if (h.plan.tiltDeg != 0) {
        run.events.emit(const ElementSpawned(ElementId.angledRing));
      }
      if (h.plan.motion != null) {
        run.events.emit(const ElementSpawned(ElementId.movingRing));
      }
    }
    for (final p in _pickups) {
      if (p.announced || p.position.x - p.hitRadius > right) continue;
      p.announced = true;
      run.events.emit(ElementSpawned(p.id));
      final extra = p.plan?.extra;
      if (extra is CapsuleType) {
        run.events.emit(ElementSpawned(extra.element));
      }
    }
  }

  void _hitTest() {
    if (!run.canCollect) return;
    final bird = run.birdTrackPosition();
    if (bird == null) return;
    final r = RunConfig.birdRadius * run.state.birdScale;
    for (final p in List.of(_pickups)) {
      if (p.collected || p.escaped) continue;
      if (p.touches(bird, r)) {
        p.collected = true;
        p.onCollect(run.ctx);
        run.events.emit(PickupCollected(p.id, p));
      } else if (p.isPast(bird.x, r)) {
        p.escaped = true;
        p.onPassedUncaught(run.ctx);
      }
    }
  }

  void _cull(double dt) {
    final left = run.state.camX - RunConfig.firstHoopOffscreen;
    _hoops.removeWhere((h) {
      final gone = h.isRemoved || h.planeX + h.opening < left;
      if (gone && !h.isRemoved) h.removeFromRun();
      return gone;
    });
    _pickups.removeWhere((p) {
      final gone = p.isRemoved || p.position.x + 2 * p.hitRadius < left;
      if (gone && !p.isRemoved) p.removeFromParent();
      return gone;
    });
    for (var i = _fading.length - 1; i >= 0; i--) {
      final (c, t) = _fading[i];
      if (t - dt <= 0) {
        c.removeFromParent();
        _fading.removeAt(i);
      } else {
        _fading[i] = (c, t - dt);
      }
    }
  }

  /// §3.0.3 portal ride: everything ahead of the bird goes ([fade] s);
  /// uncaught items do not count as missed.
  void clearAhead({double fade = 0.2}) {
    final birdX =
        run.birdTrackPosition()?.x ?? run.state.camX + RunConfig.birdX;
    _hoops.removeWhere((h) {
      if (h.planeX <= birdX) return false;
      _fading
        ..add((h, fade))
        ..add((h.front, fade));
      return true;
    });
    _pickups.removeWhere((p) {
      if (p.position.x <= birdX || p.collected) return false;
      p.escaped = true; // never judged
      _fading.add((p, fade));
      return true;
    });
    _pending.clear();
  }

  /// The next unresolved hoop the bird has not fully passed (§3.0.4 5:
  /// the ring's rightmost point, so a tilted ring whose plane centre is
  /// already behind the bird still counts while the bird crosses its upper
  /// or lower half).
  Hoop? nextHoopAhead() {
    final birdX =
        run.birdTrackPosition()?.x ?? run.state.camX + RunConfig.birdX;
    final r = RunConfig.birdRadius * run.state.birdScale;
    for (final h in _hoops) {
      if (!h.resolved && birdX - r <= h.frame().rightmostX) return h;
    }
    return null;
  }

  void dispose() {
    for (final h in _hoops) {
      h.removeFromRun();
    }
    for (final p in _pickups) {
      p.removeFromParent();
    }
    for (final (c, _) in _fading) {
      c.removeFromParent();
    }
    _hoops.clear();
    _pickups.clear();
    _fading.clear();
    _pending.clear();
  }
}
