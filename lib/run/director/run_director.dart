import 'dart:math';

import '../config/director_tables.dart';
import '../config/run_config.dart';
import '../elements.dart';
import 'director_context.dart';
import 'first_meet.dart';
import 'layout_sampler.dart';
import 'plans.dart';
import 'rng.dart';

export 'director_context.dart';
export 'plans.dart';
export 'rng.dart';

/// The PRD-2 run director (§3.0.3): decides, for every hoop slot, what kind
/// of hoop it is and, for every gap, which item floats in it. Pure Dart.
///
/// Call order per slot: [nextSlot] then [nextGap] for that slot. The same
/// seed and the same [DirectorContext] sequence always give the same plans.
/// Elements that are not in `enabled` (no WP registered them yet) are never
/// offered.
class RunDirector {
  RunDirector({
    required int seed,
    this.tables = DirectorTables.prd2,
    required Set<ElementId> enabled,
    required Set<ElementId> met,
    int startHoopIndex = 0,
    RideId? lastPortalRide,
    List<ElementId> forced = const [],
    RideId? forcedRide,
    double firstTrackX = RunConfig.worldWidth + RunConfig.firstHoopOffscreen,
    this.spacing = RunConfig.spacing,
  }) : rng = RunRandom(seed),
       enabled = {...enabled},
       _i = startHoopIndex,
       _nextX = firstTrackX,
       _lastRide = lastPortalRide,
       _forcedRide = forcedRide,
       _forced = [...forced] {
    firstMeet = FirstMeet(met, this.enabled);
    _layout = LayoutSampler(tables, rng.layout);
    final r = rng.layout;
    _cometAt = RunRandom.rangeInt(r, tables.comet.first.$1, tables.comet.first.$2);
    _portalAt = RunRandom.rangeInt(
      r,
      tables.portal.first.$1,
      tables.portal.first.$2,
    );
    _featherAt = RunRandom.rangeInt(
      r,
      tables.featherWindow.$1,
      tables.featherWindow.$2,
    );
    _pieceAt = RunRandom.rangeInt(
      r,
      tables.pieceWindow.$1,
      tables.pieceWindow.$2,
    );
    _heartAt = RunRandom.rangeInt(r, tables.heart.first.$1, tables.heart.first.$2);
    if (forcedRide != null && !_forced.contains(ElementId.portal)) {
      _forced.add(ElementId.portal);
    }
    // startHoopIndex (call, ARCH §2.2): schedules whose first window lies
    // before the start re-roll from the start; the once-per-run feather and
    // piece and the heart come at the start instead.
    final s = startHoopIndex;
    if (s > 0) {
      if (_cometAt < s) _cometAt = s + (_cometAt - tables.comet.first.$1);
      if (_portalAt < s) _portalAt = s + (_portalAt - tables.portal.first.$1);
      _heartAt = max(_heartAt, s);
      _featherAt = max(_featherAt, s);
      _pieceAt = max(_pieceAt, s);
    }
  }

  final DirectorTables tables;
  final RunRandom rng;
  final double spacing;

  /// Registered elements (hoop + pickup registries, features).
  final Set<ElementId> enabled;
  late final FirstMeet firstMeet;
  late final LayoutSampler _layout;

  int _i;
  double _nextX;

  late int _cometAt;
  late int _portalAt;
  late int _heartAt;
  late int _featherAt;
  late int _pieceAt;
  bool _featherDone = false;
  bool _pieceDone = false;
  int _heartsPlaced = 0;

  int _lastSpecial = -99;
  int _cdLeft = 0;
  final Map<HoopKindId, int> _lastOf = {};
  final Map<ElementId, int> _lastGapOf = {};
  final Map<ElementId, int> _runCount = {};
  int _lastPortal = -99;
  int _lastComet = -99;
  HoopKindId? _prevKind;
  SawDesign? _lastSaw;
  SwitchDesign? _lastSwitch;
  RideId? _lastRide;
  RideId? _forcedRide;
  final List<ElementId> _forced;
  bool _revivePending = false;
  final Set<int> _gapUsed = {};
  bool _piggyActive = false;
  int _piggyGapsLeft = 0;
  int _collectablePlannedAt = -99;
  RideKind? _ride;
  final Map<String, int> _spawned = {};

  /// Next slot index (= hoop index of the slot [nextSlot] plans next).
  int get hoopIndex => _i;

  /// Track x of the next slot's plane.
  double get nextTrackX => _nextX;

