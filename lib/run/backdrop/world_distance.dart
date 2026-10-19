import '../config/handover_config.dart';
import 'backdrop_math.dart';

/// Where the run's hoops are (PRD-2.4 §3.3 pacing): the director's next
/// slot and the planes of slots already planned.
abstract class HoopAnchors {
  /// Index of the next slot the director will plan.
  int get nextIndex;

  /// Track x of that slot's plane.
  double get nextX;

  /// Track x of planned slot [index]'s plane (null = not known any more).
  double? planeOf(int index);

  /// Plane-to-plane spacing assumed for slots not planned yet.
  double get spacing;
}

/// PRD-2.4 §3.3 "Pacing": maps the run camera to the prototype's world
/// distance `cam` (300 pt per hoop, a scene = 6 000 (20 hoops), seam k at 6 000·k).
///
/// The world distance `w` is integrated from the camera: every frame the
/// screen-centre track x `c = camX + 160` moves by `dc`, and `w` moves by
/// `r · dc`, where
///
///     r = (W* − w) / (X* − c)
///
/// with W* = 300 · n* the world distance of the next seam hoop n* (the next
/// multiple of 20 ahead) and X* the track x of that hoop's plane: its real
/// plane once the director has planned it, otherwise a prediction (the
/// director's next slot plus 310 pt per slot still to come, never closer
/// than the right screen edge). So
///
/// * `w` is continuous (it only ever moves by `r · dc`: no jump when the
///   spacing changes, on comets, rides, revive or a knock-back);
/// * `w` is monotonic in the camera (non-decreasing as it moves forward;
///   `r` is clamped to [rMin, rMax] > 0);
/// * between seams `r ≈ 300 / 310`: the layers move with the camera's
///   distance at the prototype's parallax factors (0.97×);
/// * when hoop n*'s plane reaches the screen centre `w` is exactly W*: seam k
///   is centred on hoop 20·k. Then n* becomes the next multiple of 20.
/// * while hoop n* is not planned yet the world never gets closer than
///   300 per slot still to plan (+100) to W*: when the spawner holds (a
///   portal ride) the world holds still near the seam instead of playing
///   it under the ride, and lands it on its hoop after the ride.
/// How far short of a seam hoop the world holds while that hoop is not
/// planned yet (pt of world distance).
const double kUnplannedMargin = 100;

class WorldDistance {
  WorldDistance({this.rMin = .1, this.rMax = 2.5});

  /// Bounds of the rate (world pt per camera pt).
  final double rMin, rMax;

  /// The world distance (prototype `cam`).
  double w = 0;

  /// The next seam hoop (a multiple of 20).
  int target = 0;

  double _c = 0;
  bool started = false;

  /// WP-R (PRD-2.4 §3.5): a portal ride's hook drove the world (an
  /// override), so it may be ahead of its hoop schedule. Until it is back
  /// on it (the mapped rate is normal again) the unplanned-hoop cap is off and the rate never drops
  /// below [HandoverConfig.afterRideMinRate]: the world re-syncs smoothly
  /// instead of holding still or creeping (the seam may then come a few
  /// hoops early after a ride that ends close to it).
  bool _afterRide = false;

  /// Whether the world is re-syncing after a portal ride (tests).
  bool get afterRide => _afterRide;

  /// The camera centre the distance was last advanced to.
  double get c => _c;

  /// Starts at screen-centre x [c] with slot [index]'s plane at [planeX]
  /// (the run's first hoop): `w = 300 · index − (planeX − c) · 300 / spacing`.
  void start(double c, int index, double planeX, double spacing) {
    w = kPerHoop * index - (planeX - c) * kPerHoop / spacing;
    _c = c;
    target = _nextTarget(w);
    started = true;
  }

  static int _nextTarget(double w) =>
      ((w / kPerHoop) / kHoopsPerScene).floor() * kHoopsPerScene + kHoopsPerScene;

  /// The plane x the mapping aims [target] at, seen from camera centre [c].
  double targetX(HoopAnchors a, double c) {
    final n = target;
    if (n >= a.nextIndex) {
      final from = a.nextX > c + (kVW - kANCH) ? a.nextX : c + (kVW - kANCH);
      return from + (n - a.nextIndex) * a.spacing;
    }
    return a.planeOf(n) ?? a.nextX - (a.nextIndex - n) * a.spacing;
  }

  /// Moves the camera centre to [c]. [override] (a ride hook's scroll)
  /// replaces `r · dc` when not null.
  void advance(double c, HoopAnchors a, {double? override}) {
    final dc = c - _c;
    if (dc == 0) return;
    final wt = target * kPerHoop, rem = wt - w;
    final double dw;
    if (override != null) {
      dw = override;
      _afterRide = true;
    } else {
      var lead = targetX(a, _c) - _c;
      // back on (or behind) the hoop schedule: the re-sync is over
      if (_afterRide && rem >= lead * kPerHoop / a.spacing) {
        _afterRide = false;
      }
      final lo = rem / rMax,
          hi = rem / (_afterRide ? HandoverConfig.afterRideMinRate : rMin);
      lead = lead < lo ? lo : (lead > hi ? hi : lead);
      dw = lead <= 0 ? dc : rem / lead * dc;
    }
    _c = c;
    var step = dw;
    if (override == null && !_afterRide && step > 0 && target >= a.nextIndex) {
      // The seam hoop is not planned yet (a ride holds the spawner, or the
      // spacing grew): the world may not come closer to it than the slots
      // still to plan, so the seam never plays ahead of its hoop. It holds
      // still instead (never moves back).
      final cap = wt - (target - a.nextIndex) * kPerHoop - kUnplannedMargin;
      step = w >= cap ? 0 : (w + step > cap ? cap - w : step);
    }
    w += step;
    if (w >= wt) {
      w = wt;
      target += kHoopsPerScene;
    }
  }

  /// WP-R (PRD-2.4 §3.5): sets the world distance to [to] while the world
  /// is not seen (a themed ride's scene covers the screen at its launch),
  /// so it is on its hoop schedule when control returns. It never crosses
  /// the next seam hoop, and never moves back into the last seam's window
  /// or its lingering pieces.
  void resync(double to) {
    final wt = target * kPerHoop;
    final back = (target - kHoopsPerScene) * kPerHoop + kVWIN / 2 + kLinger;
    final lo = w < back ? w : back;
    final hi = wt - 1;
    w = to < lo ? lo : (to > hi ? hi : to);
    _afterRide = true;
  }
}
