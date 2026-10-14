import 'dart:convert';

/// PRD-2.3.1 §12.3 / §19 (QA P19-01..03) every piece of achievement state
/// the tracker owns, persisted as ONE JSON value (`GameStorage` key
/// `achState`) by ONE awaited write per state transition. A transition
/// (staging a run op, a run end's commit + release, journal recovery, a
/// shop / jackpot unlock, a platform-confirmed report) mutates this object
/// synchronously and then writes the whole snapshot, so an app kill keeps
/// either the state before or the state after it: never half (no lost
/// pending achievement, no catch counted twice).
class AchState {
  /// Unlocked keys (the local truth).
  Set<String> unlocked = {};

  /// Keys the platform confirmed for [reportedPlayer].
  Set<String> reported = {};

  /// The platform player id [reported] belongs to ('' = none yet).
  String reportedPlayer = '';

  /// Portal ride ids finished (`RideId.storageId`).
  Set<String> rides = {};

  /// 2.3.1 (20) first-catch item keys (no longer written by the rules; kept
  /// so an old install's data survives the migration unchanged).
  Set<String> items = {};

  /// §19.1 lifetime catches per item achievement key.
  Map<String, int> itemCounts = {};

  /// §19.2 earned, waiting for a counting run end (FIFO, oldest first).
  List<String> pending = [];

  /// Versus wins since 2.3.1.
  int versusWins = 0;

  /// Current streak of consecutive local days with a counted run.
  int dayStreak = 0;

  /// `storage.today` of the last counted run (-1 = none).
  int lastPlayDay = -1;

  /// QA P2-03 the open run's staged rule ops (`AchOp`), empty when no run
  /// is open; committed at the run end or at the next launch.
  List<String> journal = [];

  /// The open run's journal is excluded (a debug assist): discard it.
  bool journalExcluded = false;

  AchState();

  AchState copy() => AchState.fromJson(toJson());

  Map<String, Object> toJson() => {
    'v': 1,
    'unlocked': [...unlocked]..sort(),
    'reported': [...reported]..sort(),
    'reportedPlayer': reportedPlayer,
    'rides': [...rides]..sort(),
    'items': [...items]..sort(),
    'itemCounts': {
      for (final k in itemCounts.keys.toList()..sort()) k: itemCounts[k]!,
    },
    'pending': [...pending],
    'versusWins': versusWins,
    'dayStreak': dayStreak,
    'lastPlayDay': lastPlayDay,
    'journal': [...journal],
    'journalExcluded': journalExcluded,
  };

  String encode() => jsonEncode(toJson());

  factory AchState.fromJson(Map<String, Object?> j) {
    List<String> list(String k) => [
      for (final e in (j[k] as List?) ?? const []) '$e',
    ];
    int intOf(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    return AchState()
      ..unlocked = list('unlocked').toSet()
      ..reported = list('reported').toSet()
      ..reportedPlayer = (j['reportedPlayer'] as String?) ?? ''
      ..rides = list('rides').toSet()
      ..items = list('items').toSet()
      ..itemCounts = {
        for (final e in ((j['itemCounts'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num).toInt(),
      }
      ..pending = list('pending')
      ..versusWins = intOf('versusWins', 0)
      ..dayStreak = intOf('dayStreak', 0)
      ..lastPlayDay = intOf('lastPlayDay', -1)
      ..journal = list('journal')
      ..journalExcluded = (j['journalExcluded'] as bool?) ?? false;
  }

  /// Null when [raw] is missing or unreadable.
  static AchState? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      return j is Map<String, Object?> ? AchState.fromJson(j) : null;
    } catch (_) {
      return null;
    }
  }
}
