import 'dart:math' show max;

import '../config/tuning_values.dart';
import '../elements.dart';
import 'plans.dart';

/// PRD-2.6 D3 rolling four-slot hazard accounting.
class HazardBudget {
  HazardBudget([TuningValues? values]) : _values = values ?? tuning;

  final TuningValues _values;
  final List<double> _ledger = [];

  static const int windowSize = 4;

  double budgetAt(int hoop) => _values.curve('hazard_budget').at(hoop);

  double costOf(
    SlotPlan plan, {
    double? previousY,
    double? rowP90,
    bool squeeze = false,
  }) {
    final costs = _values.obj('hazard_costs');
    if (plan.cometHang || plan.duringRide || _isRewardOrRide(plan.kind)) {
      return 0;
    }

    var cost = 0.0;
    cost += switch (plan.kind) {
      HoopKindId.saw => costs['saw']!,
      HoopKindId.switchRing => costs['switch']!,
      HoopKindId.spring => costs['spring']!,
      HoopKindId.pair => costs['pair']!,
      HoopKindId.train => costs['train']!,
      HoopKindId.normal ||
      HoopKindId.bullseye ||
      HoopKindId.fever ||
      HoopKindId.luckySpin ||
      HoopKindId.portal ||
      HoopKindId.rideRing => 0,
    };

    final tilt = plan.tiltDeg.abs();
    if (tilt > 0) {
      cost += tilt <= 20
          ? costs['tilt_20']!
          : tilt <= 30
          ? costs['tilt_30']!
          : costs['tilt_45']!;
    }
    if (plan.motion case final motion?) {
      cost += switch (motion.type) {
        MotionType.rail => costs['rail']!,
        MotionType.swing => costs['swing']!,
        MotionType.horizontal ||
        MotionType.diagonal ||
        MotionType.orbit ||
        MotionType.rock => costs['other_motion']!,
      };
    }
    if (previousY != null && rowP90 != null) {
      final dy = (plan.centreY - previousY).abs();
      // A Δy clamped exactly to p90 is not "above p90"; binary division can
      // land a fraction of an ulp over it, so compare with the ledger's own
      // tolerance.
      if (dy > rowP90 + _epsilon) {
        cost += costs['dy_p90']!;
      }
    }
    if (squeeze) {
      cost += costs['squeeze']!;
    }
    return cost;
  }

  bool allows(
    SlotPlan plan, {
    double? previousY,
    double? rowP90,
    bool squeeze = false,
  }) {
    if (plan.forced) return true;
    final cost = costOf(
      plan,
      previousY: previousY,
      rowP90: rowP90,
      squeeze: squeeze,
    );
    return _windowSum + cost <= budgetAt(plan.index) + _epsilon;
  }

  void add(
    SlotPlan plan, {
    double? previousY,
    double? rowP90,
    bool squeeze = false,
  }) {
    _ledger.add(
      costOf(plan, previousY: previousY, rowP90: rowP90, squeeze: squeeze),
    );
    if (_ledger.length > windowSize) {
      _ledger.removeRange(0, _ledger.length - windowSize);
    }
  }

  /// Checks a complete reserved shape without changing the live ledger.
  bool allowsSequence(
    List<SlotPlan> plans, {
    required double previousY,
    required double rowP90,
  }) {
    final preview = HazardBudget(_values).._ledger.addAll(_ledger);
    var previous = previousY;
    for (final plan in plans) {
      if (!preview.allows(plan, previousY: previous, rowP90: rowP90)) {
        return false;
      }
      preview.add(plan, previousY: previous, rowP90: rowP90);
      previous = plan.centreY;
    }
    return true;
  }

