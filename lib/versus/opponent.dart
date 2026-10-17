import '../skins/look.dart';
import 'timeline.dart';

/// A prefetched versus opponent (PRD-2 §3.13, ARCH §1.13): a real player's
/// stored run, replayed on our `runClock`.
class OpponentRun implements OpponentFeed {
  const OpponentRun({
    required this.uid,
    required this.name,
    this.look = Look.defaults,
    required this.score,
    required this.best,
    required this.level,
    required this.timeline,
    this.platform = 'android',
    this.runId = '',
  });

  final String uid;
  final String name;
  final Look look;
  final int score;
  final int best;
  final int level;
  final RunTimeline timeline;

  /// 'android' | 'ios'.
  final String platform;

  /// The stored run's id (WP-5b: "not repeated within a session").
  final String runId;

  @override
  int scoreAt(double runClock) => timeline.scoreAt(runClock);

  @override
  bool outAt(double runClock) => timeline.outAt(runClock);
}

/// What the versus bar reads during a run.
abstract class OpponentFeed {
  int scoreAt(double runClock);
  bool outAt(double runClock);
}

/// WIN / LOSE / DRAW of a versus run (§3.13).
enum DuelResult { win, lose, draw }
