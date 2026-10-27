import 'dart:async';
import 'dart:math' as math;

import '../../menu/home_mode.dart';
import '../../menu/wallet.dart';
import '../../services/analytics_buckets.dart';
import '../../services/ftue_tracker.dart';
import '../config/run_config.dart';
import '../director/formations.dart';
import '../director/plans.dart';
import '../elements.dart';
import '../hoops/hoop.dart';
import '../mistakes.dart';
import '../pickups/pickup.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_state.dart';
import '../run_summary.dart';

/// The plan/state snapshot of one mistake (PRD-2.6 WP-A2 `run_fail`).
///
/// It is taken when the mistake happens, not when the run later ends or the
/// player revives: by then the squeeze / ride / course state has moved on.
class _FailSnapshot {
  const _FailSnapshot(this.params);

  final Map<String, Object> params;
}

/// Run-level analytics (PRD-2 §6, PRD-2.6 WP-A; ARCH §2.7).
///
/// Sends `run_fail` once for every mistake that would have ended the run,
/// `run_end`, `run_director_hoops` and `run_director_items` (each ≤ 25
/// parameters) at the end, `run_extra` with the per-run detail whose
/// per-pass counterpart would be too expensive, plus `coins_earned`
/// aggregated per (source, egg_x2) into one event each.
class AnalyticsRouter extends RunFeature {
  RunContext? _c;
  final Map<(CoinSource, bool), int> _coins = {};

  /// Hoop kinds and modifiers of `run_director_hoops` (+ rim_touches,
  /// perfect_pct).
  static const List<String> hoopKeys = [
    'normal_hoop',
    'bullseye',
    'train',
    'spring',
    'switch_ring',
    'pair',
    'fever',
    'lucky_spin',
    'saw',
    'portal',
    'comet',
    'tilted',
    'moving',
    // region anchors — append below
    // endregion anchors
  ];

  /// Gap item types of `run_director_items`.
  static const List<String> itemKeys = [
    'heart',
    'shield',
    'star_trail',
    'capsule',
    'egg',
    'piggy',
    'jar',
    'feather',
    'puzzle_piece',
    'piggy_coins',
    'firefly_swarm',
    // region anchors — append below
    // endregion anchors
  ];

  /// The 22 `run_fail` parameters, in the PRD's order.
  static const List<String> failKeys = [
    'hoop',
    'hb',
    'cause',
    'elem',
    'tilt_deg',
    'motion',
    'opening',
    'dy_pt',
    'squeeze_idx',
    'calm',
    'hazard_x10',
    'since_calm',
    'formation',
    'ride_exit',
    'new_elem',
    'outcome',
    'run_no',
    'gb',
    'level',
    'mode',
    'showcase',
    'speed',
  ];

  /// `gamesPlayed` when the run started (PRD-2.3 §14.8 `games_played`
  /// counts this run too; WP-A's `run_no` is the 1-based game number).
  int _gamesAtStart = 0;
  // region P26-J2
  int _levelAtStart = 0;
  int _levelPointsAtStart = 0;
  // endregion

  /// The elements the player had already met when this run started. The run
  /// itself adds every spawned element to `RunState.metElements`, so asking
  /// that set at failure time would always answer "not new".
  Set<ElementId> _metAtStart = const {};

  final Map<ElementId, _PendingFirstMeet> _pendingFirstMeets = {};

  /// Perfect passes per streak tier (1 … 10). The streak owner emits
  /// `StreakChanged` from inside the `HoopPassed` dispatch; the router
  /// attaches first, so it observes that nested event and records the tier
  /// without a per-pass analytics event.
  final List<int> _perfectByTier = List.filled(10, 0);
  bool _perfectPending = false;
  final List<int> _perfectUncounted = [];

  /// Spawned slot plans by slot index (train rings share one plan index).
  final Map<int, SlotPlan> _plans = {};
  final List<Hoop> _unannouncedHoops = [];
  final List<Pickup> _unannouncedPickups = [];
  // Remember which candidates came from the spawner so its live collection
  // remains authoritative even while removed objects are still fading out.
  final Set<Hoop> _spawnerHoops = {};
  final Set<Pickup> _spawnerPickups = {};
  Hoop? _announcingHoop;
  Pickup? _announcingPickup;
  int _calmCount = 0;
  int _maxHazardX10 = 0;