  /// The current ride (between [onRideStart] and [onRideEnd]).
  RideKind? get ride => _ride;

  /// Pending debug forces (head first).
  List<ElementId> get forcedQueue => List.unmodifiable(_forced);

  /// The schedules (tests, debug overlay).
  int get portalAt => _portalAt;
  int get cometAt => _cometAt;
  int get heartAt => _heartAt;
  int get featherAt => _featherAt;
  int get pieceAt => _pieceAt;
  RideId? get lastRide => _lastRide;

  /// Spawned counts per kind / modifier / item storage id (analytics
  /// `run_director_hoops` / `run_director_items`).
  Map<String, int> get spawnedCounts => Map.unmodifiable(_spawned);

  bool _on(ElementId e) => enabled.contains(e);
  bool get _portalOn => _on(ElementId.portal);

  /// §3.0.1 opening at [hoopIndex]: 118 → −0.32 %/hoop → floor 92; ride 118.
  double openingFor(int hoopIndex, {required bool ride}) =>
      RunConfig.openingFor(hoopIndex, ride: ride);

  // --- timing-stream rolls (§3.0.3 "timing") --------------------------------

  /// §3.17 Next squeeze moment: [now] + 60..120 s.
  double rollSqueezeAt(double now) =>
      now +
      RunRandom.range(
        rng.timing,
        RunConfig.squeezeGapMin,
        RunConfig.squeezeGapMax,
      );

  /// §3.17 Hold 10..20 s.
  double rollSqueezeHold() => RunRandom.range(
    rng.timing,
    RunConfig.squeezeHoldMin,
    RunConfig.squeezeHoldMax,
  );

  /// §3.6 Big Hoops D: 30..40 s.
  double rollBigHoopsDuration() => RunRandom.range(
    rng.timing,
    RunConfig.bigHoopsMin,
    RunConfig.bigHoopsMax,
  );

  /// §3.16 Puzzle bonus 50..250 step 5.
  int rollPuzzleBonus() {
    const steps =
        (RunConfig.puzzleBonusMax - RunConfig.puzzleBonusMin) ~/
        RunConfig.puzzleBonusStep;
    return RunConfig.puzzleBonusMin +
        RunConfig.puzzleBonusStep * rng.timing.nextInt(steps + 1);
  }

  /// §3.30 Hourglass duration 10..20 s.
  double rollHourglassDuration() => RunRandom.range(
    rng.timing,
    RunConfig.hourglassMin,
    RunConfig.hourglassMax,
  );

  /// Generic timing roll in [a, b) for feature WPs (balloon prizes, …).
  double rollTiming(double a, double b) => RunRandom.range(rng.timing, a, b);

  // --- lifecycle --------------------------------------------------------------

  /// §3.0.3 slot order 2: the next slot is a plain normal hoop.
  void onRevive() => _revivePending = true;

  void onRideStart(RideKind k) => _ride = k;

  void onRideEnd(RideKind k) {
    if (_ride == k) _ride = null;
  }

  /// §3.0.8 debug: [e] spawns in the next slot / gap, ignoring unlock and
  /// cooldown (exclusivity still applies). Returns false for elements the
  /// director does not place (squeeze, starters, meta).
  bool debugForce(ElementId e) {
    if (!e.isSlotElement && !e.isGapElement) return false;
    if (e == ElementId.piggyCoins || e == ElementId.fireflySwarm) return false;
    _forced.add(e);
    return true;
  }

  /// §3.0.8 debug: the next portal (forced into the next slot) takes [id].
  void debugForceRide(RideId id) {
    _forcedRide = id;
    if (!_forced.contains(ElementId.portal)) _forced.add(ElementId.portal);
  }

  /// §3.0.8 the element was met (spawned on screen).
  void markMet(ElementId e) => firstMeet.markMet(e);

  void _count(String key) => _spawned[key] = (_spawned[key] ?? 0) + 1;

  // --- slots ------------------------------------------------------------------

  /// §3.0.3 "order of decisions for a hoop slot".
  SlotPlan nextSlot(DirectorContext ctx) {
    final i = _i++;
    final trackX = _nextX;
    final ride = ctx.rideActive || _ride != null;
    final band = ctx.band;

    double cap(double opening, [double extra = 0]) =>
        min(opening, band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin + extra));

