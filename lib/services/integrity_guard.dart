/// PRD-2.5 §3.3 WP-GUARD — MINIMAL STUB for the WP-IAP worktree only.
///
/// Builder A owns this file; at merge the orchestrator keeps A's version.
/// This stub only has the fixed interface (PRD §4): the singleton
/// [IntegrityGuard.instance], [trusted], [ready] and [markUntrusted].
class IntegrityGuard {
  IntegrityGuard._();

  static final IntegrityGuard instance = IntegrityGuard._();

  bool _trusted = true;
  String? _reason;

  /// True until something proved otherwise (fail-open, D1).
  bool get trusted => _trusted;

  /// Why the install is untrusted (null while trusted).
  String? get reason => _reason;

  /// Completes once the start-up verdict is known.
  Future<void> get ready => Future<void>.value();

  /// Marks this install untrusted for [reason] (sticky for the process).
  void markUntrusted(String reason) {
    _trusted = false;
    _reason ??= reason;
  }
}
