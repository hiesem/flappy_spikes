import '../director/plans.dart' show RideKind;
import '../elements.dart';
import '../mistakes.dart';
import '../rides/comet_ride.dart';
import '../rides/landing_slow_mo.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// Comet boost in a run (PRD-2 §3.8, §3.9, §5.6; ARCH §1.7): a collected
/// comet star — or a pair's COMET gift, which emits the same
/// `PickupCollected(ElementId.comet, null)` — starts one [CometRide]
/// (10 s at 1.7 ×, auto-pilot, rims ignored, the timed-powerup slot) and
/// sends `comet_collected {source: hoop | pair}`. The pickup's knock and
/// the boost hoops' shakes come from the rumble router (§3.33); the boost
/// hoops' banners, bursts, +2 and tier sounds from the streak / scoring
/// features (every ride pass is perfect).
class CometFeature extends RunFeature {
  RunContext? _c;

  /// The running boost (null in normal play), and the one whose landing
  /// tail is still playing.
  CometRide? ride;

  /// Every boost started this run (tests, debug).
  int started = 0;

  /// PRD-2.2 §17 the landing's slow motion (null before [attach]).
  LandingSlowMo? landing;

  @override
  void attach(RunContext c) {
    _c = c;
    landing = LandingSlowMo(c);
    c.events
      ..on<PickupCollected>(_onCollected)
      ..on<RideStarted>(_onRideStarted);
  }

  /// PRD-2.2 §17.2 a portal ride starting during the landing ends it.
  void _onRideStarted(RideStarted e) {
    if (e.kind == RideKind.portal) landing?.stop();
  }

  void _onCollected(PickupCollected e) {
    final c = _c;
    if (c == null || e.element != ElementId.comet) return;
    final source = e.pickup == null ? 'pair' : 'hoop';
    // Audit A4-2a: `comet_collected` only for a boost that really starts
    // (tracked first, as before, so the analytics order is unchanged).
    if (!canStart) return;
    c.track('comet_collected', {'source': source});
    start(source: source, starY: e.pickup?.position.y);
  }

  /// Whether [start] would start a boost now: not while a boost, a ride or
  /// another timed powerup runs (§3.0.3 exclusivity).
  bool get canStart {
    final c = _c;
    if (c == null) return false;
    final current = ride;
    if (current != null && !current.done) return false;
    return c.s.ride == null && c.s.timed == null;
  }

  /// Starts the boost now (no-op while a ride or another timed powerup
  /// runs — the director never offers one then, §3.0.3 exclusivity).
  bool start({String source = 'hoop', double? starY}) {
    final c = _c;
    if (c == null || !canStart) return false;
    final current = ride;
    current?.abort();
    final r = CometRide(c, source: source, starY: starY);
    ride = r;
    started++;
    r.start(c);
    return true;
  }

  /// True while the boost runs.
  bool get active => ride != null && !ride!.done;

  @override
  void update(double gameDt, double realDt) {
    landing?.step(realDt);
    final r = ride;
    if (r == null) return;
    final wasDone = r.done;
    r.update(gameDt);
    // PRD-2.2 §17.1 control returned: the landing's slow motion starts.
    if (!wasDone && r.done) landing?.start();
    if (r.finished) ride = null;
  }

  @override
  void onDeath(Mistake m) {
    landing?.stop();
    // Audit A4-6: a death in the landing tail must not leave the speed
    // streaks frozen on screen through the tumble and the revive offer.
    ride?.lines.clear();
  }

  @override
  void onRevive() => landing?.stop();

  @override
  void detach() {
    ride?.abort();
    ride = null;
    landing?.stop();
    landing = null;
    _c?.events
      ?..off<PickupCollected>(_onCollected)
      ..off<RideStarted>(_onRideStarted);
    _c = null;
  }
}