    // 1. Ride active: normal, full size, upright, still; no items.
    // 2. First slot after a revive: normal (call: plain — upright, still).
    if (ride || _revivePending) {
      _revivePending = false;
      final opening = cap(openingFor(i, ride: ride) * ctx.bigHoopsMult);
      final y = _layout.nextCentre(i, ctx, opening);
      _prevKind = HoopKindId.normal;
      _count(ElementId.normalHoop.storageId);
      _nextX += spacing;
      return SlotPlan(
        index: i,
        kind: HoopKindId.normal,
        element: ElementId.normalHoop,
        trackX: trackX,
        centreY: y,
        opening: opening,
        advance: spacing,
        duringRide: ride,
      );
    }

    final prevY = ctx.prevCentreY ?? _layout.lastY;
    HoopKindId? kind;
    var forced = false;
    ElementId? forceMod; // angledRing / movingRing on a normal slot
    var cometMode = 0;

    // Debug force (head slot element of the queue).
    final dbgIdx = _forced.indexWhere((e) => e.isSlotElement);
    if (dbgIdx >= 0) {
      final e = _forced[dbgIdx];
      final special = HoopKindId.specialFor(e);
      var ok = false;
      if (special != null) {
        ok = _specialAllowed(special, i, ctx, ignoreUnlock: true);
        if (ok) kind = special;
      } else if (e == ElementId.portal) {
        ok = _on(e) && !ctx.squeezeWindow;
        if (ok) kind = HoopKindId.portal;
      } else if (e == ElementId.comet) {
        ok = _cometAllowed(i, ctx, mode: 2);
        if (ok) cometMode = 2;
      } else if (e == ElementId.angledRing || e == ElementId.movingRing) {
        ok = _on(e) && !(e == ElementId.movingRing && ctx.squeezeWindow);
        if (ok) forceMod = e;
      } else if (e == ElementId.normalHoop) {
        ok = true;
      }
      if (ok) {
        _forced.removeAt(dbgIdx);
        forced = true;
      }
    }

    final due = forced ? null : firstMeet.dueSlot(i);

    // 3. Portal (fixed schedule; first-meet pulls it forward).
    if (kind == null && !forced && _portalOn) {
      if (due == ElementId.portal) _portalAt = min(_portalAt, i);
      if (i >= _portalAt &&
          !ctx.squeezeWindow &&
          i - _lastComet >= RunConfig.cometPortalDistance) {
        kind = HoopKindId.portal;
        forced = due == ElementId.portal;
      }
    }

    // 4. Cooldown. 5. Special roll (first-meet replaces the roll).
    final cooling = i - _lastSpecial <= _cdLeft;
    if (kind == null && !forced && !cooling) {
      final dueSpecial = due == null ? null : HoopKindId.specialFor(due);
      if (dueSpecial != null && _specialAllowed(dueSpecial, i, ctx)) {
        kind = dueSpecial;
        forced = true;
      } else {
        final budget = tables.budgetFor(i).special;
        if (rng.layout.nextDouble() < budget) {
          final w = <HoopKindId, int>{};
          for (final e in tables.specials.entries) {
            if (_specialAllowed(e.key, i, ctx)) {
              w[e.key] = e.value.weightAt(i);
            }
          }
          kind = RunRandom.pickWeighted<HoopKindId>(rng.layout, w);
        }
      }
    }
    if (!forced && due == ElementId.comet) cometMode = 1;
    if (!forced && (due == ElementId.angledRing || due == ElementId.movingRing)) {
      forceMod = due;
    }

