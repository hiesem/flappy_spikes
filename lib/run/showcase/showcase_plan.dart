import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../game/storage.dart';
import '../../menu/powerup_slot.dart';
import '../../services/ftue_tracker.dart';
import '../../services/obf_strings.g.dart';
import '../config/showcase_config.dart';
import '../director/plans.dart' show RideId;

/// A scripted gap item (B3). The ids are the director's stable element ids;
/// [gap] is the gap index after the hoop of the same number.
class ShowcaseGapItem {
  const ShowcaseGapItem(this.id, this.gap);

  final String id;
  final int gap;

  @override
  bool operator ==(Object other) =>
      other is ShowcaseGapItem && other.id == id && other.gap == gap;

  @override
  int get hashCode => Object.hash(id, gap);

  @override
  String toString() => 'ShowcaseGapItem($id @ $gap)';
}

/// A scripted portal ride: the hoop that starts it and its ride theme.
class ShowcasePortal {
  const ShowcasePortal({required this.hoop, required this.theme});

  final int hoop;
  final RideId theme;

  @override
  bool operator ==(Object other) =>
      other is ShowcasePortal && other.hoop == hoop && other.theme == theme;

  @override
  int get hashCode => Object.hash(hoop, theme);

  @override
  String toString() => 'ShowcasePortal(${theme.name} @ $hoop)';
}

/// Why a showcase finished (the `showcase_done.via` analytics value).
enum ShowcaseDoneVia { all, cap, fast }

/// The frozen plan for one showcase run.
class ShowcaseRunPlan {
  const ShowcaseRunPlan({
    required this.highlightId,
    required this.step,
    required this.attempt,
    this.extraStarters = const [],
    this.portalHoops = const [],
    this.cometHoops = const [],
    this.feverHoops = const [],
    this.bullseyeHoops = const [],
    this.gapItems = const [],
    this.hearts = const [],
    this.portals = const [],
    this.bigHoopsSeconds,
    this.freeRevive = true,
  });

  /// One of [ShowcaseConfig.highlightIds].
  final String highlightId;

  /// Zero-based script step (`0` portal, `1` comet, `2` FEVER).
  final int step;

  /// The run's attempt number for this step (1 is the first try).
  final int attempt;

  /// Starters to arm in addition to the consumed Home-slot powerup.
  final List<Powerup> extraStarters;

  /// B3 the scripted portal hoop slots (Cannon in step 1, Space in step 3).
  /// [portals] carries the theme of each one.
  final List<int> portalHoops;
  final List<int> cometHoops;
  final List<int> feverHoops;
  final List<int> bullseyeHoops;

  /// B3 the scripted gap items and hearts.
  final List<ShowcaseGapItem> gapItems;
  final List<int> hearts;

  /// B3 portal rides (both the step-1 Cannon and the step-3 Space one).
  final List<ShowcasePortal> portals;

  /// B2 Big Hoops duration; null means the normal 30–40 s roll.
  final double? bigHoopsSeconds;

  /// B2 the one free revive from the first death after hoop 0.
  final bool freeRevive;

  /// The gap indices of [id] (the director's element id, e.g. `star_trail`).
  List<int> gapsOf(String id) => [
    for (final item in gapItems)
      if (item.id == id) item.gap,
  ];

  @override
  bool operator ==(Object other) =>
      other is ShowcaseRunPlan &&
      other.highlightId == highlightId &&
      other.step == step &&
      other.attempt == attempt &&
      _listEquals(other.extraStarters, extraStarters) &&
      _listEquals(other.portalHoops, portalHoops) &&
      _listEquals(other.cometHoops, cometHoops) &&
      _listEquals(other.feverHoops, feverHoops) &&
      _listEquals(other.bullseyeHoops, bullseyeHoops) &&
      _listEquals(other.gapItems, gapItems) &&
      _listEquals(other.hearts, hearts) &&
      _listEquals(other.portals, portals) &&
      other.bigHoopsSeconds == bigHoopsSeconds &&
      other.freeRevive == freeRevive;

