import 'package:flutter/foundation.dart';

import '../elements.dart';
import 'pickup.dart';
import 'placeholder_heart.dart';

/// Registered pickup kinds (ARCH §1.6). One registration line per WP,
/// inside its region. Capsule types: WP-3f registers `capsule` plus each
/// type element it supports.
final Map<ElementId, PickupKind Function()> _kinds = {
  // region WP-1b — heart placement wiring (PRD-2 §3.0.3 / §3.3).
  // PLACEHOLDER: WP-2a replaces this line with its real heart kind.
  ElementId.heart: PlaceholderHeartKind.new,
  // endregion WP-1b
  // region anchors — append below (one region per WP)
  // endregion anchors
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
