/// PRD-2.4 §3.5 the run background around a portal ride: how it follows
/// the ride camera, the reveal after the launch of the five themed rides,
/// the catch-up scroll and the landing bump. Every number is the
/// prototype's (`docs/p24/ride_landings.html`, `BGV`, `softY`, `REVEAL`,
/// `RLAG`, `stepGlide`, `background()`). Per-band lists are indexed by
/// `Band.index` (sky, far, mid, near).
abstract final class HandoverConfig {
  /// PRD-2.4 §3.5 "On the ride": the share of the ride camera's height each
  /// layer follows (`BGV`): sky 0.07, far 0.17, mid 0.32, ground 0.5.
  static const List<double> share = [.07, .17, .32, .5];

  /// PRD-2.4 §3.5 the follow is capped (`softY`): at most this far when the
  /// camera goes up (pt)…
  static const double softUp = 720;

  /// PRD-2.4 §3.5 …and this far when it goes down (pt).
  static const double softDown = 100;

  /// PRD-2.4 §3.5 the themed ride's scene leaves over this long after the
  /// launch (s), on `smooth(τ / 1.7)`.
  static const double sceneLeave = 1.7;

  /// PRD-2.4 §3.5 the world arrives behind it: each layer starts this long
  /// after the launch (s; `RLAG`: sky 0, far 0.1, mid 0.25, near 0.4)…
  static const List<double> arriveLag = [0, .1, .25, .4];

  /// PRD-2.4 §3.5 …and travels over this long (s), on `smoother`.
  static const double arriveTime = 1.9;

  /// PRD-2.4 §3.5 "Catching up": from the glide start the world scrolls
  /// [catchUp] · e^(−[catchUpDecay] · t) pt/s faster than the cruise
  /// (`150 + 410·e^(−1.35·t)` in the prototype, whose cruise is 150).
  static const double catchUp = 410;
  static const double catchUpDecay = 1.35;

  /// PRD-2.4 §3.5 "Landing": on `pu_land` a bump of
  /// `[bumpAmp] · share · e^(−[bumpDecay]·w) · sin([bumpFreq]·w)` pt runs
  /// through the layers (≈ 3 pt on the ground).
  static const double bumpAmp = 6;
  static const double bumpDecay = 4;
  static const double bumpFreq = 13;

  /// PRD-2.4 §3.5 / §4 test 11 (WP-R call): the bump's tail is eased out
  /// over the settle, `1 − (w / settle)^[bumpTaperPow]`, so every offset is
  /// exactly 0 when the settle ends (the prototype leaves ≈ 0.3 pt). It
  /// changes the first swing by < 0.2 %.
  static const double bumpTaperPow = 4;

  /// PRD-2.4 §3.5 "No gaps": a layer that slides sideways is drawn this
  /// much wider than its travel (pt; the prototype's `XL − 30`, `XR + 30`).
  static const double sideMargin = 30;

  /// PRD-2.4 §3.5 "No gaps": a layer that comes down from above has its
  /// row this far below the screen bottom (pt, its own coordinates)
  /// stretched down over the gap (the prototype's `VH + 40`).
  static const double groundRow = 40;

  /// PRD-2.4 §3.5 "Control back: normal parallax" (WP-R call): after a
  /// portal ride the world re-syncs to its hoop schedule (§3.3) at no less
  /// than this rate (world pt per camera pt; normal is 300/310 ≈ 0.97),
  /// never holding still or creeping; a seam right after a ride may then
  /// come a few hoops early.
  static const double afterRideMinRate = .6;
}
