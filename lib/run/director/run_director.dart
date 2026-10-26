import 'dart:math';

import '../config/director_tables.dart';
import '../config/layout_config.dart';
import '../config/run_config.dart';
import '../config/tuning_values.dart';
import '../elements.dart';
import '../showcase/showcase_plan.dart';
import 'calm_schedule.dart';
import 'director_context.dart';
import 'first_meet.dart';
import 'formations.dart';
import 'hazard_budget.dart';
import 'headline_window.dart';
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
    this.showcase,
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
    firstMeet = FirstMeet(met, this.enabled, pullsEnabled: showcase == null);
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
    _calm = CalmSchedule(rng.timing);
    if (startHoopIndex > 34) _calm.onRideStart(startHoopIndex);
    _introductions = {
      for (final element in const [ElementId.saw, ElementId.squeeze])
        if (!this.enabled.contains(element) || !firstMeet.met.contains(element))
          element,
    };
  }

  /// Frozen START input; never added to the debug-force queue.
  final ShowcaseRunPlan? showcase;

  late final Random _showcaseRandom = Random(rng.seed ^ 0x5C0A5E);

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
  MotionSpec? _lastFinalMotion;
  SawDesign? _lastSaw;
  SwitchDesign? _lastSwitch;
  SwitchDesign? _switchBeforePlanned;
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
  late final CalmSchedule _calm;
  HazardBudget _hazard = HazardBudget();
  bool _inSqueezeWindow = false;

  /// PRD-2 §3.23 the next slot is the fixed landing of a spring shipped at
  /// this index − 1. Its 240 pt separation is part of the spring's geometry,
  /// so D3 may simplify the landing but may not move it.
  int? _springLandingAt;
  final HeadlineWindow _headline = HeadlineWindow();
  String? _headlineReservationId;
  int _headlineReservationDue = -1;
  int? _forcedHeadlineAt;
  late final Set<ElementId> _introductions;
  int _downgrades = 0;
  SlotPlan? _showcaseNormalSlot;
  int? _showcasePortalAt;
  double? _lastFinalY;

  /// PRD-2.6 D7 the post-ceiling formation scheduler. The scheduler draws
  /// from the layout stream so a formation changes the course deterministically
  /// but never shifts the timing stream.
  late final Formations _formations = Formations(
    seed: rng.seed,
    random: rng.layout,
    formationEvery: const [1, 1],
  );
  int _formationAt = 150;
  int? _lastFormationAt;

  /// Templates owned by the current formation. Recovery and forced actions
  /// can interrupt it; periodic calm stretches are avoided before starting.
  ({int start, int length, List<SlotPlan> templates})? _formationReservation;

  /// The D7 chapter stream: only used past hoop 150 to thin or thicken the
  /// ordinary moving draw to its chapter share. It is separate from the
  /// layout / timing streams, so the pre-ceiling course is untouched.
  late final Random _chapterRandom = Random(rng.seed ^ 0xD7C4A11);

  /// Next slot index (= hoop index of the slot [nextSlot] plans next).
  int get hoopIndex => _i;

  /// Track x of the next slot's plane.
  double get nextTrackX => _nextX;

  /// The current ride (between [onRideStart] and [onRideEnd]).
  RideKind? get ride => _ride;

  /// Pending debug forces (head first).
  List<ElementId> get forcedQueue => List.unmodifiable(_forced);

  /// The schedules (tests, debug overlay).
  int get portalAt => _showcasePortalAt ?? _portalAt;

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

  /// PRD-2.6 D3 slots downgraded by the rolling hazard ledger (tests and
  /// `run_extra`).
  int get downgrades => _downgrades;

  bool _on(ElementId e) => enabled.contains(e);

  /// §3.6 the Big Hoops multiplier for slot [i]. DEVIATION from PRD-2.3 §0
  /// item 3 (owner, 2026-10-19): with Big Hoops armed hoop 0 grows too (big
  /// and gold already on the waiting screen); without it hoop 0 stays 118.
  double _bigMult(int i, DirectorContext ctx) => ctx.bigHoopsMult;
  double _coreCentre(DirectorContext ctx) =>
      ctx.topTooth + min(ctx.band, LayoutConfig.courseRefBand) / 2;
  bool get _portalOn => _on(ElementId.portal);

  // region WP-A — at most N portal rides per run (PRD-2.3.1 §17)
  /// PRD-2.3.1 §17 portals placed this run. Monotonic: every placed portal
  /// counts, also one later turned plain or cleared before it was flown
  /// (owed by a revive / ride / activity); a revive does not reset it.
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

  /// §3.0.1 / PRD-2.3 §14.4 / PRD-2.4 §2 opening at [hoopIndex] before the
  /// Big Hoops multiplier: 118 at hoop 0, then `curve_opening` (118 → 66).
  /// Rides and comets use the same curve; the portal does not
  /// ([RunConfig.portalOpening]).
  double openingFor(int hoopIndex) => RunConfig.openingFor(hoopIndex);

  // --- timing-stream rolls (§3.0.3 "timing") --------------------------------

  /// §3.17 / PRD-2.3 §14.4 the next squeeze moment, counted in hoops: the
  /// first at a random hoop 25–40 ([first]: `squeeze_first`), the next
  /// 25–45 hoops after the previous one ended (`squeeze_gap`). The hoop
  /// count turns into runClock at the cruise of the hoops ahead
  /// ([RunConfig.secondsForHoops] from [hoop], the bird's hoop now).
  double rollSqueezeAt(
    double now, {
    required int hoop,
    int index = 0,
    bool first = false,
  }) {
    final (a, b) = TuningValues.current.range(
      first ? 'squeeze_first' : 'squeeze_gap',
    );
    final n = RunRandom.rangeInt(rng.timing, a, b);
    return now + RunConfig.secondsForHoops(hoop, n);
  }

  /// §3.17 / PRD-2.3 §14.4 the hold: 5–10 hoops (`squeeze_hold`) from
  /// [hoop], in runClock seconds.
  double rollSqueezeHold({required int hoop, int index = 0}) {
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

  // --- lifecycle --------------------------------------------------------------

  /// §3.0.3 slot order 2: the next slot is a plain normal hoop.
  void onRevive() {
    _revivePending = true;
    // The revive interrupts the launch; its recovery slots take priority
    // over a landing reserved by a spring before the death.
    _springLandingAt = null;
    _layout.forceY = null;
    _calm.onRevive(_i);
  }

  void onRideStart(RideKind k) {
    _ride = k;
    _calm.onRideStart(_i);
  }

  void onRideEnd(RideKind k) {
    if (_ride == k) _ride = null;
    _calm.onRideEnded(_i);
    if (k == RideKind.comet) {
      _zigEndX = null;
      _zigSide = 0;
      // PRD-2.3.1 §16.1 C stations not planned by the end are dropped; the
      // next slot is the safe first hoop after the comet.
      _cometStations = null;
    }
  }

  /// PRD-2.6 D4/D5 a squeeze warning may start at [hoop].
  bool allowsSqueezeWarning(int hoop) {
    if (!_calm.allowsSqueezeWarning(hoop)) return false;
    if (_headlineDue('squeeze', hoop)) return true;
    return false;
  }

  /// PRD-2.6 D6 the squeeze warning claimed the headline at [hoop].
  void onSqueezeWarning(int hoop) => _claimHeadline('squeeze', hoop);

  /// PRD-2.6 D4 two calm slots follow a finished squeeze.
  void onSqueezeEnded(int hoop) => _calm.startAt(max(hoop + 1, _i), 2);

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
    _nextX = stations.isNotEmpty
        ? stations.first
        : max(_nextX, _cometAfterMin!);
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
  /// plain ride hoop (the curve size of its index, upright, still, nothing
  /// attached; PRD-2.4 §2). Null outside a comet layout.
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
    final (lo, hi) = _layout.portableLimits(i, ctx, opening, useTable: false);
    final y = (_coreCentre(ctx) + _zigSide * _zigAmp).clamp(lo, hi).toDouble();
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
    final springLanding = _springLandingAt == i;
    if (springLanding) _springLandingAt = null;
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
    // tilt, nothing attached), opening 118, centre 16 pt below the middle.
    // DEVIATION from §0 item 3 (owner, 2026-10-19): Big Hoops grows it too. Debug-forced slot elements wait for
    // hoop 1.
    if (fixedFirstHoop && i == 0 && _startIndex == 0) {
      final y = _coreCentre(ctx) + RunConfig.hoop0DropY;
      _layout.lastY = y;
      _prevKind = HoopKindId.normal;
      _count(ElementId.normalHoop.storageId);
      _nextX += spacing;
      return _recordSlot(
        SlotPlan(
          index: i,
          kind: HoopKindId.normal,
          element: ElementId.normalHoop,
          trackX: trackX,
          centreY: y,
          opening: cap(RunConfig.opening0 * _bigMult(i, ctx)),
          advance: spacing,
        ),
        ctx,
        previousY: null,
        springLanding: springLanding,
      );
    }

    // 1. Ride active: normal, upright, still; no items. PRD-2.4 §2: the
    //    size is the curve's for this index (× Big Hoops), like any hoop.
    if (ride) {
      _formationReservation = null;
      final opening = cap(openingFor(i) * _bigMult(i, ctx));
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
      return _recordSlot(
        SlotPlan(
          index: i,
          kind: HoopKindId.normal,
          element: ElementId.normalHoop,
          trackX: trackX,
          centreY: y,
          opening: opening,
          advance: advance,
          duringRide: ride,
        ),
        ctx,
        previousY: null,
        springLanding: springLanding,
      );
    }

    final prevY = ctx.prevCentreY ?? _lastFinalY ?? _layout.lastY;
    // PRD-2.6 D4 a calm slot has Δy ≤ the row median, while §3.23 fixes the
    // spring landing at 240 pt. The calm stretch waits for the slot after
    // the landing instead of erasing the spring's geometry.
    final calm = !springLanding && _calm.isCalm(i);
    if (calm) _calm.startAt(i, 3);
    // PRD-2.6 D4 a calm slot is a normal hoop. Keep the sampler's
    // "previous modifier" state from claiming a motion / tilt that the
    // calm slot never gets: its Δy must not be capped as if a hard hoop
    // had shipped.
    if (calm) _layout.noteModifiers();
    HoopKindId? kind;
    var forced = false;
    ElementId? forceMod; // angledRing / movingRing on a normal slot
    var cometMode = 0;

    // Debug force (head slot element of the queue).
    final dbgIdx = _forced.indexWhere((e) => e.isSlotElement);
    if (dbgIdx >= 0 && !_scriptedSlot(i)) {
      final e = _forced[dbgIdx];
      final special = HoopKindId.specialFor(e);
      var ok = false;
      if (special != null) {
        ok = _specialAllowed(special, i, ctx, ignoreUnlock: true);
        if (ok) kind = special;
      } else if (e == ElementId.portal && portalCapped) {
        // PRD-2.3.1 §17 at the cap a forced portal is discarded (never
        // owed; the queue moves on to the next debug item).
        _forced.removeAt(dbgIdx);
        _forcedRide = null;
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

    var due = forced ? null : firstMeet.dueSlot(i);
    if (due != null && !_headlineDue('first-meet', i)) {
      final wait = firstMeet.dueSince;
      if (wait == null || i - wait < 5) due = null;
    }

    // PRD-2.6 D7 formations own whole runs of otherwise-normal slots. A
    // calm / squeeze / ride or a due forced element takes precedence.
    final freeForStart =
        !forced && !calm && !ctx.squeezeWindow && due == null && !ride;
    final formation = _nextFormationSlot(
      i,
      trackX,
      ctx,
      cap: cap,
      mayStart: freeForStart,
    );
    if (formation != null) {
      return _recordSlot(
        formation,
        ctx,
        previousY: prevY,
        firstMeetElement: due,
      );
    }

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
            !calm &&
            _headlineDue('ride', i) &&
            [
              HoopKindId.saw,
              HoopKindId.fever,
              HoopKindId.switchRing,
            ].every((hard) => i - (_lastOf[hard] ?? -99) > 3) &&
            i - _lastComet >= RunConfig.cometPortalDistance) {
          kind = HoopKindId.portal;
          forced = due == ElementId.portal;
        } else if (i >= _portalAt) {
          // PRD-2.6 D6: the portal is still due while its ride headline is
          // blocked. Keep the schedule at this hoop so the next eligible
          // slot (and the comet distance) measure from the original due
          // point, not from a silently dropped portal.
          _portalAt = min(_portalAt, i);
          if (oneBigBonus) _portalWaiting = true;
        }
      } else if (oneBigBonus && i >= _portalAt) {
        _portalWaiting = true;
      }
    }

    // 4. Cooldown. 5. Special roll (first-meet replaces the roll).
    final cooling = i - _lastSpecial <= _cdLeft;
    var owedCometReady = false;
    if (_cometOwed) {
      owedCometReady = _cometAllowed(i, ctx);
    } else if (due == ElementId.comet) {
      owedCometReady = _cometAllowed(i, ctx, mode: 1);
    }
    if (kind == null && !forced && !cooling && !owedCometReady) {
      final dueSpecial = due == null ? null : HoopKindId.specialFor(due);
      final waiting = _waitRing;
      final headlineWaiting = _headlineWaitRing;
      if (waiting != null && _specialAllowed(waiting, i, ctx)) {
        // PRD-2.3 §17.3 rule 4 the waiting reward ring comes first.
        kind = waiting;
        _waitRing = null;
      } else if (headlineWaiting != null &&
          i >= _headlineWaitRingDue &&
          _headlineDue(_headlineWaitRingId, i) &&
          _specialAllowed(headlineWaiting, i, ctx)) {
        kind = headlineWaiting;
        forced = false;
        _clearHeadlineWaitRing();
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
              final rotated =
                  e.key == HoopKindId.saw || e.key == HoopKindId.switchRing;
              w[e.key] = rotated
                  ? _rotatedSpecialWeight(e.key, e.value, i).round()
                  : e.value.weightAt(i);
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
          if (kind != null &&
              rewardKinds.contains(kind) &&
              !_headlineDue('big-bonus', i)) {
            _headlineWaitRing = kind;
            _headlineWaitRingId = 'big-bonus';
            _headlineWaitRingDue = _delayHeadline('big-bonus', i);
            kind = null;
          }
        }
      }
    }
    if (!forced && due == ElementId.comet) cometMode = 1;
    if (!forced &&
        (due == ElementId.angledRing || due == ElementId.movingRing)) {
      forceMod = due;
    }
    kind ??= HoopKindId.normal;
    // Leave the next plane free at the last formation start before the
    // cadence deadline or recovery. Earlier springs may finish their landing
    // first; a spring here would make the formation miss its available window.
    if (!forced && kind == HoopKindId.spring && i >= 150) {
      final interval = TuningValues.current.ints('formation_every');
      final last = _lastFormationAt;
      final canStartNext = last == null || i + 1 - last >= interval[0];
      final recoverySoon = List.generate(5, (k) => i + 2 + k).any(_calm.dueAt);
      if (canStartNext &&
          (last != null && i + 1 - last >= interval[1] || recoverySoon)) {
        kind = HoopKindId.normal;
      }
    }
    final planned = _buildSlot(
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
    return _recordSlot(
      planned,
      ctx,
      previousY: prevY,
      calm: calm,
      firstMeetElement: due,
      springLanding: springLanding,
    );
  }

  bool _scriptedGap(int gap) {
    final plan = showcase;
    return plan != null &&
        (plan.hearts.contains(gap) ||
            plan.gapItems.any((item) => item.gap == gap));
  }

  bool _scriptedSlot(int hoop) {
    final plan = showcase;
    return plan != null &&
        (plan.portalHoops.contains(hoop) ||
            plan.cometHoops.contains(hoop) ||
            plan.feverHoops.contains(hoop) ||
            plan.bullseyeHoops.contains(hoop));
  }

  SlotPlan? _showcaseSlot(SlotPlan normal, DirectorContext ctx) {
    final plan = showcase;
    final i = normal.index;
    if (plan == null || !_scriptedSlot(i)) return null;
    final portal = plan.portalHoops.contains(i);
    final comet = plan.cometHoops.contains(i);
    final kind = portal
        ? HoopKindId.portal
        : comet
        ? HoopKindId.normal
        : plan.feverHoops.contains(i)
        ? HoopKindId.fever
        : HoopKindId.bullseye;
    RideId? theme;
    if (portal) {
      theme = plan.portals.firstWhere((p) => p.hoop == i).theme;
      // The replacement schedule has its own stream. Never feed a script
      // decision back into the ordinary layout, cooldowns or hazard ledger.
      _showcasePortalAt = i + RunRandom.rangeInt(_showcaseRandom, 25, 40);
    }
    final opening = min(
      (portal ? RunConfig.portalOpening : openingFor(i)) * ctx.bigHoopsMult,
      ctx.band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin),
    );
    final (lo, hi) = _layout.portableLimits(i, ctx, opening, useTable: false);
    final y = normal.centreY.clamp(lo, hi).toDouble();
    return normal.copyWith(
      centreY: y,
      kind: kind,
      element: comet ? ElementId.normalHoop : kind.element,
      opening: opening,
      tiltDeg: 0,
      motion: () => null,
      cometHang: comet,
      ringOffsets: const [0],
      advance: spacing,
      extra: () => theme,
      forced: false,
      duringRide: true,
      hazardCost: 0,
      calm: false,
      attached: comet
          ? [
              GapItemPlan(
                kind: ElementId.comet,
                trackX: normal.trackX + RunConfig.cometHang,
                y: y,
              ),
            ]
          : const [],
    );
  }

  SlotPlan _recordSlot(
    SlotPlan planned,
    DirectorContext ctx, {
    required double? previousY,
    bool calm = false,
    ElementId? firstMeetElement,
    bool springLanding = false,
  }) {
    final squeezeEntry = ctx.squeezeWindow && !_inSqueezeWindow;
    if (squeezeEntry) _hazard = HazardBudget();
    final ledgerSqueeze = squeezeEntry;
    final hoop = planned.index;
    final dyRef = min(ctx.band, RunConfig.dyRefBand);
    final row = tables.bandFor(hoop).dy;
    final hazardPrevious = previousY ?? _lastFinalY;
    final shouldCalm = calm && !planned.forced;
    var finalPlan = shouldCalm
        ? _calmSlot(planned, ctx, previousY: previousY)
        : planned;
    SlotPlan alignFormation(SlotPlan plan) {
      if (plan.formation == null) return plan;
      return plan.copyWith(
        tiltDeg: _layout.alignedTilt(
          plan.tiltDeg,
          plan.centreY - (hazardPrevious ?? _coreCentre(ctx)),
          plan.motion == null ? RunConfig.maxTiltDeg : 30,
        ),
      );
    }

    finalPlan = alignFormation(finalPlan);

    // §3.23 a spring landing is committed geometry. Reserve the landing's
    // baseline Δy cost while shipping the spring; if the four-slot window
    // cannot afford it, replace the spring itself (D3's last resort) rather
    // than shortening the jump later.
    if (finalPlan.kind == HoopKindId.spring && !finalPlan.forced) {
      final dir = planned.extra == SpringDir.up ? -1 : 1;
      final landingY = planned.centreY + dir * RunConfig.springJump;
      final nextP90 = tables.bandFor(hoop + 1).dy.$2 * dyRef;
      final landingCost = (landingY - planned.centreY).abs() > nextP90
          ? TuningValues.current.obj('hazard_costs')['dy_p90']!.toDouble()
          : 0.0;
      if (!_hazard.allowsFollowing(
        planned,
        nextCost: landingCost,
        nextIndex: hoop + 1,
        previousY: hazardPrevious,
        rowP90: row.$2 * dyRef,
        squeeze: ledgerSqueeze,
      )) {
        finalPlan = planned.copyWith(
          kind: HoopKindId.normal,
          element: ElementId.normalHoop,
          ringOffsets: const [0],
          extra: () => null,
        );
        _layout.forceY = null;
        _springLandingAt = null;
      }
    }
    final willDowngrade =
        !finalPlan.forced &&
        !_hazard.allows(
          finalPlan,
          previousY: hazardPrevious,
          rowP90: row.$2 * dyRef,
          squeeze: ledgerSqueeze,
        );
    final trainAfterMovingJump =
        planned.kind == HoopKindId.train &&
        _lastFinalMotion != null &&
        _lastFinalY != null &&
        (planned.centreY - _lastFinalY!).abs() > 120;
    if (trainAfterMovingJump) {
      finalPlan = finalPlan.copyWith(
        kind: HoopKindId.normal,
        element: ElementId.normalHoop,
        ringOffsets: const [0],
        extra: () => null,
      );
    }
    if (willDowngrade || trainAfterMovingJump) {
      finalPlan = _hazard.downgrade(
        finalPlan,
        previousY: hazardPrevious,
        rowP90: row.$2 * dyRef,
        squeeze: ledgerSqueeze,
        preserveDy: springLanding,
      );
      // `downgrade` stops at a ≤15° tilt when that is still over budget;
      // D3 has two further steps (Δy to p90, then normal). Complete them
      // here so a normal slot never leaves an above-p90 Δy in the ledger.
      if (!_hazard.allows(
        finalPlan,
        previousY: hazardPrevious,
        rowP90: row.$2 * dyRef,
        squeeze: ledgerSqueeze,
      )) {
        final delta = hazardPrevious == null
            ? 0.0
            : finalPlan.centreY - hazardPrevious;
        final centre =
            springLanding ||
                hazardPrevious == null ||
                delta.abs() <= row.$2 * dyRef
            ? finalPlan.centreY
            : hazardPrevious +
                  (finalPlan.centreY - hazardPrevious).sign *
                      min(
                        (finalPlan.centreY - hazardPrevious).abs(),
                        row.$2 * dyRef - 0.000001,
                      );
        finalPlan = finalPlan.copyWith(
          centreY: centre,
          tiltDeg: 0,
          motion: () => null,
        );
        if (finalPlan.kind != HoopKindId.normal &&
            !_hazard.allows(
              finalPlan,
              previousY: hazardPrevious,
              rowP90: row.$2 * dyRef,
              squeeze: ledgerSqueeze,
            )) {
          final normal = finalPlan.copyWith(
            kind: HoopKindId.normal,
            element: ElementId.normalHoop,
            ringOffsets: const [0],
            extra: () => null,
          );
          finalPlan =
              _hazard.allows(
                normal,
                previousY: hazardPrevious,
                rowP90: row.$2 * dyRef,
                squeeze: ledgerSqueeze,
              )
              ? normal
              : normal.copyWith(centreY: planned.centreY);
        }
      }
      _downgrades++;
      if (finalPlan.kind != HoopKindId.spring) _springLandingAt = null;
    }
    if (finalPlan.kind == HoopKindId.switchRing &&
        finalPlan.centreY != planned.centreY) {
      // D3 can shorten the approach after the switch was positioned. Keep
      // its 70–100 pt offset and the previous-hoop/item-band constraints.
      final item = finalPlan.attached.single;
      final originalY = item.y!;
      double? switchY;
      for (final side in [-1, 1]) {
        final near =
            finalPlan.centreY + side * (RunConfig.switchOffsetMin + 1e-6);
        final far =
            finalPlan.centreY + side * (RunConfig.switchOffsetMax - 1e-6);
        var lo = max(
          min(near, far),
          ctx.squeezeTopTooth + RunConfig.itemEdgeMargin,
        );
        var hi = min(
          max(near, far),
          ctx.squeezeFloorTooth - RunConfig.itemEdgeMargin,
        );
        if (hazardPrevious != null) {
          lo = max(lo, hazardPrevious - RunConfig.switchMaxFromPrev);
          hi = min(hi, hazardPrevious + RunConfig.switchMaxFromPrev);
        }
        if (lo > hi) continue;
        final candidate = originalY.clamp(lo, hi).toDouble();
        if (switchY == null ||
            (candidate - originalY).abs() < (switchY - originalY).abs()) {
          switchY = candidate;
        }
      }
      if (switchY != null) {
        finalPlan = finalPlan.copyWith(attached: [item.resolved(y: switchY)]);
      } else {
        finalPlan = finalPlan.copyWith(
          kind: HoopKindId.normal,
          element: ElementId.normalHoop,
          attached: const [],
          extra: () => null,
        );
        _gapUsed.remove(hoop - 1);
      }
    }
    if (finalPlan.kind == HoopKindId.normal) {
      var opening = openingFor(hoop) * _bigMult(hoop, ctx);
      if (finalPlan.tiltDeg.abs() == 45) {
        opening += TuningValues.current.i('tilt45_extra_opening');
      }
      finalPlan = finalPlan.copyWith(
        opening: min(
          opening,
          ctx.band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin),
        ),
      );
    }
    if (finalPlan.kind == HoopKindId.spring) {
      // D3 may shorten the approach to the spring. Its landing must follow
      // the centre that actually ships, rather than the provisional centre.
      final dir = finalPlan.extra == SpringDir.up ? -1 : 1;
      final target = finalPlan.centreY + dir * RunConfig.springJump;
      final nextOpening = openingFor(hoop + 1) * _bigMult(hoop + 1, ctx);
      final (lo, hi) = _layout.portableLimits(
        hoop + 1,
        ctx,
        nextOpening,
        useTable: false,
      );
      if (target >= lo && target <= hi) {
        _layout.forceY = target;
      } else {
        finalPlan = finalPlan.copyWith(
          kind: HoopKindId.normal,
          element: ElementId.normalHoop,
          ringOffsets: const [0],
          extra: () => null,
        );
        _layout.forceY = null;
        _springLandingAt = null;
      }
    }
    finalPlan = alignFormation(finalPlan);
    finalPlan = finalPlan.copyWith(
      // A train's longer advance belongs to the train in the final plan. A
      // hazard / calm / activity downgrade to a normal hoop must restore the
      // normal gap, or every item after it is positioned against the old
      // train tail.
      advance: finalPlan.kind == HoopKindId.train ? null : spacing,
      hazardCost: _hazard.costOf(
        finalPlan,
        previousY: hazardPrevious,
        rowP90: row.$2 * dyRef,
        squeeze: ledgerSqueeze,
      ),
    );
    // The spring reservation belongs to the kind that really ships. A calm
    // conversion or a later normal fallback above may have replaced a spring
    // without passing the hazard branch that clears `_springLandingAt`.
    if (finalPlan.kind != HoopKindId.spring && _springLandingAt == hoop + 1) {
      _springLandingAt = null;
    }
    _hazard.add(
      finalPlan,
      previousY: hazardPrevious,
      rowP90: row.$2 * dyRef,
      squeeze: ledgerSqueeze,
    );
    _inSqueezeWindow = ctx.squeezeWindow;

    _markFinal(finalPlan);
    if (planned.kind == HoopKindId.portal || planned.cometHang) {
      _claimHeadline('ride', hoop);
    } else if (firstMeetElement != null &&
        (finalPlan.element == firstMeetElement ||
            (firstMeetElement == ElementId.angledRing &&
                finalPlan.tiltDeg != 0) ||
            (firstMeetElement == ElementId.movingRing &&
                finalPlan.motion != null))) {
      _claimHeadline('first-meet', hoop);
    } else if (rewardKinds.contains(finalPlan.kind)) {
      _claimHeadline('big-bonus', hoop);
    }
    if (_introductions.contains(ElementId.saw) &&
        finalPlan.kind == HoopKindId.saw) {
      _claimHeadline('introduction', hoop);
    }

    _layout.lastY = finalPlan.centreY;
    _lastFinalY = finalPlan.centreY;
    _lastFinalMotion = finalPlan.motion;
    // The sampler noted the provisional tilt / motion in `_buildSlot`; a
    // calm stretch or hazard downgrade may have removed them. Record the
    // final pair, so the next Δy is only capped after a hard hoop that
    // really shipped (PRD-2.6 D2/D3).
    _layout.noteModifiers(motion: finalPlan.motion, tiltDeg: finalPlan.tiltDeg);
    if (planned.kind != finalPlan.kind) {
      _prevKind = HoopKindId.normal;
      _layout.forceY = null;
    }
    _replaceSpawnedCount(planned, finalPlan);
    if (planned.kind == HoopKindId.switchRing &&
        finalPlan.kind != HoopKindId.switchRing) {
      _lastSwitch = _switchBeforePlanned;
    }
    _switchBeforePlanned = null;
    _nextX = finalPlan.trackX + finalPlan.advance;
    final normal = finalPlan.copyWith(
      hazardCost: _hazard.costOf(
        finalPlan,
        previousY: hazardPrevious,
        rowP90: row.$2 * dyRef,
        squeeze: ledgerSqueeze,
      ),
    );
    if (showcase == null) return normal;
    // Run the normal decision to completion first, then overlay step 0.
    // Its sampler, reservations and random streams remain exactly the same
    // as an ordinary course with first-meet pulls disabled.
    _showcaseNormalSlot = normal;
    var shipped = _showcaseSlot(normal, ctx) ?? normal;
    if (!_scriptedSlot(hoop)) {
      final portalDue = _showcasePortalAt;
      if (portalDue != null &&
          hoop >= portalDue &&
          !ctx.rideActive &&
          _ride == null &&
          !ctx.activity) {
        final theme =
            RideId.values[_showcaseRandom.nextInt(RideId.values.length)];
        shipped = _showcasePortal(normal, ctx, theme);
        _showcasePortalAt = hoop + RunRandom.rangeInt(_showcaseRandom, 25, 40);
      } else if (_showcaseHeadline(hoop) ||
          portalDue != null && normal.kind == HoopKindId.portal) {
        shipped = _showcasePlain(normal, ctx);
      }
    }
    _replaceSpawnedCount(normal, shipped);
    return shipped;
  }

  bool _showcaseHeadline(int hoop) {
    final plan = showcase;
    return plan != null &&
        [
          ...plan.portalHoops,
          ...plan.cometHoops,
          ...plan.feverHoops,
        ].any((at) => (hoop - at).abs() < 8);
  }

  SlotPlan _showcasePlain(SlotPlan normal, DirectorContext ctx) =>
      normal.copyWith(
        kind: HoopKindId.normal,
        element: ElementId.normalHoop,
        opening: min(
          openingFor(normal.index) * _bigMult(normal.index, ctx),
          ctx.band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin),
        ),
        tiltDeg: 0,
        motion: () => null,
        cometHang: false,
        ringOffsets: const [0],
        attached: const [],
        extra: () => null,
        hazardCost: 0,
      );

  SlotPlan _showcasePortal(
    SlotPlan normal,
    DirectorContext ctx,
    RideId theme,
  ) => _showcasePlain(normal, ctx).copyWith(
    kind: HoopKindId.portal,
    element: ElementId.portal,
    extra: () => theme,
    opening: min(
      RunConfig.portalOpening * ctx.bigHoopsMult,
      ctx.band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin),
    ),
  );

  void _markFinal(SlotPlan plan) {
    if (plan.cometHang) firstMeet.markMet(ElementId.comet);
    if (plan.kind == HoopKindId.normal) {
      if (plan.tiltDeg != 0) firstMeet.markMet(ElementId.angledRing);
      if (plan.motion != null) firstMeet.markMet(ElementId.movingRing);
    }
    firstMeet.markMet(plan.element);
  }

  void _replaceSpawnedCount(SlotPlan planned, SlotPlan finalPlan) {
    void remove(String key) {
      final value = (_spawned[key] ?? 1) - 1;
      if (value <= 0) {
        _spawned.remove(key);
      } else {
        _spawned[key] = value;
      }
    }

    final kindChanged = planned.kind != finalPlan.kind;
    if (kindChanged) remove(planned.element.storageId);
    if (planned.tiltDeg != 0 && finalPlan.tiltDeg == 0) remove('tilted');
    if (planned.motion != null && finalPlan.motion == null) remove('moving');
    if (planned.cometHang && !finalPlan.cometHang) {
      remove(ElementId.comet.storageId);
    }
    if (kindChanged) _count(finalPlan.element.storageId);
    if (!planned.cometHang && finalPlan.cometHang) {
      _count(ElementId.comet.storageId);
    }
  }

  /// PRD-2.6 D7: takes the next queued formation slot, or starts a new
  /// formation when the scheduler is due at [i]. The generator owns the six
  /// shapes and their 310 pt planes; this adapter places a shape in the live
  /// band and leaves the final hazard decision to [_recordSlot].
  SlotPlan? _nextFormationSlot(
    int i,
    double trackX,
    DirectorContext ctx, {
    required double Function(double, [double]) cap,
    required bool mayStart,
  }) {
    // Recovery, debug actions and rides take precedence over a queued shape.
    if (!mayStart) _formationReservation = null;
    final reservation = _formationReservation;
    if (reservation != null) {
      final offset = i - reservation.start;
      if (offset >= 0 && offset < reservation.length) {
        final plan = reservation.templates[offset];
        _countFormationSlot(plan);
        if (offset == reservation.length - 1) _formationReservation = null;
        return plan;
      }
      _formationReservation = null;
    }
    if (i < 150 || !mayStart || _layout.forceY != null) return null;
    final interval = TuningValues.current.ints('formation_every');
    final last = _lastFormationAt;
    if (last != null && i - last < interval[0]) return null;
    // Reserve room for the longest shape. If a periodic recovery is about
    // to close that room, use the last safe start in the cadence window.
    bool roomAt(int start) {
      for (var offset = 0; offset < 5; offset++) {
        if (_calm.dueAt(start + offset)) return false;
      }
      return true;
    }

    if (!roomAt(i)) return null;
    if (i < _formationAt && roomAt(i + 1)) return null;
    final id = _formations.nextAt(i);
    if (id == null) return null;
    _lastFormationAt = i;
    _formationAt = i + RunRandom.rangeInt(rng.layout, interval[0], interval[1]);
    if (!_formationEnabled(id)) return null;
    var templates = _formations.build(id, i, startTrackX: 0, centreY: 0);
    if (id == FormationId.switchChain) {
      templates = _withoutRepeatingSwitch(templates);
    }
    final placedTemplates = _placeFormation(templates, trackX, ctx, cap: cap);
    final plan = placedTemplates.first;
    _formationReservation = (
      start: i,
      length: placedTemplates.length,
      templates: placedTemplates,
    );
    _countFormationSlot(plan);
    if (templates.length == 1) _formationReservation = null;
    return plan;
  }

  List<SlotPlan> _withoutRepeatingSwitch(List<SlotPlan> templates) {
    var previous = _lastSwitch;
    final out = <SlotPlan>[];
    for (final template in templates) {
      final current = template.extra is SwitchDesign
          ? template.extra! as SwitchDesign
          : null;
      final design = current == previous
          ? _switchDesignAfter(previous)
          : current;
      previous = design;
      out.add(
        identical(design, current)
            ? template
            : _withSwitchDesign(template, design!),
      );
    }
    return out;
  }

  SwitchDesign _switchDesignAfter(SwitchDesign? previous) =>
      SwitchDesign.values.where((design) => design != previous).first;

  SlotPlan _withSwitchDesign(SlotPlan template, SwitchDesign design) {
    final attached = [
      for (final item in template.attached)
        GapItemPlan(
          kind: item.kind,
          trackX: item.trackX,
          y: item.y,
          lineOffset: item.lineOffset,
          extra: design,
          toTrackX: item.toTrackX,
          toY: item.toY,
        ),
    ];
    return template.copyWith(extra: () => design, attached: attached);
  }

  /// Whether every element a D7 shape needs is registered.
  bool _formationEnabled(FormationId id) {
    final needed = switch (id) {
      FormationId.stairs => [ElementId.angledRing],
      FormationId.slalom => <ElementId>[],
      FormationId.tiltWave => [ElementId.angledRing],
      FormationId.syncRails => [ElementId.movingRing],
      FormationId.sawGate => [ElementId.saw],
      FormationId.switchChain => [ElementId.switchRing],
    };
    return needed.every(_on);
  }

  /// Slot bookkeeping `_buildSlot` normally does for a formation slot.
  void _countFormationSlot(SlotPlan plan) {
    _prevKind = plan.kind;
    if (plan.tiltDeg != 0) _count('tilted');
    if (plan.motion != null) _count('moving');
    _count(plan.element.storageId);
    if (plan.kind == HoopKindId.switchRing) {
      _gapUsed.add(plan.index - 1);
      if (plan.extra is SwitchDesign) {
        _switchBeforePlanned = _lastSwitch;
        _lastSwitch = plan.extra! as SwitchDesign;
      }
    } else if (plan.kind == HoopKindId.saw) {
      if (plan.extra is SawDesign) _lastSaw = plan.extra! as SawDesign;
    }
    if (plan.kind != HoopKindId.normal) {
      _lastSpecial = plan.index;
      _cdLeft = tables.specials[plan.kind]!.cooldown;
      _lastOf[plan.kind] = plan.index;
    }
  }

  /// Places the normalized [templates] of one formation at [trackX] and in
  /// the live band. Relative offsets stay intact except a tilt wave's valley
  /// can flatten at the band edge; final alignment then reduces strong tilts
  /// whose approaches are too short.
  List<SlotPlan> _placeFormation(
    List<SlotPlan> templates,
    double trackX,
    DirectorContext ctx, {
    required double Function(double, [double]) cap,
  }) {
    // Reverse an outward stair only when fitting its four steps would
    // push the entrance beyond the live Δy limit. Preserve the seeded
    // direction whenever its entrance is already reachable.
    if (templates.first.formation == FormationId.stairs) {
      final coreCentre = _coreCentre(ctx);
      final coreBand = min(ctx.band, LayoutConfig.courseRefBand);
      final previous = _lastFinalY ?? coreCentre;
      final reach =
          openingFor(templates.first.index) *
              _bigMult(templates.first.index, ctx) /
              2 +
          RunConfig.rimRadius +
          RunConfig.bandMargin;
      final offsets = templates.map((p) => p.centreY);
      final low = coreCentre - coreBand / 2 + reach - offsets.reduce(min);
      final high = coreCentre + coreBand / 2 - reach - offsets.reduce(max);
      final maxStep =
          tables.bandFor(templates.first.index).dy.$3 *
          min(ctx.band, RunConfig.dyRefBand) *
          RunConfig.hardHoopDyFactor;
      if (low <= high &&
          (previous.clamp(low, high) + templates.first.centreY - previous)
                  .abs() >
              maxStep) {
        templates = [
          for (final plan in templates)
            plan.copyWith(centreY: -plan.centreY, tiltDeg: -plan.tiltDeg),
        ];
      }
    }
    // D2's short-screen ceiling also applies inside a slalom. Keep the
    // alternating shape but fit its point-space steps to the live Δy cap.
    if (templates.first.formation == FormationId.slalom) {
      final maxStep =
          tables.bandFor(templates.first.index).dy.$3 *
          min(ctx.band, RunConfig.dyRefBand);
      var largest = 0.0;
      for (var k = 1; k < templates.length; k++) {
        largest = max(
          largest,
          (templates[k].centreY - templates[k - 1].centreY).abs(),
        );
      }
      if (largest > maxStep) {
        templates = [
          for (final plan in templates)
            plan.copyWith(centreY: plan.centreY * maxStep / largest),
        ];
      }
    }
    // The pure tilt template supplies angles; give the live wave a shallow
    // valley so both 30° ends have at least a 40 pt approach (D2 / D7) where the
    // band permits it. Keep its exit at the shared origin for a smooth handoff.
    final tiltWave = templates.first.formation == FormationId.tiltWave;
    if (tiltWave) {
      final step = 1.5 * TuningValues.current.d('tilt_align_min_dy');
      final offsets = [-step, -step, -step, -step, 0.0];
      templates = [
        for (var k = 0; k < templates.length; k++)
          templates[k].copyWith(centreY: offsets[k]),
      ];
    }
    final coreCentre = _coreCentre(ctx);
    final coreBand = min(ctx.band, LayoutConfig.courseRefBand);
    final coreTop = coreCentre - coreBand / 2;
    final coreFloor = coreCentre + coreBand / 2;
    var lo = double.negativeInfinity;
    var hi = double.infinity;
    final openings = <double>[];
    for (final plan in templates) {
      final opening = cap(
        (openingFor(plan.index) +
                (plan.kind == HoopKindId.saw ? RunConfig.sawExtraOpening : 0)) *
            _bigMult(plan.index, ctx),
      );
      openings.add(opening);
      final travel = plan.motion?.halfTravel ?? 0;
      final reach =
          opening / 2 + RunConfig.rimRadius + RunConfig.bandMargin + travel;
      final offset = tiltWave ? 0.0 : plan.centreY;
      lo = max(lo, coreTop + reach - offset);
      hi = min(hi, coreFloor - reach - offset);
      for (final attached in plan.attached) {
        final y = attached.y;
        if (y == null) continue;
        final offset = y - plan.centreY;
        lo = max(lo, coreTop + RunConfig.itemEdgeMargin - offset);
        hi = min(hi, coreFloor - RunConfig.itemEdgeMargin - offset);
      }
    }
    // Very short screens are still expected to fit every D7 shape; if a
    // degenerate band cannot, use its middle and let the hazard downgrade
    // (and the spawner's normal band clamps) protect the slot.
    final preferred = _lastFinalY ?? coreCentre;
    final base = lo <= hi ? preferred.clamp(lo, hi).toDouble() : coreCentre;
    return [
      for (var k = 0; k < templates.length; k++)
        _adaptFormationSlot(
          templates[k],
          index: templates[k].index,
          trackX: trackX + k * spacing,
          centreY: tiltWave
              ? (base + templates[k].centreY).clamp(lo, hi).toDouble()
              : base + templates[k].centreY,
          opening: openings[k],
        ),
    ];
  }

  SlotPlan _adaptFormationSlot(
    SlotPlan template, {
    required int index,
    required double trackX,
    required double centreY,
    required double opening,
  }) {
    assert(template.index == index);
    final attached = [
      for (final item in template.attached)
        GapItemPlan(
          kind: item.kind,
          trackX: trackX + item.trackX - template.trackX,
          y: item.y == null ? null : centreY + (item.y! - template.centreY),
          lineOffset: item.lineOffset,
          extra: item.extra,
          toTrackX: item.toTrackX == null
              ? null
              : trackX + item.toTrackX! - template.trackX,
          toY: item.toY,
        ),
    ];
    return template.copyWith(
      trackX: trackX,
      centreY: centreY,
      opening: opening,
      advance: spacing,
      attached: attached,
    );
  }

  /// PRD-2.6 D7 chapter weights, based on the live post-ceiling hard-family
  /// masses. The sum is kept constant, so the rotation changes the mix, not
  /// the hazard budget.
  Map<MixWeightKey, double> _chapterWeights(int hoop) {
    final saw = tables.specials[HoopKindId.saw]?.weightAt(hoop) ?? 0;
    final switching =
        tables.specials[HoopKindId.switchRing]?.weightAt(hoop) ?? 0;
    final moving = (tables.movingChance(hoop) * 100).round();
    return Formations.mixWeightsAt(hoop, {
      MixWeightKey.saw: saw,
      MixWeightKey.switchRing: switching,
      MixWeightKey.moving: moving,
    });
  }

  /// PRD-2.6 D7 the moving chance after the chapter rotation (before 150:
  /// the unchanged D2 curve).
  double _movingChance(int hoop) {
    if (hoop < 150) return tables.movingChance(hoop);
    return _chapterWeights(hoop)[MixWeightKey.moving]! / 100;
  }

  /// PRD-2.6 D7 the chapter-rotated hard-family special weights. The
  /// chapter is normalized from the live base masses, then the scaling is
  /// applied to [rule]; this keeps every other special's D2 weight intact.
  double _rotatedSpecialWeight(HoopKindId kind, SpecialRule rule, int hoop) {
    final base = rule.weightAt(hoop).toDouble();
    if (hoop < 150) return base;
    return _chapterWeights(hoop)[switch (kind) {
      HoopKindId.saw => MixWeightKey.saw,
      HoopKindId.switchRing => MixWeightKey.switchRing,
      _ => throw ArgumentError.value(kind, 'kind', 'not a hard special'),
    }]!;
  }

  /// The D2 motion roll, adjusted to the D7 chapter share past hoop 150.
  /// The ordinary roll is still made, then deterministically thinned or
  /// supplemented on [_chapterRandom]; a forced (debug / first-meet) moving
  /// ring bypasses the adjustment.
  MotionSpec? _chapterMotion(
    int i,
    DirectorContext ctx,
    double y,
    double opening, {
    required bool force,
  }) {
    final base = tables.movingChance(i);
    final target = _movingChance(i);
    if (force ||
        i < 150 ||
        (target - base).abs() < 1e-12 ||
        ctx.squeezeWindow) {
      return _layout.motion(i, ctx, y, opening, force: force);
    }
    final drawn = _layout.motion(i, ctx, y, opening);
    if (target > base) {
      if (drawn != null) return drawn;
      final chance = (target - base) / (1 - base);
      if (chance <= 0 || _chapterRandom.nextDouble() >= chance) return null;
      return _layout.motion(i, ctx, y, opening, force: true);
    }
    if (drawn == null || base <= 0) return null;
    final keep = target / base;
    return _chapterRandom.nextDouble() < keep ? drawn : null;
  }

  SlotPlan _calmSlot(
    SlotPlan planned,
    DirectorContext ctx, {
    required double? previousY,
  }) {
    final hoop = planned.index;
    final opening = min(
      openingFor(hoop) * _bigMult(hoop, ctx),
      ctx.band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin),
    );
    final median =
        tables.bandFor(hoop).dy.$1 * min(ctx.band, RunConfig.dyRefBand);
    final previous = previousY ?? (ctx.topTooth + ctx.floorTooth) / 2;
    final delta = planned.centreY - previous;
    final (lo, hi) = _layout.portableLimits(
      hoop,
      ctx,
      opening,
      useTable: false,
    );
    final target = previous + delta.sign * min(delta.abs(), median);
    final calmLo = max(lo, previous - median);
    final calmHi = min(hi, previous + median);
    final centre = calmLo <= calmHi
        ? target.clamp(calmLo, calmHi)
        : previous.clamp(lo, hi);
    return planned.copyWith(
      kind: HoopKindId.normal,
      element: ElementId.normalHoop,
      centreY: centre.clamp(lo, hi).toDouble(),
      opening: opening,
      tiltDeg: 0,
      motion: () => null,
      cometHang: false,
      ringOffsets: const [0],
      advance: spacing,
      extra: () => null,
      attached: const [],
      calm: true,
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
    var opening = openingFor(i);
    var extraMargin = 0.0;
    if (kind == HoopKindId.saw) opening += RunConfig.sawExtraOpening;
    // PRD-2.2 §25.1 the portal ring stays a big, easy 118 pt entrance at
    // every hoop (it took the shrinking normal opening before). PRD-2.4
    // §2.3 keeps it unchanged: 118 × the Big Hoops multiplier, as in 2.3.1
    // (the director stays free of Flame imports).
    if (kind == HoopKindId.portal) opening = RunConfig.portalOpening;
    final pairO =
        RunConfig.pairOffsetAt711 * ctx.viewHeight / RunConfig.designHeight;
    final placementPairO =
        RunConfig.pairOffsetAt711 *
        min(ctx.viewHeight, RunConfig.designHeight) /
        RunConfig.designHeight;
    if (kind == HoopKindId.pair) extraMargin = placementPairO / 2;
    // PRD-2.3 §0 item 3 / §10.2: hoop 0 stays 118, also with Big Hoops.
    opening = cap(opening * _bigMult(i, ctx), extraMargin);
    final hardFollowUp = _layout.takeHardFollowUp();
    var y = _layout.nextCentre(
      i,
      ctx,
      opening,
      extra: extraMargin,
      hardFollowUp: hardFollowUp,
    );
    final maxJump = _layout.maxDy(i, ctx, hardFollowUp: hardFollowUp);
    final approachDy = y - (prevY ?? y);

    Object? extra;
    var advance = spacing;
    var rings = const <double>[0];
    final attached = <GapItemPlan>[];

    // Kind-specific checks that need the centre (downgrade → normal).
    if (kind == HoopKindId.spring) {
      // region WP-3c — §3.23 "always with room for the next ring inside the
      // band": the 240 pt target is checked against the band rule (tooth
      // lines − opening / 2 − 7 − 18), not the row's centre range. The
      // landing ring's opening is the curve size of i + 1, which can be
      // smaller than this spring's (the portal / 45° / pair extras differ),
      // so check both openings and use the tighter bounds.
      (double, double) landingLimits(double landingOpening) =>
          _layout.portableLimits(i + 1, ctx, landingOpening, useTable: false);
      final nextOpening = min(
        openingFor(i + 1) * _bigMult(i + 1, ctx),
        ctx.band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin),
      );
      final (lo, hi) = landingLimits(nextOpening);
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
        final (lo0, hi0) = _layout.portableLimits(i, ctx, opening);
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
        _springLandingAt = i + 1;
      } else {
        kind = HoopKindId.normal; // §3.0.3 no room for the 240 pt jump
        forced = false;
      }
    } else if (kind == HoopKindId.pair) {
      final minY =
          ctx.hudBottom +
          placementPairO / 2 +
          opening / 2 +
          RunConfig.rimRadius;
      final (lo, hi) = _layout.portableLimits(
        i,
        ctx,
        opening,
        extra: extraMargin,
        useTable: false,
      );
      if (y < minY) y = min(minY, hi);
      final reach = prevY == null
          ? 0
          : min(
              (y - placementPairO / 2 - prevY).abs(),
              (y + placementPairO / 2 - prevY).abs(),
            );
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
        final (lo, hi) = _layout.portableLimits(i, ctx, opening);
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
        _switchBeforePlanned = _lastSwitch;
        final options = SwitchDesign.values
            .where((d) => d != _lastSwitch)
            .toList();
        final picked = options[r.nextInt(options.length)];
        final d = _forcedSwitch ?? picked;
        _forcedSwitch = null;
        _lastSwitch = d;
        extra = d;
        final (lo0, hi0) = _layout.portableLimits(
          i,
          ctx,
          opening,
          useTable: false,
        );
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
          _lastSwitch = _switchBeforePlanned;
          _switchBeforePlanned = null;
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
      } else {
        // 7. Modifiers (§3.0.2): tilt, then movement.
        if (_on(ElementId.angledRing)) {
          tilt = _layout.tilt(i, force: forceMod == ElementId.angledRing);
        }
        if (_on(ElementId.movingRing)) {
          motion = _chapterMotion(
            i,
            ctx,
            y,
            opening,
            force: forceMod == ElementId.movingRing,
          );
        }
        // PRD-2.6 D2 caps the rendered ring, not just its base tilt: the
        // motion's own angular swing must fit under the same 15° / 30° cap.
        final tiltLimit = _layout.maxBaseTilt(
          i,
          motion,
          squeeze: ctx.squeezeWindow,
        );
        tilt = _layout.alignedTilt(tilt, approachDy, tiltLimit);
        _layout.noteModifiers(motion: motion, tiltDeg: tilt);
        if (tilt.abs() == 45) {
          opening = cap(
            opening + TuningValues.current.i('tilt45_extra_opening'),
            extraMargin,
          );
        }
        if (tilt != 0) {
          _count('tilted');
        }
        if (motion != null) {
          _count('moving');
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

  bool _portalWaitingForHeadline(int hoop, DirectorContext ctx) {
    if (!_portalOn || portalCapped || hoop < _portalAt) return false;
    if (_rewardsBlocked(hoop, ctx) || _bigOpen(ctx)) return false;
    return !_headlineDue('ride', hoop);
  }

  /// PRD-2.6 D6: the scheduled first portal owns its headline window. A
  /// random big bonus in the preceding seven hoops would otherwise postpone
  /// the C3 introduction past its 12–25 first-appearance window.
  bool _reservesFirstPortal(int hoop) =>
      _portalOn &&
      !portalCapped &&
      _portalCount == 0 &&
      hoop < _portalAt &&
      hoop > _portalAt - 8;

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
    if (!ignoreUnlock &&
        rewardKinds.contains(k) &&
        k != HoopKindId.portal &&
        _reservesFirstPortal(i)) {
      return false;
    }
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
    if (ctx.squeezeWindow && !rule.allowedInSqueezeAt(i)) return false;
    if (k == HoopKindId.fever && (ctx.fever || _prevKind == HoopKindId.saw)) {
      return false;
    }
    if (k == HoopKindId.saw && _prevKind == HoopKindId.fever) return false;
    if (rule.blockedNearPortal > 0 && _nearPortal(i, rule.blockedNearPortal)) {
      return false;
    }
    if (rule.blockedNearPortal > 0 &&
        _portalWaitingForHeadline(i, ctx) &&
        _nearPortal(i, rule.blockedNearPortal + 5)) {
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
    if (mode == 0 && oneBigBonus && !_cometOwed && _bonusWaits) return false;
    if (mode == 0 && !_cometOwed) {
      if (rng.layout.nextDouble() >= rule.chance) return false;
      // PRD-2.2 §14.5 / PRD-2.6 D6: a drawn comet stays due. It skips the
      // chance roll until its headline can run, so deferring it does not
      // lose the drawn ride; its 18-hoop spacing still counts from the
      // previous comet.
      _cometOwed = true;
    }
    if (mode < 2 && !_headlineDue('ride', i)) return false;
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

  HoopKindId? _headlineWaitRing;
  String _headlineWaitRingId = '';
  int _headlineWaitRingDue = -1;
  ElementId? _headlineWaitItem;
  String _headlineWaitItemId = '';
  int _headlineWaitItemDue = -1;

  void _clearHeadlineWaitRing() {
    _headlineWaitRing = null;
    _headlineWaitRingId = '';
    _headlineWaitRingDue = -1;
  }

  void _clearHeadlineWaitItem() {
    _headlineWaitItem = null;
    _headlineWaitItemId = '';
    _headlineWaitItemDue = -1;
  }

  bool _headlineDue(String id, int hoop) {
    final forcedUntil = _forcedHeadlineAt == null ? -1 : _forcedHeadlineAt! + 8;
    if (hoop < forcedUntil) {
      return _headlineReservationId == id && hoop >= _headlineReservationDue;
    }
    if (_headline.allows(id, hoop)) return true;
    _headlineReservationId ??= id;
    if (_headlineReservationId == id && _headlineReservationDue < 0) {
      _headlineReservationDue = hoop + 5;
    }
    return false;
  }

  int _delayHeadline(String id, int hoop) {
    if (_headlineDue(id, hoop)) return hoop;
    return _headlineReservationId == id ? _headlineReservationDue : hoop + 5;
  }

  void _claimHeadline(String id, int hoop) {
    if (!_headline.allows(id, hoop)) _forcedHeadlineAt = hoop;
    _headline.add(id, hoop);
    _headlineReservationId = null;
    _headlineReservationDue = -1;
  }

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
  /// meanwhile ([ride]: the curve size of its index, PRD-2.4 §2) or when an
  /// activity started (its reward ring / comet star goes, §27.3). A portal
  /// or comet hoop that never showed stays due: it comes at the first
  /// allowed slot.
  ///
  /// [keepGeometry] (PRD-2.2 §16.1, S7-12): a comet ride started after the
  /// slot was planned. The slot is already planned, so it keeps its height,
  /// tilt and motion; only what §27 removes (the reward / special kind,
  /// gifts, attached items, the comet star) goes. Its size is the curve
  /// size of its index (PRD-2.4 §2), the height clamped into the band only
  /// if the opening needs it.
  SlotPlan plainSlot(
    SlotPlan p,
    DirectorContext ctx, {
    bool ride = false,
    bool keepGeometry = false,
  }) {
    if (_scriptedSlot(p.index)) return p.copyWith(duringRide: ride);
    if (p.kind == HoopKindId.portal) {
      // PRD-2.3.1 §17 the placed portal keeps counting; below the cap it
      // is owed again, at the cap nothing is owed.
      _lastPortal = -99;
      if (!portalCapped) {
        _portalAt = p.index;
        if (oneBigBonus) _portalWaiting = true;
        _forcedRide ??= p.extra is RideId ? p.extra! as RideId : null;
      }
    }
    if (p.cometHang) {
      _cometOwed = true;
      _lastComet = -99;
    }
    final band = ctx.band;
    // PRD-2.4 §2: the same curve size as any hoop of this index, ride or not.
    final opening = min(
      openingFor(p.index) * _bigMult(p.index, ctx),
      band - 2 * (RunConfig.rimRadius + RunConfig.bandMargin),
    );
    final m = opening / 2 + RunConfig.rimRadius + RunConfig.bandMargin;
    final coreCentre = _coreCentre(ctx);
    final coreBand = min(ctx.band, LayoutConfig.courseRefBand);
    final lo = coreCentre - coreBand / 2 + m,
        hi = coreCentre + coreBand / 2 - m;
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
      formation: () => null,
      advance: spacing,
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
    _lastPortal = -99;
    // PRD-2.3.1 §17 the placed portal keeps counting; at the cap nothing is
    // owed.
    if (portalCapped) return;
    _portalAt = min(_portalAt, _i);
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

  /// §3.0.3 gap step 0, before debug force and first-meet pulls.
  GapPlan nextGap(DirectorContext ctx, SlotPlan slot) {
    final baseline = _showcaseNormalSlot;
    _showcaseNormalSlot = null;
    final normal = _normalGap(ctx, baseline ?? slot);
    final plan = showcase;
    if (plan == null) return normal;
    final ids = [
      for (final item in plan.gapItems)
        if (item.gap == slot.index) ElementId.fromStorageId(item.id)!,
      if (plan.hearts.contains(slot.index)) ElementId.heart,
    ];
    if (ids.isEmpty && !_showcaseHeadline(slot.index)) return normal;
    if (ids.isEmpty && normal.items.every((item) => !isBigItem(item.kind))) {
      return normal;
    }
    for (final item in normal.items) {
      final key = item.kind.storageId;
      final count = (_spawned[key] ?? 1) - 1;
      if (count <= 0) {
        _spawned.remove(key);
      } else {
        _spawned[key] = count;
      }
    }
    final items = <GapItemPlan>[
      if (ids.isEmpty) ...normal.items.where((item) => !isBigItem(item.kind)),
    ];
    for (final item in items) {
      _count(item.kind.storageId);
    }
    for (final id in ids) {
      final capsule = CapsuleType.values.where((c) => c.element == id);
      final kind = id.isCapsuleType ? ElementId.capsule : id;
      final missing = [
        for (var b = 0; b < 4; b++)
          if (ctx.puzzleMask & (1 << b) == 0) b,
      ];
      items.add(
        GapItemPlan(
          kind: kind,
          trackX: id == ElementId.starTrail
              ? slot.lastRingX + RunConfig.starTrailInset
              : slot.lastRingX + spacing / 2,
          toTrackX: id == ElementId.starTrail
              ? slot.trackX + slot.advance - RunConfig.starTrailInset
              : null,
          extra: id == ElementId.starTrail
              ? RunConfig.starTrailStars
              : id == ElementId.puzzlePiece
              ? (missing.isEmpty ? 0 : missing.first)
              : capsule.isEmpty
              ? null
              : capsule.first,
        ),
      );
      _count(kind.storageId);
    }
    return GapPlan(index: slot.index, items: items);
  }

  GapPlan _normalGap(DirectorContext ctx, SlotPlan slot) {
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
    if (!used && !blocked && dbgIdx >= 0 && !_scriptedGap(g)) {
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
      var due = firstMeet.dueGap(g);
      if (due != null && !_headlineDue('first-meet', g)) {
        final wait = firstMeet.dueSince;
        if (wait == null || g - wait < 5) due = null;
      }
      final pool = tables.earlyPool;
      ElementId? pick;
      CapsuleType? capsule;
      final waiting = _waitItem;
      final headlineWaiting = _headlineWaitItem;
      if (waiting != null &&
          !(_reservesFirstPortal(g) && isBigItem(waiting)) &&
          _gapAllowed(waiting, g, ctx) &&
          (!isBigItem(waiting) || _headlineDue('big-bonus', g))) {
        // PRD-2.3 §17.3 rule 4 the waiting big item comes first.
        pick = waiting;
        _waitItem = null;
      } else if (headlineWaiting != null &&
          !(_reservesFirstPortal(g) && isBigItem(headlineWaiting)) &&
          g >= _headlineWaitItemDue &&
          _headlineDue(_headlineWaitItemId, g) &&
          _gapAllowed(headlineWaiting, g, ctx)) {
        pick = headlineWaiting;
        _clearHeadlineWaitItem();
      } else if (due != null && _gapAllowed(due, g, ctx)) {
        pick = due.isCapsuleType ? ElementId.capsule : due;
        if (due.isCapsuleType) {
          capsule = CapsuleType.values.firstWhere((c) => c.element == due);
        }
      } else if (pool != null && pool.covers(g)) {
        // PRD-2.2 §19.2 the early pool's Star Trail (drawn with the slot);
        // it may come from index 4 (its min distance still holds).
        if (_earlyPicks[g] == EarlyPick.starTrail && !_reservesFirstPortal(g)) {
          if (_gapAllowed(ElementId.starTrail, g, ctx, ignoreFrom: true)) {
            if (_headlineDue('big-bonus', g)) {
              pick = ElementId.starTrail;
            } else {
              _headlineWaitItem = ElementId.starTrail;
              _headlineWaitItemId = 'big-bonus';
              _headlineWaitItemDue = _delayHeadline('big-bonus', g);
            }
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
          final preferred = slot.calm && !isBigItem(e.key) ? 3 : 1;
          if (!(isBigItem(e.key) && _reservesFirstPortal(g)) &&
              (_gapAllowed(e.key, g, ctx) ||
                  (oneBigBonus &&
                      isBigItem(e.key) &&
                      _gapAllowed(e.key, g, ctx, ignoreOpen: true)))) {
            w[e.key] = e.value.weight * preferred;
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
        if (pick != null && isBigItem(pick) && !_headlineDue('big-bonus', g)) {
          _headlineWaitItem = pick;
          _headlineWaitItemId = 'big-bonus';
          _headlineWaitItemDue = _delayHeadline('big-bonus', g);
          pick = null;
        }
      }
      if (pick != null) {
        if (due != null && pick.storageId == due.storageId) {
          _claimHeadline('first-meet', g);
        } else if (isBigItem(pick)) {
          _claimHeadline('big-bonus', g);
        }
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
    if (pick == null ||
        _bonusWaits ||
        !isBigItem(pick) ||
        _reservesFirstPortal(g)) {
      return;
    }
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
