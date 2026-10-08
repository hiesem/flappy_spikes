import '../../components/debug_panel.dart';
import '../../game/flappy_game.dart';
import '../director/plans.dart';
import '../elements.dart';

/// The §3.0.8 debug "force element" page of the debug panel (debug builds
/// and Linux only; `FlappySpikesGame.debugAvailable`). From home the
/// choices are queued into the next run's `RunSetup`; during a run (the
/// pause screen, WP-2d) they go straight to `RunController.debugForce`.
abstract final class ForceMenu {
  /// The "start at hoop N" steps the row cycles through.
  static const List<int> startSteps = [0, 6, 10, 15, 20, 25, 35, 45, 60];

  /// Every element the debug menu can force: the slot and gap elements of
  /// the catalogue plus the spike squeeze (handled by its feature).
  static List<ElementId> get forceable => [
    for (final e in ElementId.values)
      if ((e.isSlotElement || e.isGapElement || e == ElementId.squeeze) &&
          e != ElementId.piggyCoins &&
          e != ElementId.fireflySwarm &&
          e != ElementId.capsule)
        e,
  ];

  static List<DebugAction> actions(FlappySpikesGame game) {
    final d = game.runDebug;
    String queued(ElementId e) => d.force.contains(e) ? ' *' : '';
    return [
      DebugAction(
        () => 'Start at hoop ${d.startHoopIndex}',
        () async {
          final i = startSteps.indexOf(d.startHoopIndex);
          d.startHoopIndex = startSteps[(i + 1) % startSteps.length];
        },
      ),
      DebugAction(
        () => 'Reset met elements (${game.storage.metElements.length})',
        () async {
          await game.storage.saveMetElements({});
          game.showToast('Met elements reset');
        },
      ),
      DebugAction(() => 'Bot: ${d.bot ? 'ON' : 'off'}', () async {
        d.bot = !d.bot;
      }),
      DebugAction(() => 'God mode: ${d.god ? 'ON' : 'off'}', () async {
        d.god = !d.god;
      }),
      DebugAction(() => 'Overlay: ${d.overlay ? 'ON' : 'off'}', () async {
        d.overlay = !d.overlay;
      }),
      for (final e in forceable)
        DebugAction(
          () => 'Force: ${e.storageId}${queued(e)}',
          () async => game.debugForceElement(e),
        ),
      for (final r in RideId.values)
        DebugAction(
          () => 'Force portal ride: ${r.name}'
              '${d.forcedRide == r ? ' *' : ''}',
          () async => game.debugForceRide(r),
        ),
      DebugAction(() => 'Clear forced (${d.force.length})', () async {
        d.force.clear();
        d.forcedRide = null;
      }),
    ];
  }
}

/// Debug choices for the next run (and the running one).
class RunDebugState {
  final List<ElementId> force = [];
  int startHoopIndex = 0;
  RideId? forcedRide;
  bool bot = false;
  bool god = false;
  bool overlay = false;
}