  SlotPlan downgrade(
    SlotPlan plan, {
    double? previousY,
    double? rowP90,
    bool squeeze = false,
    bool preserveDy = false,
  }) {
    if (plan.forced) return plan;

    SlotPlan current = _withCost(
      plan,
      previousY: previousY,
      rowP90: rowP90,
      squeeze: squeeze,
    );
    if (_fits(
      current,
      previousY: previousY,
      rowP90: rowP90,
      squeeze: squeeze,
    )) {
      return current;
    }

    current = _withCost(
      current.copyWith(motion: () => null),
      previousY: previousY,
      rowP90: rowP90,
      squeeze: squeeze,
    );
    if (_fits(
      current,
      previousY: previousY,
      rowP90: rowP90,
      squeeze: squeeze,
    )) {
      return current;
    }

    final tilt = current.tiltDeg;
    if (tilt.abs() > 15) {
      current = _withCost(
        current.copyWith(tiltDeg: tilt.sign * 15),
        previousY: previousY,
        rowP90: rowP90,
        squeeze: squeeze,
      );
    }
    if (_fits(
      current,
      previousY: previousY,
      rowP90: rowP90,
      squeeze: squeeze,
    )) {
      return current;
    }

    if (!preserveDy && previousY != null && rowP90 != null) {
      final delta = current.centreY - previousY;
      if (delta.abs() > rowP90 + _epsilon) {
        current = _withCost(
          current.copyWith(centreY: previousY + delta.sign * rowP90),
          previousY: previousY,
          rowP90: rowP90,
          squeeze: squeeze,
        );
      }
    }
    if (_fits(
      current,
      previousY: previousY,
      rowP90: rowP90,
      squeeze: squeeze,
    )) {
      return current;
    }

    return _withCost(
      current.copyWith(
        kind: HoopKindId.normal,
        element: ElementId.normalHoop,
        ringOffsets: const [0],
        extra: () => null,
        attached: const [],
      ),
      previousY: previousY,
      rowP90: rowP90,
      squeeze: squeeze,
    );
  }

  /// Whether [current] and the following slot's [nextCost] fit the four-slot
  /// window. The next slot's row / squeeze costs are supplied by the caller;
  /// this lets the director reserve the fixed 240 pt spring landing (§3.23)
  /// before it commits the spring itself.
  bool allowsFollowing(
    SlotPlan current, {
    required double nextCost,
    required int nextIndex,
    double? previousY,
    double? rowP90,
    bool squeeze = false,
  }) {
    if (current.forced) return true;
    final costs = [..._ledger];
    if (costs.length >= windowSize) {
      costs.removeRange(0, costs.length - (windowSize - 2));
    }
    costs.add(
      costOf(current, previousY: previousY, rowP90: rowP90, squeeze: squeeze),
    );
    final sum = costs.fold(0.0, (total, cost) => total + cost);
    return sum + nextCost <= budgetAt(nextIndex) + _epsilon;
  }

  SlotPlan _withCost(
    SlotPlan plan, {
    double? previousY,
    double? rowP90,
    bool squeeze = false,
  }) => plan.copyWith(
    hazardCost: costOf(
      plan,
      previousY: previousY,
      rowP90: rowP90,
      squeeze: squeeze,
    ),
  );

  bool _fits(
    SlotPlan plan, {
    double? previousY,
    double? rowP90,
    bool squeeze = false,
  }) => _windowSum + plan.hazardCost <= budgetAt(plan.index) + _epsilon;

  /// The previous three costs only: the candidate fills the fourth slot.
  double get _windowSum => _ledger
      .skip(max(0, _ledger.length - (windowSize - 1)))
      .fold(0.0, (sum, cost) => sum + cost);

  static bool _isRewardOrRide(HoopKindId kind) => switch (kind) {
    HoopKindId.bullseye ||
    HoopKindId.fever ||
    HoopKindId.luckySpin ||
    HoopKindId.portal ||
    HoopKindId.rideRing => true,
    HoopKindId.normal ||
    HoopKindId.saw ||
    HoopKindId.switchRing ||
    HoopKindId.spring ||
    HoopKindId.pair ||
    HoopKindId.train => false,
  };

  static const double _epsilon = 0.000001;
}
