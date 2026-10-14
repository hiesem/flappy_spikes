import 'dart:math';

import '../config/director_tables.dart';
import '../config/run_config.dart';
import '../config/tuning_values.dart';
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
    DirectorTables? tables,
    required Set<ElementId> enabled,
    required Set<ElementId> met,
    int startHoopIndex = 0,
    RideId? lastPortalRide,
    List<ElementId> forced = const [],
    RideId? forcedRide,
    double firstTrackX = RunConfig.worldWidth + RunConfig.firstHoopOffscreen,
    this.fixedFirstHoop = false,
    this.spacing = RunConfig.spacing,
    bool featherAllowed = true,
    bool pieceAllowed = true,
    this.oneBigBonus = RunConfig.oneBigBonus,
  }) : tables = tables ?? DirectorTables.prd2,
       rng = RunRandom(seed),
       enabled = {...enabled},
       _i = startHoopIndex,
       _startIndex = startHoopIndex,
       _nextX = firstTrackX,
       _lastRide = lastPortalRide,
       _forcedRide = forcedRide,
       _forced = [...forced] {
    firstMeet = FirstMeet(met, this.enabled);
    final tables = this.tables;
    _layout = LayoutSampler(tables, rng.layout);
    final r = rng.layout;
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
    _heartAt = RunRandom.rangeInt(
      r,
      tables.heart.first.$1,
      tables.heart.first.$2,
    );
    // PRD-2.2 §19.3 the feather and the piece come in ≈ 60 % of runs each
    // (rolled at run start, on the timing stream so the course itself is
    // not shifted by the rolls).
    // PRD-2.3 §14.2 at most one per run, never in two runs in a row
    // ([featherAllowed] / [pieceAllowed]: `lastFeatherRun` /
    // `lastPieceRun`), and never together: if both roll, the feather wins
    // and the piece waits for a later run. (Both rolls always happen, so
    // the timing stream stays the same.)
    final featherRoll = rng.timing.nextDouble() < tables.featherChance;
    final pieceRoll = rng.timing.nextDouble() < tables.pieceChance;
    _featherOn = featherRoll && featherAllowed;
    _pieceOn = pieceRoll && pieceAllowed && !_featherOn;
    if (!_featherOn) _featherDone = true;
    if (!_pieceOn) _pieceDone = true;
    if (forcedRide != null && !_forced.contains(ElementId.portal)) {
      _forced.add(ElementId.portal);
    }
    // startHoopIndex (call, ARCH §2.2): schedules whose first window lies
    // before the start re-roll from the start; the once-per-run feather and
    // piece and the heart come at the start instead.
    final s = startHoopIndex;
    if (s > 0) {
      if (_portalAt < s) _portalAt = s + (_portalAt - tables.portal.first.$1);
      _heartAt = max(_heartAt, s);
      _featherAt = max(_featherAt, s);
      _pieceAt = max(_pieceAt, s);
    }
    // PRD-2.2 §19.3 never in the same or neighbouring gaps: the later one
    // moves 2 gaps on.
    if (_featherOn && _pieceOn && (_featherAt - _pieceAt).abs() <= 1) {
      if (_featherAt > _pieceAt) {
        _featherAt += 2;
      } else {
        _pieceAt += 2;
      }
    }
  }

  final DirectorTables tables;
  final RunRandom rng;
  final double spacing;

  /// PRD-2.3 §10.2 hoop 0 stands at its fixed easy spot (track x
  /// [RunConfig.hoop0X], y = middle + [RunConfig.hoop0DropY], opening 118,
  /// plain). The run controller sets it for every run that starts at hoop 0
  /// (not a `startHoopIndex` debug / e2e run); the caller passes
  /// `firstTrackX: RunConfig.hoop0X` with it.
  final bool fixedFirstHoop;

  /// PRD-2.3 §17.3 the one-big-bonus rule (off only for the §17.6 count
  /// baseline in tests).
  final bool oneBigBonus;

  /// Registered elements (hoop + pickup registries, features).
  final Set<ElementId> enabled;
  late final FirstMeet firstMeet;
  late final LayoutSampler _layout;

  int _i;
  double _nextX;

  /// The run's first slot (PRD-2.2 §15: no switch ring there).
  final int _startIndex;

  /// PRD-2.3 §14.5 a comet hoop that was planned but turned plain (an
  /// activity started, §27.3) is owed: it comes at the next allowed normal
  /// slot without a roll.
  bool _cometOwed = false;
  late int _portalAt;
  late int _heartAt;
  late int _featherAt;
  late int _pieceAt;
  bool _featherDone = false;
  bool _pieceDone = false;
  late final bool _featherOn;
  late final bool _pieceOn;

  /// PRD-2.2 §19.3 the gaps the feather / piece were placed in (null = not
  /// yet): the other one never lands in the same or a neighbouring gap.
  int? _featherGap;
  int? _pieceGap;

  /// PRD-2.2 §19.2 the early-pool draw per index (tests, debug overlay).
  final Map<int, EarlyPick> _earlyPicks = {};

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

  /// The last ride before [_lastRide] (a dropped portal restores it).
  RideId? _rideBefore;
  RideId? _forcedRide;
  SwitchDesign? _forcedSwitch;
  final List<ElementId> _forced;
  bool _revivePending = false;
  final Set<int> _gapUsed = {};
  bool _piggyActive = false;

  /// §3.28 bank coins the director still has to place in follow-up gaps
  /// (4 per gap). A portal clear refunds what it removed unjudged (S6-41).
  int _piggyOwed = 0;
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

  /// PRD-2.3 §14.5 the first hoop the next comet may hang in (chance-based
  /// from there; `ride_comet_from`, ≥ `ride_comet_spacing` after the last).
  int get cometAt => _cometOwed
      ? _i
      : max(tables.comet.from, _lastComet + tables.comet.spacing);
  int get heartAt => _heartAt;
  int get featherAt => _featherAt;
  int get pieceAt => _pieceAt;

  /// PRD-2.2 §19.3 the run-start rolls: does the feather / piece come?
  bool get featherThisRun => _featherOn;
  bool get pieceThisRun => _pieceOn;

  /// PRD-2.2 §19.2 the early-pool draws so far (index → pick).
  Map<int, EarlyPick> get earlyPicks => Map.unmodifiable(_earlyPicks);
  RideId? get lastRide => _lastRide;

  /// Spawned counts per kind / modifier / item storage id (analytics
  /// `run_director_hoops` / `run_director_items`).
  Map<String, int> get spawnedCounts => Map.unmodifiable(_spawned);

  bool _on(ElementId e) => enabled.contains(e);

  /// §3.6 the Big Hoops multiplier for slot [i]. PRD-2.3 §0 item 3: hoop 0
  /// always stays at 118 (§10.2 wins over §14.4), also with Big Hoops.
  double _bigMult(int i, DirectorContext ctx) => i == 0 ? 1 : ctx.bigHoopsMult;
  bool get _portalOn => _on(ElementId.portal);

  // region WP-A — at most N portal rides per run (PRD-2.3.1 §17)
  /// PRD-2.3.1 §17 portals placed this run (a portal turned plain or
  /// cleared before it was flown is owed again and does not count). A
  /// revive does not reset it.
  int _portalCount = 0;

  /// The schedule after the cap: never.
  static const int _noPortal = 1 << 30;

  /// PRD-2.3.1 §17 portals placed this run (tests).
  int get portalCount => _portalCount;

  /// PRD-2.3.1 §17 the run has its `ride_portal_max` portals (0 = no
  /// limit): the director plans no more.
  bool get portalCapped =>
      tables.portalMax > 0 && _portalCount >= tables.portalMax;
  // endregion WP-A

  /// §3.0.1 / PRD-2.3 §14.4 opening at [hoopIndex]: 118 at hoop 0, then
  /// `curve_opening` (88 → 66); ride 118.
  double openingFor(int hoopIndex, {required bool ride}) =>
      RunConfig.openingFor(hoopIndex, ride: ride);

  // --- timing-stream rolls (§3.0.3 "timing") --------------------------------

  /// §3.17 / PRD-2.3 §14.4 the next squeeze moment, counted in hoops: the
  /// first at a random hoop 25–40 ([first]: `squeeze_first`), the next
  /// 25–45 hoops after the previous one ended (`squeeze_gap`). The hoop
  /// count turns into runClock at the cruise of the hoops ahead
  /// ([RunConfig.secondsForHoops] from [hoop], the bird's hoop now).
  double rollSqueezeAt(double now, {required int hoop, bool first = false}) {
    final (a, b) = TuningValues.current.range(
      first ? 'squeeze_first' : 'squeeze_gap',
    );
    final n = RunRandom.rangeInt(rng.timing, a, b);
    return now + RunConfig.secondsForHoops(hoop, n);
  }

  /// §3.17 / PRD-2.3 §14.4 the hold: 5–10 hoops (`squeeze_hold`) from
  /// [hoop], in runClock seconds.
  double rollSqueezeHold({required int hoop}) {
    final (a, b) = TuningValues.current.range('squeeze_hold');
    final n = RunRandom.rangeInt(rng.timing, a, b);
    return RunConfig.secondsForHoops(hoop, n);
  }

  /// §3.6 Big Hoops D: 30..40 s.
  double rollBigHoopsDuration() =>
      RunRandom.range(rng.timing, RunConfig.bigHoopsMin, RunConfig.bigHoopsMax);

  /// §3.16 Puzzle bonus. PRD-2.3 §14.2: 50..150 step 5
  /// (`puzzle_reward`; was 50..250).
  int rollPuzzleBonus() {
    final min = RunConfig.puzzleBonusMin, step = RunConfig.puzzleBonusStep;
    final steps = (RunConfig.puzzleBonusMax - min) ~/ step;
    return min + step * rng.timing.nextInt(steps + 1);
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
    if (k == RideKind.comet) {
      _zigEndX = null;
      _zigSide = 0;
      // PRD-2.3.1 §16.1 C stations not planned by the end are dropped; the
      // next slot is the safe first hoop after the comet.
      _cometStations = null;
    }
  }

  // region WP-G3 — comet zigzag (PRD-2.2 §16)
  /// PRD-2.2 §16.1 the comet ride's predicted end: hoops whose plane lies
  /// at or before this track x are reached during the ride and zigzag;
  /// later ones get a normal height. Null outside a comet ride.
  double? _zigEndX;

  /// +1: the next zigzag hoop goes below the middle; −1: above; 0: off.
  int _zigSide = 0;
  double _zigAmp = 0;

  /// PRD-2.2 §16.1 a comet ride started (after [onRideStart]): [fromY] is
  /// the centre of the star's hoop (the bird's height for a pair's COMET
  /// gift), so the first zigzag hoop goes to the other side of the middle;
  /// [endTrackX] the bird's predicted track x when the ride (and its
  /// ease-out) ends; [amplitude] = `CometConfig.zigzagAmp`.
  ///
  /// PRD-2.3.1 §16.1 (2.3.1) the comet layout is locked here: the stretch
  /// from [anchorX] (the track x of the last hoop that stays: the star's
  /// hoop or the last visible hoop; default: the last planned slot) to
  /// `endTrackX − ride_comet_tail` is cut into `k = max(1, round(stretch /
  /// ride_comet_hoop_gap))` equal steps — one comet hoop at the end of each
  /// ([cometStations]). The slots planned next (and the not-yet-visible
  /// hoops the spawner re-places through [cometReplan]) take them in
  /// order; the slot after them is the first normal hoop, at ≥ the
  /// predicted end + `ride_comet_after_gap` ([cometAfterMin]).
  void onCometStart({
    required double fromY,
    required double endTrackX,
    required double viewHeight,
    required double amplitude,
    double? anchorX,
  }) {
    _zigEndX = endTrackX;
    _zigAmp = amplitude;
    _zigSide = fromY < viewHeight / 2 ? 1 : -1;
    // region WP-A — comet hoop layout (PRD-2.3.1 §16)
    final from = anchorX ?? _lastPlanX ?? _nextX - spacing;
    final last = endTrackX - RunConfig.cometTail;
    final stretch = last - from;
    final gap = RunConfig.cometHoopGap;
    final k = stretch <= 0 ? 0 : max(1, (stretch / gap).round());
    final stations = [for (var j = 1; j <= k; j++) from + stretch * j / k];
    _cometLayout = List.unmodifiable(stations);
    _cometLockedEnd = endTrackX;
    _cometStations = stations;
    _cometAfterMin = endTrackX + RunConfig.cometAfterGap;
    _nextX = stations.isNotEmpty ? stations.first : max(_nextX, _cometAfterMin!);
    // endregion WP-A
  }

  /// PRD-2.2 §16.2 the ride's end prediction, refreshed while it flies.
  /// PRD-2.3.1 §16.1 B the comet stations stay locked; only the first hoop
  /// after the ride follows the new end.
  void updateCometEnd(double endTrackX) {
    if (_zigEndX != null) _zigEndX = endTrackX;
    if (_cometAfterMin != null) {
      _cometAfterMin = endTrackX + RunConfig.cometAfterGap;
    }
  }

  // region WP-A — comet hoop layout (PRD-2.3.1 §16)
  /// PRD-2.3.1 §16.1 B the comet stations not planned yet (null: none).
  List<double>? _cometStations;

  /// PRD-2.3.1 §16.1 B every comet station locked at the comet's start.
  List<double> _cometLayout = const [];

  /// PRD-2.3.1 §16.1 C the first normal hoop after the comet goes at ≥
  /// this track x (predicted end + `ride_comet_after_gap`); null once it is
  /// planned.
  double? _cometAfterMin;

  /// The track x of the last slot planned ([nextSlot] / [cometReplan]).
  double? _lastPlanX;

  /// PRD-2.3.1 §16.1 B the comet stations of the current / last comet
  /// (tests, debug).
  List<double> get cometStations => _cometLayout;

  double? _cometLockedEnd;

  /// PRD-2.3.1 §16.1 B the predicted end the layout was locked with (tests).
  double? get cometLockedEnd => _cometLockedEnd;

  /// PRD-2.3.1 §16.1 C the minimum track x of the first hoop after the
  /// comet (null when it is planned, or no comet ran).
  double? get cometAfterMin => _cometAfterMin;

  /// PRD-2.3.1 §16.1: takes the next comet position: a station (true) or
  /// the safe first hoop after the comet (false); null outside the layout.
  /// Sets [_nextX] to it (the caller adds the slot's advance).
  (double, bool)? _takeCometX() {
    final after = _cometAfterMin;
    if (after == null) return null;
    final st = _cometStations;
    if (st != null && st.isNotEmpty) {
      final x = st.removeAt(0);
      _nextX = x;
      return (x, true);
    }
    final x = max(_nextX, after);
    _cometStations = null;
    _cometAfterMin = null;
    _nextX = x;
    return (x, false);
  }

  /// PRD-2.3.1 §16.1 B / C the advance after the comet station at [x]: to
  /// the next station, or to the safe first hoop after the comet.
  double _stationAdvance(double x) {
    final st = _cometStations;
    if (st != null && st.isNotEmpty) return st.first - x;
    return max(x + spacing, _cometAfterMin ?? x + spacing) - x;
  }

  /// PRD-2.3.1 §16.1 A a hoop (spawned off-screen) or the planned-ahead
  /// slot [p], not yet visible when a comet starts, moves into the comet
  /// layout: the next comet station at the zigzag height (or, past the
  /// stations, the safe first hoop after the comet at a normal height), a
  /// plain ride hoop (full size, upright, still, nothing attached). Null
  /// outside a comet layout.
  SlotPlan? cometReplan(SlotPlan p, DirectorContext ctx) {
    if (_cometAfterMin == null) return null;
    final plain = plainSlot(p, ctx, ride: true);
    final (x, station) = _takeCometX()!;
    _lastPlanX = x;
    final y = station
        ? _zigzagY(x, p.index, ctx, plain.opening, station: true)
        : null;
    final advance = station ? _stationAdvance(x) : spacing;
    _nextX = x + advance;
    return plain.copyWith(
      trackX: x,
      centreY: y ?? plain.centreY,
      advance: advance,
    );
  }
  // endregion WP-A

  /// The predicted end of the running comet ride (tests).
  double? get cometEndTrackX => _zigEndX;

  /// PRD-2.2 §16.1 the zigzag centre for a ride slot at [trackX], or null
  /// (no comet ride, or the hoop is reached after the ride ends).
  double? _zigzagY(
    double trackX,
    int i,
    DirectorContext ctx,
    double opening, {
    bool station = false,
  }) {
    final end = _zigEndX;
    if (end == null || _zigSide == 0 || (!station && trackX > end)) {
      return null;
    }
    final (lo, hi) = _layout.limits(i, ctx, opening, useTable: false);
    final y = (ctx.viewHeight / 2 + _zigSide * _zigAmp)
        .clamp(lo, hi)
        .toDouble();
    _layout
      ..lastSign = _zigSide.toDouble()
      ..lastY = y;
    _zigSide = -_zigSide;
    return y;
  }
  // endregion WP-G3

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

  /// §3.0.8 debug / shots: the next switch ring takes [design] (the layout
  /// draw still happens, so the course stays the same).
  void debugForceSwitchDesign(SwitchDesign design) => _forcedSwitch = design;

  // region WP-3b — portal rides (PRD-2 §3.12)
  /// §3.12 normal hoops resume after a portal ride: the next slot's plane
  /// moves to [trackX] (the course jumped while the ride flew).
  void resumeAt(double trackX) => _nextX = trackX;
  // endregion WP-3b

  /// §3.0.8 the element was met (spawned on screen).
  void markMet(ElementId e) => firstMeet.markMet(e);

  void _count(String key) => _spawned[key] = (_spawned[key] ?? 0) + 1;

  // --- slots ------------------------------------------------------------------

  /// §3.0.3 "order of decisions for a hoop slot".
  SlotPlan nextSlot(DirectorContext ctx) {
    final i = _i++;
    // PRD-2.3.1 §16.1 a comet's locked stations, then the safe first hoop
    // after it (both move [_nextX] on).
    final comet = _takeCometX();
    final cometStation = comet?.$2 ?? false;
    final trackX = _nextX;
    _lastPlanX = trackX;
    final ride = ctx.rideActive || _ride != null;
    final band = ctx.band;

    double cap(double opening, [double extra = 0]) => min(
      opening,
      band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin + extra),
    );

    // PRD-2.3 §10.2 hoop 0 of a run: plain (no special kind, no motion, no
    // tilt, nothing attached), opening 118 (also with Big Hoops, §0 item 3),
    // centre 16 pt below the middle. Debug-forced slot elements wait for
    // hoop 1.
    if (fixedFirstHoop && i == 0 && _startIndex == 0) {
      final y = ctx.viewHeight / 2 + RunConfig.hoop0DropY;
      _layout.lastY = y;
      _prevKind = HoopKindId.normal;
      _count(ElementId.normalHoop.storageId);
      _nextX += spacing;
      return SlotPlan(
        index: i,
        kind: HoopKindId.normal,
        element: ElementId.normalHoop,
        trackX: trackX,
        centreY: y,
        opening: RunConfig.opening0,
        advance: spacing,
      );
    }

    // 1. Ride active: normal, full size, upright, still; no items.
    // 2. First slot after a revive: normal (call: plain — upright, still).
    if (ride || _revivePending) {
      _revivePending = false;
      final opening = cap(openingFor(i, ride: ride) * _bigMult(i, ctx));
      // PRD-2.2 §16.1 comet ride hoops zigzag ±70 pt around the middle
      // (the normal draw still happens, so the course after the ride keeps
      // its random stream).
      final normal = _layout.nextCentre(i, ctx, opening);
      // PRD-2.3.1 §16.1 only the comet stations zigzag; the first hoop
      // after the comet (and any later ride slot) has a normal height.
      final y =
          (cometStation
              ? _zigzagY(trackX, i, ctx, opening, station: true)
              : null) ??
          normal;
      _prevKind = HoopKindId.normal;
      _count(ElementId.normalHoop.storageId);
      // Owner 2026-10-14 (2.3.0 (19)) / PRD-2.3.1 §16.1 B: during a comet
      // the next hoop is the next locked station (≈ `ride_comet_hoop_gap`
      // ahead), then the safe first hoop after the comet (≥ end +
      // `ride_comet_after_gap`); otherwise the normal spacing.
      final advance = cometStation ? _stationAdvance(trackX) : spacing;
      _nextX += advance;
      return SlotPlan(
        index: i,
        kind: HoopKindId.normal,
        element: ElementId.normalHoop,
        trackX: trackX,
        centreY: y,
        opening: opening,
        advance: advance,
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
        ok =
            _on(e) &&
            !ctx.squeezeWindow &&
            !_rewardsBlocked(i, ctx) &&
            !_bigOpen(ctx);
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

    // PRD-2.2 §19.2 the early random pool: one equal-chance draw per index
    // 4–9 (replaces the special roll and the optional gap roll there).
    final pool = tables.earlyPool;
    EarlyPick? early;
    if (pool != null && pool.covers(i)) {
      early = RunRandom.pickWeighted<EarlyPick>(rng.layout, pool.weights);
      if (early != null) _earlyPicks[i] = early;
      // §27.2 the early pool waits during an activity (its rewards).
      if (early == EarlyPick.starTrail && _rewardsBlocked(i, ctx, gap: true)) {
        // PRD-2.3 §17.3 rule 4 (S8-11): with the one-big-bonus rule the pick
        // is kept for the gap, which makes it wait ([_drawWhileBlocked]).
        if (!oneBigBonus) _earlyPicks.remove(i);
        early = null;
      }
    }

    // 3. Portal (fixed schedule; first-meet pulls it forward). PRD-2.2
    // §27.2: during an activity and its cool-down it waits.
    // PRD-2.3 §17.3 rules 1 / 4: while a big bonus is open it waits too
    // (the "stays due" path of `_portalAt`).
    // PRD-2.3.1 §17 skipped once the run has its `ride_portal_max` portals.
    if (kind == null && !forced && _portalOn && !portalCapped) {
      if (!_rewardsBlocked(i, ctx) && !_bigOpen(ctx)) {
        if (due == ElementId.portal) _portalAt = min(_portalAt, i);
        if (i >= _portalAt &&
            !ctx.squeezeWindow &&
            i - _lastComet >= RunConfig.cometPortalDistance) {
          kind = HoopKindId.portal;
          forced = due == ElementId.portal;
        }
      } else if (oneBigBonus && i >= _portalAt) {
        _portalWaiting = true;
      }
    }

    // 4. Cooldown. 5. Special roll (first-meet replaces the roll).
    final cooling = i - _lastSpecial <= _cdLeft;
    if (kind == null && !forced && !cooling) {
      final dueSpecial = due == null ? null : HoopKindId.specialFor(due);
      final waiting = _waitRing;
      if (waiting != null && _specialAllowed(waiting, i, ctx)) {
        // PRD-2.3 §17.3 rule 4 the waiting reward ring comes first.
        kind = waiting;
        _waitRing = null;
      } else if (dueSpecial != null && _specialAllowed(dueSpecial, i, ctx)) {
        kind = dueSpecial;
        forced = true;
      } else if (early != null) {
        // PRD-2.2 §19.2 Bullseye may come from index 4 here (its usual
        // min distance still holds).
        if (early == EarlyPick.bullseye &&
            _specialAllowed(HoopKindId.bullseye, i, ctx, ignoreFrom: true)) {
          kind = HoopKindId.bullseye;
        }
      } else {
        final budget = tables.budgetFor(i).special;
        if (rng.layout.nextDouble() < budget) {
          final w = <HoopKindId, int>{};
          for (final e in tables.specials.entries) {
            // PRD-2.3 §17.3 rule 4: a reward ring that only rule 1 or the
            // cool-down blocks stays in the draw (and waits if drawn).
            if (_specialAllowed(e.key, i, ctx) ||
                (oneBigBonus &&
                    rewardKinds.contains(e.key) &&
                    _specialAllowed(e.key, i, ctx, ignoreBig: true))) {
              w[e.key] = e.value.weightAt(i);
            }
          }
          kind = RunRandom.pickWeighted<HoopKindId>(rng.layout, w);
          if (oneBigBonus && kind != null && rewardKinds.contains(kind)) {
            final blocked = !_specialAllowed(kind, i, ctx);
            if (blocked || _bonusWaits) {
              // A blocked ring waits (if none waits yet); the slot is drawn
              // again from the non-big elements, so the course keeps its
              // density (as when blocked rings were not in the draw).
              if (blocked && !_bonusWaits) _waitRing = kind;
              w.removeWhere((k, _) => rewardKinds.contains(k));
              kind = RunRandom.pickWeighted<HoopKindId>(rng.layout, w);
            }
          }
        }
      }
    }
    if (!forced && due == ElementId.comet) cometMode = 1;
    if (!forced &&
        (due == ElementId.angledRing || due == ElementId.movingRing)) {
      forceMod = due;
    }
    // PRD-2.2 §19.2 the angled ring may come from index 4 here.
    if (early == EarlyPick.angled && kind == null && forceMod == null) {
      forceMod = ElementId.angledRing;
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
    // PRD-2.2 §25.1 the portal ring stays a big, easy 118 pt entrance at
    // every hoop (it took the shrinking normal opening before).
    // (`RunConfig.portalOpening` == `PortalConfig.ringOpening`; the director
    // stays free of Flame imports.)
    if (kind == HoopKindId.portal) opening = RunConfig.portalOpening;
    final pairO =
        RunConfig.pairOffsetAt711 * ctx.viewHeight / RunConfig.designHeight;
    if (kind == HoopKindId.pair) extraMargin = pairO / 2;
    // PRD-2.3 §0 item 3 / §10.2: hoop 0 stays 118, also with Big Hoops.
    opening = cap(opening * _bigMult(i, ctx), extraMargin);
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
      final minY =
          ctx.hudBottom + pairO / 2 + opening / 2 + RunConfig.rimRadius;
      final (lo, hi) = _layout.limits(
        i,
        ctx,
        opening,
        extra: extraMargin,
        useTable: false,
      );
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
        final slices = RunConfig.luckySpinSlices;
        final slice = r.nextInt(slices.length);
        extra = SpinPrize(slice, slices[slice]);
      case HoopKindId.saw:
        final options = SawDesign.values.where((d) => d != _lastSaw).toList();
        final d = options[r.nextInt(options.length)];
        _lastSaw = d;
        extra = d;
      case HoopKindId.switchRing:
        final options = SwitchDesign.values
            .where((d) => d != _lastSwitch)
            .toList();
        final picked = options[r.nextInt(options.length)];
        final d = _forcedSwitch ?? picked;
        _forcedSwitch = null;
        _lastSwitch = d;
        extra = d;
        final (lo0, hi0) = _layout.limits(i, ctx, opening, useTable: false);
        final fit = _switchItem(
          trackX,
          y,
          ctx,
          d,
          prevY,
          ringLo: lo0,
          ringHi: hi0,
          maxJump: maxJump,
        );
        if (fit == null) {
          // No ring height inside the band leaves a switch spot that obeys
          // both §3.20 rules → a normal hoop (like pair / spring).
          kind = HoopKindId.normal;
          forced = false;
          extra = null;
        } else {
          if (fit.$1 != y) {
            y = fit.$1;
            _layout.lastY = y;
          }
          attached.add(fit.$2);
          _gapUsed.add(i - 1);
        }
      case HoopKindId.portal:
        final ride =
            _forcedRide ??
            () {
              final options = RideId.values
                  .where((x) => x != _lastRide)
                  .toList();
              return options[r.nextInt(options.length)];
            }();
        _forcedRide = null;
        _rideBefore = _lastRide;
        _lastRide = ride;
        extra = ride;
        _portalAt =
            i +
            RunRandom.rangeInt(r, tables.portal.then.$1, tables.portal.then.$2);
        _lastPortal = i;
        _portalWaiting = false;
        // PRD-2.3.1 §17 every placed portal counts (debug-forced and
        // first-meet ones too); at the cap the schedule stops.
        _portalCount++;
        if (portalCapped) _portalAt = _noPortal;
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
        _cometOwed = false;
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
    bool ignoreFrom = false,
    bool ignoreBig = false,
  }) {
    final rule = tables.specials[k];
    if (rule == null || !_on(k.element)) return false;
    if (!ignoreUnlock) {
      if (!ignoreFrom && i < rule.from) return false;
      if (i - (_lastOf[k] ?? -99) < rule.minSince) return false;
    }
    // PRD-2.2 §27.2 reward rings wait for the activity + cool-down.
    // PRD-2.3 §17.3 rule 1 and while one waits ([ignoreBig]: the draw of
    // rule 4 asks whether only these block it).
    if (rewardKinds.contains(k) &&
        !ignoreBig &&
        (_rewardsBlocked(i, ctx) || _bigOpen(ctx))) {
      return false;
    }
    if (ctx.squeezeWindow && !rule.allowedInSqueeze) return false;
    if (k == HoopKindId.fever && (ctx.fever || _prevKind == HoopKindId.saw)) {
      return false;
    }
    if (k == HoopKindId.saw && _prevKind == HoopKindId.fever) return false;
    if (rule.blockedNearPortal > 0 && _nearPortal(i, rule.blockedNearPortal)) {
      return false;
    }
    if (k == HoopKindId.switchRing && _gapUsed.contains(i - 1)) return false;
    // PRD-2.2 §15 the run's first hoop scrolls in from 60 pt past the edge:
    // its switch (1 s before the ring) would already be inside the screen.
    if (k == HoopKindId.switchRing && i == _startIndex) return false;
    return true;
  }

  /// §3.0.3 slot order 6: the comet star may hang in this normal hoop.
  /// [mode]: 0 = the PRD-2.3 §14.5 roll (from `ride_comet_from`, ≥
  /// `ride_comet_spacing` hoops after the previous comet, then a
  /// `ride_comet_chance` roll on the layout stream — only for an otherwise
  /// eligible hoop; an owed comet skips the roll), 1 = first-meet (ignores
  /// the roll), 2 = debug (also ignores the portal distance; exclusivity
  /// still applies).
  bool _cometAllowed(int i, DirectorContext ctx, {int mode = 0}) {
    if (!_on(ElementId.comet)) return false;
    // PRD-2.2 §27.2 the comet hoop waits for the activity + cool-down.
    if (_rewardsBlocked(i, ctx)) return false;
    final rule = tables.comet;
    if (mode == 0 && (i < rule.from || i - _lastComet < rule.spacing)) {
      return false;
    }
    if (ctx.timedPowerupRunning || ctx.squeezeWindow || ctx.rideActive) {
      return false;
    }
    if (mode < 2 &&
        _portalOn &&
        (i - _lastPortal < RunConfig.cometPortalDistance ||
            _portalAt - i < RunConfig.cometPortalDistance)) {
      return false;
    }
    if (mode == 0 && !_cometOwed && rng.layout.nextDouble() >= rule.chance) {
      return false;
    }
    // PRD-2.3 §17.3 (after the roll, so the course stream stays the same):
    // rule 1 — a comet drawn while a big bonus is open waits (owed, rule 4)
    // unless another bonus waits already; rule 4 — while another waits no
    // new comet is drawn.
    if (_bigOpen(ctx)) {
      if (mode == 0 && !_bonusWaits) {
        _cometOwed = true;
        _lastComet = -99;
      }
      return false;
    }
    if (mode == 0 && oneBigBonus && !_cometOwed && _bonusWaits) return false;
    return true;
  }

  /// §3.21 two different gifts, filtered so none is useless.
  PairRewards _pairRewards(int i, DirectorContext ctx) {
    final w = <PairReward, int>{};
    for (final e in tables.pairWeights.entries) {
      final ok = switch (e.key) {
        PairReward.shield => !ctx.shieldArmed && _on(ElementId.shield),
        PairReward.fever => !ctx.fever && _on(ElementId.fever),
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
  /// above / below the ring centre, ≤ 110 pt from the previous hoop centre
  /// and inside the item margins. Both rules always hold (S6-45): when no
  /// switch spot fits the ring at [y], the ring moves to the nearest height
  /// in [ringLo, ringHi] (and within [maxJump] of the previous hoop) that
  /// leaves one. Returns the ring centre and the switch, or null when no
  /// ring height fits.
  (double, GapItemPlan)? _switchItem(
    double ringX,
    double y,
    DirectorContext ctx,
    SwitchDesign design,
    double? prevY, {
    required double ringLo,
    required double ringHi,
    required double maxJump,
  }) {
    final r = rng.layout;
    final lead = max(
      RunConfig.switchLeadMin,
      RunConfig.switchLeadSeconds * ctx.scrollSpeed,
    );
    final lo = ctx.squeezeTopTooth + RunConfig.itemEdgeMargin;
    final hi = ctx.squeezeFloorTooth - RunConfig.itemEdgeMargin;
    final mag = RunRandom.range(
      r,
      RunConfig.switchOffsetMin,
      RunConfig.switchOffsetMax,
    );
    final side = r.nextDouble() < 0.5 ? -1 : 1;

    /// The switch y for a ring at [ry] (preferred side first), or null.
    double? place(double ry) {
      for (final sd in [side, -side]) {
        var a = ry + sd * RunConfig.switchOffsetMin;
        var b = ry + sd * RunConfig.switchOffsetMax;
        if (a > b) (a, b) = (b, a);
        a = max(a, lo);
        b = min(b, hi);
        if (prevY != null) {
          a = max(a, prevY - RunConfig.switchMaxFromPrev);
          b = min(b, prevY + RunConfig.switchMaxFromPrev);
        }
        if (a <= b) return (ry + sd * mag).clamp(a, b).toDouble();
      }
      return null;
    }

    var ringY = y;
    var sy = place(y);
    if (sy == null) {
      // Nearest ring height (1 pt steps) that leaves a switch spot.
      final reach = max((y - ringLo).abs(), (ringHi - y).abs()).ceil();
      for (var k = 1; k <= reach && sy == null; k++) {
        for (final cand in [y - k, y + k]) {
          if (cand < ringLo || cand > ringHi) continue;
          if (prevY != null && (cand - prevY).abs() > maxJump) continue;
          sy = place(cand);
          if (sy != null) {
            ringY = cand;
            break;
          }
        }
      }
    }
    if (sy == null) return null;
    return (
      ringY,
      GapItemPlan(
        kind: ElementId.switchRing,
        trackX: ringX - lead,
        y: sy,
        extra: design,
      ),
    );
  }

  // region WP-G2 — one bonus at a time (PRD-2.2 §27), plan one ahead (§15)
  /// PRD-2.2 §27.2 the reward rings: pair, Lucky Spin, FEVER, portal (the
  /// comet-star hoop is a normal slot with `cometHang`).
  static const Set<HoopKindId> rewardKinds = {
    HoopKindId.pair,
    HoopKindId.luckySpin,
    HoopKindId.fever,
    HoopKindId.portal,
  };

  /// PRD-2.2 §27.2 the reward items (pickups) of the table.
  static bool isRewardItem(ElementId e) => switch (e) {
    ElementId.heart ||
    ElementId.shield ||
    ElementId.feather ||
    ElementId.puzzlePiece ||
    ElementId.egg ||
    ElementId.capsule ||
    ElementId.hourglass ||
    ElementId.miniBird ||
    ElementId.coinFrenzy ||
    ElementId.starTrail ||
    ElementId.piggy ||
    ElementId.jar ||
    ElementId.comet => true,
    _ => false,
  };

  /// A reward slot (§27.2): a reward ring or the comet-star hoop.
  static bool isRewardSlot(SlotPlan p) =>
      rewardKinds.contains(p.kind) || p.cometHang;

  // region WP-BONUS — one big bonus on screen (PRD-2.3 §17)
  /// PRD-2.3 §17.2 the big items: Piggy Bank, Firefly Jar, comet star, Egg,
  /// the capsules (Hourglass, Mini Bird, Coin Frenzy) and Star Trail. (The
  /// big rings are [rewardKinds]: pair, Lucky Spin, FEVER and the portal.)
  static bool isBigItem(ElementId e) => switch (e) {
    ElementId.piggy ||
    ElementId.jar ||
    ElementId.comet ||
    ElementId.egg ||
    ElementId.capsule ||
    ElementId.hourglass ||
    ElementId.miniBird ||
    ElementId.coinFrenzy ||
    ElementId.starTrail => true,
    _ => false,
  };

  /// PRD-2.3 §17.2 a slot that is (or carries) a big bonus.
  static bool isBigSlot(SlotPlan p) =>
      isRewardSlot(p) || p.attached.any((a) => isBigItem(a.kind));

  /// PRD-2.3 §17.3 rule 4 the one waiting big bonus drawn while blocked: a
  /// reward ring ([_waitRing]) or a big gap item ([_waitItem]). A due
  /// portal ([_portalWaiting]) or an owed comet follows the "stays due"
  /// path and counts as waiting too.
  HoopKindId? _waitRing;
  ElementId? _waitItem;
  bool _portalWaiting = false;

  /// The waiting reward ring / big item (tests, debug overlay).
  HoopKindId? get waitingRing => _waitRing;
  ElementId? get waitingItem => _waitItem;

  /// A big bonus waits (rule 4: at most one; further big draws fall back to
  /// the non-big elements).
  bool get bonusWaits => _bonusWaits;
  bool get _bonusWaits =>
      _waitRing != null || _waitItem != null || _portalWaiting || _cometOwed;

  /// PRD-2.3 §17.3 rule 1: a big bonus is open, so no other is planned.
  bool _bigOpen(DirectorContext ctx) => oneBigBonus && ctx.bigBonusOpen;
  // endregion WP-BONUS

  /// PRD-2.2 §27.2 no reward item at [index] while an activity runs and for
  /// [RunConfig.activityCooldownHoops] hoops after it. The planner works
  /// one slot ahead of the screen (§15), so at the end the next slot to be
  /// planned (n) still has hoop n − 1 between it and the bird: a reward
  /// ring may come from slot n + 1, a gap item from gap n (both with ≥ 2
  /// hoops between the bird and the reward when it ended).
  bool _rewardsBlocked(int index, DirectorContext ctx, {bool gap = false}) {
    if (ctx.activity) return true;
    final from =
        ctx.activityEndedAtSlot +
        RunConfig.activityCooldownHoops -
        (gap ? 2 : 1);
    return index < from;
  }

  /// PRD-2.2 §15 / §27: [p] (the planned-ahead slot, not spawned yet) as a
  /// plain normal hoop — upright, still, no gifts, one ring — at the same
  /// place: after a revive (§3.0.3 slot order 2), when a ride started
  /// meanwhile ([ride]: full size, §3.0.1) or when an activity started
  /// (its reward ring / comet star goes, §27.3). A portal or comet hoop
  /// that never showed stays due: it comes at the first allowed slot.
  ///
  /// [keepGeometry] (PRD-2.2 §16.1, S7-12): a comet ride started after the
  /// slot was planned. The slot is already planned, so it keeps its height,
  /// tilt and motion; only what §27 removes (the reward / special kind,
  /// gifts, attached items, the comet star) goes. Like every ride hoop it
  /// is full size (§3.0.1), the height clamped into the band only if the
  /// larger opening needs it.
  SlotPlan plainSlot(
    SlotPlan p,
    DirectorContext ctx, {
    bool ride = false,
    bool keepGeometry = false,
  }) {
    if (p.kind == HoopKindId.portal) {
      _portalCount = max(0, _portalCount - 1); // PRD-2.3.1 §17 owed again
      _portalAt = p.index;
      _lastPortal = -99;
      if (oneBigBonus) _portalWaiting = true;
      _forcedRide ??= p.extra is RideId ? p.extra! as RideId : null;
    }
    if (p.cometHang) {
      _cometOwed = true;
      _lastComet = -99;
    }
    final band = ctx.band;
    final opening = min(
      openingFor(p.index, ride: ride) * _bigMult(p.index, ctx),
      band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin),
    );
    final m = opening / 2 + RunConfig.rimRadius + RunConfig.bandMargin;
    final lo = ctx.topTooth + m, hi = ctx.floorTooth - m;
    final y = lo <= hi ? p.centreY.clamp(lo, hi).toDouble() : p.centreY;
    void uncount(String k) => _spawned[k] = max(0, (_spawned[k] ?? 1) - 1);
    uncount(p.element.storageId);
    if (!keepGeometry) {
      if (p.tiltDeg != 0) uncount('tilted');
      if (p.motion != null) uncount('moving');
    }
    if (p.cometHang) uncount(ElementId.comet.storageId);
    _count(ElementId.normalHoop.storageId);
    if (_prevKind == p.kind) _prevKind = HoopKindId.normal;
    return p.copyWith(
      kind: HoopKindId.normal,
      element: ElementId.normalHoop,
      centreY: y,
      opening: opening,
      tiltDeg: keepGeometry ? p.tiltDeg : 0,
      motion: () => keepGeometry ? p.motion : null,
      cometHang: false,
      ringOffsets: const [0],
      extra: () => null,
      forced: false,
      attached: const [],
      duringRide: ride,
    );
  }

  /// §3.0.3 slot order 2: true once if a revive is still waiting for its
  /// plain slot (the spawner then turns its planned-ahead slot plain).
  bool takeRevivePending() {
    final v = _revivePending;
    _revivePending = false;
    return v;
  }

  /// PRD-2.3 §17.5 a comet star still off-screen was cleared by an
  /// activity: it is owed (§14.5) and comes at the next allowed slot.
  void oweComet() {
    _cometOwed = true;
    _lastComet = -99;
  }

  /// PRD-2.3 §17.5 a portal hoop still off-screen was cleared by an
  /// activity: like a planned-ahead portal ([plainSlot]) it stays due with
  /// the same ride.
  void oweSlot(SlotPlan p) {
    if (p.kind != HoopKindId.portal) return;
    _portalCount = max(0, _portalCount - 1); // PRD-2.3.1 §17 owed again
    _portalAt = min(_portalAt, _i);
    _lastPortal = -99;
    _forcedRide ??= p.extra is RideId ? p.extra! as RideId : null;
    if (oneBigBonus) _portalWaiting = true;
  }

  /// PRD-2.2 §27.3 a golden feather ahead was cleared by an activity: it
  /// keeps its "once this run" and is placed again after the activity +
  /// cool-down.
  void oweFeather() {
    _featherDone = false;
    _featherGap = null;
    _featherAt = min(_featherAt, _i);
  }

  /// PRD-2.2 §27.3 the same for the puzzle piece.
  void owePiece() {
    _pieceDone = false;
    _pieceGap = null;
    _pieceAt = min(_pieceAt, _i);
  }

  /// PRD-2.2 §19.4 a single pickup at a random point 30–70 % along the gap
  /// after [slot], up to ±50 pt off the straight line (the spawner keeps it
  /// `itemEdgeMargin` inside the teeth).
  GapItemPlan _single(ElementId kind, SlotPlan slot, {Object? extra}) {
    final r = rng.layout;
    final u = RunRandom.range(
      r,
      RunConfig.singleAlongMin,
      RunConfig.singleAlongMax,
    );
    final off = RunRandom.range(
      r,
      -RunConfig.singleOffLine,
      RunConfig.singleOffLine,
    );
    return GapItemPlan(
      kind: kind,
      trackX: slot.lastRingX + u * spacing,
      lineOffset: off,
      extra: extra,
    );
  }

  /// PRD-2.2 §19.4 a pattern [span] pt long keeps its shape; its start
  /// moves randomly inside the gap (keeping `patternInset` from the rings).
  /// Returns the pattern's centre x.
  double _patternMid(SlotPlan slot, double span) {
    final room = spacing - 2 * RunConfig.patternInset - span;
    final mid = slot.lastRingX + spacing / 2;
    if (room <= 0) return mid;
    return mid + RunRandom.range(rng.layout, -room / 2, room / 2);
  }
  // endregion WP-G2

  /// §3.28 / §3.29 the running Piggy Bank / Firefly Jar fill the gap after
  /// [slot]. §3.17: in the squeeze window their fields wait (S6-46); the
  /// bank keeps what it still owes and places it once the squeeze has
  /// reopened. PRD-2.2 §19.4: the patterns keep their shape, their start
  /// moves inside the gap.
  List<GapItemPlan> _activityItems(
    DirectorContext ctx,
    SlotPlan slot, {
    required bool used,
  }) {
    final out = <GapItemPlan>[];
    final sq = ctx.squeezeWindow;
    if (ctx.piggyRunning) {
      if (!_piggyActive) {
        _piggyActive = true;
        _piggyOwed = RunConfig.piggyFollowGaps * RunConfig.piggyCoinsPerGap;
      }
      if (_piggyOwed > 0 && !sq) {
        final n = min(RunConfig.piggyCoinsPerGap, _piggyOwed);
        _piggyOwed -= n;
        final half = (n - 1) * RunConfig.piggyCoinSpacing / 2;
        final at = _patternMid(slot, 2 * half);
        out.add(
          GapItemPlan(
            kind: ElementId.piggyCoins,
            trackX: at - half,
            toTrackX: at + half,
            extra: n,
          ),
        );
      }
    } else {
      _piggyActive = false;
      _piggyOwed = 0;
    }
    if (ctx.jarRunning && !used && out.isEmpty && !sq) {
      final at = _patternMid(slot, 2 * RunConfig.fireflyHalfSpan);
      out.add(
        GapItemPlan(
          kind: ElementId.fireflySwarm,
          trackX: at - RunConfig.fireflyHalfSpan,
          toTrackX: at + RunConfig.fireflyHalfSpan,
          extra: RunConfig.fireflySwarm,
        ),
      );
    }
    return out;
  }

  /// PRD-2.2 §15 / §27.3 a piggy / jar run started after the gap after
  /// [slot] (the planned-ahead slot) was planned: the run's own items for
  /// that gap, so its follow-up fields still start there (and scroll in).
  /// [hasItems]: the gap already holds an item.
  List<GapItemPlan> activityItemsFor(
    DirectorContext ctx,
    SlotPlan slot, {
    bool hasItems = false,
  }) {
    if (slot.duringRide || slot.kind == HoopKindId.portal || _ride != null) {
      return const [];
    }
    final items = _activityItems(ctx, slot, used: hasItems);
    if (items.isNotEmpty) _gapUsed.add(slot.index);
    for (final p in items) {
      _count(p.kind.storageId);
    }
    return items;
  }

  // --- gaps -------------------------------------------------------------------

  /// §3.12 a planned portal with [ride] was dropped before it was flown (a
  /// portal ride clears the track ahead): its ride is not the last one, so
  /// the next portal may take any other than the one really flown (never
  /// the same ride twice in a row).
  void portalDropped(RideId ride) {
    if (_lastRide == ride) _lastRide = _rideBefore;
  }

  /// §3.0.3 / §3.28 a portal ride cleared [coins] bank coins unjudged: they
  /// are neither caught nor missed, so the bank places them again in the
  /// gaps after the landing (S6-41).
  void refundPiggyCoins(int coins) {
    if (coins <= 0) return;
    if (!_piggyActive) {
      _piggyActive = true;
      _piggyOwed = RunConfig.piggyFollowGaps * RunConfig.piggyCoinsPerGap;
    }
    _piggyOwed += coins;
  }

  /// Bank coins still to be placed (tests).
  int get piggyCoinsOwed => _piggyOwed;

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
    // PRD-2.2 §27.2 no reward item during an activity and its cool-down.
    final blocked = _rewardsBlocked(g, ctx, gap: true);
    var used = _gapUsed.contains(g);
    void put(GapItemPlan p) {
      items.add(p);
      used = true;
      _gapUsed.add(g);
      _count(p.kind.storageId);
    }

    // 1. Running Piggy Bank / Firefly Jar fill the gap.
    final sq = ctx.squeezeWindow;
    for (final p in _activityItems(ctx, slot, used: used)) {
      put(p);
    }

    // Debug force: the head gap element of the queue, ignoring unlock,
    // schedules and min distances (exclusivity still applies).
    final dbgIdx = _forced.indexWhere((e) => e.isGapElement);
    if (!used && !blocked && dbgIdx >= 0) {
      final e = _forced[dbgIdx];
      final p = _forcedGapItem(e, g, ctx, slot, mid, nextX);
      if (p != null) {
        _forced.removeAt(dbgIdx);
        put(p);
      }
    }

    // 2. Fixed schedules: heart, feather, piece (taken gap → next free gap).
    if (!used && !blocked && g >= _heartAt && _on(ElementId.heart)) {
      if (!ctx.extraLifeActive) put(_heart(g, ctx, slot));
      _heartAt =
          g + RunRandom.rangeInt(r, tables.heart.then.$1, tables.heart.then.$2);
    }
    // §3.17: in the squeeze window only scheduled hearts (and star trails)
    // spawn; the feather and the piece wait for the next free gap.
    // PRD-2.2 §19.3 never in the same or a neighbouring gap as the other.
    bool near(int? other) => other != null && (g - other).abs() <= 1;
    if (!used &&
        !sq &&
        !blocked &&
        !_featherDone &&
        g >= _featherAt &&
        !near(_pieceGap) &&
        _on(ElementId.feather)) {
      _featherDone = true;
      if (ctx.featherWanted) {
        _featherGap = g;
        put(_detour(ElementId.feather, slot, ctx, null));
      }
    }
    if (!used &&
        !sq &&
        !blocked &&
        !_pieceDone &&
        g >= _pieceAt &&
        !near(_featherGap) &&
        _on(ElementId.puzzlePiece)) {
      _pieceDone = true;
      final missing = [
        for (var b = 0; b < 4; b++)
          if (ctx.puzzleMask & (1 << b) == 0) b,
      ];
      if (missing.isNotEmpty) {
        final piece = missing[r.nextInt(missing.length)];
        _pieceGap = g;
        put(_detour(ElementId.puzzlePiece, slot, ctx, piece));
      }
    }

    // 3. The switch of a switch ring in the next slot is decided with that
    // slot (it marks this gap as used then).

    // 4. Optional item: first-meet (never-met element, ignores the budget)
    // or the budget roll.
    if (!used && blocked && oneBigBonus) {
      // PRD-2.3 §17.3 rule 4 (S8-11): during an activity and its cool-down
      // nothing is placed, but the gap is still drawn, so a big bonus picked
      // here waits (at most one) and takes the first allowed gap; §17.3
      // rule 5 keeps §14's frequency that way.
      _drawWhileBlocked(g, ctx);
    }
    if (!used && !blocked) {
      final due = firstMeet.dueGap(g);
      final pool = tables.earlyPool;
      ElementId? pick;
      CapsuleType? capsule;
      final waiting = _waitItem;
      if (waiting != null && _gapAllowed(waiting, g, ctx)) {
        // PRD-2.3 §17.3 rule 4 the waiting big item comes first.
        pick = waiting;
        _waitItem = null;
      } else if (due != null && _gapAllowed(due, g, ctx)) {
        pick = due.isCapsuleType ? ElementId.capsule : due;
        if (due.isCapsuleType) {
          capsule = CapsuleType.values.firstWhere((c) => c.element == due);
        }
      } else if (pool != null && pool.covers(g)) {
        // PRD-2.2 §19.2 the early pool's Star Trail (drawn with the slot);
        // it may come from index 4 (its min distance still holds).
        if (_earlyPicks[g] == EarlyPick.starTrail) {
          if (_gapAllowed(ElementId.starTrail, g, ctx, ignoreFrom: true)) {
            pick = ElementId.starTrail;
          } else if (oneBigBonus &&
              !_bonusWaits &&
              _gapAllowed(
                ElementId.starTrail,
                g,
                ctx,
                ignoreFrom: true,
                ignoreOpen: true,
              )) {
            _waitItem = ElementId.starTrail; // PRD-2.3 §17.3 rule 4
          }
        }
      } else if (r.nextDouble() < tables.budgetFor(g).gap) {
        final w = <ElementId, int>{};
        for (final e in tables.gapItems.entries) {
          // PRD-2.3 §17.3 rule 4: a big item that only rule 1 blocks stays
          // in the draw (and waits if drawn).
          if (_gapAllowed(e.key, g, ctx) ||
              (oneBigBonus &&
                  isBigItem(e.key) &&
                  _gapAllowed(e.key, g, ctx, ignoreOpen: true))) {
            w[e.key] = e.value.weight;
          }
        }
        pick = RunRandom.pickWeighted<ElementId>(r, w);
        if (oneBigBonus && pick != null && isBigItem(pick)) {
          final blocked = !_gapAllowed(pick, g, ctx);
          if (blocked || _bonusWaits) {
            // A blocked item waits (if none waits yet); the gap is drawn
            // again from the non-big elements.
            if (blocked && !_bonusWaits) _waitItem = pick;
            w.removeWhere((k, _) => isBigItem(k));
            pick = RunRandom.pickWeighted<ElementId>(r, w);
          }
        }
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

  /// PRD-2.3 §17.3 rule 4 (S8-11) the gap draw of a gap that the activity
  /// cool-down ([_rewardsBlocked]) blocks: the early pool's Star Trail or the
  /// budget roll, as in an open gap; a drawn big item becomes the waiting
  /// item (if none waits yet), anything else is dropped. Places nothing.
  void _drawWhileBlocked(int g, DirectorContext ctx) {
    final r = rng.layout;
    ElementId? pick;
    final pool = tables.earlyPool;
    if (firstMeet.dueGap(g) != null) return; // stays due by itself
    if (pool != null && pool.covers(g)) {
      if (_earlyPicks[g] == EarlyPick.starTrail) pick = ElementId.starTrail;
    } else if (r.nextDouble() < tables.budgetFor(g).gap) {
      final w = <ElementId, int>{
        for (final e in tables.gapItems.entries)
          if (_gapAllowed(e.key, g, ctx, ignoreOpen: true))
            e.key: e.value.weight,
      };
      pick = RunRandom.pickWeighted<ElementId>(r, w);
    }
    if (pick == null || _bonusWaits || !isBigItem(pick)) return;
    if (!_gapAllowed(pick, g, ctx, ignoreOpen: true, ignoreFrom: true)) {
      return;
    }
    _waitItem = pick;
  }

  /// §3.0.3 heart. PRD-2.2 §19.4: a single pickup (random spot in the
  /// gap, ±50 pt off the line; supersedes "first on the line, later 50 %
  /// off by 0.1–0.4 band").
  GapItemPlan _heart(int g, DirectorContext ctx, SlotPlan slot) =>
      _single(ElementId.heart, slot);

  /// §3.0.3 feather / piece. PRD-2.2 §19.4: single pickups like the others
  /// (random spot 30–70 % along the gap, ±50 pt off the line; supersedes
  /// the 0.65 × spacing / 64–200 pt above detour).
  GapItemPlan _detour(
    ElementId kind,
    SlotPlan slot,
    DirectorContext ctx,
    Object? extra,
  ) => _single(kind, slot, extra: extra);

  /// §3.0.3 optional gap-item eligibility.
  bool _gapAllowed(
    ElementId k,
    int g,
    DirectorContext ctx, {
    bool ignoreUnlock = false,
    bool ignoreFrom = false,
    bool ignoreOpen = false,
  }) {
    final key = k.isCapsuleType ? ElementId.capsule : k;
    // PRD-2.3 §17.3 rule 1 at most one open big bonus.
    if (!ignoreOpen && isBigItem(key) && _bigOpen(ctx)) return false;
    final rule = tables.gapItems[key];
    if (rule == null || !_on(key)) return false;
    if (k.isCapsuleType && !_on(k)) return false;
    if (key == ElementId.capsule &&
        !tables.capsuleWeights.keys.any((c) => _on(c.element))) {
      return false;
    }
    if (!ignoreUnlock) {
      if (!ignoreFrom && g < rule.from) return false;
      if (g - (_lastGapOf[key] ?? -99) < rule.minSince) return false;
      final maxN = rule.maxPerRun;
      if (maxN != null) {
        final n =
            (_runCount[key] ?? 0) +
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
      // PRD-2.2 §19.4 single pickups: random spot, ±50 pt off the line.
      case ElementId.capsule:
        return _single(k, slot, extra: capsule);
      default:
        return _single(k, slot);
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
        return _heart(g, ctx, slot);
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
