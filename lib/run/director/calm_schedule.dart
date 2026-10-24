/// PRD-2.6 D4 periodic and event-driven calm stretches.
///
/// The M1 schedule never requests or consumes a calm slot. WP-D implements
/// periodic timing, revive/squeeze/ride triggers and the 12-hoop minimum gap.
class CalmSchedule {
  bool dueAt(int hoop) => false;

  int remainingAt(int hoop) => 0;

  void startAt(int hoop, int length) {}

  void onRevive(int hoop) {}

  void onSqueezeEnded(int hoop) {}

  void onRideEnded(int hoop) {}
}
