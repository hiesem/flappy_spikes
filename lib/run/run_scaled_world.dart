import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

/// The game world with a run time scale (ARCH §0): everything in it —
/// Forge2D step, bird, hoops, pickups — updates with dt × [timeScale]
/// (Hourglass 0.45, §3.30). HUD and run screens live in the viewport and
/// keep real time. [timeScale] is 1 outside an Hourglass.
class RunScaledWorld extends Forge2DWorld {
  RunScaledWorld({super.gravity});

  /// Read every frame (the run controller's `RunState.timeScale`).
  double Function()? timeScaleSource;

  double get timeScale => timeScaleSource?.call() ?? 1;

  // region WP-2d — pause freezes the world (PRD-2 §5.7)
  /// True while the run is paused: the world (Forge2D step, bird, hoops,
  /// particles) gets dt 0 — except [realTime] children (an in-run menu
  /// overlay such as settings over the pause screen), which keep real dt.
  bool Function()? frozenSource;

  bool get frozen => frozenSource?.call() ?? false;

  /// World children that keep updating in real time while [frozen].
  final Set<Component> realTime = {};
  // endregion WP-2d

  @override
  void updateTree(double dt) {
    if (!frozen) {
      super.updateTree(dt * timeScale);
      return;
    }
    super.updateTree(0);
    realTime.removeWhere((c) => c.isRemoved);
    for (final c in realTime) {
      if (c.isMounted) c.updateTree(dt);
    }
  }
}
