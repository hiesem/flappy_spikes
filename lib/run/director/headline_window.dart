/// PRD-2.6 D6 one-headline-per-window arbitration.
class HeadlineWindow {
  static const _window = 8;
  static const _wait = 5;

  final Map<String, int> _waitUntil = {};
  int? _lastHeadlineAt;

  /// True when [id] can become the next headline. A blocked item reaches its
  /// hard wait deadline after five hoops and is then released.
  bool allows(String id, int hoop) {
    final last = _lastHeadlineAt;
    final deadline = _waitUntil[id];
    if (last == null || hoop >= last + _window) return true;
    return deadline != null && hoop >= deadline;
  }

  /// The first hoop at which a due [id] may run. A blocked item never waits
  /// more than five hoops from this due hoop.
  int delayedUntil(String id, int hoop) {
    if (allows(id, hoop)) return hoop;
    return _waitUntil.putIfAbsent(id, () => hoop + _wait);
  }

  void add(String id, int hoop) {
    if (!allows(id, hoop)) return;
    _lastHeadlineAt = hoop;
    _waitUntil.clear();
  }
}
