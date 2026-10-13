import 'package:flutter/foundation.dart';

import 'config.dart';

/// PRD-2.3 §13.3: the music diagnostic log, in release builds too.
///
/// A ring buffer of the last [Config.musicLogSize] entries, kept in memory
/// and never sent anywhere. Each entry holds the time, the event, the hold
/// flags, the raw `AudioWatch` answers (the playback list's usages and
/// `isMusicActive()`) and the real state of the music player. Every entry is
/// also handed to [sink] (Android: logcat tag `FS-Music`, through
/// `AudioFocus.log`) and shown on the debug panel's MUSIC LOG page. No
/// personal data.
class MusicLog {
  MusicLog({this.capacity = Config.musicLogSize});

  final int capacity;

  final List<MusicLogEntry> _entries = [];

  /// Where every new line goes too (logcat); null = nowhere.
  void Function(String line)? sink;

  /// Oldest first.
  List<MusicLogEntry> get entries => List.unmodifiable(_entries);

  /// The events only, oldest first (tests).
  List<String> get events => [for (final e in _entries) e.event];

  void add(MusicLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > capacity) _entries.removeAt(0);
    final line = entry.line;
    try {
      sink?.call(line);
    } catch (_) {}
    if (kDebugMode) debugPrint('FS-Music $line');
  }
}

@immutable
class MusicLogEntry {
  const MusicLogEntry({
    required this.time,
    required this.event,
    required this.flags,
    required this.watch,
    required this.player,
  });

  final DateTime time;

  /// start / pause / resume / skip / unskip / suspend / resume-ad /
  /// clear-suspend / background / foreground / interrupt / interrupt-end /
  /// notify / notify-end / player_dead / music_held / check.
  final String event;

  /// `susp=0 int=0 own=0 bg=0 notif=0`.
  final String flags;

  /// The last `AudioWatch` answer (`AudioWatchState.logLine`).
  final String watch;

  /// The music player's real state (audioplayers `PlayerState`).
  final String player;

  String get line {
    final t = time.toIso8601String();
    final hms = t.length >= 23 ? t.substring(11, 23) : t;
    return '$hms $event | $flags | watch $watch | player $player';
  }
}
