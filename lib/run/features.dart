import 'hoops/motion/moving_rings_feature.dart';
import 'items/analytics_router.dart';
import 'items/big_hoops.dart';
import 'items/comet.dart';
import 'items/extra_life.dart';
import 'items/fever.dart'; // WP-3c
import 'hoops/kinds/saw/saw_death.dart'; // WP-3d
import 'hoops/kinds/switch/switch_kind.dart'; // WP-3d
import 'items/invulnerability.dart';
import 'items/shield.dart';
import 'items/met_elements.dart';
import 'items/rumble_router.dart';
import 'items/scoring.dart';
import 'items/squeeze.dart'; // WP-3g
import 'items/versus_recorder.dart'; // WP-5b
import 'items/streak.dart';
import 'rides/portal_ride.dart';
import 'run_feature.dart';
import 'screens/revive_rules.dart';

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
  // region WP-3c — FEVER fire (PRD-2 §3.19, §5.18); before the streak, so
  // it sees the streak before a pass / save changes it
  FeverFeature(),
  // endregion WP-3c
  // region WP-2a — hearts / extra life / shield / Big Hoops (PRD-2 §3.3, §3.6, §3.7)
  BigHoopsFeature(),
  ShieldFeature(),
  ExtraLifeFeature(),
  InvulnerabilityFeature(),
  // endregion WP-2a
  // region WP-1a — scoring (PRD-2 §3.0.1, §3.1, §3.2)
  ScoringFeature(),
  // endregion WP-1a
  // region WP-2b — perfect streak, ring tiers, banners, pass sounds; rumble
  // (WP-2c folded in) (PRD-2 §3.4, §3.5, §3.33, §5.3, §5.4)
  StreakFeature(),
  RumbleRouter(),
  // endregion WP-2b
  // region WP-3b — portal roller-coaster rides (PRD-2 §3.12, §5.12b)
  PortalRideFeature(),
  // endregion WP-3b
  // region WP-3a — comet boost (PRD-2 §3.8, §3.9, §5.6)
  CometFeature(),
  // endregion WP-3a
  // region WP-3d — saw-ring deaths / hums / lensing, switch-ring crashes
  // (PRD-2 §3.18, §3.20, §5.17, §5.19)
  SawFeature(),
  SwitchRingFeature(),
  // endregion WP-3d
  // region WP-3g — spike squeeze (PRD-2 §3.17, §5.16); before 2d's revive
  // rules, so it sees a running squeeze before the revive resets it
  SqueezeFeature(),
  // endregion WP-3g
  // region WP-5b — versus timeline + duel (PRD-2 §3.13)
  VersusRecorder(),
  // endregion WP-5b
  // region WP-2d — revive rules (PRD-2 §3.14); keep last
  ReviveRulesFeature(),
  // endregion WP-2d
];
