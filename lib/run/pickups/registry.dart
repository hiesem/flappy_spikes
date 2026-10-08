import 'package:flutter/foundation.dart';

import '../elements.dart';
import 'pickup.dart';
import 'comet_star.dart';
import 'heart_pickup.dart';
import 'shield_pickup.dart';

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
};

/// Elements switched on without a pickup of their own (e.g. capsule types
/// sharing the capsule pickup).
final Set<ElementId> _pickupElements = {
  // region anchors — append below (one region per WP)
  // endregion anchors
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