    kind ??= HoopKindId.normal;
    return _buildSlot(
      i,
      trackX,
      ctx,
      kind,
      forced: forced,
      forceMod: forceMod,
      cometMode: cometMode,
      prevY: prevY,
      cap: cap,
    );
  }

  SlotPlan _buildSlot(
    int i,
    double trackX,
    DirectorContext ctx,
    HoopKindId kind, {
    required bool forced,
    required ElementId? forceMod,
    required int cometMode,
    required double? prevY,
    required double Function(double, [double]) cap,
  }) {
    final r = rng.layout;
    final band = ctx.band;
    var opening = openingFor(i, ride: false);
    var extraMargin = 0.0;
    if (kind == HoopKindId.saw) opening += RunConfig.sawExtraOpening;
    final pairO = RunConfig.pairOffsetAt711 * ctx.viewHeight / RunConfig.designHeight;
    if (kind == HoopKindId.pair) extraMargin = pairO / 2;
    opening = cap(opening * ctx.bigHoopsMult, extraMargin);
    var y = _layout.nextCentre(i, ctx, opening, extra: extraMargin);
    final maxJump = tables.bandFor(i).dy.$3 * band;

    Object? extra;
    var advance = spacing;
    var rings = const <double>[0];
    final attached = <GapItemPlan>[];

    // Kind-specific checks that need the centre (downgrade → normal).
    if (kind == HoopKindId.spring) {
      // region WP-3c — §3.23 "always with room for the next ring inside the
      // band": the 240 pt target is checked against the band rule (tooth
      // lines − opening / 2 − 7 − 18), not the row's centre range — that
      // range is narrower than 240 pt on a 568 pt screen until hoop 50, so
      // springs (and their first meet) never came up there.
      final (lo, hi) = _layout.limits(i + 1, ctx, opening, useTable: false);
      // endregion WP-3c
      var dir = r.nextDouble() < 0.5 ? -1 : 1;
      bool fits(int d) {
        final t = y + d * RunConfig.springJump;
        return t >= lo && t <= hi;
      }

      if (!fits(dir)) dir = -dir;
      if (!fits(dir) && forced) {
        // First-meet / debug: move the spring to the edge of its own range
        // that leaves room for the jump (still within the row's max jump).
        final (lo0, hi0) = _layout.limits(i, ctx, opening);
        final options = <(double, int)>[
          if (lo0 + RunConfig.springJump <= hi) (lo0, 1),
          if (hi0 - RunConfig.springJump >= lo) (hi0, -1),
        ]..sort((a, b) => (a.$1 - y).abs().compareTo((b.$1 - y).abs()));
        for (final (cand, d) in options) {
          if (prevY == null || (cand - prevY).abs() <= maxJump) {
            y = cand;
            dir = d;
            _layout.lastY = cand;
            break;
          }
        }
      }
      if (fits(dir)) {
        extra = dir < 0 ? SpringDir.up : SpringDir.down;
        _layout.forceY = y + dir * RunConfig.springJump;
      } else {
        kind = HoopKindId.normal; // §3.0.3 no room for the 240 pt jump
        forced = false;
      }
    } else if (kind == HoopKindId.pair) {
      final minY = ctx.hudBottom + pairO / 2 + opening / 2 + RunConfig.rimRadius;
      final (lo, hi) = _layout.limits(i, ctx, opening, extra: extraMargin, useTable: false);
      if (y < minY) y = min(minY, hi);
      final reach = prevY == null
          ? 0
          : min((y - pairO / 2 - prevY).abs(), (y + pairO / 2 - prevY).abs());
      if (y < minY || y < lo || y > hi || reach > maxJump) {
        kind = HoopKindId.normal; // §3.21 does not fit → normal hoop
        forced = false;
        _layout.lastY = y;
      } else {
        rings = [-pairO / 2, pairO / 2];
        extra = _pairRewards(i, ctx);
        _layout.lastY = y;
      }
    }

    switch (kind) {
      case HoopKindId.train:
        final (lo, hi) = _layout.limits(i, ctx, opening);
        var d = r.nextDouble() < 0.5 ? -1 : 1;
        final end = y + d * 2 * RunConfig.trainDy;
        if (end < lo || end > hi) d = -d;
        extra = TrainSpec(dir: d, dx: RunConfig.trainDx, dy: RunConfig.trainDy);
        advance = spacing + 2 * RunConfig.trainDx;
        _layout.lastY = y + d * 2 * RunConfig.trainDy;
      case HoopKindId.luckySpin:
        final slice = r.nextInt(RunConfig.luckySpinSlices.length);
        extra = SpinPrize(slice, RunConfig.luckySpinSlices[slice]);
      case HoopKindId.saw:
        final options = SawDesign.values.where((d) => d != _lastSaw).toList();
        final d = options[r.nextInt(options.length)];
        _lastSaw = d;
        extra = d;
      case HoopKindId.switchRing:
        final options = SwitchDesign.values
            .where((d) => d != _lastSwitch)
            .toList();
        final d = options[r.nextInt(options.length)];
        _lastSwitch = d;
        extra = d;
        attached.add(_switchItem(trackX, y, ctx, d, prevY));
        _gapUsed.add(i - 1);
      case HoopKindId.portal:
        final ride =
            _forcedRide ??
            () {
              final options = RideId.values.where((x) => x != _lastRide).toList();
              return options[r.nextInt(options.length)];
            }();
        _forcedRide = null;
        _lastRide = ride;
        extra = ride;
        _portalAt = i + RunRandom.rangeInt(r, tables.portal.then.$1, tables.portal.then.$2);
        _lastPortal = i;
      default:
        break;
    }

    var tilt = 0.0;
    MotionSpec? motion;
    var cometHang = false;
    if (kind == HoopKindId.normal) {
      // 6. Comet hoop (fixed schedule; first-meet / debug pull it forward).
      if (_cometAllowed(i, ctx, mode: cometMode)) {
        cometHang = true;
        _cometAt = i + RunRandom.rangeInt(r, tables.comet.then.$1, tables.comet.then.$2);
        _lastComet = i;
        attached.add(
          GapItemPlan(
            kind: ElementId.comet,
            trackX: trackX + RunConfig.cometHang,
            y: y,
          ),
        );
        _count(ElementId.comet.storageId);
        firstMeet.markMet(ElementId.comet);
      } else {
        // 7. Modifiers (§3.0.2): tilt, then movement.
        if (_on(ElementId.angledRing)) {
          tilt = _layout.tilt(i, force: forceMod == ElementId.angledRing);
        }
        if (_on(ElementId.movingRing)) {
          motion = _layout.motion(
            i,
            ctx,
            y,
            opening,
            force: forceMod == ElementId.movingRing,
          );
          if (motion?.type == MotionType.swing) tilt = 0;
        }
        if (tilt != 0) {
          _count('tilted');
          firstMeet.markMet(ElementId.angledRing);
        }
        if (motion != null) {
          _count('moving');
          firstMeet.markMet(ElementId.movingRing);
        }
      }
    }

    if (kind != HoopKindId.normal) {
      _lastSpecial = i;
      _cdLeft = kind == HoopKindId.portal
          ? RunConfig.portalCooldown
          : tables.specials[kind]!.cooldown;
      _lastOf[kind] = i;
    }
    final element = kind.element;
    firstMeet.markMet(element);
    _count(element.storageId);
    _prevKind = kind;
    _nextX += advance;
    return SlotPlan(
      index: i,
      kind: kind,
      element: element,
      trackX: trackX,
      centreY: y,
      opening: opening,
      tiltDeg: tilt,
      motion: motion,
      cometHang: cometHang,
      ringOffsets: rings,
      advance: advance,
      extra: extra,
      forced: forced,
      attached: attached,
    );
  }

  bool _nearPortal(int i, int within) {
    if (!_portalOn) return false;
    return (i - _portalAt).abs() <= within || (i - _lastPortal) <= within;
  }

  /// §3.0.3 special-hoop eligibility (unlocked, far enough, allowed now).
  bool _specialAllowed(
    HoopKindId k,
    int i,
    DirectorContext ctx, {
    bool ignoreUnlock = false,
  }) {
    final rule = tables.specials[k];
    if (rule == null || !_on(k.element)) return false;
    if (!ignoreUnlock) {
      if (i < rule.from) return false;
      if (i - (_lastOf[k] ?? -99) < rule.minSince) return false;
    }
    if (ctx.squeezeWindow && !rule.allowedInSqueeze) return false;
    if (k == HoopKindId.fever &&
        (ctx.onFire || _prevKind == HoopKindId.saw)) {
      return false;
    }
    if (k == HoopKindId.saw && _prevKind == HoopKindId.fever) return false;
    if (rule.blockedNearPortal > 0 && _nearPortal(i, rule.blockedNearPortal)) {
      return false;
    }
    if (k == HoopKindId.switchRing && _gapUsed.contains(i - 1)) return false;
    return true;
  }

  /// §3.0.3 slot order 6: the comet star may hang in this normal hoop.
  /// [mode]: 0 = schedule, 1 = first-meet (ignores the schedule), 2 = debug
  /// (also ignores the portal distance; exclusivity still applies).
  bool _cometAllowed(int i, DirectorContext ctx, {int mode = 0}) {
    if (!_on(ElementId.comet)) return false;
    if (mode == 0 && i < _cometAt) return false;
    if (ctx.timedPowerupRunning || ctx.squeezeWindow || ctx.rideActive) {
      return false;
    }
    if (mode < 2 &&
        _portalOn &&
        (i - _lastPortal < RunConfig.cometPortalDistance ||
            _portalAt - i < RunConfig.cometPortalDistance)) {
      return false;
    }
    return true;
  }

  /// §3.21 two different gifts, filtered so none is useless.
  PairRewards _pairRewards(int i, DirectorContext ctx) {
    final w = <PairReward, int>{};
    for (final e in tables.pairWeights.entries) {
      final ok = switch (e.key) {
        PairReward.shield => !ctx.shieldArmed && _on(ElementId.shield),
        PairReward.fever => !ctx.onFire && _on(ElementId.fever),
        PairReward.comet =>
          _on(ElementId.comet) &&
              !ctx.timedPowerupRunning &&
              !_nearPortal(i, RunConfig.cometPortalDistance - 1),
        _ => true,
      };
      if (ok) w[e.key] = e.value;
    }
    final a = RunRandom.pickWeighted<PairReward>(rng.layout, w)!;
    w.remove(a);
    final b = RunRandom.pickWeighted<PairReward>(rng.layout, w)!;
    return PairRewards(a, b);
  }

  /// §3.20 the switch: 1.0 s × scroll (≥ 150 pt) before its ring, 70–100 pt
  /// above / below the ring centre, ≤ 110 pt from the previous hoop centre.
  GapItemPlan _switchItem(
    double ringX,
    double y,
    DirectorContext ctx,
    SwitchDesign design,
    double? prevY,
  ) {
    final r = rng.layout;
    final lead = max(
      RunConfig.switchLeadMin,
      RunConfig.switchLeadSeconds * ctx.scrollSpeed,
    );
    final lo = ctx.squeezeTopTooth + RunConfig.itemEdgeMargin;
    final hi = ctx.squeezeFloorTooth - RunConfig.itemEdgeMargin;
    final off =
        RunRandom.range(r, RunConfig.switchOffsetMin, RunConfig.switchOffsetMax) *
        (r.nextDouble() < 0.5 ? -1 : 1);
    double place(double o) => (y + o).clamp(lo, hi).toDouble();
    var sy = place(off);
    if ((sy - y).abs() < RunConfig.switchMinFromRing) sy = place(-off);
    if (prevY != null && (sy - prevY).abs() > RunConfig.switchMaxFromPrev) {
      final other = place(-off);
      if ((other - prevY).abs() < (sy - prevY).abs()) sy = other;
      sy = sy
          .clamp(
            prevY - RunConfig.switchMaxFromPrev,
            prevY + RunConfig.switchMaxFromPrev,
          )
          .clamp(lo, hi)
          .toDouble();
    }
    return GapItemPlan(
      kind: ElementId.switchRing,
      trackX: ringX - lead,
      y: sy,
      extra: design,
    );
  }

  // --- gaps -------------------------------------------------------------------

  /// §3.0.3 "order of decisions for the gap" after [slot].
  GapPlan nextGap(DirectorContext ctx, SlotPlan slot) {
    final g = slot.index;
    final r = rng.layout;
    if (ctx.rideActive ||
        _ride != null ||
        slot.duringRide ||
        slot.kind == HoopKindId.portal) {
      // Rides: no gap items (the portal ride clears the gap after it). The
      // heart moves on to the next gap; feather / piece wait (their
      // `at <= g` stays true).
      if (_heartAt <= g) _heartAt = g + 1;
      return GapPlan(index: g);
    }
    final items = <GapItemPlan>[];
    final mid = slot.lastRingX + spacing / 2;
    final nextX = slot.trackX + slot.advance;
    var used = _gapUsed.contains(g);
    void put(GapItemPlan p) {
      items.add(p);
      used = true;
      _gapUsed.add(g);
      _count(p.kind.storageId);
    }

    // 1. Running Piggy Bank / Firefly Jar fill the gap.
    if (ctx.piggyRunning) {
      if (!_piggyActive) {
        _piggyActive = true;
        _piggyGapsLeft = RunConfig.piggyFollowGaps;
      }
      if (_piggyGapsLeft > 0) {
        _piggyGapsLeft--;
        const half = (RunConfig.piggyCoinsPerGap - 1) * 45 / 2;
        put(
          GapItemPlan(
            kind: ElementId.piggyCoins,
            trackX: mid - half,
            toTrackX: mid + half,
            extra: RunConfig.piggyCoinsPerGap,
          ),
        );
      }
    } else {
      _piggyActive = false;
    }
    if (ctx.jarRunning && !used) {
      put(
        GapItemPlan(
          kind: ElementId.fireflySwarm,
          trackX: mid - 110,
          toTrackX: mid + 110,
          extra: RunConfig.fireflySwarm,
        ),
      );
    }

    // Debug force: the head gap element of the queue, ignoring unlock,
    // schedules and min distances (exclusivity still applies).
    final dbgIdx = _forced.indexWhere((e) => e.isGapElement);
    if (!used && dbgIdx >= 0) {
      final e = _forced[dbgIdx];
      final p = _forcedGapItem(e, g, ctx, slot, mid, nextX);
      if (p != null) {
        _forced.removeAt(dbgIdx);
        put(p);
      }
    }

    // 2. Fixed schedules: heart, feather, piece (taken gap → next free gap).
    if (!used && g >= _heartAt && _on(ElementId.heart)) {
      if (!ctx.extraLifeActive) put(_heart(g, ctx, mid));
      _heartAt = g + RunRandom.rangeInt(r, tables.heart.then.$1, tables.heart.then.$2);
    }
    // §3.17: in the squeeze window only scheduled hearts (and star trails)
    // spawn; the feather and the piece wait for the next free gap.
    final sq = ctx.squeezeWindow;
    if (!used &&
        !sq &&
        !_featherDone &&
        g >= _featherAt &&
        _on(ElementId.feather)) {
      _featherDone = true;
      if (ctx.featherWanted) put(_detour(ElementId.feather, slot, ctx, null));
    }
    if (!used &&
        !sq &&
        !_pieceDone &&
        g >= _pieceAt &&
        _on(ElementId.puzzlePiece)) {
      _pieceDone = true;
      final missing = [
        for (var b = 0; b < 4; b++)
          if (ctx.puzzleMask & (1 << b) == 0) b,
      ];
      if (missing.isNotEmpty) {
        final piece = missing[r.nextInt(missing.length)];
        put(_detour(ElementId.puzzlePiece, slot, ctx, piece));
      }
    }

    // 3. The switch of a switch ring in the next slot is decided with that
    // slot (it marks this gap as used then).

    // 4. Optional item: first-meet (never-met element, ignores the budget)
    // or the budget roll.
    if (!used) {
      final due = firstMeet.dueGap(g);
      ElementId? pick;
      CapsuleType? capsule;
      if (due != null && _gapAllowed(due, g, ctx)) {
        pick = due.isCapsuleType ? ElementId.capsule : due;
        if (due.isCapsuleType) {
          capsule = CapsuleType.values.firstWhere((c) => c.element == due);
        }
      } else if (r.nextDouble() < tables.budgetFor(g).gap) {
        final w = <ElementId, int>{};
        for (final e in tables.gapItems.entries) {
          if (_gapAllowed(e.key, g, ctx)) w[e.key] = e.value.weight;
        }
        pick = RunRandom.pickWeighted<ElementId>(r, w);
      }
      if (pick != null) {
        if (pick == ElementId.capsule && capsule == null) {
          final cw = <CapsuleType, int>{
            for (final e in tables.capsuleWeights.entries)
              if (_on(e.key.element)) e.key: e.value,
          };
          capsule = RunRandom.pickWeighted<CapsuleType>(r, cw);
        }
        final p = _optionalItem(pick, g, ctx, slot, mid, nextX, capsule);
        _lastGapOf[pick] = g;
        _runCount[pick] = (_runCount[pick] ?? 0) + 1;
        if (pick == ElementId.piggy ||
            pick == ElementId.jar ||
            pick == ElementId.egg) {
          _collectablePlannedAt = g;
        }
        put(p);
        firstMeet.markMet(pick);
        if (capsule != null) firstMeet.markMet(capsule.element);
      }
    }
    return GapPlan(index: g, items: items);
  }

  GapItemPlan _heart(int g, DirectorContext ctx, double mid) {
    final r = rng.layout;
    var offset = 0.0;
    if (_heartsPlaced > 0 && r.nextDouble() >= RunConfig.heartOnLineChance) {
      offset = _offLine(ctx);
    }
    _heartsPlaced++;
    return GapItemPlan(kind: ElementId.heart, trackX: mid, lineOffset: offset);
  }

  double _offLine(DirectorContext ctx) {
    final r = rng.layout;
    return RunRandom.range(r, RunConfig.offLineMin, RunConfig.offLineMax) *
        ctx.band *
        (r.nextDouble() < 0.5 ? -1 : 1);
  }

  /// §3.0.3 feather / piece: 0.65 × spacing after the hoop, 64–200 pt above.
  GapItemPlan _detour(
    ElementId kind,
    SlotPlan slot,
    DirectorContext ctx,
    Object? extra,
  ) {
    final r = rng.layout;
    final up = RunRandom.range(
      r,
      RunConfig.detourAboveMin,
      RunConfig.detourAboveMax,
    );
    final y = (slot.centreY - up)
        .clamp(
          ctx.squeezeTopTooth + RunConfig.itemEdgeMargin,
          ctx.squeezeFloorTooth - RunConfig.itemEdgeMargin,
        )
        .toDouble();
    return GapItemPlan(
      kind: kind,
      trackX: slot.lastRingX + RunConfig.detourAfter * spacing,
      y: y,
      extra: extra,
    );
  }

  /// §3.0.3 optional gap-item eligibility.
  bool _gapAllowed(
    ElementId k,
    int g,
    DirectorContext ctx, {
    bool ignoreUnlock = false,
  }) {
    final key = k.isCapsuleType ? ElementId.capsule : k;
    final rule = tables.gapItems[key];
    if (rule == null || !_on(key)) return false;
    if (k.isCapsuleType && !_on(k)) return false;
    if (key == ElementId.capsule &&
        !tables.capsuleWeights.keys.any((c) => _on(c.element))) {
      return false;
    }
    if (!ignoreUnlock) {
      if (g < rule.from) return false;
      if (g - (_lastGapOf[key] ?? -99) < rule.minSince) return false;
      final maxN = rule.maxPerRun;
      if (maxN != null) {
        final n = (_runCount[key] ?? 0) +
            (key == ElementId.shield ? ctx.shieldPickupsThisRun : 0);
        if (n >= maxN) return false;
      }
    }
    if (ctx.squeezeWindow && !rule.allowedInSqueeze) return false;
    switch (key) {
      case ElementId.capsule:
        if (ctx.timedPowerupRunning || ctx.rideActive) return false;
      case ElementId.egg:
        if (ctx.eggOrChick || g - _collectablePlannedAt < 3) return false;
      case ElementId.piggy:
      case ElementId.jar:
        if (ctx.piggyRunning || ctx.jarRunning) return false;
        if (g - _collectablePlannedAt < 3) return false;
      case ElementId.shield:
        if (ctx.shieldArmed) return false;
      default:
        break;
    }
    return true;
  }

  GapItemPlan _optionalItem(
    ElementId k,
    int g,
    DirectorContext ctx,
    SlotPlan slot,
    double mid,
    double nextX,
    CapsuleType? capsule,
  ) {
    switch (k) {
      case ElementId.starTrail:
        return GapItemPlan(
          kind: k,
          trackX: slot.lastRingX + RunConfig.starTrailInset,
          toTrackX: nextX - RunConfig.starTrailInset,
          extra: RunConfig.starTrailStars,
        );
      case ElementId.capsule:
        return GapItemPlan(kind: k, trackX: mid, extra: capsule);
      case ElementId.shield:
        return GapItemPlan(kind: k, trackX: mid, lineOffset: _offLine(ctx));
      default:
        return GapItemPlan(kind: k, trackX: mid);
    }
  }

  GapItemPlan? _forcedGapItem(
    ElementId e,
    int g,
    DirectorContext ctx,
    SlotPlan slot,
    double mid,
    double nextX,
  ) {
    switch (e) {
      case ElementId.heart:
        if (!_on(e) || ctx.extraLifeActive) return null;
        return _heart(g, ctx, mid);
      case ElementId.feather:
        if (!_on(e)) return null;
        _featherDone = true;
        return _detour(e, slot, ctx, null);
      case ElementId.puzzlePiece:
        if (!_on(e)) return null;
        _pieceDone = true;
        final missing = [
          for (var b = 0; b < 4; b++)
            if (ctx.puzzleMask & (1 << b) == 0) b,
        ];
        return _detour(
          e,
          slot,
          ctx,
          missing.isEmpty ? 0 : missing[rng.layout.nextInt(missing.length)],
        );
      default:
        if (!_gapAllowed(e, g, ctx, ignoreUnlock: true)) return null;
        final key = e.isCapsuleType ? ElementId.capsule : e;
        CapsuleType? capsule;
        if (e.isCapsuleType) {
          capsule = CapsuleType.values.firstWhere((c) => c.element == e);
        } else if (e == ElementId.capsule) {
          capsule = RunRandom.pickWeighted<CapsuleType>(rng.layout, {
            for (final x in tables.capsuleWeights.entries)
              if (_on(x.key.element)) x.key: x.value,
          });
        }
        _lastGapOf[key] = g;
        _runCount[key] = (_runCount[key] ?? 0) + 1;
        if (key == ElementId.piggy ||
            key == ElementId.jar ||
            key == ElementId.egg) {
          _collectablePlannedAt = g;
        }
        firstMeet.markMet(key);
        if (capsule != null) firstMeet.markMet(capsule.element);
        return _optionalItem(key, g, ctx, slot, mid, nextX, capsule);
    }
  }
}
