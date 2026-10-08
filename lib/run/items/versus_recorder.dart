import '../../menu/wallet.dart';
import '../../versus/opponent.dart';
import '../config/versus_config.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// §3.13 WIN if my final score is higher, LOSE if lower, DRAW if equal.
DuelResult duelOf(int mine, int theirs) => mine > theirs
    ? DuelResult.win
    : mine < theirs
    ? DuelResult.lose
    : DuelResult.draw;

/// §3.13 win +10, draw +5 (half), lose 0.
int bonusFor(DuelResult r) => switch (r) {
  DuelResult.win => VersusConfig.winBonus,
  DuelResult.draw => VersusConfig.drawBonus,
  DuelResult.lose => 0,
};

/// The versus side of a run (PRD-2 §3.13, ARCH §1.13 / §11):
///
/// - **the timeline** — every [ScoreChanged] records one entry per point on
///   `runClock` (a pair's +5 is five points at the same time with the
///   event's `gift` flag; ride / train points carry theirs), so the
///   uploaded timeline's point count always equals the score. `runClock`
///   stops in pause, the revive offer and the phoenix and slows with the
///   Hourglass, so the recording matches what the opponent bar replays;
/// - **the duel** — when the run ends ([RunEnding], before the summary) with
///   an opponent: WIN / LOSE / DRAW against their final score, the +10 /
///   +5 bonus through `ctx.earn(…, CoinSource.winBonus)` (so it is in
///   YOUR REWARD) and `versus_result {result, score, opp_score}` (§6).
///
/// The opponent's replay itself is the versus bar's (`OpponentRun.scoreAt`
/// on the same `runClock`).
class VersusRecorder extends RunFeature {
  RunContext? _c;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events.on<ScoreChanged>(_onScore);
    c.events.on<RunEnding>(_onEnding);
  }

  void _onScore(ScoreChanged e) {
    final c = _c;
    if (c == null) return;
    for (var i = e.oldScore; i < e.newScore; i++) {
      c.s.timeline.addPoint(c.s.runClock, flag: e.flags);
    }
  }

  void _onEnding(RunEnding e) {
    final c = _c;
    final opp = c?.run.setup.opponent;
    if (c == null || opp == null || c.s.duel != null) return;
    final result = duelOf(c.s.score, opp.score);
    final bonus = bonusFor(result);
    c.s.duel = result;
    if (bonus > 0) {
      final before = c.s.coinsThisRun;
      c.earn(bonus, CoinSource.winBonus);
      c.s.duelBonus = c.s.coinsThisRun - before;
    }
    c.track('versus_result', {
      'result': result.name,
      'score': c.s.score,
      'opp_score': opp.score,
    });
  }

  @override
  void detach() {
    _c?.events
      ?..off<ScoreChanged>(_onScore)
      ..off<RunEnding>(_onEnding);
    _c = null;
  }
}
