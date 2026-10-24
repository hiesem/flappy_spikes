import 'plans.dart';

/// The six PRD-2.6 D7 post-ceiling formations.
enum FormationId { stairs, slalom, tiltWave, syncRails, sawGate, switchChain }

/// Builds deterministic multi-hoop formations from hoop 150.
///
/// The M1 planner emits no formation and changes no spacing or seed stream.
class Formations {
  FormationId? nextAt(int hoop) => null;

  Iterable<SlotPlan> build(FormationId id, int startHoop) => const [];
}