  @override
  int get hashCode => Object.hash(
    highlightId,
    step,
    attempt,
    Object.hashAll(extraStarters),
    Object.hashAll(portalHoops),
    Object.hashAll(cometHoops),
    Object.hashAll(feverHoops),
    Object.hashAll(bullseyeHoops),
    Object.hashAll(gapItems),
    Object.hashAll(hearts),
    Object.hashAll(portals),
    bigHoopsSeconds,
    freeRevive,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The B3 pure script builder. It only uses indices; the view height never
/// enters a plan (edge case "Tablets: scripted items go through the
/// director").
abstract final class ShowcaseScript {
  /// The plan for [step] and [attempt] (A = 1, A = 2, A ≥ 3).
  static ShowcaseRunPlan planFor(int step, int attempt) {
    if (step < 0 || step >= ShowcaseConfig.highlightIds.length) {
      throw RangeError.range(step, 0, ShowcaseConfig.highlightIds.length - 1);
    }
    final id = ShowcaseConfig.highlightIds[step];
    final key = ShowcaseConfig.attemptKey(attempt);
    int first(Map<String, List<int>> table) => table[key]!.first;

    final portalHoops = <int>[
      if (step == 0) first(ShowcaseConfig.portalHoops),
      if (step == 2) first(ShowcaseConfig.spacePortalHoops),
    ];
    final cometHoops = step == 1 ? [first(ShowcaseConfig.cometHoops)] : <int>[];
    final feverHoops = step == 2 ? [first(ShowcaseConfig.feverHoops)] : <int>[];
    final bullseyeHoops = step == 1
        ? [first(ShowcaseConfig.bullseyeHoops)]
        : <int>[];
    final gapItems = <ShowcaseGapItem>[
      for (final (id, gap) in ShowcaseConfig.gapItems[id]![key]!)
        ShowcaseGapItem(id, gap),
    ];
    final portals = <ShowcasePortal>[
      if (step == 0)
        ShowcasePortal(
          hoop: first(ShowcaseConfig.portalHoops),
          theme: ShowcaseConfig.portalTheme,
        ),
      if (step == 2)
        ShowcasePortal(
          hoop: first(ShowcaseConfig.spacePortalHoops),
          theme: ShowcaseConfig.feverPortalTheme,
        ),
    ];
    return ShowcaseRunPlan(
      highlightId: id,
      step: step,
      attempt: attempt,
      extraStarters: const [Powerup.bigHoops, Powerup.shield],
      portalHoops: portalHoops,
      cometHoops: cometHoops,
      feverHoops: feverHoops,
      bullseyeHoops: bullseyeHoops,
      gapItems: gapItems,
      hearts: List<int>.of(ShowcaseConfig.hearts[id]![key]!),
      portals: portals,
      bigHoopsSeconds: step == 0 ? ShowcaseConfig.portalBigHoopsSeconds : null,
      freeRevive: true,
    );
  }
}

/// Builds the showcase plan at START. The wave-1 implementation is inert and
/// always returns null; WP-B owns persistence, attempt counting and scripts.
abstract class ShowcasePlan {
  const ShowcasePlan();

  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  });
}

/// The default no-op planner used while the M1 skeleton is inert.
class InertShowcasePlan extends ShowcasePlan {
  const InertShowcasePlan();

  @override
  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  }) => null;
}

/// Persists highlight and run-end state. All wave-1 methods are no-ops.
abstract class ShowcaseProgress {
  const ShowcaseProgress();

  void onHighlight(String id, {required bool scripted, required int hoop});

  void onRunEnd({
    required int gamesPlayed,
    required int hoopsPassed,
    int score = 0,
    String cause = 'missed_hoop',
    bool shieldUsed = false,
    bool reviveUsed = false,
  });
}

