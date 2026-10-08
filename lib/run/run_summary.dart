import '../versus/opponent.dart';
import '../versus/timeline.dart';
import 'director/plans.dart';
import 'mistakes.dart';

/// Immutable result of a run, handed to the post-run screens and the versus
/// upload (ARCH §1.1).
class RunSummary {
  const RunSummary({
    required this.score,
    required this.hoopsPassed,
    required this.coins,
    required this.bestBefore,
    required this.bestAfter,
    this.saves = 0,
    this.revives = 0,
    required this.runSeconds,
    required this.cause,
    this.hoopKind,
    required this.hoopIndex,
    required this.timeline,
    this.opponent,
    this.duel,
    this.spawned = const {},
    this.rimTouches = 0,
    this.passes = 0,
    this.perfectPasses = 0,
  });

  final int score;
  final int hoopsPassed;

  /// YOUR REWARD (run coins + puzzle + win / draw bonus).
  final int coins;
  final int bestBefore;
  final int bestAfter;
  final int saves;
  final int revives;
  final double runSeconds;
  final MistakeCause cause;

  /// Kind of the hoop the run ended on (null = spikes / no hoop).
  final HoopKindId? hoopKind;
  final int hoopIndex;
  final RunTimeline timeline;
  final OpponentRun? opponent;
  final DuelResult? duel;

  /// Director spawned counts (analytics).
  final Map<String, int> spawned;
  final int rimTouches;
  final int passes;
  final int perfectPasses;

  bool get newBest => bestAfter > bestBefore;
}
