import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../game/flappy_game.dart';
import '../mistakes.dart';
import '../run_controller.dart';
import '../run_events.dart';
import 'autopilot.dart';

/// Turns the perfect autopilot's base flap requests into a deterministic
/// human-noise schedule, with Gaussian jitter (early as well as late). Each
/// base flap has a chance of producing one extra flap shortly after it.
@visibleForTesting
class HumanNoiseFlapScheduler {
  HumanNoiseFlapScheduler({
    required this.seed,
    this.jitterSigma = HumanNoiseBot.jitterSigma,
    this.extraFlapChance = HumanNoiseBot.extraFlapChance,
  }) : _random = math.Random(seed);

  final int seed;
  final double jitterSigma;
  final double extraFlapChance;
  final math.Random _random;

  /// The nominal (pre-jitter) base-flap times, in planning order.
  final List<double> plannedFlapTimes = [];

  /// Every emitted flap, including extras (the execution trace).
  final List<double> flapTimes = [];

  /// Emitted base-flap time minus its planned time. Extras are excluded; this
  /// is the timing distribution the human-noise bot must have.
  final List<double> baseFlapOffsets = [];

  /// The raw Gaussian draws (debug / diagnostics only).
  final List<double> jitterSeconds = [];

  final List<_ScheduledFlap> _scheduled = [];

  int extraFlaps = 0;
  double? _lastDelay;
  int _nextBaseId = 0;

  bool get hasPendingBase => _scheduled.any((flap) => !flap.extra);
  int get pendingBases => _scheduled.where((flap) => !flap.extra).length;
  int get pendingFlaps => _scheduled.length;
  bool get nextDueIsExtra => _scheduled.isNotEmpty && _scheduled.first.extra;
  double? get pendingBasePlannedTime {
    for (final flap in _scheduled) {
      if (!flap.extra) return flap.plannedTime;
    }
    return null;
  }

  /// Registers an autopilot flap intended at [plannedTime].
  ///
  /// [now] is the frame the schedule was made. A negative jitter can make the
  /// flap due before the autopilot's request, but not before [now] (the
  /// scheduler cannot act in the past).
  void planBase(double plannedTime, {double? now}) {
    final jitter = _gaussian() * jitterSigma;
    final jitteredTime = plannedTime + jitter;
    final extra = _random.nextDouble() < extraFlapChance;
    plannedFlapTimes.add(plannedTime);
    jitterSeconds.add(jitter);
    final at = math.max(jitteredTime, math.max(0.0, now ?? 0.0));
    final id = _nextBaseId++;
    _scheduled.add(
      _ScheduledFlap(
        at,
        extra: false,
        plannedTime: plannedTime,
        jitter: jitter,
        baseId: id,
      ),
    );
    if (extra) {
      _scheduled.add(
        _ScheduledFlap(
          at + HumanNoiseBot.extraFlapGap,
          extra: true,
          baseId: id,
        ),
      );
    }
    _scheduled.sort((a, b) => a.time.compareTo(b.time));
  }

  /// Emits one flap that is due at or before [now], or returns false.
  bool flapDue(double now) {
    if (_scheduled.isEmpty || _scheduled.first.time > now) return false;
    final flap = _scheduled.removeAt(0);
    final at = math.max(flap.time, now);
    flapTimes.add(at);
    final planned = flap.plannedTime;
    if (planned == null) {
      extraFlaps++;
    } else {
      baseFlapOffsets.add(at - planned);
    }
    return true;
  }

  // region P26-D-BOT
  double _drawJitter() {
    final jitter = _gaussian() * jitterSigma;
    jitterSeconds.add(jitter);
    return jitter;
  }

  /// Record a closed-loop base action against its fresh nominal decision.
  /// Extras are scheduled from the emitted tap, never a stale forecast.
  void _emitBase(double now, double plannedTime) {
    plannedFlapTimes.add(plannedTime);
    flapTimes.add(now);
    baseFlapOffsets.add(now - plannedTime);
    if (_random.nextDouble() < extraFlapChance) {
      _scheduled.add(
        _ScheduledFlap(now + HumanNoiseBot.extraFlapGap, extra: true),
      );
      _scheduled.sort((a, b) => a.time.compareTo(b.time));
    }
  }
  // endregion

  double _gaussian() {
    final reuse = _lastDelay;
    if (reuse != null) {
      _lastDelay = null;
      return reuse;
    }
    var u1 = _random.nextDouble();
    final u2 = _random.nextDouble();
    while (u1 == 0) {
      u1 = _random.nextDouble();
    }
    final radius = math.sqrt(-2 * math.log(u1));
    final angle = 2 * math.pi * u2;
    _lastDelay = radius * math.sin(angle);
    return radius * math.cos(angle);
  }
}

/// The shared imperfect bot (PRD-2.6 §0.3 item 4). It wraps—not replaces—the
/// hoop-aware [Autopilot], then applies deterministic timing noise and extra
/// flaps. This library is intentionally referenced only by tests (and later
/// debug-only showcase/ceiling tooling), never by release paths.
@visibleForTesting
class HumanNoiseBot {
  // region P26-D-BOT
  HumanNoiseBot(
    this.run, {
    int seed = 7,
    double jitterSigma = HumanNoiseBot.jitterSigma,
    double extraFlapChance = HumanNoiseBot.extraFlapChance,
  }) : autopilot = Autopilot(run),
       scheduler = HumanNoiseFlapScheduler(
         seed: seed,
         jitterSigma: jitterSigma,
         extraFlapChance: extraFlapChance,
       );

