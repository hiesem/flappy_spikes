import 'package:flutter/foundation.dart';

import '../../elements.dart';
import '../hoop_kind.dart';

/// Registered hoop kinds (ARCH §1.5). A kind that is not registered here is
/// never offered by the director. One registration line per WP, inside its
/// region.
final Map<HoopKindId, HoopKind Function()> _kinds = {
  // region anchors — append below (one region per WP)
  // endregion anchors
};

/// Modifier / scheduled elements that ride on hoops (angled, moving, comet,
/// portal…) and are switched on by their WP.
final Set<ElementId> _hoopElements = {
  // region WP-1b — angled and moving rings (PRD-2 §3.10, §3.11)
  ElementId.angledRing,
  ElementId.movingRing,
  // endregion WP-1b
  // region anchors — append below (one region per WP)
  // endregion anchors
};

/// Test seams: kinds / elements registered by a test.
@visibleForTesting
final Map<HoopKindId, HoopKind Function()> testHoopKinds = {};
@visibleForTesting
final Set<ElementId> testHoopElements = {};

final Map<HoopKindId, HoopKind> _cache = {};

HoopKind? hoopKindFor(HoopKindId id) {
  final f = testHoopKinds[id] ?? _kinds[id];
  if (f == null) return null;
  if (testHoopKinds.containsKey(id)) return f();
  return _cache[id] ??= f();
}

/// Elements the hoop registry offers: the registered kinds' elements plus
/// the registered hoop modifiers.
Set<ElementId> registeredElements() => {
  for (final id in {..._kinds.keys, ...testHoopKinds.keys}) id.element,
  ..._hoopElements,
  ...testHoopElements,
};
