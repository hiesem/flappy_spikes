import 'config/run_config.dart';
import 'director/plans.dart';
import 'elements.dart';
import '../versus/opponent.dart' show DuelResult;
import '../versus/timeline.dart';

/// All mutable data of one run (ARCH §2.1). Pure data: the controller and
/// the features mutate it, screens and the HUD read it. Every field exists
/// from WP-0b; feature WPs fill behaviour, not fields.
class RunState {
  RunState({
    required this.seed,
    required this.viewHeight,
    Set<ElementId>? metElements,
  }) : metElements = metElements ?? {};

  final int seed;
  final double viewHeight;

  // progress
  /// Shown score; includes a pair's "+5 score" gift.
  int score = 0;

  /// Hoops passed (rides included, gifts not): revive minimum, colour stage.
  int hoopsPassed = 0;

  /// Slots spawned (train / pair = 1 slot); NOT reset by a revive.
  int hoopIndex = 0;

  /// == index of the slot the gap follows.
  int gapIndex = 0;

  /// Mirrors `RunClock.t` (s).
  double runClock = 0;

  /// YOUR REWARD: run coins + puzzle + win / draw bonus; NOT balloon coins.
  int coinsThisRun = 0;

  /// floor(hoopsPassed / 10) % 11.
  int get stage => RunConfig.stageForHoops(hoopsPassed);

  // motion
  double camX = 0;
  double camY = 0;

  /// pt/s, the bird's forward velocity (< 0 briefly after a knock-back).
  double forwardSpeed = 0;

  /// Hourglass; PRD-2.2 §17 the comet landing (the lower of the two).
  double timeScale = 1;

  // region WP-G3 — comet landing (PRD-2.2 §17)
  /// PRD-2.2 §17.2 the Hourglass's own scale and the landing's own scale:
  /// [timeScale] is the lower of the two, frame by frame.
  double hourglassScale = 1;
  double landingScale = 1;

  /// PRD-2.2 §17 / §27 the comet's landing slow motion runs: the comet
  /// activity lasts until it is done.
  bool cometLanding = false;
  // endregion WP-G3

  /// Mini Bird 0.52 (eased).
  double birdScale = 1;

  /// s; spring launch (0.45 up / 0.28 down), rides.
  double flapLock = 0;

  // life
  /// 0..2; the 3rd converts to [extraLife].
  int hearts = 0;
  bool extraLife = false;

  /// Armed (pickup, pair gift or home slot).
  bool shield = false;

  /// Shield pickups spawned this run (max 1, §3.0.3).
  int shieldPickups = 0;

  /// s left (2 s after a save / phoenix).
  double invulnerable = 0;
  int saves = 0;

  // streak
  /// Perfect passes in a row.
  int streak = 0;
  int bestStreak = 0;

  /// PRD-2.3.1 §15.1 the streak the current perfect pass scores with: the
  /// ordinary increment (streak + 1), *before* the FEVER boost to
  /// max(5, streak + 1). Set by `StreakFeature` and consumed (reset to null)
  /// by `ScoringFeature` in the same `HoopPassed` dispatch.
  int? pointStreak;
  int get tier => streak.clamp(0, 10);

  /// PRD-2.2 §21 The bird burns (lit by a ×3 perfect streak or by FEVER).
  bool onFire = false;

  /// Perfect passes since the fire was lit (analytics `hoops_burned`).
  int hoopsBurned = 0;

  /// PRD-2 §3.19 / PRD-2.2 §21.1 FEVER was lit (FEVER ring / pair gift) and
  /// runs, unchanged, until the streak breaks (the fire goes out). It has no
  /// pass count (S7-07).
  bool feverLit = false;

  /// PRD-2.2 §21.1 Whether FEVER runs (the loud crackle loop, at least the
  /// ×5 fire size).
  bool get fever => onFire && feverLit;

  // powerups
  /// Hourglass | mini | frenzy | comet.
  TimedPowerupState? timed;
  BigHoopsState? bigHoops;

  /// Comet | portal (rideId, phase).
  RideState? ride;

  // collectables (lost on a death that brings up the revive offer, §3.14)
  EggState? egg;
  PiggyState? piggy;
  JarState? jar;
  final StarTrailState trails = StarTrailState();

  /// Once per run, also across a revive.
  bool featherSpawned = false;
  bool pieceSpawned = false;

  // squeeze
  final SqueezeState squeeze = SqueezeState();

  // region WP-G2 — one bonus at a time (PRD-2.2 §27)
  /// The running activity (comet ride, portal ride, piggy / jar run,
  /// capsule power-up), kept in sync by `RunSpawner` from the state the
  /// features set ([RunActivity.of]); null = none.
  RunActivity? activity;

  /// runClock when [activity] started.
  double activityStart = 0;

  /// The director's next slot index when the last activity ended (the
  /// 2-hoop cool-down counts from it); −99 = none yet.
  int activityEndedAtSlot = -99;
  // endregion WP-G2

  // revive
  int revivesThisGame = 0;

  /// False after the ad step is used or skipped (no fill / no-ads).
  bool adStepAvailableThisGame = true;
  bool firstSlotAfterRevive = false;

  // region WP-2d — revive ladder (PRD-2 §3.14)
  /// Revives paid with coins this game: the next coin price is
  /// 250 × 2^coinRevives.
  int coinRevives = 0;
  // endregion WP-2d

