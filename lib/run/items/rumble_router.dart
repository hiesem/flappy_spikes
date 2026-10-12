import '../mistakes.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// Run events → phone rumble (PRD-2 §3.33 with PRD-2.2 §10 / §11; ARCH
/// §2.7: the only caller of `RunContext.knock` / `shake`).
///
/// - **Shake** (80 ms, full; PRD-2.2 §10): every perfect pass — normal
///   hoops, pairs, train rings, FEVER, every comet / portal hoop (the
///   controller marks ride passes perfect). The same every time; never
///   grows with the streak.
/// - **Knock** (15 ms, ≈ 90): a rim touch **at the moment of contact**
///   ([RimTouched], PRD-2.2 §10.1), a clean off-centre pass (PRD-2.2 §11)
///   and every pickup touch ([PickupCollected]: coins, stars, fireflies,
///   hearts, shield, comet, feather, piece, switch, egg, piggy, jar,
///   capsules). A pass after a rim touch (graze) adds nothing: the touch
///   already knocked.
/// - **Nothing else** rumbles: no death, save, reward, squeeze or menu
///   rumble from a run. A lethal rim touch (saw rings: no [RimTouched]) and
///   a rim touch in the frame of a death don't rumble.
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
  bool _rimKnock = false;
  bool _shake = false;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<HoopPassed>(_onPassed)
      ..on<RimTouched>(_onRim)
      ..on<PickupCollected>(_onPickup);
  }

  bool get _live => _c?.run.isScrolling ?? false;

  void _onPassed(HoopPassed e) {
    if (!_live) return;
    if (e.perfect) {
      _shake = true;
    } else if (e.clean) {
      _knock = true;
    }
  }

  void _onRim(RimTouched e) {
    if (!_live) return;
    _rimKnock = true;
  }

  void _onPickup(PickupCollected e) {
    if (!_live) return;
    _knock = true;
  }

  /// Sends what this frame asked for: a shake wins over knocks.
  void flush() {
    final c = _c;
    final shake = _shake, knock = _knock || _rimKnock;
    _shake = _knock = _rimKnock = false;
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
    // A pass or pickup decided in the frame of a death still counts (it
    // came first); a rim touch in that frame is part of the death (PRD-2.2
    // §10.1: deaths don't rumble); nothing after it rumbles.
    _rimKnock = false;
    flush();
  }

  @override
  void detach() {
    _c?.events
      ?..off<HoopPassed>(_onPassed)
      ..off<RimTouched>(_onRim)
      ..off<PickupCollected>(_onPickup);
    _shake = _knock = _rimKnock = false;
    _c = null;
  }
}
