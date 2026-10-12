/// Decision data produced by the run director (PRD-2 §3.0.3). Pure Dart.
///
/// `RunSpawner` turns these into components through the `HoopKind` and
/// `PickupKind` registries; nothing here knows about Flame.
library;

import '../elements.dart';

/// The hoop kinds of PRD-2 §7 ("one `Hoop` component with a `kind`").
///
/// Lives here (not in `hoops/hoop_kind.dart`, which re-exports it) so the
/// director stays pure Dart (ARCH §1.2).
enum HoopKindId {
  normal,
  bullseye,
  train,
  spring,
  switchRing,
  pair,
  fever,
  luckySpin,
  saw,
  portal,
  rideRing,
  // region anchors — append below
  // endregion anchors
  ;

  /// The catalogue element of this kind (ride rings count as normal hoops).
  ElementId get element => switch (this) {
    HoopKindId.normal => ElementId.normalHoop,
    HoopKindId.bullseye => ElementId.bullseye,
    HoopKindId.train => ElementId.train,
    HoopKindId.spring => ElementId.spring,
    HoopKindId.switchRing => ElementId.switchRing,
    HoopKindId.pair => ElementId.pair,
    HoopKindId.fever => ElementId.fever,
    HoopKindId.luckySpin => ElementId.luckySpin,
    HoopKindId.saw => ElementId.saw,
    HoopKindId.portal => ElementId.portal,
    HoopKindId.rideRing => ElementId.normalHoop,
  };

  /// The special-hoop kind of [e], if [e] is one (§3.0.3 table).
  static HoopKindId? specialFor(ElementId e) => switch (e) {
    ElementId.bullseye => HoopKindId.bullseye,
    ElementId.train => HoopKindId.train,
    ElementId.spring => HoopKindId.spring,
    ElementId.switchRing => HoopKindId.switchRing,
    ElementId.pair => HoopKindId.pair,
    ElementId.fever => HoopKindId.fever,
    ElementId.luckySpin => HoopKindId.luckySpin,
    ElementId.saw => HoopKindId.saw,
    _ => null,
  };
}

/// Timed powerup + portal ride kinds (§3.8, §3.12).
enum RideKind { comet, portal }

/// The six portal rides (§3.12, §5.12b). [storageId] is persisted
/// (`lastPortalRide`).
enum RideId {
  cannon,
  space,
  volcano,
  sea,
  pinball,
  storm;

  String get storageId => name;

  static RideId? fromStorageId(String? id) {
    for (final r in values) {
      if (r.name == id) return r;
    }
    return null;
  }
}

/// Pair gifts (§3.21).
enum PairReward { shield, comet, coins, score, fever }

/// Capsule powerups (§3.30–3.32).
enum CapsuleType {
  hourglass,
  miniBird,
  coinFrenzy;

  ElementId get element => switch (this) {
    CapsuleType.hourglass => ElementId.hourglass,
    CapsuleType.miniBird => ElementId.miniBird,
    CapsuleType.coinFrenzy => ElementId.coinFrenzy,
  };
}

/// Saw-ring designs (§3.18): never the same twice in a row per run.
enum SawDesign { liveWire, frostRing, blackHole }

/// Switch-ring designs (§3.20): never the same twice in a row per run.
enum SwitchDesign { lockdown, laserGate, powerIris, snoozer, giftWrap }

/// Moving-ring types (§3.0.2, §3.11).
enum MotionType { rail, swing, horizontal, diagonal, orbit, rock }

/// Spring launch direction (§3.23).
enum SpringDir { up, down }

/// One moving-ring motion, as rolled by the director (WP-1b turns it into a
/// `HoopMotion`). Angles in degrees, distances in pt, speeds in pt/s, times
/// in s. Unused fields are 0.
class MotionSpec {
  const MotionSpec({
    required this.type,
    this.axisDeg = 0,
    this.halfTravel = 0,
    this.speed = 0,
    this.phase = 0,
    this.amplitudeDeg = 0,
    this.period = 0,
    this.rope = 0,
    this.rx = 0,
    this.ry = 0,
    this.omega = 0,
  });

  final MotionType type;

  /// Rail / horizontal / diagonal: slide axis (0 = vertical, 90 = horizontal).
  final double axisDeg;
  final double halfTravel;
  final double speed;

  /// Rail: 0..1 of a ping-pong cycle; swing / orbit / rock: radians.
  final double phase;

  /// Swing / rock.
  final double amplitudeDeg;
  final double period;

  /// Swing: rope length from the pivot above the top spikes.
  final double rope;

