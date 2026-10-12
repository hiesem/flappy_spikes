import '../config/run_config.dart';
import 'plans.dart';

/// Read-only snapshot the game passes in for each director decision
/// (ARCH §2.2). Pure data; every field has a neutral default so pure tests
/// can build one with [DirectorContext.open].
class DirectorContext {
  const DirectorContext({
    required this.viewHeight,
    required this.topTooth,
    required this.floorTooth,
    double? squeezeTopTooth,
    double? squeezeFloorTooth,
    this.squeezeWindow = false,
    this.rideActive = false,
    this.ride,
    this.timedPowerupRunning = false,
    this.onFire = false,
    this.fever = false,
    this.shieldArmed = false,
    this.extraLifeActive = false,
    this.eggOrChick = false,
    this.piggyRunning = false,
    this.jarRunning = false,
    this.shieldPickupsThisRun = 0,
    this.scrollSpeed = RunConfig.cruiseSpeed,
    this.runClock = 0,
    this.bigHoopsMult = 1,
    this.prevCentreY,
    this.hudBottom = RunConfig.hudBottom,
    this.featherWanted = true,
    this.puzzleMask = 0,
    this.activity = false,
    this.activityEndedAtSlot = -99,
  }) : squeezeTopTooth = squeezeTopTooth ?? topTooth,
       squeezeFloorTooth = squeezeFloorTooth ?? floorTooth;

  /// A plain context at [viewHeight] with the 44 pt strips (§3.0.9 #1).
  factory DirectorContext.open(
    double viewHeight, {
    bool squeezeWindow = false,
    double squeezeInset = 0,
    bool rideActive = false,
    RideKind? ride,
    bool timedPowerupRunning = false,
    bool onFire = false,
    bool fever = false,
    bool shieldArmed = false,
    bool extraLifeActive = false,
    bool eggOrChick = false,
    bool piggyRunning = false,
    bool jarRunning = false,
    double scrollSpeed = RunConfig.cruiseSpeed,
    double bigHoopsMult = 1,
    double? prevCentreY,
    bool featherWanted = true,
    int puzzleMask = 0,
    bool activity = false,
    int activityEndedAtSlot = -99,
  }) {
    const top = RunConfig.stripHeight;
    final floor = viewHeight - RunConfig.stripHeight;
    return DirectorContext(
      viewHeight: viewHeight,
      topTooth: top,
      floorTooth: floor,
      squeezeTopTooth: top + squeezeInset,
      squeezeFloorTooth: floor - squeezeInset,
      squeezeWindow: squeezeWindow,
      rideActive: rideActive,
      ride: ride,
      timedPowerupRunning: timedPowerupRunning,
      onFire: onFire,
      fever: fever,
      shieldArmed: shieldArmed,
      extraLifeActive: extraLifeActive,
      eggOrChick: eggOrChick,
      piggyRunning: piggyRunning,
      jarRunning: jarRunning,
      scrollSpeed: scrollSpeed,
      bigHoopsMult: bigHoopsMult,
      prevCentreY: prevCentreY,
      featherWanted: featherWanted,
      puzzleMask: puzzleMask,
      activity: activity,
      activityEndedAtSlot: activityEndedAtSlot,
    );
  }

  final double viewHeight;

  /// The normal (un-squeezed) tooth lines: the band of §3.0.2.
  final double topTooth;
  final double floorTooth;

  /// Squeezed tooth lines (equal to the normal ones outside a squeeze).
  final double squeezeTopTooth;
  final double squeezeFloorTooth;

  /// §3.0.3 From 3 s before the squeeze warning until the walls are open.
  final bool squeezeWindow;

  final bool rideActive;
  final RideKind? ride;

  /// Hourglass / Mini Bird / Coin Frenzy / comet running.
  final bool timedPowerupRunning;

  /// PRD-2.2 §21 The bird burns (a ×3 streak fire or FEVER). Passive: it
  /// blocks nothing (§27.1).
  final bool onFire;

  /// PRD-2 §3.19 / PRD-2.2 §21 FEVER runs. Only FEVER itself keeps a FEVER
  /// ring / pair FEVER gift away (an ordinary ×3 fire does not, S7-08).
  final bool fever;
  final bool shieldArmed;
  final bool extraLifeActive;
  final bool eggOrChick;

  /// A grabbed Piggy Bank still placing coins.
  final bool piggyRunning;

  /// A grabbed Firefly Jar not yet full or broken.
  final bool jarRunning;

  final int shieldPickupsThisRun;

  /// Current cruise (switch lead = 1.0 s × this, ≥ 150 pt).
  final double scrollSpeed;
  final double runClock;
  final double bigHoopsMult;

  /// Previous hoop centre (switch reach, pair reach); null = use the
  /// director's own last centre.
  final double? prevCentreY;

  /// y ≈ 114: a pair's upper ring stays below it.
  final double hudBottom;

  /// §3.15 `storage.feathers < 3`.
  final bool featherWanted;

  /// §3.16 `storage.puzzlePieces` (4-bit mask; 0xF = round complete).
  final int puzzleMask;

  /// PRD-2.2 §27 an activity (comet / portal ride, piggy / jar run,
  /// capsule power-up) runs: no reward item is planned.
  final bool activity;

  /// PRD-2.2 §27.2 the director's next slot index when the last activity
  /// ended (the 2-hoop cool-down counts from it); −99 = none.
  final int activityEndedAtSlot;

  double get band => floorTooth - topTooth;
}
