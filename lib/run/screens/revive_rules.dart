import '../config/revive_config.dart';
import '../mistakes.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_state.dart';

/// §3.14 what a death does to the run, whether or not the player revives
/// (WP-2d baseline; the element WPs add their own visuals in `onDeath`):
///
/// - **Lost:** a running Egg / chick, Piggy Bank and Firefly Jar (no
///   pay-out).
/// - **Ended:** a running timed powerup (Hourglass, Mini Bird, Coin
///   Frenzy, comet) — [PowerupEnded]; the time scale and bird scale go back
///   to 1.
/// - **Reset:** the bird's fire (the streak resets on [RunDied], WP-2b).
/// - **Kept:** score, coins, hearts, feather / piece progress.
///
/// On a revive (the phoenix start) a running spike squeeze is reset to
/// open: the walls slide out over 0.5 s and the next squeeze comes 60–120 s
/// of runClock later.
///
/// Registered last in `features.dart`, so the element features see their
/// state in their own `onDeath` before it is cleared here.
class ReviveRulesFeature extends RunFeature {
  RunContext? _c;
  double _openFrom = 0;
  double _openT = -1;

  @override
  void attach(RunContext c) => _c = c;

  @override
  void onDeath(Mistake m) {
    final c = _c;
    if (c == null) return;
    final s = c.s;
    s
      ..egg = null
      ..piggy = null
      ..jar = null
      ..onFire = false
      ..feverLit = false;
    final timed = s.timed;
    if (timed != null) {
      s.timed = null;
      c.emit(PowerupEnded(timed.type));
    }
    s
      ..timeScale = 1
      // PRD-2.2 §17.2 a death clears the comet landing's slow motion too.
      ..hourglassScale = 1
      ..landingScale = 1
      ..cometLanding = false
      ..birdScale = 1;
  }

  @override
  void onRevive() {
    final c = _c;
    if (c == null) return;
    final sq = c.s.squeeze;
    if (sq.phase != SqueezePhase.idle || sq.inset > 0) {
      final was = sq.phase;
      sq.phase = SqueezePhase.idle;
      sq.nextAt = c.director.rollSqueezeAt(c.s.runClock);
      if (was != SqueezePhase.idle) {
        c.emit(SqueezePhaseChanged(sq.phase, sq.index));
      }
      _openFrom = sq.inset;
      _openT = 0;
    }
  }

  @override
  void update(double gameDt, double realDt) {
    final c = _c;
    if (c == null || _openT < 0) return;
    _openT += realDt;
    final k = (_openT / ReviveConfig.squeezeOpen).clamp(0.0, 1.0);
    c.s.squeeze.inset = _openFrom * (1 - k);
    if (k >= 1) _openT = -1;
  }

  @override
  void detach() => _c = null;
}
