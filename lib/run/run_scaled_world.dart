import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide World;

import 'run_layers.dart';

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

  /// A2-5: while an opaque page covers the whole view (the results page),
  /// the priority below which the children are not drawn; null otherwise.
  /// Those children sit under the page's background, so only their drawing
  /// is skipped: they still update.
  int? Function()? coveredBelowSource;

  // region WP-TAB — the run column on wide screens
  /// WP-TAB: how far right the run column is drawn (pt): half the extra
  /// width of a wide (tablet) playfield, 0 on phones. The camera centres
  /// the 320 pt menu column; the run's content (bird, hoops, strips, run
  /// effects, all in run screen coordinates 0..320) is drawn this much
  /// further right, so the run keeps the phone's look-ahead and the extra
  /// width shows what is behind the bird (run x from −extra to 320).
  double columnShift = 0;

  static final Expando<bool> _runColumn = Expando('runColumn');

  /// WP-TAB: marks [c] (a direct world child) as run content, drawn in the
  /// run column ([columnShift]). [RunTrack] layers are always run content.
  static T inRunColumn<T extends Component>(T c) {
    _runColumn[c] = true;
    return c;
  }

  /// WP-TAB: whether [c] is drawn in the run column.
  static bool isRunColumn(Component c) =>
      c is RunTrack || (_runColumn[c] ?? false);
  // endregion WP-TAB

  @override
  void renderFromCamera(Canvas canvas) {
    final below = coveredBelowSource?.call();
    final shift = columnShift;
    if (below == null && shift == 0) {
      super.renderFromCamera(canvas);
      return;
    }
    // [Component.renderTree] without the children under the page.
    render(canvas);
    for (final child in children) {
      if (below != null && child.priority < below) continue;
      if (shift != 0 && isRunColumn(child)) {
        canvas
          ..save()
          ..translate(shift, 0);
        renderChild(canvas, child);
        canvas.restore();
        continue;
      }
      renderChild(canvas, child);
    }
    afterChildrenRendered(canvas);
    if (debugMode) renderDebugMode(canvas);
  }

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

/// WP-TAB: adds run content to the world, drawn in the run column
/// ([RunScaledWorld.columnShift]).
extension RunColumnAdd on World {
  void addRun(Component c) => add(RunScaledWorld.inRunColumn(c));
}
