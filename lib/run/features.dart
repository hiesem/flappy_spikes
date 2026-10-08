import 'items/analytics_router.dart';
import 'items/met_elements.dart';
import 'items/scoring.dart';
import 'run_feature.dart';

/// The run features of a run, in attach order (ARCH §1.7). One region per
/// WP; append only.
List<RunFeature> buildRunFeatures() => [
  // region WP-0b
  MetElementsFeature(),
  AnalyticsRouter(),
  // endregion WP-0b
  // region anchors — append below (one region per WP)
  // endregion anchors
  // region WP-1a — scoring (PRD-2 §3.0.1, §3.1, §3.2)
  ScoringFeature(),
  // endregion WP-1a
];