  /// Orbit.
  final double rx;
  final double ry;
  final double omega;

  @override
  bool operator ==(Object other) =>
      other is MotionSpec &&
      other.type == type &&
      other.axisDeg == axisDeg &&
      other.halfTravel == halfTravel &&
      other.speed == speed &&
      other.phase == phase &&
      other.amplitudeDeg == amplitudeDeg &&
      other.period == period &&
      other.rope == rope &&
      other.rx == rx &&
      other.ry == ry &&
      other.omega == omega;

  @override
  int get hashCode => Object.hash(
    type,
    axisDeg,
    halfTravel,
    speed,
    phase,
    amplitudeDeg,
    period,
    rope,
    rx,
    ry,
    omega,
  );

  @override
  String toString() =>
      'Motion(${type.name} axis ${axisDeg.toStringAsFixed(1)} '
      'half ${halfTravel.toStringAsFixed(1)} v ${speed.toStringAsFixed(1)})';
}

/// The two gifts of a pair (§3.21): [top] on the upper ring.
class PairRewards {
  const PairRewards(this.top, this.bottom);
  final PairReward top;
  final PairReward bottom;

  @override
  bool operator ==(Object other) =>
      other is PairRewards && other.top == top && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(top, bottom);

  @override
  String toString() => 'Pair(${top.name}/${bottom.name})';
}

/// Ring Train layout (§3.22): three rings [dx] apart, each [dy] further in
/// [dir] (−1 up, +1 down).
class TrainSpec {
  const TrainSpec({required this.dir, required this.dx, required this.dy});
  final int dir;
  final double dx;
  final double dy;

  @override
  bool operator ==(Object other) =>
      other is TrainSpec && other.dir == dir && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dir, dx, dy);

  @override
  String toString() => 'Train($dir)';
}

/// Lucky Spin prize (§3.25): the slice index and its coins, pre-rolled.
class SpinPrize {
  const SpinPrize(this.slice, this.coins);
  final int slice;
  final int coins;

  @override
  bool operator ==(Object other) =>
      other is SpinPrize && other.slice == slice && other.coins == coins;

  @override
  int get hashCode => Object.hash(slice, coins);

  @override
  String toString() => 'Spin($coins)';
}

/// One item in a gap (or attached to a slot: the switch before a switch
/// ring, the comet star in a hoop).
class GapItemPlan {
  const GapItemPlan({
    required this.kind,
    required this.trackX,
    this.y,
    this.lineOffset = 0,
    this.extra,
    this.toTrackX,
    this.toY,
  });

  /// heart, feather, puzzlePiece, switchRing (its switch), starTrail,
  /// capsule, egg, piggy, jar, shield, piggyCoins, fireflySwarm, comet.
  final ElementId kind;

  /// Track x of the item (star trail / coins / swarm: the start of the run).
  final double trackX;

  /// Absolute screen y, or null = on the straight line between the hoops
  /// around [trackX] plus [lineOffset], resolved by the spawner.
  final double? y;

  /// Offset from the line (heart / shield "off the line by 0.1–0.4 band").
  final double lineOffset;

  /// Star trail / piggy coins / swarm: the end x of the run.
  final double? toTrackX;

  /// The line's y at [toTrackX] (filled by the spawner).
  final double? toY;

  /// A copy with the line resolved by the spawner.
  GapItemPlan resolved({required double y, double? toY}) => GapItemPlan(
    kind: kind,
    trackX: trackX,
    y: y,
    lineOffset: lineOffset,
    extra: extra,
    toTrackX: toTrackX,
    toY: toY,
  );

  /// CapsuleType | int puzzle slot | SwitchDesign | int count.
  final Object? extra;

  @override
  bool operator ==(Object other) =>
      other is GapItemPlan &&
      other.kind == kind &&
      other.trackX == trackX &&
      other.y == y &&
      other.lineOffset == lineOffset &&
      other.toTrackX == toTrackX &&
      other.toY == toY &&
      other.extra == extra;

  @override
  int get hashCode =>
      Object.hash(kind, trackX, y, lineOffset, toTrackX, extra);

  @override
  String toString() =>
      '${kind.storageId}@${trackX.toStringAsFixed(1)}'
      '${y == null ? '' : ',y${y!.toStringAsFixed(1)}'}'
      '${extra == null ? '' : '[$extra]'}';
}

/// The director's decision for one hoop slot.
class SlotPlan {
  const SlotPlan({
    required this.index,
    required this.kind,
    required this.element,
    required this.trackX,
    required this.centreY,
    required this.opening,
    this.tiltDeg = 0,
    this.motion,
    this.cometHang = false,
    this.ringOffsets = const [0],
    required this.advance,
    this.extra,
    this.forced = false,
    this.attached = const [],
    this.duringRide = false,
  });

