import '../../components/debug_panel.dart';
import '../../game/flappy_game.dart';
import '../director/plans.dart';
import '../elements.dart';

/// The §3.0.8 debug "force element" page of the debug panel (debug builds
/// and Linux only; `FlappySpikesGame.debugAvailable`). From home the
/// choices are queued into the next run's `RunSetup`; during a run (the
/// pause screen, WP-2d) they go straight to `RunController.debugForce`.
abstract final class ForceMenu {
  /// PRD-2.3 §14.6 the "Runs" row: +5 per tap …
  static const int runsStep = 5;

  /// … and from this value (the highest gate) back to 0.
  static const int runsTop = 20;

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
      // PRD-2.3 §14.6 "Runs: N (+5 / 0)": sets `gamesPlayed` to test the
      // lifetime unlock gates (+5 per tap; from 20 — every gate open — the
      // next tap goes back to 0).
      DebugAction(
        () => 'Runs: ${game.storage.gamesPlayed} (+5 / 0)',
        () async {
          final g = game.storage.gamesPlayed;
          await game.storage.saveGamesPlayed(g >= runsTop ? 0 : g + runsStep);
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
        // PRD-2.3.1 §12.2 (P1E-02) god mode in a run excludes that run
        // (journaled before the assist applies, QA P2-03).
        final run = game.run;
        if (run != null && !run.ended) run.markDebugAssist();
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

  /// PRD-2.3 §14.6 tests: runs ignore the lifetime unlock gates (the test
  /// harness sets it; the gates have their own tests).
  bool ignoreGates = false;

  /// PRD-2.3 §17.6 tests: false flies the planner without the one-big-bonus
  /// rule (the bonus-count baseline). Always true in real runs.
  bool oneBigBonus = true;
}