/// Silent analytics sink for the showcase events. The game passes its
/// `GameServices.track`; tests pass a recorder.
typedef ShowcaseTracker =
    void Function(String event, Map<String, Object> parameters);

/// The persisted B1/B3 model. It is both the planner and the progress sink
/// so one instance can be injected in both seams; a separate progress
/// instance that uses the same [GameStorage] still sees the in-memory copy
/// (both read the same fields).
///
/// Every write updates [storage] synchronously and persists it
/// fire-and-forget (the game's START/run-end paths are synchronous). The
/// plan is frozen at START; [onHighlight] writes its bit immediately and
/// resets the step attempt for the next step.
class ShowcaseShow extends ShowcasePlan implements ShowcaseProgress {
  ShowcaseShow({
    required this.storage,
    this.tracker,
    this.ftueTracker = const InertFtueTracker(),
    this.secondsSinceInstall,
    this.maxGames,
    this.fastHoops,
  }) {
    _hadShowcaseState = _hasShowcaseState;
    if (_hadShowcaseState) {
      _processHasShowcaseState = true;
    }
    _detectReset();
  }

  final GameStorage storage;

  /// The silent analytics sink (null = no analytics).
  final ShowcaseTracker? tracker;

  FtueTracker ftueTracker;

  /// Overrides the `s_since_install` passed to analytics; the default reads
  /// [GameStorage.playtimeSeconds].
  final int Function()? secondsSinceInstall;

  /// Test / A-B overrides; null reads the baked tuning values.
  final int? maxGames;
  final int? fastHoops;

  /// Whether this model has ever seen (or created) showcase state. A legacy
  /// install has none; once the state disappears after being seen, the cause
  /// is "Delete my data", not a legacy install.
  bool _sawShowcaseState = false;
  bool _hadShowcaseState = false;
  bool _resetReplay = false;

  ShowcaseRunPlan? _active;
  bool _started = false;
  ShowcaseDoneVia? _pendingVia;

  /// Serialises the fire-and-forget preference writes, so a later reset can
  /// never be overtaken by an earlier increment.
  Future<void> _writes = Future<void>.value();

  int _writeEpoch = 0;

  static bool _processHasShowcaseState = false;

  @visibleForTesting
  static void resetProcessMemoryForTests() {
    _processHasShowcaseState = false;
  }

  bool get _hasShowcaseState =>
      storage.showcaseSeen != 0 ||
      storage.showcaseAttempt != 0 ||
      storage.showcaseRuns != 0 ||
      storage.showcaseDoneAt != null;

  void _detectReset() {
    final hasState = _hasShowcaseState;
    if (_processHasShowcaseState && !hasState) {
      _resetReplay = true;
      _sawShowcaseState = true;
      _writeEpoch++;
    } else if (_hadShowcaseState && !hasState) {
      _resetReplay = true;
      _sawShowcaseState = true;
      _writeEpoch++;
    } else if (hasState) {
      _sawShowcaseState = true;
      _processHasShowcaseState = true;
    }
    _hadShowcaseState = hasState;
  }

  /// Completes when every mirrored storage write has settled (tests).
  Future<void> get writesSettled => _writes;

  /// The plan frozen for the current run (tests / the director).
  ShowcaseRunPlan? get activePlan => _active;

  /// Whether a showcase run is active.
  bool get active => _active != null;

  int get _maxGames => maxGames ?? ShowcaseConfig.maxGames;
  int get _fastHoops => fastHoops ?? ShowcaseConfig.fastHoops;

  /// The first step whose bit is unset, or null when all three are set.
  int? get step => _stepFor(storage.showcaseSeen);

  int? _stepFor(int seen) {
    for (var i = 0; i < ShowcaseConfig.highlightIds.length; i++) {
      if (seen & (1 << i) == 0) return i;
    }
    return null;
  }