  final int index;
  final HoopKindId kind;
  final ElementId element;

  /// Track x of the (first) ring's plane.
  final double trackX;
  final double centreY;

  /// Opening incl. saw +28 and the Big Hoops multiplier (capped to the band).
  final double opening;

  /// 0 for specials, the comet hoop and rides.
  final double tiltDeg;

  /// Normal hoops only.
  final MotionSpec? motion;

  /// The comet star hangs 20 pt past this hoop's plane (§3.8).
  final bool cometHang;

  /// `[0]`, or a pair's `[−o/2, +o/2]` with o = 230 × viewHeight / 711.
  final List<double> ringOffsets;

  /// Spacing to the next slot (train: 2 × 56 + 310).
  final double advance;

  /// PairRewards | SpringDir | SpinPrize | SawDesign | SwitchDesign |
  /// TrainSpec | RideId.
  final Object? extra;

  /// First-meet or debug force.
  final bool forced;

  /// Items placed with this slot: the switch of a switch ring (it sits in
  /// the gap BEFORE the ring), the comet star of a comet hoop.
  final List<GapItemPlan> attached;

  /// Spawned while a ride was on (full size, upright, still).
  final bool duringRide;

  /// A copy with the given fields replaced (PRD-2.2 §15 / §27: the
  /// spawner turns a planned-ahead slot into a plain one).
  SlotPlan copyWith({
    HoopKindId? kind,
    ElementId? element,
    double? centreY,
    double? opening,
    double? tiltDeg,
    MotionSpec? Function()? motion,
    bool? cometHang,
    List<double>? ringOffsets,
    Object? Function()? extra,
    bool? forced,
    List<GapItemPlan>? attached,
    bool? duringRide,
  }) => SlotPlan(
    index: index,
    kind: kind ?? this.kind,
    element: element ?? this.element,
    trackX: trackX,
    centreY: centreY ?? this.centreY,
    opening: opening ?? this.opening,
    tiltDeg: tiltDeg ?? this.tiltDeg,
    motion: motion != null ? motion() : this.motion,
    cometHang: cometHang ?? this.cometHang,
    ringOffsets: ringOffsets ?? this.ringOffsets,
    advance: advance,
    extra: extra != null ? extra() : this.extra,
    forced: forced ?? this.forced,
    attached: attached ?? this.attached,
    duringRide: duringRide ?? this.duringRide,
  );

  /// Track x of the last ring of the slot (train: + 2 × 56).
  double get lastRingX => kind == HoopKindId.train && extra is TrainSpec
      ? trackX + 2 * (extra as TrainSpec).dx
      : trackX;

  @override
  bool operator ==(Object other) =>
      other is SlotPlan &&
      other.index == index &&
      other.kind == kind &&
      other.element == element &&
      other.trackX == trackX &&
      other.centreY == centreY &&
      other.opening == opening &&
      other.tiltDeg == tiltDeg &&
      other.motion == motion &&
      other.cometHang == cometHang &&
      _listEq(other.ringOffsets, ringOffsets) &&
      other.advance == advance &&
      other.extra == extra &&
      other.forced == forced &&
      _listEq(other.attached, attached) &&
      other.duringRide == duringRide;

  @override
  int get hashCode => Object.hash(
    index,
    kind,
    trackX,
    centreY,
    opening,
    tiltDeg,
    motion,
    cometHang,
    Object.hashAll(ringOffsets),
    advance,
    extra,
    forced,
    Object.hashAll(attached),
  );

  @override
  String toString() =>
      '#$index ${kind.name}${forced ? '!' : ''} '
      'y${centreY.toStringAsFixed(1)} o${opening.toStringAsFixed(1)}'
      '${tiltDeg == 0 ? '' : ' t$tiltDeg'}${motion == null ? '' : ' $motion'}'
      '${cometHang ? ' comet' : ''}${extra == null ? '' : ' $extra'}'
      '${attached.isEmpty ? '' : ' +$attached'}';
}

/// The director's decision for the gap after slot [index].
class GapPlan {
  const GapPlan({required this.index, this.items = const []});
  final int index;
  final List<GapItemPlan> items;

  bool get isEmpty => items.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is GapPlan && other.index == index && _listEq(other.items, items);

  @override
  int get hashCode => Object.hash(index, Object.hashAll(items));

  @override
  String toString() => 'gap#$index $items';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
