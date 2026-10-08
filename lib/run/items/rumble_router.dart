import '../mistakes.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// Run events → phone rumble (PRD-2 §3.33; ARCH §2.7: the only caller of
/// `RunContext.knock` / `shake`).
///
/// - **Shake** (45 ms, full): every perfect pass — normal hoops, pairs,
///   train rings, FEVER, every comet / portal hoop (the controller marks
///   ride passes perfect). The same every time; never grows with the streak.
/// - **Knock** (15 ms, ≈ 90): a non-perfect pass (rim touched, still
///   through) and every pickup touch ([PickupCollected]: coins, stars,
///   fireflies, hearts, shield, comet, feather, piece, switch, egg, piggy,
///   jar, capsules).
/// - **Nothing else** rumbles: no death, save, reward, squeeze or menu
///   rumble from a run.
///
/// The `Rumble` service owns the RUMBLE setting and the 90 ms knock
/// throttle (a shake is never skipped and wins its window). On top of that
/// the router coalesces what one frame asked for — the pass decision and
/// the pickup touches all happen inside the run's update — so a perfect
/// pass that also collects something plays **only the shake**, even when
/// the pickup was touched first in that frame. The pulses go out at the end
/// of the same frame (the moment of the decision / touch).
///
/// Only while the run is live (`RunController.isScrolling`: playing, not
/// paused, not dying / ended): paused, revive, bonus and results screens
/// never rumble. Pulses are real-time (the game clock), so the Hourglass
/// does not change them.
class RumbleRouter extends RunFeature {
  RunContext? _c;
  bool _knock = false;
  bool _shake = false;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<HoopPassed>(_onPassed)
      ..on<PickupCollected>(_onPickup);
  }

  bool get _live => _c?.run.isScrolling ?? false;

  void _onPassed(HoopPassed e) {
    if (!_live) return;
    if (e.perfect) {
      _shake = true;
    } else {
      _knock = true;
    }
  }

  void _onPickup(PickupCollected e) {
    if (!_live) return;
    _knock = true;
  }

  /// Sends what this frame asked for: a shake wins over knocks.
  void flush() {
    final c = _c;
    final shake = _shake, knock = _knock;
    _shake = _knock = false;
    if (c == null) return;
    if (shake) {
      c.shake();
    } else if (knock) {
      c.knock();
    }
  }

  @override
  void update(double gameDt, double realDt) => flush();

  @override
  void onDeath(Mistake m) {
    // A pass or touch decided in the frame of a death still counts (it came
    // first); nothing after it rumbles.
    flush();
  }

  @override
  void detach() {
    _c?.events
      ?..off<HoopPassed>(_onPassed)
      ..off<PickupCollected>(_onPickup);
    _shake = _knock = false;
    _c = null;
  }
}
