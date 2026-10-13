import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import 'package:flame/components.dart';

import 'config/capsule_config.dart';
import 'config/comet_config.dart';
import 'config/egg_config.dart';
import 'config/jar_config.dart';
import 'config/pair_config.dart';
import 'config/piggy_config.dart';
import 'config/portal_config.dart';
import 'config/run_config.dart';
import 'config/special_hoops_config.dart';
import 'config/star_trail_config.dart';
import 'director/run_director.dart';
import 'effects/clear_fade.dart';
import 'effects/collect_fx.dart';
import 'elements.dart';
import 'hoops/hoop.dart';
import 'hoops/kinds/fever.dart';
import 'hoops/kinds/registry.dart';
import 'hoops/ring_painter.dart';
import 'pickups/pickup.dart';
import 'pickups/registry.dart';
import 'run_controller.dart';
import 'run_events.dart';
import 'run_state.dart';

/// Turns director plans into components (ARCH §1.1): spawns each hoop once
/// its plane is within 60 pt of the right edge (§3.0.1 first hoop "60 pt
/// past the right edge"), resolves line items between two hoops, announces
/// elements entering the screen, runs the pickup hit test (§3.0.3) and
/// removes parts that left the screen.
///
/// PRD-2.2 §15 plan one hoop ahead: the director plans slot B (its kind,
/// centre, attached items and the gap after it) one full gap before B's
/// hoop spawns — when the hoop before it spawns. So every item between A
/// and B is resolved and created off-screen and scrolls in; nothing pops
/// into view. The planned-ahead slot ([plannedAhead]) has no hoop yet.
///
/// PRD-2.2 §27 one bonus at a time: it keeps `RunState.activity` in sync
/// ([RunActivity.of]); when an activity starts, the reward items ahead that
/// are not visible yet are cleared ([clearRewardsAhead], PRD-2.3 §17.5).
///
/// PRD-2.3 §17 one big bonus on screen: it tells the director whether a big
/// bonus is open ([bigBonusOpen]) and creates each slot's hoop at its own
/// edge ([creationEdge]) so a big bonus's halo / beam scrolls in from the
/// right.
class RunSpawner {
  RunSpawner(this.run);

  final RunController run;
  final List<Hoop> _hoops = [];
  final List<Pickup> _pickups = [];
  /// Parts a ride cleared, fading out: (part, seconds left, fade length).
  final List<(Component, double, double)> _fading = [];
  final List<(GapItemPlan, SlotPlan)> _pending = [];

  /// PRD-2.2 §15 the planned-ahead slot (no hoop yet) and the items
  /// attached to it (created when it was planned: the switch, the comet
  /// star).
  SlotPlan? _ahead;
  final List<Pickup> _aheadItems = [];

  /// PRD-2.2 §15.1 feature follow-ups popping in: (pickup, seconds).
  final List<(Pickup, double)> _popping = [];
  CollectBursts? _sparkle;

  /// Every plan, in order (tests, debug overlay).
  final List<SlotPlan> slotLog = [];
  final List<GapPlan> gapLog = [];

  Iterable<Hoop> get hoops => _hoops;
  Iterable<Pickup> get pickups => _pickups;

  /// PRD-2.2 §15 the slot planned one gap ahead (its hoop not spawned yet).
  SlotPlan? get plannedAhead => _ahead;

  /// The director's spawned counts (`run_director_hoops` / `_items`) minus
  /// the planned-ahead slot, which never spawned (PRD-2.2 §15).
  Map<String, int> get spawnedCounts {
    final out = {...run.director.spawnedCounts};
    final a = _ahead;
    if (a != null) {
      void minus(String k) {
        final n = (out[k] ?? 0) - 1;
        if (n > 0) {
          out[k] = n;
        } else {
          out.remove(k);
        }
      }

      minus(a.element.storageId);
      if (a.tiltDeg != 0) minus('tilted');
      if (a.motion != null) minus('moving');
      if (a.cometHang) minus(ElementId.comet.storageId);
    }
    return out;
  }

  /// PRD-2.2 §15 the line items waiting for the planned-ahead slot's
  /// centre (tests).
  Iterable<GapItemPlan> get pendingItems => _pending.map((e) => e.$1);

