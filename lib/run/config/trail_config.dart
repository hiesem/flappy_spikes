import '../../game/config.dart';

/// The bird's run trail (PRD-2.2 §21.1, supersedes the trail scale of
/// PRD-2 §3.5 / `TierTrail`; mock `design/menu_v2/screen_fire_choice2.html`).
/// Every member's doc starts with its PRD section.
abstract final class TrailConfig {
  /// PRD-2.2 §21.1 From tier 3 every equipped trail is drawn at 2× today's
  /// scale (today: the look scale ≈ 0.98).
  static const double runScale = 2 * Config.lookScale;

  /// WP-TRAIL (owner 2026-10-18): the Rainbow ribbon and the Afterimage
  /// copies keep the skin-shop preview's size relative to the bird (the
  /// preview draws the trail at the bird's own scale), so in a run they are
  /// drawn at the bird's look scale, not at [runScale].
  static const double birdScaleTrail = Config.lookScale;

  /// WP-TRAIL: the trails drawn at [birdScaleTrail].
  static const Set<String> birdScaleIds = {'rainbow', 'echo'};

  /// The run scale of trail [id] (pixels per bird art unit at bird scale 1).
  static double scaleFor(String id) =>
      birdScaleIds.contains(id) ? birdScaleTrail : runScale;

  /// PRD-2.2 §21.1 The block trail (Pixel blocks) at 2× its master size.
  static const double blockScale = 2;

  /// PRD-2.2 §21.1 Emission point behind the bird along the flight
  /// direction (pt; was 26). WP-TRAIL: measured along the bird's real path
  /// (arc length), times the bird's drawn scale.
  static const double runBack = 18;

  /// WP-TRAIL (owner 2026-10-18): when the bird is hidden (cannon barrel,
  /// volcano, rocket, ...) the path trails (Rainbow, Afterimage, Prism,
  /// Paint stroke) fade out in place over this long (s); particles age out
  /// on their own. When the bird is back a fresh trail starts from it.
  static const double detachFade = .3;

  /// WP-TRAIL: a camera move larger than this in one frame (pt, plus
  /// [maxWorldSpeed] × dt) is a cut (the glide's camY reset), not motion:
  /// the trail keeps its screen position.
  static const double cutSlack = 40;

  /// WP-TRAIL: the fastest real world motion (pt/s) the trail follows.
  static const double maxWorldSpeed = 1500;

  /// WP-TRAIL: the bird's centre path is sampled every this many pt.
  static const double pathStep = 1.5;
}
