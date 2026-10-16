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
/// distance `cam` (300 pt per hoop, a scene = 12 000, seam k at 12 000·k).
///
/// The world distance `w` is integrated from the camera: every frame the
/// screen-centre track x `c = camX + 160` moves by `dc`, and `w` moves by
/// `r · dc`, where
///
///     r = (W* − w) / (X* − c)
///
/// with W* = 300 · n* the world distance of the next seam hoop n* (the next
/// multiple of 40 ahead) and X* the track x of that hoop's plane: its real
/// plane once the director has planned it, otherwise a prediction (the
/// director's next slot plus 310 pt per slot still to come, never closer
/// than the right screen edge). So
///
/// * `w` is continuous (it only ever moves by `r · dc`: no jump when the
///   spacing changes, on comets, rides, revive or a knock-back);
/// * `w` is monotonic in the camera (`r` is clamped to [rMin, rMax] > 0);
/// * between seams `r ≈ 300 / 310`: the layers move with the camera's
///   distance at the prototype's parallax factors (0.97×);
/// * when hoop n*'s plane reaches the screen centre `w` is exactly W*: seam k
///   is centred on hoop 40·k. Then n* becomes the next multiple of 40.
class WorldDistance {
  WorldDistance({this.rMin = .4, this.rMax = 2.5});

  /// Bounds of the rate (world pt per camera pt).
  final double rMin, rMax;

  /// The world distance (prototype `cam`).
  double w = 0;

  /// The next seam hoop (a multiple of 40).
  int target = 0;

  double _c = 0;
  bool started = false;

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
    } else {
      var lead = targetX(a, _c) - _c;
      final lo = rem / rMax, hi = rem / rMin;
      lead = lead < lo ? lo : (lead > hi ? hi : lead);
      dw = lead <= 0 ? dc : rem / lead * dc;
    }
    _c = c;
    w += dw;
    if (w >= wt) {
      w = wt;
      target += kHoopsPerScene;
    }
  }
}
