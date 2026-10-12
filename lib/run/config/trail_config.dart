import '../../game/config.dart';

/// The bird's run trail (PRD-2.2 §21.1, supersedes the trail scale of
/// PRD-2 §3.5 / `TierTrail`; mock `design/menu_v2/screen_fire_choice2.html`).
/// Every member's doc starts with its PRD section.
abstract final class TrailConfig {
  /// PRD-2.2 §21.1 From tier 3 every equipped trail is drawn at 2× today's
  /// scale (today: the look scale ≈ 0.98).
  static const double runScale = 2 * Config.lookScale;

  /// PRD-2.2 §21.1 The block trail (Pixel blocks) at 2× its master size.
  static const double blockScale = 2;

  /// PRD-2.2 §21.1 Emission point behind the bird along the flight
  /// direction (pt; was 26).
  static const double runBack = 18;

  /// PRD-2.2 §21.1 The equipped trail drifts left at this share of the
  /// forward speed (the mock's −140 pt/s at 200 pt/s).
  static const double scrollShare = .7;
}
