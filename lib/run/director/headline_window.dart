/// PRD-2.6 D6 one-headline-per-window arbitration.
///
/// The M1 window accepts every headline immediately; WP-D adds the rolling
/// window, waiting queue and the five-hoop wait limit without a new API.
class HeadlineWindow {
  bool allows(String id, int hoop) => true;

  int delayedUntil(String id, int hoop) => hoop;

  void add(String id, int hoop) {}
}
