import 'package:flutter/foundation.dart';

import '../../elements.dart';
import '../hoop_kind.dart';
import 'normal.dart';
import 'portal.dart';
// region WP-3c — Bullseye / Train / Spring / Lucky Spin / FEVER
import 'bullseye.dart';
import 'fever.dart';
import 'lucky_spin.dart';
import 'spring.dart';
import 'train.dart';

// endregion WP-3c
// region WP-3d — saw rings, switch rings, pairs of powerup rings
import 'pair/pair_kind.dart';
import 'saw/saw_kind.dart';
import 'switch/switch_kind.dart';

// endregion WP-3d

/// Registered hoop kinds (ARCH §1.5). A kind that is not registered here is
/// never offered by the director. One registration line per WP, inside its
/// region.
final Map<HoopKindId, HoopKind Function()> _kinds = {
  // region anchors — append below (one region per WP)
  // endregion anchors
  // region WP-3c — Bullseye, Ring Train, Spring Ring, Lucky Spin, FEVER
  // (PRD-2 §3.19, §3.22–§3.25)
  HoopKindId.bullseye: BullseyeHoopKind.new,
  HoopKindId.train: TrainHoopKind.new,
  HoopKindId.spring: SpringHoopKind.new,
  HoopKindId.luckySpin: LuckySpinHoopKind.new,
  HoopKindId.fever: FeverHoopKind.new,
  // endregion WP-3c
  // region WP-1a — the normal hoop (PRD-2 §3.1)
  HoopKindId.normal: NormalHoopKind.new,
  // endregion WP-1a
  // region WP-3b — the portal and its ride rings (PRD-2 §3.12)
  HoopKindId.portal: PortalHoopKind.new,
  HoopKindId.rideRing: RideRingKind.new,
  // endregion WP-3b
  // region WP-3d — saw rings, switch rings, pairs of powerup rings
  // (PRD-2 §3.18, §3.20, §3.21)
  HoopKindId.saw: SawHoopKind.new,
  HoopKindId.switchRing: SwitchRingKind.new,
  HoopKindId.pair: PairHoopKind.new,
  // endregion WP-3d
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