  int _highlights = 0;
  int _rideHoops = 0;
  int _squeezes = 0;
  int _coinsBonus = 0;
  int _maxSpeed = 0;
  int _revivesAd = 0;
  int _revivesCoin = 0;

  /// The most recent completed ride, for `run_fail.ride_exit`.
  double? _rideEndedAt;

  /// A death that has not been resolved by a revive or the run end yet.
  _FailSnapshot? _pendingFail;

  /// PRD-2.3 §14.8 a ratio with 2 decimals.
  static double ratio2(num a, num b) =>
      ((b <= 0 ? 0 : a / b) * 100).roundToDouble() / 100;

  @override
  void attach(RunContext c) {
    _c = c;
    _gamesAtStart = c.game.storage.gamesPlayed;
    // region P26-J2
    _levelAtStart = c.game.menu.levels.level;
    _levelPointsAtStart = c.game.menu.levels.points;
    // endregion
    _metAtStart = Set.of(c.s.metElements);
    c.run.pipeline.onResolved = _onResolved;
    c.events
      ..on<CoinsEarned>(_onCoins)
      ..on<ElementSpawned>(_onElementSpawned)
      ..on<HoopSpawned>(_onHoopSpawned)
      ..on<PickupSpawned>(_onPickupSpawned)
      ..on<HoopPassed>(_onHoopPassed)
      ..on<SavedHoopPassed>(_onSavedHoopPassed)
      ..on<PickupCollected>(_onPickupCollected)
      ..on<StreakChanged>(_onStreakChanged)
      ..on<SqueezePhaseChanged>(_onSqueezeChanged)
      ..on<RideEnded>(_onRideEnded)
      ..on<HighlightStarted>(_onHighlight)
      ..on<Revived>(_onRevived)
      ..on<RunEnded>(_onEnded);
  }

  // ------------------------------------------------------------ in-run

  void _onCoins(CoinsEarned e) {
    if (e.source.aggregatedInRun) {
      final key = (e.source, e.eggX2);
      _coins[key] = (_coins[key] ?? 0) + e.amount;
    }
    if (RunContext.paysPoints(e.source)) _coinsBonus += e.amount;
  }

  void _onHoopSpawned(HoopSpawned e) {
    final plan = e.plan;
    _unannouncedHoops.add(e.hoop);
    if (_c!.run.spawner.hoops.contains(e.hoop)) _spawnerHoops.add(e.hoop);
    if (_plans.containsKey(plan.index)) return;
    _plans[plan.index] = plan;
    if (plan.calm) _calmCount++;
    final hazard = (plan.hazardCost * 10).round();
    if (hazard > _maxHazardX10) _maxHazardX10 = hazard;
  }

  void _onElementSpawned(ElementSpawned e) {
    final c = _c;
    if (c == null || !e.onScreen) return;
    final hoop = _hoopFor(e.element);
    final pickup = hoop == null ? _pickupFor(e.element) : null;
    if (_metAtStart.contains(e.element)) return;
    final plan = hoop?.plan;
    final forced =
        c.run.setup.forced.contains(e.element) || (plan?.forced ?? false);
    final hoopIndex =
        plan?.index ??
        (pickup == null ? c.s.hoopIndex : _hoopForPickup(pickup)?.index) ??
        c.s.hoopIndex;
    _pendingFirstMeets.putIfAbsent(
      e.element,
      () => _PendingFirstMeet(
        element: e.element,
        hoopIndex: hoopIndex,
        forced: forced,
        sourceHoop: hoop,
        pickup: pickup,
        squeezeIndex: e.element == ElementId.squeeze ? c.s.squeeze.index : null,
      ),
    );
    c.game.ftueTracker.firstMeetEncountered(
      e.element,
      hoop: hoopIndex,
      games: _gamesAtStart + 1,
      forced: forced,
    );
    if (e.element == ElementId.saw) {
      c.game.ftueTracker.step(
        FtueStep.firstSaw,
        gamesPlayed: _gamesAtStart + 1,
      );
    } else if (e.element == ElementId.squeeze) {
      c.game.ftueTracker.step(
        FtueStep.firstSqueeze,
        gamesPlayed: _gamesAtStart + 1,
      );
    }
  }

