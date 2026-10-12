import '../elements.dart';
import '../rides/comet_ride.dart';
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

  @override
  void attach(RunContext c) {
    _c = c;
    c.events.on<PickupCollected>(_onCollected);
  }

  void _onCollected(PickupCollected e) {
    final c = _c;
    if (c == null || e.element != ElementId.comet) return;
    final source = e.pickup == null ? 'pair' : 'hoop';
    c.track('comet_collected', {'source': source});
    start(source: source, starY: e.pickup?.position.y);
  }

  /// Starts the boost now (no-op while a ride or another timed powerup
  /// runs — the director never offers one then, §3.0.3 exclusivity).
  bool start({String source = 'hoop', double? starY}) {
    final c = _c;
    if (c == null) return false;
    final current = ride;
    if (current != null && !current.done) return false;
    if (c.s.ride != null || c.s.timed != null) return false;
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
    final r = ride;
    if (r == null) return;
    r.update(gameDt);
    if (r.finished) ride = null;
  }

  @override
  void detach() {
    ride?.abort();
    ride = null;
    _c?.events.off<PickupCollected>(_onCollected);
    _c = null;
  }
}