  /// A tester / existing install: three or more finished games and no
  /// showcase key at all. [adoptLegacyDone] turns this into explicit saved
  /// state before the first START.
  bool get isTesterInstall =>
      !_sawShowcaseState &&
      _isTesterFor(
        storage.gamesPlayed,
        storage.showcaseSeen,
        storage.showcaseAttempt,
      );

  bool _isTesterFor(int gamesPlayed, int seen, int attempt) =>
      gamesPlayed >= ShowcaseConfig.testerGamesPlayed &&
      seen == 0 &&
      attempt == 0 &&
      storage.showcaseRuns == 0 &&
      storage.showcaseDoneAt == null;

  /// Marks a tester install done without building a plan. Returns false when
  /// this is not a tester install (the caller then uses [atStart]).
  bool adoptLegacyDone([int? gamesPlayed]) {
    final finished = gamesPlayed ?? storage.gamesPlayed;
    if (_sawShowcaseState ||
        !_isTesterFor(
          finished,
          storage.showcaseSeen,
          storage.showcaseAttempt,
        )) {
      return false;
    }
    if (!done) {
      _markDone(finished, ShowcaseDoneVia.all);
    }
    _sawShowcaseState = true;
    return true;
  }

  /// Whether the safety net is finished (bit 7 or [storage.showcaseDoneAt]).
  bool get done =>
      storage.showcaseDoneAt != null ||
      storage.showcaseSeen & (1 << ShowcaseConfig.doneBit) != 0;