  Hoop? _hoopFor(ElementId element) {
    if (element == ElementId.squeeze) return null;
    final live = _c!.run.spawner.hoops;
    _unannouncedHoops.removeWhere(
      (h) => _spawnerHoops.contains(h) && !live.contains(h),
    );
    if (element == ElementId.angledRing) {
      return _announcingHoop?.plan.tiltDeg == 0 ? null : _announcingHoop;
    }
    if (element == ElementId.movingRing) {
      return _announcingHoop?.plan.motion == null ? null : _announcingHoop;
    }
    Hoop? hoop;
    for (final candidate in _unannouncedHoops) {
      if (_spawnerHoops.contains(candidate) && !candidate.announced) continue;
      final matches = element == ElementId.angledRing
          ? candidate.plan.tiltDeg != 0
          : element == ElementId.movingRing
          ? candidate.plan.motion != null
          : candidate.plan.element == element;
      if (matches) {
        hoop = candidate;
        break;
      }
    }
    if (hoop != null) _unannouncedHoops.remove(hoop);
    if (hoop != null) _announcingHoop = hoop;
    return hoop;
  }

  Pickup? _pickupFor(ElementId element) {
    final live = _c!.run.spawner.pickups;
    _unannouncedPickups.removeWhere(
      (p) => _spawnerPickups.contains(p) && !live.contains(p),
    );
    final current = _announcingPickup;
    if (current != null &&
        current.id != element &&
        (!_spawnerPickups.contains(current) || live.contains(current)) &&
        _pickupMatches(current, element)) {
      return current;
    }
    Pickup? pickup;
    for (final candidate in _unannouncedPickups) {
      if (_spawnerPickups.contains(candidate) && !candidate.announced) continue;
      if (_pickupMatches(candidate, element)) {
        pickup = candidate;
        break;
      }
    }
    if (pickup != null) {
      _unannouncedPickups.remove(pickup);
      _announcingPickup = pickup;
    }
    return pickup;
  }

  static bool _pickupMatches(Pickup pickup, ElementId element) {
    if (pickup.id == element) return true;
    if (element == ElementId.capsule && pickup.id.isCapsuleType) return true;
    final extra = pickup.plan?.extra;
    return extra is CapsuleType && extra.element == element;
  }

  SlotPlan? _hoopForPickup(Pickup pickup) {
    final spawner = _c!.run.spawner;
    final item = pickup.plan;
    bool matches(GapItemPlan candidate) =>
        item != null &&
        candidate.trackX == item.trackX &&
        candidate.kind == item.kind &&
        candidate.extra == item.extra;
    // Attached items can precede their hoop; a gap item belongs to the gap's
    // index even when comet replanning has moved the neighbouring hoops.
    for (final slot in spawner.slotLog.reversed) {
      if (slot.attached.any(matches)) return slot;
    }
    for (final gap in spawner.gapLog.reversed) {
      if (gap.items.any(matches)) {
        for (final slot in spawner.slotLog.reversed) {
          if (slot.index == gap.index) return slot;
        }
      }
    }
    SlotPlan? host;
    for (final plan in _plans.values) {
      if (plan.trackX <= pickup.position.x &&
          (host == null || plan.index > host.index)) {
        host = plan;
      }
    }
    if (host != null || _plans.isEmpty) return host;
    return _plans.values.reduce((a, b) => a.index < b.index ? a : b);
  }

  void _onPickupSpawned(PickupSpawned e) {
    _unannouncedPickups.add(e.pickup);
    if (_c!.run.spawner.pickups.contains(e.pickup)) {
      _spawnerPickups.add(e.pickup);
    }
  }

