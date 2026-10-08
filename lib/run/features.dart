import 'hoops/motion/moving_rings_feature.dart';
import 'items/analytics_router.dart';
import 'items/met_elements.dart';
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
];