  @override
  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  }) {
    _detectReset();
    // A debug / e2e / tester start never builds or spends a showcase run.
    final shown =
        storage.showcaseDoneAt != null ||
        seen & (1 << ShowcaseConfig.doneBit) != 0;
    if (forced) {
      _active = null;
      return null;
    }
    if (!_resetReplay &&
        !_sawShowcaseState &&
        _isTesterFor(gamesPlayed, seen, attempt)) {
      // Testers / existing installs are done without ever building a plan.
      // This check comes before the done-bit check on purpose: after "Delete
      // my data" on such an install the safety net must not replay either.
      if (!done) {
        adoptLegacyDone(gamesPlayed);
        _active = null;
        return null;
      }
    }
    if (shown) {
      _active = null;
      return null;
    }
    // B1: the hard cap is checked at START (gamesPlayed is the finished
    // count; this run would be the next game).
    if (!_resetReplay && gamesPlayed >= _maxGames) {
      _markDone(gamesPlayed, ShowcaseDoneVia.cap);
      _active = null;
      return null;
    }
    final s = _stepFor(seen);
    if (s == null) {
      _markDone(gamesPlayed, ShowcaseDoneVia.all);
      _active = null;
      return null;
    }
    final a = attempt + 1;
    _active = ShowcaseScript.planFor(s, a);
    _started = false;
    _pendingVia = null;
    _sawShowcaseState = true;
    _processHasShowcaseState = true;
    storage.showcaseAttempt = a;
    _saveAttempt(a);
    _track('showcase_start', {'step': s + 1, 'attempt': a});
    return _active;
  }

  @override
  void onHighlight(String id, {required bool scripted, required int hoop}) {
    final plan = _active;
    if (plan == null) return;
    final bitIndex = ShowcaseConfig.highlightIds.indexOf(id);
    if (bitIndex < 0) return;
    final bit = 1 << bitIndex;
    if (!_started) {
      _started = id == plan.highlightId;
    }
    if (storage.showcaseSeen & bit == 0) {
      final next = storage.showcaseSeen | bit;
      storage.showcaseSeen = next;
      _saveSeen(next);
    }
    if (_started) {
      // The next step starts at A = 1 (a kill after the highlight must not
      // leave the next step at A = 2).
      if (storage.showcaseAttempt != 0) {
        storage.showcaseAttempt = 0;
        _saveAttempt(0);
      }
      if (_stepFor(storage.showcaseSeen) == null) {
        _pendingVia = ShowcaseDoneVia.all;
      }
    }
  }

  @override
  void onRunEnd({
    required int gamesPlayed,
    required int hoopsPassed,
    int score = 0,
    String cause = 'missed_hoop',
    bool shieldUsed = false,
    bool reviveUsed = false,
  }) {
    final plan = _active;
    if (plan == null) return;
    _active = null;
    final runs = storage.showcaseRuns + 1;
    storage.showcaseRuns = runs;
    _saveRuns(runs);
    _track('showcase_end', {
      'step': plan.step + 1,
      'attempt': plan.attempt,
      'hoops': hoopsPassed,
      'highlight': _started ? 1 : 0,
      'score': score,
      'cause': cause,
      'shield_used': shieldUsed ? 1 : 0,
      'revive_used': reviveUsed ? 1 : 0,
    });
    if (done) return;
    final via = _pendingVia ?? _doneReason(gamesPlayed, hoopsPassed);
    if (via != null) _markDone(gamesPlayed, via);
  }

  ShowcaseDoneVia? _doneReason(int gamesPlayed, int hoopsPassed) {
    if (hoopsPassed >= _fastHoops) return ShowcaseDoneVia.fast;
    final s = step;
    if (s == null) return ShowcaseDoneVia.all;
    if (gamesPlayed >= _maxGames) return ShowcaseDoneVia.cap;
    return null;
  }

  void _markDone(int gamesPlayed, ShowcaseDoneVia? via) {
    if (done) return;
    final reason = via ?? _doneReason(gamesPlayed, 0) ?? ShowcaseDoneVia.all;
    storage.showcaseDoneAt = gamesPlayed;
    _saveDoneAt(gamesPlayed);
    final bit = 1 << ShowcaseConfig.doneBit;
    if (storage.showcaseSeen & bit == 0) {
      final next = storage.showcaseSeen | bit;
      storage.showcaseSeen = next;
      _saveSeen(next);
    }
    _sendDone(reason);
    ftueTracker.step(FtueStep.showcaseDone, gamesPlayed: gamesPlayed);
  }

  void _sendDone(ShowcaseDoneVia via) {
    _track('showcase_done', {
      'runs': storage.showcaseRuns,
      's_since_install': secondsSinceInstall?.call() ?? storage.playtimeSeconds,
      'via': via.name,
    });
  }

  void _track(String event, Map<String, Object> parameters) {
    final sink = tracker;
    if (sink == null) return;
    try {
      sink(event, parameters);
    } catch (_) {
      // Analytics must never affect gameplay.
    }
  }

  void _saveSeen(int value) => _write((prefs) async {
    if (storage.showcaseSeen != value) {
      return;
    }
    await prefs.setInt(Obf.prefShowcaseSeen, value);
  });

  void _saveAttempt(int value) => _write((prefs) async {
    if (storage.showcaseAttempt != value) {
      return;
    }
    await prefs.setInt(Obf.prefShowcaseAttempt, value);
  });

  void _saveRuns(int value) => _write((prefs) async {
    if (storage.showcaseRuns != value) {
      return;
    }
    await prefs.setInt(Obf.prefShowcaseRuns, value);
  });

  void _saveDoneAt(int value) => _write((prefs) async {
    if (storage.showcaseDoneAt != value) {
      return;
    }
    await prefs.setInt(Obf.prefShowcaseDoneAt, value);
  });

  void _write(Future<void> Function(SharedPreferences prefs) write) {
    final epoch = _writeEpoch;
    _writes = _writes
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          if (epoch != _writeEpoch) return;
          await write(prefs);
        })
        .catchError((Object _) {});
  }
}

/// The default no-op progress sink.
class InertShowcaseProgress extends ShowcaseProgress {
  const InertShowcaseProgress();

  @override
  void onHighlight(String id, {required bool scripted, required int hoop}) {}

  @override
  void onRunEnd({
    required int gamesPlayed,
    required int hoopsPassed,
    int score = 0,
    String cause = 'missed_hoop',
    bool shieldUsed = false,
    bool reviveUsed = false,
  }) {}
}
