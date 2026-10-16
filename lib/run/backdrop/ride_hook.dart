import 'dart:ui';

import 'backdrop_scene.dart';

/// PRD-2.4 §3.5 the hook a portal ride uses to drive the background around
/// its exit, launch, glide and landing (WP-R fills it in). Every method has
/// a "do nothing" default: with no hook, or this base class, the background
/// simply follows the run camera and rides look exactly as before.
///
/// Set it with `RunBackdrop.rideHook = …` while the ride runs and clear it
/// (null) when the ride is over. The ride phase is read from the run
/// (`RunBackdrop.ridePhase`, i.e. `RunState.ride?.phase`), `camX` / `camY`
/// from `RunState`.
abstract class BackdropRideHook {
  const BackdropRideHook();

  /// The offset (pt; x right, y down) added to where [band] is drawn this
  /// frame. Seam slabs and set pieces follow [Band.near] / their own band.
  Offset bandOffset(Band band) => Offset.zero;

  /// Overrides how far the world moves this frame: given the run camera's
  /// move [dc] (pt, screen-centre x), return the world distance to add, or
  /// null to keep the default mapping (README "World distance").
  double? scroll(double dc) => null;

  /// The part of the screen the ride's own scene still covers: add it to
  /// [covered] (screen coordinates, 320 × viewHeight) and return true; the
  /// background is then not drawn there. False = draw everywhere.
  bool cover(Path covered, double viewHeight) => false;

  /// WP-R: true while the ride's own scene covers the whole screen (a
  /// themed ride's scene once faded in, its exit): the background is not
  /// drawn at all.
  bool get hidden => false;

  /// WP-R (PRD-2.4 §3.5 "No gaps"): the largest sideways shift (pt, + =
  /// right) [band] gets during this handover, constant while it lasts:
  /// the band is drawn that much wider on the side it leaves open (plus a
  /// margin), so a layer that slides in has no open edge.
  double sideReach(Band band) => 0;
}