  static const double jitterSigma = .09;
  static const double extraFlapChance = .1;
  static const double extraFlapGap = .08;

  final RunController run;
  final Autopilot autopilot;
  final HumanNoiseFlapScheduler scheduler;

  double? _jitter;
  double? _wantSince;
  bool _forecastRecorded = false;
  final List<double> debugRequestTimes = [];
  final List<double> debugRequestForecast = [];

  List<double> get flapTimes => scheduler.flapTimes;
  List<double> get baseFlapOffsets => scheduler.baseFlapOffsets;
  List<double> get plannedFlapTimes => scheduler.plannedFlapTimes;
  int get extraFlaps => scheduler.extraFlaps;

  /// Re-read the real trajectory every frame, retaining one noise draw until
  /// a tap executes. Positive noise waits from the controller's current request;
  /// negative noise anticipates its fresh forecast. Re-adding positive jitter
  /// to each forecast would keep pushing the deadline away forever.
  bool shouldFlap() {
    final now = run.state.runClock;
    final delay = autopilot.nextFlapDelay();
    final wanted = delay == 0;
    if (delay != null && !_forecastRecorded) {
      debugRequestTimes.add(now);
      debugRequestForecast.add(delay);
      _forecastRecorded = true;
    }
    if (scheduler.flapDue(now)) {
      _afterFlap();
      return true;
    }
    if (delay == null) {
      _wantSince = null;
      return false;
    }
    final jitter = _jitter ??= scheduler._drawJitter();
    if (wanted) {
      _wantSince ??= now;
      if (now - _wantSince! < jitter) return false;
    } else {
      _wantSince = null;
      if (jitter >= 0 || delay > -jitter) return false;
    }
    scheduler._emitBase(now, _wantSince ?? now + delay);
    _afterFlap();
    return true;
  }

  void _afterFlap() {
    autopilot.replanAfterFlap();
    _jitter = null;
    _wantSince = null;
    _forecastRecorded = false;
  }
  // endregion
}

/// The outcome of [flyHumanNoiseBotToDeath].
@visibleForTesting
class HumanNoiseBotResult {
  HumanNoiseBotResult({
    required this.hoops,
    required this.cause,
    required this.highlightIds,
    required this.seconds,
    required this.flaps,
    required this.extraFlaps,
    required this.baseFlapOffsets,
  });

  final int hoops;
  final MistakeCause? cause;
  final Set<String> highlightIds;
  final double seconds;
  final int flaps;
  final int extraFlaps;
  final List<double> baseFlapOffsets;
}

/// Fixed-steps a started run with [HumanNoiseBot] until its first death (or
/// [maxSeconds]) and records the showcase highlights emitted on the way.
@visibleForTesting
Future<HumanNoiseBotResult> flyHumanNoiseBotToDeath(
  FlappySpikesGame game, {
  int seed = 7,
  double dt = 1 / 60,
  double maxSeconds = 120,
  // region P26-D-BOT
  double jitterSigma = HumanNoiseBot.jitterSigma,
  double extraFlapChance = HumanNoiseBot.extraFlapChance,
  // endregion
  void Function(RunController run)? onFrame,
}) async {
  final run = game.run;
  if (run == null) {
    throw StateError('flyHumanNoiseBotToDeath expects a started run');
  }

  // region P26-D-BOT
  final bot = HumanNoiseBot(
    run,
    seed: seed,
    jitterSigma: jitterSigma,
    extraFlapChance: extraFlapChance,
  );
  // endregion
  final highlights = <String>{};
  MistakeCause? cause;
  var died = false;
  void listen(RunEvent event) {
    switch (event) {
      case HighlightStarted(:final id):
        highlights.add(id);
      case RunDied(:final mistake):
        cause ??= mistake.cause;
        died = true;
      default:
        break;
    }
  }

  run.events.onAny(listen);
  var seconds = 0.0;
  var frame = 0;
  try {
    while (seconds < maxSeconds - 1e-9 &&
        game.state == GameState.playing &&
        !died
    // A held ride keeps the run playing without changing runClock; drive
    // it with the same fixed clock until normal flight returns.
    ) {
      if (bot.shouldFlap()) game.onScreenTap();
      game.update(dt);
      seconds += dt;
      onFrame?.call(run);
      if (++frame % 10 == 0) {
        // Drain component onLoad chains before advancing the fixed clock.
        // Ride/hoop children can take several microtasks to mount.
        for (var pending = 0; pending < 10; pending++) {
          await Future<void>.value();
          game.update(0);
        }
      }
    }
  } finally {
    run.events.offAny(listen);
  }

  return HumanNoiseBotResult(
    hoops: run.state.hoopsPassed,
    cause: cause,
    highlightIds: highlights,
    seconds: seconds,
    flaps: bot.flapTimes.length,
    extraFlaps: bot.extraFlaps,
    baseFlapOffsets: List.of(bot.baseFlapOffsets),
  );
}

final class _ScheduledFlap {
  _ScheduledFlap(
    this.time, {
    required this.extra,
    this.plannedTime,
    this.jitter = 0,
    this.baseId,
  });

  double time;
  final bool extra;
  double? plannedTime;
  final double jitter;
  final int? baseId;
}