  // region P26-A1
  void _onHoopPassed(HoopPassed e) {
    if (e.hoop != null) _resolveHoop(e.hoop!, survived: true);
    if (e.duringRide) _rideHoops++;
    _perfectPending = e.perfect;
    if (!e.perfect) {
      _perfectUncounted.clear();
      return;
    }
    _perfectUncounted.add(_scoredTier(e));
  }
  // endregion

  void _onSavedHoopPassed(SavedHoopPassed e) =>
      _resolveHoop(e.hoop, survived: true);

  void _onPickupCollected(PickupCollected e) {
    if (e.pickup == null) return;
    for (final meet in _pendingFirstMeets.values) {
      if (meet.pickup == e.pickup) _setSurvived(meet, true);
    }
  }

  void _resolveHoop(Hoop hoop, {required bool survived}) {
    for (final meet in _pendingFirstMeets.values) {
      if (meet.sourceHoop == hoop) _setSurvived(meet, survived);
    }
  }

  void _setSurvived(_PendingFirstMeet meet, bool survived) {
    if (meet.resolved) return;
    meet.resolved = true;
    meet.survived = survived;
    _c?.game.ftueTracker.firstMeetOutcome(meet.element, survived: survived);
  }

  void _onStreakChanged(StreakChanged e) {
    if (e.cause != StreakCause.pass && e.cause != StreakCause.fever) return;
    if (_perfectPending) {
      _perfectPending = false;
      final tier = e.newStreak.clamp(1, 10);
      _perfectByTier[tier - 1]++;
      if (_perfectUncounted.isNotEmpty) _perfectUncounted.removeLast();
    }
  }

  /// A FEVER pass can keep the streak on max(5, streak + 1), so it emits no
  /// `StreakChanged` and the handshake above has nothing to count. The
  /// summary's perfect total is authoritative; put any such pass in the
  /// tier it was scored at (its row's 5…10) so `run_extra` always sums to
  /// `run_end`'s perfect count.
  List<int> _perfectCounts(int perfectPasses) {
    final out = List.of(_perfectByTier);
    final counted = out.fold<int>(0, (sum, n) => sum + n);
    final missing = perfectPasses - counted;
    for (var i = 0; i < missing; i++) {
      final tier = i < _perfectUncounted.length
          ? _perfectUncounted[i]
          : (_c?.s.streak ?? 1).clamp(1, 10);
      out[tier - 1]++;
    }
    return out;
  }

  /// The tier a perfect pass scores at: the ordinary streak increment before
  /// `StreakFeature` boosts a FEVER ring to at least ×5.
  int _scoredTier(HoopPassed e) {
    final streak = _c?.s.streak ?? 0;
    return (e.hoop?.plan.kind == HoopKindId.fever
            ? math.max(streak + 1, 5)
            : streak + 1)
        .clamp(1, 10);
  }

  void _onSqueezeChanged(SqueezePhaseChanged e) {
    if (e.phase == SqueezePhase.warning) _squeezes++;
    for (final meet in _pendingFirstMeets.values) {
      if (meet.element != ElementId.squeeze || meet.resolved) continue;
      // SqueezeFeature advances the index before emitting idle.
      if (e.phase == SqueezePhase.idle &&
          e.index == meet.squeezeIndex! + 1 &&
          meet.sawOpening) {
        _setSurvived(meet, true);
      } else if (e.index == meet.squeezeIndex &&
          e.phase == SqueezePhase.opening) {
        meet.sawOpening = true;
      }
    }
  }

  void _onRideEnded(RideEnded e) {
    final c = _c;
    if (c != null) _rideEndedAt = c.s.runClock;
  }

  void _onHighlight(HighlightStarted e) {
    _highlights++;
    final c = _c;
    if (c == null) return;
    c.game.ftueTracker.highlight(
      e.id,
      scripted: e.scripted,
      runNo: _gamesAtStart + 1,
      hoop: e.hoop,
    );
    if (_gamesAtStart == 0) {
      c.game.ftueTracker.step(
        FtueStep.run1Highlight,
        gamesPlayed: _gamesAtStart + 1,
      );
    }
  }

