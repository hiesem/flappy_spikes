import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../game/flappy_game.dart';
import '../mistakes.dart';
import '../run_controller.dart';
import '../run_events.dart';
import 'autopilot.dart';

/// Turns the perfect autopilot's base flap requests into a deterministic
/// human-noise schedule: each request is delayed by Gaussian jitter and has a
/// chance of producing one extra flap shortly after it.
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

  final List<double> plannedFlapTimes = [];
  final List<double> flapTimes = [];
  final List<double> jitterSeconds = [];
  final List<_ScheduledFlap> _scheduled = [];

  int extraFlaps = 0;
  double? _lastDelay;

  /// Registers an autopilot flap requested at [plannedTime].
  void planBase(double plannedTime) {
    final jitter = _gaussian() * jitterSigma;
    final jitteredTime = plannedTime + jitter;
    final extra = _random.nextDouble() < extraFlapChance;
    plannedFlapTimes.add(plannedTime);
    jitterSeconds.add(jitter);
    _scheduled.add(_ScheduledFlap(jitteredTime, extra: false));
    if (extra) {
      _scheduled.add(
        _ScheduledFlap(jitteredTime + HumanNoiseBot.extraFlapGap, extra: true),
      );
    }
    _scheduled.sort((a, b) => a.time.compareTo(b.time));
  }

  /// Returns a flap whose delayed time is due at or before [now], or null.
  bool flapDue(double now) {
    if (_scheduled.isEmpty || _scheduled.first.time > now) return false;
    final flap = _scheduled.removeAt(0);
    flapTimes.add(math.max(flap.time, now));
    if (flap.extra) extraFlaps++;
    return true;
  }

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
  HumanNoiseBot(this.run, {int seed = 7})
    : autopilot = Autopilot(run),
      scheduler = HumanNoiseFlapScheduler(seed: seed);

  static const double jitterSigma = .09;
  static const double extraFlapChance = .1;
  static const double extraFlapGap = .08;

  final RunController run;
  final Autopilot autopilot;
  final HumanNoiseFlapScheduler scheduler;

  bool _autopilotWanted = false;

  List<double> get flapTimes => scheduler.flapTimes;
  List<double> get plannedFlapTimes => scheduler.plannedFlapTimes;
  int get extraFlaps => scheduler.extraFlaps;

  /// Called once per fixed frame before updating [run]. The return value is
  /// whether the noisy bot taps at this frame.
  bool shouldFlap() {
    final wanted = autopilot.shouldFlap();
    if (wanted && !_autopilotWanted) {
      scheduler.planBase(run.state.runClock);
    }
    _autopilotWanted = wanted;
    return scheduler.flapDue(run.state.runClock);
  }
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
  });

  final int hoops;
  final MistakeCause? cause;
  final Set<String> highlightIds;
  final double seconds;
  final int flaps;
  final int extraFlaps;
}

/// Fixed-steps a started run with [HumanNoiseBot] until its first death (or
/// [maxSeconds]) and records the showcase highlights emitted on the way.
@visibleForTesting
Future<HumanNoiseBotResult> flyHumanNoiseBotToDeath(
  FlappySpikesGame game, {
  int seed = 7,
  double dt = 1 / 60,
  double maxSeconds = 120,
  void Function(RunController run)? onFrame,
}) async {
  final run = game.run;
  if (run == null) {
    throw StateError('flyHumanNoiseBotToDeath expects a started run');
  }

  final bot = HumanNoiseBot(run, seed: seed);
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
        await Future<void>.value();
        game.update(0);
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
  );
}

final class _ScheduledFlap {
  const _ScheduledFlap(this.time, {required this.extra});

  final double time;
  final bool extra;
}
