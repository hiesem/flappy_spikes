import '../run_controller.dart';

/// The hoop-aware bang-bang bot (ARCH §1.12, PRD-2 §7): aims at the next
/// unresolved hoop through `HoopKind.autopilotTarget` (switch first, nearer
/// pair ring, spring launch line, saw centre) and flaps whenever the bird
/// is more than [margin] below the target and not already rising fast
/// (prototype `botStep`). Used by the debug bot, `test/helpers.dart` and
/// `integration_test/`.
class Autopilot {
  Autopilot(this.run, {this.margin = 10});

  final RunController run;
  final double margin;

  /// The prototype's "already rising" cut-off (pt/s).
  static const double risingVy = -40;

  /// The y the bot currently aims at.
  double targetY() {
    final s = run.state;
    var ty = s.viewHeight / 2;
    final bird = run.game.runBirdPosition;
    final h = run.spawner.nextHoopAhead();
    if (h != null) {
      final t = h.kind.autopilotTarget(h, s, bird?.y ?? ty);
      ty = t.preTarget != null ? t.preTarget!.y + 6 : t.y;
    }
    return ty;
  }

  bool shouldFlap() {
    final s = run.state;
    if (!run.isScrolling || s.flapLock > 0 || s.ride != null) return false;
    final bird = run.game.runBirdPosition;
    final vy = run.game.runBirdVelocityY;
    if (bird == null || vy == null) return false;
    return bird.y > targetY() + margin && vy > risingVy;
  }
}
