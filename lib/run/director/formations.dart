import 'dart:math' as math;

import '../config/run_config.dart';
import '../config/tuning_values.dart';
import '../elements.dart';
import 'plans.dart';

/// The six PRD-2.6 D7 post-ceiling formations.
enum FormationId { stairs, slalom, tiltWave, syncRails, sawGate, switchChain }

/// The hard-special families rotated by the post-ceiling mix chapters.
enum MixWeightKey { saw, switchRing, moving }

/// One post-ceiling mix chapter (50 hoops each).
enum MixChapter { sawHeavy, switchHeavy, movingHeavy }

/// Builds deterministic multi-hoop formations from hoop 150.
///
/// An instance without a seed (or random) stays inert for the M1 wiring. The
/// director passes its layout stream; `nextAt` schedules whole formations and
/// `build` emits slot templates with constant 310 pt plane spacing.
class Formations {
  Formations({
    int? seed,
    math.Random? random,
    List<int>? formationEvery,
    this.fromHoop = 150,
  }) : _seed = seed ?? 0,
       _random = random ?? (seed == null ? null : math.Random(seed)),
       _formationEvery =
           formationEvery ??
           List<int>.unmodifiable(
             TuningValues.current.ints('formation_every'),
           ) {
    if (_formationEvery.length != 2 ||
        _formationEvery[0] < 1 ||
        _formationEvery[0] > _formationEvery[1]) {
      throw ArgumentError.value(
        _formationEvery,
        'formationEvery',
        'must be an inclusive [min, max] interval',
      );
    }
    if (fromHoop < 0) {
      throw ArgumentError.value(fromHoop, 'fromHoop', 'must not be negative');
    }
    _nextStart = fromHoop;
  }

  final int _seed;
  final math.Random? _random;
  final List<int> _formationEvery;

  /// First hoop at which a formation may start.
  final int fromHoop;

  int _nextStart = 150;
  final List<FormationId> _recent = [];

  FormationId? nextAt(int hoop) {
    final random = _random;
    if (random == null || hoop < _nextStart || hoop < fromHoop) return null;

    final options = FormationId.values
        .where((id) => !_recent.contains(id))
        .toList();
    final id = options[random.nextInt(options.length)];
    _recent
      ..add(id)
      ..removeRange(0, math.max(0, _recent.length - 2));
    _nextStart =
        hoop +
        _formationEvery[0] +
        random.nextInt(_formationEvery[1] - _formationEvery[0] + 1);
    return id;
  }

  /// Returns [id]'s spawnable slots. The optional origin values let the
  /// director place a template without changing its shape; the defaults emit a
  /// normalized template around y 0.
  List<SlotPlan> build(
    FormationId id,
    int startHoop, {
    double startTrackX = 0,
    double centreY = 0,
  }) {
    if (startHoop < fromHoop || startHoop < 150) {
      throw ArgumentError.value(
        startHoop,
        'startHoop',
        'is before the ceiling',
      );
    }

    final geometrySeed =
        ((_seed ^ (id.index + 1) * 0x1F123BB5) + startHoop) & 0x7FFFFFFF;
    final geometry = math.Random(geometrySeed);
    return switch (id) {
      FormationId.stairs => _stairs(startHoop, startTrackX, centreY, geometry),
      FormationId.slalom => _slalom(startHoop, startTrackX, centreY, geometry),
      FormationId.tiltWave => _tiltWave(startHoop, startTrackX, centreY),
      FormationId.syncRails => _syncRails(
        startHoop,
        startTrackX,
        centreY,
        geometry,
      ),
      FormationId.sawGate => _sawGate(
        startHoop,
        startTrackX,
        centreY,
        geometry,
      ),
      FormationId.switchChain => _switchChain(
        startHoop,
        startTrackX,
        centreY,
        geometry,
      ),
    };
  }

  /// The chapter containing [hoop]. Hoops 150–199 favour saw, 200–249 switch
  /// and 250–299 moving; the cycle then repeats.
  static MixChapter chapterAt(int hoop) {
    if (hoop < 150) {
      throw ArgumentError.value(hoop, 'hoop', 'mix chapters start at hoop 150');
    }
    return MixChapter.values[((hoop - 150) ~/ 50) % MixChapter.values.length];
  }

  /// Scales [weights] around an equal budget. The chapter's family gets six
  /// times the relative mass of either non-chapter family; normalization keeps
  /// every chapter's total identical.
  static Map<MixWeightKey, double> mixWeightsAt(
    int hoop,
    Map<MixWeightKey, num> weights,
  ) {
    final chapter = chapterAt(hoop);
    final raw = <MixWeightKey, double>{};
    for (final key in MixWeightKey.values) {
      final base = weights[key]?.toDouble() ?? 0;
      if (base < 0) {
        throw ArgumentError.value(
          base,
          'weights[$key]',
          'must not be negative',
        );
      }
      final factor = switch (chapter) {
        MixChapter.sawHeavy => key == MixWeightKey.saw ? 3 : .5,
        MixChapter.switchHeavy => key == MixWeightKey.switchRing ? 3 : .5,
        MixChapter.movingHeavy => key == MixWeightKey.moving ? 3 : .5,
      };
      raw[key] = base * factor;
    }
    final rawTotal = raw.values.reduce((a, b) => a + b);
    if (rawTotal == 0) {
      throw ArgumentError.value(weights, 'weights', 'must have positive mass');
    }
    final total = weights.values
        .map((value) => value.toDouble())
        .reduce((a, b) => a + b);
    return {
      for (final entry in raw.entries)
        entry.key: entry.value * total / rawTotal,
    };
  }

  /// D7 runs on the D3 budget at the ceiling.
  static const double hazardBudgetAt150 = 5.5;