  // ------------------------------------------------------------ mistakes

  void _onResolved(Mistake m, MistakeResolution outcome) {
    final c = _c;
    if (c == null) return;
    final snapshot = _snapshotFail(m, outcome);
    if (m.hoop != null) {
      _resolveHoop(m.hoop!, survived: outcome != MistakeResolution.end);
    }
    if (outcome == MistakeResolution.end &&
        c.s.squeeze.phase != SqueezePhase.idle) {
      for (final meet in _pendingFirstMeets.values) {
        if (meet.element == ElementId.squeeze &&
            meet.squeezeIndex == c.s.squeeze.index) {
          _setSurvived(meet, false);
        }
      }
    }
    if (outcome == MistakeResolution.end) {
      // A death is not final yet: [Revived] replaces this with the paid
      // outcome, while the idempotent [RunEnded] confirms `end`.
      _pendingFail = snapshot;
      return;
    }
    c.track('run_fail', snapshot.params);
  }

  _FailSnapshot _snapshotFail(Mistake m, MistakeResolution outcome) {
    final c = _c!;
    final s = c.s;
    final plan = m.hoop?.plan ?? _nextHoopPlan();
    final index = plan?.index ?? s.hoopIndex;
    final previous = _previousPlan(plan);
    final motion = plan?.motion;
    return _FailSnapshot({
      'hoop': index,
      'hb': AnalyticsBuckets.hoopBucket(index),
      'cause': m.cause.analyticsName,
      'elem': plan?.element.storageId ?? 'none',
      'tilt_deg': (plan?.tiltDeg ?? 0).round(),
      'motion': motion == null ? 'none' : _snake(motion.type.name),
      'opening': (plan?.opening ?? RunConfig.openingFor(index)).round(),
      'dy_pt': previous == null
          ? 0
          : ((plan?.centreY ?? previous.centreY) - previous.centreY)
                .abs()
                .round(),
      'squeeze_idx': s.squeeze.phase == SqueezePhase.idle
          ? -1
          : s.squeeze.index,
      'calm': plan?.calm == true ? 1 : 0,
      'hazard_x10': ((plan?.hazardCost ?? 0) * 10).round(),
      'since_calm': _sinceCalm(index),
      'formation': _formationName(plan?.formation),
      'ride_exit': _rideExit(s.runClock),
      'new_elem': _newElement(plan?.element),
      'outcome': _outcomeName(outcome),
      'run_no': _gamesAtStart + 1,
      'gb': AnalyticsBuckets.gamesBucket(_gamesAtStart + 1),
      'level': 0,
      'mode': c.game.homeMode.analytics,
      'showcase': _showcase(c),
      'speed': s.forwardSpeed.round(),
    });
  }

  SlotPlan? _nextHoopPlan() {
    final c = _c;
    if (c == null) return null;
    final Hoop? hoop = c.run.spawner.nextHoopAhead();
    return hoop?.plan;
  }

  /// The nearest earlier spawned slot, excluding other rings of the same
  /// train / pair group.
  SlotPlan? _previousPlan(SlotPlan? plan) {
    if (plan == null) return null;
    SlotPlan? previous;
    for (final p in _plans.values) {
      if (p.index >= plan.index) continue;
      if (previous == null || p.index > previous.index) previous = p;
    }
    return previous;
  }

  int _sinceCalm(int index) {
    var calm = -1;
    for (final plan in _plans.values) {
      if (plan.index > index) continue;
      if (plan.calm && plan.index > calm) calm = plan.index;
    }
    return calm < 0 ? -1 : index - calm;
  }

  int _rideExit(double now) {
    final at = _rideEndedAt;
    if (at == null) return -1;
    return math.max(0, (now - at).round());
  }

  String _newElement(ElementId? element) {
    if (element == null || _metAtStart.contains(element)) return 'none';
    return element.storageId;
  }

  static String _formationName(FormationId? id) =>
      id == null ? 'none' : _snake(id.name);

