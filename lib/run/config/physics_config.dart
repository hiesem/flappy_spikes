/// Run physics knobs of WP-1a that are not in `RunConfig` (§3.0.1): the rim
/// bounce (§3.0.4), spike contact and save bounce (§3.0.5 / §3.1) and the
/// death tumble (§3.0.5). Every member's doc starts with its PRD section
/// (ARCH §4). Values are the prototype's (`proto_gameplay.html`
/// `hoopStep` / `kill` / `deathStep`). Pure Dart.
abstract final class PhysicsConfig {
  // --- §3.0.4 rim bounce ------------------------------------------------------

  /// §3.0.4 3 A rim hit starts one full turn of the bird over this long (s).
  static const double rimSpinSeconds = 0.35;

  /// §3.0.4 3 White sparks at the contact point (count).
  static const int rimSparks = 6;

  // --- PRD-2.2 §30 moving-ring pass detection --------------------------------

  /// PRD-2.2 §30.2 A moving ring whose centre or rim ends move more than this
  /// in one physics step (pt) is tested in [sweepSubsteps] sub-steps, so its
  /// plane or a rim end can never jump over the bird.
  static const double sweepSubstepThreshold = 2;

  /// PRD-2.2 §30.2 Sub-steps for a fast-moving ring (pose and bird
  /// interpolated).
  static const int sweepSubsteps = 4;

  // --- §3.1 / §3.0.5 spike strips ---------------------------------------------

  /// §3.1 Spike contact: the bird circle touches a tooth line when its edge
  /// is this far past it (pt; 0 = the tips, the 1.0 strip-box contact).
  static const double spikeContactInset = 0;

  /// §3.0.5 A save on the top strip sends the bird down at this fraction of
  /// its speed.
  static const double topSaveRestitution = 0.3;

  /// §3.0.5 A save on the floor strip sends the bird up at this velocity
  /// (pt/s; 60 % of a flap).
  static const double floorSaveVelocity = -222;

  // --- §3.0.5 death tumble ------------------------------------------------------

  /// §3.0.5 The camera and scroll ease to a stop over this long (s).
  static const double worldStopSeconds = 0.4;

  /// §3.0.5 Knock along the contact normal (pt/s).
  static const double deathKnock = 180;

  /// §3.0.5 A plain miss (no contact) pops the bird up by this (pt/s).
  static const double missPop = 140;

  /// §3.0.5 Spin = forward speed / this + impact term (rad/s per pt/s).
  static const double spinPerSpeed = 25;

  /// §3.0.5 Impact term per unit of the contact normal's −y (rad/s).
  static const double spinImpact = 4;

  /// §3.0.5 Impact term of a plain miss (rad/s).
  static const double spinMiss = 3;

  /// §3.0.5 Spin clamp (rad/s).
  static const double maxSpin = 12;

  /// §3.0.5 Light air drag on the forward speed (fraction per s).
  static const double airDrag = 0.4;

  /// §3.0.5 Restitution of a top-strip hit while tumbling.
  static const double topRestitution = 0.3;

  /// §3.0.5 Restitution of a floor bounce.
  static const double floorRestitution = 0.3;

  /// §3.0.5 A floor landing faster than this bounces (pt/s); slower rests.
  static const double bounceMinSpeed = 140;

  /// §3.0.5 Forward speed kept per floor bounce.
  static const double bounceForward = 0.6;

  /// §3.0.5 Spin per floor bounce: reverses × this.
  static const double bounceSpin = 0.6;

  /// §3.0.5 Resting line: the bird centre sits this far into the tooth tips
  /// (centre = tooth line − r + this) (pt).
  static const double restInset = 2;

  /// §3.0.5 Sliding friction on the forward speed while resting (per s).
  static const double slideFriction = 6;

  /// §3.0.5 Spin damping while resting (per s).
  static const double spinDamp = 8;

  /// §3.0.5 Rate at which the resting bird settles flat (per s).
  static const double settleRate = 6;

  /// §3.0.5 The tumbling bird bounces off the left screen edge here (pt).
  static const double edgeLeft = 24;

  /// §3.0.5 … and this far from the right edge (pt).
  static const double edgeRight = 30;

  /// §3.0.5 Edge bounce: forward speed × −this.
  static const double edgeRestitution = 0.3;

  /// §3.0.5 The post-run flow starts this long after the hit, or as soon as
  /// the bird rests if sooner (s).
  static const double resultsDelay = 1.5;

  /// §3.0.5 Themed deaths: at most this long after the hit (s).
  static const double themedResultsMax = 2.2;
}
