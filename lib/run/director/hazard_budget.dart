import 'plans.dart';

/// PRD-2.6 D3 rolling four-slot hazard accounting.
///
/// The M1 ledger is deliberately permissive: it records nothing and accepts
/// every plan. The curve task replaces these methods while retaining the API.
class HazardBudget {
  double budgetAt(int hoop) => double.infinity;

  double costOf(SlotPlan plan) => plan.hazardCost;

  bool allows(SlotPlan plan) => true;

  void add(SlotPlan plan) {}
}