  static String _outcomeName(MistakeResolution outcome) => switch (outcome) {
    MistakeResolution.shield => 'shield',
    MistakeResolution.life => 'life',
    MistakeResolution.reviveAd => 'revive_ad',
    MistakeResolution.reviveCoins => 'revive_coins',
    MistakeResolution.reviveFree => 'revive_free',
    MistakeResolution.end => 'end',
  };

  static int _showcase(RunContext c) {
    final plan = c.run.setup.showcase;
    return plan == null ? 0 : plan.step + 1;
  }

  static String _snake(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final ch = value[i];
      final upper = ch.toUpperCase() == ch && ch.toLowerCase() != ch;
      if (upper && i > 0) out.write('_');
      out.write(ch.toLowerCase());
    }
    return out.toString();
  }

  void _onRevived(Revived e) {
    final c = _c;
    final pending = _pendingFail;
    if (c == null || pending == null) return;
    _pendingFail = null;
    final outcome = e.kind == ReviveKind.ad
        ? 'revive_ad'
        : e.price == 0
        ? 'revive_free'
        : 'revive_coins';
    if (e.kind == ReviveKind.ad) {
      _revivesAd++;
    } else if (e.price > 0) {
      _revivesCoin++;
    }
    pending.params['outcome'] = outcome;
    c.track('run_fail', pending.params);
  }

  // ------------------------------------------------------------ run end

  void _onEnded(RunEnded e) {
    final c = _c;
    if (c == null) return;
    final pending = _pendingFail;
    _pendingFail = null;
    if (pending != null) c.track('run_fail', pending.params);

    final s = e.summary;
    for (final meet in _pendingFirstMeets.values) {
      c.game.ftueTracker.firstMeet(
        meet.element,
        hoop: meet.hoopIndex,
        games: _gamesAtStart + 1,
        forced: meet.forced,
        survived: meet.survived,
      );
    }
    _pendingFirstMeets.clear();
    if (c.game.homeMode == HomeMode.versus) {
      c.game.ftueTracker.step(
        FtueStep.versusFirstEnd,
        gamesPlayed: _gamesAtStart + 1,
      );
    }
    c.track('run_end', {
      'cause': s.cause.analyticsName,
      'hoop_index': s.hoopIndex,
      'hoop_kind': s.hoopKind?.element.storageId ?? 'none',
      'run_s': s.runSeconds.round(),
      // PRD-2.2 §13.6 score = points; hoops = the hoop count.
      'score': s.score,
      'hoops': s.hoopsPassed,
      'max_streak': s.maxStreak,
      // PRD-2.2 §11.4 (PRD-2.6 WP-A keeps this; opening_end / speed_end /
      // games_played make room for the new fields instead).
      'clean_passes': s.cleanPasses,
      'coins': s.coins,
      'saves': s.saves,
      // PRD-2.2 §19.3 the feather / piece came this run (0 / 1).
      'feather': c.s.featherSpawned ? 1 : 0,
      'piece': c.s.pieceSpawned ? 1 : 0,
      // PRD-2.3 §14.8 the budget and difficulty checks.
      'coins_per_hoop': ratio2(s.coins, s.hoopsPassed < 1 ? 1 : s.hoopsPassed),
      'perfect_rate': ratio2(s.perfectPasses, s.passes),
      // PRD-2.6 WP-A2.
      'mode': c.game.homeMode.analytics,
      'showcase': _showcase(c),
      'hb': AnalyticsBuckets.hoopBucket(s.hoopsPassed),
      'highlights': _highlights,
      'calm_count': _calmCount,
      'max_hazard_x10': _maxHazardX10,
      'revives_ad': _revivesAd,
      'revives_coin': _revivesCoin,
      // region P26-J2
      'level': _levelAtStart,
      'lvl_pts_before': _levelPointsAtStart,
      // endregion
      // region P26-K
      'beat_best_hoop': c.run.beatBestHoop,
      // endregion
    });
    final perfects = _perfectCounts(s.perfectPasses);
    c.track('run_extra', {
      for (var tier = 1; tier <= 10; tier++)
        'perfect_$tier': perfects[tier - 1],
      'ride_hoops': _rideHoops,
      'squeezes': _squeezes,
      'max_speed': _maxSpeed,
      'coins_bonus': _coinsBonus,
      'formations': _formationCount(),
      // region P26-A1
      'downgraded': c.director.downgrades,
      // endregion
    });
    c.track('run_director_hoops', {
      for (final k in hoopKeys) k: s.spawned[k] ?? 0,
      'rim_touches': s.rimTouches,
      'perfect_pct': s.passes == 0
          ? 0
          : (100 * s.perfectPasses / s.passes).round(),
    });
    c.track('run_director_items', {
      for (final k in itemKeys) k: s.spawned[k] ?? 0,
    });
    for (final entry in _coins.entries) {
      final (source, x2) = entry.key;
      c.track('coins_earned', {
        'amount': entry.value,
        'source': source.analyticsName,
        'egg_x2': x2 ? 1 : 0,
      });
    }
    _coins.clear();
    _setUserProperties(c, s);
  }

  void _setUserProperties(RunContext c, RunSummary s) {
    final services = c.game.services;
    // region P26-A1
    final bestHoops = c.run.countsForAchievements
        ? math.max(c.game.storage.bestHoops, s.hoopsPassed)
        : c.game.storage.bestHoops;
    // endregion
    if (c.run.countsForAchievements) {
      unawaited(c.game.storage.saveBestHoops(bestHoops));
    }
    // region P26-J2
    services.setUserProperty('fs_level', '${c.game.storage.lvlIndex}');
    // endregion
    services.setUserProperty(
      'fs_gb',
      AnalyticsBuckets.gamesBucket(_gamesAtStart + 1),
    );
    services.setUserProperty(
      'fs_best_hb',
      AnalyticsBuckets.hoopBucket(bestHoops),
    );
    services.setUserProperty(
      'fs_showcase',
      c.game.storage.showcaseDoneAt == null ? '0' : '1',
    );
    // region P26-H
    services.setUserProperty('fs_arm', c.game.storage.abArmV1);
    // endregion
  }

  /// Counts formation *starts* (a formation's slots share one id), not its
  /// individual hoops.
  int _formationCount() {
    final indices = _plans.keys.toList()..sort();
    FormationId? previous;
    var count = 0;
    for (final index in indices) {
      final id = _plans[index]!.formation;
      if (id != null && id != previous) count++;
      previous = id;
    }
    return count;
  }

  @override
  void update(double gameDt, double realDt) {
    final speed = _c?.s.forwardSpeed.round() ?? 0;
    if (speed > _maxSpeed) _maxSpeed = speed;
  }

  @override
  void detach() {
    final c = _c;
    if (c != null) {
      if (c.run.pipeline.onResolved == _onResolved) {
        c.run.pipeline.onResolved = null;
      }
      c.events
        ..off<CoinsEarned>(_onCoins)
        ..off<ElementSpawned>(_onElementSpawned)
        ..off<HoopSpawned>(_onHoopSpawned)
        ..off<PickupSpawned>(_onPickupSpawned)
        ..off<HoopPassed>(_onHoopPassed)
        ..off<SavedHoopPassed>(_onSavedHoopPassed)
        ..off<PickupCollected>(_onPickupCollected)
        ..off<StreakChanged>(_onStreakChanged)
        ..off<SqueezePhaseChanged>(_onSqueezeChanged)
        ..off<RideEnded>(_onRideEnded)
        ..off<HighlightStarted>(_onHighlight)
        ..off<Revived>(_onRevived)
        ..off<RunEnded>(_onEnded);
    }
    _c = null;
  }
}

final class _PendingFirstMeet {
  _PendingFirstMeet({
    required this.element,
    required this.hoopIndex,
    required this.forced,
    required this.sourceHoop,
    required this.pickup,
    required this.squeezeIndex,
  });

  final ElementId element;
  final int hoopIndex;
  final bool forced;
  final Hoop? sourceHoop;
  final Pickup? pickup;
  final int? squeezeIndex;
  bool resolved = false;
  bool survived = false;
  bool sawOpening = false;
}
