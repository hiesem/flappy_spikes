import 'package:flutter/foundation.dart';

import '../elements.dart';
import 'pickup.dart';
import 'comet_star.dart';
import 'heart_pickup.dart';
import 'shield_pickup.dart';
import '../hoops/kinds/switch/switch_kind.dart'; // WP-3d
import 'capsule.dart'; // WP-3f
// region WP-3e — collectable pickups (PRD-2 §3.26–§3.29)
import 'egg_pickup.dart';
import 'firefly_swarm.dart';
import 'jar_pickup.dart';
import 'piggy_coin.dart';
import 'piggy_pickup.dart';
import 'star_trail.dart';
// endregion WP-3e

/// Registered pickup kinds (ARCH §1.6). One registration line per WP,
/// inside its region. Capsule types: WP-3f registers `capsule` plus each
/// type element it supports.
final Map<ElementId, PickupKind Function()> _kinds = {
  // region anchors — append below (one region per WP)
  // endregion anchors
  // region WP-2a — hearts / shield (PRD-2 §3.3, §3.7)
  ElementId.heart: HeartPickupKind.new,
  ElementId.shield: ShieldPickupKind.new,
  // endregion WP-2a
  // region WP-3a — the comet star (PRD-2 §3.8)
  ElementId.comet: CometStarKind.new,
  // endregion WP-3a
  // region WP-3d — the switch of a switch ring (PRD-2 §3.20)
  ElementId.switchRing: SwitchPickupKind.new,
  // endregion WP-3d
  // region WP-3f — powerup capsules (PRD-2 §3.30–§3.32)
  ElementId.capsule: CapsulePickupKind.new,
  // endregion WP-3f
  // region WP-3e — collectables (PRD-2 §3.26–§3.29)
  ElementId.starTrail: StarTrailKind.new,
  ElementId.egg: EggPickupKind.new,
  ElementId.piggy: PiggyPickupKind.new,
  ElementId.piggyCoins: PiggyCoinKind.new,
  ElementId.jar: JarPickupKind.new,
  ElementId.fireflySwarm: FireflySwarmKind.new,
  // endregion WP-3e
};

/// Elements switched on without a pickup of their own (e.g. capsule types
/// sharing the capsule pickup).
final Set<ElementId> _pickupElements = {
  // region anchors — append below (one region per WP)
  // endregion anchors
  // region WP-3f — the capsule types share the capsule pickup (§3.30–§3.32)
  ElementId.hourglass,
  ElementId.miniBird,
  ElementId.coinFrenzy,
  // endregion WP-3f
};

@visibleForTesting
final Map<ElementId, PickupKind Function()> testPickupKinds = {};
@visibleForTesting
final Set<ElementId> testPickupElements = {};

final Map<ElementId, PickupKind> _cache = {};

PickupKind? pickupKindFor(ElementId e) {
  final test = testPickupKinds[e];
  if (test != null) return test();
  final f = _kinds[e];
  if (f == null) return null;
  return _cache[e] ??= f();
}

Set<ElementId> registeredPickupElements() => {
  ..._kinds.keys,
  ..._pickupElements,
  ...testPickupKinds.keys,
  ...testPickupElements,
};