  // region WP-3a — comet boost (PRD-2 §3.8)
  /// The cruise multiplier the forward motion recovers toward (1; the comet
  /// boost eases it to 1.7 and back, `BirdMotion.step`).
  double cruiseMult = 1;
  // endregion WP-3a

  // region WP-5b — versus (PRD-2 §3.13)
  /// WIN / LOSE / DRAW, settled when the run ends with an opponent (null =
  /// solo, or not over yet).
  DuelResult? duel;

  /// The win / draw bonus credited at the end (part of [coinsThisRun]).
  int duelBonus = 0;
  // endregion WP-5b

  // bookkeeping for analytics and tests
  /// run_director_hoops / _items (spawned).
  final Map<String, int> spawned = {};

  /// Taken counts per element storage id.
  final Map<String, int> taken = {};
  int passes = 0;
  int perfectPasses = 0;

  /// PRD-2.2 §11 clean off-centre passes (no rim touch, outside the zone).
  int cleanPasses = 0;
  int rimTouches = 0;
  final Set<ElementId> metThisRun = {};

  /// Install-wide copy loaded from storage at run start.
  final Set<ElementId> metElements;
  RunTimeline timeline = RunTimeline.empty();

  /// Rides and the squeeze window block director spawns of most kinds.
  bool rideOrSqueezeBlocksSpawns() =>
      ride != null || squeeze.phase != SqueezePhase.idle;
}

/// PRD-2.2 §27.1 The activities: while one runs no other reward item
/// appears. Carrying the egg / chick, a shield, an extra life, Big Hoops,
/// the fire and FEVER are not activities.
enum RunActivity {
  /// §3.8 comet ride (incl. the pair's COMET gift): the star / gift is
  /// taken → control returns.
  comet,

  /// §3.12 portal ride: the bird enters the portal → control returns.
  portal,

  /// §3.28 Piggy Bank run: the piggy is grabbed → the pay-out or the bank
  /// is lost.
  piggy,

  /// §3.29 Firefly Jar run: the jar is grabbed → JAR FULL, or the jar is
  /// lost.
  jar,

  /// §3.30–3.32 capsule power-up (Hourglass, Mini Bird, Coin Frenzy): the
  /// capsule is opened → its timer ends.
  capsule;

  /// The activity [s] is in right now, derived from what the features set
  /// (`ride`, `timed`, `piggy`, `jar`), so every start and end is seen
  /// without the features knowing about activities.
  static RunActivity? of(RunState s) {
    final ride = s.ride?.kind;
    if (ride == RideKind.portal) return RunActivity.portal;
    if (ride == RideKind.comet ||
        s.timed?.type == TimedPowerup.comet ||
        s.cometLanding) {
      return RunActivity.comet;
    }
    if (s.piggy != null) return RunActivity.piggy;
    if (s.jar != null) return RunActivity.jar;
    if (s.timed != null) return RunActivity.capsule;
    return null;
  }
}

/// Timed powerups (§3.8, §3.30–3.32): only one runs at a time.
enum TimedPowerup { hourglass, mini, frenzy, comet }

class TimedPowerupState {
  TimedPowerupState({required this.type, required this.duration})
    : remaining = duration;
  final TimedPowerup type;
  final double duration;
  double remaining;

  /// A portal ride pauses a running Hourglass / Mini / Frenzy (§3.0.3).
  bool paused = false;
}

/// §3.6 Big Hoops: D seconds of runClock from [start], ×1.5 easing back over
/// the last 8 s.
class BigHoopsState {
  BigHoopsState({required this.duration, required this.start});
  final double duration;
  final double start;

  /// The opening multiplier at [runClock] (1 when over).
  double mult(double runClock) {
    final t = runClock - start;
    if (t >= duration || t < 0) return 1;
    final easeFrom = duration - RunConfig.bigHoopsEase;
    if (t <= easeFrom) return RunConfig.bigHoopsMult;
    final u = (t - easeFrom) / RunConfig.bigHoopsEase;
    return RunConfig.bigHoopsMult + (1 - RunConfig.bigHoopsMult) * u;
  }
}

class RideState {
  RideState({required this.kind, this.rideId, this.phase = ''});
  final RideKind kind;
  final RideId? rideId;

  /// Engine-defined phase name (e.g. 'enter', 'ride', 'launch', 'glide').
  String phase;

  // region WP-3b — portal rides (PRD-2 §3.12)
  /// The bird is hidden (in the cannon barrel, the volcano, the rocket):
  /// no trail.
  bool birdHidden = false;
  // endregion WP-3b
}

enum EggStage { egg, chick }

class EggState {
  EggStage stage = EggStage.egg;

  /// 0..5 rings passed while an egg.
  int cracks = 0;
}

class PiggyState {
  int placed = 0;
  int caught = 0;
  int missed = 0;
}

class JarState {
  int caught = 0;
  int escaped = 0;
}

class StarTrailState {
  /// Caught stars per trail id.
  final Map<int, int> caught = {};
}

enum SqueezePhase { idle, warning, closing, hold, opening }

class SqueezeState {
  SqueezePhase phase = SqueezePhase.idle;

  /// Squeeze number this run (0-based).
  int index = 0;

  /// runClock of the next warning.
  double nextAt = double.infinity;
  double holdS = 0;

  /// Current inset of each tooth line (pt).
  double inset = 0;
}
