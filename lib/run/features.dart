import 'hoops/motion/moving_rings_feature.dart';
import 'items/analytics_router.dart';
import 'items/met_elements.dart';
import 'items/rumble_router.dart';
import 'items/scoring.dart';
import 'items/streak.dart';
import 'run_feature.dart';

/// The run features of a run, in attach order (ARCH §1.7). One region per
/// WP; append only.
List<RunFeature> buildRunFeatures() => [
  // region WP-0b
  MetElementsFeature(),
  AnalyticsRouter(),
  // endregion WP-0b
  // region WP-1b — angled / moving rings (PRD-2 §3.10, §3.11)
  MovingRingsFeature(),
  // endregion WP-1b
  // region anchors — append below (one region per WP)
  // endregion anchors
  // region WP-1a — scoring (PRD-2 §3.0.1, §3.1, §3.2)
  ScoringFeature(),
  // endregion WP-1a
  // region WP-2b — perfect streak, ring tiers, banners, pass sounds; rumble
  // (WP-2c folded in) (PRD-2 §3.4, §3.5, §3.33, §5.3, §5.4)
  StreakFeature(),
  RumbleRouter(),
  // endregion WP-2b
];