  /// Hoops are live once WP-1a registers the normal hoop (or a test does).
  /// Until then the 1.0 pipes run and the spawner stays idle.
  bool get live => hoopKindFor(HoopKindId.normal) != null;

  void update(double dt) {
    if (!live) return;
    syncActivity();
    final s = run.state;
    // PRD-2.3 §17.4 the creation edge is per slot: 60 pt, or the slot's
    // visual reach + 8 pt if that is larger.
    final right = s.camX + RunConfig.worldWidth + 1e-6;
    var guard = 0;
    while (!hold && guard++ < 16) {
      final ahead = _ahead;
      if (ahead == null) {
        _planSlot();
        continue;
      }
      if (ahead.trackX > right + creationEdge(ahead)) break;
      _spawnAhead();
    }
    _announce();
    _hitTest();
    _cull(dt);
    _stepPopIns(dt);
  }

  /// PRD-2.2 §15 plans the next slot one gap ahead: resolves (and creates)
  /// the line items of the gap before it, creates its attached items and
  /// plans the gap after it. Its hoop spawns later ([_spawnAhead]).
  void _planSlot() {
    final ctx = run.directorContext();
    final plan = run.director.nextSlot(ctx);
    slotLog.add(plan);
    _resolvePending(plan);
    _ahead = plan;
    _aheadItems.clear();
    for (final a in plan.attached) {
      final p = _spawnItem(a);
      if (p != null) _aheadItems.add(p);
    }
    final gap = run.director.nextGap(run.directorContext(), plan);
    gapLog.add(gap);
    for (final item in gap.items) {
      if (item.y == null) {
        _pending.add((item, plan));
      } else {
        _spawnItem(item);
      }
    }
  }

  /// The planned-ahead slot's plane reached the spawn edge: its hoop(s).
  void _spawnAhead() {
    var plan = _ahead!;
    _ahead = null;
    final s = run.state;
    // §3.0.3 slot order 1–2 hold for the slot planned one gap earlier
    // (PRD-2.2 §15): a revive since then, or a ride that started since
    // then, makes it a plain hoop (rides: full size). A comet ride keeps
    // the planned slot's height, tilt and motion (PRD-2.2 §16.1,
    // S7-12); only its reward / special part goes (§27).
    final revived = run.director.takeRevivePending();
    final rideNow = s.ride != null && !plan.duringRide;
    if (revived || rideNow) {
      final plain = run.director.plainSlot(
        plan,
        run.directorContext(),
        ride: s.ride != null,
        keepGeometry: !revived && s.ride?.kind == RideKind.comet,
      );
      _dropAheadItems();
      plan = plain;
    }
    s
      ..hoopIndex = plan.index + 1
      ..gapIndex = plan.index;
    final kind = hoopKindFor(plan.kind) ?? hoopKindFor(HoopKindId.normal)!;
    final hoop = Hoop(plan: plan, kind: kind);
    kind.onSpawn(hoop, run.ctx);
    kind.buildVisual(hoop, run.ctx);
    run.layers.back.add(hoop);
    run.layers.front.add(hoop.front);
    _hoops.add(hoop);
    for (final p in _aheadItems) {
      kind.linkAttached(hoop, p, run.ctx);
    }
    _aheadItems.clear();
    run.events.emit(HoopSpawned(hoop, plan));
    // region WP-3c — the Ring Train's rings 2 and 3 (PRD-2 §3.22)
    for (final p in kind.extraHoops(plan)) {
      final extra = Hoop(plan: p, kind: kind);
      kind.onSpawn(extra, run.ctx);
      kind.buildVisual(extra, run.ctx);
      run.layers.back.add(extra);
      run.layers.front.add(extra.front);
      _hoops.add(extra);
      run.events.emit(HoopSpawned(extra, p));
    }
    // endregion WP-3c
  }

