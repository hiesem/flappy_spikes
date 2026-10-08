import '../elements.dart';

/// §3.0.8 first-meet guarantee bookkeeping: which elements this install has
/// met, and the one-at-a-time forced queue (oldest unlock first).
///
/// Only elements in [enabled] (registered by a WP) and flagged
/// [ElementId.firstMeet] are ever forced.
class FirstMeet {
  FirstMeet(Set<ElementId> met, this.enabled) : met = {...met};

  final Set<ElementId> met;
  final Set<ElementId> enabled;

  /// Index (slot or gap) at which the current head first became due.
  int? dueSince;
  ElementId? _head;

  /// Heads that waited [patience] indices without their rules allowing
  /// them (e.g. a shield while the home-slot shield stays armed): they go
  /// behind the others for the rest of the run, so one stuck element never
  /// blocks every other first meet (call, ARCH §2.2).
  final Set<ElementId> deferred = {};
  static const int patience = 10;

  /// The never-met element with the oldest unlock that is due at [index]
  /// (its first-possible hoop / gap reached), or null.
  ElementId? due(int index) {
    final head = _head;
    final since = dueSince;
    if (head != null &&
        since != null &&
        !met.contains(head) &&
        index - since > patience) {
      deferred.add(head);
    }
    ElementId? best;
    var bestDeferred = true;
    for (final e in ElementId.values) {
      if (!e.firstMeet || met.contains(e) || !enabled.contains(e)) continue;
      final from = e.firstPossible;
      if (from == null || from > index) continue;
      final d = deferred.contains(e);
      if (best == null ||
          (bestDeferred && !d) ||
          (bestDeferred == d && from < best.firstPossible!)) {
        best = e;
        bestDeferred = d;
      }
    }
    if (best != _head) {
      _head = best;
      dueSince = best == null ? null : index;
    }
    return best;
  }

  /// The due head if it is decided in a hoop slot.
  ElementId? dueSlot(int index) {
    final e = due(index);
    return e != null && e.isSlotElement ? e : null;
  }

  /// The due head if it is decided in a gap.
  ElementId? dueGap(int index) {
    final e = due(index);
    return e != null && e.isGapElement ? e : null;
  }

  void markMet(ElementId e) {
    met.add(e);
    if (e.isCapsuleType) met.add(ElementId.capsule);
    if (e == _head) {
      _head = null;
      dueSince = null;
    }
  }
}
