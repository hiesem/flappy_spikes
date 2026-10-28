import 'dart:async';

/// PRD-2.2 §4 why a VERSUS run started solo (logs only: analytics
/// `versus_solo`, the logcat line and the debug panel; the player sees
/// nothing).
enum VersusSoloReason {
  /// The search finished and found nobody.
  noRival('no_rival'),

  /// The 6 s search limit was hit (or the search had not finished at START).
  timeout('timeout'),
  offline('offline'),

  /// Sign-in failed or is still pending.
  auth('auth'),

  /// The App Check token was refused (e.g. a sideloaded release build).
  appCheck('app_check'),

  /// permission-denied.
  rules('rules'),

  /// Anything else.
  error('error');

  const VersusSoloReason(this.code);

  /// The analytics / log value.
  final String code;
}

/// A classified backend failure: the Firebase backend wraps plugin errors
/// in it so the service (and fake backends in tests) can name the §4
/// reason without importing the plugins.
class VersusFailure implements Exception {
  const VersusFailure(this.reason, [this.cause]);

  final VersusSoloReason reason;
  final Object? cause;

  @override
  String toString() => 'VersusFailure(${reason.code}: $cause)';
}

/// The §4 reason of a failed call: a [VersusFailure] names its own; a
/// time-box ([TimeoutException]) is `timeout`; anything else `error`.
VersusSoloReason soloReasonOf(Object e) => switch (e) {
  VersusFailure(:final reason) => reason,
  TimeoutException() => VersusSoloReason.timeout,
  _ => VersusSoloReason.error,
};

/// Where the opponent search stands (PRD-2.2 §4 debug-panel line).
enum VersusSearchState { idle, running, found, solo }

// region P26-POL3
/// The best currently available connectivity evidence from versus search.
bool onlineFromSearch({required bool ready, required bool holdsOpponent,
    required VersusSearchInfo search}) => ready &&
    (holdsOpponent || search.state == VersusSearchState.found ||
        search.reason == VersusSoloReason.noRival);
// endregion

/// The latest opponent search (PRD-2.2 §3 / §4).
class VersusSearchInfo {
  const VersusSearchInfo({
    this.state = VersusSearchState.idle,
    this.reason,
    this.reads = 0,
    this.bracket = 0,
    this.opponentUid = '',
  });

  final VersusSearchState state;

  /// Why it ended solo (null while idle / running / found).
  final VersusSoloReason? reason;

  /// Pool documents read by it.
  final int reads;

  /// PRD-2.6 E4: the best-score bracket searched, independent of progression.
  final int bracket;

  /// The held opponent's uid ('' = none).
  final String opponentUid;

  /// The PRD-2.2 §4 debug-panel line: the search outcome (or its solo
  /// reason), its reads and the opponent's uid prefix.
  String get debugLine {
    final what = switch (state) {
      VersusSearchState.idle => 'none',
      VersusSearchState.running => 'running',
      VersusSearchState.found => 'found',
      VersusSearchState.solo => reason?.code ?? 'error',
    };
    final opp = opponentUid.isEmpty
        ? '-'
        : opponentUid.substring(0, opponentUid.length.clamp(0, 6));
    return 'Versus: last search $what / $reads reads / opponent $opp';
  }
}

/// PRD-2.2 §4 the logcat line of a solo VERSUS start.
String versusSoloLogLine(VersusSoloReason reason, int reads) =>
    'versus: solo (${reason.code}, $reads reads)';