  /// The planned-ahead slot's attached items go (it became plain).
  void _dropAheadItems() {
    for (final p in _aheadItems) {
      _pickups.remove(p);
      p.escaped = true;
      p.removeFromParent();
    }
    _aheadItems.clear();
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

      // PRD-2.2 §19.4 patterns keep their shape inside the margins too: an
      // arc's upward bulge stays below the top margin.
      final bulge = switch (item.kind) {
        ElementId.starTrail => RunConfig.starTrailBulge,
        ElementId.piggyCoins => PiggyConfig.coinBulge,
        _ => 0.0,
      };
      final top = math.min(lo + bulge, hi);
      double fit(double v) => v.clamp(top, hi).toDouble();
      final y = fit(line(item.trackX) + item.lineOffset);
      final toX = item.toTrackX;
      _spawnItem(
        item.resolved(y: y, toY: toX == null ? null : fit(line(toX))),
      );
    }
    _pending.clear();
  }

  Pickup? _spawnItem(GapItemPlan item) {
    final kind = pickupKindFor(item.kind);
    if (kind == null) return null;
    final p = kind.build(item, run.ctx);
    run.layers.items.add(p);
    _pickups.add(p);
    run.events.emit(PickupSpawned(p));
    return p;
  }

  /// §3.0.8 The leftmost track x of [h]'s ring artwork right now (every
  /// ring ellipse, rx 12 × ry, rotated by the frame tilt, plus half the
  /// stroke): the hoop is on screen once this is left of the right edge.
  static double artLeftX(Hoop h) {
    final f = h.frame();
    final c = math.cos(f.tilt), s = math.sin(f.tilt);
    final ry = RingPainter.ryFor(f.opening);
    final half =
        math.sqrt(math.pow(RingPainter.rx * c, 2) + math.pow(ry * s, 2)) +
        RingPainter.stroke / 2;
    var left = double.infinity;
    for (final o in f.rings) {
      final x = f.toWorld(Vector2(0, o)).x - half;
      if (x < left) left = x;
    }
    return left;
  }

  void _announce() {
    final s = run.state;
    final right = s.camX + RunConfig.worldWidth;
    for (final h in _hoops) {
      if (h.announced || artLeftX(h) > right) continue;
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
      final (c, t, len) = _fading[i];
      if (t - dt <= 0) {
        c.removeFromParent();
        _fading.removeAt(i);
      } else {
        _fading[i] = (c, t - dt, len);
        // §3.12 the opacity follows the fade (S6-47).
        if (c is ClearFade) c.clearAlpha = (t - dt) / len;
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
      _dropPortal(h.plan);
      _fading
        ..add((h, fade, fade))
        ..add((h.front, fade, fade));
      return true;
    });
    _pickups.removeWhere((p) {
      if (p.position.x <= birdX || p.collected) return false;
      // region WP-3e — a ride clears the collectables on screen unjudged
      // (§3.0.3): the Piggy Bank / Firefly Jar drop the unresolved coins /
      // fireflies from what they still owe, so the bank can resolve.
      run.events.emit(PickupCleared(p.id, p));
      // endregion WP-3e
      p.escaped = true; // never judged
      _fading.add((p, fade, fade));
      return true;
    });
    // S6-41 planned-but-unplaced bank fields are cleared too: the bank
    // places those coins again after the landing.
    for (final (item, _) in _pending) {
      if (item.kind == ElementId.piggyCoins && run.state.piggy != null) {
        run.director.refundPiggyCoins(item.extra as int? ?? 0);
      }
    }
    _pending.clear();
    // PRD-2.2 §15 the planned-ahead slot goes too (its attached items were
    // cleared with the pickups above).
    final ahead = _ahead;
    if (ahead != null) _dropPortal(ahead);
    _ahead = null;
    _aheadItems.clear();
  }

  /// §3.12 a portal planned or spawned ahead and never flown does not count
  /// as the last ride (never the same ride twice in a row).
  void _dropPortal(SlotPlan p) {
    if (p.kind != HoopKindId.portal) return;
    if (p.extra case final RideId ride) run.director.portalDropped(ride);
  }

  // region WP-G2 — one bonus at a time (PRD-2.2 §27)
  /// Keeps `RunState.activity` in step with the features' state
  /// ([RunActivity.of]): a start clears the rewards ahead, an end starts
  /// the 2-hoop cool-down (counted from the director's next slot).
  void syncActivity() {
    final s = run.state;
    final now = RunActivity.of(s);
    final was = s.activity;
    if (now == was) return;
    s.activity = now;
    if (now != null) {
      s.activityStart = s.runClock;
      run.events.emit(ActivityStarted(now));
      clearRewardsAhead();
    } else {
      s.activityEndedAtSlot = run.director.hoopIndex;
      run.events.emit(ActivityEnded(was!));
    }
  }

  /// PRD-2.2 §27.3 an activity started: every reward item ahead of the bird
  /// (on screen, created off-screen, waiting for its line, or attached to
  /// the planned-ahead slot) fades out over [fade] s and is removed; the
  /// planned-ahead slot becomes plain if it is a reward slot; a reward ring
  /// on screen (pair, Lucky Spin, FEVER) fades its reward parts and passes
  /// as a normal ring; a portal on screen fades out. The feather and the
  /// puzzle piece keep their once-per-run chance (owed); everything else is
  /// back in the normal draw. A piggy / jar run's own items for the planned
  /// gap are added so its follow-ups start there and scroll in.
  void clearRewardsAhead({double fade = RunConfig.rewardClearFade}) {
    final birdX =
        run.birdTrackPosition()?.x ?? run.state.camX + RunConfig.birdX;
    final starsGone = <GapItemPlan>{};
    _pickups.removeWhere((p) {
      if (p.collected || p.escaped || p.position.x <= birdX) return false;
      if (!RunDirector.isRewardItem(p.id)) return false;
      // PRD-2.3 §17.5 anything visible (a part of its halo included) stays.
      if (isVisible(p)) return false;
      _owe(p.id);
      if (p.id == ElementId.comet) run.director.oweComet();
      final plan = p.plan;
      if (p.id == ElementId.comet && plan != null) starsGone.add(plan);
      run.events.emit(PickupCleared(p.id, p));
      p.escaped = true; // never judged
      _aheadItems.remove(p);
      _fading.add((p, fade, fade));
      return true;
    });
    _pending.removeWhere((e) {
      if (!RunDirector.isRewardItem(e.$1.kind)) return false;
      _owe(e.$1.kind);
      return true;
    });
    final ctx = run.directorContext();
    final ahead = _ahead;
    if (ahead != null && RunDirector.isRewardSlot(ahead)) {
      _dropAheadItems();
      _ahead = run.director.plainSlot(ahead, ctx);
    }
    final a = _ahead;
    if (a != null) {
      final pending = _pending.where((e) => identical(e.$2, ahead)).toList();
      if (!identical(a, ahead)) {
        // Re-point the waiting line items to the re-planned slot.
        _pending.removeWhere((e) => identical(e.$2, ahead));
        _pending.addAll([for (final e in pending) (e.$1, a)]);
      }
      final own = run.director.activityItemsFor(
        ctx,
        a,
        hasItems: pending.isNotEmpty,
      );
      for (final item in own) {
        _pending.add((item, a));
      }
    }
    _hoops.removeWhere((h) {
      if (h.resolved || h.planeX <= birdX) return false;
      // PRD-2.3 §17.5 a visible ring keeps its reward (no portal fade, no
      // reward fade); only a hoop still beyond the right edge is cleared.
      if (hoopVisible(h)) return false;
      if (h.plan.kind == HoopKindId.portal) {
        run.director.oweSlot(h.plan);
        _fading
          ..add((h, fade, fade))
          ..add((h.front, fade, fade));
        return true;
      }
      if (RunDirector.rewardKinds.contains(h.plan.kind)) h.stripReward();
      // Its comet star went with the pickups: a plain hoop now.
      if (h.plan.cometHang && h.plan.attached.any(starsGone.contains)) {
        h.plan = h.plan.copyWith(cometHang: false);
      }
      return false;
    });
  }

  // region WP-BONUS — one big bonus on screen (PRD-2.3 §17)
  /// PRD-2.3 §17.2 the visual reach of item [e] (pt its drawing extends to
  /// the left of its x; for the Star Trail, left of its first star). Big
  /// items only; 0 for the others.
  static double itemReach(ElementId e) => switch (e) {
    ElementId.piggy => PiggyConfig.visualReach,
    ElementId.jar => JarConfig.visualReach,
    ElementId.comet => CometConfig.visualReach,
    ElementId.egg => EggConfig.visualReach,
    ElementId.capsule ||
    ElementId.hourglass ||
    ElementId.miniBird ||
    ElementId.coinFrenzy => CapsuleConfig.visualReach,
    ElementId.starTrail => StarTrailConfig.visualReach,
    _ => 0,
  };

  /// PRD-2.3 §17.2 the visual reach of [p]'s hoop and its attached big
  /// items, measured from the slot's plane (0 for a plain hoop).
  static double slotReach(SlotPlan p) {
    var r = switch (p.kind) {
      HoopKindId.portal => PortalConfig.visualReach,
      HoopKindId.fever => FeverRingPainter.visualReach(p.opening),
      HoopKindId.pair => PairConfig.visualReach,
      HoopKindId.luckySpin => LuckySpinConfig.visualReach,
      _ => 0.0,
    };
    for (final a in p.attached) {
      if (!RunDirector.isBigItem(a.kind)) continue;
      r = math.max(r, itemReach(a.kind) - (a.trackX - p.trackX));
    }
    return r;
  }

  /// PRD-2.3 §17.4 how far beyond the right screen edge [p]'s hoop is
  /// created: [RunConfig.firstHoopOffscreen], or its visual reach +
  /// [RunConfig.bigBonusEdgeMargin] if that is larger.
  static double creationEdge(SlotPlan p) => math.max(
    RunConfig.firstHoopOffscreen,
    slotReach(p) + RunConfig.bigBonusEdgeMargin,
  );

  /// PRD-2.3 §17.2 the leftmost track x of [p]'s drawing (body, halo,
  /// glow, tail).
  static double visualLeftX(Pickup p) {
    final reach = itemReach(p.id);
    // One pickup spans the whole Star Trail (its hit radius covers the arc).
    if (p.id == ElementId.starTrail) return p.position.x - p.hitRadius - reach;
    return math.min(
      p.position.x - math.max(p.hitRadius, reach),
      p.toRect().left,
    );
  }

  /// PRD-2.3 §17.2 the leftmost track x of [h]'s drawing (ring art, beam,
  /// halo, wheel, tags).
  static double hoopVisualLeftX(Hoop h) =>
      math.min(artLeftX(h), h.planeX - slotReach(h.plan));

  double get _right => run.state.camX + RunConfig.worldWidth;

  /// PRD-2.3 §17.2 any part of [p]'s drawing is inside the screen.
  bool isVisible(Pickup p) => visualLeftX(p) < _right;

  /// PRD-2.3 §17.2 any part of [h]'s drawing is inside the screen.
  bool hoopVisible(Hoop h) => hoopVisualLeftX(h) < _right;

  /// PRD-2.3 §17.2 the open big bonuses: the planned-ahead reward ring, big
  /// line items waiting for their line, reward rings and portals not yet
  /// flown through or passed, and big pickups not yet collected or passed.
  /// (A comet-star hoop counts once, through its star.)
  int get openBigCount {
    final birdX =
        run.birdTrackPosition()?.x ?? run.state.camX + RunConfig.birdX;
    final r = RunConfig.birdRadius * run.state.birdScale;
    var n = 0;
    final a = _ahead;
    if (a != null && RunDirector.rewardKinds.contains(a.kind)) n++;
    for (final (item, _) in _pending) {
      if (RunDirector.isBigItem(item.kind)) n++;
    }
    for (final h in _hoops) {
      if (h.resolved || h.planeX <= birdX) continue;
      if (RunDirector.rewardKinds.contains(h.plan.kind)) n++;
    }
    for (final p in _pickups) {
      if (!RunDirector.isBigItem(p.id)) continue;
      if (p.collected || p.escaped || p.isRemoved || p.isPast(birdX, r)) {
        continue;
      }
      n++;
    }
    return n;
  }

  /// PRD-2.3 §17.3 rule 1: a big bonus is open (the director plans none).
  bool get bigBonusOpen => openBigCount > 0;
  // endregion WP-BONUS

  void _owe(ElementId e) {
    if (e == ElementId.feather) {
      run.director.oweFeather();
      run.state.featherSpawned = false;
    } else if (e == ElementId.puzzlePiece) {
      run.director.owePiece();
      run.state.pieceSpawned = false;
    }
  }
  // endregion WP-G2

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

  // region WP-3b — portal rides (PRD-2 §3.12)
  /// The portal ride holds the course: no slots are planned while true.
  bool hold = false;

  /// §3.12 the way back: the old course (passed hoops, the portal) goes;
  /// nothing of it is judged.
  void clearAll() {
    for (final h in _hoops) {
      if (!h.resolved) _dropPortal(h.plan);
    }
    final ahead = _ahead;
    if (ahead != null) _dropPortal(ahead);
    for (final h in _hoops) {
      h.removeFromRun();
    }
    for (final p in _pickups) {
      p.escaped = p.escaped || !p.collected;
      p.removeFromParent();
    }
    _hoops.clear();
    _pickups.clear();
    _pending.clear();
    _ahead = null;
    _aheadItems.clear();
    _popping.clear();
  }
  // endregion WP-3b

  // region WP-3e — the collectables' own items (PRD-2 §3.28/§3.29)
  /// Spawns one gap item right away, hit-tested like any other (the Piggy
  /// Bank's own-gap coins and the Firefly Jar's first swarm are emitted by
  /// their features; the director's follow-gap fields come through the
  /// normal slot path).
  ///
  /// PRD-2.2 §15.1 such a follow-up placed at the moment of the grab pops
  /// in (scale 0 → 1.15 → 1 over 0.25 s + a small sparkle) when its left
  /// edge is already inside the screen; one created off-screen just
  /// scrolls in.
  Pickup? spawnItem(GapItemPlan item) {
    final p = _spawnItem(item);
    if (p != null) {
      final right = run.state.camX + RunConfig.worldWidth;
      if (p.position.x - p.hitRadius < right) _popIn(p);
    }
    return p;
  }
  // endregion WP-3e

  // region WP-G2 — pop-in of feature follow-ups (PRD-2.2 §15.1)
  /// Feature follow-ups currently popping in (tests).
  Iterable<Pickup> get poppingIn => _popping.map((e) => e.$1);

  /// The pop-in sparkle pool (tests).
  CollectBursts? get popSparkle => _sparkle;

  void _popIn(Pickup p) {
    p.popScale = 0;
    _popping.add((p, 0));
    var sparkle = _sparkle;
    if (sparkle == null || sparkle.isRemoved) {
      sparkle = _sparkle = CollectBursts();
      run.layers.fx.add(sparkle);
    }
    sparkle.burst(
      at: Offset(p.position.x, p.position.y),
      colors: const [Color(0xFFFFFFFF), Color(0xFFFFE27A)],
      pieces: RunConfig.popInSparkle,
      speed: 90,
      sizeMin: 2,
      sizeMax: 4,
      life: .35,
    );
  }

  /// PRD-2.2 §15.1 scale 0 → 1.15 (first 60 %) → 1 over 0.25 s.
  static double popInScale(double t) {
    const len = RunConfig.popInTime;
    const peak = RunConfig.popInOvershoot;
    final u = (t / len).clamp(0.0, 1.0);
    if (u < .6) {
      final k = u / .6;
      return peak * (1 - (1 - k) * (1 - k));
    }
    return peak + (1 - peak) * ((u - .6) / .4);
  }

  void _stepPopIns(double dt) {
    for (var i = _popping.length - 1; i >= 0; i--) {
      final (p, t0) = _popping[i];
      final t = t0 + dt;
      if (t >= RunConfig.popInTime || p.isRemoved) {
        p.popScale = 1;
        _popping.removeAt(i);
      } else {
        p.popScale = popInScale(t);
        _popping[i] = (p, t);
      }
    }
  }
  // endregion WP-G2

  void dispose() {
    for (final h in _hoops) {
      h.removeFromRun();
    }
    for (final p in _pickups) {
      p.removeFromParent();
    }
    for (final (c, _, _) in _fading) {
      c.removeFromParent();
    }
    _hoops.clear();
    _pickups.clear();
    _fading.clear();
    _pending.clear();
    _ahead = null;
    _aheadItems.clear();
    _popping.clear();
    _sparkle?.removeFromParent();
    _sparkle = null;
  }
}
