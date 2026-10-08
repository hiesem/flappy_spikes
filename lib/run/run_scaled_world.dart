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

  @override
  void updateTree(double dt) => super.updateTree(dt * timeScale);
}
