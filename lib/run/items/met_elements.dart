import '../elements.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// §3.0.8 an element counts as met when it is spawned on screen: persists
/// `metElements` and tells the director (first-meet bookkeeping).
class MetElementsFeature extends RunFeature {
  RunContext? _c;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events.on<ElementSpawned>(_onSpawned);
  }

  void _onSpawned(ElementSpawned e) {
    final c = _c;
    if (c == null || !e.onScreen) return;
    _met(c, e.element);
    if (e.element.isCapsuleType) _met(c, ElementId.capsule);
  }

  void _met(RunContext c, ElementId el) {
    c.s.metThisRun.add(el);
    c.director.markMet(el);
    if (c.s.metElements.add(el)) {
      c.game.storage.markElementMet(el.storageId);
    }
  }

  @override
  void detach() {
    _c?.events.off<ElementSpawned>(_onSpawned);
    _c = null;
  }
}