  /// Largest D3 cost in any four consecutive slots of [plans].
  static double fourSlotHazardCost(List<SlotPlan> plans) {
    var maximum = 0.0;
    for (var start = 0; start <= plans.length - 4; start++) {
      final cost = plans
          .skip(start)
          .take(4)
          .map((plan) => plan.hazardCost)
          .reduce((value, element) => value + element);
      maximum = math.max(maximum, cost);
    }
    return maximum;
  }

  List<SlotPlan> _stairs(int start, double x, double y, math.Random random) {
    final direction = random.nextBool() ? -1 : 1;
    final step = _range(random, 70, 90);
    final tilt = direction * 15.0;
    return [
      for (var offset = 0; offset < 4; offset++)
        _slot(
          id: FormationId.stairs,
          index: start + offset,
          trackX: x + offset * RunConfig.spacing,
          centreY: y + direction * offset * step,
          tiltDeg: tilt,
          hazardCost: 1.25,
        ),
    ];
  }

  List<SlotPlan> _slalom(int start, double x, double y, math.Random random) {
    final step = _range(random, 110, 130);
    return [
      for (var offset = 0; offset < 4; offset++)
        _slot(
          id: FormationId.slalom,
          index: start + offset,
          trackX: x + offset * RunConfig.spacing,
          centreY: y + (offset.isEven ? -step : step),
          hazardCost: 1,
        ),
    ];
  }

  List<SlotPlan> _tiltWave(int start, double x, double y) {
    const tilts = [-30.0, -15.0, 0.0, 15.0, 30.0];
    // PRD-2.6 D2/D7: strong tilts follow their approach sign, so the wave
    // rises through the negative tilts to the upright apex and descends
    // through the positive ones. A step of the minimum aligned Δy keeps every
    // approach valid without changing the angles or the 310 pt plane spacing.
    final step = TuningValues.current.d('tilt_align_min_dy');
    const path = [0.0, -1.0, -2.0, -1.0, 0.0];
    return [
      for (var offset = 0; offset < tilts.length; offset++)
        _slot(
          id: FormationId.tiltWave,
          index: start + offset,
          trackX: x + offset * RunConfig.spacing,
          centreY: y + path[offset] * step,
          tiltDeg: tilts[offset],
          hazardCost: switch (tilts[offset].abs()) {
            30 => 1,
            0 => 0,
            _ => .25,
          },
        ),
    ];
  }

  List<SlotPlan> _syncRails(int start, double x, double y, math.Random random) {
    final count = random.nextBool() ? 3 : 4;
    final motion = MotionSpec(
      type: MotionType.rail,
      halfTravel: _range(random, 30, 45),
      speed: _range(random, 34, 42),
      phase: random.nextDouble(),
    );
    return [
      for (var offset = 0; offset < count; offset++)
        _slot(
          id: FormationId.syncRails,
          index: start + offset,
          trackX: x + offset * RunConfig.spacing,
          centreY: y,
          motion: motion,
          hazardCost: 1,
        ),
    ];
  }

  List<SlotPlan> _sawGate(int start, double x, double y, math.Random random) {
    final design = SawDesign.values[random.nextInt(SawDesign.values.length)];
    return [
      _slot(id: FormationId.sawGate, index: start, trackX: x, centreY: y),
      _slot(
        id: FormationId.sawGate,
        index: start + 1,
        kind: HoopKindId.saw,
        trackX: x + RunConfig.spacing,
        centreY: y,
        extra: design,
        hazardCost: 2,
      ),
      _slot(
        id: FormationId.sawGate,
        index: start + 2,
        trackX: x + 2 * RunConfig.spacing,
        centreY: y,
      ),
    ];
  }

  List<SlotPlan> _switchChain(
    int start,
    double x,
    double y,
    math.Random random,
  ) {
    final designs = SwitchDesign.values;
    final first = designs[random.nextInt(designs.length)];
    final others = designs.where((design) => design != first).toList();
    final rest = others[random.nextInt(others.length)];
    final lead = math.max(
      RunConfig.switchLeadMin,
      RunConfig.switchLeadSeconds * RunConfig.cruise(start),
    );
    return [
      for (var offset = 0; offset < 3; offset++)
        _slot(
          id: FormationId.switchChain,
          index: start + offset,
          kind: HoopKindId.switchRing,
          trackX: x + offset * RunConfig.spacing,
          centreY: y,
          extra: offset == 0 ? first : rest,
          attached: [
            GapItemPlan(
              kind: ElementId.switchRing,
              trackX: x + offset * RunConfig.spacing - lead,
              y:
                  y +
                  (offset.isEven ? -1 : 1) *
                      _range(
                        random,
                        RunConfig.switchOffsetMin,
                        RunConfig.switchOffsetMax,
                      ),
              extra: offset == 0 ? first : rest,
            ),
          ],
          hazardCost: 1.5,
        ),
    ];
  }

  SlotPlan _slot({
    required FormationId id,
    required int index,
    required double trackX,
    required double centreY,
    HoopKindId kind = HoopKindId.normal,
    double tiltDeg = 0,
    MotionSpec? motion,
    Object? extra,
    List<GapItemPlan> attached = const [],
    double hazardCost = 0,
  }) {
    return SlotPlan(
      index: index,
      kind: kind,
      element: kind.element,
      trackX: trackX,
      centreY: centreY,
      opening: RunConfig.openingFor(index),
      tiltDeg: tiltDeg,
      motion: motion,
      advance: RunConfig.spacing,
      extra: extra,
      attached: attached,
      hazardCost: hazardCost,
      formation: id,
    );
  }

  static double _range(math.Random random, double min, double max) =>
      min + random.nextDouble() * (max - min);
}
